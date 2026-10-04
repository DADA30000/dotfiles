#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>

#ifndef PLUGIN_PATH
#define PLUGIN_PATH ""
#endif

int main() {
  const char *xdg_runtime = getenv("XDG_RUNTIME_DIR");
  const char *hypr_sig = getenv("HYPRLAND_INSTANCE_SIGNATURE");

  if (!xdg_runtime || !hypr_sig) {
    fprintf(stderr, "Missing Env Vars\n");
    return 1;
  }

  int sock = socket(AF_UNIX, SOCK_STREAM, 0);
  if (sock < 0)
    return 1;

  struct sockaddr_un addr;
  memset(&addr, 0, sizeof(addr));
  addr.sun_family = AF_UNIX;
  snprintf(addr.sun_path, sizeof(addr.sun_path), "%s/hypr/%s/.socket.sock",
           xdg_runtime, hypr_sig);

  if (connect(sock, (struct sockaddr *)&addr, sizeof(addr)) < 0) {
    close(sock);
    return 1;
  }

  char command[2048];
  snprintf(command, sizeof(command), "/plugin load %s", PLUGIN_PATH);

  if (write(sock, command, strlen(command)) < 0) {
    close(sock);
    return 1;
  }

  shutdown(sock, SHUT_WR);

  char buffer[4096];
  ssize_t bytes_read = read(sock, buffer, sizeof(buffer) - 1);
  close(sock);

  if (bytes_read > 0) {
    buffer[bytes_read] = '\0';
    if (strstr(buffer, "ok") != NULL) {
      return 0;
    } else {
      fprintf(stderr, "Failed: %s\n", buffer);
      return 1;
    }
  }
  return 1;
}
