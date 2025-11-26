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
            for_each = var.container_port != null ? [1] : []
            content {
              container_port = var.container_port
            }
          }

          dynamic "env" {
            for_each = var.env_vars
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
            }
          }

          dynamic "readiness_probe" {
            for_each = var.readiness_probe != null ? [var.readiness_probe] : []
            content {
              http_get {
                path = readiness_probe.value.http_get.path
                port = readiness_probe.value.http_get.port
              }
              initial_delay_seconds = readiness_probe.value.initial_delay_seconds
              period_seconds        = readiness_probe.value.period_seconds
            }
          }

          dynamic "liveness_probe" {
            for_each = var.liveness_probe != null ? [var.liveness_probe] : []
            content {
              http_get {
                path = liveness_probe.value.http_get.path
                port = liveness_probe.value.http_get.port
              }
              initial_delay_seconds = liveness_probe.value.initial_delay_seconds
              period_seconds        = liveness_probe.value.period_seconds
            }
          }
        }

        dynamic "volume" {
          for_each = var.volume_mounts
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
