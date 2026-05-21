# patch_claim_form_cleanup.ps1
# ------------------------------------------------------------
# 1) Adds rma_contactname (Text 100) column to rma_claim
# 2) Fixes broken view-binding on 4 subgrids on the Information form
#    (Notes, Approval Records, Approval History, Email Log)
# 3) Adds Contact Name field to General tab
# 4) Adds Timeline (notes) control to General tab
# 5) Publishes form + entity
# ------------------------------------------------------------

$ErrorActionPreference = "Stop"
$orgUrl   = "https://org6feab6b5.crm.dynamics.com"
$formId   = "05a92f92-94cc-4a07-9ba0-f704788c699c"

$token   = (az account get-access-token --resource $orgUrl --query accessToken -o tsv)
$hdr     = @{ Authorization="Bearer $token"; Accept="application/json" }
$pchHdr  = @{ Authorization="Bearer $token"; Accept="application/json"; "Content-Type"="application/json; charset=utf-8"; "If-Match"="*" }
$pchHdrSol = @{ Authorization="Bearer $token"; Accept="application/json"; "Content-Type"="application/json; charset=utf-8"; "If-Match"="*"; "MSCRM.SolutionUniqueName"="RMAReturnsMonitorRma" }
$postHdrSol = @{ Authorization="Bearer $token"; Accept="application/json"; "Content-Type"="application/json; charset=utf-8"; "OData-MaxVersion"="4.0"; "OData-Version"="4.0"; "MSCRM.SolutionUniqueName"="RMAReturnsMonitorRma" }

# ---------- 1) Add rma_contactname column ----------
Write-Host "[1/5] Adding rma_contactname column to rma_claim..."
$colExists = $false
try {
    Invoke-RestMethod -Uri "$orgUrl/api/data/v9.2/EntityDefinitions(LogicalName='rma_claim')/Attributes(LogicalName='rma_contactname')?`$select=LogicalName" -Headers $hdr | Out-Null
    $colExists = $true
} catch {}
if ($colExists) {
    Write-Host "  [skip] rma_contactname already exists."
} else {
    $body = @{
        "@odata.type"       = "Microsoft.Dynamics.CRM.StringAttributeMetadata"
        SchemaName          = "rma_ContactName"
        DisplayName         = @{ "@odata.type"="Microsoft.Dynamics.CRM.Label"; LocalizedLabels=@(@{ Label="Contact Name"; LanguageCode=1033 }) }
        Description         = @{ "@odata.type"="Microsoft.Dynamics.CRM.Label"; LocalizedLabels=@(@{ Label="Person who submitted the RMA request (from email signature or sender display name)."; LanguageCode=1033 }) }
        RequiredLevel       = @{ "@odata.type"="Microsoft.Dynamics.CRM.AttributeRequiredLevelManagedProperty"; Value="None" }
        AttributeType       = "String"
        AttributeTypeName   = @{ Value="StringType" }
        MaxLength           = 200
        FormatName          = @{ Value="Text" }
    } | ConvertTo-Json -Depth 10 -Compress
    $r = Invoke-WebRequest -Uri "$orgUrl/api/data/v9.2/EntityDefinitions(LogicalName='rma_claim')/Attributes" -Method Post -Headers $postHdrSol -Body $body
    Write-Host "  [ok] Created rma_contactname."
}

# ---------- 2-4) Patch the form ----------
Write-Host "[2/5] Loading form XML..."
$form = Invoke-RestMethod -Uri "$orgUrl/api/data/v9.2/systemforms($formId)?`$select=name,formxml" -Headers $hdr
[xml]$xml = $form.formxml

# View IDs (real, looked up from savedqueries)
$viewMap = @{
    "rma_claimnote"       = "41aac493-1b6f-4c8f-81e3-d7e1ec59ad30"  # Active Claim Notes
    "rma_approvalrecord"  = "1bd18347-860a-4d60-a9f7-2de3dd1accad"  # Active Approval Records
    "rma_approvalhistory" = "0d0e7b2a-1c4e-4626-aa84-68a87d1d34f4"  # Active Approval History
    "rma_emaillog"        = "f06d85ab-d44e-f111-bec6-000d3a5aed87"  # Inbound — Unprocessed (default true)
}

