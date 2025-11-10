# Talos Kubernetes Cluster Documentation

This directory contains comprehensive documentation for the Talos Kubernetes cluster deployment on Proxmox.

## Cluster Information

**Cluster Name**: talos-proxmox-cluster
**Kubernetes Version**: v1.33.3
**Talos Version**: v1.11.1
**Platform**: Proxmox VE

### Control Plane Nodes

| Node | IP Address | Role | Status |
|------|------------|------|--------|
| talos-control-01 | 192.168.50.95 | Control Plane | Running |
| talos-control-02 | 192.168.50.94 | Control Plane | Running |
| talos-control-03 | 192.168.50.93 | Control Plane | Running |

**VIP**: 192.168.50.100 (Kubernetes API endpoint)

## Installed Components

### 1. Cilium CNI (Network)

**Status**: ✅ Operational
**Documentation**: [CILIUM_SETUP.md](./CILIUM_SETUP.md)

**Configuration**:
- Version: v1.18.3
- Routing Mode: tunnel (VXLAN)
- IPAM Mode: kubernetes
- Kube-proxy Replacement: Enabled (eBPF)
- Host Firewall: Enabled
- Hubble: Disabled (resource optimization)
- Envoy: Disabled

**Components**:
```
Cilium Agents:    3/3 Running
Cilium Operators: 2/2 Running
CoreDNS:          2/2 Running
```

**Features**:
- ✅ eBPF-based networking
- ✅ Kube-proxy replacement
- ✅ Host firewall for security
- ✅ External IPs support
- ✅ NodePort services
- ✅ Maglev load balancing

### 2. Piraeus Operator (Storage)

**Status**: ✅ Operational (ZFS + DRBD)
**Documentation**: [PIRAEUS_SETUP.md](./PIRAEUS_SETUP.md)

**Configuration**:
- Version: v2.9.1
- Storage Backend: **ZFS** (not LVM thin pools)
- Replication: **DRBD** (2-way and 3-way)
- LINSTOR Nodes: 3/3 Online
- Storage Pools: `pool1` on all nodes (ZFS on /dev/vdb)

**Components**:
```
Operator:              2/2 Running
Controller:            1/1 Running
Satellites:            3/3 Running (2 containers each)
CSI Driver:            7/7 Running
HA Controllers:        3/3 Running
Affinity Controller:   1/1 Running
```

**Storage Capacity**:
- Per Node: 496 GiB (ZFS pool on /dev/vdb)
- Total Raw: ~1.5 TB
- With 2-way replication: ~750 GB usable
- With 3-way replication: ~500 GB usable

**StorageClasses**:
- `piraeus-storage-single` - 1 replica (no replication)
- `piraeus-storage` - 2 replicas (default, 2-way DRBD)
- `piraeus-storage-ha` - 3 replicas (3-way DRBD for critical data)

**Key Achievement**: **ZFS + DRBD Working!** No need for `dm-thin-pool` module. ZFS provides native snapshots, checksums, compression, and DRBD provides block-level replication.

### 3. MetalLB (LoadBalancer)

**Status**: ✅ Operational
**Documentation**: [METALLB_SETUP.md](./METALLB_SETUP.md)

**Configuration**:
- Version: v0.15.2 (Helm-based installation)
- Mode: L2 (Layer 2 / ARP-based)
- IP Pool: `192.168.50.50-192.168.50.250` (201 IPs)
- Auto-assign: Enabled
- Interface: `eth0` (TalosOS compatibility)
- Special Setting: `speaker.ignoreExcludeLB=true` (for TalosOS)

**Components**:
```
Controller: 1/1 Running
Speakers:   3/3 Running (4 containers each)
```

**IP Assignments**:
- `192.168.50.80` - NGINX Ingress Controller

**Available IPs**: 200 IPs (192.168.50.50-79, 81-250)

### 4. Cert-Manager (Certificate Management)

