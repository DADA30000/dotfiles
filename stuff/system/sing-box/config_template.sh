set -o pipefail

# For a sing-box JSON subscription:
# until RESULT=$(curl --doh-url https://1.1.1.1/dns-query -fsSL -H "User-Agent: Karing/9.9.9" -H "x-hwid: $(cat /etc/machine-id)" "https://sub.url.xyz/api/sub/AAAAAAAAAAAA" 2>/dev/null | jq '{outbounds: [.outbounds[] | select(.type | IN("selector", "urltest", "direct", "block", "dns") | not)]}' 2>/dev/null) && [[ -n "$RESULT" ]]; do
#   sleep 1
# done

# For an Xray JSON subscription (including xhttp / whitelist profiles):
until RESULT=$(curl --doh-url https://1.1.1.1/dns-query -fsSL -H "User-Agent: v2raytun/android" -H "x-hwid: $(cat /etc/machine-id)" "https://sub.url.xyz/api/sub/AAAAAAAAAAAA" 2>/dev/null | xray-to-singbox 2>/dev/null) && [[ -n "$RESULT" ]]; do
  sleep 1
done
printf "%s\n" "$RESULT"
