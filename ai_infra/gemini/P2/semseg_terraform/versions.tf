# We pin the provider versions to ensure consistent behavior.
# This configuration assumes you have a valid kubeconfig context
# pointed at your Docker Desktop Kubernetes cluster.
terraform {
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.30.0"
    }
  }
}

provider "kubernetes" {
  config_path = "~/.kube/config"
}