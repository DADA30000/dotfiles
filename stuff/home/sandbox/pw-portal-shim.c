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
#include <pthread.h>
#include <sys/ioctl.h>
#include <sys/stat.h>
#include <sys/mman.h>
#include <sys/eventfd.h>
#include <sys/time.h>
#include <linux/videodev2.h>
#include <dbus/dbus.h>
#include <pipewire/pipewire.h>

static int (*real_open)(const char *, int, ...) = NULL;
static int (*real_open64)(const char *, int, ...) = NULL;
static int (*real_openat)(int, const char *, int, ...) = NULL;
static int (*real_openat64)(int, const char *, int, ...) = NULL;
static int (*real_close)(int) = NULL;
static int (*real_ioctl)(int, unsigned long, ...) = NULL;
static void *(*real_mmap)(void *, size_t, int, int, int, off_t) = NULL;
static void *(*real_mmap64)(void *, size_t, int, int, int, off_t) = NULL;
static int (*real_munmap)(void *, size_t) = NULL;
static struct pw_core *(*real_connect_fd)(struct pw_context *, int, struct pw_properties *, size_t) = NULL;
static void *g_v4l2_handle = NULL;
static int (*v4l2_open)(const char *, int, ...) = NULL;
static int (*v4l2_close)(int) = NULL;
static int (*v4l2_ioctl)(int, unsigned long, ...) = NULL;
static void *(*v4l2_mmap)(void *, size_t, int, int, int, off_t) = NULL;
static void *(*v4l2_mmap64)(void *, size_t, int, int, int, off64_t) = NULL;
static int (*v4l2_munmap)(void *, size_t) = NULL;

static int g_current_portal_fd = -1;

static int ensure_v4l2_loaded(void) {
    if (g_v4l2_handle) return 1;
    const char *path = getenv("PW_V4L2_PATH");
#ifdef PW_V4L2_PATH
    if (!path || !*path) path = PW_V4L2_PATH;
#endif
    if (!path || !*path) return 0;
    g_v4l2_handle = dlopen(path, RTLD_LAZY | RTLD_LOCAL);
    if (!g_v4l2_handle) {
        fprintf(stderr, "[pw-portal-shim] dlopen(%s) failed: %s\n", path, dlerror());
        return 0;
    }
    v4l2_open = dlsym(g_v4l2_handle, "open");
    v4l2_close = dlsym(g_v4l2_handle, "close");
    v4l2_ioctl = dlsym(g_v4l2_handle, "ioctl");
    v4l2_mmap = dlsym(g_v4l2_handle, "mmap");
    v4l2_mmap64 = dlsym(g_v4l2_handle, "mmap64");
    v4l2_munmap = dlsym(g_v4l2_handle, "munmap");
    return v4l2_open && v4l2_close && v4l2_ioctl && v4l2_mmap && v4l2_munmap;
}

#define DUMMY_WIDTH 1280
#define DUMMY_HEIGHT 720
#define DUMMY_BUF_SIZE (DUMMY_WIDTH * DUMMY_HEIGHT * 2)
#define NUM_DUMMY_BUFS 4

struct virtual_cam {
    int app_fd;
    int is_active;
    int real_fd;
    int is_dummy;
    char path[64];
    char card_name[64];
    struct v4l2_format fmt;

    // Dummy mode state
    uint32_t sequence;
    void *dummy_bufs[NUM_DUMMY_BUFS];
    int buf_queued[NUM_DUMMY_BUFS];
    pthread_t dummy_thread;
    int dummy_running;
};

#define MAX_VIRT_CAMS 16
static struct virtual_cam g_cams[MAX_VIRT_CAMS];

static void init_fops(void) {
    if (!real_open) real_open = dlsym(RTLD_NEXT, "open");
    if (!real_open64) real_open64 = dlsym(RTLD_NEXT, "open64");
    if (!real_openat) real_openat = dlsym(RTLD_NEXT, "openat");
    if (!real_openat64) real_openat64 = dlsym(RTLD_NEXT, "openat64");
    if (!real_close) real_close = dlsym(RTLD_NEXT, "close");
    if (!real_ioctl) real_ioctl = dlsym(RTLD_NEXT, "ioctl");
    if (!real_mmap) real_mmap = dlsym(RTLD_NEXT, "mmap");
    if (!real_mmap64) real_mmap64 = dlsym(RTLD_NEXT, "mmap64");
    if (!real_munmap) real_munmap = dlsym(RTLD_NEXT, "munmap");
    if (!real_connect_fd) {
        real_connect_fd = dlsym(RTLD_DEFAULT, "pw_context_connect_fd");
        if (!real_connect_fd) {
            void *h = dlopen("libpipewire-0.3.so.0", RTLD_LAZY | RTLD_NOLOAD);
            if (h) real_connect_fd = dlsym(h, "pw_context_connect_fd");
        }
    }
}

