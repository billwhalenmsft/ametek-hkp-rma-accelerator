# Deploy Email Body Preview web resource + add Body Preview tab to rma_emaillog form.
# Pattern matches deploy_smart_insights_webresource.ps1 + patch_claim_form_smart_insights.ps1
param(
    [string]$OrgUrl = "https://org6feab6b5.crm.dynamics.com",
    [string]$LocalHtml = "customers\ametek\hkp_rma\ui\rma_email_body_preview.html",
    [string]$WebResourceName = "rma_/board/email_body_preview.html",
    [string]$EmailLogFormId = "eec402c7-2c29-412c-897d-c5d17ec3668c"
)
$ErrorActionPreference = "Stop"
$token = az account get-access-token --resource $OrgUrl --query accessToken -o tsv
$h = @{ Authorization = "Bearer $token"; Accept = "application/json"; "Content-Type" = "application/json"; "OData-MaxVersion" = "4.0"; "OData-Version" = "4.0" }

# Read + base64 the HTML
if (-not (Test-Path $LocalHtml)) { throw "HTML not found: $LocalHtml" }
$bytes = [System.IO.File]::ReadAllBytes((Resolve-Path $LocalHtml))
$content = [System.Convert]::ToBase64String($bytes)
Write-Host "HTML: $($bytes.Length) bytes -> $($content.Length) base64 chars" -ForegroundColor Cyan

# Find or create web resource
$existing = (Invoke-RestMethod -Uri "$OrgUrl/api/data/v9.2/webresourceset?`$filter=name eq '$WebResourceName'&`$select=webresourceid,name" -Headers $h).value
if ($existing) {
    $wrId = $existing[0].webresourceid
    Write-Host "Updating existing web resource $wrId..." -ForegroundColor Yellow
    $body = @{ content = $content; displayname = "RMA Email Body Preview"; description = "Renders the rma_emaillog body in a styled preview pane." } | ConvertTo-Json -Depth 3
    Invoke-WebRequest -Method PATCH -Uri "$OrgUrl/api/data/v9.2/webresourceset($wrId)" -Headers $h -Body $body -UseBasicParsing | Out-Null
} else {
    Write-Host "Creating new web resource..." -ForegroundColor Yellow
    $body = @{
        name = $WebResourceName
        displayname = "RMA Email Body Preview"
        description = "Renders the rma_emaillog body in a styled preview pane."
        webresourcetype = 1   # HTML
        languagecode = 1033   # CRITICAL: empty languagecode causes PrimaryNameLookup failure on form ref
        content = $content
    } | ConvertTo-Json -Depth 3
    $resp = Invoke-WebRequest -Method POST -Uri "$OrgUrl/api/data/v9.2/webresourceset" -Headers $h -Body $body -UseBasicParsing
    $loc = $resp.Headers["OData-EntityId"]
    if ($loc -match 'webresourceset\(([0-9a-f-]+)\)') { $wrId = $Matches[1] }
}
Write-Host "  WebResource ID: $wrId" -ForegroundColor Green

# Publish web resource
$pubXml = "<importexportxml><webresources><webresource>$wrId</webresource></webresources></importexportxml>"
Invoke-WebRequest -Method POST -Uri "$OrgUrl/api/data/v9.2/PublishXml" -Headers $h -Body (@{ ParameterXml = $pubXml } | ConvertTo-Json) -UseBasicParsing | Out-Null
Write-Host "  Published web resource" -ForegroundColor Green

# Now patch the rma_emaillog form to add a Body Preview tab
$form = Invoke-RestMethod -Uri "$OrgUrl/api/data/v9.2/systemforms($EmailLogFormId)?`$select=name,formxml" -Headers $h
$formxml = $form.formxml

# Idempotency: if tab already exists, skip
if ($formxml -match 'name="bodypreview_tab"') {
    Write-Host "Body Preview tab already on form. Skipping XML patch." -ForegroundColor Yellow
} else {
    Write-Host "Patching form XML to add Body Preview tab..." -ForegroundColor Yellow

    # Build the new tab XML — single tab, single 1-column section, full-width web resource cell, rowspan=12
    # NOTE: Url is plain web resource name (no $webresource: prefix). WebResourceId param is REQUIRED so Dataverse can resolve the dependency at form-save time.
    $newTab = '<tab verticallayout="true" id="{a3aaaaaa-1111-4444-bbbb-aaaaaaaaaaaa}" IsUserDefined="1" name="bodypreview_tab"><labels><label description="Body Preview" languagecode="1033" /></labels><columns><column width="100%"><sections><section showlabel="false" showbar="false" id="{a4aaaaaa-2222-4444-bbbb-aaaaaaaaaaaa}" columns="1" labelwidth="115" name="bodypreview_section"><labels><label description="Body Preview" languagecode="1033" /></labels><rows><row><cell id="{a5aaaaaa-3333-4444-bbbb-aaaaaaaaaaaa}" colspan="1" rowspan="12" showlabel="false"><labels><label description="Email Body" languagecode="1033" /></labels><control id="WebResource_emailbodypreview" classid="{9FDF5F91-88B1-47f4-AD53-C11EFC01A01D}"><parameters><Url>rma_/board/email_body_preview.html</Url><PassParameters>true</PassParameters><Security>false</Security><Scrolling>auto</Scrolling><Border>false</Border><ShowOnMobileClient>false</ShowOnMobileClient><WebResourceId>{' + $wrId + '}</WebResourceId></parameters></control></cell></row><row /><row /><row /><row /><row /><row /><row /><row /><row /><row /><row /></rows></section></sections></column></columns></tab>'

    # Insert just before </tabs>
    if ($formxml -notmatch '</tabs>') { throw "Form XML has no </tabs> close - abort" }
    $newFormXml = $formxml -replace '</tabs>', "$newTab</tabs>"

    # Validate XML still well-formed
    try { [xml]$newFormXml | Out-Null; Write-Host "  Patched XML validates OK" } catch { throw "Patched XML malformed: $_" }

    # PATCH form
    $patchBody = @{ formxml = $newFormXml } | ConvertTo-Json -Depth 5
    Invoke-WebRequest -Method PATCH -Uri "$OrgUrl/api/data/v9.2/systemforms($EmailLogFormId)" -Headers $h -Body $patchBody -UseBasicParsing | Out-Null
    Write-Host "  Form patched" -ForegroundColor Green
}

# Publish entity
$pubXml2 = "<importexportxml><entities><entity>rma_emaillog</entity></entities></importexportxml>"
Invoke-WebRequest -Method POST -Uri "$OrgUrl/api/data/v9.2/PublishXml" -Headers $h -Body (@{ ParameterXml = $pubXml2 } | ConvertTo-Json) -UseBasicParsing | Out-Null
Write-Host "  Published rma_emaillog" -ForegroundColor Green

Write-Host ""
Write-Host "Open any rma_emaillog record in the RMA Operations app -> 'Body Preview' tab." -ForegroundColor Cyan
