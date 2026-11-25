set -e

echo "Initializing base network policies..."
%{{{setup_script}}}

CACHE_DIR="%{{{CACHE_DIR}}}"
CACHED_CONF="$CACHE_DIR/cached_config.json"
CACHED_SUB_CONF="$CACHE_DIR/cached_sub_config.json"
RUN_CONF="/run/sing-box/config.json"

install -d -m 700 "$CACHE_DIR"

if [[ -s "$CACHED_CONF" ]] && %{{{patched-sing-box}}}/bin/sing-box check -c "$CACHED_CONF" >/dev/null 2>&1; then
  echo "Using cached sing-box config from $CACHED_CONF..."
  install -m 600 "$CACHED_CONF" "${RUN_CONF}.tmp"
else
  echo "No valid cached config; bootstrapping from base sing-box config..."
  install -m 600 "%{{{sing-box-config-file}}}" "${RUN_CONF}.tmp"
fi
mv -f "${RUN_CONF}.tmp" "$RUN_CONF"

SUB_OUT="%{{{sub-output-path}}}"
if [[ -n "$SUB_OUT" ]] && [[ -s "$CACHED_SUB_CONF" ]] && jq -e 'type == "object"' "$CACHED_SUB_CONF" >/dev/null 2>&1; then
  echo "Seeding cached SFA subscription config at $SUB_OUT..."
  SUB_DIR="$(dirname "$SUB_OUT")"
  mkdir -p "$SUB_DIR"
  install -m 640 "$CACHED_SUB_CONF" "${SUB_OUT}.tmp"
  chown root:nginx "${SUB_OUT}.tmp" 2>/dev/null || true
  mv -f "${SUB_OUT}.tmp" "$SUB_OUT"
fi

echo "sing-box initialization complete."
