$org = "https://org6feab6b5.crm.dynamics.com"
$tok = az account get-access-token --resource $org --query accessToken -o tsv
$h = @{ Authorization = "Bearer $tok"; Accept="application/json"; "OData-Version"="4.0" }

Write-Host "=== rma_emaillog attributes ===" -Fore Cyan
$attrs = Invoke-RestMethod -Uri "$org/api/data/v9.2/EntityDefinitions(LogicalName='rma_emaillog')/Attributes?`$select=LogicalName,AttributeType,DisplayName" -Headers $h
$attrs.value | Where-Object { $_.LogicalName -like 'rma_*' } | Sort-Object LogicalName | Select-Object LogicalName, AttributeType, @{n='Display';e={$_.DisplayName.UserLocalizedLabel.Label}} | Format-Table -AutoSize

Write-Host "`n=== rma_claim attributes (all rma_*) ===" -Fore Cyan
$cattrs = Invoke-RestMethod -Uri "$org/api/data/v9.2/EntityDefinitions(LogicalName='rma_claim')/Attributes?`$select=LogicalName,AttributeType,DisplayName" -Headers $h
$cattrs.value | Where-Object { $_.LogicalName -like 'rma_*' } | Sort-Object LogicalName | Select-Object LogicalName, AttributeType, @{n='Display';e={$_.DisplayName.UserLocalizedLabel.Label}} | Format-Table -AutoSize

Write-Host "`n=== Sample claim with all fields ===" -Fore Cyan
$rs = Invoke-RestMethod -Uri "$org/api/data/v9.2/rma_claims?`$top=1&`$orderby=createdon desc" -Headers @{Authorization="Bearer $tok"; Accept="application/json"; "OData-Version"="4.0"; "Prefer"='odata.include-annotations="OData.Community.Display.V1.FormattedValue"'}
$rs.value[0] | Format-List
