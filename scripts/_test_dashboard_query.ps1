$orgUrl="https://org6feab6b5.crm.dynamics.com"
$token=(az account get-access-token --resource $orgUrl --query accessToken -o tsv)
$h=@{Authorization="Bearer $token"; Accept="application/json"; Prefer='odata.include-annotations="OData.Community.Display.V1.FormattedValue"'}
$q='$select=rma_claimid,rma_claimnumber,rma_customername,rma_partnumber,_rma_assignedplant_value,rma_status,rma_creditamount,rma_haspendingresponse,createdon,rma_closeddate,statecode&$orderby=createdon desc&$top=10'
$r=(Invoke-RestMethod -Uri "$orgUrl/api/data/v9.2/rma_claims?$q" -Headers $h)
Write-Host "Returned $($r.value.Count) claims (top 10)"
$r.value | Select-Object rma_claimnumber, rma_customername, rma_partnumber, @{n='plant';e={$_.'_rma_assignedplant_value@OData.Community.Display.V1.FormattedValue'}}, @{n='status';e={$_.'rma_status@OData.Community.Display.V1.FormattedValue'}}, rma_creditamount | Format-Table -AutoSize
