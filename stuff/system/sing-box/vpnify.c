#define _GNU_SOURCE
#include <fcntl.h>
#include <linux/capability.h>
#include <sched.h>
#include <stdio.h>
#include <sys/prctl.h>
#include <sys/syscall.h>
#include <unistd.h>

int main(int argc, char **argv) {
  if (argc < 2) {
    fprintf(stderr, "usage: vpnify <cmd> [args...]\n");
    return 1;
  }

  int fd = open("/var/run/netns/vpn_wrapper", O_RDONLY | O_CLOEXEC);
  if (fd < 0) {
    perror("open netns");
    return 1;
  }

  if (setns(fd, CLONE_NEWNET) != 0) {
    perror("setns(net)");
    close(fd);
    return 1;
  }
  close(fd);

  if (prctl(PR_CAP_AMBIENT, PR_CAP_AMBIENT_CLEAR_ALL, 0, 0, 0) != 0) {
    perror("prctl(PR_CAP_AMBIENT_CLEAR_ALL)");
    return 1;
  }

  struct __user_cap_header_struct hdr = {_LINUX_CAPABILITY_VERSION_3, 0};
  struct __user_cap_data_struct data[2] = {0};
  if (syscall(SYS_capset, &hdr, data) != 0) {
    perror("capset");
    return 1;
  }

  execvp(argv[1], &argv[1]);
  perror("execvp");
  return 1;
}
