$org='https://org6feab6b5.crm.dynamics.com'
$token=az account get-access-token --resource $org --query accessToken -o tsv
$h=@{Authorization="Bearer $token";Accept='application/json';'Content-Type'='application/json'}
$formId='edc4d9dc-4854-4df6-a2ba-efa9031afe3f'
$cur=Invoke-RestMethod -Uri "$org/api/data/v9.2/systemforms($formId)?`$select=formxml" -Headers $h
$anchor='datafieldname="ownerid" /></cell></row>'
$one='<row><cell id="{b1000001-0001-0001-0001-000000000099}"><labels><label description="Subject" languagecode="1033" /></labels><control id="rma_subject" classid="{4273EDBD-AC1D-40d3-9FB2-095C621B552D}" datafieldname="rma_subject" /></cell></row>'
$new=$cur.formxml.Replace($anchor,$anchor+$one)
Write-Host "changed: $($new -ne $cur.formxml)"
$body=@{formxml=$new}|ConvertTo-Json -Depth 5
try {
  Invoke-RestMethod -Uri "$org/api/data/v9.2/systemforms($formId)" -Method Patch -Headers $h -Body $body -ErrorAction Stop
  Write-Host "patched OK"
} catch {
  Write-Host "ERROR: $($_.Exception.Message)"
  Write-Host $_.ErrorDetails.Message
  exit 1
}
$verify=Invoke-RestMethod -Uri "$org/api/data/v9.2/systemforms($formId)?`$select=formxml" -Headers $h
Write-Host "contains rma_subject after PATCH: $($verify.formxml.Contains('rma_subject'))"
Write-Host "new length: $($verify.formxml.Length) (was $($cur.formxml.Length))"
