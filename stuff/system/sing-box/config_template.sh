set -o pipefail

until RESULT=$(curl --doh-url https://1.1.1.1/dns-query -fsSL -H "User-Agent: Karing/9.9.9" -H "x-hwid: $(cat /etc/machine-id)" "https://sub.url.xyz/api/sub/AAAAAAAAAAAA" 2>/dev/null | jq '{outbounds: [.outbounds[] | select(.type | IN("selector", "urltest", "direct", "block", "dns") | not)]}' 2>/dev/null) && [[ -n "$RESULT" ]]; do
  sleep 1
done
printf "%s\n" "$RESULT"
