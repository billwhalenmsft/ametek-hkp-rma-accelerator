<#
.SYNOPSIS
    Populate the "RMA Operations and Monitoring" Model-Driven app.

    App ID: 8661f960-1f4e-f111-bec6-000d3a5aed87
#>

[CmdletBinding()]
param(
    [string]$OrgUrl = "https://org6feab6b5.crm.dynamics.com",
    [string]$AppId  = "8661f960-1f4e-f111-bec6-000d3a5aed87"
)

$ErrorActionPreference = "Stop"

$token = (az account get-access-token --resource $OrgUrl --query accessToken -o tsv)
$hdrBase = @{
    Authorization      = "Bearer $token"
    Accept             = "application/json"
    "OData-Version"    = "4.0"
    "OData-MaxVersion" = "4.0"
    "MSCRM.SolutionUniqueName" = "RMAReturnsMonitor"
}

function Invoke-Dv {
    param([string]$Method, [string]$Path, $Body = $null, [switch]$ReturnHeaders, [int]$MaxRetries = 5)
    $url = "$OrgUrl/api/data/v9.2/$Path"
    $h = $hdrBase.Clone()
    if ($Method -in @('PATCH','DELETE')) { $h['If-Match'] = '*' }
    if ($Body) { $h['Content-Type'] = 'application/json; charset=utf-8' }
    $params = @{ Uri = $url; Method = $Method; Headers = $h }
    if ($Body) { $params.Body = ($Body | ConvertTo-Json -Depth 30 -Compress) }
    $attempt = 0
    while ($true) {
        $attempt++
        try {
            if ($ReturnHeaders) { return Invoke-WebRequest @params -ErrorAction Stop }
            return Invoke-RestMethod @params -ErrorAction Stop
        } catch {
            $msg = $_.Exception.Message
            if ($_.ErrorDetails.Message) { $msg = $_.ErrorDetails.Message }
            if ($msg -match '0x80072324|Too many concurrent|429|503' -and $attempt -lt $MaxRetries) {
                $wait = [Math]::Min(60, [Math]::Pow(2, $attempt) * 2)
                Write-Host "    [throttled] retry $attempt after ${wait}s..." -ForegroundColor DarkYellow
                Start-Sleep -Seconds $wait
                continue
            }
            throw "API [$Method $Path]: $msg"
        }
    }
}

Write-Host "`n=== Populating RMA Operations and Monitoring ===" -ForegroundColor Cyan
$app = Invoke-Dv -Method GET -Path "appmodules($AppId)?`$select=name,uniquename"
Write-Host "  App: $($app.name) [$($app.uniquename)]" -ForegroundColor Green

# ============================================================================
# STEP 1: Add all 10 entities
# ============================================================================
Write-Host "`nStep 1: Add 10 entities to the app" -ForegroundColor Cyan
$entities = @(
    "rma_claim", "rma_emaillog", "rma_approvalrecord",
    "rma_plant", "rma_routingrule", "rma_plantapprover",
    "rma_emailtemplate", "rma_emailsignature",
    "rma_claimnote", "rma_approvalhistory"
)
foreach ($e in $entities) {
    try {
        $em = Invoke-Dv -Method GET -Path "EntityDefinitions(LogicalName='$e')?`$select=LogicalName,MetadataId"
        Invoke-Dv -Method POST -Path "appmodules($AppId)/Microsoft.Dynamics.CRM.AddAppComponents" -Body @{
            Components = @(@{ "@odata.id" = "$OrgUrl/api/data/v9.2/EntityDefinitions($($em.MetadataId))" })
        } | Out-Null
        Write-Host "  [add] $e" -ForegroundColor Green
    } catch {
        $m = $_.Exception.Message
        if ($_.ErrorDetails.Message) { $m = $_.ErrorDetails.Message }
        if ($m -match 'already|duplicate|exists as a component') {
            Write-Host "  [skip] $e already in app" -ForegroundColor DarkGray
        } else {
            Write-Host "  [warn] $e : $m" -ForegroundColor DarkYellow
        }
    }
}

