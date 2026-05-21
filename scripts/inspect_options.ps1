$org='https://org6feab6b5.crm.dynamics.com'
$token=az account get-access-token --resource $org --query accessToken -o tsv
$h=@{Authorization="Bearer $token";Accept='application/json'}

$m=Invoke-RestMethod -Uri "$org/api/data/v9.2/EntityDefinitions(LogicalName='rma_claim')/Attributes(LogicalName='rma_status')/Microsoft.Dynamics.CRM.PicklistAttributeMetadata?`$expand=OptionSet" -Headers $h
Write-Host "rma_status options:"
$m.OptionSet.Options | ForEach-Object { "  $($_.Value): $($_.Label.UserLocalizedLabel.Label)" }

$mr=Invoke-RestMethod -Uri "$org/api/data/v9.2/EntityDefinitions(LogicalName='rma_claim')/Attributes(LogicalName='rma_resolution')/Microsoft.Dynamics.CRM.PicklistAttributeMetadata?`$expand=OptionSet" -Headers $h
Write-Host "`nrma_resolution options:"
$mr.OptionSet.Options | ForEach-Object { "  $($_.Value): $($_.Label.UserLocalizedLabel.Label)" }
