#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <fcntl.h>
#include <errno.h>
#include <string.h>
#include <limits.h>

int main() {
    char pipe_path[PATH_MAX];
    const char *xdg_runtime_dir = getenv("XDG_RUNTIME_DIR");

    if (xdg_runtime_dir) {
        snprintf(pipe_path, PATH_MAX, "%s/nautilus_select_pipe", xdg_runtime_dir);
    } else {
        snprintf(pipe_path, PATH_MAX, "/tmp/nautilus_select_pipe_%d", getuid());
    }

    if (mkfifo(pipe_path, 0666) == -1) {
        if (errno != EEXIST) {
            perror("mkfifo");
            exit(EXIT_FAILURE);
        }
    }

    while (1) {
        int fd = open(pipe_path, O_RDONLY);
        if (fd == -1) {
            perror("open");
            sleep(5);
            continue;
        }

        char buffer[PATH_MAX];
        ssize_t num_read = read(fd, buffer, PATH_MAX - 1);
        close(fd);

        if (num_read > 0) {
            buffer[num_read] = '\0';
            if (buffer[num_read - 1] == '\n') {
                buffer[num_read - 1] = '\0';
            }

            usleep(100000);

            pid_t pid = fork();
            if (pid == -1) {
                perror("fork");
            } else if (pid == 0) {
                char *args[] = {"nautilus", "--select", buffer, NULL};
                execvp("nautilus", args);
                perror("execvp");
                exit(EXIT_FAILURE);
            }
        }
    }

    return 0;
}
