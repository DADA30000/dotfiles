#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include <unistd.h>
#include <errno.h>
#include <dlfcn.h>
#include <fcntl.h>
#include <stdarg.h>
#include <sys/ioctl.h>
#include <sys/stat.h>
#include <sys/mman.h>
#include <sys/time.h>
#include <linux/videodev2.h>
#include <dbus/dbus.h>
#include <pipewire/pipewire.h>

static int (*next_open)(const char *, int, ...) = NULL;
static int (*next_open64)(const char *, int, ...) = NULL;
static int (*next_openat)(int, const char *, int, ...) = NULL;
static int (*next_openat64)(int, const char *, int, ...) = NULL;
static int (*next_close)(int) = NULL;
static int (*next_ioctl)(int, unsigned long, ...) = NULL;
static void *(*next_mmap)(void *, size_t, int, int, int, off_t) = NULL;
static void *(*next_mmap64)(void *, size_t, int, int, int, off_t) = NULL;
static int (*next_munmap)(void *, size_t) = NULL;
static struct pw_core *(*real_connect_fd)(struct pw_context *, int, struct pw_properties *, size_t) = NULL;

static int g_portal_fd = -1;
static int g_access_denied = 0;

#define DUMMY_WIDTH 1280
#define DUMMY_HEIGHT 720
#define DUMMY_BUF_SIZE (DUMMY_WIDTH * DUMMY_HEIGHT * 2)
#define NUM_DUMMY_BUFS 4

struct dummy_cam {
    int fd;
    int is_active;
    int streaming;
    uint32_t sequence;
    void *bufs[NUM_DUMMY_BUFS];
    int buf_queued[NUM_DUMMY_BUFS];
    struct v4l2_format fmt;
};

#define MAX_DUMMY_CAMS 16
static struct dummy_cam g_dummy_cams[MAX_DUMMY_CAMS];

static struct dummy_cam *find_dummy(int fd) {
    if (fd < 0) return NULL;
    for (int i = 0; i < MAX_DUMMY_CAMS; i++) {
        if (g_dummy_cams[i].is_active && g_dummy_cams[i].fd == fd)
            return &g_dummy_cams[i];
    }
    return NULL;
}

static void init_next_fops(void) {
    if (!next_open) next_open = dlsym(RTLD_NEXT, "open");
    if (!next_open64) next_open64 = dlsym(RTLD_NEXT, "open64");
    if (!next_openat) next_openat = dlsym(RTLD_NEXT, "openat");
    if (!next_openat64) next_openat64 = dlsym(RTLD_NEXT, "openat64");
    if (!next_close) next_close = dlsym(RTLD_NEXT, "close");
    if (!next_ioctl) next_ioctl = dlsym(RTLD_NEXT, "ioctl");
    if (!next_mmap) next_mmap = dlsym(RTLD_NEXT, "mmap");
    if (!next_mmap64) next_mmap64 = dlsym(RTLD_NEXT, "mmap64");
    if (!next_munmap) next_munmap = dlsym(RTLD_NEXT, "munmap");
}

