# CI/CD registration for ecoflow-monitor, fully reproducible in Terraform.
#
# Harbor (always managed — admin creds are in tfvars from the start):
#   - project "homelab" (the image registry namespace)
#   - CI push-robot + cluster pull-robot, secrets pinned from tfvars
# GitLab (managed only when gitlab_api_token is set — gated so a fresh cluster
# can boot GitLab before the token exists):
#   - the ecoflow-monitor project (code pushed separately via git)
#   - CI/CD variables HARBOR_USER / HARBOR_PASS / HARBOR_IMAGE, wired from the
#     Harbor robot so buildkit can authenticate to the registry
#
# The robot secrets flow tfvars -> robot -> {GitLab CI var, cluster
# imagePullSecret in apps.tf}, so the same value is set everywhere with no
# manual copying.

# =============================================================================
# Harbor: registry project + robot accounts
# =============================================================================

resource "harbor_project" "homelab" {
  depends_on = [helm_release.harbor]

  name   = "homelab"
  public = false
}

# CI push-robot — buildkit authenticates with this to push the built image.
resource "harbor_robot_account" "ecoflow_ci" {
  name        = "ecoflow-ci"
  description = "GitLab CI buildkit push (managed by Terraform)"
  level       = "project"
  secret      = var.ecoflow_ci_robot_secret

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

# Cluster pull-robot — the ecoflow Deployment's imagePullSecret uses this.
resource "harbor_robot_account" "ecoflow_pull" {
  name        = "ecoflow-pull"
  description = "Cluster image pull (managed by Terraform)"
  level       = "project"
  secret      = var.ecoflow_pull_robot_secret

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

resource "gitlab_project" "ecoflow_monitor" {
  count = var.gitlab_api_token == "" ? 0 : 1

  # Server itself ships via the apps manifest set; must be up first.
  depends_on = [kubectl_manifest.apps]

  name                   = "ecoflow-monitor"
  description            = "EcoFlow DELTA 3 telemetry backend — mirror of GitHub. Managed by Terraform; code pushed via git."
  visibility_level       = "private"
  initialize_with_readme = false
  # created under the token owner's namespace (root) -> root/ecoflow-monitor
}

# HARBOR_USER — the robot's full name (robot$homelab+ecoflow-ci). raw so the
# '$' isn't treated as a CI variable reference.
resource "gitlab_project_variable" "harbor_user" {
  count = var.gitlab_api_token == "" ? 0 : 1

  project = gitlab_project.ecoflow_monitor[0].id
  key     = "HARBOR_USER"
  value   = harbor_robot_account.ecoflow_ci.full_name
  raw     = true
  masked  = false
}

resource "gitlab_project_variable" "harbor_pass" {
  count = var.gitlab_api_token == "" ? 0 : 1

  project = gitlab_project.ecoflow_monitor[0].id
  key     = "HARBOR_PASS"
  value   = var.ecoflow_ci_robot_secret
  raw     = true
  masked  = true
}

resource "gitlab_project_variable" "harbor_image" {
  count = var.gitlab_api_token == "" ? 0 : 1

  project = gitlab_project.ecoflow_monitor[0].id
  key     = "HARBOR_IMAGE"
  value   = "harbor.${local.fqdn_base}/${harbor_project.homelab.name}/ecoflow-monitor"
  raw     = true
  masked  = false
}
