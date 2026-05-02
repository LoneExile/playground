# Path to kubeconfig produced by stage 01.
variable "kubeconfig_path" {
  type    = string
  default = "../01-talos-cluster/kubeconfig"
}

# --- Chart versions ---
variable "cilium_version" {
  type    = string
  default = "1.19.3"
}

variable "metallb_version" {
  type    = string
  default = "0.15.2"
}

variable "gateway_api_version" {
  description = "Gateway API CRD release tag (kubectl apply from upstream)"
  type        = string
  default     = "v1.2.1"
}

variable "nfs_subdir_provisioner_version" {
  type    = string
  default = "4.0.18"
}

variable "metrics_server_version" {
  type    = string
  default = "3.13.0"
}

variable "cert_manager_version" {
  type    = string
  default = "v1.19.4"
}

variable "envoy_gateway_version" {
  description = "envoy-gateway-helm chart version (OCI registry tag)"
  type        = string
  default     = "1.5.0"
}

# --- Network ---
variable "metallb_ip_range" {
  description = "MetalLB L2 IP pool (must be in cluster subnet)"
  type        = string
  default     = "10.0.10.210-10.0.10.230"
}

variable "gateway_external_ip" {
  description = "Static IP the Cloudflare wildcard A record points to. Must fall inside metallb_ip_range."
  type        = string
  default     = "10.0.10.212"
}

# --- NFS ---
variable "nfs_server" {
  type    = string
  default = "192.168.1.179"
}

variable "nfs_path" {
  type    = string
  default = "/zpool1/nfs_share"
}

# --- Domain + TLS ---
variable "primary_domain" {
  description = "Root Cloudflare zone used for public TLS + DNS"
  type        = string
  default     = "0dl.me"
}

variable "subdomain" {
  description = "Subdomain under primary_domain for all apps (wildcard)"
  type        = string
  default     = "home"
}

variable "acme_email" {
  description = "Let's Encrypt ACME account email"
  type        = string
  default     = "admin@0dl.me"
}

variable "tls_issuer" {
  description = "Default ClusterIssuer for Gateway. letsencrypt-staging | letsencrypt-prod | ca-issuer"
  type        = string
  default     = "letsencrypt-prod"
}

variable "cloudflare_api_token" {
  description = "Cloudflare API token with Zone:DNS:Edit + Zone:Zone:Read on primary_domain. Used by cert-manager for DNS-01 and by Terraform to manage the A record."
  type        = string
  sensitive   = true
}

# --- UniFi ---
variable "unifi_api_url" {
  description = "UniFi Network controller base URL (UDM-SE)"
  type        = string
  default     = "https://10.0.10.1"
}

variable "unifi_api_key" {
  description = "UniFi API key with Network permissions"
  type        = string
  sensitive   = true
}

variable "unifi_site" {
  description = "UniFi site name (legacy API slug)"
  type        = string
  default     = "default"
}

variable "unifi_home_network_name" {
  description = "UniFi network name for VLAN 2 (Home)"
  type        = string
  default     = "Home"
}

# --- Paperless ---
# Used by manifests/paperless.yaml (rendered via templatefile in apps.tf).
# Postgres data dir is restored from NFS; the existing 'paperless' role's
# password is unknown, so the postgres container's postStart hook re-asserts
# this value via ALTER USER on every pod start using local-socket trust auth.
variable "paperless_db_password" {
  description = "Password for the 'paperless' Postgres role. Re-asserted on every postgres pod start via ALTER USER. Rotate by editing terraform.tfvars and rolling the postgres deployment."
  type        = string
  sensitive   = true
}

# Django secret key (PAPERLESS_SECRET_KEY). Used for session cookies and CSRF
# tokens. Treat as opaque; rotating invalidates all active sessions but does
# not affect stored documents or metadata.
variable "paperless_secret_key" {
  description = "PAPERLESS_SECRET_KEY (Django session/CSRF crypto). Generate with: openssl rand -base64 64"
  type        = string
  sensitive   = true
}

# --- Immich ---
# Used by manifests/immich.yaml (rendered via templatefile in apps.tf).
# Postgres data dir is fresh; the 'immich' role is created on initdb from this
# password. The Job/immich-restore then loads the latest pg_dump backup.
variable "immich_db_password" {
  description = "Password for the 'immich' Postgres role. Used by initdb on first boot and by immich-server. Rotate by editing terraform.tfvars and re-applying (immich-server reads it from the Secret on each pod start)."
  type        = string
  sensitive   = true
}

# --- Inherit harmless 01-stage vars so shared terraform.tfvars doesn't error ---
# Not used in this stage; declared only so Terraform doesn't complain about
# "undeclared variable" when loading ../terraform.tfvars.
variable "proxmox_api_token_id" {
  type    = string
  default = ""
}
variable "proxmox_api_token_secret" {
  type      = string
  default   = ""
  sensitive = true
}
variable "proxmox_password" {
  type      = string
  default   = ""
  sensitive = true
}
variable "proxmox_api_token_secret_nas" {
  type      = string
  default   = ""
  sensitive = true
}
variable "proxmox_password_nas" {
  type      = string
  default   = ""
  sensitive = true
}
variable "vm_password" {
  type      = string
  default   = ""
  sensitive = true
}
variable "vm_password_hash" {
  type    = string
  default = ""
}
variable "ssh_public_key" {
  type    = string
  default = ""
}
variable "rustfs_root_user" {
  type    = string
  default = ""
}
variable "rustfs_root_password" {
  type      = string
  default   = ""
  sensitive = true
}
