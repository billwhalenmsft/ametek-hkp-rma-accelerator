# Patch the rma_claim main form:
#   1. Bump Pizza Tracker (BPF) rowspan from 2 to 6 to fix cutoff
#   2. Add new "Smart Insights" section after Progress (web resource: rma_/board/smart_insights.html)
#   3. Merge "Customer & Part" + "Plant & Status" sections into single "Claim Details" section
#
# Run:
#   - Pre-req: Smart Insights web resource must already exist (deploy_smart_insights_webresource.ps1)
#   - This script PATCHes the live form, publishes, and verifies
param(
    [string]$OrgUrl = "https://org6feab6b5.crm.dynamics.com",
    [string]$FormId = "05a92f92-94cc-4a07-9ba0-f704788c699c",
    [string]$SmartInsightsWrName = "rma_/board/smart_insights.html",
    [string]$SmartInsightsWrId   = ""   # if blank, will look up by name
)
$ErrorActionPreference = "Stop"
$token = az account get-access-token --resource $OrgUrl --query accessToken -o tsv
$h = @{
    Authorization     = "Bearer $token"
    Accept            = "application/json"
    "Content-Type"    = "application/json"
    "OData-MaxVersion"= "4.0"
    "OData-Version"   = "4.0"
}

# 1. Look up smart insights web resource id if not given
if (-not $SmartInsightsWrId) {
    $r = (Invoke-RestMethod -Uri "$OrgUrl/api/data/v9.2/webresourceset?`$filter=name eq '$SmartInsightsWrName'&`$select=webresourceid" -Headers $h).value
    if ($r.Count -eq 0) { throw "Smart Insights web resource not found: $SmartInsightsWrName. Deploy it first." }
    $SmartInsightsWrId = $r[0].webresourceid
}
Write-Host "Smart Insights webresource id: $SmartInsightsWrId" -ForegroundColor Cyan

# 2. Backup current form XML
Write-Host "Fetching current form XML..."
$f = (Invoke-RestMethod -Uri "$OrgUrl/api/data/v9.2/systemforms($FormId)?`$select=name,formxml" -Headers $h)
$ts = Get-Date -Format "yyyyMMdd_HHmmss"
$bk = "customers\ametek\hkp_rma\backup\rma_claim_form_${ts}_PRE_PATCH.xml"
[System.IO.File]::WriteAllText((Resolve-Path "customers\ametek\hkp_rma\backup").Path + "\rma_claim_form_${ts}_PRE_PATCH.xml", $f.formxml)
Write-Host "  backup: $bk" -ForegroundColor DarkGray

# 3. Build the new sections (raw XML - keep on single line for FormXML compatibility)
$smartInsightsSection = @"
<section showlabel="true" showbar="true" id="{a1b2c3d4-e5f6-7890-abcd-ef0123456789}" columns="1" labelwidth="115" IsUserDefined="1"><labels><label description="Smart Insights" languagecode="1033" /></labels><rows><row><cell id="{b1b2c3d4-e5f6-7890-abcd-ef0123456789}" showlabel="false" rowspan="14" colspan="1"><labels><label description="Smart Insights" languagecode="1033" /></labels><control id="WebResource_smart_insights" classid="{9FDF5F91-88B1-47F4-AD53-C11EFC01A01D}"><parameters><Url>$SmartInsightsWrName</Url><PassParameters>true</PassParameters><Security>false</Security><Scrolling>auto</Scrolling><Border>false</Border><ShowOnMobileClient>false</ShowOnMobileClient><WebResourceId>{$SmartInsightsWrId}</WebResourceId></parameters></control></cell></row><row /><row /><row /><row /><row /><row /><row /><row /><row /><row /><row /><row /><row /></rows></section>
"@

