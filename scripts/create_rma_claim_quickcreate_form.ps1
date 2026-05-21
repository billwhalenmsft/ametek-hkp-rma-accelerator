# Build a Quick Create form for rma_claim (was missing)
# Quick Create = systemform type 7. Used by global "+ New" button + email-to-claim creation.
param(
    [string]$OrgUrl = "https://org6feab6b5.crm.dynamics.com"
)
$ErrorActionPreference = "Stop"
$token = az account get-access-token --resource $OrgUrl --query accessToken -o tsv
$h = @{
    Authorization = "Bearer $token"
    Accept = "application/json"
    "Content-Type" = "application/json"
    "OData-MaxVersion" = "4.0"
    "OData-Version" = "4.0"
}

# Check if a Quick Create already exists
$existing = (Invoke-RestMethod -Uri "$OrgUrl/api/data/v9.2/systemforms?`$filter=objecttypecode eq 'rma_claim' and type eq 7&`$select=name,formid" -Headers $h).value
if ($existing) {
    Write-Host "Quick Create form already exists: $($existing[0].formid). Skipping." -ForegroundColor Yellow
    return
}

# Quick Create form XML — 1 tab, 2 columns side-by-side, each with 1-column section.
# Description section spans full width below as a 3rd column under the tab.
# Constraints: max 1 tab, each section columns="1".
$formxml = @'
<form><tabs><tab verticallayout="true" id="{f1aaaaaa-1111-4444-bbbb-aaaaaaaaaaaa}" IsUserDefined="1" name="quickcreate_tab"><labels><label description="Quick Create" languagecode="1033" /></labels><columns><column width="33%"><sections><section showlabel="true" showbar="false" id="{f2aaaaaa-2222-4444-bbbb-aaaaaaaaaaaa}" columns="1" labelwidth="115" IsUserDefined="0" name="customer_section"><labels><label description="Customer" languagecode="1033" /></labels><rows><row><cell id="{f3aaaaaa-3333-4444-bbbb-aaaaaaaaaaaa}" colspan="1" rowspan="1"><labels><label description="Customer Name" languagecode="1033" /></labels><control id="rma_customername" classid="{4273EDBD-AC1D-40d3-9FB2-095C621B552D}" datafieldname="rma_customername" /></cell></row><row><cell id="{f4aaaaaa-4444-4444-bbbb-aaaaaaaaaaaa}" colspan="1" rowspan="1"><labels><label description="Customer Email" languagecode="1033" /></labels><control id="rma_customeremail" classid="{4273EDBD-AC1D-40d3-9FB2-095C621B552D}" datafieldname="rma_customeremail" /></cell></row><row><cell id="{f5aaaaaa-5555-4444-bbbb-aaaaaaaaaaaa}" colspan="1" rowspan="1"><labels><label description="Customer Region" languagecode="1033" /></labels><control id="rma_customerregion" classid="{3EF39988-22BB-4f0b-BBBE-64B5A3748AEE}" datafieldname="rma_customerregion" /></cell></row><row><cell id="{f6aaaaaa-6666-4444-bbbb-aaaaaaaaaaaa}" colspan="1" rowspan="1"><labels><label description="Contact Name" languagecode="1033" /></labels><control id="rma_contactname" classid="{4273EDBD-AC1D-40d3-9FB2-095C621B552D}" datafieldname="rma_contactname" /></cell></row></rows></section></sections></column><column width="33%"><sections><section showlabel="true" showbar="false" id="{e2aaaaaa-2222-4444-bbbb-bbbbbbbbbbbb}" columns="1" labelwidth="115" IsUserDefined="0" name="part_section"><labels><label description="Part &amp; Failure" languagecode="1033" /></labels><rows><row><cell id="{f7aaaaaa-7777-4444-bbbb-aaaaaaaaaaaa}" colspan="1" rowspan="1"><labels><label description="Part Number" languagecode="1033" /></labels><control id="rma_partnumber" classid="{4273EDBD-AC1D-40d3-9FB2-095C621B552D}" datafieldname="rma_partnumber" /></cell></row><row><cell id="{f8aaaaaa-8888-4444-bbbb-aaaaaaaaaaaa}" colspan="1" rowspan="1"><labels><label description="Quantity" languagecode="1033" /></labels><control id="rma_quantity" classid="{C6D124CA-7EDA-4a60-AEA9-7FB8D318B68F}" datafieldname="rma_quantity" /></cell></row><row><cell id="{f9aaaaaa-9999-4444-bbbb-aaaaaaaaaaaa}" colspan="1" rowspan="1"><labels><label description="Failure Mode" languagecode="1033" /></labels><control id="rma_failuremode" classid="{3EF39988-22BB-4f0b-BBBE-64B5A3748AEE}" datafieldname="rma_failuremode" /></cell></row><row><cell id="{faaaaaaa-aaaa-4444-bbbb-aaaaaaaaaaaa}" colspan="1" rowspan="1"><labels><label description="Assigned Plant" languagecode="1033" /></labels><control id="rma_assignedplant" classid="{270BD3DB-D9AF-4782-9025-509E298DEC0A}" datafieldname="rma_assignedplant" /></cell></row></rows></section></sections></column><column width="34%"><sections><section showlabel="true" showbar="false" id="{c2aaaaaa-2222-4444-bbbb-cccccccccccc}" columns="1" labelwidth="115" IsUserDefined="0" name="desc_section"><labels><label description="Failure Details" languagecode="1033" /></labels><rows><row><cell id="{fbaaaaaa-bbbb-4444-bbbb-aaaaaaaaaaaa}" colspan="1" rowspan="4"><labels><label description="Failure Description" languagecode="1033" /></labels><control id="rma_failuredescription" classid="{E0DECE4B-6FC8-4a8f-A065-082708572369}" datafieldname="rma_failuredescription" /></cell></row><row /><row /><row /></rows></section></sections></column></columns></tab></tabs></form>
'@

# Validate XML well-formed
try { [xml]$formxml | Out-Null; "  XML validates OK" } catch { throw "Form XML malformed: $_" }

$body = @{
    name = "RMA Claim Quick Create"
    description = "Quick Create form for rma_claim - 8 essential intake fields"
    objecttypecode = "rma_claim"
    type = 7
    formxml = $formxml
    formactivationstate = 1
} | ConvertTo-Json -Depth 5

Write-Host "POSTing new Quick Create form..." -ForegroundColor Cyan
$resp = Invoke-WebRequest -Method POST -Uri "$OrgUrl/api/data/v9.2/systemforms" -Headers $h -Body $body -UseBasicParsing
$loc = $resp.Headers["OData-EntityId"]
if ($loc -match 'systemforms\(([0-9a-f-]+)\)') { $formId = $Matches[1] }
Write-Host "  Created form id: $formId" -ForegroundColor Green

# Publish entity
Write-Host "Publishing rma_claim..."
$pubXml = "<importexportxml><entities><entity>rma_claim</entity></entities></importexportxml>"
$pubBody = @{ ParameterXml = $pubXml } | ConvertTo-Json
Invoke-WebRequest -Method POST -Uri "$OrgUrl/api/data/v9.2/PublishXml" -Headers $h -Body $pubBody -UseBasicParsing | Out-Null
Write-Host "  Published" -ForegroundColor Green

Write-Host ""
Write-Host "Quick Create form ready. Click '+ New' in the global app bar -> 'RMA Claim'." -ForegroundColor Cyan
