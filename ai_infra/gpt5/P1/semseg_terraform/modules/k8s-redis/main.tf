locals {
  base_labels = merge(
    {
      "app.kubernetes.io/name"       = var.name
      "app.kubernetes.io/instance"   = var.name
      "app.kubernetes.io/managed-by" = "terraform"
      "app.kubernetes.io/part-of"    = "semantic-segmenter"
    },
    var.labels
  )
}

# Use default k3s local-path storage class for single-node persistence.
resource "kubernetes_stateful_set" "this" {
  metadata {
    name      = var.name
    namespace = var.namespace
    labels    = local.base_labels
  }

  spec {
    service_name = var.name
    replicas     = 1

    selector {
      match_labels = local.base_labels
    }

    template {
      metadata {
        labels = local.base_labels
      }

      spec {
        container {
          name  = var.name
          image = var.image

          port {
            container_port = var.service_port
          }

          # Match main implementation behavior: enable AOF, disable RDB snapshots to reduce stalls
          args = ["--appendonly", "yes", "--save", ""]

          volume_mount {
            name       = "data"
            mount_path = "/data"
          }
        }
      }
    }

    volume_claim_template {
      metadata {
        name   = "data"
        labels = local.base_labels
      }
      spec {
        access_modes = ["ReadWriteOnce"]
        resources {
          requests = {
            storage = "${var.storage_gi}Gi"
          }
        }
        # storage_class_name left null to use cluster default (k3s local-path)
      }
    }
  }
}

resource "kubernetes_service" "this" {
  metadata {
    name      = var.name
    namespace = var.namespace
    labels    = local.base_labels
  }

  spec {
    type     = "ClusterIP"
    selector = local.base_labels

    port {
      name        = "redis"
      port        = var.service_port
      target_port = var.service_port
      protocol    = "TCP"
    }
  }
}

output "service_name" {
  value = kubernetes_service.this.metadata[0].name
}

output "service_port" {
  value = kubernetes_service.this.spec[0].port[0].port
}
