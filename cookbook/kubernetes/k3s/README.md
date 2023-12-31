# [K3s](https://github.com/k3s-io/k3s)

Lightweight Kubernetes. Easy to install, half the memory, all in a binary less
than 100 MB.

## Install k3s

### Install k3s on master node

```bash

curl -sfL https://get.k3s.io | INSTALL_K3S_CHANNEL=v1.27.4+k3s1 INSTALL_K3S_EXEC="--disable servicelb --disable traefik --write-kubeconfig-mode 644 --kube-apiserver-arg default-not-ready-toleration-seconds=10 --kube-apiserver-arg default-unreachable-toleration-seconds=10" sh -s -
```

### Install k3s on worker node

```bash
curl -sfL https://get.k3s.io | INSTALL_K3S_CHANNEL=v1.27.4+k3s1 K3S_URL=https://MASTER_IP:6443 K3S_TOKEN=K3S_TOKEN INSTALL_K3S_CHANNEL=v1.27.4+k3s1 sh -s -
```

`cp /etc/rancher/k3s/k3s.yaml ~/.kube/config`

## Uninstalling

### To uninstall K3s from a server node, run

```bash
/usr/local/bin/k3s-uninstall.sh
```

### To uninstall K3s from an agent node, run

```bash
/usr/local/bin/k3s-agent-uninstall.sh
```

## reference

<https://github.com/k3s-io/k3s/issues/1264>

---

Here are the steps to troubleshoot and resolve the issue:

1. Duplicate Hostname: Ensure that each node in your cluster has a unique
   hostname. Duplicate hostnames can cause issues when nodes try to join the
   cluster. You can check the hostname with the hostname command and set a new
   hostname with sudo hostnamectl set-hostname NEW_HOSTNAME.

2. Token Verification: Ensure that you're using the correct token from the
   master node when joining the worker node. Retrieve the token from the master
   node with:

```bash
cat /var/lib/rancher/k3s/server/node-token
```

Use this token when joining the worker node to the master.

3. Network Connectivity: Ensure that the worker node can reach the master node.
   Test the connectivity using:

```bash
ping MASTER_NODE_IP
```

Replace MASTER_NODE_IP with the IP address of your master node.

4. Firewall Rules: Ensure there are no firewall rules blocking the communication
   between the worker and master nodes. Specifically, the worker node needs to
   communicate with the master node on port 6443.

5. Rejoin the Worker Node: If you've made changes based on the above steps, try
   to rejoin the worker node to the master. Before doing so, it's a good idea to
   uninstall k3s from the worker node to start with a clean slate:

```bash
/usr/local/bin/k3s-agent-uninstall.sh
```

Then, attempt to join the worker node again using the correct token and master
node IP.

6. Check Master Node Logs: It might also be helpful to check the logs on the
   master node to see if there are any indications of issues from its
   perspective. Use:

```bash
journalctl -u k3s
```

on the master node to view its logs.
