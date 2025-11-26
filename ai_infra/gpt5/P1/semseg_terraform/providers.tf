provider "kubernetes" {
  # For single-node k3s on Ubuntu, this is the default kubeconfig path.
  # If running terraform as a non-root user, you may need to copy/chgrp this file.
  config_path = var.kubeconfig_path
}
