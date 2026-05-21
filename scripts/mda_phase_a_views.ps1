<#
.SYNOPSIS
    Phase A: Create 5 system saved views on rma_claim.

    Views:
      1. All Open RMAs        — anything not in 'Closed' status
      2. My Open RMAs         — open + owned by current user
      3. Closed RMAs          — status = Closed
      4. Needs Manager Approval — status = Decision and credit > 1000
      5. New This Week        — status = New + created in last 7 days

.NOTES
    Idempotent. Looks up by view name first.

    Status option values (rma_claim.rma_status):
      100000000 = New
      100000001 = Triage
      100000002 = Investigation
      100000003 = Decision
      100000004 = Closed
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
    param([string]$Method, [string]$Path, $Body = $null, [switch]$ReturnHeaders, [int]$MaxRetries = 5)
    $url = "$OrgUrl/api/data/v9.2/$Path"
    $h = $hdrBase.Clone()
    if ($Method -in @('PATCH','DELETE')) { $h['If-Match'] = '*' }
    if ($Body) { $h['Content-Type'] = 'application/json; charset=utf-8' }
    $params = @{ Uri = $url; Method = $Method; Headers = $h }
    if ($Body) {
        if ($Body -is [string]) { $params.Body = $Body }
        else { $params.Body = ($Body | ConvertTo-Json -Depth 30 -Compress) }
    }
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

# ---------------------------------------------------------------------------
# Layout XML used by all views — same column order, slightly different filters
# ---------------------------------------------------------------------------
$layoutXml = @'
<grid name="resultset" object="10000" jump="rma_claimnumber" select="1" preview="1" icon="1">
  <row name="result" id="rma_claimid">
    <cell name="rma_claimnumber" width="120" />
    <cell name="rma_customername" width="180" />
    <cell name="rma_partnumber" width="120" />
    <cell name="rma_status" width="100" />
    <cell name="rma_customerregion" width="120" />
    <cell name="rma_assignedplant" width="160" />
    <cell name="rma_warrantystatus" width="120" />
    <cell name="rma_creditamount" width="110" />
    <cell name="rma_createddate" width="120" />
  </row>
</grid>
'@

# ---------------------------------------------------------------------------
# View definitions
# ---------------------------------------------------------------------------
$views = @(
    @{
        Name        = "All Open RMAs"
        Description = "All RMA claims not yet closed."
        FetchXml    = @'
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
    <attribute name="rma_createddate" />
    <attribute name="rma_claimid" />
    <order attribute="rma_createddate" descending="true" />
    <filter type="and">
      <condition attribute="rma_status" operator="ne" value="100000004" />
    </filter>
  </entity>
</fetch>
'@
    },
    @{
        Name        = "My Open RMAs"
        Description = "Open RMAs owned by the current user."
        FetchXml    = @'
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
    <attribute name="rma_createddate" />
    <attribute name="rma_claimid" />
    <order attribute="rma_createddate" descending="true" />
    <filter type="and">
      <condition attribute="rma_status" operator="ne" value="100000004" />
      <condition attribute="ownerid" operator="eq-userid" />
    </filter>
  </entity>
</fetch>
'@
    },
    @{
        Name        = "Closed RMAs"
        Description = "All RMAs that have been resolved/closed."
        FetchXml    = @'
<fetch version="1.0" output-format="xml-platform" mapping="logical">
  <entity name="rma_claim">
    <attribute name="rma_claimnumber" />
    <attribute name="rma_customername" />
    <attribute name="rma_partnumber" />
    <attribute name="rma_status" />
    <attribute name="rma_resolution" />
    <attribute name="rma_assignedplant" />
    <attribute name="rma_creditamount" />
    <attribute name="rma_closeddate" />
    <attribute name="rma_claimid" />
    <order attribute="rma_closeddate" descending="true" />
    <filter type="and">
      <condition attribute="rma_status" operator="eq" value="100000004" />
    </filter>
  </entity>
</fetch>
'@
    },
    @{
        Name        = "Needs Manager Approval"
        Description = "Decision-stage RMAs with credit over $1,000."
        FetchXml    = @'
<fetch version="1.0" output-format="xml-platform" mapping="logical">
  <entity name="rma_claim">
    <attribute name="rma_claimnumber" />
    <attribute name="rma_customername" />
    <attribute name="rma_partnumber" />
    <attribute name="rma_status" />
    <attribute name="rma_assignedplant" />
    <attribute name="rma_creditamount" />
    <attribute name="rma_createddate" />
    <attribute name="rma_claimid" />
    <order attribute="rma_creditamount" descending="true" />
    <filter type="and">
      <condition attribute="rma_status" operator="eq" value="100000003" />
      <condition attribute="rma_creditamount" operator="gt" value="1000" />
    </filter>
  </entity>
</fetch>
'@
    },
    @{
        Name        = "New This Week"
        Description = "New RMAs created in the past 7 days."
        FetchXml    = @'
<fetch version="1.0" output-format="xml-platform" mapping="logical">
  <entity name="rma_claim">
    <attribute name="rma_claimnumber" />
    <attribute name="rma_customername" />
    <attribute name="rma_partnumber" />
    <attribute name="rma_status" />
    <attribute name="rma_customerregion" />
    <attribute name="rma_warrantystatus" />
    <attribute name="rma_createddate" />
    <attribute name="rma_claimid" />
    <order attribute="rma_createddate" descending="true" />
    <filter type="and">
      <condition attribute="rma_status" operator="eq" value="100000000" />
      <condition attribute="rma_createddate" operator="last-x-days" value="7" />
    </filter>
  </entity>
</fetch>
'@
    }
)