static int request_camera_from_portal(void) {
    if (g_portal_fd >= 0) return g_portal_fd;
    if (g_access_denied) return -1;

    DBusError err;
    dbus_error_init(&err);
    DBusConnection *conn = dbus_bus_get(DBUS_BUS_SESSION, &err);
    if (!conn) {
        fprintf(stderr, "[pw-portal-shim] Failed to connect to session bus: %s\n", err.message);
        dbus_error_free(&err);
        g_access_denied = 1;
        return -1;
    }

    DBusMessage *msg = dbus_message_new_method_call(
        "org.freedesktop.portal.Desktop",
        "/org/freedesktop/portal/desktop",
        "org.freedesktop.portal.Camera",
        "AccessCamera"
    );
    if (!msg) {
        g_access_denied = 1;
        return -1;
    }

    DBusMessageIter iter, dict;
    dbus_message_iter_init_append(msg, &iter);
    dbus_message_iter_open_container(&iter, DBUS_TYPE_ARRAY, "{sv}", &dict);
    dbus_message_iter_close_container(&iter, &dict);

    DBusMessage *reply = dbus_connection_send_with_reply_and_block(conn, msg, 120000, &err);
    dbus_message_unref(msg);
    if (!reply) {
        fprintf(stderr, "[pw-portal-shim] AccessCamera call failed: %s\n", err.message);
        dbus_error_free(&err);
        g_access_denied = 1;
        return -1;
    }

    const char *req_path = NULL;
    dbus_message_get_args(reply, &err, DBUS_TYPE_OBJECT_PATH, &req_path, DBUS_TYPE_INVALID);
    char *path_copy = strdup(req_path);
    dbus_message_unref(reply);

    char match[512];
    snprintf(match, sizeof(match),
             "type='signal',interface='org.freedesktop.portal.Request',member='Response',path='%s'",
             path_copy);
    dbus_bus_add_match(conn, match, &err);
    dbus_connection_flush(conn);

    int granted = 0;
    while (dbus_connection_read_write_dispatch(conn, -1)) {
        DBusMessage *sig = dbus_connection_pop_message(conn);
        if (!sig) continue;
        if (dbus_message_is_signal(sig, "org.freedesktop.portal.Request", "Response") &&
            strcmp(dbus_message_get_path(sig), path_copy) == 0) {
            uint32_t code = 1;
            DBusMessageIter s_iter;
            if (dbus_message_iter_init(sig, &s_iter) &&
                dbus_message_iter_get_arg_type(&s_iter) == DBUS_TYPE_UINT32) {
                dbus_message_iter_get_basic(&s_iter, &code);
            }
            if (code == 0) granted = 1;
            dbus_message_unref(sig);
            break;
        }
        dbus_message_unref(sig);
    }
    free(path_copy);

    if (!granted) {
        fprintf(stderr, "[pw-portal-shim] Camera permission denied by user - switching to dummy output\n");
        g_access_denied = 1;
        return -1;
    }

    msg = dbus_message_new_method_call(
        "org.freedesktop.portal.Desktop",
        "/org/freedesktop/portal/desktop",
        "org.freedesktop.portal.Camera",
        "OpenPipeWireRemote"
    );
    dbus_message_iter_init_append(msg, &iter);
    dbus_message_iter_open_container(&iter, DBUS_TYPE_ARRAY, "{sv}", &dict);
    dbus_message_iter_close_container(&iter, &dict);

    reply = dbus_connection_send_with_reply_and_block(conn, msg, 10000, &err);
    dbus_message_unref(msg);
    if (!reply) {
        fprintf(stderr, "[pw-portal-shim] OpenPipeWireRemote failed: %s\n", err.message);
        dbus_error_free(&err);
        g_access_denied = 1;
        return -1;
    }

    int pw_fd = -1;
    dbus_message_get_args(reply, &err, DBUS_TYPE_UNIX_FD, &pw_fd, DBUS_TYPE_INVALID);
    dbus_message_unref(reply);
    g_portal_fd = pw_fd;
    return g_portal_fd;
}

