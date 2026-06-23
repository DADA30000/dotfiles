#!/usr/bin/env bash
set -euo pipefail

# Enable nullglob to safely handle directories with no .conf files
shopt -s nullglob

# If argument is a directory, recursively process all config files inside it
if [[ -d "${1:-}" ]]; then
  echo "==> Directory detected: $1. Processing configs..."
  for conf in "$1"/*.conf; do
    if [[ -f "$conf" ]]; then
      echo "==> Running update for: $conf"
      # Run this script on the configuration file
      "$0" "$conf" || echo "==> Failed to update configuration: $conf"
    fi
  done
  exit 0
fi

CONFIG_FILE="${1:-/update-cloudflare-dns.conf}"

if ! [[ -f "$CONFIG_FILE" ]]; then
  echo "Error! Configuration file not found: $CONFIG_FILE" >&2
  exit 1
fi

# Source configuration file
# shellcheck source=/dev/null
source "$CONFIG_FILE"

# Validate parameters with safe defaults
ttl="${ttl:-0}"
proxied="${proxied:-false}"
what_ip="${what_ip:-external}"

if [ "$ttl" -lt 120 ] || [ "$ttl" -gt 7200 ] && [ "$ttl" -ne 1 ]; then
  echo "Error! ttl out of range (120-7200) or not set to 1" >&2
  exit 1
fi

if [ "$proxied" != "false" ] && [ "$proxied" != "true" ]; then
  echo "Error! Incorrect 'proxied' parameter, choose 'true' or 'false'" >&2
  exit 1
fi

if [ "$what_ip" != "external" ] && [ "$what_ip" != "internal" ]; then
  echo "Error! Incorrect 'what_ip' parameter, choose 'external' or 'internal'" >&2
  exit 1
fi

if [ "$what_ip" == "internal" ] && [ "$proxied" == "true" ]; then
  echo "Error! Internal IP cannot be proxied" >&2
  exit 1
fi

REIP='^((25[0-5]|(2[0-4]|1[0-9]|[1-9]|)[0-9])\.){3}(25[0-5]|(2[0-4]|1[0-9]|[1-9]|)[0-9])$'

# Get current IP Address
if [ "$what_ip" == "external" ]; then
  ip=$('%{{{pkgs.curl}}}'/bin/curl -4 -s -X GET https://checkip.amazonaws.com --max-time 10)
  if [ -z "$ip" ] || ! [[ "$ip" =~ $REIP ]]; then
    echo "Error! Invalid or empty external IP returned: '$ip'" >&2
    exit 1
  fi
  echo "==> External IP is: $ip"
else
  # Retrieve primary network interface
  interface=$('%{{{pkgs.iproute2}}}/bin/ip' route get 1.1.1.1 2>/dev/null | '%{{{pkgs.gawk}}}/bin/awk' '/dev/ { print $5 }')
  if [ -z "$interface" ]; then
    echo "Error! Could not detect default interface" >&2
    exit 1
  fi
  ip=$('%{{{pkgs.iproute2}}}/bin/ip' -o -4 addr show "${interface}" scope global | '%{{{pkgs.gawk}}}/bin/awk' '{print $4;}' | cut -d/ -f 1)
  if [ -z "$ip" ] || ! [[ "$ip" =~ $REIP ]]; then
    echo "Error! Invalid or empty internal IP: '$ip'" >&2
    exit 1
  fi
  echo "==> Internal IP on interface ${interface} is: $ip"
fi

# Split DNS records
IFS=',' read -r -a dns_records <<<"$dns_record"

for record in "${dns_records[@]}"; do
  # Strip whitespaces
  record=$(echo "$record" | xargs)
  [ -z "$record" ] && continue

  dns_record_ip=""
  is_proxied=""

  if [ "$proxied" == "false" ]; then
    # Try resolving via nslookup, fall back to host
    dns_record_ip=$('%{{{pkgs.dnsutils}}}/bin/nslookup' "$record" 1.1.1.1 2>/dev/null | '%{{{pkgs.gawk}}}/bin/awk' '/Address/ { print $2 }' | sed -n '2p')
    if [ -z "$dns_record_ip" ]; then
      dns_record_ip=$('%{{{pkgs.bind}}}/bin/host' -t A "$record" 1.1.1.1 2>/dev/null | '%{{{pkgs.gawk}}}/bin/awk' '/has address/ { print $4 }' | sed -n '1p')
    fi

    if [ -z "$dns_record_ip" ]; then
      echo "Error! Can't resolve DNS record for $record" >&2
      exit 1
    fi
    is_proxied="false"
  else
    dns_record_info=$(%{{{pkgs.curl}}}/bin/curl -s -X GET "https://api.cloudflare.com/client/v4/zones/$zoneid/dns_records?type=A&name=$record" \
      -H "Authorization: Bearer $cloudflare_zone_api_token" \
      -H "Content-Type: application/json")

    if [[ "$(echo "$dns_record_info" | '%{{{pkgs.jq}}}/bin/jq' -r '.success')" != "true" ]]; then
      echo "$dns_record_info" >&2
      echo "Error! Could not fetch DNS record details from Cloudflare API" >&2
      exit 1
    fi

    dns_record_ip=$(echo "$dns_record_info" | '%{{{pkgs.jq}}}/bin/jq' -r '.result[0].content')
    is_proxied=$(echo "$dns_record_info" | '%{{{pkgs.jq}}}/bin/jq' -r '.result[0].proxied | tostring')
  fi

  # Check if updates are needed
  if [ "$dns_record_ip" == "$ip" ] && [ "$is_proxied" == "$proxied" ]; then
    echo "==> DNS record IP of $record is already $dns_record_ip, no changes needed."
    continue
  fi

  echo "==> DNS record of $record is currently: $dns_record_ip. Updating to $ip..."

  # Query Cloudflare API for the specific Record ID
  cloudflare_record_info=$('%{{{pkgs.curl}}}/bin/curl' -s -X GET "https://api.cloudflare.com/client/v4/zones/$zoneid/dns_records?type=A&name=$record" \
    -H "Authorization: Bearer $cloudflare_zone_api_token" \
    -H "Content-Type: application/json")

  if [[ "$(echo "$cloudflare_record_info" | '%{{{pkgs.jq}}}/bin/jq' -r '.success')" != "true" ]]; then
    echo "$cloudflare_record_info" >&2
    echo "Error! Could not fetch Cloudflare record ID" >&2
    exit 1
  fi
  cloudflare_dns_record_id=$(echo "$cloudflare_record_info" | '%{{{pkgs.jq}}}/bin/jq' -r '.result[0].id')

  # Send the PUT request to apply updates
  update_dns_record=$('%{{{pkgs.curl}}}/bin/curl' -s -X PUT "https://api.cloudflare.com/client/v4/zones/$zoneid/dns_records/$cloudflare_dns_record_id" \
    -H "Authorization: Bearer $cloudflare_zone_api_token" \
    -H "Content-Type: application/json" \
    --data "{\"type\":\"A\",\"name\":\"$record\",\"content\":\"$ip\",\"ttl\":$ttl,\"proxied\":$proxied}")

  if [[ "$(echo "$update_dns_record" | '%{{{pkgs.jq}}}/bin/jq' -r '.success')" != "true" ]]; then
    echo "$update_dns_record" >&2
    echo "Error! Cloudflare update failed." >&2
    exit 1
  fi

  echo "==> Success! $record updated to $ip (ttl: $ttl, proxied: $proxied)"
done
