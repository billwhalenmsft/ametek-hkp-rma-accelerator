# Patch RMA Email Monitor flow to use the AI Builder prompt "RMA Email Extractor".
#
# Before: 18 Compose actions parsing HTML by string-anchoring on '<b>Label:</b>'
# After:  1 prompt call + 1 Parse JSON + Create_item rewired to Parse JSON outputs
#
# Source of wire shape: copied from "Conversation Analyzer | Analyze Conversation
# Based On Prompt" (e55931c1-601f-f01...) in the same environment.
#
# Notes:
#  - operationId: aibuilderpredict_customprompt
#  - host apiId : shared_commondataserviceforapps  (Dataverse)
#  - recordId   : the prompt's msdyn_aimodelid (47496811-062f-4506-af6e-273b6e2f805f)
#  - input shape: item/requestv2/{VariableName}  -- we created EmailBody
#  - output text: body/responsev2/predictionOutput/text  (the JSON string the prompt returns)
#
# REQUIRES: flow must have a Dataverse (commondataserviceforapps) connection
# reference. This script adds the reference to the flow definition. If Bill
# hasn't already authorized that connection in this env, the flow will show
# a yellow banner asking him to pick a connection in the UI -- a 10-second click.

[CmdletBinding()]
param(
    [string]$EnvId    = "2404ccaf-d7e5-e1ff-863a-3ecbe2f0f013",
    [string]$FlowId   = "b26a7f4b-b181-cd5e-ff45-454939890b06",
    [string]$PromptId = "47496811-062f-4506-af6e-273b6e2f805f"
)

$ErrorActionPreference = "Stop"
$ProgressPreference    = "SilentlyContinue"

Write-Host "`n=== Patching RMA Email Monitor -> AI Builder prompt ===" -ForegroundColor Cyan

$paToken = (az account get-access-token --resource "https://service.flow.microsoft.com/" --query accessToken -o tsv)
if (-not $paToken) { throw "No PA token. Run 'az login' first." }
$hdr = @{
    Authorization = "Bearer $paToken"
    "Content-Type" = "application/json"
}

$flowUri = "https://api.flow.microsoft.com/providers/Microsoft.ProcessSimple/environments/$EnvId/flows/$FlowId" + "?api-version=2016-11-01"

# ---------------------------------------------------------------------------
# 1. Fetch + backup
# ---------------------------------------------------------------------------
Write-Host "  Fetching current flow..." -ForegroundColor Gray
$flow = Invoke-RestMethod -Uri $flowUri -Headers $hdr

$backupDir = Join-Path (Get-Location) "customers\ametek\hkp_rma\d365"
if (-not (Test-Path $backupDir)) { New-Item -ItemType Directory -Path $backupDir -Force | Out-Null }
$backupPath = Join-Path $backupDir ("rma_email_monitor_backup_{0:yyyyMMdd-HHmmss}.json" -f (Get-Date))
$flow | ConvertTo-Json -Depth 30 | Out-File -FilePath $backupPath -Encoding utf8
Write-Host "  Backup: $backupPath" -ForegroundColor DarkGray

# ---------------------------------------------------------------------------
# 2. Build the new actions
# ---------------------------------------------------------------------------

# 2a. Run_RMA_Prompt -- calls the AI Builder prompt
$runPrompt = [ordered]@{
    runAfter = @{}
    metadata = @{
        operationMetadataId = [Guid]::NewGuid().ToString()
        flowSystemMetadata = @{
            portalOperationId                   = "aibuilderpredict_customprompt"
            portalOperationGroup                = "aibuilder"
            portalOperationApiDisplayNameOverride = "AI Builder"
            portalOperationIconOverride         = "https://content.powerapps.com/resource/makerx/static/pauto/images/designeroperations/aiBuilderNew.51dbdb6b.png"
            portalOperationBrandColorOverride   = "#0A76C4"
            portalOperationApiTierOverride      = "Standard"
        }
    }
    type     = "OpenApiConnection"
    inputs   = @{
        parameters = [ordered]@{
            recordId                  = $PromptId
            "item/requestv2/EmailBody" = "@triggerOutputs()?['body/body']"
        }
        host = @{
            apiId          = "/providers/Microsoft.PowerApps/apis/shared_commondataserviceforapps"
            operationId    = "aibuilderpredict_customprompt"
            connectionName = "shared_commondataserviceforapps"
        }
    }
}

