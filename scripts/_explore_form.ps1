$file = Get-ChildItem "customers\ametek\hkp_rma\backup\rma_claim_form_*.xml" | Sort-Object LastWriteTime -Descending | Select-Object -First 1
Write-Host "Form file: $($file.FullName)"
$xml = [xml](Get-Content $file.FullName -Raw)
Write-Host "`n=== Tabs ===" -ForegroundColor Cyan
$xml.form.tabs.tab | ForEach-Object {
    $tab = $_
    $lbl = $null
    if ($tab.labels.label) {
        $lblItems = $tab.labels.label
        if ($lblItems -is [array]) { $lbl = $lblItems[0].description } else { $lbl = $lblItems.description }
    }
    Write-Host "Tab: id=$($tab.id) name=$($tab.name) label='$lbl' visible=$($tab.visible)" -ForegroundColor Yellow
    $tab.columns.column.sections.section | ForEach-Object {
        $sec = $_
        $slbl = $null
        if ($sec.labels.label) {
            $sl = $sec.labels.label
            if ($sl -is [array]) { $slbl = $sl[0].description } else { $slbl = $sl.description }
        }
        Write-Host "  Section: id=$($sec.id) name=$($sec.name) label='$slbl' columns=$($sec.columns) visible=$($sec.visible)" -ForegroundColor Green
        $sec.rows.row | ForEach-Object {
            $row = $_
            $row.cell | ForEach-Object {
                if ($_) {
                    $ctl = $_.control
                    $dt = $ctl.datafieldname
                    $cid = $ctl.classid
                    $cellLbl = $null
                    if ($_.labels.label) {
                        $cl = $_.labels.label
                        if ($cl -is [array]) { $cellLbl = $cl[0].description } else { $cellLbl = $cl.description }
                    }
                    Write-Host "    Cell rowspan=$($_.rowspan) colspan=$($_.colspan) field=$dt label='$cellLbl' classid=$cid"
                }
            }
        }
    }
}
Write-Host "`n=== Header ===" -ForegroundColor Cyan
if ($xml.form.header) {
    $xml.form.header.rows.row | ForEach-Object {
        $_.cell | ForEach-Object { if ($_) { Write-Host "  $($_.control.datafieldname)" } }
    }
}
