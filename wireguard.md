# WireGuard VPN Setup on AWS EC2 (Windows Client)

A step-by-step guide to setting up a WireGuard VPN server on an AWS EC2 instance with a Windows laptop as the client.

---

## 1. Launch and Prepare the EC2 Instance

Launch an EC2 instance with **Ubuntu 22.04/24.04** (Amazon Linux 2023 also works). A `t3.micro` or `t3.nano` is sufficient for a personal VPN.

**Configure the Security Group** to allow:

| Protocol | Port  | Source        | Purpose    |
|----------|-------|---------------|------------|
| UDP      | 51820 | 0.0.0.0/0 *  | WireGuard  |
| TCP      | 22    | Your IP       | SSH        |

> \* For tighter security, restrict to your home IP.

**Allocate an Elastic IP** and associate it with your instance so the public IP doesn't change on reboot.

SSH into your instance:

```bash
ssh -i your-key.pem ubuntu@<ELASTIC_IP>
```

---

## 2. Install WireGuard on the EC2 Instance

```bash
sudo apt update && sudo apt upgrade -y
sudo apt install wireguard -y
```

---

## 3. Generate Server Keys

```bash
wg genkey | tee /tmp/server_private.key | wg pubkey > /tmp/server_public.key
```

Note both keys:

```bash
cat /tmp/server_private.key
cat /tmp/server_public.key
```

---

## 4. Generate Client Keys

Generate on the server for convenience:

```bash
wg genkey | tee /tmp/client_private.key | wg pubkey > /tmp/client_public.key
```

Note both keys:

```bash
cat /tmp/client_private.key
cat /tmp/client_public.key
```

---

## 5. Create the Server Configuration

```bash
sudo nano /etc/wireguard/wg0.conf
```

Paste the following, replacing the placeholder values:

```ini
[Interface]
Address = 10.0.0.1/24
ListenPort = 51820
PrivateKey = <SERVER_PRIVATE_KEY>

# NAT / forwarding rules
PostUp = iptables -A FORWARD -i wg0 -j ACCEPT; iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
PostDown = iptables -D FORWARD -i wg0 -j ACCEPT; iptables -t nat -D POSTROUTING -o eth0 -j MASQUERADE

[Peer]
# Windows client
PublicKey = <CLIENT_PUBLIC_KEY>
AllowedIPs = 10.0.0.2/32
```

> **Important:** Check your network interface name with `ip a`. It's usually `eth0` on EC2, but could be `ens5` or `enX0` on newer instance types. Replace `eth0` in the PostUp/PostDown lines accordingly.

---

## 6. Enable IP Forwarding

```bash
echo "net.ipv4.ip_forward = 1" | sudo tee -a /etc/sysctl.conf
sudo sysctl -p
```

---

## 7. Start WireGuard on the Server

```bash
sudo systemctl enable wg-quick@wg0
sudo systemctl start wg-quick@wg0
```

Verify it's running:

```bash
sudo wg show
```

---

## 8. Install WireGuard on Your Windows Laptop

Download and install from: [https://www.wireguard.com/install/](https://www.wireguard.com/install/) (grab the Windows installer).

---

## 9. Create the Client Configuration

Open the WireGuard Windows app, click **Add Tunnel → Add empty tunnel**, and paste this configuration:

```ini
[Interface]
PrivateKey = <CLIENT_PRIVATE_KEY>
Address = 10.0.0.2/24
DNS = 1.1.1.1, 8.8.8.8

[Peer]
PublicKey = <SERVER_PUBLIC_KEY>
Endpoint = <ELASTIC_IP>:51820
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 25
```

### AllowedIPs Explained

| Value         | Mode         | Use Case                                      |
|---------------|--------------|-----------------------------------------------|
| `0.0.0.0/0`  | Full tunnel  | Routes **all** traffic through VPN (privacy)   |
| `10.0.0.0/24` | Split tunnel | Routes **only** VPN subnet traffic (selective) |

---

## 10. Connect and Verify

1. Click **Activate** in the WireGuard Windows app.
2. On the server, check the connection:

```bash
sudo wg show
```

You should see a `latest handshake` timestamp and data transfer stats for the peer.

3. On your Windows laptop, visit [https://whatismyipaddress.com](https://whatismyipaddress.com) — it should show your EC2 Elastic IP if using full tunnel mode.

---

## Troubleshooting

| Symptom | Check |
|---------|-------|
| No handshake | EC2 Security Group allows UDP 51820 inbound; Endpoint IP and port are correct in client config |
| Handshake works but no internet | IP forwarding enabled (`sysctl net.ipv4.ip_forward` returns `1`); PostUp iptables rules reference the correct interface |
| DNS not resolving | Change DNS in client config to `8.8.8.8` or your preferred resolver |
| Key mismatch | Server config needs the **client's public** key; client config needs the **server's public** key |

---

## Adding More Clients

For each new client:

1. Generate a new key pair.
2. Add a `[Peer]` block to `/etc/wireguard/wg0.conf` with a unique IP (e.g., `10.0.0.3/32`).
3. Restart WireGuard:

```bash
sudo systemctl restart wg-quick@wg0
```

---

## Quick Reference

| Item | Value |
|------|-------|
| VPN Subnet | `10.0.0.0/24` |
| Server VPN IP | `10.0.0.1` |
| Client VPN IP | `10.0.0.2` |
| WireGuard Port | `51820/UDP` |
| Protocol | UDP only |
