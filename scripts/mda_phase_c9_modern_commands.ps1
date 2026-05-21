# mda_phase_c9_modern_commands.ps1
#
# Wire 7 modern command buttons (6 on rma_claim form + 1 on rma_emaillog form)
# that invoke the HKPCommands JS handlers in hkp_rma_form_commands.js.
#
# Modern command bar architecture stores button defs in the 'appaction' Dataverse
# entity (NOT the legacy ribbondiffxml). Each appaction record describes:
#   - name + uniquename (must be unique across the org)
#   - location: 0=Form, 1=HomepageGrid
#   - context: 1=Entity (singular form)
#   - contextvalue: entity logical name
#   - _contextentity_value: entity metadata GUID (NOT objecttypecode)
#   - onclickeventtype: 2=JavaScript
#   - _onclickeventjavascriptwebresourceid_value: webresource GUID
#   - onclickeventjavascriptfunctionname: namespaced function (e.g. HKPCommands.resolveCredit)
#   - onclickeventjavascriptparameters: JSON array of CrmParameter (type 2 = PrimaryControl)
#   - visibilitytype: 0=always visible
#   - fonticon: icon name (Fluent UI icon set)
#   - buttonlabeltext, buttontooltiptitle, buttontooltipdescription
#   - sequence: float, lower = leftmost
#   - _appmoduleid_value: scope to the RMA app (optional but recommended)
#
# After creating records we call pac solution publish to make them appear in UI.

[CmdletBinding()]
param(
    [string] $OrgUrl = "https://org6feab6b5.crm.dynamics.com",
    [string] $SolutionUniqueName = "RMAReturnsMonitor"
)

$ErrorActionPreference = "Stop"

# --- Constants discovered in prep -----------------------------------------------
$rmaClaimMetadataId    = "4060a9e5-1a4a-f111-bec6-7ced8d6e623f"
$rmaEmailLogMetadataId = "6c664fda-384a-f111-bec6-7ced8d6e623f"
$jsWebResourceId       = "a0a128d8-d44e-f111-bec6-000d3a5aed87"   # rma_/scripts/hkp_rma_form_commands.js
$appModuleId           = "8661f960-1f4e-f111-bec6-000d3a5aed87"   # RMA Operations and Monitoring
$publisherPrefix       = "bw"

# --- Get auth token ------------------------------------------------------------
Write-Host "Getting auth token..." -ForegroundColor DarkGray
$token = az account get-access-token --resource $OrgUrl --query accessToken -o tsv
if (-not $token) { throw "Failed to get access token. Run 'az login' first." }

$hdr = @{
    Authorization           = "Bearer $token"
    Accept                  = "application/json"
    "Content-Type"          = "application/json; charset=utf-8"
    "OData-MaxVersion"      = "4.0"
    "OData-Version"         = "4.0"
    "MSCRM.SolutionUniqueName" = $SolutionUniqueName
}

# --- Button definitions --------------------------------------------------------
# PrimaryControl parameter shape: [{"type":2,"value":null}]
$primaryControlParam = '[{"type":2,"value":null}]'

$buttons = @(
    # rma_claim form
    @{
        ShortName      = "ResolveCredit"
        Entity         = "rma_claim"
        EntityMetaId   = $rmaClaimMetadataId
        FuncName       = "HKPCommands.resolveCredit"
        Label          = "Resolve - Credit Issued"
        TooltipTitle   = "Resolve with Credit"
        TooltipDesc    = "Mark this claim resolved with a credit. Above-threshold credits will trigger approval."
        Icon           = "Money"
        Sequence       = 100100010
    },
    @{
        ShortName      = "ResolveReplacement"
        Entity         = "rma_claim"
        EntityMetaId   = $rmaClaimMetadataId
        FuncName       = "HKPCommands.resolveReplacement"
        Label          = "Resolve - Replacement Sent"
        TooltipTitle   = "Resolve with Replacement"
        TooltipDesc    = "Mark this claim resolved with a replacement part sent to the customer."
        Icon           = "Sync"
        Sequence       = 100100020
    },
    @{
        ShortName      = "ResolveRepair"
        Entity         = "rma_claim"
        EntityMetaId   = $rmaClaimMetadataId
        FuncName       = "HKPCommands.resolveRepair"
        Label          = "Resolve - Repair Completed"
        TooltipTitle   = "Resolve with Repair"
        TooltipDesc    = "Mark this claim resolved after repair completed."
        Icon           = "Repair"
        Sequence       = 100100030
    },
    @{
        ShortName      = "DenyClaim"
        Entity         = "rma_claim"
        EntityMetaId   = $rmaClaimMetadataId
        FuncName       = "HKPCommands.denyClaim"
        Label          = "Deny Claim"
        TooltipTitle   = "Deny Claim"
        TooltipDesc    = "Deny this RMA claim with reason."
        Icon           = "Blocked"
        Sequence       = 100100040
    },
    @{
        ShortName      = "SendCustomerEmail"
        Entity         = "rma_claim"
        EntityMetaId   = $rmaClaimMetadataId
        FuncName       = "HKPCommands.sendCustomerEmail"
        Label          = "Send Customer Email"
        TooltipTitle   = "Send Email"
        TooltipDesc    = "Compose and send an outbound email to the customer about this claim."
        Icon           = "Mail"
        Sequence       = 100100050
    },
    @{
        ShortName      = "RequestApproval"
        Entity         = "rma_claim"
        EntityMetaId   = $rmaClaimMetadataId
        FuncName       = "HKPCommands.requestManagerApproval"
        Label          = "Request Manager Approval"
        TooltipTitle   = "Request Approval"
        TooltipDesc    = "Send an approval request to plant managers."
        Icon           = "RoutingRule"
        Sequence       = 100100060
    },
    # rma_emaillog form
    @{
        ShortName      = "CreateClaimFromEmail"
        Entity         = "rma_emaillog"
        EntityMetaId   = $rmaEmailLogMetadataId
        FuncName       = "HKPCommands.createClaimFromEmail"
        Label          = "Create RMA Claim from Email"
        TooltipTitle   = "Create Claim"
        TooltipDesc    = "Create a new RMA claim prefilled from this inbound email's extracted fields."
        Icon           = "NewMail"
        Sequence       = 100100010
    }
)

