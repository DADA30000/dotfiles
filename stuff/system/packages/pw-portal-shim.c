#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <errno.h>
#include <dlfcn.h>
#include <fcntl.h>
#include <stdarg.h>
#include <sys/ioctl.h>
#include <sys/stat.h>
#include <sys/mman.h>
#include <linux/videodev2.h>
#include <dbus/dbus.h>
#include <pipewire/pipewire.h>

static int (*real_open)(const char *, int, ...) = NULL;
static int (*real_openat)(int, const char *, int, ...) = NULL;
static int (*real_close)(int) = NULL;
static int (*real_ioctl)(int, unsigned long, ...) = NULL;
static void *(*real_mmap)(void *, size_t, int, int, int, off_t) = NULL;
static int (*real_munmap)(void *, size_t) = NULL;
static struct pw_core *(*real_connect_fd)(struct pw_context *, int, struct pw_properties *, size_t) = NULL;

static DBusConnection *g_dbus_conn = NULL;
static int g_portal_fd = -1;

struct virtual_cam {
    int fd;
    int is_active;
    int real_fd;
    char path[64];
    struct v4l2_format fmt;
};

#define MAX_VIRT_CAMS 16
static struct virtual_cam g_cams[MAX_VIRT_CAMS];

static struct virtual_cam *find_cam(int fd) {
    if (fd < 0) return NULL;
    for (int i = 0; i < MAX_VIRT_CAMS; i++) {
        if (g_cams[i].is_active && g_cams[i].fd == fd)
            return &g_cams[i];
    }
    return NULL;
}

static void init_libc_fops(void) {
    if (!real_open) real_open = dlsym(RTLD_NEXT, "open");
    if (!real_openat) real_openat = dlsym(RTLD_NEXT, "openat");
    if (!real_close) real_close = dlsym(RTLD_NEXT, "close");
    if (!real_ioctl) real_ioctl = dlsym(RTLD_NEXT, "ioctl");
    if (!real_mmap) real_mmap = dlsym(RTLD_NEXT, "mmap");
    if (!real_munmap) real_munmap = dlsym(RTLD_NEXT, "munmap");
}

