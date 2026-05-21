<#
.SYNOPSIS
    Phase 13c (Bill, 5/20): Move the "Email Records" sitemap SubArea from
    the Daily Work group into the History group, and give it a Fluent UI
    icon (mail_clock_24_regular -> "historical emails").

    Steps:
      1. Download mail_clock_24_regular.svg from unpkg CDN (Fluent UI MIT)
      2. Upsert it as a Dataverse web resource pp_/icons/rma_mail_clock_24_regular.svg
      3. Read LIVE sitemap XML
      4. Remove any existing rma_subarea_inbox_records SubArea(s) wherever
         they live (Daily Work group or anywhere else)
      5. Append a single fresh SubArea to rma_group_audit (History group)
         with the new VectorIcon + Icon attributes
      6. PATCH sitemap and PublishXml (sitemap + appmodule together)

    Scope: only sitemap 2191c458-1f4e-f111-bec6-000d3a5aed87 and app
    8661f960-1f4e-f111-bec6-000d3a5aed87 (RMA Operations and Monitoring).
    No other apps touched.
#>

[CmdletBinding()]
param(
  [string]$OrgUrl    = "https://org6feab6b5.crm.dynamics.com",
  [string]$AppId     = "8661f960-1f4e-f111-bec6-000d3a5aed87",
  [string]$SiteMapId = "2191c458-1f4e-f111-bec6-000d3a5aed87",
  [string]$SolutionUniqueName = "RMAReturnsMonitor",
  # Try each in order until one downloads from unpkg. Picked names that
  # convey "records / archive / history of emails".
  [string[]]$IconCandidates = @(
    "mail_read_multiple_24_regular",
    "mail_read_24_regular",
    "archive_24_regular",
    "document_data_24_regular",
    "database_24_regular"
  ),
  [string]$SubAreaId = "rma_subarea_inbox_records",
  [string]$SubAreaTitle = "Email Records",
  [string]$SubAreaEntity = "rma_emaillog"
)
$ErrorActionPreference = "Stop"

# --- Token + headers ---
$token = (az account get-access-token --resource $OrgUrl --query accessToken -o tsv)
$dvHdr = @{
  Authorization              = "Bearer $token"
  Accept                     = "application/json"
  "Content-Type"             = "application/json; charset=utf-8"
  "OData-MaxVersion"         = "4.0"
  "OData-Version"            = "4.0"
  "MSCRM.SolutionUniqueName" = $SolutionUniqueName
}
$dvGet = @{ Authorization = "Bearer $token"; Accept = "application/json" }

# --- Step 1: download a Fluent SVG, trying candidates until one works ---
$wc = New-Object Net.WebClient
$wc.Headers.Add("User-Agent", "PowerShell-FluentIconFetcher")
$iconName = $null
$svgText  = $null
foreach ($candidate in $IconCandidates) {
  $cdnUrl = "https://unpkg.com/@fluentui/svg-icons@latest/icons/$candidate.svg"
  Write-Host "Trying $candidate ... " -NoNewline -ForegroundColor DarkCyan
  try {
    $text = $wc.DownloadString($cdnUrl)
    if (-not [string]::IsNullOrWhiteSpace($text) -and $text.StartsWith('<svg')) {
      Write-Host "OK ($($text.Length) bytes)" -ForegroundColor Green
      $iconName = $candidate
      $svgText  = $text
      break
    } else {
      $preview = if ($text) { $text.Substring(0, [Math]::Min(80, $text.Length)) } else { "<empty>" }
      Write-Host "not SVG ($preview)" -ForegroundColor Yellow
    }
  } catch {
    Write-Host "FAIL ($($_.Exception.Message))" -ForegroundColor Yellow
  }
}
if (-not $svgText) { throw "None of the candidate Fluent icons could be downloaded. Check network or update `$IconCandidates." }

# --- Step 2: upsert as Dataverse web resource ---
$wrName = "pp_/icons/rma_$iconName.svg"
$b64    = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($svgText))

$existing = Invoke-RestMethod -Uri ("$OrgUrl/api/data/v9.2/webresourceset?`$filter=name eq '$wrName'&`$select=webresourceid,name") -Headers $dvGet
$wrBody = @{
  name            = $wrName
  displayname     = "RMA " + ($iconName -replace '_24_regular','' -replace '_',' ')
  description     = "Fluent UI System Icon - $iconName (RMA Email Records sitemap subarea)"
  webresourcetype = 11   # 11 = SVG
  languagecode    = 1033 # REQUIRED for dependency lookups (per user memory rule #1)
  content         = $b64
} | ConvertTo-Json -Compress

