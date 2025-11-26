provider "kubernetes" {
  config_path = var.kubeconfig_path
}

# Create namespace
resource "kubernetes_namespace" "semseg" {
  metadata {
    name = "semseg"
    labels = {
      app = "semantic-segmenter"
    }
  }
}

# Persistent Volume Claims
resource "kubernetes_persistent_volume_claim" "sub_pc_frames" {
  metadata {
    name      = "sub-pc-frames-pvc"
    namespace = kubernetes_namespace.semseg.metadata[0].name
  }
  spec {
    access_modes = ["ReadWriteOnce"]
    resources {
      requests = {
        storage = "10Gi"
      }
    }
  }
}

resource "kubernetes_persistent_volume_claim" "pc_frames" {
  metadata {
    name      = "pc-frames-pvc"
    namespace = kubernetes_namespace.semseg.metadata[0].name
  }
  spec {
    access_modes = ["ReadWriteOnce"]
    resources {
      requests = {
        storage = "50Gi"
      }
    }
  }
}

resource "kubernetes_persistent_volume_claim" "segments" {
  metadata {
    name      = "segments-pvc"
    namespace = kubernetes_namespace.semseg.metadata[0].name
  }
  spec {
    access_modes = ["ReadWriteOnce"]
    resources {
      requests = {
        storage = "100Gi"
      }
    }
  }
}

# Redis Deployment
resource "kubernetes_deployment" "redis" {
  metadata {
    name      = "redis"
    namespace = kubernetes_namespace.semseg.metadata[0].name
    labels = {
      app       = "redis"
      component = "cache"
    }
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app       = "redis"
        component = "cache"
      }
    }

    template {
      metadata {
        labels = {
          app       = "redis"
          component = "cache"
        }
      }

      spec {
        container {
          name  = "redis"
          image = var.redis_image
          image_pull_policy = "IfNotPresent"

          port {
            container_port = 6379
            name           = "redis"
          }

          resources {
            requests = {
              memory = "128Mi"
              cpu    = "100m"
            }
            limits = {
              memory = "256Mi"
              cpu    = "200m"
            }
          }
        }
      }
    }
  }
}

# Redis Service
resource "kubernetes_service" "redis" {
  metadata {
    name      = "redis"
    namespace = kubernetes_namespace.semseg.metadata[0].name
    labels = {
      app       = "redis"
      component = "cache"
    }
  }

  spec {
    type = "ClusterIP"

    selector = {
      app       = "redis"
      component = "cache"
    }

    port {
      port        = 6379
      target_port = 6379
      protocol    = "TCP"
      name        = "redis"
    }
  }
}

# Ingest API Deployment
resource "kubernetes_deployment" "ingest_api" {
  metadata {
    name      = "ingest-api"
    namespace = kubernetes_namespace.semseg.metadata[0].name
    labels = {
      app       = "ingest-api"
      component = "api"
    }
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app       = "ingest-api"
        component = "api"
      }
    }

    template {
      metadata {
        labels = {
          app       = "ingest-api"
          component = "api"
        }
      }

      spec {
        volume {
          name = "sub-pc-frames"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.sub_pc_frames.metadata[0].name
          }
        }

        container {
          name  = "ingest-api"
          image = var.ingest_image
          image_pull_policy = "IfNotPresent"

          port {
            container_port = 8080
            name           = "http"
          }

          env {
            name  = "INGEST_OUT_DIR"
            value = "/sub-pc-frames"
          }

          volume_mount {
            name       = "sub-pc-frames"
            mount_path = "/sub-pc-frames"
          }

          resources {
            requests = {
              memory = "256Mi"
              cpu    = "200m"
            }
            limits = {
              memory = "512Mi"
              cpu    = "500m"
            }
          }
        }
      }
    }
  }
}

