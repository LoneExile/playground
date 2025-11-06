# Complete Guide: MetalLB on Talos Kubernetes

This guide walks you through setting up MetalLB in L2 mode on a Talos Kubernetes cluster using Helm, enabling LoadBalancer services with bare-metal load balancing.

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Architecture Overview](#architecture-overview)
3. [Step 1: Install MetalLB with Helm](#step-1-install-metallb-with-helm)
4. [Step 2: Configure IPAddressPool](#step-2-configure-ipaddresspool)
5. [Step 3: Configure L2Advertisement](#step-3-configure-l2advertisement)
6. [Step 4: Test LoadBalancer Service](#step-4-test-loadbalancer-service)
7. [Troubleshooting](#troubleshooting)
8. [Production Considerations](#production-considerations)

## Prerequisites

- **Talos Kubernetes cluster** running and accessible
- **kubectl** configured with cluster access
- **Helm 3.x** installed on your local machine
- **IP address range** available on your network that doesn't overlap with DHCP or existing assignments
- **Network connectivity** - Nodes must be on the same L2 network segment for L2 mode
- **Proxmox** (if applicable) - Promiscuous mode must be enabled on the network bridge

### Network Requirements

- **IP Range**: 192.168.50.50-192.168.50.250 (201 IPs available)
- **Network**: Must be routable from clients
- **L2 Adjacency**: All nodes must be on the same broadcast domain
- **No IP conflicts**: Ensure this range isn't used by DHCP or other services

### Talos Configuration Requirements

For MetalLB to work properly on Talos, you need the following sysctls configured:

```yaml
machine:
  sysctls:
    net.ipv4.neigh.default.gc_thresh1: "4096"
    net.ipv4.neigh.default.gc_thresh2: "8192"
    net.ipv4.neigh.default.gc_thresh3: "16384"
```

These settings increase the ARP neighbor table limits, which is essential for MetalLB L2 mode to function correctly.

## Architecture Overview

MetalLB provides network load balancer functionality for Kubernetes clusters that don't run on cloud providers. It has two main components:

- **Controller**: Watches for LoadBalancer services and assigns IP addresses
- **Speaker**: Announces IP addresses using L2 (ARP/NDP) or BGP protocols

In **L2 mode**:
- One node "owns" the service IP (elected leader)
- Traffic goes directly to that node
- Node forwards traffic to appropriate pods
- Failover happens automatically if the leader node fails

## Step 1: Install MetalLB with Helm

### 1.1: Add MetalLB Helm Repository

```bash
helm repo add metallb https://metallb.github.io/metallb
helm repo update
```

### 1.2: Install MetalLB

```bash
helm install my-metallb metallb/metallb \
  --version 0.15.2 \
  --namespace metallb-system \
  --create-namespace \
  --set speaker.ignoreExcludeLB=true
```

**Configuration details:**
- `speaker.ignoreExcludeLB=true`: Tells MetalLB to ignore the `node.kubernetes.io/exclude-from-external-load-balancers` label that TalosOS applies by default. This is crucial for TalosOS compatibility.

**Note**: Check [MetalLB Helm chart releases](https://github.com/metallb/metallb/releases) for the latest version.

### 1.3: Configure Namespace PodSecurity

MetalLB speakers require privileged capabilities. Set the namespace PodSecurity policy:

```bash
kubectl label namespace metallb-system \
  pod-security.kubernetes.io/enforce=privileged \
  pod-security.kubernetes.io/audit=privileged \
  pod-security.kubernetes.io/warn=privileged
```

### 1.4: Remove Node Exclusion Labels

If your control plane nodes have the `exclude-from-external-load-balancers` label, remove it:

```bash
kubectl label nodes --all node.kubernetes.io/exclude-from-external-load-balancers-
```

### 1.5: Wait for MetalLB Pods to be Ready

```bash
kubectl wait pod --for=condition=Ready -n metallb-system \
  -l app.kubernetes.io/name=metallb \
  --timeout=120s
```

This may take 1-2 minutes as images are pulled.

### 1.6: Verify MetalLB Installation

```bash
kubectl get pods -n metallb-system
```

Expected output:
```
NAME                                     READY   STATUS    RESTARTS   AGE
my-metallb-controller-xxxxxxxxxx-xxxxx   1/1     Running   0          2m
my-metallb-speaker-xxxxx                 4/4     Running   0          2m
my-metallb-speaker-xxxxx                 4/4     Running   0          2m
my-metallb-speaker-xxxxx                 4/4     Running   0          2m
```

You should see:
- **1 controller** pod (Deployment)
- **1 speaker** pod per node (DaemonSet)
- Each speaker pod has 4 containers (cp-frr-files, cp-reloader, cp-metrics, speaker, frr, reloader, frr-metrics)

### 1.7: Verify Components

Check the controller:
```bash
kubectl get deployment -n metallb-system my-metallb-controller
```

Check the speaker DaemonSet:
```bash
kubectl get daemonset -n metallb-system my-metallb-speaker
```

All pods should be **Running** and **Ready**.

## Step 2: Configure IPAddressPool

The IPAddressPool defines which IP addresses MetalLB can assign to LoadBalancer services.

### 2.1: Create IPAddressPool

```bash
kubectl apply -f - <<'EOF'
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: default-pool
  namespace: metallb-system
spec:
  addresses:
  - 192.168.50.50-192.168.50.250
EOF
```

**Configuration details:**
- `addresses`: IP range to allocate (192.168.50.50-192.168.50.250 = 201 IPs)
- `autoAssign: true` is the default - automatically assigns IPs to LoadBalancer services
- `name: default-pool`: You can create multiple pools for different purposes

### 2.2: Verify IPAddressPool

```bash
kubectl get ipaddresspool -n metallb-system
```

Expected output:
```
NAME           AUTO ASSIGN   AVOID BUGGY IPS   ADDRESSES
default-pool   true          false             ["192.168.50.50-192.168.50.250"]
```

### 2.3: Check Pool Details

```bash
kubectl describe ipaddresspool default-pool -n metallb-system
```

You should see your IP range listed under `Addresses`.

## Step 3: Configure L2Advertisement

L2Advertisement tells MetalLB to advertise service IPs using Layer 2 protocols (ARP/NDP).

### 3.1: Create L2Advertisement

```bash
kubectl apply -f - <<'EOF'
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: default-l2
  namespace: metallb-system
spec:
  ipAddressPools:
  - default-pool
  interfaces:
  - eth0
EOF
```

**Configuration details:**
- `ipAddressPools`: References the IPAddressPool(s) to advertise
- `interfaces: [eth0]`: Explicitly specify the network interface for Talos
- No `nodeSelectors`: All nodes can become speakers

**Important**: The `interfaces` field is crucial for Talos Linux. On TalosOS, MetalLB speaker pods (which run with `hostNetwork: true`) see the interface as `eth0`, not `ens18`. To verify the correct interface name, check the speaker logs:

```bash
kubectl logs -n metallb-system -l app.kubernetes.io/component=speaker | grep localIfs
```

### 3.2: Verify L2Advertisement

```bash
kubectl get l2advertisement -n metallb-system
```

Expected output:
```
NAME         IPADDRESSPOOLS     IPADDRESSPOOL SELECTORS   INTERFACES
default-l2   ["default-pool"]                             ["eth0"]
```

### 3.3: Check L2Advertisement Details

```bash
kubectl describe l2advertisement default-l2 -n metallb-system
```

You should see it references `default-pool` and the `eth0` interface.

## Step 4: Test LoadBalancer Service

Now let's verify MetalLB is working by testing an existing LoadBalancer service.

### 4.1: Check Existing Services

```bash
kubectl get svc --all-namespaces -o wide | grep LoadBalancer
```

You should see services with EXTERNAL-IP assigned from your pool (e.g., 192.168.50.80 for ingress-nginx).

### 4.2: Test from Within Cluster

```bash
kubectl run test-curl --image=curlimages/curl:latest --rm -it --restart=Never -- \
  curl --max-time 5 http://192.168.50.80
```

You should receive a response (404 or similar from nginx is expected without Host header).

### 4.3: Test from External Network

From your local machine or another host on the network:

```bash
curl http://192.168.50.80
```

**Expected Result**: You should receive a response from the ingress controller.

**If this times out**, see the Proxmox configuration in the Troubleshooting section below.

### 4.4: Create a Test LoadBalancer Service

If you want to create a dedicated test service:

```bash
kubectl apply -f - <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx-test
  labels:
    app: nginx-test
spec:
  replicas: 2
  selector:
    matchLabels:
      app: nginx-test
  template:
    metadata:
      labels:
        app: nginx-test
    spec:
      containers:
      - name: nginx
        image: nginx:alpine
        ports:
        - containerPort: 80
          name: http
---
apiVersion: v1
kind: Service
metadata:
  name: nginx-test
  labels:
    app: nginx-test
spec:
  type: LoadBalancer
  selector:
    app: nginx-test
  ports:
  - name: http
    protocol: TCP
    port: 80
    targetPort: 80
EOF
```

Check the assigned IP:
```bash
kubectl get svc nginx-test
```

You should see an EXTERNAL-IP from your pool range.

### 4.5: Clean Up Test Resources

```bash
kubectl delete deployment nginx-test
kubectl delete service nginx-test
```

## Troubleshooting

### Issue: Speaker Pods Not Starting

**Error**: `violates PodSecurity "baseline:latest"`

**Solution**: Label the namespace with privileged PodSecurity policy:

```bash
kubectl label namespace metallb-system \
  pod-security.kubernetes.io/enforce=privileged \
  pod-security.kubernetes.io/audit=privileged \
  pod-security.kubernetes.io/warn=privileged
```

### Issue: No IP Assigned to Service

**Check**:
1. Verify IPAddressPool exists and has available IPs
2. Check MetalLB controller logs

```bash
kubectl logs -n metallb-system -l app.kubernetes.io/component=controller
```

**Common causes**:
- IP pool exhausted
- Service doesn't match pool selectors
- Controller not running

### Issue: Cannot Reach LoadBalancer IP from External Network

**Symptoms**: LoadBalancer IP works from within cluster but times out from external machines.

**Diagnosis**:

1. **Test from within cluster** (should work):
   ```bash
   kubectl run test-curl --image=curlimages/curl:latest --rm -it --restart=Never -- \
     curl --max-time 5 http://LOADBALANCER_IP
   ```

2. **Check MetalLB speaker logs** for announcement activity:
   ```bash
   kubectl logs -n metallb-system -l app.kubernetes.io/component=speaker
   ```

3. **Verify L2Advertisement configuration**:
   ```bash
   kubectl get l2advertisement -n metallb-system -o yaml
   ```

**Solution for Proxmox Users**:

If you're running on Proxmox, the network bridge (`vmbr0`) blocks ARP announcements by default. You must enable **promiscuous mode**:

**Temporary (until reboot)**:
```bash
# SSH to Proxmox host
ip link set vmbr0 promisc on

# Verify
ip link show vmbr0 | grep PROMISC
```

**Permanent**:

Edit `/etc/network/interfaces` on your Proxmox host:

```bash
auto vmbr0
iface vmbr0 inet static
    address YOUR_PROXMOX_IP/24
    gateway YOUR_GATEWAY
    bridge-ports YOUR_PHYSICAL_INTERFACE
    bridge-stp off
    bridge-fd 0
    post-up ip link set vmbr0 promisc on
```

Then restart networking:
```bash
systemctl restart networking
```

### Issue: ARP Neighbor Table Full

**Symptoms**: MetalLB stops announcing IPs after some time.

**Solution**: Ensure Talos sysctls are configured (see Prerequisites section above). These should be set in your Talos machine configuration:

```yaml
machine:
  sysctls:
    net.ipv4.neigh.default.gc_thresh1: "4096"
    net.ipv4.neigh.default.gc_thresh2: "8192"
    net.ipv4.neigh.default.gc_thresh3: "16384"
```

### Issue: Node Label Prevents MetalLB

**Symptoms**: Speaker pods don't schedule or LoadBalancer IPs not announced.

**Check**:
```bash
kubectl get nodes --show-labels | grep exclude
```

**Solution**: Remove the exclusion label:
```bash
kubectl label nodes --all node.kubernetes.io/exclude-from-external-load-balancers-
```

### Viewing MetalLB Logs

**Controller logs**:
```bash
kubectl logs -n metallb-system -l app.kubernetes.io/component=controller --tail=100
```

**Speaker logs** (from all speakers):
```bash
kubectl logs -n metallb-system -l app.kubernetes.io/component=speaker --tail=50 --prefix=true
```

**Speaker logs** (from specific node):
```bash
kubectl logs -n metallb-system -l app.kubernetes.io/component=speaker --field-selector spec.nodeName=NODE_NAME
```

### Check MetalLB Configuration

View all MetalLB CRDs:
```bash
kubectl get ipaddresspool,l2advertisement -n metallb-system
```

Detailed view:
```bash
kubectl get ipaddresspool,l2advertisement -n metallb-system -o yaml
```

## Production Considerations

### High Availability

- **Speaker DaemonSet**: Runs on every node, providing redundancy
- **Leader Election**: One speaker "owns" each LoadBalancer IP
- **Automatic Failover**: If the leader node fails, another speaker takes over
- **Graceful Migration**: When a speaker pod restarts, IPs are migrated gracefully

### IP Pool Management

**Multiple Pools**:
```yaml
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: production-pool
  namespace: metallb-system
spec:
  addresses:
  - 192.168.50.100-192.168.50.150
  autoAssign: false  # Manual assignment only
---
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: development-pool
  namespace: metallb-system
spec:
  addresses:
  - 192.168.50.200-192.168.50.250
```

**Service-specific IP assignment**:
```yaml
apiVersion: v1
kind: Service
metadata:
  name: my-service
  annotations:
    metallb.universe.tf/address-pool: production-pool
    metallb.universe.tf/loadBalancerIPs: 192.168.50.100
spec:
  type: LoadBalancer
  # ...
```

### Resource Limits

Add resource limits to the Helm values file for production:

```yaml
# values.yaml
controller:
  resources:
    limits:
      cpu: 100m
      memory: 100Mi
    requests:
      cpu: 50m
      memory: 64Mi

speaker:
  resources:
    limits:
      cpu: 100m
      memory: 100Mi
    requests:
      cpu: 50m
      memory: 64Mi
```

Install with values:
```bash
helm install my-metallb metallb/metallb \
  --version 0.15.2 \
  --namespace metallb-system \
  --create-namespace \
  --values values.yaml
```

### Network Policies

Restrict MetalLB traffic with NetworkPolicies if needed:

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: metallb-controller
  namespace: metallb-system
spec:
  podSelector:
    matchLabels:
      app.kubernetes.io/component: controller
  policyTypes:
  - Ingress
  - Egress
  ingress:
  - from:
    - namespaceSelector: {}
    ports:
    - protocol: TCP
      port: 9443  # Webhook
  egress:
  - to:
    - namespaceSelector: {}
    ports:
    - protocol: TCP
      port: 6443  # Kubernetes API
```

### Monitoring

MetalLB exposes Prometheus metrics:

**Controller metrics**: `http://controller-pod:7472/metrics`
**Speaker metrics**: `http://speaker-pod:7472/metrics`

Key metrics to monitor:
- `metallb_allocator_addresses_in_use_total`: Number of IPs allocated
- `metallb_allocator_addresses_total`: Total IPs available
- `metallb_speaker_announced`: Number of services announced
- `metallb_k8s_client_update_errors_total`: API errors

### Upgrading MetalLB

To upgrade MetalLB to a newer version:

```bash
# Check current version
helm list -n metallb-system

# Update Helm repo
helm repo update

# Search for available versions
helm search repo metallb/metallb --versions

# Upgrade
helm upgrade my-metallb metallb/metallb \
  --version NEW_VERSION \
  --namespace metallb-system \
  --reuse-values
```

### Uninstalling MetalLB

To completely remove MetalLB:

```bash
# Remove Helm release
helm uninstall my-metallb -n metallb-system

# Remove CRDs (if needed)
kubectl delete crd \
  addresspools.metallb.io \
  bfdprofiles.metallb.io \
  bgpadvertisements.metallb.io \
  bgppeers.metallb.io \
  communities.metallb.io \
  ipaddresspools.metallb.io \
  l2advertisements.metallb.io \
  servicebgpstatuses.metallb.io \
  servicel2statuses.metallb.io

# Remove namespace
kubectl delete namespace metallb-system
```

## Additional Resources

- [MetalLB Official Documentation](https://metallb.universe.tf/)
- [MetalLB GitHub Repository](https://github.com/metallb/metallb)
- [MetalLB Helm Chart](https://github.com/metallb/metallb/tree/main/charts/metallb)
- [Talos Linux Documentation](https://www.talos.dev/)
- [Kubernetes Service LoadBalancer](https://kubernetes.io/docs/concepts/services-networking/service/#loadbalancer)

---

**Last Updated**: 2025-11-06
**MetalLB Version**: v0.15.2 (Helm chart)
**Talos Version**: v1.11.1
**Kubernetes Version**: v1.33.3
