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
$wrId = "29995807-8d53-f111-a824-0022480a5e8d"
$path = Join-Path $PSScriptRoot "..\ui\rma_email_assist.html"
$bytes = [IO.File]::ReadAllBytes($path)
$content = [Convert]::ToBase64String($bytes)
Write-Host "Patching web resource ($([Math]::Round($bytes.Length / 1KB, 1)) KB)..."
Invoke-RestMethod -Method Patch -Uri "$org/api/data/v9.2/webresourceset($wrId)" -Headers $headers -Body (@{ content = $content } | ConvertTo-Json -Compress) | Out-Null
Write-Host "Publishing..."
$publishBody = "<importexportxml><webresources><webresource>{$wrId}</webresource></webresources></importexportxml>"
Invoke-RestMethod -Method Post -Uri "$org/api/data/v9.2/PublishXml" -Headers $headers -Body (@{ ParameterXml = $publishBody } | ConvertTo-Json -Compress) | Out-Null
Write-Host "Done. Hard-refresh (Ctrl+F5) the email log record."
