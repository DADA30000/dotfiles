set -e

echo "Initializing base network policies..."
%{{{setup_script}}}

CRED_CONF="%{{{CREDENTIAL_DIR}}}/config.json"
SUB_SCRIPT="%{{{CREDENTIAL_DIR}}}/config.sh"
EXTRA_CONFIGS=()

if [[ -f "$SUB_SCRIPT" ]]; then
  echo "Executing subscription script $SUB_SCRIPT..."
  SUB_CONF="/run/sing-box/sub_config.json"
  if %{{{pkgs.bash}}}/bin/bash "$SUB_SCRIPT" > "$SUB_CONF" && jq empty "$SUB_CONF" 2>/dev/null; then
    echo "Subscription config generated successfully."
    EXTRA_CONFIGS+=("$SUB_CONF")
  else
    echo "Warning: $SUB_SCRIPT failed or output invalid JSON, skipping." >&2
    rm -f "$SUB_CONF"
  fi
fi

if [[ -f "$CRED_CONF" ]]; then
  EXTRA_CONFIGS+=("$CRED_CONF")
fi

echo "Assembling unified sing-box config..."
python3 %{{{build-config-py}}} \
  "%{{{sing-box-config-file}}}" \
  "/run/sing-box/config.json" \
  "[]" \
  "${EXTRA_CONFIGS[@]}"

chmod 600 /run/sing-box/config.json
echo "sing-box initialization complete."
