# patch_ack_to_field.ps1
# Fix Send_Acknowledgement.To: coalesce treats "" as non-null, so it picks the empty
# string from Parse_RMA_Fields.Email and never falls back to triggerOutputs().body/from.
# Replace with an empty-aware expression.

$ErrorActionPreference = "Stop"
$env = "2404ccaf-d7e5-e1ff-863a-3ecbe2f0f013"
$fid = "b26a7f4b-b181-cd5e-ff45-454939890b06"

$paToken = (az account get-access-token --resource "https://service.flow.microsoft.com/" --query accessToken -o tsv)
$hdr     = @{ Authorization="Bearer $paToken"; "Content-Type"="application/json" }

Write-Host "[1/3] Fetching flow..."
$flow = Invoke-RestMethod -Uri "https://api.flow.microsoft.com/providers/Microsoft.ProcessSimple/environments/$env/flows/${fid}?api-version=2016-11-01" -Headers $hdr
$defn = $flow.properties.definition

# Backup
$bak = "customers\ametek\hkp_rma\d365\rma_email_monitor_backup_$(Get-Date -Format 'yyyyMMdd-HHmmss').json"
$defn | ConvertTo-Json -Depth 50 | Set-Content -Path $bak -Encoding UTF8
Write-Host "  Backup: $bak"

Write-Host "[2/3] Patching Send_Acknowledgement.To and bolded part..."

$toExpr = "@if(empty(coalesce(body('Parse_RMA_Fields')?['Email'],'')), coalesce(triggerOutputs()?['body/from'],''), body('Parse_RMA_Fields')?['Email'])"

$body = @"
<p>Hi,</p>
<p>Thanks for your email regarding part <b>@{if(empty(coalesce(body('Parse_RMA_Fields')?['PartNumber'],'')), '(part not detected)', body('Parse_RMA_Fields')?['PartNumber'])}</b>.</p>
<p>We've logged your request and our team will review it shortly. You'll either receive confirmation that an RMA claim has been opened, or we'll reach back out with questions/updates.</p>
<p>&mdash; RMA Team<br/>HKP / Ametek</p>
"@

$defn.actions.Send_Acknowledgement.inputs.parameters.emailMessage.To = $toExpr
$defn.actions.Send_Acknowledgement.inputs.parameters.emailMessage.Body = $body

Write-Host "[3/3] PATCHing flow..."
$patchBody = @{
    properties = @{
        displayName          = $flow.properties.displayName
        definition           = $defn
        connectionReferences = $flow.properties.connectionReferences
    }
} | ConvertTo-Json -Depth 50

Invoke-WebRequest -Uri "https://api.flow.microsoft.com/providers/Microsoft.ProcessSimple/environments/$env/flows/${fid}?api-version=2016-11-01" -Method Patch -Headers $hdr -Body $patchBody | Out-Null
Write-Host "  [ok] Flow patched."
