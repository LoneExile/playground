# GitLab Runner (kubernetes executor). Guarded on the token so a fresh
# provision works in two passes: apply brings GitLab up with no runner, then
# mint an instance runner token and re-apply:
#   kubectl -n gitlab exec deploy/gitlab -- gitlab-rails runner \
#     "r = Ci::Runner.create!(runner_type: 'instance_type', \
#      description: 'k8s cluster runner', run_untagged: true); puts r.token"
#   # -> glrt-... into terraform.tfvars gitlab_runner_token, terraform apply

# CI build pods run rootless BuildKit, which clones a user namespace. The
# containerd default seccomp profile blocks CLONE_NEWUSER without CAP_SYS_ADMIN,
# so the build container must run with seccomp Unconfined (see gitlab-runner.yaml).
# Talos enforces baseline PSA cluster-wide, and baseline rejects Unconfined — so
# this namespace opts up to privileged. Scope is limited to CI job pods; the
# build container still runs as uid 1000 with no privileged flag and no caps.
resource "kubernetes_namespace" "gitlab_runner" {
  count = var.gitlab_runner_token == "" ? 0 : 1

  metadata {
    name = "gitlab-runner"
    labels = {
      "pod-security.kubernetes.io/enforce" = "privileged"
      "pod-security.kubernetes.io/audit"   = "privileged"
      "pod-security.kubernetes.io/warn"    = "privileged"
    }
  }
}

resource "helm_release" "gitlab_runner" {
  count = var.gitlab_runner_token == "" ? 0 : 1

  depends_on = [
    kubectl_manifest.apps,               # gitlab itself ships via the apps manifest set
    kubernetes_namespace.gitlab_runner,  # privileged-PSA namespace must exist first
  ]

  name             = "gitlab-runner"
  repository       = "https://charts.gitlab.io"
  chart            = "gitlab-runner"
  version          = var.gitlab_runner_chart_version
  namespace        = "gitlab-runner"
  create_namespace = false
  wait             = true
  timeout          = 300

  values = [file("${path.module}/values/gitlab-runner.yaml")]

  set_sensitive {
    name  = "runnerToken"
    value = var.gitlab_runner_token
  }
}
