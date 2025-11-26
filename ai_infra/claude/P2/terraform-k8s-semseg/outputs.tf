output "ingest_api_url" {
  description = "Ingest API NodePort URL"
  value       = "http://localhost:30080"
}

output "results_api_url" {
  description = "Results API NodePort URL"
  value       = "http://localhost:30081"
}

output "qa_web_url" {
  description = "QA Web NodePort URL"
  value       = "http://localhost:30082"
}

output "namespace" {
  description = "Kubernetes namespace"
  value       = kubernetes_namespace.semseg.metadata[0].name
}

output "redis_service_url" {
  description = "Redis ClusterIP service URL"
  value       = "redis://redis.semseg.svc.cluster.local:6379/0"
}
