#define _GNU_SOURCE

#include <errno.h>
#include <fcntl.h>
#include <grp.h>
#include <limits.h>
#include <pwd.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mount.h>
#include <sys/prctl.h>
#include <sys/stat.h>
#include <sys/statfs.h>
#include <unistd.h>

#ifndef FUSE_SUPER_MAGIC
#define FUSE_SUPER_MAGIC 0x65735546
#endif

static int parse_uid(const char *s, uid_t *out) {
    if (!s || s[0] == '\0') {
        return -1;
    }
    char *end = NULL;
    errno = 0;
    unsigned long val = strtoul(s, &end, 10);
    if (errno != 0 || *end != '\0' || val == 0 || val > UINT_MAX) {
        return -1;
    }
    *out = (uid_t)val;
    return 0;
}

static int unmount_if_fuse(const char *doc_path) {
    struct stat st;
    struct statfs stfs;
    int is_fuse = 0;

    if (lstat(doc_path, &st) == -1 && errno == ENOTCONN) {
        is_fuse = 1;
    } else if (statfs(doc_path, &stfs) == -1 && errno == ENOTCONN) {
        is_fuse = 1;
    } else if (statfs(doc_path, &stfs) == 0 && (unsigned long)stfs.f_type == FUSE_SUPER_MAGIC) {
        is_fuse = 1;
    }

    if (is_fuse) {
        if (umount2(doc_path, MNT_DETACH) != 0 && errno != EINVAL && errno != ENOENT) {
            perror("xdp-document-portal-launch: umount2");
            return -1;
        }
    }
    return 0;
}

int main(int argc, char **argv) {
    if (argc == 3 && strcmp(argv[1], "-u") == 0) {
        uid_t uid = 0;
        if (parse_uid(argv[2], &uid) != 0) {
            fprintf(stderr, "xdp-document-portal-launch: invalid uid '%s'\n", argv[2]);
            return 2;
        }
        char doc_path[128];
        snprintf(doc_path, sizeof(doc_path), "/run/user/%u/doc", (unsigned)uid);
        return unmount_if_fuse(doc_path) == 0 ? 0 : 1;
    }

    if (argc != 3) {
        fprintf(stderr, "usage: %s <uid> <xdg-document-portal-bin>\n       %s -u <uid>\n", argv[0], argv[0]);
        return 2;
    }

    uid_t uid = 0;
    if (parse_uid(argv[1], &uid) != 0) {
        fprintf(stderr, "xdp-document-portal-launch: invalid uid '%s'\n", argv[1]);
        return 2;
    }
    const char *portal_bin = argv[2];

    struct passwd *pw = getpwuid(uid);
    if (!pw) {
        fprintf(stderr, "xdp-document-portal-launch: unknown uid %u\n", (unsigned)uid);
        return 1;
    }
    gid_t gid = pw->pw_gid;

    char rt_path[64];
    char doc_path[128];
    snprintf(rt_path, sizeof(rt_path), "/run/user/%u", (unsigned)uid);
    snprintf(doc_path, sizeof(doc_path), "/run/user/%u/doc", (unsigned)uid);

    int rt_fd = open(rt_path, O_PATH | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
    if (rt_fd < 0) {
        perror("xdp-document-portal-launch: open runtime dir");
        return 1;
    }

    struct stat rt_st;
    if (fstat(rt_fd, &rt_st) != 0 || !S_ISDIR(rt_st.st_mode) || rt_st.st_uid != uid) {
        fprintf(stderr, "xdp-document-portal-launch: runtime dir ownership mismatch\n");
        close(rt_fd);
        return 1;
    }

    unmount_if_fuse(doc_path);

    if (mkdirat(rt_fd, "doc", 0700) != 0 && errno != EEXIST) {
        perror("xdp-document-portal-launch: mkdirat doc");
        close(rt_fd);
        return 1;
    }

    int doc_fd = openat(rt_fd, "doc", O_PATH | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
    if (doc_fd < 0) {
        perror("xdp-document-portal-launch: openat doc");
        close(rt_fd);
        return 1;
    }

    struct stat doc_st;
    if (fstat(doc_fd, &doc_st) != 0 || !S_ISDIR(doc_st.st_mode)) {
        fprintf(stderr, "xdp-document-portal-launch: doc is not a directory\n");
        close(doc_fd);
        close(rt_fd);
        return 1;
    }

    if (doc_st.st_uid == 0) {
        if (fchownat(rt_fd, "doc", uid, gid, AT_SYMLINK_NOFOLLOW) != 0) {
            perror("xdp-document-portal-launch: fchownat doc");
            close(doc_fd);
            close(rt_fd);
            return 1;
        }
    } else if (doc_st.st_uid != uid) {
        fprintf(stderr, "xdp-document-portal-launch: doc dir owned by unexpected uid %u\n", (unsigned)doc_st.st_uid);
        close(doc_fd);
        close(rt_fd);
        return 1;
    }

    /* Keep /dev/fuse open across exec so xdg-document-portal uses /dev/fd/<N>. */
    int fuse_fd = open("/dev/fuse", O_RDWR);
    if (fuse_fd < 0) {
        perror("xdp-document-portal-launch: open /dev/fuse");
        close(doc_fd);
        close(rt_fd);
        return 1;
    }

    char target_proc[64];
    char mount_opts[160];
    snprintf(target_proc, sizeof(target_proc), "/proc/self/fd/%d", doc_fd);
    snprintf(
        mount_opts,
        sizeof(mount_opts),
        "fd=%d,rootmode=040000,user_id=%u,group_id=%u",
        fuse_fd,
        (unsigned)uid,
        (unsigned)gid
    );

    if (mount("portal", target_proc, "fuse.portal", MS_NOSUID | MS_NODEV, mount_opts) != 0) {
        perror("xdp-document-portal-launch: mount fuse.portal");
        close(fuse_fd);
        close(doc_fd);
        close(rt_fd);
        return 1;
    }

    close(doc_fd);
    close(rt_fd);

    /* Drop all privileges permanently before exec'ing xdg-document-portal. */
    if (setgroups(0, NULL) != 0) {
        perror("xdp-document-portal-launch: setgroups");
        return 1;
    }
    if (setresgid(gid, gid, gid) != 0) {
        perror("xdp-document-portal-launch: setresgid");
        return 1;
    }
    if (setresuid(uid, uid, uid) != 0) {
        perror("xdp-document-portal-launch: setresuid");
        return 1;
    }
    if (prctl(PR_SET_NO_NEW_PRIVS, 1, 0, 0, 0) != 0) {
        perror("xdp-document-portal-launch: prctl(PR_SET_NO_NEW_PRIVS)");
        return 1;
    }

    char fuse_fd_str[32];
    char bus_addr[128];
    snprintf(fuse_fd_str, sizeof(fuse_fd_str), "%d", fuse_fd);
    snprintf(bus_addr, sizeof(bus_addr), "unix:path=%s/bus", rt_path);

    setenv("XDG_RUNTIME_DIR", rt_path, 1);
    setenv("HOME", pw->pw_dir, 1);
    setenv("DBUS_SESSION_BUS_ADDRESS", bus_addr, 1);
    setenv("XDP_FUSE_FD", fuse_fd_str, 1);

    char *child_argv[] = { (char *)portal_bin, NULL };
    execv(portal_bin, child_argv);
    perror("xdp-document-portal-launch: execv");
    return 127;
}
