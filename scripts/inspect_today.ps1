$org='https://org6feab6b5.crm.dynamics.com'
$token=az account get-access-token --resource $org --query accessToken -o tsv
$h=@{Authorization="Bearer $token";Accept='application/json'}

$claimId='3d911961-6454-f111-a825-0022480a5e8d'

Write-Host "=== ALL annotations created today ==="
$today=(Get-Date).ToString('yyyy-MM-dd')
$notes=Invoke-RestMethod -Uri "$org/api/data/v9.2/annotations?`$filter=createdon ge $today&`$orderby=createdon desc&`$top=20&`$select=subject,_objectid_value,objecttypecode,createdon" -Headers $h
Write-Host "Count: $($notes.value.Count)"
$notes.value | Format-Table createdon, subject, objecttypecode, _objectid_value -AutoSize

Write-Host "`n=== ALL emails created today ==="
$emails=Invoke-RestMethod -Uri "$org/api/data/v9.2/emails?`$filter=createdon ge $today&`$orderby=createdon desc&`$top=20&`$select=subject,statecode,statuscode,torecipients,_regardingobjectid_value,createdon" -Headers $h
Write-Host "Count: $($emails.value.Count)"
$emails.value | Format-Table createdon, subject, statecode, statuscode, torecipients -AutoSize

Write-Host "`n=== Approval history created today ==="
$ah=Invoke-RestMethod -Uri "$org/api/data/v9.2/rma_approvalhistories?`$filter=createdon ge $today&`$orderby=createdon desc&`$top=20&`$select=rma_name,rma_action,_rma_claim_value,createdon" -Headers $h
Write-Host "Count: $($ah.value.Count)"
$ah.value | Format-Table createdon, rma_name, rma_action -AutoSize
