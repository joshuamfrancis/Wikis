# WireGuard over wstunnel (TCP 443) on AWS EC2

## Overview

This guide sets up a WireGuard VPN tunneled through wstunnel over TCP 443 using an AWS EC2 RHEL instance as the server. Two RHEL clients connect to each other through this tunnel.

**Architecture:**

```
Client A ↔ (wstunnel TCP 443) ↔ EC2 Server ↔ (wstunnel TCP 443) ↔ Client B
```

WireGuard runs UDP locally on each machine. wstunnel wraps it in a WebSocket over TCP 443, allowing traversal of restrictive firewalls and NATs. The only externally exposed port is **TCP 443**.

---

## Network Plan

| Node       | WireGuard IP | WireGuard Port (local UDP) |
| ---------- | ------------ | -------------------------- |
| EC2 Server | 10.0.0.1/24  | 51820                      |
| Client A   | 10.0.0.2/24  | 51820                      |
| Client B   | 10.0.0.3/24  | 51820                      |

---

## 1. EC2 Server Setup

### 1a. AWS Security Group

Open **TCP 443** inbound from `0.0.0.0/0` (or restrict to your client IPs). You do **not** need to open UDP 51820 externally — wstunnel handles that internally.

### 1b. Install WireGuard and wstunnel

```bash
# Enable EPEL repository (required for WireGuard on RHEL)
sudo dnf install -y epel-release
sudo dnf install -y wireguard-tools

# Install wstunnel (check https://github.com/erebe/wstunnel/releases for latest)
WSTUNNEL_VERSION="v10.1.0"
wget "https://github.com/erebe/wstunnel/releases/download/${WSTUNNEL_VERSION}/wstunnel_${WSTUNNEL_VERSION}_linux_amd64.tar.gz"
tar xzf wstunnel_*.tar.gz
sudo mv wstunnel /usr/local/bin/
sudo chmod +x /usr/local/bin/wstunnel
# Allow wstunnel to bind to privileged ports under SELinux
sudo semanage permissive -a bin_t 2>/dev/null || true
```

### 1c. Generate WireGuard Keys

```bash
wg genkey | tee server_private.key | wg pubkey > server_public.key
cat server_private.key
cat server_public.key
```

Save these — you will need the public key on both clients.

### 1d. WireGuard Config

```bash
sudo tee /etc/wireguard/wg0.conf << 'EOF'
[Interface]
Address = 10.0.0.1/24
ListenPort = 51820
PrivateKey = <SERVER_PRIVATE_KEY>

# Enable forwarding between peers so Client A <-> Client B works
PostUp = firewall-cmd --add-interface=wg0 --zone=trusted && firewall-cmd --direct --add-rule ipv4 filter FORWARD 0 -i wg0 -o wg0 -j ACCEPT
PostDown = firewall-cmd --remove-interface=wg0 --zone=trusted && firewall-cmd --direct --remove-rule ipv4 filter FORWARD 0 -i wg0 -o wg0 -j ACCEPT

[Peer]
# Client A
PublicKey = <CLIENT_A_PUBLIC_KEY>
AllowedIPs = 10.0.0.2/32

[Peer]
# Client B
PublicKey = <CLIENT_B_PUBLIC_KEY>
AllowedIPs = 10.0.0.3/32
EOF
```

### 1e. Firewall and SELinux

Open TCP 443 in firewalld for wstunnel:

```bash
sudo firewall-cmd --permanent --add-port=443/tcp
sudo firewall-cmd --reload
```

If SELinux is enforcing and wstunnel fails to bind, allow it:

```bash
# Check SELinux status
getenforce

# If enforcing, either set wstunnel permissive or create a policy
# Quick fix — set permissive for the binary context:
sudo semanage permissive -a bin_t

# Or generate a custom policy after a denial (preferred long-term):
# sudo ausearch -m avc -ts recent | audit2allow -M wstunnel_policy
# sudo semodule -i wstunnel_policy.pp
```

### 1f. Enable IP Forwarding

```bash
echo 'net.ipv4.ip_forward = 1' | sudo tee -a /etc/sysctl.d/99-wireguard.conf
sudo sysctl -p /etc/sysctl.d/99-wireguard.conf
```

### 1g. Start WireGuard

```bash
sudo systemctl enable --now wg-quick@wg0
```

### 1h. Run wstunnel Server

wstunnel listens on TCP 443 and forwards incoming WebSocket traffic to the local WireGuard UDP port:

```bash
sudo wstunnel server --restrict-to 127.0.0.1:51820 wss://0.0.0.0:443
```

#### Systemd Service (recommended for production)

