module "app" {
  source                 = "./modules/app"
  namespace              = var.namespace
  image_repo             = var.image_repo
  ingest_image           = var.ingest_image
  node_port_base         = var.node_port_base
  pvc_storage_class_name = var.pvc_storage_class_name
  pvc_volume_binding_mode = var.pvc_volume_binding_mode
  depends_on             = [kubernetes_namespace.app]
}

resource "kubernetes_namespace" "app" {
  metadata { name = var.namespace }
}
