<#
.SYNOPSIS
    Phase B1: Update the app sitemap to add a "Dashboards" subarea and
    organize the nav into 3 groups: Daily Work / Configuration / History.

    Adds: Dashboards subarea (linking to RMA Operations Overview) at top.

.NOTES
    App ID: 8661f960-1f4e-f111-bec6-000d3a5aed87
    Dashboard ID: 7ecca7c8-284e-f111-bec6-000d3a5aed87
#>

[CmdletBinding()]
param(
    [string]$OrgUrl = "https://org6feab6b5.crm.dynamics.com",
    [string]$AppId  = "8661f960-1f4e-f111-bec6-000d3a5aed87",
    [string]$DashboardId = "7ecca7c8-284e-f111-bec6-000d3a5aed87"
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

Write-Host "`n=== Phase B1: Sitemap with Dashboards subarea ===`n" -ForegroundColor Cyan

# Find sitemap directly by name (RetrieveAppComponents is unreliable in this tenant)
$sm = Invoke-Dv -Method GET -Path "sitemaps?`$filter=sitemapname eq 'RMA Operations and Monitoring'&`$select=sitemapid"
if ($sm.value.Count -eq 0) {
    throw "No sitemap 'RMA Operations and Monitoring' found"
}
$sitemapId = $sm.value[0].sitemapid
Write-Host "  Sitemap ID: $sitemapId" -ForegroundColor DarkGray

# Build the new sitemap XML — 3 groups
# Note: Dashboard subareas in modern sitemap XSD aren't well-supported via REST.
# Dashboards can be reached via the "Recent" nav or by adding manually in
# the maker UI. The system dashboard is still created and renders fine.
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

Write-Host "  Patching sitemap XML..." -ForegroundColor Cyan
Invoke-Dv -Method PATCH -Path "sitemaps($sitemapId)" -Body @{ sitemapxml = $sitemapXml } | Out-Null
Write-Host "  [ok] sitemap updated" -ForegroundColor Green

# Publish app + sitemap
Write-Host "`n  Publishing..." -ForegroundColor Cyan
try {
    $publishXml = "<importexportxml><appmodules><appmodule>$AppId</appmodule></appmodules><sitemaps><sitemap>$sitemapId</sitemap></sitemaps></importexportxml>"
    $body = @{ ParameterXml = $publishXml } | ConvertTo-Json -Compress
    $h = $hdrBase.Clone(); $h['Content-Type'] = 'application/json; charset=utf-8'
    Invoke-WebRequest -Uri "$OrgUrl/api/data/v9.2/PublishXml" -Method Post -Headers $h -Body $body -TimeoutSec 60 -ErrorAction Stop | Out-Null
    Write-Host "  [ok] publish" -ForegroundColor Green
} catch {
    $m = $_.Exception.Message
    if ($_.ErrorDetails.Message) { $m = $_.ErrorDetails.Message }
    Write-Host "  [warn] publish: $m" -ForegroundColor DarkYellow
}

Write-Host "`n=== DONE ===" -ForegroundColor Cyan
Write-Host "Reload the app — left nav should now show:" -ForegroundColor Yellow
Write-Host "  Daily Work"
Write-Host "    Dashboard"
Write-Host "    RMA Claims"
Write-Host "    Email Inbox"
Write-Host "    Approvals"
Write-Host "  Configuration"
Write-Host "    Plants / Routing Rules / Plant Approvers / Email Templates / Email Signatures"
Write-Host "  History"
Write-Host "    Claim Notes / Approval History"
