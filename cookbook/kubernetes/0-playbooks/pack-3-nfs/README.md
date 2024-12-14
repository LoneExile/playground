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

## undo NFS w/o omv
To undo the changes made by these commands, you can follow these steps in reverse order:

1. Remove NFS configuration:
```
sudo nano /etc/exports
# Remove the line you added for /mnt/nvme0n1
sudo exportfs -ra
sudo systemctl stop nfs-kernel-server
sudo apt remove nfs-kernel-server
```

2. Remove the automatic mounting entry:
```
sudo nano /etc/fstab
# Remove the line you added for /dev/nvme0n1p1
```

3. Unmount the partition:
```
sudo umount /mnt/nvme0n1
sudo rmdir /mnt/nvme0n1
```

4. If you want to remove the formatting and partition:
   (Be very careful with this step, as it will erase all data on the partition)
```
sudo fdisk /dev/nvme0n1
# Use the 'd' command to delete the partition
# Use the 'w' command to write changes and exit
```

5. If you want to completely remove the formatting:
   (This will erase all data on the device, be absolutely sure before proceeding)
```
sudo dd if=/dev/zero of=/dev/nvme0n1 bs=4M status=progress
```
