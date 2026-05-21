<#
.SYNOPSIS
    Phase C1 — rma_claim main form full redesign.
    Embeds Pizza Tracker at top, builds 4 tabs (General/Notes/Approvals/Emails),
    matching the Vibe Code App look-and-feel (information density + grouping).

    Tabs:
      General      — Header info, Customer/Part group, Plant/Status group, Resolution group
      Notes        — Subgrid of rma_claimnote + native Timeline
      Approvals    — Subgrid of rma_approvalrecord + subgrid of rma_approvalhistory
      Emails       — Subgrid of rma_emaillog (related claim)

    Pizza Tracker stays in a section above all tabs (header area).

.NOTES
    Form ID: 05a92f92-94cc-4a07-9ba0-f704788c699c
    Pizza Tracker web resource ID: b3e04439-304e-f111-bec6-000d3a5aed87
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

$formId       = "05a92f92-94cc-4a07-9ba0-f704788c699c"
$pizzaWrId    = "b3e04439-304e-f111-bec6-000d3a5aed87"

# Helper for new GUIDs
function NewGuid { return [Guid]::NewGuid().ToString().ToLower() }

Write-Host "`n=== Phase C1: rma_claim main form redesign ===`n" -ForegroundColor Cyan

# --------------------------------------------------------------------------
# Build the form XML programmatically — explicit GUIDs everywhere so labelid
# validation doesn't trip us.
# --------------------------------------------------------------------------

# Tab IDs
$tabGeneralId   = NewGuid
$tabNotesId     = NewGuid
$tabApprovalsId = NewGuid
$tabEmailsId    = NewGuid

# Section IDs — General tab
$secPizzaId     = NewGuid
$secCustomerId  = NewGuid
$secPlantId     = NewGuid
$secResolutionId= NewGuid

# Section IDs — Notes tab
$secClaimNotesId = NewGuid
$secTimelineId   = NewGuid

# Section IDs — Approvals tab
$secApprovalsRecsId = NewGuid
$secApprovalsHistId = NewGuid

# Section IDs — Emails tab
$secEmailsId = NewGuid

# Header ID stays the same
$headerId = NewGuid
$footerId = NewGuid

# Cell IDs (need many) — using a helper
function CellId { NewGuid }

# Build cell IDs
$cellPizza      = CellId
$cellCustName   = CellId; $cellCustEmail  = CellId
$cellRegion     = CellId; $cellPartNum    = CellId
$cellQty        = CellId; $cellFailMode   = CellId
$cellFailDesc   = CellId
$cellPlant      = CellId; $cellPlantName  = CellId
$cellStatus     = CellId; $cellWarrStatus = CellId
$cellWarrDate   = CellId; $cellSrcEmailId = CellId
$cellResolution = CellId; $cellCreditAmt  = CellId
$cellClosedDate = CellId; $cellPendingResp= CellId

# Notes tab cells
$cellClaimNotesGrid = CellId
$cellTimeline       = CellId

# Approvals tab cells
$cellApprovalRecsGrid = CellId
$cellApprovalHistGrid = CellId

# Emails tab cells
$cellEmailsGrid = CellId

# Header cells (4 chips: Claim#, Status, Resolution, Owner)
$hCell1 = CellId; $hCell2 = CellId; $hCell3 = CellId; $hCell4 = CellId

# Footer cell
$footCell = CellId

# --------------------------------------------------------------------------
# Compose XML — Vibe-style info density: 3-col grid in General, 2-col in tabs.
# --------------------------------------------------------------------------

$formXml = @"
<form headerdensity="HighWithControls">
<tabs>

