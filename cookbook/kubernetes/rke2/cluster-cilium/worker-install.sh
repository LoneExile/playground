#!/bin/bash

# cat /var/lib/rancher/rke2/server/token
export TOKEN=""
KUBE_VIP_IP="192.168.1.9"
KUBE_VIP_NAME="master"

cat <<EOF >>/etc/hosts
$KUBE_VIP_IP $KUBE_VIP_NAME
EOF
chattr +i /etc/hosts

## if TOKEN is not set, then exit
if [ -z "$TOKEN" ]; then
  echo "TOKEN is not set"
  exit 1
fi

curl -sfL https://get.rke2.io | INSTALL_RKE2_TYPE="agent" sh -
systemctl enable rke2-agent.service

mkdir -p /etc/rancher/rke2/
cat <<EOF >/etc/rancher/rke2/config.yaml
token: ${TOKEN}
server: https://$KUBE_VIP_NAME:9345
EOF
systemctl start rke2-agent.service
