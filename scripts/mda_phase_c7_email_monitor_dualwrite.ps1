<#
.SYNOPSIS
    Phase C7 — Patch RMA Email Monitor flow to dual-write to rma_emaillog.

    Adds a new "Add_to_rma_emaillog" action after Parse_RMA_Fields that creates
    a Dataverse rma_emaillog record (Inbound, Unprocessed) using values from
    the trigger + extracted JSON. SharePoint write is preserved as a backup.

    The flow keeps the SharePoint backup intact (per Bill's "don't delete the
    SharePoint dual-write" instruction).

    Flow ID: 6d9fc9b0-5e4d-f111-bec6-000d3a5aed87
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
}
$flowId = "6d9fc9b0-5e4d-f111-bec6-000d3a5aed87"

function Invoke-Dv {
    param([string]$Method, [string]$Path, $Body = $null)
    $url = "$OrgUrl/api/data/v9.2/$Path"
    $h = $hdrBase.Clone()
    if ($Method -in @('PATCH','DELETE')) { $h['If-Match'] = '*' }
    if ($Body) { $h['Content-Type'] = 'application/json; charset=utf-8' }
    $params = @{ Uri = $url; Method = $Method; Headers = $h }
    if ($Body) { $params.Body = if ($Body -is [string]) { $Body } else { ($Body | ConvertTo-Json -Depth 50 -Compress) } }
    return Invoke-RestMethod @params
}

# Fetch current flow definition
$flow = Invoke-Dv -Method GET -Path "workflows($flowId)?`$select=clientdata,name,statecode"
$clientData = $flow.clientdata | ConvertFrom-Json -Depth 50

# Check if already patched
if ($clientData.properties.definition.actions.PSObject.Properties.Name -contains "Add_to_rma_emaillog") {
    Write-Host "  [skip] flow already has Add_to_rma_emaillog action" -ForegroundColor DarkYellow
    return
}

# Build a new action: create rma_emaillog
# Uses the same shared_commondataserviceforapps connection already in the flow
$newAction = [PSCustomObject]@{
    runAfter = [PSCustomObject]@{
        Parse_RMA_Fields = @("Succeeded")
    }
    metadata = [PSCustomObject]@{
        operationMetadataId = [Guid]::NewGuid().ToString()
    }
    type = "OpenApiConnection"
    inputs = [PSCustomObject]@{
        parameters = [PSCustomObject]@{
            entityName             = "rma_emaillogs"
            "item/rma_subject"     = "@triggerOutputs()?['body/subject']"
            "item/rma_fromaddress" = "@triggerOutputs()?['body/from']"
            "item/rma_recipient"   = "@triggerOutputs()?['body/toRecipients']"
            "item/rma_receiveddate"= "@triggerOutputs()?['body/receivedDateTime']"
            "item/rma_sentdate"    = "@triggerOutputs()?['body/receivedDateTime']"
            "item/rma_bodypreview" = "@if(greater(length(coalesce(triggerOutputs()?['body/bodyPreview'],'')), 4000), substring(triggerOutputs()?['body/bodyPreview'], 0, 4000), coalesce(triggerOutputs()?['body/bodyPreview'],''))"
            "item/rma_body"        = "@coalesce(triggerOutputs()?['body/body'],'')"
            "item/rma_messageid"   = "@triggerOutputs()?['body/id']"
            "item/rma_direction"   = 100000000   # Inbound
            "item/rma_isprocessed" = $false
            "item/rma_sentby"      = "@coalesce(triggerOutputs()?['body/from'],'')"
        }
        host = [PSCustomObject]@{
            apiId           = "/providers/Microsoft.PowerApps/apis/shared_commondataserviceforapps"
            connectionName  = "shared_commondataserviceforapps"
            operationId     = "CreateRecord"
        }
        authentication = "@parameters('`$authentication')"
    }
}

# Make sure SharePoint Create_item runs after rma_emaillog (so the rma write
# is guaranteed first). Keep parallel branches: both run after Parse_RMA_Fields.
# We keep Create_item runAfter Parse_RMA_Fields too — no change needed.

# Inject new action
$clientData.properties.definition.actions | Add-Member -MemberType NoteProperty -Name "Add_to_rma_emaillog" -Value $newAction

$newClientData = $clientData | ConvertTo-Json -Depth 50 -Compress

# Save snapshot
$snap = "C:\Users\billwhalen\OneDrive - Microsoft\Documents\GitHub\RAPP\CommunityRAPP-main\customers\ametek\hkp_rma\d365\rma_email_monitor_clientdata_patched.json"
$newClientData | Out-File -Encoding UTF8 $snap
Write-Host "  [saved] snapshot -> $snap" -ForegroundColor DarkGray

# Important: deactivate flow before patching, then reactivate
Write-Host "  [step 1] deactivating flow..." -ForegroundColor Cyan
Invoke-Dv -Method PATCH -Path "workflows($flowId)" -Body @{ statecode = 0; statuscode = 1 } | Out-Null
Start-Sleep -Seconds 2

Write-Host "  [step 2] patching clientdata..." -ForegroundColor Cyan
try {
    Invoke-Dv -Method PATCH -Path "workflows($flowId)" -Body @{ clientdata = $newClientData } | Out-Null
    Write-Host "    [ok] clientdata updated" -ForegroundColor Green
} catch {
    Write-Host "    [error] $($_.Exception.Message)" -ForegroundColor Red
    if ($_.ErrorDetails.Message) { Write-Host "    detail: $($_.ErrorDetails.Message)" -ForegroundColor Red }
    # Try to reactivate anyway
}

Write-Host "  [step 3] reactivating flow..." -ForegroundColor Cyan
try {
    Invoke-Dv -Method PATCH -Path "workflows($flowId)" -Body @{ statecode = 1; statuscode = 2 } | Out-Null
    Write-Host "    [ok] flow reactivated" -ForegroundColor Green
} catch {
    Write-Host "    [warn] $($_.Exception.Message)" -ForegroundColor DarkYellow
    Write-Host "    Bill TODO: open flow in PA UI and turn on manually" -ForegroundColor Yellow
}

Write-Host "`nDone." -ForegroundColor Cyan
