#define _POSIX_C_SOURCE 200809L

#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <sys/wait.h>
#include <unistd.h>

static volatile sig_atomic_t g_stop = 0;

static void on_signal(int sig) {
    (void)sig;
    g_stop = 1;
}

static int notify_ready(void) {
    const char *sock_path = getenv("NOTIFY_SOCKET");
    if (!sock_path || sock_path[0] == '\0') {
        return 0;
    }

    struct sockaddr_un addr;
    memset(&addr, 0, sizeof(addr));
    addr.sun_family = AF_UNIX;

    size_t path_len = strlen(sock_path);
    if (path_len >= sizeof(addr.sun_path)) {
        fprintf(stderr, "dbus-proxy-launch: NOTIFY_SOCKET path too long\n");
        return -1;
    }

    socklen_t addr_len;
    if (sock_path[0] == '@') {
        addr.sun_path[0] = '\0';
        memcpy(addr.sun_path + 1, sock_path + 1, path_len - 1);
        addr_len = (socklen_t)(offsetof(struct sockaddr_un, sun_path) + path_len);
    } else {
        memcpy(addr.sun_path, sock_path, path_len + 1);
        addr_len = (socklen_t)(offsetof(struct sockaddr_un, sun_path) + path_len + 1);
    }

    int fd = socket(AF_UNIX, SOCK_DGRAM | SOCK_CLOEXEC, 0);
    if (fd < 0) {
        perror("dbus-proxy-launch: socket");
        return -1;
    }

    const char msg[] = "READY=1";
    ssize_t sent = sendto(fd, msg, sizeof(msg) - 1, 0, (struct sockaddr *)&addr, addr_len);
    int saved = errno;
    close(fd);
    if (sent < 0) {
        errno = saved;
        perror("dbus-proxy-launch: sendto(NOTIFY_SOCKET)");
        return -1;
    }
    return 0;
}

int main(int argc, char **argv) {
    if (argc < 2) {
        fprintf(stderr, "usage: %s <xdg-dbus-proxy-bin> [args...]\n", argv[0]);
        return 2;
    }

    int pfd[2];
    if (pipe(pfd) != 0) {
        perror("dbus-proxy-launch: pipe");
        return 1;
    }

    if (fcntl(pfd[0], F_SETFD, FD_CLOEXEC) != 0) {
        perror("dbus-proxy-launch: fcntl");
        return 1;
    }

    char fd_arg[32];
    snprintf(fd_arg, sizeof(fd_arg), "--fd=%d", pfd[1]);

    pid_t pid = fork();
    if (pid < 0) {
        perror("dbus-proxy-launch: fork");
        return 1;
    }

    if (pid == 0) {
        close(pfd[0]);
        char **child_argv = calloc((size_t)argc + 2, sizeof(char *));
        if (!child_argv) {
            _exit(127);
        }
        child_argv[0] = argv[1];
        child_argv[1] = fd_arg;
        for (int i = 2; i < argc; i++) {
            child_argv[i] = argv[i];
        }
        child_argv[argc] = NULL;
        execv(argv[1], child_argv);
        perror("dbus-proxy-launch: execv");
        _exit(127);
    }

    close(pfd[1]);

    struct sigaction sa;
    memset(&sa, 0, sizeof(sa));
    sa.sa_handler = on_signal;
    sigemptyset(&sa.sa_mask);
    sigaction(SIGTERM, &sa, NULL);
    sigaction(SIGINT, &sa, NULL);

    char byte = 0;
    ssize_t n;
    do {
        n = read(pfd[0], &byte, 1);
    } while (n < 0 && errno == EINTR && !g_stop);

    if (n != 1) {
        close(pfd[0]);
        int st = 0;
        waitpid(pid, &st, 0);
        if (WIFEXITED(st)) {
            return WEXITSTATUS(st) ? WEXITSTATUS(st) : 1;
        }
        return 1;
    }

    if (notify_ready() != 0) {
        close(pfd[0]);
        int st = 0;
        waitpid(pid, &st, 0);
        return 1;
    }

    int status = 0;
    for (;;) {
        pid_t w = waitpid(pid, &status, 0);
        if (w == pid) {
            break;
        }
        if (w < 0 && errno == EINTR) {
            if (g_stop && pfd[0] >= 0) {
                close(pfd[0]);
                pfd[0] = -1;
            }
            continue;
        }
        break;
    }

    if (pfd[0] >= 0) {
        close(pfd[0]);
    }

    if (WIFEXITED(status)) {
        return WEXITSTATUS(status);
    }
    if (WIFSIGNALED(status)) {
        return 128 + WTERMSIG(status);
    }
    return 1;
}
