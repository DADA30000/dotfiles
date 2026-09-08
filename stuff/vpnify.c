#define _GNU_SOURCE
#include <fcntl.h>
#include <sched.h>
#include <stdio.h>
#include <sys/mount.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <unistd.h>

extern char **environ;

int main(int argc, char **argv) {
  if (argc < 2) {
    fprintf(stderr, "usage: vpnify <cmd> [args...]\n");
    return 1;
  }

  char **saved_env = environ;

  int fd = open("/var/run/netns/vpn_wrapper", O_RDONLY);
  if (fd < 0) {
    perror("open netns");
    return 1;
  }

  if (setns(fd, CLONE_NEWNET) != 0) {
    perror("setns(net)");
    return 1;
  }

  if (unshare(CLONE_NEWNS) != 0) {
    perror("unshare mount ns");
    return 1;
  }

  if (mount(NULL, "/", NULL, MS_REC | MS_PRIVATE, NULL) != 0) {
    perror("mount private");
    return 1;
  }

  const char *ns_resolv = "/etc/netns/vpn_wrapper/resolv.conf";
  struct stat st;
  if (stat(ns_resolv, &st) == 0) {
    if (mount(ns_resolv, "/etc/resolv.conf", NULL, MS_BIND, NULL) != 0) {
      perror("bind resolv.conf");
      return 1;
    }
  }

  if (setuid(getuid()) != 0) {
    perror("setuid");
    return 1;
  }

  environ = saved_env;

  execvp(argv[1], &argv[1]);
  perror("execvp");
  return 1;
}
