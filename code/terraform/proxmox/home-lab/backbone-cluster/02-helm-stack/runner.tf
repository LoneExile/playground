# GitLab Runner (kubernetes executor). Guarded on the token so a fresh
# provision works in two passes: apply brings GitLab up with no runner, then
# mint an instance runner token and re-apply:
#   kubectl -n gitlab exec deploy/gitlab -- gitlab-rails runner \
#     "r = Ci::Runner.create!(runner_type: 'instance_type', \
#      description: 'k8s cluster runner', run_untagged: true); puts r.token"
#   # -> glrt-... into terraform.tfvars gitlab_runner_token, terraform apply

resource "helm_release" "gitlab_runner" {
  count = var.gitlab_runner_token == "" ? 0 : 1

  depends_on = [kubectl_manifest.apps] # gitlab itself ships via the apps manifest set

  name             = "gitlab-runner"
  repository       = "https://charts.gitlab.io"
  chart            = "gitlab-runner"
  version          = var.gitlab_runner_chart_version
  namespace        = "gitlab-runner"
  create_namespace = true
  wait             = true
  timeout          = 300

  values = [file("${path.module}/values/gitlab-runner.yaml")]

  set_sensitive {
    name  = "runnerToken"
    value = var.gitlab_runner_token
  }
}
