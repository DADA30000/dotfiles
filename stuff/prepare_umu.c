#define _GNU_SOURCE
#include "asm/unistd_64.h" // for __NR_mount_setattr, __NR_move_mount, __NR...
#include "linux/mount.h"   // for OPEN_TREE_CLOEXEC
#include <fcntl.h>         // for open, O_CLOEXEC, O_RDONLY, AT_EMPTY_PATH
#include <linux/loop.h>    // for loop_info64, LOOP_CLR_FD, LOOP_CTL_GET_FREE
#include <pwd.h>           // for passwd, getpwuid
#include <sched.h>         // for CLONE_NEWUSER, unshare
#include <signal.h>        // for SIGKILL, kill
#include <stdint.h>        // for uint64_t
#include <stdio.h>         // for snprintf, NULL
#include <stdlib.h>        // for exit, mkdtemp
#include <sys/ioctl.h>     // for ioctl
#include <sys/mount.h>     // for MNT_DETACH, umount2, MS_NODEV, MS_NOSUID
#include <sys/stat.h>      // for stat, mkdir, fstat, lstat
#include <sys/statfs.h>    // for statfs, fstatfs
#include <sys/types.h>     // for uid_t, gid_t, pid_t, dev_t
#include <sys/wait.h>      // for waitpid
#include <unistd.h>        // for close, rmdir, setegid, seteuid, syscall

struct clone_mount_attr {
  uint64_t attr_set;
  uint64_t attr_clr;
  uint64_t propagation;
  uint64_t userns_fd;
};

#define TRUSTED_LOWER_IMG "%{{{runtime}}}"
#define IMAGE_UID 0
#define IMAGE_GID 0

static int write_map(pid_t pid, const char *file, unsigned int id1,
                     unsigned int id2) {
  char path[64], map[256];
  snprintf(path, sizeof(path), "/proc/%d/%s", pid, file);
  if (id1 > id2) {
    unsigned int t = id1;
    id1 = id2;
    id2 = t;
  }

  int off = (id1 == id2) ? snprintf(map, sizeof(map), "0 0 65536\n") : 0;
  if (id1 != id2) {
    if (id1 > 0)
      off += snprintf(map + off, sizeof(map) - off, "0 0 %u\n", id1);
    off += snprintf(map + off, sizeof(map) - off, "%u %u 1\n", id1, id2);
    if (id2 > id1 + 1)
      off += snprintf(map + off, sizeof(map) - off, "%u %u %u\n", id1 + 1,
                      id1 + 1, id2 - id1 - 1);
    off += snprintf(map + off, sizeof(map) - off, "%u %u 1\n", id2, id1);
    if (id2 < 65535)
      off += snprintf(map + off, sizeof(map) - off, "%u %u %u\n", id2 + 1,
                      id2 + 1, 65535 - id2);
  }

  int fd = open(path, O_WRONLY);
  if (fd < 0)
    return -1;
  int ret = write(fd, map, off) == off ? 0 : -1;
  close(fd);
  return ret;
}

static int create_userns(uid_t i_uid, uid_t u_uid, gid_t i_gid, gid_t u_gid) {
  int pipefd[2];
  if (pipe(pipefd) < 0)
    return -1;
  pid_t pid = fork();
  if (pid < 0) {
    close(pipefd[0]);
    close(pipefd[1]);
    return -1;
  }

  if (pid == 0) {
    close(pipefd[0]);
    if (unshare(CLONE_NEWUSER) != 0 || write(pipefd[1], "1", 1) != 1)
      exit(1);
    close(pipefd[1]);
    pause();
    exit(0);
  }
  close(pipefd[1]);

  char c;
  if (read(pipefd[0], &c, 1) <= 0 ||
      write_map(pid, "uid_map", i_uid, u_uid) < 0)
    goto err;
  close(pipefd[0]);

  char path[64];
  snprintf(path, sizeof(path), "/proc/%d/setgroups", pid);
  int fd = open(path, O_WRONLY);
  if (fd >= 0) {
    if (write(fd, "deny", 4) < 0) {
    }
    close(fd);
  }

  if (write_map(pid, "gid_map", i_gid, u_gid) < 0)
    goto err;

  snprintf(path, sizeof(path), "/proc/%d/ns/user", pid);
  int userns_fd = open(path, O_RDONLY | O_CLOEXEC);

  kill(pid, SIGKILL);
  waitpid(pid, NULL, 0);
  return userns_fd;

err:
  close(pipefd[0]);
  kill(pid, SIGKILL);
  waitpid(pid, NULL, 0);
  return -1;
}

