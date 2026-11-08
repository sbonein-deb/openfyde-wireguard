# WireGuard for OpenFyde (kernel 5.4)

Out-of-tree WireGuard kernel modules and a boot-time loader for **OpenFyde
`amd64-openfyde`** on kernel **`5.4.284-23346-g56829367912d-dirty`**.

The stock OpenFyde kernel is built without `CONFIG_WIREGUARD`, while shill
(ChromeOS network manager) only supports **kernel** WireGuard — there is no
userspace `wireguard-go` fallback in the stock VPN UI. This repository provides
the missing modules built from the exact ChromiumOS kernel commit, plus a
script that loads them at boot.

## What is included

| Path | Purpose |
|---|---|
| `scripts/build-wg.sh` | Reproducible build recipe (clang-19 / lld-19) |
| `scripts/load-wireguard.sh` | Dependency-ordered module loader |
| `scripts/setup-wireguard-persist.sh` | Installer + upstart boot job |
| `scripts/diagnose-host-vpn.sh` | Host-side routing/DNS/NAT diagnostics |
| `scripts/diagnose-container-vpn.sh` | Crostini-side connectivity diagnostics |
| `scripts/fix-crostini-mss.sh` | TCP MSS clamping for forwarded traffic |
| `docs/BUILD.md` | Build details and rebuild procedure |
| `docs/TROUBLESHOOTING.md` | Common problems and fixes |
| Releases | Prebuilt `wg-modules.tar.gz` for the kernel above |

## Requirements

- Root shell on the OpenFyde host.
- Kernel `5.4.284-23346-g56829367912d-dirty` for the prebuilt modules.
  For any other kernel, rebuild from the matching source (see `docs/BUILD.md`).
- `CONFIG_MODULE_SIG` and `CONFIG_MODVERSIONS` unset (stock OpenFyde).

## Quick start (prebuilt modules)

1. Download `wg-modules.tar.gz` from the **Releases** page.
2. Install and create the boot job:

   ```bash
   sudo bash scripts/setup-wireguard-persist.sh ./wg-modules.tar.gz
   ```

3. Reboot.
4. Before connecting the VPN, verify:

   ```bash
   lsmod | grep -E 'wireguard|curve25519|chacha20poly1305'
   cat /var/log/wireguard-load.log
   ip link add wgtest0 type wireguard && ip link del wgtest0 && echo WG_OK
   ```

5. Add the WireGuard profile in ChromeOS **Settings → Network → Add VPN** and
   connect. Check the tunnel with:

   ```bash
   wg show
   ```

## Build from source

```bash
# 1. Get the exact kernel source
git clone https://chromium.googlesource.com/chromiumos/third_party/kernel
cd kernel
git checkout 56829367912de64ccb421cc7157aba0681d4d722

# 2. Save the running host config
zcat /proc/config.gz > /tmp/host.config   # or /boot/config-$(uname -r)

# 3. Build
SRC="$PWD" CFG=/tmp/host.config OUT=/tmp/wg-out bash scripts/build-wg.sh
```

See `docs/BUILD.md` for the full list of config overrides and the exact
`vermagic` requirements.

## Boot persistence

`setup-wireguard-persist.sh` installs:

- modules to `/usr/local/lib/wireguard/` (stateful partition, survives reboot);
- `/usr/local/bin/load-wireguard.sh`;
- `/etc/init/wireguard.conf` (upstart job);
- backup copies in `/usr/local/lib/wireguard/`.

The rootfs job is lost on an OS update. Restore it with:

```bash
sudo mount -o remount,rw /
sudo cp /usr/local/lib/wireguard/wireguard.conf /etc/init/wireguard.conf
```

After a kernel update the module `vermagic` changes; rebuild the modules from
the matching kernel source before restoring the job.

## Troubleshooting

- **`Failed to create wireguard interface`** — the module is not loaded or its
  `vermagic` does not match. Check `dmesg`, `lsmod`, and
  `modinfo /usr/local/lib/wireguard/wireguard.ko`.
- **Crostini loses connectivity when the VPN is on** — run
  `scripts/diagnose-host-vpn.sh` and `scripts/diagnose-container-vpn.sh` with
  the VPN connected, then see `docs/TROUBLESHOOTING.md`.

## License

GPL-2.0. The kernel modules are built from Linux kernel sources and
WireGuard, both GPL-2.0.