static struct virtual_cam *find_cam(int fd) {
    if (fd < 0) return NULL;
    for (int i = 0; i < MAX_VIRT_CAMS; i++) {
        if (g_cams[i].is_active && g_cams[i].app_fd == fd)
            return &g_cams[i];
    }
    return NULL;
}

static void read_hardware_camera_name(const char *dev_path, char *out_name, size_t max_len) {
    const char *base = strrchr(dev_path, '/');
    if (!base) base = dev_path;
    else base++;

    char sys_path[128];
    snprintf(sys_path, sizeof(sys_path), "/sys/class/video4linux/%s/name", base);
    int fd = real_open ? real_open(sys_path, O_RDONLY) : -1;
    if (fd >= 0) {
        ssize_t n = read(fd, out_name, max_len - 1);
        close(fd);
        if (n > 0) {
            out_name[n] = '\0';
            char *colon = strchr(out_name, ':');
            if (colon) *colon = '\0';
            char *nl = strchr(out_name, '\n');
            if (nl) *nl = '\0';
            return;
        }
    }
    strncpy(out_name, "GIGABYTE FHD CAMERA", max_len - 1);
    out_name[max_len - 1] = '\0';
}

static void *dummy_frame_emitter(void *arg) {
    struct virtual_cam *cam = (struct virtual_cam *)arg;
    uint64_t val = 1;
    while (cam->dummy_running) {
        usleep(33333); // 30 FPS throttle
        if (!cam->dummy_running) break;
        if (write(cam->app_fd, &val, sizeof(val)) < 0) {
            // Buffer full or closed
        }
    }
    return NULL;
}

static int request_camera_remote_from_portal(void) {
    DBusError err;
    dbus_error_init(&err);

    DBusConnection *conn = dbus_bus_get(DBUS_BUS_SESSION, &err);
    if (!conn) {
        fprintf(stderr, "[pw-portal-shim] Failed to connect to session bus: %s\n", err.message);
        dbus_error_free(&err);
        return -1;
    }

    DBusMessage *msg = dbus_message_new_method_call(
        "org.freedesktop.portal.Desktop",
        "/org/freedesktop/portal/desktop",
        "org.freedesktop.portal.Camera",
        "AccessCamera"
    );
    if (!msg) return -1;

    DBusMessageIter iter, dict;
    dbus_message_iter_init_append(msg, &iter);
    dbus_message_iter_open_container(&iter, DBUS_TYPE_ARRAY, "{sv}", &dict);
    dbus_message_iter_close_container(&iter, &dict);

    DBusMessage *reply = dbus_connection_send_with_reply_and_block(conn, msg, 120000, &err);
    dbus_message_unref(msg);
    if (!reply) {
        fprintf(stderr, "[pw-portal-shim] AccessCamera call failed: %s\n", err.message);
        dbus_error_free(&err);
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
        return -1;
    }

    int pw_fd = -1;
    dbus_message_get_args(reply, &err, DBUS_TYPE_UNIX_FD, &pw_fd, DBUS_TYPE_INVALID);
    dbus_message_unref(reply);
    return pw_fd;
}

// Override pw_context_connect in libpipewire-0.3 to redirect to portal fd when authorized
struct pw_core *pw_context_connect(struct pw_context *context,
                                    struct pw_properties *properties,
                                    size_t user_data_size)
{
    init_fops();
    if (g_current_portal_fd >= 0 && real_connect_fd) {
        int fd = g_current_portal_fd;
        g_current_portal_fd = -1;
        fprintf(stderr, "[pw-portal-shim] Connecting PipeWire core with fresh portal fd %d\n", fd);
        return real_connect_fd(context, fd, properties, user_data_size);
    }

    struct pw_core *(*real_connect)(struct pw_context *, struct pw_properties *, size_t) =
        dlsym(RTLD_NEXT, "pw_context_connect");
    if (real_connect) return real_connect(context, properties, user_data_size);
    return NULL;
}

