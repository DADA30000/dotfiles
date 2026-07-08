#include <fcntl.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>

#define FAN_MODE_PATH "/sys/devices/platform/aorus_laptop/fan_mode"

int main(int argc, char *argv[]) {
  // Prevent Null Pointer Dereference if an attacker passes an empty argv array
  if (argc != 2 || argv[0] == NULL || argv[1] == NULL) {
    fprintf(stderr, "Usage: fan-control [quiet|auto|max]\n");
    return 1;
  }

  // Elevate privileges to root explicitly
  if (setuid(0) != 0) {
    perror("Failed to acquire root privileges");
    return 1;
  }

  // Use raw open() with O_NOFOLLOW to strictly prevent symlink attacks.
  // O_CLOEXEC prevents leaking the file descriptor to child processes.
  int fd = open(FAN_MODE_PATH, O_WRONLY | O_TRUNC | O_NOFOLLOW | O_CLOEXEC);
  if (fd < 0) {
    perror("Failed to open fan_mode interface");
    return 1;
  }

  const char *val = NULL;
  if (strcmp(argv[1], "quiet") == 0) {
    val = "3\n";
  } else if (strcmp(argv[1], "auto") == 0) {
    val = "0\n";
  } else if (strcmp(argv[1], "max") == 0) {
    val = "5\n";
  } else {
    fprintf(stderr, "Invalid argument. Use 'quiet', 'auto' or 'max'.\n");
    close(fd);
    return 1;
  }

  // Write directly using the file descriptor and verify the entire write
  // succeeded
  size_t len = strlen(val);
  if (write(fd, val, len) != (ssize_t)len) {
    perror("Failed to write to fan_mode");
    close(fd);
    return 1;
  }

  close(fd);
  return 0;
}