<!-- TAB 1: GENERAL — Pizza Tracker + Customer/Part + Plant/Status + Resolution -->
<tab verticallayout="true" id="{$tabGeneralId}" IsUserDefined="1" name="general_tab">
  <labels><label description="General" languagecode="1033" /></labels>
  <columns>
    <column width="100%">
      <sections>

        <!-- Pizza Tracker — full width -->
        <section showlabel="false" showbar="false" IsUserDefined="0" id="{$secPizzaId}" columns="1">
          <labels><label description="Progress" languagecode="1033" /></labels>
          <rows>
            <row>
              <cell id="{$cellPizza}" showlabel="false" rowspan="2" colspan="1">
                <labels><label description="Pizza Tracker" languagecode="1033" /></labels>
                <control id="WebResource_pizza_tracker" classid="{9FDF5F91-88B1-47F4-AD53-C11EFC01A01D}">
                  <parameters>
                    <Url>rma_/pizzatracker/rma_pizza_tracker.html</Url>
                    <PassParameters>false</PassParameters>
                    <Security>false</Security>
                    <Scrolling>no</Scrolling>
                    <Border>false</Border>
                    <ShowOnMobileClient>false</ShowOnMobileClient>
                    <WebResourceId>{$pizzaWrId}</WebResourceId>
                  </parameters>
                </control>
              </cell>
            </row>
            <row />
          </rows>
        </section>

        <!-- Customer & Part — 4 internal columns -->
        <section showlabel="true" showbar="true" id="{$secCustomerId}" columns="4" labelwidth="115">
          <labels><label description="Customer &amp; Part" languagecode="1033" /></labels>
          <rows>
            <row>
              <cell id="{$cellCustName}" colspan="1" rowspan="1">
                <labels><label description="Customer Name" languagecode="1033" /></labels>
                <control id="rma_customername" classid="{4273EDBD-AC1D-40d3-9FB2-095C621B552D}" datafieldname="rma_customername" />
              </cell>
              <cell id="{$cellCustEmail}" colspan="1" rowspan="1">
                <labels><label description="Customer Email" languagecode="1033" /></labels>
                <control id="rma_customeremail" classid="{4273EDBD-AC1D-40d3-9FB2-095C621B552D}" datafieldname="rma_customeremail" />
              </cell>
              <cell id="{$cellRegion}" colspan="1" rowspan="1">
                <labels><label description="Customer Region" languagecode="1033" /></labels>
                <control id="rma_customerregion" classid="{3EF39988-22BB-4f0b-BBBE-64B5A3748AEE}" datafieldname="rma_customerregion" />
              </cell>
              <cell id="{$cellPartNum}" colspan="1" rowspan="1">
                <labels><label description="Part Number" languagecode="1033" /></labels>
                <control id="rma_partnumber" classid="{4273EDBD-AC1D-40d3-9FB2-095C621B552D}" datafieldname="rma_partnumber" />
              </cell>
            </row>
            <row>
              <cell id="{$cellQty}" colspan="1" rowspan="1">
                <labels><label description="Quantity" languagecode="1033" /></labels>
                <control id="rma_quantity" classid="{C6D124CA-7EDA-4a60-AEA9-7FB8D318B68F}" datafieldname="rma_quantity" />
              </cell>
              <cell id="{$cellFailMode}" colspan="1" rowspan="1">
                <labels><label description="Failure Mode" languagecode="1033" /></labels>
                <control id="rma_failuremode" classid="{3EF39988-22BB-4f0b-BBBE-64B5A3748AEE}" datafieldname="rma_failuremode" />
              </cell>
              <cell id="{$cellFailDesc}" colspan="2" rowspan="2">
                <labels><label description="Failure Description" languagecode="1033" /></labels>
                <control id="rma_failuredescription" classid="{E0DECE4B-6FC8-4a8f-A065-082708572369}" datafieldname="rma_failuredescription" />
              </cell>
            </row>
            <row />
          </rows>
        </section>

        <!-- Plant & Status — 4 internal columns -->
        <section showlabel="true" showbar="true" id="{$secPlantId}" columns="4" labelwidth="115">
          <labels><label description="Plant &amp; Status" languagecode="1033" /></labels>
          <rows>
            <row>
              <cell id="{$cellPlant}" colspan="2" rowspan="1">
                <labels><label description="Assigned Plant" languagecode="1033" /></labels>
                <control id="rma_assignedplant" classid="{270BD3DB-D9AF-4782-9025-509E298DEC0A}" datafieldname="rma_assignedplant" />
              </cell>
              <cell id="{$cellStatus}" colspan="1" rowspan="1">
                <labels><label description="Status" languagecode="1033" /></labels>
                <control id="rma_status" classid="{3EF39988-22BB-4f0b-BBBE-64B5A3748AEE}" datafieldname="rma_status" />
              </cell>
              <cell id="{$cellWarrStatus}" colspan="1" rowspan="1">
                <labels><label description="Warranty Status" languagecode="1033" /></labels>
                <control id="rma_warrantystatus" classid="{3EF39988-22BB-4f0b-BBBE-64B5A3748AEE}" datafieldname="rma_warrantystatus" />
              </cell>
            </row>
            <row>
              <cell id="{$cellWarrDate}" colspan="1" rowspan="1">
                <labels><label description="Warranty Verified Date" languagecode="1033" /></labels>
                <control id="rma_warrantyverifieddate" classid="{5B773807-9FB2-42db-97C3-7A91EFF8ADFF}" datafieldname="rma_warrantyverifieddate" />
              </cell>
              <cell id="{$cellPendingResp}" colspan="1" rowspan="1">
                <labels><label description="Awaiting Customer Response" languagecode="1033" /></labels>
                <control id="rma_haspendingresponse" classid="{B0C6723A-8503-4fd7-BB28-C8A06AC933C2}" datafieldname="rma_haspendingresponse" />
              </cell>
              <cell id="{$cellSrcEmailId}" colspan="2" rowspan="1">
                <labels><label description="Source Email ID" languagecode="1033" /></labels>
                <control id="rma_sourceemailid" classid="{4273EDBD-AC1D-40d3-9FB2-095C621B552D}" datafieldname="rma_sourceemailid" />
              </cell>
            </row>
          </rows>
        </section>

        <!-- Resolution — 4 internal columns -->
        <section showlabel="true" showbar="true" id="{$secResolutionId}" columns="4" labelwidth="115">
          <labels><label description="Resolution" languagecode="1033" /></labels>
          <rows>
            <row>
              <cell id="{$cellResolution}" colspan="1" rowspan="1">
                <labels><label description="Resolution" languagecode="1033" /></labels>
                <control id="rma_resolution" classid="{3EF39988-22BB-4f0b-BBBE-64B5A3748AEE}" datafieldname="rma_resolution" />
              </cell>
              <cell id="{$cellCreditAmt}" colspan="1" rowspan="1">
                <labels><label description="Credit Amount" languagecode="1033" /></labels>
                <control id="rma_creditamount" classid="{533B9E00-756B-4312-95A0-DC888637AC78}" datafieldname="rma_creditamount" />
              </cell>
              <cell id="{$cellClosedDate}" colspan="1" rowspan="1">
                <labels><label description="Closed Date" languagecode="1033" /></labels>
                <control id="rma_closeddate" classid="{5B773807-9FB2-42db-97C3-7A91EFF8ADFF}" datafieldname="rma_closeddate" />
              </cell>
              <cell id="{NewGuid}" colspan="1" rowspan="1" showlabel="false">
                <labels><label description="spacer" languagecode="1033" /></labels>
              </cell>
            </row>
          </rows>
        </section>

      </sections>
    </column>
  </columns>
