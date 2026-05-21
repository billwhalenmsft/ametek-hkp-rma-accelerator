# deploy_email_inbox_subarea.ps1
# Repoints the existing "Email Inbox" sitemap subarea (rma_subarea_inbox) from
# Entity="rma_emaillog" to Url="$webresource:rma_/productivity/rma_email_assist.html?mode=full"
# so clicking it opens the Outlook.com-style full-page inbox UI rather than the entity list.
#
# Pattern follows the 4 sitemap rules from user memory:
#   1. Web resource (already exists, no upload here — handled by deploy_email_assist_pane.ps1)
#   2. Sitemap Url MUST include the $webresource: prefix
#   3. NO Type="Url" attribute
#   4. NO <Titles> / <Descriptions> elements (inline Title="..." instead)
#   5. PublishXml must include both sitemap AND appmodule
#
# Also adds a second subarea "Email Records" pointing to the original rma_emaillog
# entity list so power-users can still drill into raw records via the sitemap.
#
# Run this AFTER deploy_email_assist_pane.ps1 has uploaded the HTML web resource.

[CmdletBinding()]
param(
    [switch]$DryRun,
    [switch]$Rollback   # restore original Entity-based subarea
)

$ErrorActionPreference = "Stop"

$orgUrl = "https://org6feab6b5.crm.dynamics.com"
$appId  = "8661f960-1f4e-f111-bec6-000d3a5aed87"   # RMA Operations and Monitoring
$smId   = "2191c458-1f4e-f111-bec6-000d3a5aed87"   # Its sitemap
$wrName = "rma_/productivity/rma_email_assist.html"

Write-Host ""
Write-Host "=== deploy_email_inbox_subarea.ps1 ===" -ForegroundColor Cyan
Write-Host "Org:        $orgUrl"
Write-Host "Sitemap:    $smId"
Write-Host "App:        $appId"
Write-Host "DryRun:     $DryRun"
Write-Host "Rollback:   $Rollback"
Write-Host ""

# ---- Token ----
Write-Host "Acquiring token..." -ForegroundColor Gray
$token = (az account get-access-token --resource $orgUrl --query accessToken -o tsv).Trim()
if (-not $token) { throw "az account get-access-token returned empty" }

$h = @{
    Authorization      = "Bearer $token"
    Accept             = "application/json"
    "Content-Type"     = "application/json; charset=utf-8"
    "OData-MaxVersion" = "4.0"
    "OData-Version"    = "4.0"
}

# ---- Read sitemap ----
Write-Host "Fetching current sitemap..." -ForegroundColor Gray
$smRec = Invoke-RestMethod -Uri "$orgUrl/api/data/v9.2/sitemaps($smId)?`$select=sitemapxml" -Headers $h
$xml = [xml]$smRec.sitemapxml
$origLen = $smRec.sitemapxml.Length
Write-Host "Sitemap loaded ($origLen chars)" -ForegroundColor Gray

# ---- Snapshot original to disk (always — for rollback safety) ----
$backupDir = Join-Path $PSScriptRoot "..\backups"
if (-not (Test-Path $backupDir)) { New-Item -ItemType Directory -Path $backupDir | Out-Null }
$ts = Get-Date -Format "yyyyMMdd-HHmmss"
$backupPath = Join-Path $backupDir "sitemap_$ts.xml"
$smRec.sitemapxml | Set-Content -Path $backupPath -Encoding UTF8
Write-Host "Sitemap snapshot written to: $backupPath" -ForegroundColor Gray

# ---- Locate the existing Email Inbox subarea ----
# NOTE: must wrap with @(...) — indexing [0] on a bare XmlElement returns its first CHILD NODE
$inbox = @($xml.SelectNodes("//SubArea") | Where-Object { $_.Id -eq "rma_subarea_inbox" })
if (-not $inbox -or $inbox.Count -eq 0) { throw "Subarea 'rma_subarea_inbox' not found in sitemap" }
$inbox = $inbox[0]

