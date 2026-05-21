$org='https://org6feab6b5.crm.dynamics.com'
$token=az account get-access-token --resource $org --query accessToken -o tsv
$h=@{Authorization="Bearer $token";Accept='application/json';'Content-Type'='application/json';'OData-Version'='4.0';'OData-MaxVersion'='4.0'}
$hp=@{Authorization="Bearer $token";Accept='application/json';'Content-Type'='application/json; charset=utf-8';'If-Match'='*';'MSCRM.SolutionUniqueName'='RMAReturnsMonitor'}
$formId='edc4d9dc-4854-4df6-a2ba-efa9031afe3f'

$current=Invoke-RestMethod -Uri "$org/api/data/v9.2/systemforms($formId)?`$select=formxml" -Headers $h
$xml=$current.formxml

$ownerEnd='datafieldname="ownerid" /></cell></row>'
if ($xml -notmatch [regex]::Escape($ownerEnd)) { Write-Host "Anchor not found" -ForegroundColor Red; exit 1 }

$newRows = '<row><cell id="{a1000001-0001-0001-0001-000000000001}"><labels><label description="Template Type" languagecode="1033" /></labels><control id="rma_templatetype" classid="{3EF39988-22BB-4f0b-BBBE-64B5A3748AEE}" datafieldname="rma_templatetype" /></cell></row>'
$newRows += '<row><cell id="{a1000001-0001-0001-0001-000000000002}"><labels><label description="Active" languagecode="1033" /></labels><control id="rma_isactive" classid="{67FAC785-CD58-4f9f-ABB3-4B7DDC6ED5ED}" datafieldname="rma_isactive" /></cell></row>'
$newRows += '<row><cell id="{a1000001-0001-0001-0001-000000000003}"><labels><label description="Trigger Status" languagecode="1033" /></labels><control id="rma_triggerstatus" classid="{4273EDBD-AC1D-40d3-9FB2-095C621B552D}" datafieldname="rma_triggerstatus" /></cell></row>'
$newRows += '<row><cell id="{a1000001-0001-0001-0001-000000000004}"><labels><label description="Trigger Resolution" languagecode="1033" /></labels><control id="rma_triggerresolution" classid="{4273EDBD-AC1D-40d3-9FB2-095C621B552D}" datafieldname="rma_triggerresolution" /></cell></row>'
$newRows += '<row><cell colspan="2" id="{a1000001-0001-0001-0001-000000000005}"><labels><label description="Subject" languagecode="1033" /></labels><control id="rma_subject" classid="{4273EDBD-AC1D-40d3-9FB2-095C621B552D}" datafieldname="rma_subject" /></cell></row>'
$newRows += '<row><cell colspan="2" rowspan="10" id="{a1000001-0001-0001-0001-000000000006}"><labels><label description="Body" languagecode="1033" /></labels><control id="rma_body" classid="{E0DECE4B-6FC8-4a8f-A065-082708572369}" datafieldname="rma_body" /></cell></row>'

$newXml = $xml.Replace($ownerEnd, ($ownerEnd + $newRows))
if ($newXml -eq $xml) { Write-Host "Replacement did not change xml" -ForegroundColor Red; exit 1 }

$body=@{formxml=$newXml}|ConvertTo-Json -Depth 5
try {
  Invoke-RestMethod -Uri "$org/api/data/v9.2/systemforms($formId)" -Method Patch -Headers $hp -Body $body -ErrorAction Stop
  Write-Host "Form patched" -ForegroundColor Green
} catch {
  Write-Host "PATCH FAILED:" -ForegroundColor Red
  Write-Host $_.ErrorDetails.Message
  exit 1
}

$px="<importexportxml><systemforms><systemform>{$formId}</systemform></systemforms></importexportxml>"
Invoke-RestMethod -Uri "$org/api/data/v9.2/PublishXml" -Method Post -Headers $h -Body (@{ParameterXml=$px}|ConvertTo-Json)
Write-Host "Form published" -ForegroundColor Green
