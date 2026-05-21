# Patch RMA Email Monitor flow:
#   - Replace EmailText (raw JSON dump) with HTML-stripped plain text
#   - Rewrite all 18 extract Composes to use plain text + newline anchors
#   - Keep Create_item bindings unchanged

[CmdletBinding()]
param(
    [string]$EnvId  = "2404ccaf-d7e5-e1ff-863a-3ecbe2f0f013",
    [string]$FlowId = "b26a7f4b-b181-cd5e-ff45-454939890b06"
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

Write-Host "`n=== Patching RMA Email Monitor flow ===" -ForegroundColor Cyan

$paToken = (az account get-access-token --resource "https://service.flow.microsoft.com/" --query accessToken -o tsv)
if (-not $paToken) { throw "Failed to get PA token. Run 'az login' first." }
$hdr = @{
    Authorization = "Bearer $paToken"
    "Content-Type" = "application/json"
}

$baseUri = "https://api.flow.microsoft.com/providers/Microsoft.ProcessSimple/environments/$EnvId/flows/$FlowId"
$flowUri = "$baseUri" + "?api-version=2016-11-01"

# ---------------------------------------------------------------------------
# 1. Fetch + backup current flow
# ---------------------------------------------------------------------------
Write-Host "  Fetching current flow definition..." -ForegroundColor Gray
$flow = Invoke-RestMethod -Uri $flowUri -Headers $hdr
$backupDir = Join-Path (Get-Location) "customers\ametek\hkp_rma\d365"
if (-not (Test-Path $backupDir)) { New-Item -ItemType Directory -Path $backupDir -Force | Out-Null }
$backupPath = Join-Path $backupDir ("rma_email_monitor_backup_{0:yyyyMMdd-HHmmss}.json" -f (Get-Date))
$flow | ConvertTo-Json -Depth 30 | Out-File -FilePath $backupPath -Encoding utf8
Write-Host "  Backup saved: $backupPath" -ForegroundColor DarkGray

# ---------------------------------------------------------------------------
# 2. Build new EmailText Compose (HTML -> plain text)
#
#    Strategy: replace common block-level tags with newline, strip inline tags,
#    decode common HTML entities. Robust enough for form-generated emails.
# ---------------------------------------------------------------------------
$nl = "decodeUriComponent('%0A')"
$src = "triggerOutputs()?['body/body']"

# Build a nested replace() chain
$replacements = @(
    @{ Find = '<br>';      Replace = $nl    },
    @{ Find = '<br/>';     Replace = $nl    },
    @{ Find = '<br />';    Replace = $nl    },
    @{ Find = '<BR>';      Replace = $nl    },
    @{ Find = '</p>';      Replace = $nl    },
    @{ Find = '</P>';      Replace = $nl    },
    @{ Find = '</div>';    Replace = $nl    },
    @{ Find = '</DIV>';    Replace = $nl    },
    @{ Find = '</tr>';     Replace = $nl    },
    @{ Find = '</li>';     Replace = $nl    },
    @{ Find = '<b>';       Replace = "''"   },
    @{ Find = '</b>';      Replace = "''"   },
    @{ Find = '<B>';       Replace = "''"   },
    @{ Find = '</B>';      Replace = "''"   },
    @{ Find = '<strong>';  Replace = "''"   },
    @{ Find = '</strong>'; Replace = "''"   },
    @{ Find = '<i>';       Replace = "''"   },
    @{ Find = '</i>';      Replace = "''"   },
    @{ Find = '<u>';       Replace = "''"   },
    @{ Find = '</u>';      Replace = "''"   },
    @{ Find = '<em>';      Replace = "''"   },
    @{ Find = '</em>';     Replace = "''"   },
    @{ Find = '<p>';       Replace = "''"   },
    @{ Find = '<P>';       Replace = "''"   },
    @{ Find = '<div>';     Replace = "''"   },
    @{ Find = '<DIV>';     Replace = "''"   },
    @{ Find = '<o:p>';     Replace = "''"   },
    @{ Find = '</o:p>';    Replace = "''"   },
    @{ Find = '<span>';    Replace = "''"   },
    @{ Find = '</span>';   Replace = "''"   },
    @{ Find = '<font>';    Replace = "''"   },
    @{ Find = '</font>';   Replace = "''"   },
    @{ Find = '<table>';   Replace = "''"   },
    @{ Find = '</table>';  Replace = "''"   },
    @{ Find = '<tr>';      Replace = "''"   },
    @{ Find = '<td>';      Replace = "''"   },
    @{ Find = '</td>';     Replace = "''"   },
    @{ Find = '<ul>';      Replace = "''"   },
    @{ Find = '</ul>';     Replace = "''"   },
    @{ Find = '<li>';      Replace = "''"   },
    @{ Find = '&nbsp;';    Replace = "' '"  },
    @{ Find = '&amp;';     Replace = "'&'"  },
    @{ Find = '&lt;';      Replace = "'<'"  },
    @{ Find = '&gt;';      Replace = "'>'"  },
    @{ Find = '&quot;';    Replace = '''"''' },
    @{ Find = '&#39;';     Replace = "''''" },
    @{ Find = '&apos;';    Replace = "''''" }
)

# Build expression: replace(replace(replace($src, '<br>', NL), '<br/>', NL), ...)
$expr = $src
foreach ($r in $replacements) {
    $findEscaped = $r.Find -replace "'", "''"
    $expr = "replace($expr, '$findEscaped', $($r.Replace))"
}
$emailTextExpr = "@trim($expr)"

# ---------------------------------------------------------------------------
# 3. Field extraction patterns — each operates on plain text
#    Pattern: trim(first(split(last(split(plainText, 'LABEL:')), newline)))
#    Using 'last' picks the form-field occurrence (after any From:/To: that
#    might contain similar substrings)
# ---------------------------------------------------------------------------
$fields = @(
    @{ ActionName="ExtractCompany";            Label="Company:" },
    @{ ActionName="ExtractEmail";              Label="Email:" },
    @{ ActionName="ExtractPhone";              Label="Phone:" },
    @{ ActionName="ExtractReturnAddress";      Label="Address returned parts will ship to:" },
    @{ ActionName="ExtractQuantity";           Label="Quantity of Suspect Parts:" },
    @{ ActionName="ExtractPONumber";           Label="PO Number parts were ordered on:" },
    @{ ActionName="ExtractDateCodeorSerial";   Label="Manufacturing Date Code/Serial Number, please see label on parts:" },
    @{ ActionName="ExtractPartNumber";         Label="AMETEK Part Number:" },
    @{ ActionName="ExtractMfgLocation";        Label="MFG Location:" },
    @{ ActionName="ExtractComplaintReason";    Label="What is the complaint reason? With details (Please send photos/videos):" },
    @{ ActionName="CompliantReasonOther";      Label="What is the complaint reason - Other:" },
    @{ ActionName="ExtractSalesRep";           Label="Please select your primary HKP sales representative:" },
    @{ ActionName="ExtractHowDetected";        Label="How was the suspect part detected:" },
    @{ ActionName="ExtractProductDescription"; Label="Product Description:" },
    @{ ActionName="ExtractWhereDetected";      Label="Where in your process was the suspect part detected:" },
    @{ ActionName="ExtractNCRNumber";          Label="Is there a Non-Conformance Report? What is the Non-Conformance Number:" },
    @{ ActionName="ExtractOtherComments";      Label="Other Comments or explanation of your concern:" }
)

function New-ExtractExpr {
    param([string]$Label)
    $labelEsc = $Label -replace "'", "''"
    return "@trim(first(split(last(split(outputs('EmailText'), '$labelEsc')), decodeUriComponent('%0A'))))"
}

# ---------------------------------------------------------------------------
# 4. Rebuild the actions object
# ---------------------------------------------------------------------------
$newActions = [ordered]@{}

# EmailText runs first (no dependency)
$newActions["EmailText"] = [ordered]@{
    runAfter = @{}
    type     = "Compose"
    inputs   = $emailTextExpr
}

# Each extract runs after EmailText (parallel, fast)
foreach ($f in $fields) {
    $newActions[$f.ActionName] = [ordered]@{
        runAfter = @{ EmailText = @("Succeeded") }
        type     = "Compose"
        inputs   = (New-ExtractExpr -Label $f.Label)
    }
}

# Create_item: keep original action, but make runAfter wait on ALL extracts
$origCreateItem = $flow.properties.definition.actions.Create_item
$createItem = $origCreateItem | ConvertTo-Json -Depth 30 | ConvertFrom-Json -AsHashtable
$createItem.runAfter = [ordered]@{}
foreach ($f in $fields) {
    $createItem.runAfter[$f.ActionName] = @("Succeeded")
}
$newActions["Create_item"] = $createItem

# ---------------------------------------------------------------------------
# 5. Build the updated flow definition
# ---------------------------------------------------------------------------
$updatedDef = $flow.properties.definition | ConvertTo-Json -Depth 30 | ConvertFrom-Json -AsHashtable
$updatedDef.actions = $newActions

$body = @{
    properties = @{
        definition           = $updatedDef
        connectionReferences = $flow.properties.connectionReferences
    }
} | ConvertTo-Json -Depth 30

# ---------------------------------------------------------------------------
# 6. PATCH the flow
# ---------------------------------------------------------------------------
Write-Host "  Patching flow definition..." -ForegroundColor Gray
try {
    $resp = Invoke-WebRequest -Uri $flowUri -Method Patch -Headers $hdr -Body $body -ErrorAction Stop
    Write-Host "  PATCH succeeded (HTTP $($resp.StatusCode))" -ForegroundColor Green
} catch {
    $msg = $_.Exception.Message
    if ($_.ErrorDetails.Message) { $msg = $_.ErrorDetails.Message }
    Write-Host "  PATCH failed: $msg" -ForegroundColor Red
    throw
}

# ---------------------------------------------------------------------------
# 7. Verify by re-fetching
# ---------------------------------------------------------------------------
Write-Host "`n  Verifying..." -ForegroundColor Gray
$verify = Invoke-RestMethod -Uri $flowUri -Headers $hdr
Write-Host "  Actions in flow:" -ForegroundColor Cyan
$verify.properties.definition.actions.PSObject.Properties | ForEach-Object {
    Write-Host ("    - {0,-32} type={1}" -f $_.Name, $_.Value.type)
}

Write-Host "`n=== DONE ===" -ForegroundColor Cyan
Write-Host "Backup: $backupPath"
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Yellow
Write-Host "  1. Open flow in UI: https://make.preview.powerautomate.com/environments/$EnvId/flows/$FlowId/details"
Write-Host "  2. Click Test -> Manually -> use a forwarded RMA email"
Write-Host "  3. After test run completes, click into 'EmailText' to confirm it shows clean plain-text"
Write-Host "  4. Spot-check 2-3 extract outputs (Company, Email, PONumber) — should be clean values, no '<' or '>'"
Write-Host "  5. Verify the SharePoint item created has all fields populated"
Write-Host ""
Write-Host "If anything is empty for a specific field, the label string may have a slight"
Write-Host "variation (extra colon, different capitalization). Send me the email body raw"
Write-Host "and I'll tune that one extract."