# Ingest API Service
resource "kubernetes_service" "ingest_api" {
  metadata {
    name      = "ingest-api"
    namespace = kubernetes_namespace.semseg.metadata[0].name
    labels = {
      app       = "ingest-api"
      component = "api"
    }
  }

  spec {
    type = "NodePort"

    selector = {
      app       = "ingest-api"
      component = "api"
    }

    port {
      port        = 8080
      target_port = 8080
      node_port   = 30080
      protocol    = "TCP"
      name        = "http"
    }
  }
}

# Results API Deployment
resource "kubernetes_deployment" "results_api" {
  metadata {
    name      = "results-api"
    namespace = kubernetes_namespace.semseg.metadata[0].name
    labels = {
      app       = "results-api"
      component = "api"
    }
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app       = "results-api"
        component = "api"
      }
    }

    template {
      metadata {
        labels = {
          app       = "results-api"
          component = "api"
        }
      }

      spec {
        volume {
          name = "segments"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.segments.metadata[0].name
          }
        }

        container {
          name  = "results-api"
          image = var.shared_image
          image_pull_policy = "IfNotPresent"

          command = ["uvicorn"]
          args = ["services.results_api.app:app", "--host", "0.0.0.0", "--port", "8080", "--workers", "1"]

          port {
            container_port = 8080
            name           = "http"
          }

          env {
            name  = "SEGMENTS_DIR"
            value = "/segments"
          }

          env {
            name  = "REDIS_URL"
            value = "redis://redis.${kubernetes_namespace.semseg.metadata[0].name}.svc.cluster.local:6379"
          }

          env {
            name  = "REDIS_STREAM_FRAMES_CONVERTED"
            value = "s_frames_converted"
          }

          env {
            name  = "REDIS_STREAM_PARTS_LABELED"
            value = "s_parts_labeled"
          }

          env {
            name  = "REDIS_STREAM_REDACTED_DONE"
            value = "s_redacted_done"
          }

          env {
            name  = "REDIS_STREAM_ANALYTICS_DONE"
            value = "s_analytics_done"
          }

          volume_mount {
            name       = "segments"
            mount_path = "/segments"
          }

          resources {
            requests = {
              memory = "256Mi"
              cpu    = "200m"
            }
            limits = {
              memory = "512Mi"
              cpu    = "500m"
            }
          }
        }
      }
    }
  }
}

# Results API Service
resource "kubernetes_service" "results_api" {
  metadata {
    name      = "results-api"
    namespace = kubernetes_namespace.semseg.metadata[0].name
    labels = {
      app       = "results-api"
      component = "api"
    }
  }

  spec {
    type = "NodePort"

    selector = {
      app       = "results-api"
      component = "api"
    }

    port {
      port        = 8080
      target_port = 8080
      node_port   = 30081
      protocol    = "TCP"
      name        = "http"
    }
  }
}

# QA Web Deployment
resource "kubernetes_deployment" "qa_web" {
  metadata {
    name      = "qa-web"
    namespace = kubernetes_namespace.semseg.metadata[0].name
    labels = {
      app       = "qa-web"
      component = "frontend"
    }
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app       = "qa-web"
        component = "frontend"
      }
    }

    template {
      metadata {
        labels = {
          app       = "qa-web"
          component = "frontend"
        }
      }

      spec {
        container {
          name  = "qa-web"
          image = var.shared_image
          image_pull_policy = "IfNotPresent"

          command = ["uvicorn"]
          args = ["services.qa_web.app:app", "--host", "0.0.0.0", "--port", "3000", "--workers", "1"]

          port {
            container_port = 3000
            name           = "http"
          }

          env {
            name  = "RESULTS_API_URL"
            value = "http://results-api.${kubernetes_namespace.semseg.metadata[0].name}.svc.cluster.local:8080"
          }

          resources {
            requests = {
              memory = "128Mi"
              cpu    = "100m"
            }
            limits = {
              memory = "256Mi"
              cpu    = "200m"
            }
          }
        }
      }
    }
  }
}

