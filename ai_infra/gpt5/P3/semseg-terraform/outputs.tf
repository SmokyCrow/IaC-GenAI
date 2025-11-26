output "ingest_url" {
  description = "NodePort URL for ingest-api"
  value       = "http://localhost:${var.node_port_base + 0}"
}

output "results_url" {
  description = "NodePort URL for results-api"
  value       = "http://localhost:${var.node_port_base + 1}"
}

output "qa_url" {
  description = "NodePort URL for qa-web"
  value       = "http://localhost:${var.node_port_base + 2}"
}
