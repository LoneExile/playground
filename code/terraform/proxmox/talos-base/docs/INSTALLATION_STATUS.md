# Installation Status - Talos Kubernetes Cluster

**Cluster Name**: talos-proxmox-cluster
**Installation Date**: 2025-11-10
**Status**: ✅ Fully Operational

## Cluster Information

| Component | Version | Details |
|-----------|---------|---------|
| **Talos OS** | v1.11.1 | Kernel 6.12.45-talos |
| **Kubernetes** | v1.33.3 | 3 control-plane nodes |
| **Total Pods** | 48 | All running |
| **VIP** | 192.168.50.100 | Kubernetes API endpoint |

### Nodes

| Node | IP Address | Role | Status |
|------|------------|------|--------|
| talos-control-01 | 192.168.50.95 | Control Plane | Ready |
| talos-control-02 | 192.168.50.94 | Control Plane | Ready |
| talos-control-03 | 192.168.50.93 | Control Plane | Ready |

## Installed Components

### 1. Cilium CNI - ✅ OPERATIONAL

**Version**: v1.18.3
**Installation Date**: 2025-11-10
**Documentation**: [CILIUM_SETUP.md](./CILIUM_SETUP.md)

**Configuration**:
- Mode: tunnel (VXLAN on port 8473)
- IPAM: kubernetes
- Kube-proxy Replacement: **Enabled** (eBPF)
- Host Firewall: **Enabled**
- Hubble: **Disabled** (resource optimization)
- Envoy: **Disabled**

**Components Running**:
```
Cilium Agents:    3/3 (one per node)
Cilium Operators: 2/2
CoreDNS:          2/2
```

**Installation Command**:
```bash
helm install cilium cilium/cilium \
  --version 1.18.3 \
  --namespace kube-system \
  --values cilium/values.yaml
```

**Values File**: `cilium/values.yaml`

---

### 2. Piraeus Operator (Storage) - ✅ OPERATIONAL

**Version**: v2.9.1
**Installation Date**: 2025-11-10
**Documentation**: [PIRAEUS_SETUP.md](./PIRAEUS_SETUP.md)

**Configuration**:
- Storage Backend: **ZFS** (not LVM thin)
- Replication: **DRBD** (loaded and working)
- LINSTOR Nodes: 3/3 Online
- Storage Pools: pool1 on all nodes

**Storage Capacity**:
- Per Node: 496 GiB (ZFS pool on /dev/vdb)
- Total Raw: ~1.5 TB
- With 2-way replication: ~750 GB usable
- With 3-way replication: ~500 GB usable

**Components Running**:
```
Operator:              2/2
Controller:            1/1
Satellites:            3/3 (2 containers each)
CSI Driver:            7/7
HA Controllers:        3/3
Affinity Controller:   1/1
```

**StorageClasses Created**:
- `piraeus-storage-single` - 1 replica (no replication)
- `piraeus-storage` - 2 replicas (default, 2-way DRBD)
- `piraeus-storage-ha` - 3 replicas (3-way DRBD for critical data)

**Installation Commands**:
```bash
# Install operator
kubectl apply --server-side -f https://github.com/piraeusdatastore/piraeus-operator/releases/latest/download/manifest.yaml

# Configure for Talos (remove systemd dependencies)
kubectl apply -f talos-satellite-config.yaml

# Create LinstorCluster
kubectl apply -f linstor-cluster.yaml

# Create ZFS storage pools
linstor physical-storage create-device-pool --pool-name pool1 zfs talos-control-01 /dev/vdb --storage-pool pool1
linstor physical-storage create-device-pool --pool-name pool1 zfs talos-control-02 /dev/vdb --storage-pool pool1
linstor physical-storage create-device-pool --pool-name pool1 zfs talos-control-03 /dev/vdb --storage-pool pool1
```

**Key Achievement**: **ZFS + DRBD** working! No need for dm-thin-pool module.

---

### 3. MetalLB (LoadBalancer) - ✅ OPERATIONAL

**Version**: v0.15.2
**Installation Date**: 2025-11-10
**Documentation**: [METALLB_SETUP.md](./METALLB_SETUP.md)

**Configuration**:
- Mode: L2 (Layer 2 / ARP-based)
- IP Pool: 192.168.50.50-192.168.50.250 (201 IPs)
- Interface: eth0
- Talos Setting: `speaker.ignoreExcludeLB=true`

**Components Running**:
```
Controller: 1/1
Speakers:   3/3 (one per node, 4 containers each)
```

**IP Assignments**:
- `192.168.50.80` - NGINX Ingress Controller

**Available IPs**: 200 (192.168.50.50-79, 81-250)

