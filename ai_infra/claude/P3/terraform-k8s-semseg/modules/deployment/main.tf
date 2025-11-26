resource "kubernetes_deployment" "this" {
  metadata {
    name      = var.name
    namespace = var.namespace
    labels = {
      app = var.name
    }
  }

  spec {
    replicas = var.replicas

    selector {
      match_labels = {
        app = var.name
      }
    }

    template {
      metadata {
        labels = {
          app = var.name
        }
      }

      spec {
        container {
          name              = var.name
          image             = var.image
          image_pull_policy = var.image_pull_policy
          command           = var.command
          args              = var.args

          dynamic "port" {
            for_each = var.port != null ? [1] : []
            content {
              container_port = var.port
            }
          }

          dynamic "env" {
            for_each = var.environment
            content {
              name  = env.key
              value = env.value
            }
          }

          dynamic "volume_mount" {
            for_each = var.volumes
            content {
              name       = volume_mount.value.name
              mount_path = volume_mount.value.mount_path
            }
          }

          dynamic "resources" {
            for_each = var.resources != null ? [1] : []
            content {
              requests = var.resources.requests
              limits   = var.resources.limits
            }
          }

          dynamic "liveness_probe" {
            for_each = var.liveness_probe != null ? [1] : []
            content {
              http_get {
                path = var.liveness_probe.path
                port = var.liveness_probe.port
              }
              initial_delay_seconds = var.liveness_probe.initial_delay_seconds
              period_seconds        = var.liveness_probe.period_seconds
              timeout_seconds       = var.liveness_probe.timeout_seconds
              failure_threshold     = var.liveness_probe.failure_threshold
            }
          }

          dynamic "readiness_probe" {
            for_each = var.readiness_probe != null ? [1] : []
            content {
              http_get {
                path = var.readiness_probe.path
                port = var.readiness_probe.port
              }
              initial_delay_seconds = var.readiness_probe.initial_delay_seconds
              period_seconds        = var.readiness_probe.period_seconds
              timeout_seconds       = var.readiness_probe.timeout_seconds
              failure_threshold     = var.readiness_probe.failure_threshold
            }
          }
        }

        dynamic "volume" {
          for_each = var.volumes
          content {
            name = volume.value.name

            persistent_volume_claim {
              claim_name = volume.value.pvc_name
            }
          }
        }
      }
    }
  }
}
