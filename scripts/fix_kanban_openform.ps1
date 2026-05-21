<#
.SYNOPSIS
    Fix pp_kanban openForm to use the MDA's Xrm context directly (not the
    iframe-wrapper context). This eliminates the "two Dynamics headers"
    double-render Bill sees when clicking a card.

    The pattern: walk window.parent.parent chain until we find an Xrm context
    that has Navigation.openForm. Then call it from there. This unwinds the
    iframe nesting cleanly.
#>

[CmdletBinding()]
param([string]$OrgUrl = "https://org6feab6b5.crm.dynamics.com")
$ErrorActionPreference = "Stop"
$token = (az account get-access-token --resource $OrgUrl --query accessToken -o tsv)
$hdr = @{ Authorization="Bearer $token"; Accept="application/json"; "Content-Type"="application/json; charset=utf-8"; "If-Match"="*"; "MSCRM.SolutionUniqueName"="RMAReturnsMonitor" }

# Get current HTML
$gr = Invoke-RestMethod -Uri "$OrgUrl/api/data/v9.2/webresourceset?`$filter=name eq 'pp_/kanban/kanban.html'&`$select=webresourceid,content" -Headers @{Authorization="Bearer $token"; Accept="application/json"}
$wrId = $gr.value[0].webresourceid
$bytes = [Convert]::FromBase64String($gr.value[0].content)
$html = [Text.Encoding]::UTF8.GetString($bytes)

# ---- Replace getXrm() and openRecord() with iframe-walking versions ----
$oldGetXrm = @'
  function getXrm() {
    if (window.parent && window.parent.Xrm) return window.parent.Xrm;
    if (window.Xrm) return window.Xrm;
    return null;
  }
'@

$newGetXrm = @'
  function getXrm() {
    // Walk up the iframe chain to find the topmost MDA Xrm context.
    // This avoids the "two Dynamics headers" stacked render when kanban is
    // wrapped in an MDA shell webresource pagetype.
    try {
      var w = window;
      var visited = 0;
      while (w && visited < 10) {
        if (w.Xrm && w.Xrm.Navigation && w.Xrm.Navigation.openForm) return w.Xrm;
        if (w === w.parent) break;
        w = w.parent;
        visited++;
      }
    } catch (e) { /* cross-origin or detached */ }
    if (window.parent && window.parent.Xrm) return window.parent.Xrm;
    if (window.Xrm) return window.Xrm;
    return null;
  }
'@

$oldOpen = @'
  function openRecord(recordId) {
    if (cfg.onclick !== "form") return;
    var xrm = getXrm();
    if (xrm && xrm.Navigation && xrm.Navigation.openForm) {
      xrm.Navigation.openForm({ entityName: cfg.entity, entityId: recordId });
    } else {
      var u = clientUrl() + "/main.aspx?etn=" + cfg.entity + "&id=%7B" + recordId + "%7D&pagetype=entityrecord";
      window.parent.location = u;
    }
  }
'@

$newOpen = @'
  function openRecord(recordId) {
    if (cfg.onclick !== "form") return;
    var xrm = getXrm();
    if (xrm && xrm.Navigation && xrm.Navigation.openForm) {
      // openMode: 1 = inline (same window, no iframe wrap)
      // useQuickCreateForm: false ensures we get the main form
      xrm.Navigation.openForm({
        entityName: cfg.entity,
        entityId: recordId,
        openInNewWindow: false,
        useQuickCreateForm: false
      }).catch(function(){
        // Fallback if openForm fails
        var u = clientUrl() + "/main.aspx?etn=" + cfg.entity + "&id=%7B" + recordId + "%7D&pagetype=entityrecord";
        try { window.top.location = u; } catch (e) { window.parent.location = u; }
      });
    } else {
      // No Xrm context — fall back to direct URL navigation on the TOP window
      // (not parent) so we replace the whole MDA shell instead of nesting.
      var u = clientUrl() + "/main.aspx?etn=" + cfg.entity + "&id=%7B" + recordId + "%7D&pagetype=entityrecord";
      try { window.top.location = u; } catch (e) { window.parent.location = u; }
    }
  }
'@

if ($html -notmatch [regex]::Escape($oldGetXrm)) { throw "Could not find old getXrm block to replace" }
if ($html -notmatch [regex]::Escape($oldOpen)) { throw "Could not find old openRecord block to replace" }

$html = $html.Replace($oldGetXrm, $newGetXrm).Replace($oldOpen, $newOpen)

# Upload
$newB64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($html))
Invoke-WebRequest -Uri "$OrgUrl/api/data/v9.2/webresourceset($wrId)" -Method Patch -Headers $hdr -Body (@{ content=$newB64 } | ConvertTo-Json -Compress) | Out-Null
Write-Host "[ok] pp_kanban patched with iframe-walking openForm" -ForegroundColor Green

# Publish via pac (REST publish hangs in this env)
Write-Host "Publishing via pac CLI..." -ForegroundColor Cyan
pac auth select --name mfg-gold 2>&1 | Out-Null
pac solution publish 2>&1 | Select-Object -Last 5
