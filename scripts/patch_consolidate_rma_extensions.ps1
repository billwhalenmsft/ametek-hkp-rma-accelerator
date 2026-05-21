# Consolidate the auto-spawned "(rma_ extensions)" solution into RMAReturnsMonitor.
# Then delete the stray.
#
# Background: Entities rma_claim / rma_emaillog / rma_plant are owned by RMAPublisher
# (prefix=rma), but Bill's main solution RMAReturnsMonitor uses publisher BillWhalenSE
# (prefix=bw). When Web API patches modify rma_* components, Dataverse auto-creates
# an "extensions" solution under RMAPublisher to track those changes. This script
# moves the 3 additional components (1 attribute, 1 attribute, 1 form) into the
# main solution, then deletes the now-redundant stray solution.

$ErrorActionPreference = 'Stop'
$orgUrl = "https://org6feab6b5.crm.dynamics.com"
$token  = (az account get-access-token --resource $orgUrl --query accessToken -o tsv)
$h      = @{ Authorization = "Bearer $token"; Accept = 'application/json' }
$hPost  = $h + @{ 'Content-Type' = 'application/json' }

$mainSolUq = 'RMAReturnsMonitor'
$straySolUq = 'RMAReturnsMonitorRma'

# Components in stray that aren't in main yet (verified earlier):
$missing = @(
  @{ id = '4df9f6d7-9e4f-f111-bec6-000d3a5aed87'; type = 2;  desc = 'attribute rma_contactname (rma_claim)' }
  @{ id = 'f28d54cc-9b4f-f111-bec6-000d3a5aed87'; type = 2;  desc = 'attribute rma_autoclaimconfidence (rma_plant)' }
  @{ id = '05a92f92-94cc-4a07-9ba0-f704788c699c'; type = 60; desc = 'systemform Information (rma_claim)' }
)

Write-Host "[1/2] Adding 3 components to '$mainSolUq'..."
foreach ($c in $missing) {
  $body = @{
    ComponentId        = $c.id
    ComponentType      = $c.type
    SolutionUniqueName = $mainSolUq
    AddRequiredComponents = $false
    DoNotIncludeSubcomponents = $true
  } | ConvertTo-Json -Compress
  try {
    Invoke-WebRequest -Uri "$orgUrl/api/data/v9.2/AddSolutionComponent" -Method Post -Headers $hPost -Body $body | Out-Null
    Write-Host "      [ok] $($c.desc)"
  } catch {
    Write-Host "      [WARN] $($c.desc): $($_.ErrorDetails.Message)"
  }
}

Write-Host "[2/2] Deleting stray solution '$straySolUq'..."
$stray = (Invoke-RestMethod -Uri "$orgUrl/api/data/v9.2/solutions?`$filter=uniquename eq '$straySolUq'&`$select=solutionid" -Headers $h).value[0]
if (-not $stray) { Write-Host "      Already gone."; return }
try {
  Invoke-WebRequest -Uri "$orgUrl/api/data/v9.2/solutions($($stray.solutionid))" -Method Delete -Headers $h | Out-Null
  Write-Host "      [ok] Stray solution deleted."
} catch {
  Write-Host "      [ERR] $($_.ErrorDetails.Message)"
}

Write-Host "Done."
