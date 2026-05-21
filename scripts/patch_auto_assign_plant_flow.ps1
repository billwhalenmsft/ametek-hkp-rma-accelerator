# patch_auto_assign_plant_flow.ps1
# Fix two bugs in RMA Auto-Assign Plant flow:
#   1) Update_a_row has no item body - add rma_AssignedPlant@odata.bind binding
#   2) Refresh webhook trigger subscription via stop -> start

$ErrorActionPreference = "Stop"
$env  = "2404ccaf-d7e5-e1ff-863a-3ecbe2f0f013"
$fid  = "ca45e93e-0681-e973-b682-4fe62456dbfa"

$paToken = (az account get-access-token --resource "https://service.flow.microsoft.com/" --query accessToken -o tsv)
$hdr     = @{ Authorization="Bearer $paToken"; "Content-Type"="application/json" }

# 1. Fetch current flow
Write-Host "[1/4] Fetching flow..."
$flow = Invoke-RestMethod -Uri "https://api.flow.microsoft.com/providers/Microsoft.ProcessSimple/environments/$env/flows/${fid}?api-version=2016-11-01" -Headers $hdr

# Backup
$backup = $flow.properties.definition | ConvertTo-Json -Depth 50
$backupPath = "customers\ametek\hkp_rma\d365\autoassignplant_flow_backup_$(Get-Date -Format 'yyyyMMdd-HHmmss').json"
$backup | Set-Content -Path $backupPath -Encoding UTF8
Write-Host "  Backup: $backupPath"

# 2. Build patched definition - add item body to Update_a_row
Write-Host "[2/4] Patching Update_a_row action body..."
$defn = $flow.properties.definition

# Update_a_row lives inside Update_RMA_Claim.actions
$update = $defn.actions.Update_RMA_Claim.actions.Update_a_row

# Add the 'item' parameter with the lookup binding
$updateInputs = @{
    parameters = @{
        entityName = "rma_claims"
        recordId   = "@triggerOutputs()?['body/rma_claimid']"
        item       = @{
            "rma_AssignedPlant@odata.bind" = "@{concat('/rma_plants(', variables('AssignedPlantId'), ')')}"
        }
    }
    host = @{
        apiId          = "/providers/Microsoft.PowerApps/apis/shared_commondataserviceforapps"
        connectionName = "shared_commondataserviceforapps"
        operationId    = "UpdateRecord"
    }
    authentication = "@parameters('`$authentication')"
}

# Replace the inputs property
$defn.actions.Update_RMA_Claim.actions.Update_a_row.inputs = $updateInputs

# 3. PATCH the flow definition
Write-Host "[3/4] PATCHing flow..."
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

# 4. Refresh webhook subscription by toggling state
Write-Host "[4/4] Refreshing trigger (stop -> start)..."
Invoke-WebRequest -Uri "https://api.flow.microsoft.com/providers/Microsoft.ProcessSimple/environments/$env/flows/${fid}/stop?api-version=2016-11-01" -Method Post -Headers $hdr | Out-Null
Start-Sleep -Seconds 3
Invoke-WebRequest -Uri "https://api.flow.microsoft.com/providers/Microsoft.ProcessSimple/environments/$env/flows/${fid}/start?api-version=2016-11-01" -Method Post -Headers $hdr | Out-Null
Write-Host "  [ok] Trigger refreshed."

Write-Host ""
Write-Host "Done. New webhook subscription registered. Next claim create will trigger plant assignment."
