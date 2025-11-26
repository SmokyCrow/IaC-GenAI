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
        dynamic "volume" {
          for_each = var.volumes
          content {
            name = volume.value.name
            persistent_volume_claim {
              claim_name = volume.value.claim_name
            }
          }
        }

        container {
          name              = var.name
          image             = var.image
          image_pull_policy = var.image_pull_policy

          port { container_port = var.container_port }

          # env and mounts are valid blocks — keep them dynamic
          dynamic "env" {
            for_each = var.env
            content {
              name  = env.key
              value = env.value
            }
          }

          dynamic "volume_mount" {
            for_each = var.volume_mounts
            content {
              name       = volume_mount.value.name
              mount_path = volume_mount.value.mount_path
              read_only  = try(volume_mount.value.read_only, false)
            }
          }

          # resources wants maps, not nested blocks
          resources {
            requests = try(var.resources.requests, null)
            limits   = try(var.resources.limits,   null)
          }

          # probes are valid blocks — keep them
          dynamic "readiness_probe" {
            for_each = var.readiness_probe == null ? [] : [var.readiness_probe]
            content {
              http_get { 
                path = readiness_probe.value.path
                port = readiness_probe.value.port 
              }
              initial_delay_seconds = readiness_probe.value.initial_delay_secs
              period_seconds        = readiness_probe.value.period_secs
              timeout_seconds       = readiness_probe.value.timeout_secs
              failure_threshold     = readiness_probe.value.failure_threshold
              success_threshold     = readiness_probe.value.success_threshold
            }
          }

          dynamic "liveness_probe" {
            for_each = var.liveness_probe == null ? [] : [var.liveness_probe]
            content {
              http_get { 
                path = liveness_probe.value.path
                port = liveness_probe.value.port 
              }
              initial_delay_seconds = liveness_probe.value.initial_delay_secs
              period_seconds        = liveness_probe.value.period_secs
              timeout_seconds       = liveness_probe.value.timeout_secs
              failure_threshold     = liveness_probe.value.failure_threshold
              success_threshold     = liveness_probe.value.success_threshold
            }
          }

          # ✅ command/args are attributes; set conditionally via null
          command = length(var.command) == 0 ? null : var.command
          args    = length(var.args)    == 0 ? null : var.args
        }
      }
    }
  }
}
