output "ingest_url" {
  description = "URL for ingest API service"
  value       = "http://localhost:${var.node_port_base + 0}"
}

output "results_url" {
  description = "URL for results API service"
  value       = "http://localhost:${var.node_port_base + 1}"
}

output "qa_url" {
  description = "URL for QA web service"
  value       = "http://localhost:${var.node_port_base + 2}"
}
