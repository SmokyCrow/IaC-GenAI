resource "kubernetes_persistent_volume_claim" "this" {
  # Wait for binding only when the StorageClass binding mode is Immediate.
  # For WaitForFirstConsumer (e.g., k3s local-path), waiting can deadlock at apply time.
  wait_until_bound = var.volume_binding_mode == "Immediate"
  
  metadata {
    name      = var.name
    namespace = var.namespace
  }
  spec {
    access_modes = var.access_modes
    storage_class_name = var.storage_class_name
    resources {
      requests = { storage = var.storage }
    }
  }
}

