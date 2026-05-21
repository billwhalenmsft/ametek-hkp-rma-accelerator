# Backup the rma_claim main form XML (read-only safety net for future form edits)
param(
    [string]$OrgUrl = "https://org6feab6b5.crm.dynamics.com",
    [string]$OutDir = "customers/ametek/hkp_rma/backup"
)
$ErrorActionPreference = "Stop"
$token = az account get-access-token --resource $OrgUrl --query accessToken -o tsv
$h = @{ Authorization = "Bearer $token"; Accept = "application/json" }

if (-not (Test-Path $OutDir)) { New-Item -ItemType Directory -Path $OutDir | Out-Null }

# Get the Main form (type=2) for rma_claim
$forms = (Invoke-RestMethod -Uri "$OrgUrl/api/data/v9.2/systemforms?`$filter=objecttypecode eq 'rma_claim' and type eq 2&`$select=name,formid,type,formactivationstate,formxml" -Headers $h).value

if (-not $forms) { Write-Host "No main forms found for rma_claim"; exit 1 }

$ts = Get-Date -Format "yyyyMMdd_HHmmss"
foreach ($f in $forms) {
    $safe = ($f.name -replace '[^a-zA-Z0-9_]', '_')
    $outPath = Join-Path $OutDir "rma_claim_form_${safe}_${ts}.xml"
    [System.IO.File]::WriteAllText((Resolve-Path $OutDir).Path + "\rma_claim_form_${safe}_${ts}.xml", $f.formxml)
    Write-Host "  backed up: $($f.name) (formid=$($f.formid))"
    Write-Host "    -> $outPath"
}
Write-Host ""
Write-Host "Done. To restore a form: PATCH /systemforms({formid}) with body {""formxml"":""<contents>""}"
