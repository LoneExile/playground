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
| talos-control-01 | 192.168.50.10 | Control Plane | Running |
| talos-control-02 | 192.168.50.9 | Control Plane | Running |
| talos-control-03 | 192.168.50.8 | Control Plane | Running |

**VIP**: 192.168.50.100 (Kubernetes API endpoint)

## Installed Components

### 1. Piraeus Operator (Storage)

**Status**: ✅ Operational
**Documentation**: [PIRAEUS_SETUP.md](./PIRAEUS_SETUP.md)

**Configuration**:
- Storage Pool: `pool1` (~500GB per node, 1.5TB total)
- Storage Driver: LVM Thin Pools
- Replication: DRBD-based block replication
- StorageClasses:
  - `piraeus-storage-single` - 1 replica (testing)
  - `piraeus-storage` - 2-way replication (default)
  - `piraeus-storage-ha` - 3-way replication (critical data)

**Nodes**:
```
talos-control-01: 500GB (Online)
talos-control-02: 500GB (Online)
talos-control-03: 500GB (Online)
```

**Features**:
- ✅ Block storage with DRBD replication
- ✅ LVM thin provisioning
- ✅ CSI driver for Kubernetes
- ✅ Snapshot support
- ✅ Volume expansion

### 2. MetalLB (LoadBalancer)

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

### 3. NGINX Ingress Controller

**Status**: ✅ Operational
**Documentation**: [NGINX_INGRESS_SETUP.md](./NGINX_INGRESS_SETUP.md)

**Configuration**:
- Version: NGINX Ingress Controller 1.14.0 (Chart 4.14.0)
- LoadBalancer IP: 192.168.50.80
- Ingress Class: `nginx` (default)
- Replicas: 2 (high availability)

**Components**:
```
Controller Pods:  2/2 Running
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
- ✅ TLS/SSL termination
- ✅ WebSocket support
- ✅ Prometheus metrics
- ✅ Single LoadBalancer IP for multiple services

**Test Applications**:
- `hello.local` → hello-world service (HTTPS enabled)
- `goodbye.local` → goodbye-world service (HTTPS enabled)

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

**Issued Certificates**:
- `harbor.cloud.local` - 90-day certificate (includes core.harbor.cloud.local, notary.harbor.cloud.local)

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

### 5. Harbor Container Registry

**Status**: ✅ Operational
**Documentation**: [HARBOR_SETUP.md](./HARBOR_SETUP.md)

**Configuration**:
- Access URL: https://harbor.cloud.local
- Ingress: NGINX Ingress Controller
- Certificate: Self-signed (via cert-manager)
- Default Credentials: admin / Harbor12345

**Components**:
```
Harbor Core:      1/1 Running
Harbor Portal:    1/1 Running
Harbor Registry:  2/2 Running
PostgreSQL:       1/1 Running
Redis:            1/1 Running
Jobservice:       1/1 Running
Trivy Scanner:    1/1 Running
```

**Storage Allocated (Piraeus)**:
```
Registry:     20Gi (2-way replication)
Database:      5Gi (2-way replication)
Redis:         1Gi (2-way replication)
Jobservice:    1Gi (2-way replication)
Trivy:         5Gi (2-way replication)
Total:        32Gi
```

**Features**:
- ✅ Container image registry
- ✅ Vulnerability scanning (Trivy)
- ✅ RBAC and project management
- ✅ Image replication
- ✅ HTTPS with self-signed certificate
- ✅ Webhook notifications
- ✅ Audit logging

**Quick Start**:
```bash
# Add to /etc/hosts
echo "192.168.50.80 harbor.cloud.local" | sudo tee -a /etc/hosts

# Configure Docker
sudo mkdir -p /etc/docker/certs.d/harbor.cloud.local
sudo cp docs/talos-ca.crt /etc/docker/certs.d/harbor.cloud.local/ca.crt

