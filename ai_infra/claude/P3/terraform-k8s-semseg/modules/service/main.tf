resource "kubernetes_service" "this" {
  metadata {
    name      = var.name
    namespace = var.namespace
  }

  spec {
    selector = {
      app = var.selector_app
    }

    type = var.type

    port {
      port        = var.port
      target_port = var.target_port
      node_port   = var.type == "NodePort" ? var.node_port : null
    }
  }
}
