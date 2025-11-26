output "ingest_url" {
  description = "The local URL for the Ingest API."
  value       = "http://localhost:${var.node_port_base + 0}"
}

output "results_url" {
  description = "The local URL for the Results API."
  value       = "http://localhost:${var.node_port_base + 1}"
}

output "qa_url" {
  description = "The local URL for the QA Web UI."
  value       = "http://localhost:${var.node_port_base + 2}"
}

output "namespace" {
  description = "The namespace where the application is deployed."
  value       = module.app.namespace
}