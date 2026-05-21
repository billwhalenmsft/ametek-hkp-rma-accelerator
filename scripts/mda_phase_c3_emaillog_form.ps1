<#
.SYNOPSIS
    Phase C3 — rma_emaillog main form redesign.
    Optimized for inbound email triage workbench:
      - Header: Subject, Direction, Received Date, Is Processed
      - General tab: From/To, Received/Sent dates, Body Preview, Body
      - Linked Claim tab: rma_claim lookup + extracted fields the AI populated
#>
[CmdletBinding()]
param([string]$OrgUrl = "https://org6feab6b5.crm.dynamics.com")
$ErrorActionPreference = "Stop"
$token = (az account get-access-token --resource $OrgUrl --query accessToken -o tsv)
$hdr = @{
    Authorization      = "Bearer $token"
    Accept             = "application/json"
    "OData-Version"    = "4.0"
    "OData-MaxVersion" = "4.0"
    "If-Match"         = "*"
    "Content-Type"     = "application/json; charset=utf-8"
    "MSCRM.SolutionUniqueName" = "RMAReturnsMonitor"
}
$formId = "eec402c7-2c29-412c-897d-c5d17ec3668c"
function NewGuid { return [Guid]::NewGuid().ToString().ToLower() }

$tab1=NewGuid; $tab2=NewGuid
$secMeta=NewGuid; $secBody=NewGuid; $secLink=NewGuid
$h1=NewGuid;$h2=NewGuid;$h3=NewGuid;$h4=NewGuid
$cellFrom=NewGuid; $cellTo=NewGuid; $cellSentBy=NewGuid; $cellMsgId=NewGuid
$cellRecv=NewGuid; $cellSent=NewGuid; $cellTpl=NewGuid; $cellSrc=NewGuid
$cellBodyPrev=NewGuid; $cellBody=NewGuid
$cellClaim=NewGuid; $cellClaimName=NewGuid

$xml = @"
<form headerdensity="HighWithControls">
<tabs>

<tab verticallayout="true" id="{$tab1}" IsUserDefined="1" name="general_tab">
  <labels><label description="General" languagecode="1033" /></labels>
  <columns>
    <column width="100%">
      <sections>
        <section showlabel="true" showbar="true" id="{$secMeta}" columns="4" labelwidth="115">
          <labels><label description="Email Metadata" languagecode="1033" /></labels>
          <rows>
            <row>
              <cell id="{$cellFrom}"><labels><label description="From Address" languagecode="1033" /></labels>
                <control id="rma_fromaddress" classid="{4273EDBD-AC1D-40d3-9FB2-095C621B552D}" datafieldname="rma_fromaddress" /></cell>
              <cell id="{$cellTo}"><labels><label description="Recipient" languagecode="1033" /></labels>
                <control id="rma_recipient" classid="{4273EDBD-AC1D-40d3-9FB2-095C621B552D}" datafieldname="rma_recipient" /></cell>
              <cell id="{$cellSentBy}"><labels><label description="Sent By" languagecode="1033" /></labels>
                <control id="rma_sentby" classid="{4273EDBD-AC1D-40d3-9FB2-095C621B552D}" datafieldname="rma_sentby" /></cell>
              <cell id="{$cellMsgId}"><labels><label description="Message ID" languagecode="1033" /></labels>
                <control id="rma_messageid" classid="{4273EDBD-AC1D-40d3-9FB2-095C621B552D}" datafieldname="rma_messageid" /></cell>
            </row>
            <row>
              <cell id="{$cellRecv}"><labels><label description="Received Date" languagecode="1033" /></labels>
                <control id="rma_receiveddate" classid="{5B773807-9FB2-42db-97C3-7A91EFF8ADFF}" datafieldname="rma_receiveddate" /></cell>
              <cell id="{$cellSent}"><labels><label description="Sent Date" languagecode="1033" /></labels>
                <control id="rma_sentdate" classid="{5B773807-9FB2-42db-97C3-7A91EFF8ADFF}" datafieldname="rma_sentdate" /></cell>
              <cell id="{$cellTpl}"><labels><label description="Template Used" languagecode="1033" /></labels>
                <control id="rma_templateused" classid="{4273EDBD-AC1D-40d3-9FB2-095C621B552D}" datafieldname="rma_templateused" /></cell>
              <cell id="{$cellSrc}"><labels><label description="Source SharePoint ID" languagecode="1033" /></labels>
                <control id="rma_sourcesharepointid" classid="{4273EDBD-AC1D-40d3-9FB2-095C621B552D}" datafieldname="rma_sourcesharepointid" /></cell>
            </row>
          </rows>
        </section>

        <section showlabel="true" showbar="true" id="{$secBody}" columns="1" labelwidth="115">
          <labels><label description="Email Body" languagecode="1033" /></labels>
          <rows>
            <row>
              <cell id="{$cellBodyPrev}"><labels><label description="Body Preview" languagecode="1033" /></labels>
                <control id="rma_bodypreview" classid="{4273EDBD-AC1D-40d3-9FB2-095C621B552D}" datafieldname="rma_bodypreview" /></cell>
            </row>
            <row>
              <cell id="{$cellBody}" rowspan="8"><labels><label description="Body (Full)" languagecode="1033" /></labels>
                <control id="rma_body" classid="{E0DECE4B-6FC8-4a8f-A065-082708572369}" datafieldname="rma_body" /></cell>
            </row>
            <row /><row /><row /><row /><row /><row /><row />
          </rows>
        </section>

      </sections>
    </column>
  </columns>
