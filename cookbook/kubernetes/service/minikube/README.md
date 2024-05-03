# MiniKube

```bash

# Driver is one of: virtualbox, kvm2, qemu2, qemu, vmware, none, docker, podman, ssh (defaults to auto-detect)
minikube start

minikube start -p dev --embed-certs --driver=docker --memory 8192 --cpus 4

minikube tunnel -p dev --bind-address='localhost'

```
---

https://devopscube.com/kubernetes-minikube-tutorial/
