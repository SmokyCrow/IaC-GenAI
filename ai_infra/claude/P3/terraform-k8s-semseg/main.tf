terraform {
  required_version = ">= 1.0"
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.23"
    }
  }
}

provider "kubernetes" {
  config_path = var.kubeconfig != "" ? var.kubeconfig : "~/.kube/config"
}

resource "kubernetes_namespace" "main" {
  metadata {
    name = var.namespace
  }
}

# PVCs
module "sub_pc_frames_pvc" {
  source              = "./modules/pvc"
  name                = "sub-pc-frames-pvc"
  namespace           = kubernetes_namespace.main.metadata[0].name
  storage             = "64Mi"
  storage_class_name  = var.pvc_storage_class_name
  access_modes        = ["ReadWriteOnce"]
  wait_until_bound    = false
}

module "pc_frames_pvc" {
  source              = "./modules/pvc"
  name                = "pc-frames-pvc"
  namespace           = kubernetes_namespace.main.metadata[0].name
  storage             = "128Mi"
  storage_class_name  = var.pvc_storage_class_name
  access_modes        = ["ReadWriteOnce"]
  wait_until_bound    = false
}

module "segments_pvc" {
  source              = "./modules/pvc"
  name                = "segments-pvc"
  namespace           = kubernetes_namespace.main.metadata[0].name
  storage             = "256Mi"
  storage_class_name  = var.pvc_storage_class_name
  access_modes        = ["ReadWriteOnce"]
  wait_until_bound    = false
}

# Applications
module "ingest_api" {
  source     = "./modules/app"
  name       = "ingest-api"
  namespace  = kubernetes_namespace.main.metadata[0].name
  image      = var.ingest_image
  port       = 8080
  node_port  = var.node_port_base + 0
  service_port = 80

  environment = {
    REDIS_URL                       = "redis://redis.${var.namespace}.svc.cluster.local:6379/0"
    REDIS_STREAM_FRAMES_CONVERTED   = "s_frames_converted"
    REDIS_STREAM_PARTS_LABELED      = "s_parts_labeled"
    REDIS_STREAM_REDACTED_DONE      = "s_redacted_done"
    REDIS_STREAM_ANALYTICS_DONE     = "s_analytics_done"
    REDIS_GROUP_PART_LABELER        = "g_part_labeler"
    REDIS_GROUP_REDACTOR            = "g_redactor"
    REDIS_GROUP_ANALYTICS           = "g_analytics"
    INGEST_OUT_DIR                  = "/sub-pc-frames"
  }

  volumes = [
    {
      name       = "sub-pc-frames"
      mount_path = "/sub-pc-frames"
      pvc_name   = module.sub_pc_frames_pvc.name
    }
  ]

  enable_health_probes = true
}

module "results_api" {
  source     = "./modules/app"
  name       = "results-api"
  namespace  = kubernetes_namespace.main.metadata[0].name
  image      = var.image_repo
  port       = 8081
  node_port  = var.node_port_base + 1
  service_port = 80
  command    = ["bash", "-lc"]
  args       = ["uvicorn services.results_api.app:app --host 0.0.0.0 --port 8081 --workers 1"]

  environment = {
    REDIS_URL                       = "redis://redis.${var.namespace}.svc.cluster.local:6379/0"
    REDIS_STREAM_FRAMES_CONVERTED   = "s_frames_converted"
    REDIS_STREAM_PARTS_LABELED      = "s_parts_labeled"
    REDIS_STREAM_REDACTED_DONE      = "s_redacted_done"
    REDIS_STREAM_ANALYTICS_DONE     = "s_analytics_done"
    REDIS_GROUP_PART_LABELER        = "g_part_labeler"
    REDIS_GROUP_REDACTOR            = "g_redactor"
    REDIS_GROUP_ANALYTICS           = "g_analytics"
    SEGMENTS_DIR                    = "/segments"
  }

  volumes = [
    {
      name       = "segments"
      mount_path = "/segments"
      pvc_name   = module.segments_pvc.name
    }
  ]

  enable_health_probes = true
}

module "qa_web" {
  source     = "./modules/app"
  name       = "qa-web"
  namespace  = kubernetes_namespace.main.metadata[0].name
  image      = var.image_repo
  port       = 8082
  node_port  = var.node_port_base + 2
  service_port = 80
  command    = ["bash", "-lc"]
  args       = ["uvicorn services.qa_web.app:app --host 0.0.0.0 --port 8082 --workers 1"]

  environment = {
    REDIS_URL                       = "redis://redis.${var.namespace}.svc.cluster.local:6379/0"
    REDIS_STREAM_FRAMES_CONVERTED   = "s_frames_converted"
    REDIS_STREAM_PARTS_LABELED      = "s_parts_labeled"
    REDIS_STREAM_REDACTED_DONE      = "s_redacted_done"
    REDIS_STREAM_ANALYTICS_DONE     = "s_analytics_done"
    REDIS_GROUP_PART_LABELER        = "g_part_labeler"
    REDIS_GROUP_REDACTOR            = "g_redactor"
    REDIS_GROUP_ANALYTICS           = "g_analytics"
    RESULTS_API_URL                 = "http://results-api.${var.namespace}.svc.cluster.local"
  }

  enable_health_probes = true
}

module "convert_ply" {
  source    = "./modules/app"
  name      = "convert-ply"
  namespace = kubernetes_namespace.main.metadata[0].name
  image     = var.image_repo
  command   = ["python3", "/semantic-segmenter/services/convert_service/convert-ply"]
  args      = ["--in-dir", "/sub-pc-frames", "--out-dir", "/pc-frames", "--preview-out-dir", "/segments", "--delete-source", "--log-level", "info"]

