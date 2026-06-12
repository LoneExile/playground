# Raspberry Pi 4 Worker Join Runbook (backbone-cluster)

How to add a **physical Raspberry Pi 4** (arm64) as a worker to the
Talos cluster. Written after joining `bb-worker-02` (2026-06-12).

The Pi is **not** a Proxmox VM, so it does not go through the `worker_nodes`
map in stage-01 (that builds Proxmox VMs). It boots from a flashed SBC image
and joins over the maintenance API, then is codified as its own
`talos_machine_configuration_apply.pi_worker` resource.

End state for `bb-worker-02`:

| field | value |
|-------|-------|
| node IP (static) | `10.0.10.206` |
| MAC | `e4:5f:01:f4:c9:e3` (Raspberry Pi OUI `e4:5f:01`) |
| hostname | `bb-worker-02` |
| arch | arm64 |
| boot/install disk | `/dev/sda` (USB SSD — no SD card) |
| NIC | `end0` |
| Talos | v1.13.4, kernel `6.18.34-talos` |
| schematic | `7eced002b21eec49a420a36a4c31df7a4552cacc5052f2edfc8887e5e0da98d4` |

---

## TL;DR

```
1. Generate a SBC schematic (overlay rpi_generic) — NOT a generic metal one (§1).
2. Flash the raw.xz disk image to the SD/USB (NOT the ISO) (§2).
3. Put the switch port on the cluster VLAN (Home / 10.0.10.0/24) (§3).
   - changing native VLAN does NOT bounce the link → replug the cable to re-DHCP.
4. Find the Pi's maintenance IP (UniFi API or scan) + detect disk/NIC (§4).
5. Add talos_machine_configuration_apply.pi_worker, apply -target (§5).
6. Verify Ready + arm64 (§6).
```

The Pi reuses the cluster's existing machine secrets (via Terraform), so no new
bootstrap — it just joins.

---

## 1. Schematic — MUST use the Raspberry Pi overlay

The biggest trap: a Pi 4 needs the **`siderolabs/sbc-raspberrypi` overlay**
(board `rpi_generic`). The generic `metal-arm64` image has **no Pi
bootloader/U-Boot/firmware** and will not boot. (Pi 5 = `rpi_5`.)

Also drop the **x86-only** extensions — they're dead weight on ARM:
`amd-ucode`, `intel-ucode`, `intel-ice-firmware`, `bnx2-bnx2x`, `qlogic-firmware`.
And skip `zfs`/`drbd` unless the Pi will host that storage (RAM-heavy, and they
trigger the boot-hang gotcha — see `talos-upgrade.md` §5).

List the available overlays for a version:

```bash
curl -fsSL https://factory.talos.dev/version/v1.13.4/overlays/official \
  | jq -r '.[] | "\(.name)\t\(.image)"' | grep -i rpi
# rpi_generic  siderolabs/sbc-raspberrypi
# rpi_5        siderolabs/sbc-raspberrypi
```

Create the schematic (note the `overlay:` block on top of `customization:`):

```bash
read -r -d '' BODY <<'YAML'
overlay:
  image: siderolabs/sbc-raspberrypi
  name: rpi_generic
customization:
  systemExtensions:
    officialExtensions:
      - siderolabs/binfmt-misc
      - siderolabs/bird2        # matches the worker bird2 ExtensionServiceConfig
      - siderolabs/nfs-utils    # NFS client for NAS-backed PVs
      - siderolabs/nfsd
      - siderolabs/nfsrahead
YAML
curl -fsSL -X POST --data-binary "$BODY" https://factory.talos.dev/schematics | jq -r .id
# => 7eced002b21eec49a420a36a4c31df7a4552cacc5052f2edfc8887e5e0da98d4
```

Confirm the factory recognised it as an SBC: the schematic page should show
**"disk image for Raspberry Pi Series"** + `metal-arm64.raw.xz` (and no ISO).
That's the tell the overlay took.

---

## 2. Flash the disk image (not the ISO)

