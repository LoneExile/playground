# Cilium CNI Setup for Talos OS

This guide documents the installation and configuration of Cilium as the CNI (Container Network Interface) for a Talos OS Kubernetes cluster.

## Overview

Cilium is an eBPF-based networking, observability, and security solution for Kubernetes. This setup uses Cilium v1.18.3 with Hubble for network observability.

## Prerequisites

- Talos OS cluster provisioned with CNI set to "none"
- Helm 3.x installed
- kubectl configured with cluster access
- Cluster API server accessible

## Cluster Configuration

The Talos cluster must be configured with no default CNI in the machine configuration:

```yaml
cluster:
  network:
    cni:
      name: none
```

## Installation Steps

### 1. Add Cilium Helm Repository

```bash
helm repo add cilium https://helm.cilium.io/
helm repo update cilium
```

### 2. Create Cilium Configuration

Create a values file at `cilium/values.yaml`:

```yaml
# Cilium Configuration for Talos OS
# This is a production-ready configuration for Cilium on Talos

# Routing configuration
routingMode: tunnel
tunnelProtocol: vxlan
tunnelPort: 8473

# IPAM configuration
ipam:
  mode: "kubernetes"

# Talos-specific configuration
# Talos uses KubePrism which runs on localhost:7445
k8sServiceHost: localhost
k8sServicePort: 7445

# Security context for Talos
securityContext:
  capabilities:
    ciliumAgent:
      - CHOWN
      - KILL
      - NET_ADMIN
      - NET_RAW
      - IPC_LOCK
      - SYS_ADMIN
      - SYS_RESOURCE
      - DAC_OVERRIDE
      - FOWNER
      - SETGID
      - SETUID
    cleanCiliumState:
      - NET_ADMIN
      - SYS_ADMIN
      - SYS_RESOURCE

# Cgroup configuration for Talos
cgroup:
  autoMount:
    enabled: false
  hostRoot: /sys/fs/cgroup

# Enable Hubble for observability (optional)
hubble:
  relay:
    enabled: true
  ui:
    enabled: true
```

### 3. Install Cilium

```bash
helm install cilium cilium/cilium \
  --version 1.18.3 \
  --namespace kube-system \
  --values cilium/values.yaml
```

### 4. Verify Installation

Wait for Cilium pods to be ready:

```bash
kubectl get pods -n kube-system -l app.kubernetes.io/part-of=cilium
```

Expected output:
```
NAME                              READY   STATUS    RESTARTS   AGE
cilium-envoy-xxxxx                1/1     Running   0          2m
cilium-envoy-yyyyy                1/1     Running   0          2m
cilium-envoy-zzzzz                1/1     Running   0          2m
cilium-xxxxx                      1/1     Running   0          2m
cilium-yyyyy                      1/1     Running   0          2m
cilium-zzzzz                      1/1     Running   0          2m
cilium-operator-xxxxxxxxxx-xxxxx  1/1     Running   0          2m
cilium-operator-xxxxxxxxxx-yyyyy  1/1     Running   0          2m
hubble-relay-xxxxxxxxxx-xxxxx     1/1     Running   0          2m
hubble-ui-xxxxxxxxxx-xxxxx        2/2     Running   0          2m
```

Check node status:

```bash
kubectl get nodes
```

All nodes should show status **Ready**:
```
NAME               STATUS   ROLES           AGE   VERSION
talos-control-01   Ready    control-plane   5m    v1.33.3
talos-control-02   Ready    control-plane   5m    v1.33.3
talos-control-03   Ready    control-plane   5m    v1.33.3
```

### 5. Verify Network Connectivity

Test pod networking:

```bash
kubectl run test-nginx --image=nginx --rm -it --restart=Never -- curl -I http://kubernetes.default.svc.cluster.local
```

## Configuration Details

### Talos-Specific Settings

#### KubePrism Configuration
Talos uses KubePrism, a local load balancer for the Kubernetes API server running on `localhost:7445`. Cilium must be configured to use this endpoint instead of the standard `kubernetes.default.svc` service.