# 2b. Parse_RMA_Fields -- parses the JSON string returned by the prompt
$schema = @{
    type = "object"
    properties = [ordered]@{
        Company              = @{ type = "string" }
        Email                = @{ type = "string" }
        Phone                = @{ type = "string" }
        ReturnAddress        = @{ type = "string" }
        Quantity             = @{ type = "string" }
        PONumber             = @{ type = "string" }
        DateCodeOrSerial     = @{ type = "string" }
        PartNumber           = @{ type = "string" }
        MfgLocation          = @{ type = "string" }
        ComplaintReason      = @{ type = "string" }
        ComplaintReasonOther = @{ type = "string" }
        SalesRep             = @{ type = "string" }
        HowDetected          = @{ type = "string" }
        ProductDescription   = @{ type = "string" }
        WhereDetected        = @{ type = "string" }
        NCRNumber            = @{ type = "string" }
        OtherComments        = @{ type = "string" }
    }
}

$parseJson = [ordered]@{
    runAfter = @{ Run_RMA_Prompt = @("Succeeded") }
    metadata = @{ operationMetadataId = [Guid]::NewGuid().ToString() }
    type     = "ParseJson"
    inputs   = @{
        content = "@outputs('Run_RMA_Prompt')?['body/responsev2/predictionOutput/text']"
        schema  = $schema
    }
}

# 2c. Create_item -- start from original, rewire item/* to Parse JSON outputs
$origCreateItem = $flow.properties.definition.actions.Create_item
$createItem = $origCreateItem | ConvertTo-Json -Depth 30 | ConvertFrom-Json -AsHashtable
$createItem.runAfter = @{ Parse_RMA_Fields = @("Succeeded") }

# Map of SP column -> Parse JSON property name
$promptMap = @{
    "item/Company"              = "Company"
    "item/Phone"                = "Phone"
    "item/ReturnAddress"        = "ReturnAddress"
    "item/Quantity"             = "Quantity"
    "item/PONumber"             = "PONumber"
    "item/DateCodeOrSerial"     = "DateCodeOrSerial"
    "item/PartNumber"           = "PartNumber"
    "item/MfgLocation"          = "MfgLocation"
    "item/ComplaintReason"      = "ComplaintReason"
    "item/ComplaintReasonOther" = "ComplaintReasonOther"
    "item/SalesRep"             = "SalesRep"
    "item/HowDetected"          = "HowDetected"
    "item/ProductDescription"   = "ProductDescription"
    "item/WhereDetected"        = "WhereDetected"
    "item/NCRNumber"            = "NCRNumber"
    "item/OtherComments"        = "OtherComments"
}
# Note: existing flow has no 'item/Email' column, just 'item/From' (which is
# already wired to triggerOutputs body/from). We do NOT add a new column.

foreach ($key in $promptMap.Keys) {
    if ($createItem.inputs.parameters.ContainsKey($key)) {
        $jsonProp = $promptMap[$key]
        $createItem.inputs.parameters[$key] = "@body('Parse_RMA_Fields')?['$jsonProp']"
    }
}

# ---------------------------------------------------------------------------
# 3. Assemble new actions ordered map  (only 3 actions besides trigger)
# ---------------------------------------------------------------------------
$newActions = [ordered]@{
    Run_RMA_Prompt    = $runPrompt
    Parse_RMA_Fields  = $parseJson
    Create_item       = $createItem
}

