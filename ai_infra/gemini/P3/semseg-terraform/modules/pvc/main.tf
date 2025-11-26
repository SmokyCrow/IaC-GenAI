resource "kubernetes_persistent_volume_claim" "pvc" {
  metadata {
    name      = var.name
    namespace = var.namespace
  }
  spec {
    access_modes = var.access_modes
    resources {
      requests = {
        storage = var.storage_size
      }
    }
    storage_class_name = var.storage_class_name
  }
  # This is critical for CI/CD and rapid apply/destroy cycles,
  # especially when a scheduler isn't immediately binding it.
  wait_until_bound = var.wait_until_bound
}