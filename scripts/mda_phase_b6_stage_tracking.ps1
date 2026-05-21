<#
.SYNOPSIS
    Stage tracking foundation:
      1. Add rma_stageenteredon (DateTime) column to rma_claim
      2. Add rma_stageagedays (Int) calculated column showing days in current stage
      3. Create Power Automate flow that updates rma_stageenteredon whenever
         rma_status changes (or on Create)

    Both rma_stageenteredon and rma_stageagedays are then used by:
      - the Pizza Tracker custom page (shows current stage + days in stage)
      - dashboard charts for "average time in stage" analytics
      - views like "Stale claims" (claims sitting in same stage > N days)
#>

[CmdletBinding()]
param(
    [string]$OrgUrl = "https://org6feab6b5.crm.dynamics.com",
    [string]$EnvId  = "2404ccaf-d7e5-e1ff-863a-3ecbe2f0f013"
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

function Find-Column {
    param($Table, $Column)
    try { Invoke-Dv -Method GET -Path "EntityDefinitions(LogicalName='$Table')/Attributes(LogicalName='$Column')?`$select=LogicalName" } catch { $null }
}

# ============================================================================
# STEP 1: Add rma_stageenteredon
# ============================================================================
Write-Host "`n=== Stage tracking setup ===`n" -ForegroundColor Cyan
Write-Host "Step 1: Add rma_stageenteredon column" -ForegroundColor Cyan
if (Find-Column -Table "rma_claim" -Column "rma_stageenteredon") {
    Write-Host "  [skip] rma_stageenteredon exists" -ForegroundColor DarkGray
} else {
    $body = @{
        "@odata.type"      = "Microsoft.Dynamics.CRM.DateTimeAttributeMetadata"
        AttributeType      = "DateTime"
        AttributeTypeName  = @{ Value = "DateTimeType" }
        SchemaName         = "rma_StageEnteredOn"
        DisplayName        = @{ LocalizedLabels = @(@{ Label = "Stage Entered On"; LanguageCode = 1033 }) }
        Description        = @{ LocalizedLabels = @(@{ Label = "Timestamp when the claim entered its current status. Set by the auto-stage-tracker flow."; LanguageCode = 1033 }) }
        RequiredLevel      = @{ Value = "None"; CanBeChanged = $true }
        Format             = "DateAndTime"
        DateTimeBehavior   = @{ Value = "UserLocal" }
    }
    Invoke-Dv -Method POST -Path "EntityDefinitions(LogicalName='rma_claim')/Attributes" -Body $body | Out-Null
    Write-Host "  [add] rma_stageenteredon (DateTime)" -ForegroundColor Green
}

# Wait for column metadata to propagate before adding calc col that references it
Start-Sleep -Seconds 3

# ============================================================================
# STEP 2: Add rma_stageagedays (calculated integer)
# ============================================================================
Write-Host "`nStep 2: Add rma_stageagedays calculated column" -ForegroundColor Cyan
if (Find-Column -Table "rma_claim" -Column "rma_stageagedays") {
    Write-Host "  [skip] rma_stageagedays exists" -ForegroundColor DarkGray
} else {
    # Calculated column formula: days between rma_stageenteredon and Now()
    # When rma_stageenteredon is null, falls back to createdon
    $formula = 'IF(ISNULL([rma_stageenteredon]), DIFFINDAYS([createdon],Now()), DIFFINDAYS([rma_stageenteredon],Now()))'
    $body = @{
        "@odata.type"      = "Microsoft.Dynamics.CRM.IntegerAttributeMetadata"
        AttributeType      = "Integer"
        AttributeTypeName  = @{ Value = "IntegerType" }
        SchemaName         = "rma_StageAgeDays"
        DisplayName        = @{ LocalizedLabels = @(@{ Label = "Stage Age (Days)"; LanguageCode = 1033 }) }
        Description        = @{ LocalizedLabels = @(@{ Label = "Number of days this claim has been in its current stage."; LanguageCode = 1033 }) }
        RequiredLevel      = @{ Value = "None"; CanBeChanged = $true }
        MinValue           = -2147483648
        MaxValue           = 2147483647
        SourceTypeMask     = 1   # 1 = Calculated
        Format             = "None"
        FormulaDefinition  = $formula
    }
    try {
        Invoke-Dv -Method POST -Path "EntityDefinitions(LogicalName='rma_claim')/Attributes" -Body $body | Out-Null
        Write-Host "  [add] rma_stageagedays (calculated integer)" -ForegroundColor Green
    } catch {
        $m = $_.Exception.Message
        if ($_.ErrorDetails.Message) { $m = $_.ErrorDetails.Message }
        Write-Host "  [warn] could not add calc column: $m" -ForegroundColor DarkYellow
        Write-Host "  Falling back to regular Integer column — flow will set it." -ForegroundColor DarkGray
        # Fallback: regular integer
        $body2 = @{
            "@odata.type"      = "Microsoft.Dynamics.CRM.IntegerAttributeMetadata"
            AttributeType      = "Integer"
            AttributeTypeName  = @{ Value = "IntegerType" }
            SchemaName         = "rma_StageAgeDays"
            DisplayName        = @{ LocalizedLabels = @(@{ Label = "Stage Age (Days)"; LanguageCode = 1033 }) }
            Description        = @{ LocalizedLabels = @(@{ Label = "Number of days this claim has been in its current stage."; LanguageCode = 1033 }) }
            RequiredLevel      = @{ Value = "None"; CanBeChanged = $true }
            MinValue           = 0
            MaxValue           = 9999
        }
        try {
            Invoke-Dv -Method POST -Path "EntityDefinitions(LogicalName='rma_claim')/Attributes" -Body $body2 | Out-Null
            Write-Host "  [add] rma_stageagedays (regular integer fallback)" -ForegroundColor Green
        } catch {
            $m2 = $_.Exception.Message
            if ($_.ErrorDetails.Message) { $m2 = $_.ErrorDetails.Message }
            Write-Host "  [FAIL] $m2" -ForegroundColor Red
        }
    }
}

# Publish entity so new columns are usable in views/forms/flows
Write-Host "`nPublishing rma_claim..." -ForegroundColor Cyan
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

# ============================================================================
# STEP 3: Backfill rma_stageenteredon = createdon for existing claims
# ============================================================================
Write-Host "`nStep 3: Backfill existing claims (rma_stageenteredon = createdon)" -ForegroundColor Cyan
$claims = (Invoke-Dv -Method GET -Path "rma_claims?`$filter=rma_stageenteredon eq null&`$select=rma_claimid,rma_claimnumber,createdon").value
Write-Host "  Found $($claims.Count) claims without stage timestamp" -ForegroundColor DarkGray
$ok = 0; $fail = 0
foreach ($c in $claims) {
    try {
        Invoke-Dv -Method PATCH -Path "rma_claims($($c.rma_claimid))" -Body @{ rma_stageenteredon = $c.createdon } | Out-Null
        $ok++
    } catch {
        $fail++
        Write-Host "    [fail] $($c.rma_claimnumber): $($_.Exception.Message)" -ForegroundColor DarkYellow
    }
}
Write-Host "  Backfilled: $ok  Failed: $fail" -ForegroundColor Green

# ============================================================================
# STEP 4: Build Power Automate flow to update rma_stageenteredon on status change
# ============================================================================
Write-Host "`nStep 4: Build Power Automate flow 'RMA Stage Tracker'" -ForegroundColor Cyan

$paToken = (az account get-access-token --resource "https://service.flow.microsoft.com/" --query accessToken -o tsv)
$paHdr = @{ Authorization = "Bearer $paToken"; "Content-Type" = "application/json" }

# Check if flow exists already
$listUri = "https://api.flow.microsoft.com/providers/Microsoft.ProcessSimple/environments/$EnvId/flows?api-version=2016-11-01"
$allFlows = @()
$next = $listUri
while ($next) {
    $r = Invoke-RestMethod -Uri $next -Headers @{Authorization="Bearer $paToken"}
    $allFlows += $r.value
    $next = $r.nextLink
}
$existingFlow = $allFlows | Where-Object { $_.properties.displayName -eq "RMA Stage Tracker" } | Select-Object -First 1

if ($existingFlow) {
    Write-Host "  [skip] flow exists -> $($existingFlow.name)" -ForegroundColor DarkGray
    $flowId = $existingFlow.name
} else {
    $flowDef = @{
        "`$schema" = "https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#"
        contentVersion = "1.0.0.0"
        parameters = @{
            "`$connections" = @{ defaultValue = @{}; type = "Object" }
            "`$authentication" = @{ defaultValue = @{}; type = "SecureObject" }
        }
        triggers = @{
            "When_status_changes_or_claim_is_created" = @{
                type = "OpenApiConnectionWebhook"
                inputs = @{
                    host = @{
                        connectionName = "shared_commondataserviceforapps"
                        operationId    = "SubscribeWebhookTrigger"
                        apiId          = "/providers/Microsoft.PowerApps/apis/shared_commondataserviceforapps"
                    }
                    parameters = @{
                        subscriptionRequest = @{
                            message              = 3      # 3 = both Create + Update (combined)
                            entityname           = "rma_claim"
                            scope                = 4       # 4 = Organization
                            runas                = 1
                            filteringattributes  = "rma_status"
                        }
                    }
                    authentication = "@parameters('`$authentication')"
                }
            }
        }
        actions = @{
            "Update_StageEnteredOn" = @{
                runAfter = @{}
                type = "OpenApiConnection"
                inputs = @{
                    host = @{
                        connectionName = "shared_commondataserviceforapps"
                        operationId    = "UpdateRecord"
                        apiId          = "/providers/Microsoft.PowerApps/apis/shared_commondataserviceforapps"
                    }
                    parameters = @{
                        entityName = "rma_claims"
                        recordId   = "@triggerOutputs()?['body/rma_claimid']"
                        item       = @{
                            rma_stageenteredon = "@utcNow()"
                        }
                    }
                    authentication = "@parameters('`$authentication')"
                }
            }
        }
    }

    $connRefs = @{
        "shared_commondataserviceforapps" = @{
            connectionName                 = "shared-commondataser-9933c9ef-b98c-4170-8251-695bb41a22f2"
            connectionReferenceLogicalName = "bw_sharedcommondataserviceforapps_6fb4c"
            source                         = "Embedded"
            id                             = "/providers/Microsoft.PowerApps/apis/shared_commondataserviceforapps"
            displayName                    = "Microsoft Dataverse"
            iconUri                        = "https://connectoricons-prod.azureedge.net/releases/v1.0.1681/1.0.1681.3668/commondataserviceforapps/icon.png"
            brandColor                     = "#001B69"
            tier                           = "Standard"
            apiName                        = "commondataserviceforapps"
            isProcessSimpleApiReferenceConversionAlreadyDone = $false
        }
    }

    $body = @{
        properties = @{
            displayName          = "RMA Stage Tracker"
            definition           = $flowDef
            connectionReferences = $connRefs
            state                = "Stopped"
        }
    }
    $resp = Invoke-RestMethod -Uri $listUri -Method Post -Headers $paHdr -Body ($body | ConvertTo-Json -Depth 50 -Compress)
    $flowId = $resp.name
    Write-Host "  [create] flow 'RMA Stage Tracker' -> $flowId" -ForegroundColor Green
}

Write-Host "`n=== DONE ===" -ForegroundColor Cyan
Write-Host ""
Write-Host "New columns on rma_claim:" -ForegroundColor Cyan
Write-Host "  - rma_stageenteredon  (DateTime — set by flow on status change)"
Write-Host "  - rma_stageagedays    (Days since stage entered)"
Write-Host ""
Write-Host "Backfilled $ok existing claims with createdon as initial stage timestamp" -ForegroundColor Cyan
Write-Host ""
Write-Host "Activate the flow:" -ForegroundColor Yellow
Write-Host "  https://make.powerautomate.com/environments/$EnvId/flows/$flowId/details"
Write-Host "  Open -> Save -> Turn on"
