$path = "customers\ametek\hkp_rma\ui\rma_claims_dashboard.html"
$content = Get-Content $path -Raw
$scriptStart = $content.LastIndexOf('<script>')
$scriptEnd = $content.LastIndexOf('</script>')
$js = $content.Substring($scriptStart + 8, $scriptEnd - $scriptStart - 8)
$tmp = "$env:TEMP\dashboard_check.js"
[System.IO.File]::WriteAllText($tmp, $js)
node --check $tmp
if ($LASTEXITCODE -eq 0) { Write-Host "OK - JS parses cleanly" -ForegroundColor Green } else { Write-Host "JS PARSE FAILED" -ForegroundColor Red }
Remove-Item $tmp -ErrorAction SilentlyContinue
