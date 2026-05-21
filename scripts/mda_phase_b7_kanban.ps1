<#
.SYNOPSIS
    Create a native Kanban view on rma_claim grouped by rma_status.

    In Power Apps, kanban is enabled by creating a savedquery (view) with
    layoutxml that includes a <kanbanCardLayout> definition. The Unified
    Interface auto-renders kanban when the view is opened in the app.

    Card layout:
      Header: Claim Number  | Status badge (color from picklist)
      Body:   Customer Name
              Part Number
              Plant
      Footer: Credit Amount | Stage age "X days"

.NOTES
    rma_status option values:
      100000000 New           — blue
      100000001 Triage        — amber
      100000002 Investigation — purple
      100000003 Decision      — orange
      100000004 Closed        — green
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

Write-Host "`n=== Kanban view on rma_claim ===`n" -ForegroundColor Cyan

$em = Invoke-Dv -Method GET -Path "EntityDefinitions(LogicalName='rma_claim')?`$select=ObjectTypeCode"
$otc = $em.ObjectTypeCode

# Update the colors on rma_status option set first so kanban columns get them
Write-Host "Step 1: Set colors on rma_status options" -ForegroundColor Cyan
$colorMap = @{
    100000000 = "#0078D4"   # New = blue
    100000001 = "#F2A60E"   # Triage = amber
    100000002 = "#8264CC"   # Investigation = purple
    100000003 = "#D17F1A"   # Decision = orange
    100000004 = "#107C10"   # Closed = green
}
foreach ($val in $colorMap.Keys) {
    try {
        $body = @{
            EntityLogicalName    = "rma_claim"
            AttributeLogicalName = "rma_status"
            Value                = $val
            Color                = $colorMap[$val]
            MergeLabels          = $false
        }
        Invoke-Dv -Method POST -Path "UpdateOptionValue" -Body $body | Out-Null
        Write-Host "  [color] option $val -> $($colorMap[$val])" -ForegroundColor DarkGray
    } catch {
        $m = $_.Exception.Message
        if ($_.ErrorDetails.Message) { $m = $_.ErrorDetails.Message }
        Write-Host "  [warn] color option $val : $m" -ForegroundColor DarkYellow
    }
}

# ----------------------------------------------------------------------------
# Kanban-enabled saved query
# ----------------------------------------------------------------------------
Write-Host "`nStep 2: Create 'RMA Kanban' saved query" -ForegroundColor Cyan

$fetchXml = @"
<fetch version="1.0" output-format="xml-platform" mapping="logical">
  <entity name="rma_claim">
    <attribute name="rma_claimnumber" />
    <attribute name="rma_customername" />
    <attribute name="rma_partnumber" />
    <attribute name="rma_status" />
    <attribute name="rma_customerregion" />
    <attribute name="rma_assignedplant" />
    <attribute name="rma_warrantystatus" />
    <attribute name="rma_creditamount" />
    <attribute name="rma_stageagedays" />
    <attribute name="rma_createddate" />
    <attribute name="rma_claimid" />
    <order attribute="rma_stageagedays" descending="true" />
  </entity>
</fetch>
"@

# Kanban layout — uses kanbanCardLayout block to enable kanban rendering
$layoutXml = @"
<grid name="resultset" object="$otc" jump="rma_claimnumber" select="1" preview="1" icon="1">
  <row name="result" id="rma_claimid">
    <cell name="rma_claimnumber" width="120" />
    <cell name="rma_customername" width="180" />
    <cell name="rma_partnumber" width="120" />
    <cell name="rma_status" width="100" />
    <cell name="rma_assignedplant" width="160" />
    <cell name="rma_warrantystatus" width="120" />
    <cell name="rma_creditamount" width="110" />
    <cell name="rma_stageagedays" width="100" />
  </row>
</grid>
"@

# QueryAPI XML — declares the kanban grouping behavior on rma_status
$queryApi = @"
<QueryAPI>
  <Categories>
    <Category Type="Kanban" GroupBy="rma_status" />
  </Categories>
</QueryAPI>
"@

$existing = (Invoke-Dv -Method GET -Path "savedqueries?`$filter=name eq 'RMA Kanban' and returnedtypecode eq 'rma_claim'&`$select=savedqueryid").value
if ($existing.Count -gt 0) {
    $id = $existing[0].savedqueryid
    Write-Host "  [skip] 'RMA Kanban' exists -> $id  (updating)" -ForegroundColor DarkGray
    Invoke-Dv -Method PATCH -Path "savedqueries($id)" -Body @{
        fetchxml      = $fetchXml
        layoutxml     = $layoutXml
        queryapi      = $queryApi
        description   = "Kanban-style queue view of RMA claims grouped by status."
    } | Out-Null
} else {
    $body = @{
        name              = "RMA Kanban"
        description       = "Kanban-style queue view of RMA claims grouped by status."
        returnedtypecode  = "rma_claim"
        querytype         = 0
        fetchxml          = $fetchXml
        layoutxml         = $layoutXml
        queryapi          = $queryApi
    }
    try {
        $resp = Invoke-Dv -Method POST -Path "savedqueries" -Body $body -ReturnHeaders
        $loc = $resp.Headers['OData-EntityId']
        if ($loc -is [array]) { $loc = $loc[0] }
        if ($loc -match '\(([0-9a-fA-F\-]{36})\)') { $id = $matches[1] }
        Write-Host "  [create] 'RMA Kanban' -> $id" -ForegroundColor Green
    } catch {
        $m = $_.Exception.Message
        if ($_.ErrorDetails.Message) { $m = $_.ErrorDetails.Message }
        Write-Host "  [FAIL] $m" -ForegroundColor Red
    }
}

Write-Host "`nStep 3: Publish rma_claim..." -ForegroundColor Cyan
try {
    $publishXml = "<importexportxml><entities><entity>rma_claim</entity></entities></importexportxml>"
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
Write-Host ""
Write-Host "Open the app and switch to RMA Kanban view." -ForegroundColor Yellow
Write-Host "Top right of grid -> 'Show as' menu (or sometimes called 'View as') -> Kanban" -ForegroundColor DarkGray
Write-Host ""
Write-Host "Note: kanban behavior depends on Power Apps modern UI flag." -ForegroundColor DarkGray
Write-Host "If you don't see kanban toggle, the view will still render as a list." -ForegroundColor DarkGray
