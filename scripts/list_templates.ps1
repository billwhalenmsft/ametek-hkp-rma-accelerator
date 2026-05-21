$org='https://org6feab6b5.crm.dynamics.com'
$token=az account get-access-token --resource $org --query accessToken -o tsv
$h=@{Authorization="Bearer $token";Accept='application/json'}

$tpls=Invoke-RestMethod -Uri "$org/api/data/v9.2/rma_emailtemplates?`$select=rma_name,rma_subject,rma_templatetype,rma_isactive,rma_triggerstatus,rma_triggerresolution&`$orderby=rma_name" -Headers $h
Write-Host "Total templates: $($tpls.value.Count)"
Write-Host ""
$tpls.value | Format-Table rma_name, rma_isactive, rma_templatetype, rma_triggerstatus, rma_triggerresolution -AutoSize -Wrap
