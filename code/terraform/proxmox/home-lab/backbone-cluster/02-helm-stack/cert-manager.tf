# cert-manager + ClusterIssuers. DNS-01 via Cloudflare for real-domain certs
# (letsencrypt-prod/staging); self-signed CA for internal-only hostnames.

resource "helm_release" "cert_manager" {
  depends_on = [time_sleep.wait_for_gateway_crds]

  name             = "cert-manager"
  repository       = "https://charts.jetstack.io"
  chart            = "cert-manager"
  version          = var.cert_manager_version
  namespace        = "cert-manager"
  create_namespace = true
  wait             = true
  timeout          = 300

  values = [file("${path.module}/values/cert-manager.yaml")]
}

resource "time_sleep" "wait_for_cert_manager" {
  depends_on      = [helm_release.cert_manager]
  create_duration = "20s"
}

# Cloudflare API token used by cert-manager's DNS-01 solver.
resource "kubernetes_secret" "cloudflare_api_token" {
  depends_on = [time_sleep.wait_for_cert_manager]

  metadata {
    name      = "cloudflare-api-token"
    namespace = "cert-manager"
  }

  data = {
    api-token = var.cloudflare_api_token
  }

  type = "Opaque"
}

# --- ClusterIssuers ---

resource "kubectl_manifest" "cluster_issuer_le_staging" {
  depends_on = [kubernetes_secret.cloudflare_api_token]

  yaml_body = yamlencode({
    apiVersion = "cert-manager.io/v1"
    kind       = "ClusterIssuer"
    metadata = {
      name = "letsencrypt-staging"
    }
    spec = {
      acme = {
        server = "https://acme-staging-v02.api.letsencrypt.org/directory"
        email  = var.acme_email
        privateKeySecretRef = {
          name = "letsencrypt-staging-account-key"
        }
        solvers = [{
          dns01 = {
            cloudflare = {
              apiTokenSecretRef = {
                name = "cloudflare-api-token"
                key  = "api-token"
              }
            }
          }
        }]
      }
    }
  })
}

resource "kubectl_manifest" "cluster_issuer_le_prod" {
  depends_on = [kubernetes_secret.cloudflare_api_token]

  yaml_body = yamlencode({
    apiVersion = "cert-manager.io/v1"
    kind       = "ClusterIssuer"
    metadata = {
      name = "letsencrypt-prod"
    }
    spec = {
      acme = {
        server = "https://acme-v02.api.letsencrypt.org/directory"
        email  = var.acme_email
        privateKeySecretRef = {
          name = "letsencrypt-prod-account-key"
        }
        solvers = [{
          dns01 = {
            cloudflare = {
              apiTokenSecretRef = {
                name = "cloudflare-api-token"
                key  = "api-token"
              }
            }
          }
        }]
      }
    }
  })
}

# --- Self-signed CA chain (local-only hostnames) ---

resource "kubectl_manifest" "cluster_issuer_selfsigned" {
  depends_on = [time_sleep.wait_for_cert_manager]

  yaml_body = yamlencode({
    apiVersion = "cert-manager.io/v1"
    kind       = "ClusterIssuer"
    metadata = {
      name = "selfsigned-issuer"
    }
    spec = {
      selfSigned = {}
    }
  })
}

resource "kubectl_manifest" "ca_certificate" {
  depends_on = [kubectl_manifest.cluster_issuer_selfsigned]

  yaml_body = yamlencode({
    apiVersion = "cert-manager.io/v1"
    kind       = "Certificate"
    metadata = {
      name      = "ca-certificate"
      namespace = "cert-manager"
    }
    spec = {
      isCA        = true
      commonName  = "backbone-cluster-ca"
      secretName  = "ca-secret"
      duration    = "87600h" # 10 years
      renewBefore = "720h"   # 30 days
      privateKey = {
        algorithm = "RSA"
        size      = 4096
      }
      issuerRef = {
        name  = "selfsigned-issuer"
        kind  = "ClusterIssuer"
        group = "cert-manager.io"
      }
    }
  })
}

resource "kubectl_manifest" "cluster_issuer_ca" {
  depends_on = [kubectl_manifest.ca_certificate]

  yaml_body = yamlencode({
    apiVersion = "cert-manager.io/v1"
    kind       = "ClusterIssuer"
    metadata = {
      name = "ca-issuer"
    }
    spec = {
      ca = {
        secretName = "ca-secret"
      }
    }
  })
}
