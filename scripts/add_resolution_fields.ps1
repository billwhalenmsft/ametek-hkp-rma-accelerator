<#
.SYNOPSIS
    Adds resolution + ERP audit fields to rma_approvalhistory, and extends the
    rma_action picklist with resolution outcomes.

    Schema deltas:
      rma_approvalhistory:
        + rma_amount              (Money)   final amount captured at resolve
        + rma_amountoriginal      (Money)   amount the manager approved
        + rma_amountoverridden    (Bool)    true if operator changed amount at confirm
        + rma_overridereason      (Text)    why amount was changed
        + rma_emailto             (Text)    recipient address of resolution email
        + rma_emailbody           (Memo)    snapshot of email body that was sent
        + rma_erpstatus           (Picklist) Not Required / Pending / Sent / Failed
        + rma_erpreference        (Text)    ERP doc id once returned
        + rma_erppayload          (Memo)    JSON payload pushed to ERP

      rma_action picklist (rma_approvalhistory):
        + Credit Issued
        + Replacement Sent
        + Repair Completed
        + Other Action

    Idempotent.

.NOTES
    Requires az login. Uses RMAReturnsMonitor solution.
#>

$ErrorActionPreference = "Stop"
$orgUrl       = "https://org6feab6b5.crm.dynamics.com"
$solutionName = "RMAReturnsMonitor"

Write-Host "Acquiring token..." -ForegroundColor Cyan
$token = (az account get-access-token --resource $orgUrl --query accessToken -o tsv)
$hdr = @{
    Authorization              = "Bearer $token"
    Accept                     = "application/json"
    "Content-Type"             = "application/json; charset=utf-8"
    "OData-Version"            = "4.0"
    "OData-MaxVersion"         = "4.0"
    "MSCRM.SolutionUniqueName" = $solutionName
}

function Invoke-Dv {
    param([string]$Method, [string]$Path, $Body = $null)
    $url = "$orgUrl/api/data/v9.2/$Path"
    $params = @{ Uri = $url; Method = $Method; Headers = $hdr; TimeoutSec = 180 }
    if ($Body) { $params.Body = ($Body | ConvertTo-Json -Depth 20 -Compress) }
    return Invoke-RestMethod @params
}

function Find-Column {
    param([string]$Table, [string]$Col)
    try {
        return Invoke-Dv -Method GET -Path "EntityDefinitions(LogicalName='$Table')/Attributes(LogicalName='$Col')?`$select=LogicalName"
    } catch { return $null }
}

function Add-Col {
    param([string]$Table, [string]$Logical, [hashtable]$Body)
    if (Find-Column -Table $Table -Col $Logical) { Write-Host "    $Logical exists - skip" -ForegroundColor DarkYellow; return }
    Write-Host "    + $Logical" -ForegroundColor White
    Invoke-Dv -Method POST -Path "EntityDefinitions(LogicalName='$Table')/Attributes" -Body $Body | Out-Null
}

function P-Text  { param([string]$S, [string]$D, [int]$Max = 100, [bool]$Req = $false)
    @{ "@odata.type" = "Microsoft.Dynamics.CRM.StringAttributeMetadata"; AttributeType = "String"; AttributeTypeName = @{ Value = "StringType" }; SchemaName = $S; DisplayName = @{ LocalizedLabels = @(@{ Label = $D; LanguageCode = 1033 }) }; RequiredLevel = @{ Value = ($(if($Req){"ApplicationRequired"}else{"None"})); CanBeChanged = $true }; MaxLength = $Max; FormatName = @{ Value = "Text" } }
}
function P-Memo  { param([string]$S, [string]$D, [int]$Max = 10000)
    @{ "@odata.type" = "Microsoft.Dynamics.CRM.MemoAttributeMetadata"; AttributeType = "Memo"; AttributeTypeName = @{ Value = "MemoType" }; SchemaName = $S; DisplayName = @{ LocalizedLabels = @(@{ Label = $D; LanguageCode = 1033 }) }; RequiredLevel = @{ Value = "None"; CanBeChanged = $true }; MaxLength = $Max; Format = "TextArea" }
}
function P-Money { param([string]$S, [string]$D)
    @{ "@odata.type" = "Microsoft.Dynamics.CRM.MoneyAttributeMetadata"; AttributeType = "Money"; AttributeTypeName = @{ Value = "MoneyType" }; SchemaName = $S; DisplayName = @{ LocalizedLabels = @(@{ Label = $D; LanguageCode = 1033 }) }; RequiredLevel = @{ Value = "None"; CanBeChanged = $true }; PrecisionSource = 2 }
}
function P-Bool  { param([string]$S, [string]$D, [bool]$Default = $false)
    @{ "@odata.type" = "Microsoft.Dynamics.CRM.BooleanAttributeMetadata"; AttributeType = "Boolean"; AttributeTypeName = @{ Value = "BooleanType" }; SchemaName = $S; DisplayName = @{ LocalizedLabels = @(@{ Label = $D; LanguageCode = 1033 }) }; RequiredLevel = @{ Value = "None"; CanBeChanged = $true }; DefaultValue = $Default; OptionSet = @{ TrueOption = @{ Value = 1; Label = @{ LocalizedLabels = @(@{ Label = "Yes"; LanguageCode = 1033 }) } }; FalseOption = @{ Value = 0; Label = @{ LocalizedLabels = @(@{ Label = "No"; LanguageCode = 1033 }) } } } }
}
function P-Picklist { param([string]$S, [string]$D, [string[]]$Opts)
    $list = @(); $val = 100000000
    foreach ($o in $Opts) { $list += @{ "@odata.type" = "Microsoft.Dynamics.CRM.OptionMetadata"; Value = $val++; Label = @{ LocalizedLabels = @(@{ Label = $o; LanguageCode = 1033 }) } } }
    @{ "@odata.type" = "Microsoft.Dynamics.CRM.PicklistAttributeMetadata"; AttributeType = "Picklist"; AttributeTypeName = @{ Value = "PicklistType" }; SchemaName = $S; DisplayName = @{ LocalizedLabels = @(@{ Label = $D; LanguageCode = 1033 }) }; RequiredLevel = @{ Value = "None"; CanBeChanged = $true }; OptionSet = @{ "@odata.type" = "Microsoft.Dynamics.CRM.OptionSetMetadata"; OptionSetType = "Picklist"; IsGlobal = $false; Options = $list } }
}

