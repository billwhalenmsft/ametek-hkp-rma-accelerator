<#
.SYNOPSIS
    Pizza Tracker — HTML web resource that renders 5-dot progress bar on
    rma_claim form. Shows current stage, age in stage, total age.

    Reads from the parent form via Xrm.Page (classic) / parent.Xrm (UCI).
    Falls back to fetching the record via Web API if needed.

    Visual:
      [● New] --- [● Triage] --- [○ Investigation] --- [○ Decision] --- [○ Closed]
      In Triage for 3 days | Total age: 7 days
#>

[CmdletBinding()]
param(
    [string]$OrgUrl = "https://org6feab6b5.crm.dynamics.com"
)

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
    if ($Body) {
        $params.Body = if ($Body -is [string]) { $Body } else { ($Body | ConvertTo-Json -Depth 30 -Compress) }
    }
    if ($ReturnHeaders) { return Invoke-WebRequest @params }
    return Invoke-RestMethod @params
}

Write-Host "`n=== Pizza Tracker HTML web resource ===`n" -ForegroundColor Cyan

# ----------------------------------------------------------------------------
# The HTML — self-contained, no external deps
# ----------------------------------------------------------------------------
$html = @'
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8" />
<meta http-equiv="X-UA-Compatible" content="IE=edge" />
<style>
  * { box-sizing: border-box; }
  body {
    margin: 0;
    font-family: "Segoe UI", system-ui, -apple-system, sans-serif;
    color: #1a1f2c;
    background: #ffffff;
    font-size: 13px;
    overflow: hidden;
  }
  .tracker {
    padding: 14px 24px 18px;
  }
  .track-row {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 4px;
    margin-bottom: 10px;
  }
  .step {
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 4px;
    flex: 0 0 auto;
    min-width: 96px;
    text-align: center;
    position: relative;
  }
  .step .dot {
    width: 32px;
    height: 32px;
    border-radius: 50%;
    border: 3px solid #d0d4dc;
    background: #ffffff;
    display: flex;
    align-items: center;
    justify-content: center;
    font-size: 14px;
    font-weight: 700;
    color: #8a8f9a;
    transition: all 0.2s ease;
    z-index: 2;
  }
  .step .label {
    font-size: 12px;
    color: #5b6577;
    white-space: nowrap;
  }
  .step.done .dot {
    border-color: #107C10;
    background: #107C10;
    color: white;
  }
  .step.done .label {
    color: #1a1f2c;
    font-weight: 500;
  }
  .step.current .dot {
    border-color: var(--current-color, #0078D4);
    background: var(--current-color, #0078D4);
    color: white;
    box-shadow: 0 0 0 4px rgba(0, 120, 212, 0.18);
    animation: pulse 2s ease-in-out infinite;
  }
  .step.current .label {
    color: var(--current-color, #0078D4);
    font-weight: 700;
  }
  @keyframes pulse {
    0%, 100% { box-shadow: 0 0 0 4px rgba(0, 120, 212, 0.18); }
    50% { box-shadow: 0 0 0 8px rgba(0, 120, 212, 0.08); }
  }
  .connector {
    flex: 1 1 auto;
    height: 3px;
    background: #d0d4dc;
    margin-top: -22px;
    margin-bottom: 22px;
    z-index: 1;
    min-width: 20px;
  }
  .connector.done {
    background: #107C10;
  }
  .meta-row {
    display: flex;
    gap: 24px;
    padding-top: 8px;
    border-top: 1px solid #eef0f4;
    font-size: 12px;
    color: #5b6577;
  }
  .meta-row .meta-item {
    display: flex;
    align-items: center;
    gap: 6px;
  }
  .meta-row .meta-item b {
    color: #1a1f2c;
    font-weight: 600;
  }
  .meta-row .meta-pill {
    padding: 2px 10px;
    border-radius: 12px;
    font-size: 11px;
    font-weight: 600;
  }
  .meta-pill.stale {
    background: #fee2e2;
    color: #991b1b;
  }
  .meta-pill.fresh {
    background: #dcfce7;
    color: #166534;
  }
  .meta-pill.normal {
    background: #e0f2fe;
    color: #075985;
  }
  .empty {
    padding: 16px 24px;
    color: #8a8f9a;
    font-style: italic;
    font-size: 12px;
  }
</style>
</head>
<body>
<div id="root">
  <div class="empty">Loading…</div>
</div>

<script>
(function() {
  // 5-stage pizza tracker for rma_claim
  // Stage order matches rma_status picklist:
  //   100000000 New
  //   100000001 Triage
  //   100000002 Investigation
  //   100000003 Decision
  //   100000004 Closed

  var STAGES = [
    { value: 100000000, label: "New",           color: "#0078D4" },
    { value: 100000001, label: "Triage",        color: "#F2A60E" },
    { value: 100000002, label: "Investigation", color: "#8264CC" },
    { value: 100000003, label: "Decision",      color: "#D17F1A" },
    { value: 100000004, label: "Closed",        color: "#107C10" }
  ];

  function getXrm() {
    // Try multiple paths to find Xrm context (form is in iframe)
    if (window.parent && window.parent.Xrm) return window.parent.Xrm;
    if (window.Xrm) return window.Xrm;
    return null;
  }

  function getRecordId() {
    var xrm = getXrm();
    if (!xrm) return null;
    try {
      if (xrm.Page && xrm.Page.data && xrm.Page.data.entity) {
        var id = xrm.Page.data.entity.getId();
        return id ? id.replace(/[{}]/g, "") : null;
      }
      // Modern UCI form context — get from parent's formContext
      // We may not have direct access, fall back to URL parse
    } catch (e) {}

    // Fallback: parse the parent URL for ?id=... or /rma_claim/<guid>/
    try {
      var url = window.parent.location.href;
      var m = url.match(/id=([0-9a-fA-F-]{36})/);
      if (m) return m[1];
      m = url.match(/\/rma_claim\/([0-9a-fA-F-]{36})/);
      if (m) return m[1];
    } catch (e) {}
    return null;
  }

  function fetchClaim(id, callback) {
    var url = "/api/data/v9.2/rma_claims(" + id +
      ")?$select=rma_status,rma_stageenteredon,rma_createddate,rma_claimnumber";
    var req = new XMLHttpRequest();
    req.open("GET", url, true);
    req.setRequestHeader("Accept", "application/json");
    req.setRequestHeader("OData-Version", "4.0");
    req.setRequestHeader("OData-MaxVersion", "4.0");
    req.onreadystatechange = function() {
      if (req.readyState === 4) {
        if (req.status === 200) {
          callback(null, JSON.parse(req.responseText));
        } else {
          callback(req.status + ": " + req.statusText, null);
        }
      }
    };
    req.send();
  }

  function daysBetween(a, b) {
    if (!a || !b) return 0;
    var ms = new Date(b).getTime() - new Date(a).getTime();
    return Math.max(0, Math.floor(ms / (1000 * 60 * 60 * 24)));
  }

  function render(claim) {
    var statusVal = claim.rma_status;
    var currentIdx = -1;
    for (var i = 0; i < STAGES.length; i++) {
      if (STAGES[i].value === statusVal) { currentIdx = i; break; }
    }

    var stageAge = claim.rma_stageenteredon ? daysBetween(claim.rma_stageenteredon, new Date()) : null;
    var totalAge = claim.rma_createddate ? daysBetween(claim.rma_createddate, new Date()) : null;
    var currentStage = currentIdx >= 0 ? STAGES[currentIdx] : null;

    var html = '<div class="tracker">';

    // Track row
    html += '<div class="track-row">';
    for (var j = 0; j < STAGES.length; j++) {
      var s = STAGES[j];
      var cls = "step";
      if (currentIdx >= 0 && j < currentIdx) cls += " done";
      if (j === currentIdx) cls += " current";
      var styleVar = j === currentIdx ? ('style="--current-color: ' + s.color + '"') : '';
      html += '<div class="' + cls + '" ' + styleVar + '>';
      html += '<div class="dot">' + (j === currentIdx ? '●' : (j < currentIdx ? '✓' : (j + 1))) + '</div>';
      html += '<div class="label">' + s.label + '</div>';
      html += '</div>';
      if (j < STAGES.length - 1) {
        var conn = "connector";
        if (currentIdx >= 0 && j < currentIdx) conn += " done";
        html += '<div class="' + conn + '"></div>';
      }
    }
    html += '</div>';

    // Meta row
    html += '<div class="meta-row">';

    if (currentStage) {
      var pillClass = "normal";
      if (stageAge !== null) {
        if (stageAge >= 7) pillClass = "stale";
        else if (stageAge <= 1) pillClass = "fresh";
      }
      html += '<div class="meta-item">';
      html += '<span>In </span><b>' + currentStage.label + '</b><span> for </span>';
      if (stageAge !== null) {
        html += '<span class="meta-pill ' + pillClass + '">' + stageAge + ' day' + (stageAge === 1 ? '' : 's') + '</span>';
      } else {
        html += '<span class="meta-pill normal">just now</span>';
      }
      html += '</div>';
    }

    if (totalAge !== null) {
      html += '<div class="meta-item"><span>Total age: </span><b>' + totalAge + ' day' + (totalAge === 1 ? '' : 's') + '</b></div>';
    }

    if (claim.rma_claimnumber) {
      html += '<div class="meta-item" style="margin-left:auto"><b>' + claim.rma_claimnumber + '</b></div>';
    }

    html += '</div>';
    html += '</div>';

    document.getElementById("root").innerHTML = html;
  }

  function showError(msg) {
    document.getElementById("root").innerHTML =
      '<div class="empty">' + (msg || "Could not load claim.") + '</div>';
  }

  function init() {
    var id = getRecordId();
    if (!id) {
      // Try again after a delay — form may still be loading
      setTimeout(function() {
        var retryId = getRecordId();
        if (!retryId) {
          showError("No claim selected.");
        } else {
          fetchClaim(retryId, function(err, claim) {
            if (err) showError(err); else render(claim);
          });
        }
      }, 800);
      return;
    }
    fetchClaim(id, function(err, claim) {
      if (err) showError(err); else render(claim);
    });
  }

  if (document.readyState === "complete" || document.readyState === "interactive") {
    init();
  } else {
    document.addEventListener("DOMContentLoaded", init);
  }
})();
</script>
</body>
</html>
'@

# ----------------------------------------------------------------------------
# Upload as web resource
# ----------------------------------------------------------------------------
$wrName = "rma_/pizzatracker/rma_pizza_tracker.html"
$wrDisplayName = "RMA Pizza Tracker"

$bytes = [System.Text.Encoding]::UTF8.GetBytes($html)
$b64 = [Convert]::ToBase64String($bytes)

$existing = (Invoke-Dv -Method GET -Path "webresourceset?`$filter=name eq '$wrName'&`$select=webresourceid,name").value
if ($existing.Count -gt 0) {
    $wrId = $existing[0].webresourceid
    Write-Host "  [skip] webresource exists -> $wrId  (updating content)" -ForegroundColor DarkGray
    Invoke-Dv -Method PATCH -Path "webresourceset($wrId)" -Body @{
        content     = $b64
        displayname = $wrDisplayName
    } | Out-Null
} else {
    $body = @{
        name             = $wrName
        displayname      = $wrDisplayName
        webresourcetype  = 1   # HTML
        content          = $b64
        description      = "Visual progress tracker showing claim stage + age on rma_claim form."
        languagecode     = 1033
    }
    $resp = Invoke-Dv -Method POST -Path "webresourceset" -Body $body -ReturnHeaders
    $loc = $resp.Headers['OData-EntityId']
    if ($loc -is [array]) { $loc = $loc[0] }
    if ($loc -match '\(([0-9a-fA-F\-]{36})\)') { $wrId = $matches[1] }
    Write-Host "  [create] webresource -> $wrId" -ForegroundColor Green
}

# Publish web resource
Write-Host "`nPublishing web resource..." -ForegroundColor Cyan
try {
    $publishXml = "<importexportxml><webresources><webresource>$wrId</webresource></webresources></importexportxml>"
    $body = @{ ParameterXml = $publishXml } | ConvertTo-Json -Compress
    $h = $hdrBase.Clone(); $h['Content-Type'] = 'application/json; charset=utf-8'
    Invoke-WebRequest -Uri "$OrgUrl/api/data/v9.2/PublishXml" -Method Post -Headers $h -Body $body -TimeoutSec 60 -ErrorAction Stop | Out-Null
    Write-Host "  [ok] publish" -ForegroundColor Green
} catch {
    $m = $_.Exception.Message
    if ($_.ErrorDetails.Message) { $m = $_.ErrorDetails.Message }
    Write-Host "  [warn] publish: $m" -ForegroundColor DarkYellow
}

Write-Host "`n=== DONE ===" -ForegroundColor Cyan
Write-Host ""
Write-Host "Web resource:    $wrName" -ForegroundColor Cyan
Write-Host "Web resource ID: $wrId" -ForegroundColor Cyan
Write-Host ""
Write-Host "Preview directly in a browser:" -ForegroundColor Yellow
Write-Host "  $OrgUrl/WebResources/$wrName" -ForegroundColor Gray
Write-Host ""
Write-Host "To put on the rma_claim form (~1 min in maker UI):" -ForegroundColor Yellow
Write-Host "  1. Open the rma_claim main form in form designer"
Write-Host "  2. Add a NEW SECTION at the top of the first tab — 1 column, no label"
Write-Host "  3. Drop a 'Web Resource' component into that section"
Write-Host "  4. Pick: rma_/pizzatracker/rma_pizza_tracker.html"
Write-Host "  5. Set height ~ 110px, scrolling off, border off"
Write-Host "  6. Save + Publish the form"
Write-Host ""
Write-Host "Tracker will render automatically using the form's record context." -ForegroundColor DarkGray
