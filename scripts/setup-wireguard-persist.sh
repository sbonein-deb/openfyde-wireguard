#!/bin/bash
# Install WireGuard modules and a boot-time loader on an OpenFyde/ChromeOS host.
#
# Usage:
#   sudo bash setup-wireguard-persist.sh /path/to/wg-modules.tar.gz
#   sudo URL=https://example.com/wg-modules.tar.gz \
#       bash setup-wireguard-persist.sh
#
# The tarball must contain the .ko files and load-wireguard.sh.
set -u

TARBALL="${1:-${TARBALL:-}}"
URL="${URL:-}"
WORK=$(mktemp -d /tmp/wg-modules.XXXXXX)
DESTDIR=/usr/local/lib/wireguard

cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT

if [ -n "$URL" ]; then
  echo "== downloading $URL"
  TARBALL=/tmp/wg-modules.tar.gz
  rm -f "$TARBALL"
  if ! curl -fsSL "$URL" -o "$TARBALL"; then
    echo "download failed" >&2
    exit 1
  fi
fi

if [ -z "$TARBALL" ] || [ ! -f "$TARBALL" ]; then
  echo "Usage: $0 <wg-modules.tar.gz>" >&2
  echo "   or: URL=https://.../wg-modules.tar.gz $0" >&2
  exit 1
fi

echo "== extracting $TARBALL"
tar -xzf "$TARBALL" -C "$WORK"
ls -l "$WORK"

if [ ! -f "$WORK/load-wireguard.sh" ] || [ ! -f "$WORK/wireguard.ko" ]; then
  echo "tarball does not look like a wg-modules package" >&2
  exit 1
fi

echo "== installing modules to $DESTDIR"
mkdir -p "$DESTDIR"
cp -v "$WORK"/*.ko "$DESTDIR"/
install -m 0755 "$WORK/load-wireguard.sh" /usr/local/bin/load-wireguard.sh

echo "== saving backup files"
for f in BUILD.md build-wg.sh; do
  if [ -f "$WORK/$f" ]; then
    cp -v "$WORK/$f" "$DESTDIR"/
  fi
done
cp -v "$TARBALL" "$DESTDIR/wg-modules.tar.gz" 2>/dev/null || true

echo "== remounting / rw"
mount -o remount,rw / || echo "remount failed (continuing)"

echo "== choosing upstart event"
if [ -f /etc/init/system-services.conf ]; then
  EVENT=system-services
elif [ -f /etc/init/boot-services.conf ]; then
  EVENT=boot-services
else
  EVENT=startup
fi
echo "event: $EVENT"

echo "== writing /etc/init/wireguard.conf"
cat > /etc/init/wireguard.conf <<EOF
# Load out-of-tree WireGuard modules at boot
start on started $EVENT
task
script
  /usr/local/bin/load-wireguard.sh >> /var/log/wireguard-load.log 2>&1
end script
EOF
cp -v /etc/init/wireguard.conf "$DESTDIR/wireguard.conf"

echo "== checking obsolete wrapper"
if [ -f /usr/sbin/wireguard ]; then
  if head -20 /usr/sbin/wireguard 2>/dev/null | grep -q 'wireguard-go'; then
    rm -f /usr/sbin/wireguard && echo "removed /usr/sbin/wireguard"
  else
    echo "keeping /usr/sbin/wireguard (not a wireguard-go wrapper)"
    file /usr/sbin/wireguard 2>/dev/null || true
  fi
fi

echo "== verifying module load (idempotent)"
/usr/local/bin/load-wireguard.sh "$DESTDIR"
echo "load rc=$?"

echo "== remounting / ro"
mount -o remount,ro / 2>/dev/null || true

echo "== done"
echo "Backup dir: $DESTDIR"
echo "After reboot check:"
echo "  lsmod | grep -E 'wireguard|curve25519|chacha20poly1305'"
echo "  cat /var/log/wireguard-load.log"
echo "  wg show"
