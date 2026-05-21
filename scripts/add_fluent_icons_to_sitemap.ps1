<#
.SYNOPSIS
    Add Fluent UI System Icons to the RMA Operations & Monitoring MDA sitemap.
    SCOPE: Only sitemap 2191c458-1f4e-f111-bec6-000d3a5aed87 (the RMA app).
    Other apps (Customer Service, Sales, etc.) are NOT touched.

    Workflow:
      1. Download Fluent SVGs from unpkg CDN (no auth, MIT license)
      2. Upload each as a Dataverse web resource (pp_/icons/rma_*.svg, type 11 = SVG)
      3. Patch the sitemap XML to add Icon="$webresource:..." per SubArea
      4. PATCH the sitemap, then publish only that sitemap entity
#>

[CmdletBinding()]
param(
  [string]$OrgUrl  = "https://org6feab6b5.crm.dynamics.com",
  [string]$AppId   = "8661f960-1f4e-f111-bec6-000d3a5aed87",  # RMA Operations and Monitoring
  [string]$SiteMapId = "2191c458-1f4e-f111-bec6-000d3a5aed87",
  [string]$SolutionUniqueName = "RMAReturnsMonitor"
)
$ErrorActionPreference = "Stop"

# --- Icon map: SubArea Id => Fluent icon name (24px regular) ---
# Browse icons: https://github.com/microsoft/fluentui-system-icons/blob/main/icons_regular.md
$IconMap = [ordered]@{
  "rma_subarea_board"           = "board_24_regular"             # Kanban / board view
  "rma_subarea_inbox"           = "mail_inbox_24_regular"        # Email Inbox
  "rma_subarea_claims"          = "clipboard_task_24_regular"    # RMA Claims (work items)
  "rma_subarea_approvals"       = "checkmark_circle_24_regular"  # Approvals (active)
  "rma_subarea_plants"          = "building_factory_24_regular"  # Plants
  "rma_subarea_routing"         = "arrow_routing_24_regular"     # Routing Rules
  "rma_subarea_approvers"       = "people_24_regular"            # Plant Approvers
  "rma_subarea_templates"       = "mail_template_24_regular"     # Email Templates
  "rma_subarea_signatures"      = "signature_24_regular"         # Email Signatures
  "rma_subarea_claimnotes"      = "note_24_regular"              # Claim Notes
  "rma_subarea_approvalhistory" = "history_24_regular"           # Approval History
}

# --- Token + headers ---
$token = (az account get-access-token --resource $OrgUrl --query accessToken -o tsv)
$dvHdr = @{
  Authorization = "Bearer $token"
  Accept        = "application/json"
  "Content-Type" = "application/json; charset=utf-8"
  "OData-MaxVersion" = "4.0"
  "OData-Version"    = "4.0"
  "MSCRM.SolutionUniqueName" = $SolutionUniqueName
}
$dvGet = @{ Authorization = "Bearer $token"; Accept = "application/json" }

