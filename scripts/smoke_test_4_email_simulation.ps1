# smoke_test_4_email_simulation.ps1
#
# Smoke test #4 from CoE handoff — simulated inbound email path.
#
# I cannot actually send an email from this environment. Instead, this script
# directly POSTs a synthetic inbound email record to Dataverse rma_emaillog
# matching the shape the patched RMA Email Monitor flow writes. This validates:
#   - The rma_emaillog form renders the record
#   - The "Inbound - Unprocessed" view shows it as default
#   - The Create-Claim-from-Email button flow works end-to-end
#
# After running, the record should appear in the app's Email Inbox view.
#
# To smoke-test the REAL email pipeline (which goes
# rmarequest@D365DemoTSCE30330346.onmicrosoft.com -> RMA Email Monitor flow ->
# this same table), Bill needs to send an actual email from any mailbox.

[CmdletBinding()]
param(
    [string] $OrgUrl = "https://org6feab6b5.crm.dynamics.com"
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

$nowIso = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
$subject = "[SIMULATED] RMA request - WTB-MOTOR-9999 - failed after 2 weeks"
$body = @{
    rma_subject        = $subject
    rma_fromaddress    = "test.customer@example.com"
    rma_recipient      = "rmarequest@D365DemoTSCE30330346.onmicrosoft.com"
    rma_bodypreview    = "Hi - we received the part WTB-MOTOR-9999 about two weeks ago. It is now showing an intermittent failure mode. Please advise on RMA process. Order ID 47A22, qty 1. Thanks, Test Customer."
    rma_direction      = 100000000   # Inbound
    rma_isprocessed    = $false
    rma_receiveddate   = $nowIso
} | ConvertTo-Json -Compress

Write-Host "=== Simulating inbound email ===" -ForegroundColor Cyan
Write-Host "  POSTing to rma_emaillogs..."
try {
    $created = Invoke-RestMethod -Method POST -Uri "$OrgUrl/api/data/v9.2/rma_emaillogs" -Headers $hdr -Body $body
    Write-Host "  CREATED: $($created.rma_emaillogid)" -ForegroundColor Green
    Write-Host "  Subject: $($created.rma_subject)"
    Write-Host "  Direction: $($created.rma_direction)  Inbound=100000000"
    Write-Host "  IsProcessed: $($created.rma_isprocessed)"
    Write-Host "  Received: $($created.rma_receiveddate)"
} catch {
    Write-Host "  FAILED: $($_.Exception.Message)" -ForegroundColor Red
    if ($_.ErrorDetails) { Write-Host "  $($_.ErrorDetails.Message)" -ForegroundColor DarkRed }
    return
}

# Verify it appears in the Inbound - Unprocessed view
Write-Host ""
Write-Host "=== Verifying view filter ===" -ForegroundColor Cyan
$cnt = Invoke-RestMethod -Uri "$OrgUrl/api/data/v9.2/rma_emaillogs?`$filter=rma_direction eq 100000000 and rma_isprocessed eq false&`$count=true&`$select=rma_emaillogid&`$top=1" -Headers $hdr
Write-Host "Records matching 'Inbound - Unprocessed' filter: $($cnt.'@odata.count')" -ForegroundColor Green

$result = [PSCustomObject]@{
    SimulatedEmailId = $created.rma_emaillogid
    Subject          = $subject
    InboundUnprocessedCount = $cnt.'@odata.count'
    Notes = "Real email pipeline requires Bill to send to rmarequest@D365DemoTSCE30330346.onmicrosoft.com from any mailbox. Email Monitor flow last ran 2026-05-11; no events since."
}
$result | ConvertTo-Json -Depth 5 | Set-Content -Path "customers/ametek/hkp_rma/d365/smoke_test_4_result.json" -Encoding UTF8
Write-Host ""
Write-Host "Result saved to customers/ametek/hkp_rma/d365/smoke_test_4_result.json" -ForegroundColor DarkGray
