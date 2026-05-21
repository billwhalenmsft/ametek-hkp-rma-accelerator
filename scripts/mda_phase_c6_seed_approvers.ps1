<#
.SYNOPSIS
    Phase C6 — Seed 5 plant approver records (one per plant).

    Uses admin@D365DemoTSCE30330346.onmicrosoft.com as placeholder.
    Bill TODO: replace with real plant manager names + UPNs in v2.
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

# Fetch plants by name
$plants = (Invoke-Dv -Method GET -Path "rma_plants?`$select=rma_name,rma_plantid").value
Write-Host "Plants found:" $plants.Count -ForegroundColor Cyan

$admin = "admin@D365DemoTSCE30330346.onmicrosoft.com"

# Notify-when option enum: assume 100000000 = OnRequest. Pick first option.
$nwOpts = (Invoke-Dv -Method GET -Path "EntityDefinitions(LogicalName='rma_plantapprover')/Attributes(LogicalName='rma_notifywhen')/Microsoft.Dynamics.CRM.PicklistAttributeMetadata?`$expand=OptionSet").OptionSet.Options
$notifyVal = if ($nwOpts.Count -gt 0) { $nwOpts[0].Value } else { 100000000 }
$amOpts = (Invoke-Dv -Method GET -Path "EntityDefinitions(LogicalName='rma_plantapprover')/Attributes(LogicalName='rma_assignmentmode')/Microsoft.Dynamics.CRM.PicklistAttributeMetadata?`$expand=OptionSet").OptionSet.Options
$assignVal = if ($amOpts.Count -gt 0) { $amOpts[0].Value } else { 100000000 }

Write-Host "notifyWhen default: $notifyVal" -ForegroundColor DarkGray
Write-Host "assignmentMode default: $assignVal" -ForegroundColor DarkGray

foreach ($p in $plants) {
    # Check if approver already exists
    $existing = (Invoke-Dv -Method GET -Path ("rma_plantapprovers?`$filter=_rma_plant_value eq " + $p.rma_plantid + "&`$select=rma_plantapproverid")).value
    if ($existing.Count -gt 0) {
        Write-Host "  [skip] $($p.rma_name) already has approver" -ForegroundColor DarkGray
        continue
    }

    $body = @{
        "rma_name"               = "$($p.rma_name) Manager (placeholder)"
        "rma_Plant@odata.bind"   = "/rma_plants($($p.rma_plantid))"
        "rma_email"              = $admin
        "rma_teamsupn"           = $admin
        "rma_role"               = "Plant Manager"
        "rma_highvaluethreshold" = 10000
        "rma_isactive"           = $true
        "rma_notifywhen"         = $notifyVal
        "rma_assignmentmode"     = $assignVal
    }
    $resp = Invoke-Dv -Method POST -Path "rma_plantapprovers" -Body $body -ReturnHeaders
    $loc = $resp.Headers['OData-EntityId']
    if ($loc -is [array]) { $loc = $loc[0] }
    if ($loc -match '\(([0-9a-fA-F\-]{36})\)') { $id = $matches[1] }
    Write-Host "  [create] $($p.rma_name) -> $id" -ForegroundColor Green
}

Write-Host "`nDone." -ForegroundColor Cyan
Write-Host "Bill TODO: Replace placeholder name + email with real plant managers (rma_plantapprover form)." -ForegroundColor Yellow
