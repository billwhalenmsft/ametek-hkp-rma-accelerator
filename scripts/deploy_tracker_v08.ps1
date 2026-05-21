$org='https://org6feab6b5.crm.dynamics.com'
$token=az account get-access-token --resource $org --query accessToken -o tsv
$hg=@{Authorization="Bearer $token";Accept='application/json'}
$hp=@{Authorization="Bearer $token";Accept='application/json';'Content-Type'='application/json; charset=utf-8';'If-Match'='*'}
$wrId='b3e04439-304e-f111-bec6-000d3a5aed87'
$path='customers\ametek\hkp_rma\ui\rma_pizza_tracker.html'

$bytes=[System.IO.File]::ReadAllBytes($path)
$b64=[Convert]::ToBase64String($bytes)
Write-Host "File size: $($bytes.Length) bytes"

$body=@{content=$b64}|ConvertTo-Json
try {
  Invoke-WebRequest -Uri "$org/api/data/v9.2/webresourceset($wrId)" -Method Patch -Headers $hp -Body $body -UseBasicParsing -ErrorAction Stop | Out-Null
  Write-Host "WR patched OK"
} catch {
  Write-Host "PATCH ERR: $($_.ErrorDetails.Message)"
  exit 1
}

$px="<importexportxml><webresources><webresource>{$wrId}</webresource></webresources></importexportxml>"
Invoke-WebRequest -Uri "$org/api/data/v9.2/PublishXml" -Method Post -Headers $hp -Body (@{ParameterXml=$px}|ConvertTo-Json) -UseBasicParsing -ErrorAction Stop | Out-Null
Write-Host "Published"
