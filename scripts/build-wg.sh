#!/bin/bash
# Build WireGuard and its crypto dependencies as out-of-tree modules.
#
# Usage:
#   SRC=/path/to/kernel CFG=/path/to/host.config OUT=/path/to/out \
#       bash build-wg.sh
#
# Optional:
#   JOBS=4
#   KREL=5.4.284-23346-g56829367912d-dirty
#   LOCALVERSION=-23346-g56829367912d-dirty
#
# The resulting modules must have vermagic == KREL.
set -euo pipefail

SRC=${SRC:-}
OUT=${OUT:-$(pwd)/out}
CFG=${CFG:-/tmp/host.config}
JOBS=${JOBS:-2}
KREL=${KREL:-5.4.284-23346-g56829367912d-dirty}
LOCALVERSION=${LOCALVERSION:--23346-g56829367912d-dirty}

if [ -z "$SRC" ] || [ ! -d "$SRC" ]; then
  echo "SRC must point at the kernel source tree" >&2
  exit 1
fi
if [ ! -f "$CFG" ]; then
  echo "CFG must point at a kernel config (e.g. /tmp/host.config)" >&2
  exit 1
fi

cd "$SRC"

MAKEVARS=(
  CC=clang-19
  LD=ld.lld-19
  AR=llvm-ar-19
  NM=llvm-nm-19
  OBJCOPY=llvm-objcopy-19
  OBJDUMP=llvm-objdump-19
  READELF=llvm-readelf-19
  STRIP=llvm-strip-19
  HOSTCC=clang-19
  HOSTLD=ld.lld-19
  HOSTAR=llvm-ar-19
  HOSTNM=llvm-nm-19
)

# Prevent setlocalversion from appending '+' when LOCALVERSION is not exported.
sed -i 's/if test "${LOCALVERSION+set}" != "set"; then/if false; then/' scripts/setlocalversion

cp "$CFG" .config
scripts/config --module WIREGUARD
scripts/config --module CRYPTO_LIB_CURVE25519
scripts/config --module CRYPTO_LIB_CURVE25519_GENERIC
scripts/config --module CRYPTO_CURVE25519_X86
scripts/config --module CRYPTO_LIB_CHACHA20POLY1305
scripts/config --module CRYPTO_LIB_CHACHA
scripts/config --module CRYPTO_LIB_POLY1305
scripts/config --disable DEBUG_INFO
scripts/config --disable GDB_SCRIPTS
scripts/config --set-str LOCALVERSION "$LOCALVERSION"
scripts/config --disable LOCALVERSION_AUTO

make "${MAKEVARS[@]}" olddefconfig

# The running kernel was built with clang 19. If Kconfig did not detect it,
# force the version so compiler-dependent code matches.
if ! grep -q '^CONFIG_CC_IS_CLANG=y' .config; then
  scripts/config --enable CC_IS_CLANG
fi
if ! grep -q '^CONFIG_CLANG_VERSION=190000' .config; then
  scripts/config --set-val CLANG_VERSION 190000
fi

echo "--- target release ---"
echo "$KREL"
echo "--- relevant config ---"
grep -E '^CONFIG_(WIREGUARD|CRYPTO_LIB_CURVE25519|CRYPTO_LIB_CURVE25519_GENERIC|CRYPTO_CURVE25519_X86|CRYPTO_LIB_CHACHA20POLY1305|CRYPTO_LIB_CHACHA|CRYPTO_LIB_POLY1305|LOCALVERSION|LOCALVERSION_AUTO|DEBUG_INFO|CC_IS_CLANG|CLANG_VERSION|LD_IS_LLD|GCC_VERSION)=' .config || true

make -j"$JOBS" "${MAKEVARS[@]}" modules_prepare

# Ensure the exact release string (no trailing '+').
echo "$KREL" > include/config/kernel.release
sed -i "s/^#define UTS_RELEASE .*/#define UTS_RELEASE \"$KREL\"/" include/generated/utsrelease.h
cat include/config/kernel.release
grep UTS_RELEASE include/generated/utsrelease.h

make -j"$JOBS" "${MAKEVARS[@]}" M=lib/crypto KBUILD_MODPOST_WARN=1 modules
make -j"$JOBS" "${MAKEVARS[@]}" M=arch/x86/crypto KBUILD_MODPOST_WARN=1 modules
make -j"$JOBS" "${MAKEVARS[@]}" M=net/ipv4 KBUILD_MODPOST_WARN=1 udp_tunnel.ko
make -j"$JOBS" "${MAKEVARS[@]}" M=net/ipv6 KBUILD_MODPOST_WARN=1 ip6_udp_tunnel.ko
make -j"$JOBS" "${MAKEVARS[@]}" M=drivers/net/wireguard KBUILD_MODPOST_WARN=1 modules

mkdir -p "$OUT"
for f in \
  lib/crypto/libcurve25519-generic.ko \
  lib/crypto/libchacha20poly1305.ko \
  arch/x86/crypto/curve25519-x86_64.ko \
  net/ipv4/udp_tunnel.ko \
  net/ipv6/ip6_udp_tunnel.ko \
  drivers/net/wireguard/wireguard.ko
do
  if [ -f "$f" ]; then
    cp -v "$f" "$OUT/"
  fi
done

echo "--- built modules ---"
for f in "$OUT"/*.ko; do
  echo "=== $f"
  grep -a -o 'vermagic=[^ ]*' "$f" | head -1 || true
done
