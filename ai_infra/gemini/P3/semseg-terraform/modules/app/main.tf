# Locals for common environment variables
locals {
  redis_url = "redis://redis.${var.namespace}.svc.cluster.local:6379/0"

  # Stream names
  redis_stream_frames_converted = "s_frames_converted"
  redis_stream_parts_labeled    = "s_parts_labeled"
  redis_stream_redacted_done    = "s_redacted_done"
  redis_stream_analytics_done   = "s_analytics_done"

  # Group names
  redis_group_part_labeler = "g_part_labeler"
  redis_group_redactor     = "g_redactor"
  redis_group_analytics    = "g_analytics"

  # Common env vars for workers
  worker_env_vars = {
    REDIS_URL                     = local.redis_url
    REDIS_STREAM_FRAMES_CONVERTED = local.redis_stream_frames_converted
    REDIS_STREAM_PARTS_LABELED    = local.redis_stream_parts_labeled
    REDIS_STREAM_REDACTED_DONE    = local.redis_stream_redacted_done
    REDIS_STREAM_ANALYTICS_DONE   = local.redis_stream_analytics_done
    REDIS_GROUP_PART_LABELER      = local.redis_group_part_labeler
    REDIS_GROUP_REDACTOR          = local.redis_group_redactor
    REDIS_GROUP_ANALYTICS         = local.redis_group_analytics
  }

  # Basic resource requests for services
  default_resources = {
    requests = {
      cpu    = "100m"
      memory = "256Mi"
    }
    limits = {
      cpu    = "500m"
      memory = "512Mi"
    }
  }
}

# 1. --- Persistent Volume Claims ---

module "sub_pc_frames_pvc" {
  source             = "../pvc"
  name               = "sub-pc-frames-pvc"
  namespace          = var.namespace
  storage_class_name = var.pvc_storage_class_name
  storage_size       = "64Mi"
}

module "pc_frames_pvc" {
  source             = "../pvc"
  name               = "pc-frames-pvc"
  namespace          = var.namespace
  storage_class_name = var.pvc_storage_class_name
  storage_size       = "128Mi"
}

module "segments_pvc" {
  source             = "../pvc"
  name               = "segments-pvc"
  namespace          = var.namespace
  storage_class_name = var.pvc_storage_class_name
  storage_size       = "256Mi"
}

# 2. --- Redis ---

module "redis_deployment" {
  source            = "../deployment"
  name              = "redis"
  namespace         = var.namespace
  image             = "redis:7-alpine"
  image_pull_policy = "Always" # This is a public image
  container_port    = 6379
  args              = ["--appendonly", "yes", "--save", ""]
  resources         = local.default_resources
}

module "redis_service" {
  source         = "../service"
  name           = "redis"
  namespace      = var.namespace
  service_type   = "ClusterIP"
  selector_app   = "redis"
  port           = 6379
  target_port    = 6379
}

# 3. --- Web APIs ---

# Ingest API
module "ingest_api_deployment" {
  source         = "../deployment"
  name           = "ingest-api"
  namespace      = var.namespace
  image          = var.ingest_image
  container_port = 8080
  env_vars = {
    REDIS_URL      = local.redis_url
    INGEST_OUT_DIR = "/sub-pc-frames"
  }
  volumes = [{
    name      = "sub-pc-frames-vol"
    pvc_claim = module.sub_pc_frames_pvc.pvc_name
  }]
  volume_mounts = [{
    name       = "sub-pc-frames-vol"
    mount_path = "/sub-pc-frames"
  }]
  liveness_probe = {
    path = "/healthz",
    port = 8080
  }
  readiness_probe = {
    path = "/healthz",
    port = 8080
  }
  resources = local.default_resources
  depends_on = [
    module.redis_service # Ensure redis is created first
  ]
}

module "ingest_api_service" {
  source         = "../service"
  name           = "ingest-api"
  namespace      = var.namespace
  service_type   = "NodePort"
  selector_app   = "ingest-api"
  port           = 80
  target_port    = 8080
  node_port      = var.node_port_base + 0
}

# Results API
module "results_api_deployment" {
  source         = "../deployment"
  name           = "results-api"
  namespace      = var.namespace
  image          = var.image_repo
  container_port = 8081
  command        = ["bash", "-lc"]
  # --- FIX: Combine args into a single string for 'bash -c' ---
  args = ["uvicorn services.results_api.app:app --host 0.0.0.0 --port 8081 --workers 1"]
  env_vars = {
    REDIS_URL     = local.redis_url
    SEGMENTS_DIR  = "/segments"
  }
  volumes = [{
    name      = "segments-vol"
    pvc_claim = module.segments_pvc.pvc_name
  }]
  volume_mounts = [{
    name       = "segments-vol"
    mount_path = "/segments"
  }]
  liveness_probe = {
    path = "/healthz",
    port = 8081
  }
  readiness_probe = {
    path = "/healthz",
    port = 8081
  }
  resources = local.default_resources
  depends_on = [
    module.redis_service
  ]
}

