#!/bin/sh
# Load WireGuard and its out-of-tree crypto dependencies.
# Usage: load-wireguard.sh [module-dir]
set -u

D=${1:-/usr/local/lib/wireguard}

log() { echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) $*"; }

# At boot this may run before /usr/local is mounted. Wait for the module dir.
i=0
while [ ! -f "$D/wireguard.ko" ] && [ "$i" -lt 60 ]; do
  i=$((i + 1))
  sleep 1
done

if [ ! -f "$D/wireguard.ko" ]; then
  log "ERROR: $D/wireguard.ko not found; is /usr/local mounted?"
  exit 1
fi

# Existing in-tree modules that provide symbols WireGuard needs.
for m in libchacha chacha-x86_64 poly1305-x86_64 blake2s-x86_64 ip_tunnel; do
  modprobe "$m" 2>/dev/null || true
done

# Out-of-tree modules, in dependency order.
for m in libcurve25519-generic curve25519-x86_64 libchacha20poly1305 udp_tunnel ip6_udp_tunnel wireguard; do
  name=$(echo "$m" | tr '-' '_')
  if grep -q "^$name " /proc/modules 2>/dev/null; then
    log "already loaded: $name"
    continue
  fi
  log "loading: $m"
  if ! insmod "$D/$m.ko"; then
    log "ERROR: failed to load $m"
    exit 1
  fi
done

log "wireguard loaded"
