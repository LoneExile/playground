# rook-ceph

### install rook-ceph

```bash
git clone --single-branch --branch v1.12.4 https://github.com/rook/rook.git
cd rook/deploy/examples
kubectl create -f crds.yaml -f common.yaml -f operator.yaml
```

```bash
kubectl create -f cluster.yaml
```

```bash
kubectl create -f toolbox.yaml

# kubectl -n rook-ceph exec -it deploy/rook-ceph-tools -- bash
```

```bash
kubectl create -f filesystem.yaml
```
```bash
# not need?
kubectl create -f deploy/examples/csi/cephfs/kube-registry.yaml
```

```bash
kubectl create -f storageclass.yaml
# kubectl create -f filesystem.yaml
# kubectl create -f object.yaml
# kubectl create -f pool.yaml
```

### Dashboard

```bash
# id: admin
kubectl -n rook-ceph get secret rook-ceph-dashboard-password -o jsonpath="{['data']['password']}" | base64 --decode && echo

## Access via localhostL:8443
# kubectl -n rook-ceph port-forward svc/rook-ceph-mgr-dashboard 8443:8443

## Access via 192.x.x.x:8443
# kubectl -n rook-ceph port-forward svc/rook-ceph-mgr-dashboard --address 0.0.0.0 8443:8443
```

### uninstall rook-ceph

```bash
kubectl delete -f cluster.yaml -n rook-ceph
```

```bash
kubectl delete -f toolbox.yaml -f operator.yaml -n rook-ceph
```

```bash
kubectl delete -f common.yaml -f crds.yaml -n rook-ceph
```

```bash
sudo rm -rf /var/lib/rook
```

## format and mount cephfs

after burn image to sd card, trim the partition via fdisk or gparted.
this partition will be used for cephfs.

```bash
sudo fdisk /dev/sda

sudo mkfs.ext4 /dev/mmcblk0p3
# sudo mkfs.ext4 /dev/sda1

## remove filesystem
sudo dd if=/dev/zero of=/dev/mmcblk0p3 bs=1M count=100

## check filesystem
lsblk -f

# -------
# set name in cluster.yaml
# kubectl get node orangepi5 --show-labels
# NAME        STATUS   ROLES                  AGE   VERSION        LABELS
# orangepi5   Ready    control-plane,master   25h   v1.27.4+k3s1   beta.kubernetes.io/arch=arm64,beta.kubernetes.io/instance-type=k3s,beta.kubernetes.io/os=linux,kubernetes.io/arch=arm64,kubernetes.io/hostname=orangepi5,kubernetes.io/os=linux,node-role.kubernetes.io/control-plane=true,node-role.kubernetes.io/master=true,node.kubernetes.io/instance-type=k3s
# -------


## mount cephfs
# sudo mkdir -p /mnt/cephfs
# sudo mount -t ext4 /dev/sda1 /mnt/cephfs
# sudo chmod 777 /mnt/cephfs
# sudo chown -R 1000:1000 /mnt/cephfs

## umount cephfs
# sudo umount /mnt/cephfs
# sudo rm -rf /mnt/cephfs
# sudo rm -rf /var/lib/rook

```

### Adding an OSD

```bash
ceph orch daemon add osd node1:/dev/sda1

## set OSD device class for osd.0 to SSD
# ceph osd crush set-device-class ssd osd.0

## if already set, remove the device class before
# ceph osd crush rm-device-class osd.0
```

### Removing an OSD

```bash
kubectl -n rook-ceph scale deployment rook-ceph-operator --replicas=0
kubectl -n rook-ceph scale deployment rook-ceph-osd-0 --replicas=0
kubectl drain <NODE_NAME> --ignore-daemonsets
kubectl uncordon <NODE_NAME>
```

```bash
ceph osd out osd.<OSD_ID>
```

```bash
ceph osd purge osd.<OSD_ID> --yes-i-really-mean-it
```

```bash
ceph auth list
ceph osd rm osd.<YOUR-OSD-ID>
ceph auth del osd.<YOUR-OSD-ID>
```

```bash
kubectl -n rook-ceph scale deployment rook-ceph-operator --replicas=1
kubectl -n rook-ceph scale deployment rook-ceph-osd-0 --replicas=1

# kubectl -n rook-ceph delete deployment rook-ceph-osd-<OSD_ID>
```

### Reuse existing drives

```bash
## If you're adding a disk that has been used (at least partitioned) before, ceph will require that you clear (zap in ceph jargon) the device before.
ceph orch device zap <HOST> <DEVICE> --force

# ceph balancer status
# ceph balancer mode upmap
# ceph balancer on
```

### troubleshoot

```bash
ceph crash ls
ceph crash info [<CRASH_ID>]

ceph crash archive [<CRASH_ID>]
ceph crash archive-all
```

```bash
ceph mgr module ls
ceph mgr module enable rook
ceph orch set backend rook
ceph orch status
```