# --- Create each button ---------------------------------------------------------
$results = @()
foreach ($b in $buttons) {
    $entity        = $b.Entity
    $shortName     = $b.ShortName
    $name          = "Mscrm.Form.$entity.$shortName"
    # uniquename must be globally unique. Pattern matches existing custom commands.
    $uniqueName    = "$($publisherPrefix)__Mscrm.Form.$entity.$shortName!$entity!0"
    $componentIdUq = [Guid]::NewGuid().ToString()

    $body = @{
        name                                                   = $name
        uniquename                                             = $uniqueName
        componentidunique                                      = $componentIdUq
        buttonlabeltext                                        = $b.Label
        buttontooltiptitle                                     = $b.TooltipTitle
        buttontooltipdescription                               = $b.TooltipDesc
        buttonaccessibilitytext                                = $b.Label
        fonticon                                               = $b.Icon
        sequence                                               = [double]$b.Sequence
        buttonsequencepriority                                 = [double]$b.Sequence
        location                                               = 0     # Form
        context                                                = 1     # Entity
        contextvalue                                           = $entity
        type                                                   = 0
        visibilitytype                                         = 0     # Always visible
        hidden                                                 = $false
        isdisabled                                             = $false
        # JS event
        onclickeventtype                                       = 2     # JavaScript
        onclickeventjavascriptfunctionname                     = $b.FuncName
        onclickeventjavascriptparameters                       = $primaryControlParam
        # Navigation property bindings (PascalCase names from EntityDefinitions metadata)
        "ContextEntity@odata.bind"                             = "/entities($($b.EntityMetaId))"
        "OnClickEventJavaScriptWebResourceId@odata.bind"       = "/webresourceset($jsWebResourceId)"
        "AppModuleId@odata.bind"                               = "/appmodules($appModuleId)"
    }

    $json = $body | ConvertTo-Json -Depth 6 -Compress

    Write-Host ""
    Write-Host "[$entity] Creating button: $($b.Label)" -ForegroundColor Cyan
    Write-Host "  name=$name" -ForegroundColor DarkGray
    Write-Host "  uniquename=$uniqueName" -ForegroundColor DarkGray

    try {
        $resp = Invoke-WebRequest -Method POST `
            -Uri "$OrgUrl/api/data/v9.2/appactions" `
            -Headers $hdr `
            -Body $json `
            -UseBasicParsing
        $location = $resp.Headers.'OData-EntityId'
        if ($location -is [array]) { $location = $location[0] }
        $newId = ($location -split '\(')[1] -replace '\)$',''
        Write-Host "  CREATED: $newId" -ForegroundColor Green
        $results += [PSCustomObject]@{
            Entity   = $entity
            Label    = $b.Label
            FuncName = $b.FuncName
            Status   = "CREATED"
            Id       = $newId
            Error    = $null
        }
    } catch {
        $errMsg = $_.Exception.Message
        $errBody = $null
        if ($_.ErrorDetails -and $_.ErrorDetails.Message) {
            $errBody = $_.ErrorDetails.Message
        }
        Write-Host "  FAILED: $errMsg" -ForegroundColor Red
        if ($errBody) { Write-Host "    Body: $errBody" -ForegroundColor DarkRed }
        $results += [PSCustomObject]@{
            Entity   = $entity
            Label    = $b.Label
            FuncName = $b.FuncName
            Status   = "FAILED"
            Id       = $null
            Error    = if ($errBody) { $errBody } else { $errMsg }
        }
    }
}

# --- Summary -------------------------------------------------------------------
Write-Host ""
Write-Host "=== Summary ===" -ForegroundColor Cyan
$results | Format-Table Entity, Label, Status, Id -AutoSize

$created = ($results | Where-Object { $_.Status -eq "CREATED" }).Count
$failed  = ($results | Where-Object { $_.Status -eq "FAILED" }).Count
Write-Host ""
Write-Host "Created: $created | Failed: $failed" -ForegroundColor $(if ($failed -eq 0) { 'Green' } else { 'Yellow' })

if ($created -gt 0) {
    Write-Host ""
    Write-Host "Publishing solution..." -ForegroundColor Cyan
    pac solution publish
    Write-Host "Done." -ForegroundColor Green
}

# Save report
$reportPath = "customers/ametek/hkp_rma/d365/modern_commands_creation_results.json"
$results | ConvertTo-Json -Depth 5 | Set-Content -Path $reportPath -Encoding UTF8
Write-Host ""
Write-Host "Results saved to $reportPath" -ForegroundColor DarkGray