# ============================================================================
# STEP 2: Sitemap
# ============================================================================
Write-Host "`nStep 2: Build + link sitemap" -ForegroundColor Cyan

$sitemapXml = @"
<SiteMap IntroducedVersion="9.0.0.0">
  <Area Id="rma_operations_area" ShowGroups="true" Title="RMA Operations">
    <Group Id="rma_group_work" Title="Daily Work">
      <SubArea Id="rma_subarea_claims" Entity="rma_claim" Title="RMA Claims">
        <Privilege Entity="rma_claim" Privilege="Read" />
      </SubArea>
      <SubArea Id="rma_subarea_inbox" Entity="rma_emaillog" Title="Email Inbox">
        <Privilege Entity="rma_emaillog" Privilege="Read" />
      </SubArea>
      <SubArea Id="rma_subarea_approvals" Entity="rma_approvalrecord" Title="Approvals">
        <Privilege Entity="rma_approvalrecord" Privilege="Read" />
      </SubArea>
    </Group>
    <Group Id="rma_group_admin" Title="Configuration">
      <SubArea Id="rma_subarea_plants" Entity="rma_plant" Title="Plants">
        <Privilege Entity="rma_plant" Privilege="Read" />
      </SubArea>
      <SubArea Id="rma_subarea_routing" Entity="rma_routingrule" Title="Routing Rules">
        <Privilege Entity="rma_routingrule" Privilege="Read" />
      </SubArea>
      <SubArea Id="rma_subarea_approvers" Entity="rma_plantapprover" Title="Plant Approvers">
        <Privilege Entity="rma_plantapprover" Privilege="Read" />
      </SubArea>
      <SubArea Id="rma_subarea_templates" Entity="rma_emailtemplate" Title="Email Templates">
        <Privilege Entity="rma_emailtemplate" Privilege="Read" />
      </SubArea>
      <SubArea Id="rma_subarea_signatures" Entity="rma_emailsignature" Title="Email Signatures">
        <Privilege Entity="rma_emailsignature" Privilege="Read" />
      </SubArea>
    </Group>
    <Group Id="rma_group_audit" Title="History">
      <SubArea Id="rma_subarea_claimnotes" Entity="rma_claimnote" Title="Claim Notes">
        <Privilege Entity="rma_claimnote" Privilege="Read" />
      </SubArea>
      <SubArea Id="rma_subarea_approvalhistory" Entity="rma_approvalhistory" Title="Approval History">
        <Privilege Entity="rma_approvalhistory" Privilege="Read" />
      </SubArea>
    </Group>
  </Area>
</SiteMap>
"@

# Find existing sitemap for this app
$sitemapId = $null
$rc = Invoke-Dv -Method GET -Path "RetrieveAppComponents(AppModuleId=$AppId)"
$existingSitemap = $rc.AppComponents | Where-Object { $_.ComponentType -eq 62 } | Select-Object -First 1
if ($existingSitemap) {
    $sitemapId = $existingSitemap.ObjectId
    Write-Host "  [found] existing sitemap $sitemapId" -ForegroundColor DarkGray
    Invoke-Dv -Method PATCH -Path "sitemaps($sitemapId)" -Body @{ sitemapxml = $sitemapXml } | Out-Null
    Write-Host "  [patch] sitemap XML updated" -ForegroundColor Green
} else {
    Write-Host "  [info] no sitemap linked, creating new one..." -ForegroundColor Yellow
    $body = @{
        sitemapname       = "RMA Operations and Monitoring"
        sitemapnameunique = "cr74e_RMAOperationsandMonitoring_sitemap"
        sitemapxml        = $sitemapXml
    }
    $resp = Invoke-Dv -Method POST -Path "sitemaps" -Body $body -ReturnHeaders
    $loc = $resp.Headers['OData-EntityId']
    if ($loc -is [array]) { $loc = $loc[0] }
    if ($loc -match '\(([0-9a-fA-F\-]{36})\)') { $sitemapId = $matches[1] }
    Write-Host "  [create] sitemap -> $sitemapId" -ForegroundColor Green

    # Attach to appmodule via AddAppComponents
    try {
        Invoke-Dv -Method POST -Path "appmodules($AppId)/Microsoft.Dynamics.CRM.AddAppComponents" -Body @{
            Components = @(@{ "@odata.id" = "$OrgUrl/api/data/v9.2/sitemaps($sitemapId)" })
        } | Out-Null
        Write-Host "  [link]  sitemap -> app" -ForegroundColor Green
    } catch {
        $m = $_.Exception.Message
        if ($_.ErrorDetails.Message) { $m = $_.ErrorDetails.Message }
        Write-Host "  [warn] link sitemap: $m" -ForegroundColor DarkYellow
    }
}

