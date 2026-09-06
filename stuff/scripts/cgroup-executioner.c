#define _GNU_SOURCE
#include <dirent.h>
#include <errno.h>
#include <limits.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/epoll.h>
#include <sys/inotify.h>
#include <sys/signalfd.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <unistd.h>

#define HASH_SIZE 1024
#define MAX_EVENTS 64

typedef struct WatchNode {
  int wd;
  char *path;
  char *scope_dir;
  char *scope_name;
  int is_events_file;
  struct WatchNode *next;
} WatchNode;

static WatchNode *hash_table[HASH_SIZE];
static int inotify_fd = -1;

static unsigned int hash_wd(int wd) { return ((unsigned int)wd) % HASH_SIZE; }

static void add_node(int wd, const char *path, const char *scope_dir,
                     const char *scope_name, int is_events_file) {
  unsigned int h = hash_wd(wd);
  WatchNode *node = malloc(sizeof(WatchNode));
  if (!node)
    return;

  node->wd = wd;
  node->path = strdup(path);
  node->scope_dir = scope_dir ? strdup(scope_dir) : NULL;
  node->scope_name = scope_name ? strdup(scope_name) : NULL;
  node->is_events_file = is_events_file;
  node->next = hash_table[h];
  hash_table[h] = node;
}

static WatchNode *find_node(int wd) {
  unsigned int h = hash_wd(wd);
  WatchNode *cur = hash_table[h];
  while (cur) {
    if (cur->wd == wd)
      return cur;
    cur = cur->next;
  }
  return NULL;
}

static void remove_node(int wd) {
  unsigned int h = hash_wd(wd);
  WatchNode **curr = &hash_table[h];
  while (*curr) {
    if ((*curr)->wd == wd) {
      WatchNode *to_free = *curr;
      *curr = (*curr)->next;
      free(to_free->path);
      free(to_free->scope_dir);
      free(to_free->scope_name);
      free(to_free);
      return;
    }
    curr = &(*curr)->next;
  }
}

static void check_and_kill(int wd, const char *events_path,
                           const char *scope_dir, const char *scope_name) {
  (void)scope_dir;
  size_t len = strlen(scope_name);
  if (len < 6 || strcmp(scope_name + len - 6, ".scope") != 0)
    return;

  FILE *fp = fopen(events_path, "r");
  if (!fp)
    return;

  char line[256];
  int breached = 0;
  while (fgets(line, sizeof(line), fp)) {
    if (strncmp(line, "max ", 4) == 0) {
      long max_val = strtol(line + 4, NULL, 10);
      if (max_val > 0) {
        breached = 1;
        break;
      }
    }
  }
  fclose(fp);

  if (!breached)
    return;

  if (wd >= 0) {
    inotify_rm_watch(inotify_fd, wd);
  }

  fprintf(stderr,
          "CRITICAL: %s breached TasksMax! Enforcing full teardown via "
          "systemctl stop.\n",
          scope_name);

  pid_t pid = fork();
  if (pid == 0) {
    execlp("systemctl", "systemctl", "--user", "stop", "--no-block", scope_name,
           (char *)NULL);
    _exit(1);
  } else if (pid > 0) {
    waitpid(pid, NULL, 0);
  }
}

static void watch_path_recursive(const char *dir_path) {
  int wd = inotify_add_watch(inotify_fd, dir_path, IN_CREATE | IN_ONLYDIR);
  if (wd >= 0) {
    add_node(wd, dir_path, NULL, NULL, 0);
  }

  char events_file[PATH_MAX];
  snprintf(events_file, sizeof(events_file), "%s/pids.events", dir_path);

  if (access(events_file, R_OK) == 0) {
    const char *scope_name = strrchr(dir_path, '/');
    scope_name = scope_name ? scope_name + 1 : dir_path;

    int fwd = inotify_add_watch(inotify_fd, events_file, IN_MODIFY);
    if (fwd >= 0) {
      add_node(fwd, events_file, dir_path, scope_name, 1);
    }
    check_and_kill(fwd, events_file, dir_path, scope_name);
  }

  DIR *dir = opendir(dir_path);
  if (!dir)
    return;

  struct dirent *entry;
  while ((entry = readdir(dir)) != NULL) {
    if (entry->d_type == DT_DIR) {
      if (strcmp(entry->d_name, ".") == 0 || strcmp(entry->d_name, "..") == 0)
        continue;
      char sub_path[PATH_MAX];
      snprintf(sub_path, sizeof(sub_path), "%s/%s", dir_path, entry->d_name);
      watch_path_recursive(sub_path);
    }
  }
  closedir(dir);
}

