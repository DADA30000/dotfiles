set -e

echo "Initializing base network policies..."
%{{{setup_script}}}

ALL_NEW_TAGS="[]"
CRED_CONF="%{{{CREDENTIAL_DIR}}}/config.json"
if [[ -f "$CRED_CONF" ]]; then
  EXTRA_TAGS=$(jq -r '[.outbounds[]?.tag // empty, .endpoints[]?.tag // empty] | reverse | .[]' "$CRED_CONF" 2>/dev/null || true)
  for tag in $EXTRA_TAGS; do
    ALL_NEW_TAGS=$(jq -n --argjson list "$ALL_NEW_TAGS" --arg tag "$tag" '[$tag] + $list')
  done
else
  CRED_CONF="none"
fi

echo "Assembling unified sing-box config..."
python3 %{{{build-config-py}}} \
  "%{{{sing-box-config-file}}}" \
  "$CRED_CONF" \
  "/run/sing-box/config.json" \
  "[]" \
  "$ALL_NEW_TAGS"

chmod 600 /run/sing-box/config.json
echo "sing-box initialization complete."
