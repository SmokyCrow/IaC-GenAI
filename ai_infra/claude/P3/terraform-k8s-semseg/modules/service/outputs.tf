output "name" {
  description = "Name of the service"
  value       = kubernetes_service.this.metadata[0].name
}

output "namespace" {
  description = "Namespace of the service"
  value       = kubernetes_service.this.metadata[0].namespace
}

output "cluster_ip" {
  description = "Cluster IP of the service"
  value       = kubernetes_service.this.spec[0].cluster_ip
}
