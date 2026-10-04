PATH="$PATH:%{{{pkgs.iproute2}}}/bin:%{{{pkgs.nftables}}}/bin"

nft delete table inet vpn_routing 2>/dev/null || true

rm -rf /etc/netns/vpn_wrapper
ip netns del vpn_wrapper 2>/dev/null || true
ip link del veth_host 2>/dev/null || true
ip link del zapret0 2>/dev/null || true

ip addr del 10.201.0.1/24 dev lo 2>/dev/null || true
ip -6 addr del fd00:201::1/112 dev lo 2>/dev/null || true

ip rule del to 10.200.0.0/24 lookup main priority 2 2>/dev/null || true
ip -6 rule del to fd00:200::/126 lookup main priority 2 2>/dev/null || true
