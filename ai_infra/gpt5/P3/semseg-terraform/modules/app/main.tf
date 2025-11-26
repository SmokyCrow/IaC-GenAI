locals {
  # Common environment variables
  common_env = {
    REDIS_URL                   = "redis://redis.${var.namespace}.svc.cluster.local:6379/0"
    REDIS_STREAM_FRAMES_CONVERTED = "s_frames_converted"
    REDIS_STREAM_PARTS_LABELED    = "s_parts_labeled"
    REDIS_STREAM_REDACTED_DONE    = "s_redacted_done"
    REDIS_STREAM_ANALYTICS_DONE   = "s_analytics_done"
    REDIS_GROUP_PART_LABELER      = "g_part_labeler"
    REDIS_GROUP_REDACTOR          = "g_redactor"
    REDIS_GROUP_ANALYTICS         = "g_analytics"
  }

  probe_ingest = {
    path               = "/healthz"
    port               = 8080
    initial_delay_secs = 5
    period_secs        = 10
  }
  probe_results = {
    path               = "/healthz"
    port               = 8081
    initial_delay_secs = 5
    period_secs        = 10
  }
  probe_qa = {
    path               = "/healthz"
    port               = 8082
    initial_delay_secs = 5
    period_secs        = 10
  }
}

# --- PVCs ---
module "pvc_sub_pc_frames" {
  source               = "../pvc"
  name                 = "sub-pc-frames-pvc"
  namespace            = var.namespace
  storage_class_name   = var.pvc_storage_class_name
  size                 = "64Mi"
}

module "pvc_pc_frames" {
  source               = "../pvc"
  name                 = "pc-frames-pvc"
  namespace            = var.namespace
  storage_class_name   = var.pvc_storage_class_name
  size                 = "128Mi"
}

module "pvc_segments" {
  source               = "../pvc"
  name                 = "segments-pvc"
  namespace            = var.namespace
  storage_class_name   = var.pvc_storage_class_name
  size                 = "256Mi"
}

# --- Deployments ---

# ingest-api
module "dep_ingest_api" {
  source          = "../deployment"
  name            = "ingest-api"
  namespace       = var.namespace
  image           = var.ingest_image
  container_port  = 8080
  image_pull_policy = "IfNotPresent"

  env = merge(local.common_env, {
    INGEST_OUT_DIR = "/sub-pc-frames"
  })

  readiness_probe = local.probe_ingest
  liveness_probe  = merge(local.probe_ingest, { initial_delay_secs = 10 })

  volume_mounts = [
    { name = "sub-pc-frames", mount_path = "/sub-pc-frames" }
  ]

  volumes = [
    { name = "sub-pc-frames", claim_name = module.pvc_sub_pc_frames.name }
  ]
}

# results-api
module "dep_results_api" {
  source            = "../deployment"
  name              = "results-api"
  namespace         = var.namespace
  image             = var.image_repo
  container_port    = 8081
  image_pull_policy = "IfNotPresent"

  env = merge(local.common_env, {
    SEGMENTS_DIR = "/segments"
  })

  command = ["bash"]
  args    = ["-lc", "uvicorn services.results_api.app:app --host 0.0.0.0 --port 8081 --workers 1"]

  readiness_probe = local.probe_results
  liveness_probe  = merge(local.probe_results, { initial_delay_secs = 10 })

  volume_mounts = [
    { name = "segments", mount_path = "/segments" }
  ]

  volumes = [
    { name = "segments", claim_name = module.pvc_segments.name }
  ]
}

# qa-web
module "dep_qa_web" {
  source            = "../deployment"
  name              = "qa-web"
  namespace         = var.namespace
  image             = var.image_repo
  container_port    = 8082
  image_pull_policy = "IfNotPresent"

  env = merge(local.common_env, {
    RESULTS_API_URL = "http://results-api.${var.namespace}.svc.cluster.local"
  })

  command = ["bash"]
  args    = ["-lc", "uvicorn services.qa_web.app:app --host 0.0.0.0 --port 8082 --workers 1"]

  readiness_probe = local.probe_qa
  liveness_probe  = merge(local.probe_qa, { initial_delay_secs = 10 })
}

# convert-ply
module "dep_convert_ply" {
  source            = "../deployment"
  name              = "convert-ply"
  namespace         = var.namespace
  image             = var.image_repo
  container_port    = 8081 # unused but must be defined; no service targets this
  image_pull_policy = "IfNotPresent"

