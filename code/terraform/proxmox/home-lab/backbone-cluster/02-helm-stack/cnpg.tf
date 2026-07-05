# CloudNativePG — a Postgres operator that manages HA Postgres Clusters
# declaratively. It replaces the ad-hoc per-app `postgres:16` Deployments as the
# unified DB platform: each app gets its own Cluster under this one operator,
# with consistent backups, failover, pooling and Prometheus metrics.
#
# First tenant: the *arr stack. Sonarr/Radarr/Prowlarr can't run their SQLite DBs
# reliably on NFS (WAL/-shm locking → "database is locked"); Postgres fixes that
# for good. Each app needs two databases (main + log) → 6 DBs on one Cluster,
# all owned by the auto-provisioned `arr` role (secret: arr-pg-app).
#
# Storage note: CNPG prefers block storage; only nfs-client (NFS) exists here.
# A single instance on NFS is fine for a homelab (the existing Postgres pods
# already run on this NFS); multi-instance HA would want real block storage.

resource "helm_release" "cnpg" {
  name             = "cnpg"
  repository       = "https://cloudnative-pg.github.io/charts"
  chart            = "cloudnative-pg"
  version          = var.cnpg_version
  namespace        = "cnpg-system"
  create_namespace = true
  wait             = true
  timeout          = 300
}

# Give the operator + CRDs a moment to register before applying Cluster/Database.
resource "time_sleep" "wait_for_cnpg" {
  depends_on      = [helm_release.cnpg]
  create_duration = "30s"
}

# Single-instance Postgres 17 Cluster for the *arr stack, in the arr namespace so
# apps reach it over same-ns Service DNS (arr-pg-rw.arr.svc:5432) and share the
# auto-generated arr-pg-app secret. wait_for_rollout is off: a CNPG Cluster is a
# custom resource reconciled by the operator, not a Deployment/StatefulSet.
resource "kubectl_manifest" "arr_pg_cluster" {
  depends_on       = [time_sleep.wait_for_cnpg]
  wait_for_rollout = false

  yaml_body = yamlencode({
    apiVersion = "postgresql.cnpg.io/v1"
    kind       = "Cluster"
    metadata = {
      name      = "arr-pg"
      namespace = "arr"
    }
    spec = {
      instances = 1
      imageName = "ghcr.io/cloudnative-pg/postgresql:17"
      # initdb creates the base db + the unprivileged owner role `arr`; CNPG
      # auto-generates the arr-pg-app secret (keys: username/password/...).
      bootstrap = {
        initdb = {
          database = "arr"
          owner    = "arr"
        }
      }
      storage = {
        size         = "10Gi"
        storageClass = "nfs-client"
      }
      resources = {
        requests = { cpu = "100m", memory = "256Mi" }
        limits   = { memory = "1Gi" }
      }
    }
  })
}

# The two databases each *arr app needs (main + log), owned by the `arr` role.
# Declarative Database CRs (reconciled by the operator once the Cluster is up).
resource "kubectl_manifest" "arr_pg_databases" {
  for_each = toset([
    "sonarr-main", "sonarr-log",
    "radarr-main", "radarr-log",
    "prowlarr-main", "prowlarr-log",
  ])

  depends_on       = [kubectl_manifest.arr_pg_cluster]
  wait_for_rollout = false

  yaml_body = yamlencode({
    apiVersion = "postgresql.cnpg.io/v1"
    kind       = "Database"
    metadata = {
      name      = each.key
      namespace = "arr"
    }
    spec = {
      name  = each.key
      owner = "arr"
      cluster = {
        name = "arr-pg"
      }
    }
  })
}
