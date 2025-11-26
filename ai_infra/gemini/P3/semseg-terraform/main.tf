# Configure the Kubernetes provider
provider "kubernetes" {
  # If var.kubeconfig is null, the provider will use its default
  # resolution (e.g., KUBECONFIG env var or ~/.kube/config)
  config_path = var.kubeconfig
}

# Create the namespace for the application
resource "kubernetes_namespace" "app_namespace" {
  metadata {
    name = var.namespace
  }
}

# Deploy the entire application stack using the 'app' module
module "app" {
  source = "./modules/app"

  # Pass all root variables to the app module
  namespace                = kubernetes_namespace.app_namespace.metadata[0].name
  image_repo               = var.image_repo
  ingest_image             = var.ingest_image
  node_port_base           = var.node_port_base
  pvc_storage_class_name   = var.pvc_storage_class_name
}