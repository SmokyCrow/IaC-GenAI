output "namespace" {
  description = "The namespace where the app is deployed."
  value       = var.namespace
}

output "ingest_service_name" {
  description = "Name of the ingest API service."
  value       = module.ingest_api_service.service_name
}

output "results_service_name" {
  description = "Name of the results API service."
  value       = module.results_api_service.service_name
}

output "qa_web_service_name" {
  description = "Name of the QA Web service."
  value       = module.qa_web_service.service_name
}

output "redis_service_name" {
  description = "Name of the Redis service."
  value       = module.redis_service.service_name
}