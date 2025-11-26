# deployment module

Reusable Kubernetes Deployment for a single container. Supports env vars, probes, ports, volumes, and mounts.

## Inputs
- name (string, required): Deployment and container logical name (unless container_name set)
- namespace (string, required): K8s namespace
- labels (map(string), optional): Pod/selector labels
- replicas (number, default: 1)
- container_name (string, optional): Overrides container name
- image (string, required)
- image_pull_policy (string, default: IfNotPresent)
- container_ports (list(number), optional)
- command (list(string), optional)
- args (list(string), optional)
- env (map(string), optional): Environment variables
- volume_mounts (list(object{name, mount_path}), optional)
- volumes (list(object{name, claim_name}), optional)
- readiness_http (object{path, port}, optional)
- readiness_exec (list(string), optional): Exec command alternative to HTTP readiness
- readiness_initial_delay_seconds (number, default: 0)
- readiness_period_seconds (number, default: 10)
- liveness_http (object{path, port}, optional)
- liveness_initial_delay_seconds (number, default: 0)
- liveness_period_seconds (number, default: 10)

## Outputs
- name: Deployment name

## Example
```hcl
module "api" {
  source          = "./modules/deployment"
  name            = "my-api"
  namespace       = var.namespace
  labels          = { app = "my-api" }
  image           = "myrepo/my-api:latest"
  container_ports = [8080]
  env = { LOG_LEVEL = "info" }
  readiness_http = { path = "/healthz", port = 8080 }
}
```