# QA Web Service
resource "kubernetes_service" "qa_web" {
  metadata {
    name      = "qa-web"
    namespace = kubernetes_namespace.semseg.metadata[0].name
    labels = {
      app       = "qa-web"
      component = "frontend"
    }
  }

  spec {
    type = "NodePort"

    selector = {
      app       = "qa-web"
      component = "frontend"
    }

    port {
      port        = 3000
      target_port = 3000
      node_port   = 30000
      protocol    = "TCP"
      name        = "http"
    }
  }
}

# Convert PLY Worker Deployment
resource "kubernetes_deployment" "convert_ply" {
  metadata {
    name      = "convert-ply"
    namespace = kubernetes_namespace.semseg.metadata[0].name
    labels = {
      app       = "convert-ply"
      component = "worker"
    }
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app       = "convert-ply"
        component = "worker"
      }
    }

    template {
      metadata {
        labels = {
          app       = "convert-ply"
          component = "worker"
        }
      }

      spec {
        volume {
          name = "sub-pc-frames"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.sub_pc_frames.metadata[0].name
          }
        }

        volume {
          name = "pc-frames"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.pc_frames.metadata[0].name
          }
        }

        volume {
          name = "segments"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.segments.metadata[0].name
          }
        }

        container {
          name  = "convert-ply"
          image = var.shared_image
          image_pull_policy = "IfNotPresent"

          command = ["python3"]
          args = ["/semantic-segmenter/services/convert_service/convert-ply", "--in-dir", "/sub-pc-frames", "--out-dir", "/pc-frames", "--preview-out-dir", "/segments", "--delete-source", "--log-level", "info"]

          env {
            name  = "REDIS_URL"
            value = "redis://redis.${kubernetes_namespace.semseg.metadata[0].name}.svc.cluster.local:6379"
          }

          env {
            name  = "REDIS_STREAM_FRAMES_CONVERTED"
            value = "s_frames_converted"
          }

          env {
            name  = "PREVIEW_OUT_DIR"
            value = "/segments"
          }

          volume_mount {
            name       = "sub-pc-frames"
            mount_path = "/sub-pc-frames"
          }

          volume_mount {
            name       = "pc-frames"
            mount_path = "/pc-frames"
          }

          volume_mount {
            name       = "segments"
            mount_path = "/segments"
          }

          resources {
            requests = {
              memory = "512Mi"
              cpu    = "500m"
            }
            limits = {
              memory = "1Gi"
              cpu    = "1000m"
            }
          }
        }
      }
    }
  }
}

# Part Labeler Worker Deployment
resource "kubernetes_deployment" "part_labeler" {
  metadata {
    name      = "part-labeler"
    namespace = kubernetes_namespace.semseg.metadata[0].name
    labels = {
      app       = "part-labeler"
      component = "worker"
    }
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app       = "part-labeler"
        component = "worker"
      }
    }

    template {
      metadata {
        labels = {
          app       = "part-labeler"
          component = "worker"
        }
      }

      spec {
        volume {
          name = "pc-frames"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.pc_frames.metadata[0].name
          }
        }

        volume {
          name = "segments"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.segments.metadata[0].name
          }
        }

        container {
          name  = "part-labeler"
          image = var.shared_image
          image_pull_policy = "IfNotPresent"

          command = ["python3"]
          args = ["/semantic-segmenter/services/part_labeler/part_labeler.py", "--log-level", "info", "--out-dir", "/segments", "--colorized-dir", "/segments/labels", "--write-colorized"]

          env {
            name  = "REDIS_URL"
            value = "redis://redis.${kubernetes_namespace.semseg.metadata[0].name}.svc.cluster.local:6379"
          }

          env {
            name  = "REDIS_STREAM_PARTS_LABELED"
            value = "s_parts_labeled"
          }

          env {
            name  = "REDIS_STREAM_FRAMES_CONVERTED"
            value = "s_frames_converted"
          }

          env {
            name  = "REDIS_GROUP_PART_LABELER"
            value = "g_part_labeler"
          }

          volume_mount {
            name       = "pc-frames"
            mount_path = "/pc-frames"
          }

          volume_mount {
            name       = "segments"
            mount_path = "/segments"
          }

          resources {
            requests = {
              memory = "512Mi"
              cpu    = "500m"
            }
            limits = {
              memory = "1Gi"
              cpu    = "1000m"
            }
          }
        }
      }
    }
  }
}

