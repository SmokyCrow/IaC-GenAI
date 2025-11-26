output "namespace" {
  description = "The Kubernetes namespace where resources are deployed"
  value       = kubernetes_namespace.semseg.metadata[0].name
}

output "ingest_api_nodeport" {
  description = "NodePort for the Ingest API service"
  value       = kubernetes_service.ingest_api.spec[0].port[0].node_port
}

output "results_api_nodeport" {
  description = "NodePort for the Results API service"
  value       = kubernetes_service.results_api.spec[0].port[0].node_port
}

output "qa_web_nodeport" {
  description = "NodePort for the QA Web UI service"
  value       = kubernetes_service.qa_web.spec[0].port[0].node_port
}

output "redis_service" {
  description = "Internal Redis service DNS name"
  value       = "redis.${kubernetes_namespace.semseg.metadata[0].name}.svc.cluster.local"
}

output "access_urls" {
  description = "URLs to access the application services on Docker Desktop"
  value = {
    qa_web      = "http://localhost:${kubernetes_service.qa_web.spec[0].port[0].node_port}"
    ingest_api  = "http://localhost:${kubernetes_service.ingest_api.spec[0].port[0].node_port}"
    results_api = "http://localhost:${kubernetes_service.results_api.spec[0].port[0].node_port}"
  }
}

output "deployment_status" {
  description = "List of deployed components"
  value = {
    deployments = [
      kubernetes_deployment.ingest_api.metadata[0].name,
      kubernetes_deployment.results_api.metadata[0].name,
      kubernetes_deployment.qa_web.metadata[0].name,
      kubernetes_deployment.convert_ply.metadata[0].name,
      kubernetes_deployment.part_labeler.metadata[0].name,
      kubernetes_deployment.redactor.metadata[0].name,
      kubernetes_deployment.analytics.metadata[0].name,
      kubernetes_deployment.redis.metadata[0].name,
    ]
    services = [
      kubernetes_service.ingest_api.metadata[0].name,
      kubernetes_service.results_api.metadata[0].name,
      kubernetes_service.qa_web.metadata[0].name,
      kubernetes_service.redis.metadata[0].name,
    ]
  }
}
