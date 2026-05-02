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
    filebrowser     = "${path.module}/manifests/filebrowser.yaml"
    jellyfin        = "${path.module}/manifests/jellyfin.yaml"
    memos           = "${path.module}/manifests/memos.yaml"
    qbittorrent_qui = "${path.module}/manifests/qbittorrent-qui.yaml"
    syncthing       = "${path.module}/manifests/syncthing.yaml"
  }

  # Templated manifests — secrets / values from sensitive vars rendered in.
  app_rendered = {
    paperless = templatefile("${path.module}/manifests/paperless.yaml", {
      paperless_db_password = var.paperless_db_password
      paperless_secret_key  = var.paperless_secret_key
    })
    immich = templatefile("${path.module}/manifests/immich.yaml", {
      immich_db_password = var.immich_db_password
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
}
