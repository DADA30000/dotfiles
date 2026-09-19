#define _GNU_SOURCE
#include <fcntl.h>
#include <sched.h>
#include <stdio.h>
#include <sys/mount.h>
#include <sys/prctl.h>
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

  // 1. Open with O_CLOEXEC to prevent leaking descriptor to child processes
  int fd = open("/var/run/netns/vpn_wrapper", O_RDONLY | O_CLOEXEC);
  if (fd < 0) {
    perror("open netns");
    return 1;
  }

  // 2. Attach to the VPN network namespace
  if (setns(fd, CLONE_NEWNET) != 0) {
    perror("setns(net)");
    close(fd);
    return 1;
  }
  // 3. Immediately close the descriptor
  close(fd);

  // 4. Create an isolated mount namespace for DNS redirection
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

  // 5. Lock privileges: child process can NEVER gain capabilities or run SUID
  if (prctl(PR_SET_NO_NEW_PRIVS, 1, 0, 0, 0) != 0) {
    perror("prctl(PR_SET_NO_NEW_PRIVS)");
    return 1;
  }

  environ = saved_env;

  execvp(argv[1], &argv[1]);
  perror("execvp");
  return 1;
}
