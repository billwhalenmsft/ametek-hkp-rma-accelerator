<#
.SYNOPSIS
    Build pp_kanban — a portable, config-driven Kanban web resource.

    Configurable via URL query string:
      entity      logical name of the entity (rma_claim)
      group       logical name of the choice/status field to group by (rma_status)
      title       attribute used as card title (rma_claimnumber)
      subtitle    optional subtitle attribute (rma_customername)
      fields      comma list of additional fields to show on the card
      badge       attribute for age/score pill on the card header
      filter      OData $filter for the query
      onclick     'form' | 'none'  (default 'form')
      orderby     attribute for in-column sort (default badge field)

    Embed in any solution as Web Resource:
      pp_/kanban/kanban.html?entity=rma_claim&group=rma_status&title=rma_claimnumber&subtitle=rma_customername&fields=rma_partnumber,rma_assignedplant,rma_creditamount&badge=rma_stageagedays&filter=statecode eq 0
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

# ----------------------------------------------------------------------------
# Kanban HTML (single self-contained file)
# ----------------------------------------------------------------------------
$html = @'
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8" />
<meta http-equiv="X-UA-Compatible" content="IE=edge" />
<title>pp-kanban</title>
<style>
  * { box-sizing: border-box; }
  html, body {
    margin: 0; height: 100%;
    font-family: "Segoe UI", system-ui, -apple-system, sans-serif;
    color: #1a1f2c; background: #f7f8fb; font-size: 13px;
    overflow: hidden;
  }
  .ppk-board {
    display: flex; gap: 12px; padding: 14px;
    height: 100%; overflow-x: auto; overflow-y: hidden;
  }
  .ppk-col {
    flex: 0 0 280px; max-width: 280px;
    background: #ffffff; border-radius: 8px;
    border: 1px solid #e3e7ee;
    display: flex; flex-direction: column;
    overflow: hidden;
  }
  .ppk-col-head {
    padding: 10px 14px; border-bottom: 1px solid #e3e7ee;
    display: flex; align-items: center; gap: 8px;
    background: #fafbfd;
  }
  .ppk-col-dot {
    width: 10px; height: 10px; border-radius: 50%;
    flex: 0 0 10px;
  }
  .ppk-col-title {
    font-weight: 600; font-size: 13px; flex: 1; white-space: nowrap;
    overflow: hidden; text-overflow: ellipsis;
  }
  .ppk-col-count {
    background: #eef2f7; color: #5b6577;
    padding: 2px 8px; border-radius: 10px; font-size: 11px; font-weight: 600;
  }
  .ppk-col-body {
    flex: 1; overflow-y: auto; padding: 8px;
    display: flex; flex-direction: column; gap: 8px;
  }
  .ppk-card {
    background: #ffffff; border: 1px solid #e3e7ee;
    border-radius: 6px; padding: 10px 12px;
    cursor: pointer; transition: all 0.15s ease;
    border-left: 3px solid var(--card-accent, #d0d4dc);
  }
  .ppk-card:hover {
    border-color: #0078D4; box-shadow: 0 2px 6px rgba(0, 120, 212, 0.12);
    transform: translateY(-1px);
  }
  .ppk-card-head {
    display: flex; justify-content: space-between; align-items: center;
    gap: 8px; margin-bottom: 6px;
  }
  .ppk-card-title {
    font-weight: 700; font-size: 13px; color: #1a1f2c;
    white-space: nowrap; overflow: hidden; text-overflow: ellipsis;
    flex: 1;
  }
  .ppk-badge {
    flex: 0 0 auto; font-size: 11px; font-weight: 600;
    padding: 2px 8px; border-radius: 10px; white-space: nowrap;
  }
  .ppk-badge.fresh { background: #dcfce7; color: #166534; }
  .ppk-badge.normal { background: #e0f2fe; color: #075985; }
  .ppk-badge.stale { background: #fef3c7; color: #92400e; }
  .ppk-badge.overdue { background: #fee2e2; color: #991b1b; }
  .ppk-card-subtitle {
    font-size: 12px; color: #5b6577;
    white-space: nowrap; overflow: hidden; text-overflow: ellipsis;
    margin-bottom: 6px;
  }
  .ppk-card-fields {
    display: flex; flex-direction: column; gap: 3px;
    font-size: 11px; color: #5b6577;
  }
  .ppk-card-field { display: flex; gap: 6px; align-items: center; }
  .ppk-card-field .ppk-fkey { color: #8a8f9a; min-width: 54px; }
  .ppk-card-field .ppk-fval { color: #1a1f2c; font-weight: 500; flex: 1; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
  .ppk-empty {
    padding: 24px 12px; text-align: center; color: #8a8f9a;
    font-style: italic; font-size: 12px;
  }
  .ppk-loading {
    padding: 24px; text-align: center; color: #5b6577;
  }
  .ppk-error {
    padding: 16px; background: #fee2e2; color: #991b1b;
    border-radius: 6px; margin: 14px;
  }
</style>
</head>
<body>
<div id="ppk-root"><div class="ppk-loading">Loading…</div></div>

<script>
(function() {
  "use strict";

  // ====================================================================
  // pp-kanban  v1.0
  // Reusable Dataverse Kanban web resource. Config via URL query string.
  // ====================================================================

  function qs() {
    var p = {}, q = window.location.search.replace(/^\?/, "");
    if (!q) return p;
    q.split("&").forEach(function(kv) {
      var idx = kv.indexOf("=");
      var k = idx >= 0 ? kv.substring(0, idx) : kv;
      var v = idx >= 0 ? kv.substring(idx + 1) : "";
      p[decodeURIComponent(k)] = decodeURIComponent((v || "").replace(/\+/g, " "));
    });
    return p;
  }

  var cfg = (function() {
    var p = qs();
    return {
      entity:   p.entity || "",
      group:    p.group || "",
      title:    p.title || "",
      subtitle: p.subtitle || "",
      fields:   (p.fields || "").split(",").map(function(s){ return s.trim(); }).filter(Boolean),
      badge:    p.badge || "",
      filter:   p.filter || "",
      onclick:  p.onclick || "form",
      orderby:  p.orderby || ""
    };
  })();

  function getXrm() {
    if (window.parent && window.parent.Xrm) return window.parent.Xrm;
    if (window.Xrm) return window.Xrm;
    return null;
  }

  function clientUrl() {
    var xrm = getXrm();
    if (xrm) {
      try {
        var c = xrm.Utility.getGlobalContext().getClientUrl();
        if (c) return c;
      } catch (e) {}
    }
    return "";
  }

  function api(path, callback) {
    var base = clientUrl();
    var url = base + "/api/data/v9.2/" + path;
    var req = new XMLHttpRequest();
    req.open("GET", url, true);
    req.setRequestHeader("Accept", "application/json");
    req.setRequestHeader("OData-Version", "4.0");
    req.setRequestHeader("OData-MaxVersion", "4.0");
    req.setRequestHeader("Prefer", 'odata.include-annotations="*"');
    req.onreadystatechange = function() {
      if (req.readyState === 4) {
        if (req.status >= 200 && req.status < 300) {
          callback(null, req.responseText ? JSON.parse(req.responseText) : null);
        } else {
          var msg = req.statusText;
          try { msg = JSON.parse(req.responseText).error.message; } catch(e){}
          callback(msg, null);
        }
      }
    };
    req.send();
  }

  function entitySetName(entity, cb) {
    api("EntityDefinitions(LogicalName='" + entity + "')?$select=LogicalCollectionName,PrimaryIdAttribute,PrimaryNameAttribute,ObjectTypeCode", function(err, r) {
      if (err) return cb(err);
      cb(null, {
        entitySet: r.LogicalCollectionName,
        primaryKey: r.PrimaryIdAttribute,
        primaryName: r.PrimaryNameAttribute,
        objectTypeCode: r.ObjectTypeCode
      });
    });
  }

  function loadGroupOptions(entity, attr, cb) {
    var path = "EntityDefinitions(LogicalName='" + entity + "')/Attributes(LogicalName='" + attr +
      "')/Microsoft.Dynamics.CRM.PicklistAttributeMetadata?$select=LogicalName&$expand=OptionSet";
    api(path, function(err, r) {
      if (err) return cb(err);
      var opts = (r.OptionSet && r.OptionSet.Options) || [];
      var mapped = opts.map(function(o) {
        var color = o.Color;
        var label = "";
        if (o.Label && o.Label.UserLocalizedLabel) label = o.Label.UserLocalizedLabel.Label;
        else if (o.Label && o.Label.LocalizedLabels && o.Label.LocalizedLabels[0]) label = o.Label.LocalizedLabels[0].Label;
        return { value: o.Value, label: label || ("Option " + o.Value), color: color || "#5b6577" };
      });
      cb(null, mapped);
    });
  }

  function buildSelect() {
    var fields = [cfg.title, cfg.subtitle, cfg.group, cfg.badge].concat(cfg.fields).filter(Boolean);
    return Array.from(new Set(fields)).join(",");
  }

  function buildOrderBy() {
    if (cfg.orderby) return cfg.orderby + " desc";
    if (cfg.badge) return cfg.badge + " desc";
    return "createdon desc";
  }

  function loadRecords(meta, cb) {
    var path = meta.entitySet + "?$select=" + meta.primaryKey + "," + buildSelect();
    if (cfg.filter) path += "&$filter=" + encodeURIComponent(cfg.filter);
    path += "&$orderby=" + buildOrderBy();
    path += "&$top=500";
    api(path, function(err, r) {
      if (err) return cb(err);
      cb(null, (r && r.value) || []);
    });
  }

  function getFormatted(rec, attr) {
    var fv = rec[attr + "@OData.Community.Display.V1.FormattedValue"];
    if (fv !== undefined) return fv;
    var v = rec[attr];
    if (v === null || v === undefined) return "";
    return String(v);
  }

  function getValue(rec, attr) {
    return rec["_" + attr + "_value"] !== undefined
      ? rec["_" + attr + "_value"]
      : rec[attr];
  }

  function ageBadgeClass(days) {
    if (days === null || days === undefined) return "normal";
    var n = Number(days);
    if (isNaN(n)) return "normal";
    if (n <= 1) return "fresh";
    if (n <= 5) return "normal";
    if (n <= 14) return "stale";
    return "overdue";
  }

  function ageBadgeText(days) {
    if (days === null || days === undefined || days === "") return "";
    var n = Number(days);
    if (isNaN(n)) return String(days);
    return n + "d";
  }

  function openRecord(meta, recordId) {
    if (cfg.onclick !== "form") return;
    var xrm = getXrm();
    if (xrm && xrm.Navigation && xrm.Navigation.openForm) {
      xrm.Navigation.openForm({
        entityName: cfg.entity,
        entityId: recordId
      });
    } else {
      var u = clientUrl() + "/main.aspx?etn=" + cfg.entity + "&id=%7B" + recordId + "%7D&pagetype=entityrecord";
      window.parent.location = u;
    }
  }

  function render(meta, options, records) {
    // Group records by the group attr value
    var byGroup = {};
    options.forEach(function(o) { byGroup[o.value] = []; });
    var ungrouped = [];

    records.forEach(function(r) {
      var v = r[cfg.group];
      if (v !== undefined && v !== null && byGroup[v]) byGroup[v].push(r);
      else ungrouped.push(r);
    });

    var root = document.getElementById("ppk-root");
    var html = '<div class="ppk-board">';

    options.forEach(function(o) {
      var rows = byGroup[o.value] || [];
      html += '<div class="ppk-col">';
      html += '<div class="ppk-col-head">';
      html += '<span class="ppk-col-dot" style="background:' + (o.color || "#5b6577") + '"></span>';
      html += '<span class="ppk-col-title">' + escapeHtml(o.label) + '</span>';
      html += '<span class="ppk-col-count">' + rows.length + '</span>';
      html += '</div>';
      html += '<div class="ppk-col-body">';
      if (rows.length === 0) {
        html += '<div class="ppk-empty">No items</div>';
      } else {
        rows.forEach(function(rec) {
          html += renderCard(rec, o, meta);
        });
      }
      html += '</div></div>';
    });

    if (ungrouped.length > 0) {
      html += '<div class="ppk-col">';
      html += '<div class="ppk-col-head">';
      html += '<span class="ppk-col-dot" style="background:#8a8f9a"></span>';
      html += '<span class="ppk-col-title">Unset</span>';
      html += '<span class="ppk-col-count">' + ungrouped.length + '</span>';
      html += '</div>';
      html += '<div class="ppk-col-body">';
      ungrouped.forEach(function(rec) { html += renderCard(rec, { color:"#8a8f9a" }, meta); });
      html += '</div></div>';
    }

    html += '</div>';
    root.innerHTML = html;

    // Wire click handlers
    var cards = root.querySelectorAll(".ppk-card");
    for (var i = 0; i < cards.length; i++) {
      cards[i].addEventListener("click", (function(id) {
        return function() { openRecord(meta, id); };
      })(cards[i].getAttribute("data-id")));
    }
  }

  function renderCard(rec, option, meta) {
    var id = rec[meta.primaryKey];
    var titleVal = cfg.title ? getFormatted(rec, cfg.title) : (rec[meta.primaryName] || "");
    var subtitleVal = cfg.subtitle ? getFormatted(rec, cfg.subtitle) : "";
    var badgeRaw = cfg.badge ? rec[cfg.badge] : "";
    var badgeText = ageBadgeText(badgeRaw);
    var badgeClass = ageBadgeClass(badgeRaw);

    var html = '<div class="ppk-card" data-id="' + escapeAttr(id) + '" style="--card-accent: ' + (option.color || "#d0d4dc") + '">';
    html += '<div class="ppk-card-head">';
    html += '<div class="ppk-card-title">' + escapeHtml(titleVal) + '</div>';
    if (badgeText) html += '<div class="ppk-badge ' + badgeClass + '">' + badgeText + '</div>';
    html += '</div>';
    if (subtitleVal) html += '<div class="ppk-card-subtitle">' + escapeHtml(subtitleVal) + '</div>';
    if (cfg.fields.length > 0) {
      html += '<div class="ppk-card-fields">';
      cfg.fields.forEach(function(f) {
        var v = getFormatted(rec, f);
        if (!v) return;
        html += '<div class="ppk-card-field">';
        html += '<span class="ppk-fkey">' + escapeHtml(prettyName(f)) + ':</span>';
        html += '<span class="ppk-fval">' + escapeHtml(v) + '</span>';
        html += '</div>';
      });
      html += '</div>';
    }
    html += '</div>';
    return html;
  }

  function prettyName(logical) {
    // Strip prefix, then split by underscore + title-case
    var base = logical.replace(/^[a-z]+_/, "");
    return base.split("_").map(function(s){ return s.charAt(0).toUpperCase() + s.slice(1); }).join(" ");
  }

  function escapeHtml(s) {
    return String(s).replace(/[&<>"']/g, function(c) {
      return { "&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;" }[c];
    });
  }
  function escapeAttr(s) { return escapeHtml(s); }

  function showError(msg) {
    document.getElementById("ppk-root").innerHTML =
      '<div class="ppk-error"><b>pp-kanban error:</b> ' + escapeHtml(msg || "Unknown") + '</div>';
  }

  // ====================================================================
  // INIT
  // ====================================================================
  if (!cfg.entity || !cfg.group) {
    showError("Missing required ?entity=...&group=... query parameters");
    return;
  }

  entitySetName(cfg.entity, function(err, meta) {
    if (err) return showError("Could not load entity metadata: " + err);
    loadGroupOptions(cfg.entity, cfg.group, function(err, options) {
      if (err) return showError("Could not load group options: " + err);
      loadRecords(meta, function(err, records) {
        if (err) return showError("Could not load records: " + err);
        render(meta, options, records);
      });
    });
  });
})();
</script>
</body>
</html>
'@

# ----------------------------------------------------------------------------
# Upload as web resource with pp_ prefix (Portable Power Platform component)
# ----------------------------------------------------------------------------
$wrName = "pp_/kanban/kanban.html"
$wrDisplayName = "pp-kanban (reusable)"

$bytes = [System.Text.Encoding]::UTF8.GetBytes($html)
$b64 = [Convert]::ToBase64String($bytes)

Write-Host "`n=== pp_kanban web resource ===`n" -ForegroundColor Cyan

# Solution to put it in
$hdrBase["MSCRM.SolutionUniqueName"] = "RMAReturnsMonitor"

$existing = (Invoke-Dv -Method GET -Path "webresourceset?`$filter=name eq '$wrName'&`$select=webresourceid,name").value
if ($existing.Count -gt 0) {
    $wrId = $existing[0].webresourceid
    Write-Host "  [skip] webresource exists -> $wrId (updating content)" -ForegroundColor DarkGray
    Invoke-Dv -Method PATCH -Path "webresourceset($wrId)" -Body @{ content = $b64; displayname = $wrDisplayName } | Out-Null
} else {
    $body = @{
        name             = $wrName
        displayname      = $wrDisplayName
        webresourcetype  = 1   # HTML
        content          = $b64
        description      = "Portable, config-driven Kanban renderer. Reusable across solutions. Configure via URL query string."
        languagecode     = 1033
    }
    $resp = Invoke-Dv -Method POST -Path "webresourceset" -Body $body -ReturnHeaders
    $loc = $resp.Headers['OData-EntityId']
    if ($loc -is [array]) { $loc = $loc[0] }
    if ($loc -match '\(([0-9a-fA-F\-]{36})\)') { $wrId = $matches[1] }
    Write-Host "  [create] webresource -> $wrId" -ForegroundColor Green
}

Write-Host "`nPublishing..." -ForegroundColor Cyan
try {
    $publishXml = "<importexportxml><webresources><webresource>$wrId</webresource></webresources></importexportxml>"
    $body = @{ ParameterXml = $publishXml } | ConvertTo-Json -Compress
    $h = $hdrBase.Clone(); $h['Content-Type'] = 'application/json; charset=utf-8'
    Invoke-WebRequest -Uri "$OrgUrl/api/data/v9.2/PublishXml" -Method Post -Headers $h -Body $body -TimeoutSec 60 -ErrorAction Stop | Out-Null
    Write-Host "  [ok] published" -ForegroundColor Green
} catch {
    $m = $_.Exception.Message
    if ($_.ErrorDetails.Message) { $m = $_.ErrorDetails.Message }
    Write-Host "  [warn] publish: $m" -ForegroundColor DarkYellow
}

# ----------------------------------------------------------------------------
# Test URL for HKP
# ----------------------------------------------------------------------------
$testQs = "entity=rma_claim&group=rma_status&title=rma_claimnumber&subtitle=rma_customername&fields=rma_partnumber,rma_assignedplant,rma_creditamount&badge=rma_stageagedays&filter=statecode eq 0"

Write-Host "`n=== DONE ===" -ForegroundColor Cyan
Write-Host ""
Write-Host "Web resource: pp_/kanban/kanban.html" -ForegroundColor Cyan
Write-Host "ID:           $wrId" -ForegroundColor Cyan
Write-Host ""
Write-Host "Test URL (HKP claims):" -ForegroundColor Yellow
Write-Host ""
Write-Host "$OrgUrl/WebResources/$wrName`?$testQs" -ForegroundColor White
Write-Host ""
Write-Host "Open that URL in a browser while logged into Power Apps — it will render." -ForegroundColor DarkGray
Write-Host ""
Write-Host "To reuse on a different solution:" -ForegroundColor Yellow
Write-Host "  Just change ?entity=, ?group= and the field params. No code change needed." -ForegroundColor DarkGray
Write-Host ""
Write-Host "Example for a generic Service Cases kanban:" -ForegroundColor DarkGray
Write-Host "  ?entity=incident&group=statuscode&title=ticketnumber&subtitle=title&fields=prioritycode,customerid&badge=age" -ForegroundColor DarkGray
