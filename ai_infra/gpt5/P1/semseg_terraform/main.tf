# Namespace
module "ns" {
  source = "./modules/k8s-namespace"
  name   = var.namespace
  create = true
}

# ------------------------
# Services that need an external port
# - qa-web: NodePort for browser access on single-node k3s
# Internal services: ClusterIP (default)
# ------------------------

# ingest-api (ClusterIP)
module "ingest_api" {
  source            = "./modules/k8s-app"
  name              = "ingest-api"
  namespace         = module.ns.name
  image             = var.ingest_image
  image_pull_policy = var.image_pull_policy

  labels = {
    app       = "semseg"
    component = "ingest-api"
  }

  env = {
    INGEST_OUT_DIR = "/sub-pc-frames"
  }

  container_port = 8080

  service_enabled = true
  service_port    = 8080
  service_type    = "NodePort"
  node_port       = 32081
  pvc_mounts = {
    "sub-pc-frames-pvc" = "/sub-pc-frames"
  }

}

# results-api (ClusterIP)
module "results_api" {
  source            = "./modules/k8s-app"
  name              = "results-api"
  namespace         = module.ns.name
  image             = var.shared_image
  image_pull_policy = var.image_pull_policy

  labels = {
    app       = "semseg"
    component = "results-api"
  }

  env = {
    SEGMENTS_DIR                  = "/segments"
    REDIS_URL                     = "redis://redis.semseg.svc.cluster.local:6379/0"
    REDIS_STREAM_FRAMES_CONVERTED = "s_frames_converted"
    REDIS_STREAM_PARTS_LABELED    = "s_parts_labeled"
    REDIS_STREAM_REDACTED_DONE    = "s_redacted_done"
    REDIS_STREAM_ANALYTICS_DONE   = "s_analytics_done"
  }

  command = ["/bin/sh", "-c"]
  args    = ["uvicorn services.results_api.app:app --host 0.0.0.0 --port 8080 --workers 1"]

  container_port  = 8080
  service_enabled = true
  service_port    = 8080
  service_type    = "ClusterIP"

  pvc_mounts = {
    "segments-pvc" = "/segments"
  }
}

# qa-web (NodePort for single-node exposure)
module "qa_web" {
  source            = "./modules/k8s-app"
  name              = "qa-web"
  namespace         = module.ns.name
  image             = var.shared_image
  image_pull_policy = var.image_pull_policy

  labels = {
    app       = "semseg"
    component = "qa-web"
  }

  env = {
    RESULTS_API_URL = "http://results-api.semseg.svc.cluster.local:8080"
  }

  command = ["/bin/sh", "-c"]
  args    = ["uvicorn services.qa_web.app:app --host 0.0.0.0 --port 3000 --workers 1"]

  container_port  = 3000
  service_enabled = true
  service_port    = 3000
  service_type    = "NodePort"
  node_port       = 32080 # k8s NodePort range: 30000-32767
}

# ------------------------
# Workers (no service)
# ------------------------

module "convert_ply" {
  source            = "./modules/k8s-app"
  name              = "convert-ply"
  namespace         = module.ns.name
  image             = var.shared_image
  image_pull_policy = var.image_pull_policy

  labels = {
    app       = "semseg"
    component = "convert-ply"
  }

  env = {
    REDIS_URL                     = "redis://redis.semseg.svc.cluster.local:6379/0"
    REDIS_STREAM_FRAMES_CONVERTED = "s_frames_converted"
    PREVIEW_OUT_DIR               = "/segments"
  }

  command = ["/bin/sh", "-c"]
  args    = ["python3 /semantic-segmenter/services/convert_service/convert-ply --in-dir /sub-pc-frames --out-dir /pc-frames --preview-out-dir /segments --delete-source --log-level debug"]
  # No service
  service_enabled = false

  pvc_mounts = {
    "sub-pc-frames-pvc" = "/sub-pc-frames"
    "pc-frames-pvc"     = "/pc-frames"
    "segments-pvc"      = "/segments"
  }
}

module "part_labeler" {
  source            = "./modules/k8s-app"
  name              = "part-labeler"
  namespace         = module.ns.name
  image             = var.shared_image
  image_pull_policy = var.image_pull_policy

