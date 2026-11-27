#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <gio/gio.h>
#include <gio/gunixfdlist.h>
#include <gio/gunixfdmessage.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <unistd.h>

#define PORTAL_BUS_NAME "org.freedesktop.portal.Flatpak"
#define PORTAL_OBJ_PATH "/org/freedesktop/portal/Flatpak"
#define PORTAL_IFACE "org.freedesktop.portal.Flatpak"
#define PORTAL_VERSION 6u
#define PORTAL_SUPPORTS_EXPOSE_PIDS 1u

#define FLATPAK_SPAWN_FLAGS_WATCH_BUS (1u << 4)

#define OP_SPAWN 1
#define OP_SIGNAL 2
#define OP_KILL 3

#define EVT_STARTED 1
#define EVT_EXITED 2

#define MAX_SCM_FDS 250

static const gchar introspection_xml[] =
  "<node>"
  "  <interface name='org.freedesktop.portal.Flatpak'>"
  "    <property name='version' type='u' access='read'/>"
  "    <property name='supports' type='u' access='read'/>"
  "    <method name='Spawn'>"
  "      <annotation name='org.gtk.GDBus.C.UnixFD' value='true'/>"
  "      <arg type='ay' name='cwd_path' direction='in'/>"
  "      <arg type='aay' name='argv' direction='in'/>"
  "      <arg type='a{uh}' name='fds' direction='in'/>"
  "      <arg type='a{ss}' name='envs' direction='in'/>"
  "      <arg type='u' name='flags' direction='in'/>"
  "      <arg type='a{sv}' name='options' direction='in'/>"
  "      <arg type='u' name='pid' direction='out'/>"
  "    </method>"
  "    <method name='SpawnSignal'>"
  "      <arg type='u' name='pid' direction='in'/>"
  "      <arg type='u' name='signal' direction='in'/>"
  "      <arg type='b' name='to_process_group' direction='in'/>"
  "    </method>"
  "    <signal name='SpawnStarted'>"
  "      <arg type='u' name='pid' direction='out'/>"
  "      <arg type='u' name='relpid' direction='out'/>"
  "    </signal>"
  "    <signal name='SpawnExited'>"
  "      <arg type='u' name='pid' direction='out'/>"
  "      <arg type='u' name='exit_status' direction='out'/>"
  "    </signal>"
  "  </interface>"
  "</node>";

typedef struct
{
  guint32 pid;
  gchar *sender;
  gchar *app_id;
  gboolean watch_bus;
  GSocket *sock;
  GSource *source;
  GByteArray *rx_buf;
} ChildWatch;

static GDBusConnection *session_bus = NULL;
static GDBusNodeInfo *introspection_data = NULL;
static GMainLoop *main_loop = NULL;
static GHashTable *children_by_pid = NULL;
static GHashTable *sender_cache = NULL;

typedef struct
{
  guint32 pid;
  gchar *app_id;
} SenderInfo;

static void
sender_info_free (gpointer p)
{
  SenderInfo *si = p;
  if (!si)
    return;
  g_free (si->app_id);
  g_free (si);
}

static void
child_watch_free (gpointer p)
{
  ChildWatch *cw = p;
  if (!cw)
    return;
  if (cw->source)
    {
      g_source_destroy (cw->source);
      g_source_unref (cw->source);
    }
  if (cw->sock)
    g_object_unref (cw->sock);
  if (cw->rx_buf)
    g_byte_array_unref (cw->rx_buf);
  g_free (cw->sender);
  g_free (cw->app_id);
  g_free (cw);
}

static void
buf_append_u8 (GByteArray *buf, guint8 v)
{
  g_byte_array_append (buf, &v, 1);
}

static void
buf_append_u32 (GByteArray *buf, guint32 v)
{
  guint8 le[4];
  le[0] = (guint8) (v & 0xffu);
  le[1] = (guint8) ((v >> 8) & 0xffu);
  le[2] = (guint8) ((v >> 16) & 0xffu);
  le[3] = (guint8) ((v >> 24) & 0xffu);
  g_byte_array_append (buf, le, 4);
}

