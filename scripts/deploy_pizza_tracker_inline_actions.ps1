param(
    [string]$OrgUrl = "https://org6feab6b5.crm.dynamics.com",
    [string]$SolutionUniqueName = "RMAReturnsMonitor",
    [int]$TrackerRowSpan = 4
)

$ErrorActionPreference = "Stop"

$root = Resolve-Path (Join-Path $PSScriptRoot "..\..\..\..")
$trackerPath = Join-Path $root "customers\ametek\hkp_rma\ui\rma_pizza_tracker.html"
if (-not (Test-Path $trackerPath)) { throw "Tracker source not found: $trackerPath" }

$token = az account get-access-token --resource $OrgUrl --query accessToken -o tsv
$hdr = @{
    Authorization = "Bearer $token"
    Accept = "application/json"
    "Content-Type" = "application/json; charset=utf-8"
    "OData-MaxVersion" = "4.0"
    "OData-Version" = "4.0"
    "MSCRM.SolutionUniqueName" = $SolutionUniqueName
}
$getHdr = @{ Authorization = "Bearer $token"; Accept = "application/json" }

Write-Host "Uploading pizza tracker web resource..." -ForegroundColor Cyan
$wrName = "rma_/pizzatracker/rma_pizza_tracker.html"
$html = [System.IO.File]::ReadAllText($trackerPath)
$b64 = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($html))
$existing = (Invoke-RestMethod -Uri "$OrgUrl/api/data/v9.2/webresourceset?`$filter=name eq '$wrName'&`$select=webresourceid,name" -Headers $getHdr).value
if ($existing.Count -gt 0) {
    $wrId = $existing[0].webresourceid
    $patchHdr = $hdr.Clone(); $patchHdr["If-Match"] = "*"
    Invoke-RestMethod -Method Patch -Uri "$OrgUrl/api/data/v9.2/webresourceset($wrId)" -Headers $patchHdr -Body (@{ content = $b64; displayname = "RMA Pizza Tracker" } | ConvertTo-Json -Compress) | Out-Null
    Write-Host "  Updated $wrName -> $wrId" -ForegroundColor Green
} else {
    $resp = Invoke-WebRequest -Uri "$OrgUrl/api/data/v9.2/webresourceset" -Method Post -Headers $hdr -Body (@{
        name = $wrName
        displayname = "RMA Pizza Tracker"
        webresourcetype = 1
        content = $b64
        description = "Compact claim tracker with inline actions and template email shortcuts."
        languagecode = 1033
    } | ConvertTo-Json -Compress)
    $loc = $resp.Headers['OData-EntityId']
    if ($loc -is [array]) { $loc = $loc[0] }
    if ($loc -match '\(([0-9a-fA-F-]{36})\)') { $wrId = $matches[1] }
    Write-Host "  Created $wrName -> $wrId" -ForegroundColor Green
}

$pubWr = @{ ParameterXml = "<importexportxml><webresources><webresource>{$wrId}</webresource></webresources></importexportxml>" } | ConvertTo-Json -Compress
Invoke-RestMethod -Method Post -Uri "$OrgUrl/api/data/v9.2/PublishXml" -Headers $hdr -Body $pubWr | Out-Null
Write-Host "  Published web resource" -ForegroundColor Green

Write-Host "`nPatching live rma_claim main form(s)..." -ForegroundColor Cyan
$forms = (Invoke-RestMethod -Uri "$OrgUrl/api/data/v9.2/systemforms?`$filter=objecttypecode eq 'rma_claim' and type eq 2&`$select=name,formid,formactivationstate,formxml" -Headers $getHdr).value
if (-not $forms) { throw "No rma_claim main forms found." }

$backupDir = Join-Path $root "customers\ametek\hkp_rma\backup"
if (-not (Test-Path $backupDir)) { New-Item -ItemType Directory -Path $backupDir | Out-Null }

$patchedAny = $false
foreach ($form in $forms) {
    if ($form.formxml -notmatch [regex]::Escape($wrName)) { continue }
    $safe = ($form.name -replace '[^a-zA-Z0-9_]', '_')
    $stamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $backupPath = Join-Path $backupDir ("rma_claim_form_{0}_{1}_PRE_PIZZA_INLINE.xml" -f $safe, $stamp)
    [System.IO.File]::WriteAllText($backupPath, $form.formxml)

    [xml]$xml = $form.formxml
    $controls = $xml.SelectNodes("//control[parameters/Url='rma_/pizzatracker/rma_pizza_tracker.html']")
    if (-not $controls -or $controls.Count -eq 0) { continue }

    foreach ($control in $controls) {
        $params = $control.SelectSingleNode("parameters")
        if ($params) {
            $scroll = $params.SelectSingleNode("Scrolling")
            if ($scroll) { $scroll.InnerText = "no" }
        }
        $cell = $control.ParentNode
        if ($cell -and $cell.Name -eq "cell") {
            $null = $cell.SetAttribute("rowspan", [string]$TrackerRowSpan)
            $rowsNode = $cell.ParentNode.ParentNode
            if ($rowsNode -and $rowsNode.Name -eq "rows") {
                while ($rowsNode.SelectNodes("row").Count -gt $TrackerRowSpan) {
                    $last = $rowsNode.SelectNodes("row")[$rowsNode.SelectNodes("row").Count - 1]
                    [void]$rowsNode.RemoveChild($last)
                }
                while ($rowsNode.SelectNodes("row").Count -lt $TrackerRowSpan) {
                    $newRow = $xml.CreateElement("row")
                    [void]$rowsNode.AppendChild($newRow)
                }
            }
        }
    }

    $patchHdr = $hdr.Clone(); $patchHdr["If-Match"] = "*"
    Invoke-RestMethod -Method Patch -Uri "$OrgUrl/api/data/v9.2/systemforms($($form.formid))" -Headers $patchHdr -Body (@{ formxml = $xml.OuterXml } | ConvertTo-Json -Compress) | Out-Null
    Write-Host "  Patched form: $($form.name) ($($form.formid))" -ForegroundColor Green
    Write-Host "    Backup: $backupPath" -ForegroundColor DarkGray
    $patchedAny = $true
}

if ($patchedAny) {
    $pubEntity = @{ ParameterXml = "<importexportxml><entities><entity>rma_claim</entity></entities></importexportxml>" } | ConvertTo-Json -Compress
    Invoke-RestMethod -Method Post -Uri "$OrgUrl/api/data/v9.2/PublishXml" -Headers $hdr -Body $pubEntity | Out-Null
    Write-Host "  Published rma_claim form changes" -ForegroundColor Green
} else {
    Write-Host "  No matching form found to patch. Web resource still updated." -ForegroundColor Yellow
}

Write-Host "`nDone. Hard refresh the claim form (Ctrl+F5)." -ForegroundColor Cyan