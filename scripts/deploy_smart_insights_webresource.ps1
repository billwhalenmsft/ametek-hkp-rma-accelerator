# Deploy the Smart Insights HTML as a Dataverse web resource
param(
    [string]$OrgUrl = "https://org6feab6b5.crm.dynamics.com",
    [string]$HtmlPath = "customers/ametek/hkp_rma/ui/rma_claim_smart_insights.html",
    [string]$WebResourceName = "rma_/board/smart_insights.html",
    [string]$WebResourceDisplayName = "RMA Claim - Smart Insights (Navision)"
)
$ErrorActionPreference = "Stop"
$token = az account get-access-token --resource $OrgUrl --query accessToken -o tsv
$h = @{
    Authorization     = "Bearer $token"
    Accept            = "application/json"
    "Content-Type"    = "application/json"
    "OData-MaxVersion"= "4.0"
    "OData-Version"   = "4.0"
}
$bytes = [System.IO.File]::ReadAllBytes((Resolve-Path $HtmlPath).Path)
$base64 = [Convert]::ToBase64String($bytes)
Write-Host "Loaded $HtmlPath ($($bytes.Length) bytes)"
$existing = (Invoke-RestMethod -Uri "$OrgUrl/api/data/v9.2/webresourceset?`$filter=name eq '$WebResourceName'&`$select=webresourceid" -Headers $h).value
if ($existing) {
    $wrId = $existing[0].webresourceid
    Write-Host "Updating existing web resource $wrId..."
    $body = @{ content = $base64; displayname = $WebResourceDisplayName } | ConvertTo-Json
    Invoke-WebRequest -Method PATCH -Uri "$OrgUrl/api/data/v9.2/webresourceset($wrId)" -Headers $h -Body $body -UseBasicParsing | Out-Null
} else {
    Write-Host "Creating new web resource..."
    $body = @{
        name = $WebResourceName
        displayname = $WebResourceDisplayName
        webresourcetype = 1
        content = $base64
        description = "RMA Claim Smart Insights panel - Navision scoring (stubbed) + customer history (live)"
        languagecode = 1033
    } | ConvertTo-Json
    $resp = Invoke-WebRequest -Method POST -Uri "$OrgUrl/api/data/v9.2/webresourceset" -Headers $h -Body $body -UseBasicParsing
    $loc = $resp.Headers["OData-EntityId"]
    if ($loc -match 'webresourceset\(([0-9a-f-]+)\)') { $wrId = $Matches[1] }
}
Write-Host "Web resource id: $wrId"

# Publish
$publishXml = "<importexportxml><webresources><webresource>$wrId</webresource></webresources></importexportxml>"
$pubBody = @{ ParameterXml = $publishXml } | ConvertTo-Json
Invoke-WebRequest -Method POST -Uri "$OrgUrl/api/data/v9.2/PublishXml" -Headers $h -Body $pubBody -UseBasicParsing | Out-Null
Write-Host "Published." -ForegroundColor Green
Write-Host "Web resource id (capture for form patch): $wrId" -ForegroundColor Cyan
