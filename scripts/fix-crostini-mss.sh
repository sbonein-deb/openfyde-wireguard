#!/bin/bash
# Clamp TCP MSS for forwarded traffic to the path MTU.
# Run this ON THE HOST. Useful when Crostini traffic is forwarded through a
# WireGuard tunnel whose MTU (1420) is smaller than vmtap0 (1500).
set -u

if ! command -v iptables >/dev/null 2>&1; then
  echo "iptables not found" >&2
  exit 1
fi

if iptables -t mangle -C FORWARD -p tcp --tcp-flags SYN,RST SYN \
     -j TCPMSS --clamp-mss-to-pmtu 2>/dev/null; then
  echo "MSS clamping already present"
else
  iptables -t mangle -A FORWARD -p tcp --tcp-flags SYN,RST SYN \
    -j TCPMSS --clamp-mss-to-pmtu
  echo "MSS clamping added"
fi
