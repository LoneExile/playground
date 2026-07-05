# Self-hosted login wallpaper for TinyAuth. assets/homelab-bg.webp is a webp
# re-encode of the same Unsplash forest photo baked into the Keycloak homelab
# login theme (themes/homelab/login/login.ftl), so both SSO screens share one
# wallpaper. Shipping it locally means no Unsplash CDN hotlink, a smaller payload
# (~250 KB webp vs ~570 KB jpg), and a login page that renders with zero egress.
#
# Delivered as a binary ConfigMap (base64 via filebase64) rather than inlined in
# manifests/tinyauth.yaml so the blob doesn't bloat the templated YAML — same
# split rationale as keycloak-theme.tf. The Deployment mounts this at /resources
# (TINYAUTH_RESOURCES_PATH) and TinyAuth's file server serves the file at
# /homelab-bg.webp (TINYAUTH_UI_BACKGROUNDIMAGE).
#
# ConfigMaps cap at ~1 MiB; the webp base64s to ~325 KB, well under. To refresh
# the image, re-run the cwebp encode and `terraform apply` — the pod picks up the
# new ConfigMap on its next roll (Recreate strategy).
resource "kubernetes_config_map_v1" "tinyauth_bg" {
  # Namespace comes from manifests/tinyauth.yaml (applied in the apps batch).
  depends_on = [kubectl_manifest.apps]

  metadata {
    name      = "tinyauth-bg"
    namespace = "tinyauth"
  }

  binary_data = {
    "homelab-bg.webp" = filebase64("${path.module}/assets/homelab-bg.webp")
  }
}
