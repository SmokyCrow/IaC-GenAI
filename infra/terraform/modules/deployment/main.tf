resource "kubernetes_deployment" "this" {
  metadata {
    name      = var.name
    namespace = var.namespace
    labels    = var.labels
  }
  spec {
    replicas = var.replicas
    selector {
      match_labels = var.labels
    }
    template {
      metadata {
        labels = var.labels
      }
      spec {
        container {
          name              = coalesce(var.container_name, var.name)
          image             = var.image
          image_pull_policy = var.image_pull_policy

          dynamic "port" {
            for_each = var.container_ports
            content {
              container_port = port.value
            }
          }

          dynamic "env" {
            for_each = var.env
            content {
              name  = env.key
              value = env.value
            }
          }

          command = var.command
          args    = var.args

          dynamic "readiness_probe" {
            for_each = length(var.readiness_exec) > 0 || var.readiness_http != null ? [1] : []
            content {
              dynamic "http_get" {
                for_each = var.readiness_http != null ? [var.readiness_http] : []
                content {
                  path = http_get.value.path
                  port = http_get.value.port
                }
              }
              dynamic "exec" {
                for_each = length(var.readiness_exec) > 0 ? [1] : []
                content {
                  command = var.readiness_exec
                }
              }
              initial_delay_seconds = var.readiness_initial_delay_seconds
              period_seconds        = var.readiness_period_seconds
            }
          }

          dynamic "liveness_probe" {
            for_each = var.liveness_http != null ? [1] : []
            content {
              http_get {
                path = var.liveness_http.path
                port = var.liveness_http.port
              }
              initial_delay_seconds = var.liveness_initial_delay_seconds
              period_seconds        = var.liveness_period_seconds
            }
          }

          dynamic "volume_mount" {
            for_each = var.volume_mounts
            content {
              name       = volume_mount.value.name
              mount_path = volume_mount.value.mount_path
            }
          }
        }

        dynamic "volume" {
          for_each = var.volumes
          content {
            name = volume.value.name
            persistent_volume_claim {
              claim_name = volume.value.claim_name
            }
          }
        }
      }
    }
  }

}