# Add a new option to an existing local picklist on a table. Idempotent.
function Add-PicklistOption {
    param([string]$Table, [string]$Col, [string]$Label, [int]$Value)
    $existing = Invoke-Dv -Method GET -Path "EntityDefinitions(LogicalName='$Table')/Attributes(LogicalName='$Col')/Microsoft.Dynamics.CRM.PicklistAttributeMetadata?`$expand=OptionSet"
    $found = $existing.OptionSet.Options | Where-Object { $_.Value -eq $Value -or ($_.Label.LocalizedLabels[0].Label -eq $Label) }
    if ($found) { Write-Host "    option '$Label' ($Value) exists - skip" -ForegroundColor DarkYellow; return }
    $body = @{
        EntityLogicalName    = $Table
        AttributeLogicalName = $Col
        Value                = $Value
        Label                = @{ LocalizedLabels = @(@{ Label = $Label; LanguageCode = 1033 }) }
        SolutionUniqueName   = $solutionName
    }
    Write-Host "    + option '$Label' ($Value) -> $Table.$Col" -ForegroundColor White
    Invoke-Dv -Method POST -Path "InsertOptionValue" -Body $body | Out-Null
}

# ============================================================================
# rma_approvalhistory column additions
# ============================================================================
Write-Host "`n========== rma_approvalhistory columns ==========" -ForegroundColor Cyan
$T = "rma_approvalhistory"
Add-Col $T "rma_amount"             (P-Money "rma_Amount"            "Amount")
Add-Col $T "rma_amountoriginal"     (P-Money "rma_AmountOriginal"    "Amount (Original/Approved)")
Add-Col $T "rma_amountoverridden"   (P-Bool  "rma_AmountOverridden"  "Amount Overridden" $false)
Add-Col $T "rma_overridereason"     (P-Text  "rma_OverrideReason"    "Override Reason" 500)
Add-Col $T "rma_emailto"            (P-Text  "rma_EmailTo"           "Email To" 200)
Add-Col $T "rma_emailbody"          (P-Memo  "rma_EmailBody"         "Email Body" 10000)
Add-Col $T "rma_erpstatus"          (P-Picklist "rma_ErpStatus" "ERP Status" @("Not Required","Pending","Sent","Failed"))
Add-Col $T "rma_erpreference"       (P-Text  "rma_ErpReference"      "ERP Reference" 100)
Add-Col $T "rma_erppayload"         (P-Memo  "rma_ErpPayload"        "ERP Payload (JSON)" 10000)

# ============================================================================
# Extend rma_action picklist with resolution outcomes
# Existing options:
#   100000000 Approval Requested
#   100000001 Approved
#   100000002 Denied
#   100000003 Escalated
# New:
#   100000004 Credit Issued
#   100000005 Replacement Sent
#   100000006 Repair Completed
#   100000007 Other Action
# ============================================================================
Write-Host "`n========== rma_action picklist ==========" -ForegroundColor Cyan
Add-PicklistOption -Table $T -Col "rma_action" -Label "Credit Issued"     -Value 100000004
Add-PicklistOption -Table $T -Col "rma_action" -Label "Replacement Sent"  -Value 100000005
Add-PicklistOption -Table $T -Col "rma_action" -Label "Repair Completed"  -Value 100000006
Add-PicklistOption -Table $T -Col "rma_action" -Label "Other Action"      -Value 100000007

# ============================================================================
# Publish all customizations
# ============================================================================
Write-Host "`nPublishing all customizations..." -ForegroundColor Cyan
$pubBody = @{ ParameterXml = "<importexportxml><entities><entity>rma_approvalhistory</entity></entities></importexportxml>" }
Invoke-Dv -Method POST -Path "PublishXml" -Body $pubBody | Out-Null
Write-Host "Published" -ForegroundColor Green

Write-Host "`nDONE." -ForegroundColor Green
