#include <stdio.h>
#include <string.h>
#include <unistd.h>

#define FAN_MODE_PATH "/sys/devices/platform/aorus_laptop/fan_mode"

int main(int argc, char *argv[]) {
  if (argc != 2) {
    fprintf(stderr, "Usage: %s [auto|max]\n", argv[0]);
    return 1;
  }

  // Elevate privileges to root explicitly
  if (setuid(0) != 0) {
    perror("Failed to acquire root privileges");
    return 1;
  }

  FILE *f = fopen(FAN_MODE_PATH, "w");
  if (!f) {
    perror("Failed to open fan_mode interface");
    return 1;
  }

  if (strcmp(argv[1], "auto") == 0) {
    fprintf(f, "0\n");
  } else if (strcmp(argv[1], "max") == 0) {
    fprintf(f, "5\n");
  } else {
    fprintf(stderr, "Invalid argument. Use 'auto' or 'max'.\n");
    fclose(f);
    return 1;
  }

  fclose(f);
  return 0;
}
