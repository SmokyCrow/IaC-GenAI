module "deployment" {
  source = "../deployment"

  name              = var.name
  namespace         = var.namespace
  image             = var.image
  image_pull_policy = var.image_pull_policy
  replicas          = var.replicas
  port              = var.port
  command           = var.command
  args              = var.args
  environment       = var.environment
  volumes           = var.volumes
  resources         = var.resources

  liveness_probe = var.enable_health_probes && var.port != null ? {
    path                  = "/healthz"
    port                  = var.port
    initial_delay_seconds = 10
    period_seconds        = 10
    timeout_seconds       = 5
    failure_threshold     = 3
  } : null

  readiness_probe = var.enable_health_probes && var.port != null ? {
    path                  = "/healthz"
    port                  = var.port
    initial_delay_seconds = 5
    period_seconds        = 5
    timeout_seconds       = 3
    failure_threshold     = 3
  } : null
}

module "service" {
  count  = var.port != null ? 1 : 0
  source = "../service"

  name         = var.name
  namespace    = var.namespace
  selector_app = var.name
  type         = var.service_type
  port         = var.service_port != null ? var.service_port : var.port
  target_port  = var.port
  node_port    = var.node_port
}
