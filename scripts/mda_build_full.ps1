<#
.SYNOPSIS
    Build the RMA Operations Model-Driven app fully via REST.

    Steps:
    1. Clean up any orphaned solutioncomponent entries pointing to the phantom appId.
    2. Create an HTML webresource (rma_operations_app_resource) — required by appmodule.
    3. Create the appmodule pointing to that webresource.
    4. Create + link the sitemap.
    5. Add 10 entities via AddAppComponents.
    6. Publish.
#>

[CmdletBinding()]
param(
    [string]$OrgUrl     = "https://org6feab6b5.crm.dynamics.com",
    [string]$PhantomApp = "50c3f3eb-194e-f111-bec6-000d3a5aed87"
)

$ErrorActionPreference = "Stop"

$token = (az account get-access-token --resource $OrgUrl --query accessToken -o tsv)
if (-not $token) { throw "No token." }

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

Write-Host "`n=== RMA Operations app — full programmatic build ===`n" -ForegroundColor Cyan

# ============================================================================
# STEP 0: Clean up orphan solutioncomponent entries
# ============================================================================
Write-Host "Step 0: Clean orphan solutioncomponent entries for phantom app $PhantomApp" -ForegroundColor Cyan
try {
    $orphans = (Invoke-Dv -Method GET -Path "solutioncomponents?`$filter=componenttype eq 80 and objectid eq $PhantomApp&`$select=solutioncomponentid,_solutionid_value").value
    foreach ($o in $orphans) {
        try {
            Invoke-Dv -Method DELETE -Path "solutioncomponents($($o.solutioncomponentid))" | Out-Null
            Write-Host "  [delete] orphan solution component $($o.solutioncomponentid)" -ForegroundColor DarkGray
        } catch {
            Write-Host "  [warn] couldn't delete orphan $($o.solutioncomponentid)" -ForegroundColor DarkYellow
        }
    }
} catch {
    Write-Host "  [info] no orphans to clean" -ForegroundColor DarkGray
}

# ============================================================================
# STEP 1: Create the placeholder HTML webresource (required by appmodule)
# ============================================================================
Write-Host "`nStep 1: Create / find HTML webresource" -ForegroundColor Cyan
$wrUniqueName = "rma_/appresource/rma_operations_app_resource.html"
$webResourceId = $null

# Look for existing
$existingWr = (Invoke-Dv -Method GET -Path "webresourceset?`$filter=name eq '$wrUniqueName'&`$select=webresourceid,name,displayname").value
if ($existingWr.Count -gt 0) {
    $webResourceId = $existingWr[0].webresourceid
    Write-Host "  [skip] webresource exists -> $webResourceId" -ForegroundColor DarkGray
} else {
    # Minimal HTML content base64-encoded
    $htmlContent = '<!DOCTYPE html><html><head><title>RMA Operations</title></head><body></body></html>'
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($htmlContent)
    $b64 = [Convert]::ToBase64String($bytes)
    $body = @{
        name             = $wrUniqueName
        displayname      = "RMA Operations App Resource"
        webresourcetype  = 1   # HTML
        content          = $b64
        description      = "Placeholder web resource for RMA Operations model-driven app"
        languagecode     = 1033
    }
    $resp = Invoke-Dv -Method POST -Path "webresourceset" -Body $body -ReturnHeaders
    $loc = $resp.Headers['OData-EntityId']
    if ($loc -is [array]) { $loc = $loc[0] }
    if ($loc -match '\(([0-9a-fA-F\-]{36})\)') { $webResourceId = $matches[1] }
    Write-Host "  [create] webresource -> $webResourceId" -ForegroundColor Green
}

# ============================================================================
# STEP 2: Create the appmodule
# ============================================================================
Write-Host "`nStep 2: Create appmodule" -ForegroundColor Cyan
$appUniqueName = "rma_RMAOperations"
$appDisplayName = "RMA Operations"

$existingApp = (Invoke-Dv -Method GET -Path "appmodules?`$filter=uniquename eq '$appUniqueName'&`$select=appmoduleid,name").value
$appModuleId = $null
if ($existingApp.Count -gt 0) {
    $appModuleId = $existingApp[0].appmoduleid
    Write-Host "  [skip] appmodule exists -> $appModuleId" -ForegroundColor DarkGray
} else {
    # Build JSON literally. Note: webresourceid is a Uniqueidentifier primitive
    # (not a Lookup), so it takes the GUID directly — no @odata.bind needed.
    $descriptorGuid = [Guid]::NewGuid().ToString()
    $bodyJson = @"
{
  "name": "$appDisplayName",
  "uniquename": "$appUniqueName",
  "description": "Model-Driven app for RMA claim operations across HKP plants",
  "clienttype": 4,
  "navigationtype": 1,
  "formfactor": 1,
  "isfeatured": false,
  "isdefault": false,
  "descriptor": "{\"appId\":\"$descriptorGuid\",\"title\":\"RMA Operations\",\"webResourceId\":\"$webResourceId\"}",
  "webresourceid": "$webResourceId"
}
"@
    try {
        $h = $hdrBase.Clone()
        $h['Content-Type'] = 'application/json; charset=utf-8'
        $resp = Invoke-WebRequest -Uri "$OrgUrl/api/data/v9.2/appmodules" -Method Post -Headers $h -Body $bodyJson -ErrorAction Stop
        $loc = $resp.Headers['OData-EntityId']
        if ($loc -is [array]) { $loc = $loc[0] }
        if ($loc -match '\(([0-9a-fA-F\-]{36})\)') { $appModuleId = $matches[1] }
        Write-Host "  [create] appmodule -> $appModuleId" -ForegroundColor Green
    } catch {
        $msg = $_.Exception.Message
        if ($_.ErrorDetails.Message) { $msg = $_.ErrorDetails.Message }
        Write-Host "  [FAIL] $msg" -ForegroundColor Red
        throw
    }
}