# ============================================================================
# STEP 3: Publish (best-effort, may stall — that's OK)
# ============================================================================
Write-Host "`nStep 3: Publish (best-effort)" -ForegroundColor Cyan
try {
    $publishXml = "<importexportxml><appmodules><appmodule>$AppId</appmodule></appmodules>"
    if ($sitemapId) { $publishXml += "<sitemaps><sitemap>$sitemapId</sitemap></sitemaps>" }
    $publishXml += "</importexportxml>"
    # Time-bounded — don't sit forever
    $job = Start-Job -ScriptBlock {
        param($url, $token, $body)
        $h = @{
            Authorization      = "Bearer $token"
            Accept             = "application/json"
            "Content-Type"     = "application/json; charset=utf-8"
            "OData-Version"    = "4.0"
            "OData-MaxVersion" = "4.0"
        }
        Invoke-WebRequest -Uri "$url/api/data/v9.2/PublishXml" -Method Post -Headers $h -Body ($body | ConvertTo-Json -Compress)
    } -ArgumentList $OrgUrl, $token, @{ ParameterXml = $publishXml }
    if (Wait-Job $job -Timeout 90) {
        $r = Receive-Job $job
        Write-Host "  [ok] publish ($($r.StatusCode))" -ForegroundColor Green
    } else {
        Write-Host "  [info] publish still running >90s — proceeding (it'll finish in background)" -ForegroundColor DarkYellow
    }
    Remove-Job $job -Force -ErrorAction SilentlyContinue
} catch {
    $m = $_.Exception.Message
    if ($_.ErrorDetails.Message) { $m = $_.ErrorDetails.Message }
    Write-Host "  [warn] publish: $m" -ForegroundColor DarkYellow
}

# ============================================================================
# Final verification
# ============================================================================
Write-Host "`n=== Verification ===" -ForegroundColor Cyan
$rc = Invoke-Dv -Method GET -Path "RetrieveAppComponents(AppModuleId=$AppId)"
Write-Host "  Components in app: $($rc.AppComponents.Count)" -ForegroundColor Green
$rc.AppComponents | Group-Object ComponentType | ForEach-Object {
    $type = switch ($_.Name) {
        '1'  { 'Entity' }
        '62' { 'SiteMap' }
        '60' { 'SystemForm' }
        '26' { 'SavedQuery' }
        default { "Type $($_.Name)" }
    }
    Write-Host "    $type : $($_.Count)" -ForegroundColor DarkGray
}

Write-Host "`n=== DONE ===" -ForegroundColor Cyan
Write-Host "App URL: $OrgUrl/main.aspx?appid=$AppId" -ForegroundColor Yellow
Write-Host ""
Write-Host "Open the app. If nav is empty, do a hard refresh (Ctrl+F5)."
Write-Host "If publish stalls in the UI, the API publish above completed when you saw [ok] publish."
