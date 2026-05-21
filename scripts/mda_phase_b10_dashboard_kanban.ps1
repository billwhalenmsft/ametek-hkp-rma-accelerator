<#
.SYNOPSIS
    Rebuild the RMA Operations Overview dashboard with pp-kanban on top
    + 2 charts at the bottom.

    Layout:
      ┌────────────────────────────────────────────────────────────────┐
      │              pp-kanban (full width, ~500px tall)                │
      └────────────────────────────────────────────────────────────────┘
      ┌──────────────────────────────┐ ┌──────────────────────────────┐
      │   Open Claims by Status      │ │   Claims by Plant            │
      └──────────────────────────────┘ └──────────────────────────────┘
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

# Look up existing chart IDs + open view ID
$views = (Invoke-Dv -Method GET -Path "savedqueries?`$filter=name eq 'All Open RMAs' and returnedtypecode eq 'rma_claim'&`$select=savedqueryid").value
$openViewId = $views[0].savedqueryid

$chartByName = @{}
foreach ($c in (Invoke-Dv -Method GET -Path "savedqueryvisualizations?`$filter=primaryentitytypecode eq 'rma_claim'&`$select=savedqueryvisualizationid,name").value) {
    $chartByName[$c.name] = $c.savedqueryvisualizationid
}
$c1 = $chartByName["Open Claims by Status"]
$c2 = $chartByName["Claims by Plant"]
if (-not $c1 -or -not $c2) { throw "Required charts not found" }

# Look up dashboard
$dashName = "RMA Operations Overview"
$dash = (Invoke-Dv -Method GET -Path "systemforms?`$filter=name eq '$dashName' and type eq 0&`$select=formid,name").value
if ($dash.Count -eq 0) { throw "Dashboard '$dashName' not found" }
$dashId = $dash[0].formid

# Web resource ID for the kanban
$wr = (Invoke-Dv -Method GET -Path "webresourceset?`$filter=name eq 'pp_/kanban/kanban.html'&`$select=webresourceid,name").value
if ($wr.Count -eq 0) { throw "Web resource pp_/kanban/kanban.html not found" }
$wrName = $wr[0].name   # used in URL

Write-Host "`n=== Rebuild RMA Operations Overview with kanban top ===" -ForegroundColor Cyan
Write-Host "  dashboard: $dashId" -ForegroundColor DarkGray
Write-Host "  kanban WR: $wrName" -ForegroundColor DarkGray
Write-Host "  chart 1:   $c1" -ForegroundColor DarkGray
Write-Host "  chart 2:   $c2" -ForegroundColor DarkGray

# Kanban configuration query string
$qs = "entity=rma_claim&group=rma_status&title=rma_claimnumber&subtitle=rma_customername&fields=rma_partnumber,rma_assignedplant,rma_creditamount&badge=rma_stageagedays&filter=statecode eq 0"
# Dashboard web-resource control uses Url = WR name (resolved at runtime),
# Data = the query-string portion. Url must be the unprefixed WR name.
$wrNameForCtrl = $wrName   # e.g. "pp_/kanban/kanban.html"
$qsEsc = $qs.Replace('&', '&amp;')