**Status**: ✅ Operational
**Documentation**: [CERT_MANAGER_SETUP.md](./CERT_MANAGER_SETUP.md)

**Configuration**:
- Version: v1.13.3
- Certificate Authority: Self-signed CA (4096-bit RSA, 10-year validity)
- ClusterIssuer: `ca-issuer`
- Certificate Validity: 90 days (auto-renewal at 75 days)

**Components**:
```
Controller:       1/1 Running
Webhook:          1/1 Running
CA Injector:      1/1 Running
```

**Features**:
- ✅ Self-signed CA infrastructure
- ✅ Automated certificate issuance
- ✅ Automated certificate renewal
- ✅ TLS secret management
- ✅ Ingress TLS integration
- ✅ Certificate validation

**CA Certificate**:
- Location: `docs/talos-ca.crt`
- Import to macOS: `sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain docs/talos-ca.crt`

### 5. NGINX Ingress Controller

**Status**: ✅ Operational
**Documentation**: [NGINX_INGRESS_SETUP.md](./NGINX_INGRESS_SETUP.md)

**Configuration**:
- Version: NGINX Ingress Controller (Helm chart)
- LoadBalancer IP: 192.168.50.80 (via MetalLB)
- Ingress Class: `nginx` (default)
- Replicas: 1

**Components**:
```
Controller Pods:  1/1 Running
Admission Webhook: Running
Metrics Endpoint:  Enabled (port 10254)
```

**Services**:
```
LoadBalancer:     192.168.50.80 (HTTP: 80, HTTPS: 443)
Admission:        ClusterIP (internal)
Metrics:          ClusterIP (Prometheus scraping)
```

**Features**:
- ✅ HTTP/HTTPS routing
- ✅ Host-based routing (virtual hosts)
- ✅ Path-based routing
- ✅ TLS/SSL termination (via cert-manager)
- ✅ WebSocket support
- ✅ Prometheus metrics
- ✅ Single LoadBalancer IP for multiple services

### 6. Harbor Container Registry

**Status**: ✅ Operational
**Documentation**: [HARBOR_SETUP.md](./HARBOR_SETUP.md)

**Configuration**:
- Version: Latest (Helm chart harbor/harbor)
- URL: https://harbor.cloud.local
- Ingress IP: 192.168.50.80 (via MetalLB)
- Admin Password: Harbor12345
- TLS: Enabled (cert-manager with self-signed CA)

**Components**:
```
harbor-core:          1/1 Running (API & Web UI)
harbor-portal:        1/1 Running (Frontend)
harbor-registry:      2/2 Running (Docker Distribution)
harbor-database:      1/1 Running (PostgreSQL)
harbor-redis:         1/1 Running (Cache)
harbor-jobservice:    1/1 Running (Background Jobs)
harbor-trivy:         1/1 Running (Vulnerability Scanner)
```

**Persistent Storage** (Piraeus ZFS+DRBD 2-way):
```
Registry:    20Gi (40Gi with replication)
Database:     5Gi (10Gi with replication)
Redis:        1Gi (2Gi with replication)
Jobservice:   1Gi (2Gi with replication)
Trivy:        5Gi (10Gi with replication)
Total:       32Gi (~64Gi with replication)
```

**Access**:
1. Add to /etc/hosts: `192.168.50.80 harbor.cloud.local`
2. Trust CA: `sudo security add-trusted-cert -k /Library/Keychains/System.keychain docs/talos-ca.crt`
3. Web UI: https://harbor.cloud.local
4. Login: admin / Harbor12345
5. Docker: `docker login harbor.cloud.local`

## Architecture Diagram