# Redactor Worker Deployment
resource "kubernetes_deployment" "redactor" {
  metadata {
    name      = "redactor"
    namespace = kubernetes_namespace.semseg.metadata[0].name
    labels = {
      app       = "redactor"
      component = "worker"
    }
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app       = "redactor"
        component = "worker"
      }
    }

    template {
      metadata {
        labels = {
          app       = "redactor"
          component = "worker"
        }
      }

      spec {
        volume {
          name = "pc-frames"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.pc_frames.metadata[0].name
          }
        }

        volume {
          name = "segments"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.segments.metadata[0].name
          }
        }

        container {
          name  = "redactor"
          image = var.shared_image
          image_pull_policy = "IfNotPresent"

          command = ["python3"]
          args = ["/semantic-segmenter/services/redactor/redactor.py", "--log-level", "info", "--out-dir", "/segments"]

          env {
            name  = "REDIS_URL"
            value = "redis://redis.${kubernetes_namespace.semseg.metadata[0].name}.svc.cluster.local:6379"
          }

          env {
            name  = "REDIS_STREAM_PARTS_LABELED"
            value = "s_parts_labeled"
          }

          env {
            name  = "REDIS_STREAM_REDACTED_DONE"
            value = "s_redacted_done"
          }

          env {
            name  = "REDIS_GROUP_REDACTOR"
            value = "g_redactor"
          }

          volume_mount {
            name       = "pc-frames"
            mount_path = "/pc-frames"
          }

          volume_mount {
            name       = "segments"
            mount_path = "/segments"
          }

          resources {
            requests = {
              memory = "512Mi"
              cpu    = "500m"
            }
            limits = {
              memory = "1Gi"
              cpu    = "1000m"
            }
          }
        }
      }
    }
  }
}

# Analytics Worker Deployment
resource "kubernetes_deployment" "analytics" {
  metadata {
    name      = "analytics"
    namespace = kubernetes_namespace.semseg.metadata[0].name
    labels = {
      app       = "analytics"
      component = "worker"
    }
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app       = "analytics"
        component = "worker"
      }
    }

    template {
      metadata {
        labels = {
          app       = "analytics"
          component = "worker"
        }
      }

      spec {
        volume {
          name = "segments"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.segments.metadata[0].name
          }
        }

        container {
          name  = "analytics"
          image = var.shared_image
          image_pull_policy = "IfNotPresent"

          command = ["python3"]
          args = ["/semantic-segmenter/services/analytics/analytics.py", "--log-level", "info", "--out-dir", "/segments"]

          env {
            name  = "REDIS_URL"
            value = "redis://redis.${kubernetes_namespace.semseg.metadata[0].name}.svc.cluster.local:6379"
          }

          env {
            name  = "REDIS_STREAM_PARTS_LABELED"
            value = "s_parts_labeled"
          }

          env {
            name  = "REDIS_STREAM_ANALYTICS_DONE"
            value = "s_analytics_done"
          }

          env {
            name  = "REDIS_GROUP_ANALYTICS"
            value = "g_analytics"
          }

          volume_mount {
            name       = "segments"
            mount_path = "/segments"
          }

          resources {
            requests = {
              memory = "512Mi"
              cpu    = "500m"
            }
            limits = {
              memory = "1Gi"
              cpu    = "1000m"
            }
          }
        }
      }
    }
  }
}
