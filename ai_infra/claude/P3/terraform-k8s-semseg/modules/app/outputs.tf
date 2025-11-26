output "deployment_name" {
  description = "Name of the deployment"
  value       = module.deployment.name
}

output "service_name" {
  description = "Name of the service (if created)"
  value       = length(module.service) > 0 ? module.service[0].name : null
}

output "service_cluster_ip" {
  description = "Cluster IP of the service (if created)"
  value       = length(module.service) > 0 ? module.service[0].cluster_ip : null
}
