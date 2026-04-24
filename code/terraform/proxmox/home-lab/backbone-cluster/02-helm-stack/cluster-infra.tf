# Foundational cluster services: Cilium (CNI + Gateway controller),
# MetalLB (LoadBalancer IPAM), nfs-subdir-external-provisioner (dynamic PVCs),
# metrics-server (kubectl top + HPA).

# =============================================================================
# 1. Cilium (CNI)
# =============================================================================

resource "helm_release" "cilium" {
  depends_on = [time_sleep.wait_for_gateway_crds]

  name             = "cilium"
  repository       = "https://helm.cilium.io/"
  chart            = "cilium"
  version          = var.cilium_version
  namespace        = "kube-system"
  create_namespace = false
  wait             = true
  timeout          = 600

  values = [file("${path.module}/values/cilium.yaml")]
}

resource "time_sleep" "wait_for_cilium" {
  depends_on      = [helm_release.cilium]
  create_duration = "30s"
}

# =============================================================================
# 2. MetalLB + IP pool
# =============================================================================

# Speaker pods need privileged PodSecurity (NET_ADMIN, NET_RAW, hostNetwork).
resource "kubernetes_namespace" "metallb_system" {
  depends_on = [time_sleep.wait_for_cilium]

  metadata {
    name = "metallb-system"
    labels = {
      "pod-security.kubernetes.io/enforce" = "privileged"
      "pod-security.kubernetes.io/audit"   = "privileged"
      "pod-security.kubernetes.io/warn"    = "privileged"
    }
  }
}

resource "helm_release" "metallb" {
  depends_on = [kubernetes_namespace.metallb_system]

  name             = "metallb"
  repository       = "https://metallb.github.io/metallb"
  chart            = "metallb"
  version          = var.metallb_version
  namespace        = "metallb-system"
  create_namespace = false
  wait             = true
  timeout          = 300

  # Inline the single value we set; the multi-doc YAML in values/metallb.yaml
  # also contains IPAddressPool + L2Advertisement which we apply separately.
  set {
    name  = "speaker.ignoreExcludeLB"
    value = "true"
  }
}

resource "time_sleep" "wait_for_metallb" {
  depends_on      = [helm_release.metallb]
  create_duration = "20s"
}

resource "kubectl_manifest" "metallb_pool" {
  depends_on = [time_sleep.wait_for_metallb]

  yaml_body = yamlencode({
    apiVersion = "metallb.io/v1beta1"
    kind       = "IPAddressPool"
    metadata = {
      name      = "backbone-pool"
      namespace = "metallb-system"
    }
    spec = {
      addresses = [var.metallb_ip_range]
    }
  })
}

resource "kubectl_manifest" "metallb_l2adv" {
  depends_on = [kubectl_manifest.metallb_pool]

  yaml_body = yamlencode({
    apiVersion = "metallb.io/v1beta1"
    kind       = "L2Advertisement"
    metadata = {
      name      = "backbone-l2"
      namespace = "metallb-system"
    }
    spec = {
      ipAddressPools = ["backbone-pool"]
    }
  })
}

# =============================================================================
# 3. nfs-subdir-external-provisioner (StorageClass nfs-client)
# =============================================================================

resource "helm_release" "nfs_subdir_provisioner" {
  depends_on = [time_sleep.wait_for_cilium]

  name             = "nfs-subdir-external-provisioner"
  repository       = "https://kubernetes-sigs.github.io/nfs-subdir-external-provisioner/"
  chart            = "nfs-subdir-external-provisioner"
  version          = var.nfs_subdir_provisioner_version
  namespace        = "nfs-system"
  create_namespace = true
  wait             = true
  timeout          = 300

  values = [file("${path.module}/values/nfs-subdir-external-provisioner.yaml")]

  # Ensure values-file NFS server/path matches vars (override to stay DRY).
  set {
    name  = "nfs.server"
    value = var.nfs_server
  }
  set {
    name  = "nfs.path"
    value = var.nfs_path
  }
}

# =============================================================================
# 4. metrics-server (kubectl top)
# =============================================================================

resource "helm_release" "metrics_server" {
  depends_on = [time_sleep.wait_for_cilium]

  name             = "metrics-server"
  repository       = "https://kubernetes-sigs.github.io/metrics-server/"
  chart            = "metrics-server"
  version          = var.metrics_server_version
  namespace        = "kube-system"
  create_namespace = false
  wait             = true
  timeout          = 300

  values = [file("${path.module}/values/metrics-server.yaml")]
}

# =============================================================================
# 5. Envoy Gateway (Gateway API controller)
# =============================================================================
# Replaces Cilium Gateway as the controller for `backbone-gateway`. Cilium
# Gateway's Envoy config hard-codes a gRPC-Web HTTP filter that rejects
# Connect-RPC (Memos) with 505 regardless of appProtocol. Envoy Gateway applies
# the filter only to GRPCRoute, so HTTPRoute passes Connect-RPC through cleanly.
# Cilium CNI + kube-proxy-replacement + LB-IPAM are untouched.

resource "helm_release" "envoy_gateway" {
  depends_on = [time_sleep.wait_for_cilium]

  name             = "eg"
  chart            = "oci://docker.io/envoyproxy/gateway-helm"
  version          = var.envoy_gateway_version
  namespace        = "envoy-gateway-system"
  create_namespace = true
  wait             = true
  timeout          = 600
}

resource "time_sleep" "wait_for_envoy_gateway" {
  depends_on      = [helm_release.envoy_gateway]
  create_duration = "30s"
}