```yaml
k8sServiceHost: localhost
k8sServicePort: 7445
```

#### Security Context
Talos requires specific capabilities for Cilium agents:

```yaml
securityContext:
  capabilities:
    ciliumAgent:
      - CHOWN
      - KILL
      - NET_ADMIN
      - NET_RAW
      - IPC_LOCK
      - SYS_ADMIN
      - SYS_RESOURCE
      - DAC_OVERRIDE
      - FOWNER
      - SETGID
      - SETUID
```

#### Cgroup Configuration
Talos manages cgroups differently than other distributions:

```yaml
cgroup:
  autoMount:
    enabled: false
  hostRoot: /sys/fs/cgroup
```

### Networking Configuration

#### Tunnel Mode
Cilium uses VXLAN encapsulation on port 8473:

```yaml
routingMode: tunnel
tunnelProtocol: vxlan
tunnelPort: 8473
```

#### IPAM Mode
Using Kubernetes native IPAM mode, which allocates pod CIDRs from the node's PodCIDR:

```yaml
ipam:
  mode: "kubernetes"
```

## Hubble Observability

Hubble provides deep visibility into network traffic and security policies.

### Access Hubble UI

Port-forward the Hubble UI service:

```bash
kubectl port-forward -n kube-system svc/hubble-ui 12000:80
```

Access the UI at: http://localhost:12000

### Hubble CLI

Install Hubble CLI:

```bash
# macOS
brew install cilium-cli

# Linux
HUBBLE_VERSION=$(curl -s https://raw.githubusercontent.com/cilium/hubble/master/stable.txt)
curl -L --remote-name-all https://github.com/cilium/hubble/releases/download/$HUBBLE_VERSION/hubble-linux-amd64.tar.gz
tar xzvf hubble-linux-amd64.tar.gz
sudo mv hubble /usr/local/bin
```

Use Hubble CLI:

```bash
# Port-forward Hubble Relay
kubectl port-forward -n kube-system svc/hubble-relay 4245:80

# Observe flows
hubble observe
```

## Troubleshooting

### Pods Not Starting

Check Cilium agent logs:

```bash
kubectl logs -n kube-system -l app.kubernetes.io/name=cilium --tail=50
```

### Nodes Not Ready

Verify Cilium is running on all nodes:

```bash
kubectl get pods -n kube-system -l app.kubernetes.io/name=cilium -o wide
```

### Network Connectivity Issues

Check Cilium connectivity:

```bash
kubectl exec -n kube-system ds/cilium -- cilium status
```

### CoreDNS Pods Pending

CoreDNS pods require Cilium to be fully functional. If they remain in Pending state:

1. Check Cilium agent status
2. Verify node readiness
3. Check for CNI plugin errors in kubelet logs

## Upgrading Cilium

To upgrade Cilium to a newer version:

```bash
helm upgrade cilium cilium/cilium \
  --version <new-version> \
  --namespace kube-system \
  --values cilium/values.yaml \
  --reuse-values
```

## Uninstalling Cilium

**Warning**: Uninstalling Cilium will disrupt all pod networking.

```bash
helm uninstall cilium --namespace kube-system
```

After uninstalling, you must either:
1. Install a replacement CNI
2. Reboot all nodes to clear network state

## Additional Resources

- [Cilium Documentation](https://docs.cilium.io/)
- [Cilium on Talos](https://www.talos.dev/latest/kubernetes-guides/network/deploying-cilium/)
- [Hubble Documentation](https://docs.cilium.io/en/stable/gettingstarted/hubble/)
- [Cilium Helm Chart](https://github.com/cilium/cilium/tree/main/install/kubernetes/cilium)

## Installation Summary

**Date**: November 10, 2025
**Cilium Version**: 1.18.3
**Talos Version**: v1.11.1
**Kubernetes Version**: v1.33.3
**Cluster**: talos-proxmox-cluster

**Installation Result**: ✅ Success
- All 3 nodes: Ready
- Cilium agents: Running (3/3)
- Cilium operators: Running (2/2)
- CoreDNS: Running (2/2)
- Hubble: Enabled
- Network connectivity: Verified
