locals {
  ns = var.namespace
}

# Redis via reusable modules
module "deploy_redis" {
  source          = "../deployment"
  name            = "redis"
  namespace       = local.ns
  labels          = { app = "redis" }
  image           = "redis:7-alpine"
  container_name  = "redis"
  container_ports = [6379]
  args            = ["--appendonly", "yes", "--save", ""]
}

module "svc_redis" {
  source      = "../service"
  name        = "redis"
  namespace   = local.ns
  selector    = { app = "redis" }
  port        = 6379
  target_port = 6379
}

locals {
  redis_url = "redis://${module.svc_redis.name}.${local.ns}.svc.cluster.local:6379/0"
}

module "pvc_sub" {
  source    = "../pvc"
  name      = "sub-pc-frames-pvc"
  namespace = local.ns
  storage   = "64Mi"
  storage_class_name = var.pvc_storage_class_name
  volume_binding_mode = var.pvc_volume_binding_mode
}

module "pvc_pc" {
  source    = "../pvc"
  name      = "pc-frames-pvc"
  namespace = local.ns
  storage   = "128Mi"
  storage_class_name = var.pvc_storage_class_name
  volume_binding_mode = var.pvc_volume_binding_mode
}

module "pvc_segments" {
  source    = "../pvc"
  name      = "segments-pvc"
  namespace = local.ns
  storage   = "256Mi"
  storage_class_name = var.pvc_storage_class_name
  volume_binding_mode = var.pvc_volume_binding_mode
}

module "deploy_convert" {
  source         = "../deployment"
  name           = "convert-ply"
  namespace      = local.ns
  labels         = { app = "convert-ply" }
  image          = var.image_repo
  container_name = "convert"
  command        = ["python3","/semantic-segmenter/services/convert_service/convert-ply"]
  args           = ["--in-dir","/sub-pc-frames","--out-dir","/pc-frames","--preview-out-dir","/segments","--delete-source","--log-level","info"]
  env = {
    REDIS_URL                     = local.redis_url
    REDIS_STREAM_FRAMES_CONVERTED = "s_frames_converted"
    PREVIEW_OUT_DIR               = "/segments"
  }
  readiness_exec = ["sh","-lc","test -d /pc-frames || true"]
  readiness_initial_delay_seconds = 5
  readiness_period_seconds        = 10
  volume_mounts = [
    { name = "sub", mount_path = "/sub-pc-frames" },
    { name = "pc",  mount_path = "/pc-frames" },
    { name = "seg", mount_path = "/segments" }
  ]
  volumes = [
    { name = "sub", claim_name = module.pvc_sub.name },
    { name = "pc",  claim_name = module.pvc_pc.name },
    { name = "seg", claim_name = module.pvc_segments.name }
  ]
}

module "deploy_labeler" {
  source         = "../deployment"
  name           = "part-labeler"
  namespace      = local.ns
  labels         = { app = "part-labeler" }
  image          = var.image_repo
  container_name = "part-labeler"
  command        = ["bash","-lc"]
  args           = ["python3 /semantic-segmenter/services/part_labeler/part_labeler.py --log-level info --out-dir /segments --colorized-dir /segments/labels --write-colorized"]
  env = {
    REDIS_URL                     = local.redis_url
    REDIS_STREAM_PARTS_LABELED    = "s_parts_labeled"
    REDIS_STREAM_FRAMES_CONVERTED = "s_frames_converted"
    REDIS_GROUP_PART_LABELER      = "g_part_labeler"
  }
  volume_mounts = [
    { name = "pc",  mount_path = "/pc-frames" },
    { name = "seg", mount_path = "/segments" }
  ]
  volumes = [
    { name = "pc",  claim_name = module.pvc_pc.name },
    { name = "seg", claim_name = module.pvc_segments.name }
  ]
}

module "deploy_redactor" {
  source         = "../deployment"
  name           = "redactor"
  namespace      = local.ns
  labels         = { app = "redactor" }
  image          = var.image_repo
  container_name = "redactor"
  command        = ["bash","-lc"]
  args           = ["python3 /semantic-segmenter/services/redactor/redactor.py --log-level info --out-dir /segments"]
  env = {
    REDIS_URL                  = local.redis_url
    REDIS_STREAM_PARTS_LABELED = "s_parts_labeled"
    REDIS_STREAM_REDACTED_DONE = "s_redacted_done"
    REDIS_GROUP_REDACTOR       = "g_redactor"
  }
  volume_mounts = [
    { name = "pc",  mount_path = "/pc-frames" },
    { name = "seg", mount_path = "/segments" }
  ]
  volumes = [
    { name = "pc",  claim_name = module.pvc_pc.name },
    { name = "seg", claim_name = module.pvc_segments.name }
  ]
}

