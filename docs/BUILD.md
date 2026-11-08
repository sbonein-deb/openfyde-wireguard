# Build details

## Environment

- Board: `amd64-openfyde`
- Kernel: `5.4.284-23346-g56829367912d-dirty`
- Source: `chromiumos/third_party/kernel`
- Commit: `56829367912de64ccb421cc7157aba0681d4d722`
- Toolchain: `clang-19`, `ld.lld-19`, `llvm-ar-19`
- `CONFIG_MODULE_SIG` and `CONFIG_MODVERSIONS` are both unset, so unsigned
  out-of-tree modules can be loaded.

## Host config

The build starts from the running host kernel config. On OpenFyde:

```bash
zcat /proc/config.gz > /tmp/host.config
# or, if /proc/config.gz is unavailable:
cp /boot/config-$(uname -r) /tmp/host.config
```

The stock config has:

```
# CONFIG_WIREGUARD is not set
# CONFIG_CRYPTO_LIB_CURVE25519 is not set
# CONFIG_CRYPTO_LIB_CHACHA20POLY1305 is not set
# CONFIG_MODULE_SIG is not set
# CONFIG_MODVERSIONS is not set
```

## Config overrides

`build-wg.sh` applies:

```
CONFIG_WIREGUARD=m
CONFIG_CRYPTO_LIB_CURVE25519=m
CONFIG_CRYPTO_LIB_CURVE25519_GENERIC=m
CONFIG_CRYPTO_CURVE25519_X86=m
CONFIG_CRYPTO_LIB_CHACHA20POLY1305=m
CONFIG_CRYPTO_LIB_CHACHA=m
CONFIG_CRYPTO_LIB_POLY1305=m
CONFIG_DEBUG_INFO=n
CONFIG_GDB_SCRIPTS=n
CONFIG_LOCALVERSION="-23346-g56829367912d-dirty"
CONFIG_LOCALVERSION_AUTO=n
```

`LOCALVERSION` is forced and `scripts/setlocalversion` is patched to not append
`+`, so the resulting `vermagic` matches the running kernel exactly.

## Modules

```
libcurve25519-generic.ko
curve25519-x86_64.ko
libchacha20poly1305.ko
udp_tunnel.ko
ip6_udp_tunnel.ko
wireguard.ko
```

`libcurve25519.ko` is an empty helper and is not loaded.

## Load order

`load-wireguard.sh` loads:

```
libcurve25519-generic -> curve25519-x86_64 -> libchacha20poly1305
-> udp_tunnel -> ip6_udp_tunnel -> wireguard
```

Existing in-tree modules used: `libchacha`, `chacha-x86_64`,
`poly1305-x86_64`, `blake2s-x86_64`, `ip_tunnel`.

## Build

```bash
git clone https://chromium.googlesource.com/chromiumos/third_party/kernel
cd kernel
git checkout 56829367912de64ccb421cc7157aba0681d4d722

zcat /proc/config.gz > /tmp/host.config

SRC="$PWD" CFG=/tmp/host.config OUT=/tmp/wg-out \
  bash /path/to/scripts/build-wg.sh
```

The script needs `make`, `bc`, `bison`, `flex`, `libssl-dev`, `libelf-dev`,
`clang-19`, `lld-19`, and `llvm-19`.

## Verify

```bash
for f in /tmp/wg-out/*.ko; do
  printf '%s: ' "$(basename "$f")"
  grep -a -o 'vermagic=[^ ]*' "$f" | head -1
done
```

Every module must report:

```
vermagic=5.4.284-23346-g56829367912d-dirty
```

## Rebuild after a kernel update

1. Get the new kernel release: `uname -r`.
2. Find the matching `chromiumos/third_party/kernel` commit for that build.
3. Fetch the source at that commit.
4. Save the running config (`zcat /proc/config.gz > /tmp/host.config`).
5. Run `build-wg.sh` with `KREL` and `LOCALVERSION` matching the new kernel.
6. Copy the new `.ko` files to `/usr/local/lib/wireguard/`.
7. Run `/usr/local/bin/load-wireguard.sh`.
8. If the kernel changed, the old modules will not load because `vermagic`
   differs. Check `dmesg` for `version magic ... should be ...`.
