#include <wp/wp.h>

WP_DEFINE_LOCAL_LOG_TOPIC ("m-mic-portal")

#define PORTAL_DEST  "org.freedesktop.impl.portal.desktop.gtk"
#define PORTAL_PATH  "/org/freedesktop/portal/desktop"
#define PORTAL_IFACE "org.freedesktop.impl.portal.Access"

enum
{
  ACTION_REQUEST_ACCESS,
  SIGNAL_RESPONSE,
  LAST_SIGNAL
};

static guint signals[LAST_SIGNAL] = { 0 };

struct _WpMicPortalPlugin
{
  WpPlugin parent;
  WpPlugin *dbus;
  guint next_id;
};

G_DECLARE_FINAL_TYPE (WpMicPortalPlugin, wp_mic_portal_plugin,
    WP, MIC_PORTAL_PLUGIN, WpPlugin)
G_DEFINE_TYPE (WpMicPortalPlugin, wp_mic_portal_plugin, WP_TYPE_PLUGIN)

typedef struct
{
  WpMicPortalPlugin *self;
  guint req_id;
} RequestData;

static void
on_access_dialog_done (GObject *source, GAsyncResult *res, gpointer user_data)
{
  RequestData *rd = user_data;
  g_autoptr (GError) error = NULL;
  g_autoptr (GVariant) reply = NULL;
  gboolean granted = FALSE;

  reply = g_dbus_connection_call_finish (G_DBUS_CONNECTION (source), res, &error);
  if (error) {
    wp_warning_object (rd->self, "AccessDialog failed: %s", error->message);
  } else if (reply) {
    guint32 response = 1;
    g_autoptr (GVariant) results = NULL;
    g_variant_get (reply, "(u@a{sv})", &response, &results);
    granted = (response == 0);
  }

  g_signal_emit (rd->self, signals[SIGNAL_RESPONSE], 0, rd->req_id, granted);
  g_object_unref (rd->self);
  g_free (rd);
}

static guint
wp_mic_portal_plugin_request_access (WpMicPortalPlugin *self,
    const gchar *app_id, const gchar *app_name)
{
  g_autoptr (GDBusConnection) conn = NULL;
  g_autofree gchar *handle_path = NULL;
  g_autofree gchar *title = NULL;
  g_autofree gchar *subtitle = NULL;
  const gchar *display = (app_name && *app_name) ? app_name
      : ((app_id && *app_id) ? app_id : "An application");
  GVariantBuilder opts;
  RequestData *rd;
  guint req_id;

  if (!self->dbus)
    return 0;

  g_object_get (self->dbus, "connection", &conn, NULL);
  if (!conn) {
    wp_warning_object (self, "D-Bus session connection not ready");
    return 0;
  }

  req_id = ++self->next_id;
  handle_path = g_strdup_printf (
      "/org/freedesktop/portal/desktop/request/wp_mic/r%u", req_id);
  title = g_strdup_printf ("Allow %s to Use the Microphone?", display);
  subtitle = g_strdup_printf ("%s wants to access the microphone.", display);

  g_variant_builder_init (&opts, G_VARIANT_TYPE ("a{sv}"));
  g_variant_builder_add (&opts, "{sv}", "icon",
      g_variant_new_string ("audio-input-microphone-symbolic"));
  g_variant_builder_add (&opts, "{sv}", "grant_label",
      g_variant_new_string ("Allow"));
  g_variant_builder_add (&opts, "{sv}", "deny_label",
      g_variant_new_string ("Deny"));

  rd = g_new0 (RequestData, 1);
  rd->self = g_object_ref (self);
  rd->req_id = req_id;

  g_dbus_connection_call (conn,
      PORTAL_DEST,
      PORTAL_PATH,
      PORTAL_IFACE,
      "AccessDialog",
      g_variant_new ("(osssssa{sv})",
          handle_path,
          app_id ? app_id : "",
          "",
          title,
          subtitle,
          "This permission applies only to the current recording session.",
          &opts),
      G_VARIANT_TYPE ("(ua{sv})"),
      G_DBUS_CALL_FLAGS_NONE,
      120000,
      NULL,
      on_access_dialog_done,
      rd);

  return req_id;
}

static void
wp_mic_portal_plugin_init (WpMicPortalPlugin *self)
{
  self->next_id = 0;
}

static void
wp_mic_portal_plugin_enable (WpPlugin *plugin, WpTransition *transition)
{
  WpMicPortalPlugin *self = WP_MIC_PORTAL_PLUGIN (plugin);
  g_autoptr (WpCore) core = wp_object_get_core (WP_OBJECT (self));

  self->dbus = wp_plugin_find (core, "dbus-connection");
  if (!self->dbus) {
    wp_transition_return_error (transition, g_error_new (WP_DOMAIN_LIBRARY,
        WP_LIBRARY_ERROR_INVARIANT,
        "dbus-connection module must be loaded before mic-portal"));
    return;
  }

  wp_object_update_features (WP_OBJECT (self), WP_PLUGIN_FEATURE_ENABLED, 0);
}

static void
wp_mic_portal_plugin_disable (WpPlugin *plugin)
{
  WpMicPortalPlugin *self = WP_MIC_PORTAL_PLUGIN (plugin);
  g_clear_object (&self->dbus);
  wp_object_update_features (WP_OBJECT (self), 0, WP_PLUGIN_FEATURE_ENABLED);
}

static void
wp_mic_portal_plugin_class_init (WpMicPortalPluginClass *klass)
{
  WpPluginClass *plugin_class = (WpPluginClass *) klass;

  plugin_class->enable = wp_mic_portal_plugin_enable;
  plugin_class->disable = wp_mic_portal_plugin_disable;

  signals[ACTION_REQUEST_ACCESS] = g_signal_new_class_handler (
      "request-access", G_TYPE_FROM_CLASS (klass),
      G_SIGNAL_RUN_LAST | G_SIGNAL_ACTION,
      (GCallback) wp_mic_portal_plugin_request_access,
      NULL, NULL, NULL,
      G_TYPE_UINT, 2, G_TYPE_STRING, G_TYPE_STRING);

  signals[SIGNAL_RESPONSE] = g_signal_new (
      "response", G_TYPE_FROM_CLASS (klass),
      G_SIGNAL_RUN_LAST,
      0, NULL, NULL, NULL,
      G_TYPE_NONE, 2, G_TYPE_UINT, G_TYPE_BOOLEAN);
}

WP_PLUGIN_EXPORT GObject *
wireplumber__module_init (WpCore *core, WpSpaJson *args, GError **error)
{
  (void) args;
  (void) error;
  return G_OBJECT (g_object_new (
      wp_mic_portal_plugin_get_type (),
      "name", "mic-portal",
      "core", core,
      NULL));
}
