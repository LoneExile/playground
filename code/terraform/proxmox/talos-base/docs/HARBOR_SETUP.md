# Complete Guide: Harbor Container Registry on Talos Kubernetes

This guide walks you through deploying Harbor, an open-source container registry, on a Talos Kubernetes cluster using Helm with HTTPS and NGINX Ingress.

## Quick Installation Summary

**Installed Version**: Harbor (Helm Chart: harbor/harbor)
**Access URL**: https://harbor.cloud.local
**Admin Credentials**: admin / Harbor12345
**Status**: ✅ Fully Operational

### Current Deployment

```
Components Running:
✓ Harbor Core (API & Web UI)
✓ Harbor Portal (Frontend)
✓ Harbor Registry (Docker Distribution)
✓ PostgreSQL Database
✓ Redis Cache
✓ Jobservice (Background Jobs)
✓ Trivy (Vulnerability Scanner)

Storage Allocated (Piraeus Storage):
- Registry:     20Gi (2-way replication)
- Database:      5Gi (2-way replication)
- Redis:         1Gi (2-way replication)
- Jobservice:    1Gi (2-way replication)
- Trivy:         5Gi (2-way replication)

External Access:
- Domain: harbor.cloud.local
- Ingress: NGINX Ingress Controller
- LoadBalancer IP: 192.168.50.80 (via MetalLB)
- Protocol: HTTPS (self-signed certificate via cert-manager)
```

### Quick Start

1. **Add harbor.cloud.local to /etc/hosts**:
   ```bash
   echo "192.168.50.80 harbor.cloud.local" | sudo tee -a /etc/hosts
   ```

2. **Trust the CA certificate** (macOS):
   ```bash
   sudo security add-trusted-cert -d -r trustRoot \
     -k /Library/Keychains/System.keychain docs/talos-ca.crt
   ```

3. **Access Web UI**: Open browser to https://harbor.cloud.local

4. **Login**: Username `admin`, Password `Harbor12345`

5. **Configure Docker** to trust the CA:
   ```bash
   # macOS/Linux
   sudo mkdir -p /etc/docker/certs.d/harbor.cloud.local
   sudo cp docs/talos-ca.crt /etc/docker/certs.d/harbor.cloud.local/ca.crt
   sudo systemctl restart docker  # Linux only
   ```

6. **Login to Harbor**:
   ```bash
   docker login harbor.cloud.local
   ```

7. **Push an image**:
   ```bash
   docker tag nginx:alpine harbor.cloud.local/library/nginx:alpine
   docker push harbor.cloud.local/library/nginx:alpine
   ```

