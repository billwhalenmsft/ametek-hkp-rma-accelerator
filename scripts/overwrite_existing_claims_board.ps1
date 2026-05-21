$orgUrl="https://org6feab6b5.crm.dynamics.com"
$token=(az account get-access-token --resource $orgUrl --query accessToken -o tsv)
$h=@{Authorization="Bearer $token"; Accept="application/json"; "Content-Type"="application/json"; "OData-MaxVersion"="4.0"; "OData-Version"="4.0"}

$existingWrId = "a1ed7ef9-3a4e-f111-bec6-000d3a5aed87"   # rma_/board/claims_board.html (sitemap target)
$htmlPath = "customers/ametek/hkp_rma/ui/rma_claims_dashboard.html"

$bytes = [System.IO.File]::ReadAllBytes((Resolve-Path $htmlPath).Path)
$base64 = [Convert]::ToBase64String($bytes)
Write-Host "Loading $htmlPath ($($bytes.Length) bytes)"

Write-Host "PATCHing existing webresource $existingWrId (rma_/board/claims_board.html)..."
$body = @{ content = $base64; displayname = "HKP Claims Board (Dashboard v2)" } | ConvertTo-Json
Invoke-WebRequest -Method PATCH -Uri "$orgUrl/api/data/v9.2/webresourceset($existingWrId)" -Headers $h -Body $body -UseBasicParsing | Out-Null
Write-Host "  PATCHed."

Write-Host "Publishing..."
$publishXml = "<importexportxml><webresources><webresource>$existingWrId</webresource></webresources></importexportxml>"
$pubBody = @{ ParameterXml = $publishXml } | ConvertTo-Json
Invoke-WebRequest -Method POST -Uri "$orgUrl/api/data/v9.2/PublishXml" -Headers $h -Body $pubBody -UseBasicParsing | Out-Null
Write-Host "  Published."

Write-Host ""
Write-Host "Done. Refresh the RMA Operations app -> click 'Claims Board' in left nav."
Write-Host "Direct URL: $orgUrl/WebResources/rma_/board/claims_board.html"
