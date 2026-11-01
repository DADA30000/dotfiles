#!/usr/bin/env bash
#
# FPTN Bridge Daemon
# Runs fptn-client-cli inside an isolated network/user namespace via pasta,
# exposing the tunnel as a local VLESS endpoint for sing-box on 127.0.0.1:10808.

set -euo pipefail

PATH="$PATH:%{{{pkgs.iproute2}}}/bin:%{{{pkgs.procps}}}/bin:%{{{pkgs.util-linux}}}/bin:%{{{pkgs.coreutils}}}/bin:%{{{pkgs.passt}}}/bin"

# 1. Source credentials / environment overrides from credstore if present
if [ -f "/etc/credstore/fptn.env" ]; then
  # shellcheck disable=SC1091
  source "/etc/credstore/fptn.env"
fi
if [ -z "${ACCESS_TOKEN:-}" ] && [ -f "/etc/credstore/fptn-token" ]; then
  ACCESS_TOKEN="$(tr -d '\r\n' < /etc/credstore/fptn-token)"
fi

# 2. Configuration with fallbacks to Nix-evaluated module defaults
PORT="${PORT:-%{{{toString fptn-port}}}}"
UUID="${UUID:-%{{{fptn-uuid}}}}"
PREFERRED_SERVER="${PREFERRED_SERVER:-%{{{fptn-server}}}}"
SNI="${SNI:-%{{{fptn-sni}}}}"
BYPASS_METHOD="${BYPASS_METHOD:-%{{{fptn-bypass-method}}}}"
ACCESS_TOKEN="${ACCESS_TOKEN:-}"

if [ -z "$ACCESS_TOKEN" ]; then
  echo "Error: ACCESS_TOKEN is missing. Provide it via environment or /etc/credstore/fptn.env" >&2
  exit 1
fi

FPTN_CLI="%{{{fptnClientCli}}}/bin/fptn-client-cli"
SING_BOX_BIN="%{{{patched-sing-box}}}/bin/sing-box"

# -----------------------------------------------------------------------------
# Internal Stage (Runs inside pasta network + user namespace)
# -----------------------------------------------------------------------------
if [ "${1:-}" = "__STAGE_MOUNT__" ]; then
  WORK_DIR="$(mktemp -d /tmp/fptn-bridge.XXXXXX)"
  FPTN_PID=""
  BRIDGE_PID=""

  inner_cleanup() {
    echo "[*] Cleaning up FPTN bridge..."
    if [ -n "$BRIDGE_PID" ] && kill -0 "$BRIDGE_PID" 2>/dev/null; then
      kill "$BRIDGE_PID" 2>/dev/null || true
    fi
    if [ -n "$FPTN_PID" ] && kill -0 "$FPTN_PID" 2>/dev/null; then
      kill -SIGINT "$FPTN_PID" 2>/dev/null || true
      wait "$FPTN_PID" 2>/dev/null || true
    fi
    rm -rf "$WORK_DIR"
  }
  trap inner_cleanup EXIT INT TERM

  # 1. Mount private tmpfs over /var/log for fptn-client-cli logging
  mount -t tmpfs tmpfs /var/log
  mkdir -p /var/log/fptn

  # 2. Dummy chattr shim for fptn-client-cli
  SHIM_DIR="$WORK_DIR/shims"
  mkdir -p "$SHIM_DIR"
  cat > "$SHIM_DIR/chattr" << 'EOF'
#!/bin/sh
exit 0
EOF
  chmod +x "$SHIM_DIR/chattr"
  export PATH="$SHIM_DIR:$PATH"

  # 3. Private /etc/resolv.conf
  TMP_RESOLV="$WORK_DIR/resolv.conf"
  cat > "$TMP_RESOLV" << 'EOF'