**Installation Commands**:
```bash
helm install my-metallb metallb/metallb \
  --version 0.15.2 \
  --namespace metallb-system \
  --create-namespace \
  --set speaker.ignoreExcludeLB=true

kubectl label namespace metallb-system \
  pod-security.kubernetes.io/enforce=privileged

kubectl apply -f metallb-ippool.yaml
kubectl apply -f metallb-l2advertisement.yaml
```

---

### 4. Cert-Manager (Certificate Management) - ✅ OPERATIONAL

**Version**: v1.13.3
**Installation Date**: 2025-11-10
**Documentation**: [CERT_MANAGER_SETUP.md](./CERT_MANAGER_SETUP.md)

**Configuration**:
- CA Type: Self-signed (4096-bit RSA, 10-year validity)
- ClusterIssuer: `ca-issuer`
- Certificate Validity: 90 days (auto-renewal at 75 days)

**Components Running**:
```
Controller:       1/1
Webhook:          1/1
CA Injector:      1/1
```

**CA Certificate**: `docs/talos-ca.crt`

**Installation Commands**:
```bash
# Install CRDs
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.3/cert-manager.crds.yaml

# Install cert-manager
helm install cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --create-namespace \
  --version v1.13.3

# Create self-signed CA
openssl genrsa -out ca.key 4096
openssl req -new -x509 -sha256 -days 3650 -key ca.key -out ca.crt \
  -subj "/CN=Talos Local CA/O=Talos Cluster/C=US"

kubectl create secret tls ca-secret --cert=ca.crt --key=ca.key -n cert-manager

# Create ClusterIssuer
kubectl apply -f ca-issuer.yaml
```

**Certificates Issued**:
- `harbor-cert` - Harbor Container Registry (harbor.cloud.local)

---

### 5. NGINX Ingress Controller - ✅ OPERATIONAL

**Version**: Latest (Helm chart)
**Installation Date**: 2025-11-10
**Documentation**: [NGINX_INGRESS_SETUP.md](./NGINX_INGRESS_SETUP.md)

**Configuration**:
- LoadBalancer IP: 192.168.50.80 (via MetalLB)
- Ingress Class: `nginx` (default)
- Replicas: 1

**Components Running**:
```
Controller:   1/1
```

**Services**:
- LoadBalancer: 192.168.50.80 (HTTP: 80, HTTPS: 443)
- Metrics: Enabled (port 10254, Prometheus compatible)

**Installation Commands**:
```bash
helm install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  --create-namespace \
  --set controller.service.type=LoadBalancer \
  --set controller.service.loadBalancerIP=192.168.50.80 \
  --set controller.ingressClassResource.default=true \
  --set controller.metrics.enabled=true
```

**Ingress Resources**:
- `harbor-ingress` - Harbor Container Registry

---

### 6. Harbor Container Registry - ✅ OPERATIONAL

**Version**: Latest (Helm chart)
**Installation Date**: 2025-11-10
**Documentation**: [HARBOR_SETUP.md](./HARBOR_SETUP.md)

**Configuration**:
- URL: https://harbor.cloud.local
- Ingress IP: 192.168.50.80
- Admin Password: Harbor12345
- TLS: Enabled (cert-manager)

**Components Running (7/7)**:
```
harbor-core:          1/1  (API & Web UI)
harbor-portal:        1/1  (Frontend)
harbor-registry:      2/2  (Docker Distribution)
harbor-database:      1/1  (PostgreSQL)
harbor-redis:         1/1  (Cache)
harbor-jobservice:    1/1  (Background Jobs)
harbor-trivy:         1/1  (Vulnerability Scanner)
```

**Persistent Storage (Piraeus ZFS+DRBD 2-way)**:
```
Registry:    20Gi (40Gi with replication)
Database:     5Gi (10Gi with replication)
Redis:        1Gi (2Gi with replication)
Jobservice:   1Gi (2Gi with replication)
Trivy:        5Gi (10Gi with replication)
──────────────────────────────────────
Total:       32Gi (~64Gi with replication)
```

**Installation Commands**:
```bash
# Create certificate
kubectl apply -f harbor-cert.yaml

# Install Harbor
helm install harbor harbor/harbor \
  --namespace harbor \
  --create-namespace \
  --values harbor-values.yaml
```

**Values File**: `harbor-values.yaml`

**Access**:
1. Add to /etc/hosts: `192.168.50.80 harbor.cloud.local`
2. Trust CA: `sudo security add-trusted-cert -k /Library/Keychains/System.keychain docs/talos-ca.crt`
3. Browse: https://harbor.cloud.local
4. Login: admin / Harbor12345

---

## Network Architecture

