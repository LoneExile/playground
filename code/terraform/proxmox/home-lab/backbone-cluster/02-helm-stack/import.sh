#!/usr/bin/env bash
# One-time: adopt the state that was created by hand (helm install, kubectl apply,
# curl to Cloudflare/UniFi) into this 02-helm-stack terraform stage.
#
# Run from this directory (02-helm-stack/). Requires:
#   - terraform init already run
#   - ../terraform.tfvars populated (see ../terraform.tfvars.example)
#   - Cluster reachable via ../01-talos-cluster/kubeconfig
#
# Safe to re-run — imports that already exist are no-ops.

set -euo pipefail
cd "$(dirname "$0")"

TFVARS="../terraform.tfvars"
if [ ! -f "$TFVARS" ]; then
  echo "ERROR: ../terraform.tfvars missing"
  exit 1
fi

run() {
  echo "+ terraform import $*"
  terraform import -var-file="$TFVARS" "$@" 2>&1 | grep -vE "^$" || true
  echo ""
}

echo "=== Helm releases ==="
run 'helm_release.cilium'                       kube-system/cilium
run 'helm_release.metallb'                      metallb-system/metallb
run 'helm_release.nfs_subdir_provisioner'       nfs-system/nfs-subdir-external-provisioner
run 'helm_release.metrics_server'               kube-system/metrics-server
run 'helm_release.cert_manager'                 cert-manager/cert-manager

echo "=== Namespaces ==="
run 'kubernetes_namespace.metallb_system'       metallb-system
run 'kubernetes_namespace.gateway_system'       gateway-system

echo "=== Secrets ==="
run 'kubernetes_secret.cloudflare_api_token'    cert-manager/cloudflare-api-token

echo "=== MetalLB pool + L2Advertisement ==="
run 'kubectl_manifest.metallb_pool'             'metallb.io/v1beta1//IPAddressPool//backbone-pool//metallb-system'
run 'kubectl_manifest.metallb_l2adv'            'metallb.io/v1beta1//L2Advertisement//backbone-l2//metallb-system'

echo "=== ClusterIssuers + CA Certificate ==="
run 'kubectl_manifest.cluster_issuer_le_staging' 'cert-manager.io/v1//ClusterIssuer//letsencrypt-staging'
run 'kubectl_manifest.cluster_issuer_le_prod'    'cert-manager.io/v1//ClusterIssuer//letsencrypt-prod'
run 'kubectl_manifest.cluster_issuer_selfsigned' 'cert-manager.io/v1//ClusterIssuer//selfsigned-issuer'
run 'kubectl_manifest.ca_certificate'            'cert-manager.io/v1//Certificate//ca-certificate//cert-manager'
run 'kubectl_manifest.cluster_issuer_ca'         'cert-manager.io/v1//ClusterIssuer//ca-issuer'

echo "=== Gateway ==="
run 'kubectl_manifest.backbone_gateway'          'gateway.networking.k8s.io/v1//Gateway//backbone-gateway//gateway-system'

echo "=== Cloudflare A record ==="
# Import expects "<zone_id>/<record_id>". Find them via API.
ZONE_ID=$(curl -sS -H "Authorization: Bearer $(grep ^cloudflare_api_token $TFVARS | cut -d\" -f2)" \
  "https://api.cloudflare.com/client/v4/zones?name=0dl.me" | jq -r '.result[0].id')
RECORD_ID=$(curl -sS -H "Authorization: Bearer $(grep ^cloudflare_api_token $TFVARS | cut -d\" -f2)" \
  "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records?type=A&name=*.home.0dl.me" | jq -r '.result[0].id')
if [ -n "$RECORD_ID" ] && [ "$RECORD_ID" != "null" ]; then
  run 'cloudflare_record.wildcard_home' "$ZONE_ID/$RECORD_ID"
else
  echo "Skipping Cloudflare record import — not found at CF."
fi

echo ""
echo "=== Apps: filebrowser, jellyfin, qbittorrent-qui ==="
echo "These are applied fresh on first terraform apply. To avoid a re-create,"
echo "destroy any existing objects you don't want duplicated, OR skip apps.tf"
echo "entirely by setting skip_apps=true (not implemented yet)."
echo ""
echo "=== UniFi reservations ==="
echo "null_resources are always re-run on apply; no import needed."
echo ""
echo "=== Done — run: terraform plan -var-file=$TFVARS ==="
echo "Expected: small diffs for chart values + apps to create/update in place."
