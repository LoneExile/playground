## create NFS w/o omv

```bash
# Step 1: Partition the Disk
sudo fdisk /dev/nvme0n1

# Step 2: Format the Partition
sudo mkfs.ext4 /dev/nvme0n1p1

# Mount the Partition
sudo mkdir /mnt/nvme0n1
sudo mount /dev/nvme0n1p1 /mnt/nvme0n1

# Step 4: Automate the Mounting
sudo nano /etc/fstab
/dev/nvme0n1p1 /mnt/nvme0n1 ext4 defaults 0 0


# Step 5: Configure NFS to Share the Mounted Directory
sudo apt update
sudo apt install nfs-kernel-server

sudo nano /etc/exports
# /mnt/nvme0n1 <client_IP>(rw,sync,no_subtree_check)

sudo exportfs -a
sudo systemctl restart nfs-kernel-server
```
