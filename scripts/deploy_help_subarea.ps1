# deploy_help_subarea.ps1
# Deploys rma_help.html web resource AND adds a Help subarea to the RMA Operations sitemap.
# Pattern proven by deploy_email_body_preview.ps1 (web resource creation requires languagecode=1033).
# 
# Sitemap requires both:
#   - publish the sitemap web resource
#   - add a SubArea with Type="Url" + Url="$webresource:rma_/help/help.html" + WebResourceId
#   - publish the sitemap entity AND the appmodule

$ErrorActionPreference = "Stop"

$orgUrl  = "https://org6feab6b5.crm.dynamics.com"
$appId   = "8661f960-1f4e-f111-bec6-000d3a5aed87"   # RMA Operations and Monitoring
$smId    = "2191c458-1f4e-f111-bec6-000d3a5aed87"   # Its sitemap
$wrName  = "rma_/help/help.html"
$wrPath  = Join-Path $PSScriptRoot "..\ui\rma_help.html" | Resolve-Path | Select-Object -ExpandProperty Path

Write-Host "Acquiring token..."
$token = az account get-access-token --resource $orgUrl --query accessToken -o tsv
if (-not $token) { throw "az account get-access-token returned empty" }

$h = @{
    Authorization      = "Bearer $token"
    Accept             = "application/json"
    "Content-Type"     = "application/json; charset=utf-8"
    "OData-MaxVersion" = "4.0"
    "OData-Version"    = "4.0"
}

# ---- 1. Web resource: create or update -------------------------------------
$bytes  = [IO.File]::ReadAllBytes($wrPath)
$base64 = [Convert]::ToBase64String($bytes)
Write-Host "HTML: $($bytes.Length) bytes -> $($base64.Length) base64 chars"

$existing = Invoke-RestMethod -Uri "$orgUrl/api/data/v9.2/webresourceset?`$filter=name eq '$($wrName.Replace("'", "''"))'&`$select=webresourceid,name,languagecode" -Headers $h
$wrId = if ($existing.value -and $existing.value.Count -gt 0) { $existing.value[0].webresourceid } else { $null }

if ($wrId) {
    Write-Host "Updating existing web resource $wrId"
    $body = @{
        content      = $base64
        displayname  = "RMA Help"
        languagecode = 1033
    } | ConvertTo-Json
    Invoke-RestMethod -Method Patch -Uri "$orgUrl/api/data/v9.2/webresourceset($wrId)" -Headers $h -Body $body | Out-Null
} else {
    Write-Host "Creating new web resource $wrName"
    $createBody = @{
        name           = $wrName
        displayname    = "RMA Help"
        webresourcetype= 1            # HTML
        content        = $base64
        languagecode   = 1033         # CRITICAL — empty languagecode breaks dependency lookup
    } | ConvertTo-Json
    $resp = Invoke-WebRequest -Method Post -Uri "$orgUrl/api/data/v9.2/webresourceset" -Headers $h -Body $createBody -UseBasicParsing
    $loc = $resp.Headers["OData-EntityId"]
    if ($loc -is [array]) { $loc = $loc[0] }
    if ($loc -match "\(([0-9a-fA-F-]+)\)") { $wrId = $matches[1] }
    Write-Host "Created web resource id=$wrId"
}

# Publish the web resource
Write-Host "Publishing web resource..."
$pubBody = @{ ParameterXml = "<importexportxml><webresources><webresource>{$wrId}</webresource></webresources></importexportxml>" } | ConvertTo-Json
Invoke-RestMethod -Method Post -Uri "$orgUrl/api/data/v9.2/PublishXml" -Headers $h -Body $pubBody | Out-Null
Write-Host "Published web resource"

# ---- 2. Sitemap: insert Help SubArea ---------------------------------------
Write-Host "Reading current sitemap..."
$smRec = Invoke-RestMethod -Uri "$orgUrl/api/data/v9.2/sitemaps($smId)?`$select=sitemapxml" -Headers $h
$x = [xml]$smRec.sitemapxml

# Already has Help?
$existingHelp = $x.SelectNodes("//SubArea") | Where-Object { $_.Id -eq "rma_subarea_help" }
if ($existingHelp -and $existingHelp.Count -gt 0) {
    Write-Host "Help subarea already exists. Removing first to re-insert with current WebResourceId..."
    foreach ($n in $existingHelp) { [void]$n.ParentNode.RemoveChild($n) }
}
# Already has Help group?
$existingGroup = $x.SelectNodes("//Group") | Where-Object { $_.Id -eq "rma_group_help" }
if ($existingGroup -and $existingGroup.Count -gt 0) {
    foreach ($n in $existingGroup) { [void]$n.ParentNode.RemoveChild($n) }
}

# Build new Group + SubArea
$ns = $x.DocumentElement.NamespaceURI
$area = $x.SelectSingleNode("//Area[@Id='rma_operations_area']")
if (-not $area) { throw "Area rma_operations_area not found" }

$groupXml = @"
<Group Id="rma_group_help" IsProfile="false" Title="Help" ToolTipResourseId="SitemapDesigner.Unknown">
  <SubArea Id="rma_subarea_help" VectorIcon="/WebResources/pp_/icons/rma_question_circle_24_regular.svg" Icon="/WebResources/pp_/icons/rma_question_circle_24_regular.svg" Url="`$webresource:$wrName" Title="Help &amp; Cheat Sheet" AvailableOffline="false" PassParams="false" />
</Group>
"@

# Sitemap XML has no namespace — direct InnerXml append works
$frag = $x.CreateDocumentFragment()
$frag.InnerXml = $groupXml
[void]$area.AppendChild($frag)

# Save updated XML
$updated = $x.OuterXml
Write-Host "New sitemap length: $($updated.Length) (was $($smRec.sitemapxml.Length))"

# Validate it parses
[void]([xml]$updated)
Write-Host "Updated XML validates OK"

# Patch the sitemap
$patchBody = @{ sitemapxml = $updated } | ConvertTo-Json
Invoke-RestMethod -Method Patch -Uri "$orgUrl/api/data/v9.2/sitemaps($smId)" -Headers $h -Body $patchBody | Out-Null
Write-Host "Sitemap patched"

# Publish sitemap + appmodule (forces app to pick up the new subarea)
Write-Host "Publishing sitemap and appmodule..."
$pubAll = @{ ParameterXml = "<importexportxml><sitemaps><sitemap>{$smId}</sitemap></sitemaps><appmodules><appmodule>{$appId}</appmodule></appmodules></importexportxml>" } | ConvertTo-Json
Invoke-RestMethod -Method Post -Uri "$orgUrl/api/data/v9.2/PublishXml" -Headers $h -Body $pubAll | Out-Null
Write-Host "Published sitemap + appmodule"

Write-Host ""
Write-Host "DONE.  Help subarea added at: rma_operations_area > rma_group_help > rma_subarea_help"
Write-Host "Web resource id: $wrId"
Write-Host "Open the app and look for 'Help' group at the bottom of the left sitemap."
