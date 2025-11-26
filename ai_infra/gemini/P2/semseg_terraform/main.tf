# Define local variables for shared settings to reduce repetition
locals {
  namespace = var.namespace

  # Common environment variables for all Redis-using apps
  common_env_vars = {
    "REDIS_URL" = "redis://redis.${local.namespace}.svc.cluster.local:6379/0"
  }

  # Worker-specific stream and group environment variables
  worker_env_vars = {
    "REDIS_STREAM_FRAMES_CONVERTED" = "s_frames_converted"
    "REDIS_STREAM_PARTS_LABELED"    = "s_parts_labeled"
    "REDIS_STREAM_REDACTED_DONE"    = "s_redacted_done"
    "REDIS_STREAM_ANALYTICS_DONE"   = "s_analytics_done"
    "REDIS_GROUP_PART_LABELER"      = "g_part_labeler"
    "REDIS_GROUP_REDACTOR"          = "g_redactor"
    "REDIS_GROUP_ANALYTICS"         = "g_analytics"
  }

  # Definitions for volumes that will be shared
  # This makes it easy to reference the PVC claim names
  volume_definitions = {
    sub-pc-frames = {
      name = "sub-pc-frames-vol"
      persistent_volume_claim = {
        claim_name = "sub-pc-frames-pvc"
      }
    }
    pc-frames = {
      name = "pc-frames-vol"
      persistent_volume_claim = {
        claim_name = "pc-frames-pvc"
      }
    }
    segments = {
      name = "segments-vol"
      persistent_volume_claim = {
        claim_name = "segments-pvc"
      }
    }
  }

  # Definitions for volume mounts
  volume_mount_definitions = {
    sub-pc-frames = {
      name       = "sub-pc-frames-vol"
      mount_path = "/sub-pc-frames"
    }
    pc-frames = {
      name       = "pc-frames-vol"
      mount_path = "/pc-frames"
    }
    segments = {
      name       = "segments-vol"
      mount_path = "/segments"
    }
  }
}

# 1. Namespace
resource "kubernetes_namespace" "semseg" {
  metadata {
    name = local.namespace
  }
}

# 2. Persistent Volume Claims (PVCs)
module "sub_pc_frames_pvc" {
  source = "./modules/pvc"

  name               = "sub-pc-frames-pvc"
  namespace          = local.namespace
  storage_class_name = "hostpath"
  size               = "64Mi"
  wait_until_bound   = false
}

module "pc_frames_pvc" {
  source = "./modules/pvc"

  name               = "pc-frames-pvc"
  namespace          = local.namespace
  storage_class_name = "hostpath"
  size               = "128Mi"
  wait_until_bound   = false
}

module "segments_pvc" {
  source = "./modules/pvc"

  name               = "segments-pvc"
  namespace          = local.namespace
  storage_class_name = "hostpath"
  size               = "256Mi"
  wait_until_bound   = false
}

# 3. Redis
module "redis_service" {
  source = "./modules/service"

  name         = "redis"
  namespace    = local.namespace
  selector_app = "redis"
  type         = "ClusterIP"
  ports = [{
    port        = 6379
    target_port = 6379
  }]
}

module "redis_deployment" {
  source = "./modules/deployment"

  name           = "redis"
  namespace      = local.namespace
  image          = var.redis_image
  container_port = 6379
  # No env vars, volumes, or probes needed for this simple redis
}

# 4. Ingest API (NodePort)
module "ingest_api_service" {
  source = "./modules/service"

  name         = "ingest-api"
  namespace    = local.namespace
  selector_app = "ingest-api"
  type         = "NodePort"
  ports = [{
    port        = 8080
    target_port = 8080
    node_port   = 30080
  }]
}

module "ingest_api_deployment" {
  source    = "./modules/deployment"
  depends_on = [module.sub_pc_frames_pvc] # Ensure PVC exists before mounting

  name           = "ingest-api"
  namespace      = local.namespace
  image          = var.ingest_image
  container_port = 8080
  env_vars = merge(local.common_env_vars, {
    "INGEST_OUT_DIR" = "/sub-pc-frames"
  })
  volumes = [
    local.volume_definitions["sub-pc-frames"]
  ]
  volume_mounts = [
    local.volume_mount_definitions["sub-pc-frames"]
  ]
  probes = {
    enabled = true
    port    = 8080
    path    = "/healthz"
  }
}

# 5. Results API (NodePort)
module "results_api_service" {
  source = "./modules/service"

  name         = "results-api"
  namespace    = local.namespace
  selector_app = "results-api"
  type         = "NodePort"
  ports = [{
    port        = 8081
    target_port = 8081
    node_port   = 30081
  }]
}

module "results_api_deployment" {
  source    = "./modules/deployment"
  depends_on = [module.segments_pvc]

