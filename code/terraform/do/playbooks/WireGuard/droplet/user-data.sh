#!/bin/bash
set -euo pipefail

# Log everything
exec > >(tee -a /var/log/wireguard-setup.log)
exec 2>&1

echo "Starting WireGuard setup at $(date)"

# Set non-interactive frontend for apt
export DEBIAN_FRONTEND=noninteractive

# Update package lists only (don't upgrade - it's slow and can cause issues)
apt-get update

# Install WireGuard and tools
apt-get install -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" \
  wireguard wireguard-tools qrencode htop curl

# Create WireGuard directory
mkdir -p /etc/wireguard
chmod 700 /etc/wireguard
cd /etc/wireguard

# Generate VPS (server) keys
umask 077
wg genkey | tee vps-private.key | wg pubkey > vps-public.key
chmod 600 vps-private.key

# Get the default network interface
DEFAULT_IFACE=$(ip route | grep default | awk '{print $5}' | head -n1)

# Get the private key content
PRIVATE_KEY=$(cat /etc/wireguard/vps-private.key)

# Create WireGuard config as central hub
cat > /etc/wireguard/wg0.conf <<WGCONF
[Interface]
Address = 10.0.0.1/24
ListenPort = 51820
PrivateKey = ${PRIVATE_KEY}

# Enable IP forwarding for routing between peers
PostUp = sysctl -w net.ipv4.ip_forward=1
PostUp = iptables -A FORWARD -i wg0 -j ACCEPT
PostUp = iptables -A FORWARD -o wg0 -j ACCEPT
PostUp = iptables -t nat -A POSTROUTING -o ${DEFAULT_IFACE} -j MASQUERADE
PostDown = iptables -D FORWARD -i wg0 -j ACCEPT
PostDown = iptables -D FORWARD -o wg0 -j ACCEPT
PostDown = iptables -t nat -D POSTROUTING -o ${DEFAULT_IFACE} -j MASQUERADE

# Peers will be added below
# [Peer] sections should be added manually or via script
WGCONF

chmod 600 /etc/wireguard/wg0.conf

# Enable IP forwarding permanently
echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
echo "net.ipv6.conf.all.forwarding=1" >> /etc/sysctl.conf
sysctl -p

# Create helper script to add peers
cat > /usr/local/bin/wg-add-peer.sh <<'ADDPEER'
#!/bin/bash
# Usage: wg-add-peer.sh <peer-name> <peer-ip> [allowed-ips]

if [ "$#" -lt 2 ]; then
    echo "Usage: $0 <peer-name> <peer-ip> [allowed-ips]"
    echo "Example: $0 local-server 10.0.0.2 10.0.0.2/32"
    exit 1
fi

PEER_NAME=$1
PEER_IP=$2
ALLOWED_IPS=${3:-$PEER_IP/32}

# Generate peer keys
cd /etc/wireguard
wg genkey | tee $PEER_NAME-private.key | wg pubkey > $PEER_NAME-public.key
PEER_PUBKEY=$(cat $PEER_NAME-public.key)
PEER_PRIVKEY=$(cat $PEER_NAME-private.key)

# Add peer to server config
cat >> /etc/wireguard/wg0.conf <<EOF

# Peer: $PEER_NAME
[Peer]
PublicKey = $PEER_PUBKEY
AllowedIPs = $ALLOWED_IPS
PersistentKeepalive = 25
EOF

# Reload WireGuard if running
if systemctl is-active --quiet wg-quick@wg0; then
    wg syncconf wg0 <(wg-quick strip wg0)
fi

# Get server public key and IP
VPS_PUBKEY=$(cat /etc/wireguard/vps-public.key)
VPS_IP=$(curl -s ifconfig.me)

# Generate client config
cat > /etc/wireguard/$PEER_NAME-client.conf <<CLIENTCONF
[Interface]
PrivateKey = $PEER_PRIVKEY
Address = $PEER_IP/24
DNS = 1.1.1.1, 8.8.8.8