static int create_virtual_cam(const char *path) {
    init_fops();
    // Create an eventfd for poll/select/epoll support
    int fd = eventfd(0, EFD_CLOEXEC | EFD_NONBLOCK);
    if (fd < 0) return -1;

    for (int i = 0; i < MAX_VIRT_CAMS; i++) {
        if (!g_cams[i].is_active) {
            struct virtual_cam *cam = &g_cams[i];
            cam->app_fd = fd;
            cam->is_active = 1;
            cam->real_fd = -1;
            cam->is_dummy = 0;
            cam->sequence = 0;
            cam->dummy_running = 0;
            strncpy(cam->path, path, sizeof(cam->path) - 1);
            read_hardware_camera_name(path, cam->card_name, sizeof(cam->card_name));

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
                cam->dummy_bufs[b] = NULL;
                cam->buf_queued[b] = 0;
            }
            return fd;
        }
    }
    close(fd);
    return -1;
}

int open(const char *path, int flags, ...) {
    init_fops();
    va_list args;
    va_start(args, flags);
    mode_t mode = va_arg(args, mode_t);
    va_end(args);

    if (strncmp(path, "/dev/video", 10) == 0) {
        // Return a virtual camera immediately: ZERO prompts during device probing!
        return create_virtual_cam(path);
    }
    return real_open ? real_open(path, flags, mode) : -1;
}

int open64(const char *path, int flags, ...) {
    init_fops();
    va_list args;
    va_start(args, flags);
    mode_t mode = va_arg(args, mode_t);
    va_end(args);

    if (strncmp(path, "/dev/video", 10) == 0) {
        return create_virtual_cam(path);
    }
    return real_open64 ? real_open64(path, flags, mode) : -1;
}

int openat(int dirfd, const char *path, int flags, ...) {
    init_fops();
    va_list args;
    va_start(args, flags);
    mode_t mode = va_arg(args, mode_t);
    va_end(args);

    if (path && strncmp(path, "/dev/video", 10) == 0) {
        return create_virtual_cam(path);
    }
    return real_openat ? real_openat(dirfd, path, flags, mode) : -1;
}

int openat64(int dirfd, const char *path, int flags, ...) {
    init_fops();
    va_list args;
    va_start(args, flags);
    mode_t mode = va_arg(args, mode_t);
    va_end(args);

    if (path && strncmp(path, "/dev/video", 10) == 0) {
        return create_virtual_cam(path);
    }
    return real_openat64 ? real_openat64(dirfd, path, flags, mode) : -1;
}

int close(int fd) {
    init_fops();
    struct virtual_cam *cam = find_cam(fd);
    if (cam) {
        cam->is_active = 0;
        if (cam->dummy_running) {
            cam->dummy_running = 0;
            pthread_join(cam->dummy_thread, NULL);
        }
        for (int b = 0; b < NUM_DUMMY_BUFS; b++) {
            if (cam->dummy_bufs[b]) {
                free(cam->dummy_bufs[b]);
                cam->dummy_bufs[b] = NULL;
            }
        }
        if (cam->real_fd >= 0) {
            if (v4l2_close) v4l2_close(cam->real_fd);
            else real_close(cam->real_fd);
            cam->real_fd = -1;
        }
    }
    return real_close ? real_close(fd) : -1;
}

void *mmap(void *addr, size_t length, int prot, int flags, int fd, off_t offset) {
    init_fops();
    struct virtual_cam *cam = find_cam(fd);
    if (cam) {
        if (cam->is_dummy) {
            int index = offset / DUMMY_BUF_SIZE;
            if (index >= 0 && index < NUM_DUMMY_BUFS) {
                return cam->dummy_bufs[index];
            }
            return MAP_FAILED;
        }
        if (cam->real_fd >= 0) {
            if (v4l2_mmap) return v4l2_mmap(addr, length, prot, flags, cam->real_fd, offset);
            return real_mmap(addr, length, prot, flags, cam->real_fd, offset);
        }
    }
    return real_mmap ? real_mmap(addr, length, prot, flags, fd, offset) : MAP_FAILED;
}

