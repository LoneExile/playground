# Talos Kubernetes Cluster on Proxmox

Terraform/Terragrunt infrastructure for deploying a production-ready Talos Linux Kubernetes cluster on Proxmox VE.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                      Proxmox VE Host                        │
├─────────────────────────────────────────────────────────────┤
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐         │
│  │ Control-01  │  │ Control-02  │  │ Control-03  │         │
│  │  (Talos)    │  │  (Talos)    │  │  (Talos)    │         │
│  │  4 CPU      │  │  4 CPU      │  │  4 CPU      │         │
│  │  20GB RAM   │  │  20GB RAM   │  │  20GB RAM   │         │
│  └──────┬──────┘  └──────┬──────┘  └──────┬──────┘         │
│         │                │                │                 │
│         └────────────────┼────────────────┘                 │
│                          │                                  │
│                    VIP: 10.0.10.100                         │
│                   (Kubernetes API)                          │
└─────────────────────────────────────────────────────────────┘
```

## Features

- **High Availability**: 3 control plane nodes with VIP failover
- **Talos Linux**: Immutable, secure, minimal OS purpose-built for Kubernetes
- **Modular Design**: Reusable Terraform modules managed by Terragrunt
- **DRY Configuration**: Environment-specific settings separated from infrastructure code
- **CNI Ready**: Configured for external CNI (Cilium, Calico, etc.)
- **Storage Ready**: Additional storage disk for persistent volumes

## Prerequisites

- [Terraform](https://www.terraform.io/downloads) >= 1.1.0
- [Terragrunt](https://terragrunt.gruntwork.io/docs/getting-started/install/) >= 0.50.0
- [Proxmox VE](https://www.proxmox.com/) >= 7.0
- Talos ISO uploaded to Proxmox storage

## Project Structure

```
.
├── live/                              # Environment configurations
│   ├── root.hcl                       # Common Terragrunt config
│   └── production/
│       ├── env.hcl                    # Environment variables
│       ├── control-plane-vms/         # Control plane VM deployment
│       ├── worker-vms/                # Worker node deployment
│       ├── talos-cluster/             # Talos configuration & bootstrap
│       └── output-files/              # Kubeconfig & secrets export
│
└── modules/                           # Reusable Terraform modules
    ├── proxmox-talos-vm/              # Proxmox VM creation
    ├── talos-cluster/                 # Talos machine configuration
    ├── wait-for-talos-api/            # API readiness check
    └── output-files/                  # File output utilities
```

## Quick Start

### 1. Configure Environment

Edit `live/production/env.hcl` with your settings:

```hcl
locals {
  # Proxmox Configuration
  pm_host         = "https://your-proxmox:8006/api2/json"
  pm_api_token_id = "terraform-prov@pve!mytoken"

  # Network
  vip_ip       = "10.0.10.100"
  ipv4_cidr    = "10.0.10.0/24"

  # Talos
  talos_version      = "v1.11.5"
  kubernetes_version = "v1.33.3"
  cdrom_iso          = "local:iso/talos-amd64.iso"
}
```

### 2. Set API Token Secret

```bash
export PM_API_TOKEN_SECRET="your-proxmox-api-token-secret"
```

### 3. Deploy Infrastructure

```bash
cd live/production

# Preview changes
terragrunt run --all plan

# Apply all modules in dependency order
terragrunt run --all apply
```

### 4. Access Cluster

After deployment, kubeconfig is saved to `live/production/output-files/kubeconfig`:

```bash
export KUBECONFIG=$(pwd)/output-files/kubeconfig
kubectl get nodes
```

## Module Details

### proxmox-talos-vm

Creates Proxmox VMs with:
- Configurable CPU, RAM, storage
- Talos ISO attached as CD-ROM
- Virtio network and disk drivers
- QEMU guest agent enabled

### talos-cluster

Handles Talos configuration:
- Generates cluster secrets
- Applies machine configuration to nodes
- Configures VIP for API server HA
- Bootstraps the cluster
- Retrieves kubeconfig

### output-files

Exports sensitive files:
- `kubeconfig` - Kubernetes admin configuration
- `secrets.yaml` - Talos machine secrets (for recovery)

## Configuration Reference

### Control Plane Resources

| Variable | Default | Description |
|----------|---------|-------------|
| `control_plane_cpu_core` | 4 | CPU cores per node |
| `control_plane_ram` | 20480 | RAM in MB |
| `control_plane_os_disk_size` | 40G | OS disk size |
| `control_plane_storage_disk_size` | 500G | Data disk size |

### Worker Resources

| Variable | Default | Description |
|----------|---------|-------------|
| `worker_cpu_core` | 4 | CPU cores per node |
| `worker_ram` | 20480 | RAM in MB |
| `worker_os_disk_size` | 40G | OS disk size |
| `worker_storage_disk_size` | 500G | Data disk size |

### Cluster Settings

| Variable | Default | Description |
|----------|---------|-------------|
| `dns_domain` | maxcloud.local | Cluster DNS domain |
| `pod_subnets` | 10.244.0.0/16 | Pod network CIDR |
| `service_subnets` | 10.96.0.0/16 | Service network CIDR |

## Adding Worker Nodes

Uncomment worker nodes in `live/production/env.hcl`:

```hcl
worker_nodes = {
  "talos-worker-01" = {
    target_node = "pve"
    arc         = "amd64"
  }
  "talos-worker-02" = {
    target_node = "pve"
    arc         = "amd64"
  }
}
```

Then apply:

```bash
cd live/production
terragrunt run --all apply
```

## Adding New Environments

1. Copy the production directory:
   ```bash
   cp -r live/production live/staging
   ```

2. Modify `live/staging/env.hcl` with new values

3. Deploy:
   ```bash
   cd live/staging
   terragrunt run --all apply
   ```

## Post-Deployment

### Install CNI (Cilium)

```bash
helm repo add cilium https://helm.cilium.io/
helm install cilium cilium/cilium \
  --namespace kube-system \
  --set ipam.mode=kubernetes \
  --set kubeProxyReplacement=true \
  --set k8sServiceHost=10.0.10.100 \
  --set k8sServicePort=6443
```

### Verify Cluster

```bash
# Check nodes
kubectl get nodes -o wide

# Check system pods
kubectl get pods -n kube-system
```

## Troubleshooting

### Talos API Not Responding

```bash
# Check VM console in Proxmox for boot errors
# Verify network connectivity to VMs
talosctl -n <node-ip> health
```

### Bootstrap Fails

```bash
# Check Talos logs
talosctl -n <node-ip> logs controller-runtime

# Reset and retry
talosctl -n <node-ip> reset --graceful=false
```

### State Recovery

If you need to recover state:
```bash
cd live/production/control-plane-vms
terragrunt import proxmox_vm_qemu.this[\"talos-control-px-01\"] pve/qemu/<vmid>
```

## Security Notes

- API token secrets are passed via environment variables
- Sensitive outputs (kubeconfig, secrets) are marked sensitive in Terraform
- State files contain sensitive data - secure accordingly
- Consider using remote state backend for production

## License

MIT