  labels = {
    app       = "semseg"
    component = "part-labeler"
  }

  env = {
    REDIS_URL                     = "redis://redis.semseg.svc.cluster.local:6379/0"
    REDIS_STREAM_PARTS_LABELED    = "s_parts_labeled"
    REDIS_STREAM_FRAMES_CONVERTED = "s_frames_converted"
    REDIS_GROUP_PART_LABELER      = "g_part_labeler"
  }

  command = ["/bin/sh", "-c"]
  args    = ["python3 /semantic-segmenter/services/part_labeler/part_labeler.py --log-level debug --out-dir /segments --colorized-dir /segments/labels --write-colorized"]
  service_enabled = false

  pvc_mounts = {
    "pc-frames-pvc" = "/pc-frames"
    "segments-pvc"  = "/segments"
  }

}

module "redactor" {
  source            = "./modules/k8s-app"
  name              = "redactor"
  namespace         = module.ns.name
  image             = var.shared_image
  image_pull_policy = var.image_pull_policy

  labels = {
    app       = "semseg"
    component = "redactor"
  }

  env = {
    REDIS_URL                  = "redis://redis.semseg.svc.cluster.local:6379/0"
    REDIS_STREAM_PARTS_LABELED = "s_parts_labeled"
    REDIS_STREAM_REDACTED_DONE = "s_redacted_done"
    REDIS_GROUP_REDACTOR       = "g_redactor"
  }

  command = ["/bin/sh", "-c"]
  args    = ["python3 /semantic-segmenter/services/redactor/redactor.py --log-level debug --out-dir /segments"]
  service_enabled = false

  pvc_mounts = {
    "pc-frames-pvc" = "/pc-frames"
    "segments-pvc"  = "/segments"
  }

}

module "analytics" {
  source            = "./modules/k8s-app"
  name              = "analytics"
  namespace         = module.ns.name
  image             = var.shared_image
  image_pull_policy = var.image_pull_policy

  labels = {
    app       = "semseg"
    component = "analytics"
  }

  env = {
    REDIS_URL                   = "redis://redis.semseg.svc.cluster.local:6379/0"
    REDIS_STREAM_PARTS_LABELED  = "s_parts_labeled"
    REDIS_STREAM_ANALYTICS_DONE = "s_analytics_done"
    REDIS_GROUP_ANALYTICS       = "g_analytics"
  }

  command = ["/bin/sh", "-c"]
  args    = ["python3 /semantic-segmenter/services/analytics/analytics.py --log-level debug --out-dir /segments"]
  service_enabled = false

  pvc_mounts = {
    "segments-pvc" = "/segments"
  }

}

# ------------------------
# Redis (StatefulSet + PVC + ClusterIP service)
# ------------------------

module "redis" {
  source       = "./modules/k8s-redis"
  name         = "redis"
  namespace    = module.ns.name
  storage_gi   = 1
  service_port = 6379
  # Fixed image as requested
  image = "redis:7-alpine"

  labels = {
    app       = "semseg"
    component = "redis"
  }
}

resource "kubernetes_persistent_volume_claim" "sub_pc_frames" {
  metadata {
    name      = "sub-pc-frames-pvc"
    namespace = module.ns.name
  }
  spec {
    access_modes = ["ReadWriteOnce"]
    resources {
      requests = {
        storage = "${var.sub_pc_frames_size_gi}Gi"
      }
    }
    # storage_class_name omitted to use cluster default (e.g., local-path)
  }
}

resource "kubernetes_persistent_volume_claim" "pc_frames" {
  metadata {
    name      = "pc-frames-pvc"
    namespace = module.ns.name
  }
  spec {
    access_modes = ["ReadWriteOnce"]
    resources {
      requests = {
        storage = "${var.pc_frames_size_gi}Gi"
      }
    }
  }
}

resource "kubernetes_persistent_volume_claim" "segments" {
  metadata {
    name      = "segments-pvc"
    namespace = module.ns.name
  }
  spec {
    access_modes = ["ReadWriteOnce"]
    resources {
      requests = {
        storage = "${var.segments_size_gi}Gi"
      }
    }
  }
}
