# Cluster edge: namespace, Gateway (HTTP+HTTPS wildcard), Cloudflare DNS,
# EndpointSlice label workaround (Cilium <-> MetalLB).

resource "kubernetes_namespace" "gateway_system" {
  depends_on = [time_sleep.wait_for_cilium]

  metadata {
    name = "gateway-system"
  }
}

# Single Gateway carries all app hostnames under *.home.0dl.me.
# cert-manager watches the cert-manager.io/cluster-issuer annotation and
# auto-issues a wildcard Certificate for the HTTPS listener's hostname.
resource "kubectl_manifest" "backbone_gateway" {
  depends_on = [
    kubernetes_namespace.gateway_system,
    kubectl_manifest.cluster_issuer_le_prod,
    kubectl_manifest.cluster_issuer_le_staging,
    kubectl_manifest.cluster_issuer_ca,
    kubectl_manifest.metallb_l2adv,
  ]

  yaml_body = yamlencode({
    apiVersion = "gateway.networking.k8s.io/v1"
    kind       = "Gateway"
    metadata = {
      name      = "backbone-gateway"
      namespace = "gateway-system"
      annotations = {
        "cert-manager.io/cluster-issuer" = var.tls_issuer
      }
    }
    spec = {
      gatewayClassName = "cilium"
      listeners = [
        {
          name     = "http"
          port     = 80
          protocol = "HTTP"
          allowedRoutes = {
            namespaces = { from = "All" }
          }
        },
        {
          name     = "https-wildcard"
          port     = 443
          protocol = "HTTPS"
          hostname = "*.${local.fqdn_base}"
          tls = {
            mode = "Terminate"
            certificateRefs = [{
              name = "wildcard-${replace(local.fqdn_base, ".", "-")}-tls"
            }]
          }
          allowedRoutes = {
            namespaces = { from = "All" }
          }
        }
      ]
    }
  })
}

resource "time_sleep" "wait_for_gateway" {
  depends_on      = [kubectl_manifest.backbone_gateway]
  create_duration = "30s"
}

# -----------------------------------------------------------------------------
# Known issue workaround: Cilium Gateway auto-creates an EndpointSlice for its
# LoadBalancer Service without the standard `kubernetes.io/service-name` label
# that MetalLB uses to determine readiness. Without this label MetalLB refuses
# to announce the gateway IP (ARP stays incomplete). Patch the label in post.
#
# Re-runs whenever the Gateway is recreated.
# -----------------------------------------------------------------------------
resource "null_resource" "gateway_endpointslice_label" {
  depends_on = [time_sleep.wait_for_gateway]

  triggers = {
    gateway_uid = kubectl_manifest.backbone_gateway.uid
  }

  provisioner "local-exec" {
    command = <<-EOT
      #!/bin/bash
      set -e
      # Wait up to 60s for Cilium to create the EndpointSlice, then patch.
      for i in $(seq 1 30); do
        if kubectl --kubeconfig ${var.kubeconfig_path} -n gateway-system \
             get endpointslice cilium-gateway-backbone-gateway >/dev/null 2>&1; then
          kubectl --kubeconfig ${var.kubeconfig_path} -n gateway-system label \
            endpointslice cilium-gateway-backbone-gateway \
            kubernetes.io/service-name=cilium-gateway-backbone-gateway \
            --overwrite
          exit 0
        fi
        sleep 2
      done
      echo "EndpointSlice didn't appear in 60s; MetalLB may not announce gateway IP"
      exit 1
    EOT
  }
}

# =============================================================================
# Cloudflare DNS: wildcard A record pointing at the gateway's MetalLB IP.
# Applies only to the primary domain. If you add voidbox.io/apinant.dev later,
# duplicate this block with a different zone data source.
# =============================================================================

data "cloudflare_zone" "primary" {
  name = var.primary_domain
}

resource "cloudflare_record" "wildcard_home" {
  zone_id = data.cloudflare_zone.primary.id
  name    = "*.${var.subdomain}"
  content = var.gateway_external_ip
  type    = "A"
  ttl     = 300
  proxied = false
  comment = "backbone-cluster gateway (MetalLB). Managed by Terraform."
}
