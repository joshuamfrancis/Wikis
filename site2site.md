# WireGuard + WebSocket Tunnel Setup Guide

## Hub-and-Spoke VPN with WebSocket Wrapping

This guide walks through setting up a WireGuard VPN in a hub-and-spoke topology with WebSocket tunneling. One central server routes traffic between two client machines. The setup is done in two phases: first getting WireGuard working on its own, then layering WebSocket on top.

---

## Architecture Overview

```
┌─────────────────┐         ┌─────────────────┐
│   Client A      │         │   Client B      │
│   10.0.0.2/24   │         │   10.0.0.3/24   │
│   (On-Prem DC)  │         │   (On-Prem DC)  │
└────────┬────────┘         └────────┬────────┘
         │ WireGuard (UDP 51820)     │ WireGuard (UDP 51820)
         │ wrapped in WebSocket      │ wrapped in WebSocket
         │ (TCP 443)                 │ (TCP 443)
         │                           │
         └───────────┬───────────────┘
                     │
            ┌────────┴────────┐
            │     Server      │
            │   10.0.0.1/24   │
            │   (EC2 / PVE)   │
            └─────────────────┘
```

### Machine Roles

| Role | WireGuard IP | OS | Description |
|---|---|---|---|
| Server | `10.0.0.1/24` | Ubuntu 22.04+ | Central hub, routes traffic between clients |
| Client A | `10.0.0.2/24` | Ubuntu 22.04+ | On-prem data centre machine |
| Client B | `10.0.0.3/24` | Ubuntu 22.04+ | On-prem data centre machine |

### Proxmox Lab Setup

For the initial lab setup, create three Ubuntu VMs (or LXCs) in Proxmox. Ensure all three can reach each other over the Proxmox bridge network. Note the IP address of each VM on the bridge — these are used as WireGuard endpoints in Phase 1.

---

## Phase 1: WireGuard VPN (No WebSocket)

Get the core VPN working first so you can validate connectivity before adding complexity.

### Step 1.1 — Install WireGuard on All Three Machines

Run the following on each machine:

```bash
sudo apt update
sudo apt install -y wireguard wireguard-tools
```

Verify the kernel module loads:

```bash
sudo modprobe wireguard
lsmod | grep wireguard
```

### Step 1.2 — Generate Key Pairs

On **each machine**, generate a private and public key pair:

```bash
wg genkey | tee /etc/wireguard/privatekey | wg pubkey > /etc/wireguard/publickey
chmod 600 /etc/wireguard/privatekey
```

Record the public keys — you will need them for peer configuration:

```bash
cat /etc/wireguard/publickey
```

Keep track of which public key belongs to which machine. For this guide we will reference them as:

- `<SERVER_PUBKEY>`
- `<CLIENT_A_PUBKEY>`
- `<CLIENT_B_PUBKEY>`
- `<SERVER_PRIVKEY>`, `<CLIENT_A_PRIVKEY>`, `<CLIENT_B_PRIVKEY>`

### Step 1.3 — Configure the Server

Create `/etc/wireguard/wg0.conf` on the **server**:

```ini
[Interface]
Address = 10.0.0.1/24
ListenPort = 51820
PrivateKey = <SERVER_PRIVKEY>

# Enable IP forwarding and NAT when the interface comes up
PostUp = sysctl -w net.ipv4.ip_forward=1
PostUp = iptables -A FORWARD -i wg0 -j ACCEPT
PostUp = iptables -A FORWARD -o wg0 -j ACCEPT
PostUp = iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE

PostDown = iptables -D FORWARD -i wg0 -j ACCEPT
PostDown = iptables -D FORWARD -o wg0 -j ACCEPT
PostDown = iptables -t nat -D POSTROUTING -o eth0 -j MASQUERADE

# Client A
[Peer]
PublicKey = <CLIENT_A_PUBKEY>
AllowedIPs = 10.0.0.2/32

# Client B
[Peer]
PublicKey = <CLIENT_B_PUBKEY>
AllowedIPs = 10.0.0.3/32
```

> **Note:** Replace `eth0` with your actual network interface name (check with `ip a`). On Proxmox VMs this is often `ens18` or `enp0s3`.

### Step 1.4 — Configure Client A

Create `/etc/wireguard/wg0.conf` on **Client A**:

```ini
[Interface]
Address = 10.0.0.2/24
PrivateKey = <CLIENT_A_PRIVKEY>

[Peer]
PublicKey = <SERVER_PUBKEY>
Endpoint = <SERVER_PROXMOX_IP>:51820
AllowedIPs = 10.0.0.0/24
PersistentKeepalive = 25
```

