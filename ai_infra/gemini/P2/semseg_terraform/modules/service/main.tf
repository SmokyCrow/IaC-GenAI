resource "kubernetes_service" "service" {
  metadata {
    name      = var.name
    namespace = var.namespace
    labels = {
      app = var.name
    }
  }
  spec {
    selector = {
      app = var.selector_app
    }
    type = var.type

    dynamic "port" {
      for_each = var.ports
      content {
        name        = "${port.value.port}-tcp"
        port        = port.value.port
        target_port = port.value.target_port
        node_port   = var.type == "NodePort" ? port.value.node_port : null
      }
    }
  }
}