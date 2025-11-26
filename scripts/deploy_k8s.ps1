param(
    [string]$Namespace = $(if ($env:NAMESPACE) { $env:NAMESPACE } else { 'semseg' }),
    [string]$K8sDir = $(if ($env:K8S_DIR) { $env:K8S_DIR } else { Join-Path (Split-Path $PSScriptRoot -Parent) 'deploy/k8s' })
)

$manifests = @(
    "00-namespace.yaml",
    "03-pvc.yaml",
    "05-redis.yaml",
    "06-postgres.yaml",
    "10-ingest-api.yaml",
    "20-convert.yaml",
    "40-part-labeler.yaml",
    "50-redactor.yaml",
    "60-analytics.yaml",
    "70-results-api.yaml",
    "80-qa-web.yaml"
)

Write-Host "Applying Kubernetes manifests from $K8sDir" -ForegroundColor Cyan
foreach ($manifest in $manifests) {
    $file = Join-Path $K8sDir $manifest
    if (-not (Test-Path $file)) {
        Write-Error "Missing manifest: $file"
        exit 1
    }
    Write-Host "--- kubectl apply -f $manifest" -ForegroundColor Yellow
    kubectl apply -f $file
}

Write-Host "`nWorkloads in namespace $($Namespace):" -ForegroundColor Cyan
kubectl get pods -n $Namespace