Write-Host "[3/5] Fixing subgrid ViewId bindings..."
$grids = $xml.SelectNodes("//control[@classid='{E7A81278-8635-4d9e-8D4D-59480B391C5B}']")
foreach ($g in $grids) {
    $target = $g.parameters.TargetEntityType
    if ($viewMap.ContainsKey($target)) {
        $newView = "{$($viewMap[$target])}"
        $oldView = $g.parameters.ViewId
        $g.parameters.ViewId = $newView
        # Also ensure ViewIds element references it (some Dataverse forms need this)
        $viewIds = $g.parameters.SelectSingleNode("ViewIds")
        if ($viewIds) {
            $viewIds.InnerText = $newView
        } else {
            $vi = $xml.CreateElement("ViewIds")
            $vi.InnerText = $newView
            $g.parameters.AppendChild($vi) | Out-Null
        }
        # AvailableViewIds should also list this view
        $avail = $g.parameters.SelectSingleNode("AvailableViewIds")
        if ($avail) { $avail.InnerText = $newView }
        Write-Host "  [ok] $($g.id) ($target): $oldView -> $newView"
    }
}

Write-Host "[4/5] Adding Contact Name field + Timeline to General tab..."

# Find Customer & Part section, append a new row with Contact Name
$genTab = $xml.SelectSingleNode("//tab[@name='general_tab']")
$custSection = $genTab.SelectNodes(".//section") | Where-Object { $_.labels.label.description -eq "Customer & Part" } | Select-Object -First 1

if ($custSection) {
    # Check we haven't already added it
    $existing = $custSection.SelectSingleNode(".//control[@datafieldname='rma_contactname']")
    if (-not $existing) {
        $newRow = $xml.CreateElement("row")
        $newCell = $xml.CreateElement("cell")
        $newCell.SetAttribute("id", "{$([guid]::NewGuid())}")
        $newCell.SetAttribute("colspan", "2")
        $newCell.SetAttribute("rowspan", "1")
        $cellLabels = $xml.CreateElement("labels")
        $cellLabel = $xml.CreateElement("label")
        $cellLabel.SetAttribute("description", "Contact Name")
        $cellLabel.SetAttribute("languagecode", "1033")
        $cellLabels.AppendChild($cellLabel) | Out-Null
        $newCell.AppendChild($cellLabels) | Out-Null
        $cellCtl = $xml.CreateElement("control")
        $cellCtl.SetAttribute("id", "rma_contactname")
        $cellCtl.SetAttribute("classid", "{4273EDBD-AC1D-40d3-9FB2-095C621B552D}")
        $cellCtl.SetAttribute("datafieldname", "rma_contactname")
        $newCell.AppendChild($cellCtl) | Out-Null
        $newRow.AppendChild($newCell) | Out-Null
        # Append at end of Customer & Part rows
        $custSection.SelectSingleNode("rows").AppendChild($newRow) | Out-Null
        Write-Host "  [ok] Added Contact Name to Customer & Part section."
    } else {
        Write-Host "  [skip] Contact Name field already on form."
    }
} else {
    Write-Host "  [warn] Could not find Customer & Part section."
}

