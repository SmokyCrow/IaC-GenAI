# pvc module

Reusable PersistentVolumeClaim.

## Inputs
- name (string, required)
- namespace (string, required)
- storage (string, required): e.g., "2Gi" (adjust to cluster capacity)
- access_modes (list(string), default: ["ReadWriteOnce"])

## Outputs
- name: PVC claim name

## Example
```hcl
module "data" {
  source    = "./modules/pvc"
  name      = "data-pvc"
  namespace = var.namespace
  storage   = "2Gi"
}
```