```
                                    Internet
                                       |
                      +----------------+----------------+
                      |                                 |
                [192.168.50.0/24 Network]
                      |
         +------------+------------+------------+
         |            |            |            |
    VIP: 192.168.50.100      192.168.50.50-250
         |                    (MetalLB Pool)
         |                         |
    +----+----+              192.168.50.80
    |         |              (NGINX Ingress with HTTPS)
    | Talos   |
    | Control |         +------------------------+
    | Plane   |         |  Storage Layer         |
    |         |         |  (Piraeus/LINSTOR)     |
    | Nodes   |         |                        |
    +---------+         |  ✅ ZFS + DRBD         |
    |         |         |  ~1.5 TB (3x 500GB)    |
    | 3 nodes |         |  2-way replication     |
    |         |         +------------------------+
    +---------+
         |
    +----+----+
    |         |
    | Pods &  |
    | Services|
    |         |
    +---------+
    - Cilium CNI (eBPF networking)
    - NGINX Ingress Controller
    - Cert-Manager (CA + Certificates)
    - MetalLB Speakers
    - Piraeus Components
    - Harbor Container Registry
    - System Workloads
```

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

## Quick Access

### Kubernetes API
```bash
export KUBECONFIG=/path/to/kubeconfig
kubectl get nodes
```

### NGINX Ingress Controller
```bash
# Access URLs
http://192.168.50.80   # HTTP
https://192.168.50.80  # HTTPS (requires cert-manager and certificate)

# Test connectivity
curl http://192.168.50.80
```

### Create Your Own Ingress with HTTPS
```yaml
# First, create a Certificate
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: myapp-cert
  namespace: default
spec:
  secretName: myapp-tls-secret
  issuerRef:
    name: ca-issuer
    kind: ClusterIssuer
  dnsNames:
    - myapp.local
  duration: 2160h  # 90 days
  renewBefore: 360h  # Renew 15 days before expiry
---
# Then, create an Ingress with TLS
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: my-app
  annotations:
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
    nginx.ingress.kubernetes.io/force-ssl-redirect: "true"
spec:
  ingressClassName: nginx
  tls:
  - hosts:
    - myapp.local
    secretName: myapp-tls-secret
  rules:
  - host: myapp.local
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: my-service
            port:
              number: 80
```

## Common Operations

### Check Cluster Status
```bash
# Nodes
kubectl get nodes -o wide

# All pods
kubectl get pods -A

# MetalLB
kubectl get ipaddresspool -n metallb-system
kubectl get services -A -o wide | grep LoadBalancer

# NGINX Ingress
kubectl get pods -n ingress-nginx
kubectl get ingress -A

# Cert-Manager
kubectl get pods -n cert-manager
kubectl get certificates -A
kubectl get clusterissuer

# Piraeus
kubectl get pods -n piraeus-datastore
kubectl -n piraeus-datastore exec deploy/linstor-controller -- linstor node list
kubectl -n piraeus-datastore exec deploy/linstor-controller -- linstor storage-pool list
```

### MetalLB Operations
```bash
# Check MetalLB status
kubectl get pods -n metallb-system
kubectl get ipaddresspool -n metallb-system
kubectl get l2advertisement -n metallb-system

# View speaker logs
kubectl logs -n metallb-system daemonset/speaker

# Check assigned IPs
kubectl get services -A -o json | \
  jq -r '.items[] | select(.spec.type=="LoadBalancer") | "\(.metadata.name)\t\(.status.loadBalancer.ingress[0].ip)"'
```

### NGINX Ingress Operations
```bash
# Check NGINX Ingress status
kubectl get pods -n ingress-nginx
kubectl get svc -n ingress-nginx

# View ingress controller logs
kubectl logs -n ingress-nginx -l app.kubernetes.io/component=controller -f

# Check all ingress resources
kubectl get ingress -A

# Test ingress connectivity
curl -I http://192.168.50.80
```

### Cert-Manager Operations
```bash
# Check cert-manager status
kubectl get pods -n cert-manager

# View all certificates
kubectl get certificates -A

# Check certificate details
kubectl describe certificate <cert-name> -n <namespace>

# View cert-manager logs
kubectl logs -n cert-manager -l app=cert-manager -f

# Check ClusterIssuer status
kubectl get clusterissuer ca-issuer -o yaml

# Force certificate renewal
kubectl delete secret <tls-secret-name> -n <namespace>
# Cert-manager will automatically recreate it
```

