resource "kubernetes_service" "this" {
  metadata {
    name      = var.name
    namespace = var.namespace
    labels = {
      app = var.name
    }
  }

  spec {
    type = var.service_type

    selector = var.selector

    port {
      port        = var.port
      target_port = var.target_port
      node_port   = var.service_type == "NodePort" ? var.node_port : null
    }
  }
}