---

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Architecture Overview](#architecture-overview)
3. [Step 1: Prepare for Installation](#step-1-prepare-for-installation)
4. [Step 2: Install Harbor with Helm](#step-2-install-harbor-with-helm)
5. [Step 3: Access Harbor](#step-3-access-harbor)
6. [Step 4: Configure Docker/Podman](#step-4-configure-dockerpodman)
7. [Step 5: Push and Pull Images](#step-5-push-and-pull-images)
8. [Troubleshooting](#troubleshooting)
9. [Production Considerations](#production-considerations)

## Prerequisites

- **Talos Kubernetes cluster** running and accessible
- **kubectl** configured with cluster access
- **Helm 3** installed
- **StorageClass** available (e.g., Piraeus storage)
- **MetalLB** or LoadBalancer capability
- **Domain name** or accessible IP address

### Component Requirements

- **Storage**: Persistent volumes for registry, database, Redis, and job logs
- **LoadBalancer**: External access via MetalLB (L2) or cloud provider LoadBalancer
- **Resources**: Minimum 4 CPU cores and 8GB RAM recommended

## Architecture Overview

Harbor consists of several components:
- **Core**: Main API server and web UI
- **Portal**: Web UI frontend
- **Registry**: Docker registry (distribution)
- **Database (PostgreSQL)**: Metadata storage
- **Redis**: Caching and job queue
- **Jobservice**: Asynchronous job execution
- **Chartmuseum** (optional): Helm chart repository
- **Trivy** (optional): Vulnerability scanner
- **Notary** (optional): Image signing

## Step 1: Prepare for Installation

### 1.1: Add Harbor Helm Repository

```bash
helm repo add harbor https://helm.goharbor.io
helm repo update
```

### 1.2: Create Namespace

```bash
kubectl create namespace harbor
```

### 1.3: Verify Prerequisites

Check that you have a StorageClass:
```bash
kubectl get storageclass
```

You should see your default StorageClass (e.g., `piraeus-storage`).

Check that MetalLB is ready:
```bash
kubectl get pods -n metallb-system
```

All MetalLB pods should be running.

### 1.4: Plan Your Configuration

Decide on these key parameters:

| Parameter | Example | Description |
|-----------|---------|-------------|
| **External URL** | `https://harbor.example.com` | How users access Harbor |
| **External IP** | `192.168.50.80` | LoadBalancer IP (if not using domain) |
| **Storage size** | Registry: 100Gi, DB: 5Gi | Persistent volume sizes |
| **Admin password** | `HarborAdmin123` | Initial admin password |
| **TLS/SSL** | Enabled/Disabled | HTTPS configuration |

## Step 2: Install Harbor with Helm

### 2.1: Create Certificate for Harbor

First, create a cert-manager Certificate for Harbor:

```bash
cat <<EOF | kubectl apply -f -
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: harbor-cert
  namespace: default
spec:
  secretName: harbor-tls-secret
  issuerRef:
    name: ca-issuer
    kind: ClusterIssuer
  dnsNames:
    - harbor.cloud.local
    - core.harbor.cloud.local
    - notary.harbor.cloud.local
  duration: 2160h  # 90 days
  renewBefore: 360h  # Renew 15 days before expiry
EOF
```

Verify the certificate is ready:
```bash
kubectl get certificate harbor-cert -n default
# Should show READY = True
```

### 2.2: Installation with Ingress and HTTPS

Create a `harbor-values.yaml` file:

```yaml
# harbor-values.yaml
expose:
  type: ingress
  tls:
    enabled: true
    certSource: secret
    secret:
      secretName: harbor-tls-secret
  ingress:
    hosts:
      core: harbor.cloud.local
    className: nginx
    annotations:
      cert-manager.io/cluster-issuer: ca-issuer

externalURL: https://harbor.cloud.local

# Use Piraeus storage
persistence:
  enabled: true
  persistentVolumeClaim:
    registry:
      storageClass: piraeus-storage
      size: 20Gi
    chartmuseum:
      storageClass: piraeus-storage
      size: 5Gi
    jobservice:
      jobLog:
        storageClass: piraeus-storage
        size: 1Gi
    database:
      storageClass: piraeus-storage
      size: 5Gi
    redis:
      storageClass: piraeus-storage
      size: 1Gi
    trivy:
      storageClass: piraeus-storage
      size: 5Gi

# Resource limits
core:
  resources:
    requests:
      memory: 256Mi
      cpu: 100m
    limits:
      memory: 512Mi
      cpu: 500m

jobservice:
  resources:
    requests:
      memory: 256Mi
      cpu: 100m
    limits:
      memory: 512Mi
      cpu: 500m

registry:
  resources:
    requests:
      memory: 256Mi
      cpu: 100m
    limits:
      memory: 512Mi
      cpu: 500m

database:
  internal:
    resources:
      requests:
        memory: 256Mi
        cpu: 100m
      limits:
        memory: 512Mi
        cpu: 500m

redis:
  internal:
    resources:
      requests:
        memory: 256Mi
        cpu: 100m
      limits:
        memory: 512Mi
        cpu: 500m

trivy:
  enabled: true
  resources:
    requests:
      memory: 256Mi
      cpu: 100m
    limits:
      memory: 512Mi
      cpu: 500m

# Default admin password (change after first login)
harborAdminPassword: Harbor12345
```

### 2.3: Install Harbor

```bash
helm install harbor harbor/harbor \
  --namespace harbor \
  --create-namespace \
  --values harbor-values.yaml
```

Monitor the installation:

```bash
# Watch pods starting up
kubectl get pods -n harbor -w

# Check ingress
kubectl get ingress -n harbor

# Verify certificate
kubectl get certificate harbor-cert -n default
```

Harbor installation takes 3-5 minutes. Wait for all pods to be **Running**.

### 2.4: Alternative Installation Methods

#### Option A: LoadBalancer with HTTP (Not Recommended)

For production with TLS/SSL:

1. **Create TLS certificate** (self-signed or Let's Encrypt):

```bash
# Self-signed certificate (for testing)
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout harbor-key.pem \
  -out harbor-cert.pem \
  -subj "/CN=harbor.example.com/O=MyOrg"

# Create Kubernetes secret
kubectl create secret tls harbor-tls \
  --cert=harbor-cert.pem \
  --key=harbor-key.pem \
  -n harbor
```

2. **Update values file** for HTTPS:

```yaml
expose:
  type: loadBalancer
  tls:
    enabled: true
    certSource: secret
    secret:
      secretName: harbor-tls
  loadBalancer:
    name: harbor
    IP: 192.168.50.80
    ports:
      httpsPort: 443

externalURL: https://harbor.example.com
```

### 2.4: Monitor Installation Progress

```bash
# Watch pods starting up
kubectl get pods -n harbor -w

# Check Helm release status
helm status harbor -n harbor
```

Harbor installation takes 3-5 minutes. Wait for all pods to be **Running**.

## Step 3: Access Harbor

### 3.1: Get Ingress Information

```bash
kubectl get ingress -n harbor
```

Expected output:
```
NAME             CLASS   HOSTS                ADDRESS         PORTS     AGE
harbor-ingress   nginx   harbor.cloud.local   192.168.50.80   80, 443   5m
```

### 3.2: Configure Local DNS

Add harbor.cloud.local to your `/etc/hosts` file:

```bash
echo "192.168.50.80 harbor.cloud.local" | sudo tee -a /etc/hosts
```

### 3.3: Trust the CA Certificate

**macOS:**
```bash
sudo security add-trusted-cert -d -r trustRoot \
  -k /Library/Keychains/System.keychain docs/talos-ca.crt
```

**Linux:**
```bash
sudo cp docs/talos-ca.crt /usr/local/share/ca-certificates/talos-ca.crt
sudo update-ca-certificates
```

### 3.4: Access Web UI

Open a browser and navigate to:
- **HTTPS**: `https://harbor.cloud.local`

**Default credentials:**
- Username: `admin`
- Password: `Harbor12345` (change after first login)

### 3.5: Verify Installation

After logging in:
1. Check the **Projects** page - you should see the default `library` project
2. Go to **System Settings** → **Configuration** to verify settings
3. Check **Administration** → **Replications** (should be empty initially)
4. Verify **Interrogation Services** → **Scanners** shows Trivy (if enabled)

### 3.4: Initial Configuration

1. **Change admin password**: Click on admin user → Change Password
2. **Create a project**:
   - Go to **Projects** → **+ NEW PROJECT**
   - Name: `my-app`
   - Access Level: Private (or Public for testing)
   - Click **OK**

## Step 4: Configure Docker/Podman

### 4.1: Configure Docker to Trust the CA Certificate

**Docker on macOS:**
```bash
# Copy CA certificate to Docker certs directory
sudo mkdir -p /etc/docker/certs.d/harbor.cloud.local
sudo cp docs/talos-ca.crt /etc/docker/certs.d/harbor.cloud.local/ca.crt
```

**Docker on Linux:**
```bash
# Copy CA certificate to Docker certs directory
sudo mkdir -p /etc/docker/certs.d/harbor.cloud.local
sudo cp docs/talos-ca.crt /etc/docker/certs.d/harbor.cloud.local/ca.crt

# Restart Docker
sudo systemctl restart docker
```

**Docker Desktop (Mac/Windows):**
- The certificate should already be trusted if you added it to the system keychain
- Alternatively, copy it to Docker's certificate directory as shown above

**Podman:**
```bash
# Copy CA certificate to system trust store
sudo cp docs/talos-ca.crt /etc/pki/ca-trust/source/anchors/
sudo update-ca-trust
```

### 4.2: Login to Harbor

```bash
docker login harbor.cloud.local
# Username: admin
# Password: Harbor12345
```

Expected output:
```
Login Succeeded
```

### 4.3: Troubleshooting Docker Login

If login fails with certificate errors:

**Error: "x509: certificate signed by unknown authority"**

Solution:
1. Verify the CA cert is in the correct directory
2. Restart Docker daemon
3. Test with curl: `curl -v https://harbor.cloud.local`

## Step 5: Push and Pull Images

### 5.1: Tag and Push an Image

```bash
# Pull a test image
docker pull nginx:alpine

# Tag for Harbor
docker tag nginx:alpine harbor.cloud.local/library/nginx:alpine

# Push to Harbor
docker push harbor.cloud.local/library/nginx:alpine
```

Expected output:
```
The push refers to repository [harbor.cloud.local/library/nginx]
...
alpine: digest: sha256:... size: 1234
```

### 5.2: Verify in Web UI

1. Go to Harbor web UI at https://harbor.cloud.local
2. Navigate to **Projects** → **library**
3. You should see the `nginx` repository
4. Click on `nginx` to see the `alpine` tag

### 5.3: Pull Image from Harbor

```bash
# Remove local image
docker rmi harbor.cloud.local/library/nginx:alpine

# Pull from Harbor
docker pull harbor.cloud.local/library/nginx:alpine
```

### 5.4: Use Harbor Image in Kubernetes

Create a deployment using a Harbor image:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx-from-harbor
spec:
  replicas: 1
  selector:
    matchLabels:
      app: nginx
  template:
    metadata:
      labels:
        app: nginx
    spec:
      containers:
      - name: nginx
        image: harbor.cloud.local/library/nginx:alpine
        ports:
        - containerPort: 80
      imagePullSecrets:
      - name: harbor-registry
```

Create the image pull secret:

```bash
kubectl create secret docker-registry harbor-registry \
  --docker-server=harbor.cloud.local \
  --docker-username=admin \
  --docker-password=Harbor12345 \
  --docker-email=admin@example.com
```

## Troubleshooting

### Pods Stuck in Pending

**Symptom:**
```bash
kubectl get pods -n harbor
# Shows pods in Pending state
```

**Diagnosis:**
```bash
kubectl describe pod <pod-name> -n harbor | grep -A10 Events
```

**Common Causes:**

#### Issue 1: No StorageClass available

**Solution**: Verify StorageClass exists:
```bash
kubectl get storageclass
```

If missing, create one or specify an existing StorageClass in values.yaml.

#### Issue 2: PVC not bound

**Solution**: Check PVCs:
```bash
kubectl get pvc -n harbor
```

If stuck in Pending, check CSI driver (e.g., Piraeus) is working.

### Cannot Access Harbor Web UI

**Symptom**: Browser shows connection refused or timeout.

**Diagnosis:**

1. Check service has external IP:
```bash
kubectl get service harbor -n harbor
```

2. Check LoadBalancer (MetalLB) is announcing the IP:
```bash
kubectl logs -n metallb-system daemonset/speaker | grep harbor
```

3. Check harbor pod is running:
```bash
kubectl get pods -n harbor
```

**Solution**:
- Ensure MetalLB is configured correctly
- Verify the IP is in your MetalLB pool range
- Check firewall rules if accessing from external network

### Docker Login Fails with "x509: certificate signed by unknown authority"

**Symptom**:
```
Error response from daemon: Get "https://192.168.50.80/v2/": x509: certificate signed by unknown authority
```

**Solution**:
- Add self-signed certificate to Docker's trusted certificates (see [Step 4.2](#42-https-with-self-signed-certificate))
- Or use HTTP with insecure registry configuration

### Push Fails with "denied: requested access to the resource is denied"

**Symptom**:
```
denied: requested access to the resource is denied
```

**Solution**:
1. Verify you're logged in: `docker login 192.168.50.80`
2. Check project exists in Harbor UI
3. Verify image name format: `<harbor-ip>/<project>/<image>:<tag>`
4. Check user has push permissions for the project

### Harbor Core Pod CrashLoopBackOff

**Symptom**:
```bash
kubectl get pods -n harbor
# harbor-core-xxx shows CrashLoopBackOff
```

**Diagnosis**:
```bash
kubectl logs -n harbor harbor-core-xxx
```

**Common Causes**:
- Database connection issues
- Database password mismatch
- Database not ready

**Solution**:
1. Check database pod is running:
```bash
kubectl get pods -n harbor | grep database
```

2. Verify database password in values.yaml matches deployed secret

3. Restart core pod:
```bash
kubectl delete pod -n harbor harbor-core-xxx
```

### Out of Disk Space

**Symptom**: Registry or database pod shows disk space errors.

**Diagnosis**:
```bash
kubectl get pvc -n harbor
kubectl exec -n harbor <registry-pod> -- df -h /storage
```

**Solution**:
Resize PVCs (if StorageClass supports volume expansion):

```bash
# Edit PVC to increase size
kubectl edit pvc harbor-registry -n harbor
# Change spec.resources.requests.storage to larger value (e.g., 200Gi)
```

Or clean up old images:
1. Go to Harbor UI → Projects → Repository
2. Delete unused images and tags
3. Run garbage collection: **Administration** → **Garbage Collection** → **GC Now**

## Production Considerations

### High Availability

For production HA setup:

1. **External Database**: Use external PostgreSQL cluster instead of internal
```yaml
database:
  type: external
  external:
    host: postgres.example.com
    port: 5432
    username: harbor
    password: secretpassword
    coreDatabase: registry
```

2. **External Redis**: Use external Redis cluster
```yaml
redis:
  type: external
  external:
    addr: redis.example.com:6379
    password: secretpassword
```

3. **Multiple Replicas**: Scale Harbor components
```yaml
portal:
  replicas: 2
core:
  replicas: 2
registry:
  replicas: 2
```

4. **Shared Storage**: Use object storage (S3-compatible) for registry images
```yaml
persistence:
  imageChartStorage:
    type: s3
    s3:
      region: us-east-1
      bucket: harbor-registry
      accesskey: AWS_ACCESS_KEY
      secretkey: AWS_SECRET_KEY
```

### HTTPS with Let's Encrypt

For automatic TLS certificates with cert-manager:

1. **Install cert-manager**:
```bash
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.3/cert-manager.yaml
```

2. **Create ClusterIssuer**:
```yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: admin@example.com
    privateKeySecretRef:
      name: letsencrypt-prod
    solvers:
    - http01:
        ingress:
          class: nginx
```

3. **Update Harbor values for Ingress**:
```yaml
expose:
  type: ingress
  tls:
    enabled: true
    certSource: auto
    auto:
      commonName: harbor.example.com
  ingress:
    hosts:
      core: harbor.example.com
    className: nginx
    annotations:
      cert-manager.io/cluster-issuer: letsencrypt-prod
```

### Storage Backend Options

Harbor supports multiple storage backends:

| Backend | Use Case | Configuration |
|---------|----------|---------------|
| **Filesystem** | Small deployments, local storage | Default (PVC) |
| **S3** | AWS, MinIO, Ceph | Object storage, HA ready |
| **Azure Blob** | Azure environments | Azure-native storage |
| **GCS** | Google Cloud | GCP-native storage |
| **Swift** | OpenStack | Swift object storage |

Example S3 configuration:
```yaml
persistence:
  imageChartStorage:
    type: s3
    s3:
      region: us-east-1
      bucket: my-harbor-registry
      encrypt: true
      secure: true
      accesskey: AKIAIOSFODNN7EXAMPLE
      secretkey: wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY
```

### Security Best Practices

1. **Change default passwords**: Immediately change admin and database passwords

2. **Enable HTTPS**: Always use TLS in production

3. **Enable vulnerability scanning**: Use Trivy or integrate with other scanners

4. **Content trust**: Enable Notary for image signing
```yaml
notary:
  enabled: true
```

5. **RBAC**: Use Harbor's project-based access control
   - Create separate projects for teams
   - Assign appropriate roles (Admin, Developer, Guest)

6. **Image replication**: Set up replication policies for disaster recovery

7. **Enable audit logs**: Review logs regularly
```bash
kubectl logs -n harbor harbor-core-xxx | grep audit
```

8. **Webhooks**: Configure webhooks for security scanning notifications

### Backup and Restore

#### Backup Harbor Data

1. **Database backup**:
```bash
# Get database pod
DB_POD=$(kubectl get pods -n harbor -l component=database -o jsonpath='{.items[0].metadata.name}')

# Backup database
kubectl exec -n harbor $DB_POD -- pg_dump -U postgres registry > harbor-db-backup.sql
```

2. **PVC backup**: Use Piraeus snapshots or velero
```bash
# Using velero
velero backup create harbor-backup --include-namespaces harbor
```

3. **Export configuration**:
```bash
helm get values harbor -n harbor > harbor-values-backup.yaml
```

#### Restore Harbor

1. **Restore PVCs** from backup

2. **Restore database**:
```bash
kubectl exec -i -n harbor $DB_POD -- psql -U postgres registry < harbor-db-backup.sql
```

3. **Reinstall Harbor** with backed-up configuration:
```bash
helm install harbor harbor/harbor -n harbor -f harbor-values-backup.yaml
```

### Monitoring and Metrics

Harbor exposes Prometheus metrics:

```yaml
# In harbor-values.yaml
metrics:
  enabled: true
  core:
    path: /metrics
    port: 8001
  registry:
    path: /metrics
    port: 8001
  exporter:
    port: 8001
```

Create ServiceMonitor for Prometheus Operator:
```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: harbor
  namespace: harbor
spec:
  selector:
    matchLabels:
      app: harbor
  endpoints:
  - port: metrics
    path: /metrics
```

### Resource Planning

Recommended resources for different scales:

| Deployment Size | Users | Images | CPU | Memory | Storage |
|----------------|-------|--------|-----|--------|---------|
| **Small** | <50 | <1000 | 4 cores | 8 GB | 100 GB |
| **Medium** | 50-200 | 1000-5000 | 8 cores | 16 GB | 500 GB |
| **Large** | 200+ | 5000+ | 16+ cores | 32+ GB | 1+ TB |

### Garbage Collection

Harbor stores deleted images until garbage collection runs:

1. **Manual GC**: Administration → Garbage Collection → GC Now
2. **Scheduled GC**: Configure cron schedule
```yaml
jobservice:
  jobLoggers:
    - stdout
  # Run GC every day at 2 AM
  schedule:
    - type: Daily
      cron: "0 2 * * *"
```

## Common Use Cases

### 1. CI/CD Integration

**GitHub Actions example**:
```yaml
name: Build and Push to Harbor
on: [push]
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
    - uses: actions/checkout@v2

    - name: Login to Harbor
      run: docker login 192.168.50.80 -u admin -p ${{ secrets.HARBOR_PASSWORD }}

    - name: Build and push
      run: |
        docker build -t 192.168.50.80/my-app/myimage:${{ github.sha }} .
        docker push 192.168.50.80/my-app/myimage:${{ github.sha }}
```

### 2. Helm Chart Repository

Harbor includes Chartmuseum for Helm charts:

```bash
# Add Harbor as Helm repo
helm repo add my-harbor http://192.168.50.80/chartrepo/library

# Push a Helm chart
helm push my-chart.tgz my-harbor
```

### 3. Image Replication

Set up replication between registries:
1. Go to **Administration** → **Registries** → **+ NEW ENDPOINT**
2. Add remote registry (Docker Hub, another Harbor, etc.)
3. Create replication rule: **Administration** → **Replications** → **+ NEW REPLICATION RULE**
4. Configure source/destination and triggers

### 4. Robot Accounts for CI/CD

Create robot accounts for automated access:
1. Go to project → **Robot Accounts** → **+ NEW ROBOT ACCOUNT**
2. Set name: `robot-ci`
3. Grant permissions (push, pull)
4. Copy generated token
5. Use in CI/CD: `docker login -u robot$robot-ci -p <token>`

## References

- [Harbor Official Documentation](https://goharbor.io/docs/)
- [Harbor GitHub Repository](https://github.com/goharbor/harbor)
- [Harbor Helm Chart](https://github.com/goharbor/harbor-helm)
- [Harbor Security Advisories](https://github.com/goharbor/harbor/security/advisories)

## Appendix: Complete Values File Example

```yaml
# production-harbor-values.yaml
expose:
  type: loadBalancer
  tls:
    enabled: true
    certSource: secret
    secret:
      secretName: harbor-tls
  loadBalancer:
    name: harbor
    IP: 192.168.50.80
    ports:
      httpsPort: 443

externalURL: https://harbor.example.com

persistence:
  enabled: true
  resourcePolicy: "keep"
  persistentVolumeClaim:
    registry:
      storageClass: "piraeus-storage-ha"  # 3-way replication
      size: 200Gi
    database:
      storageClass: "piraeus-storage-ha"
      size: 10Gi
    redis:
      storageClass: "piraeus-storage"  # 2-way replication
      size: 2Gi
    jobservice:
      jobLog:
        storageClass: "piraeus-storage"
        size: 2Gi
    trivy:
      storageClass: "piraeus-storage"
      size: 10Gi

harborAdminPassword: "ChangeMe123!"

database:
  type: internal
  internal:
    password: "SecureDbPassword123"

redis:
  type: internal

trivy:
  enabled: true

chartmuseum:
  enabled: true

notary:
  enabled: true

metrics:
  enabled: true

# Resource limits
portal:
  replicas: 2
  resources:
    requests:
      memory: 256Mi
      cpu: 100m
    limits:
      memory: 512Mi
      cpu: 500m

core:
  replicas: 2
  resources:
    requests:
      memory: 512Mi
      cpu: 200m
    limits:
      memory: 2Gi
      cpu: 2000m

registry:
  replicas: 2
  resources:
    requests:
      memory: 512Mi
      cpu: 200m
    limits:
      memory: 2Gi
      cpu: 2000m
```

## Appendix: Useful Commands

```bash
# Check Harbor version
helm list -n harbor

# Upgrade Harbor
helm upgrade harbor harbor/harbor -n harbor -f harbor-values.yaml

# Uninstall Harbor (keeps PVCs)
helm uninstall harbor -n harbor

# Delete all Harbor resources including PVCs
helm uninstall harbor -n harbor
kubectl delete pvc -n harbor --all

# View Harbor logs
kubectl logs -n harbor -l component=core -f

# Get admin password from secret (if lost)
kubectl get secret -n harbor harbor-core -o jsonpath='{.data.HARBOR_ADMIN_PASSWORD}' | base64 -d

# List all Harbor PVCs
kubectl get pvc -n harbor

# Check storage usage
kubectl exec -n harbor <registry-pod> -- df -h /storage

# Force garbage collection
kubectl exec -n harbor <core-pod> -- /harbor/harbor-core gc

# Export all projects (backup)
# (Requires Harbor API)
curl -u admin:Harbor12345 http://192.168.50.80/api/v2.0/projects | jq . > projects-backup.json
```

---

**Last Updated:** 2025-11-06
**Tested with:** Talos v1.11.1, Kubernetes v1.33.3, Harbor Helm Chart v1.16.1
