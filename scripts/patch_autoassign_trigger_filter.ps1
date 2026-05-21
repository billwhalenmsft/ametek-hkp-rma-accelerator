# patch_autoassign_trigger_filter.ps1
# Fix the subscription BadRequest by removing 'filteringattributes' from the trigger.
# That property is only valid when the trigger message includes Update.
# Our message is Create-only so the filter has no effect and was blocking subscription registration.

$ErrorActionPreference = "Stop"
$env  = "2404ccaf-d7e5-e1ff-863a-3ecbe2f0f013"
$fid  = "ca45e93e-0681-e973-b682-4fe62456dbfa"

$paToken = (az account get-access-token --resource "https://service.flow.microsoft.com/" --query accessToken -o tsv)
$hdr     = @{ Authorization="Bearer $paToken"; "Content-Type"="application/json" }

Write-Host "[1/3] Fetching flow..."
$flow = Invoke-RestMethod -Uri "https://api.flow.microsoft.com/providers/Microsoft.ProcessSimple/environments/$env/flows/${fid}?api-version=2016-11-01" -Headers $hdr
$defn = $flow.properties.definition

$trigName = "When_a_new_RMA_claim_is_created"
$trig = $defn.triggers.$trigName

Write-Host "[2/3] Stripping filteringattributes..."

# Rebuild the inputs without filteringattributes
$newInputs = @{
    parameters = @{
        "subscriptionRequest/message"    = 1
        "subscriptionRequest/entityname" = "rma_claim"
        "subscriptionRequest/scope"      = 4
        subscriptionRequest              = @{
            scope      = 4
            message    = 1
            entityname = "rma_claim"
            runas      = 1
        }
    }
    host = @{
        apiId          = "/providers/Microsoft.PowerApps/apis/shared_commondataserviceforapps"
        connectionName = "shared_commondataserviceforapps"
        operationId    = "SubscribeWebhookTrigger"
    }
    authentication = "@parameters('`$authentication')"
}
$defn.triggers.$trigName.inputs = $newInputs

Write-Host "[3/3] PATCHing flow..."
$patchBody = @{
    properties = @{
        displayName = $flow.properties.displayName
        definition  = $defn
        connectionReferences = $flow.properties.connectionReferences
    }
} | ConvertTo-Json -Depth 50

try {
    Invoke-WebRequest -Uri "https://api.flow.microsoft.com/providers/Microsoft.ProcessSimple/environments/$env/flows/${fid}?api-version=2016-11-01" -Method Patch -Headers $hdr -Body $patchBody | Out-Null
    Write-Host "  [ok] Flow patched."
} catch {
    Write-Host "  [ERR] $($_.ErrorDetails.Message)"
    throw
}

# Stop / start to register fresh subscription
Write-Host "Refreshing subscription..."
Invoke-WebRequest -Uri "https://api.flow.microsoft.com/providers/Microsoft.ProcessSimple/environments/$env/flows/${fid}/stop?api-version=2016-11-01" -Method Post -Headers $hdr | Out-Null
Start-Sleep -Seconds 3
Invoke-WebRequest -Uri "https://api.flow.microsoft.com/providers/Microsoft.ProcessSimple/environments/$env/flows/${fid}/start?api-version=2016-11-01" -Method Post -Headers $hdr | Out-Null
Write-Host "Done."
