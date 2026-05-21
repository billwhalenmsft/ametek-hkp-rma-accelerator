<#
.SYNOPSIS
    Phase C5 — Upload JS form library + add it to the rma_claim main form's
    formLibraries so functions are callable from modern command buttons.

    Modern command bar buttons themselves are best authored in the
    Power Apps "command bar" UI (~10 min) — but the FormLibrary registration
    here makes the function namespace available the moment Bill wires them.
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
    param([string]$Method, [string]$Path, $Body = $null, [switch]$ReturnHeaders)
    $url = "$OrgUrl/api/data/v9.2/$Path"
    $h = $hdrBase.Clone()
    if ($Method -in @('PATCH','DELETE')) { $h['If-Match'] = '*' }
    if ($Body) { $h['Content-Type'] = 'application/json; charset=utf-8' }
    $params = @{ Uri = $url; Method = $Method; Headers = $h }
    if ($Body) { $params.Body = if ($Body -is [string]) { $Body } else { ($Body | ConvertTo-Json -Depth 30 -Compress) } }
    if ($ReturnHeaders) { return Invoke-WebRequest @params }
    return Invoke-RestMethod @params
}

# Upload JS web resource
$wrName = "rma_/scripts/hkp_rma_form_commands.js"
$src = "C:\Users\billwhalen\OneDrive - Microsoft\Documents\GitHub\RAPP\CommunityRAPP-main\customers\ametek\hkp_rma\d365\hkp_rma_form_commands.js"
$bytes = [System.IO.File]::ReadAllBytes($src)
$b64 = [Convert]::ToBase64String($bytes)

$existing = (Invoke-Dv -Method GET -Path "webresourceset?`$filter=name eq '$wrName'&`$select=webresourceid").value
if ($existing.Count -gt 0) {
    $wrId = $existing[0].webresourceid
    Write-Host "  [update] $wrName -> $wrId" -ForegroundColor DarkGray
    Invoke-Dv -Method PATCH -Path "webresourceset($wrId)" -Body @{ content = $b64; displayname = "HKP RMA Form Commands" } | Out-Null
} else {
    $body = @{
        name             = $wrName
        displayname      = "HKP RMA Form Commands"
        webresourcetype  = 3    # JavaScript
        content          = $b64
        description      = "Modern command handlers for rma_claim form: resolve, deny, email, request approval."
        languagecode     = 1033
    }
    $resp = Invoke-Dv -Method POST -Path "webresourceset" -Body $body -ReturnHeaders
    $loc = $resp.Headers['OData-EntityId']
    if ($loc -is [array]) { $loc = $loc[0] }
    if ($loc -match '\(([0-9a-fA-F\-]{36})\)') { $wrId = $matches[1] }
    Write-Host "  [create] $wrName -> $wrId" -ForegroundColor Green
}

# Add to rma_claim main form's <formLibraries>
$formId = "05a92f92-94cc-4a07-9ba0-f704788c699c"
$form = Invoke-Dv -Method GET -Path "systemforms($formId)?`$select=formxml,name"
$xml = $form.formxml

# Add library if not present
if ($xml -notmatch [regex]::Escape($wrName)) {
    # Insert before </form>
    $lib = "<formLibraries><Library name=`"$wrName`" libraryUniqueId=`"{$wrId}`" /></formLibraries>"
    if ($xml -match "</tabs>") {
        $xml = $xml -replace "</tabs>", "</tabs>$lib"
    } else {
        $xml = $xml -replace "</form>", "$lib</form>"
    }
    Write-Host "  [add] formLibrary registration to rma_claim main form" -ForegroundColor Green
    $body = @{ formxml = $xml } | ConvertTo-Json -Compress
    Invoke-Dv -Method PATCH -Path "systemforms($formId)" -Body $body | Out-Null
} else {
    Write-Host "  [skip] formLibrary already on rma_claim main form" -ForegroundColor DarkGray
}

Write-Host "`nDone. Web resource ID: $wrId" -ForegroundColor Cyan
Write-Host "Run 'pac solution publish' to make changes live." -ForegroundColor Yellow