# --- Step 1+2: Download each SVG from unpkg, upsert as web resource ---
$webResNames = @{}  # subAreaId => web resource name
foreach ($subAreaId in $IconMap.Keys) {
  $iconName = $IconMap[$subAreaId]
  $cdnUrl   = "https://unpkg.com/@fluentui/svg-icons@latest/icons/$iconName.svg"
  $wrName   = "pp_/icons/rma_$iconName.svg"
  $wrSchema = "pp_icons_rma_$iconName"

  Write-Host "[$subAreaId] ↓ $iconName" -ForegroundColor DarkCyan
  try {
    # Use WebClient for clean text download (Invoke-WebRequest returns mixed content type on PS 5.1)
    $svgText = (New-Object Net.WebClient).DownloadString($cdnUrl)
    if ([string]::IsNullOrWhiteSpace($svgText) -or -not $svgText.StartsWith('<svg')) {
      throw "unexpected response (not SVG)"
    }
  } catch {
    Write-Host "    !! download failed: $($_.Exception.Message)" -ForegroundColor Red
    continue
  }

  # Make icon currentColor-friendly (Fluent SVGs use fill=currentColor by default — keep as-is)
  $b64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($svgText))

  # Check if web resource exists
  $existing = Invoke-RestMethod -Uri ("$OrgUrl/api/data/v9.2/webresourceset?`$filter=name eq '$wrName'&`$select=webresourceid,name") -Headers $dvGet
  $body = @{
    name              = $wrName
    displayname       = "RMA " + ($iconName -replace '_24_regular','' -replace '_',' ')
    description       = "Fluent UI System Icon - $iconName (used by RMA Operations app sitemap)"
    webresourcetype   = 11   # 11 = SVG
    content           = $b64
  } | ConvertTo-Json -Compress

  if ($existing.value.Count -gt 0) {
    $wrId = $existing.value[0].webresourceid
    $patchHdr = $dvHdr.Clone(); $patchHdr["If-Match"] = "*"
    Invoke-WebRequest -Uri "$OrgUrl/api/data/v9.2/webresourceset($wrId)" -Method Patch -Headers $patchHdr -Body $body | Out-Null
    Write-Host "    ↻ updated existing $wrName" -ForegroundColor Yellow
  } else {
    $resp = Invoke-WebRequest -Uri "$OrgUrl/api/data/v9.2/webresourceset" -Method Post -Headers $dvHdr -Body $body
    $loc = $resp.Headers.'OData-EntityId'
    if ($loc -match 'webresourceset\(([^)]+)\)') { $wrId = $matches[1] }
    Write-Host "    + created $wrName" -ForegroundColor Green
  }
  $webResNames[$subAreaId] = $wrName
}

# --- Step 3: Patch sitemap XML to add Icon attribute on each SubArea ---
Write-Host ""
Write-Host "Patching sitemap XML..." -ForegroundColor Cyan
$sm = Invoke-RestMethod -Uri "$OrgUrl/api/data/v9.2/sitemaps($SiteMapId)?`$select=sitemapxml" -Headers $dvGet
$xml = $sm.sitemapxml

foreach ($subAreaId in $webResNames.Keys) {
  $wrName = $webResNames[$subAreaId]
  $iconAttr = "Icon=`"`$webresource:$wrName`""
  # Match the SubArea element with this Id, then ensure Icon attr is set (replace if exists)
  $pattern  = '(<SubArea\s+Id="' + [regex]::Escape($subAreaId) + '")(\s+Icon="[^"]*")?'
  $replace  = '$1 ' + $iconAttr
  $newXml   = [regex]::Replace($xml, $pattern, $replace)
  if ($newXml -eq $xml) {
    Write-Host "  !! could not match SubArea $subAreaId" -ForegroundColor Red
  } else {
    Write-Host "  ✓ $subAreaId → $wrName" -ForegroundColor Green
    $xml = $newXml
  }
}

# --- Step 4: PATCH sitemap and publish ---
$patchHdr = $dvHdr.Clone(); $patchHdr["If-Match"] = "*"
$patchBody = @{ sitemapxml = $xml } | ConvertTo-Json -Compress
Invoke-WebRequest -Uri "$OrgUrl/api/data/v9.2/sitemaps($SiteMapId)" -Method Patch -Headers $patchHdr -Body $patchBody | Out-Null
Write-Host ""
Write-Host "[ok] Sitemap PATCHed" -ForegroundColor Green

# Publish only this sitemap (scoped, doesn't touch other MDAs)
$pubHdr = $dvHdr.Clone()
$pubXml  = "<importexportxml><sitemaps><sitemap>$SiteMapId</sitemap></sitemaps></importexportxml>"
$pubBody = @{ ParameterXml = $pubXml } | ConvertTo-Json -Compress
Invoke-RestMethod -Uri "$OrgUrl/api/data/v9.2/PublishXml" -Method Post -Headers $pubHdr -Body $pubBody | Out-Null
Write-Host "[ok] Sitemap published (scoped to RMA Operations app only)" -ForegroundColor Green
Write-Host ""
Write-Host "Refresh the MDA in browser (Ctrl+F5) to see the new icons." -ForegroundColor Cyan
