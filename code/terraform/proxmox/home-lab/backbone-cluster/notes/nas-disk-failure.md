# NAS Disk Failure — ZL2PZ3B7 (2026-06-25) — RESOLVED 2026-06-28

Incident + standing context for the NAS ZFS pool that backs the cluster's NFS storage.
Read this first if NFS-backed apps start crashlooping or `zpool status` shows DEGRADED.

## TL;DR

- A mirror disk (`ZL2PZ3B7`) in the NAS ZFS pool **died** (172k+ bad sectors). Its
  failure made all **sync writes hang** → NFS stalled → every NFS-backed app crashlooped
  and a postgres `postmaster.pid` got corrupted.
- **Recovered immediately** by offlining the dead disk → pool ran DEGRADED on the one
  healthy disk; cluster restored.
- **RESOLVED 2026-06-28**: replaced the dead disk with a new 16 TB (`ZYDHG0C2`), resilvered
  8.21 TB with **0 errors** in ~20 h. Pool is **ONLINE** — full 2-disk mirror, redundancy
  restored. Old `ZL2PZ3B7` detached from the pool (safe to physically pull, port 3).
- **Data was never lost** (it was a mirror; the good disk had a complete copy throughout).
- The dead disk's copy is gone (stale + we zeroed its ZFS label during a write test) — do
  NOT try to import it.
- Root cause was an **individual drive defect** (failing head/media), NOT power/heat/cabling
  — the twin disk on the same power/temp/batch is pristine. The bad disk was out of warranty
  (likely bought used / old-stock).

## Hardware / topology

- **NAS host**: `192.168.1.179` — a **Proxmox** box (hostname `proxmox`), SEPARATE from the
  cluster's main Proxmox (`10.0.10.10`). Access: `ssh root@192.168.1.179` (from the Mac /
  LAN; the builder VM `10.0.10.199` cannot route to `192.168.1.0/24`).
- This host also runs **VM 300 = `bb-worker-01`** (a cluster worker node) and other VMs;
  several VM zvols live on the SAME pool (`zpool1/vm-901-*` macOS, etc.).
- **Pool**: `zpool1` — single `mirror-0` vdev, 2× 16 TB Seagate IronWolf Pro (post-fix:
  one `ST16000NE000` survivor + one new `ST16000NT001`).
- **Controller**: ASMedia **ASM1164** PCIe SATA AHCI (PCI `04:00.0`). Both 16 TB disks
  share this one card.
- **NFS export**: `/zpool1/nfs_share` → `10.0.10.0/24` and `192.168.1.0/24` (rw,sync). This
  is the cluster's `nfs-subdir-external-provisioner` backend (PVC `*-nas`, NFS server
  `192.168.1.179`). ~8.2 TB used; biggest dir `backup/` ≈ 440 GB.

### The disks (after fix)

| Role | Serial | Model | /dev | Port | State | SMART |
|------|--------|-------|------|------|-------|-------|
| **Survivor** | `ZL2PZ3VV` | ST16000NE000 | sda | ASM1164 **port 1** (`ata-1`) | ONLINE | clean (0 realloc / 0 pending) |
| **New** | `ZYDHG0C2` | ST16000NT001 | sdd | ASM1164 **port 2** (`ata-2`) | ONLINE | pristine (new, 0/0/0) |
| **Dead (detached)** | `ZL2PZ3B7` | ST16000NE000 | sdb | ASM1164 **port 3** (`ata-3`) | removed from pool | 27,760 realloc · **172,040 pending** · 215 UNC — pull & discard/RMA-via-seller |

Identify physically by the Seagate serial sticker. The dead one ends `…B7` (port 3) — safe
to pull now. Leave `…VV` (port 1) and `…0C2` (port 2) in place.
NOTE: the new disk only showed up after a controller rescan
(`for h in /sys/class/scsi_host/host*; do echo "- - -" > $h/scan; done`) — hot-plug event
was missed on insert.

## Root cause (the full chain)

```
Disk ZL2PZ3B7 failing (172k pending sectors)
  → ZFS mirror waits on BOTH members for every sync write; the dying one hangs on
    cache-flush/FUA (seconds-long command timeouts)
  → zil_commit / txg_sync wedge in D-state → all sync writes block
  → NFS server (nfsd) threads all stuck in D → NFS writes hang cluster-wide
  → every NFS-backed pod stalls on startup/health → CrashLoopBackOff
  → also wrote an empty/corrupt postgres postmaster.pid (the "lock file is empty" bug)
```

