# Deploy Email Assist productivity side pane
# - Uploads HTML web resource: rma_/productivity/rma_email_assist.html
# - Uploads JS  web resource: rma_/scripts/email_productivity_pane.js
# - Patches rma_emaillog form:
#     - Adds the JS to formLibraries
#     - Adds an events section with OnLoad → RmaEmailAssist.onLoad
# - Publishes web resources + entity

$ErrorActionPreference = "Stop"

$ORG  = "https://org6feab6b5.crm.dynamics.com"
$TOK  = az account get-access-token --resource $ORG --query accessToken -o tsv
$H    = @{ Authorization = "Bearer $TOK"; "Content-Type" = "application/json"; Accept = "application/json" }

$FORM_ID = "eec402c7-2c29-412c-897d-c5d17ec3668c"  # rma_emaillog Information form

$HTML_PATH = "customers/ametek/hkp_rma/ui/rma_email_assist.html"
$JS_PATH   = "customers/ametek/hkp_rma/scripts/email_productivity_pane.js"

$HTML_NAME = "rma_/productivity/rma_email_assist.html"
$JS_NAME   = "rma_/scripts/email_productivity_pane.js"
$HTML_DISPLAY = "RMA Email Assist Pane (HTML)"
$JS_DISPLAY   = "RMA Email Assist Pane (JS)"

function To-Base64Content([string]$path) {
    $bytes = [IO.File]::ReadAllBytes((Resolve-Path $path).Path)
    return [Convert]::ToBase64String($bytes)
}

function Get-WebResourceId([string]$name) {
    $u = "$ORG/api/data/v9.2/webresourceset?`$filter=name eq '$name'&`$select=webresourceid"
    $r = Invoke-RestMethod -Uri $u -Headers $H
    if ($r.value.Count -gt 0) { return $r.value[0].webresourceid }
    return $null
}

function Upsert-WebResource {
    param([string]$Name, [string]$Display, [int]$Type, [string]$Path)
    $content = To-Base64Content $Path
    $existingId = Get-WebResourceId $Name
    if ($existingId) {
        Write-Host "  Updating $Name ($existingId)"
        $body = @{ content = $content; displayname = $Display } | ConvertTo-Json -Compress
        Invoke-RestMethod -Method Patch -Uri "$ORG/api/data/v9.2/webresourceset($existingId)" -Headers $H -Body $body | Out-Null
        return $existingId
    } else {
        Write-Host "  Creating $Name"
        $body = @{
            name = $Name
            displayname = $Display
            webresourcetype = $Type   # 1=HTML, 3=JS
            content = $content
            languagecode = 1033
        } | ConvertTo-Json -Compress
        $hRet = $H.Clone()
        $hRet["Prefer"] = "return=representation"
        $r = Invoke-RestMethod -Method Post -Uri "$ORG/api/data/v9.2/webresourceset" -Headers $hRet -Body $body
        return $r.webresourceid
    }
}

Write-Host "=== Uploading web resources ==="
$htmlId = Upsert-WebResource -Name $HTML_NAME -Display $HTML_DISPLAY -Type 1 -Path $HTML_PATH
$jsId   = Upsert-WebResource -Name $JS_NAME   -Display $JS_DISPLAY   -Type 3 -Path $JS_PATH
Write-Host "  HTML id: $htmlId"
Write-Host "  JS   id: $jsId"

Write-Host "`n=== Publishing web resources ==="
$pubBody = @{ ParameterXml = "<importexportxml><webresources><webresource>{$htmlId}</webresource><webresource>{$jsId}</webresource></webresources></importexportxml>" } | ConvertTo-Json -Compress
Invoke-RestMethod -Method Post -Uri "$ORG/api/data/v9.2/PublishXml" -Headers $H -Body $pubBody -TimeoutSec 60 | Out-Null
Write-Host "  Published"

Write-Host "`n=== Reading form XML ==="
$form = Invoke-RestMethod -Uri "$ORG/api/data/v9.2/systemforms($FORM_ID)?`$select=formxml" -Headers $H
$xml = $form.formxml

# Backup
$stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$bk = "customers/ametek/hkp_rma/backup/rma_emaillog_form_${stamp}_PRE_ASSIST_PANE.xml"
New-Item -ItemType Directory -Force -Path (Split-Path $bk) | Out-Null
[IO.File]::WriteAllText((Resolve-Path .).Path + "/" + $bk, $xml)
Write-Host "  Backup: $bk"
Write-Host "  Length before: $($xml.Length)"

# 1) Add the JS library to <formLibraries> if not already present
$jsGuidNoBraces = $jsId.ToString()
if ($xml -match [regex]::Escape($JS_NAME)) {
    Write-Host "  formLibraries already contains $JS_NAME — skipping add"
} else {
    $newLib = "<Library name=`"$JS_NAME`" libraryUniqueId=`"{$jsGuidNoBraces}`" />"
    $xml = $xml -replace '</formLibraries>', "$newLib</formLibraries>"
    Write-Host "  Added library entry"
}

# 2) Add or augment <events> section with OnLoad handler
$handlerSnippet = "<Handler functionName=`"RmaEmailAssist.onLoad`" libraryName=`"$JS_NAME`" handlerUniqueId=`"{$((New-Guid).Guid)}`" enabled=`"true`" parameters=`"`" passExecutionContext=`"true`" />"

if ($xml -match '<events>') {
    if ($xml -match 'RmaEmailAssist\.onLoad') {
        Write-Host "  Events already contain RmaEmailAssist.onLoad — skipping"
    } else {
        if ($xml -match '<event name="onload"[^>]*>') {
            # add Handler to existing onload event
            $xml = $xml -replace '(<event name="onload"[^>]*>\s*<Handlers>)', "`$1$handlerSnippet"
            Write-Host "  Added Handler to existing onload event"
        } else {
            # add a new onload event block inside <events>
            $eventBlock = "<event name=`"onload`" application=`"false`" active=`"false`"><Handlers>$handlerSnippet</Handlers></event>"
            $xml = $xml -replace '</events>', "$eventBlock</events>"
            Write-Host "  Added new onload event block"
        }
    }
} else {
    # Insert events section right after </formLibraries>
    $eventsSection = "<events><event name=`"onload`" application=`"false`" active=`"false`"><Handlers>$handlerSnippet</Handlers></event></events>"
    $xml = $xml -replace '</formLibraries>', "</formLibraries>$eventsSection"
    Write-Host "  Created new events section"
}

Write-Host "  Length after: $($xml.Length)"

Write-Host "`n=== Patching form ==="
$body = @{ formxml = $xml } | ConvertTo-Json -Compress
Invoke-RestMethod -Method Patch -Uri "$ORG/api/data/v9.2/systemforms($FORM_ID)" -Headers $H -Body $body | Out-Null
Write-Host "  Form patched"

Write-Host "`n=== Publishing rma_emaillog ==="
$pubBody2 = @{ ParameterXml = '<importexportxml><entities><entity>rma_emaillog</entity></entities></importexportxml>' } | ConvertTo-Json -Compress
Invoke-RestMethod -Method Post -Uri "$ORG/api/data/v9.2/PublishXml" -Headers $H -Body $pubBody2 -TimeoutSec 60 | Out-Null
Write-Host "  Published"

Write-Host "`nDone. Hard-refresh (Ctrl+F5) and open any rma_emaillog record to see the Email Assist side pane."