</tab>

<!-- TAB 2: NOTES — Claim Notes subgrid + Timeline -->
<tab verticallayout="true" id="{$tabNotesId}" IsUserDefined="1" name="notes_tab">
  <labels><label description="Notes" languagecode="1033" /></labels>
  <columns>
    <column width="50%">
      <sections>
        <section showlabel="true" showbar="true" id="{$secClaimNotesId}" columns="1">
          <labels><label description="Claim Notes" languagecode="1033" /></labels>
          <rows>
            <row>
              <cell id="{$cellClaimNotesGrid}" colspan="1" rowspan="20">
                <labels><label description="Claim Notes" languagecode="1033" /></labels>
                <control id="rma_claimnotes_grid" classid="{E7A81278-8635-4d9e-8D4D-59480B391C5B}">
                  <parameters>
                    <ViewId>{00000000-0000-0000-00AA-000010001003}</ViewId>
                    <IsUserView>false</IsUserView>
                    <RelationshipName>rma_claimnote_rma_claim</RelationshipName>
                    <TargetEntityType>rma_claimnote</TargetEntityType>
                    <AutoExpand>Fixed</AutoExpand>
                    <EnableQuickFind>false</EnableQuickFind>
                    <EnableViewPicker>false</EnableViewPicker>
                    <EnableJumpBar>false</EnableJumpBar>
                    <ChartGridMode>Grid</ChartGridMode>
                    <VisualizationId />
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
        <section showlabel="true" showbar="true" id="{$secTimelineId}" columns="1">
          <labels><label description="Timeline" languagecode="1033" /></labels>
          <rows>
            <row>
              <cell id="{$cellTimeline}" showlabel="false" rowspan="20" auto="false">
                <labels><label description="Timeline" languagecode="1033" /></labels>
                <control id="notescontrol" classid="{06375649-c143-495e-a496-c962e5b4488e}">
                  <parameters>
                    <DefaultTabId>NotesTab</DefaultTabId>
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

