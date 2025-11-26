terraform {
  required_version = ">= 1.5.0"
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.23"
    }
  }
}

provider "kubernetes" {
  config_path    = "~/.kube/config"
  config_context = "docker-desktop"
}

# Namespace
resource "kubernetes_namespace" "semseg" {
  metadata {
    name = var.namespace
  }
}

# PVCs
module "sub_pc_frames_pvc" {
  source = "./modules/pvc"

  name              = "sub-pc-frames-pvc"
  namespace         = kubernetes_namespace.semseg.metadata[0].name
  storage_class     = var.storage_class
  storage_size      = var.sub_pc_frames_size
  wait_until_bound  = false
}

module "pc_frames_pvc" {
  source = "./modules/pvc"

  name              = "pc-frames-pvc"
  namespace         = kubernetes_namespace.semseg.metadata[0].name
  storage_class     = var.storage_class
  storage_size      = var.pc_frames_size
  wait_until_bound  = false
}

module "segments_pvc" {
  source = "./modules/pvc"

  name              = "segments-pvc"
  namespace         = kubernetes_namespace.semseg.metadata[0].name
  storage_class     = var.storage_class
  storage_size      = var.segments_size
  wait_until_bound  = false
}

# Redis Deployment
module "redis_deployment" {
  source = "./modules/deployment"

  name      = "redis"
  namespace = kubernetes_namespace.semseg.metadata[0].name
  image     = var.redis_image
  replicas  = 1

  container_port = 6379

  env_vars = {}
  volume_mounts = []

  depends_on = [kubernetes_namespace.semseg]
}

# Redis Service (ClusterIP)
module "redis_service" {
  source = "./modules/service"

  name         = "redis"
  namespace    = kubernetes_namespace.semseg.metadata[0].name
  service_type = "ClusterIP"
  port         = 6379
  target_port  = 6379
  selector = {
    app = "redis"
  }

  depends_on = [module.redis_deployment]
}

# Convert PLY Deployment
module "convert_ply_deployment" {
  source = "./modules/deployment"

  name      = "convert-ply"
  namespace = kubernetes_namespace.semseg.metadata[0].name
  image     = var.shared_image
  replicas  = 1

  command = ["python3"]
  args = [
    "/semantic-segmenter/services/convert_service/convert-ply",
    "--in-dir",
    "/sub-pc-frames",
    "--out-dir",
    "/pc-frames",
    "--preview-out-dir",
    "/segments",
    "--delete-source",
    "--log-level",
    "info"
  ]

  env_vars = merge(
    local.common_env_vars,
    local.stream_env_vars
  )

  volume_mounts = [
    {
      name       = "sub-pc-frames"
      mount_path = "/sub-pc-frames"
      claim_name = module.sub_pc_frames_pvc.name
    },
    {
      name       = "pc-frames"
      mount_path = "/pc-frames"
      claim_name = module.pc_frames_pvc.name
    },
    {
      name       = "segments"
      mount_path = "/segments"
      claim_name = module.segments_pvc.name
    }
  ]

  depends_on = [
    module.sub_pc_frames_pvc,
    module.pc_frames_pvc,
    module.segments_pvc,
    module.redis_service
  ]
}

# Part Labeler Deployment
module "part_labeler_deployment" {
  source = "./modules/deployment"

  name      = "part-labeler"
  namespace = kubernetes_namespace.semseg.metadata[0].name
  image     = var.shared_image
  replicas  = 1

  command = ["python3"]
  args = [
    "/semantic-segmenter/services/part_labeler/part_labeler.py",
    "--log-level",
    "info",
    "--out-dir",
    "/segments",
    "--colorized-dir",
    "/segments/labels",
    "--write-colorized"
  ]

  env_vars = merge(
    local.common_env_vars,
    local.stream_env_vars
  )

  volume_mounts = [
    {
      name       = "pc-frames"
      mount_path = "/pc-frames"
      claim_name = module.pc_frames_pvc.name
    },
    {
      name       = "segments"
      mount_path = "/segments"
      claim_name = module.segments_pvc.name
    }
  ]

  depends_on = [
    module.pc_frames_pvc,
    module.segments_pvc,
    module.redis_service
  ]
}

# Redactor Deployment
module "redactor_deployment" {
  source = "./modules/deployment"

  name      = "redactor"
  namespace = kubernetes_namespace.semseg.metadata[0].name
  image     = var.shared_image
  replicas  = 1

  command = ["python3"]
  args = [
    "/semantic-segmenter/services/redactor/redactor.py",
    "--log-level",
    "info",
    "--out-dir",
    "/segments"
  ]

  env_vars = merge(
    local.common_env_vars,
    local.stream_env_vars
  )

  volume_mounts = [
    {
      name       = "pc-frames"
      mount_path = "/pc-frames"
      claim_name = module.pc_frames_pvc.name
    },
    {
      name       = "segments"
      mount_path = "/segments"
      claim_name = module.segments_pvc.name
    }
  ]

  depends_on = [
    module.pc_frames_pvc,
    module.segments_pvc,
    module.redis_service
  ]
}

# Analytics Deployment
module "analytics_deployment" {
  source = "./modules/deployment"

  name      = "analytics"
  namespace = kubernetes_namespace.semseg.metadata[0].name
  image     = var.shared_image
  replicas  = 1

  command = ["python3"]
  args = [
    "/semantic-segmenter/services/analytics/analytics.py",
    "--log-level",
    "info",
    "--out-dir",
    "/segments"
  ]

