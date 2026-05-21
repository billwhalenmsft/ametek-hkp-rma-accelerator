# Wrap selected Create_item bindings with a 255-char safe substring expression
# to prevent SharePoint single-line-text overflow errors.
#
# Triggered by: 'The API operation PostItem requires the property
#               item/ComplaintReasonOther to be a string of maximum length 255
#               but is of length 303.'
#
# This patch wraps ALL 16 prompt-derived bindings with the same guard so we don't
# whack-a-mole if other long values come through later. Trigger-level bindings
# (Subject, From, BodyFull, etc.) are NOT touched.

[CmdletBinding()]
param(
    [string]$EnvId  = "2404ccaf-d7e5-e1ff-863a-3ecbe2f0f013",
    [string]$FlowId = "b26a7f4b-b181-cd5e-ff45-454939890b06"
)

$ErrorActionPreference = "Stop"

$paToken = (az account get-access-token --resource "https://service.flow.microsoft.com/" --query accessToken -o tsv)
if (-not $paToken) { throw "No PA token." }
$hdr = @{ Authorization = "Bearer $paToken"; "Content-Type" = "application/json" }
$flowUri = "https://api.flow.microsoft.com/providers/Microsoft.ProcessSimple/environments/$EnvId/flows/$FlowId" + "?api-version=2016-11-01"

Write-Host "  Fetching flow..." -ForegroundColor Gray
$flow = Invoke-RestMethod -Uri $flowUri -Headers $hdr

$updatedDef = $flow.properties.definition | ConvertTo-Json -Depth 30 | ConvertFrom-Json -AsHashtable

$promptFields = @(
    "Company","Phone","ReturnAddress","Quantity","PONumber","DateCodeOrSerial",
    "PartNumber","MfgLocation","ComplaintReason","ComplaintReasonOther","SalesRep",
    "HowDetected","ProductDescription","WhereDetected","NCRNumber","OtherComments"
)

$createParams = $updatedDef.actions.Create_item.inputs.parameters
$changed = 0
foreach ($p in $promptFields) {
    $key = "item/$p"
    if (-not $createParams.ContainsKey($key)) { continue }
    $current = $createParams[$key]
    # Only rewrite if it's the simple body('Parse_RMA_Fields')?['Field'] form
    if ($current -match "^@body\('Parse_RMA_Fields'\)\?\['$p'\]$") {
        $createParams[$key] = "@if(greater(length(coalesce(body('Parse_RMA_Fields')?['$p'],'')), 255), substring(body('Parse_RMA_Fields')?['$p'], 0, 255), coalesce(body('Parse_RMA_Fields')?['$p'],''))"
        $changed++
    }
}

Write-Host "  Rewrote $changed bindings with length-safe substring guard" -ForegroundColor Green

$body = @{
    properties = @{
        definition           = $updatedDef
        connectionReferences = $flow.properties.connectionReferences
    }
} | ConvertTo-Json -Depth 30

Write-Host "  PATCHing..." -ForegroundColor Gray
$resp = Invoke-WebRequest -Uri $flowUri -Method Patch -Headers $hdr -Body $body
Write-Host "  PATCH succeeded (HTTP $($resp.StatusCode))" -ForegroundColor Green
Write-Host ""
Write-Host "Re-test the flow. The 303-char ComplaintReasonOther will now be"
Write-Host "truncated to 255 chars before hitting SharePoint." -ForegroundColor Cyan
Write-Host ""
Write-Host "If you want to KEEP the full text (vs truncate), change that one column"
Write-Host "in the SharePoint list from 'Single line of text' to 'Multiple lines of"
Write-Host "text' (Settings -> column -> change type) and re-test. The flow truncation"
Write-Host "will pass through any value <= 255 chars unchanged." -ForegroundColor Yellow