</tab>

<tab verticallayout="true" id="{$tab2}" IsUserDefined="1" name="linkedclaim_tab">
  <labels><label description="Linked Claim" languagecode="1033" /></labels>
  <columns>
    <column width="100%">
      <sections>
        <section showlabel="true" showbar="true" id="{$secLink}" columns="2" labelwidth="115">
          <labels><label description="Linked RMA Claim" languagecode="1033" /></labels>
          <rows>
            <row>
              <cell id="{$cellClaim}" colspan="2"><labels><label description="RMA Claim" languagecode="1033" /></labels>
                <control id="rma_claim" classid="{270BD3DB-D9AF-4782-9025-509E298DEC0A}" datafieldname="rma_claim" /></cell>
            </row>
            <row>
              <cell id="{$cellClaimName}" colspan="2"><labels><label description="Claim Name" languagecode="1033" /></labels>
                <control id="rma_claimname" classid="{4273EDBD-AC1D-40d3-9FB2-095C621B552D}" datafieldname="rma_claimname" /></cell>
            </row>
          </rows>
        </section>
      </sections>
    </column>
  </columns>
</tab>

</tabs>

<header id="{$(NewGuid)}" celllabelposition="Top" columns="1111" labelwidth="115" celllabelalignment="Left">
  <rows>
    <row>
      <cell id="{$h1}"><labels><label description="Subject" languagecode="1033" /></labels>
        <control id="header_rma_subject" classid="{4273EDBD-AC1D-40d3-9FB2-095C621B552D}" datafieldname="rma_subject" /></cell>
      <cell id="{$h2}"><labels><label description="Direction" languagecode="1033" /></labels>
        <control id="header_rma_direction" classid="{3EF39988-22BB-4f0b-BBBE-64B5A3748AEE}" datafieldname="rma_direction" /></cell>
      <cell id="{$h3}"><labels><label description="Received Date" languagecode="1033" /></labels>
        <control id="header_rma_receiveddate" classid="{5B773807-9FB2-42db-97C3-7A91EFF8ADFF}" datafieldname="rma_receiveddate" /></cell>
      <cell id="{$h4}"><labels><label description="Is Processed" languagecode="1033" /></labels>
        <control id="header_rma_isprocessed" classid="{B0C6723A-8503-4fd7-BB28-C8A06AC933C2}" datafieldname="rma_isprocessed" /></cell>
    </row>
  </rows>
</header>

<footer id="{$(NewGuid)}" celllabelposition="Top" columns="11" labelwidth="115" celllabelalignment="Left">
  <rows>
    <row>
      <cell id="{$(NewGuid)}" showlabel="false">
        <labels><label description="" languagecode="1033" /></labels>
      </cell>
    </row>
  </rows>
</footer>

</form>
"@

Write-Host "PATCHing rma_emaillog main form $formId..." -ForegroundColor Cyan
$body = @{ formxml = $xml } | ConvertTo-Json -Compress
try {
    Invoke-WebRequest -Uri "$OrgUrl/api/data/v9.2/systemforms($formId)" -Method Patch -Headers $hdr -Body $body -ErrorAction Stop | Out-Null
    Write-Host "  [ok]" -ForegroundColor Green
} catch {
    $m = $_.Exception.Message
    if ($_.ErrorDetails.Message) { $m = $_.ErrorDetails.Message }
    Write-Host "  [error] $m" -ForegroundColor Red
    throw
}
Write-Host "Done." -ForegroundColor Cyan
