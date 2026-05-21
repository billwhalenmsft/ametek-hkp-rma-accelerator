<#
.SYNOPSIS
    Update pp_kanban to handle lookup fields correctly.

    Lookups can't be referenced by their bare logical name in $select; you
    need _<name>_value or the navigation property. Solution: query entity
    metadata once, identify which requested fields are lookups, and rewrite
    the $select clause accordingly.

    Also display the lookup's formatted value (the related record name).
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

# Updated kanban HTML — now handles lookups automatically
$html = @'
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8" />
<meta http-equiv="X-UA-Compatible" content="IE=edge" />
<title>pp-kanban</title>
<style>
  * { box-sizing: border-box; }
  html, body { margin: 0; height: 100%;
    font-family: "Segoe UI", system-ui, -apple-system, sans-serif;
    color: #1a1f2c; background: #f7f8fb; font-size: 13px; overflow: hidden; }
  .ppk-board { display: flex; gap: 12px; padding: 14px; height: 100%;
    overflow-x: auto; overflow-y: hidden; }
  .ppk-col { flex: 0 0 280px; max-width: 280px; background: #ffffff;
    border-radius: 8px; border: 1px solid #e3e7ee;
    display: flex; flex-direction: column; overflow: hidden; }
  .ppk-col-head { padding: 10px 14px; border-bottom: 1px solid #e3e7ee;
    display: flex; align-items: center; gap: 8px; background: #fafbfd; }
  .ppk-col-dot { width: 10px; height: 10px; border-radius: 50%; flex: 0 0 10px; }
  .ppk-col-title { font-weight: 600; font-size: 13px; flex: 1; white-space: nowrap;
    overflow: hidden; text-overflow: ellipsis; }
  .ppk-col-count { background: #eef2f7; color: #5b6577;
    padding: 2px 8px; border-radius: 10px; font-size: 11px; font-weight: 600; }
  .ppk-col-body { flex: 1; overflow-y: auto; padding: 8px;
    display: flex; flex-direction: column; gap: 8px; }
  .ppk-card { background: #ffffff; border: 1px solid #e3e7ee; border-radius: 6px;
    padding: 10px 12px; cursor: pointer; transition: all 0.15s ease;
    border-left: 3px solid var(--card-accent, #d0d4dc); }
  .ppk-card:hover { border-color: #0078D4; box-shadow: 0 2px 6px rgba(0,120,212,0.12);
    transform: translateY(-1px); }
  .ppk-card-head { display: flex; justify-content: space-between; align-items: center;
    gap: 8px; margin-bottom: 6px; }
  .ppk-card-title { font-weight: 700; font-size: 13px; color: #1a1f2c;
    white-space: nowrap; overflow: hidden; text-overflow: ellipsis; flex: 1; }
  .ppk-badge { flex: 0 0 auto; font-size: 11px; font-weight: 600;
    padding: 2px 8px; border-radius: 10px; white-space: nowrap; }
  .ppk-badge.fresh { background: #dcfce7; color: #166534; }
  .ppk-badge.normal { background: #e0f2fe; color: #075985; }
  .ppk-badge.stale { background: #fef3c7; color: #92400e; }
  .ppk-badge.overdue { background: #fee2e2; color: #991b1b; }
  .ppk-card-subtitle { font-size: 12px; color: #5b6577;
    white-space: nowrap; overflow: hidden; text-overflow: ellipsis; margin-bottom: 6px; }
  .ppk-card-fields { display: flex; flex-direction: column; gap: 3px;
    font-size: 11px; color: #5b6577; }
  .ppk-card-field { display: flex; gap: 6px; align-items: center; }
  .ppk-card-field .ppk-fkey { color: #8a8f9a; min-width: 54px; }
  .ppk-card-field .ppk-fval { color: #1a1f2c; font-weight: 500; flex: 1;
    white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
  .ppk-empty { padding: 24px 12px; text-align: center; color: #8a8f9a;
    font-style: italic; font-size: 12px; }
  .ppk-loading { padding: 24px; text-align: center; color: #5b6577; }
  .ppk-error { padding: 16px; background: #fee2e2; color: #991b1b;
    border-radius: 6px; margin: 14px; }
</style>
</head>
<body>
<div id="ppk-root"><div class="ppk-loading">Loading…</div></div>

<script>
(function() {
  "use strict";

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
      entity: p.entity || "",
      group:  p.group  || "",
      title:  p.title  || "",
      subtitle: p.subtitle || "",
      fields: (p.fields || "").split(",").map(function(s){ return s.trim(); }).filter(Boolean),
      badge:  p.badge  || "",
      filter: p.filter || "",
      onclick: p.onclick || "form",
      orderby: p.orderby || ""
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
      try { var c = xrm.Utility.getGlobalContext().getClientUrl(); if (c) return c; } catch (e) {}
    }
    return "";
  }

  function api(path, callback) {
    var url = clientUrl() + "/api/data/v9.2/" + path;
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

  function loadEntityMeta(entity, cb) {
    api("EntityDefinitions(LogicalName='" + entity + "')?$select=LogicalCollectionName,PrimaryIdAttribute,PrimaryNameAttribute,ObjectTypeCode", function(err, r) {
      if (err) return cb(err);
      cb(null, {
        entitySet: r.LogicalCollectionName,
        primaryKey: r.PrimaryIdAttribute,
        primaryName: r.PrimaryNameAttribute
      });
    });
  }

  function loadAttributeTypes(entity, attrs, cb) {
    if (!attrs || attrs.length === 0) return cb(null, {});
    var filterParts = attrs.map(function(a){ return "LogicalName eq '" + a + "'"; });
    var filter = filterParts.join(" or ");
    var path = "EntityDefinitions(LogicalName='" + entity + "')/Attributes?$select=LogicalName,AttributeType&$filter=" + encodeURIComponent(filter);
    api(path, function(err, r) {
      if (err) return cb(err);
      var map = {};
      (r.value || []).forEach(function(a){ map[a.LogicalName] = a.AttributeType; });
      cb(null, map);
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

  // Convert a list of bare attribute names into select-friendly names,
  // rewriting Lookup attrs to _<name>_value
  function buildSelectFields(meta, attrs, typesMap) {
    return Array.from(new Set(attrs)).map(function(a) {
      if (!a) return null;
      if (typesMap[a] === "Lookup") return "_" + a + "_value";
      return a;
    }).filter(Boolean);
  }

  function buildOrderBy(typesMap) {
    var raw = cfg.orderby || cfg.badge || "createdon";
    if (typesMap[raw] === "Lookup") raw = "_" + raw + "_value";
    return raw + " desc";
  }

  function loadRecords(meta, typesMap, cb) {
    var allAttrs = [cfg.title, cfg.subtitle, cfg.group, cfg.badge].concat(cfg.fields).filter(Boolean);
    var selectFields = buildSelectFields(meta, allAttrs, typesMap);
    var path = meta.entitySet + "?$select=" + meta.primaryKey + "," + selectFields.join(",");
    if (cfg.filter) path += "&$filter=" + encodeURIComponent(cfg.filter);
    path += "&$orderby=" + buildOrderBy(typesMap);
    path += "&$top=500";
    api(path, function(err, r) {
      if (err) return cb(err);
      cb(null, (r && r.value) || []);
    });
  }

  function getDisplay(rec, attr, typesMap) {
    // Lookup: read formatted value of _<name>_value
    if (typesMap[attr] === "Lookup") {
      var key = "_" + attr + "_value";
      return rec[key + "@OData.Community.Display.V1.FormattedValue"] || "";
    }
    var fv = rec[attr + "@OData.Community.Display.V1.FormattedValue"];
    if (fv !== undefined) return fv;
    var v = rec[attr];
    if (v === null || v === undefined) return "";
    return String(v);
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

  function render(meta, options, records, typesMap) {
    var byGroup = {};
    options.forEach(function(o){ byGroup[o.value] = []; });
    var ungrouped = [];

    records.forEach(function(r){
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
      if (rows.length === 0) html += '<div class="ppk-empty">No items</div>';
      else rows.forEach(function(rec){ html += renderCard(rec, o, meta, typesMap); });
      html += '</div></div>';
    });
    if (ungrouped.length > 0) {
      html += '<div class="ppk-col">';
      html += '<div class="ppk-col-head"><span class="ppk-col-dot" style="background:#8a8f9a"></span><span class="ppk-col-title">Unset</span><span class="ppk-col-count">' + ungrouped.length + '</span></div>';
      html += '<div class="ppk-col-body">';
      ungrouped.forEach(function(rec){ html += renderCard(rec, {color:"#8a8f9a"}, meta, typesMap); });
      html += '</div></div>';
    }
    html += '</div>';
    root.innerHTML = html;

    var cards = root.querySelectorAll(".ppk-card");
    for (var i = 0; i < cards.length; i++) {
      cards[i].addEventListener("click", (function(id){
        return function(){ openRecord(id); };
      })(cards[i].getAttribute("data-id")));
    }
  }

  function renderCard(rec, option, meta, typesMap) {
    var id = rec[meta.primaryKey];
    var titleVal = cfg.title ? getDisplay(rec, cfg.title, typesMap) : (rec[meta.primaryName] || "");
    var subtitleVal = cfg.subtitle ? getDisplay(rec, cfg.subtitle, typesMap) : "";
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
      cfg.fields.forEach(function(f){
        var v = getDisplay(rec, f, typesMap);
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
    var base = logical.replace(/^[a-z]+_/, "");
    return base.split("_").map(function(s){ return s.charAt(0).toUpperCase() + s.slice(1); }).join(" ");
  }
  function escapeHtml(s) {
    return String(s).replace(/[&<>"']/g, function(c){
      return { "&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;" }[c];
    });
  }
  function escapeAttr(s) { return escapeHtml(s); }
  function showError(msg) {
    document.getElementById("ppk-root").innerHTML =
      '<div class="ppk-error"><b>pp-kanban error:</b> ' + escapeHtml(msg || "Unknown") + '</div>';
  }

  if (!cfg.entity || !cfg.group) {
    showError("Missing required ?entity=...&group=... query parameters");
    return;
  }

  loadEntityMeta(cfg.entity, function(err, meta) {
    if (err) return showError("Could not load entity metadata: " + err);
    var allAttrs = [cfg.title, cfg.subtitle, cfg.group, cfg.badge].concat(cfg.fields).filter(Boolean);
    loadAttributeTypes(cfg.entity, allAttrs, function(err, typesMap) {
      if (err) return showError("Could not load attribute types: " + err);
      loadGroupOptions(cfg.entity, cfg.group, function(err, options) {
        if (err) return showError("Could not load group options: " + err);
        loadRecords(meta, typesMap, function(err, records) {
          if (err) return showError("Could not load records: " + err);
          render(meta, options, records, typesMap);
        });
      });
    });
  });
})();
</script>
</body>
</html>
'@

$bytes = [System.Text.Encoding]::UTF8.GetBytes($html)
$b64 = [Convert]::ToBase64String($bytes)

Write-Host "`nUpdating pp_/kanban/kanban.html with lookup-aware logic..." -ForegroundColor Cyan
$wr = (Invoke-Dv -Method GET -Path "webresourceset?`$filter=name eq 'pp_/kanban/kanban.html'&`$select=webresourceid").value
$wrId = $wr[0].webresourceid
Invoke-Dv -Method PATCH -Path "webresourceset($wrId)" -Body @{ content = $b64 } | Out-Null
Write-Host "  [ok] PATCHed -> $wrId" -ForegroundColor Green

Write-Host "`nPublishing web resource..." -ForegroundColor Cyan
$publishXml = "<importexportxml><webresources><webresource>$wrId</webresource></webresources></importexportxml>"
$body = @{ ParameterXml = $publishXml } | ConvertTo-Json -Compress
$h = $hdrBase.Clone(); $h['Content-Type'] = 'application/json; charset=utf-8'
try {
    Invoke-WebRequest -Uri "$OrgUrl/api/data/v9.2/PublishXml" -Method Post -Headers $h -Body $body -TimeoutSec 60 -ErrorAction Stop | Out-Null
    Write-Host "  [ok] published" -ForegroundColor Green
} catch {
    Write-Host "  [warn] $($_.Exception.Message)" -ForegroundColor DarkYellow
}

Write-Host "`n=== DONE — refresh the page ===" -ForegroundColor Cyan
Write-Host "Hard refresh: Ctrl+Shift+R or open in InPrivate" -ForegroundColor Yellow
