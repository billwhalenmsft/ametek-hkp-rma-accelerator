$path = "customers\ametek\hkp_rma\ui\rma_claim_smart_insights.html"
$content = Get-Content $path -Raw
$scriptStart = $content.LastIndexOf('<script>')
$scriptEnd = $content.LastIndexOf('</script>')
$js = $content.Substring($scriptStart + 8, $scriptEnd - $scriptStart - 8)
$tmp = "$env:TEMP\insights_check.js"
[System.IO.File]::WriteAllText($tmp, $js)
node --check $tmp
if ($LASTEXITCODE -eq 0) { Write-Host "OK - JS parses cleanly" -ForegroundColor Green } else { Write-Host "JS PARSE FAILED" -ForegroundColor Red; exit 1 }
Remove-Item $tmp -ErrorAction SilentlyContinue
Write-Host "File size: $((Get-Item $path).Length) bytes"
