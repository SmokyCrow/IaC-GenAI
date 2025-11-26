output "redis_url" {
  description = "Redis connection URL"
  value       = local.redis_url
}

output "results_service_name" {
  value = module.svc_results.name
}

output "qa_service_name" {
  value = module.svc_qa.name
}

output "ingest_service_name" {
  value = module.svc_ingest.name
}

output "results_url" {
  description = "External URL for results-api (NodePort)"
  value       = "http://localhost:${var.node_port_base + 1}"
}

output "qa_url" {
  description = "External URL for qa-web (NodePort)"
  value       = "http://localhost:${var.node_port_base + 2}"
}

output "ingest_url" {
  description = "External URL for ingest-api (NodePort)"
  value       = "http://localhost:${var.node_port_base + 0}"
}