  name           = "results-api"
  namespace      = local.namespace
  image          = var.shared_image
  container_port = 8081
  command = [
    "uvicorn"
  ]
  args = [
    "services.results_api.app:app",
    "--host", "0.0.0.0",
    "--port", "8081",
    "--workers", "1"
  ]
  env_vars = merge(local.common_env_vars, {
    "SEGMENTS_DIR" = "/segments"
  })
  volumes = [
    local.volume_definitions["segments"]
  ]
  volume_mounts = [
    local.volume_mount_definitions["segments"]
  ]
  probes = {
    enabled = true
    port    = 8081
    path    = "/healthz"
  }
}

# 6. QA Web (NodePort)
module "qa_web_service" {
  source = "./modules/service"

  name         = "qa-web"
  namespace    = local.namespace
  selector_app = "qa-web"
  type         = "NodePort"
  ports = [{
    port        = 8082
    target_port = 8082
    node_port   = 30082
  }]
}

module "qa_web_deployment" {
  source = "./modules/deployment"

  name           = "qa-web"
  namespace      = local.namespace
  image          = var.shared_image
  container_port = 8082
  command = [
    "uvicorn"
  ]
  args = [
    "services.qa_web.app:app",
    "--host", "0.0.0.0",
    "--port", "8082",
    "--workers", "1"
  ]
  env_vars = merge(local.common_env_vars, {
    "RESULTS_API_URL" = "http://results-api.${local.namespace}.svc.cluster.local:8081"
  })
  # No volumes for QA Web
  probes = {
    enabled = true
    port    = 8082
    path    = "/healthz"
  }
}

# 7. Worker: convert-ply
module "convert_ply_deployment" {
  source    = "./modules/deployment"
  depends_on = [module.sub_pc_frames_pvc, module.pc_frames_pvc, module.segments_pvc]

  name      = "convert-ply"
  namespace = local.namespace
  image     = var.shared_image
  command = [
    "python3"
  ]
  args = [
    "/semantic-segmenter/services/convert_service/convert-ply",
    "--in-dir", "/sub-pc-frames",
    "--out-dir", "/pc-frames",
    "--preview-out-dir", "/segments",
    "--delete-source",
    "--log-level", "info"
  ]
  env_vars = merge(local.common_env_vars, local.worker_env_vars)
  volumes = [
    local.volume_definitions["sub-pc-frames"],
    local.volume_definitions["pc-frames"],
    local.volume_definitions["segments"]
  ]
  volume_mounts = [
    local.volume_mount_definitions["sub-pc-frames"],
    local.volume_mount_definitions["pc-frames"],
    local.volume_mount_definitions["segments"]
  ]
  # No probes or ports for this worker
}

# 8. Worker: part-labeler
module "part_labeler_deployment" {
  source    = "./modules/deployment"
  depends_on = [module.pc_frames_pvc, module.segments_pvc]

  name      = "part-labeler"
  namespace = local.namespace
  image     = var.shared_image
  command = [
    "python3"
  ]
  args = [
    "/semantic-segmenter/services/part_labeler/part_labeler.py",
    "--log-level", "info",
    "--out-dir", "/segments",
    "--colorized-dir", "/segments/labels",
    "--write-colorized"
  ]
  env_vars = merge(local.common_env_vars, local.worker_env_vars)
  volumes = [
    local.volume_definitions["pc-frames"],
    local.volume_definitions["segments"]
  ]
  volume_mounts = [
    local.volume_mount_definitions["pc-frames"],
    local.volume_mount_definitions["segments"]
  ]
}

# 9. Worker: redactor
module "redactor_deployment" {
  source    = "./modules/deployment"
  depends_on = [module.pc_frames_pvc, module.segments_pvc]

  name      = "redactor"
  namespace = local.namespace
  image     = var.shared_image
  command = [
    "python3"
  ]
  args = [
    "/semantic-segmenter/services/redactor/redactor.py",
    "--log-level", "info",
    "--out-dir", "/segments"
  ]
  env_vars = merge(local.common_env_vars, local.worker_env_vars)
  volumes = [
    local.volume_definitions["pc-frames"],
    local.volume_definitions["segments"]
  ]
  volume_mounts = [
    local.volume_mount_definitions["pc-frames"],
    local.volume_mount_definitions["segments"]
  ]
}

# 10. Worker: analytics
module "analytics_deployment" {
  source    = "./modules/deployment"
  depends_on = [module.segments_pvc]

  name      = "analytics"
  namespace = local.namespace
  image     = var.shared_image
  command = [
    "python3"
  ]
  args = [
    "/semantic-segmenter/services/analytics/analytics.py",
    "--log-level", "info",
    "--out-dir", "/segments"
  ]
  env_vars = merge(local.common_env_vars, local.worker_env_vars)
  volumes = [
    local.volume_definitions["segments"]
  ]
  volume_mounts = [
    local.volume_mount_definitions["segments"]
  ]
}