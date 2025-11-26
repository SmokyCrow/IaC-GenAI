resource "kubernetes_deployment" "this" {
  metadata {
    name      = var.name
    namespace = var.namespace
    labels = { app = var.name }
  }

  spec {
    replicas = var.replicas

    selector {
      match_labels = { app = var.name }
    }

    template {
      metadata { labels = { app = var.name } }

      spec {
        container {
          name  = var.name
          image = var.image
          image_pull_policy = "IfNotPresent"

          # ✅ NEW: command & args (only set if provided)
          command = length(var.command) > 0 ? var.command : null
          args    = length(var.args)    > 0 ? var.args    : null

          dynamic "port" {
            for_each = var.port == null ? [] : [var.port]
            content { container_port = port.value }
          }

          dynamic "env" {
            for_each = var.env
            content {
              name  = env.key
              value = env.value
            }
          }

          dynamic "readiness_probe" {
            for_each = var.readiness_path == null ? [] : [var.readiness_path]
            content {
              http_get {
                path = var.readiness_path
                port = var.port
              }
              initial_delay_seconds = 3
              period_seconds        = 5
            }
          }

          dynamic "liveness_probe" {
            for_each = var.liveness_path == null ? [] : [var.liveness_path]
            content {
              http_get {
                path = var.liveness_path
                port = var.port
              }
              initial_delay_seconds = 5
              period_seconds        = 10
            }
          }

          dynamic "volume_mount" {
            for_each = var.volume_mounts
            content {
              name       = volume_mount.value.name
              mount_path = volume_mount.value.mount_path
              read_only  = lookup(volume_mount.value, "read_only", false)
            }
          }
        }

        dynamic "volume" {
          for_each = var.volume_claims
          content {
            name = volume.value.name
            persistent_volume_claim { claim_name = volume.value.claim }
          }
        }
      }
    }
  }
}
