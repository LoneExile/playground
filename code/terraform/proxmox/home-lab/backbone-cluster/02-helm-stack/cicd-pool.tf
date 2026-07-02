# CI/CD registration for pool-monitor — same pattern as cicd.tf (ecoflow).
# Reuses the existing Harbor project "homelab" (harbor_project.homelab) and adds
# a CI push-robot + cluster pull-robot, plus the GitLab project and CI/CD vars.

# =============================================================================
# Harbor: robot accounts (project "homelab" is defined in cicd.tf)
# =============================================================================

resource "harbor_robot_account" "pool_ci" {
  name        = "pool-ci"
  description = "GitLab CI buildkit push for pool-monitor (managed by Terraform)"
  level       = "project"
  secret      = var.pool_ci_robot_secret

  permissions {
    access {
      action   = "push"
      resource = "repository"
    }
    access {
      action   = "pull"
      resource = "repository"
    }
    kind      = "project"
    namespace = harbor_project.homelab.name
  }
}

resource "harbor_robot_account" "pool_pull" {
  name        = "pool-pull"
  description = "Cluster image pull for pool-monitor (managed by Terraform)"
  level       = "project"
  secret      = var.pool_pull_robot_secret

  permissions {
    access {
      action   = "pull"
      resource = "repository"
    }
    kind      = "project"
    namespace = harbor_project.homelab.name
  }
}

# =============================================================================
# GitLab: project + CI/CD variables (gated on the API token)
# =============================================================================

resource "gitlab_project" "pool_monitor" {
  count = var.gitlab_api_token == "" ? 0 : 1

  depends_on = [kubectl_manifest.apps] # GitLab server ships via the apps manifest set

  name                   = "pool-monitor"
  description            = "Proxmox ZFS pool + disk health monitor — mirror of GitHub. Managed by Terraform; code pushed via git."
  visibility_level       = "private"
  initialize_with_readme = false
}

# HARBOR_USER — robot full name (robot$homelab+pool-ci). raw so '$' isn't a ref.
resource "gitlab_project_variable" "pool_harbor_user" {
  count = var.gitlab_api_token == "" ? 0 : 1

  project = gitlab_project.pool_monitor[0].id
  key     = "HARBOR_USER"
  value   = harbor_robot_account.pool_ci.full_name
  raw     = true
  masked  = false
}

resource "gitlab_project_variable" "pool_harbor_pass" {
  count = var.gitlab_api_token == "" ? 0 : 1

  project = gitlab_project.pool_monitor[0].id
  key     = "HARBOR_PASS"
  value   = var.pool_ci_robot_secret
  raw     = true
  masked  = true
}

resource "gitlab_project_variable" "pool_harbor_image" {
  count = var.gitlab_api_token == "" ? 0 : 1

  project = gitlab_project.pool_monitor[0].id
  key     = "HARBOR_IMAGE"
  value   = "harbor.${local.fqdn_base}/${harbor_project.homelab.name}/pool-monitor"
  raw     = true
  masked  = false
}
