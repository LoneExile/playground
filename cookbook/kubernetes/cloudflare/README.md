# Cloudflare

- [Cloudflare tunnel Kubernetes](https://developers.cloudflare.com/cloudflare-one/tutorials/many-cfd-one-tunnel/)

## Install cloudflared

**this is bookworm specific**

[other](https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/downloads/)

```bash
# Add cloudflare gpg key
sudo mkdir -p --mode=0755 /usr/share/keyrings
curl -fsSL https://pkg.cloudflare.com/cloudflare-main.gpg | sudo tee /usr/share/keyrings/cloudflare-main.gpg >/dev/null

# Add this repo to your apt repositories
echo 'deb [signed-by=/usr/share/keyrings/cloudflare-main.gpg] https://pkg.cloudflare.com/cloudflared bookworm main' | sudo tee /etc/apt/sources.list.d/cloudflared.list

# install cloudflared
sudo apt-get update && sudo apt-get install cloudflared

cloudflared tunnel login
cloudflared tunnel create [<tunnel-name>]
cloudflared tunnel route dns [<tunnel>] [<hostname>]
```

## K9s

```bash
git clone --depth 1 https://github.com/udhos/update-golang
cd update-golang \
  && ./update-golang.sh \
  && cd .. \
  && rm -rf update-golang

go install github.com/derailed/k9s@latest

wget https://raw.githubusercontent.com/derailed/k9s/master/skins/transparent.yml -O ~/.config/k9s/skin.yml
```

## Cloudflare Tunnel

Example:
[cloudflared.yaml](https://github.com/cloudflare/argo-tunnel-examples/blob/master/named-tunnel-k8s/cloudflared.yaml)
or use [cloudflared.yaml](./cloudflared.yaml)

```bash
kubectl create namespace cloudflared
kubectl create secret generic tunnel-credentials --from-file=credentials.json=/home/le/.cloudflared/<YOUR_TUNNEL_ID>.json -n cloudflared
kubectl create secret generic cloudflared-cert --from-file=cert.pem=/home/le/.cloudflared/cert.pem -n cloudflared

wget https://raw.githubusercontent.com/LoneExile/playground/main/cookbook/k3s/cloudflared.yaml
kubectl apply -f ./cloudflared.yaml -n cloudflared

kubectl create deployment nginx --image=nginx
kubectl expose deployment nginx --port=80 --type=ClusterIP

# kubectl rollout restart -f cloudflared.yaml
kubectl edit cm cloudflared

kubectl delete -f cloudflared.yaml -n cloudflared && kubectl apply -f cloudflared.yaml -n cloudflared

```

### Adding new route

- edit the file cloudflared.yaml
- update the configmap
```bash
# then
cloudflared tunnel route dns [<tunnel>] [<hostname>]
```

### Trobleshooting

```bash
kubectl run curlpod --image=busybox -i --tty --rm --restart=Never -- sh
# then
wget -O - http://grafana.monitoring.svc.cluster.local:3000/api/health
```