## Backup Recommendations

### 1. Kubernetes Configuration
```bash
# Backup kubeconfig
cp kubeconfig kubeconfig.backup

# Export Helm releases
helm list -A -o yaml > helm-releases-backup.yaml

# Backup cert-manager CA
kubectl get secret ca-secret -n cert-manager -o yaml > ca-secret-backup.yaml
```

### 2. Certificate Authority
```bash
# Backup self-signed CA certificate and key
cp docs/talos-ca.crt backups/
cp ca.key backups/
kubectl get secret ca-secret -n cert-manager -o yaml > backups/ca-secret.yaml

# Backup ClusterIssuer configuration
kubectl get clusterissuer ca-issuer -o yaml > backups/ca-issuer.yaml
```

### 3. Ingress and Certificate Configuration
```bash
# Backup all ingress resources
kubectl get ingress -A -o yaml > backups/ingress-backup.yaml

# Backup all certificates
kubectl get certificates -A -o yaml > backups/certificates-backup.yaml
```

## Monitoring and Maintenance

### Health Checks

**Daily**:
- Check all pods are running: `kubectl get pods -A | grep -v Running`
- Check node status: `kubectl get nodes`
- Check LoadBalancer IPs: `kubectl get svc -A | grep LoadBalancer`

**Weekly**:
- Check certificate expiration dates: `kubectl get certificates -A`
- Review MetalLB IP allocation
- Review NGINX Ingress logs for errors
- Update Helm repositories: `helm repo update`

**Monthly**:
- Review certificate renewal history
- Check for component updates (Helm charts)
- Review and rotate credentials
- Test disaster recovery procedures

### Upgrade Paths

**Kubernetes/Talos**:
- Follow Talos upgrade documentation
- Upgrade one node at a time
- Verify cluster health between upgrades

**Cilium**:
```bash
helm repo update
helm upgrade cilium cilium/cilium \
  --version <new-version> \
  --namespace kube-system \
  --reuse-values
```

**MetalLB**:
```bash
helm repo update
helm upgrade my-metallb metallb/metallb \
  --version <new-version> \
  --namespace metallb-system \
  --reuse-values
```

**NGINX Ingress**:
```bash
helm repo update
helm upgrade ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  --reuse-values
```

**Cert-Manager**:
```bash
helm repo update
helm upgrade cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --reuse-values
```

**Piraeus**:
```bash
kubectl apply --server-side -f https://github.com/piraeusdatastore/piraeus-operator/releases/latest/download/manifest.yaml
```

## Troubleshooting

### Common Issues

**Pods in Pending State**:
1. Check node resources: `kubectl describe nodes`
2. Check events: `kubectl get events -A --sort-by='.lastTimestamp'`
3. Check for taints: `kubectl describe nodes | grep -A 5 "Taints:"`

**LoadBalancer Service No External IP**:
1. Check MetalLB pods: `kubectl get pods -n metallb-system`
2. Check IP pools: `kubectl get ipaddresspool -n metallb-system`
3. Check L2 advertisement: `kubectl get l2advertisement -n metallb-system`
4. Review speaker logs: `kubectl logs -n metallb-system daemonset/speaker`

**Ingress Not Accessible**:
1. Check NGINX pods: `kubectl get pods -n ingress-nginx`
2. Check LoadBalancer IP: `kubectl get svc -n ingress-nginx ingress-nginx-controller`
3. Check ingress resources: `kubectl get ingress -A`
4. Check controller logs: `kubectl logs -n ingress-nginx -l app.kubernetes.io/component=controller`

