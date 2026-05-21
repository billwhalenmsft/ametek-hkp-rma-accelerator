$orgUrl="https://org6feab6b5.crm.dynamics.com"
$token=(az account get-access-token --resource $orgUrl --query accessToken -o tsv)
$h=@{Authorization="Bearer $token"; Accept="application/json"}
$wrName="rma_/board/claims_board.html"
$existing=(Invoke-RestMethod -Uri "$orgUrl/api/data/v9.2/webresourceset?`$filter=name eq '$wrName'&`$select=webresourceid,displayname,name,webresourcetype,modifiedon" -Headers $h).value
if ($existing) {
    $existing | Format-List webresourceid,displayname,name,webresourcetype,modifiedon
    $full=(Invoke-RestMethod -Uri "$orgUrl/api/data/v9.2/webresourceset($($existing[0].webresourceid))?`$select=content" -Headers $h)
    $bytes=[Convert]::FromBase64String($full.content)
    Write-Host "Content size: $($bytes.Length) bytes"
    $bk = "customers\ametek\hkp_rma\backup\original_claims_board_$(Get-Date -Format 'yyyyMMdd_HHmmss').html"
    [System.IO.File]::WriteAllBytes($bk, $bytes)
    Write-Host "Backup: $bk"
    $text=[System.Text.Encoding]::UTF8.GetString($bytes)
    Write-Host "`n=== First 500 chars ==="
    Write-Host $text.Substring(0, [Math]::Min(500, $text.Length))
} else {
    Write-Host "Web resource '$wrName' not found"
}
