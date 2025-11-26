provider "kubernetes" {
  config_path = var.kubeconfig != null ? var.kubeconfig : pathexpand("~/.kube/config")
}

# Create (or ensure) the target namespace exists first
resource "kubernetes_namespace" "ns" {
  metadata {
    name = var.namespace
  }
}

module "app" {
  source = "./modules/app"

  namespace               = var.namespace
  image_repo              = var.image_repo
  ingest_image            = var.ingest_image
  node_port_base          = var.node_port_base
  pvc_storage_class_name  = var.pvc_storage_class_name

  # Ensure namespace is created before resources inside module
  depends_on = [kubernetes_namespace.ns]
}
