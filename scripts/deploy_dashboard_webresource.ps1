# Deploy RMA Monitor Dashboard as Dataverse web resource
# Run this AFTER reviewing the HTML in your browser.
# Then in Power Apps maker: open the RMA Operations app, edit the Sitemap or
# add a Dashboard sub-area pointing to web resource cr74e_/rma/dashboard.html

param(
    [string]$OrgUrl = "https://org6feab6b5.crm.dynamics.com",
    [string]$HtmlPath = "customers/ametek/hkp_rma/ui/rma_claims_dashboard.html",
    [string]$WebResourceName = "cr74e_/rma/dashboard.html",   # Schema name
    [string]$WebResourceDisplayName = "RMA Monitor Dashboard",
    [switch]$Publish
)

$ErrorActionPreference = "Stop"

Write-Host "=== Acquiring Dataverse token ==="
$token = az account get-access-token --resource $OrgUrl --query accessToken -o tsv
$h = @{
    Authorization     = "Bearer $token"
    Accept            = "application/json"
    "Content-Type"    = "application/json"
    "OData-MaxVersion"= "4.0"
    "OData-Version"   = "4.0"
}

if (-not (Test-Path $HtmlPath)) { throw "HTML file not found: $HtmlPath" }

$bytes = [System.IO.File]::ReadAllBytes((Resolve-Path $HtmlPath).Path)
$base64 = [Convert]::ToBase64String($bytes)
Write-Host "  loaded $HtmlPath ($($bytes.Length) bytes)"

Write-Host ""
Write-Host "=== Check if web resource already exists: $WebResourceName ==="
$encName = [Uri]::EscapeDataString($WebResourceName)
$existing = (Invoke-RestMethod -Uri "$OrgUrl/api/data/v9.2/webresourceset?`$filter=name eq '$WebResourceName'&`$select=webresourceid,displayname" -Headers $h).value

if ($existing) {
    $wrId = $existing[0].webresourceid
    Write-Host "  found existing webresourceid=$wrId  - will UPDATE content"
    $body = @{ content = $base64; displayname = $WebResourceDisplayName } | ConvertTo-Json
    Invoke-WebRequest -Method PATCH -Uri "$OrgUrl/api/data/v9.2/webresourceset($wrId)" -Headers $h -Body $body -UseBasicParsing | Out-Null
    Write-Host "  updated"
} else {
    Write-Host "  not found - will CREATE new web resource"
    $body = @{
        name                  = $WebResourceName
        displayname           = $WebResourceDisplayName
        webresourcetype       = 1            # 1 = HTML/Webpage
        content               = $base64
        description           = "RMA Monitor dashboard - drag-n-drop Kanban + KPIs. Embed via Sitemap > Sub Area > URL = `$webresource:$WebResourceName"
        languagecode          = 1033
    } | ConvertTo-Json
    $resp = Invoke-WebRequest -Method POST -Uri "$OrgUrl/api/data/v9.2/webresourceset" -Headers $h -Body $body -UseBasicParsing
    $loc = $resp.Headers["OData-EntityId"]
    if ($loc -match 'webresourceset\(([0-9a-f-]+)\)') { $wrId = $Matches[1] }
    Write-Host "  created webresourceid=$wrId"
}

if ($Publish) {
    Write-Host ""
    Write-Host "=== Publishing webresource ==="
    $publishXml = "<importexportxml><webresources><webresource>$wrId</webresource></webresources></importexportxml>"
    $pubBody = @{ ParameterXml = $publishXml } | ConvertTo-Json
    Invoke-WebRequest -Method POST -Uri "$OrgUrl/api/data/v9.2/PublishXml" -Headers $h -Body $pubBody -UseBasicParsing | Out-Null
    Write-Host "  published"
} else {
    Write-Host ""
    Write-Host "[INFO] Skipped publish. Re-run with -Publish to make it live, or publish via maker portal."
}

Write-Host ""
Write-Host "=== Next steps ==="
Write-Host "  1. Open https://make.powerapps.com -> Solutions -> open the RMA Operations solution"
Write-Host "  2. Add the web resource '$WebResourceName' as a component"
Write-Host "  3. Open the model-driven app 'RMA Operations and Monitoring' -> edit Sitemap"
Write-Host "  4. Add a sub-area: Type=URL, URL=`$webresource:$WebResourceName, Title='Claims Board'"
Write-Host "  5. Save + Publish app. Refresh browser. Click 'Claims Board' in left nav."
Write-Host ""
Write-Host "  Standalone preview:  open the HTML directly in a browser (mock data will load)"
Write-Host "  Live URL after deploy: $OrgUrl/WebResources/$WebResourceName"