  environment = {
    REDIS_URL                       = "redis://redis.${var.namespace}.svc.cluster.local:6379/0"
    REDIS_STREAM_FRAMES_CONVERTED   = "s_frames_converted"
    REDIS_STREAM_PARTS_LABELED      = "s_parts_labeled"
    REDIS_STREAM_REDACTED_DONE      = "s_redacted_done"
    REDIS_STREAM_ANALYTICS_DONE     = "s_analytics_done"
    REDIS_GROUP_PART_LABELER        = "g_part_labeler"
    REDIS_GROUP_REDACTOR            = "g_redactor"
    REDIS_GROUP_ANALYTICS           = "g_analytics"
    PREVIEW_OUT_DIR                 = "/segments"
  }

  volumes = [
    {
      name       = "sub-pc-frames"
      mount_path = "/sub-pc-frames"
      pvc_name   = module.sub_pc_frames_pvc.name
    },
    {
      name       = "pc-frames"
      mount_path = "/pc-frames"
      pvc_name   = module.pc_frames_pvc.name
    },
    {
      name       = "segments"
      mount_path = "/segments"
      pvc_name   = module.segments_pvc.name
    }
  ]
}

module "part_labeler" {
  source    = "./modules/app"
  name      = "part-labeler"
  namespace = kubernetes_namespace.main.metadata[0].name
  image     = var.image_repo
  command   = ["bash", "-lc"]
  args      = ["python3 /semantic-segmenter/services/part_labeler/part_labeler.py --log-level info --out-dir /segments --colorized-dir /segments/labels --write-colorized"]

  environment = {
    REDIS_URL                       = "redis://redis.${var.namespace}.svc.cluster.local:6379/0"
    REDIS_STREAM_FRAMES_CONVERTED   = "s_frames_converted"
    REDIS_STREAM_PARTS_LABELED      = "s_parts_labeled"
    REDIS_STREAM_REDACTED_DONE      = "s_redacted_done"
    REDIS_STREAM_ANALYTICS_DONE     = "s_analytics_done"
    REDIS_GROUP_PART_LABELER        = "g_part_labeler"
    REDIS_GROUP_REDACTOR            = "g_redactor"
    REDIS_GROUP_ANALYTICS           = "g_analytics"
  }

  volumes = [
    {
      name       = "pc-frames"
      mount_path = "/pc-frames"
      pvc_name   = module.pc_frames_pvc.name
    },
    {
      name       = "segments"
      mount_path = "/segments"
      pvc_name   = module.segments_pvc.name
    }
  ]
}

module "redactor" {
  source    = "./modules/app"
  name      = "redactor"
  namespace = kubernetes_namespace.main.metadata[0].name
  image     = var.image_repo
  command   = ["bash", "-lc"]
  args      = ["python3 /semantic-segmenter/services/redactor/redactor.py --log-level info --out-dir /segments"]

  environment = {
    REDIS_URL                       = "redis://redis.${var.namespace}.svc.cluster.local:6379/0"
    REDIS_STREAM_FRAMES_CONVERTED   = "s_frames_converted"
    REDIS_STREAM_PARTS_LABELED      = "s_parts_labeled"
    REDIS_STREAM_REDACTED_DONE      = "s_redacted_done"
    REDIS_STREAM_ANALYTICS_DONE     = "s_analytics_done"
    REDIS_GROUP_PART_LABELER        = "g_part_labeler"
    REDIS_GROUP_REDACTOR            = "g_redactor"
    REDIS_GROUP_ANALYTICS           = "g_analytics"
  }

  volumes = [
    {
      name       = "pc-frames"
      mount_path = "/pc-frames"
      pvc_name   = module.pc_frames_pvc.name
    },
    {
      name       = "segments"
      mount_path = "/segments"
      pvc_name   = module.segments_pvc.name
    }
  ]
}

module "analytics" {
  source    = "./modules/app"
  name      = "analytics"
  namespace = kubernetes_namespace.main.metadata[0].name
  image     = var.image_repo
  command   = ["bash", "-lc"]
  args      = ["python3 /semantic-segmenter/services/analytics/analytics.py --log-level info --out-dir /segments"]

  environment = {
    REDIS_URL                       = "redis://redis.${var.namespace}.svc.cluster.local:6379/0"
    REDIS_STREAM_FRAMES_CONVERTED   = "s_frames_converted"
    REDIS_STREAM_PARTS_LABELED      = "s_parts_labeled"
    REDIS_STREAM_REDACTED_DONE      = "s_redacted_done"
    REDIS_STREAM_ANALYTICS_DONE     = "s_analytics_done"
    REDIS_GROUP_PART_LABELER        = "g_part_labeler"
    REDIS_GROUP_REDACTOR            = "g_redactor"
    REDIS_GROUP_ANALYTICS           = "g_analytics"
  }

  volumes = [
    {
      name       = "segments"
      mount_path = "/segments"
      pvc_name   = module.segments_pvc.name
    }
  ]
}

module "redis" {
  source    = "./modules/app"
  name      = "redis"
  namespace = kubernetes_namespace.main.metadata[0].name
  image     = "redis:7-alpine"
  port      = 6379
  args      = ["--appendonly", "yes", "--save", ""]
  service_type = "ClusterIP"
  image_pull_policy = "IfNotPresent"
}
