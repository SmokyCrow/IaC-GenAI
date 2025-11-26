param(
  [string]$Namespace = "semseg",
  [string]$AppImageTag = "semantic-segmenter:latest",
  [string]$IngestImageTag = "ingest-api:latest",
  [switch]$IncludeRedis = $true,
  [switch]$IncludePostgres = $false
)

function Get-DedupImageSummary {
  # docker system df -v is the most accurate for deduplicated layer usage
  $df = docker system df -v 2>$null
  if (-not $df) {
    Write-Warning "docker system df -v failed. Falling back to 'docker images' naive sum."
    return $null
  }
  $df
}

function Get-NaiveImageBytes([string[]]$images) {
  $total = [int64]0
  foreach ($img in $images) {
    $size = docker image inspect $img --format '{{.Size}}' 2>$null
    if ($size) { $total += [int64]$size }
  }
  return $total
}

function Format-Bytes([int64]$bytes) {
  if ($bytes -ge 1GB) { return "{0:N2} GiB" -f ($bytes/1GB) }
  if ($bytes -ge 1MB) { return "{0:N2} MiB" -f ($bytes/1MB) }
  if ($bytes -ge 1KB) { return "{0:N2} KiB" -f ($bytes/1KB) }
  return "$bytes B"
}

# 1) Images referenced by deployments in the namespace
Write-Host "== Images referenced by Deployments in namespace '$Namespace' ==" -ForegroundColor Cyan
$deployImages = kubectl -n $Namespace get deploy -o jsonpath='{range .items[*]}{.spec.template.spec.containers[*].image}{"\n"}{end}' 2>$null |
  Where-Object { $_ -and $_.Trim() -ne '' } |
  Sort-Object -Unique
$deployImages | ForEach-Object { Write-Host "  - $_" }

# 2) Compute image footprint
Write-Host "\n== Image storage usage ==" -ForegroundColor Cyan
$dedup = Get-DedupImageSummary
if ($dedup) {
  Write-Host "(Deduplicated layers)"
  $dedup
} else {
  $images = @($AppImageTag,$IngestImageTag)
  if ($IncludeRedis) { $images += "redis:7-alpine" }
  $bytes = Get-NaiveImageBytes -images $images
  Write-Host "Naive sum of selected images: $(Format-Bytes $bytes) (shared layers may be double-counted)"
}

# 3) PVC caps (what the node must be able to provide)
Write-Host "\n== PVC requested capacity (caps) ==" -ForegroundColor Cyan
$pvc = kubectl -n $Namespace get pvc -o jsonpath='{range .items[*]}{.metadata.name}{"|"}{.status.phase}{"|"}{.spec.resources.requests.storage}{"\n"}{end}' 2>$null |
  Where-Object { $_ -and $_.Trim() -ne '' }
if (-not $pvc) {
  Write-Host "No PVCs found in namespace '$Namespace' yet."
} else {
  $totalMi = 0.0
  foreach ($line in $pvc) {
    $parts = $line.Split('|')
    $name = $parts[0]
    $phase = $parts[1]
    $req = $parts[2]
    Write-Host ("  - {0} [{1}] -> {2}" -f $name,$phase,$req)
    if ($req.ToLower().EndsWith('mi')) {
      $totalMi += [double]($req.ToLower().Replace('mi',''))
    } elseif ($req.ToLower().EndsWith('gi')) {
      $totalMi += ([double]($req.ToLower().Replace('gi','')) * 1024.0)
    }
  }
  Write-Host ("Total requested (caps): {0:N1} MiB (~{1:N2} GiB)" -f $totalMi, ($totalMi/1024.0))
}

# 4) Optional Postgres cap add-on (if using raw YAML or future TF wiring)
if ($IncludePostgres) {
  Write-Host "\nIncluding Postgres PVC cap: +1Gi (test default)" -ForegroundColor Yellow
}

Write-Host "\nTip: This script reports image storage from Docker and PVC caps from Kubernetes. Real file data usage will be below caps in most runs." -ForegroundColor DarkGray
