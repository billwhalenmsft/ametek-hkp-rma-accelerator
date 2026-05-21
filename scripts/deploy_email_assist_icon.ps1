#requires -Version 7
[CmdletBinding()]
param()
$ErrorActionPreference = "Stop"
$org = "https://org6feab6b5.crm.dynamics.com"
$token = (az account get-access-token --resource $org --query accessToken -o tsv).Trim()
$headers = @{
  Authorization      = "Bearer $token"
  "Content-Type"     = "application/json"
  Accept             = "application/json"
  "OData-MaxVersion" = "4.0"
  "OData-Version"    = "4.0"
}

function Get-WebResource($name) {
  $u = "$org/api/data/v9.2/webresourceset?`$filter=name eq '$name'&`$select=webresourceid,name"
  $r = Invoke-RestMethod -Uri $u -Headers $headers
  if ($r.value.Count -gt 0) { return $r.value[0] } else { return $null }
}

function Upsert-WebResource($name, $display, $type, $path) {
  $bytes = [IO.File]::ReadAllBytes($path)
  $content = [Convert]::ToBase64String($bytes)
  $existing = Get-WebResource $name
  if ($existing) {
    Write-Host "  Patching $name ($([Math]::Round($bytes.Length / 1KB, 1)) KB)"
    $body = @{ content = $content; displayname = $display } | ConvertTo-Json -Compress
    Invoke-RestMethod -Method Patch -Uri "$org/api/data/v9.2/webresourceset($($existing.webresourceid))" -Headers $headers -Body $body | Out-Null
    return $existing.webresourceid
  }
  else {
    Write-Host "  Creating $name ($([Math]::Round($bytes.Length / 1KB, 1)) KB)"
    $body = @{
      name            = $name
      displayname     = $display
      webresourcetype = $type
      languagecode    = 1033
      content         = $content
    } | ConvertTo-Json -Compress
    $r = Invoke-WebRequest -Method Post -Uri "$org/api/data/v9.2/webresourceset" -Headers $headers -Body $body
    # Newly created entity id is in OData-EntityId header
    $loc = $r.Headers["OData-EntityId"]
    if ($loc -is [array]) { $loc = $loc[0] }
    $id = [regex]::Match($loc, "\(([0-9a-fA-F\-]+)\)").Groups[1].Value
    return $id
  }
}

Write-Host "=== Uploading icon + updated JS ==="
$iconId = Upsert-WebResource "rma_/productivity/email_assist_icon.svg" "Email Assist Icon" 11 (Join-Path $PSScriptRoot "..\ui\email_assist_icon.svg")
$jsId   = Upsert-WebResource "rma_/scripts/email_productivity_pane.js" "Email Productivity Pane (form library)" 3 (Join-Path $PSScriptRoot "email_productivity_pane.js")

Write-Host "  Icon id: $iconId"
Write-Host "  JS   id: $jsId"

Write-Host "=== Publishing web resources ==="
$publishBody = "<importexportxml><webresources><webresource>{$iconId}</webresource><webresource>{$jsId}</webresource></webresources></importexportxml>"
Invoke-RestMethod -Method Post -Uri "$org/api/data/v9.2/PublishXml" -Headers $headers -Body (@{ ParameterXml = $publishBody } | ConvertTo-Json -Compress) | Out-Null
Write-Host "  Published"

Write-Host "`nDone. Hard-refresh (Ctrl+F5) the email log record. The icon should appear on the right-side productivity rail."