nameserver 1.1.1.1
nameserver 8.8.8.8
nameserver 2606:4700:4700::1111
EOF
  mount --bind "$TMP_RESOLV" /etc/resolv.conf

  # 4. Detect gateway & interface
  OUT_IF=""
  for ip in 8.8.8.8 8.8.4.4 77.88.8.8; do
    r=$(ip route get "$ip" 2>/dev/null | awk '{print $5; exit}')
    [ -n "$r" ] && OUT_IF="$r" && break
  done
  [ -z "$OUT_IF" ] && OUT_IF="eno1"

  GW_IP=""
  for ip in 8.8.8.8 8.8.4.4 77.88.8.8; do
    r=$(ip route get "$ip" 2>/dev/null | awk '{print $3; exit}')
    [ -n "$r" ] && GW_IP="$r" && break
  done
  [ -z "$GW_IP" ] && GW_IP="192.168.0.1"

  # 5. Prevent physical IPv6 leaks by removing local ISP default route on OUT_IF
  ip -6 route del default dev "$OUT_IF" 2>/dev/null || true

  echo "[*] Launching fptn-client-cli (server: $PREFERRED_SERVER)..."
  "$FPTN_CLI" \
    --access-token "$ACCESS_TOKEN" \
    --preferred-server "$PREFERRED_SERVER" \
    --out-network-interface "$OUT_IF" \
    --gateway-ip "$GW_IP" \
    --enable-split-tunnel=false \
    --exclude-tunnel-networks "10.0.0.0/8,172.16.0.0/12,192.168.0.0/16" \
    --sni "$SNI" \
    --bypass-method "$BYPASS_METHOD" > "$WORK_DIR/fptn.log" 2>&1 &
  FPTN_PID=$!

  echo "[*] Waiting for tun0 interface..."
  if ! ip link show tun0 >/dev/null 2>&1; then
    ip monitor link | grep -m 1 -E "tun[0-9]+" >/dev/null &
    MON_PID=$!
    while kill -0 "$FPTN_PID" 2>/dev/null && kill -0 "$MON_PID" 2>/dev/null; do
      if ip link show tun0 >/dev/null 2>&1; then
        kill "$MON_PID" 2>/dev/null || true
        break
      fi
      read -t 1 -u 0 2>/dev/null || true
    done
    if ! kill -0 "$FPTN_PID" 2>/dev/null; then
      echo "Error: fptn-client-cli failed to connect." >&2
      cat "$WORK_DIR/fptn.log" >&2
      exit 1
    fi
  fi

  echo "[*] FPTN tunnel connected!"
  # Set VPN default IPv6 route priority
  ip -6 route del default dev "$OUT_IF" 2>/dev/null || true
  ip -6 route replace default via fc00:1::1 dev tun0 metric 1 2>/dev/null || true

  echo "[*] Starting VLESS bridge on port $PORT..."
  cat > "$WORK_DIR/bridge-sing-box.json" <<EOF
{
  "log": {
    "level": "warn"
  },
  "inbounds": [
    {
      "type": "vless",
      "tag": "vless-in",
      "listen": "0.0.0.0",
      "listen_port": $PORT,
      "users": [
        {
          "uuid": "$UUID",
          "name": "fptn-bridge"
        }
      ],
      "multiplex": {
        "enabled": true
      }
    }
  ],
  "outbounds": [
    {
      "type": "direct",
      "tag": "direct"
    }
  ],
  "route": {
    "rules": []
  }
}
EOF

  "$SING_BOX_BIN" run -c "$WORK_DIR/bridge-sing-box.json" > "$WORK_DIR/bridge.log" 2>&1 &
  BRIDGE_PID=$!

  echo "[*] FPTN bridge ready on 127.0.0.1:$PORT."
  wait "$FPTN_PID"
  exit 0
fi

# -----------------------------------------------------------------------------
# Outer Stage: Launch pasta to manage user + network namespaces
# -----------------------------------------------------------------------------
exec pasta \
  --config-net \
  --chroot-fallback \
  -t "127.0.0.1/$PORT" \
  -u "127.0.0.1/$PORT" \
  -- unshare -m -- "$0" __STAGE_MOUNT__
