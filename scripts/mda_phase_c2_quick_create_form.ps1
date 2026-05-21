<#
.SYNOPSIS
    Phase C2 — rma_claim Quick Create form.
    Adds essential intake fields for the "Create RMA Claim from Email" path
    + manual triage worker creating a claim from scratch.

    Fields:  Customer Name, Customer Email, Customer Region, Part Number,
             Quantity, Failure Mode, Failure Description, Assigned Plant
#>

[CmdletBinding()]
param(
    [string]$OrgUrl = "https://org6feab6b5.crm.dynamics.com"
)
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

$formId = "2fe1a3f1-41c4-4a16-b6cd-3af53afb9724"
function NewGuid { return [Guid]::NewGuid().ToString().ToLower() }

$tabId = NewGuid; $secId = NewGuid
$c1=NewGuid; $c2=NewGuid; $c3=NewGuid; $c4=NewGuid
$c5=NewGuid; $c6=NewGuid; $c7=NewGuid; $c8=NewGuid

$xml = @"
<form><tabs><tab verticallayout="true" id="{$tabId}" IsUserDefined="1">
<labels><label description="" languagecode="1033" /></labels>
<columns>
  <column width="100%">
    <sections>
      <section showlabel="false" showbar="false" IsUserDefined="0" id="{$secId}" columns="1">
        <labels><label description="New RMA Claim" languagecode="1033" /></labels>
        <rows>
          <row>
            <cell id="{$c1}"><labels><label description="Customer Name" languagecode="1033" /></labels>
              <control id="rma_customername" classid="{4273EDBD-AC1D-40d3-9FB2-095C621B552D}" datafieldname="rma_customername" /></cell>
          </row>
          <row>
            <cell id="{$c2}"><labels><label description="Customer Email" languagecode="1033" /></labels>
              <control id="rma_customeremail" classid="{4273EDBD-AC1D-40d3-9FB2-095C621B552D}" datafieldname="rma_customeremail" /></cell>
          </row>
          <row>
            <cell id="{$c3}"><labels><label description="Customer Region" languagecode="1033" /></labels>
              <control id="rma_customerregion" classid="{3EF39988-22BB-4f0b-BBBE-64B5A3748AEE}" datafieldname="rma_customerregion" /></cell>
          </row>
          <row>
            <cell id="{$c4}"><labels><label description="Part Number" languagecode="1033" /></labels>
              <control id="rma_partnumber" classid="{4273EDBD-AC1D-40d3-9FB2-095C621B552D}" datafieldname="rma_partnumber" /></cell>
          </row>
          <row>
            <cell id="{$c5}"><labels><label description="Quantity" languagecode="1033" /></labels>
              <control id="rma_quantity" classid="{C6D124CA-7EDA-4a60-AEA9-7FB8D318B68F}" datafieldname="rma_quantity" /></cell>
          </row>
          <row>
            <cell id="{$c6}"><labels><label description="Failure Mode" languagecode="1033" /></labels>
              <control id="rma_failuremode" classid="{3EF39988-22BB-4f0b-BBBE-64B5A3748AEE}" datafieldname="rma_failuremode" /></cell>
          </row>
          <row>
            <cell id="{$c7}" rowspan="2"><labels><label description="Failure Description" languagecode="1033" /></labels>
              <control id="rma_failuredescription" classid="{E0DECE4B-6FC8-4a8f-A065-082708572369}" datafieldname="rma_failuredescription" /></cell>
          </row>
          <row />
          <row>
            <cell id="{$c8}"><labels><label description="Assigned Plant" languagecode="1033" /></labels>
              <control id="rma_assignedplant" classid="{270BD3DB-D9AF-4782-9025-509E298DEC0A}" datafieldname="rma_assignedplant" /></cell>
          </row>
        </rows>
      </section>
    </sections>
  </column>
</columns>
</tab></tabs></form>
"@

Write-Host "PATCHing Quick Create form $formId..." -ForegroundColor Cyan
$body = @{ formxml = $xml } | ConvertTo-Json -Compress
try {
    Invoke-WebRequest -Uri "$OrgUrl/api/data/v9.2/systemforms($formId)" -Method Patch -Headers $hdr -Body $body -ErrorAction Stop | Out-Null
    Write-Host "  [ok] quick create form patched" -ForegroundColor Green
} catch {
    $m = $_.Exception.Message
    if ($_.ErrorDetails.Message) { $m = $_.ErrorDetails.Message }
    Write-Host "  [error] $m" -ForegroundColor Red
    throw
}
Write-Host "`nDone." -ForegroundColor Cyan
