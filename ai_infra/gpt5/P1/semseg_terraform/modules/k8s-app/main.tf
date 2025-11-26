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

resource "kubernetes_deployment" "this" {
  metadata {
    name      = var.name
    namespace = var.namespace
    labels    = local.base_labels
  }

  spec {
    replicas = var.replicas

    selector {
      match_labels = local.base_labels
    }

    template {
      metadata {
        labels      = local.base_labels
        annotations = var.extra_annotations
      }

      spec {
        dynamic "volume" {
          for_each = var.pvc_mounts
          content {
            name = volume.key
            persistent_volume_claim {
              claim_name = volume.key
            }
          }
        }
        
        container {
          name              = var.name
          image             = var.image
          image_pull_policy = var.image_pull_policy

          dynamic "port" {
            for_each = var.container_port > 0 ? [1] : []
            content {
              container_port = var.container_port
            }
          }

          dynamic "env" {
            for_each = var.env
            content {
              name  = env.key
              value = env.value
            }
          }

          dynamic "volume_mount" {
            for_each = var.pvc_mounts
            content {
              name       = volume_mount.key
              mount_path = volume_mount.value
            }
          }

          # Use defaults; resources/liveness/readiness are intentionally omitted per request.
          # Add them later if desired.

          # Correct way to set command/args with provider:
          command = length(var.command) > 0 ? var.command : null
          args    = length(var.args) > 0 ? var.args : null
        }
      }
    }
  }
}

# Service (optional)
resource "kubernetes_service" "this" {
  count = var.service_enabled ? 1 : 0

  metadata {
    name      = var.name
    namespace = var.namespace
    labels    = local.base_labels
  }

  spec {
    selector = local.base_labels
    type     = var.service_type

    port {
      port        = var.service_port
      target_port = var.container_port > 0 ? var.container_port : var.service_port
      protocol    = "TCP"
      node_port   = var.service_type == "NodePort" && var.node_port != 0 ? var.node_port : null
    }
  }
}

output "name" {
  value = var.name
}

output "service_name" {
  value = var.service_enabled ? kubernetes_service.this[0].metadata[0].name : null
}

output "service_port" {
  value = var.service_enabled ? kubernetes_service.this[0].spec[0].port[0].port : null
}

output "node_port" {
  value = var.service_enabled && var.service_type == "NodePort" ? kubernetes_service.this[0].spec[0].port[0].node_port : null
}