SBCs boot from a pre-written disk image; the overlay bakes in the Pi bootloader.
Write the **raw.xz** to the SD card or USB SSD:

```bash
curl -fsSL -o talos-rpi.raw.xz \
  https://factory.talos.dev/image/7eced002b21eec49a420a36a4c31df7a4552cacc5052f2edfc8887e5e0da98d4/v1.13.4/metal-arm64.raw.xz
xz -d talos-rpi.raw.xz
sudo dd if=talos-rpi.raw of=/dev/diskN bs=4M conv=fsync status=progress   # diskN = SD/USB
```

`bb-worker-02` boots from a **USB SSD** (more durable than SD). Either works;
the install disk in §5 must match what you flashed (`/dev/sda` for USB SSD,
`/dev/mmcblk0` for SD).

---

## 3. Put the port on the cluster VLAN

The cluster lives on `10.0.10.0/24` = the **"Home" VLAN** (id 2), not the
default `192.168.1.0/24`. In UniFi set the Pi's switch port:
**Port Settings → Core Settings → Native VLAN / Network → Home (2)**.

> GOTCHA: changing a port's native VLAN does **not** bounce the link. The Pi
> keeps its old `192.168.1.x` DHCP lease, which no longer routes — it goes dark
> on both subnets. **Unplug + replug the ethernet cable** (or power-cycle the
> Pi) to force a re-DHCP onto the Home VLAN. A PoE power-cycle does nothing if
> the Pi is USB-C powered (check `poe.state` — `DOWN` = not PoE-powered).

---

## 4. Find the Pi + detect its hardware

Find the maintenance IP (UniFi integration API, keyed on MAC):

```bash
KEY=$(grep -E '^unifi_api_key' ../terraform.tfvars | sed -E 's/.*"([^"]+)".*/\1/')
SITE=$(curl -sk -H "X-API-KEY: $KEY" https://10.0.10.1/proxy/network/integrations/v1/sites | jq -r '.data[0].id')
curl -sk -H "X-API-KEY: $KEY" "https://10.0.10.1/proxy/network/integrations/v1/sites/$SITE/clients?limit=200" \
  | jq -r '.data[]? | select((.macAddress//""|ascii_downcase)=="e4:5f:01:f4:c9:e3") | "\(.name) \(.ipAddress)"'
```

Or just scan for the Talos API port:

```bash
for i in $(seq 1 254); do (nc -z -G1 -w1 10.0.10.$i 50000 2>/dev/null && echo 10.0.10.$i) & done; wait
# exclude known: .201 .202 .203 (+ .204 VIP) .205
```

Confirm it's Talos in maintenance mode (no certs, no SSH):

```bash
talosctl -n <pi-ip> version --insecure        # Tag: v1.13.4, OS/Arch: linux/arm64
```

Detect the install disk and NIC (you need these for the config — wrong disk
wipes the wrong device):

```bash
talosctl -n <pi-ip> get disks --insecure              # find the system disk
talosctl -n <pi-ip> get discoveredvolumes --insecure  # the one with EFI/BOOT/META = boot disk
talosctl -n <pi-ip> get links --insecure | grep -i ether   # NIC name (end0 on Pi 4)
```

`bb-worker-02`: single disk `sda` (240 GB USB SSD, transport `usb`), NIC `end0`.
Note `talosctl disks` (the command) does NOT accept `--insecure` — use
`talosctl get disks --insecure` (the resource API) in maintenance mode.

---

## 5. Join via Terraform (reuses cluster secrets)

The Pi reuses `talos_machine_secrets.this` + `data.talos_machine_configuration.worker`,
so it joins the existing cluster with no bootstrap. The resource lives in
`01-talos-cluster/main.tf` (section 12). Key points baked in:

- `node` = the Pi's **static** IP; `endpoint` = its **maintenance** IP for the
  first apply only (remove/equalise afterwards — see note in the resource).
- **No `depends_on` the bootstrap** — otherwise `-target` drags the whole
  CP/VM/ISO chain in. The cluster is already up; the worker just joins.