**HTTPS Certificate Issues**:
1. Check certificate status: `kubectl get certificates -A`
2. Check cert-manager logs: `kubectl logs -n cert-manager -l app=cert-manager`
3. Check TLS secret: `kubectl get secret <tls-secret-name> -n <namespace>`
4. Verify CA is trusted on client machine
5. Check ClusterIssuer: `kubectl get clusterissuer ca-issuer`

## Security Considerations

### Current Security Posture

**✅ Implemented**:
- RBAC enabled in Kubernetes
- Network policies (Cilium default)
- Encrypted etcd
- HTTPS/TLS for ingress traffic
- Self-signed CA infrastructure
- Automated certificate management
- Certificate auto-renewal (cert-manager)
- Cilium host firewall enabled
- eBPF-based security policies

**⚠️ Needs Improvement**:
- Self-signed CA (consider Let's Encrypt for public domains)
- No external authentication (consider OIDC/LDAP)
- No network policies for applications
- Storage encryption (requires Piraeus storage pools)

**🔒 Recommended Actions**:
1. Replace self-signed CA with Let's Encrypt for public domains
2. Implement network policies for workloads
3. Enable audit logging
4. Set up backup and disaster recovery
5. Configure monitoring and alerting (Prometheus/Grafana)
6. Implement pod security policies/standards
7. Configure Piraeus storage pools with encryption

## Future Enhancements

### Planned Additions

1. **Monitoring Stack**: Prometheus + Grafana for metrics and dashboards
2. **Logging Stack**: Loki + Promtail for centralized logging
3. **Backup Solution**: Velero for cluster and volume backups
4. **Service Mesh**: Consider Istio or Linkerd for advanced traffic management
5. **CI/CD Integration**: GitOps with ArgoCD or Flux for automated deployments
6. **External Secrets**: External Secrets Operator for secret management
7. **Policy Engine**: OPA/Gatekeeper for policy enforcement

### Capacity Planning

**Current Capacity**:
- Nodes: 3 control-plane nodes (can add workers)
- Storage: ~1.5 TB raw capacity (ZFS + DRBD)
  - 2-way replication: ~750 GB usable
  - Currently used: ~64 GB
  - Available: ~686 GB
- IPs: 200 LoadBalancer IPs available (1 in use)
- Total Pods: 48 running

**Expansion Options**:
- Add dedicated worker nodes
- Add additional storage disks to nodes
- Expand MetalLB IP pool
- Deploy to multiple availability zones
- Expand storage pools for more capacity

## References

- [Talos Linux Documentation](https://www.talos.dev/)
- [Cilium Documentation](https://docs.cilium.io/)
- [Piraeus Operator Documentation](https://github.com/piraeusdatastore/piraeus-operator/blob/v2/docs/README.md)
- [MetalLB Documentation](https://metallb.universe.tf/)
- [NGINX Ingress Controller Documentation](https://kubernetes.github.io/ingress-nginx/)
- [Cert-Manager Documentation](https://cert-manager.io/docs/)
- [Kubernetes Documentation](https://kubernetes.io/docs/)

## Document Updates

| Date | Component | Version | Notes |
|------|-----------|---------|-------|
| 2025-11-10 | Cilium | v1.18.3 | Initial deployment with kube-proxy replacement |
| 2025-11-10 | Piraeus | v2.9.1 | Deployed with ZFS + DRBD (2-way replication) |
| 2025-11-10 | MetalLB | v0.15.2 | Helm-based deployment with L2 mode |
| 2025-11-10 | Cert-Manager | v1.13.3 | Self-signed CA with automated certificate management |
| 2025-11-10 | NGINX Ingress | Latest | Deployed with LoadBalancer (192.168.50.80) |
| 2025-11-10 | Harbor | Latest | Container registry with 32Gi storage (64Gi with replication) |

---

**Last Updated**: 2025-11-10
**Cluster Status**: ✅ Production Ready
**Total Installation Time**: ~30 minutes
**Storage Allocated**: ~64GB (with 2-way replication)
**Available Storage**: ~686GB (with 2-way replication)
