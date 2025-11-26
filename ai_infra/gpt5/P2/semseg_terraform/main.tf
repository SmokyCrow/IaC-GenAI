terraform {
  required_version = ">= 1.5.0"
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.29.0"
    }
  }
}

provider "kubernetes" {
  config_path    = var.kubeconfig
  config_context = var.kube_context
}

# Namespace
resource "kubernetes_namespace" "ns" {
  metadata {
    name = var.namespace
  }
}

# ---------------------------
# PersistentVolumeClaims
# ---------------------------
module "pvc_sub_pc_frames" {
  source              = "./modules/pvc"
  name                = "sub-pc-frames-pvc"
  namespace           = kubernetes_namespace.ns.metadata[0].name
  storage_class_name  = "hostpath"
  size                = "64Mi"
  wait_until_bound    = false
}

module "pvc_pc_frames" {
  source              = "./modules/pvc"
  name                = "pc-frames-pvc"
  namespace           = kubernetes_namespace.ns.metadata[0].name
  storage_class_name  = "hostpath"
  size                = "128Mi"
  wait_until_bound    = false
}

module "pvc_segments" {
  source              = "./modules/pvc"
  name                = "segments-pvc"
  namespace           = kubernetes_namespace.ns.metadata[0].name
  storage_class_name  = "hostpath"
  size                = "256Mi"
  wait_until_bound    = false
}

# ---------------------------
# Locals for shared config
# ---------------------------
locals {
  common_env = {
    REDIS_URL                  = "redis://redis.${var.namespace}.svc.cluster.local:6379/0"
    REDIS_STREAM_FRAMES_CONVERTED = "s_frames_converted"
    REDIS_STREAM_PARTS_LABELED    = "s_parts_labeled"
    REDIS_STREAM_REDACTED_DONE    = "s_redacted_done"
    REDIS_STREAM_ANALYTICS_DONE   = "s_analytics_done"
    REDIS_GROUP_PART_LABELER      = "g_part_labeler"
    REDIS_GROUP_REDACTOR          = "g_redactor"
    REDIS_GROUP_ANALYTICS         = "g_analytics"
  }

  vol_claims = [
    { name = "sub-pc-frames", claim = module.pvc_sub_pc_frames.claim_name  },
    { name = "pc-frames",     claim = module.pvc_pc_frames.claim_name      },
    { name = "segments",      claim = module.pvc_segments.claim_name       },
  ]
}

# ---------------------------
# Deployments
# ---------------------------

# ingest-api (separate image, port 8080, probes, mount /sub-pc-frames)
module "deploy_ingest_api" {
  source     = "./modules/deployment"
  name       = "ingest-api"
  namespace  = kubernetes_namespace.ns.metadata[0].name
  image      = var.ingest_image
  replicas   = 1
  port       = 8080

  env = merge(local.common_env, {
    INGEST_OUT_DIR = "/sub-pc-frames"
  })

  readiness_path = "/healthz"
  liveness_path  = "/healthz"

  volume_claims = [
    for v in local.vol_claims : v if v.name == "sub-pc-frames"
  ]
  volume_mounts = [
    { name = "sub-pc-frames", mount_path = "/sub-pc-frames" }
  ]
}

# results-api (shared image, port 8081, probes, mount /segments)
module "deploy_results_api" {
  source     = "./modules/deployment"
  name       = "results-api"
  namespace  = kubernetes_namespace.ns.metadata[0].name
  image      = var.shared_image
  replicas   = 1
  port       = 8081

  command = ["uvicorn"]
  args    = ["services.results_api.app:app", "--host", "0.0.0.0", "--port", "8081", "--workers", "1"]

  env = merge(local.common_env, { SEGMENTS_DIR = "/segments" })

  readiness_path = "/healthz"
  liveness_path  = "/healthz"

  volume_claims = [for v in local.vol_claims : v if v.name == "segments"]
  volume_mounts = [{ name = "segments", mount_path = "/segments" }]
}

# qa-web (shared image, port 8082, probes)
module "deploy_qa_web" {
  source     = "./modules/deployment"
  name       = "qa-web"
  namespace  = kubernetes_namespace.ns.metadata[0].name
  image      = var.shared_image
  replicas   = 1
  port       = 8082

  command = ["uvicorn"]
  args    = ["services.qa_web.app:app", "--host", "0.0.0.0", "--port", "8082", "--workers", "1"]

  env = merge(local.common_env, {
    RESULTS_API_URL = "http://results-api.${var.namespace}.svc.cluster.local:30081"
  })

  readiness_path = "/healthz"
  liveness_path  = "/healthz"
}

