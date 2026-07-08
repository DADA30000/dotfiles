#include <dirent.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

void isolate_nodes() {
  DIR *dir = opendir("/dev");
  if (!dir) {
    perror("Failed to open /dev");
    return;
  }

  struct dirent *entry;
  while ((entry = readdir(dir)) != NULL) {
    if (strncmp(entry->d_name, "nvidia", 6) == 0) {
      size_t len = strlen(entry->d_name);

      // Skip if it already ends in .bak
      if (len > 4 && strcmp(entry->d_name + len - 4, ".bak") == 0) {
        continue;
      }

      char oldpath[512];
      char newpath[512];
      snprintf(oldpath, sizeof(oldpath), "/dev/%s", entry->d_name);
      snprintf(newpath, sizeof(newpath), "/dev/%s.bak", entry->d_name);

      if (rename(oldpath, newpath) != 0) {
        perror("Failed to rename device node");
      }
    }
  }
  closedir(dir);
}

void restore_nodes() {
  DIR *dir = opendir("/dev");
  if (!dir) {
    perror("Failed to open /dev");
    return;
  }

  struct dirent *entry;
  while ((entry = readdir(dir)) != NULL) {
    if (strncmp(entry->d_name, "nvidia", 6) == 0) {
      size_t len = strlen(entry->d_name);

      // Only process if it ends in .bak
      if (len > 4 && strcmp(entry->d_name + len - 4, ".bak") == 0) {
        char oldpath[512];
        char newpath[512];
        char base_name[256];

        snprintf(oldpath, sizeof(oldpath), "/dev/%s", entry->d_name);
        // Strip the ".bak" extension (len - 4 characters)
        snprintf(base_name, len - 3, "%s", entry->d_name);
        snprintf(newpath, sizeof(newpath), "/dev/%s", base_name);

        if (rename(oldpath, newpath) != 0) {
          perror("Failed to restore device node");
        }
      }
    }
  }
  closedir(dir);
}

int main(int argc, char *argv[]) {
  // Prevent Null Pointer Dereference if an attacker passes an empty argv array
  if (argc != 2 || argv[0] == NULL || argv[1] == NULL) {
    fprintf(stderr, "Usage: nv-blindfold [block|unblock]\n");
    return 1;
  }

  // Elevate privileges to root explicitly for the execution thread
  if (setuid(0) != 0) {
    perror("Failed to acquire root privileges");
    return 1;
  }

  if (strcmp(argv[1], "block") == 0) {
    isolate_nodes();
  } else if (strcmp(argv[1], "unblock") == 0) {
    restore_nodes();
  } else {
    fprintf(stderr, "Invalid argument. Use 'block' or 'unblock'.\n");
    return 1;
  }

  return 0;
}