void *mmap64(void *addr, size_t length, int prot, int flags, int fd, off_t offset) {
    init_fops();
    struct virtual_cam *cam = find_cam(fd);
    if (cam) {
        if (cam->is_dummy) {
            int index = offset / DUMMY_BUF_SIZE;
            if (index >= 0 && index < NUM_DUMMY_BUFS) {
                return cam->dummy_bufs[index];
            }
            return MAP_FAILED;
        }
        if (cam->real_fd >= 0) {
            if (v4l2_mmap64) return v4l2_mmap64(addr, length, prot, flags, cam->real_fd, offset);
            if (v4l2_mmap) return v4l2_mmap(addr, length, prot, flags, cam->real_fd, offset);
            return real_mmap64(addr, length, prot, flags, cam->real_fd, offset);
        }
    }
    return real_mmap64 ? real_mmap64(addr, length, prot, flags, fd, offset) : MAP_FAILED;
}

int munmap(void *addr, size_t length) {
    init_fops();
    for (int i = 0; i < MAX_VIRT_CAMS; i++) {
        if (g_cams[i].is_active && g_cams[i].is_dummy) {
            for (int b = 0; b < NUM_DUMMY_BUFS; b++) {
                if (g_cams[i].dummy_bufs[b] == addr)
                    return 0;
            }
        }
    }
    if (v4l2_munmap) return v4l2_munmap(addr, length);
    return real_munmap ? real_munmap(addr, length) : -1;
}

static void activate_dummy_mode(struct virtual_cam *cam) {
    cam->is_dummy = 1;
    for (int b = 0; b < NUM_DUMMY_BUFS; b++) {
        if (!cam->dummy_bufs[b]) {
            cam->dummy_bufs[b] = malloc(DUMMY_BUF_SIZE);
            uint8_t *p = (uint8_t *)cam->dummy_bufs[b];
            for (size_t j = 0; j < DUMMY_BUF_SIZE; j += 4) {
                p[j] = 0;     // Y0 (black)
                p[j+1] = 128; // U
                p[j+2] = 0;   // Y1 (black)
                p[j+3] = 128; // V
            }
        }
        cam->buf_queued[b] = 0;
    }
    if (!cam->dummy_running) {
        cam->dummy_running = 1;
        pthread_create(&cam->dummy_thread, NULL, dummy_frame_emitter, cam);
    }
}

