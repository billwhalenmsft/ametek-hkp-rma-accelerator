<#
.SYNOPSIS
    Phase A continued: Create 4 charts + 1 dashboard for the RMA Operations app.

    Charts (savedqueryvisualizations on rma_claim):
      1. Open Claims by Status        (donut, group by rma_status)
      2. Claims by Plant              (column, group by rma_AssignedPlant)
      3. Claims by Customer Region    (donut, group by rma_customerregion)
      4. Total Credit Amount by Plant (column, sum of rma_creditamount by plant)

    Dashboard:
      RMA Operations Overview (system dashboard, 4 charts in 2x2)
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
    param([string]$Method, [string]$Path, $Body = $null, [switch]$ReturnHeaders, [int]$MaxRetries = 5)
    $url = "$OrgUrl/api/data/v9.2/$Path"
    $h = $hdrBase.Clone()
    if ($Method -in @('PATCH','DELETE')) { $h['If-Match'] = '*' }
    if ($Body) { $h['Content-Type'] = 'application/json; charset=utf-8' }
    $params = @{ Uri = $url; Method = $Method; Headers = $h }
    if ($Body) {
        if ($Body -is [string]) { $params.Body = $Body }
        else { $params.Body = ($Body | ConvertTo-Json -Depth 30 -Compress) }
    }
    $attempt = 0
    while ($true) {
        $attempt++
        try {
            if ($ReturnHeaders) { return Invoke-WebRequest @params -ErrorAction Stop }
            return Invoke-RestMethod @params -ErrorAction Stop
        } catch {
            $msg = $_.Exception.Message
            if ($_.ErrorDetails.Message) { $msg = $_.ErrorDetails.Message }
            if ($msg -match '0x80072324|Too many concurrent|429|503' -and $attempt -lt $MaxRetries) {
                $wait = [Math]::Min(60, [Math]::Pow(2, $attempt) * 2)
                Write-Host "    [throttled] retry $attempt after ${wait}s..." -ForegroundColor DarkYellow
                Start-Sleep -Seconds $wait
                continue
            }
            throw "API [$Method $Path]: $msg"
        }
    }
}

