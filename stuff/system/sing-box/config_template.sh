until curl --doh-url https://1.1.1.1/dns-query -fsSL -H "User-Agent: Karing/9.9.9" -H "x-hwid: $(cat /etc/machine-id)" "https://sub.url.xyz/api/sub/AAAAAAAAAAAAA" | jq '{outbounds: [.outbounds[] | select(.type | IN("selector", "urltest", "direct", "block", "dns") | not)]}'; do
  sleep 1
done
