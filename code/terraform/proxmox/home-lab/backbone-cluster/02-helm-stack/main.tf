# Stage 02: in-cluster services + edge (DNS/TLS).
# Reads kubeconfig produced by stage 01, installs Helm charts and manifests that
# live on top of the Talos cluster, plus manages Cloudflare DNS and UniFi DHCP
# reservations so the whole cluster is reproducible via terraform.

# =============================================================================
# Providers
# =============================================================================

provider "kubernetes" {
  config_path = var.kubeconfig_path
}

provider "helm" {
  kubernetes {
    config_path = var.kubeconfig_path
  }
}

# kubectl provider is used for raw manifests (CRDs, ClusterIssuers, Gateway,
# HTTPRoutes). Better than null_resource+local-exec because it tracks state
# and cleans up on destroy.
provider "kubectl" {
  config_path      = var.kubeconfig_path
  load_config_file = true
}

provider "cloudflare" {
  api_token = var.cloudflare_api_token
}

# =============================================================================
# Locals
# =============================================================================

locals {
  fqdn_base = "${var.subdomain}.${var.primary_domain}" # e.g. home.0dl.me

  # Fully qualified hostnames per app.
  hostnames = {
    filebrowser = "files.${local.fqdn_base}"
    jellyfin    = "jellyfin.${local.fqdn_base}"
    qui         = "qui.${local.fqdn_base}"
    qbittorrent = "qbit.${local.fqdn_base}"
  }
}

# =============================================================================
# 0. Gateway API CRDs — prerequisite for Cilium gatewayAPI: true
# =============================================================================

resource "null_resource" "gateway_api_crds" {
  triggers = {
    version = var.gateway_api_version
  }

  provisioner "local-exec" {
    command = "kubectl --kubeconfig ${var.kubeconfig_path} apply --server-side -f https://github.com/kubernetes-sigs/gateway-api/releases/download/${var.gateway_api_version}/standard-install.yaml"
  }
}

resource "time_sleep" "wait_for_gateway_crds" {
  depends_on      = [null_resource.gateway_api_crds]
  create_duration = "10s"
}