static guint32
read_u32_le (const guint8 *p)
{
  return (guint32) p[0] | ((guint32) p[1] << 8) | ((guint32) p[2] << 16) |
         ((guint32) p[3] << 24);
}

static void
buf_append_str (GByteArray *buf, const gchar *s)
{
  size_t len = s ? strlen (s) : 0;
  buf_append_u32 (buf, (guint32) len);
  if (len > 0)
    g_byte_array_append (buf, (const guint8 *) s, (guint) len);
}

static void
buf_append_bytes_nul (GByteArray *buf, GVariant *v)
{
  gsize len = 0;
  const gchar *data = g_variant_get_fixed_array (v, &len, 1);
  gsize actual = 0;
  while (actual < len && data[actual] != '\0')
    actual++;
  buf_append_u32 (buf, (guint32) actual);
  if (actual > 0)
    g_byte_array_append (buf, (const guint8 *) data, (guint) actual);
}

static gboolean
valid_app_id (const gchar *id)
{
  if (!id || id[0] == '\0')
    return FALSE;
  if (strstr (id, "..") != NULL)
    return FALSE;
  for (const gchar *p = id; *p; p++)
    {
      if (*p == '/' || *p == '\\' || (guchar) *p < 0x20)
        return FALSE;
    }
  return TRUE;
}

static gchar *
read_sandbox_app_id (guint32 pid)
{
  g_autofree gchar *path = g_strdup_printf ("/proc/%u/root/.sb-sandbox", pid);
  g_autofree gchar *content = NULL;
  if (!g_file_get_contents (path, &content, NULL, NULL))
    return NULL;
  g_strstrip (content);
  if (!valid_app_id (content))
    return NULL;
  return g_steal_pointer (&content);
}

static const SenderInfo *
lookup_sender_info (GDBusConnection *conn, const gchar *sender, GError **error)
{
  const SenderInfo *cached = g_hash_table_lookup (sender_cache, sender);
  if (cached)
    return cached;

  g_autoptr (GVariant) reply = g_dbus_connection_call_sync (
      conn, "org.freedesktop.DBus", "/org/freedesktop/DBus", "org.freedesktop.DBus",
      "GetConnectionCredentials", g_variant_new ("(s)", sender),
      G_VARIANT_TYPE ("(a{sv})"), G_DBUS_CALL_FLAGS_NONE, 5000, NULL, error);
  if (!reply)
    return NULL;

  g_autoptr (GVariant) dict = g_variant_get_child_value (reply, 0);
  guint32 pid = 0;
  if (!g_variant_lookup (dict, "ProcessID", "u", &pid) || pid == 0)
    {
      g_set_error (error, G_DBUS_ERROR, G_DBUS_ERROR_ACCESS_DENIED,
                   "Unable to determine caller ProcessID");
      return NULL;
    }

  g_autofree gchar *app_id = read_sandbox_app_id (pid);
  if (!app_id)
    {
      g_set_error (error, G_DBUS_ERROR, G_DBUS_ERROR_ACCESS_DENIED,
                   "Caller is not inside an sb-run sandbox");
      return NULL;
    }

  SenderInfo *si = g_new0 (SenderInfo, 1);
  si->pid = pid;
  si->app_id = g_steal_pointer (&app_id);
  g_hash_table_replace (sender_cache, g_strdup (sender), si);
  return si;
}

static gchar *
resolve_portal_socket_path (const gchar *app_id)
{
  const gchar *rt = g_get_user_runtime_dir ();
  gchar *p1 = g_build_filename (rt, ".nixpak", app_id, "runtime", "flatpak-portal.sock", NULL);
  if (g_file_test (p1, G_FILE_TEST_EXISTS))
    return p1;
  g_free (p1);

  gchar *p2 = g_build_filename (rt, "sb-run", app_id, "flatpak-portal.sock", NULL);
  if (g_file_test (p2, G_FILE_TEST_EXISTS))
    return p2;
  g_free (p2);
  return NULL;
}