Diagnostic tells: async writes instant (4.5 GB/s to ARC) but `dd oflag=sync` hung; disks
idle (inflight 0), 0% iowait, SMART "PASSED" (Seagate's lying overall flag) — the raw
attributes + per-disk `zpool iostat -v -l` latency (ZL2PZ3B7 write wait 18 s) pinpointed it.

## What was done (2026-06-25 → 06-28)

1. Diagnosed cluster via SSH tunnel through builder VM (`10.0.10.199`) because the Mac's
   wifi flaps EHOSTUNREACH to `10.0.10.0/24` (the original "kubectl no route to host").
2. Cleared the corrupt empty `postmaster.pid` → reactive-resume postgres recovered.
3. **Committed code fix** `0a4add8`: `pgdata-prep` init container in
   `02-helm-stack/manifests/{reactive-resume,immich}.yaml` now self-heals an empty
   `postmaster.pid` on start (safe: replicas:1 + Recreate). Pushed to `main`.
4. Traced the real cause to the NAS; rebooted the NAS host (didn't fix → proved hardware).
5. Identified `ZL2PZ3B7` via per-disk latency + SMART + dmesg ata3 IDENTIFY timeouts.
6. `zpool offline zpool1 ata-ST16000NE000-2RW103_ZL2PZ3B7` → sync writes recovered
   (20–45 MB/s), NFS unblocked, kicked stuck pods (trilium, paperless) → all 60 pods Running.
7. Physically pulled/reseated the dead disk (reseat fixed only the cabling/link, not media);
   write-stress test confirmed healthy regions write fine and DON'T disrupt the good disk on
   the shared controller, but the 172k bad sectors are untouched/terminal. The write test
   zeroed the dead disk's front (ZFS label) — it's no longer an importable copy.
8. **(06-27/28) Replaced the disk.** Fitted a new 16 TB `ST16000NT001` (`ZYDHG0C2`) in the
   free port 2, verified pristine SMART, then:
   `zpool replace zpool1 ata-ST16000NE000-2RW103_ZL2PZ3B7 ata-ST16000NT001-3MC101_ZYDHG0C2`.
   Resilvered **8.21 TB in 19:59:21 with 0 errors** (survived being left running ~20 h).
   Pool back to **ONLINE**, full mirror, redundancy restored. Old disk auto-detached.

## Current state — RESOLVED ✅

- `zpool1`: **ONLINE**, healthy `mirror-0` = `ZL2PZ3VV` (survivor) + `ZYDHG0C2` (new). 0 errors.
  8.21 T used / 6.34 T free. Full redundancy.
- Cluster + all apps healthy.
- Old `ZL2PZ3B7` is detached from the pool but may still be **physically in port 3** — pull
  and discard (or try seller RMA). It was **NOT under Seagate warranty** (counted from
  manufacture/purchase date, not the 13,287 power-on hours; likely bought used/old-stock).

## TODO / plan

### Done ✅
- [x] Buy replacement 16 TB (got IronWolf Pro `ST16000NT001`, NEW, 5 yr warranty).
- [x] `zpool replace` + resilver → redundancy restored (2026-06-28, 0 errors).

### Open
- [ ] **Physically pull the dead `ZL2PZ3B7`** (port 3) — already detached from pool. Discard
      or try seller RMA. Leave `…VV` (port 1) and `…0C2` (port 2) alone.
- [ ] **UPS auto-shutdown.** EcoFlow DELTA 3 Classic ordered (1024 Wh, ~8 h ride-through,
      ~10 ms switchover). It has NO native USB-HID UPS signaling — wire EcoFlow IoT API /
      Home Assistant → detect on-battery/low-SoC → script `qm shutdown` VMs + `poweroff`
      the host. (Outages are NOT what killed the disk, but they corrupt DBs/FS on every
      unclean shutdown.) Plug NAS into the UPS/EPS output + enable UPS mode when it lands.
- [ ] Optional `zpool scrub zpool1` for a final end-to-end verify (resilver already 0 errors).
- [ ] SMART monitoring/alerting on both pool disks for early warning next time.
- [ ] Optional: don't buy both mirror disks from the same batch in future (avoid twin
      infant-mortality); source NAS drives NEW with valid warranty.

### Replacement runbook (on `192.168.1.179`) — kept for next time
```bash
# after inserting the new disk, if it doesn't appear, force a controller rescan:
for h in /sys/class/scsi_host/host*; do echo "- - -" > $h/scan; done

# find the new disk's by-id name + verify pristine SMART/size first
ls -l /dev/disk/by-id/ | grep -i ata
smartctl -A /dev/sdX | grep -E 'Reallocated|Pending|Power_On_Hours'

# replace the dead member with the new disk (this starts the resilver)
zpool replace zpool1 <DEAD_BY_ID> /dev/disk/by-id/<NEW_BY_ID>

# watch resilver (16 TB ≈ ~20 h here; pool stays ONLINE + serving the whole time)
zpool status zpool1
# done when: state ONLINE, "resilvered ... with 0 errors", replacing-1 vdev gone.
# survives power loss — resilver RESUMES after reboot, doesn't restart. then optional:
zpool scrub zpool1
```
If physically removing the dead disk first: it's the drive whose serial ends `B7`, port 3.
Lower-risk order = insert new in the free port, resilver, THEN pull the dead one.

### Unrelated loose ends from this session
- [ ] Restore terraform backend for `02-helm-stack`: the local `.terraform` cache is pointed
      at an SSH tunnel (`127.0.0.1:19000`) because the Mac's link flaps to `10.0.10.199:9000`.
      From a stable link: `cd 02-helm-stack && terraform init -reconfigure -backend-config=backend.tfvars`
- [ ] Kill leftover diagnostic SSH tunnels on the Mac: `pkill -f 'ubuntu@10.0.10.199'`

## Access cheatsheet
- NAS host: `ssh root@192.168.1.179`
- Cluster (when Mac wifi flaps): tunnel via builder —
  `ssh -i ~/.ssh/id_ed25519 -fN -L16443:10.0.10.201:6443 -L15000:10.0.10.201:50000 ubuntu@10.0.10.199`
  then point kubeconfig server at `https://127.0.0.1:16443` (`--insecure-skip-tls-verify`).
- Cluster control planes `10.0.10.201/202/203`, workers `.205` (bb-worker-01 = VM 300 on the
  NAS host), `.206` (bb-worker-02 = Pi). VIP `10.0.10.204`.
