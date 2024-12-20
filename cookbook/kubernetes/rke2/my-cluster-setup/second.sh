#!/bin/bash

KUBE_VIP_IP="192.168.1.200"
KUBE_VIP_NAME="master"
TOKEN="K10ee291eac59bed9210ea564907c2b48df70de978adcf061bd9458d615ca94b609::server:4d3d7d3407d0f6d57917bd32982a62c4" 

curl -sfL https://get.rke2.io | sh -
systemctl enable rke2-server.service

mkdir -p /etc/rancher/rke2/
cat <<EOF >/etc/rancher/rke2/config.yaml
advertise-address: $(hostname -I | cut -d' ' -f1)
node-ip: $(hostname -I | cut -d' ' -f1)
cni: none
tls-san:
  - $(hostname)
  - $(hostname -I | cut -d' ' -f1)
  - 192.168.1.200
  - master
write-kubeconfig-mode: 0644
etcd-expose-metrics: true
kube-apiserver-arg:
  - "bind-address=0.0.0.0"
  - "advertise-address=$(hostname -I | cut -d' ' -f1)"
kube-controller-manager-arg:
  - "bind-address=0.0.0.0"
kube-cloud-controller-manager-arg:
  - "bind-address=0.0.0.0"
kube-scheduler-arg:
  - "bind-address=0.0.0.0"
disable:
  - rke2-ingress-nginx
  - rke2-snapshot-validation-webhook
  - rke2-snapshot-controller
  - rke2-snapshot-controller-crd
disable-kube-proxy: true
EOF

chattr -i /etc/hosts
cat <<EOF >>/etc/hosts
${KUBE_VIP_IP} ${KUBE_VIP_NAME}
$(hostname -I | cut -d' ' -f1) $(hostname)
192.168.1.218 master1
EOF
chattr +i /etc/hosts

# Start RKE2
systemctl start rke2-server.service

cat <<EOF >>~/.bashrc
export KUBECONFIG=/etc/rancher/rke2/rke2.yaml
export PATH=\${PATH}:/var/lib/rancher/rke2/bin
source <(kubectl completion bash)
export CONTAINER_RUNTIME_ENDPOINT=unix:///run/k3s/containerd/containerd.sock
export CONTAINERD_ADDRESS=/run/k3s/containerd/containerd.sock
alias k=kubectl
complete -o default -F __start_kubectl k
if [ -f /etc/bash_completion ] && ! shopt -oq posix; then
    . /etc/bash_completion
fi
EOF
