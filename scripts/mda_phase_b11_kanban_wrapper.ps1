<#
.SYNOPSIS
    Fix the kanban subarea + clean up sitemap.

    The issue: sitemap SubArea with Url="$webresource:..." strips query strings.
    Solution: create a thin HKP-specific wrapper HTML that embeds the pp_kanban
    iframe with HKP config hardcoded. Point sitemap to the wrapper.

    Also: drop the Analytics subarea (redundant with the dashboard view in MDA).
#>

[CmdletBinding()]
param(
    [string]$OrgUrl = "https://org6feab6b5.crm.dynamics.com"
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
    param([string]$Method, [string]$Path, $Body = $null, [switch]$ReturnHeaders)
    $url = "$OrgUrl/api/data/v9.2/$Path"
    $h = $hdrBase.Clone()
    if ($Method -in @('PATCH','DELETE')) { $h['If-Match'] = '*' }
    if ($Body) { $h['Content-Type'] = 'application/json; charset=utf-8' }
    $params = @{ Uri = $url; Method = $Method; Headers = $h }
    if ($Body) {
        $params.Body = if ($Body -is [string]) { $Body } else { ($Body | ConvertTo-Json -Depth 30 -Compress) }
    }
    if ($ReturnHeaders) { return Invoke-WebRequest @params }
    return Invoke-RestMethod @params
}

# -----------------------------------------------------------------------
# 1. HKP-specific wrapper: rma_/board/claims_board.html
#    Hardcodes the kanban params, iframes pp_kanban
# -----------------------------------------------------------------------
$wrapper = @'
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8" />
<style>
  html, body { margin: 0; padding: 0; height: 100%; overflow: hidden; }
  iframe { width: 100%; height: 100%; border: 0; display: block; }
</style>
</head>
<body>
<iframe
  src="/WebResources/pp_/kanban/kanban.html?entity=rma_claim&group=rma_status&title=rma_claimnumber&subtitle=rma_customername&fields=rma_partnumber,rma_assignedplant,rma_creditamount&badge=rma_stageagedays&filter=statecode%20eq%200"
  title="RMA Claims Kanban"></iframe>
</body>
</html>
'@

$wrapperName = "rma_/board/claims_board.html"
$bytes = [System.Text.Encoding]::UTF8.GetBytes($wrapper)
$b64 = [Convert]::ToBase64String($bytes)

Write-Host "`n=== Fix kanban subarea ===`n" -ForegroundColor Cyan

Write-Host "Step 1: Create/update HKP wrapper web resource" -ForegroundColor Cyan
$ex = (Invoke-Dv -Method GET -Path "webresourceset?`$filter=name eq '$wrapperName'&`$select=webresourceid").value
if ($ex.Count -gt 0) {
    $wrapperId = $ex[0].webresourceid
    Invoke-Dv -Method PATCH -Path "webresourceset($wrapperId)" -Body @{ content = $b64; displayname = "HKP Claims Board (wrapper)" } | Out-Null
    Write-Host "  [update] $wrapperName -> $wrapperId" -ForegroundColor DarkGray
} else {
    $body = @{
        name             = $wrapperName
        displayname      = "HKP Claims Board (wrapper)"
        webresourcetype  = 1
        content          = $b64
        description      = "HKP-specific wrapper that iframes pp_kanban with HKP claim params. Used as sitemap subarea."
        languagecode     = 1033
    }
    $r = Invoke-Dv -Method POST -Path "webresourceset" -Body $body -ReturnHeaders
    $loc = $r.Headers['OData-EntityId']
    if ($loc -is [array]) { $loc = $loc[0] }
    if ($loc -match '\(([0-9a-fA-F\-]{36})\)') { $wrapperId = $matches[1] }
    Write-Host "  [create] $wrapperName -> $wrapperId" -ForegroundColor Green
}

# -----------------------------------------------------------------------
# 2. Update sitemap: point Claims Board at wrapper, drop Analytics subarea
# -----------------------------------------------------------------------
Write-Host "`nStep 2: PATCH sitemap (point Claims Board at wrapper, drop Analytics)" -ForegroundColor Cyan

$smId = "2191c458-1f4e-f111-bec6-000d3a5aed87"
$smxml = @"
<SiteMap IntroducedVersion="9.0.0.0">
  <Area Id="rma_operations_area" ShowGroups="true" Title="RMA Operations">
    <Group Id="rma_group_work" Title="Daily Work">
      <SubArea Id="rma_subarea_board" Url="`$webresource:$wrapperName" Title="Claims Board" />
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

Invoke-Dv -Method PATCH -Path "sitemaps($smId)" -Body @{ sitemapxml = $smxml } | Out-Null
Write-Host "  [ok] sitemap PATCHed" -ForegroundColor Green

# -----------------------------------------------------------------------
# 3. Try publish (best-effort)
# -----------------------------------------------------------------------
Write-Host "`nStep 3: Publish (best-effort)" -ForegroundColor Cyan
try {
    $publishXml = "<importexportxml><sitemaps><sitemap>$smId</sitemap></sitemaps><webresources><webresource>$wrapperId</webresource></webresources></importexportxml>"
    $body = @{ ParameterXml = $publishXml } | ConvertTo-Json -Compress
    $h = $hdrBase.Clone(); $h['Content-Type'] = 'application/json; charset=utf-8'
    Invoke-WebRequest -Uri "$OrgUrl/api/data/v9.2/PublishXml" -Method Post -Headers $h -Body $body -TimeoutSec 120 -ErrorAction Stop | Out-Null
    Write-Host "  [ok] published" -ForegroundColor Green
} catch {
    $m = $_.Exception.Message
    if ($_.ErrorDetails.Message) { $m = $_.ErrorDetails.Message }
    Write-Host "  [warn] publish: $m" -ForegroundColor DarkYellow
}

Write-Host "`n=== DONE ===" -ForegroundColor Cyan
Write-Host ""
Write-Host "Reload the app:" -ForegroundColor Yellow
Write-Host "  $OrgUrl/main.aspx?appid=8661f960-1f4e-f111-bec6-000d3a5aed87"
Write-Host ""
Write-Host "Claims Board should now render the kanban with your claims." -ForegroundColor Yellow
Write-Host ""
Write-Host "About the 'RMA Operations / Analytics' area at the top of your nav:" -ForegroundColor DarkGray
Write-Host "  That's the standard Dynamics dashboards area, not in your sitemap." -ForegroundColor DarkGray
Write-Host "  It can be hidden by setting Settings -> Personalization -> Hide ootb dashboards." -ForegroundColor DarkGray
Write-Host "  Or we can leave it — users will naturally use Claims Board as the home." -ForegroundColor DarkGray
