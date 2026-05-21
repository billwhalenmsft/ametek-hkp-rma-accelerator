$org='https://org6feab6b5.crm.dynamics.com'
$token=az account get-access-token --resource $org --query accessToken -o tsv
$hg=@{Authorization="Bearer $token";Accept='application/json'}
$hp=@{Authorization="Bearer $token";Accept='application/json';'Content-Type'='application/json; charset=utf-8';'If-Match'='*';'MSCRM.SolutionUniqueName'='RMAReturnsMonitor'}
$formId='edc4d9dc-4854-4df6-a2ba-efa9031afe3f'

Write-Host "=== Test 1: rename form to confirm PATCH works at all ==="
$body=@{name='InformationTEST'}|ConvertTo-Json
try { Invoke-WebRequest -Uri "$org/api/data/v9.2/systemforms($formId)" -Method Patch -Headers $hp -Body $body -UseBasicParsing -ErrorAction Stop | Out-Null } catch { Write-Host "rename failed: $($_.ErrorDetails.Message)" }
$v=Invoke-RestMethod -Uri "$org/api/data/v9.2/systemforms($formId)?`$select=name" -Headers $hg
Write-Host "Name now: $($v.name)"
try { Invoke-WebRequest -Uri "$org/api/data/v9.2/systemforms($formId)" -Method Patch -Headers $hp -Body (@{name='Information'}|ConvertTo-Json) -UseBasicParsing -ErrorAction Stop | Out-Null } catch {}

Write-Host "`n=== Test 2: add a single string field row, no colspan ==="
$cur=Invoke-RestMethod -Uri "$org/api/data/v9.2/systemforms($formId)?`$select=formxml" -Headers $hg
$anchor='datafieldname="ownerid" /></cell></row>'
$one='<row><cell id="{99999991-9991-9991-9991-999999999991}"><labels><label description="Subject" languagecode="1033" /></labels><control id="rma_subject" classid="{4273EDBD-AC1D-40d3-9FB2-095C621B552D}" datafieldname="rma_subject" /></cell></row>'
$new=$cur.formxml.Replace($anchor,$anchor+$one)
$body=@{formxml=$new}|ConvertTo-Json -Depth 5 -Compress
try { Invoke-WebRequest -Uri "$org/api/data/v9.2/systemforms($formId)" -Method Patch -Headers $hp -Body $body -UseBasicParsing -ErrorAction Stop | Out-Null; Write-Host "PATCH ok" } catch { Write-Host "PATCH ERR: $($_.ErrorDetails.Message)" }
$v=Invoke-RestMethod -Uri "$org/api/data/v9.2/systemforms($formId)?`$select=formxml" -Headers $hg
Write-Host "After: contains rma_subject: $($v.formxml.Contains('rma_subject'))  len: $($v.formxml.Length)"
