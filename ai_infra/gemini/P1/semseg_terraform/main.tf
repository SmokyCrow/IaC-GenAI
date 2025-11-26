# Define a local constant for the namespace name
locals {
  namespace_name = "semseg"
}

# Configure the Kubernetes provider
provider "kubernetes" {
  config_path = var.kubeconfig
}

# 1. Create the Namespace
resource "kubernetes_namespace" "semseg" {
  metadata {
    name = local.namespace_name
  }
}

# 2. Define and Create Persistent Volume Claims
locals {
  # Define all PVCs in one place
  pvcs = {
    "sub-pc-frames-pvc" = { size = var.storage_sub_pc_frames }
    "pc-frames-pvc"     = { size = var.storage_pc_frames }
    "segments-pvc"      = { size = var.storage_segments }
    "redis-data-pvc"    = { size = var.storage_redis }
  }
}

resource "kubernetes_persistent_volume_claim" "main" {
  for_each = local.pvcs

  metadata {
    name      = each.key
    namespace = local.namespace_name
  }
  spec {
    access_modes       = ["ReadWriteOnce"] # Required for Docker Desktop
    resources {
      requests = {
        storage = each.value.size
      }
    }
  }
}

# 3. Define Deployment and Service Data
locals {
  # --- Dynamic Internal URLs ---
  redis_service_url = "redis://redis.${local.namespace_name}.svc.cluster.local:6379/0"
  results_api_url   = "http://results-api.${local.namespace_name}.svc.cluster.local:8080"

  # --- Volume Definitions ---
  # Define reusable volume structures to pass to deployments
  volumes = {
    sub_pc_frames = {
      name       = "data-sub-pc-frames"
      claim_name = kubernetes_persistent_volume_claim.main["sub-pc-frames-pvc"].metadata[0].name
      mount_path = "/sub-pc-frames"
    }
    pc_frames = {
      name       = "data-pc-frames"
      claim_name = kubernetes_persistent_volume_claim.main["pc-frames-pvc"].metadata[0].name
      mount_path = "/pc-frames"
    }
    segments = {
      name       = "data-segments"
      claim_name = kubernetes_persistent_volume_claim.main["segments-pvc"].metadata[0].name
      mount_path = "/segments"
    }
    redis_data = {
      name       = "data-redis"
      claim_name = kubernetes_persistent_volume_claim.main["redis-data-pvc"].metadata[0].name
      mount_path = "/data" # Standard for Redis container
    }
  }

  # --- Deployment Definitions ---
  deployments = {
    "ingest-api" = {
      image      = var.ingest_image
      port       = 8080
      probe_type = "tcp"
      env_vars   = {}
      volumes    = [local.volumes.sub_pc_frames]
      args       = [] # No args specified
    }
    "results-api" = {
      image      = var.shared_image
      port       = 8080
      probe_type = "tcp"
      env_vars = {
        "REDIS_URL"                       = local.redis_service_url
        "REDIS_STREAM_FRAMES_CONVERTED" = var.redis_stream_frames_converted
        "REDIS_STREAM_PARTS_LABELED"    = var.redis_stream_parts_labeled
        "REDIS_STREAM_REDACTED_DONE"    = var.redis_stream_redacted_done
        "REDIS_STREAM_ANALYTICS_DONE"   = var.redis_stream_analytics_done
      }
      volumes = [local.volumes.segments]
      # --- NEW: Add application arguments ---
      args = [
        "uvicorn", "services.results_api.app:app",
        "--host", "0.0.0.0",
        "--port", "8080",
        "--workers", "1"
      ]
    }
    "qa-web" = {
      image      = var.shared_image
      # --- UPDATED: Port changed from 80 to 3000 to match args ---
      port       = 3000
      probe_type = "http"
      probe_path = "/"
      env_vars = {
        "RESULTS_API_URL" = local.results_api_url
      }
      volumes = []
      # --- NEW: Add application arguments ---
      args = [
        "uvicorn", "services.qa_web.app:app",
        "--host", "0.0.0.0",
        "--port", "3000",
        "--workers", "1"
      ]
    }
    "convert-ply" = {
      image      = var.shared_image
      port       = null
      probe_type = null
      env_vars = {
        "REDIS_URL"                       = local.redis_service_url
        "REDIS_STREAM_FRAMES_CONVERTED" = var.redis_stream_frames_converted
      }
      volumes = [
        local.volumes.sub_pc_frames,
        local.volumes.pc_frames,
        local.volumes.segments
      ]
      # --- NEW: Add application arguments ---
      args = [
        "python3", "/semantic-segmenter/services/convert_service/convert-ply",
        "--in-dir", "/sub-pc-frames",
        "--out-dir", "/pc-frames",
        "--preview-out-dir", "/segments",
        "--delete-source",
        "--log-level", "info"
      ]
    }
    "part-labeler" = {
      image      = var.shared_image
      port       = null
      probe_type = null
      env_vars = {
        "REDIS_URL"                       = local.redis_service_url
        "REDIS_STREAM_PARTS_LABELED"    = var.redis_stream_parts_labeled
        "REDIS_STREAM_FRAMES_CONVERTED" = var.redis_stream_frames_converted
        "REDIS_GROUP_PART_LABELER"      = var.redis_group_part_labeler
      }
      volumes = [
        local.volumes.pc_frames,
        local.volumes.segments
      ]
      # --- NEW: Add application arguments ---
      args = [
        "python3", "/semantic-segmenter/services/part_labeler/part_labeler.py",
        "--log-level", "info",
        "--out-dir", "/segments",
        "--colorized-dir", "/segments/labels",
        "--write-colorized"
      ]
    }
    "redactor" = {
      image      = var.shared_image
      port       = null
      probe_type = null
      env_vars = {
        "REDIS_URL"                    = local.redis_service_url
        "REDIS_STREAM_PARTS_LABELED" = var.redis_stream_parts_labeled
        "REDIS_STREAM_REDACTED_DONE" = var.redis_stream_redacted_done
        "REDIS_GROUP_REDACTOR"       = var.redis_group_redactor
      }
      volumes = [
        local.volumes.pc_frames,
        local.volumes.segments
      ]
      # --- NEW: Add application arguments ---
      args = [
        "python3", "/semantic-segmenter/services/redactor/redactor.py",
        "--log-level", "info",
        "--out-dir", "/segments"
      ]
    }
    "analytics" = {
      image      = var.shared_image
      port       = null
      probe_type = null
      env_vars = {
        "REDIS_URL"                   = local.redis_service_url
        "REDIS_STREAM_PARTS_LABELED"  = var.redis_stream_parts_labeled
        "REDIS_STREAM_ANALYTICS_DONE" = var.redis_stream_analytics_done
        "REDIS_GROUP_ANALYTICS"       = var.redis_group_analytics
      }
      volumes = [local.volumes.segments]
      # --- NEW: Add application arguments ---
      args = [
        "python3", "/semantic-segmenter/services/analytics/analytics.py",
        "--log-level", "info",
        "--out-dir", "/segments"
      ]
    }
    "redis" = {
      image      = var.redis_image
      port       = 6379
      probe_type = "tcp"
      env_vars   = {}
      volumes    = [local.volumes.redis_data]
      args       = [] # No args specified
    }
  }

  # --- Service Definitions ---
  services = {
    "ingest-api"  = { type = "NodePort", port = 8080 }
    "results-api" = { type = "NodePort", port = 8080 }
    "qa-web"      = { type = "NodePort", port = 80 } # Service port 80, container port 3000
    "redis"       = { type = "ClusterIP", port = 6379 }
  }
}

