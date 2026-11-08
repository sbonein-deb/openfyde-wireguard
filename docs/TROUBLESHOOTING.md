# Troubleshooting

## The module does not load

```bash
dmesg | tail -30
lsmod | grep -E 'wireguard|curve25519|chacha20poly1305'
modinfo /usr/local/lib/wireguard/wireguard.ko
cat /var/log/wireguard-load.log
```

A `version magic ... should be ...` message means the module was built for a
different kernel. Rebuild it from the matching kernel source (see
`BUILD.md`).

Quick check that the kernel accepts WireGuard interfaces:

```bash
ip link add wgtest0 type wireguard && ip link del wgtest0 && echo WG_OK
```

## UI says "Failed to create wireguard interface"

shill R132 creates the interface through the kernel only:

```cpp
manager()->device_info()->CreateWireGuardInterface(...)
```

There is no userspace `wireguard-go` fallback. The module must already be
loaded before connecting. Check `lsmod` and `dmesg`.

## VPN connects but sites do not open

Start with:

```bash
wg show
```

### No `latest handshake`

`wg show` omits the handshake line until a handshake succeeds. Typical causes:

1. **Client `Address` equals peer `Endpoint`.** The kernel treats the endpoint
   as a local address and the encrypted packets never leave the host.

   ```bash
   ip route get <endpoint-ip>
   ```

   If this prints `local ... dev lo`, fix the profile: `Address` must be the
   tunnel IP assigned by the server (for example `10.0.0.2/32`), not the
   server's public IP.

2. **Endpoint is unreachable** because of routing, firewall, or a wrong port.
   Check `ip route get <endpoint-ip>` and `wg show` (`transfer: 0 B received`).

3. **`AllowedIPs` is empty.** WireGuard drops all outbound data for a peer
   without allowed IPs. Use `0.0.0.0/0, ::/0` for a full tunnel.

### Handshake works but traffic fails

- **DNS:** `getent hosts example.com`, `cat /etc/resolv.conf`, and
  `grep -i dns /var/log/net.log`.
- **MTU:** `wg0` is created with MTU 1420. Test with:

  ```bash
  ping -M do -s 1372 -c1 1.1.1.1   # 1400 bytes
  ping -M do -s 1392 -c1 1.1.1.1   # 1420 bytes
  ```

  If 1400 works and 1420 fails, the path MTU is smaller than the WireGuard
  default. Lower the MTU or clamp TCP MSS.

- **Routing:** check `ip rule show` and `ip route show table all`. ChromeOS
  uses policy routing; the VPN routes live in a separate table (for example
  `1014`).

## Crostini loses connectivity when the VPN is on

Crostini traffic is forwarded by the host through `vmtap0`. With a VPN
connected, patchpanel forwards that traffic to the VPN uplink (`wg0`), whose
MTU is 1420 while `vmtap0`/`eth0` are 1500. DNS and NAT are also handled by the
host.

Collect diagnostics **while the VPN is connected**:

On the host:

```bash
sudo bash scripts/diagnose-host-vpn.sh
```

Inside the Linux container:

```bash
bash scripts/diagnose-container-vpn.sh
```

Then disconnect the VPN and inspect:

```bash
cat /tmp/vpn-diag-host.txt
cat /tmp/vpn-diag-container.txt
```

What to look for:

1. **MTU probes.** In `vpn-diag-container.txt`, if `1400`/`1420` fail but
   `1300` works, the tunnel path MTU is the problem. Try lowering the
   container MTU:

   ```bash
   sudo bash scripts/fix-container-mtu.sh 1420
   ```

   If that is not enough, use `1280`. To persist it in Crostini, add `mtu 1420`
   to the `iface eth0 inet dhcp` stanza in `/etc/network/interfaces`.

   Alternatively, clamp TCP MSS on the host:

   ```bash
   sudo bash scripts/fix-crostini-mss.sh
   ```

2. **DNS.** If `getent hosts` fails in the container, check
   `/etc/resolv.conf` and the `dnsproxyd` lines in `/var/log/net.log`.

3. **NAT.** In `vpn-diag-host.txt`, look at `iptables-save -t nat` and the
   conntrack entries for `100.115.92.0/24`. If container traffic is forwarded
   to `wg0` without source NAT, the VPN server cannot route the replies. As a
   diagnostic experiment only:

   ```bash
   iptables -t nat -A POSTROUTING -s 100.115.92.0/24 -o wg0 -j MASQUERADE
   ```

   patchpanel normally manages these rules; do not rely on a manual rule
   surviving a reconnect or reboot.

4. **Policy routing.** Compare `ip rule show` and the route tables (`249`,
   `1009`, `1014`) with and without the VPN. If the container subnet is sent
   into the VPN table but the return path is missing, the VPN server or its
   firewall is the likely cause.

## After an OS update

- `/etc/init/wireguard.conf` lives on the rootfs and is lost. Restore it from
  `/usr/local/lib/wireguard/wireguard.conf`.
- The kernel `vermagic` changes, so the modules must be rebuilt from the
  matching kernel source.
