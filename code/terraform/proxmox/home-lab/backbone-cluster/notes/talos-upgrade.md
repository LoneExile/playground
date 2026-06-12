# Talos OS Upgrade Runbook (backbone-cluster)

How to upgrade the Talos version on the backbone cluster **the right way**, and
the two gotchas that will bite you if you don't. Written after the
`v1.12.6 → v1.13.4` upgrade (2026-06-12).

The cluster is 3 control-plane VMs on `pve` + 1 GPU worker on the NAS host:

| node | role | IP | host |
|------|------|----|----|
| bb-ctrl-01 | controlplane (etcd, bootstrap) | 10.0.10.201 | pve |
| bb-ctrl-02 | controlplane (etcd) | 10.0.10.202 | pve |
| bb-ctrl-03 | controlplane (etcd) | 10.0.10.203 | pve |
| bb-worker-01 | worker (Intel iGPU / i915) | 10.0.10.205 | NAS (proxmox) |

K8s API VIP: `10.0.10.204`. Stage-01 dir: `01-talos-cluster/`.

---

## TL;DR

**Do NOT `terraform apply` to upgrade a running cluster.** The stage-01
machineconfig has `install.wipe = true`; a reprovision is for building a fresh
cluster, not upgrading a live one. Upgrades are done with **`talosctl upgrade`**
(A/B partition swap, rolling, non-destructive), then the Terraform source is
edited to *match* reality so future fresh-provisions are correct.

```
1. Confirm v1.13.4 is the target; existing schematic IDs work as-is
   UNLESS you are also changing the extension set (then regenerate, see §2).
2. talosctl upgrade each node, ONE at a time, control-plane first.
   - use --wait=false to dodge the too_many_pings bug (§4)
   - patch kernel modules if zfs/drbd extensions are present (§5)
3. Verify each node Ready + etcd healthy BEFORE touching the next.
4. Edit variables.tf (version + schematic IDs) + main.tf (kernel.modules)
   so the committed source matches. Do NOT apply — it's only for future
   fresh provisions.
```

Wall time: ~5-8 min per node, ~25-35 min total for 4 nodes.

---

## Key fact: schematic ID vs version are independent

The Talos Image Factory schematic ID is a **hash of the customization**
(extensions, kernel args) — it is NOT tied to a Talos version. The same
schematic ID serves every version:

```
factory.talos.dev/metal-installer/<schematic_id>:<version>
factory.talos.dev/image/<schematic_id>/<version>/metal-amd64.iso
```

So **if you only bump the OS version and keep the same extensions, you do NOT
need to touch factory.talos.dev** — just change the version string. You only
regenerate a schematic when the *extension set* changes.

---

## 0. Pre-flight

```bash
cd 01-talos-cluster
export TALOSCONFIG="$PWD/talosconfig" KUBECONFIG="$PWD/kubeconfig"

# what version is latest?
curl -fsSL https://api.github.com/repos/siderolabs/talos/releases/latest | jq -r .tag_name

# talosctl client should be >= target minor
talosctl version --client

# cluster healthy BEFORE starting? etcd must have NO alarms and full membership
talosctl -n 10.0.10.201 etcd members
talosctl -n 10.0.10.201 etcd alarm list      # empty = healthy
kubectl get nodes
```

Never start an upgrade with a degraded etcd or a NotReady node — you have a
3-node etcd, so you can lose exactly **one** member at a time. Lose two and the
cluster loses quorum.

---

## 1. Set the target version

`TALOS=v1.13.4` (or whatever is latest). Current schematic IDs live in
`01-talos-cluster/variables.tf`:

- `talos_schematic_id`  — control plane
- `worker_schematic_id` — worker (control-plane set **+ i915** for the iGPU)

---

## 2. (Only if changing extensions) regenerate schematics

Skip this whole section if the extension set is unchanged.

Inspect what a schematic currently contains:

```bash
curl -fsSL https://factory.talos.dev/schematics/<schematic_id>
```

Validate any new extension name exists for the target version:

```bash
curl -fsSL https://factory.talos.dev/version/v1.13.4/extensions/official \
  | jq -r '.[].name' | sort
```

Create a new schematic (POST a YAML body; the factory canonicalises + returns
an `id`). Order doesn't matter for the resulting hash, but keep it sorted:

```bash
read -r -d '' BODY <<'YAML'
customization:
  systemExtensions:
    officialExtensions:
      - siderolabs/amazon-ena
      - siderolabs/amd-ucode
      - siderolabs/amdgpu
      - siderolabs/binfmt-misc
      - siderolabs/bird2
      - siderolabs/bnx2-bnx2x
      - siderolabs/btrfs
      - siderolabs/drbd
      - siderolabs/intel-ice-firmware
      - siderolabs/intel-ucode
      - siderolabs/nfs-utils
      - siderolabs/nfsd
      - siderolabs/nfsrahead
      - siderolabs/qlogic-firmware
      - siderolabs/zfs
YAML
curl -fsSL -X POST --data-binary "$BODY" https://factory.talos.dev/schematics | jq -r .id
# worker = same list + "- siderolabs/i915"
```

