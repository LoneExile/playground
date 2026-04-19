# UniFi DHCP reservations. Using null_resource + curl against the UDM REST
# API because the paultyng/unifi provider needs legacy username/password auth,
# and we only have an API key.

locals {
  # Keyed by hostname. Match MACs + IPs with 01-talos-cluster/variables.tf.
  unifi_reservations = {
    "bb-ctrl-01"   = { mac = "bc:24:11:bb:60:01", ip = "10.0.10.201" }
    "bb-ctrl-02"   = { mac = "bc:24:11:bb:61:02", ip = "10.0.10.202" }
    "bb-ctrl-03"   = { mac = "bc:24:11:bb:62:03", ip = "10.0.10.203" }
    "bb-worker-01" = { mac = "bc:24:11:bb:64:01", ip = "10.0.10.205" }
  }
}

resource "null_resource" "unifi_reservation" {
  for_each = local.unifi_reservations

  triggers = {
    mac     = each.value.mac
    ip      = each.value.ip
    name    = each.key
    api_url = var.unifi_api_url
    site    = var.unifi_site
    # Store api_key in triggers so destroy provisioner can access via self.triggers
    api_key = var.unifi_api_key
  }

  # Create / update reservation. Idempotent.
  provisioner "local-exec" {
    command = <<-EOT
      #!/bin/bash
      set -euo pipefail

      API="${var.unifi_api_url}/proxy/network/api/s/${var.unifi_site}"
      HDR_AUTH="X-API-KEY: ${var.unifi_api_key}"
      HDR_JSON="Content-Type: application/json"

      NET_ID=$(curl -sk -H "$HDR_AUTH" "$API/rest/networkconf" \
        | jq -r '.data[] | select(.name=="${var.unifi_home_network_name}") | ._id')
      if [ -z "$NET_ID" ] || [ "$NET_ID" = "null" ]; then
        echo "ERROR: UniFi network '${var.unifi_home_network_name}' not found"
        exit 1
      fi

      EXISTING_ID=$(curl -sk -H "$HDR_AUTH" "$API/list/user" \
        | jq -r --arg mac "${each.value.mac}" '.data[] | select(.mac==$mac) | ._id // empty')

      if [ -n "$EXISTING_ID" ]; then
        curl -sk -X PUT -H "$HDR_AUTH" -H "$HDR_JSON" \
          "$API/rest/user/$EXISTING_ID" \
          -d "{\"name\":\"${each.key}\",\"use_fixedip\":true,\"fixed_ip\":\"${each.value.ip}\",\"network_id\":\"$NET_ID\"}" \
          >/dev/null
        echo "Updated reservation: ${each.key} (${each.value.mac} -> ${each.value.ip})"
      else
        curl -sk -X POST -H "$HDR_AUTH" -H "$HDR_JSON" \
          "$API/rest/user" \
          -d "{\"mac\":\"${each.value.mac}\",\"name\":\"${each.key}\",\"use_fixedip\":true,\"fixed_ip\":\"${each.value.ip}\",\"network_id\":\"$NET_ID\"}" \
          >/dev/null
        echo "Created reservation: ${each.key} (${each.value.mac} -> ${each.value.ip})"
      fi
    EOT
  }

  # Delete on destroy. Uses self.triggers since var.* isn't accessible then.
  provisioner "local-exec" {
    when = destroy

    command = <<-EOT
      #!/bin/bash
      set -euo pipefail
      API="${self.triggers.api_url}/proxy/network/api/s/${self.triggers.site}"
      EXISTING_ID=$(curl -sk -H "X-API-KEY: ${self.triggers.api_key}" "$API/list/user" \
        | jq -r --arg mac "${self.triggers.mac}" '.data[] | select(.mac==$mac) | ._id // empty')
      if [ -n "$EXISTING_ID" ]; then
        curl -sk -X DELETE -H "X-API-KEY: ${self.triggers.api_key}" \
          "$API/rest/user/$EXISTING_ID" >/dev/null
        echo "Deleted reservation for ${self.triggers.name} (${self.triggers.mac})"
      fi
    EOT
  }
}
