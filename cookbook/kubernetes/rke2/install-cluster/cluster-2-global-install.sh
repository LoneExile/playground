#!/bin/bash

######################################################################################################################
### another cluster
# cat /var/lib/rancher/rke2/server/token

export TOKEN=""

## if TOKEN is not set, then exit
if [ -z "$TOKEN" ]; then
  echo "TOKEN is not set"
  exit 1
fi

KUBE_VIP_IP="192.168.1.200"
KUBE_VIP_NAME="master"
BASHRC_FILE="/root/.bashrc"
CILIUM_ID="2"

curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# Install RKE2 with Cilium as CNI
curl -sfL https://get.rke2.io | sh -
systemctl enable rke2-server.service

cat <<EOF >>/etc/hosts
$KUBE_VIP_IP $KUBE_VIP_NAME
EOF
chattr +i /etc/hosts

mkdir -p /etc/rancher/rke2
touch /etc/rancher/rke2/config.yaml

cat <<EOF >/etc/rancher/rke2/config.yaml
token: ${TOKEN}
cni: none
server: https://$KUBE_VIP_NAME:9345
tls-san:
  - $(hostname)
  #- $(hostname -i)
  - master
write-kubeconfig-mode: 0644
disable:
  - rke2-ingress-nginx
disable-kube-proxy: "true"
EOF

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

cat <<EOF >/root/cilium-values.yaml
kubeProxyReplacement: true
k8sServiceHost: $KUBE_VIP_NAME
k8sServicePort: 6443
cni:
  chainingMode: none
clustermesh:
  useAPIServer: true
  apiServer:
    service:
      type: LoadBalancer
cluster:
  name: $(hostname)
  id: $CILIUM_ID
hubble:
  enabled: true
  ui:
    enabled: true
  metrics:
    enabled:
      - dns
      - drop
      - tcp
      - flow
      - icmp
      - http
  relay:
    enabled: true
EOF

helm install cilium cilium/cilium --namespace kube-system --values cilium-values.yaml
