#!/bin/bash

KUBE_VIP_IP="192.168.1.200"
KUBE_VIP_NAME="master"
KUBE_VIP_CIDR_RANGE="192.168.1.201-192.168.1.209"
BASHRC_FILE="/root/.bashrc"
CILIUM_ID="1"

CLOUDFLARE_API_TOKEN=""
CLOUDFLARE_API_TOKEN_BASE64=$(echo -n "$CLOUDFLARE_API_TOKEN" | base64)
ACME_EMAIL="me@apinant.dev"
DOMAIN="voidbox.io"

curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# Install RKE2 with Cilium as CNI
curl -sfL https://get.rke2.io | sh -
systemctl enable rke2-server.service

# Create or modify the RKE2 config file
mkdir -p /etc/rancher/rke2/
cat <<EOF >/etc/rancher/rke2/config.yaml
#cni: cilium
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
sleep 169

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

KUBECONFIG=~/.kube/config kubectl get nodes -o wide

helm repo add cilium https://helm.cilium.io/
#helm install cilium cilium/cilium --namespace=kube-system

# `kubeProxyReplacement=true` This enables Cilium to completely replace kube-proxy functionality
# `cni.chainingMode=none` Ensures Cilium has complete control over network configuration

# helm install cilium cilium/cilium \
#   --namespace kube-system \
#   --set kubeProxyReplacement=true --set k8sServiceHost=ubuntu-1 \
#   --set k8sServicePort=6443 \
#   --set cni.chainingMode=none

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
# helm upgrade cilium cilium/cilium --namespace kube-system --values cilium-values.yaml

# mkdir -p $HOME/.kube
# export VIP=$(hostname -I | cut -d' ' -f1)
# sudo cat /etc/rancher/rke2/rke2.yaml | sed 's/127.0.0.1/'$VIP'/g' >$HOME/.kube/config
# sudo chown $(id -u):$(id -g) $HOME/.kube/config

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
helm install kube-vip kube-vip/kube-vip \
  --namespace kube-system \
  -f kube-vip-value.yaml
helm install kube-vip-cloud-provider kube-vip/kube-vip-cloud-provider --namespace kube-system -f cloud-provider-values.yaml

sleep 30

# NOTE: add this before
# `vim /etc/hosts`
# 192.168.1.200 master

mkdir -p "$HOME/.kube"
export VIP=192.168.1.206
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

# kubectl create deployment nginx --image=nginx
# kubectl expose deployment nginx --name=nginx-lb --port=80 --type=LoadBalancer
# kubectl delete svc nginx-lb
# kubectl delete deployment nginx

helm repo add traefik https://traefik.github.io/charts

cat <<EOF >/root/traefik-values.yaml
ports:
  web:
    redirectTo:
      port: websecure
