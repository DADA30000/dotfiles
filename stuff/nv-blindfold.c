#include <dirent.h>   // for dirent, DIR, closedir, opendir, readdir
#include <stdio.h>    // for perror, NULL, fprintf, snprintf, stderr
#include <string.h>   // for strcmp, strncmp
#include <sys/stat.h> // for stat, S_ISDIR, chmod
#include <unistd.h>   // for setuid

void isolate_nodes() {
  DIR *dir = opendir("/dev");
  if (!dir) {
    perror("Failed to open /dev");
    return;
  }

  struct dirent *entry;
  while ((entry = readdir(dir)) != NULL) {
    if (strncmp(entry->d_name, "nvidia", 6) == 0) {
      char path[512];
      snprintf(path, sizeof(path), "/dev/%s", entry->d_name);

      struct stat st;
      if (stat(path, &st) == 0) {
        if (S_ISDIR(st.st_mode)) {
          continue;
        }

        if (chmod(path, 0000) != 0) {
          perror("Failed to set device permissions to 000");
        }
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
      char path[512];
      snprintf(path, sizeof(path), "/dev/%s", entry->d_name);

      struct stat st;
      if (stat(path, &st) == 0) {
        if (S_ISDIR(st.st_mode)) {
          continue;
        }

        if (chmod(path, 0666) != 0) {
          perror("Failed to set device permissions to 666");
        }
      }
    }
  }
  closedir(dir);
}

int main(int argc, char *argv[]) {
  if (argc != 2 || argv[0] == NULL || argv[1] == NULL) {
    fprintf(stderr, "Usage: nv-blindfold [block|unblock]\n");
    return 1;
  }

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
