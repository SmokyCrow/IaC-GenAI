param(
    [string]$ApiHost = $(if ($env:RESULTS_HOST) { $env:RESULTS_HOST } else { '127.0.0.1' }),
    [int]$Port = $(if ($env:RESULTS_PORT) { [int]$env:RESULTS_PORT } else { 30081 }),
    [string]$FrameId = $(if ($env:FRAME_ID) { $env:FRAME_ID } else { '' })
)

function Invoke-Json($url) {
    try {
        $resp = curl.exe --fail --silent --show-error $url
        if (-not $resp) { return $null }
        return $resp | ConvertFrom-Json
    }
    catch {
        Write-Warning "Request failed: $url :: $_"
        return $null
    }
}

$base = "http://$($ApiHost):$Port"

Write-Host "GET /healthz" -ForegroundColor Cyan
curl.exe --fail --silent --show-error "$base/healthz" | Out-String

Write-Host "`nGET /frames" -ForegroundColor Cyan
$frames = Invoke-Json "$base/frames"
if ($frames -and $frames.frames) {
    $count = ($frames.frames | Measure-Object).Count
    Write-Host "Frames: $count" -ForegroundColor Green
    $first = $frames.frames[0]
    Write-Host ("First: {0} (segments={1}, labels={2}, metrics={3}, anonymized={4})" -f $first.frame_id, $first.has.segments, $first.has.labels, $first.has.metrics, $first.has.anonymized)
    if (-not $FrameId) { $FrameId = $first.frame_id }
}
else {
    Write-Warning "No frames available yet."
}

if ($FrameId) {
    Write-Host "`nFetch artifacts for $FrameId" -ForegroundColor Cyan
    foreach ($p in @("labels.json", "metrics.json")) {
        $u = "$base/frames/$FrameId/$p"
        $ok = curl.exe --silent --output /dev/null --write-out "%{http_code}" $u
        Write-Host ("  {0}: HTTP {1}" -f $p, $ok)
    }
}

Write-Host "`nStreams overview: GET /streams" -ForegroundColor Cyan
$streams = Invoke-Json "$base/streams"
if ($streams -and $streams.streams) {
    foreach ($s in $streams.streams) {
        Write-Host ("  {0} (key={1}) enabled={2} len={3}" -f $s.name, $s.key, $s.enabled, $s.len)
    }
    # Fetch last 20 from parts_labeled and analytics_done if enabled
    foreach ($name in @('s_parts_labeled','s_analytics_done')) {
        $entry = $streams.streams | Where-Object { $_.name -eq $name -and $_.enabled -eq $true }
        if ($entry) {
            Write-Host "`nGET /streams/${name}?count=20" -ForegroundColor Cyan
            $data = Invoke-Json "$base/streams/${name}?count=20"
            if ($data -and $data.entries) {
                $sample = $data.entries | Select-Object -First 3
                $sample | ConvertTo-Json -Depth 5
            }
        }
    }
}
else {
    Write-Warning "Streams endpoint returned no data. Ensure REDIS_URL is set in results-api deployment."
}

Write-Host "`nDone." -ForegroundColor Green