# Merged "Claim Details" replaces both "Customer & Part" and "Plant & Status"
$claimDetailsSection = @"
<section showlabel="true" showbar="true" id="{2add3a7a-1d0d-40a2-8616-b9efe4b2d39d}" columns="4" labelwidth="115"><labels><label description="Claim Details" languagecode="1033" /></labels><rows><row><cell id="{e2815afd-6042-4ab4-989a-f3a05f5c30d0}" colspan="1" rowspan="1"><labels><label description="Customer Name" languagecode="1033" /></labels><control id="rma_customername" classid="{4273EDBD-AC1D-40d3-9FB2-095C621B552D}" datafieldname="rma_customername" /></cell><cell id="{358d2898-81a3-4f42-bb47-02b021feb8a7}" colspan="1" rowspan="1"><labels><label description="Customer Email" languagecode="1033" /></labels><control id="rma_customeremail" classid="{4273EDBD-AC1D-40d3-9FB2-095C621B552D}" datafieldname="rma_customeremail" /></cell><cell id="{16aded93-c977-400e-b4ab-d654a9448a2e}" colspan="1" rowspan="1"><labels><label description="Customer Region" languagecode="1033" /></labels><control id="rma_customerregion" classid="{3EF39988-22BB-4f0b-BBBE-64B5A3748AEE}" datafieldname="rma_customerregion" /></cell><cell id="{b0d744c0-995e-417b-a225-b96abc0deef6}" colspan="1" rowspan="1"><labels><label description="Contact Name" languagecode="1033" /></labels><control id="rma_contactname" classid="{4273EDBD-AC1D-40d3-9FB2-095C621B552D}" datafieldname="rma_contactname" /></cell></row><row><cell id="{c7392465-af6d-439c-9d2c-0fa529ae96a4}" colspan="1" rowspan="1"><labels><label description="Part Number" languagecode="1033" /></labels><control id="rma_partnumber" classid="{4273EDBD-AC1D-40d3-9FB2-095C621B552D}" datafieldname="rma_partnumber" /></cell><cell id="{7702e57a-e788-434c-bd4c-2fffe2cd9552}" colspan="1" rowspan="1"><labels><label description="Quantity" languagecode="1033" /></labels><control id="rma_quantity" classid="{C6D124CA-7EDA-4a60-AEA9-7FB8D318B68F}" datafieldname="rma_quantity" /></cell><cell id="{15bea34e-091c-46ff-abd6-233fff708d78}" colspan="1" rowspan="1"><labels><label description="Failure Mode" languagecode="1033" /></labels><control id="rma_failuremode" classid="{3EF39988-22BB-4f0b-BBBE-64B5A3748AEE}" datafieldname="rma_failuremode" /></cell><cell id="{186a8c63-1315-4f50-8f1c-e4964976e40a}" colspan="1" rowspan="1"><labels><label description="Assigned Plant" languagecode="1033" /></labels><control id="rma_assignedplant" classid="{270BD3DB-D9AF-4782-9025-509E298DEC0A}" datafieldname="rma_assignedplant" /></cell></row><row><cell id="{9ceabb9d-df71-43ff-8aa0-a0ad9150e1f3}" colspan="1" rowspan="1"><labels><label description="Status" languagecode="1033" /></labels><control id="rma_status" classid="{3EF39988-22BB-4f0b-BBBE-64B5A3748AEE}" datafieldname="rma_status" /></cell><cell id="{9bdca648-b1e6-4feb-9a9b-5cc1c0bc3971}" colspan="1" rowspan="1"><labels><label description="Warranty Status" languagecode="1033" /></labels><control id="rma_warrantystatus" classid="{3EF39988-22BB-4f0b-BBBE-64B5A3748AEE}" datafieldname="rma_warrantystatus" /></cell><cell id="{a4e6d76f-0d14-4ae4-9f97-5d786dc33dbb}" colspan="1" rowspan="1"><labels><label description="Warranty Verified" languagecode="1033" /></labels><control id="rma_warrantyverifieddate" classid="{5B773807-9FB2-42db-97C3-7A91EFF8ADFF}" datafieldname="rma_warrantyverifieddate" /></cell><cell id="{7f4ccb5a-5ec0-4f00-89d4-29980aea47df}" colspan="1" rowspan="1"><labels><label description="Awaiting Customer" languagecode="1033" /></labels><control id="rma_haspendingresponse" classid="{B0C6723A-8503-4fd7-BB28-C8A06AC933C2}" datafieldname="rma_haspendingresponse" /></cell></row><row><cell id="{9e77d370-a8f3-465c-a257-5e103ddd68f0}" colspan="4" rowspan="2"><labels><label description="Failure Description" languagecode="1033" /></labels><control id="rma_failuredescription" classid="{E0DECE4B-6FC8-4a8f-A065-082708572369}" datafieldname="rma_failuredescription" /></cell></row><row /><row><cell id="{056160dd-6498-403f-b74d-d4e7f8b13df2}" colspan="4" rowspan="1"><labels><label description="Source Email ID" languagecode="1033" /></labels><control id="rma_sourceemailid" classid="{4273EDBD-AC1D-40d3-9FB2-095C621B552D}" datafieldname="rma_sourceemailid" /></cell></row></rows></section>
"@

# 4. Transform the FormXML
$xml = $f.formxml

# 4a. Bump BPF cell rowspan from 2 to 6 (and add 4 more <row /> entries to give it height)
$bpfOldCell = '<cell id="{27f58771-f3db-4158-9006-280ac7268cd6}" showlabel="false" rowspan="2" colspan="1">'
$bpfNewCell = '<cell id="{27f58771-f3db-4158-9006-280ac7268cd6}" showlabel="false" rowspan="6" colspan="1">'
if ($xml -notmatch [regex]::Escape($bpfOldCell)) { throw "Could not find BPF cell to patch (rowspan=2)" }
$xml = $xml.Replace($bpfOldCell, $bpfNewCell)