static int create_dummy_cam(void) {
    int (*real_open_libc)(const char *, int, ...) = dlsym(RTLD_DEFAULT, "open");
    int fd = real_open_libc ? real_open_libc("/dev/null", O_RDWR) : -1;
    if (fd < 0) return -1;

    for (int i = 0; i < MAX_DUMMY_CAMS; i++) {
        if (!g_dummy_cams[i].is_active) {
            struct dummy_cam *cam = &g_dummy_cams[i];
            cam->fd = fd;
            cam->is_active = 1;
            cam->streaming = 0;
            cam->sequence = 0;
            memset(&cam->fmt, 0, sizeof(cam->fmt));
            cam->fmt.type = V4L2_BUF_TYPE_VIDEO_CAPTURE;
            cam->fmt.fmt.pix.width = DUMMY_WIDTH;
            cam->fmt.fmt.pix.height = DUMMY_HEIGHT;
            cam->fmt.fmt.pix.pixelformat = V4L2_PIX_FMT_YUYV;
            cam->fmt.fmt.pix.field = V4L2_FIELD_NONE;
            cam->fmt.fmt.pix.bytesperline = DUMMY_WIDTH * 2;
            cam->fmt.fmt.pix.sizeimage = DUMMY_BUF_SIZE;
            cam->fmt.fmt.pix.colorspace = V4L2_COLORSPACE_SRGB;

            for (int b = 0; b < NUM_DUMMY_BUFS; b++) {
                if (!cam->bufs[b]) {
                    cam->bufs[b] = malloc(DUMMY_BUF_SIZE);
                    uint8_t *p = (uint8_t *)cam->bufs[b];
                    for (size_t j = 0; j < DUMMY_BUF_SIZE; j += 4) {
                        p[j] = 0;     // Y0 (black)
                        p[j+1] = 128; // U
                        p[j+2] = 0;   // Y1 (black)
                        p[j+3] = 128; // V
                    }
                }
                cam->buf_queued[b] = 0;
            }
            return fd;
        }
    }
    if (next_close) next_close(fd);
    return -1;
}

int open(const char *path, int flags, ...) {
    init_next_fops();
    va_list args;
    va_start(args, flags);
    mode_t mode = va_arg(args, mode_t);
    va_end(args);

    if (strncmp(path, "/dev/video", 10) == 0) {
        int pfd = request_camera_from_portal();
        if (pfd < 0) {
            return create_dummy_cam();
        }
    }
    return next_open ? next_open(path, flags, mode) : -1;
}

int open64(const char *path, int flags, ...) {
    init_next_fops();
    va_list args;
    va_start(args, flags);
    mode_t mode = va_arg(args, mode_t);
    va_end(args);

    if (strncmp(path, "/dev/video", 10) == 0) {
        int pfd = request_camera_from_portal();
        if (pfd < 0) return create_dummy_cam();
    }
    return next_open64 ? next_open64(path, flags, mode) : -1;
}

int openat(int dirfd, const char *path, int flags, ...) {
    init_next_fops();
    va_list args;
    va_start(args, flags);
    mode_t mode = va_arg(args, mode_t);
    va_end(args);

    if (path && strncmp(path, "/dev/video", 10) == 0) {
        int pfd = request_camera_from_portal();
        if (pfd < 0) return create_dummy_cam();
    }
    return next_openat ? next_openat(dirfd, path, flags, mode) : -1;
}

int openat64(int dirfd, const char *path, int flags, ...) {
    init_next_fops();
    va_list args;
    va_start(args, flags);
    mode_t mode = va_arg(args, mode_t);
    va_end(args);

    if (path && strncmp(path, "/dev/video", 10) == 0) {
        int pfd = request_camera_from_portal();
        if (pfd < 0) return create_dummy_cam();
    }
    return next_openat64 ? next_openat64(dirfd, path, flags, mode) : -1;
}

int close(int fd) {
    init_next_fops();
    struct dummy_cam *cam = find_dummy(fd);
    if (cam) {
        cam->is_active = 0;
        cam->streaming = 0;
    }
    return next_close ? next_close(fd) : -1;
}

void *mmap(void *addr, size_t length, int prot, int flags, int fd, off_t offset) {
    init_next_fops();
    struct dummy_cam *cam = find_dummy(fd);
    if (cam) {
        int index = offset / DUMMY_BUF_SIZE;
        if (index >= 0 && index < NUM_DUMMY_BUFS) {
            return cam->bufs[index];
        }
    }
    return next_mmap ? next_mmap(addr, length, prot, flags, fd, offset) : MAP_FAILED;
}

void *mmap64(void *addr, size_t length, int prot, int flags, int fd, off_t offset) {
    init_next_fops();
    struct dummy_cam *cam = find_dummy(fd);
    if (cam) {
        int index = offset / DUMMY_BUF_SIZE;
        if (index >= 0 && index < NUM_DUMMY_BUFS) {
            return cam->bufs[index];
        }
    }
    return next_mmap64 ? next_mmap64(addr, length, prot, flags, fd, offset) : MAP_FAILED;
}

