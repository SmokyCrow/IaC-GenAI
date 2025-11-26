resource "kubernetes_deployment" "deployment" {
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
              claim_name = volume.value.persistent_volume_claim.claim_name
            }
          }
        }

        container {
          name              = var.name
          image             = var.image
          image_pull_policy = var.image_pull_policy
          command           = var.command
          args              = var.args
          dynamic "port" {
            for_each = var.container_port != null ? [var.container_port] : []
            content {
              container_port = port.value
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

          dynamic "liveness_probe" {
            for_each = var.probes.enabled ? [1] : []
            content {
              http_get {
                path = var.probes.path
                port = var.probes.port != null ? var.probes.port : var.container_port
              }
              initial_delay_seconds = 15
              period_seconds        = 10
            }
          }

          dynamic "readiness_probe" {
            for_each = var.probes.enabled ? [1] : []
            content {
              http_get {
                path = var.probes.path
                port = var.probes.port != null ? var.probes.port : var.container_port
              }
              initial_delay_seconds = 5
              period_seconds        = 5
            }
          }
        }
      }
    }
  }
}