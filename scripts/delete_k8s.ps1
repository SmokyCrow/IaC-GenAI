param(
    [string]$Namespace = $(if ($env:NAMESPACE) { $env:NAMESPACE } else { 'semseg' }),
    [string]$K8sDir = $(if ($env:K8S_DIR) { $env:K8S_DIR } else { Join-Path (Split-Path $PSScriptRoot -Parent) 'deploy/k8s' })
)

$manifests = @(
    "60-analytics.yaml",
    "70-results-api.yaml",
    "80-qa-web.yaml",
    "50-redactor.yaml",
    "40-part-labeler.yaml",
    "20-convert.yaml",
    "10-ingest-api.yaml",
    "05-redis.yaml",
    "06-postgres.yaml",
    "03-pvc.yaml",
    "00-namespace.yaml"
)

function Clear-PvcPath {
    param(
        [string]$Deployment,
        [string]$Path
    )
    Write-Host "Clearing $($Path) via $($Deployment)" -ForegroundColor DarkYellow
    $cmd = "rm -rf $Path/*"
    try {
        kubectl exec "deploy/$Deployment" -n $Namespace -- sh -c $cmd | Out-Null
    }
    catch {
        Write-Warning "Unable to clean $($Path) on $($Deployment): $_"
    }
}

Write-Host "Clearing PVC contents (if deployments are running)" -ForegroundColor Cyan
Clear-PvcPath 'ingest-api' '/sub-pc-frames'
Clear-PvcPath 'convert-ply' '/pc-frames'
Clear-PvcPath 'part-labeler' '/segments'

# The part-labeler may delete inputs itself, but explicitly clear its colorized outputs
Clear-PvcPath 'part-labeler' '/segments/labels'
# Redactor output
Clear-PvcPath 'redactor' '/segments'
# Analytics output
Clear-PvcPath 'analytics' '/segments'

Write-Host "Deleting Kubernetes resources from $K8sDir" -ForegroundColor Cyan
foreach ($manifest in $manifests) {
    $file = Join-Path $K8sDir $manifest
    if (-not (Test-Path $file)) {
        Write-Warning "Skipping missing manifest: $file"
        continue
    }
    Write-Host "--- kubectl delete -f $manifest" -ForegroundColor Yellow
    kubectl delete -f $file --ignore-not-found | Out-Null
}

Write-Host "`nRemaining workloads in namespace $($Namespace):" -ForegroundColor Cyan
kubectl get pods -n $Namespace