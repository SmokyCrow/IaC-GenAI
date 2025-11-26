# modules/service/main.tf
resource "kubernetes_service" "this" {
  metadata {
    name      = var.name
    namespace = var.namespace
    labels    = { app = var.name }
  }

  spec {
    selector = { app = var.name }
    type     = var.type

    port {
      port        = var.port
      target_port = var.target_port
      protocol    = "TCP"
      node_port   = var.type == "NodePort" && var.node_port != null ? var.node_port : null
    }
  }
}
