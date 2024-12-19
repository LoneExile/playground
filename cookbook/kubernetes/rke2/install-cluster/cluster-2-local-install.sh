#!/bin/bash

export TOKEN=""
## if TOKEN is not set, then exit
if [ -z "$TOKEN" ]; then
  echo "TOKEN is not set"
  exit 1
fi

KUBE_VIP_IP="192.168.1.200"
KUBE_VIP_NAME="master"
BASHRC_FILE="/root/.bashrc"

curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# Install RKE2 with Cilium as CNI
curl -sfL https://get.rke2.io | sh -
systemctl enable rke2-server.service

# Create or modify the RKE2 config file
mkdir -p /etc/rancher/rke2/
cat <<EOF >/etc/rancher/rke2/config.yaml
token: ${TOKEN}
server: https://$KUBE_VIP_NAME:9345
cni: none
tls-san:
  - $(hostname)
  #- $(hostname -i)
  - master
write-kubeconfig-mode: 0644
disable:
  - rke2-ingress-nginx
disable-kube-proxy: "true"
EOF

cat <<EOF >>/etc/hosts
$KUBE_VIP_IP $KUBE_VIP_NAME
EOF
chattr +i /etc/hosts

# Start RKE2
systemctl start rke2-server.service
sleep 69

cat <<EOF >>~/.bashrc
export KUBECONFIG=/etc/rancher/rke2/rke2.yaml
export PATH=\${PATH}:/var/lib/rancher/rke2/bin
source <(kubectl completion bash)
alias k=kubectl
complete -o default -F __start_kubectl k
if [ -f /etc/bash_completion ] && ! shopt -oq posix; then
    . /etc/bash_completion
fi
EOF

# shellcheck disable=SC1090
source "$BASHRC_FILE"

# KUBECONFIG=~/.kube/config kubectl get nodes -o wide
