resource "digitalocean_droplet" "this" {
  count = var.instance_count

  name      = var.instance_count > 1 ? "${var.name}-${count.index + 1}" : var.name
  size      = var.size
  image     = var.image
  region    = var.region
  vpc_uuid  = var.vpc_id
  tags      = var.tags
  ssh_keys  = var.ssh_keys
  user_data = var.user_data

  backups           = var.backups
  monitoring        = var.monitoring
  ipv6              = var.ipv6
  resize_disk       = var.resize_disk
  droplet_agent     = var.droplet_agent
  graceful_shutdown = var.graceful_shutdown
}

resource "digitalocean_firewall" "this" {
  count = var.create_firewall ? 1 : 0

  name        = "${var.name}-firewall"
  droplet_ids = digitalocean_droplet.this[*].id
  tags        = var.tags

  dynamic "inbound_rule" {
    for_each = var.inbound_rules
    content {
      protocol         = inbound_rule.value.protocol
      port_range       = inbound_rule.value.port_range
      source_addresses = inbound_rule.value.source_addresses
    }
  }

  dynamic "outbound_rule" {
    for_each = var.outbound_rules
    content {
      protocol              = outbound_rule.value.protocol
      port_range            = outbound_rule.value.port_range
      destination_addresses = outbound_rule.value.destination_addresses
    }
  }
}

resource "digitalocean_volume" "this" {
  count = var.create_volume ? var.instance_count : 0

  region                  = var.region
  name                    = var.instance_count > 1 ? "${var.volume_name}-${count.index + 1}" : var.volume_name
  size                    = var.volume_size
  initial_filesystem_type = var.volume_filesystem_type
  description             = var.volume_description
  tags                    = var.tags
}

resource "digitalocean_volume_attachment" "this" {
  count = var.create_volume ? var.instance_count : 0

  droplet_id = digitalocean_droplet.this[count.index].id
  volume_id  = digitalocean_volume.this[count.index].id
}

resource "digitalocean_project_resources" "this" {
  count = var.project_id != null ? 1 : 0

  project   = var.project_id
  resources = digitalocean_droplet.this[*].urn
}