# Login
docker login harbor.cloud.local
# Username: admin, Password: Harbor12345

# Push an image
docker tag nginx:alpine harbor.cloud.local/library/nginx:alpine
docker push harbor.cloud.local/library/nginx:alpine
```

## Quick Access

### Kubernetes API
```bash
export KUBECONFIG=/path/to/kubeconfig
kubectl get nodes
```

### Harbor Container Registry
```bash
# Add to /etc/hosts
echo "192.168.50.80 harbor.cloud.local" | sudo tee -a /etc/hosts

# Trust the CA certificate (macOS)
sudo security add-trusted-cert -d -r trustRoot \
  -k /Library/Keychains/System.keychain \
  docs/talos-ca.crt

# Configure Docker to trust the CA
sudo mkdir -p /etc/docker/certs.d/harbor.cloud.local
sudo cp docs/talos-ca.crt /etc/docker/certs.d/harbor.cloud.local/ca.crt

# Access Web UI
https://harbor.cloud.local
# Username: admin, Password: Harbor12345

# Login with Docker
docker login harbor.cloud.local

# Push an image
docker tag nginx:alpine harbor.cloud.local/library/nginx:alpine
docker push harbor.cloud.local/library/nginx:alpine
```

### NGINX Ingress Controller with HTTPS
```bash
# Access URLs
http://192.168.50.80   # HTTP (redirects to HTTPS)
https://192.168.50.80  # HTTPS

# Add to /etc/hosts
echo "192.168.50.80 hello.local goodbye.local" | sudo tee -a /etc/hosts

# Trust the CA certificate (macOS)
sudo security add-trusted-cert -d -r trustRoot \
  -k /Library/Keychains/System.keychain \
  docs/talos-ca.crt

# Then access via browser (HTTPS)
https://hello.local
https://goodbye.local

# Test with curl (after trusting CA)
curl https://hello.local
curl https://goodbye.local
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
    |         |         |  (Piraeus/DRBD)        |
    | Nodes   |         |                        |
    +---------+         |  pool1: 500GB × 3      |
    |         |         |  DRBD Replication      |
    | 1, 2, 3 |<------->|  2-way / 3-way         |
    |         |         +------------------------+
    +---------+
         |
    +----+----+
    |         |
    | Pods &  |
    | Services|
    |         |
    +---------+
    - NGINX Ingress Controller
    - Cert-Manager (CA + Certificates)
    - Harbor Container Registry
    - Piraeus Components
    - MetalLB Speakers
    - System Workloads
```

## Storage Architecture

```
                       Piraeus Operator
                             |
              +--------------+--------------+
              |              |              |
         Node 01         Node 02        Node 03
       (500GB pool1)   (500GB pool1)  (500GB pool1)
              |              |              |
              +------DRBD----+------DRBD----+
                    (Replication)

Storage Classes:
- piraeus-storage-single → 1 replica (1 node)
- piraeus-storage (default) → 2 replicas (2 nodes)
- piraeus-storage-ha → 3 replicas (all 3 nodes)

Current Usage:
- System volumes for cluster components
- Ready for application persistent volumes
- ~1.5TB total capacity available
```

## Network Architecture

```
192.168.50.0/24 Network
│
├─ 192.168.50.8     → talos-control-03
├─ 192.168.50.9     → talos-control-02
├─ 192.168.50.10    → talos-control-01
├─ 192.168.50.100   → Kubernetes VIP (kube-apiserver)
│
└─ 192.168.50.50-250 → MetalLB IP Pool
   │
   ├─ 192.168.50.80  → NGINX Ingress Controller (HTTP/HTTPS)
   │                    └─ harbor.cloud.local (Harbor Registry - HTTPS)
   └─ 192.168.50.50-79, 81-250 → Available for services
```

## Resource Utilization

### Storage Breakdown
```
Total Storage: 1500GB (500GB × 3 nodes)

