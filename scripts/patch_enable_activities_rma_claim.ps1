# Enable HasActivities on rma_claim so Timeline shows emails (and any future activity types).
# IRREVERSIBLE Dataverse operation — once flipped to true, cannot be set back to false.
# After this, the rma_claim form Timeline (already added in patch_claim_form_cleanup.ps1)
# will surface Activities (Email, Phone Call, Task, Appointment) in addition to Notes.

$ErrorActionPreference = 'Stop'
$orgUrl = "https://org6feab6b5.crm.dynamics.com"
$token  = (az account get-access-token --resource $orgUrl --query accessToken -o tsv)
$h      = @{ Authorization = "Bearer $token"; Accept = "application/json"; 'Content-Type' = 'application/json' }

Write-Host "[1/4] Reading current rma_claim metadata..."
$ent = Invoke-RestMethod -Uri "$orgUrl/api/data/v9.2/EntityDefinitions(LogicalName='rma_claim')?`$select=LogicalName,HasActivities,HasNotes,MetadataId" -Headers $h
Write-Host "      Before: HasActivities=$($ent.HasActivities)  HasNotes=$($ent.HasNotes)"
if ($ent.HasActivities) { Write-Host "      Already enabled — exiting."; return }

Write-Host "[2/4] Patching EntityDefinition (HasActivities=true)..."
# Per Dataverse Web API metadata rules, EntityMetadata PATCH requires MSCRM.MergeLabels=false
# and the body must include MetadataId. HasActivities flip is supported via this endpoint.
$body = @{
  '@odata.type'   = '#Microsoft.Dynamics.CRM.EntityMetadata'
  MetadataId      = $ent.MetadataId
  LogicalName     = 'rma_claim'
  HasActivities   = $true
} | ConvertTo-Json -Compress

$pHdr = $h.Clone()
$pHdr['MSCRM.MergeLabels'] = 'false'
$pHdr['If-Match'] = '*'

try {
  Invoke-WebRequest -Uri "$orgUrl/api/data/v9.2/EntityDefinitions(LogicalName='rma_claim')" -Method Patch -Headers $pHdr -Body $body | Out-Null
  Write-Host "      [ok] PATCH succeeded"
} catch {
  Write-Host "      [ERR] $($_.ErrorDetails.Message)"; throw
}

Write-Host "[3/4] Publishing customizations..."
$pubBody = @{ ParameterXml = "<importexportxml><entities><entity>rma_claim</entity></entities></importexportxml>" } | ConvertTo-Json -Compress
try {
  Invoke-WebRequest -Uri "$orgUrl/api/data/v9.2/PublishXml" -Method Post -Headers $h -Body $pubBody | Out-Null
  Write-Host "      [ok] Published."
} catch {
  Write-Host "      [WARN] Publish failed: $($_.ErrorDetails.Message)"
}

Write-Host "[4/4] Verifying..."
$ent2 = Invoke-RestMethod -Uri "$orgUrl/api/data/v9.2/EntityDefinitions(LogicalName='rma_claim')?`$select=HasActivities,HasNotes" -Headers $h
Write-Host "      After:  HasActivities=$($ent2.HasActivities)  HasNotes=$($ent2.HasNotes)"