Replace `<SERVER_PROXMOX_IP>` with the server VM's IP on the Proxmox bridge (e.g., `192.168.1.100`). Later, when moving to EC2, this becomes the EC2 public IP.

### Step 1.5 — Configure Client B

Create `/etc/wireguard/wg0.conf` on **Client B**:

```ini
[Interface]
Address = 10.0.0.3/24
PrivateKey = <CLIENT_B_PRIVKEY>

[Peer]
PublicKey = <SERVER_PUBKEY>
Endpoint = <SERVER_PROXMOX_IP>:51820
AllowedIPs = 10.0.0.0/24
PersistentKeepalive = 25
```

### Step 1.6 — Start WireGuard and Enable on Boot

On **all three machines**:

```bash
sudo systemctl enable wg-quick@wg0
sudo systemctl start wg-quick@wg0
```

Check the interface is up:

```bash
sudo wg show
```

### Step 1.7 — Test Connectivity

From **Client A**, test connectivity to the server and Client B:

```bash
ping -c 4 10.0.0.1   # Server
ping -c 4 10.0.0.3   # Client B
```

From **Client B**, test the reverse:

```bash
ping -c 4 10.0.0.1   # Server
ping -c 4 10.0.0.2   # Client A
```

From the **Server**, test both clients:

```bash
ping -c 4 10.0.0.2   # Client A
ping -c 4 10.0.0.3   # Client B
```

If all pings succeed, Phase 1 is complete. WireGuard is routing traffic between both clients through the server.

### Phase 1 Troubleshooting

If pings fail, check the following:

```bash
# Verify the WireGuard interface is up
ip a show wg0

# Check for handshake — if "latest handshake" is missing, keys or endpoints are wrong
sudo wg show

# Verify IP forwarding is enabled on the server
sysctl net.ipv4.ip_forward

# Check iptables rules are in place on the server
sudo iptables -L FORWARD -v
sudo iptables -t nat -L POSTROUTING -v

# Check for firewall rules blocking UDP 51820
sudo ufw status
```

Common issues:

- **No handshake on `wg show`**: Public/private keys are mismatched. Double-check that each peer's `PublicKey` matches the other machine's actual public key.
- **Handshake exists but no ping**: IP forwarding is not enabled on the server, or iptables FORWARD rules are missing.
- **Client-to-client fails but client-to-server works**: The `AllowedIPs` on the clients must include `10.0.0.0/24` (the whole subnet), not just the server's IP. This tells WireGuard to route all VPN subnet traffic through the tunnel.

---

## Phase 2: WebSocket Wrapping with wstunnel

Now that WireGuard works over plain UDP, wrap it in WebSocket so it can traverse restrictive firewalls that block UDP.

### How It Works

```
Client A WireGuard
    │
    ▼ UDP to 127.0.0.1:51821
wstunnel client (TCP 443) ──────────► wstunnel server (TCP 443)
                                            │
                                            ▼ UDP to 127.0.0.1:51820
                                       Server WireGuard
```

Each client's WireGuard talks to a local `wstunnel` process via localhost UDP. That process wraps the packets in a WebSocket connection to the server, where the server-side `wstunnel` unwraps them and delivers to WireGuard.

### Step 2.1 — Install wstunnel on All Three Machines

