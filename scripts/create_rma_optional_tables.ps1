<#
.SYNOPSIS
    Creates the 5 optional Dataverse tables for the RMA Returns Monitor app:
    - rma_PlantApprover    (Teams approval routing)
    - rma_ApprovalHistory  (Detailed audit trail)
    - rma_EmailTemplate    (Customer email templates)
    - rma_EmailSignature   (Email signatures)
    - rma_EmailLog         (Sent email tracking)
    Adds all 5 to the RMAReturnsMonitor solution.

.NOTES
    Idempotent - safe to re-run. Uses MSCRM.SolutionUniqueName header for solution scoping.
#>

$ErrorActionPreference = "Stop"
$orgUrl = "https://org6feab6b5.crm.dynamics.com"
$solutionName = "RMAReturnsMonitor"
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
    param([string]$Method, [string]$Path, $Body = $null, [int]$TimeoutSec = 180)
    $url = "$orgUrl/api/data/v9.2/$Path"
    $params = @{
        Uri        = $url
        Method     = $Method
        Headers    = $hdr
        TimeoutSec = $TimeoutSec
    }
    if ($Body) { $params.Body = ($Body | ConvertTo-Json -Depth 20 -Compress) }
    return Invoke-RestMethod @params
}

function Find-Table {
    param([string]$LogicalName)
    try {
        return Invoke-Dv -Method GET -Path "EntityDefinitions(LogicalName='$LogicalName')?`$select=LogicalName,SchemaName,MetadataId"
    } catch { return $null }
}

function Find-Column {
    param([string]$Table, [string]$Col)
    try {
        return Invoke-Dv -Method GET -Path "EntityDefinitions(LogicalName='$Table')/Attributes(LogicalName='$Col')?`$select=LogicalName"
    } catch { return $null }
}

# --- Attribute factories ---
function P-Picklist { param([string]$S, [string]$D, [string[]]$Opts, [bool]$Req = $false)
    $list = @(); $val = 100000000
    foreach ($o in $Opts) { $list += @{ "@odata.type" = "Microsoft.Dynamics.CRM.OptionMetadata"; Value = $val++; Label = @{ LocalizedLabels = @(@{ Label = $o; LanguageCode = 1033 }) } } }
    @{ "@odata.type" = "Microsoft.Dynamics.CRM.PicklistAttributeMetadata"; AttributeType = "Picklist"; AttributeTypeName = @{ Value = "PicklistType" }; SchemaName = $S; DisplayName = @{ LocalizedLabels = @(@{ Label = $D; LanguageCode = 1033 }) }; RequiredLevel = @{ Value = ($(if($Req){"ApplicationRequired"}else{"None"})); CanBeChanged = $true }; OptionSet = @{ "@odata.type" = "Microsoft.Dynamics.CRM.OptionSetMetadata"; OptionSetType = "Picklist"; IsGlobal = $false; Options = $list } }
}
function P-Text  { param([string]$S, [string]$D, [int]$Max = 100, [bool]$Req = $false, [string]$Fmt = "Text")
    @{ "@odata.type" = "Microsoft.Dynamics.CRM.StringAttributeMetadata"; AttributeType = "String"; AttributeTypeName = @{ Value = "StringType" }; SchemaName = $S; DisplayName = @{ LocalizedLabels = @(@{ Label = $D; LanguageCode = 1033 }) }; RequiredLevel = @{ Value = ($(if($Req){"ApplicationRequired"}else{"None"})); CanBeChanged = $true }; MaxLength = $Max; FormatName = @{ Value = $Fmt } }
}
function P-Memo  { param([string]$S, [string]$D, [int]$Max = 4000, [bool]$Req = $false)
    @{ "@odata.type" = "Microsoft.Dynamics.CRM.MemoAttributeMetadata"; AttributeType = "Memo"; AttributeTypeName = @{ Value = "MemoType" }; SchemaName = $S; DisplayName = @{ LocalizedLabels = @(@{ Label = $D; LanguageCode = 1033 }) }; RequiredLevel = @{ Value = ($(if($Req){"ApplicationRequired"}else{"None"})); CanBeChanged = $true }; MaxLength = $Max; Format = "TextArea" }
}
function P-Money { param([string]$S, [string]$D, [bool]$Req = $false)
    @{ "@odata.type" = "Microsoft.Dynamics.CRM.MoneyAttributeMetadata"; AttributeType = "Money"; AttributeTypeName = @{ Value = "MoneyType" }; SchemaName = $S; DisplayName = @{ LocalizedLabels = @(@{ Label = $D; LanguageCode = 1033 }) }; RequiredLevel = @{ Value = ($(if($Req){"ApplicationRequired"}else{"None"})); CanBeChanged = $true }; PrecisionSource = 2 }
}
function P-DT    { param([string]$S, [string]$D, [bool]$Req = $false)
    @{ "@odata.type" = "Microsoft.Dynamics.CRM.DateTimeAttributeMetadata"; AttributeType = "DateTime"; AttributeTypeName = @{ Value = "DateTimeType" }; SchemaName = $S; DisplayName = @{ LocalizedLabels = @(@{ Label = $D; LanguageCode = 1033 }) }; RequiredLevel = @{ Value = ($(if($Req){"ApplicationRequired"}else{"None"})); CanBeChanged = $true }; Format = "DateAndTime"; DateTimeBehavior = @{ Value = "UserLocal" } }
}
function P-Bool  { param([string]$S, [string]$D, [bool]$Default = $false, [bool]$Req = $false)
    @{ "@odata.type" = "Microsoft.Dynamics.CRM.BooleanAttributeMetadata"; AttributeType = "Boolean"; AttributeTypeName = @{ Value = "BooleanType" }; SchemaName = $S; DisplayName = @{ LocalizedLabels = @(@{ Label = $D; LanguageCode = 1033 }) }; RequiredLevel = @{ Value = ($(if($Req){"ApplicationRequired"}else{"None"})); CanBeChanged = $true }; DefaultValue = $Default; OptionSet = @{ TrueOption = @{ Value = 1; Label = @{ LocalizedLabels = @(@{ Label = "Yes"; LanguageCode = 1033 }) } }; FalseOption = @{ Value = 0; Label = @{ LocalizedLabels = @(@{ Label = "No"; LanguageCode = 1033 }) } } } }
}