static GSocket *
connect_portal_socket (const gchar *app_id, GError **error)
{
  g_autofree gchar *sock_path = resolve_portal_socket_path (app_id);
  if (!sock_path)
    {
      g_set_error (error, G_DBUS_ERROR, G_DBUS_ERROR_ACCESS_DENIED,
                   "flatpak_portal is not enabled for sandbox '%s'", app_id);
      return NULL;
    }

  g_autoptr (GSocketAddress) addr = g_unix_socket_address_new (sock_path);
  g_autoptr (GSocket) sock =
      g_socket_new (G_SOCKET_FAMILY_UNIX, G_SOCKET_TYPE_STREAM, 0, error);
  if (!sock)
    return NULL;

  if (!g_socket_connect (sock, addr, NULL, error))
    return NULL;

  return g_steal_pointer (&sock);
}

static gboolean
send_all_with_fds (GSocket *sock, const guint8 *data, gsize len, const gint *fds, gsize nfds,
                   GError **error)
{
  gsize off = 0;
  gboolean fds_sent = (nfds == 0);

  while (off < len || !fds_sent)
    {
      g_autoptr (GSocketControlMessage) cmsg = NULL;
      GSocketControlMessage **cmsgs = NULL;
      gint n_cmsgs = 0;

      if (!fds_sent)
        {
          g_autoptr (GUnixFDList) list = g_unix_fd_list_new ();
          for (gsize i = 0; i < nfds; i++)
            {
              if (g_unix_fd_list_append (list, fds[i], error) < 0)
                return FALSE;
            }
          cmsg = g_unix_fd_message_new_with_fd_list (list);
          cmsgs = &cmsg;
          n_cmsgs = 1;
        }

      GOutputVector vec = { data + off, len - off };
      gssize sent = g_socket_send_message (sock, NULL, &vec, 1, cmsgs, n_cmsgs, 0, NULL, error);
      if (sent < 0)
        return FALSE;
      if (sent == 0)
        {
          g_set_error (error, G_IO_ERROR, G_IO_ERROR_CLOSED, "Portal socket closed during send");
          return FALSE;
        }
      fds_sent = TRUE;
      off += (gsize) sent;
    }

  return TRUE;
}

static gboolean
send_framed_with_fds (GSocket *sock, GByteArray *payload, const gint *fds, gsize nfds,
                      GError **error)
{
  guint32 body_len = (guint32) (payload->len - 4);
  payload->data[0] = (guint8) (body_len & 0xffu);
  payload->data[1] = (guint8) ((body_len >> 8) & 0xffu);
  payload->data[2] = (guint8) ((body_len >> 16) & 0xffu);
  payload->data[3] = (guint8) ((body_len >> 24) & 0xffu);
  return send_all_with_fds (sock, payload->data, payload->len, fds, nfds, error);
}

static gboolean
recv_exact (GSocket *sock, guint8 *buf, gsize len, GError **error)
{
  gsize off = 0;
  while (off < len)
    {
      gssize r = g_socket_receive (sock, (gchar *) buf + off, len - off, NULL, error);
      if (r < 0)
        return FALSE;
      if (r == 0)
        {
          g_set_error (error, G_IO_ERROR, G_IO_ERROR_CLOSED, "Portal socket closed during recv");
          return FALSE;
        }
      off += (gsize) r;
    }
  return TRUE;
}

