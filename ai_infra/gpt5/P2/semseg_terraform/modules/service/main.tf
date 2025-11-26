resource "kubernetes_service" "this" {
  metadata {
    name      = var.name
    namespace = var.namespace
    labels = {
      app = var.name
    }
  }

  spec {
    selector = var.selector
    type     = var.service_type

    port {
      name        = "http"
      port        = var.port
      target_port = var.target_port
      node_port   = var.service_type == "NodePort" ? var.node_port : null
      protocol    = "TCP"
    }
  }
}
