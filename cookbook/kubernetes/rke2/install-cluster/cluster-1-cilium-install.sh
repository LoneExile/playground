#!/bin/bash

KUBE_VIP_IP="192.168.1.200"
KUBE_VIP_NAME="master"
KUBE_VIP_CIDR_RANGE="192.168.1.201-192.168.1.249"
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
# cni: cilium
cni: none
tls-san:
  - $(hostname)
  - $(hostname -I | cut -d' ' -f1)
  - $KUBE_VIP_IP
  - master
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
$KUBE_VIP_IP $KUBE_VIP_NAME
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
# k8sServiceHost: $KUBE_VIP_NAME
k8sServiceHost: $(hostname -I | cut -d' ' -f1)
k8sServicePort: 6443
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

cat <<EOF >/root/kube-vip-value.yaml
config:
  address: "$KUBE_VIP_IP"
env:
  vip_interface: "eth0"
  vip_cidr: "32"
  dns_mode: "first"
  cp_enable: "true"
  cp_namespace: "kube-system"
  svc_enable: "true"
  svc_leasename: "plndr-svcs-lock"
  vip_leaderelection: "true"
  vip_leasename: "plndr-cp-lock"
  vip_leaseduration: "5"
  vip_renewdeadline: "3"
  vip_retryperiod: "1"
  prometheus_server: ":2112"
  vip_arp: "true"
affinity:
  nodeAffinity:
    requiredDuringSchedulingIgnoredDuringExecution:
      nodeSelectorTerms:
      - matchExpressions:
        - key: node-role.kubernetes.io/master
          operator: Exists
      - matchExpressions:
        - key: node-role.kubernetes.io/control-plane
          operator: Exists

tolerations:
  - effect: NoSchedule
    operator: Exists
  - effect: NoExecute
    operator: Exists
EOF

cat <<EOF >/root/cloud-provider-values.yaml
cm:
  data:
    cidr-global: $KUBE_VIP_CIDR_RANGE
    # cidr-default: "192.168.1.201-192.168.1.209" # for default ns
EOF

helm repo add kube-vip https://kube-vip.github.io/helm-charts
helm install kube-vip kube-vip/kube-vip --namespace kube-system -f kube-vip-value.yaml
helm install kube-vip-cloud-provider kube-vip/kube-vip-cloud-provider --namespace kube-system -f cloud-provider-values.yaml

sleep 30

mkdir -p "$HOME/.kube"
export VIP=$KUBE_VIP_IP
sudo cat /etc/rancher/rke2/rke2.yaml | sed 's/127.0.0.1/'$VIP'/g' >"$HOME/.kube/config"
sudo chown "$(id -u)":"$(id -g)" "$HOME/.kube/config"

KUBECONFIG=~/.kube/config kubectl get nodes -o wide

###
kubectl create ns test
kubectl create deployment nginx --image=nginx -n test
kubectl expose deployment nginx --name=nginx-lb --port=80 --type=LoadBalancer -n test
kubectl get svc -n test
# kubectl delete svc nginx-lb -n test
# kubectl delete deployment nginx -n test
