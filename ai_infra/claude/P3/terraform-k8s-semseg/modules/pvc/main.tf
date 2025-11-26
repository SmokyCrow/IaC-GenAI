resource "kubernetes_persistent_volume_claim" "this" {
  wait_until_bound = var.wait_until_bound

  metadata {
    name      = var.name
    namespace = var.namespace
  }

  spec {
    access_modes       = var.access_modes
    storage_class_name = var.storage_class_name

    resources {
      requests = {
        storage = var.storage
      }
    }
  }
}
