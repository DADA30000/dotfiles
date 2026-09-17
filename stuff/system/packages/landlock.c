#include <linux/landlock.h>
#include <stdio.h>
#include <sys/prctl.h>
#include <sys/syscall.h>
#include <unistd.h>

int main(int argc, char *argv[]) {
  if (argc < 2) {
    fprintf(stderr, "Usage: %s <command> [args...]\n", argv[0]);
    return 1;
  }

  struct landlock_ruleset_attr attr = {
      .scoped = LANDLOCK_SCOPE_SIGNAL,
  };

  int fd = syscall(__NR_landlock_create_ruleset, &attr, sizeof(attr), 0);
  if (fd < 0) {
    perror("landlock_create_ruleset");
    return 1;
  }

  if (prctl(PR_SET_NO_NEW_PRIVS, 1, 0, 0, 0)) {
    perror("prctl");
    return 1;
  }

  if (syscall(__NR_landlock_restrict_self, fd, 0)) {
    perror("landlock_restrict_self");
    return 1;
  }
  close(fd);

  execvp(argv[1], &argv[1]);
  return 0;
}
