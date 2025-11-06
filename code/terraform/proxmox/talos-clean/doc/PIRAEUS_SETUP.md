# Complete Guide: Piraeus Operator on Talos Kubernetes

This comprehensive guide walks you through setting up Piraeus Operator on a Talos Kubernetes cluster from scratch.

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Architecture Overview](#architecture-overview)
3. [Step 1: Configure Talos for Piraeus](#step-1-configure-talos-for-piraeus)
4. [Step 2: Install Piraeus Operator](#step-2-install-piraeus-operator)
5. [Step 3: Apply Talos-Specific Configuration](#step-3-apply-talos-specific-configuration)
6. [Step 4: Deploy LinstorCluster](#step-4-deploy-linstorcluster)
7. [Step 5: Configure Storage Pools](#step-5-configure-storage-pools)
8. [Step 6: Create StorageClass and Test](#step-6-create-storageclass-and-test)
9. [Troubleshooting](#troubleshooting)
10. [Production Considerations](#production-considerations)

## Prerequisites

- **Talos Kubernetes cluster** running and accessible
- **kubectl** configured with cluster access
- **Terraform** (if using IaC to manage Talos configuration)
- **Storage disks** attached to nodes (separate from OS disk)
- **Admin access** to modify Talos machine configuration

### Talos Cluster Requirements

- Minimum 3 nodes (for replication)
- Each node should have a dedicated storage disk (e.g., `/dev/vdb`)
- Talos image built with DRBD extension (from [factory.talos.dev](https://factory.talos.dev))
- Kernel modules: `dm-thin-pool`, `drbd`, `drbd_transport_tcp`

## Architecture Overview

This setup uses:
- **LVM Thin Pools** on dedicated storage disks for efficient space utilization
- **DRBD** for block-level replication (2-way or 3-way)
- **CSI Driver** for Kubernetes integration
- **No systemd dependencies** (Talos doesn't use systemd)

## Step 1: Configure Talos for Piraeus

Piraeus requires specific kernel modules and cluster settings to work properly on Talos.

### 1.1: Verify Talos Image Has DRBD Extension

Check if your Talos image includes the DRBD extension:

```bash
kubectl get nodes -o jsonpath='{.items[0].metadata.labels}' | grep drbd
```

**Expected output:**
```
extensions.talos.dev/drbd
```

If you don't see this, you need to build a custom Talos image with the DRBD extension:
1. Go to [https://factory.talos.dev](https://factory.talos.dev)
2. Select your Talos version
3. Add the **DRBD** system extension
4. Download or use the generated factory image URL
5. Rebuild your cluster with the new image

### 1.2: Enable Required Kernel Modules

Edit your Terraform `main.tf` file (or Talos machine configuration) to load DRBD and storage modules:

```hcl
resource "talos_machine_configuration_apply" "controlplane" {
  for_each = local.talos_master_nodes

  depends_on = [proxmox_vm_qemu.talos]

  client_configuration        = talos_machine_secrets.this.client_configuration
  machine_configuration_input = data.talos_machine_configuration.controlplane.machine_configuration
  node                       = proxmox_vm_qemu.talos[each.key].default_ipv4_address

  config_patches = [
    yamlencode({
      cluster = {
        allowSchedulingOnControlPlanes = true  # Only if no worker nodes
        controlPlane = {
          endpoint = "https://${local.talos_vip_ip}:6443"
        }
      }
      machine = {
        network = {
          hostname = each.key
          interfaces = [
            {
              interface = "ens18"
              dhcp      = true
              vip = {
                ip = local.talos_vip_ip
              }
            }
          ]
        }
        kernel = {
          modules = [
            {
              name = "drbd"
              parameters = [
                "usermode_helper=disabled"  # Required for Talos
              ]
            },
            {
              name = "drbd_transport_tcp"  # DRBD TCP transport
            },
            {
              name = "dm-thin-pool"  # Required for LVM thin pools
            }
          ]
        }
        features = {
          kubePrism = {
            enabled = true
            port    = 7445
          }
        }
      }
    })
  ]
}
```

**Key configurations:**
- `allowSchedulingOnControlPlanes: true` - Only needed if you have no worker nodes
- `kernel.modules` - **CRITICAL**: Must include DRBD modules for replication:
  - `drbd` with `usermode_helper=disabled` parameter
  - `drbd_transport_tcp` for network replication
  - `dm-thin-pool` for LVM thin pool support

### 1.3: Apply Terraform Configuration

```bash
terraform apply -auto-approve -target=talos_machine_configuration_apply.controlplane
```

Wait for nodes to reconfigure (30-60 seconds).

### 1.4: Verify Configuration

Check that taints are removed (if using control-plane nodes):

```bash
kubectl get nodes -o custom-columns=NAME:.metadata.name,TAINTS:.spec.taints
```

Expected output: `<none>` for taints

**Note:** DRBD and dm-thin-pool modules will be verified in Step 5 after LINSTOR satellites are deployed.

## Step 2: Install Piraeus Operator

### 2.1: Install Operator

```bash
kubectl apply --server-side -f "https://github.com/piraeusdatastore/piraeus-operator/releases/latest/download/manifest.yaml"
```

### 2.2: Wait for Operator to be Ready

```bash
kubectl wait pod --for=condition=Ready -n piraeus-datastore \
  -l app.kubernetes.io/component=piraeus-operator \
  --timeout=120s
```

### 2.3: Verify Operator Installation

```bash
kubectl get pods -n piraeus-datastore
```

Expected output:
```
NAME                                                   READY   STATUS    RESTARTS   AGE
piraeus-operator-controller-manager-xxxx               1/1     Running   0          2m
piraeus-operator-gencert-xxxx                          1/1     Running   0          2m
```

## Step 3: Apply Talos-Specific Configuration

Talos doesn't use systemd, so we need to configure Piraeus to skip systemd-related components.

### 3.1: Create Talos Satellite Configuration

```bash
kubectl apply -f - <<'EOF'
apiVersion: piraeus.io/v1
kind: LinstorSatelliteConfiguration
metadata:
  name: talos-loader-override
spec:
  podTemplate:
    spec:
      initContainers:
        - name: drbd-shutdown-guard
          $patch: delete
        - name: drbd-module-loader
          $patch: delete
      volumes:
        - name: run-systemd-system
          $patch: delete
        - name: run-drbd-shutdown-guard
          $patch: delete
        - name: systemd-bus-socket
          $patch: delete
        - name: lib-modules
          $patch: delete
        - name: usr-src
          $patch: delete
        - name: etc-lvm-backup
          hostPath:
            path: /var/etc/lvm/backup
            type: DirectoryOrCreate
        - name: etc-lvm-archive
          hostPath:
            path: /var/etc/lvm/archive
            type: DirectoryOrCreate
EOF
```

**What this does:**
- Removes systemd-related volumes and init containers
- Redirects LVM paths to `/var/etc/lvm/` (Talos has read-only `/etc`)
- Removes DRBD module loader (we'll use Talos system extension or pre-loaded module)

## Step 4: Deploy LinstorCluster

### 4.1: Create LinstorCluster

```bash
kubectl apply -f - <<'EOF'
apiVersion: piraeus.io/v1
kind: LinstorCluster
metadata:
  name: linstorcluster
spec: {}
EOF
```

### 4.2: Wait for Controller to be Ready

```bash
kubectl wait pod --for=condition=Ready -n piraeus-datastore \
  -l app.kubernetes.io/component=linstor-controller \
  --timeout=300s
```

This may take 2-5 minutes as the controller runs database migrations.

### 4.3: Verify LINSTOR Nodes

```bash
kubectl -n piraeus-datastore exec deploy/linstor-controller -- linstor node list
```

Expected output:
```
+------------------------------------------------------------------+
| Node             | NodeType  | Addresses                | State  |
|==================================================================|
| talos-control-01 | SATELLITE | 10.244.x.x:3366 (PLAIN)  | Online |
| talos-control-02 | SATELLITE | 10.244.x.x:3366 (PLAIN)  | Online |
| talos-control-03 | SATELLITE | 10.244.x.x:3366 (PLAIN)  | Online |
+------------------------------------------------------------------+
```

All nodes should show **Online** status.

## Step 5: Configure Storage Pools

Now we'll configure LVM thin pools on the dedicated storage disks (not the OS disk).

### 5.1: Identify Storage Disks

Check available disks on a node:

```bash
kubectl -n piraeus-datastore exec daemonset/linstor-satellite.talos-control-01 \
  -c linstor-satellite -- lsblk
```

Look for your storage disk (e.g., `vdb` with 500G).

### 5.2: Verify dm-thin-pool Module is Loaded

```bash
kubectl -n piraeus-datastore exec daemonset/linstor-satellite.talos-control-01 \
  -c linstor-satellite -- lsmod | grep dm_thin_pool
```

Expected output:
```
dm_thin_pool          102400  0
dm_persistent_data    114688  1 dm_thin_pool
dm_bio_prison          24576  1 dm_thin_pool
```

If not loaded, the Talos configuration from Step 1 may not have been applied correctly.

### 5.3: Prepare Storage Disks

Wipe disk signatures on all nodes (replace `/dev/vdb` with your storage disk):

```bash
for node in talos-control-01 talos-control-02 talos-control-03; do
  echo "Wiping /dev/vdb on $node..."
  kubectl -n piraeus-datastore exec daemonset/linstor-satellite.$node \
    -c linstor-satellite -- dd if=/dev/zero of=/dev/vdb bs=1M count=100
done
```

### 5.4: Create LVM Thin Pools

Create storage pools on all nodes:

```bash
for node in talos-control-01 talos-control-02 talos-control-03; do
  echo "Creating LVM thin pool on $node..."
  kubectl -n piraeus-datastore exec deploy/linstor-controller -- \
    linstor physical-storage create-device-pool \
    --pool-name pool1 \
    lvmthin $node /dev/vdb \
    --storage-pool pool1
done
```

**Note:** If any node fails with a "device has a signature" or "can't open exclusively" error, see [Troubleshooting](#troubleshooting-storage-pool-creation-fails).

### 5.5: Verify Storage Pools

```bash
kubectl -n piraeus-datastore exec deploy/linstor-controller -- \
  linstor storage-pool list
```

Expected output:
```
+--------------------------------------------------------------------------------------------------------+
| StoragePool          | Node             | Driver   | PoolName            | FreeCapacity | TotalCapacity |
|========================================================================================================|
| DfltDisklessStorPool | talos-control-01 | DISKLESS |                     |              |               |
| DfltDisklessStorPool | talos-control-02 | DISKLESS |                     |              |               |
| DfltDisklessStorPool | talos-control-03 | DISKLESS |                     |              |               |
| pool1                | talos-control-01 | LVM_THIN | linstor_pool1/pool1 |   499.75 GiB |    499.75 GiB |
| pool1                | talos-control-02 | LVM_THIN | linstor_pool1/pool1 |   499.75 GiB |    499.75 GiB |
| pool1                | talos-control-03 | LVM_THIN | linstor_pool1/pool1 |   499.75 GiB |    499.75 GiB |
+--------------------------------------------------------------------------------------------------------+
```

All nodes should show **pool1** with your configured storage size.

### 5.6: Verify DRBD Module is Loaded

**CRITICAL:** DRBD is required for volume replication (2-way, 3-way). Verify it's loaded correctly:

```bash
# Check DRBD module on first satellite pod
kubectl -n piraeus-datastore get pods -l app.kubernetes.io/component=linstor-satellite -o name | head -1 | \
  xargs -I {} kubectl -n piraeus-datastore exec {} -- lsmod | grep drbd
```

**Expected output:**
```
drbd_transport_tcp     32768  0
drbd                  901120  1 drbd_transport_tcp
```

Verify usermode_helper is disabled:

```bash
kubectl -n piraeus-datastore get pods -l app.kubernetes.io/component=linstor-satellite -o name | head -1 | \
  xargs -I {} kubectl -n piraeus-datastore exec {} -- cat /sys/module/drbd/parameters/usermode_helper
```

**Expected output:**
```
disabled
```

If DRBD is not loaded:
1. Verify your Talos image has the DRBD extension (see Step 1.1)
2. Verify kernel modules are configured in Terraform (see Step 1.2)
3. Reapply Terraform configuration

### 5.7: Disable Auto-Quorum Tiebreaker

DRBD's auto-quorum-tiebreaker can cause issues with 3-node clusters. Disable it:

```bash
kubectl -n piraeus-datastore exec deploy/linstor-controller -- \
  linstor controller set-property DrbdOptions/auto-add-quorum-tiebreaker false
```

**Expected output:**
```
SUCCESS:
    Successfully set property 'DrbdOptions/auto-add-quorum-tiebreaker' to value 'false'
```

## Step 6: Create StorageClass and Test

### 6.1: Understanding Replication Modes

Piraeus/LINSTOR supports different replication levels controlled by `placementCount`:

| Placement Count | Replicas | Storage Used | Can Lose | Best For |
|----------------|----------|--------------|----------|----------|
| `"1"` | 1 copy | 1x | 0 nodes | Testing, temporary data, caches |
| `"2"` | 2 copies | 2x | 1 node | **Recommended default** for most workloads |
| `"3"` | 3 copies | 3x | 2 nodes | Critical data (databases, stateful apps) |

#### How 2-Way Replication Works with 3 Nodes

With **3 nodes** and `placementCount: "2"`:
- LINSTOR creates **2 replicas** of each volume
- Each volume exists on **2 out of 3 nodes** at any time
- LINSTOR automatically selects which 2 nodes based on:
  - Available space
  - Load balancing
  - Network topology
  - Node availability

**Example:**
```
Volume "my-app-data" (10GB):
├─ Replica 1 → talos-control-01 (Primary, actively used) - 10GB
├─ Replica 2 → talos-control-02 (Secondary, synced) - 10GB
└─ talos-control-03 (Not used for this volume) - 0GB

Total storage used: 20GB (10GB × 2 replicas)
```

If `talos-control-01` fails, LINSTOR can:
1. Promote `talos-control-02` to primary
2. Create a new replica on `talos-control-03`

#### Storage Capacity Planning

With **~500GB per node** (1500GB total):

**Scenario 1: All 1-way (no redundancy)**
- Usable space: ~1500GB
- Risk: Data loss if any node fails

**Scenario 2: All 2-way replication**
- Usable space: ~750GB
- Risk: Data loss if 2 specific nodes fail
- **Recommended for most use cases**

**Scenario 3: All 3-way replication**
- Usable space: ~500GB
- Risk: Data loss only if all 3 nodes fail
- Best for critical data

**Scenario 4: Mixed (recommended for production)**
- 70% as 2-way: 525GB usable (1050GB consumed)
- 30% as 3-way: 150GB usable (450GB consumed)
- Total usable: ~675GB
- Balances capacity and redundancy

### 6.2: Create StorageClasses with DRBD Replication

Create three StorageClasses for different replication levels:

```bash
kubectl apply -f - <<'EOF'
---
# Single replica - for testing/temporary data only
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: piraeus-storage-single
provisioner: linstor.csi.linbit.com
allowVolumeExpansion: true
volumeBindingMode: WaitForFirstConsumer
parameters:
  linstor.csi.linbit.com/storagePool: pool1
  linstor.csi.linbit.com/placementCount: "1"
---
# 2-way replication - DEFAULT for most workloads
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: piraeus-storage
  annotations:
    storageclass.kubernetes.io/is-default-class: "true"
provisioner: linstor.csi.linbit.com
allowVolumeExpansion: true
volumeBindingMode: WaitForFirstConsumer
parameters:
  linstor.csi.linbit.com/storagePool: pool1
  linstor.csi.linbit.com/placementCount: "2"
---
# 3-way replication - for critical data
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: piraeus-storage-ha
provisioner: linstor.csi.linbit.com
allowVolumeExpansion: true
volumeBindingMode: WaitForFirstConsumer
parameters:
  linstor.csi.linbit.com/storagePool: pool1
  linstor.csi.linbit.com/placementCount: "3"
EOF
```

**What this creates:**
- `piraeus-storage-single` - 1 replica, no redundancy
- `piraeus-storage` - 2 replicas (2-way replication), **default** for all PVCs
- `piraeus-storage-ha` - 3 replicas (3-way replication) for critical data
- ✅ **DRBD automatically used** for replication when `placementCount > 1`

**Notes:**
- `volumeBindingMode: WaitForFirstConsumer` delays provisioning until a pod uses the PVC
- DRBD layer is automatically added when replication is needed (no need to specify `layerList`)

### 6.3: Verify StorageClasses

```bash
kubectl get storageclass
```

Expected output:
```
NAME                       PROVISIONER                RECLAIMPOLICY   VOLUMEBINDINGMODE      ALLOWVOLUMEEXPANSION
piraeus-storage (default)  linstor.csi.linbit.com     Delete          WaitForFirstConsumer   true
piraeus-storage-ha         linstor.csi.linbit.com     Delete          WaitForFirstConsumer   true
piraeus-storage-single     linstor.csi.linbit.com     Delete          WaitForFirstConsumer   true
```

### 6.4: Usage Patterns

**When to use each StorageClass:**

| Use Case | StorageClass | Why |
|----------|--------------|-----|
| Development/testing | `piraeus-storage-single` | Saves space, fast |
| Web apps, APIs | `piraeus-storage` | Good balance |
| Caching (Redis w/ backup) | `piraeus-storage` | Can restore if needed |
| **PostgreSQL/MySQL** | `piraeus-storage-ha` | Critical data |
| **Elasticsearch master** | `piraeus-storage-ha` | Cluster state is critical |
| **etcd** | `piraeus-storage-ha` | Critical metadata |
| Config/secrets | `piraeus-storage-ha` | Small but important |
| Temporary scratch space | `piraeus-storage-single` | Not important |

### 6.5: Create Test PVC (2-way replication)

```bash
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: test-pvc
spec:
  storageClassName: piraeus-storage  # Uses default 2-way replication
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 1Gi
EOF
```

### 6.6: Create Test Pod

```bash
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: test-pod
spec:
  containers:
    - name: test
      image: nginx:alpine
      volumeMounts:
        - name: data
          mountPath: /data
      command: ["/bin/sh", "-c"]
      args:
        - |
          echo "Testing Piraeus storage" > /data/test.txt
          echo "Hostname: $(hostname)" >> /data/test.txt
          echo "Date: $(date)" >> /data/test.txt
          tail -f /dev/null
  volumes:
    - name: data
      persistentVolumeClaim:
        claimName: test-pvc
EOF
```

### 6.7: Verify Volume is Bound and Pod is Running

```bash
kubectl get pvc test-pvc
kubectl get pod test-pod
```

Expected output:
```
NAME       STATUS   VOLUME                                     CAPACITY   ACCESS MODES
test-pvc   Bound    pvc-xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx   1Gi        RWO

NAME       READY   STATUS    RESTARTS   AGE
test-pod   1/1     Running   0          30s
```

### 6.8: Check LINSTOR Resources

Check which nodes have replicas and verify DRBD is active:

```bash
kubectl -n piraeus-datastore exec deploy/linstor-controller -- \
  linstor resource list
```

Expected output (2 replicas on 2 different nodes):
```
+------------------------------------------------------------------------------------------------------------------------------+
| ResourceName                             | Node             | Layers       | Usage  | Conns |    State | CreatedOn           |
|==============================================================================================================================|
| pvc-xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx | talos-control-01 | DRBD,STORAGE | Unused | Ok    | UpToDate | 2025-11-05 17:21:27 |
| pvc-xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx | talos-control-02 | DRBD,STORAGE | InUse  | Ok    | UpToDate | 2025-11-05 17:21:26 |
+------------------------------------------------------------------------------------------------------------------------------+
```

**What to look for:**
- ✅ **Layers: DRBD,STORAGE** - Confirms DRBD replication is active
- ✅ **2 nodes** - Correct for 2-way replication (only 2 out of 3 nodes)
- ✅ **State: UpToDate** - Both replicas are synchronized
- ✅ **One InUse** - The node where the pod is running
- ✅ **Conns: Ok** - DRBD connections established

Note: Only 2 out of 3 nodes will have the volume (2-way replication). The third node is available if one replica fails.

### 6.9: Test Volume Persistence

Verify data persists across pod restarts:

```bash
# Read data written by pod
kubectl exec test-pod -- cat /data/test.txt

# Delete and recreate pod
kubectl delete pod test-pod
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: test-pod
spec:
  containers:
    - name: test
      image: nginx:alpine
      volumeMounts:
        - name: data
          mountPath: /data
  volumes:
    - name: data
      persistentVolumeClaim:
        claimName: test-pvc
EOF

# Wait for pod to be ready
kubectl wait pod test-pod --for=condition=Ready --timeout=60s

# Verify data is still there
kubectl exec test-pod -- cat /data/test.txt
```

You should see the same data, proving persistence across pod restarts.

### 6.10: Test Different Replication Modes (Optional)

Test 3-way replication for critical data:

```bash
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: critical-pvc
spec:
  storageClassName: piraeus-storage-ha  # 3-way replication
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 1Gi
---
apiVersion: v1
kind: Pod
metadata:
  name: critical-pod
spec:
  containers:
    - name: database
      image: postgres:15-alpine
      env:
        - name: POSTGRES_PASSWORD
          value: "testpass"
      volumeMounts:
        - name: data
          mountPath: /var/lib/postgresql/data
  volumes:
    - name: data
      persistentVolumeClaim:
        claimName: critical-pvc
EOF
```

Verify 3 replicas:

```bash
kubectl -n piraeus-datastore exec deploy/linstor-controller -- \
  linstor resource list-volumes | grep critical-pvc
```

You should see the volume on **all 3 nodes**.

### 6.11: View Storage Usage

Check how much storage is being used:

```bash
# Storage pool status
kubectl -n piraeus-datastore exec deploy/linstor-controller -- \
  linstor storage-pool list

# Volume details
kubectl -n piraeus-datastore exec deploy/linstor-controller -- \
  linstor volume list
```

### 6.12: Cleanup Test Resources

```bash
# Delete test resources
kubectl delete pod test-pod
kubectl delete pvc test-pvc

# Delete critical test resources (if created)
kubectl delete pod critical-pod
kubectl delete pvc critical-pvc
```

### 6.13: How Multiple StorageClasses Work Together

All three StorageClasses **share the same physical storage pool** (`pool1`), but create volumes with different replication settings.

**Example scenario:**
```
Application A (Web App):
├─ PVC: uses piraeus-storage (2-way)
├─ Size: 10GB requested
└─ Storage used: 20GB total (10GB × 2 replicas)

Application B (Database):
├─ PVC: uses piraeus-storage-ha (3-way)
├─ Size: 5GB requested
└─ Storage used: 15GB total (5GB × 3 replicas)

Total consumed from 1500GB pool: 35GB
Remaining available: 1465GB
```

**Visual representation:**
```
┌─────────────────────────────────────────┐
│ talos-control-01 (pool1: 500GB)         │
├─────────────────────────────────────────┤
│ ✓ App A - Replica 1  → 10GB (Primary)   │
│ ✓ App B - Replica 1  → 5GB  (Primary)   │
│ Used: 15GB / 500GB                       │
└─────────────────────────────────────────┘

┌─────────────────────────────────────────┐
│ talos-control-02 (pool1: 500GB)         │
├─────────────────────────────────────────┤
│ ✓ App A - Replica 2  → 10GB (Secondary) │
│ ✓ App B - Replica 2  → 5GB  (Secondary) │
│ Used: 15GB / 500GB                       │
└─────────────────────────────────────────┘

┌─────────────────────────────────────────┐
│ talos-control-03 (pool1: 500GB)         │
├─────────────────────────────────────────┤
│   App A - No replica → 0GB  (2-way only)│
│ ✓ App B - Replica 3  → 5GB  (Secondary) │
│ Used: 5GB / 500GB                        │
└─────────────────────────────────────────┘
```

LINSTOR automatically manages replica placement across nodes for optimal distribution.

## Troubleshooting

### PVC Stuck in Pending - "Not enough free storage"

**Symptom:**
```bash
kubectl get pvc
# NAME       STATUS    VOLUME   CAPACITY   ACCESS MODES   STORAGECLASS
# test-pvc   Pending                                      piraeus-storage

kubectl describe pod <pod-name>
# Error: "0/3 nodes are available: 3 node(s) did not have enough free storage"
```

**Root Cause:**

CSI storage capacity objects are reporting 0 capacity, even though storage pools have available space.

**Diagnosis:**

Check CSI storage capacities:
```bash
kubectl get csistoragecapacities -n piraeus-datastore -o yaml | grep "capacity:" | head -10
```

If you see `capacity: "0"`, this is the issue.

**Solution:**

Delete stale CSI storage capacity objects to force refresh:

```bash
kubectl delete csistoragecapacities -n piraeus-datastore --all
```

Wait 10-15 seconds for them to be recreated with correct values:

```bash
kubectl get csistoragecapacities -n piraeus-datastore -o yaml | grep -A2 "storageClassName: piraeus-storage"
# Should now show capacity in MiB (e.g., "capacity: 1535220Mi")
```

The PVC should now provision successfully.

### PVC Stuck in Pending - "Additional replica count" Error

**Symptom:**
```bash
kubectl get pvc
# NAME       STATUS    VOLUME   CAPACITY   ACCESS MODES   STORAGECLASS
# test-pvc   Pending                                      piraeus-storage

kubectl describe pvc test-pvc
# Error: "Additional replica count: 2" or "Replica count: 2, Additional replica count: 2"
# Error: "failed to enough replicas on requisite nodes"
```

**Root Cause:**

DRBD's auto-quorum-tiebreaker is trying to add extra replicas for quorum, which exceeds available nodes.

**Solution:**

Disable auto-quorum-tiebreaker:

```bash
kubectl -n piraeus-datastore exec deploy/linstor-controller -- \
  linstor controller set-property DrbdOptions/auto-add-quorum-tiebreaker false
```

Restart LINSTOR controllers to apply the setting:

```bash
kubectl -n piraeus-datastore rollout restart deployment/linstor-controller deployment/linstor-csi-controller
kubectl -n piraeus-datastore rollout status deployment/linstor-controller deployment/linstor-csi-controller --timeout=60s
```

Delete and recreate stuck PVC:

```bash
kubectl delete pvc test-pvc
kubectl apply -f <your-pvc-manifest>
```

### PVC Stuck in Pending - DRBD Module Not Loaded

**Symptom:**
```bash
kubectl describe pvc test-pvc
# Error: "Satellite does not support the following layers: [DRBD]"
```

**Root Cause:**

DRBD kernel module is not loaded on Talos nodes.

**Diagnosis:**

Check if DRBD module is loaded:
```bash
kubectl -n piraeus-datastore get pods -l app.kubernetes.io/component=linstor-satellite -o name | head -1 | \
  xargs -I {} kubectl -n piraeus-datastore exec {} -- lsmod | grep drbd
```

If no output, DRBD is not loaded.

**Solution:**

1. Verify Talos image has DRBD extension (see [Step 1.1](#11-verify-talos-image-has-drbd-extension))
2. Verify kernel modules in Terraform config (see [Step 1.2](#12-enable-required-kernel-modules))
3. Apply Terraform configuration:
   ```bash
   terraform apply -auto-approve -target=talos_machine_configuration_apply.controlplane
   ```
4. Wait 30-60 seconds for nodes to reload modules
5. Verify DRBD is now loaded (see [Step 5.6](#56-verify-drbd-module-is-loaded))

### Pods Stuck in Pending

**Symptom:**
```bash
kubectl get pods -n piraeus-datastore
# Shows pods with STATUS: Pending
```

**Diagnosis:**
```bash
kubectl describe pod -n piraeus-datastore <pod-name>
```

Look for events mentioning taints.

**Solution:**

Check for control-plane taints:
```bash
kubectl describe nodes | grep -A 5 "Taints:"
```

If you see `node-role.kubernetes.io/control-plane:NoSchedule`:
- Verify Step 1.1 was applied correctly
- Re-apply Terraform configuration
- Taints may reappear if `allowSchedulingOnControlPlanes` is not in cluster config

### Systemd Volume Mount Failures

**Symptom:**
```bash
kubectl describe pod -n piraeus-datastore linstor-satellite.xxx
# Shows: MountVolume.SetUp failed for volume "run-systemd-system"
```

**Solution:**

Ensure you applied the Talos-specific satellite configuration from Step 3.1. If already applied, delete and recreate the LinstorCluster:

```bash
kubectl delete linstorcluster linstorcluster
kubectl apply -f - <<'EOF'
apiVersion: piraeus.io/v1
kind: LinstorCluster
metadata:
  name: linstorcluster
spec: {}
EOF
```

### Storage Pool Creation Fails

**Symptom:**
```bash
linstor physical-storage create-device-pool ...
# ERROR: Can't open /dev/vdb exclusively. Mounted filesystem?
# ERROR: device has a signature
```

**Solution:**

The device has remnant signatures or is temporarily locked. Try:

**Option 1: More thorough wipe**
```bash
# Replace node name and device as needed
kubectl -n piraeus-datastore exec daemonset/linstor-satellite.talos-control-01 \
  -c linstor-satellite -- sh -c "
  dd if=/dev/zero of=/dev/vdb bs=1M count=500 &&
  dd if=/dev/zero of=/dev/vdb bs=1M seek=511500 count=100
  "
```

**Option 2: Manual pool creation**

If automated creation continues to fail, create manually:

```bash
# Step 1: Create physical volume
kubectl -n piraeus-datastore exec daemonset/linstor-satellite.talos-control-01 \
  -c linstor-satellite -- pvcreate /dev/vdb

# Step 2: Create volume group and thin pool
kubectl -n piraeus-datastore exec daemonset/linstor-satellite.talos-control-01 \
  -c linstor-satellite -- sh -c "
  vgcreate linstor_pool1 /dev/vdb &&
  lvcreate -l 100%FREE -T linstor_pool1/pool1
  "

# Step 3: Register with LINSTOR
kubectl -n piraeus-datastore exec deploy/linstor-controller -- \
  linstor storage-pool create lvmthin talos-control-01 pool1 linstor_pool1/pool1
```

Repeat for each node.

### Controller CrashLoopBackOff with Migration Errors

**Symptom:**
```bash
kubectl logs -n piraeus-datastore linstor-controller-xxx -c run-migration
# Shows: Cannot perform Migration X while a rollback has to be done
```

**Solution:**

Database is in rollback state from previous failed installation. Clean up:

```bash
# Delete cluster
kubectl delete linstorcluster linstorcluster

# Wait for cleanup
sleep 10

# Delete rollback resources
kubectl delete rollback.internal.linstor.linbit.com --all

# Delete all LINSTOR CRDs (optional, only if issues persist)
# kubectl get crd | grep internal.linstor | awk '{print $1}' | xargs kubectl delete crd

# Recreate cluster
kubectl apply -f - <<'EOF'
apiVersion: piraeus.io/v1
kind: LinstorCluster
metadata:
  name: linstorcluster
spec: {}
EOF
```

### dm-thin-pool Module Not Found

**Symptom:**
```bash
linstor physical-storage create-device-pool ...
# ERROR: modprobe: FATAL: Module dm-thin-pool not found
```

**Solution:**

The kernel module isn't loaded. This means Step 1.1 wasn't applied correctly:

1. Verify Terraform/Talos config includes `kernel.modules` section
2. Re-apply Terraform configuration
3. Wait for nodes to reconfigure
4. Verify module is loaded:
```bash
kubectl -n piraeus-datastore exec daemonset/linstor-satellite.talos-control-01 \
  -c linstor-satellite -- lsmod | grep dm_thin_pool
```

### CSI Pods Stuck in Init

**Symptom:**
```bash
kubectl get pods -n piraeus-datastore
# linstor-csi-controller and linstor-csi-node pods in Init:0/1
```

**Diagnosis:**

CSI pods wait for controller to be ready. Check controller status:
```bash
kubectl get pods -n piraeus-datastore -l app.kubernetes.io/component=linstor-controller
```

If controller is Running, CSI pods should start within 1-2 minutes. If they remain in Init, check logs:
```bash
kubectl logs -n piraeus-datastore linstor-csi-controller-xxx -c init
```

## Production Considerations

### DRBD Replication

For full DRBD replication support with kernel module:

1. Build Talos with DRBD system extension:
   - Visit [Talos Factory](https://factory.talos.dev)
   - Include `siderolabs/drbd` extension
   - Use generated installer image

2. Configure DRBD module parameters:
```hcl
kernel = {
  modules = [
    {
      name = "drbd"
      parameters = ["usermode_helper=disabled"]
    },
    {
      name = "drbd_transport_tcp"
    },
    {
      name = "dm-thin-pool"
    }
  ]
}
```

3. Verify DRBD is loaded:
```bash
kubectl -n piraeus-datastore exec daemonset/linstor-satellite.talos-control-01 \
  -c linstor-satellite -- sh -c "cat /proc/drbd"
```

### Worker Nodes vs Control-Plane

**For production clusters:**
- Use dedicated worker nodes for workloads
- Remove `allowSchedulingOnControlPlanes = true`
- Keep control-plane nodes for cluster management only
- Deploy Piraeus satellites on worker nodes

### Storage Pool Sizing

- **Over-provisioning**: LVM thin pools allow over-provisioning
- **Monitoring**: Set up alerts for storage pool usage
- **Capacity planning**: Keep 20-30% free space for snapshots and thin pool overhead

### High Availability

- **Replication count**: Use `placementCount: "3"` for critical data
- **Auto-evict**: Configure LINSTOR to auto-evict failed nodes
- **Backup**: Regular backups using LINSTOR snapshots

### Security

- Enable TLS for LINSTOR API
- Use DRBD TLS for replication traffic
- Network policies to restrict access

### Monitoring

Integrate with Prometheus:
```bash
kubectl apply -f https://github.com/piraeusdatastore/piraeus-operator/raw/v2/docs/how-to/monitoring-examples.yaml
```

## Complete Working Example

Here's a complete working Terraform snippet for reference:

```hcl
resource "talos_machine_configuration_apply" "controlplane" {
  for_each = local.talos_master_nodes

  client_configuration        = talos_machine_secrets.this.client_configuration
  machine_configuration_input = data.talos_machine_configuration.controlplane.machine_configuration
  node                       = proxmox_vm_qemu.talos[each.key].default_ipv4_address

  config_patches = [
    yamlencode({
      cluster = {
        allowSchedulingOnControlPlanes = true
        controlPlane = {
          endpoint = "https://${local.talos_vip_ip}:6443"
        }
      }
      machine = {
        network = {
          hostname = each.key
          interfaces = [
            {
              interface = "ens18"
              dhcp      = true
              vip = {
                ip = local.talos_vip_ip
              }
            }
          ]
        }
        kernel = {
          modules = [
            {
              name = "dm-thin-pool"
            }
          ]
        }
        features = {
          kubePrism = {
            enabled = true
            port    = 7445
          }
        }
      }
    })
  ]
}
```

## References

- [Piraeus Operator Documentation](https://github.com/piraeusdatastore/piraeus-operator/blob/v2/docs/README.md)
- [Piraeus on Talos Linux](https://github.com/piraeusdatastore/piraeus-operator/blob/v2/docs/how-to/talos.md)
- [Talos System Extensions](https://github.com/siderolabs/extensions)
- [LINSTOR User Guide](https://linbit.com/drbd-user-guide/linstor-guide-1_0-en/)
- [LVM Thin Provisioning](https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/7/html/logical_volume_manager_administration/lv#thinly_provisioned_volume_creation)

## Appendix: Common Commands

### Check Cluster Status
```bash
# All pods
kubectl get pods -n piraeus-datastore

# LINSTOR nodes
kubectl -n piraeus-datastore exec deploy/linstor-controller -- linstor node list

# Storage pools
kubectl -n piraeus-datastore exec deploy/linstor-controller -- linstor storage-pool list

# Resources/volumes
kubectl -n piraeus-datastore exec deploy/linstor-controller -- linstor resource list-volumes
```

### Create Storage Pool (alternative methods)

**File thin pool** (simpler, less performant):
```bash
kubectl apply -f - <<'EOF'
apiVersion: piraeus.io/v1
kind: LinstorSatelliteConfiguration
metadata:
  name: file-pool
spec:
  storagePools:
    - name: pool1
      fileThinPool:
        directory: /var/lib/piraeus-datastore/pool1
EOF
```

**LVM thin pool** (recommended):
See Step 5 above.

### Uninstall Piraeus

```bash
# Delete cluster
kubectl delete linstorcluster linstorcluster

# Wait for cleanup
sleep 30

# Delete operator
kubectl delete ns piraeus-datastore

# Delete CRDs
kubectl get crd | grep piraeus.io | awk '{print $1}' | xargs kubectl delete crd
kubectl get crd | grep internal.linstor | awk '{print $1}' | xargs kubectl delete crd
```

---

**Last Updated:** 2025-11-05
**Tested with:** Talos v1.11.1, Kubernetes v1.33.3, Piraeus Operator v2.9.1
