#!/bin/bash
# Collect host-side VPN / Crostini routing diagnostics.
# Run this ON THE HOST while the VPN is connected.
#
# Usage: sudo bash diagnose-host-vpn.sh [output-file]
set -u

OUT="${1:-/tmp/vpn-diag-host.txt}"

{
  echo "=== date ==="
  date -u
  echo "=== uname ==="
  uname -a
  echo "=== links ==="
  ip -br addr
  echo "=== wg show ==="
  wg show 2>&1
  echo "=== ip rule ==="
  ip rule show
  echo "=== routes (all tables) ==="
  ip route show table all
  for t in 249 250 1009 1014; do
    echo "=== table $t ==="
    ip route show table "$t" 2>&1
  done
  echo "=== forwarding ==="
  sysctl net.ipv4.ip_forward net.ipv6.conf.all.forwarding 2>&1
  echo "=== iptables nat ==="
  iptables-save -t nat 2>&1
  echo "=== iptables mangle ==="
  iptables-save -t mangle 2>&1
  echo "=== iptables filter ==="
  iptables-save -t filter 2>&1
  echo "=== nftables ==="
  nft list ruleset 2>&1
  echo "=== neighbours ==="
  ip neigh show
  echo "=== conntrack (Crostini subnet) ==="
  grep -E '100\.115\.92' /proc/net/nf_conntrack 2>/dev/null | head -100
  echo "=== shill / patchpanel log ==="
  grep -iE 'vmtap|crostini|vpn|route|dns' /var/log/net.log 2>/dev/null | tail -150
} > "$OUT" 2>&1

echo "saved to $OUT"