static gboolean
on_child_socket_event (GSocket *sock, GIOCondition cond, gpointer user_data)
{
  ChildWatch *cw = user_data;
  guint8 tmp[512];

  if (cond & G_IO_IN)
    {
      for (;;)
        {
          g_autoptr (GError) err = NULL;
          gssize r = g_socket_receive (sock, (gchar *) tmp, sizeof (tmp), NULL, &err);
          if (r > 0)
            {
              g_byte_array_append (cw->rx_buf, tmp, (guint) r);
              continue;
            }
          if (r < 0 && g_error_matches (err, G_IO_ERROR, G_IO_ERROR_WOULD_BLOCK))
            break;
          cond |= G_IO_HUP;
          break;
        }
    }

  while (cw->rx_buf->len >= 9)
    {
      guint8 evt = cw->rx_buf->data[0];
      guint32 pid = read_u32_le (cw->rx_buf->data + 1);
      guint32 val = read_u32_le (cw->rx_buf->data + 5);
      g_byte_array_remove_range (cw->rx_buf, 0, 9);

      if (evt == EVT_STARTED)
        {
          g_dbus_connection_emit_signal (session_bus, cw->sender, PORTAL_OBJ_PATH, PORTAL_IFACE,
                                         "SpawnStarted", g_variant_new ("(uu)", pid, val), NULL);
        }
      else if (evt == EVT_EXITED)
        {
          g_dbus_connection_emit_signal (session_bus, cw->sender, PORTAL_OBJ_PATH, PORTAL_IFACE,
                                         "SpawnExited", g_variant_new ("(uu)", pid, val), NULL);
          g_hash_table_remove (children_by_pid, GUINT_TO_POINTER (cw->pid));
          return G_SOURCE_REMOVE;
        }
    }

  if (cond & (G_IO_HUP | G_IO_ERR))
    {
      g_hash_table_remove (children_by_pid, GUINT_TO_POINTER (cw->pid));
      return G_SOURCE_REMOVE;
    }

  return G_SOURCE_CONTINUE;
}

static gboolean
append_fd_handle (gint32 handle, const gint *in_fds, gint in_fds_len, GArray *out_fds,
                  GError **error)
{
  if (!in_fds || handle < 0 || handle >= in_fds_len)
    {
      g_set_error (error, G_DBUS_ERROR, G_DBUS_ERROR_INVALID_ARGS,
                   "Invalid file descriptor handle %d", handle);
      return FALSE;
    }
  if (out_fds->len >= MAX_SCM_FDS)
    {
      g_set_error (error, G_DBUS_ERROR, G_DBUS_ERROR_LIMITS_EXCEEDED, "Too many file descriptors");
      return FALSE;
    }
  gint fd = in_fds[handle];
  g_array_append_val (out_fds, fd);
  return TRUE;
}

static void
append_str_array_opt (GByteArray *payload, GVariant *options, const gchar *key)
{
  g_auto (GStrv) arr = NULL;
  guint32 count = 0;
  if (g_variant_lookup (options, key, "^as", &arr) && arr)
    count = g_strv_length (arr);
  buf_append_u32 (payload, count);
  for (guint32 i = 0; i < count; i++)
    buf_append_str (payload, arr[i]);
}

static gboolean
append_fd_array_opt (GVariant *options, const gchar *key, const gint *in_fds, gint in_fds_len,
                     GArray *out_fds, guint32 *out_count, GError **error)
{
  g_autoptr (GVariant) arr = g_variant_lookup_value (options, key, G_VARIANT_TYPE ("ah"));
  *out_count = 0;
  if (!arr)
    return TRUE;
  gsize n = g_variant_n_children (arr);
  for (gsize i = 0; i < n; i++)
    {
      gint32 handle = -1;
      g_variant_get_child (arr, i, "h", &handle);
      if (!append_fd_handle (handle, in_fds, in_fds_len, out_fds, error))
        return FALSE;
    }
  *out_count = (guint32) n;
  return TRUE;
}

