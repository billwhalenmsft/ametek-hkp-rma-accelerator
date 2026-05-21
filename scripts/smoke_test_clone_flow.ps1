# Smoke test the cloned RMA: Request Manager Approval flow
# Creates a test rma_approvalrecord then checks if flow fired

$OrgUrl = "https://org6feab6b5.crm.dynamics.com"
$FlowId = "5d730ad8-1750-f111-a824-0022480a5e8d"
$ClaimId = "2320ba6d-ef4e-f111-bec6-000d3a5aed87"   # RMA-SMOKE-WTB-SMOKE-05131216

$token = (az account get-access-token --resource $OrgUrl --query accessToken -o tsv)
$h = @{ Authorization = "Bearer $token"; Accept = "application/json" }
$hP = @{
    Authorization = "Bearer $token"
    Accept = "application/json"
    "Content-Type" = "application/json"
    "OData-MaxVersion" = "4.0"
    "OData-Version" = "4.0"
    Prefer = "return=representation"
}

Write-Host "=== Creating test rma_approvalrecord on claim $ClaimId ==="
$body = @{
    "rma_name"             = "SMOKE TEST: Manager Approval Flow $(Get-Date -Format 'HHmmss')"
    "rma_requestedamount"  = 1500
    "rma_thresholdamount"  = 500
    "rma_requestreason"    = "Smoke test - 1500 USD credit exceeds threshold"
    "rma_approvalstatus"   = 100000000
    "rma_Claim@odata.bind" = "/rma_claims($ClaimId)"
} | ConvertTo-Json

$r = Invoke-RestMethod -Method POST -Uri "$OrgUrl/api/data/v9.2/rma_approvalrecords" -Headers $hP -Body $body
Write-Host "Created approval record: $($r.rma_approvalrecordid)"
Write-Host "  name:   $($r.rma_name)"
Write-Host "  amount: $($r.rma_requestedamount)"
Write-Host ""

Write-Host "Waiting 12s for flow trigger to register..."
Start-Sleep -Seconds 12

Write-Host ""
Write-Host "=== Latest 3 runs of our flow ==="
$runs = (Invoke-RestMethod -Uri "$OrgUrl/api/data/v9.2/flowsessions?`$filter=_regardingobjectid_value eq $FlowId&`$orderby=startedon desc&`$top=3&`$select=startedon,statuscode,statecode,errorcode,errormessage" -Headers $h).value

if (-not $runs) {
    Write-Host "  (no runs returned via flowsessions table - that table may not be queryable here)"
    Write-Host "  Open the flow in the maker portal to see runs:"
    Write-Host "  https://make.powerautomate.com/environments/2404ccaf-d7e5-e1ff-863a-3ecbe2f0f013/solutions/Default/flows/$FlowId/details"
} else {
    foreach ($run in $runs) {
        Write-Host ("  startedon={0}  statuscode={1}  statecode={2}" -f $run.startedon, $run.statuscode, $run.statecode)
        if ($run.errormessage) { Write-Host "    error: $($run.errormessage)" }
    }
}

Write-Host ""
Write-Host "=== Re-fetch our test approval record - did flow update its status? ==="
$check = Invoke-RestMethod -Uri "$OrgUrl/api/data/v9.2/rma_approvalrecords($($r.rma_approvalrecordid))?`$select=rma_name,rma_approvalstatus,rma_approvaldate" -Headers $h
Write-Host "  approvalstatus: $($check.rma_approvalstatus)  (100000000=Pending, 100000001=Approved, 100000002=Denied)"
Write-Host "  approvaldate:   $($check.rma_approvaldate)"
Write-Host ""
Write-Host "Test record id (delete after demo): $($r.rma_approvalrecordid)"