```bash
sudo tee /etc/systemd/system/wstunnel-server.service << 'EOF'
[Unit]
Description=wstunnel server
After=network.target

[Service]
ExecStart=/usr/local/bin/wstunnel server --restrict-to 127.0.0.1:51820 wss://0.0.0.0:443
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl enable --now wstunnel-server.service
```

> **Note on TLS:** `wss://` mode uses a self-signed certificate by default. For a proper cert, you can place it behind an nginx reverse proxy with Let's Encrypt, or pass `--tls-certificate` and `--tls-private-key` flags to wstunnel. For a private tunnel, self-signed works fine — just use `--tls-verify-certificate=false` on the clients.

---

## 2. Client A Setup

### 2a. Install WireGuard and wstunnel

Same installation steps as [1b](#1b-install-wireguard-and-wstunnel) above (EPEL + dnf + wstunnel binary).

### 2b. Generate Keys

```bash
wg genkey | tee clientA_private.key | wg pubkey > clientA_public.key
```

### 2c. WireGuard Config

```bash
sudo tee /etc/wireguard/wg0.conf << 'EOF'
[Interface]
Address = 10.0.0.2/24
PrivateKey = <CLIENT_A_PRIVATE_KEY>

[Peer]
PublicKey = <SERVER_PUBLIC_KEY>
Endpoint = 127.0.0.1:51820
AllowedIPs = 10.0.0.0/24
PersistentKeepalive = 25
EOF
```

The endpoint is `127.0.0.1:51820` because wstunnel exposes the remote WireGuard port locally.

### 2d. Run wstunnel Client

```bash
wstunnel client \
  --local-to-remote 'udp://127.0.0.1:51820:127.0.0.1:51820?timeout-sec=0' \
  --tls-verify-certificate=false \
  wss://<EC2_PUBLIC_IP>:443
```

This binds a local UDP listener on `127.0.0.1:51820` that tunnels to the server's `127.0.0.1:51820` over the WebSocket on TCP 443. The `timeout-sec=0` keeps the UDP tunnel alive indefinitely.

#### Systemd Service

```bash
sudo tee /etc/systemd/system/wstunnel-client.service << 'EOF'
[Unit]
Description=wstunnel client
After=network-online.target
Wants=network-online.target

[Service]
ExecStart=/usr/local/bin/wstunnel client \
  --local-to-remote 'udp://127.0.0.1:51820:127.0.0.1:51820?timeout-sec=0' \
  --tls-verify-certificate=false \
  wss://<EC2_PUBLIC_IP>:443
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl enable --now wstunnel-client.service
```

### 2e. Start WireGuard

```bash
sudo systemctl enable --now wg-quick@wg0
```

---

## 3. Client B Setup

Identical to Client A, with these differences:

- Use Client B's own private key
- Set `Address = 10.0.0.3/24` in `wg0.conf`
- Everything else (wstunnel command, endpoint, etc.) remains the same

---

## 4. Startup Order

On every machine, the order matters:

1. **wstunnel** first — the UDP tunnel must be available
2. **WireGuard** second — it needs to send packets through the tunnel

To enforce this with systemd on the clients, override the WireGuard service:

```bash
sudo systemctl edit wg-quick@wg0
```

Add:

```ini
[Unit]
After=wstunnel-client.service
Requires=wstunnel-client.service
```

---

## 5. Verification

From **Client A**:

```bash
# Ping the server
ping 10.0.0.1

# Ping Client B through the tunnel
ping 10.0.0.3

# Check WireGuard handshake status
sudo wg show
```

From **Client B**:

```bash
ping 10.0.0.1
ping 10.0.0.2
sudo wg show
```

You should see recent handshakes and traffic flowing in `wg show`.

---

## 6. Troubleshooting

| Symptom                                  | Check                                                                                                          |
| ---------------------------------------- | -------------------------------------------------------------------------------------------------------------- |
| No WireGuard handshake                   | Is wstunnel running? `ss -tlnp \| grep 443` on server, `ss -ulnp \| grep 51820` on client                    |
| Handshake OK but no ping between clients | IP forwarding enabled on server? `sysctl net.ipv4.ip_forward`. firewalld FORWARD rule present? Check `firewall-cmd --list-all --zone=trusted` |
| wstunnel connection refused              | Security group allows TCP 443? EC2 instance has a public IP? firewalld allows 443/tcp? `firewall-cmd --list-ports` |
| wstunnel permission denied on bind       | SELinux blocking? Check `ausearch -m avc -ts recent`. See section 1e for SELinux workarounds                   |
| Intermittent drops                       | Ensure `PersistentKeepalive = 25` is set in WireGuard config and `timeout-sec=0` is set in wstunnel client     |
