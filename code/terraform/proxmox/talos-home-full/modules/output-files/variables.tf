variable "kubeconfig_raw" {
  description = "Raw kubeconfig content"
  type        = string
  sensitive   = true
}

variable "machine_secrets" {
  description = "Talos machine secrets"
  type        = any
  sensitive   = true
}

variable "output_dir" {
  description = "Directory to save output files"
  type        = string
}