  env_vars = merge(
    local.common_env_vars,
    local.stream_env_vars
  )

  volume_mounts = [
    {
      name       = "segments"
      mount_path = "/segments"
      claim_name = module.segments_pvc.name
    }
  ]

  depends_on = [
    module.segments_pvc,
    module.redis_service
  ]
}

# Ingest API Deployment
module "ingest_api_deployment" {
  source = "./modules/deployment"

  name      = "ingest-api"
  namespace = kubernetes_namespace.semseg.metadata[0].name
  image     = var.ingest_image
  replicas  = 1

  container_port = 8080

  env_vars = merge(
    local.common_env_vars,
    local.stream_env_vars,
    {
      INGEST_OUT_DIR = "/sub-pc-frames"
    }
  )

  volume_mounts = [
    {
      name       = "sub-pc-frames"
      mount_path = "/sub-pc-frames"
      claim_name = module.sub_pc_frames_pvc.name
    }
  ]

  readiness_probe = {
    http_get = {
      path = "/healthz"
      port = 8080
    }
    initial_delay_seconds = 5
    period_seconds        = 10
  }

  liveness_probe = {
    http_get = {
      path = "/healthz"
      port = 8080
    }
    initial_delay_seconds = 15
    period_seconds        = 20
  }

  depends_on = [
    module.sub_pc_frames_pvc,
    module.redis_service
  ]
}

# Ingest API Service (NodePort)
module "ingest_api_service" {
  source = "./modules/service"

  name         = "ingest-api"
  namespace    = kubernetes_namespace.semseg.metadata[0].name
  service_type = "NodePort"
  port         = 8080
  target_port  = 8080
  node_port    = 30080
  selector = {
    app = "ingest-api"
  }

  depends_on = [module.ingest_api_deployment]
}

# Results API Deployment
module "results_api_deployment" {
  source = "./modules/deployment"

  name      = "results-api"
  namespace = kubernetes_namespace.semseg.metadata[0].name
  image     = var.shared_image
  replicas  = 1

  container_port = 8081

  command = ["uvicorn"]
  args = [
    "services.results_api.app:app",
    "--host",
    "0.0.0.0",
    "--port",
    "8081",
    "--workers",
    "1"
  ]

  env_vars = merge(
    local.common_env_vars,
    local.stream_env_vars,
    {
      SEGMENTS_DIR = "/segments"
    }
  )

  volume_mounts = [
    {
      name       = "segments"
      mount_path = "/segments"
      claim_name = module.segments_pvc.name
    }
  ]

  readiness_probe = {
    http_get = {
      path = "/healthz"
      port = 8081
    }
    initial_delay_seconds = 5
    period_seconds        = 10
  }

  liveness_probe = {
    http_get = {
      path = "/healthz"
      port = 8081
    }
    initial_delay_seconds = 15
    period_seconds        = 20
  }

  depends_on = [
    module.segments_pvc,
    module.redis_service
  ]
}

# Results API Service (NodePort)
module "results_api_service" {
  source = "./modules/service"

  name         = "results-api"
  namespace    = kubernetes_namespace.semseg.metadata[0].name
  service_type = "NodePort"
  port         = 8081
  target_port  = 8081
  node_port    = 30081
  selector = {
    app = "results-api"
  }

  depends_on = [module.results_api_deployment]
}

# QA Web Deployment
module "qa_web_deployment" {
  source = "./modules/deployment"

  name      = "qa-web"
  namespace = kubernetes_namespace.semseg.metadata[0].name
  image     = var.shared_image
  replicas  = 1

  container_port = 8082

  command = ["uvicorn"]
  args = [
    "services.qa_web.app:app",
    "--host",
    "0.0.0.0",
    "--port",
    "8082",
    "--workers",
    "1"
  ]

  env_vars = merge(
    local.common_env_vars,
    {
      RESULTS_API_URL = "http://results-api.semseg.svc.cluster.local:8081"
    }
  )

  volume_mounts = []

  readiness_probe = {
    http_get = {
      path = "/healthz"
      port = 8082
    }
    initial_delay_seconds = 5
    period_seconds        = 10
  }

  liveness_probe = {
    http_get = {
      path = "/healthz"
      port = 8082
    }
    initial_delay_seconds = 15
    period_seconds        = 20
  }

  depends_on = [
    module.redis_service,
    module.results_api_service
  ]
}

# QA Web Service (NodePort)
module "qa_web_service" {
  source = "./modules/service"

  name         = "qa-web"
  namespace    = kubernetes_namespace.semseg.metadata[0].name
  service_type = "NodePort"
  port         = 8082
  target_port  = 8082
  node_port    = 30082
  selector = {
    app = "qa-web"
  }

  depends_on = [module.qa_web_deployment]
}

# Local variables for environment variables
locals {
  common_env_vars = {
    REDIS_URL = "redis://redis.semseg.svc.cluster.local:6379/0"
  }

  stream_env_vars = {
    REDIS_STREAM_FRAMES_CONVERTED = "s_frames_converted"
    REDIS_STREAM_PARTS_LABELED    = "s_parts_labeled"
    REDIS_STREAM_REDACTED_DONE    = "s_redacted_done"
    REDIS_STREAM_ANALYTICS_DONE   = "s_analytics_done"
    REDIS_GROUP_PART_LABELER      = "g_part_labeler"
    REDIS_GROUP_REDACTOR          = "g_redactor"
    REDIS_GROUP_ANALYTICS         = "g_analytics"
  }
}
