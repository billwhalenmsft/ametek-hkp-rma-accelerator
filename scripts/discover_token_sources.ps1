#requires -Version 7
$ErrorActionPreference = "Stop"
$org = "https://org6feab6b5.crm.dynamics.com"
$token = (az account get-access-token --resource $org --query accessToken -o tsv).Trim()
$h = @{ Authorization = "Bearer $token"; Accept = "application/json" }
$hFmt = @{ Authorization = "Bearer $token"; Accept = "application/json"; Prefer = 'odata.include-annotations="OData.Community.Display.V1.FormattedValue"' }

Write-Host "=== rma_claim attributes (filtered) ===" -ForegroundColor Cyan
$attrs = Invoke-RestMethod -Uri "$org/api/data/v9.2/EntityDefinitions(LogicalName='rma_claim')/Attributes?`$select=LogicalName,DisplayName,AttributeType,IsValidForRead" -Headers $h
$attrs.value | Where-Object { $_.LogicalName -match 'customer|contact|status|account|account|sender|email' -and $_.IsValidForRead -eq $true } | Sort-Object LogicalName | ForEach-Object {
  "  $($_.LogicalName) [$($_.AttributeType)] :: $($_.DisplayName.UserLocalizedLabel.Label)"
}

Write-Host "`n=== Sample claim (full record) ===" -ForegroundColor Cyan
$c = Invoke-RestMethod -Uri "$org/api/data/v9.2/rma_claims?`$top=1" -Headers $hFmt
$c.value[0].PSObject.Properties | Where-Object { $_.Value -and $_.Name -notmatch '^_.+_value$|^@|owninguser|owningteam|owningbusinessunit|importsequencenumber|timezoneruleversionnumber|utcconversiontimezonecode|overriddencreatedon|versionnumber' } | Sort-Object Name | ForEach-Object { "  $($_.Name) = $($_.Value)" }

Write-Host "`n=== rma_emaillog attributes (filtered) ===" -ForegroundColor Cyan
$eattrs = Invoke-RestMethod -Uri "$org/api/data/v9.2/EntityDefinitions(LogicalName='rma_emaillog')/Attributes?`$select=LogicalName,DisplayName,AttributeType,IsValidForRead" -Headers $h
$eattrs.value | Where-Object { $_.LogicalName -match 'from|sender|customer|name|contact' -and $_.IsValidForRead -eq $true } | Sort-Object LogicalName | ForEach-Object {
  "  $($_.LogicalName) [$($_.AttributeType)] :: $($_.DisplayName.UserLocalizedLabel.Label)"
}
