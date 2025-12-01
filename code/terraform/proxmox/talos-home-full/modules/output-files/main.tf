# Save kubeconfig to local file
resource "local_file" "kubeconfig" {
  content  = var.kubeconfig_raw
  filename = "${var.output_dir}/kubeconfig"
}

# Save secrets to local file (equivalent to talosctl gen secrets)
resource "local_file" "secrets" {
  content = yamlencode({
    version = "v1alpha1"
    cluster = {
      id     = var.machine_secrets.cluster.id
      secret = var.machine_secrets.cluster.secret
    }
    secrets = {
      bootstraptoken            = var.machine_secrets.secrets.bootstrap_token
      secretboxencryptionsecret = var.machine_secrets.secrets.secretbox_encryption_secret
      aescbcencryptionsecret    = var.machine_secrets.secrets.aescbc_encryption_secret
    }
    trustdinfo = {
      token = var.machine_secrets.trustdinfo.token
    }
    certs = {
      os = {
        crt = var.machine_secrets.certs.os.cert
        key = var.machine_secrets.certs.os.key
      }
      k8s = {
        crt = var.machine_secrets.certs.k8s.cert
        key = var.machine_secrets.certs.k8s.key
      }
      k8saggregator = {
        crt = var.machine_secrets.certs.k8s_aggregator.cert
        key = var.machine_secrets.certs.k8s_aggregator.key
      }
      k8sserviceaccount = {
        key = var.machine_secrets.certs.k8s_serviceaccount.key
      }
      etcd = {
        crt = var.machine_secrets.certs.etcd.cert
        key = var.machine_secrets.certs.etcd.key
      }
    }
  })
  filename = "${var.output_dir}/secrets.yaml"
}