int munmap(void *addr, size_t length) {
    init_next_fops();
    for (int i = 0; i < MAX_DUMMY_CAMS; i++) {
        if (g_dummy_cams[i].is_active) {
            for (int b = 0; b < NUM_DUMMY_BUFS; b++) {
                if (g_dummy_cams[i].bufs[b] == addr)
                    return 0;
            }
        }
    }
    return next_munmap ? next_munmap(addr, length) : -1;
}

int ioctl(int fd, unsigned long request, ...) {
    init_next_fops();
    va_list args;
    va_start(args, request);
    void *arg = va_arg(args, void *);
    va_end(args);

    struct dummy_cam *cam = find_dummy(fd);
    if (!cam) {
        return next_ioctl ? next_ioctl(fd, request, arg) : -1;
    }

    switch (request & 0xffffffff) {
    case VIDIOC_QUERYCAP: {
        struct v4l2_capability *cap = (struct v4l2_capability *)arg;
        memset(cap, 0, sizeof(*cap));
        strncpy((char *)cap->driver, "dummy-cam", sizeof(cap->driver) - 1);
        strncpy((char *)cap->card, "Virtual Dummy Camera", sizeof(cap->card) - 1);
        strncpy((char *)cap->bus_info, "platform:dummy", sizeof(cap->bus_info) - 1);
        cap->capabilities = V4L2_CAP_VIDEO_CAPTURE | V4L2_CAP_STREAMING | V4L2_CAP_DEVICE_CAPS;
        cap->device_caps = V4L2_CAP_VIDEO_CAPTURE | V4L2_CAP_STREAMING;
        return 0;
    }
    case VIDIOC_ENUM_FMT: {
        struct v4l2_fmtdesc *fmt = (struct v4l2_fmtdesc *)arg;
        if (fmt->type != V4L2_BUF_TYPE_VIDEO_CAPTURE || fmt->index > 0) return -EINVAL;
        fmt->pixelformat = V4L2_PIX_FMT_YUYV;
        strncpy((char *)fmt->description, "YUYV 4:2:2", sizeof(fmt->description) - 1);
        return 0;
    }
    case VIDIOC_ENUM_FRAMESIZES: {
        struct v4l2_frmsizeenum *fsize = (struct v4l2_frmsizeenum *)arg;
        if (fsize->index > 0) return -EINVAL;
        fsize->type = V4L2_FRMSIZE_TYPE_DISCRETE;
        fsize->discrete.width = DUMMY_WIDTH;
        fsize->discrete.height = DUMMY_HEIGHT;
        return 0;
    }
    case VIDIOC_G_FMT:
    case VIDIOC_S_FMT:
    case VIDIOC_TRY_FMT: {
        struct v4l2_format *f = (struct v4l2_format *)arg;
        *f = cam->fmt;
        return 0;
    }
    case VIDIOC_ENUMINPUT: {
        struct v4l2_input *inp = (struct v4l2_input *)arg;
        if (inp->index > 0) return -EINVAL;
        memset(inp, 0, sizeof(*inp));
        strncpy((char *)inp->name, "Camera", sizeof(inp->name) - 1);
        inp->type = V4L2_INPUT_TYPE_CAMERA;
        return 0;
    }
    case VIDIOC_G_INPUT: {
        int *inp = (int *)arg;
        *inp = 0;
        return 0;
    }
    case VIDIOC_S_INPUT: {
        return 0;
    }
    case VIDIOC_G_PARM:
    case VIDIOC_S_PARM: {
        struct v4l2_streamparm *p = (struct v4l2_streamparm *)arg;
        if (p->type == V4L2_BUF_TYPE_VIDEO_CAPTURE) {
            p->parm.capture.capability = V4L2_CAP_TIMEPERFRAME;
            p->parm.capture.timeperframe.numerator = 1;
            p->parm.capture.timeperframe.denominator = 30;
        }
        return 0;
    }
    case VIDIOC_REQBUFS: {
        struct v4l2_requestbuffers *rb = (struct v4l2_requestbuffers *)arg;
        rb->count = NUM_DUMMY_BUFS;
        rb->type = V4L2_BUF_TYPE_VIDEO_CAPTURE;
        rb->memory = V4L2_MEMORY_MMAP;
        return 0;
    }
    case VIDIOC_QUERYBUF: {
        struct v4l2_buffer *b = (struct v4l2_buffer *)arg;
        if (b->index >= NUM_DUMMY_BUFS) return -EINVAL;
        b->type = V4L2_BUF_TYPE_VIDEO_CAPTURE;
        b->memory = V4L2_MEMORY_MMAP;
        b->m.offset = b->index * DUMMY_BUF_SIZE;
        b->length = DUMMY_BUF_SIZE;
        b->flags = V4L2_BUF_FLAG_TIMESTAMP_MONOTONIC;
        if (cam->buf_queued[b->index]) b->flags |= V4L2_BUF_FLAG_QUEUED;
        return 0;
    }
    case VIDIOC_QBUF: {
        struct v4l2_buffer *b = (struct v4l2_buffer *)arg;
        if (b->index >= NUM_DUMMY_BUFS) return -EINVAL;
        cam->buf_queued[b->index] = 1;
        b->flags |= V4L2_BUF_FLAG_QUEUED;
        b->flags &= ~V4L2_BUF_FLAG_DONE;
        return 0;
    }
    case VIDIOC_DQBUF: {
        struct v4l2_buffer *b = (struct v4l2_buffer *)arg;
        int found = -1;
        for (int i = 0; i < NUM_DUMMY_BUFS; i++) {
            if (cam->buf_queued[i]) {
                found = i;
                break;
            }
        }
        if (found < 0) found = 0;
        cam->buf_queued[found] = 0;

        usleep(33333); // 30 FPS throttle

        b->index = found;
        b->type = V4L2_BUF_TYPE_VIDEO_CAPTURE;
        b->memory = V4L2_MEMORY_MMAP;
        b->m.offset = found * DUMMY_BUF_SIZE;
        b->length = DUMMY_BUF_SIZE;
        b->bytesused = DUMMY_BUF_SIZE;
        b->flags = V4L2_BUF_FLAG_DONE | V4L2_BUF_FLAG_TIMESTAMP_MONOTONIC;
        b->sequence = cam->sequence++;
        gettimeofday(&b->timestamp, NULL);
        return 0;
    }
    case VIDIOC_STREAMON: {
        cam->streaming = 1;
        return 0;
    }
    case VIDIOC_STREAMOFF: {
        cam->streaming = 0;
        return 0;
    }
    default:
        return 0;
    }
}

// Override pw_context_connect in libpipewire-0.3 to redirect to portal fd when authorized
struct pw_core *pw_context_connect(struct pw_context *context,
                                    struct pw_properties *properties,
                                    size_t user_data_size)
{
    if (!real_connect_fd) {
        real_connect_fd = dlsym(RTLD_DEFAULT, "pw_context_connect_fd");
        if (!real_connect_fd) {
            void *h = dlopen("libpipewire-0.3.so.0", RTLD_LAZY | RTLD_NOLOAD);
            if (h) real_connect_fd = dlsym(h, "pw_context_connect_fd");
        }
    }

    int pfd = request_camera_from_portal();
    if (pfd >= 0 && real_connect_fd) {
        int dup_fd = dup(pfd);
        fprintf(stderr, "[pw-portal-shim] Redirecting PipeWire core to portal fd %d\n", dup_fd);
        return real_connect_fd(context, dup_fd, properties, user_data_size);
    }

    struct pw_core *(*real_connect)(struct pw_context *, struct pw_properties *, size_t) =
        dlsym(RTLD_NEXT, "pw_context_connect");
    if (real_connect) return real_connect(context, properties, user_data_size);
    return NULL;
}
