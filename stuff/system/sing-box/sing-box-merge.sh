set -euo pipefail

CRED_CONF="%{{{CREDENTIAL_DIR}}}/config.json"
SUB_SCRIPT="%{{{CREDENTIAL_DIR}}}/config.sh"
CACHE_DIR="%{{{CACHE_DIR}}}"
CACHED_CONF="$CACHE_DIR/cached_config.json"
CACHED_SUB_CONF="$CACHE_DIR/cached_sub_config.json"
RUN_CONF="/run/sing-box/config.json"
SUB_OUT="%{{{sub-output-path}}}"

WORK_DIR="$(mktemp -d /run/sing-box/merge.XXXXXX)"
trap 'rm -rf "$WORK_DIR"' EXIT

EXTRA_CONFIGS=()

if [[ -f "$SUB_SCRIPT" ]]; then
  echo "Executing subscription script $SUB_SCRIPT..."
  SUB_CONF="$WORK_DIR/sub_config.json"
  %{{{pkgs.bash}}}/bin/bash "$SUB_SCRIPT" > "$SUB_CONF"
  if grep -q '[^[:space:]]' "$SUB_CONF"; then
    jq -e 'type == "object"' "$SUB_CONF" >/dev/null
    EXTRA_CONFIGS+=("$SUB_CONF")
    echo "Subscription config generated successfully."
  else
    echo "Subscription script output is empty; continuing."
  fi
fi

if [[ -f "$CRED_CONF" ]]; then
  if grep -q '[^[:space:]]' "$CRED_CONF"; then
    jq -e 'type == "object"' "$CRED_CONF" >/dev/null
    EXTRA_CONFIGS+=("$CRED_CONF")
  else
    echo "Credential config $CRED_CONF is empty; continuing."
  fi
fi

echo "Assembling unified sing-box config..."
NEW_CONF="$WORK_DIR/config.json"
python3 %{{{build-config-py}}} \
  "%{{{sing-box-config-file}}}" \
  "$NEW_CONF" \
  "${EXTRA_CONFIGS[@]}"

%{{{patched-sing-box}}}/bin/sing-box check -c "$NEW_CONF"

if [[ -n "$SUB_OUT" ]]; then
  echo "Assembling SFA subscription config at $SUB_OUT..."
  NEW_SUB_CONF="$WORK_DIR/sub_out.json"
  python3 %{{{build-config-py}}} \
    --sfa \
    "%{{{sing-box-shared-config-file}}}" \
    "$NEW_SUB_CONF" \
    "${EXTRA_CONFIGS[@]}"
  jq -e 'type == "object"' "$NEW_SUB_CONF" >/dev/null
fi

install -d -m 700 "$CACHE_DIR"
install -m 600 "$NEW_CONF" "${CACHED_CONF}.tmp"
mv -f "${CACHED_CONF}.tmp" "$CACHED_CONF"

if [[ -n "$SUB_OUT" ]]; then
  install -m 600 "$NEW_SUB_CONF" "${CACHED_SUB_CONF}.tmp"
  mv -f "${CACHED_SUB_CONF}.tmp" "$CACHED_SUB_CONF"

  SUB_DIR="$(dirname "$SUB_OUT")"
  mkdir -p "$SUB_DIR"
  if [[ ! -f "$SUB_OUT" ]] || ! cmp -s "$NEW_SUB_CONF" "$SUB_OUT"; then
    install -m 640 "$NEW_SUB_CONF" "${SUB_OUT}.tmp"
    chown root:nginx "${SUB_OUT}.tmp" 2>/dev/null || true
    mv -f "${SUB_OUT}.tmp" "$SUB_OUT"
  fi
fi

if [[ ! -f "$RUN_CONF" ]] || ! cmp -s "$NEW_CONF" "$RUN_CONF"; then
  echo "Merged sing-box config changed; updating $RUN_CONF and restarting sing-box-core..."
  install -m 600 "$NEW_CONF" "${RUN_CONF}.tmp"
  mv -f "${RUN_CONF}.tmp" "$RUN_CONF"
  %{{{pkgs.systemd}}}/bin/systemctl restart sing-box-core.service
else
  echo "Merged sing-box config is identical to $RUN_CONF; skipping sing-box-core restart."
fi
