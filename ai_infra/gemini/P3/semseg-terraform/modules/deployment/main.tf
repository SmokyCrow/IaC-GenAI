resource "kubernetes_deployment" "dep" {
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
        dynamic "volume" {
          for_each = var.volumes
          content {
            name = volume.value.name
            persistent_volume_claim {
              claim_name = volume.value.pvc_claim
            }
          }
        }

        container {
          name  = var.name
          image = var.image

          # Use "IfNotPresent" to support local images in Docker Desktop
          image_pull_policy = var.image_pull_policy

          # Only add port block if container_port is specified
          dynamic "port" {
            for_each = var.container_port != null ? [var.container_port] : []
            content {
              container_port = port.value
            }
          }

          # --- FIX ---
          # 'command' and 'args' are not blocks, they are attributes.
          # Assign them directly, using a ternary to respect the null default.
          command = var.command != null ? var.command : null
          args    = var.args != null ? var.args : null
          # --- END FIX ---

          # Add environment variables
          dynamic "env" {
            for_each = var.env_vars
            content {
              name  = env.key
              value = env.value
            }
          }

          # Add volume mounts
          dynamic "volume_mount" {
            for_each = var.volume_mounts
            content {
              name       = volume_mount.value.name
              mount_path = volume_mount.value.mount_path
            }
          }

          # Optional resources block
          dynamic "resources" {
            for_each = var.resources != null ? [var.resources] : []
            content {
              requests = lookup(resources.value, "requests", null)
              limits   = lookup(resources.value, "limits", null)
            }
          }

          # Optional liveness probe
          dynamic "liveness_probe" {
            for_each = var.liveness_probe != null ? [var.liveness_probe] : []
            content {
              http_get {
                path = liveness_probe.value.path
                port = liveness_probe.value.port
              }
              initial_delay_seconds = lookup(liveness_probe.value, "initial_delay", 15)
              period_seconds        = lookup(liveness_probe.value, "period", 20)
              timeout_seconds       = lookup(liveness_probe.value, "timeout", 1)
              success_threshold     = 1
              failure_threshold     = 3
            }
          }

          # Optional readiness probe
          dynamic "readiness_probe" {
            for_each = var.readiness_probe != null ? [var.readiness_probe] : []
            content {
              http_get {
                path = readiness_probe.value.path
                port = readiness_probe.value.port
              }
              initial_delay_seconds = lookup(readiness_probe.value, "initial_delay", 5)
              period_seconds        = lookup(readiness_probe.value, "period", 10)
              timeout_seconds       = lookup(readiness_probe.value, "timeout", 1)
              success_threshold     = 1
              failure_threshold     = 3
            }
          }
        }
      }
    }
  }
}