$wrId = $null
if ($existing.value -and $existing.value.Count -gt 0) {
  $wrId = $existing.value[0].webresourceid
  $patchHdr = $dvHdr.Clone(); $patchHdr["If-Match"] = "*"
  Invoke-WebRequest -Uri "$OrgUrl/api/data/v9.2/webresourceset($wrId)" -Method Patch -Headers $patchHdr -Body $wrBody -UseBasicParsing | Out-Null
  Write-Host "  Updated existing web resource $wrName (id $wrId)" -ForegroundColor Yellow
} else {
  $resp = Invoke-WebRequest -Uri "$OrgUrl/api/data/v9.2/webresourceset" -Method Post -Headers $dvHdr -Body $wrBody -UseBasicParsing
  $loc = $resp.Headers.'OData-EntityId'
  if ($loc -and $loc -match 'webresourceset\(([^)]+)\)') { $wrId = $matches[1] }
  if (-not $wrId) {
    # Re-query to find the just-created id
    $just = Invoke-RestMethod -Uri ("$OrgUrl/api/data/v9.2/webresourceset?`$filter=name eq '$wrName'&`$select=webresourceid") -Headers $dvGet
    if ($just.value -and $just.value.Count -gt 0) { $wrId = $just.value[0].webresourceid }
  }
  Write-Host "  Created web resource $wrName (id $wrId)" -ForegroundColor Green

  if ($wrId) {
    $pubWr = @{ ParameterXml = "<importexportxml><webresources><webresource>{$wrId}</webresource></webresources></importexportxml>" } | ConvertTo-Json
    Invoke-RestMethod -Method Post -Uri "$OrgUrl/api/data/v9.2/PublishXml" -Headers $dvHdr -Body $pubWr | Out-Null
    Write-Host "  Published web resource" -ForegroundColor Green
  }
}

# --- Step 3: read live sitemap XML ---
Write-Host ""
Write-Host "Reading live sitemap $SiteMapId" -ForegroundColor Cyan
$sm = Invoke-RestMethod -Uri "$OrgUrl/api/data/v9.2/sitemaps($SiteMapId)?`$select=sitemapxml,sitemapname,sitemapnameunique" -Headers $dvGet
Write-Host "  sitemapname: $($sm.sitemapname)   length: $($sm.sitemapxml.Length)"

# Save a backup before mutation
$backupDir = Join-Path $PSScriptRoot "..\backups"
if (-not (Test-Path $backupDir)) { New-Item -ItemType Directory -Path $backupDir | Out-Null }
$ts = Get-Date -Format "yyyyMMdd-HHmmss"
$backupPath = Join-Path $backupDir "sitemap_$ts.before_move_email_records.xml"
$sm.sitemapxml | Set-Content -Path $backupPath -Encoding UTF8
Write-Host "  Backup saved: $backupPath"

# --- Step 4: parse + mutate ---
$x = [xml]$sm.sitemapxml

# Find every SubArea with our Id (regardless of group) and log + remove them
# (Use $existingSubs instead of $matches to avoid clobbering the PS automatic variable.)
$existingSubs = $x.SelectNodes("//SubArea[@Id='$SubAreaId']")
if (-not $existingSubs -or $existingSubs.Count -eq 0) {
  Write-Host "  No existing SubArea with Id=$SubAreaId found in live sitemap (creating fresh)" -ForegroundColor Yellow
} else {
  foreach ($n in @($existingSubs)) {
    $parentGroup = $n.ParentNode
    $parentGroupId = $parentGroup.Id
    Write-Host "  Removing existing SubArea $SubAreaId from group '$parentGroupId'" -ForegroundColor Yellow
    [void]$parentGroup.RemoveChild($n)
  }
}

# Find History group
$historyGroup = $x.SelectSingleNode("//Group[@Id='rma_group_audit']")
if (-not $historyGroup) {
  # Show groups available so user can correct if needed
  $groupsFound = ($x.SelectNodes("//Group") | ForEach-Object { $_.Id }) -join ", "
  throw "rma_group_audit (History group) not found. Available groups: $groupsFound"
}

# Build + append new SubArea
$iconUrl = "/WebResources/pp_/icons/rma_$iconName.svg"
$newSubAreaXml = "<SubArea Id=`"$SubAreaId`" Entity=`"$SubAreaEntity`" Title=`"$SubAreaTitle`" VectorIcon=`"$iconUrl`" Icon=`"$iconUrl`" AvailableOffline=`"false`" PassParams=`"false`" />"
$frag = $x.CreateDocumentFragment()
$frag.InnerXml = $newSubAreaXml
[void]$historyGroup.AppendChild($frag)
Write-Host "  Added SubArea $SubAreaId to rma_group_audit with icon $iconUrl" -ForegroundColor Green

# Validate
$updated = $x.OuterXml
[void]([xml]$updated)
Write-Host "  Updated XML validates OK (length: $($updated.Length), was $($sm.sitemapxml.Length))"

# --- Step 5: PATCH sitemap ---
$patchBody = @{ sitemapxml = $updated } | ConvertTo-Json
$patchHdr  = $dvHdr.Clone(); $patchHdr["If-Match"] = "*"
Invoke-RestMethod -Method Patch -Uri "$OrgUrl/api/data/v9.2/sitemaps($SiteMapId)" -Headers $patchHdr -Body $patchBody | Out-Null
Write-Host "Sitemap PATCHed" -ForegroundColor Green

# --- Step 6: Publish sitemap + appmodule together (per user memory rule #4) ---
$pubAll = @{ ParameterXml = "<importexportxml><sitemaps><sitemap>{$SiteMapId}</sitemap></sitemaps><appmodules><appmodule>{$AppId}</appmodule></appmodules></importexportxml>" } | ConvertTo-Json
Invoke-RestMethod -Method Post -Uri "$OrgUrl/api/data/v9.2/PublishXml" -Headers $dvHdr -Body $pubAll | Out-Null
Write-Host "Published sitemap + appmodule" -ForegroundColor Green

Write-Host ""
Write-Host "DONE.  Email Records moved to: rma_operations_area > rma_group_audit (History)" -ForegroundColor Cyan
Write-Host "       Icon:  $iconUrl"
Write-Host "       Hard-refresh the app (Ctrl+F5) to see the updated left nav."