- Pi-specific patches: `install.disk = /dev/sda` (**no wipe** — the SBC image is
  already on disk), `image` = the arm64 SBC installer (for future upgrades),
  interface `end0`, static IP, hostname. **No `kernel.modules`** (no zfs/drbd
  in the Pi schematic). The `bird2` ExtensionServiceConfig IS included (the
  schematic ships bird2; without its config the boot hangs ~1h10m).

Apply only the Pi (narrow blast radius — no ISO/VM/CP churn):

```bash
cd 01-talos-cluster
terraform plan  -target=talos_machine_configuration_apply.pi_worker -var-file=../terraform.tfvars
# expect: 1 to add (pi_worker) + 1 to change (talos_machine_secrets in-place) , 0 destroy
terraform apply -target=talos_machine_configuration_apply.pi_worker -var-file=../terraform.tfvars
```

The talos provider applies over the maintenance API (no certs needed for the
first push). The Pi then reboots onto the static IP and joins.

> Why `-target`: a full `terraform apply` would also reconcile the OS-upgrade
> drift (re-download ISOs, re-assert CP machineconfigs). That's safe but broader
> than a worker join — keep it scoped with `-target` here.

### Manual alternative (no Terraform)

If joining outside TF, extract the cluster secrets from state and generate a
worker config, then `talosctl apply-config --insecure -n <pi-ip> --file worker.yaml`
with the same Pi patches. The TF route is preferred — it handles the secrets and
codifies the node.

---

## 6. Verify

The node goes `NotReady` until the arm64 Cilium agent pulls + starts on it
(~5 min), then `Ready`.

```bash
export TALOSCONFIG=./talosconfig KUBECONFIG=./kubeconfig
kubectl get node bb-worker-02 -o custom-columns=\
'NAME:.metadata.name,ARCH:.status.nodeInfo.architecture,OS:.status.nodeInfo.osImage,KERNEL:.status.nodeInfo.kernelVersion'
talosctl -n 10.0.10.206 services | grep -E 'ext-bird2|ext-rpc|kubelet'   # all Running, no zfs hang
kubectl -n kube-system get pods -o wide | grep bb-worker-02              # cilium + cilium-envoy Running
```

Expect: `arm64`, `Talos (v1.13.4)`, kernel `6.18.34-talos`, Ready.

---

## 7. After the join

- **arm64 scheduling**: only multi-arch / arm64 images will run on the Pi.
  amd64-only workloads will crashloop with `exec format error` if they land
  there. Pin them off the Pi with a nodeSelector:
  ```yaml
  nodeSelector:
    kubernetes.io/arch: amd64
  ```
  (or target the Pi explicitly with `kubernetes.io/arch: arm64`).
- **DHCP reservation** (optional, matches the other nodes): in UniFi reserve
  MAC `e4:5f:01:f4:c9:e3` → `10.0.10.206`. The Talos static IP already pins the
  running node; the reservation only matters for a re-flash/maintenance boot so
  the maintenance IP equals the static IP (then `endpoint` == `node`).
- **Commit** the TF changes (`main.tf` `pi_worker` resource) — left uncommitted
  for review.

---

## Quick reference — Pi gotchas

| symptom | cause | fix |
|---------|-------|-----|
| Pi won't boot after flashing | used a generic `metal-arm64` schematic, no overlay | regenerate with `overlay: rpi_generic` (§1) |
| Pi disappears after VLAN change | native-VLAN change doesn't bounce the link; stale lease | replug ethernet / power-cycle the Pi (§3) |
| `talosctl disks --insecure` errors | wrong command in maintenance mode | use `talosctl get disks --insecure` (§4) |
| node stuck `booting`, ext-zfs-service waiting | zfs/drbd ext without `kernel.modules` | don't add zfs/drbd to the Pi; or patch modules |
| `-target` apply wants to replace ISOs / touch CPs | `depends_on` bootstrap drags the chain | drop `depends_on`; the cluster is already up (§5) |
| pod `exec format error` on the Pi | amd64-only image on arm64 | nodeSelector `kubernetes.io/arch` (§7) |
