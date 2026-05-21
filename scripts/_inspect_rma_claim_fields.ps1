$orgUrl="https://org6feab6b5.crm.dynamics.com"
$token=(az account get-access-token --resource $orgUrl --query accessToken -o tsv)
$h=@{Authorization="Bearer $token"; Accept="application/json"}

Write-Host "=== rma_claim attributes (filtered) ==="
$attrs=(Invoke-RestMethod -Uri "$orgUrl/api/data/v9.2/EntityDefinitions(LogicalName='rma_claim')/Attributes?`$select=LogicalName,SchemaName,AttributeType,IsCustomAttribute" -Headers $h).value
$attrs | Where-Object { $_.LogicalName -like '*plant*' -or $_.LogicalName -like '*customer*' -or $_.LogicalName -like '*part*' -or $_.LogicalName -like '*claim*' -or $_.LogicalName -like '*credit*' -or $_.LogicalName -like '*status*' -or $_.LogicalName -like '*pending*' -or $_.LogicalName -like '*age*' -or $_.LogicalName -like '*closed*' } | Sort-Object LogicalName | Format-Table LogicalName,AttributeType -AutoSize

Write-Host "`n=== ALL rma_claim attribute logical names (compact) ==="
$attrs | Sort-Object LogicalName | ForEach-Object { "  $($_.LogicalName)  ($($_.AttributeType))" }
