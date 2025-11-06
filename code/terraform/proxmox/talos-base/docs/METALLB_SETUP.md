# Complete Guide: MetalLB on Talos Kubernetes

This guide walks you through setting up MetalLB in L2 mode on a Talos Kubernetes cluster, enabling LoadBalancer services with bare-metal load balancing.

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Architecture Overview](#architecture-overview)
3. [Step 1: Install MetalLB](#step-1-install-metallb)
4. [Step 2: Configure IPAddressPool](#step-2-configure-ipaddresspool)
5. [Step 3: Configure L2Advertisement](#step-3-configure-l2advertisement)
6. [Step 4: Test LoadBalancer Service](#step-4-test-loadbalancer-service)
7. [Troubleshooting](#troubleshooting)
8. [Production Considerations](#production-considerations)

## Prerequisites

- **Talos Kubernetes cluster** running and accessible
- **kubectl** configured with cluster access
- **IP address range** available on your network that doesn't overlap with DHCP or existing assignments
- **Network connectivity** - Nodes must be on the same L2 network segment for L2 mode

### Network Requirements

- **IP Range**: 192.168.50.50-192.168.50.250 (201 IPs available)
- **Network**: Must be routable from clients
- **L2 Adjacency**: All nodes must be on the same broadcast domain
- **No IP conflicts**: Ensure this range isn't used by DHCP or other services

## Architecture Overview

MetalLB provides network load balancer functionality for Kubernetes clusters that don't run on cloud providers. It has two main components:

- **Controller**: Watches for LoadBalancer services and assigns IP addresses
- **Speaker**: Announces IP addresses using L2 (ARP/NDP) or BGP protocols

In **L2 mode**:
- One node "owns" the service IP (elected leader)
- Traffic goes directly to that node
- Node forwards traffic to appropriate pods
- Failover happens automatically if the leader node fails

## Step 1: Install MetalLB

MetalLB can be installed via manifest or Helm. We'll use the official manifest method.

### 1.1: Apply MetalLB Manifest

```bash
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.15.2/config/manifests/metallb-native.yaml
```

**Note**: Check [MetalLB releases](https://github.com/metallb/metallb/releases) for the latest version.

### 1.2: Wait for MetalLB Pods to be Ready

```bash
kubectl wait pod --for=condition=Ready -n metallb-system \
  -l app=metallb \
  --timeout=120s
```

This may take 1-2 minutes as images are pulled.

### 1.3: Verify MetalLB Installation

```bash
kubectl get pods -n metallb-system
```

Expected output:
```
NAME                          READY   STATUS    RESTARTS   AGE
controller-xxxxxxxxxx-xxxxx   1/1     Running   0          2m
speaker-xxxxx                 1/1     Running   0          2m
speaker-xxxxx                 1/1     Running   0          2m
speaker-xxxxx                 1/1     Running   0          2m
```

You should see:
- **1 controller** pod
- **1 speaker** pod per node (DaemonSet)

### 1.4: Verify Components

Check the controller:
```bash
kubectl get deployment -n metallb-system controller
```

Check the speaker DaemonSet:
```bash
kubectl get daemonset -n metallb-system speaker
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
  autoAssign: true
EOF
```

**Configuration details:**
- `addresses`: IP range to allocate (192.168.50.50-192.168.50.250 = 201 IPs)
- `autoAssign: true`: Automatically assign IPs to LoadBalancer services
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
EOF
```

**Configuration details:**
- `ipAddressPools`: References the IPAddressPool(s) to advertise
- No `interfaces` specified: Advertise on all network interfaces
- No `nodeSelectors`: All nodes can become speakers

### 3.2: Verify L2Advertisement

```bash
kubectl get l2advertisement -n metallb-system
```

Expected output:
```
NAME         IPADDRESSPOOLS   IPADDRESSPOOL SELECTORS   INTERFACES
default-l2   ["default-pool"]
```

### 3.3: Check L2Advertisement Details

```bash
kubectl describe l2advertisement default-l2 -n metallb-system
```

You should see it references `default-pool`.

## Step 4: Test LoadBalancer Service

Now let's verify MetalLB is working by creating a test LoadBalancer service.

### 4.1: Deploy Test Application

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
        command: ["/bin/sh", "-c"]
        args:
        - |
          echo "<h1>MetalLB Test</h1><p>Hostname: $(hostname)</p><p>Pod IP: $(hostname -i)</p>" > /usr/share/nginx/html/index.html
          nginx -g 'daemon off;'
EOF
```

### 4.2: Create LoadBalancer Service

```bash
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: Service
metadata:
  name: nginx-test-lb
spec:
  type: LoadBalancer
  selector:
    app: nginx-test
  ports:
  - protocol: TCP
    port: 80
    targetPort: 80
    name: http
EOF
```

### 4.3: Check Service Status

```bash
kubectl get service nginx-test-lb
```

Expected output:
```
NAME            TYPE           CLUSTER-IP      EXTERNAL-IP      PORT(S)        AGE
nginx-test-lb   LoadBalancer   10.96.123.45    192.168.50.50    80:32100/TCP   30s
```

**Important**: The `EXTERNAL-IP` should be assigned from your pool (192.168.50.50-192.168.50.250). If it shows `<pending>`, see [Troubleshooting](#troubleshooting).

### 4.4: Verify IP Assignment

```bash
kubectl describe service nginx-test-lb | grep "LoadBalancer Ingress"
```

You should see an IP from your configured range.

### 4.5: Check Which Node Owns the IP

```bash
kubectl get pods -n metallb-system -l component=speaker -o wide
```

Check the speaker logs to see which node is announcing the IP:
```bash
# Replace with one of your speaker pod names
kubectl logs -n metallb-system speaker-xxxxx | grep nginx-test-lb
```

You should see logs indicating the IP is being announced.

### 4.6: Test Connectivity

From a machine on the same network (not inside the cluster):

```bash
# Replace with your assigned IP
curl http://192.168.50.50
```

Expected output:
```html
<h1>MetalLB Test</h1>
<p>Hostname: nginx-test-xxxxxxxxx-xxxxx</p>
<p>Pod IP: 10.244.x.x</p>
```

You can also test from your browser by visiting `http://192.168.50.50`.

### 4.7: Test Load Balancing

Make multiple requests to see different pod hostnames:

```bash
for i in {1..10}; do
  curl -s http://192.168.50.50 | grep Hostname
done
```

You should see requests distributed between the 2 nginx pods.

### 4.8: Test Failover (Optional)

To test failover, find which node is currently announcing the IP and cordon it:

```bash
# Find the node running the speaker that owns the IP
kubectl get pods -n metallb-system -l component=speaker -o wide

# Cordon the node (replace with actual node name)
kubectl cordon talos-control-01

# Delete the speaker pod on that node to force failover
kubectl delete pod -n metallb-system speaker-xxxxx

# Wait a moment, then check if the service is still accessible
curl http://192.168.50.50
```

The service should remain accessible as another speaker takes over. Uncordon the node when done:

```bash
kubectl uncordon talos-control-01
```

### 4.9: Cleanup Test Resources

If you want to remove the test deployment:

```bash
kubectl delete service nginx-test-lb
kubectl delete deployment nginx-test
```

## Troubleshooting

### LoadBalancer Service Stuck in Pending

**Symptom:**
```bash
kubectl get service nginx-test-lb
# EXTERNAL-IP shows <pending>
```

**Diagnosis:**

1. Check MetalLB controller logs:
```bash
kubectl logs -n metallb-system deployment/controller
```

2. Check speaker logs:
```bash
kubectl logs -n metallb-system daemonset/speaker
```

**Common Causes:**

#### Issue 1: No IPAddressPool configured

**Solution**: Ensure you created the IPAddressPool (Step 2).

```bash
kubectl get ipaddresspool -n metallb-system
```

#### Issue 2: No L2Advertisement configured

**Solution**: Ensure you created the L2Advertisement (Step 3).

```bash
kubectl get l2advertisement -n metallb-system
```

#### Issue 3: IPAddressPool not referenced in L2Advertisement

**Solution**: Check that L2Advertisement references the correct pool:

```bash
kubectl get l2advertisement default-l2 -n metallb-system -o yaml | grep -A5 ipAddressPools
```

#### Issue 4: All IPs in pool exhausted

**Solution**: Check if all IPs are already assigned:

```bash
kubectl get services --all-namespaces -o wide | grep LoadBalancer
```

If all 201 IPs are used, expand your pool or delete unused services.

### Service Unreachable from Outside

**Symptom**: Service gets an EXTERNAL-IP but is unreachable from outside the cluster.

**Diagnosis:**

1. Check if you can reach it from a cluster node:
```bash
# SSH to a node or use kubectl exec
curl http://192.168.50.50
```

2. Check ARP table on your client machine:
```bash
# Linux/Mac
arp -a | grep 192.168.50.50

# Windows
arp -a | findstr 192.168.50.50
```

**Common Causes:**

#### Issue 1: Network not on same L2 segment

**Solution**: L2 mode requires nodes and clients to be on the same broadcast domain. If you're on a different subnet, you need:
- A router that forwards ARP/routes the subnet
- Or use BGP mode instead of L2 mode

#### Issue 2: Firewall blocking traffic

**Solution**: Check if a firewall on the Talos nodes is blocking traffic:

```bash
# Talos doesn't use iptables, but check if kube-proxy rules are correct
kubectl get endpoints nginx-test-lb
```

#### Issue 3: Speaker not running on any node

**Solution**: Verify speaker DaemonSet is running:

```bash
kubectl get pods -n metallb-system -l component=speaker
```

All nodes should have a speaker pod in **Running** state.

### Speaker Pods CrashLoopBackOff

**Symptom:**
```bash
kubectl get pods -n metallb-system
# speaker-xxx shows CrashLoopBackOff
```

**Diagnosis:**

Check speaker logs:
```bash
kubectl logs -n metallb-system speaker-xxxxx
```

**Common Causes:**

#### Issue 1: Permission issues

MetalLB speaker requires certain capabilities. Check the DaemonSet security context:

```bash
kubectl get daemonset -n metallb-system speaker -o yaml | grep -A10 securityContext
```

**Solution**: Ensure speaker has `NET_RAW` capability (already configured in official manifest).

#### Issue 2: Conflicting network plugin

Some CNI plugins conflict with MetalLB's L2 mode.

**Solution**: Verify your CNI (Talos uses default CNI). MetalLB should work with most CNIs, but check [MetalLB compatibility](https://metallb.universe.tf/installation/network-addons/).

### Multiple Services Get Same IP

**Symptom**: Two different services are assigned the same EXTERNAL-IP.

**Diagnosis:**

```bash
kubectl get services --all-namespaces | grep LoadBalancer
```

**Solution**: This should not happen. MetalLB controller prevents duplicate assignments. If it occurs:

1. Check controller logs:
```bash
kubectl logs -n metallb-system deployment/controller
```

2. Restart MetalLB controller:
```bash
kubectl rollout restart deployment -n metallb-system controller
```

## Production Considerations

### IP Address Pool Planning

**Current configuration**: 192.168.50.50-192.168.50.250 (201 IPs)

Consider:
- **Service growth**: How many LoadBalancer services will you need?
- **Reserved IPs**: Leave some IPs for future expansion or manual assignment
- **Pool segmentation**: Create multiple pools for different purposes

Example of multiple pools:

```yaml
---
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: web-services
  namespace: metallb-system
spec:
  addresses:
  - 192.168.50.50-192.168.50.100
  autoAssign: true
---
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: database-services
  namespace: metallb-system
spec:
  addresses:
  - 192.168.50.101-192.168.50.150
  autoAssign: true
---
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: reserved-manual
  namespace: metallb-system
spec:
  addresses:
  - 192.168.50.151-192.168.50.250
  autoAssign: false  # Manual assignment only
```

You can then specify which pool to use in a Service:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: my-db-service
  annotations:
    metallb.universe.tf/address-pool: database-services
spec:
  type: LoadBalancer
  # ...
```

### Requesting Specific IPs

You can request a specific IP from the pool:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: my-web-service
spec:
  type: LoadBalancer
  loadBalancerIP: 192.168.50.100  # Request specific IP
  # ...
```

**Note**: The IP must be within a configured IPAddressPool.

### L2 Mode Limitations

**Bandwidth bottleneck**:
- In L2 mode, all traffic for a service goes through a single node
- If you have high-traffic services, consider:
  - Using multiple services (each gets its own IP and node)
  - Switching to BGP mode for better load distribution
  - Using Ingress controller with a single LoadBalancer

**Failover time**:
- When a node fails, it takes ~10 seconds for another node to take over
- This is due to ARP cache expiration on client devices
- For faster failover, consider BGP mode

### L2 vs BGP Mode

| Feature | L2 Mode | BGP Mode |
|---------|---------|----------|
| Setup complexity | Simple (what we did) | Complex (requires BGP router) |
| Network requirements | Same L2 segment | Routable network |
| Load distribution | Single node per service | Multiple nodes (ECMP) |
| Failover time | ~10 seconds | ~1 second |
| Bandwidth | Limited to 1 node | Distributed across nodes |
| Best for | Small/medium clusters, simple networks | Large clusters, datacenter environments |

For most home labs and small clusters, **L2 mode (what we configured) is perfect**.

### High Availability

To ensure MetalLB availability:

1. **Multiple nodes**: MetalLB speaker DaemonSet runs on all nodes, providing automatic failover.

2. **Controller replicas**: For production, consider running multiple controller replicas:

```bash
kubectl scale deployment -n metallb-system controller --replicas=2
```

3. **Pod disruption budgets**: Prevent all speakers from being evicted during maintenance:

```yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: metallb-speaker
  namespace: metallb-system
spec:
  minAvailable: 1
  selector:
    matchLabels:
      component: speaker
```

### Monitoring

MetalLB exposes Prometheus metrics. To monitor:

1. **Controller metrics**: Available at port 7472
2. **Speaker metrics**: Available at port 7472

Example ServiceMonitor for Prometheus Operator:

```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: metallb
  namespace: metallb-system
spec:
  selector:
    matchLabels:
      app: metallb
  endpoints:
  - port: monitoring
```

Key metrics to watch:
- `metallb_allocator_addresses_in_use_total`: IPs allocated
- `metallb_speaker_announced`: Services being announced
- `metallb_allocator_addresses_total`: Total IPs in pools

### Security

1. **Network policies**: Restrict access to MetalLB components:

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: metallb-controller
  namespace: metallb-system
spec:
  podSelector:
    matchLabels:
      app: metallb
      component: controller
  policyTypes:
  - Ingress
  ingress:
  - from:
    - namespaceSelector: {}
    ports:
    - protocol: TCP
      port: 7472  # Metrics only
```

2. **RBAC**: The official manifest includes proper RBAC rules. Don't modify unless necessary.

3. **Pod security**: Speakers need `NET_RAW` capability to send ARP packets. This is required and already configured.

### Upgrades

To upgrade MetalLB:

```bash
# Check current version
kubectl get pods -n metallb-system -o jsonpath='{.items[0].spec.containers[0].image}'

# Apply new manifest (replace version)
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.15.2/config/manifests/metallb-native.yaml
```

**Important**: Always check [MetalLB release notes](https://metallb.universe.tf/release-notes/) for breaking changes.

### Integration with Ingress Controllers

A common pattern is to use MetalLB to expose an Ingress controller:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: ingress-nginx-controller
  namespace: ingress-nginx
spec:
  type: LoadBalancer
  loadBalancerIP: 192.168.50.80  # Reserve specific IP
  ports:
  - name: http
    port: 80
    targetPort: http
  - name: https
    port: 443
    targetPort: https
  selector:
    app.kubernetes.io/name: ingress-nginx
```

Then all your web services use Ingress resources (sharing the single LoadBalancer IP) instead of individual LoadBalancer services.

## Common Use Cases

### 1. Exposing a Web Application

```yaml
apiVersion: v1
kind: Service
metadata:
  name: my-webapp
spec:
  type: LoadBalancer
  selector:
    app: webapp
  ports:
  - port: 80
    targetPort: 8080
```

### 2. Exposing a Database (with specific IP)

```yaml
apiVersion: v1
kind: Service
metadata:
  name: postgres-external
spec:
  type: LoadBalancer
  loadBalancerIP: 192.168.50.100
  selector:
    app: postgres
  ports:
  - port: 5432
    targetPort: 5432
```

### 3. Exposing Multiple Ports

```yaml
apiVersion: v1
kind: Service
metadata:
  name: game-server
spec:
  type: LoadBalancer
  selector:
    app: game-server
  ports:
  - name: game-port
    port: 7777
    targetPort: 7777
    protocol: UDP
  - name: query-port
    port: 27015
    targetPort: 27015
    protocol: UDP
```

### 4. Combining with ExternalDNS

If you use ExternalDNS, you can automatically create DNS records:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: my-service
  annotations:
    external-dns.alpha.kubernetes.io/hostname: myapp.example.com
spec:
  type: LoadBalancer
  # ...
```

## References

- [MetalLB Official Documentation](https://metallb.universe.tf/)
- [MetalLB GitHub Repository](https://github.com/metallb/metallb)
- [MetalLB Configuration Reference](https://metallb.universe.tf/configuration/)
- [MetalLB Concepts](https://metallb.universe.tf/concepts/)
- [Talos Network Configuration](https://www.talos.dev/latest/talos-guides/network/)

## Appendix: Complete Configuration

Here's the complete MetalLB configuration for quick reference:

```yaml
---
# IPAddressPool: Defines available IP addresses
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: default-pool
  namespace: metallb-system
spec:
  addresses:
  - 192.168.50.50-192.168.50.250
  autoAssign: true

---
# L2Advertisement: Configures L2 mode announcement
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: default-l2
  namespace: metallb-system
spec:
  ipAddressPools:
  - default-pool
```

## Appendix: Useful Commands

```bash
# Check MetalLB status
kubectl get pods -n metallb-system
kubectl get ipaddresspool -n metallb-system
kubectl get l2advertisement -n metallb-system

# List all LoadBalancer services
kubectl get services --all-namespaces -o wide | grep LoadBalancer

# Check which IPs are assigned
kubectl get services --all-namespaces -o json | \
  jq -r '.items[] | select(.spec.type=="LoadBalancer") | "\(.metadata.name)\t\(.status.loadBalancer.ingress[0].ip)"'

# View MetalLB controller logs
kubectl logs -n metallb-system deployment/controller -f

# View speaker logs on all nodes
kubectl logs -n metallb-system daemonset/speaker -f

# Check speaker on specific node
kubectl logs -n metallb-system speaker-xxxxx -f

# Restart MetalLB components
kubectl rollout restart deployment -n metallb-system controller
kubectl rollout restart daemonset -n metallb-system speaker
```

---

**Last Updated:** 2025-11-06
**Tested with:** Talos v1.11.1, Kubernetes v1.33.3, MetalLB v0.15.2
