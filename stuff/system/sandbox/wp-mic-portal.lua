-- Prompt via XDG AccessDialog when a sandboxed client on a mic-portal socket
-- starts an Audio capture stream; redirect to sandbox-null-mic on denial.

lutils = require ("linking-utils")
log = Log.open_topic ("s-linking")

local mic_portal = Plugin.find ("mic-portal")
local pending = {}
local decisions = {}

if mic_portal then
  mic_portal:connect ("response", function (_, req_id, granted)
    local cb = pending[req_id]
    pending[req_id] = nil
    if cb then
      cb (granted)
    end
  end)
end

local function find_null_mic (om)
  for target in om:iterate {
    type = "SiLinkable",
    Constraint { "node.name", "=", "sandbox-null-mic" },
  } do
    return target
  end
  return nil
end

local function is_mic_portal_client (client)
  local acc = client.properties["pipewire.access"]
  local cacc = client.properties["pipewire.client.access"]
  local sock = client.properties["pipewire.sec.socket"]
  return acc == "restricted-mic-portal"
      or cacc == "restricted-mic-portal"
      or sock == "pipewire-0-restricted-mic-portal"
end

AsyncEventHook {
  name = "linking/mic-portal-gate",
  after = {
    "linking/find-defined-target",
    "linking/find-filter-target",
    "linking/find-media-role-target",
    "linking/find-default-target",
    "linking/find-best-target",
  },
  before = "linking/prepare-link",
  interests = {
    EventInterest {
      Constraint { "event.type", "=", "select-target" },
    },
  },
  steps = {
    start = {
      next = "none",
      execute = function (event, transition)
        local source, om, si, si_props, _, target =
            lutils:unwrap_select_target_event (event)

        if not target or si_props["media.class"] ~= "Stream/Input/Audio" then
          transition:advance ()
          return
        end

        if target.properties["node.name"] == "sandbox-null-mic" then
          transition:advance ()
          return
        end

        local node = si:get_associated_proxy ("node")
        local client_id = node and node.properties["client.id"]
        if not client_id then
          transition:advance ()
          return
        end

        local clients_om = source:call ("get-object-manager", "client")
        local client = clients_om and clients_om:lookup {
          Constraint { "bound-id", "=", client_id, type = "gobject" },
        }
        if not client or not is_mic_portal_client (client) then
          transition:advance ()
          return
        end

        local stream_id = si.id
        local cached = decisions[stream_id]
        if cached ~= nil then
          if not cached then
            local null_mic = find_null_mic (om)
            if null_mic then
              event:set_data ("target", null_mic)
            else
              event:set_data ("target", nil)
            end
          end
          transition:advance ()
          return
        end

        local function finish (granted)
          decisions[stream_id] = granted
          if not granted then
            local null_mic = find_null_mic (om)
            if null_mic then
              log:info (si, "Microphone denied; redirecting stream to sandbox-null-mic")
              event:set_data ("target", null_mic)
            else
              log:warning (si, "Microphone denied and sandbox-null-mic not found; dropping target")
              event:set_data ("target", nil)
            end
          else
            log:info (si, "Microphone access granted")
          end
          transition:advance ()
        end

        if not mic_portal then
          finish (false)
          return
        end

        local app_id = client.properties["pipewire.access.portal.app_id"]
            or client.properties["application.name"] or ""
        local app_name = client.properties["application.name"] or app_id

        local req_id = mic_portal:call ("request-access", app_id, app_name)
        if not req_id or req_id == 0 then
          finish (false)
          return
        end

        pending[req_id] = finish
      end,
    },
  },
}:register ()

SimpleEventHook {
  name = "linking/mic-portal-cleanup",
  interests = {
    EventInterest {
      Constraint { "event.type", "=", "session-item-removed" },
    },
  },
  execute = function (event)
    local si = event:get_subject ()
    if si then
      decisions[si.id] = nil
    end
  end,
}:register ()
