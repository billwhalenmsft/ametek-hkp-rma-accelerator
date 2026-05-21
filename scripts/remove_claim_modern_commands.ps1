param(
    [string]$OrgUrl = "https://org6feab6b5.crm.dynamics.com",
    [string]$SolutionUniqueName = "RMAReturnsMonitor",
    [string]$ReportPath = "customers/ametek/hkp_rma/d365/modern_commands_creation_results.json"
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path $ReportPath)) {
    throw "Command report not found: $ReportPath"
}

$report = Get-Content $ReportPath -Raw | ConvertFrom-Json
$claimButtons = @($report | Where-Object { $_.Entity -eq 'rma_claim' -and $_.Id })
if ($claimButtons.Count -eq 0) {
    Write-Host "No rma_claim custom command buttons found in report." -ForegroundColor Yellow
    exit 0
}

$token = az account get-access-token --resource $OrgUrl --query accessToken -o tsv
if (-not $token) {
    throw "Failed to get access token. Run 'az login' first."
}

$hdr = @{
    Authorization = "Bearer $token"
    Accept = "application/json"
    "Content-Type" = "application/json; charset=utf-8"
    "OData-MaxVersion" = "4.0"
    "OData-Version" = "4.0"
    "MSCRM.SolutionUniqueName" = $SolutionUniqueName
}

Write-Host "Removing custom rma_claim command-bar buttons..." -ForegroundColor Cyan
$removed = 0
$skipped = 0

foreach ($button in $claimButtons) {
    $id = [string]$button.Id
    $label = [string]$button.Label
    Write-Host "  - $label ($id)" -ForegroundColor DarkGray
    try {
        Invoke-RestMethod -Method Delete -Uri "$OrgUrl/api/data/v9.2/appactions($id)" -Headers $hdr | Out-Null
        Write-Host "    removed" -ForegroundColor Green
        $removed++
    } catch {
        $msg = $_.Exception.Message
        if ($_.ErrorDetails -and $_.ErrorDetails.Message) { $msg = $_.ErrorDetails.Message }
        if ($msg -match '404|Not Found|does not exist') {
            Write-Host "    already gone" -ForegroundColor Yellow
            $skipped++
        } else {
            throw
        }
    }
}

Write-Host "`nPublishing command-bar changes..." -ForegroundColor Cyan
pac solution publish

Write-Host "`nDone. Removed: $removed | Already gone: $skipped" -ForegroundColor Green
Write-Host "Hard refresh the claim form (Ctrl+F5)." -ForegroundColor Cyan