Allocated:
- System volumes:      ~10GB
- Harbor Registry:     ~32GB (20GB registry, 5GB DB, 5GB Trivy, 2GB misc)

Available: ~1458GB
```

### IP Address Allocation
```
Total MetalLB IPs: 201 (192.168.50.50-250)

Assigned:
- NGINX Ingress: 192.168.50.80

Available: 200 IPs
```

## Common Operations

### Check Cluster Status
```bash
# Nodes
kubectl get nodes -o wide

# All pods
kubectl get pods -A

# Storage
kubectl get pvc -A
kubectl get sc

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
```

### Check Piraeus Storage
```bash
# LINSTOR nodes
kubectl -n piraeus-datastore exec deploy/linstor-controller -- linstor node list

# Storage pools
kubectl -n piraeus-datastore exec deploy/linstor-controller -- linstor storage-pool list

# Resources/volumes
kubectl -n piraeus-datastore exec deploy/linstor-controller -- linstor resource list
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
curl -H "Host: hello.local" http://192.168.50.80
curl -k https://hello.local
```

### Cert-Manager Operations
```bash
# Check cert-manager status
kubectl get pods -n cert-manager

# View all certificates
kubectl get certificates -A

# Check certificate details
kubectl describe certificate hello-cert -n default

# View cert-manager logs
kubectl logs -n cert-manager -l app=cert-manager -f

# Check ClusterIssuer status
kubectl get clusterissuer ca-issuer -o yaml

# Force certificate renewal
kubectl delete secret hello-tls-secret -n default
# Cert-manager will automatically recreate it
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

# Backup NGINX Ingress configuration
helm get values my-ingress-nginx -n ingress-nginx > backups/nginx-values.yaml
```

### 4. Persistent Volumes
```bash
# Using Piraeus snapshots
kubectl -n piraeus-datastore exec deploy/linstor-controller -- \
  linstor snapshot create <resource-name> backup-$(date +%Y%m%d)

# Using velero (if installed)
velero backup create full-backup --include-namespaces ingress-nginx,cert-manager
```

## Monitoring and Maintenance

### Health Checks

**Daily**:
- Check all pods are running: `kubectl get pods -A | grep -v Running`
- Check PVC status: `kubectl get pvc -A | grep -v Bound`
- Check node status: `kubectl get nodes`

**Weekly**:
- Check certificate expiration dates: `kubectl get certificates -A`
- Check Piraeus storage pool capacity
- Review MetalLB IP allocation
- Review NGINX Ingress logs for errors
- Update Helm repositories: `helm repo update`

**Monthly**:
- Review certificate renewal history
- Check for component updates (Helm charts)
- Review and rotate credentials
- Test disaster recovery procedures
- Review ingress access logs

### Upgrade Paths

**Kubernetes/Talos**:
- Follow Talos upgrade documentation
- Upgrade one node at a time
- Verify cluster health between upgrades

**Piraeus**:
```bash
kubectl apply -f https://github.com/piraeusdatastore/piraeus-operator/releases/latest/download/manifest.yaml
```

**MetalLB**:
```bash
helm repo update
helm upgrade my-metallb metallb/metallb \
  --version NEW_VERSION \
  --namespace metallb-system \
  --reuse-values
```

**NGINX Ingress**:
```bash
helm repo update
helm upgrade my-ingress-nginx ingress-nginx/ingress-nginx \
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

## Troubleshooting

### Common Issues

**PVC Stuck in Pending**:
1. Check Piraeus satellites: `kubectl get pods -n piraeus-datastore`
2. Check storage pools: `kubectl -n piraeus-datastore exec deploy/linstor-controller -- linstor storage-pool list`
3. Check CSI driver: `kubectl get pods -n piraeus-datastore | grep csi`

**LoadBalancer Service No External IP**:
1. Check MetalLB pods: `kubectl get pods -n metallb-system`
2. Check IP pools: `kubectl get ipaddresspool -n metallb-system`
3. Check L2 advertisement: `kubectl get l2advertisement -n metallb-system`
4. Review speaker logs: `kubectl logs -n metallb-system daemonset/speaker`

