# [MetalLB](https://github.com/metallb/metallb)

MetalLB is a load-balancer implementation for bare metal Kubernetes clusters,

## Helm

### [Install](https://helm.sh/docs/intro/install/)

```bash
curl https://baltocdn.com/helm/signing.asc | gpg --dearmor | sudo tee /usr/share/keyrings/helm.gpg > /dev/null
sudo apt-get install apt-transport-https --yes
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/helm.gpg] https://baltocdn.com/helm/stable/debian/ all main" | sudo tee /etc/apt/sources.list.d/helm-stable-debian.list
sudo apt-get update
sudo apt-get install helm
```

```bash
sudo cp -i /etc/rancher/k3s/k3s.yaml $HOME/.kube/config

export KUBECONFIG=~/.kube/config

chmod 644 $HOME/.kube/config

```

MetalLB](https://metallb.universe.tf/installation/)

```bash
helm repo add metallb https://metallb.github.io/metallb
helm install metallb metallb/metallb
```

or (this worked for me)

```bash
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.13.12/config/manifests/metallb-native.yaml

```

# set up layer 2

metallb.yaml

```yaml
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: first-pool
  namespace: metallb-system
spec:
  addresses:
    - 192.168.1.230-192.168.1.250
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: example
  namespace: metallb-system
```

```bash
kubectl apply -f metallb.yaml

```

## test

```bash
kubectl create deployment nginx --image=nginx
kubectl expose deployment nginx --port=80 --type=LoadBalancer
```