if ($Rollback) {
    Write-Host "ROLLBACK: restoring Entity-based subarea..." -ForegroundColor Yellow
    # Remove inbox-app + inbox-records if present
    $xml.SelectNodes("//SubArea") | Where-Object { $_.Id -in @("rma_subarea_inbox_records") } | ForEach-Object { [void]$_.ParentNode.RemoveChild($_) }
    # Reset inbox to the original entity-based config
    $inbox.RemoveAttribute("Url") 2>$null
    $inbox.SetAttribute("Entity", "rma_emaillog")
    $inbox.SetAttribute("Title", "Email Inbox")
} else {
    Write-Host "Repointing 'Email Inbox' subarea to web resource..." -ForegroundColor Green
    # Drop the Entity attribute (sitemap subarea is EITHER Entity OR Url)
    if ($inbox.HasAttribute("Entity")) { $inbox.RemoveAttribute("Entity") }
    if ($inbox.HasAttribute("DefaultDashboard")) { $inbox.RemoveAttribute("DefaultDashboard") }
    # Set the Url attribute — MUST include $webresource: prefix; NO Type="Url" attribute
    # Brace ${wrName} so PowerShell doesn't slurp '?mode' into the variable name
    $inbox.SetAttribute("Url", "`$webresource:${wrName}?mode=full")
    $inbox.SetAttribute("Title", "Email Inbox")
    # Ensure these inline attrs are present so the subarea renders cleanly
    if (-not $inbox.HasAttribute("AvailableOffline")) { $inbox.SetAttribute("AvailableOffline", "false") }
    if (-not $inbox.HasAttribute("PassParams")) { $inbox.SetAttribute("PassParams", "false") }
    # If there are nested <Titles>/<Descriptions>/<DependencyData> elements, strip them — XSD rejects them
    foreach ($childName in @("Titles", "Descriptions", "DependencyData")) {
        $children = @($inbox.SelectNodes($childName))
        foreach ($c in $children) { [void]$inbox.RemoveChild($c) }
    }

    # Also add a "Email Records" entity subarea so power-users can still get to the raw list
    $hasRecordsSubarea = @($xml.SelectNodes("//SubArea") | Where-Object { $_.Id -eq "rma_subarea_inbox_records" })
    if (-not $hasRecordsSubarea -or $hasRecordsSubarea.Count -eq 0) {
        $parentGroup = $inbox.ParentNode
        $recordsXml = '<SubArea Id="rma_subarea_inbox_records" Entity="rma_emaillog" Title="Email Records" AvailableOffline="false" PassParams="false" />'
        $frag = $xml.CreateDocumentFragment()
        $frag.InnerXml = $recordsXml
        # Insert immediately after the inbox subarea
        if ($inbox.NextSibling) {
            [void]$parentGroup.InsertBefore($frag, $inbox.NextSibling)
        } else {
            [void]$parentGroup.AppendChild($frag)
        }
        Write-Host "  + Added 'Email Records' subarea (entity list) after Email Inbox" -ForegroundColor Gray
    } else {
        Write-Host "  (Email Records subarea already present)" -ForegroundColor Gray
    }
}

$updated = $xml.OuterXml
Write-Host ""
Write-Host "New sitemap length: $($updated.Length) (was $origLen, delta=$($updated.Length - $origLen))" -ForegroundColor Gray

# Validate
[void]([xml]$updated)
Write-Host "XML validates OK" -ForegroundColor Gray

# Show the modified subarea(s) for visibility
Write-Host ""
Write-Host "Modified subareas:" -ForegroundColor Cyan
$verify = [xml]$updated
$verify.SelectNodes("//SubArea") | Where-Object { $_.Id -in @("rma_subarea_inbox","rma_subarea_inbox_records") } | ForEach-Object {
    Write-Host "  Id=$($_.Id) | Entity=$($_.Entity) | Url=$($_.Url) | Title=$($_.Title)"
}
Write-Host ""

if ($DryRun) {
    Write-Host "DRY-RUN: no PATCH or PublishXml issued. Re-run without -DryRun to apply." -ForegroundColor Yellow
    return
}

# ---- PATCH sitemap ----
Write-Host "PATCHing sitemap..." -ForegroundColor Green
$patchBody = @{ sitemapxml = $updated } | ConvertTo-Json -Depth 10
Invoke-RestMethod -Method Patch -Uri "$orgUrl/api/data/v9.2/sitemaps($smId)" -Headers $h -Body $patchBody | Out-Null
Write-Host "Sitemap patched OK" -ForegroundColor Green

# ---- Publish sitemap + appmodule ----
Write-Host "Publishing sitemap + appmodule..." -ForegroundColor Green
$pubXml = "<importexportxml><sitemaps><sitemap>{$smId}</sitemap></sitemaps><appmodules><appmodule>{$appId}</appmodule></appmodules></importexportxml>"
$pubBody = @{ ParameterXml = $pubXml } | ConvertTo-Json
Invoke-RestMethod -Method Post -Uri "$orgUrl/api/data/v9.2/PublishXml" -Headers $h -Body $pubBody | Out-Null
Write-Host "Published sitemap + appmodule OK" -ForegroundColor Green

Write-Host ""
Write-Host "=== DONE ===" -ForegroundColor Cyan
if ($Rollback) {
    Write-Host "Sitemap restored: Email Inbox now opens the rma_emaillog entity list" -ForegroundColor Green
} else {
    Write-Host "Email Inbox now opens the full-page Outlook-style web resource" -ForegroundColor Green
    Write-Host "URL: `$webresource:$wrName?mode=full"
    Write-Host ""
    Write-Host "Refresh the RMA Operations app in your browser (Ctrl+F5) to see the change." -ForegroundColor Yellow
    Write-Host "To roll back: pwsh -File $($MyInvocation.MyCommand.Name) -Rollback" -ForegroundColor Gray
}
Write-Host ""