Verify the new ID resolves for the target version (expect HTTP 200):

```bash
curl -fsSL -o /dev/null -w '%{http_code}\n' \
  https://factory.talos.dev/image/<new_id>/v1.13.4/metal-amd64.iso
```

Current extension set (as of v1.13.4):

- **Control plane** (`d0d6faa0…`): amazon-ena, amd-ucode, amdgpu, binfmt-misc,
  bird2, bnx2-bnx2x, btrfs, **drbd**, intel-ice-firmware, intel-ucode,
  nfs-utils, nfsd, nfsrahead, qlogic-firmware, **zfs**
- **Worker** (`20811fa4…`): same **+ i915**

> NFS note: nodes are NFS *clients* (mounting the NAS), so only `nfs-utils` is
> strictly required. `nfsd`/`nfsrahead` are kept to match the original set.

---

## 3. The upgrade loop (per node)

Control plane **first, one at a time**, then the worker last. Define the
installer images once:

```bash
CP=factory.talos.dev/metal-installer/d0d6faa0e0c33f9953065bb820a97c4d7e7d3fc208efdcd2aef41da5e87de2cb:v1.13.4
WK=factory.talos.dev/metal-installer/20811fa476a08d5f86b967fdece62903ebeb3bc26e8a65df4b4b72415642c414:v1.13.4
```

For each node `N` (201 → 202 → 203 → 205):

```bash
# 3a. fire the upgrade — see §4 for why --wait=false
talosctl upgrade -n $N --image "$CP" --preserve --wait=false      # $WK for the worker

# 3b. node reboots into the new version. If the schematic has zfs/drbd,
#     it will hang in stage "booting" — patch kernel modules, see §5
talosctl -n $N patch machineconfig --mode=no-reboot --patch @- <<'YAML'
machine:
  kernel:
    modules:
      - name: zfs
      - name: drbd
YAML

# 3c. wait for running + verify BEFORE next node
talosctl -n $N get machinestatus          # STAGE must be "running"
talosctl -n $N services | grep -E 'etcd|kubelet|ext-zfs-service'   # all Running
talosctl -n 10.0.10.201 etcd alarm list   # still empty
kubectl get nodes                          # node Ready, OS-IMAGE = Talos (v1.13.4)
```

`--preserve` keeps the EPHEMERAL partition (etcd data) so the member rejoins
fast instead of re-syncing from peers. Harmless on the worker.

The worker (`205`) is not an etcd member — `talosctl upgrade` `--drain` (default)
cordons + evicts its pods first, so GPU workloads reschedule cleanly.

---

## 4. GOTCHA: `too_many_pings` / ENHANCE_YOUR_CALM

When the client minor is **ahead** of the server (e.g. talosctl `v1.13` driving
a `v1.12.6` node — true for the *first* upgrade of each node), the gRPC
keepalive pings exceed the old server's policy and the server sends a GoAway:

```
ERROR: [transport] Client received GoAway with error code ENHANCE_YOUR_CALM
       and debug data equal to ASCII "too_many_pings".
rpc error: code = Unavailable desc = closing transport ... "too_many_pings"
```

This **cancels the server-side image-pull context mid-fetch**, so the upgrade
aborts and the node stays on the old version (safe, but nothing happened). Look
for this in `talosctl -n $N dmesg`:

```
[talos] validating "factory.talos.dev/metal-installer/...:v1.13.4"
level=info msg=fetch failed error=... context canceled
[talos] retrying error: failed to pull image ... context canceled
```

**Fix:** add `--wait=false`. talosctl issues the upgrade RPC and disconnects
immediately; the upgrade actor then runs server-side, independent of the
client, so there's no long-held pinging stream to get killed.

It's still racy — sometimes the GoAway fires before the actor registers. If the
node doesn't start rebooting within ~30s, **just fire it again** (idempotent).
A fire-until-the-port-closes loop:

```bash
N=10.0.10.205
for try in 1 2 3 4 5; do
  talosctl upgrade -n $N --image "$WK" --preserve --wait=false 2>&1 | tail -2
  for j in $(seq 1 4); do
    nc -z -w2 $N 50000 || { echo "reboot started"; break 2; }   # port closed = upgrading
    [ "$(talosctl -n $N version 2>/dev/null | awk '/Tag:/{c++;if(c==2)print $2}')" = "$TALOS" ] \
      && { echo "already upgraded"; break 2; }
    sleep 8
  done
done
```

This bug disappears once the node is on the new version (the new server speaks
the new upgrade API, no ping-policy violation).

---

## 5. GOTCHA: zfs / drbd extensions hang the boot

If the schematic includes `siderolabs/zfs` (and/or `drbd`), the node will get
**stuck in stage `booting` forever** after the upgrade:

