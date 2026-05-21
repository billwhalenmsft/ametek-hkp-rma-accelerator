# Hard-delete rma_claimnote table.
# Path: clear AppModuleComponent refs (orphan + RMA Operations app) → remove from solutions → DeleteEntity
# rma_claimnote table is empty (verified). All 7 demo notes were migrated to annotations on parent claims.

$ErrorActionPreference = 'Stop'
$orgUrl = "https://org6feab6b5.crm.dynamics.com"
$token  = (az account get-access-token --resource $orgUrl --query accessToken -o tsv)
$h      = @{ Authorization = "Bearer $token"; Accept = 'application/json' }
$hPost  = $h + @{ 'Content-Type' = 'application/json' }
$hDel   = $h

$mid = "f70cee41-1b4a-f111-bec6-7ced8d6e623f"
$appComp1 = "c11b38af-224e-f111-bec6-000d3a5aed87"   # orphan (parent appmodule fa7af971 deleted)
$appComp2 = "d8985f9c-5103-4e72-8948-cb5bd1fc5d42"   # RMA Operations and Monitoring app
$opsApp   = "8661f960-1f4e-f111-bec6-000d3a5aed87"   # RMA Operations and Monitoring appmoduleid

Write-Host "[0/5] Confirming table is empty..."
$cnt = Invoke-RestMethod -Uri "$orgUrl/api/data/v9.2/rma_claimnotes?`$count=true&`$top=1" -Headers ($h + @{Prefer = 'odata.include-annotations="*"'})
Write-Host "      record count = $($cnt.'@odata.count')"
if ($cnt.'@odata.count' -gt 0) { throw "Table still has records — aborting." }

Write-Host "[1/5] Deleting orphan AppModuleComponent ($appComp1)..."
try {
  Invoke-WebRequest -Uri "$orgUrl/api/data/v9.2/appmodulecomponents($appComp1)" -Method Delete -Headers $hDel | Out-Null
  Write-Host "      [ok]"
} catch { Write-Host "      [WARN] $($_.ErrorDetails.Message)" }

Write-Host "[2/5] Removing rma_claimnote from 'RMA Operations and Monitoring' app via RemoveAppComponents action..."
$body = @{
  AppId = $opsApp
  Components = @(@{
    '@odata.type' = 'Microsoft.Dynamics.CRM.entitymetadata'
    MetadataId   = $mid
    LogicalName  = 'rma_claimnote'
  })
} | ConvertTo-Json -Compress -Depth 5
try {
  Invoke-WebRequest -Uri "$orgUrl/api/data/v9.2/RemoveAppComponents" -Method Post -Headers $hPost -Body $body | Out-Null
  Write-Host "      [ok] RemoveAppComponents action succeeded"
} catch {
  Write-Host "      [WARN] action failed: $($_.ErrorDetails.Message)"
  Write-Host "      Falling back to direct AppModuleComponent delete..."
  try {
    Invoke-WebRequest -Uri "$orgUrl/api/data/v9.2/appmodulecomponents($appComp2)" -Method Delete -Headers $hDel | Out-Null
    Write-Host "      [ok] direct delete succeeded"
  } catch { Write-Host "      [ERR] $($_.ErrorDetails.Message)" }
}

Write-Host "[3/5] Removing rma_claimnote from solutions (RemoveSolutionComponent action)..."
foreach ($solUq in @('RMAReturnsMonitor','Default')) {
  $body = @{ ComponentId = $mid; ComponentType = 1; SolutionUniqueName = $solUq } | ConvertTo-Json -Compress
  try {
    Invoke-WebRequest -Uri "$orgUrl/api/data/v9.2/RemoveSolutionComponent" -Method Post -Headers $hPost -Body $body | Out-Null
    Write-Host "      [ok] removed from $solUq"
  } catch { Write-Host "      [WARN] ${solUq}: $($_.ErrorDetails.Message)" }
}

Write-Host "[4/5] Publishing customizations..."
$pubBody = @{ ParameterXml = "<importexportxml><entities><entity>rma_claimnote</entity></entities><apps><app>$opsApp</app></apps></importexportxml>" } | ConvertTo-Json -Compress
try {
  Invoke-WebRequest -Uri "$orgUrl/api/data/v9.2/PublishXml" -Method Post -Headers $hPost -Body $pubBody | Out-Null
  Write-Host "      [ok]"
} catch { Write-Host "      [WARN] $($_.ErrorDetails.Message)" }

Write-Host "[5/5] DELETE EntityDefinition rma_claimnote..."
try {
  Invoke-WebRequest -Uri "$orgUrl/api/data/v9.2/EntityDefinitions(LogicalName='rma_claimnote')" -Method Delete -Headers $hDel | Out-Null
  Write-Host "      [ok] table deleted"
} catch {
  Write-Host "      [ERR] $($_.ErrorDetails.Message)"
  Write-Host "      Inspecting remaining dependents..."
  $deps = Invoke-RestMethod -Uri "$orgUrl/api/data/v9.2/RetrieveDependentComponents(ObjectId=$mid,ComponentType=1)" -Headers $h
  Write-Host "      remaining dependents: $($deps.value.Count)"
  $deps.value | ForEach-Object { Write-Host "        depType=$($_.dependentcomponenttype) id=$($_.dependentcomponentobjectid)" }
}

Write-Host "Done."
