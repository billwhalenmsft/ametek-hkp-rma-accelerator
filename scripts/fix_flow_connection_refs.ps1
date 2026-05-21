# fix_flow_connection_refs.ps1
#
# RMA Auto-Assign Plant and RMA Stage Tracker reference connection
# `msdyn_docprocessor_dataverse` which doesn't exist in this solution/env.
# The actual Dataverse connection ref is `bw_sharedcommondataserviceforapps_6fb4c`
# (already used by RMA Email Monitor).
#
# This is why both flows are activated but never fire — the connection points
# to nothing.
#
# Fix: PATCH workflows.clientdata to swap the bad logical name with the good one.

[CmdletBinding()]
param(
    [string] $OrgUrl       = "https://org6feab6b5.crm.dynamics.com",
    [string] $BadConnLogicalName  = "msdyn_docprocessor_dataverse",
    [string] $GoodConnLogicalName = "bw_sharedcommondataserviceforapps_6fb4c"
)

$ErrorActionPreference = "Stop"
$token = az account get-access-token --resource $OrgUrl --query accessToken -o tsv
$hdr = @{
    Authorization      = "Bearer $token"
    Accept             = "application/json"
    "Content-Type"     = "application/json; charset=utf-8"
    "OData-MaxVersion" = "4.0"
    "OData-Version"    = "4.0"
}

$flows = @(
    @{Name='RMA Auto-Assign Plant'; Id='98f4965b-2e4e-f111-bec6-000d3a5aed87'},
    @{Name='RMA Stage Tracker';     Id='2755df62-2f4e-f111-bec6-000d3a5aed87'}
)

foreach ($f in $flows) {
    Write-Host ""
    Write-Host "=== $($f.Name) ===" -ForegroundColor Cyan

    # Backup
    $orig = Invoke-RestMethod -Uri "$OrgUrl/api/data/v9.2/workflows($($f.Id))?`$select=name,clientdata,statecode,statuscode" -Headers $hdr
    $backup = "customers/ametek/hkp_rma/d365/flow_$($f.Id)_clientdata_pre_fix.json"
    @{ name = $orig.name; clientdata = $orig.clientdata; statecode = $orig.statecode; statuscode = $orig.statuscode } | ConvertTo-Json -Depth 5 | Set-Content -Path $backup -Encoding UTF8
    Write-Host "  Backup saved to $backup" -ForegroundColor DarkGray

    # Check current state
    $cd = $orig.clientdata
    $countBefore = ([regex]::Matches($cd, [regex]::Escape($BadConnLogicalName))).Count
    Write-Host "  '$BadConnLogicalName' occurrences in clientdata: $countBefore"
    if ($countBefore -eq 0) {
        Write-Host "  No swap needed; skipping." -ForegroundColor Yellow
        continue
    }

    # Swap
    $patched = $cd.Replace($BadConnLogicalName, $GoodConnLogicalName)
    $countAfter = ([regex]::Matches($patched, [regex]::Escape($GoodConnLogicalName))).Count
    Write-Host "  After swap, '$GoodConnLogicalName' occurrences: $countAfter"

    # Step 1: deactivate (statecode=0, statuscode=1) before patch — required for clientdata changes
    Write-Host "  Deactivating flow..." -ForegroundColor DarkGray
    $deact = @{ statecode = 0; statuscode = 1 } | ConvertTo-Json -Compress
    Invoke-WebRequest -Method PATCH -Uri "$OrgUrl/api/data/v9.2/workflows($($f.Id))" -Headers $hdr -Body $deact -UseBasicParsing | Out-Null

    # Step 2: patch clientdata
    Write-Host "  Patching clientdata..." -ForegroundColor DarkGray
    $body = @{ clientdata = $patched } | ConvertTo-Json -Depth 1 -Compress
    Invoke-WebRequest -Method PATCH -Uri "$OrgUrl/api/data/v9.2/workflows($($f.Id))" -Headers $hdr -Body $body -UseBasicParsing | Out-Null

    # Step 3: reactivate
    Write-Host "  Reactivating flow..." -ForegroundColor DarkGray
    $reactt = @{ statecode = 1; statuscode = 2 } | ConvertTo-Json -Compress
    try {
        Invoke-WebRequest -Method PATCH -Uri "$OrgUrl/api/data/v9.2/workflows($($f.Id))" -Headers $hdr -Body $reactt -UseBasicParsing | Out-Null
        Write-Host "  Reactivation OK" -ForegroundColor Green
    } catch {
        Write-Host "  Reactivation FAILED: $($_.Exception.Message)" -ForegroundColor Red
        if ($_.ErrorDetails -and $_.ErrorDetails.Message) {
            Write-Host "    $($_.ErrorDetails.Message)" -ForegroundColor DarkRed
        }
    }

    # Verify
    $now = Invoke-RestMethod -Uri "$OrgUrl/api/data/v9.2/workflows($($f.Id))?`$select=clientdata,statecode,statuscode" -Headers $hdr
    $afterFix = ([regex]::Matches($now.clientdata, [regex]::Escape($BadConnLogicalName))).Count
    Write-Host "  Verification: bad-connection-ref still in clientdata? $afterFix times. statecode=$($now.statecode) statuscode=$($now.statuscode)" -ForegroundColor $(if ($afterFix -eq 0) {'Green'} else {'Red'})
}

Write-Host ""
Write-Host "Done. Note: flows may still not run if the connection itself isn't authenticated under the running user." -ForegroundColor DarkGray