# --- Create table (with primary name attr) ---
function Make-Table {
    param([string]$L, [string]$S, [string]$Disp, [string]$DispP, [string]$Desc, [string]$PnSchema, [string]$PnDisp, [int]$PnLen = 200)
    if (Find-Table -LogicalName $L) {
        Write-Host "  Table $L exists - skip" -ForegroundColor DarkYellow
        return
    }
    $primary = @{ "@odata.type" = "Microsoft.Dynamics.CRM.StringAttributeMetadata"; AttributeType = "String"; AttributeTypeName = @{ Value = "StringType" }; SchemaName = $PnSchema; IsPrimaryName = $true; DisplayName = @{ LocalizedLabels = @(@{ Label = $PnDisp; LanguageCode = 1033 }) }; RequiredLevel = @{ Value = "ApplicationRequired"; CanBeChanged = $true }; MaxLength = $PnLen; FormatName = @{ Value = "Text" } }
    $body = @{ "@odata.type" = "Microsoft.Dynamics.CRM.EntityMetadata"; SchemaName = $S; LogicalName = $L; DisplayName = @{ LocalizedLabels = @(@{ Label = $Disp; LanguageCode = 1033 }) }; DisplayCollectionName = @{ LocalizedLabels = @(@{ Label = $DispP; LanguageCode = 1033 }) }; Description = @{ LocalizedLabels = @(@{ Label = $Desc; LanguageCode = 1033 }) }; OwnershipType = "UserOwned"; HasActivities = $false; HasNotes = $true; Attributes = @($primary) }
    Write-Host "  Creating $L..." -ForegroundColor White
    Invoke-Dv -Method POST -Path "EntityDefinitions" -Body $body | Out-Null
    Write-Host "    Created" -ForegroundColor Green
}

function Add-Col {
    param([string]$Table, [string]$Logical, [hashtable]$Body)
    if (Find-Column -Table $Table -Col $Logical) { Write-Host "    $Logical exists - skip" -ForegroundColor DarkYellow; return }
    Write-Host "    + $Logical" -ForegroundColor White
    Invoke-Dv -Method POST -Path "EntityDefinitions(LogicalName='$Table')/Attributes" -Body $Body | Out-Null
}