module "results_api_service" {
  source         = "../service"
  name           = "results-api"
  namespace      = var.namespace
  service_type   = "NodePort"
  selector_app   = "results-api"
  port           = 80
  target_port    = 8081
  node_port      = var.node_port_base + 1
}

# QA Web
module "qa_web_deployment" {
  source         = "../deployment"
  name           = "qa-web"
  namespace      = var.namespace
  image          = var.image_repo
  container_port = 8082
  command        = ["bash", "-lc"]
  # --- FIX: Combine args into a single string for 'bash -c' ---
  args = ["uvicorn services.qa_web.app:app --host 0.0.0.0 --port 8082 --workers 1"]
  env_vars = {
    REDIS_URL       = local.redis_url
    # Service name resolution, no port needed due to service port=80
    RESULTS_API_URL = "http://results-api.${var.namespace}.svc.cluster.local"
  }
  liveness_probe = {
    path = "/healthz",
    port = 8082
  }
  readiness_probe = {
    path = "/healthz",
    port = 8082
  }
  resources = local.default_resources
  depends_on = [
    module.redis_service,
    module.results_api_service # Depends on the results API
  ]
}

module "qa_web_service" {
  source         = "../service"
  name           = "qa-web"
  namespace      = var.namespace
  service_type   = "NodePort"
  selector_app   = "qa-web"
  port           = 80
  target_port    = 8082
  node_port      = var.node_port_base + 2
}

# 4. --- Worker Services ---

# Convert PLY
module "convert_ply_deployment" {
  source    = "../deployment"
  name      = "convert-ply"
  namespace = var.namespace
  image     = var.image_repo
  command   = ["python3", "/semantic-segmenter/services/convert_service/convert-ply"]
  args = [
    "--in-dir", "/sub-pc-frames",
    "--out-dir", "/pc-frames",
    "--preview-out-dir", "/segments",
    "--delete-source",
    "--log-level", "info"
  ]
  env_vars = local.worker_env_vars
  volumes = [
    { name = "sub-pc-frames", pvc_claim = module.sub_pc_frames_pvc.pvc_name },
    { name = "pc-frames", pvc_claim = module.pc_frames_pvc.pvc_name },
    { name = "segments", pvc_claim = module.segments_pvc.pvc_name }
  ]
  volume_mounts = [
    { name = "sub-pc-frames", mount_path = "/sub-pc-frames" },
    { name = "pc-frames", mount_path = "/pc-frames" },
    { name = "segments", mount_path = "/segments" }
  ]
  resources = local.default_resources
  depends_on = [
    module.redis_service
  ]
}

# Part Labeler
module "part_labeler_deployment" {
  source    = "../deployment"
  name      = "part-labeler"
  namespace = var.namespace
  image     = var.image_repo
  command   = ["bash", "-lc"]
  # --- FIX: Combine args into a single string for 'bash -c' ---
  args = [
    "python3 /semantic-segmenter/services/part_labeler/part_labeler.py --log-level info --out-dir /segments --colorized-dir /segments/labels --write-colorized"
  ]
  env_vars = local.worker_env_vars
  volumes = [
    { name = "pc-frames", pvc_claim = module.pc_frames_pvc.pvc_name },
    { name = "segments", pvc_claim = module.segments_pvc.pvc_name }
  ]
  volume_mounts = [
    { name = "pc-frames", mount_path = "/pc-frames" },
    { name = "segments", mount_path = "/segments" }
  ]
  resources = local.default_resources
  depends_on = [
    module.redis_service
  ]
}

# Redactor
module "redactor_deployment" {
  source    = "../deployment"
  name      = "redactor"
  namespace = var.namespace
  image     = var.image_repo
  command   = ["bash", "-lc"]
  # --- FIX: Combine args into a single string for 'bash -c' ---
  args = [
    "python3 /semantic-segmenter/services/redactor/redactor.py --log-level info --out-dir /segments"
  ]
  env_vars = local.worker_env_vars
  volumes = [
    { name = "pc-frames", pvc_claim = module.pc_frames_pvc.pvc_name },
    { name = "segments", pvc_claim = module.segments_pvc.pvc_name }
  ]
  volume_mounts = [
    { name = "pc-frames", mount_path = "/pc-frames" },
    { name = "segments", mount_path = "/segments" }
  ]
  resources = local.default_resources
  depends_on = [
    module.redis_service
  ]
}

# Analytics
module "analytics_deployment" {
  source    = "../deployment"
  name      = "analytics"
  namespace = var.namespace
  image     = var.image_repo
  command   = ["bash", "-lc"]
  # --- FIX: Combine args into a single string for 'bash -c' ---
  args = [
    "python3 /semantic-segmenter/services/analytics/analytics.py --log-level info --out-dir /segments"
  ]
  env_vars = local.worker_env_vars
  volumes = [
    { name = "segments", pvc_claim = module.segments_pvc.pvc_name }
  ]
  volume_mounts = [
    { name = "segments", mount_path = "/segments" }
  ]
  resources = local.default_resources
  depends_on = [
    module.redis_service
  ]
}