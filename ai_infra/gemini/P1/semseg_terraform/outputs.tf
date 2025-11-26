output "qa_web_url" {
  description = "Access URL for the QA Web UI. Assumes Docker Desktop is on localhost."
  value       = "http://localhost:${kubernetes_service.svcs["qa-web"].spec[0].port[0].node_port}"
}

output "ingest_api_url" {
  description = "Access URL for the Ingest API. Assumes Docker Desktop is on localhost."
  value       = "http://localhost:${kubernetes_service.svcs["ingest-api"].spec[0].port[0].node_port}"
}

output "results_api_url" {
  description = "Access URL for the Results API. Assumes Docker Desktop is on localhost."
  value       = "http://localhost:${kubernetes_service.svcs["results-api"].spec[0].port[0].node_port}"
}

output "redis_cluster_ip" {
  description = "Internal ClusterIP for Redis (for use by other pods in the cluster)."
  value       = kubernetes_service.svcs["redis"].spec[0].cluster_ip
}

output "redis_service_name" {
  description = "Internal DNS name for Redis."
  value       = local.redis_service_url # Updated to show the full, correct URL
}

output "persistent_volume_claims" {
  description = "Map of Persistent Volume Claims created."
  value = {
    for k, v in kubernetes_persistent_volume_claim.main :
    k => "Created PVC '${v.metadata[0].name}' with size ${v.spec[0].resources[0].requests.storage}"
  }
}