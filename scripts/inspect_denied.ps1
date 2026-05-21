$org='https://org6feab6b5.crm.dynamics.com'
$token=az account get-access-token --resource $org --query accessToken -o tsv
$h=@{Authorization="Bearer $token";Accept='application/json'}

# Find claims where resolution = Claim Denied (100000003)
$claims=Invoke-RestMethod -Uri "$org/api/data/v9.2/rma_claims?`$filter=rma_resolution eq 100000003&`$orderby=modifiedon desc&`$top=10&`$select=rma_claimid,rma_claimnumber,rma_status,statecode,statuscode,modifiedon,rma_customeremail" -Headers $h
Write-Host "Claims with Resolution=Claim Denied: $($claims.value.Count)"
$claims.value | Format-Table rma_claimnumber, rma_status, statecode, modifiedon, rma_customeremail -AutoSize

if ($claims.value.Count -gt 0) {
  $c = $claims.value[0]
  Write-Host "`n=== Most recent denied claim: $($c.rma_claimnumber) ($($c.rma_claimid)) ==="

  $notes=Invoke-RestMethod -Uri "$org/api/data/v9.2/annotations?`$filter=_objectid_value eq $($c.rma_claimid)&`$orderby=createdon desc&`$select=subject,notetext,createdon" -Headers $h
  Write-Host "`nAnnotations: $($notes.value.Count)"
  $notes.value | Format-Table createdon, subject -AutoSize

  $emails=Invoke-RestMethod -Uri "$org/api/data/v9.2/emails?`$filter=_regardingobjectid_value eq $($c.rma_claimid)&`$orderby=createdon desc&`$select=subject,statecode,statuscode,directioncode,createdon,torecipients" -Headers $h
  Write-Host "`nEmails: $($emails.value.Count)"
  $emails.value | Format-Table createdon, subject, statecode, statuscode, torecipients -AutoSize
}