```
192.168.50.0/24 Network
│
├─ 192.168.50.93    → talos-control-03
├─ 192.168.50.94    → talos-control-02
├─ 192.168.50.95    → talos-control-01
├─ 192.168.50.100   → Kubernetes VIP (kube-apiserver)
│
└─ 192.168.50.50-250 → MetalLB IP Pool
   │
   ├─ 192.168.50.80  → NGINX Ingress Controller (HTTP/HTTPS)
   └─ 192.168.50.50-79, 81-250 → Available for services
```

## Storage Architecture

```
Application
    ↓
CSI Driver (linstor.csi.linbit.com)
    ↓
DRBD (2-way or 3-way replication across nodes)
    ↓
ZFS (local storage pool on each node)
    ↓
/dev/vdb (500GB disk per node)
```

## Resource Summary

### CPU & Memory
- **Control Plane Nodes**: 3x (configured in Terraform)
- **Total Pods**: 48 running
- **Namespaces**: 7 (default, kube-system, kube-public, kube-node-lease, metallb-system, cert-manager, ingress-nginx, piraeus-datastore, harbor)

### Storage
- **Raw Capacity**: ~1.5 TB (500GB × 3 nodes)
- **Usable (2-way replication)**: ~750 GB
- **Usable (3-way replication)**: ~500 GB
- **Currently Used**: ~64 GB (Harbor with replication)
- **Available**: ~686 GB (with 2-way replication)

### Network
- **LoadBalancer IPs**: 201 available, 1 in use
- **Ingress**: 1 (Harbor)
- **Certificates**: 1 (Harbor)

## Verification Commands

### Check All Components
```bash
# Nodes
kubectl get nodes

# All pods
kubectl get pods -A

# StorageClasses
kubectl get storageclass

# PVCs with replication
kubectl get pvc -A

# LoadBalancer services
kubectl get svc -A | grep LoadBalancer

# Ingress resources
kubectl get ingress -A

# Certificates
kubectl get certificates -A
```

### Check Storage
```bash
# LINSTOR nodes
kubectl -n piraeus-datastore exec deploy/linstor-controller -- linstor node list

# Storage pools
kubectl -n piraeus-datastore exec deploy/linstor-controller -- linstor storage-pool list

# DRBD resources
kubectl -n piraeus-datastore exec deploy/linstor-controller -- linstor resource list
```

### Check Harbor
```bash
# Harbor pods
kubectl get pods -n harbor

# Harbor ingress
kubectl get ingress -n harbor

# Test Harbor access
curl -k https://harbor.cloud.local
```

## Known Issues & Solutions

### Issue 1: dm-thin-pool Module Not Available
**Status**: ✅ Resolved
**Solution**: Used ZFS instead of LVM thin pools. ZFS module is available in Talos image and works perfectly with DRBD.

### Issue 2: Cilium Optimized Configuration
**Status**: ✅ Configured
**Details**: Disabled Hubble and Envoy to reduce resource usage by 46% (from 13 pods to 7 pods). Kube-proxy replacement enabled for better performance.

### Issue 3: Harbor Initial Installation
**Status**: ✅ Resolved
**Details**: Required Piraeus storage to be configured first. Once ZFS+DRBD storage was ready, Harbor installed successfully with all persistent volumes.

## Next Steps & Recommendations

### Immediate
- ✅ All core infrastructure installed and operational
- ✅ Persistent storage with replication working
- ✅ LoadBalancer and Ingress working
- ✅ Container registry available

### Optional Enhancements
1. **Monitoring**: Install Prometheus + Grafana for metrics
2. **Logging**: Install Loki + Promtail for centralized logging
3. **Backup**: Configure Velero for cluster and volume backups
4. **GitOps**: Install ArgoCD or Flux for declarative deployments
5. **Service Mesh**: Consider Istio or Linkerd for advanced traffic management
6. **Policy Engine**: Install OPA/Gatekeeper for policy enforcement

### Maintenance
- **Certificate Renewal**: Automatic (cert-manager handles it)
- **Storage Monitoring**: Monitor Piraeus/LINSTOR pool usage
- **IP Pool Management**: Track MetalLB IP assignments
- **Backup Schedule**: Plan for etcd and persistent volume backups

## Support & Documentation

- **Main README**: [README.md](./README.md) - Overview and quick reference
- **Component Docs**: Individual setup guides in this directory
- **Talos Docs**: https://www.talos.dev/
- **Kubernetes Docs**: https://kubernetes.io/docs/

---

**Installation Completed**: 2025-11-10
**Installed By**: Claude Code
**Cluster Status**: ✅ Production Ready
**Total Installation Time**: ~30 minutes
