# App deployments. Each app's YAML lives in manifests/<app>.yaml as the single
# source of truth; this file loads them as multi-doc manifests and applies via
# kubectl_manifest for_each. Edits go in the YAML files, not here.
#
# Most apps are static (file()). Apps that need secret values rendered into the
# manifest are listed under app_rendered (templatefile()) and are merged with
# the static set into a single kubectl_manifest for_each.

locals {
  # Static manifests — applied verbatim.
  app_files = {
    blog            = "${path.module}/manifests/blog.yaml"
    # Off-cluster app (uvicorn on 10.0.10.29) fronted by the gateway purely to be
    # gated by TinyAuth: selector-less Service + external EndpointSlice + routes +
    # SecurityPolicy. See the MANUAL Cloudflare cutover note in the manifest.
    hermes          = "${path.module}/manifests/hermes.yaml"
    image_gen       = "${path.module}/manifests/image-gen.yaml"
    jellyfin        = "${path.module}/manifests/jellyfin.yaml"
    llm             = "${path.module}/manifests/llm.yaml"
    memos           = "${path.module}/manifests/memos.yaml"
    node_thermal    = "${path.module}/manifests/node-thermal.yaml"
    openbao         = "${path.module}/manifests/openbao-nfs.yaml"
    qbittorrent_qui = "${path.module}/manifests/qbittorrent-qui.yaml"
    syncthing       = "${path.module}/manifests/syncthing.yaml"
    trilium         = "${path.module}/manifests/trilium.yaml"
    # Envoy Gateway SecurityPolicies gating the SSO-less apps behind TinyAuth.
    # Kept separate from each app's manifest so the gate is opt-in and auditable
    # in one place; depends on the tinyauth Service + ReferenceGrant (both in
    # manifests/tinyauth.yaml), which apply in the same kubectl_manifest batch.
    tinyauth_securitypolicies = "${path.module}/manifests/tinyauth-securitypolicies.yaml"
  }

  # Templated manifests — secrets / values from sensitive vars rendered in.
  app_rendered = {
    # dashy carries no secret; it's templated only to inline the standalone
    # dashboard config (manifests/dashy/conf.yml) into its ConfigMap doc, so the
    # ConfigMap and Deployment apply in the same kubectl batch (no mount race).
    dashy = templatefile("${path.module}/manifests/dashy.yaml", {
      dashy_conf = file("${path.module}/manifests/dashy/conf.yml")
    })
    paperless = templatefile("${path.module}/manifests/paperless.yaml", {
      paperless_db_password = var.paperless_db_password
      paperless_secret_key  = var.paperless_secret_key
      # Pinned OIDC secret rendered into the PAPERLESS_SOCIALACCOUNT_PROVIDERS JSON
      # (var, not the client attribute — cycle break, see variables.tf).
      paperless_oidc_client_secret = var.paperless_oidc_client_secret
    })
    immich = templatefile("${path.module}/manifests/immich.yaml", {
      immich_db_password = var.immich_db_password
    })
    siyuan = templatefile("${path.module}/manifests/siyuan.yaml", {
      siyuan_access_auth_code = var.siyuan_access_auth_code
    })
    zennotes = templatefile("${path.module}/manifests/zennotes.yaml", {
      zennotes_auth_token = var.zennotes_auth_token
    })
    gitlab = templatefile("${path.module}/manifests/gitlab.yaml", {
      gitlab_root_password_b64 = base64encode(var.gitlab_root_password)
      gitlab_ssh_ip            = var.gitlab_ssh_ip
      # Pinned OIDC secret, base64'd into the gitlab-secrets Secret (var, not the
      # client attribute, to avoid the apps↔keycloak cycle — see variables.tf).
      gitlab_oidc_client_secret_b64 = base64encode(var.gitlab_oidc_client_secret)
    })
    ecoflow = templatefile("${path.module}/manifests/ecoflow-monitor.yaml", {
      ecoflow_image        = var.ecoflow_image
      ecoflow_email_b64    = base64encode(var.ecoflow_email)
      ecoflow_password_b64 = base64encode(var.ecoflow_password)
      # Harbor pull-robot docker credential. The robot name is deterministic
      # (robot$<project>+<name>) and the secret is the tfvars value TF also pins
      # on the robot — referenced literally (not via the harbor_robot_account
      # resource) to avoid a dependency cycle through the helm_release chain.
      # The robot itself is created in cicd.tf.
      harbor_pull_dockerconfig_b64 = base64encode(jsonencode({
        auths = {
          "harbor.${local.fqdn_base}" = {
            auth = base64encode("robot$homelab+ecoflow-pull:${var.ecoflow_pull_robot_secret}")
          }
        }
      }))
    })
    pool = templatefile("${path.module}/manifests/pool-monitor.yaml", {
      pool_image           = var.pool_image
      pve_host             = var.pool_pve_host
      pve_node             = var.pool_pve_node
      pve_token_id         = var.pool_pve_token_id
      pve_token_secret_b64 = base64encode(var.proxmox_api_token_secret_nas)
      # Harbor pull-robot credential — deterministic robot name + tfvars secret,
      # referenced literally (not via the resource) to avoid a dependency cycle
      # through the helm_release chain. Robot created in cicd-pool.tf.
      harbor_pull_dockerconfig_b64 = base64encode(jsonencode({
        auths = {
          "harbor.${local.fqdn_base}" = {
            auth = base64encode("robot$homelab+pool-pull:${var.pool_pull_robot_secret}")
          }
        }
      }))
    })
    keycloak = templatefile("${path.module}/manifests/keycloak-db.yaml", {
      keycloak_db_password    = var.keycloak_db_password
      keycloak_admin_password = var.keycloak_admin_password
    })
    sftpgo = templatefile("${path.module}/manifests/sftpgo.yaml", {
      sftpgo_oidc_client_secret = var.sftpgo_oidc_client_secret
      sftpgo_bootstrap_password = var.sftpgo_bootstrap_password
      sftpgo_host               = local.hostnames.sftpgo
      sftpgo_tunnel_host        = "sftpgo.${var.primary_domain}"
      sftpgo_s3_access_key      = var.sftpgo_s3_access_key
      sftpgo_s3_secret_key      = var.sftpgo_s3_secret_key
    })
    reactive_resume = templatefile("${path.module}/manifests/reactive-resume.yaml", {
      reactive_resume_db_password        = var.reactive_resume_db_password
      reactive_resume_auth_secret        = var.reactive_resume_auth_secret
      reactive_resume_encryption_secret  = var.reactive_resume_encryption_secret
      reactive_resume_storage_secret_key = var.reactive_resume_storage_secret_key
      # Pinned OIDC secret for the Better Auth genericOAuth provider (var, not the
      # client attribute — cycle break, see variables.tf).
      reactive_resume_oidc_client_secret = var.reactive_resume_oidc_client_secret
    })
    tinyauth = templatefile("${path.module}/manifests/tinyauth.yaml", {
      # Pinned OIDC secret, base64'd into the tinyauth-secrets Secret (var, not
      # the client attribute — cycle break, see variables.tf / tinyauth.tf).
      tinyauth_oidc_client_secret_b64 = base64encode(var.tinyauth_oidc_client_secret)
      tinyauth_owner_email            = var.tinyauth_owner_email
      tinyauth_host                   = "tinyauth.${var.primary_domain}"
      keycloak_host                   = "keycloak.${var.primary_domain}"
      # Envoy gateway pods (pod CIDR) are the only proxies allowed to set the
      # X-Forwarded-* headers TinyAuth trusts for host/proto reconstruction.
      trusted_proxies = "100.124.0.0/16"
    })
  }
}

