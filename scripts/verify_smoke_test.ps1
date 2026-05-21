# Check side-effects after smoke test
$OrgUrl = "https://org6feab6b5.crm.dynamics.com"
$ApprId = "94059a88-1a50-f111-a824-0022480a5e8d"
$ClaimId = "2320ba6d-ef4e-f111-bec6-000d3a5aed87"

$token = (az account get-access-token --resource $OrgUrl --query accessToken -o tsv)
$h = @{ Authorization = "Bearer $token"; Accept = "application/json" }

Write-Host "=== Sleep 30s for flow to fire + Approvals to deliver ==="
Start-Sleep -Seconds 30

Write-Host ""
Write-Host "=== Approval record state ==="
$ar = Invoke-RestMethod -Uri "$OrgUrl/api/data/v9.2/rma_approvalrecords($ApprId)?`$select=rma_name,rma_approvalstatus,rma_approvaldate,rma_approvername,rma_approvalnotes" -Headers $h
Write-Host "  status: $($ar.rma_approvalstatus)  (100000000=Pending, 100000001=Approved, 100000002=Denied)"
Write-Host "  approvaldate: $($ar.rma_approvaldate)"
Write-Host "  approvername: $($ar.rma_approvername)"

Write-Host ""
Write-Host "=== Claim status (flow Step 4 sets to 100000003=Decision while waiting) ==="
$cl = Invoke-RestMethod -Uri "$OrgUrl/api/data/v9.2/rma_claims($ClaimId)?`$select=rma_claimnumber,rma_status,statuscode" -Headers $h
Write-Host "  number: $($cl.rma_claimnumber)"
Write-Host "  rma_status: $($cl.rma_status)  (100000003=Decision=waiting, 100000004=Closed=approved)"
Write-Host "  statuscode: $($cl.statuscode)"

Write-Host ""
Write-Host "=== History rows for this claim ==="
$hist = (Invoke-RestMethod -Uri "$OrgUrl/api/data/v9.2/rma_approvalhistories?`$filter=_rma_claim_value eq $ClaimId&`$orderby=createdon desc&`$top=5&`$select=rma_action,rma_actiondate,rma_viateams,rma_comments,createdon" -Headers $h).value
if (-not $hist) {
    Write-Host "  (no history rows yet)"
} else {
    $hist | ForEach-Object { Write-Host "  $($_.createdon) action=$($_.rma_action) viaTeams=$($_.rma_viateams)" }
}

Write-Host ""
Write-Host "=== Pending approvals visible to admin (Teams Approvals API surface) ==="
Write-Host "  Open Teams > Approvals app for admin@D365DemoTSCE30330346.onmicrosoft.com to see the card."
Write-Host "  Or check the flow run history at:"
Write-Host "  https://make.powerautomate.com/environments/2404ccaf-d7e5-e1ff-863a-3ecbe2f0f013/solutions/Default/flows/5d730ad8-1750-f111-a824-0022480a5e8d/details"