module "deploy_analytics" {
  source         = "../deployment"
  name           = "analytics"
  namespace      = local.ns
  labels         = { app = "analytics" }
  image          = var.image_repo
  container_name = "analytics"
  command        = ["bash","-lc"]
  args           = ["python3 /semantic-segmenter/services/analytics/analytics.py --log-level info --out-dir /segments"]
  env = {
    REDIS_URL                   = local.redis_url
    REDIS_STREAM_PARTS_LABELED  = "s_parts_labeled"
    REDIS_STREAM_ANALYTICS_DONE = "s_analytics_done"
    REDIS_GROUP_ANALYTICS       = "g_analytics"
  }
  volume_mounts = [
    { name = "seg", mount_path = "/segments" }
  ]
  volumes = [
    { name = "seg", claim_name = module.pvc_segments.name }
  ]
}

module "deploy_results" {
  source          = "../deployment"
  name            = "results-api"
  namespace       = local.ns
  labels          = { app = "results-api" }
  image           = var.image_repo
  container_name  = "results-api"
  container_ports = [8081]
  command         = ["bash","-lc"]
  args            = ["uvicorn services.results_api.app:app --host 0.0.0.0 --port 8081 --workers 1"]
  env = {
    SEGMENTS_DIR                  = "/segments"
    REDIS_URL                     = local.redis_url
    REDIS_STREAM_FRAMES_CONVERTED = "s_frames_converted"
    REDIS_STREAM_PARTS_LABELED    = "s_parts_labeled"
    REDIS_STREAM_REDACTED_DONE    = "s_redacted_done"
    REDIS_STREAM_ANALYTICS_DONE   = "s_analytics_done"
  }
  readiness_http = {
    path = "/healthz"
    port = 8081
  }
  readiness_initial_delay_seconds = 3
  readiness_period_seconds        = 5
  liveness_http = {
    path = "/healthz"
    port = 8081
  }
  liveness_initial_delay_seconds = 10
  liveness_period_seconds        = 10
  volume_mounts = [
    { name = "seg", mount_path = "/segments" }
  ]
  volumes = [
    { name = "seg", claim_name = module.pvc_segments.name }
  ]
}

module "svc_results" {
  source      = "../service"
  name        = "results-api"
  namespace   = local.ns
  selector    = { app = "results-api" }
  type        = "NodePort"
  port        = 80
  target_port = 8081
  node_port   = var.node_port_base + 1
}

module "deploy_qa" {
  source          = "../deployment"
  name            = "qa-web"
  namespace       = local.ns
  labels          = { app = "qa-web" }
  image           = var.image_repo
  container_name  = "qa-web"
  container_ports = [8082]
  command         = ["bash","-lc"]
  args            = ["uvicorn services.qa_web.app:app --host 0.0.0.0 --port 8082 --workers 1"]
  env = {
    RESULTS_API_URL = "http://results-api.${local.ns}.svc.cluster.local"
  }
  readiness_http = {
    path = "/healthz"
    port = 8082
  }
  readiness_initial_delay_seconds = 3
  readiness_period_seconds        = 5
  liveness_http = {
    path = "/healthz"
    port = 8082
  }
  liveness_initial_delay_seconds = 10
  liveness_period_seconds        = 10
}

module "svc_qa" {
  source      = "../service"
  name        = "qa-web"
  namespace   = local.ns
  selector    = { app = "qa-web" }
  type        = "NodePort"
  port        = 80
  target_port = 8082
  node_port   = var.node_port_base + 2
}

module "deploy_ingest" {
  source          = "../deployment"
  name            = "ingest-api"
  namespace       = local.ns
  labels          = { app = "ingest-api" }
  image           = var.ingest_image
  container_name  = "ingest"
  container_ports = [8080]
  env = {
    INGEST_OUT_DIR = "/sub-pc-frames"
  }
  readiness_http = {
    path = "/healthz"
    port = 8080
  }
  readiness_initial_delay_seconds = 3
  readiness_period_seconds        = 5
  liveness_http = {
    path = "/healthz"
    port = 8080
  }
  liveness_initial_delay_seconds = 10
  liveness_period_seconds        = 10
  volume_mounts = [
    { name = "sub", mount_path = "/sub-pc-frames" }
  ]
  volumes = [
    { name = "sub", claim_name = module.pvc_sub.name }
  ]
}

module "svc_ingest" {
  source      = "../service"
  name        = "ingest-api"
  namespace   = local.ns
  selector    = { app = "ingest-api" }
  type        = "NodePort"
  port        = 80
  target_port = 8080
  node_port   = var.node_port_base + 0
}