  env = merge(local.common_env, {
    PREVIEW_OUT_DIR = "/segments"
  })

  command = ["python3", "/semantic-segmenter/services/convert_service/convert-ply"]
  args = [
    "--in-dir", "/sub-pc-frames",
    "--out-dir", "/pc-frames",
    "--preview-out-dir", "/segments",
    "--delete-source",
    "--log-level", "info"
  ]

  volume_mounts = [
    { name = "sub-pc-frames", mount_path = "/sub-pc-frames" },
    { name = "pc-frames",     mount_path = "/pc-frames"     },
    { name = "segments",      mount_path = "/segments"      }
  ]

  volumes = [
    { name = "sub-pc-frames", claim_name = module.pvc_sub_pc_frames.name },
    { name = "pc-frames",     claim_name = module.pvc_pc_frames.name     },
    { name = "segments",      claim_name = module.pvc_segments.name      }
  ]
}

# part-labeler
module "dep_part_labeler" {
  source            = "../deployment"
  name              = "part-labeler"
  namespace         = var.namespace
  image             = var.image_repo
  container_port    = 8081 # placeholder
  image_pull_policy = "IfNotPresent"

  env     = local.common_env
  command = ["bash"]
  args    = ["-lc", "python3 /semantic-segmenter/services/part_labeler/part_labeler.py --log-level info --out-dir /segments --colorized-dir /segments/labels --write-colorized"]

  volume_mounts = [
    { name = "pc-frames", mount_path = "/pc-frames" },
    { name = "segments",  mount_path = "/segments"  }
  ]

  volumes = [
    { name = "pc-frames", claim_name = module.pvc_pc_frames.name },
    { name = "segments",  claim_name = module.pvc_segments.name  }
  ]
}

# redactor
module "dep_redactor" {
  source            = "../deployment"
  name              = "redactor"
  namespace         = var.namespace
  image             = var.image_repo
  container_port    = 8081 # placeholder
  image_pull_policy = "IfNotPresent"

  env     = local.common_env
  command = ["bash"]
  args    = ["-lc", "python3 /semantic-segmenter/services/redactor/redactor.py --log-level info --out-dir /segments"]

  volume_mounts = [
    { name = "pc-frames", mount_path = "/pc-frames" },
    { name = "segments",  mount_path = "/segments"  }
  ]

  volumes = [
    { name = "pc-frames", claim_name = module.pvc_pc_frames.name },
    { name = "segments",  claim_name = module.pvc_segments.name  }
  ]
}

# analytics
module "dep_analytics" {
  source            = "../deployment"
  name              = "analytics"
  namespace         = var.namespace
  image             = var.image_repo
  container_port    = 8081 # placeholder
  image_pull_policy = "IfNotPresent"

  env     = local.common_env
  command = ["bash"]
  args    = ["-lc", "python3 /semantic-segmenter/services/analytics/analytics.py --log-level info --out-dir /segments"]

  volume_mounts = [
    { name = "segments", mount_path = "/segments" }
  ]

  volumes = [
    { name = "segments", claim_name = module.pvc_segments.name }
  ]
}

# redis
module "dep_redis" {
  source            = "../deployment"
  name              = "redis"
  namespace         = var.namespace
  image             = "redis:7-alpine"
  container_port    = 6379
  image_pull_policy = "IfNotPresent"

  command = ["redis-server"]
  args    = ["--appendonly", "yes", "--save", ""]

  # No probes required; lightweight default resources are OK
}

# --- Services ---

module "svc_ingest_api" {
  source      = "../service"
  name        = "ingest-api"
  namespace   = var.namespace
  type        = "NodePort"
  port        = 80
  target_port = 8080
  node_port   = var.node_port_base + 0
}

module "svc_results_api" {
  source      = "../service"
  name        = "results-api"
  namespace   = var.namespace
  type        = "NodePort"
  port        = 80
  target_port = 8081
  node_port   = var.node_port_base + 1
}

module "svc_qa_web" {
  source      = "../service"
  name        = "qa-web"
  namespace   = var.namespace
  type        = "NodePort"
  port        = 80
  target_port = 8082
  node_port   = var.node_port_base + 2
}

module "svc_redis" {
  source      = "../service"
  name        = "redis"
  namespace   = var.namespace
  type        = "ClusterIP"
  port        = 6379
  target_port = 6379
}
