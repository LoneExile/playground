resource "null_resource" "wait_for_talos_api" {
  count = length(var.vm_ips)

  triggers = {
    vm_ip = var.vm_ips[count.index]
  }

  provisioner "local-exec" {
    command = <<-EOT
      for i in $(seq 1 ${var.max_retries}); do
        if nc -z ${var.vm_ips[count.index]} ${var.talos_api_port} 2>/dev/null; then
          echo "Talos API is ready on ${var.vm_ips[count.index]}"
          exit 0
        fi
        echo "Waiting for Talos API on ${var.vm_ips[count.index]} (attempt $i/${var.max_retries})..."
        sleep ${var.retry_interval}
      done
      echo "Timeout waiting for Talos API on ${var.vm_ips[count.index]}"
      exit 1
    EOT
  }
}