data "kubectl_file_documents" "apps" {
  for_each = local.app_files
  content  = file(each.value)
}

data "kubectl_file_documents" "apps_rendered" {
  for_each = local.app_rendered
  content  = each.value
}

# Flatten { app => [doc1, doc2, ...] } into a stable map of {"app-N" => doc}
# so kubectl_manifest can for_each over a single dimension. Both static and
# rendered maps are merged.
locals {
  app_manifests = merge(
    merge([
      for app, docs in data.kubectl_file_documents.apps :
      { for idx, doc in docs.documents : "${app}-${idx}" => doc }
    ]...),
    merge([
      for app, docs in data.kubectl_file_documents.apps_rendered :
      { for idx, doc in docs.documents : "${app}-${idx}" => doc }
    ]...),
  )
}

resource "kubectl_manifest" "apps" {
  for_each = local.app_manifests

  depends_on = [
    time_sleep.wait_for_gateway,
    helm_release.nfs_subdir_provisioner,
  ]

  yaml_body = each.value

  # Don't block apply on the ecoflow/pool Deployments rolling out: their images
  # are built by GitLab CI *after* this apply creates the project + registry
  # robots, so the pod is ImagePullBackOff until the first pipeline runs. Other
  # apps keep the default rollout wait.
  wait_for_rollout = !startswith(each.key, "ecoflow-") && !startswith(each.key, "pool-")
}