**Ingress Not Accessible**:
1. Check NGINX pods: `kubectl get pods -n ingress-nginx`
2. Check LoadBalancer IP: `kubectl get svc -n ingress-nginx ingress-nginx-controller`
3. Check ingress resources: `kubectl get ingress -A`
4. Verify DNS/hosts entry: `cat /etc/hosts | grep hello.local`
5. Check controller logs: `kubectl logs -n ingress-nginx -l app.kubernetes.io/component=controller`

**HTTPS Certificate Issues**:
1. Check certificate status: `kubectl get certificates -A`
2. Check cert-manager logs: `kubectl logs -n cert-manager -l app=cert-manager`
3. Check TLS secret: `kubectl get secret hello-tls-secret -n default`
4. Verify CA is trusted on client machine
5. Check ClusterIssuer: `kubectl get clusterissuer ca-issuer`

**Storage Full**:
1. Check usage: `kubectl -n piraeus-datastore exec deploy/linstor-controller -- linstor storage-pool list`
2. Delete unused PVCs: `kubectl get pvc -A`
3. Consider expanding storage pools
4. Check for orphaned volumes

## Security Considerations

### Current Security Posture

**✅ Implemented**:
- RBAC enabled in Kubernetes
- Network policies (Talos default)
- Encrypted etcd
- Piraeus volumes encrypted at rest
- HTTPS/TLS for all ingress traffic
- Self-signed CA infrastructure
- Automated certificate management
- Certificate auto-renewal (cert-manager)

**⚠️ Needs Improvement**:
- Self-signed CA (consider Let's Encrypt for public domains)
- No external authentication (consider OIDC/LDAP)
- No network policies for applications
- Test applications running (should remove in production)

**🔒 Recommended Actions**:
1. Replace self-signed CA with Let's Encrypt for public domains
2. Implement network policies for workloads
3. Enable audit logging
4. Set up backup and disaster recovery
5. Configure monitoring and alerting (Prometheus/Grafana)
6. Remove test applications before production use
7. Implement pod security policies/standards

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
- Storage: ~1490GB available (1.5TB total)
- IPs: 200 LoadBalancer IPs available (1 in use)

**Expansion Options**:
- Add dedicated worker nodes
- Add more storage disks to existing nodes
- Expand MetalLB IP pool
- Deploy to multiple availability zones

## References

- [Talos Linux Documentation](https://www.talos.dev/)
- [Piraeus Operator Documentation](https://github.com/piraeusdatastore/piraeus-operator/blob/v2/docs/README.md)
- [MetalLB Documentation](https://metallb.universe.tf/)
- [NGINX Ingress Controller Documentation](https://kubernetes.github.io/ingress-nginx/)
- [Cert-Manager Documentation](https://cert-manager.io/docs/)
- [Kubernetes Documentation](https://kubernetes.io/docs/)

## Document Updates

| Date | Component | Version | Notes |
|------|-----------|---------|-------|
| 2025-11-04 | Piraeus | v2.9.1 | Initial deployment with 3-way replication |
| 2025-11-04 | MetalLB | v0.15.2 | Initial L2 mode deployment (manifest-based) |
| 2025-11-06 | MetalLB | v0.15.2 | Migrated to Helm chart, fixed eth0 interface issue |
| 2025-11-06 | NGINX Ingress | v1.14.0 | Deployed with LoadBalancer (192.168.50.80) |
| 2025-11-06 | Cert-Manager | v1.13.3 | Self-signed CA with automated certificate management |
| 2025-11-06 | Harbor | 2.14.0 | Deployed then removed (not needed) |

---

**Last Updated**: 2025-11-06
**Cluster Status**: ✅ Fully Operational with HTTPS
**Next Review**: 2025-11-13
