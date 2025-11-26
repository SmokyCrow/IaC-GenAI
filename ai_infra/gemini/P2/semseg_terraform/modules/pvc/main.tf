resource "kubernetes_persistent_volume_claim" "pvc" {
  metadata {
    name      = var.name
    namespace = var.namespace
  }
  spec {
    access_modes       = ["ReadWriteOnce"] # Sufficient for hostpath
    storage_class_name = var.storage_class_name
    resources {
      requests = {
        storage = var.size
      }
    }
  }
  wait_until_bound = var.wait_until_bound
}