# 4. Create Deployments
resource "kubernetes_deployment" "apps" {

  depends_on = [
    kubernetes_service.svcs,
    kubernetes_persistent_volume_claim.main
  ]

  for_each = local.deployments

  metadata {
    name      = each.key
    namespace = local.namespace_name
    labels = {
      app = each.key
    }
  }

  spec {
    replicas = 1
    selector {
      match_labels = {
        app = each.key
      }
    }
    template {
      metadata {
        labels = {
          app = each.key
        }
      }
      spec {
        # --- Pod-level Volume Definitions ---
        dynamic "volume" {
          for_each = lookup(each.value, "volumes", [])
          content {
            name = volume.value.name
            persistent_volume_claim {
              claim_name = volume.value.claim_name
            }
          }
        }

        container {
          name  = each.key
          image = each.value.image
          image_pull_policy = "IfNotPresent"

          # --- NEW: Add container arguments from locals map ---
          args = each.value.args

          # --- Dynamic "env" block ---
          dynamic "env" {
            for_each = lookup(each.value, "env_vars", {})
            content {
              name  = env.key
              value = env.value
            }
          }

          # --- Container-level Volume Mounts ---
          dynamic "volume_mount" {
            for_each = lookup(each.value, "volumes", [])
            content {
              name       = volume_mount.value.name
              # --- FIX: Changed "path" to "mount_path" to match the local.volumes map ---
              mount_path = volume_mount.value.mount_path
            }
          }

          # --- Dynamic "port" block ---
          dynamic "port" {
            for_each = each.value.port != null ? [each.value.port] : []
            content {
              container_port = port.value
            }
          }

          # --- Readiness Probe ---
          dynamic "readiness_probe" {
            for_each = each.value.probe_type != null ? [1] : []
            content {
              dynamic "tcp_socket" {
                for_each = each.value.probe_type == "tcp" ? [1] : []
                content {
                  port = each.value.port
                }
              }
              dynamic "http_get" {
                for_each = each.value.probe_type == "http" ? [1] : []
                content {
                  path = lookup(each.value, "probe_path", "/")
                  port = each.value.port
                }
              }
              initial_delay_seconds = 10
              period_seconds        = 10
            }
          }
        } # end container
      } # end spec
    } # end template
  } # end spec
}

# 5. Create Services
resource "kubernetes_service" "svcs" {
  # Create a service for each key in local.services,
  # but only if a deployment exists with the same name.
  for_each = { for k, v in local.services : k => v if contains(keys(local.deployments), k) }

  metadata {
    name      = each.key
    namespace = local.namespace_name
  }

  spec {
    type = each.value.type
    selector = {
      app = each.key
    }
    port {
      port = each.value.port
      # --- UPDATED: This now correctly maps service port to container port ---
      # e.g., qa-web: 80 -> 3000
      # e.g., results-api: 8080 -> 8080
      target_port = local.deployments[each.key].port
    }
  }
}