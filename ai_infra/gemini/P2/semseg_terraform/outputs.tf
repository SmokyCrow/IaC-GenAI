# Outputs the URLs for the NodePort services
# Assumes Docker Desktop is running on localhost.

output "ingest_api_url" {
  description = "The URL for the ingest-api NodePort service."
  value       = "http://localhost:30080"
}

output "results_api_url" {
  description = "The URL for the results-api NodePort service."
  value       = "http://localhost:30081"
}

output "qa_web_url" {
  description = "The URL for the qa-web NodePort service."
  value       = "http://localhost:30082"
}