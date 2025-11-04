terraform {
  required_version = ">= 1.1.0"
  required_providers {
    null = {
      source  = "hashicorp/null"
      version = "3.2.4"
    }
  }
}

variable "vm_ips" {
  type = list(string)
}

variable "ipv4_subnet" {
  type        = string
  description = "IPv4 subnet for final network scan (e.g., 10.0.10.0/24)"
  default     = "10.0.10.0/24"
}

resource "null_resource" "wait_for_talos_api" {
  provisioner "local-exec" {
    command = <<-EOT
      echo "Checking Talos API readiness on port 50000..."

      VM_IPS=(${join(" ", var.vm_ips)})

      for ip in "$${VM_IPS[@]}"; do
        echo "Checking $ip:50000..."
        for i in {1..30}; do
          if nmap -Pn -n -p 50000 "$ip" | grep -q "50000.*open"; then
            echo "$ip:50000 is ready!"
            break
          fi
          echo "Waiting for $ip:50000... (attempt $i/30)"
          sleep 10
        done
      done

      echo "Final scan of ${var.ipv4_subnet} on port 50000:"
      nmap -Pn -n -p 50000 ${var.ipv4_subnet} -vv | grep 'Discovered'
    EOT
  }

  triggers = {
    vm_ips = join(",", var.vm_ips)
  }
}