static void
handle_spawn (GDBusMethodInvocation *invocation, GVariant *parameters, const SenderInfo *si)
{
  g_autoptr (GError) error = NULL;
  GDBusMessage *msg = g_dbus_method_invocation_get_message (invocation);
  GUnixFDList *fd_list = g_dbus_message_get_unix_fd_list (msg);
  gint in_fds_len = 0;
  const gint *in_fds = fd_list ? g_unix_fd_list_peek_fds (fd_list, &in_fds_len) : NULL;

  g_autoptr (GVariant) cwd_v = g_variant_get_child_value (parameters, 0);
  g_autoptr (GVariant) argv_v = g_variant_get_child_value (parameters, 1);
  g_autoptr (GVariant) fds_v = g_variant_get_child_value (parameters, 2);
  g_autoptr (GVariant) envs_v = g_variant_get_child_value (parameters, 3);
  guint32 flags = 0;
  g_variant_get_child (parameters, 4, "u", &flags);
  g_autoptr (GVariant) options = g_variant_get_child_value (parameters, 5);

  gsize argc = g_variant_n_children (argv_v);
  if (argc == 0)
    {
      g_dbus_method_invocation_return_error (invocation, G_DBUS_ERROR, G_DBUS_ERROR_INVALID_ARGS,
                                             "Empty argv");
      return;
    }

  g_autoptr (GByteArray) payload = g_byte_array_new ();
  g_autoptr (GArray) send_fds = g_array_new (FALSE, FALSE, sizeof (gint));

  buf_append_u32 (payload, 0);
  buf_append_u8 (payload, OP_SPAWN);
  buf_append_u32 (payload, si->pid);
  buf_append_u32 (payload, flags);

  guint32 sandbox_flags = 0;
  g_variant_lookup (options, "sandbox-flags", "u", &sandbox_flags);
  buf_append_u32 (payload, sandbox_flags);

  buf_append_bytes_nul (payload, cwd_v);

  buf_append_u32 (payload, (guint32) argc);
  for (gsize i = 0; i < argc; i++)
    {
      g_autoptr (GVariant) arg_v = g_variant_get_child_value (argv_v, i);
      buf_append_bytes_nul (payload, arg_v);
    }

  gsize n_envs = g_variant_n_children (envs_v);
  buf_append_u32 (payload, (guint32) n_envs);
  for (gsize i = 0; i < n_envs; i++)
    {
      const gchar *k = NULL;
      const gchar *v = NULL;
      g_variant_get_child (envs_v, i, "{&s&s}", &k, &v);
      g_autofree gchar *kv = g_strdup_printf ("%s=%s", k, v);
      buf_append_str (payload, kv);
    }

  append_str_array_opt (payload, options, "unset-env");
  append_str_array_opt (payload, options, "sandbox-expose");
  append_str_array_opt (payload, options, "sandbox-expose-ro");

  gsize n_fds = g_variant_n_children (fds_v);
  buf_append_u32 (payload, (guint32) n_fds);
  for (gsize i = 0; i < n_fds; i++)
    {
      guint32 dest_fd = 0;
      gint32 handle = -1;
      g_variant_get_child (fds_v, i, "{uh}", &dest_fd, &handle);
      if (!append_fd_handle (handle, in_fds, in_fds_len, send_fds, &error))
        {
          g_dbus_method_invocation_return_gerror (invocation, error);
          return;
        }
      buf_append_u32 (payload, dest_fd);
    }

  guint32 expose_rw_count = 0;
  guint32 expose_ro_count = 0;
  if (!append_fd_array_opt (options, "sandbox-expose-fd", in_fds, in_fds_len, send_fds,
                            &expose_rw_count, &error) ||
      !append_fd_array_opt (options, "sandbox-expose-fd-ro", in_fds, in_fds_len, send_fds,
                            &expose_ro_count, &error))
    {
      g_dbus_method_invocation_return_gerror (invocation, error);
      return;
    }
  buf_append_u32 (payload, expose_rw_count);
  buf_append_u32 (payload, expose_ro_count);

  g_autoptr (GVariant) usr_fd_v = g_variant_lookup_value (options, "usr-fd", G_VARIANT_TYPE_HANDLE);
  g_autoptr (GVariant) app_fd_v = g_variant_lookup_value (options, "app-fd", G_VARIANT_TYPE_HANDLE);
  guint8 has_usr = usr_fd_v ? 1 : 0;
  guint8 has_app = app_fd_v ? 1 : 0;
  buf_append_u8 (payload, has_usr);
  buf_append_u8 (payload, has_app);
  if (has_usr &&
      !append_fd_handle (g_variant_get_handle (usr_fd_v), in_fds, in_fds_len, send_fds, &error))
    {
      g_dbus_method_invocation_return_gerror (invocation, error);
      return;
    }
  if (has_app &&
      !append_fd_handle (g_variant_get_handle (app_fd_v), in_fds, in_fds_len, send_fds, &error))
    {
      g_dbus_method_invocation_return_gerror (invocation, error);
      return;
    }

  g_autoptr (GSocket) sock = connect_portal_socket (si->app_id, &error);
  if (!sock)
    {
      g_dbus_method_invocation_return_gerror (invocation, error);
      return;
    }

  if (!send_framed_with_fds (sock, payload, (const gint *) send_fds->data, send_fds->len, &error))
    {
      g_dbus_method_invocation_return_gerror (invocation, error);
      return;
    }

  guint8 hdr[5];
  if (!recv_exact (sock, hdr, sizeof (hdr), &error))
    {
      g_dbus_method_invocation_return_gerror (invocation, error);
      return;
    }

  guint32 val = read_u32_le (hdr + 1);
  if (hdr[0] == 0)
    {
      gsize err_len = val > 4096 ? 4096 : val;
      g_autofree gchar *err_msg = g_malloc0 (err_len + 1);
      if (err_len > 0)
        (void) recv_exact (sock, (guint8 *) err_msg, err_len, NULL);
      g_dbus_method_invocation_return_error (invocation, G_DBUS_ERROR, G_DBUS_ERROR_FAILED,
                                             "%s", *err_msg ? err_msg : "Spawn failed");
      return;
    }

  g_socket_set_blocking (sock, FALSE);
  ChildWatch *cw = g_new0 (ChildWatch, 1);
  cw->pid = val;
  cw->sender = g_strdup (g_dbus_method_invocation_get_sender (invocation));
  cw->app_id = g_strdup (si->app_id);
  cw->watch_bus = (flags & FLATPAK_SPAWN_FLAGS_WATCH_BUS) != 0;
  cw->sock = g_steal_pointer (&sock);
  cw->rx_buf = g_byte_array_new ();
  cw->source = g_socket_create_source (cw->sock, G_IO_IN | G_IO_HUP | G_IO_ERR, NULL);
  g_source_set_callback (cw->source, G_SOURCE_FUNC (on_child_socket_event), cw, NULL);
  g_source_attach (cw->source, NULL);

  g_hash_table_replace (children_by_pid, GUINT_TO_POINTER (cw->pid), cw);
  g_dbus_method_invocation_return_value (invocation, g_variant_new ("(u)", val));
}