function Add-Lookup {
    param([string]$Child, [string]$Parent, [string]$ColSchema, [string]$ColDisp, [bool]$Req = $false)
    $logical = $ColSchema.ToLower()
    if (Find-Column -Table $Child -Col $logical) { Write-Host "    Lookup $logical exists - skip" -ForegroundColor DarkYellow; return }
    $rel = "${Child}_${logical}".ToLower(); if ($rel.Length -gt 100) { $rel = $rel.Substring(0, 100) }
    $body = @{ "@odata.type" = "Microsoft.Dynamics.CRM.OneToManyRelationshipMetadata"; SchemaName = $rel; ReferencedEntity = $Parent; ReferencingEntity = $Child; Lookup = @{ "@odata.type" = "Microsoft.Dynamics.CRM.LookupAttributeMetadata"; AttributeType = "Lookup"; AttributeTypeName = @{ Value = "LookupType" }; SchemaName = $ColSchema; DisplayName = @{ LocalizedLabels = @(@{ Label = $ColDisp; LanguageCode = 1033 }) }; RequiredLevel = @{ Value = ($(if($Req){"ApplicationRequired"}else{"None"})); CanBeChanged = $true } }; AssociatedMenuConfiguration = @{ Behavior = "UseCollectionName"; Group = "Details"; Order = 10000 }; CascadeConfiguration = @{ Assign = "NoCascade"; Delete = "RemoveLink"; Merge = "NoCascade"; Reparent = "NoCascade"; Share = "NoCascade"; Unshare = "NoCascade" } }
    Write-Host "    + Lookup $ColSchema -> $Parent" -ForegroundColor White
    Invoke-Dv -Method POST -Path "RelationshipDefinitions" -Body $body | Out-Null
}

# ============================================================================
# 1. rma_plantapprover
# ============================================================================
Write-Host "`n========== rma_plantapprover ==========" -ForegroundColor Cyan
Make-Table "rma_plantapprover" "rma_PlantApprover" "Plant Approver" "Plant Approvers" "Teams approval routing per plant." "rma_Name" "Approver Name"
Add-Col "rma_plantapprover" "rma_email"               (P-Text  "rma_Email" "Email" 200 $true "Email")
Add-Col "rma_plantapprover" "rma_teamsupn"            (P-Text  "rma_TeamsUPN" "Teams UPN" 200)
Add-Col "rma_plantapprover" "rma_assignmentmode"      (P-Picklist "rma_AssignmentMode" "Assignment Mode" @("Specific User","Role-Based","Manager Chain") $true)
Add-Col "rma_plantapprover" "rma_role"                (P-Text  "rma_Role" "Role" 100)
Add-Col "rma_plantapprover" "rma_notifywhen"          (P-Picklist "rma_NotifyWhen" "Notify When" @("All Claims","High Value Only","Manual Only") $true)
Add-Col "rma_plantapprover" "rma_highvaluethreshold"  (P-Money "rma_HighValueThreshold" "High Value Threshold")
Add-Col "rma_plantapprover" "rma_isactive"            (P-Bool  "rma_IsActive" "Is Active" $true $true)
Add-Lookup "rma_plantapprover" "rma_plant" "rma_Plant" "Plant" $true

# ============================================================================
# 2. rma_approvalhistory
# ============================================================================
Write-Host "`n========== rma_approvalhistory ==========" -ForegroundColor Cyan
Make-Table "rma_approvalhistory" "rma_ApprovalHistory" "Approval History" "Approval History" "Detailed audit trail for approval actions." "rma_Name" "Action Description"
Add-Col "rma_approvalhistory" "rma_action"           (P-Picklist "rma_Action" "Action" @("Approval Requested","Approved","Denied","Escalated") $true)
Add-Col "rma_approvalhistory" "rma_actionby"         (P-Text  "rma_ActionBy" "Action By" 200 $true)
Add-Col "rma_approvalhistory" "rma_actionbyupn"      (P-Text  "rma_ActionByUPN" "Action By UPN" 200)
Add-Col "rma_approvalhistory" "rma_actiondate"       (P-DT    "rma_ActionDate" "Action Date" $true)
Add-Col "rma_approvalhistory" "rma_previousstatus"   (P-Text  "rma_PreviousStatus" "Previous Status" 100)
Add-Col "rma_approvalhistory" "rma_newstatus"        (P-Text  "rma_NewStatus" "New Status" 100)
Add-Col "rma_approvalhistory" "rma_comments"         (P-Memo  "rma_Comments" "Comments")
Add-Col "rma_approvalhistory" "rma_viateams"         (P-Bool  "rma_ViaTeams" "Via Teams" $false)
Add-Lookup "rma_approvalhistory" "rma_claim" "rma_Claim" "RMA Claim" $true

