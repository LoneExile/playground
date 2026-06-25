# NAS Disk Failure — ZL2PZ3B7 (2026-06-25)

Incident + standing context for the NAS ZFS pool that backs the cluster's NFS storage.
Read this first if NFS-backed apps start crashlooping or `zpool status` shows DEGRADED.

## TL;DR

- A mirror disk (`ZL2PZ3B7`) in the NAS ZFS pool **died** (172k+ bad sectors). Its
  failure made all **sync writes hang** → NFS stalled → every NFS-backed app crashlooped
  and a postgres `postmaster.pid` got corrupted.
- **Fixed by offlining the dead disk.** Pool now runs **DEGRADED on the one healthy
  disk** (`ZL2PZ3VV`). Cluster is fully healthy.
- **Data is safe** (it was a mirror; the good disk has a complete copy).
- **No redundancy until a replacement disk is added.** Dead disk is **out of warranty**.
- The dead disk's copy is gone (stale + we zeroed its ZFS label during a write test) — do
  NOT try to import it.

## Hardware / topology

- **NAS host**: `192.168.1.179` — a **Proxmox** box (hostname `proxmox`), SEPARATE from the
  cluster's main Proxmox (`10.0.10.10`). Access: `ssh root@192.168.1.179` (from the Mac /
  LAN; the builder VM `10.0.10.199` cannot route to `192.168.1.0/24`).
- This host also runs **VM 300 = `bb-worker-01`** (a cluster worker node) and other VMs;
  several VM zvols live on the SAME pool (`zpool1/vm-901-*` macOS, etc.).
- **Pool**: `zpool1` — single `mirror-0` vdev, 2× 16 TB Seagate IronWolf Pro `ST16000NE000`.
- **Controller**: ASMedia **ASM1164** PCIe SATA AHCI (PCI `04:00.0`). Both 16 TB disks
  share this one card.
- **NFS export**: `/zpool1/nfs_share` → `10.0.10.0/24` and `192.168.1.0/24` (rw,sync). This
  is the cluster's `nfs-subdir-external-provisioner` backend (PVC `*-nas`, NFS server
  `192.168.1.179`). ~8.2 TB used; biggest dir `backup/` ≈ 440 GB.

### The two disks

| Role | Serial | /dev | Port | State | SMART |
|------|--------|------|------|-------|-------|
| **Good** | `ZL2PZ3VV` | sda | ASM1164 **port 1** (`ata-1`) | ONLINE | clean (0 realloc / 0 pending) |
| **Dead** | `ZL2PZ3B7` | sdb | ASM1164 **port 3** (`ata-3`) | OFFLINE/REMOVED | 27,760 realloc · **172,040 pending** · 215 UNC · 42.9B cmd-timeouts |

Port 2 (`ata-2`) is empty. Identify physically by the Seagate serial sticker: keep `…VV`,
the dead one ends `…B7`.

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

## What was done (2026-06-25)

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

## Current state

- `zpool1`: **DEGRADED**, `ZL2PZ3VV` ONLINE, `ZL2PZ3B7` REMOVED. **Single copy, no redundancy.**
- Good disk SMART clean → stable day-to-day. Cluster + all apps healthy.
- Warranty: serial `ZL2PZ3B7` checked on Seagate → **NOT under warranty** (counted from
  manufacture/purchase date, not the 13,287 power-on hours). "Rescue Data Recovery" plan is
  valid but that's a recovery *service*, not a replacement, and not needed (data is safe).

## TODO / plan

### Now (free, while running degraded — no redundancy)
- [ ] **Back up the irreplaceable data** off the single disk. Don't copy all 8.2 TB — just:
      postgres DBs (immich / paperless / reactive-resume via `pg_dump`), immich photos,
      paperless docs, trilium notes. Skip torrents / media / caches.
      Targets: the 2.7 TB WD already in the NAS (`sdc`, exFAT) or a cloud free tier or the Mac.
- [ ] Confirm SMART monitoring/alerting on the **good** disk (`ZL2PZ3VV`) for early warning.
- [ ] Optional: check with the **seller** — if bought recently they may still cover the RMA
      even though Seagate's factory warranty has lapsed.

### When funds allow
- [ ] Buy a replacement **≥ 16 TB CMR/NAS** drive (doesn't have to be Seagate; e.g. the
      newer IronWolf Pro `ST16000NT001` is fine — different model, same family/size).
- [ ] Fit it (ASM1164 port 2 is free, or replace ZL2PZ3B7 in port 3).
- [ ] Resilver (runbook below) → redundancy restored.

### Replacement runbook (on `192.168.1.179`)
```bash
# find the new disk's by-id name
ls -l /dev/disk/by-id/ | grep -i ata

# replace the dead member with the new disk
zpool replace zpool1 ata-ST16000NE000-2RW103_ZL2PZ3B7 /dev/disk/by-id/<NEW_DISK>

# watch resilver (16 TB ≈ several hours)
zpool status zpool1
# when "resilvered ... with 0 errors" and state ONLINE → done; then optional scrub:
zpool scrub zpool1
```
If physically removing ZL2PZ3B7 first, it's the drive whose serial ends `B7`, ASM1164 port 3.

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