static void
handle_spawn_signal (GDBusMethodInvocation *invocation, GVariant *parameters)
{
  guint32 pid = 0;
  guint32 sig = 0;
  gboolean to_pg = FALSE;
  g_variant_get (parameters, "(uub)", &pid, &sig, &to_pg);

  const gchar *sender = g_dbus_method_invocation_get_sender (invocation);
  ChildWatch *cw = g_hash_table_lookup (children_by_pid, GUINT_TO_POINTER (pid));
  if (!cw || g_strcmp0 (cw->sender, sender) != 0)
    {
      g_dbus_method_invocation_return_error (invocation, G_DBUS_ERROR,
                                             G_DBUS_ERROR_UNIX_PROCESS_ID_UNKNOWN, "No such pid");
      return;
    }

  g_autoptr (GError) error = NULL;
  g_autoptr (GSocket) sock = connect_portal_socket (cw->app_id, &error);
  if (!sock)
    {
      g_dbus_method_invocation_return_gerror (invocation, error);
      return;
    }

  g_autoptr (GByteArray) payload = g_byte_array_new ();
  buf_append_u32 (payload, 0);
  buf_append_u8 (payload, OP_SIGNAL);
  buf_append_u32 (payload, pid);
  buf_append_u32 (payload, sig);
  buf_append_u8 (payload, to_pg ? 1 : 0);

  if (!send_framed_with_fds (sock, payload, NULL, 0, &error))
    {
      g_dbus_method_invocation_return_gerror (invocation, error);
      return;
    }

  guint8 ack[4];
  if (!recv_exact (sock, ack, sizeof (ack), &error))
    {
      g_dbus_method_invocation_return_gerror (invocation, error);
      return;
    }
  if (read_u32_le (ack) != 0)
    {
      g_dbus_method_invocation_return_error (invocation, G_DBUS_ERROR,
                                             G_DBUS_ERROR_UNIX_PROCESS_ID_UNKNOWN, "No such pid");
      return;
    }
  g_dbus_method_invocation_return_value (invocation, NULL);
}

