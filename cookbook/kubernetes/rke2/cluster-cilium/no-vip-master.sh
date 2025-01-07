#!/bin/bash

BASHRC_FILE="/root/.bashrc"
CILIUM_ID="1"

curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# Install RKE2 with Cilium as CNI
curl -sfL https://get.rke2.io | sh -
systemctl enable rke2-server.service

# Create or modify the RKE2 config file
mkdir -p /etc/rancher/rke2/
cat <<EOF >/etc/rancher/rke2/config.yaml
advertise-address: $(hostname -I | cut -d' ' -f1)
node-ip: $(hostname -I | cut -d' ' -f1)
cni: none
tls-san:
  - $(hostname)
  - $(hostname -I | cut -d' ' -f1)
  - master
  - 127.0.0.1
write-kubeconfig-mode: 0644
etcd-expose-metrics: true
disable:
- rke2-ingress-nginx
- rke2-snapshot-validation-webhook
- rke2-snapshot-controller
- rke2-snapshot-controller-crd
disable-kube-proxy: "true"
EOF

chattr -i /etc/hosts
cat <<EOF >>/etc/hosts
$(hostname -I | cut -d' ' -f1) $(hostname)
EOF
chattr +i /etc/hosts

# Start RKE2
systemctl start rke2-server.service
sleep 169

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

# shellcheck disable=SC1090
source "$BASHRC_FILE"

helm repo add cilium https://helm.cilium.io/

cat <<EOF >/root/cilium-values.yaml
kubeProxyReplacement: true
k8sServiceHost: 127.0.0.1
k8sServicePort: 6443
l2announcements:
  enabled: true
  leaseDuration: 3s
  leaseRenewDeadline: 1s
  leaseRetryPeriod: 500ms
# devices: {eth0,net0}
externalIPs:
  enabled: true
ipv4:
  enabled: true
ipv6:
  enabled: false
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

sleep 30

mkdir -p "$HOME/.kube"
sudo cat /etc/rancher/rke2/rke2.yaml | sed 's/127.0.0.1/127.0.0.1/g' >"$HOME/.kube/config"
sudo chown "$(id -u)":"$(id -g)" "$HOME/.kube/config"

KUBECONFIG=~/.kube/config kubectl get nodes -o wide

###
kubectl create ns test
kubectl create deployment nginx --image=nginx -n test
kubectl expose deployment nginx --name=nginx-lb --port=80 --type=LoadBalancer -n test
kubectl get svc -n test
# kubectl delete svc nginx-lb -n test
# kubectl delete deployment nginx -n test