ingressRoute:
  dashboard:
    enabled: true
    entryPoints:
      - web
      - websecure
    match: Host(\`traefik.$DOMAIN\`)
EOF

helm install traefik traefik/traefik --namespace traefik --create-namespace --values traefik-values.yaml
# helm upgrade traefik traefik/traefik --namespace traefik --values traefik-values.yaml

# curl -k -H "Host: traefik.$DOMAIN" $(kubectl get svc traefik -n traefik -o jsonpath='{.status.loadBalancer.ingress[0].ip}')

# # ingress
# cat <<EOF >/root/ingress.yaml
# apiVersion: networking.k8s.io/v1
# kind: Ingress
# metadata:
#   name: nginx-ingress
#   namespace: test
#   annotations:
#     traefik.ingress.kubernetes.io/router.entrypoints: websecure
# spec:
#   rules:
#   - host: nginx.$DOMAIN
#     http:
#       paths:
#       - path: /
#         pathType: Prefix
#         backend:
#           service:
#             name: nginx-lb
#             port:
#               number: 80
# EOF

# kubectl apply -f ingress.yaml
# curl -k -H "Host: nginx.$DOMAIN" $(kubectl get svc traefik -n traefik -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
# kubectl delete -f ingress.yaml

# ingressRoute
# cat <<EOF >/root/ingressroute.yaml
# apiVersion: traefik.io/v1alpha1
# kind: IngressRoute
# metadata:
#   name: nginx-ingress
#   namespace: test
# spec:
#   entryPoints:
#     - websecure
#   routes:
#     - match: Host(\`nginx.$DOMAIN\`)
#       kind: Rule
#       services:
#         - name: nginx-lb
#           port: 80
# EOF

# kubectl apply -f ingressroute.yaml
# curl -k -H "Host: nginx.$DOMAIN" $(kubectl get svc traefik -n traefik -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
# kubectl delete -f ingressroute.yaml

helm repo add jetstack https://charts.jetstack.io --force-update

cat <<EOF >/root/cert-manager-values.yaml
namespace: cert-manager
crds:
  enabled: true
extraArgs:
  - --dns01-recursive-nameservers-only
  - --dns01-recursive-nameservers=1.1.1.1:53,1.0.0.1:53
EOF

helm install cert-manager jetstack/cert-manager --namespace cert-manager --create-namespace --values cert-manager-values.yaml

# cloudflare-api-token-secret
cat <<EOF >/root/cloudflare-api-token-secret.yaml
apiVersion: v1
kind: Secret
metadata:
  name: cloudflare-api-token-secret
  namespace: cert-manager
type: Opaque
data:
  api-token: $CLOUDFLARE_API_TOKEN_BASE64
EOF

kubectl apply -f cloudflare-api-token-secret.yaml

## https://cert-manager.io/docs/configuration/acme/dns01/cloudflare/

# Issuer
cat <<EOF >/root/issuer.yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: cloudflare-cluster-issuer
spec:
  acme:
    email: $ACME_EMAIL
    # server: https://acme-staging-v02.api.letsencrypt.org/directory
    server: https://acme-v02.api.letsencrypt.org/directory
    privateKeySecretRef:
      name: cloudflare-issuer-account-key
    solvers:
    - dns01:
        cloudflare:
          apiTokenSecretRef:
            name: cloudflare-api-token-secret
            key: api-token
EOF

kubectl apply -f issuer.yaml

## test cert
# nginx cert
cat <<EOF >/root/nginx-cert.yaml
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: nginx-cert
  namespace: test
spec:
  secretName: nginx-cert-secret
  issuerRef:
    name: cloudflare-cluster-issuer
    kind: ClusterIssuer
  dnsNames:
    - nginx.$DOMAIN
EOF

kubectl apply -f nginx-cert.yaml

## nginx ingressRoute with tls
cat <<EOF >/root/ingressroute-tls.yaml
apiVersion: traefik.io/v1alpha1
kind: IngressRoute
metadata:
  name: nginx-ingress
  namespace: test
spec:
  entryPoints:
    - websecure
  routes:
    - match: Host(\`nginx.$DOMAIN\`)
      kind: Rule
      services:
        - name: nginx-lb
          port: 80
  tls:
    secretName: nginx-cert-secret
EOF

kubectl apply -f ingressroute-tls.yaml

kubectl get certificate -n test

# `vim /etc/hosts`
# 192.168.1.203 nginx.$DOMAIN

sleep 80
curl -v https://nginx.$DOMAIN

## https://cert-manager.io/docs/troubleshooting/#troubleshooting-a-failed-certificate-request

## traefik dashboard cert
cat <<EOF >/root/traefik-cert.yaml
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: traefik-cert
  namespace: traefik
spec:
  secretName: traefik-cert-secret
  issuerRef:
    name: cloudflare-cluster-issuer
    kind: ClusterIssuer
  dnsNames:
    - traefik.home.$DOMAIN
EOF

kubectl apply -f traefik-cert.yaml

cat <<EOF >/root/traefik-values.yaml
ports:
  web:
    redirectTo:
      port: websecure
ingressRoute:
  dashboard:
    enabled: true
    entryPoints:
      - web
      - websecure
    match: Host(\`traefik.home.$DOMAIN\`)
    tls:
      secretName: traefik-cert-secret
EOF

helm upgrade traefik traefik/traefik --namespace traefik --values traefik-values.yaml

####

# kubectl label node ubuntu-3 node-role.kubernetes.io/worker=worker
