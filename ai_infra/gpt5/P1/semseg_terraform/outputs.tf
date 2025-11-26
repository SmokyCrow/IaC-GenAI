output "namespace" {
  description = "Namespace for the Semantic Segmenter stack"
  value       = module.ns.name
}

output "qa_web_nodeport" {
  description = "NodePort for qa-web (reachable on the k3s node IP)"
  value       = module.qa_web.node_port
}

output "services" {
  description = "ClusterIP services and ports"
  value = {
    ingest_api  = { name = module.ingest_api.service_name, port = module.ingest_api.service_port }
    results_api = { name = module.results_api.service_name, port = module.results_api.service_port }
    redis       = { name = module.redis.service_name, port = module.redis.service_port }
  }
}

output "ingest_api_nodeport" {
  description = "NodePort for ingest-api (reachable on the node IP)"
  value       = module.ingest_api.node_port
}