# ============================================================================
# 3. rma_emailtemplate
# ============================================================================
Write-Host "`n========== rma_emailtemplate ==========" -ForegroundColor Cyan
Make-Table "rma_emailtemplate" "rma_EmailTemplate" "Email Template" "Email Templates" "Customer email templates." "rma_Name" "Template Name"
Add-Col "rma_emailtemplate" "rma_templatetype"       (P-Picklist "rma_TemplateType" "Template Type" @("Submission Confirmation","Status Update","Resolution","Information Request") $true)
Add-Col "rma_emailtemplate" "rma_subject"            (P-Text  "rma_Subject" "Subject" 500 $true)
Add-Col "rma_emailtemplate" "rma_body"               (P-Memo  "rma_Body" "Body" 10000 $true)
Add-Col "rma_emailtemplate" "rma_isautosend"         (P-Bool  "rma_IsAutoSend" "Auto Send" $false)
Add-Col "rma_emailtemplate" "rma_triggerstatus"      (P-Text  "rma_TriggerStatus" "Trigger Status" 100)
Add-Col "rma_emailtemplate" "rma_triggerresolution"  (P-Text  "rma_TriggerResolution" "Trigger Resolution" 100)
Add-Col "rma_emailtemplate" "rma_isactive"           (P-Bool  "rma_IsActive" "Is Active" $true $true)

# ============================================================================
# 4. rma_emailsignature
# ============================================================================
Write-Host "`n========== rma_emailsignature ==========" -ForegroundColor Cyan
Make-Table "rma_emailsignature" "rma_EmailSignature" "Email Signature" "Email Signatures" "Email signatures used in customer communications." "rma_Name" "Signature Name"
Add-Col "rma_emailsignature" "rma_signername"        (P-Text  "rma_SignerName" "Signer Name" 200 $true)
Add-Col "rma_emailsignature" "rma_title"             (P-Text  "rma_Title" "Title" 200)
Add-Col "rma_emailsignature" "rma_phone"             (P-Text  "rma_Phone" "Phone" 50)
Add-Col "rma_emailsignature" "rma_email"             (P-Text  "rma_Email" "Email" 200 $false "Email")
Add-Col "rma_emailsignature" "rma_imageurl"          (P-Text  "rma_ImageUrl" "Image URL" 500)
Add-Col "rma_emailsignature" "rma_isdefault"         (P-Bool  "rma_IsDefault" "Is Default" $false)

# ============================================================================
# 5. rma_emaillog
# ============================================================================
Write-Host "`n========== rma_emaillog ==========" -ForegroundColor Cyan
Make-Table "rma_emaillog" "rma_EmailLog" "Email Log" "Email Logs" "Sent email tracking." "rma_Subject" "Subject" 500
Add-Col "rma_emaillog" "rma_recipient"               (P-Text  "rma_Recipient" "Recipient" 200 $true "Email")
Add-Col "rma_emaillog" "rma_body"                    (P-Memo  "rma_Body" "Body" 10000)
Add-Col "rma_emaillog" "rma_templateused"            (P-Text  "rma_TemplateUsed" "Template Used" 200)
Add-Col "rma_emaillog" "rma_sentdate"                (P-DT    "rma_SentDate" "Sent Date" $true)
Add-Col "rma_emaillog" "rma_sentby"                  (P-Text  "rma_SentBy" "Sent By" 200)
Add-Col "rma_emaillog" "rma_messageid"               (P-Text  "rma_MessageId" "Message ID" 200)
Add-Lookup "rma_emaillog" "rma_claim" "rma_Claim" "RMA Claim" $false

# ============================================================================
# Add all 5 to RMAReturnsMonitor solution
# ============================================================================
Write-Host "`n========== Adding tables to solution ==========" -ForegroundColor Cyan
$names = @("rma_plantapprover","rma_approvalhistory","rma_emailtemplate","rma_emailsignature","rma_emaillog")
foreach ($n in $names) {
    $t = Find-Table -LogicalName $n
    if (-not $t) { Write-Host "  NOT FOUND: $n - skipping" -ForegroundColor Red; continue }
    $body = @{ ComponentId = $t.MetadataId; ComponentType = 1; SolutionUniqueName = $solutionName; AddRequiredComponents = $true; DoNotIncludeSubcomponents = $false }
    try {
        Invoke-Dv -Method POST -Path "AddSolutionComponent" -Body $body -TimeoutSec 30 | Out-Null
        Write-Host "  Added $n" -ForegroundColor Green
    } catch {
        Write-Host "  $($n): $_" -ForegroundColor DarkYellow
    }
}

Write-Host "`n========== DONE ==========" -ForegroundColor Cyan
Write-Host "Re-export the solution to get a v1.0.0.3 .zip with all 10 tables."
