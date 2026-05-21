# Diagnose why the cloned flow isn't firing on rma_approvalrecord create
$OrgUrl = "https://org6feab6b5.crm.dynamics.com"
$FlowId = "5d730ad8-1750-f111-a824-0022480a5e8d"
$SourceFlowId = "8ce6f8e5-196f-f011-b4cc-7ced8d6eb30e"

$token = (az account get-access-token --resource $OrgUrl --query accessToken -o tsv)
$h = @{ Authorization = "Bearer $token"; Accept = "application/json" }

Write-Host "=== Check sdkmessageprocessingsteps for flow webhook subscriptions ==="
# These are server-side webhook subscriptions
$ourFilter = "contains(name,'$FlowId') or contains(description,'$FlowId')"
$ours = (Invoke-RestMethod -Uri "$OrgUrl/api/data/v9.2/sdkmessageprocessingsteps?`$filter=$ourFilter&`$select=name,description,sdkmessagefilterid,statecode,createdon" -Headers $h).value
Write-Host "  Our cloned flow ($FlowId): $($ours.Count) subscriptions"
$ours | ForEach-Object { Write-Host "    - $($_.name) statecode=$($_.statecode)" }

Write-Host ""
$srcFilter = "contains(name,'$SourceFlowId') or contains(description,'$SourceFlowId')"
$src = (Invoke-RestMethod -Uri "$OrgUrl/api/data/v9.2/sdkmessageprocessingsteps?`$filter=$srcFilter&`$select=name,description,statecode,createdon" -Headers $h).value
Write-Host "  Source flow   ($SourceFlowId): $($src.Count) subscriptions"
$src | ForEach-Object { Write-Host "    - $($_.name) statecode=$($_.statecode)" }

Write-Host ""
Write-Host "=== Look for any webhook subscriptions tied to rma_approvalrecord create ==="
# webhooks are usually in the "webhook" entity for service endpoints, or sdkmessageprocessingstep with sdkmessage=Create + filter on rma_approvalrecord
# Let's check the webhooks table:
try {
    $webhooks = (Invoke-RestMethod -Uri "$OrgUrl/api/data/v9.2/serviceendpoints?`$select=name,url,createdon,statecode" -Headers $h).value
    Write-Host "  Total service endpoints: $($webhooks.Count)"
    $webhooks | Where-Object { $_.url -like '*flow*' -or $_.name -like '*flow*' } | Select-Object -First 5 | ForEach-Object {
        Write-Host "    - $($_.name) statecode=$($_.statecode)"
    }
} catch {
    Write-Host "  (serviceendpoints query not allowed)"
}

Write-Host ""
Write-Host "=== Power Automate run history endpoint test (Dataverse-side) ==="
# Try direct flowruns / flow_run table
try {
    $runs = (Invoke-RestMethod -Uri "$OrgUrl/api/data/v9.2/flow_runs?`$top=3" -Headers $h).value
    Write-Host "  flow_runs table accessible, $($runs.Count) recent runs"
} catch {
    Write-Host "  flow_runs not queryable: $($_.Exception.Message.Substring(0,[Math]::Min(80,$_.Exception.Message.Length)))"
}
try {
    $sessions = (Invoke-RestMethod -Uri "$OrgUrl/api/data/v9.2/flowsessions?`$top=3&`$select=name,startedon,statuscode,statecode" -Headers $h).value
    Write-Host "  flowsessions table accessible, total=$($sessions.Count)"
} catch {
    Write-Host "  flowsessions not queryable"
}
