#!/bin/bash
# Set Crostini eth0 MTU so TCP fits inside a WireGuard tunnel.
# Run this INSIDE the Linux container.
#
# Usage: sudo bash fix-container-mtu.sh [mtu]
set -u

MTU="${1:-1420}"
ip link set eth0 mtu "$MTU"
echo "eth0 MTU set to $MTU"

cat <<'EOF'

To persist this in Crostini, add the MTU to /etc/network/interfaces:

  auto eth0
  iface eth0 inet dhcp
      mtu 1420

Then run: sudo ifdown eth0 && sudo ifup eth0
EOF