# ---------------------------------------------------------------------------
# 4. Add Dataverse connectionReference if not present
# ---------------------------------------------------------------------------
$connRefs = $flow.properties.connectionReferences | ConvertTo-Json -Depth 10 | ConvertFrom-Json -AsHashtable
if (-not $connRefs.ContainsKey("shared_commondataserviceforapps")) {
    Write-Host "  Adding shared_commondataserviceforapps connection reference (reusing Bill's existing ref)..." -ForegroundColor Yellow
    # Reuse Bill's pre-existing & authorized Dataverse connection reference:
    #   logical name : bw_sharedcommondataserviceforapps_6fb4c
    #   connectionid : shared-commondataser-9933c9ef-b98c-4170-8251-695bb41a22f2
    $connRefs["shared_commondataserviceforapps"] = [ordered]@{
        connectionName                    = "shared-commondataser-9933c9ef-b98c-4170-8251-695bb41a22f2"
        connectionReferenceLogicalName    = "bw_sharedcommondataserviceforapps_6fb4c"
        source                            = "Embedded"
        id                                = "/providers/Microsoft.PowerApps/apis/shared_commondataserviceforapps"
        displayName                       = "Microsoft Dataverse"
        iconUri                           = "https://connectoricons-prod.azureedge.net/releases/v1.0.1681/1.0.1681.3668/commondataserviceforapps/icon.png"
        brandColor                        = "#001B69"
        tier                              = "Standard"
        apiName                           = "commondataserviceforapps"
        isProcessSimpleApiReferenceConversionAlreadyDone = $false
    }
}

# ---------------------------------------------------------------------------
# 5. Assemble updated definition + PATCH
# ---------------------------------------------------------------------------
$updatedDef = $flow.properties.definition | ConvertTo-Json -Depth 30 | ConvertFrom-Json -AsHashtable
$updatedDef.actions = $newActions

$body = @{
    properties = @{
        definition           = $updatedDef
        connectionReferences = $connRefs
    }
} | ConvertTo-Json -Depth 30

Write-Host "  PATCHing flow definition..." -ForegroundColor Gray
try {
    $resp = Invoke-WebRequest -Uri $flowUri -Method Patch -Headers $hdr -Body $body -ErrorAction Stop
    Write-Host "  PATCH succeeded (HTTP $($resp.StatusCode))" -ForegroundColor Green
} catch {
    $msg = $_.Exception.Message
    if ($_.ErrorDetails.Message) { $msg = $_.ErrorDetails.Message }
    Write-Host "  PATCH FAILED:" -ForegroundColor Red
    Write-Host $msg -ForegroundColor DarkYellow
    Write-Host "`n  Restoring from backup..." -ForegroundColor Yellow
    $backup = Get-Content $backupPath -Raw | ConvertFrom-Json -AsHashtable
    $restoreBody = @{
        properties = @{
            definition           = $backup.properties.definition
            connectionReferences = $backup.properties.connectionReferences
        }
    } | ConvertTo-Json -Depth 30
    try {
        $r2 = Invoke-WebRequest -Uri $flowUri -Method Patch -Headers $hdr -Body $restoreBody -ErrorAction Stop
        Write-Host "  Restore OK (HTTP $($r2.StatusCode))" -ForegroundColor Green
    } catch {
        Write-Host "  RESTORE ALSO FAILED. Manually re-import from $backupPath" -ForegroundColor Red
    }
    throw "PATCH failed; original flow restored"
}

# ---------------------------------------------------------------------------
# 6. Verify
# ---------------------------------------------------------------------------
Start-Sleep -Seconds 2
$verify = Invoke-RestMethod -Uri $flowUri -Headers $hdr
Write-Host "`n  Actions after patch:" -ForegroundColor Cyan
$verify.properties.definition.actions.PSObject.Properties | ForEach-Object {
    Write-Host ("    - {0,-22} type={1}" -f $_.Name, $_.Value.type)
}

Write-Host "`n=== DONE ===" -ForegroundColor Cyan
Write-Host ""
Write-Host "What to do now in the Power Automate UI:" -ForegroundColor Yellow
Write-Host "  1. Open https://make.preview.powerautomate.com/environments/$EnvId/solutions/~preferred/flows/$FlowId/details"
Write-Host "  2. If you see a yellow 'Connections needed' banner -> click it, pick or"
Write-Host "     create a Microsoft Dataverse connection (signs you in as admin@)."
Write-Host "  3. Save the flow."
Write-Host "  4. Click Test -> Manually -> Forward a sample RMA email."
Write-Host "  5. After test run completes, drill into 'Run_RMA_Prompt' to confirm"
Write-Host "     the prompt returned a clean JSON string, and 'Parse_RMA_Fields'"
Write-Host "     to confirm each property has its value. Create_item shows the"
Write-Host "     SharePoint item created with all 16 mapped fields populated."
Write-Host ""
Write-Host "Rollback if needed:" -ForegroundColor DarkGray
Write-Host "  Backup is at $backupPath"
