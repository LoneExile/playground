# App deployments. Each app's YAML lives in manifests/<app>.yaml as the single
# source of truth; this file loads them as multi-doc manifests and applies via
# kubectl_manifest for_each. Edits go in the YAML files, not here.

locals {
  app_files = {
    filebrowser     = "${path.module}/manifests/filebrowser.yaml"
    jellyfin        = "${path.module}/manifests/jellyfin.yaml"
    memos           = "${path.module}/manifests/memos.yaml"
    qbittorrent_qui = "${path.module}/manifests/qbittorrent-qui.yaml"
  }
}

data "kubectl_file_documents" "apps" {
  for_each = local.app_files
  content  = file(each.value)
}

# Flatten { app => [doc1, doc2, ...] } into a stable map of {"app-N" => doc}
# so kubectl_manifest can for_each over a single dimension.
locals {
  app_manifests = merge([
    for app, docs in data.kubectl_file_documents.apps : {
      for idx, doc in docs.documents : "${app}-${idx}" => doc
    }
  ]...)
}

resource "kubectl_manifest" "apps" {
  for_each = local.app_manifests

  depends_on = [
    time_sleep.wait_for_gateway,
    helm_release.nfs_subdir_provisioner,
  ]

  yaml_body = each.value
}
