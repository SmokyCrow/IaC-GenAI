resource "kubernetes_persistent_volume_claim" "this" {
  metadata {
    name      = var.name
    namespace = var.namespace
  }

  wait_until_bound = var.wait_until_bound

  spec {
    access_modes = ["ReadWriteOnce"]
    storage_class_name = var.storage_class_name

    resources {
      requests = {
        storage = var.size
      }
    }
  }
}