static void
handle_method_call (GDBusConnection *connection, const gchar *sender,
                    const gchar *object_path G_GNUC_UNUSED,
                    const gchar *interface_name G_GNUC_UNUSED, const gchar *method_name,
                    GVariant *parameters, GDBusMethodInvocation *invocation,
                    gpointer user_data G_GNUC_UNUSED)
{
  g_autoptr (GError) error = NULL;
  const SenderInfo *si = lookup_sender_info (connection, sender, &error);
  if (!si)
    {
      g_dbus_method_invocation_return_gerror (invocation, error);
      return;
    }

  if (g_strcmp0 (method_name, "Spawn") == 0)
    handle_spawn (invocation, parameters, si);
  else if (g_strcmp0 (method_name, "SpawnSignal") == 0)
    handle_spawn_signal (invocation, parameters);
}

static GVariant *
handle_get_property (GDBusConnection *connection G_GNUC_UNUSED,
                     const gchar *sender G_GNUC_UNUSED,
                     const gchar *object_path G_GNUC_UNUSED,
                     const gchar *interface_name G_GNUC_UNUSED, const gchar *property_name,
                     GError **error, gpointer user_data G_GNUC_UNUSED)
{
  if (g_strcmp0 (property_name, "version") == 0)
    return g_variant_new_uint32 (PORTAL_VERSION);
  if (g_strcmp0 (property_name, "supports") == 0)
    return g_variant_new_uint32 (PORTAL_SUPPORTS_EXPOSE_PIDS);
  g_set_error (error, G_DBUS_ERROR, G_DBUS_ERROR_UNKNOWN_PROPERTY, "Unknown property %s",
               property_name);
  return NULL;
}

static GDBusMessage *
dbus_incoming_filter (GDBusConnection *connection G_GNUC_UNUSED, GDBusMessage *message,
                      gboolean incoming, gpointer user_data G_GNUC_UNUSED)
{
  if (!incoming || g_dbus_message_get_message_type (message) != G_DBUS_MESSAGE_TYPE_METHOD_CALL)
    return message;

  if (g_strcmp0 (g_dbus_message_get_interface (message), PORTAL_IFACE) == 0 &&
      g_strcmp0 (g_dbus_message_get_member (message), "SpawnSignal") == 0 &&
      g_strcmp0 (g_dbus_message_get_signature (message), "uu") == 0)
    {
      GVariant *body = g_dbus_message_get_body (message);
      guint32 pid = 0;
      guint32 sig = 0;
      g_variant_get (body, "(uu)", &pid, &sig);
      GDBusMessage *copy = g_dbus_message_copy (message, NULL);
      if (copy)
        {
          g_dbus_message_set_body (copy, g_variant_new ("(uub)", pid, sig, FALSE));
          g_object_unref (message);
          return copy;
        }
    }
  return message;
}

