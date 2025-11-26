# service module

Reusable Kubernetes Service with optional NodePort.

## Inputs
- name (string, required)
- namespace (string, required)
- labels (map(string), optional)
- selector (map(string), required): Pod selector
- port (number, required): Service port
- target_port (number, required): Target container port
- type (string, default: "ClusterIP")
- node_port (number, optional): Only used when type = "NodePort"

## Outputs
- name: Service name

## Example
```hcl
module "svc" {
  source      = "./modules/service"
  name        = "my-api"
  namespace   = var.namespace
  selector    = { app = "my-api" }
  type        = "NodePort"
  port        = 80
  target_port = 8080
  node_port   = 30080
}
```