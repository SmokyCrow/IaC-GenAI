# app module

One-call deploy of the semantic-segmenter stack:
- Redis (Deployment + Service)
- PVCs (sub, pc, segments)
- Deployments: convert, part-labeler, redactor, analytics, results-api, qa-web, ingest-api
- Services: results-api (NodePort), qa-web (NodePort), ingest-api (NodePort)

## Inputs
- namespace (string, required)
- image_repo (string, required): Image for all Python services
- ingest_image (string, required): Image for ingest-api
- node_port_base (number, required): Base port for NodePort services; results uses +1, qa uses +2, ingest uses +0

## Outputs
- (none currently). Can expose service URLs or ports if desired.

## Example
```hcl
module "app" {
  source         = "./modules/app"
  namespace      = var.namespace
  image_repo     = var.image_repo
  ingest_image   = var.ingest_image
  node_port_base = var.node_port_base
}
```