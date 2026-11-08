#!/bin/bash
# Collect Crostini-side connectivity diagnostics.
# Run this INSIDE the Linux container while the VPN is connected.
#
# Usage: bash diagnose-container-vpn.sh [output-file]
set -u

OUT="${1:-/tmp/vpn-diag-container.txt}"
GW=$(ip route 2>/dev/null | awk '/^default/ {print $3; exit}')
GW=${GW:-100.115.92.1}

{
  echo "=== date ==="
  date -u
  echo "=== links ==="
  ip -br addr
  echo "=== eth0 ==="
  ip -d link show eth0
  echo "=== routes ==="
  ip route
  echo "=== resolv.conf ==="
  cat /etc/resolv.conf
  echo "=== DNS lookups ==="
  getent hosts api.github.com
  getent hosts github.com
  echo "=== ping gateway ($GW) ==="
  ping -c2 -W2 "$GW" 2>&1
  echo "=== ping 1.1.1.1 ==="
  ping -c2 -W2 1.1.1.1 2>&1
  echo "=== curl small (api.github.com) ==="
  curl -sS -m 10 -o /dev/null -w '%{http_code} %{time_total}\n' https://api.github.com 2>&1
  echo "=== curl large (1 MB) ==="
  curl -sS -m 30 -o /dev/null -w '%{http_code} %{size_download} %{time_total}\n' \
    'https://speed.cloudflare.com/__down?bytes=1000000' 2>&1
  echo "=== MTU probes to 1.1.1.1 ==="
  for s in 1200 1300 1380 1400 1420 1472; do
    if ping -M do -s "$s" -c1 -W2 1.1.1.1 >/dev/null 2>&1; then
      echo "$s ok"
    else
      echo "$s fail"
    fi
  done
} > "$OUT" 2>&1

echo "saved to $OUT"