Write-Host "`n=== Phase A: Saved views on rma_claim ===`n" -ForegroundColor Cyan

# Get entity metadata id + objecttypecode (for layout @object)
$em = Invoke-Dv -Method GET -Path "EntityDefinitions(LogicalName='rma_claim')?`$select=LogicalName,ObjectTypeCode,MetadataId"
Write-Host "rma_claim ObjectTypeCode: $($em.ObjectTypeCode)`n" -ForegroundColor DarkGray

# Update layoutXml with correct object code
$correctedLayout = $layoutXml -replace 'object="10000"', "object=`"$($em.ObjectTypeCode)`""

foreach ($v in $views) {
    $nameEsc = $v.Name -replace "'", "''"
    $existing = (Invoke-Dv -Method GET -Path "savedqueries?`$filter=name eq '$nameEsc' and returnedtypecode eq 'rma_claim'&`$select=savedqueryid").value
    if ($existing.Count -gt 0) {
        $id = $existing[0].savedqueryid
        Write-Host "  [skip] '$($v.Name)' exists -> $id  (updating fetchxml)" -ForegroundColor DarkGray
        $patch = @{
            name        = $v.Name
            description = $v.Description
            fetchxml    = $v.FetchXml
            layoutxml   = $correctedLayout
        }
        Invoke-Dv -Method PATCH -Path "savedqueries($id)" -Body $patch | Out-Null
        continue
    }
    $body = @{
        name              = $v.Name
        description       = $v.Description
        returnedtypecode  = "rma_claim"
        querytype         = 0       # 0 = Main application view (shows in view picker)
        fetchxml          = $v.FetchXml
        layoutxml         = $correctedLayout
        isdefault         = $false
    }
    try {
        $resp = Invoke-Dv -Method POST -Path "savedqueries" -Body $body -ReturnHeaders
        $loc = $resp.Headers['OData-EntityId']
        if ($loc -is [array]) { $loc = $loc[0] }
        if ($loc -match '\(([0-9a-fA-F\-]{36})\)') { $id = $matches[1] }
        Write-Host "  [create] '$($v.Name)' -> $id" -ForegroundColor Green
    } catch {
        Write-Host "  [FAIL] $($v.Name): $($_.Exception.Message)" -ForegroundColor Red
    }
}

# ---------------------------------------------------------------------------
# Publish savedqueries (this is the one that historically completes fast)
# ---------------------------------------------------------------------------
Write-Host "`nPublishing rma_claim entity..." -ForegroundColor Cyan
try {
    $publishXml = "<importexportxml><entities><entity>rma_claim</entity></entities></importexportxml>"
    $body = @{ ParameterXml = $publishXml } | ConvertTo-Json -Compress
    $h = $hdrBase.Clone()
    $h['Content-Type'] = 'application/json; charset=utf-8'
    Invoke-WebRequest -Uri "$OrgUrl/api/data/v9.2/PublishXml" -Method Post -Headers $h -Body $body -TimeoutSec 60 -ErrorAction Stop | Out-Null
    Write-Host "  [ok] publish" -ForegroundColor Green
} catch {
    $m = $_.Exception.Message
    if ($_.ErrorDetails.Message) { $m = $_.ErrorDetails.Message }
    Write-Host "  [warn] publish: $m" -ForegroundColor DarkYellow
    Write-Host "  Views still persisted — they'll show after next publish or after a few minutes." -ForegroundColor DarkGray
}

Write-Host "`n=== DONE — 5 views on rma_claim ===" -ForegroundColor Cyan
Write-Host "Open the app and you should see the new views in the RMA Claims view picker." -ForegroundColor Yellow
Write-Host "App URL: $OrgUrl/main.aspx?appid=8661f960-1f4e-f111-bec6-000d3a5aed87" -ForegroundColor Yellow