# convert-ply (shared image, mounts: /sub-pc-frames, /pc-frames, /segments)
module "deploy_convert_ply" {
  source     = "./modules/deployment"
  name       = "convert-ply"
  namespace  = kubernetes_namespace.ns.metadata[0].name
  image      = var.shared_image
  replicas   = 1

  command = ["python3"]
  args    = [
    "/semantic-segmenter/services/convert_service/convert-ply",
    "--in-dir", "/sub-pc-frames",
    "--out-dir", "/pc-frames",
    "--preview-out-dir", "/segments",
    "--delete-source",
    "--log-level", "info"
  ]

  env = local.common_env

  volume_claims = local.vol_claims
  volume_mounts = [
    { name = "sub-pc-frames", mount_path = "/sub-pc-frames" },
    { name = "pc-frames",     mount_path = "/pc-frames"     },
    { name = "segments",      mount_path = "/segments"      },
  ]
}

# part-labeler (shared image, mounts: /pc-frames, /segments)
module "deploy_part_labeler" {
  source     = "./modules/deployment"
  name       = "part-labeler"
  namespace  = kubernetes_namespace.ns.metadata[0].name
  image      = var.shared_image
  replicas   = 1

  command = ["python3"]
  args    = [
    "/semantic-segmenter/services/part_labeler/part_labeler.py",
    "--log-level", "info",
    "--out-dir", "/segments",
    "--colorized-dir", "/segments/labels",
    "--write-colorized"
  ]

  env = local.common_env

  volume_claims = [for v in local.vol_claims : v if contains(["pc-frames", "segments"], v.name)]
  volume_mounts = [
    { name = "pc-frames", mount_path = "/pc-frames" },
    { name = "segments",  mount_path = "/segments"  },
  ]
}


# redactor (shared image, mounts: /pc-frames, /segments)
module "deploy_redactor" {
  source     = "./modules/deployment"
  name       = "redactor"
  namespace  = kubernetes_namespace.ns.metadata[0].name
  image      = var.shared_image
  replicas   = 1

  command = ["python3"]
  args    = [
    "/semantic-segmenter/services/redactor/redactor.py",
    "--log-level", "info",
    "--out-dir", "/segments"
  ]

  env = local.common_env

  volume_claims = [for v in local.vol_claims : v if contains(["pc-frames", "segments"], v.name)]
  volume_mounts = [
    { name = "pc-frames", mount_path = "/pc-frames" },
    { name = "segments",  mount_path = "/segments"  },
  ]
}


# analytics (shared image, mounts: /segments)
module "deploy_analytics" {
  source     = "./modules/deployment"
  name       = "analytics"
  namespace  = kubernetes_namespace.ns.metadata[0].name
  image      = var.shared_image
  replicas   = 1

  command = ["python3"]
  args    = [
    "/semantic-segmenter/services/analytics/analytics.py",
    "--log-level", "info",
    "--out-dir", "/segments"
  ]

  env = local.common_env

  volume_claims = [for v in local.vol_claims : v if v.name == "segments"]
  volume_mounts = [{ name = "segments", mount_path = "/segments" }]
}


# redis (official image, port 6379)
module "deploy_redis" {
  source     = "./modules/deployment"
  name       = "redis"
  namespace  = kubernetes_namespace.ns.metadata[0].name
  image      = var.redis_image
  replicas   = 1
  port       = 6379

  # No probes/volumes needed per spec
}

# ---------------------------
# Services
# ---------------------------

# NodePort services
module "svc_ingest_api" {
  source      = "./modules/service"
  name        = "ingest-api"
  namespace   = kubernetes_namespace.ns.metadata[0].name
  service_type = "NodePort"
  port        = 30080
  target_port = 8080
  node_port   = 30080
  selector    = { app = "ingest-api" }
}

module "svc_results_api" {
  source      = "./modules/service"
  name        = "results-api"
  namespace   = kubernetes_namespace.ns.metadata[0].name
  service_type = "NodePort"
  port        = 30081
  target_port = 8081
  node_port   = 30081
  selector    = { app = "results-api" }
}

module "svc_qa_web" {
  source      = "./modules/service"
  name        = "qa-web"
  namespace   = kubernetes_namespace.ns.metadata[0].name
  service_type = "NodePort"
  port        = 30082
  target_port = 8082
  node_port   = 30082
  selector    = { app = "qa-web" }
}

# redis as ClusterIP
module "svc_redis" {
  source      = "./modules/service"
  name        = "redis"
  namespace   = kubernetes_namespace.ns.metadata[0].name
  service_type = "ClusterIP"
  port        = 6379
  target_port = 6379
  selector    = { app = "redis" }
}
