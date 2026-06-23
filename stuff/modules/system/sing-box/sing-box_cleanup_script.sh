PATH="$PATH"'%{{{":${pkgs.iptables}/bin:${pkgs.iproute2}/bin:${pkgs.ipset}/bin:${pkgs.gawk}/bin"}}}'
FIX_INCOMING_PACKETS_TABLE='%{{{FIX_INCOMING_PACKETS_TABLE}}}'
FIX_INCOMING_PACKETS_MARK='%{{{FIX_INCOMING_PACKETS_MARK}}}'
VPNIFY_TABLE='%{{{VPNIFY_TABLE}}}'
GAME_PEERS_TABLE='%{{{GAME_PEERS_TABLE}}}'

rm -rf /etc/netns/vpn_wrapper

ip netns del vpn_wrapper 2>/dev/null || true
ip link del veth_host 2>/dev/null || true
ip route flush table $VPNIFY_TABLE 2>/dev/null || true

for prio in 1 2; do
  while ip rule del priority $prio 2>/dev/null; do :; done
done

iptables -t mangle -D PREROUTING -j CONNMARK --restore-mark --mask 0xFFFE 2>/dev/null || true
iptables -t mangle -D OUTPUT -m mark --mark '%{{{toString zapret-mark}}}' -j CONNMARK --save-mark --mask 0xFFFE 2>/dev/null || true
iptables -t mangle -D OUTPUT -m mark --mark '%{{{toString zapret-mark}}}' -j NFQUEUE --queue-num '%{{{zapret-qnum}}}' --queue-bypass 2>/dev/null || true

iptables -t mangle -D PREROUTING -m conntrack --ctstate NEW -j BYPASS_CHECK 2>/dev/null || true
iptables -t mangle -D OUTPUT -m connmark --mark $FIX_INCOMING_PACKETS_MARK -j CONNMARK --restore-mark 2>/dev/null || true
iptables -t mangle -F BYPASS_CHECK 2>/dev/null || true
iptables -t mangle -X BYPASS_CHECK 2>/dev/null || true
ip rule del fwmark $FIX_INCOMING_PACKETS_MARK lookup $FIX_INCOMING_PACKETS_TABLE priority 50 2>/dev/null || true
ip route flush table $FIX_INCOMING_PACKETS_TABLE 2>/dev/null || true

iptables-save -t mangle | grep -e "-j SET --add-set bypass_peers src" | sed 's/-A /-D /' | while read -r cmd; do
  iptables -t mangle "$cmd" 2>/dev/null || true
done
ip rule del lookup $GAME_PEERS_TABLE priority 5000 2>/dev/null || true
ip route flush table $GAME_PEERS_TABLE 2>/dev/null || true
ipset destroy bypass_peers 2>/dev/null || true
