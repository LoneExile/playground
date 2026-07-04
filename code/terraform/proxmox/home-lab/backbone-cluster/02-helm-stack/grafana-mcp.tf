# Grafana MCP — service account + token for the standalone mcp-grafana server.
#
# There is NO built-in MCP server in OSS Grafana 13.1 (no /api/mcp route, no
# feature toggle — verified: /api/mcp returns 404 with a valid admin token). The
# supported path is the standalone `mcp-grafana` server
# (https://github.com/grafana/mcp-grafana): it runs wherever the MCP client runs
# (here: locally on the workstation via `uvx mcp-grafana`, stdio transport) and
# talks to Grafana over HTTP using a service-account token.
#
# This file provisions that token as code. Grafana is reachable at either
# hostname (mcp-grafana can target whichever):
#   https://grafana.home.0dl.me   (LAN, wildcard TLS)
#   https://grafana.0dl.me        (public via Cloudflare Tunnel)
#
# Wire it into the client after apply:
#   TOKEN=$(terraform output -raw grafana_mcp_token)
#   claude mcp add --scope user grafana \
#     --env GRAFANA_URL=https://grafana.0dl.me \
#     --env GRAFANA_SERVICE_ACCOUNT_TOKEN=$TOKEN \
#     -- uvx mcp-grafana

# Provider authenticates as admin (basic auth) over the LAN hostname to
# provision the service account. admin password is the same tfvars value that
# seeds Grafana (variables.tf: grafana_admin_password).
provider "grafana" {
  url  = "https://${local.hostnames.grafana}"
  auth = "admin:${var.grafana_admin_password}"
}

# Admin role: mcp-grafana can read/query and manage dashboards, alerts,
# datasources, etc. (chosen deliberately — least-privilege would be Viewer).
resource "grafana_service_account" "claude_mcp" {
  depends_on = [helm_release.kube_prometheus_stack] # Grafana API must be up

  name = "claude-mcp"
  role = "Admin"
}

# Non-expiring token (no seconds_to_live). The key is returned once at creation
# and kept in state (sensitive) — surfaced via the grafana_mcp_token output.
resource "grafana_service_account_token" "claude_mcp" {
  name               = "claude-mcp"
  service_account_id = grafana_service_account.claude_mcp.id
}
