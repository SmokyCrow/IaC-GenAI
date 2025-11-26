resource "kubernetes_service" "svc" {
  metadata {
    name      = var.name
    namespace = var.namespace
  }
  spec {
    type = var.service_type
    selector = {
      app = var.selector_app
    }
    port {
      name        = "http" # Name the port for clarity
      port        = var.port
      target_port = var.target_port
      # Only add node_port if type is NodePort
      node_port = var.service_type == "NodePort" ? var.node_port : null
    }
  }
}