# ============================================================================
# STEP 3: Sitemap
# ============================================================================
Write-Host "`nStep 3: Build + link sitemap" -ForegroundColor Cyan

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

$smUnique = "rma_RMAOperations_sitemap"
$existingSm = (Invoke-Dv -Method GET -Path "sitemaps?`$filter=sitemapnameunique eq '$smUnique'&`$select=sitemapid,sitemapname").value
$sitemapId = $null
if ($existingSm.Count -gt 0) {
    $sitemapId = $existingSm[0].sitemapid
    Write-Host "  [exists] sitemap -> $sitemapId — updating XML" -ForegroundColor DarkGray
    Invoke-Dv -Method PATCH -Path "sitemaps($sitemapId)" -Body @{ sitemapxml = $sitemapXml } | Out-Null
} else {
    $body = @{
        sitemapname       = "RMA Operations Sitemap"
        sitemapnameunique = $smUnique
        sitemapxml        = $sitemapXml
    }
    $resp = Invoke-Dv -Method POST -Path "sitemaps" -Body $body -ReturnHeaders
    $loc = $resp.Headers['OData-EntityId']
    if ($loc -is [array]) { $loc = $loc[0] }
    if ($loc -match '\(([0-9a-fA-F\-]{36})\)') { $sitemapId = $matches[1] }
    Write-Host "  [create] sitemap -> $sitemapId" -ForegroundColor Green
}

# Link sitemap to appmodule via N:N (relationship name: appmodule_sitemap)
try {
    Invoke-Dv -Method POST -Path "appmodules($appModuleId)/appmodule_sitemap/`$ref" -Body @{
        "@odata.id" = "$OrgUrl/api/data/v9.2/sitemaps($sitemapId)"
    } | Out-Null
    Write-Host "  [link]  sitemap -> app" -ForegroundColor Green
} catch {
    $m = $_.Exception.Message
    if ($_.ErrorDetails.Message) { $m = $_.ErrorDetails.Message }
    if ($m -match 'already|duplicate') {
        Write-Host "  [skip]  sitemap already linked" -ForegroundColor DarkGray
    } else {
        Write-Host "  [warn]  link sitemap: $m" -ForegroundColor DarkYellow
    }
}

# ============================================================================
# STEP 4: Add entities
# ============================================================================
Write-Host "`nStep 4: Add 10 RMA entities to the app" -ForegroundColor Cyan

$entities = @(
    "rma_claim", "rma_emaillog", "rma_approvalrecord",
    "rma_plant", "rma_routingrule", "rma_plantapprover",
    "rma_emailtemplate", "rma_emailsignature",
    "rma_claimnote", "rma_approvalhistory"
)

foreach ($e in $entities) {
    try {
        $em = Invoke-Dv -Method GET -Path "EntityDefinitions(LogicalName='$e')?`$select=LogicalName,MetadataId"
        Invoke-Dv -Method POST -Path "appmodules($appModuleId)/Microsoft.Dynamics.CRM.AddAppComponents" -Body @{
            Components = @(
                @{ "@odata.id" = "$OrgUrl/api/data/v9.2/EntityDefinitions($($em.MetadataId))" }
            )
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
# STEP 5: Validate + publish
# ============================================================================
Write-Host "`nStep 5: Validate app" -ForegroundColor Cyan
try {
    Invoke-Dv -Method POST -Path "ValidateApp" -Body @{ AppModuleId = $appModuleId } | Out-Null
    Write-Host "  [ok] validate" -ForegroundColor Green
} catch {
    $m = $_.Exception.Message
    if ($_.ErrorDetails.Message) { $m = $_.ErrorDetails.Message }
    Write-Host "  [warn] validate: $m" -ForegroundColor DarkYellow
}

Write-Host "`nStep 6: Publish" -ForegroundColor Cyan
try {
    $publishXml = "<importexportxml><appmodules><appmodule>$appModuleId</appmodule></appmodules><sitemaps><sitemap>$sitemapId</sitemap></sitemaps></importexportxml>"
    Invoke-Dv -Method POST -Path "PublishXml" -Body @{ ParameterXml = $publishXml } | Out-Null
    Write-Host "  [ok] publish" -ForegroundColor Green
} catch {
    $m = $_.Exception.Message
    if ($_.ErrorDetails.Message) { $m = $_.ErrorDetails.Message }
    Write-Host "  [warn] publish: $m" -ForegroundColor DarkYellow
}

Write-Host "`n=== DONE ===" -ForegroundColor Cyan
Write-Host "App ID:       $appModuleId" -ForegroundColor Green
Write-Host "App URL:      $OrgUrl/main.aspx?appid=$appModuleId" -ForegroundColor Green
Write-Host ""
Write-Host "Open the app and look for the 3 groups in left nav:" -ForegroundColor Yellow
Write-Host "  - Daily Work (Claims, Inbox, Approvals)"
Write-Host "  - Configuration (Plants, Routing Rules, Approvers, Templates, Signatures)"
Write-Host "  - History (Claim Notes, Approval History)"
