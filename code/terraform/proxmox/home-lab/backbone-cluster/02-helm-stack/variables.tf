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

variable "kube_prometheus_stack_version" {
  description = "kube-prometheus-stack chart version (packaged kube-prometheus: operator + Prometheus + Grafana)"
  type        = string
  default     = "87.5.0"
}

variable "harbor_chart_version" {
  description = "Harbor helm chart version (chart 1.19.x = Harbor 2.15.x)"
  type        = string
  default     = "1.19.1"
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

# --- SiYuan ---
# Used by manifests/siyuan.yaml (rendered via templatefile in apps.tf).
# Mandatory CLI flag --accessAuthCode since SiYuan v2.10.8 — kernel refuses to
# start without it. Stored in a Secret and passed to the kernel as a CLI arg
# via env var substitution at the deployment level.
variable "siyuan_access_auth_code" {
  description = "SiYuan --accessAuthCode value. Mandatory for Docker deploys since v2.10.8; the kernel refuses to start without it. Generate with: openssl rand -base64 32. Rotate by editing terraform.tfvars and re-applying (deployment rolls with the new value)."
  type        = string
  sensitive   = true
}

# --- ZenNotes ---
# Used by manifests/zennotes.yaml (rendered via templatefile in apps.tf).
# ZenNotes is secure-by-default and refuses unauthenticated access unless
# ZENNOTES_ALLOW_INSECURE_NOAUTH=1. This bootstrap token is injected via
# ZENNOTES_AUTH_TOKEN; the browser is prompted for it once, then uses an
# HttpOnly session cookie. Generate with: openssl rand -hex 32. Rotate by
# editing terraform.tfvars and re-applying (deployment rolls; existing
# sessions invalidate and clients re-enter the new token).
variable "zennotes_auth_token" {
  description = "ZENNOTES_AUTH_TOKEN bootstrap auth token. Generate with: openssl rand -hex 32. Rotate by editing terraform.tfvars and re-applying."
  type        = string
  sensitive   = true
}

# --- Reactive Resume ---
# Used by manifests/reactive-resume.yaml (rendered via templatefile in apps.tf).
# Stack is fresh on first deploy: postgres initdb creates the 'reactive_resume'
# role from db_password; minio creates its root user from storage_secret_key; the
# app (v5, Better Auth) signs sessions with auth_secret and encrypts saved
# provider credentials with encryption_secret. Rotating db_password requires also
# resetting the role's password (it's only read by initdb on an empty PGDATA);
# the others roll cleanly on apply (rotating auth_secret logs everyone out).
variable "reactive_resume_db_password" {
  description = "Password for the 'reactive_resume' Postgres role. Set by initdb on first boot; embedded in DATABASE_URL. Generate with: openssl rand -base64 32"
  type        = string
  sensitive   = true
}

variable "reactive_resume_auth_secret" {
  description = "AUTH_SECRET — Better Auth session/token signing secret (v5; replaces the v4 access+refresh token secrets). Generate with: openssl rand -hex 32"
  type        = string
  sensitive   = true
}

variable "reactive_resume_encryption_secret" {
  description = "ENCRYPTION_SECRET — encrypts saved AI-provider credentials (v5). Generate with: openssl rand -hex 32"
  type        = string
  sensitive   = true
}

variable "reactive_resume_storage_secret_key" {
  description = "Minio root password = app STORAGE_SECRET_KEY. Must be >=8 chars. Generate with: openssl rand -base64 24"
  type        = string
  sensitive   = true
}

# --- Monitoring ---
# Used by monitoring.tf (kube-prometheus-stack helm release).
variable "grafana_admin_password" {
  description = "Grafana 'admin' user password. Grafana is reachable at grafana.<subdomain>.<primary_domain>, so keep this strong. Generate with: openssl rand -base64 24. Only seeds the admin user on first boot — persistence is enabled, so the password lives in Grafana's sqlite DB afterwards. To actually rotate: kubectl -n monitoring exec deploy/kube-prometheus-stack-grafana -- grafana cli admin reset-admin-password <new>, then update terraform.tfvars to match."
  type        = string
  sensitive   = true
}

# --- Harbor ---
# Used by harbor.tf (harbor helm release).
variable "harbor_admin_password" {
  description = "Harbor 'admin' user password. Publicly browsable at harbor.<primary_domain>, so keep this strong. Generate with: openssl rand -base64 18. Rotating via tfvars only works before first boot; afterwards change it in the UI (or via API) and update tfvars to match."
  type        = string
  sensitive   = true
}

variable "harbor_db_password" {
  description = "Password for Harbor's internal Postgres. Set by initdb on first boot; consumed by core/jobservice/registry. Generate with: openssl rand -base64 24. NOTE: the DB StatefulSet PVC survives helm uninstall/terraform destroy — on re-provision with a different value, initdb is skipped and core crashloops on auth failure; delete the retained PVC (or keep the old password) when intentionally reprovisioning."
  type        = string
  sensitive   = true
}

variable "harbor_secret_key" {
  description = "Harbor secretKey — encrypts stored remote-registry credentials. MUST be exactly 16 characters. Generate with: openssl rand -hex 8. Changing it orphans previously-encrypted credentials."
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.harbor_secret_key) == 16
    error_message = "harbor_secret_key must be exactly 16 characters (e.g. openssl rand -hex 8)."
  }
}

# --- GitLab ---
# Used by manifests/gitlab.yaml (rendered via templatefile in apps.tf).
variable "gitlab_root_password" {
  description = "GitLab 'root' user password. Seeds the account on FIRST boot only (GITLAB_ROOT_PASSWORD); afterwards it lives in GitLab's Postgres — rotate in the UI (or gitlab-rails console) and update tfvars to match. Publicly browsable at gitlab.<primary_domain>, so keep this strong. Generate with: openssl rand -base64 18"
  type        = string
  sensitive   = true
}

variable "gitlab_runner_chart_version" {
  description = "gitlab-runner helm chart version (0.90.x = runner 19.1.x; keep in step with the GitLab image)"
  type        = string
  default     = "0.90.1"
}

variable "gitlab_runner_token" {
  description = "GitLab instance-runner authentication token (glrt-...). Empty disables the runner release (fresh provisions boot GitLab first). Mint via: kubectl -n gitlab exec deploy/gitlab -- gitlab-rails runner \"r = Ci::Runner.create!(runner_type: 'instance_type', description: 'k8s cluster runner', run_untagged: true); puts r.token\""
  type        = string
  sensitive   = true
  default     = ""
}

variable "gitlab_ssh_ip" {
  description = "Static MetalLB IP for the GitLab SSH LoadBalancer (must fall inside metallb_ip_range and match the annotation in manifests/gitlab.yaml). gitlab-ssh.<subdomain>.<primary_domain> A record points here."
  type        = string
  default     = "10.0.10.213"
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