static int open_safe_dir(const char *path, uid_t uid, dev_t dev) {
  int fd = open(path, O_PATH | O_NOFOLLOW | O_DIRECTORY | O_CLOEXEC);
  if (fd < 0)
    return -1;
  struct stat st;
  struct statfs sfs;
  if (fstat(fd, &st) != 0 || fstatfs(fd, &sfs) != 0 || st.st_uid != uid ||
      st.st_dev != dev || sfs.f_type == 0x65735546 /* FUSE */ ||
      sfs.f_type == 0x794c7630 /* OVERLAYFS */) {
    close(fd);
    return -1;
  }
  return fd;
}

int main(void) {
  uid_t uid = getuid(), euid = geteuid();
  gid_t gid = getgid(), egid = getegid();
  int ret = 1;

  struct passwd *pw = getpwuid(uid);
  if (!pw || !pw->pw_dir)
    return 1;

  struct stat homest;
  if (lstat(pw->pw_dir, &homest) != 0)
    return 1;

  char target[512], upper[512], work[512];
  if (snprintf(target, sizeof(target), "%s/.local/share/umu", pw->pw_dir) >=
          sizeof(target) ||
      snprintf(upper, sizeof(upper), "%s/.local/share/umu-upper", pw->pw_dir) >=
          sizeof(upper) ||
      snprintf(work, sizeof(work), "%s/.local/share/umu-work", pw->pw_dir) >=
          sizeof(work)) {
    return 1;
  }

  // Drop privileges temporarily to safely resolve and unmount existing paths
  if (setegid(gid) != 0 || seteuid(uid) != 0)
    return 1;

  // SECURE AUTO-UNMOUNT: Since the system mounted this, the user can't umount
  // it. We use O_PATH to prevent symlink TOCTOU attacks while verifying the
  // mount.
  int unmount_fd = open(target, O_PATH | O_NOFOLLOW | O_DIRECTORY | O_CLOEXEC);
  if (unmount_fd >= 0) {
    struct stat st;
    struct statfs sfs;
    if (fstat(unmount_fd, &st) == 0 && fstatfs(unmount_fd, &sfs) == 0) {
      // Ensure we only unmount if it's an OverlayFS currently owned by this
      // user
      if (st.st_uid == uid && sfs.f_type == 0x794c7630) {
        if (seteuid(euid) == 0 &&
            setegid(egid) == 0) { // Restore SUID to unmount
          char target_proc[64];
          snprintf(target_proc, sizeof(target_proc), "/proc/self/fd/%d",
                   unmount_fd);
          umount2(target_proc, MNT_DETACH);
          if (setegid(gid) != 0 || seteuid(uid) != 0)
            return 1; // Drop again
        }
      }
    }
    close(unmount_fd);
  }

  mkdir(upper, 0755);
  mkdir(work, 0755);
  mkdir(target, 0755);

  int target_fd = open_safe_dir(target, uid, homest.st_dev);
  int upper_fd = open_safe_dir(upper, uid, homest.st_dev);
  int work_fd = open_safe_dir(work, uid, homest.st_dev);

  // Restore SUID capability to actually perform mounts
  if (seteuid(euid) != 0 || setegid(egid) != 0)
    return 1;
  if (target_fd < 0 || upper_fd < 0 || work_fd < 0)
    goto cleanup_fds;

  // Prefixing with a dot ignores 'udisks2' UI pollers (e.g. Nautilus)
  char tmp_path[] = "/tmp/.umu-XXXXXX";
  if (!mkdtemp(tmp_path))
    goto cleanup_fds;

  int ctrl_fd = open("/dev/loop-control", O_RDWR | O_CLOEXEC);
  if (ctrl_fd < 0)
    goto cleanup_tmp;
  int dev_num = ioctl(ctrl_fd, LOOP_CTL_GET_FREE);
  close(ctrl_fd);
  if (dev_num < 0)
    goto cleanup_tmp;

  char loop_dev[64];
  snprintf(loop_dev, sizeof(loop_dev), "/dev/loop%d", dev_num);

  int img_fd = open(TRUSTED_LOWER_IMG, O_RDONLY | O_CLOEXEC);
  int loop_fd = open(loop_dev, O_RDONLY | O_CLOEXEC);
  if (img_fd < 0 || loop_fd < 0 || ioctl(loop_fd, LOOP_SET_FD, img_fd) < 0) {
    if (img_fd >= 0)
      close(img_fd);
    if (loop_fd >= 0)
      close(loop_fd);
    goto cleanup_tmp;
  }
  close(img_fd);

  struct loop_info64 info = {.lo_flags =
                                 LO_FLAGS_READ_ONLY | LO_FLAGS_AUTOCLEAR};
  if (ioctl(loop_fd, LOOP_SET_STATUS64, &info) < 0 ||
      mount(loop_dev, tmp_path, "erofs", MS_RDONLY | MS_NOSUID | MS_NODEV,
            NULL) != 0) {
    ioctl(loop_fd, LOOP_CLR_FD, 0);
    close(loop_fd);
    goto cleanup_tmp;
  }
  close(loop_fd);

  int tree_fd = syscall(__NR_open_tree, AT_FDCWD, tmp_path,
                        OPEN_TREE_CLOEXEC | 1); // 1 is OPEN_TREE_CLONE
  umount2(tmp_path, MNT_DETACH); // Instantly detach origin from namespace
  if (tree_fd < 0)
    goto cleanup_tmp;

  if (IMAGE_UID != uid || IMAGE_GID != gid) {
    int userns_fd = create_userns(IMAGE_UID, uid, IMAGE_GID, gid);
    if (userns_fd < 0) {
      close(tree_fd);
      goto cleanup_tmp;
    }

    struct clone_mount_attr attr = {.attr_set = MOUNT_ATTR_IDMAP,
                                    .userns_fd = userns_fd};
    if (syscall(__NR_mount_setattr, tree_fd, "", AT_EMPTY_PATH | AT_RECURSIVE,
                &attr, sizeof(attr)) != 0) {
      close(userns_fd);
      close(tree_fd);
      goto cleanup_tmp;
    }
    close(userns_fd);
  }

  if (syscall(__NR_move_mount, tree_fd, "", AT_FDCWD, tmp_path,
              MOVE_MOUNT_F_EMPTY_PATH) != 0) {
    close(tree_fd);
    goto cleanup_tmp;
  }
  close(tree_fd);

  char opts[2048], target_proc[64];
  snprintf(opts, sizeof(opts),
           "lowerdir=%s,upperdir=/proc/self/fd/%d,workdir=/proc/self/fd/"
           "%d,index=on,metacopy=on,redirect_dir=on",
           tmp_path, upper_fd, work_fd);
  snprintf(target_proc, sizeof(target_proc), "/proc/self/fd/%d", target_fd);

  if (mount("overlay", target_proc, "overlay", MS_NOSUID | MS_NODEV, opts) ==
      0) {
    ret = 0; // Success
  }

  umount2(tmp_path, MNT_DETACH);
cleanup_tmp:
  rmdir(tmp_path);
cleanup_fds:
  if (target_fd >= 0)
    close(target_fd);
  if (upper_fd >= 0)
    close(upper_fd);
  if (work_fd >= 0)
    close(work_fd);
  return ret;
}