<!-- TAB 3: APPROVALS — Approval Records + Approval History -->
<tab verticallayout="true" id="{$tabApprovalsId}" IsUserDefined="1" name="approvals_tab">
  <labels><label description="Approvals" languagecode="1033" /></labels>
  <columns>
    <column width="100%">
      <sections>
        <section showlabel="true" showbar="true" id="{$secApprovalsRecsId}" columns="1">
          <labels><label description="Approval Requests" languagecode="1033" /></labels>
          <rows>
            <row>
              <cell id="{$cellApprovalRecsGrid}" colspan="1" rowspan="10">
                <labels><label description="Approval Requests" languagecode="1033" /></labels>
                <control id="rma_approvalrecords_grid" classid="{E7A81278-8635-4d9e-8D4D-59480B391C5B}">
                  <parameters>
                    <ViewId>{00000000-0000-0000-00AA-000010001003}</ViewId>
                    <IsUserView>false</IsUserView>
                    <RelationshipName>rma_approvalrecord_rma_claim</RelationshipName>
                    <TargetEntityType>rma_approvalrecord</TargetEntityType>
                    <AutoExpand>Fixed</AutoExpand>
                    <EnableQuickFind>false</EnableQuickFind>
                    <EnableViewPicker>false</EnableViewPicker>
                    <EnableJumpBar>false</EnableJumpBar>
                    <ChartGridMode>Grid</ChartGridMode>
                    <VisualizationId />
                    <IsUserChart>false</IsUserChart>
                    <EnableChartPicker>false</EnableChartPicker>
                    <RecordsPerPage>10</RecordsPerPage>
                  </parameters>
                </control>
              </cell>
            </row>
          </rows>
        </section>
        <section showlabel="true" showbar="true" id="{$secApprovalsHistId}" columns="1">
          <labels><label description="Approval History" languagecode="1033" /></labels>
          <rows>
            <row>
              <cell id="{NewGuid}" colspan="1" rowspan="10">
                <labels><label description="Approval History" languagecode="1033" /></labels>
                <control id="rma_approvalhistory_grid" classid="{E7A81278-8635-4d9e-8D4D-59480B391C5B}">
                  <parameters>
                    <ViewId>{00000000-0000-0000-00AA-000010001003}</ViewId>
                    <IsUserView>false</IsUserView>
                    <RelationshipName>rma_approvalhistory_rma_claim</RelationshipName>
                    <TargetEntityType>rma_approvalhistory</TargetEntityType>
                    <AutoExpand>Fixed</AutoExpand>
                    <EnableQuickFind>false</EnableQuickFind>
                    <EnableViewPicker>false</EnableViewPicker>
                    <EnableJumpBar>false</EnableJumpBar>
                    <ChartGridMode>Grid</ChartGridMode>
                    <VisualizationId />
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

<!-- TAB 4: EMAILS — Email Log for this claim -->
<tab verticallayout="true" id="{$tabEmailsId}" IsUserDefined="1" name="emails_tab">
  <labels><label description="Emails" languagecode="1033" /></labels>
  <columns>
    <column width="100%">
      <sections>
        <section showlabel="true" showbar="true" id="{$secEmailsId}" columns="1">
          <labels><label description="Email Log" languagecode="1033" /></labels>
          <rows>
            <row>
              <cell id="{$cellEmailsGrid}" colspan="1" rowspan="20">
                <labels><label description="Email Log" languagecode="1033" /></labels>
                <control id="rma_emaillog_grid" classid="{E7A81278-8635-4d9e-8D4D-59480B391C5B}">
                  <parameters>
                    <ViewId>{00000000-0000-0000-00AA-000010001003}</ViewId>
                    <IsUserView>false</IsUserView>
                    <RelationshipName>rma_emaillog_rma_claim</RelationshipName>
                    <TargetEntityType>rma_emaillog</TargetEntityType>
                    <AutoExpand>Fixed</AutoExpand>
                    <EnableQuickFind>false</EnableQuickFind>
                    <EnableViewPicker>false</EnableViewPicker>
                    <EnableJumpBar>false</EnableJumpBar>
                    <ChartGridMode>Grid</ChartGridMode>
                    <VisualizationId />
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