static int request_camera_fd_from_portal(void) {
    if (g_portal_fd >= 0) return g_portal_fd;

    DBusError err;
    dbus_error_init(&err);

    if (!g_dbus_conn) {
        g_dbus_conn = dbus_bus_get(DBUS_BUS_SESSION, &err);
        if (!g_dbus_conn) {
            fprintf(stderr, "[pw-portal-shim] Failed to connect to session D-Bus: %s\n",
                    err.message ? err.message : "unknown error");
            dbus_error_free(&err);
            return -1;
        }
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

    DBusMessage *reply = dbus_connection_send_with_reply_and_block(g_dbus_conn, msg, 120000, &err);
    dbus_message_unref(msg);

    if (!reply) {
        fprintf(stderr, "[pw-portal-shim] AccessCamera call failed: %s\n",
                err.message ? err.message : "unknown error");
        dbus_error_free(&err);
        return -1;
    }

    const char *request_path = NULL;
    if (!dbus_message_get_args(reply, &err, DBUS_TYPE_OBJECT_PATH, &request_path, DBUS_TYPE_INVALID)) {
        dbus_message_unref(reply);
        dbus_error_free(&err);
        return -1;
    }
    char *req_path_copy = strdup(request_path);
    dbus_message_unref(reply);

    char match_rule[512];
    snprintf(match_rule, sizeof(match_rule),
             "type='signal',interface='org.freedesktop.portal.Request',member='Response',path='%s'",
             req_path_copy);
    dbus_bus_add_match(g_dbus_conn, match_rule, &err);
    dbus_connection_flush(g_dbus_conn);
    if (dbus_error_is_set(&err)) {
        free(req_path_copy);
        dbus_error_free(&err);
        return -1;
    }

    int granted = 0;
    while (dbus_connection_read_write_dispatch(g_dbus_conn, -1)) {
        DBusMessage *sig = dbus_connection_pop_message(g_dbus_conn);
        if (!sig) continue;

        if (dbus_message_is_signal(sig, "org.freedesktop.portal.Request", "Response") &&
            strcmp(dbus_message_get_path(sig), req_path_copy) == 0) {
            uint32_t response_code = 1;
            DBusMessageIter sig_iter;
            if (dbus_message_iter_init(sig, &sig_iter) &&
                dbus_message_iter_get_arg_type(&sig_iter) == DBUS_TYPE_UINT32) {
                dbus_message_iter_get_basic(&sig_iter, &response_code);
            }
            if (response_code == 0) {
                granted = 1;
            } else {
                fprintf(stderr, "[pw-portal-shim] Camera permission denied by user (response %u)\n", response_code);
            }
            dbus_message_unref(sig);
            break;
        }
        dbus_message_unref(sig);
    }
    free(req_path_copy);

    if (!granted) return -1;

    msg = dbus_message_new_method_call(
        "org.freedesktop.portal.Desktop",
        "/org/freedesktop/portal/desktop",
        "org.freedesktop.portal.Camera",
        "OpenPipeWireRemote"
    );
    if (!msg) return -1;
    dbus_message_iter_init_append(msg, &iter);
    dbus_message_iter_open_container(&iter, DBUS_TYPE_ARRAY, "{sv}", &dict);
    dbus_message_iter_close_container(&iter, &dict);

    reply = dbus_connection_send_with_reply_and_block(g_dbus_conn, msg, 10000, &err);
    dbus_message_unref(msg);
    if (!reply) {
        fprintf(stderr, "[pw-portal-shim] OpenPipeWireRemote call failed: %s\n",
                err.message ? err.message : "unknown error");
        dbus_error_free(&err);
        return -1;
    }

    int pw_fd = -1;
    if (!dbus_message_get_args(reply, &err, DBUS_TYPE_UNIX_FD, &pw_fd, DBUS_TYPE_INVALID)) {
        fprintf(stderr, "[pw-portal-shim] Failed to extract UNIX fd from reply: %s\n",
                err.message ? err.message : "unknown error");
        dbus_error_free(&err);
        dbus_message_unref(reply);
        return -1;
    }
    dbus_message_unref(reply);

    usleep(50000);
    g_portal_fd = pw_fd;
    return g_portal_fd;
}

// Override pw_context_connect in libpipewire-0.3 to redirect to portal fd
struct pw_core *pw_context_connect(struct pw_context *context,
                                    struct pw_properties *properties,
                                    size_t user_data_size)
{
    if (!real_connect_fd) {
        void *handle = dlopen("libpipewire-0.3.so.0", RTLD_LAZY | RTLD_NOLOAD);
        if (handle) {
            real_connect_fd = dlsym(handle, "pw_context_connect_fd");
            dlclose(handle);
        }
        if (!real_connect_fd) {
            real_connect_fd = dlsym(RTLD_DEFAULT, "pw_context_connect_fd");
        }
    }
    if (!real_connect_fd) {
        fprintf(stderr, "[pw-portal-shim] Cannot resolve pw_context_connect_fd\n");
        errno = ENOSYS;
        return NULL;
    }

    int portal_fd = request_camera_fd_from_portal();
    if (portal_fd < 0) {
        errno = EPERM;
        return NULL;
    }

    fprintf(stderr, "[pw-portal-shim] Camera portal access authorized, connecting via fd %d\n", portal_fd);
    return real_connect_fd(context, portal_fd, properties, user_data_size);
}

static int create_virtual_cam(const char *path) {
    init_libc_fops();
    int fd = real_open("/dev/null", O_RDWR);
    if (fd < 0) return -1;

    for (int i = 0; i < MAX_VIRT_CAMS; i++) {
        if (!g_cams[i].is_active) {
            g_cams[i].fd = fd;
            g_cams[i].is_active = 1;
            g_cams[i].real_fd = -1;
            strncpy(g_cams[i].path, path, sizeof(g_cams[i].path) - 1);
            memset(&g_cams[i].fmt, 0, sizeof(g_cams[i].fmt));
            g_cams[i].fmt.type = V4L2_BUF_TYPE_VIDEO_CAPTURE;
            g_cams[i].fmt.fmt.pix.width = 1280;
            g_cams[i].fmt.fmt.pix.height = 720;
            g_cams[i].fmt.fmt.pix.pixelformat = V4L2_PIX_FMT_MJPEG;
            g_cams[i].fmt.fmt.pix.field = V4L2_FIELD_NONE;
            return fd;
        }
    }
    real_close(fd);
    return -1;
}

int open(const char *path, int flags, ...) {
    init_libc_fops();
    if (strncmp(path, "/dev/video", 10) == 0) {
        return create_virtual_cam(path);
    }
    va_list args;
    va_start(args, flags);
    mode_t mode = va_arg(args, mode_t);
    va_end(args);
    return real_open(path, flags, mode);
}

int open64(const char *path, int flags, ...) {
    init_libc_fops();
    if (strncmp(path, "/dev/video", 10) == 0) {
        return create_virtual_cam(path);
    }
    va_list args;
    va_start(args, flags);
    mode_t mode = va_arg(args, mode_t);
    va_end(args);
    return real_open(path, flags, mode);
}

int openat(int dirfd, const char *path, int flags, ...) {
    init_libc_fops();
    if (strncmp(path, "/dev/video", 10) == 0) {
        return create_virtual_cam(path);
    }
    va_list args;
    va_start(args, flags);
    mode_t mode = va_arg(args, mode_t);
    va_end(args);
    return real_openat(dirfd, path, flags, mode);
}

int openat64(int dirfd, const char *path, int flags, ...) {
    init_libc_fops();
    if (strncmp(path, "/dev/video", 10) == 0) {
        return create_virtual_cam(path);
    }
    va_list args;
    va_start(args, flags);
    mode_t mode = va_arg(args, mode_t);
    va_end(args);
    return real_openat(dirfd, path, flags, mode);
}

int close(int fd) {
    init_libc_fops();
    struct virtual_cam *cam = find_cam(fd);
    if (cam) {
        cam->is_active = 0;
        if (cam->real_fd >= 0) {
            real_close(cam->real_fd);
            cam->real_fd = -1;
        }
        if (g_portal_fd >= 0) {
            close(g_portal_fd);
            g_portal_fd = -1;
        }
    }
    return real_close(fd);
}

void *mmap(void *addr, size_t length, int prot, int flags, int fd, off_t offset) {
    init_libc_fops();
    struct virtual_cam *cam = find_cam(fd);
    int target_fd = (cam && cam->real_fd >= 0) ? cam->real_fd : fd;
    return real_mmap(addr, length, prot, flags, target_fd, offset);
}

void *mmap64(void *addr, size_t length, int prot, int flags, int fd, off_t offset) {
    init_libc_fops();
    struct virtual_cam *cam = find_cam(fd);
    int target_fd = (cam && cam->real_fd >= 0) ? cam->real_fd : fd;
    return real_mmap(addr, length, prot, flags, target_fd, offset);
}

int ioctl(int fd, unsigned long request, ...) {
    init_libc_fops();
    va_list args;
    va_start(args, request);
    void *arg = va_arg(args, void *);
    va_end(args);

    struct virtual_cam *cam = find_cam(fd);
    if (!cam) {
        return real_ioctl(fd, request, arg);
    }

    if (cam->real_fd >= 0) {
        return real_ioctl(cam->real_fd, request, arg);
    }

    switch (request & 0xffffffff) {
    case VIDIOC_QUERYCAP: {
        struct v4l2_capability *cap = (struct v4l2_capability *)arg;
        memset(cap, 0, sizeof(*cap));
        strncpy((char *)cap->driver, "PipeWire", sizeof(cap->driver) - 1);
        strncpy((char *)cap->card, "Camera (Portal)", sizeof(cap->card) - 1);
        strncpy((char *)cap->bus_info, "platform:pipewire", sizeof(cap->bus_info) - 1);
        cap->capabilities = V4L2_CAP_VIDEO_CAPTURE | V4L2_CAP_STREAMING | V4L2_CAP_DEVICE_CAPS;
        cap->device_caps = V4L2_CAP_VIDEO_CAPTURE | V4L2_CAP_STREAMING;
        return 0;
    }
    case VIDIOC_ENUM_FMT: {
        struct v4l2_fmtdesc *fmt = (struct v4l2_fmtdesc *)arg;
        if (fmt->type != V4L2_BUF_TYPE_VIDEO_CAPTURE) return -EINVAL;
        if (fmt->index == 0) {
            fmt->pixelformat = V4L2_PIX_FMT_MJPEG;
            strncpy((char *)fmt->description, "Motion-JPEG", sizeof(fmt->description) - 1);
            return 0;
        } else if (fmt->index == 1) {
            fmt->pixelformat = V4L2_PIX_FMT_YUYV;
            strncpy((char *)fmt->description, "YUYV 4:2:2", sizeof(fmt->description) - 1);
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
    case VIDIOC_STREAMOFF: {
        if (cam->real_fd >= 0) {
            int res = real_ioctl(cam->real_fd, request, arg);
            real_close(cam->real_fd);
            cam->real_fd = -1;
            if (g_portal_fd >= 0) {
                close(g_portal_fd);
                g_portal_fd = -1;
            }
            return res;
        }
        return 0;
    }
    case VIDIOC_REQBUFS:
    case VIDIOC_STREAMON: {
        // ACTUAL STREAM DATA REQUESTED!
        int portal_fd = request_camera_fd_from_portal();
        if (portal_fd < 0) {
            errno = EPERM;
            return -1;
        }
        // Call libpw-v4l2 open to get real PipeWire stream fd
        int real_cam_fd = -1;
        void *handle = dlopen("libpw-v4l2.so", RTLD_LAZY | RTLD_NOLOAD);
        if (handle) {
            int (*v4l2_open)(const char *, int, ...) = dlsym(handle, "open");
            if (v4l2_open) real_cam_fd = v4l2_open(cam->path, O_RDWR);
            dlclose(handle);
        }
        if (real_cam_fd < 0) {
            int (*pw_open)(const char *, int, ...) = dlsym(RTLD_DEFAULT, "open");
            if (pw_open && pw_open != open) {
                real_cam_fd = pw_open(cam->path, O_RDWR);
            }
        }
        if (real_cam_fd < 0) {
            errno = EIO;
            return -1;
        }

        // Apply format on real fd
        real_ioctl(real_cam_fd, VIDIOC_S_FMT, &cam->fmt);

        // Replace dummy fd in kernel with real fd so poll/select/epoll wake up!
        dup2(real_cam_fd, cam->fd);
        cam->real_fd = real_cam_fd;

        return real_ioctl(cam->real_fd, request, arg);
    }
    default:
        return -ENOTTY;
    }
}
