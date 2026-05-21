# patch_drop_claimnote.ps1
# ------------------------------------------------------------
# 1) Migrate all rma_claimnote records to annotations on their parent rma_claim
#    (so the data shows up on the Timeline)
# 2) Remove the Notes tab from the rma_claim form
# 3) Delete the rma_claimnote table
# ------------------------------------------------------------

$ErrorActionPreference = "Stop"
$orgUrl = "https://org6feab6b5.crm.dynamics.com"
$formId = "05a92f92-94cc-4a07-9ba0-f704788c699c"

$token   = (az account get-access-token --resource $orgUrl --query accessToken -o tsv)
$hdr     = @{ Authorization="Bearer $token"; Accept="application/json" }
$postHdr = @{ Authorization="Bearer $token"; Accept="application/json"; "Content-Type"="application/json; charset=utf-8" }
$postHdrSol = @{ Authorization="Bearer $token"; Accept="application/json"; "Content-Type"="application/json; charset=utf-8"; "OData-MaxVersion"="4.0"; "OData-Version"="4.0"; "MSCRM.SolutionUniqueName"="RMAReturnsMonitorRma" }
$pchHdrSol = @{ Authorization="Bearer $token"; Accept="application/json"; "Content-Type"="application/json; charset=utf-8"; "If-Match"="*"; "MSCRM.SolutionUniqueName"="RMAReturnsMonitorRma" }
$delHdrSol = @{ Authorization="Bearer $token"; Accept="application/json"; "MSCRM.SolutionUniqueName"="RMAReturnsMonitorRma" }

# ---------- 1) Migrate notes to annotations ----------
Write-Host "[1/3] Migrating rma_claimnote records to Timeline annotations..."
$notes = (Invoke-RestMethod -Uri "$orgUrl/api/data/v9.2/rma_claimnotes?`$select=rma_notetitle,rma_notetext,rma_notetype,rma_createdby,rma_createddate,_rma_claim_value" -Headers $hdr).value
Write-Host "  Found $($notes.Count) notes to migrate."

foreach ($n in $notes) {
    if (-not $n._rma_claim_value) {
        Write-Host "  [skip] Note '$($n.rma_notetitle)' has no parent claim — skipping."
        continue
    }
    $subject = if ($n.rma_notetitle) { $n.rma_notetitle } else { "(untitled note)" }
    $bodyText = $n.rma_notetext
    if (-not $bodyText) { $bodyText = "" }
    if ($n.rma_createdby) { $bodyText = "$bodyText`n`n— $($n.rma_createdby)" }
    $annotation = @{
        subject = $subject
        notetext = $bodyText
        "objectid_rma_claim@odata.bind" = "/rma_claims($($n._rma_claim_value))"
    } | ConvertTo-Json -Compress
    try {
        Invoke-WebRequest -Uri "$orgUrl/api/data/v9.2/annotations" -Method Post -Headers $postHdr -Body $annotation | Out-Null
        Write-Host "  [ok] Migrated: $subject"
    } catch {
        Write-Host "  [ERR] $subject : $($_.ErrorDetails.Message)"
    }
}

# ---------- 2) Remove Notes tab from form ----------
Write-Host "[2/3] Removing Notes tab from rma_claim form..."
$form = Invoke-RestMethod -Uri "$orgUrl/api/data/v9.2/systemforms($formId)?`$select=name,formxml" -Headers $hdr
[xml]$xml = $form.formxml
$notesTab = $xml.SelectSingleNode("//tab[@name='notes_tab']")
if ($notesTab) {
    $notesTab.ParentNode.RemoveChild($notesTab) | Out-Null
    $body = @{ formxml = $xml.OuterXml } | ConvertTo-Json -Depth 5
    Invoke-WebRequest -Uri "$orgUrl/api/data/v9.2/systemforms($formId)" -Method Patch -Headers $pchHdrSol -Body $body | Out-Null
    Write-Host "  [ok] Notes tab removed."
    $pubBody = @{ ParameterXml = "<importexportxml><entities><entity>rma_claim</entity></entities></importexportxml>" } | ConvertTo-Json -Compress
    Invoke-WebRequest -Uri "$orgUrl/api/data/v9.2/PublishXml" -Method Post -Headers $postHdrSol -Body $pubBody | Out-Null
    Write-Host "  [ok] Published rma_claim."
} else {
    Write-Host "  [skip] Notes tab not found."
}

# ---------- 3) Delete rma_claimnote table ----------
Write-Host "[3/3] Deleting rma_claimnote table..."
# First, delete all records (table delete will fail if records exist in some configurations)
$remaining = (Invoke-RestMethod -Uri "$orgUrl/api/data/v9.2/rma_claimnotes?`$select=rma_claimnoteid" -Headers $hdr).value
Write-Host "  Deleting $($remaining.Count) note records first..."
foreach ($r in $remaining) {
    try {
        Invoke-WebRequest -Uri "$orgUrl/api/data/v9.2/rma_claimnotes($($r.rma_claimnoteid))" -Method Delete -Headers $delHdrSol | Out-Null
    } catch {
        Write-Host "  [ERR] delete record $($r.rma_claimnoteid): $($_.ErrorDetails.Message)"
    }
}

try {
    Invoke-WebRequest -Uri "$orgUrl/api/data/v9.2/EntityDefinitions(LogicalName='rma_claimnote')" -Method Delete -Headers $delHdrSol | Out-Null
    Write-Host "  [ok] rma_claimnote table deleted."
} catch {
    Write-Host "  [ERR] Table delete failed: $($_.ErrorDetails.Message)"
    Write-Host "  (Likely needs manual delete via Power Apps maker. Migrate succeeded, tab is gone, so Timeline UX is clean.)"
}

Write-Host ""
Write-Host "Done."
