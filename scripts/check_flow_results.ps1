# Verify flow side-effects
$OrgUrl = "https://org6feab6b5.crm.dynamics.com"
$ApprId = "b30f291d-1850-f111-a824-0022480a5e8d"
$ClaimId = "2320ba6d-ef4e-f111-bec6-000d3a5aed87"

$token = (az account get-access-token --resource $OrgUrl --query accessToken -o tsv)
$h = @{ Authorization = "Bearer $token"; Accept = "application/json" }

Write-Host "=== rma_approvalrecord field list (rma_*) ==="
$attrs = (Invoke-RestMethod -Uri "$OrgUrl/api/data/v9.2/EntityDefinitions(LogicalName='rma_approvalrecord')/Attributes?`$select=LogicalName,SchemaName" -Headers $h).value
$attrs | Where-Object { $_.LogicalName -like 'rma_*' } | Select-Object -ExpandProperty LogicalName | Sort-Object | ForEach-Object { Write-Host "  $_" }

Write-Host ""
Write-Host "=== Test approval record state (after smoke test) ==="
$ar = Invoke-RestMethod -Uri "$OrgUrl/api/data/v9.2/rma_approvalrecords($ApprId)?`$select=rma_name,rma_approvalstatus,rma_requestedamount" -Headers $h
Write-Host "  status: $($ar.rma_approvalstatus)  (100000000=Pending, 100000001=Approved, 100000002=Denied)"
Write-Host "  amount: $($ar.rma_requestedamount)"

Write-Host ""
Write-Host "=== Claim status (flow Step 4 sets to 100000003=Decision) ==="
$cl = Invoke-RestMethod -Uri "$OrgUrl/api/data/v9.2/rma_claims($ClaimId)?`$select=rma_claimnumber,rma_status,statuscode" -Headers $h
Write-Host "  number: $($cl.rma_claimnumber)"
Write-Host "  rma_status: $($cl.rma_status)  (100000003=Decision)"
Write-Host "  statuscode: $($cl.statuscode)"

Write-Host ""
Write-Host "=== History rows for this approval/claim ==="
$hist = (Invoke-RestMethod -Uri "$OrgUrl/api/data/v9.2/rma_approvalhistories?`$filter=_rma_claim_value eq $ClaimId&`$orderby=createdon desc&`$top=5&`$select=rma_action,rma_actiondate,rma_viateams,rma_comments,createdon" -Headers $h).value
if (-not $hist) { Write-Host "  (no history rows yet)" } else {
    $hist | ForEach-Object { Write-Host "  $($_.createdon) action=$($_.rma_action) viaTeams=$($_.rma_viateams) comments=$($_.rma_comments)" }
}
