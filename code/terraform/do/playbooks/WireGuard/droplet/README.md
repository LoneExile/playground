# WireGuard VPN Droplet - Central Hub

This configuration creates a minimal DigitalOcean droplet for running WireGuard VPN as a **Central Hub** to connect multiple devices.

## Architecture

```
Third Device (10.0.0.3) <-> VPS Central Hub (10.0.0.1) <-> Local Server (10.0.0.2)
```

The VPS acts as a central hub, routing traffic between all connected peers.

## Specifications

- **Size**: s-1vcpu-1gb (1 vCPU, 1GB RAM, 25GB SSD)
- **OS**: Ubuntu 24.04 LTS
- **Region**: sgp1 (Singapore)
- **Cost**: ~$6/month
- **Network**: 10.0.0.0/24 (VPS uses 10.0.0.1)

## Automated Setup

**WireGuard is automatically installed and configured during droplet creation** via cloud-init user-data script. The setup includes:

- ✅ WireGuard and tools installation
- ✅ Server key generation
- ✅ Central hub configuration with IP forwarding
- ✅ iptables NAT rules for routing
- ✅ Helper scripts for peer management
- ✅ Setup logging to `/var/log/wireguard-setup.log`

## Prerequisites

Before deploying, ensure your SSH key is configured in `terragrunt.hcl`:

```bash
# Get your SSH key ID
doctl compute ssh-key list

# Update terragrunt.hcl line 35
ssh_keys = ["51735948"]  # Replace with your key ID
```

## Firewall Rules

**Inbound:**
- Port 22 (TCP) - SSH access
- Port 51820 (UDP) - WireGuard VPN

**Outbound:**
- All traffic allowed

## Deployment

1. **Ensure VPC is created first:**
   ```bash
   cd ../vpc
   source ../.env
   tg apply
   ```

2. **Deploy the WireGuard droplet:**
   ```bash
   cd ../droplet
   source ../.env
   tg plan    # Review the plan
   tg apply   # Deploy the droplet
   ```

3. **Wait for cloud-init to complete** (~2-3 minutes)

4. **Get the droplet IP address:**
   ```bash
   tg output
   ```

## Post-Deployment Setup

### 1. Verify Installation

SSH into the droplet and check installation status:

```bash
ssh root@<droplet-ip>

# Check if installation completed
./check-status.sh

# Or check completion indicator
cat /root/WIREGUARD-INSTALL-COMPLETE

# View setup information
./wireguard-info.sh
```

### 2. Add Peers

Use the automated peer management script:

```bash
# Add local server (10.0.0.2)
wg-add-peer.sh local-server 10.0.0.2

# Add third device (10.0.0.3)
wg-add-peer.sh third-device 10.0.0.3

# Add more peers as needed
wg-add-peer.sh laptop 10.0.0.4
```

This script automatically:
- Generates peer keys
- Adds peer to server configuration
- Creates client configuration file
- Reloads WireGuard if running

### 3. Start WireGuard

```bash
systemctl enable wg-quick@wg0
systemctl start wg-quick@wg0
systemctl status wg-quick@wg0
```

### 4. Get Client Configurations

```bash
# View client config
cat /etc/wireguard/local-server-client.conf
cat /etc/wireguard/third-device-client.conf

# Generate QR code for mobile devices
qrencode -t ansiutf8 < /etc/wireguard/third-device-client.conf
```

## Client Configuration Example

The generated client configurations will look like this:

```ini
[Interface]
PrivateKey = <peer_private_key>
Address = 10.0.0.2/24
DNS = 1.1.1.1, 8.8.8.8

[Peer]
PublicKey = <vps_public_key>
Endpoint = <droplet_ip>:51820
AllowedIPs = 10.0.0.0/24
PersistentKeepalive = 25
```

**Note**: `AllowedIPs = 10.0.0.0/24` routes only VPN traffic through the tunnel. To route all internet traffic, use `AllowedIPs = 0.0.0.0/0, ::/0`

## Advanced: Accessing LAN Networks Behind Peers

If your local server (10.0.0.2) is on a private LAN (e.g., 192.168.50.0/24) and you want to access devices on that LAN from your third device, follow these steps:

### Scenario

```
Third Device (MacBook) -> VPS (10.0.0.1) -> Local Server (10.0.0.2) -> LAN (192.168.50.0/24)
                                                                         └─ Harbor: 192.168.50.51
```

### Step 1: Configure Local Server for LAN Routing

**On local server (via WGDashboard or direct config edit):**

Edit the WireGuard configuration to enable IP forwarding and NAT:

```ini
[Interface]
PrivateKey = <your-private-key>
Address = 10.0.0.2/24

# Enable IP forwarding and NAT for LAN access
PostUp = sysctl -w net.ipv4.ip_forward=1
PostUp = iptables -A FORWARD -i wg0 -j ACCEPT
PostUp = iptables -A FORWARD -o wg0 -j ACCEPT
PostUp = iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
PostDown = iptables -D FORWARD -i wg0 -j ACCEPT
PostDown = iptables -D FORWARD -o wg0 -j ACCEPT
PostDown = iptables -t nat -D POSTROUTING -o eth0 -j MASQUERADE

[Peer]
PublicKey = <vps-public-key>
Endpoint = <vps-ip>:51820
AllowedIPs = 10.0.0.0/24
PersistentKeepalive = 25
```

**Important**: Replace `eth0` with your actual network interface. Find it with:
```bash
ip route | grep default
```

### Step 2: Update VPS to Route LAN Subnet

**On VPS, edit `/etc/wireguard/wg0.conf`:**

Find the local-server peer section and add the LAN subnet to `AllowedIPs`:

```ini
# Peer: local-server
[Peer]
PublicKey = <local-server-public-key>
AllowedIPs = 10.0.0.2/32, 192.168.50.0/24  # Added LAN subnet
PersistentKeepalive = 25
```

Reload WireGuard:
```bash
wg syncconf wg0 <(wg-quick strip wg0)
```

### Step 3: Update Third Device Config

**On your MacBook/third device, edit the WireGuard config:**

Add the LAN subnet to `AllowedIPs`:

```ini
[Interface]
PrivateKey = <your-private-key>
Address = 10.0.0.3/24
DNS = 1.1.1.1, 8.8.8.8

[Peer]
PublicKey = <vps-public-key>
Endpoint = <vps-ip>:51820
AllowedIPs = 10.0.0.0/24, 192.168.50.0/24  # Added LAN subnet
PersistentKeepalive = 25
```

Deactivate and reactivate the tunnel for changes to take effect.

### Step 4: Configure DNS/Hosts (Optional)

For accessing services by hostname (e.g., `harbor.voidbox.io`):

**On MacBook:**
```bash
sudo nano /etc/hosts
```

Add:
```
192.168.50.51 harbor.voidbox.io
```

### Step 5: Test

```bash
# From MacBook, test LAN access
ping 192.168.50.51

# Test Harbor access
curl http://192.168.50.51
# or open in browser: http://harbor.voidbox.io
```

### Alternative: Reverse Proxy Approach

If you don't want to route the entire LAN subnet, use a reverse proxy on the local server:

**Install nginx on local server:**
```bash
sudo apt install nginx -y
```

**Create proxy config:**
```bash
sudo nano /etc/nginx/sites-available/harbor-proxy
```

```nginx
server {
    listen 10.0.0.2:80;
    server_name harbor.voidbox.io;

    location / {
        proxy_pass http://192.168.50.51;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

Enable and reload:
```bash
sudo ln -s /etc/nginx/sites-available/harbor-proxy /etc/nginx/sites-enabled/
sudo nginx -t
sudo systemctl reload nginx
```

**On MacBook `/etc/hosts`:**
```
10.0.0.2 harbor.voidbox.io
```

Access via: `http://harbor.voidbox.io`

### Common Issues with LAN Routing

**Can't access LAN devices:**
- Verify IP forwarding is enabled on local server: `cat /proc/sys/net/ipv4/ip_forward` (should be 1)
- Check iptables rules on local server: `sudo iptables -L -n -v`
- Verify VPS has the LAN subnet in AllowedIPs
- Check that local server's network interface name is correct in PostUp/PostDown rules

**DNS resolution not working:**
- If using WGDashboard, ensure `resolvconf` or `openresolv` is installed
- Or remove DNS line from config and use `/etc/hosts` instead

## Key Files and Scripts

- **Server config**: `/etc/wireguard/wg0.conf`
- **Server keys**: `/etc/wireguard/vps-private.key`, `/etc/wireguard/vps-public.key`
- **Client configs**: `/etc/wireguard/*-client.conf`
- **Add peer script**: `/usr/local/bin/wg-add-peer.sh`
- **Setup info**: `/root/wireguard-info.sh`
- **Status check**: `/root/check-status.sh`
- **Installation log**: `/var/log/wireguard-setup.log`
- **Completion indicator**: `/root/WIREGUARD-INSTALL-COMPLETE`

## Troubleshooting

### Check Installation Status

```bash
# Quick status check
./check-status.sh

# View installation logs
tail -f /var/log/wireguard-setup.log

# Check if WireGuard is running
systemctl status wg-quick@wg0
wg show
```

### Common Issues

**SSH connection refused:**
- Wait 2-3 minutes for cloud-init to complete
- Check firewall allows port 22

**WireGuard not working:**
```bash
# Check if interface is up
ip addr show wg0

# Verify IP forwarding
sysctl net.ipv4.ip_forward

# Check iptables rules
iptables -L -n -v
iptables -t nat -L -n -v

# Test connectivity between peers
ping 10.0.0.2  # From VPS to peer
```

**Cloud-init failed:**
```bash
# Check cloud-init status
cloud-init status

# View cloud-init logs
cat /var/log/cloud-init-output.log
tail -f /var/log/wireguard-setup.log
```

**IPv6 endpoint issues:**
If the auto-generated client configs have IPv6 endpoints, you may need to use IPv4 instead:
```bash
# On VPS, get IPv4 address
curl -4 ifconfig.me

# Edit client config and change Endpoint from:
# Endpoint = 2400:6180:0:d2:0:2:5d43:0:51820  ❌
# To:
# Endpoint = <IPv4-address>:51820  ✅
```

**WGDashboard resolvconf error:**
If you get `/usr/bin/wg-quick: line 32: resolvconf: command not found`:
```bash
# Install resolvconf or openresolv
sudo apt install resolvconf -y
# OR
sudo apt install openresolv -y

# Or remove DNS line from config
```

## Monitoring

The droplet has monitoring enabled. You can view metrics in the DigitalOcean dashboard:
- CPU usage
- Memory usage
- Disk I/O
- Network traffic

## Backup

Backups are currently disabled to save costs. To enable:

1. Edit `terragrunt.hcl` line 41:
   ```hcl
   backups = true
   ```

2. Apply the changes:
   ```bash
   tg apply
   ```

## Scaling

If you need more resources:

1. Update the `size` in `terragrunt.hcl` line 19:
   ```hcl
   size = "s-2vcpu-2gb"  # or larger
   ```

2. Apply the changes (requires droplet restart):
   ```bash
   tg apply
   ```

## Destroy

To delete the droplet:

```bash
tg destroy
```

---