int ioctl(int fd, unsigned long request, ...) {
    init_fops();
    va_list args;
    va_start(args, request);
    void *arg = va_arg(args, void *);
    va_end(args);

    struct virtual_cam *cam = find_cam(fd);
    if (!cam) {
        return real_ioctl ? real_ioctl(fd, request, arg) : -1;
    }

    // If live PipeWire stream is active, delegate directly to real fd!
    if (cam->real_fd >= 0) {
        return v4l2_ioctl ? v4l2_ioctl(cam->real_fd, request, arg) : real_ioctl(cam->real_fd, request, arg);
    }

    // If dummy stream is active:
    if (cam->is_dummy) {
        switch (request & 0xffffffff) {
        case VIDIOC_QUERYCAP: {
            struct v4l2_capability *cap = (struct v4l2_capability *)arg;
            memset(cap, 0, sizeof(*cap));
            strncpy((char *)cap->driver, "PipeWire", sizeof(cap->driver) - 1);
            strncpy((char *)cap->card, cam->card_name, sizeof(cap->card) - 1);
            strncpy((char *)cap->bus_info, "platform:pipewire", sizeof(cap->bus_info) - 1);
            cap->capabilities = V4L2_CAP_VIDEO_CAPTURE | V4L2_CAP_STREAMING | V4L2_CAP_DEVICE_CAPS;
            cap->device_caps = V4L2_CAP_VIDEO_CAPTURE | V4L2_CAP_STREAMING;
            return 0;
        }
        case VIDIOC_G_FMT:
        case VIDIOC_S_FMT:
        case VIDIOC_TRY_FMT: {
            struct v4l2_format *f = (struct v4l2_format *)arg;
            *f = cam->fmt;
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
            // Drain eventfd token
            uint64_t val;
            if (read(cam->app_fd, &val, sizeof(val)) < 0) {
                // Non-blocking drain
            }

            int found = -1;
            for (int i = 0; i < NUM_DUMMY_BUFS; i++) {
                if (cam->buf_queued[i]) {
                    found = i;
                    break;
                }
            }
            if (found < 0) found = 0;
            cam->buf_queued[found] = 0;

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
        case VIDIOC_STREAMON:
        case VIDIOC_STREAMOFF:
            return 0;
        default:
            return 0;
        }
    }

    // In probing state:
    switch (request & 0xffffffff) {
    case VIDIOC_QUERYCAP: {
        struct v4l2_capability *cap = (struct v4l2_capability *)arg;
        memset(cap, 0, sizeof(*cap));
        strncpy((char *)cap->driver, "PipeWire", sizeof(cap->driver) - 1);
        strncpy((char *)cap->card, cam->card_name, sizeof(cap->card) - 1);
        strncpy((char *)cap->bus_info, "platform:pipewire", sizeof(cap->bus_info) - 1);
        cap->capabilities = V4L2_CAP_VIDEO_CAPTURE | V4L2_CAP_STREAMING | V4L2_CAP_DEVICE_CAPS;
        cap->device_caps = V4L2_CAP_VIDEO_CAPTURE | V4L2_CAP_STREAMING;
        return 0;
    }
    case VIDIOC_ENUM_FMT: {
        struct v4l2_fmtdesc *fmt = (struct v4l2_fmtdesc *)arg;
        if (fmt->type != V4L2_BUF_TYPE_VIDEO_CAPTURE) return -EINVAL;
        if (fmt->index == 0) {
            fmt->pixelformat = V4L2_PIX_FMT_YUYV;
            strncpy((char *)fmt->description, "YUYV 4:2:2", sizeof(fmt->description) - 1);
            return 0;
        } else if (fmt->index == 1) {
            fmt->pixelformat = V4L2_PIX_FMT_MJPEG;
            strncpy((char *)fmt->description, "Motion-JPEG", sizeof(fmt->description) - 1);
            return 0;
        }
        return -EINVAL;
    }
    case VIDIOC_ENUM_FRAMESIZES: {
        struct v4l2_frmsizeenum *fsize = (struct v4l2_frmsizeenum *)arg;
        if (fsize->index == 0) {
            fsize->type = V4L2_FRMSIZE_TYPE_DISCRETE;
            fsize->discrete.width = 1920; fsize->discrete.height = 1080;
            return 0;
        } else if (fsize->index == 1) {
            fsize->type = V4L2_FRMSIZE_TYPE_DISCRETE;
            fsize->discrete.width = 1280; fsize->discrete.height = 720;
            return 0;
        } else if (fsize->index == 2) {
            fsize->type = V4L2_FRMSIZE_TYPE_DISCRETE;
            fsize->discrete.width = 640; fsize->discrete.height = 480;
            return 0;
        }
        return -EINVAL;
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
    case VIDIOC_G_FMT: {
        struct v4l2_format *f = (struct v4l2_format *)arg;
        *f = cam->fmt;
        return 0;
    }
    case VIDIOC_S_FMT:
    case VIDIOC_TRY_FMT: {
        struct v4l2_format *f = (struct v4l2_format *)arg;
        cam->fmt = *f;
        return 0;
    }
    case VIDIOC_REQBUFS:
    case VIDIOC_STREAMON: {
        // ACTUAL STREAM DATA FLOW INITIATED!
        // This is the trigger: prompt the user now!
        int portal_fd = request_camera_remote_from_portal();
        if (portal_fd < 0) {
            // User denied camera access: activate graceful dummy camera!
            activate_dummy_mode(cam);
            return ioctl(cam->app_fd, request, arg);
        }

        // User allowed: connect libpw-v4l2 to PipeWire using this fresh portal remote fd!
        g_current_portal_fd = portal_fd;
        int real_cam_fd = -1;
        if (ensure_v4l2_loaded() && v4l2_open) {
            real_cam_fd = v4l2_open(cam->path, O_RDWR);
        }

        if (real_cam_fd < 0) {
            if (g_current_portal_fd >= 0) {
                if (real_close) real_close(g_current_portal_fd);
                else close(g_current_portal_fd);
                g_current_portal_fd = -1;
            }
            fprintf(stderr, "[pw-portal-shim] Failed to open libpw-v4l2 stream\n");
            activate_dummy_mode(cam);
            return ioctl(cam->app_fd, request, arg);
        }

        // Apply saved format
        if (v4l2_ioctl) v4l2_ioctl(real_cam_fd, VIDIOC_S_FMT, &cam->fmt);
        else real_ioctl(real_cam_fd, VIDIOC_S_FMT, &cam->fmt);

        // Replace dummy eventfd with the real stream eventfd in the kernel table
        dup2(real_cam_fd, cam->app_fd);
        cam->real_fd = real_cam_fd;

        return v4l2_ioctl ? v4l2_ioctl(cam->real_fd, request, arg) : real_ioctl(cam->real_fd, request, arg);
    }
    default:
        return 0;
    }
}
