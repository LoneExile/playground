# Cluster edge: namespace, EnvoyProxy config (MetalLB IP pin), Gateway
# (HTTP + HTTPS wildcard), Cloudflare DNS.
#
# Note: we use Envoy Gateway (gatewayClassName: eg) instead of Cilium Gateway
# because Cilium's Envoy config hard-codes a gRPC-Web filter that rejects
# Connect-RPC (Memos) with 505. Envoy Gateway applies the filter only to
# GRPCRoute, letting HTTPRoute pass Connect-RPC through untouched.

resource "kubernetes_namespace" "gateway_system" {
  depends_on = [time_sleep.wait_for_cilium]

  metadata {
    name = "gateway-system"
  }
}

# Per-gateway Envoy proxy config: sets the MetalLB annotation on the Service
# that Envoy Gateway auto-provisions for the Gateway below, pinning it to the
# static gateway IP so DNS + Cloudflare tunnel origins stay stable across
# restarts. Referenced via Gateway.spec.infrastructure.parametersRef.
resource "kubectl_manifest" "envoyproxy_backbone" {
  depends_on = [
    kubernetes_namespace.gateway_system,
    time_sleep.wait_for_envoy_gateway,
  ]

  yaml_body = yamlencode({
    apiVersion = "gateway.envoyproxy.io/v1alpha1"
    kind       = "EnvoyProxy"
    metadata = {
      name      = "backbone-proxy"
      namespace = "gateway-system"
    }
    spec = {
      provider = {
        type = "Kubernetes"
        kubernetes = {
          envoyService = {
            annotations = {
              "metallb.universe.tf/loadBalancerIPs" = var.gateway_external_ip
            }
          }
        }
      }
    }
  })
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
    kubectl_manifest.envoyproxy_backbone,
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
      gatewayClassName = "eg"
      infrastructure = {
        parametersRef = {
          group = "gateway.envoyproxy.io"
          kind  = "EnvoyProxy"
          name  = "backbone-proxy"
        }
      }
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