int main(int argc, char *argv[]) {
  sigset_t mask;
  sigemptyset(&mask);
  sigaddset(&mask, SIGTERM);
  sigaddset(&mask, SIGINT);
  if (sigprocmask(SIG_BLOCK, &mask, NULL) < 0) {
    perror("sigprocmask");
    return 1;
  }

  int sfd = signalfd(-1, &mask, SFD_NONBLOCK | SFD_CLOEXEC);
  if (sfd < 0) {
    perror("signalfd");
    return 1;
  }

  char cgroup_root[PATH_MAX];
  if (argc > 1) {
    strncpy(cgroup_root, argv[1], PATH_MAX - 1);
    cgroup_root[PATH_MAX - 1] = '\0';
  } else {
    snprintf(cgroup_root, sizeof(cgroup_root),
             "/sys/fs/cgroup/user.slice/user-%u.slice/user@%u.service",
             getuid(), getuid());
  }

  fprintf(stderr, "Cgroup Executioner active (Inotify + signalfd). Root: %s\n",
          cgroup_root);

  inotify_fd = inotify_init1(IN_CLOEXEC | IN_NONBLOCK);
  if (inotify_fd < 0) {
    perror("inotify_init1");
    close(sfd);
    return 1;
  }

  int epfd = epoll_create1(EPOLL_CLOEXEC);
  if (epfd < 0) {
    perror("epoll_create1");
    close(inotify_fd);
    close(sfd);
    return 1;
  }

  struct epoll_event ev_sig = {.events = EPOLLIN, .data.fd = sfd};
  epoll_ctl(epfd, EPOLL_CTL_ADD, sfd, &ev_sig);

  struct epoll_event ev_ino = {.events = EPOLLIN, .data.fd = inotify_fd};
  epoll_ctl(epfd, EPOLL_CTL_ADD, inotify_fd, &ev_ino);

  watch_path_recursive(cgroup_root);

  struct epoll_event events[MAX_EVENTS];
  char buf[4096] __attribute__((aligned(__alignof__(struct inotify_event))));
  int running = 1;

  while (running) {
    int n = epoll_wait(epfd, events, MAX_EVENTS, -1);
    if (n < 0) {
      if (errno == EINTR)
        continue;
      break;
    }

    for (int i = 0; i < n; i++) {
      if (events[i].data.fd == sfd) {
        struct signalfd_siginfo fdsi;
        ssize_t s = read(sfd, &fdsi, sizeof(fdsi));
        if (s == sizeof(fdsi)) {
          running = 0;
          break;
        }
      } else if (events[i].data.fd == inotify_fd) {
        while (1) {
          ssize_t len = read(inotify_fd, buf, sizeof(buf));
          if (len <= 0)
            break;

          const struct inotify_event *event;
          for (char *ptr = buf; ptr < buf + len;
               ptr += sizeof(struct inotify_event) + event->len) {
            event = (const struct inotify_event *)ptr;

            if (event->mask & IN_IGNORED) {
              remove_node(event->wd);
              continue;
            }

            WatchNode *node = find_node(event->wd);
            if (!node)
              continue;

            if (node->is_events_file && (event->mask & IN_MODIFY)) {
              check_and_kill(node->wd, node->path, node->scope_dir,
                             node->scope_name);
            } else if (!node->is_events_file && (event->mask & IN_CREATE)) {
              if (event->len > 0) {
                char new_path[PATH_MAX];
                snprintf(new_path, sizeof(new_path), "%s/%s", node->path,
                         event->name);

                struct stat st;
                if (stat(new_path, &st) == 0 && S_ISDIR(st.st_mode)) {
                  watch_path_recursive(new_path);
                }
              }
            }
          }
        }
      }
    }
  }

  close(epfd);
  close(inotify_fd);
  close(sfd);
  return 0;
}
