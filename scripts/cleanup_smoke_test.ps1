$OrgUrl = "https://org6feab6b5.crm.dynamics.com"
$token = (az account get-access-token --resource $OrgUrl --query accessToken -o tsv)
$h = @{ Authorization = "Bearer $token"; Accept = "application/json" }

Write-Host "=== Delete leftover smoke test approval records ==="
foreach ($id in @("b30f291d-1850-f111-a824-0022480a5e8d", "6118f904-1850-f111-a824-0022480a5e8d")) {
    try {
        Invoke-WebRequest -Method DELETE -Uri "$OrgUrl/api/data/v9.2/rma_approvalrecords($id)" -Headers $h -UseBasicParsing | Out-Null
        Write-Host "  deleted $id"
    } catch {
        Write-Host "  delete failed for $id"
    }
}
