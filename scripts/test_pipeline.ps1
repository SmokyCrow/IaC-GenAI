param(
    [string]$Namespace = $(if ($env:NAMESPACE) { $env:NAMESPACE } else { 'semseg' }),
    [string]$IngestHost = $(if ($env:INGEST_HOST) { $env:INGEST_HOST } else { 'localhost' }),
    [int]$IngestPort = $(if ($env:INGEST_PORT) { [int]$env:INGEST_PORT } else { 30080 }),
    [int]$ResultsPort = $(if ($env:RESULTS_PORT) { [int]$env:RESULTS_PORT } else { 30081 }),
    [string]$FrameList = $(if ($env:FRAMES) { $env:FRAMES } else { (0..9 -join ' ') }),
    [int]$WaitSeconds = $(if ($env:WAIT_SECONDS) { [int]$env:WAIT_SECONDS } else { 30 })
)

$rootDir = Split-Path $PSScriptRoot -Parent
$frames = $FrameList -split '\s+' | Where-Object { $_ }

Write-Host "Testing deployment at $IngestHost (ports: ingest=$IngestPort, results=$ResultsPort)" -ForegroundColor Cyan

foreach ($frame in $frames) {
    $frameId = '{0:D5}' -f [int]$frame
    $file = Join-Path $rootDir "full_frames\drc\0-frame_$frameId.drc"
    if (-not (Test-Path $file)) {
        Write-Error "Missing test payload: $file"
        exit 1
    }
    Write-Host "Uploading frame $frameId from $file" -ForegroundColor Yellow
    $curlArgs = @(
        '--fail', '--silent', '--show-error',
        '-H', 'Content-Type: application/octet-stream',
        '--data-binary', "@$file",
        "http://$($IngestHost):$IngestPort/frames/$frameId"
    )
    & curl.exe @curlArgs | Out-Null
    Write-Host "  ok" -ForegroundColor Green
}

if ($WaitSeconds -gt 0) {
    Write-Host "Waiting $WaitSeconds seconds for processing to finish..." -ForegroundColor Cyan
    Start-Sleep -Seconds $WaitSeconds
}

# QA Web basic check
Write-Host "`nQA Web root page status:" -ForegroundColor Cyan
try {
    $qaStatus = curl.exe --silent --output /dev/null --write-out "%{http_code}" "http://$($IngestHost):30082/"
    Write-Host "QA Web / HTTP $qaStatus" -ForegroundColor Green
}
catch {
    Write-Warning "QA Web request failed: $_"
}

# Results API quick check
Write-Host "`nResults API (/frames):" -ForegroundColor Cyan
try {
    $resp = curl.exe --fail --silent --show-error "http://$($IngestHost):$ResultsPort/frames"
    if ($resp) {
        $json = $resp | ConvertFrom-Json
        $count = ($json.frames | Measure-Object).Count
        Write-Host "Frames in Results API index: $count" -ForegroundColor Green
        if ($count -gt 0) {
            $first = $json.frames[0]
            Write-Host ("Sample frame: {0} (has: labels={1}, metrics={2}, anonymized={3})" -f $first.frame_id, $first.has.labels, $first.has.metrics, $first.has.anonymized)
        }
    }
}
catch {
    Write-Warning "Results API call failed: $_"
}