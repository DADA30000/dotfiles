PATH="$PATH:%{{{pkgs.iproute2}}}/bin:%{{{pkgs.nftables}}}/bin:%{{{pkgs.procps}}}/bin"
%{{{cleanup_script}}}
set -e

ip addr add 10.201.0.1/24 dev lo 2>/dev/null || true
ip -6 addr add fd00:201::1/112 dev lo 2>/dev/null || true

nft -f %{{{vpnRoutingNft}}}

ip netns add vpn_wrapper
ip link add veth_host mtu %{{{toString MTU}}} type veth peer name veth_peer mtu %{{{toString MTU}}}
ip link set veth_peer netns vpn_wrapper

ip addr add 10.200.0.1/24 dev veth_host
ip addr add fd00:200::1/126 dev veth_host
ip link set veth_host up

ip netns exec vpn_wrapper ip addr add 10.200.0.2/24 dev veth_peer
ip netns exec vpn_wrapper ip -6 addr add fd00:200::2/126 dev veth_peer
ip netns exec vpn_wrapper ip link set veth_peer up
ip netns exec vpn_wrapper ip link set lo up
ip netns exec vpn_wrapper ip route add default via 10.200.0.1
ip netns exec vpn_wrapper ip -6 route add default via fd00:200::1

ip rule add to 10.200.0.0/24 lookup main priority 2
ip -6 rule add to fd00:200::/126 lookup main priority 2 2>/dev/null || true

ip netns exec vpn_wrapper sysctl -q net.ipv4.conf.all.route_localnet=1
ip netns exec vpn_wrapper sysctl -q net.ipv4.ping_group_range="0 2147483647"
ip netns exec vpn_wrapper nft add table inet nat
ip netns exec vpn_wrapper nft add chain inet nat output '{ type nat hook output priority dstnat; policy accept; }'
ip netns exec vpn_wrapper nft add rule inet nat output ip daddr 127.0.0.1 meta l4proto '{ tcp, udp }' th dport 53 dnat to 10.200.0.1:53

mkdir -p /etc/netns/vpn_wrapper
echo "nameserver 10.200.0.1" >/etc/netns/vpn_wrapper/resolv.conf
