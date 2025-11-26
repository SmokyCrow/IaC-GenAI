output "service_name" {
  description = "The name of the created service."
  value       = kubernetes_service.svc.metadata[0].name
}

output "cluster_ip" {
  description = "The ClusterIP of the service."
  value       = kubernetes_service.svc.spec[0].cluster_ip
}