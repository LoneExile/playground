# Custom Keycloak login theme for the homelab realm. The theme source lives in
# themes/homelab/login/ (version-controlled); this ConfigMap ships those files
# into the Keycloak pod, mounted at /opt/keycloak/themes/homelab/login via
# extraVolumeMounts in values/keycloak.yaml. The realm's login_theme is set to
# "homelab" in keycloak-oidc.tf.
#
# Files are read with file() (NOT templatefile) — login.ftl is full of FreeMarker
# ${...} that must reach Keycloak verbatim, not be interpreted by Terraform.
#
# Keycloak caches themes, so a change here needs a pod restart to take effect;
# the helm_release picks up the values change and rolls the pod automatically,
# but an edit to only these files (same mount) needs a manual
# `kubectl -n keycloak rollout restart statefulset/keycloak`.
resource "kubernetes_config_map_v1" "keycloak_theme_homelab" {
  # Namespace comes from manifests/keycloak-db.yaml.
  depends_on = [kubectl_manifest.apps]

  metadata {
    name      = "keycloak-theme-homelab"
    namespace = "keycloak"
  }

  data = {
    "theme.properties" = file("${path.module}/themes/homelab/login/theme.properties")
    "login.ftl"        = file("${path.module}/themes/homelab/login/login.ftl")
  }

  # Login wallpaper, self-hosted as a theme resource instead of a CDN hotlink.
  # Same assets/homelab-bg.webp that TinyAuth serves (tinyauth-bg.tf) — one source
  # of truth, so both SSO screens share a byte-identical background. Mounted via
  # subPath into themes/homelab/login/resources/ in values/keycloak.yaml, and
  # referenced from login.ftl as ${url.resourcesPath}/homelab-bg.webp.
  binary_data = {
    "homelab-bg.webp" = filebase64("${path.module}/assets/homelab-bg.webp")
  }
}