[Peer]
PublicKey = $VPS_PUBKEY
Endpoint = $VPS_IP:51820
AllowedIPs = 10.0.0.0/24
PersistentKeepalive = 25
CLIENTCONF

echo "Peer '$PEER_NAME' added successfully!"
echo "Client config saved to: /etc/wireguard/$PEER_NAME-client.conf"
echo ""
echo "To view the config:"
echo "  cat /etc/wireguard/$PEER_NAME-client.conf"
echo ""
echo "To generate QR code (for mobile):"
echo "  qrencode -t ansiutf8 < /etc/wireguard/$PEER_NAME-client.conf"
ADDPEER

chmod +x /usr/local/bin/wg-add-peer.sh

# Create setup info script
cat > /root/wireguard-info.sh <<'INFO'
#!/bin/bash
echo "======================================"
echo "WireGuard Central Hub - Setup Info"
echo "======================================"
echo ""
echo "VPS Public Key:"
cat /etc/wireguard/vps-public.key
echo ""
echo "VPS Public IP:"
curl -s ifconfig.me
echo ""
echo ""
echo "======================================"
echo "Add Peers with:"
echo "======================================"
echo "wg-add-peer.sh local-server 10.0.0.2"
echo "wg-add-peer.sh third-device 10.0.0.3"
echo ""
echo "======================================"
echo "Start WireGuard:"
echo "======================================"
echo "systemctl enable wg-quick@wg0"
echo "systemctl start wg-quick@wg0"
echo ""
echo "======================================"
echo "Check Status:"
echo "======================================"
echo "systemctl status wg-quick@wg0"
echo "wg show"
INFO

chmod +x /root/wireguard-info.sh

# Create README
cat > /root/WIREGUARD-SETUP.txt <<'README'
WireGuard Central Hub Setup Complete!
======================================

Architecture:
  Third Device (10.0.0.3) <-> VPS (10.0.0.1) <-> Local Server (10.0.0.2)

Next Steps:
-----------

1. View setup information:
   ./wireguard-info.sh

2. Add your peers:
   wg-add-peer.sh local-server 10.0.0.2
   wg-add-peer.sh third-device 10.0.0.3

3. Start WireGuard:
   systemctl enable wg-quick@wg0
   systemctl start wg-quick@wg0

4. Check status:
   systemctl status wg-quick@wg0
   wg show

5. Get client configs:
   cat /etc/wireguard/local-server-client.conf
   cat /etc/wireguard/third-device-client.conf

6. Generate QR codes (for mobile devices):
   qrencode -t ansiutf8 < /etc/wireguard/third-device-client.conf

Key Files:
----------
- Server config: /etc/wireguard/wg0.conf
- Server keys: /etc/wireguard/vps-*.key
- Client configs: /etc/wireguard/*-client.conf
- Add peer script: /usr/local/bin/wg-add-peer.sh

Troubleshooting:
----------------
- View logs: journalctl -u wg-quick@wg0 -f
- Test connectivity: ping 10.0.0.2 (from VPS to peer)
- Check firewall: ufw status
- Verify forwarding: sysctl net.ipv4.ip_forward
README

echo "WireGuard Central Hub installation complete!"
echo "Run: ./wireguard-info.sh for setup information"
echo "Setup completed successfully at $(date)" | tee /root/WIREGUARD-INSTALL-COMPLETE

# Create a simple status check
cat > /root/check-status.sh <<'STATUS'
#!/bin/bash
echo "WireGuard Installation Status"
echo "=============================="
if [ -f /root/WIREGUARD-INSTALL-COMPLETE ]; then
    echo "✓ Installation completed"
    cat /root/WIREGUARD-INSTALL-COMPLETE
else
    echo "✗ Installation not complete"
    echo "Check logs: tail -f /var/log/wireguard-setup.log"
fi
echo ""
echo "WireGuard service status:"
systemctl status wg-quick@wg0 --no-pager 2>/dev/null || echo "Not started yet"
STATUS

chmod +x /root/check-status.sh

echo "All setup complete at $(date)"
