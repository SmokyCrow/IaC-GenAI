resource "kubernetes_persistent_volume_claim" "this" {
  wait_until_bound = false

  metadata {
    name      = var.name
    namespace = var.namespace
  }

  spec {
    access_modes       = var.access_modes
    storage_class_name = var.storage_class_name

    resources {
      requests = {
        storage = var.size
      }
    }
  }
}