# 4b. Add extra row stubs to BPF section to allow the increased rowspan to render
$bpfOldRows = '<rows><row><cell id="{27f58771-f3db-4158-9006-280ac7268cd6}" showlabel="false" rowspan="6" colspan="1"><labels><label description="Pizza Tracker" languagecode="1033" /></labels><control id="WebResource_pizza_tracker" classid="{9FDF5F91-88B1-47F4-AD53-C11EFC01A01D}"><parameters><Url>rma_/pizzatracker/rma_pizza_tracker.html</Url><PassParameters>false</PassParameters><Security>false</Security><Scrolling>no</Scrolling><Border>false</Border><ShowOnMobileClient>false</ShowOnMobileClient><WebResourceId>{b3e04439-304e-f111-bec6-000d3a5aed87}</WebResourceId></parameters></control></cell></row><row /></rows>'
$bpfNewRows = '<rows><row><cell id="{27f58771-f3db-4158-9006-280ac7268cd6}" showlabel="false" rowspan="6" colspan="1"><labels><label description="Pizza Tracker" languagecode="1033" /></labels><control id="WebResource_pizza_tracker" classid="{9FDF5F91-88B1-47F4-AD53-C11EFC01A01D}"><parameters><Url>rma_/pizzatracker/rma_pizza_tracker.html</Url><PassParameters>false</PassParameters><Security>false</Security><Scrolling>no</Scrolling><Border>false</Border><ShowOnMobileClient>false</ShowOnMobileClient><WebResourceId>{b3e04439-304e-f111-bec6-000d3a5aed87}</WebResourceId></parameters></control></cell></row><row /><row /><row /><row /><row /></rows>'
if ($xml -notmatch [regex]::Escape($bpfOldRows)) {
    Write-Host "WARNING: Could not match BPF section rows exactly. Trying alternate match..." -ForegroundColor Yellow
    # Just add 4 row stubs after the first <row /> in the Progress section
    $xml = $xml -replace '(<section[^>]*id="\{f207ad81-e51f-46c7-a545-d51e28e92698\}"[^>]*>.*?</row><row />)</rows>', '$1<row /><row /><row /><row /></rows>'
} else {
    $xml = $xml.Replace($bpfOldRows, $bpfNewRows)
}

# 4c. Replace the original "Customer & Part" + "Plant & Status" sections with the merged "Claim Details"
# Both old sections start with <section ... id="{2add3a7a..." or "{e7afdcd6..." 
# Strategy: find the start of the Customer & Part section and the END of the Plant & Status section, replace the whole span
$startMarker = '<!-- Customer & Part'
$middleSearch = '<!-- Plant & Status'
$endSearch = '<!-- Resolution'

$startIdx = $xml.IndexOf($startMarker)
$endIdx   = $xml.IndexOf($endSearch)
if ($startIdx -lt 0 -or $endIdx -lt 0) { throw "Could not locate section markers (start=$startIdx end=$endIdx)" }

$before = $xml.Substring(0, $startIdx)
$after = $xml.Substring($endIdx)
$replacement = "<!-- Claim Details (merged Customer & Part + Plant & Status) -->" + $claimDetailsSection.Trim() + "<!-- Smart Insights -->" + $smartInsightsSection.Trim()
$xml = $before + $replacement + $after

# 5. Validate well-formed XML
try {
    $check = [xml]$xml
    Write-Host "  XML validates OK" -ForegroundColor Green
} catch {
    $bad = "customers\ametek\hkp_rma\backup\bad_form_${ts}.xml"
    [System.IO.File]::WriteAllText((Resolve-Path "customers\ametek\hkp_rma\backup").Path + "\bad_form_${ts}.xml", $xml)
    throw "Generated XML is not well-formed. Saved to $bad. Error: $_"
}

# 6. Save the new XML for diffing
$outFile = "customers\ametek\hkp_rma\backup\rma_claim_form_${ts}_NEW.xml"
[System.IO.File]::WriteAllText((Resolve-Path "customers\ametek\hkp_rma\backup").Path + "\rma_claim_form_${ts}_NEW.xml", $xml)
Write-Host "  new xml saved: $outFile" -ForegroundColor DarkGray

# 7. PATCH the form
Write-Host "PATCHing form $FormId..." -ForegroundColor Cyan
$body = @{ formxml = $xml } | ConvertTo-Json -Depth 5
Invoke-WebRequest -Method PATCH -Uri "$OrgUrl/api/data/v9.2/systemforms($FormId)" -Headers $h -Body $body -UseBasicParsing | Out-Null
Write-Host "  patched"

# 8. Publish
Write-Host "Publishing entity..."
$publishXml = "<importexportxml><entities><entity>rma_claim</entity></entities></importexportxml>"
$pubBody = @{ ParameterXml = $publishXml } | ConvertTo-Json
Invoke-WebRequest -Method POST -Uri "$OrgUrl/api/data/v9.2/PublishXml" -Headers $h -Body $pubBody -UseBasicParsing | Out-Null
Write-Host "  published" -ForegroundColor Green

Write-Host ""
Write-Host "Done. Refresh an open RMA Claim form (Ctrl+F5)." -ForegroundColor Cyan
Write-Host "Rollback if needed:" -ForegroundColor DarkGray
Write-Host "  `$old = Get-Content '$bk' -Raw" -ForegroundColor DarkGray
Write-Host "  Invoke-WebRequest -Method PATCH -Uri '$OrgUrl/api/data/v9.2/systemforms($FormId)' -Headers `$h -Body (@{formxml=`$old}|ConvertTo-Json -Depth 5)" -ForegroundColor DarkGray
