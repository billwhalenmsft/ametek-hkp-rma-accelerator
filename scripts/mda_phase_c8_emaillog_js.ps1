<#
.SYNOPSIS
    Phase C8 — Re-upload JS form library with createClaimFromEmail() and
    register on rma_emaillog main form.
#>
[CmdletBinding()]
param([string]$OrgUrl = "https://org6feab6b5.crm.dynamics.com")
$ErrorActionPreference = "Stop"
$token = (az account get-access-token --resource $OrgUrl --query accessToken -o tsv)
$hdrBase = @{
    Authorization      = "Bearer $token"
    Accept             = "application/json"
    "OData-Version"    = "4.0"
    "OData-MaxVersion" = "4.0"
    "MSCRM.SolutionUniqueName" = "RMAReturnsMonitor"
}
function Invoke-Dv {
    param([string]$Method, [string]$Path, $Body = $null)
    $url = "$OrgUrl/api/data/v9.2/$Path"
    $h = $hdrBase.Clone()
    if ($Method -in @('PATCH','DELETE')) { $h['If-Match'] = '*' }
    if ($Body) { $h['Content-Type'] = 'application/json; charset=utf-8' }
    $params = @{ Uri = $url; Method = $Method; Headers = $h }
    if ($Body) { $params.Body = if ($Body -is [string]) { $Body } else { ($Body | ConvertTo-Json -Depth 30 -Compress) } }
    return Invoke-RestMethod @params
}

# Re-upload JS web resource
$wrName = "rma_/scripts/hkp_rma_form_commands.js"
$src = "C:\Users\billwhalen\OneDrive - Microsoft\Documents\GitHub\RAPP\CommunityRAPP-main\customers\ametek\hkp_rma\d365\hkp_rma_form_commands.js"
$bytes = [System.IO.File]::ReadAllBytes($src)
$b64 = [Convert]::ToBase64String($bytes)

$existing = (Invoke-Dv -Method GET -Path "webresourceset?`$filter=name eq '$wrName'&`$select=webresourceid").value
$wrId = $existing[0].webresourceid
Invoke-Dv -Method PATCH -Path "webresourceset($wrId)" -Body @{ content = $b64 } | Out-Null
Write-Host "  [update] $wrName ($wrId)" -ForegroundColor Green

# Register on rma_emaillog main form
$emailFormId = "eec402c7-2c29-412c-897d-c5d17ec3668c"
$form = Invoke-Dv -Method GET -Path "systemforms($emailFormId)?`$select=formxml,name"
$xml = $form.formxml

if ($xml -notmatch [regex]::Escape($wrName)) {
    $lib = "<formLibraries><Library name=`"$wrName`" libraryUniqueId=`"{$wrId}`" /></formLibraries>"
    if ($xml -match "</tabs>") {
        $xml = $xml -replace "</tabs>", "</tabs>$lib"
    } else {
        $xml = $xml -replace "</form>", "$lib</form>"
    }
    Write-Host "  [add] formLibrary to rma_emaillog main form" -ForegroundColor Green
    Invoke-Dv -Method PATCH -Path "systemforms($emailFormId)" -Body @{ formxml = $xml } | Out-Null
} else {
    Write-Host "  [skip] formLibrary already on rma_emaillog form" -ForegroundColor DarkGray
}

Write-Host "`nDone." -ForegroundColor Cyan