```
ext-zfs-service   Waiting   Waiting for file "/dev/zfs" to exist
[talos] task startAllServices (1/1): service "ext-zfs-service" to be "up"   # loops
```

Talos ships the kernel **module** in the extension but does **not auto-load it**.
Without `/dev/zfs`, `ext-zfs-service` never comes up, and `startAllServices`
blocks the whole boot sequence. (Same failure class as the `bird2` extension
needing a config file — see the note in `main.tf`.)

**Fix:** load the modules explicitly via machineconfig. Two places:

1. **Live, during the stuck boot** (apid is up even while `booting`):

   ```bash
   talosctl -n $N patch machineconfig --mode=no-reboot --patch @- <<'YAML'
   machine:
     kernel:
       modules:
         - name: zfs
         - name: drbd
   YAML
   ```

   Within seconds: `drbd: registered as block device major 147`,
   `ZFS: Loaded module`, `ext-zfs-service` → Running, stage → `running`.

2. **Permanently, in Terraform** so it survives a config re-assert / fresh
   provision. Already added to `main.tf` `config_patches` for **both** the
   controlplane and worker apply blocks:

   ```hcl
   machine = {
     install = { ... }
     kernel = {
       modules = [
         { name = "zfs" },
         { name = "drbd" },
       ]
     }
     network = { ... }
   }
   ```

> If `main.tf` already carries `kernel.modules` for the node's class, a fresh
> provision boots clean and step 1 is unnecessary. Step 1 is only needed when
> upgrading nodes whose *on-disk* config predates the extension being added.

---

## 6. Reconcile Terraform (source only — do NOT apply)

After all nodes are on the new version, edit `01-talos-cluster/` so the
committed source matches the live cluster:

- `variables.tf` → `talos_version`, `talos_schematic_id`, `worker_schematic_id`
- `main.tf` → `machine.kernel.modules` in both apply blocks (if extensions added)

A `terraform plan` will then show drift that is **safe but should not be applied
just to upgrade**:

```
talos_machine_secrets.this            will be updated in-place   # version field only, CA NOT regenerated — safe
talos_machine_configuration_apply.*   will be updated in-place   # re-assert install.image + kernel.modules
proxmox_download_file.talos_iso*      must be replaced           # re-download new ISO, delete old
proxmox_virtual_environment_vm.*      will be updated in-place   # hot-swap cdrom to new ISO, no VM/disk destroy
Plan: 4 to add, 11 to change, 3 to destroy.
```

The "3 to destroy" are 2 ISO files + the local `talosconfig` regen — **no VM or
cluster destroy**. Confirm `talos_machine_secrets` is **in-place, not replaced**
(a replace would regenerate the cluster CA = new cluster). Applying is optional
and only affects fresh-provision media; the running cluster is already upgraded.

---

## 7. Final verification

```bash
kubectl get nodes -o custom-columns=\
'NAME:.metadata.name,STATUS:.status.conditions[-1].type,OS:.status.nodeInfo.osImage,KERNEL:.status.nodeInfo.kernelVersion'

for n in 10.0.10.201 10.0.10.202 10.0.10.203 10.0.10.205; do
  echo "== $n =="
  talosctl -n $n get machinestatus | awk 'NR>1{print "stage="$6}'
  talosctl -n $n services | grep -E 'etcd|kubelet|ext-zfs-service'
done
talosctl -n 10.0.10.201 etcd members
talosctl -n 10.0.10.201 etcd alarm list                       # empty
kubectl get node bb-worker-01 -o jsonpath='{.metadata.labels.accelerator}'   # intel-quicksync
kubectl get pods -A | grep -vE 'Running|Completed'            # only the header
```

Expect: all nodes `Talos (v1.13.4)`, kernel `6.18.34-talos`, stage `running`,
etcd 3 members + no alarms, worker iGPU label intact, zero unhealthy pods.

---

## 8. Kubernetes version (separate, optional)

Talos OS and Kubernetes upgrade independently. The cluster runs K8s `v1.35.0`.
To bump K8s after the OS upgrade:

```bash
talosctl -n 10.0.10.201 upgrade-k8s --to v1.35.x
```

Then update `kubernetes_version` in `variables.tf`. Not part of the OS upgrade.

---

## Quick reference — what bit us, what to do

| symptom | cause | fix |
|---------|-------|-----|
| `too_many_pings` GoAway, upgrade aborts, node stays on old ver | client minor > server minor, gRPC keepalive | `--wait=false`, retry until port closes (§4) |
| node stuck stage `booting`, `ext-zfs-service Waiting for /dev/zfs` | zfs/drbd module not auto-loaded | patch `machine.kernel.modules` (§5) |
| `terraform apply` wants to wipe/replace nodes | wrong upgrade method | never apply to upgrade — use `talosctl upgrade` (§TL;DR) |
| etcd alarm or 2 members down mid-upgrade | upgraded a 2nd node before the 1st rejoined | only one etcd member down at a time (§0) |