<header id="{$headerId}" celllabelposition="Top" columns="1111" labelwidth="115" celllabelalignment="Left">
  <rows>
    <row>
      <cell id="{$hCell1}" colspan="1" rowspan="1">
        <labels><label description="Claim Number" languagecode="1033" /></labels>
        <control id="header_rma_claimnumber" classid="{4273EDBD-AC1D-40d3-9FB2-095C621B552D}" datafieldname="rma_claimnumber" />
      </cell>
      <cell id="{$hCell2}" colspan="1" rowspan="1">
        <labels><label description="Status" languagecode="1033" /></labels>
        <control id="header_rma_status" classid="{3EF39988-22BB-4f0b-BBBE-64B5A3748AEE}" datafieldname="rma_status" />
      </cell>
      <cell id="{$hCell3}" colspan="1" rowspan="1">
        <labels><label description="Plant" languagecode="1033" /></labels>
        <control id="header_rma_assignedplant" classid="{270BD3DB-D9AF-4782-9025-509E298DEC0A}" datafieldname="rma_assignedplant" />
      </cell>
      <cell id="{$hCell4}" colspan="1" rowspan="1">
        <labels><label description="Owner" languagecode="1033" /></labels>
        <control id="header_ownerid" classid="{270BD3DB-D9AF-4782-9025-509E298DEC0A}" datafieldname="ownerid" />
      </cell>
    </row>
  </rows>
</header>

<footer id="{$footerId}" celllabelposition="Top" columns="11" labelwidth="115" celllabelalignment="Left">
  <rows>
    <row>
      <cell id="{$footCell}" showlabel="false">
        <labels><label description="" languagecode="1033" /></labels>
      </cell>
    </row>
  </rows>
</footer>

</form>
"@

# Replace inline {NewGuid} placeholders with unique GUIDs each occurrence
while ($formXml -match '\{NewGuid\}') {
    $formXml = [regex]::new('\{NewGuid\}').Replace($formXml, "{$(NewGuid)}", 1)
}

# Save snapshot
$snap = "C:\Users\billwhalen\OneDrive - Microsoft\Documents\GitHub\RAPP\CommunityRAPP-main\customers\ametek\hkp_rma\d365\rma_claim_main_form_new.xml"
$formXml | Out-File -Encoding UTF8 $snap
Write-Host "  [saved] new form xml -> $snap  ($($formXml.Length) chars)" -ForegroundColor Green

# --------------------------------------------------------------------------
# PATCH the form
# --------------------------------------------------------------------------
Write-Host "`nPATCHing main form $formId..." -ForegroundColor Cyan

$body = @{ formxml = $formXml } | ConvertTo-Json -Compress
$h = $hdrBase.Clone(); $h['If-Match'] = '*'; $h['Content-Type'] = 'application/json; charset=utf-8'

try {
    Invoke-WebRequest -Uri "$OrgUrl/api/data/v9.2/systemforms($formId)" -Method Patch -Headers $h -Body $body -ErrorAction Stop | Out-Null
    Write-Host "  [ok] form patched" -ForegroundColor Green
} catch {
    $m = $_.Exception.Message
    if ($_.ErrorDetails.Message) { $m = $_.ErrorDetails.Message }
    Write-Host "  [error] $m" -ForegroundColor Red
    throw
}

Write-Host "`n=== Phase C1 DONE ===" -ForegroundColor Cyan
Write-Host "Form ID:    $formId" -ForegroundColor DarkGray
Write-Host ""
Write-Host "Next: run 'pac solution publish' to make form live." -ForegroundColor Yellow