# Build the new dashboard formxml
# Tab 1: web resource (kanban) - full width, large
# Tab 2: 2 charts side by side
$dashFormXml = @"
<form>
  <tabs>
    <tab name="tab_kanban" id="{$([Guid]::NewGuid())}" verticallayout="true" labelid="{$([Guid]::NewGuid())}" showlabel="true" visible="true" expanded="true">
      <labels>
        <label description="Claims Board" languagecode="1033" />
      </labels>
      <columns>
        <column width="100%">
          <sections>
            <section name="section_kanban" showlabel="false" showbar="false" labelid="{$([Guid]::NewGuid())}" columns="1">
              <labels>
                <label description="Kanban" languagecode="1033" />
              </labels>
              <rows>
                <row>
                  <cell id="{$([Guid]::NewGuid())}" colspan="1" rowspan="12" showlabel="false" auto="false">
                    <labels>
                      <label description="Claims Kanban" languagecode="1033" />
                    </labels>
                    <control id="KanbanWR" classid="{9FDF5F91-88B1-47f4-AD53-C11EFC01A01D}">
                      <parameters>
                        <Url>$wrNameForCtrl</Url>
                        <Data>$qsEsc</Data>
                        <PassParameters>true</PassParameters>
                        <Security>false</Security>
                        <Scrolling>auto</Scrolling>
                        <Border>false</Border>
                      </parameters>
                    </control>
                  </cell>
                </row>
              </rows>
            </section>
          </sections>
        </column>
      </columns>
    </tab>
    <tab name="tab_charts" id="{$([Guid]::NewGuid())}" verticallayout="true" labelid="{$([Guid]::NewGuid())}" showlabel="true" visible="true" expanded="true">
      <labels>
        <label description="Analytics" languagecode="1033" />
      </labels>
      <columns>
        <column width="50%">
          <sections>
            <section name="section_topleft" showlabel="false" showbar="false" labelid="{$([Guid]::NewGuid())}" columns="1">
              <labels>
                <label description="Open Claims by Status" languagecode="1033" />
              </labels>
              <rows>
                <row>
                  <cell id="{$([Guid]::NewGuid())}" colspan="1" rowspan="8" showlabel="false" auto="false">
                    <labels>
                      <label description="Open Claims by Status" languagecode="1033" />
                    </labels>
                    <control id="ChartTopLeft" classid="{E7A81278-8635-4d9e-8D4D-59480B391C5B}" indicationOfSubgrid="true">
                      <parameters>
                        <ViewId>{$openViewId}</ViewId>
                        <IsUserView>false</IsUserView>
                        <RelationshipName />
                        <TargetEntityType>rma_claim</TargetEntityType>
                        <AutoExpand>Fixed</AutoExpand>
                        <EnableQuickFind>false</EnableQuickFind>
                        <EnableViewPicker>false</EnableViewPicker>
                        <ViewIds />
                        <EnableJumpBar>false</EnableJumpBar>
                        <ChartGridMode>Chart</ChartGridMode>
                        <VisualizationId>{$c1}</VisualizationId>
                        <IsUserChart>false</IsUserChart>
                        <EnableChartPicker>false</EnableChartPicker>
                        <RecordsPerPage>10</RecordsPerPage>
                      </parameters>
                    </control>
                  </cell>
                </row>
              </rows>
            </section>
          </sections>
        </column>
        <column width="50%">
          <sections>
            <section name="section_topright" showlabel="false" showbar="false" labelid="{$([Guid]::NewGuid())}" columns="1">
              <labels>
                <label description="Claims by Plant" languagecode="1033" />
              </labels>
              <rows>
                <row>
                  <cell id="{$([Guid]::NewGuid())}" colspan="1" rowspan="8" showlabel="false" auto="false">
                    <labels>
                      <label description="Claims by Plant" languagecode="1033" />
                    </labels>
                    <control id="ChartTopRight" classid="{E7A81278-8635-4d9e-8D4D-59480B391C5B}" indicationOfSubgrid="true">
                      <parameters>
                        <ViewId>{$openViewId}</ViewId>
                        <IsUserView>false</IsUserView>
                        <RelationshipName />
                        <TargetEntityType>rma_claim</TargetEntityType>
                        <AutoExpand>Fixed</AutoExpand>
                        <EnableQuickFind>false</EnableQuickFind>
                        <EnableViewPicker>false</EnableViewPicker>
                        <ViewIds />
                        <EnableJumpBar>false</EnableJumpBar>
                        <ChartGridMode>Chart</ChartGridMode>
                        <VisualizationId>{$c2}</VisualizationId>
                        <IsUserChart>false</IsUserChart>
                        <EnableChartPicker>false</EnableChartPicker>
                        <RecordsPerPage>10</RecordsPerPage>
                      </parameters>
                    </control>
                  </cell>
                </row>
              </rows>
            </section>
          </sections>
        </column>
      </columns>
    </tab>
  </tabs>
</form>
"@

Write-Host "`nPatching dashboard..." -ForegroundColor Cyan
Invoke-Dv -Method PATCH -Path "systemforms($dashId)" -Body @{
    formxml = $dashFormXml
    description = "Kanban board (Claims Board tab) + analytics (Analytics tab) for RMA operations."
} | Out-Null
Write-Host "  [ok] dashboard updated" -ForegroundColor Green

Write-Host "`nPublishing..." -ForegroundColor Cyan
try {
    $publishXml = "<importexportxml><entities><entity>rma_claim</entity></entities></importexportxml>"
    $body = @{ ParameterXml = $publishXml } | ConvertTo-Json -Compress
    $h = $hdrBase.Clone(); $h['Content-Type'] = 'application/json; charset=utf-8'
    Invoke-WebRequest -Uri "$OrgUrl/api/data/v9.2/PublishXml" -Method Post -Headers $h -Body $body -TimeoutSec 60 -ErrorAction Stop | Out-Null
    Write-Host "  [ok] published" -ForegroundColor Green
} catch {
    $m = $_.Exception.Message
    if ($_.ErrorDetails.Message) { $m = $_.ErrorDetails.Message }
    Write-Host "  [warn] publish: $m" -ForegroundColor DarkYellow
}

Write-Host "`n=== DONE ===" -ForegroundColor Cyan
Write-Host ""
Write-Host "Dashboard layout now has 2 tabs:" -ForegroundColor Yellow
Write-Host "  Claims Board  — pp-kanban (5 status swim lanes)"
Write-Host "  Analytics     — Open Claims by Status + Claims by Plant charts"
Write-Host ""
Write-Host "Open dashboard:" -ForegroundColor Yellow
Write-Host "  $OrgUrl/main.aspx?pagetype=dashboard&id=$dashId"
