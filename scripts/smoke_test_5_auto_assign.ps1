# smoke_test_5_auto_assign.ps1
#
# Smoke test #5 from CoE handoff:
# Create a test rma_claim with part `WTB-MOTOR-9999` (matches routing rule WTB-)
# Wait 2-3 minutes. Verify:
#   - rma_AssignedPlant is now Waterbury CT (set by RMA Auto-Assign Plant flow)
#   - rma_stageenteredon got stamped (set by RMA Stage Tracker flow)
#
# Both flows are async — they trigger on create. Stage Tracker likely triggers on
# rma_status change, but should also fire on Create if it stamps the initial stage.

[CmdletBinding()]
param(
    [string] $OrgUrl = "https://org6feab6b5.crm.dynamics.com",
    [int]    $WaitSeconds = 150
)

$ErrorActionPreference = "Stop"
$token = az account get-access-token --resource $OrgUrl --query accessToken -o tsv
$hdr = @{
    Authorization      = "Bearer $token"
    Accept             = "application/json"
    "Content-Type"     = "application/json; charset=utf-8"
    "OData-MaxVersion" = "4.0"
    "OData-Version"    = "4.0"
    "Prefer"           = "return=representation"
}

# Step 1: create the test claim
$testTag = "SMOKE-" + (Get-Date -Format "MMddHHmm")
$body = @{
    rma_claimnumber       = "RMA-SMOKE-WTB-$testTag"
    rma_partnumber        = "WTB-MOTOR-9999"
    rma_customername      = "Smoke Test Customer"
    rma_customeremail     = "smoketest@example.com"
    rma_customerregion    = 100000000  # whatever the default optionset value is
    rma_quantity          = 1
    rma_creditamount      = 100
    rma_failuredescription= "Smoke test claim to verify auto-assign + stage tracker flows."
    rma_status            = 100000000  # New
    rma_warrantystatus    = 100000000  # Default first option
}
$json = $body | ConvertTo-Json -Depth 4

Write-Host "=== Creating smoke-test claim with part WTB-MOTOR-9999 ===" -ForegroundColor Cyan
$createStart = Get-Date
$created = Invoke-RestMethod -Method POST `
    -Uri "$OrgUrl/api/data/v9.2/rma_claims" `
    -Headers $hdr `
    -Body $json
$claimId = $created.rma_claimid
Write-Host "Created claim id=$claimId" -ForegroundColor Green
Write-Host "  Initial _rma_assignedplant_value=$($created._rma_assignedplant_value)"
Write-Host "  Initial rma_stageenteredon=$($created.rma_stageenteredon)"
Write-Host "  Created at: $createStart"

# Step 2: wait
Write-Host ""
Write-Host "Waiting $WaitSeconds seconds for flows to fire..." -ForegroundColor DarkGray
Start-Sleep -Seconds $WaitSeconds

# Step 3: re-read the claim and check
Write-Host ""
Write-Host "=== Re-reading claim after wait ===" -ForegroundColor Cyan
$claim = Invoke-RestMethod -Uri "$OrgUrl/api/data/v9.2/rma_claims($claimId)?`$select=rma_claimnumber,rma_partnumber,_rma_assignedplant_value,rma_stageenteredon,rma_status,modifiedon" -Headers $hdr
Write-Host "  claimnumber=$($claim.rma_claimnumber)"
Write-Host "  partnumber=$($claim.rma_partnumber)"
Write-Host "  _rma_assignedplant_value=$($claim._rma_assignedplant_value)"
Write-Host "  rma_stageenteredon=$($claim.rma_stageenteredon)"
Write-Host "  rma_status=$($claim.rma_status)"
Write-Host "  modifiedon=$($claim.modifiedon)"

$assignedPlantName = $null
if ($claim._rma_assignedplant_value) {
    $plant = Invoke-RestMethod -Uri "$OrgUrl/api/data/v9.2/rma_plants($($claim._rma_assignedplant_value))?`$select=rma_name" -Headers $hdr
    $assignedPlantName = $plant.rma_name
    Write-Host "  -> Plant name: $assignedPlantName" -ForegroundColor Green
}

# Step 4: check workflow run history
Write-Host ""
Write-Host "=== Recent flow runs (asyncoperation) for both flows ===" -ForegroundColor Cyan
foreach ($f in @(
    @{Name='Auto-Assign Plant'; Id='98f4965b-2e4e-f111-bec6-000d3a5aed87'},
    @{Name='Stage Tracker';     Id='2755df62-2f4e-f111-bec6-000d3a5aed87'}
)) {
    $isoStart = $createStart.ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    $q = "$OrgUrl/api/data/v9.2/asyncoperations?`$filter=_workflowactivationid_value eq $($f.Id) and createdon gt $isoStart&`$select=name,statecode,statuscode,createdon,completedon,errorcode,message&`$orderby=createdon desc&`$top=5"
    try {
        $r = Invoke-RestMethod -Uri $q -Headers $hdr
        Write-Host "$($f.Name): $($r.value.Count) runs since $isoStart" -ForegroundColor Yellow
        foreach ($run in $r.value) {
            $status = switch ($run.statuscode) { 30 {"SUCCEEDED"} 31 {"FAILED"} 32 {"CANCELLED"} default {"state=$($run.statecode)/status=$($run.statuscode)"} }
            Write-Host "   $status  createdon=$($run.createdon)  msg=$($run.message)"
        }
    } catch {
        Write-Host "$($f.Name): query error $($_.Exception.Message)" -ForegroundColor Red
    }
}

# Step 5: write result
Write-Host ""
Write-Host "=== Smoke test #5 verdict ===" -ForegroundColor Cyan
$autoAssignOk = ($null -ne $claim._rma_assignedplant_value)
$stageOk      = ($null -ne $claim.rma_stageenteredon)
Write-Host "  Auto-Assign Plant flow fired & plant set: $(if ($autoAssignOk) {'PASS (' + $assignedPlantName + ')'} else {'FAIL (plant still empty)'})" -ForegroundColor $(if ($autoAssignOk) {'Green'} else {'Red'})
Write-Host "  Stage Tracker flow fired & stage stamped: $(if ($stageOk) {'PASS'} else {'FAIL (stageenteredon still null)'})" -ForegroundColor $(if ($stageOk) {'Green'} else {'Red'})

$result = [PSCustomObject]@{
    TestClaimId        = $claimId
    TestClaimNumber    = $claim.rma_claimnumber
    PartNumber         = $claim.rma_partnumber
    CreatedAt          = $createStart
    WaitedSeconds      = $WaitSeconds
    AssignedPlantValue = $claim._rma_assignedplant_value
    AssignedPlantName  = $assignedPlantName
    StageEnteredOn     = $claim.rma_stageenteredon
    AutoAssignPass     = $autoAssignOk
    StageTrackerPass   = $stageOk
}
$result | ConvertTo-Json -Depth 5 | Set-Content -Path "customers/ametek/hkp_rma/d365/smoke_test_5_result.json" -Encoding UTF8
Write-Host ""
Write-Host "Result saved to customers/ametek/hkp_rma/d365/smoke_test_5_result.json" -ForegroundColor DarkGray
