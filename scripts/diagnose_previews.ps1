[CmdletBinding()] param(
    [string]$Namespace = $(if ($env:NAMESPACE) { $env:NAMESPACE } else { 'semseg' }),
    [string]$ResultsApiUrl = 'http://localhost:30081',
    [int]$Sample = 5,
    [string]$FrameId,
    [switch]$ForcePreviews,
    [switch]$Overwrite,
    [ValidateSet('generic','anonymized','labels','all')] [string]$Which = 'all',
    [switch]$ShowDebug
)

function Write-Info($msg){ Write-Host $msg -ForegroundColor Cyan }
function Write-Warn($msg){ Write-Host $msg -ForegroundColor Yellow }
function Write-Err($msg){ Write-Host $msg -ForegroundColor Red }

function Get-ResultsPodName {
    $pod = kubectl get pod -n $Namespace -l app=results-api -o jsonpath='{.items[0].metadata.name}' 2>$null
    if (-not $pod) { throw "results-api pod not found in namespace $Namespace" }
    return $pod
}

function Exec-InResults {
    param([string]$Command)
    $pod = Get-ResultsPodName
    kubectl exec -n $Namespace $pod -- sh -c $Command 2>$null
}

function Get-List($pattern){
    $cmd = "ls -1 $pattern 2>/dev/null"
    $out = Exec-InResults $cmd
    if (-not $out) { return @() }
    return ($out -split "`n" | Where-Object { $_ })
}

function Get-FrameIdFromPath([string]$path,[string]$prefix){
    if ($path -match "/$prefix-(?<id>[^/]+)\.") { return $Matches.id }
    return $null
}

function Build-Set($list,[string]$prefix){
    $h = @{}
    foreach ($p in $list){
        $id = Get-FrameIdFromPath -path $p -prefix $prefix
        if ($id){ $h[$id] = $true }
    }
    return $h
}

function Invoke-Api($method,$url){
    try { return Invoke-RestMethod -Method $method -Uri $url -TimeoutSec 30 }
    catch { Write-Warn "API call failed: $url -> $($_.Exception.Message)"; return $null }
}

Write-Info "Collecting file inventories from results-api pod..."
$anonList   = Get-List '/segments/anonymized-*.ply'
$labelsList = Get-List '/segments/labels/labels-colored-*.ply'
$prevGen    = Get-List '/segments/preview-*.png'
$prevAnon   = Get-List '/segments/preview-anonymized-*.png'
$prevLab    = Get-List '/segments/preview-labels-colored-*.png'

$anonSet   = Build-Set $anonList 'anonymized'
$labelsSet = Build-Set $labelsList 'labels-colored'
$prevSet   = Build-Set $prevGen 'preview'
$prevAnonSet = Build-Set $prevAnon 'preview-anonymized'
$prevLabSet  = Build-Set $prevLab 'preview-labels-colored'

# Union of frame ids from anonymized & labels & previews
$allIds = New-Object System.Collections.Generic.HashSet[string]
foreach ($k in $anonSet.Keys)   { [void]$allIds.Add($k) }
foreach ($k in $labelsSet.Keys) { [void]$allIds.Add($k) }
foreach ($k in $prevSet.Keys)   { [void]$allIds.Add($k) }
foreach ($k in $prevAnonSet.Keys){ [void]$allIds.Add($k) }
foreach ($k in $prevLabSet.Keys){ [void]$allIds.Add($k) }

$rows = foreach ($fid in ($allIds | Sort-Object)) {
    [pscustomobject]@{
        Frame = $fid
        AnonPLY = [bool]$anonSet[$fid]
        LabelsPLY = [bool]$labelsSet[$fid]
        Preview = [bool]$prevSet[$fid]
        PreviewAnon = [bool]$prevAnonSet[$fid]
        PreviewLabels = [bool]$prevLabSet[$fid]
    }
}

Write-Host ""; Write-Info "Summary (first $Sample frames):"
$rows | Select-Object -First $Sample | Format-Table -AutoSize
Write-Host ""; Write-Info ("Counts: anonymized={0} labels-colored={1} preview={2} preview-anon={3} preview-labels={4}" -f $anonList.Count,$labelsList.Count,$prevGen.Count,$prevAnon.Count,$prevLab.Count)

# Optionally retrieve /frames API for cross-check
$framesApi = Invoke-Api GET ("$ResultsApiUrl/frames")
if ($framesApi -and $framesApi.frames) {
    $apiCount = $framesApi.frames.Count
    Write-Info "Results API reports $apiCount frames."
    $missingPreviewReported = @($framesApi.frames | Where-Object { -not $_.has.preview }).Count
    if ($missingPreviewReported -gt 0) {
        Write-Warn "$missingPreviewReported frames missing generic preview per API." }
}

if ($FrameId) {
    if (-not ($allIds.Contains($FrameId))) {
        Write-Warn "Specified FrameId $FrameId not present in discovered files (may still be in pipeline)." }
    if ($ForcePreviews) {
        $whichParam = if ($Which -eq 'all') { '' } else { "&which=$Which" }
        $ov = if ($Overwrite) { 'true' } else { 'false' }
        $url = "$ResultsApiUrl/frames/$FrameId/preview/generate?overwrite=$ov$whichParam"
        Write-Info "Forcing preview generation: $url"
        $res = Invoke-Api POST $url
        if ($res) { $res | ConvertTo-Json -Depth 6 | Write-Output }
    }
    if ($ShowDebug) {
        $dbgUrl = "$ResultsApiUrl/frames/$FrameId/preview/debug"
        Write-Info "Fetching preview debug: $dbgUrl"
        $dbg = Invoke-Api GET $dbgUrl
        if ($dbg) { $dbg | ConvertTo-Json -Depth 6 | Write-Output }
    }
}

Write-Host ""; Write-Info "Done. Use -FrameId <id> -ForcePreviews to trigger creation, -ShowDebug to inspect file stats."