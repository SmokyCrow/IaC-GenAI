param(
    [string]$Namespace = $(if ($env:NAMESPACE) { $env:NAMESPACE } else { 'semseg' }),
    [string]$DestDir = $(if ($args.Count -ge 1) { $args[0] } else { './out_ply' })
)

function Ensure-Dir([string]$Path) {
    if (-not (Test-Path $Path)) { New-Item -ItemType Directory -Path $Path | Out-Null }
}

# Prepare destination subfolders
$labDir = Join-Path $DestDir 'labeler'
$redDir = Join-Path $DestDir 'redactor'
Ensure-Dir $DestDir
Ensure-Dir $labDir
Ensure-Dir $redDir

# Copy from part-labeler: colorized previews live in /segments/labels/*.ply
$labPod = kubectl get pod -n $Namespace -l app=part-labeler -o jsonpath='{.items[0].metadata.name}'
if ($labPod) {
    Write-Host ("Copying labeler colorized PLYs from {0}:/segments/labels -> {1}" -f $labPod, $labDir) -ForegroundColor Cyan
    $plyList = kubectl exec -n $Namespace $labPod -- sh -lc "ls -1 /segments/labels/*.ply 2>/dev/null || true"
    if ($plyList) {
        foreach ($p in ($plyList -split "`n" | Where-Object { $_ })) {
            $leaf = Split-Path -Path $p -Leaf
            kubectl cp "$Namespace/${labPod}:$p" (Join-Path $labDir $leaf)
        }
    } else { Write-Host "  (no *.ply in part-labeler /segments/labels)" -ForegroundColor DarkGray }
} else { Write-Host "part-labeler pod not found" -ForegroundColor DarkYellow }

# Copy from redactor: anonymized-*.ply
$redPod = kubectl get pod -n $Namespace -l app=redactor -o jsonpath='{.items[0].metadata.name}'
if ($redPod) {
    Write-Host ("Copying anonymized PLYs from {0}:/segments -> {1}" -f $redPod, $redDir) -ForegroundColor Cyan
    $plyList = kubectl exec -n $Namespace $redPod -- sh -lc "ls -1 /segments/anonymized-*.ply 2>/dev/null || true"
    if ($plyList) {
        foreach ($p in ($plyList -split "`n" | Where-Object { $_ })) {
            $leaf = Split-Path -Path $p -Leaf
            kubectl cp "$Namespace/${redPod}:$p" (Join-Path $redDir $leaf)
        }
    } else { Write-Host "  (no anonymized-*.ply in redactor /segments)" -ForegroundColor DarkGray }
} else { Write-Host "redactor pod not found" -ForegroundColor DarkYellow }

Write-Host ("Done. Output folders: `n  - {0}`n  - {1}" -f $labDir, $redDir) -ForegroundColor Green
