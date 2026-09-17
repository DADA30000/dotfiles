#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/epoll.h>
#include <sys/syscall.h>
#include <unistd.h>

#define MAX_EVENTS 64

static int pidfd_open(pid_t pid, unsigned int flags) {
  return syscall(SYS_pidfd_open, pid, flags);
}

int main(int argc, char *argv[]) {
  if (argc < 3) {
    fprintf(stderr, "Usage: %s <cgroup.procs path> <runner pid>\n", argv[0]);
    return 1;
  }

  const char *procs_path = argv[1];
  pid_t runner_pid = (pid_t)atoi(argv[2]);

  int epfd = epoll_create1(EPOLL_CLOEXEC);
  if (epfd < 0)
    return 1;

  // Also monitor runner_pid so we exit if the runner crashes
  int runner_fd = pidfd_open(runner_pid, 0);
  if (runner_fd >= 0) {
    struct epoll_event ev = {.events = EPOLLIN, .data.fd = runner_fd};
    epoll_ctl(epfd, EPOLL_CTL_ADD, runner_fd, &ev);
  }

  while (1) {
    FILE *f = fopen(procs_path, "r");
    if (!f)
      break;

    int non_runner_count = 0;
    char line[64];

    while (fgets(line, sizeof(line), f)) {
      pid_t pid = (pid_t)atoi(line);
      if (pid <= 0 || pid == runner_pid)
        continue;

      non_runner_count++;
      int pfd = pidfd_open(pid, 0);
      if (pfd >= 0) {
        struct epoll_event ev = {.events = EPOLLIN | EPOLLONESHOT,
                                 .data.fd = pfd};
        if (epoll_ctl(epfd, EPOLL_CTL_ADD, pfd, &ev) < 0) {
          close(pfd); // Already added or exited
        }
      }
    }
    fclose(f);

    // If only runner (or 0 processes) is left, teardown
    if (non_runner_count == 0) {
      break;
    }

    struct epoll_event events[MAX_EVENTS];
    int n = epoll_wait(epfd, events, MAX_EVENTS, -1);
    if (n < 0 && errno != EINTR)
      break;

    for (int i = 0; i < n; i++) {
      if (events[i].data.fd == runner_fd) {
        // Runner died
        close(runner_fd);
        close(epfd);
        return 0;
      }
      close(events[i].data.fd);
    }
  }

  if (runner_fd >= 0)
    close(runner_fd);
  close(epfd);
  return 0;
}