# Add Timeline section to general_tab if not present
$timelineExists = $genTab.SelectSingleNode(".//control[@id='notescontrol']")
if (-not $timelineExists) {
    $tlSection = $xml.CreateElement("section")
    $tlSection.SetAttribute("showlabel", "true")
    $tlSection.SetAttribute("showbar", "true")
    $tlSection.SetAttribute("id", "{$([guid]::NewGuid())}")
    $tlSection.SetAttribute("columns", "1")
    $tlLabels = $xml.CreateElement("labels")
    $tlLabel = $xml.CreateElement("label")
    $tlLabel.SetAttribute("description", "Timeline")
    $tlLabel.SetAttribute("languagecode", "1033")
    $tlLabels.AppendChild($tlLabel) | Out-Null
    $tlSection.AppendChild($tlLabels) | Out-Null
    $tlRows = $xml.CreateElement("rows")
    $tlRow = $xml.CreateElement("row")
    $tlCell = $xml.CreateElement("cell")
    $tlCell.SetAttribute("id", "{$([guid]::NewGuid())}")
    $tlCell.SetAttribute("showlabel", "false")
    $tlCell.SetAttribute("rowspan", "8")
    $tlCell.SetAttribute("colspan", "1")
    $tlCellLabels = $xml.CreateElement("labels")
    $tlCellLabel = $xml.CreateElement("label")
    $tlCellLabel.SetAttribute("description", "Timeline")
    $tlCellLabel.SetAttribute("languagecode", "1033")
    $tlCellLabels.AppendChild($tlCellLabel) | Out-Null
    $tlCell.AppendChild($tlCellLabels) | Out-Null
    $tlCtl = $xml.CreateElement("control")
    $tlCtl.SetAttribute("id", "notescontrol")
    $tlCtl.SetAttribute("classid", "{06375649-c143-495e-a496-c962e5b4488e}")
    $tlParams = $xml.CreateElement("parameters")
    foreach ($p in @(
        @{n="DefaultTabId"; v="Notes"},
        @{n="SortActivityWall"; v="descending"},
        @{n="OrderByActivityWall"; v="modifiedon"},
        @{n="FilterResults"; v="false"},
        @{n="AllowChangingFiltersOnUI"; v="true"}
    )) {
        $pe = $xml.CreateElement($p.n)
        $pe.InnerText = $p.v
        $tlParams.AppendChild($pe) | Out-Null
    }
    $tlCtl.AppendChild($tlParams) | Out-Null
    $tlCell.AppendChild($tlCtl) | Out-Null
    $tlRow.AppendChild($tlCell) | Out-Null
    $tlRows.AppendChild($tlRow) | Out-Null
    # add 7 empty rows for the rowspan
    1..7 | ForEach-Object { $tlRows.AppendChild($xml.CreateElement("row")) | Out-Null }
    $tlSection.AppendChild($tlRows) | Out-Null
    # Append the Timeline section as a new section in the first column of general_tab
    $firstColumn = $genTab.SelectSingleNode("columns/column")
    $firstColumn.SelectSingleNode("sections").AppendChild($tlSection) | Out-Null
    Write-Host "  [ok] Added Timeline section to General tab."
} else {
    Write-Host "  [skip] Timeline already on form."
}

# ---------- PATCH form ----------
Write-Host "[5/5] PATCHing form + publishing..."
$newFormXml = $xml.OuterXml
$body = @{ formxml = $newFormXml } | ConvertTo-Json -Depth 5
try {
    Invoke-WebRequest -Uri "$orgUrl/api/data/v9.2/systemforms($formId)" -Method Patch -Headers $pchHdrSol -Body $body | Out-Null
    Write-Host "  [ok] Form patched."
} catch {
    Write-Host "  [ERR] PATCH failed: $($_.ErrorDetails.Message)"
    throw
}

# Publish entity (so column shows in form designer + in views)
$pubBody = @{ ParameterXml = "<importexportxml><entities><entity>rma_claim</entity></entities></importexportxml>" } | ConvertTo-Json -Compress
try {
    Invoke-WebRequest -Uri "$orgUrl/api/data/v9.2/PublishXml" -Method Post -Headers $postHdrSol -Body $pubBody | Out-Null
    Write-Host "  [ok] Published rma_claim entity."
} catch {
    Write-Host "  [ERR] Publish failed: $($_.ErrorDetails.Message)"
    throw
}

Write-Host ""
Write-Host "Done. Refresh the RMA Operations app to see changes."