Download the latest release from the [wstunnel GitHub releases page](https://github.com/erebe/wstunnel/releases). Pick the appropriate binary for your architecture (likely `linux_amd64`).

```bash
# Check the latest version at https://github.com/erebe/wstunnel/releases
# Replace the URL below with the latest release URL
WSTUNNEL_VERSION="10.1.6"
wget https://github.com/erebe/wstunnel/releases/download/v${WSTUNNEL_VERSION}/wstunnel_${WSTUNNEL_VERSION}_linux_amd64.tar.gz
tar -xzf wstunnel_${WSTUNNEL_VERSION}_linux_amd64.tar.gz
sudo mv wstunnel /usr/local/bin/
sudo chmod +x /usr/local/bin/wstunnel
```

Verify:

```bash
wstunnel --version
```

> **Note:** Check the releases page for the latest version. The command syntax may differ between major versions. This guide uses v10.x syntax. If you are using an older version, consult the wstunnel README for the correct flags.

### Step 2.2 — Configure wstunnel Server

On the **server**, create a systemd service for wstunnel. This will listen on TCP 443 and forward incoming tunnelled packets to the local WireGuard port (UDP 51820).

Create `/etc/systemd/system/wstunnel-server.service`:

```ini
[Unit]
Description=wstunnel server
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/local/bin/wstunnel server \
    ws://0.0.0.0:443
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
```

Enable and start:

```bash
sudo systemctl daemon-reload
sudo systemctl enable wstunnel-server
sudo systemctl start wstunnel-server
sudo systemctl status wstunnel-server
```

### Step 2.3 — Configure wstunnel on Client A

On **Client A**, create `/etc/systemd/system/wstunnel-client.service`:

```ini
[Unit]
Description=wstunnel client for WireGuard
After=network-online.target
Wants=network-online.target
Before=wg-quick@wg0.service

[Service]
Type=simple
ExecStart=/usr/local/bin/wstunnel client \
    --local-to-remote udp://127.0.0.1:51821:127.0.0.1:51820 \
    ws://<SERVER_PROXMOX_IP>:443
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
```

This tells wstunnel to:

1. Listen for UDP on `127.0.0.1:51821` (where local WireGuard will send packets)
2. Wrap them in a WebSocket connection to the server on port 443
3. On the server side, deliver them to `127.0.0.1:51820` (where WireGuard listens)

Enable and start:

```bash
sudo systemctl daemon-reload
sudo systemctl enable wstunnel-client
sudo systemctl start wstunnel-client
sudo systemctl status wstunnel-client
```

### Step 2.4 — Configure wstunnel on Client B

Same as Client A. Create `/etc/systemd/system/wstunnel-client.service` on **Client B**:

```ini
[Unit]
Description=wstunnel client for WireGuard
After=network-online.target
Wants=network-online.target
Before=wg-quick@wg0.service

[Service]
Type=simple
ExecStart=/usr/local/bin/wstunnel client \
    --local-to-remote udp://127.0.0.1:51821:127.0.0.1:51820 \
    ws://<SERVER_PROXMOX_IP>:443
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
```

Enable and start:

```bash
sudo systemctl daemon-reload
sudo systemctl enable wstunnel-client
sudo systemctl start wstunnel-client
```

### Step 2.5 — Update WireGuard Client Configs

Now update the WireGuard configs on **both clients** to point at the local wstunnel endpoint instead of the server directly.

On **Client A**, edit `/etc/wireguard/wg0.conf`:

```ini
[Interface]
Address = 10.0.0.2/24
PrivateKey = <CLIENT_A_PRIVKEY>

[Peer]
PublicKey = <SERVER_PUBKEY>
Endpoint = 127.0.0.1:51821
AllowedIPs = 10.0.0.0/24
PersistentKeepalive = 25
```

On **Client B**, edit `/etc/wireguard/wg0.conf`:

```ini
[Interface]
Address = 10.0.0.3/24
PrivateKey = <CLIENT_B_PRIVKEY>

[Peer]
PublicKey = <SERVER_PUBKEY>
Endpoint = 127.0.0.1:51821
AllowedIPs = 10.0.0.0/24
PersistentKeepalive = 25
```

The key change: `Endpoint` now points to `127.0.0.1:51821` (the local wstunnel listener) instead of the server's IP directly.

### Step 2.6 — Restart WireGuard on Clients

```bash
sudo systemctl restart wg-quick@wg0
```

### Step 2.7 — Test Connectivity Again

Repeat the same ping tests from Phase 1:

```bash
# From Client A
ping -c 4 10.0.0.1   # Server
ping -c 4 10.0.0.3   # Client B (routed through server)

# From Client B
ping -c 4 10.0.0.1   # Server
ping -c 4 10.0.0.2   # Client A (routed through server)
```

### Phase 2 Troubleshooting

```bash
# Check wstunnel service is running
sudo systemctl status wstunnel-client   # on clients
sudo systemctl status wstunnel-server   # on server

# Check wstunnel logs
sudo journalctl -u wstunnel-client -f   # on clients
sudo journalctl -u wstunnel-server -f   # on server

# Verify wstunnel is listening
ss -tlnp | grep 443    # on server (TCP)
ss -ulnp | grep 51821  # on clients (UDP)

# Verify WireGuard handshake is still happening
sudo wg show
```

Common issues:

- **wstunnel fails to bind port 443**: Another service (like Apache or Nginx) is using port 443. Either stop it or use a different port (e.g., 8443) and update both server and client configs.
- **No WireGuard handshake after switching to WebSocket**: wstunnel client is not running, or the `--local-to-remote` mapping is incorrect. Check that UDP 51821 is the local listen port and UDP 51820 is the remote delivery port.
- **Connection refused on port 443**: Firewall is blocking TCP 443 on the server. Open it with `sudo ufw allow 443/tcp`.

---

## Phase 3: Migrating the Server to AWS EC2

Once everything works in Proxmox, migrating the server to EC2 is straightforward.

### Step 3.1 — Launch an EC2 Instance

Launch an Ubuntu 22.04+ instance. A `t3.micro` or `t3.small` is sufficient for a VPN relay.

### Step 3.2 — Configure the Security Group

If you are still using Phase 1 (WireGuard only, no WebSocket):

| Type | Protocol | Port | Source |
|---|---|---|---|
| Custom UDP | UDP | 51820 | 0.0.0.0/0 (or restrict to client IPs) |
| SSH | TCP | 22 | Your IP |

If you have completed Phase 2 (WebSocket wrapping):

| Type | Protocol | Port | Source |
|---|---|---|---|
| HTTPS | TCP | 443 | 0.0.0.0/0 (or restrict to client IPs) |
| SSH | TCP | 22 | Your IP |

You can remove the UDP 51820 rule once WebSocket is confirmed working, since all WireGuard traffic flows over TCP 443.

### Step 3.3 — Install and Configure on EC2

SSH into the EC2 instance and repeat the server setup:

1. Install WireGuard (Step 1.1)
2. Copy or regenerate keys (Step 1.2) — if you regenerate, update the `PublicKey` on both clients
3. Copy the server's `wg0.conf` (Step 1.3) — update the interface name in PostUp/PostDown rules (EC2 typically uses `ens5` or `enX0`)
4. Install and start wstunnel server (Steps 2.1 and 2.2)

### Step 3.4 — Update Client Endpoints

On both clients, update the wstunnel client service to point to the EC2 public IP:

```bash
# Edit /etc/systemd/system/wstunnel-client.service
# Change ws://<SERVER_PROXMOX_IP>:443 to ws://<EC2_PUBLIC_IP>:443
sudo systemctl daemon-reload
sudo systemctl restart wstunnel-client
sudo systemctl restart wg-quick@wg0
```

### Step 3.5 — Verify

Run the same connectivity tests. If using an Elastic IP on the EC2 instance, the endpoint will remain stable across instance stop/start cycles.

---

## Optional Enhancements

### TLS Encryption for wstunnel

For production, use `wss://` (WebSocket Secure) instead of `ws://` to encrypt the WebSocket layer. While WireGuard already encrypts the payload, TLS makes the traffic look like normal HTTPS to deep packet inspection.

On the server, you can either:

- Terminate TLS directly in wstunnel using a certificate (e.g., from Let's Encrypt)
- Place wstunnel behind a reverse proxy like Nginx or Caddy that handles TLS

Example with wstunnel native TLS:

```bash
# Server
wstunnel server \
    wss://0.0.0.0:443 \
    --tls-certificate /etc/letsencrypt/live/yourdomain.com/fullchain.pem \
    --tls-private-key /etc/letsencrypt/live/yourdomain.com/privkey.pem

# Clients
wstunnel client \
    --local-to-remote udp://127.0.0.1:51821:127.0.0.1:51820 \
    wss://<SERVER_IP_OR_DOMAIN>:443
```

### Monitoring with Prometheus + Grafana

Since you already have Grafana in your home lab, you can monitor the WireGuard interfaces:

- **prometheus-wireguard-exporter** exposes peer metrics (handshake time, bytes transferred, last handshake)
- Add a Grafana dashboard to visualise tunnel health and throughput across all three nodes

### DNS Resolution over the Tunnel

If you want the clients to resolve internal DNS through the VPN, add to each client's `wg0.conf`:

```ini
[Interface]
DNS = 10.0.0.1
```

Then run a lightweight DNS server (like `dnsmasq` or `systemd-resolved`) on the server.

---

## Quick Reference: Service Management

```bash
# WireGuard
sudo systemctl start wg-quick@wg0
sudo systemctl stop wg-quick@wg0
sudo systemctl restart wg-quick@wg0
sudo wg show

# wstunnel
sudo systemctl start wstunnel-server    # server only
sudo systemctl start wstunnel-client    # clients only
sudo journalctl -u wstunnel-server -f   # server logs
sudo journalctl -u wstunnel-client -f   # client logs
```

## Startup Order

On the clients, services should start in this order:

1. **wstunnel-client** — establishes the WebSocket tunnel
2. **wg-quick@wg0** — brings up WireGuard, which connects through the tunnel

The systemd `Before=wg-quick@wg0.service` in the wstunnel unit file handles this. On the server, the order does not matter since wstunnel and WireGuard listen independently.
