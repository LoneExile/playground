# nfs-subdir-external-provisioner

## prerequisite

```bash
sudo apt install nfs-common -y
```

- NFS option on OpenMediaVault ([ref](https://manpages.debian.org/bookworm/nfs-kernel-server/exports.5.en.html))
```
insecure, no_root_squash, rw, subtree_check
```