# ---------------------------------------------------------------------------
# Common chart XML helpers
# ---------------------------------------------------------------------------
function New-DonutChart {
    param([string]$GroupAttr, [string]$AggregateAttr = "rma_claimid", [string]$Filter = "")
    $filterBlock = if ($Filter) { "<filter type=`"and`">$Filter</filter>" } else { "" }
    $data = @"
<datadefinition>
  <fetchcollection>
    <fetch mapping="logical" aggregate="true">
      <entity name="rma_claim">
        <attribute name="$AggregateAttr" aggregate="count" alias="agg_count" />
        <attribute name="$GroupAttr" groupby="true" alias="grp" />
        $filterBlock
      </entity>
    </fetch>
  </fetchcollection>
  <categorycollection>
    <category alias="grp">
      <measurecollection>
        <measure alias="agg_count" />
      </measurecollection>
    </category>
  </categorycollection>
</datadefinition>
"@
    $presentation = @'
<Chart>
  <Series>
    <Series IsValueShownAsLabel="True" Color="91, 151, 213" BackSecondaryColor="41, 88, 145" Font="{0}, 9.5px" LabelForeColor="59, 59, 59" ChartType="Doughnut" CustomProperties="PointWidth=0.75, MaxPixelPointWidth=40">
      <SmartLabelStyle Enabled="True" />
      <Points />
    </Series>
  </Series>
  <ChartAreas>
    <ChartArea BorderColor="White" BorderDashStyle="Solid" />
  </ChartAreas>
  <Titles>
    <Title Alignment="TopLeft" DockingOffset="-3" Font="{0}, 13px" ForeColor="59, 59, 59"></Title>
  </Titles>
  <Legends>
    <Legend Alignment="Center" LegendStyle="Table" Docking="Right" IsEquallySpacedItems="True" Font="{0}, 11px" ShadowColor="0, 0, 0, 0" ForeColor="59, 59, 59" />
  </Legends>
</Chart>
'@
    return @{ data=$data; presentation=$presentation }
}

function New-ColumnChart {
    param([string]$GroupAttr, [string]$AggregateAttr = "rma_claimid", [string]$AggregateType = "count", [string]$Filter = "")
    $filterBlock = if ($Filter) { "<filter type=`"and`">$Filter</filter>" } else { "" }
    $data = @"
<datadefinition>
  <fetchcollection>
    <fetch mapping="logical" aggregate="true">
      <entity name="rma_claim">
        <attribute name="$AggregateAttr" aggregate="$AggregateType" alias="agg_val" />
        <attribute name="$GroupAttr" groupby="true" alias="grp" />
        $filterBlock
      </entity>
    </fetch>
  </fetchcollection>
  <categorycollection>
    <category alias="grp">
      <measurecollection>
        <measure alias="agg_val" />
      </measurecollection>
    </category>
  </categorycollection>
</datadefinition>
"@
    $presentation = @'
<Chart>
  <Series>
    <Series IsValueShownAsLabel="True" Color="91, 151, 213" BackSecondaryColor="41, 88, 145" Font="{0}, 9.5px" LabelForeColor="59, 59, 59" ChartType="Column" CustomProperties="PointWidth=0.75, MaxPixelPointWidth=40">
      <SmartLabelStyle Enabled="True" />
      <Points />
    </Series>
  </Series>
  <ChartAreas>
    <ChartArea BorderColor="White" BorderDashStyle="Solid">
      <AxisY LabelAutoFitMinFontSize="8" TitleForeColor="59, 59, 59" TitleFont="{0}, 10.5px" LineColor="165, 172, 181">
        <MajorGrid LineColor="239, 242, 246" />
        <MajorTickMark LineColor="165, 172, 181" />
        <LabelStyle Font="{0}, 10.5px" ForeColor="59, 59, 59" />
      </AxisY>
      <AxisX LabelAutoFitMinFontSize="8" TitleForeColor="59, 59, 59" TitleFont="{0}, 10.5px" LineColor="165, 172, 181">
        <MajorGrid Enabled="False" />
        <MajorTickMark Enabled="False" />
        <LabelStyle Font="{0}, 10.5px" ForeColor="59, 59, 59" />
      </AxisX>
    </ChartArea>
  </ChartAreas>
  <Titles>
    <Title Alignment="TopLeft" DockingOffset="-3" Font="{0}, 13px" ForeColor="59, 59, 59"></Title>
  </Titles>
</Chart>
'@
    return @{ data=$data; presentation=$presentation }
}

# ---------------------------------------------------------------------------
# Chart definitions
# ---------------------------------------------------------------------------
$charts = @(
    @{
        Name = "Open Claims by Status"
        Description = "Count of currently-open RMA claims grouped by their workflow stage."
        Spec = New-DonutChart -GroupAttr "rma_status" -Filter '<condition attribute="rma_status" operator="ne" value="100000004" />'
    },
    @{
        Name = "Claims by Plant"
        Description = "Total claims per assigned plant (open + closed)."
        Spec = New-ColumnChart -GroupAttr "rma_assignedplant" -AggregateType "count"
    },
    @{
        Name = "Claims by Customer Region"
        Description = "Claim volume by customer geographic region."
        Spec = New-DonutChart -GroupAttr "rma_customerregion"
    },
    @{
        Name = "Total Credit Amount by Plant"
        Description = "Sum of credit amounts authorised per plant."
        Spec = New-ColumnChart -GroupAttr "rma_assignedplant" -AggregateAttr "rma_creditamount" -AggregateType "sum"
    }
)

Write-Host "`n=== Phase A: Charts on rma_claim ===`n" -ForegroundColor Cyan

$chartIds = @{}
foreach ($c in $charts) {
    $nameEsc = $c.Name -replace "'", "''"
    $existing = (Invoke-Dv -Method GET -Path "savedqueryvisualizations?`$filter=name eq '$nameEsc' and primaryentitytypecode eq 'rma_claim'&`$select=savedqueryvisualizationid").value
    if ($existing.Count -gt 0) {
        $id = $existing[0].savedqueryvisualizationid
        Write-Host "  [skip] '$($c.Name)' exists -> $id  (updating)" -ForegroundColor DarkGray
        Invoke-Dv -Method PATCH -Path "savedqueryvisualizations($id)" -Body @{
            name = $c.Name
            description = $c.Description
            datadescription = $c.Spec.data
            presentationdescription = $c.Spec.presentation
        } | Out-Null
        $chartIds[$c.Name] = $id
        continue
    }
    $body = @{
        name                    = $c.Name
        description             = $c.Description
        primaryentitytypecode   = "rma_claim"
        datadescription         = $c.Spec.data
        presentationdescription = $c.Spec.presentation
    }
    try {
        $resp = Invoke-Dv -Method POST -Path "savedqueryvisualizations" -Body $body -ReturnHeaders
        $loc = $resp.Headers['OData-EntityId']
        if ($loc -is [array]) { $loc = $loc[0] }
        if ($loc -match '\(([0-9a-fA-F\-]{36})\)') { $chartIds[$c.Name] = $matches[1] }
        Write-Host "  [create] '$($c.Name)' -> $($chartIds[$c.Name])" -ForegroundColor Green
    } catch {
        $m = $_.Exception.Message
        if ($_.ErrorDetails.Message) { $m = $_.ErrorDetails.Message }
        Write-Host "  [FAIL] $($c.Name): $m" -ForegroundColor Red
    }
}

# ---------------------------------------------------------------------------
# Dashboard — 2x2 grid of the 4 charts
# ---------------------------------------------------------------------------
Write-Host "`n=== Building RMA Operations Overview dashboard ===" -ForegroundColor Cyan

$em = Invoke-Dv -Method GET -Path "EntityDefinitions(LogicalName='rma_claim')?`$select=ObjectTypeCode,MetadataId"
$otc = $em.ObjectTypeCode

# Get the All Open RMAs view id (chart cells reference a savedquery for filtering)
$allOpenView = (Invoke-Dv -Method GET -Path "savedqueries?`$filter=name eq 'All Open RMAs' and returnedtypecode eq 'rma_claim'&`$select=savedqueryid").value
if ($allOpenView.Count -eq 0) { throw "View 'All Open RMAs' not found — run mda_phase_a_views.ps1 first" }
$openViewId = $allOpenView[0].savedqueryid

$c1 = $chartIds["Open Claims by Status"]
$c2 = $chartIds["Claims by Plant"]
$c3 = $chartIds["Claims by Customer Region"]
$c4 = $chartIds["Total Credit Amount by Plant"]

# Dashboard formxml schema for system dashboards (type=0)
$dashFormXml = @"
<form>
  <tabs>
    <tab name="tab_main" id="{$([Guid]::NewGuid())}" verticallayout="true" labelid="{$([Guid]::NewGuid())}" showlabel="false" visible="true" expanded="true">
      <labels>
        <label description="RMA Operations Overview" languagecode="1033" />
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
    <tab name="tab_bottom" id="{$([Guid]::NewGuid())}" verticallayout="true" labelid="{$([Guid]::NewGuid())}" showlabel="false" visible="true" expanded="true">
      <labels>
        <label description="More" languagecode="1033" />
      </labels>
      <columns>
        <column width="50%">
          <sections>
            <section name="section_botleft" showlabel="false" showbar="false" labelid="{$([Guid]::NewGuid())}" columns="1">
              <labels>
                <label description="Claims by Customer Region" languagecode="1033" />
              </labels>
              <rows>
                <row>
                  <cell id="{$([Guid]::NewGuid())}" colspan="1" rowspan="8" showlabel="false" auto="false">
                    <labels>
                      <label description="Claims by Customer Region" languagecode="1033" />
                    </labels>
                    <control id="ChartBotLeft" classid="{E7A81278-8635-4d9e-8D4D-59480B391C5B}" indicationOfSubgrid="true">
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
                        <VisualizationId>{$c3}</VisualizationId>
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
            <section name="section_botright" showlabel="false" showbar="false" labelid="{$([Guid]::NewGuid())}" columns="1">
              <labels>
                <label description="Total Credit Amount by Plant" languagecode="1033" />
              </labels>
              <rows>
                <row>
                  <cell id="{$([Guid]::NewGuid())}" colspan="1" rowspan="8" showlabel="false" auto="false">
                    <labels>
                      <label description="Total Credit Amount by Plant" languagecode="1033" />
                    </labels>
                    <control id="ChartBotRight" classid="{E7A81278-8635-4d9e-8D4D-59480B391C5B}" indicationOfSubgrid="true">
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
                        <VisualizationId>{$c4}</VisualizationId>
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

# Create / update the dashboard (systemform type=0)
$dashName = "RMA Operations Overview"
$existing = (Invoke-Dv -Method GET -Path "systemforms?`$filter=name eq '$dashName' and type eq 0&`$select=formid").value
if ($existing.Count -gt 0) {
    $dashId = $existing[0].formid
    Write-Host "  [skip] dashboard exists -> $dashId  (updating)" -ForegroundColor DarkGray
    Invoke-Dv -Method PATCH -Path "systemforms($dashId)" -Body @{
        description = "Overview of RMA claims by status, plant, region, and credit."
        formxml = $dashFormXml
    } | Out-Null
} else {
    $body = @{
        name             = $dashName
        description      = "Overview of RMA claims by status, plant, region, and credit."
        formxml          = $dashFormXml
        type             = 0    # Dashboard
        objecttypecode   = "none"
    }
    try {
        $resp = Invoke-Dv -Method POST -Path "systemforms" -Body $body -ReturnHeaders
        $loc = $resp.Headers['OData-EntityId']
        if ($loc -is [array]) { $loc = $loc[0] }
        if ($loc -match '\(([0-9a-fA-F\-]{36})\)') { $dashId = $matches[1] }
        Write-Host "  [create] dashboard -> $dashId" -ForegroundColor Green
    } catch {
        $m = $_.Exception.Message
        if ($_.ErrorDetails.Message) { $m = $_.ErrorDetails.Message }
        Write-Host "  [FAIL] dashboard: $m" -ForegroundColor Red
    }
}

# Publish
Write-Host "`nPublishing rma_claim..." -ForegroundColor Cyan
try {
    $publishXml = "<importexportxml><entities><entity>rma_claim</entity></entities></importexportxml>"
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
Write-Host "Charts: $($chartIds.Count)"
Write-Host "Dashboard: $dashName"
Write-Host ""
Write-Host "To use the dashboard:" -ForegroundColor Yellow
Write-Host "  1. Open the RMA Operations and Monitoring app"
Write-Host "  2. Click the dashboards icon (or sitemap will need the dashboard area — we'll wire it next)"
Write-Host ""
Write-Host "To use the charts independently:" -ForegroundColor Yellow
Write-Host "  Open RMA Claims view -> Show Chart -> click chart picker -> pick one of the new charts"

