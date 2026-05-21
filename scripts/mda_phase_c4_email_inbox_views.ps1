<#
.SYNOPSIS
    Phase C4 — Email Inbox saved views on rma_emaillog.

    Creates 3 system views:
      - Inbound — Unprocessed   (DEFAULT, replaces "Active Email Logs")
      - Inbound — Processed
      - All Outbound

    Direction picklist values (rma_direction):
      100000000 = Inbound
      100000001 = Outbound
    (Verified via OptionSet metadata below.)
#>
[CmdletBinding()]
param([string]$OrgUrl = "https://org6feab6b5.crm.dynamics.com")
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
    if ($Body) { $params.Body = if ($Body -is [string]) { $Body } else { ($Body | ConvertTo-Json -Depth 30 -Compress) } }
    if ($ReturnHeaders) { return Invoke-WebRequest @params }
    return Invoke-RestMethod @params
}

# Verify direction option values
$opts = Invoke-Dv -Method GET -Path "EntityDefinitions(LogicalName='rma_emaillog')/Attributes(LogicalName='rma_direction')/Microsoft.Dynamics.CRM.PicklistAttributeMetadata?`$expand=OptionSet"
Write-Host "rma_direction option values:" -ForegroundColor Cyan
$opts.OptionSet.Options | ForEach-Object { Write-Host "  $($_.Value) = $($_.Label.UserLocalizedLabel.Label)" }
Write-Host ""

# Common columns layout
$cols = @"
<grid name='resultset' object='12724' jump='rma_subject' select='1' icon='1' preview='1'>
<row name='result' id='rma_emaillogid'>
<cell name='rma_subject' width='300' />
<cell name='rma_fromaddress' width='200' />
<cell name='rma_receiveddate' width='130' />
<cell name='rma_bodypreview' width='320' />
<cell name='rma_isprocessed' width='100' />
<cell name='rma_claim' width='180' />
</row>
</grid>
"@

# Outbound has different relevant columns
$outboundCols = @"
<grid name='resultset' object='12724' jump='rma_subject' select='1' icon='1' preview='1'>
<row name='result' id='rma_emaillogid'>
<cell name='rma_subject' width='300' />
<cell name='rma_recipient' width='220' />
<cell name='rma_sentdate' width='130' />
<cell name='rma_templateused' width='180' />
<cell name='rma_claim' width='180' />
<cell name='rma_sentby' width='180' />
</row>
</grid>
"@

# View 1: Inbound — Unprocessed (becomes default by setting isdefault=true)
$fetch_inboundUnprocessed = @"
<fetch version='1.0' output-format='xml-platform' mapping='logical' distinct='false'>
<entity name='rma_emaillog'>
<attribute name='rma_emaillogid' />
<attribute name='rma_subject' />
<attribute name='rma_fromaddress' />
<attribute name='rma_receiveddate' />
<attribute name='rma_bodypreview' />
<attribute name='rma_isprocessed' />
<attribute name='rma_claim' />
<order attribute='rma_receiveddate' descending='true' />
<filter type='and'>
<condition attribute='rma_direction' operator='eq' value='100000000' />
<condition attribute='rma_isprocessed' operator='eq' value='0' />
</filter>
</entity>
</fetch>
"@

# View 2: Inbound — Processed
$fetch_inboundProcessed = @"
<fetch version='1.0' output-format='xml-platform' mapping='logical' distinct='false'>
<entity name='rma_emaillog'>
<attribute name='rma_emaillogid' />
<attribute name='rma_subject' />
<attribute name='rma_fromaddress' />
<attribute name='rma_receiveddate' />
<attribute name='rma_bodypreview' />
<attribute name='rma_isprocessed' />
<attribute name='rma_claim' />
<order attribute='rma_receiveddate' descending='true' />
<filter type='and'>
<condition attribute='rma_direction' operator='eq' value='100000000' />
<condition attribute='rma_isprocessed' operator='eq' value='1' />
</filter>
</entity>
</fetch>
"@

# View 3: All Outbound
$fetch_outbound = @"
<fetch version='1.0' output-format='xml-platform' mapping='logical' distinct='false'>
<entity name='rma_emaillog'>
<attribute name='rma_emaillogid' />
<attribute name='rma_subject' />
<attribute name='rma_recipient' />
<attribute name='rma_sentdate' />
<attribute name='rma_templateused' />
<attribute name='rma_claim' />
<attribute name='rma_sentby' />
<order attribute='rma_sentdate' descending='true' />
<filter type='and'>
<condition attribute='rma_direction' operator='eq' value='100000001' />
</filter>
</entity>
</fetch>
"@

function Upsert-View {
    param([string]$Name, [string]$Fetch, [string]$Layout, [bool]$MakeDefault = $false)

    $existing = (Invoke-Dv -Method GET -Path "savedqueries?`$filter=name eq '$Name' and returnedtypecode eq 'rma_emaillog'&`$select=savedqueryid,querytype,isdefault").value
    $body = @{
        name             = $Name
        returnedtypecode = "rma_emaillog"
        querytype        = 0
        fetchxml         = $Fetch
        layoutxml        = $Layout
        isdefault        = $MakeDefault
        statecode        = 0
        statuscode       = 1
    }
    if ($existing.Count -gt 0) {
        $id = $existing[0].savedqueryid
        Write-Host "  [update] $Name -> $id" -ForegroundColor DarkGray
        Invoke-Dv -Method PATCH -Path "savedqueries($id)" -Body $body | Out-Null
        return $id
    } else {
        Write-Host "  [create] $Name" -ForegroundColor Green
        $resp = Invoke-Dv -Method POST -Path "savedqueries" -Body $body -ReturnHeaders
        $loc = $resp.Headers['OData-EntityId']
        if ($loc -is [array]) { $loc = $loc[0] }
        if ($loc -match '\(([0-9a-fA-F\-]{36})\)') { return $matches[1] }
    }
}

Write-Host "Creating email inbox views..." -ForegroundColor Cyan
$id1 = Upsert-View -Name "Inbound — Unprocessed" -Fetch $fetch_inboundUnprocessed -Layout $cols -MakeDefault $true
$id2 = Upsert-View -Name "Inbound — Processed"  -Fetch $fetch_inboundProcessed   -Layout $cols  -MakeDefault $false
$id3 = Upsert-View -Name "All Outbound"          -Fetch $fetch_outbound           -Layout $outboundCols -MakeDefault $false

# Clear isdefault on the old "Active Email Logs" view so our Inbound view is the primary
$old = (Invoke-Dv -Method GET -Path "savedqueries?`$filter=name eq 'Active Email Logs' and returnedtypecode eq 'rma_emaillog'&`$select=savedqueryid,isdefault").value
if ($old.Count -gt 0 -and $old[0].isdefault) {
    Write-Host "  [clear] removing default from 'Active Email Logs'" -ForegroundColor DarkYellow
    Invoke-Dv -Method PATCH -Path "savedqueries($($old[0].savedqueryid))" -Body @{ isdefault = $false } | Out-Null
}

Write-Host "`nDone." -ForegroundColor Cyan
Write-Host "  Inbound Unprocessed: $id1"
Write-Host "  Inbound Processed:   $id2"
Write-Host "  All Outbound:        $id3"
