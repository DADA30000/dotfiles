#define _GNU_SOURCE
#include <fcntl.h>
#include <sched.h>
#include <stdio.h>
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

  execvp(argv[1], &argv[1]);
  perror("execvp");
  return 1;
}