static void
on_name_owner_changed (GDBusConnection *connection G_GNUC_UNUSED,
                       const gchar *sender_name G_GNUC_UNUSED,
                       const gchar *object_path G_GNUC_UNUSED,
                       const gchar *interface_name G_GNUC_UNUSED,
                       const gchar *signal_name G_GNUC_UNUSED, GVariant *parameters,
                       gpointer user_data G_GNUC_UNUSED)
{
  const gchar *name = NULL;
  const gchar *old_owner = NULL;
  const gchar *new_owner = NULL;
  g_variant_get (parameters, "(&s&s&s)", &name, &old_owner, &new_owner);
  if (!name || name[0] != ':' || g_strcmp0 (name, old_owner) != 0 || new_owner[0] != '\0')
    return;

  g_hash_table_remove (sender_cache, name);

  GHashTableIter iter;
  gpointer k, v;
  g_autoptr (GArray) to_remove = g_array_new (FALSE, FALSE, sizeof (guint32));
  g_hash_table_iter_init (&iter, children_by_pid);
  while (g_hash_table_iter_next (&iter, &k, &v))
    {
      ChildWatch *cw = v;
      if (cw->watch_bus && g_strcmp0 (cw->sender, name) == 0)
        g_array_append_val (to_remove, cw->pid);
    }

  for (guint i = 0; i < to_remove->len; i++)
    {
      guint32 pid = g_array_index (to_remove, guint32, i);
      ChildWatch *cw = g_hash_table_lookup (children_by_pid, GUINT_TO_POINTER (pid));
      if (cw && cw->sock)
        {
          guint8 kill_op = OP_KILL;
          (void) g_socket_send (cw->sock, (const gchar *) &kill_op, 1, NULL, NULL);
        }
      g_hash_table_remove (children_by_pid, GUINT_TO_POINTER (pid));
    }
}

static const GDBusInterfaceVTable interface_vtable = {
  handle_method_call,
  handle_get_property,
  NULL,
  { 0 }
};

static void
on_bus_acquired (GDBusConnection *connection, const gchar *name G_GNUC_UNUSED,
                 gpointer user_data G_GNUC_UNUSED)
{
  session_bus = connection;
  g_dbus_connection_add_filter (connection, dbus_incoming_filter, NULL, NULL);
  g_dbus_connection_signal_subscribe (connection, "org.freedesktop.DBus", "org.freedesktop.DBus",
                                      "NameOwnerChanged", "/org/freedesktop/DBus", NULL,
                                      G_DBUS_SIGNAL_FLAGS_NONE, on_name_owner_changed, NULL, NULL);

  g_autoptr (GError) err = NULL;
  if (g_dbus_connection_register_object (connection, PORTAL_OBJ_PATH,
                                         introspection_data->interfaces[0], &interface_vtable,
                                         NULL, NULL, &err) == 0)
    {
      g_printerr ("[sb-flatpak-portal] Failed to register object: %s\n", err->message);
      g_main_loop_quit (main_loop);
    }
}

static void
on_name_lost (GDBusConnection *connection G_GNUC_UNUSED, const gchar *name G_GNUC_UNUSED,
              gpointer user_data G_GNUC_UNUSED)
{
  g_main_loop_quit (main_loop);
}

int
main (void)
{
  g_autoptr (GError) err = NULL;
  introspection_data = g_dbus_node_info_new_for_xml (introspection_xml, &err);
  if (!introspection_data)
    {
      g_printerr ("[sb-flatpak-portal] XML parse error: %s\n", err->message);
      return 1;
    }

  children_by_pid = g_hash_table_new_full (g_direct_hash, g_direct_equal, NULL, child_watch_free);
  sender_cache = g_hash_table_new_full (g_str_hash, g_str_equal, g_free, sender_info_free);
  main_loop = g_main_loop_new (NULL, FALSE);

  guint owner_id = g_bus_own_name (G_BUS_TYPE_SESSION, PORTAL_BUS_NAME,
                                   G_BUS_NAME_OWNER_FLAGS_NONE, on_bus_acquired, NULL,
                                   on_name_lost, NULL, NULL);

  g_main_loop_run (main_loop);

  g_bus_unown_name (owner_id);
  g_hash_table_destroy (children_by_pid);
  g_hash_table_destroy (sender_cache);
  g_main_loop_unref (main_loop);
  g_dbus_node_info_unref (introspection_data);
  return 0;
}
