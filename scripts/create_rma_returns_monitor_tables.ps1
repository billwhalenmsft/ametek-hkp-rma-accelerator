<#
.SYNOPSIS
    Builds the 5 custom Dataverse tables for the RMA Returns Monitor app.
    Creates publisher 'RMAPublisher' with prefix 'rma'.
    Adds tables to existing 'RMAReturnsMonitor' solution.

.NOTES
    Designed to be idempotent - safe to re-run.
    Order: plant -> routingrule (lookup) -> claim (lookup) -> claimnote (lookup) -> approvalrecord (lookup)
#>

$ErrorActionPreference = "Stop"
$orgUrl = "https://org6feab6b5.crm.dynamics.com"
$token = (az account get-access-token --resource $orgUrl --query accessToken -o tsv)
$hdr = @{
    Authorization      = "Bearer $token"
    Accept             = "application/json"
    "Content-Type"     = "application/json; charset=utf-8"
    "OData-Version"    = "4.0"
    "OData-MaxVersion" = "4.0"
    "MSCRM.SolutionUniqueName" = "RMAReturnsMonitor"
}

function Invoke-Dv {
    param([string]$Method, [string]$Path, $Body = $null, [hashtable]$ExtraHeaders = @{})
    $h = $hdr.Clone()
    foreach ($k in $ExtraHeaders.Keys) { $h[$k] = $ExtraHeaders[$k] }
    $url = "$orgUrl/api/data/v9.2/$Path"
    $params = @{
        Uri = $url
        Method = $Method
        Headers = $h
    }
    if ($Body) {
        $params.Body = ($Body | ConvertTo-Json -Depth 20 -Compress)
    }
    try {
        return Invoke-RestMethod @params -ErrorAction Stop
    }
    catch {
        $errorMsg = $_.Exception.Message
        if ($_.ErrorDetails.Message) {
            $errorMsg = $_.ErrorDetails.Message
        }
        throw "API call failed [$Method $Path]: $errorMsg"
    }
}

function Find-Publisher {
    param([string]$Prefix)
    $r = Invoke-Dv -Method GET -Path "publishers?`$filter=customizationprefix eq '$Prefix'&`$select=publisherid,uniquename,customizationprefix"
    if ($r.value.Count -gt 0) { return $r.value[0] }
    return $null
}

function Find-Table {
    param([string]$LogicalName)
    try {
        $r = Invoke-Dv -Method GET -Path "EntityDefinitions(LogicalName='$LogicalName')?`$select=LogicalName,SchemaName,MetadataId"
        return $r
    } catch {
        return $null
    }
}

function Find-Column {
    param([string]$TableLogicalName, [string]$ColumnLogicalName)
    try {
        $r = Invoke-Dv -Method GET -Path "EntityDefinitions(LogicalName='$TableLogicalName')/Attributes(LogicalName='$ColumnLogicalName')?`$select=LogicalName"
        return $r
    } catch {
        return $null
    }
}

function Find-Solution {
    param([string]$UniqueName)
    $r = Invoke-Dv -Method GET -Path "solutions?`$filter=uniquename eq '$UniqueName'&`$select=solutionid,uniquename,_publisherid_value"
    if ($r.value.Count -gt 0) { return $r.value[0] }
    return $null
}

# ============================================================================
# STEP 1: Publisher
# ============================================================================
Write-Host "`n========== STEP 1: Publisher ==========" -ForegroundColor Cyan
$prefix = "rma"
$pub = Find-Publisher -Prefix $prefix
if ($pub) {
    Write-Host "  Publisher with prefix '$prefix' already exists: $($pub.uniquename)" -ForegroundColor Yellow
}
else {
    $pubBody = @{
        uniquename                     = "RMAPublisher"
        friendlyname                   = "RMA Returns Monitor Publisher"
        description                    = "Publisher for the self-contained RMA Returns Monitor app and tables"
        customizationprefix            = $prefix
        customizationoptionvalueprefix = 50000
    }
    $pubResult = Invoke-Dv -Method POST -Path "publishers" -Body $pubBody -ExtraHeaders @{ Prefer = "return=representation" }
    Write-Host "  Created publisher: $($pubResult.uniquename)" -ForegroundColor Green
    $pub = $pubResult
}

# Look up the existing solution and re-publish the prefix for new components
$sol = Find-Solution -UniqueName "RMAReturnsMonitor"
if (-not $sol) {
    throw "Solution 'RMAReturnsMonitor' not found in this environment. Create it first."
}
Write-Host "  Found target solution: RMAReturnsMonitor (id: $($sol.solutionid))" -ForegroundColor Green

# ============================================================================
# STEP 2: Choice columns are global option sets in Dataverse - we'll create
# them as LOCAL picklists per table to keep things simple.
# Helper to build a local picklist column body
# ============================================================================
function New-PicklistAttribute {
    param([string]$LogicalName, [string]$DisplayName, [string]$Description, [object[]]$Options, [bool]$Required)
    $optionList = @()
    $val = 100000000
    foreach ($o in $Options) {
        $optionList += @{
            "@odata.type" = "Microsoft.Dynamics.CRM.OptionMetadata"
            Value = $val
            Label = @{
                LocalizedLabels = @(@{ Label = $o; LanguageCode = 1033 })
            }
        }
        $val++
    }
    $reqLevel = if ($Required) { "ApplicationRequired" } else { "None" }
    return @{
        "@odata.type"     = "Microsoft.Dynamics.CRM.PicklistAttributeMetadata"
        AttributeType     = "Picklist"
        AttributeTypeName = @{ Value = "PicklistType" }
        SchemaName        = $LogicalName
        DisplayName       = @{ LocalizedLabels = @(@{ Label = $DisplayName; LanguageCode = 1033 }) }
        Description       = @{ LocalizedLabels = @(@{ Label = $Description; LanguageCode = 1033 }) }
        RequiredLevel     = @{ Value = $reqLevel; CanBeChanged = $true }
        OptionSet         = @{
            "@odata.type" = "Microsoft.Dynamics.CRM.OptionSetMetadata"
            OptionSetType = "Picklist"
            IsGlobal      = $false
            Options       = $optionList
        }
    }
}

function New-StringAttribute {
    param([string]$LogicalName, [string]$DisplayName, [int]$MaxLength = 100, [bool]$Required = $false, [string]$Format = "Text")
    $reqLevel = if ($Required) { "ApplicationRequired" } else { "None" }
    return @{
        "@odata.type"     = "Microsoft.Dynamics.CRM.StringAttributeMetadata"
        AttributeType     = "String"
        AttributeTypeName = @{ Value = "StringType" }
        SchemaName        = $LogicalName
        DisplayName       = @{ LocalizedLabels = @(@{ Label = $DisplayName; LanguageCode = 1033 }) }
        RequiredLevel     = @{ Value = $reqLevel; CanBeChanged = $true }
        MaxLength         = $MaxLength
        FormatName        = @{ Value = $Format }
    }
}

function New-MemoAttribute {
    param([string]$LogicalName, [string]$DisplayName, [bool]$Required = $false)
    $reqLevel = if ($Required) { "ApplicationRequired" } else { "None" }
    return @{
        "@odata.type"     = "Microsoft.Dynamics.CRM.MemoAttributeMetadata"
        AttributeType     = "Memo"
        AttributeTypeName = @{ Value = "MemoType" }
        SchemaName        = $LogicalName
        DisplayName       = @{ LocalizedLabels = @(@{ Label = $DisplayName; LanguageCode = 1033 }) }
        RequiredLevel     = @{ Value = $reqLevel; CanBeChanged = $true }
        MaxLength         = 4000
        Format            = "TextArea"
    }
}

function New-IntegerAttribute {
    param([string]$LogicalName, [string]$DisplayName, [bool]$Required = $false)
    $reqLevel = if ($Required) { "ApplicationRequired" } else { "None" }
    return @{
        "@odata.type"     = "Microsoft.Dynamics.CRM.IntegerAttributeMetadata"
        AttributeType     = "Integer"
        AttributeTypeName = @{ Value = "IntegerType" }
        SchemaName        = $LogicalName
        DisplayName       = @{ LocalizedLabels = @(@{ Label = $DisplayName; LanguageCode = 1033 }) }
        RequiredLevel     = @{ Value = $reqLevel; CanBeChanged = $true }
    }
}

function New-MoneyAttribute {
    param([string]$LogicalName, [string]$DisplayName, [bool]$Required = $false)
    $reqLevel = if ($Required) { "ApplicationRequired" } else { "None" }
    return @{
        "@odata.type"     = "Microsoft.Dynamics.CRM.MoneyAttributeMetadata"
        AttributeType     = "Money"
        AttributeTypeName = @{ Value = "MoneyType" }
        SchemaName        = $LogicalName
        DisplayName       = @{ LocalizedLabels = @(@{ Label = $DisplayName; LanguageCode = 1033 }) }
        RequiredLevel     = @{ Value = $reqLevel; CanBeChanged = $true }
        PrecisionSource   = 2
    }
}

function New-DateTimeAttribute {
    param([string]$LogicalName, [string]$DisplayName, [bool]$Required = $false)
    $reqLevel = if ($Required) { "ApplicationRequired" } else { "None" }
    return @{
        "@odata.type"     = "Microsoft.Dynamics.CRM.DateTimeAttributeMetadata"
        AttributeType     = "DateTime"
        AttributeTypeName = @{ Value = "DateTimeType" }
        SchemaName        = $LogicalName
        DisplayName       = @{ LocalizedLabels = @(@{ Label = $DisplayName; LanguageCode = 1033 }) }
        RequiredLevel     = @{ Value = $reqLevel; CanBeChanged = $true }
        Format            = "DateAndTime"
        DateTimeBehavior  = @{ Value = "UserLocal" }
    }
}

function New-BooleanAttribute {
    param([string]$LogicalName, [string]$DisplayName, [bool]$Required = $false)
    $reqLevel = if ($Required) { "ApplicationRequired" } else { "None" }
    return @{
        "@odata.type"     = "Microsoft.Dynamics.CRM.BooleanAttributeMetadata"
        AttributeType     = "Boolean"
        AttributeTypeName = @{ Value = "BooleanType" }
        SchemaName        = $LogicalName
        DisplayName       = @{ LocalizedLabels = @(@{ Label = $DisplayName; LanguageCode = 1033 }) }
        RequiredLevel     = @{ Value = $reqLevel; CanBeChanged = $true }
        DefaultValue      = $false
        OptionSet         = @{
            TrueOption  = @{ Value = 1; Label = @{ LocalizedLabels = @(@{ Label = "Yes"; LanguageCode = 1033 }) } }
            FalseOption = @{ Value = 0; Label = @{ LocalizedLabels = @(@{ Label = "No"; LanguageCode = 1033 }) } }
        }
    }
}

function Create-Table {
    param(
        [string]$LogicalName,
        [string]$SchemaName,
        [string]$DisplayName,
        [string]$DisplayCollectionName,
        [string]$Description,
        [string]$PrimaryNameColumnSchema,
        [string]$PrimaryNameDisplay,
        [int]$PrimaryNameMaxLength = 200
    )
    $existing = Find-Table -LogicalName $LogicalName
    if ($existing) {
        Write-Host "  Table $LogicalName already exists - skipping create" -ForegroundColor Yellow
        return $existing
    }

    $primaryNameAttr = @{
        "@odata.type"     = "Microsoft.Dynamics.CRM.StringAttributeMetadata"
        AttributeType     = "String"
        AttributeTypeName = @{ Value = "StringType" }
        SchemaName        = $PrimaryNameColumnSchema
        IsPrimaryName     = $true
        DisplayName       = @{ LocalizedLabels = @(@{ Label = $PrimaryNameDisplay; LanguageCode = 1033 }) }
        RequiredLevel     = @{ Value = "ApplicationRequired"; CanBeChanged = $true }
        MaxLength         = $PrimaryNameMaxLength
        FormatName        = @{ Value = "Text" }
    }

    $tableBody = @{
        "@odata.type"            = "Microsoft.Dynamics.CRM.EntityMetadata"
        SchemaName               = $SchemaName
        LogicalName              = $LogicalName
        DisplayName              = @{ LocalizedLabels = @(@{ Label = $DisplayName; LanguageCode = 1033 }) }
        DisplayCollectionName    = @{ LocalizedLabels = @(@{ Label = $DisplayCollectionName; LanguageCode = 1033 }) }
        Description              = @{ LocalizedLabels = @(@{ Label = $Description; LanguageCode = 1033 }) }
        OwnershipType            = "UserOwned"
        HasActivities            = $false
        HasNotes                 = $true
        Attributes               = @($primaryNameAttr)
    }

    Write-Host "  Creating table $LogicalName..." -ForegroundColor White
    Invoke-Dv -Method POST -Path "EntityDefinitions" -Body $tableBody | Out-Null
    Write-Host "    Created" -ForegroundColor Green
    return Find-Table -LogicalName $LogicalName
}

function Add-Column {
    param([string]$TableLogicalName, [string]$ColumnLogicalName, [hashtable]$AttributeBody)
    $existing = Find-Column -TableLogicalName $TableLogicalName -ColumnLogicalName $ColumnLogicalName
    if ($existing) {
        Write-Host "    Column $ColumnLogicalName already exists - skipping" -ForegroundColor DarkYellow
        return
    }
    Write-Host "    Adding column $ColumnLogicalName..." -ForegroundColor White
    Invoke-Dv -Method POST -Path "EntityDefinitions(LogicalName='$TableLogicalName')/Attributes" -Body $AttributeBody | Out-Null
    Write-Host "      Added" -ForegroundColor Green
}

function Add-Lookup {
    param(
        [string]$TableSchema,           # ChildEntity (the table the lookup is ON)
        [string]$ColumnSchemaName,       # The lookup column SchemaName
        [string]$ColumnDisplay,
        [string]$ReferencedEntitySchema, # ParentEntity
        [bool]$Required = $false
    )
    $logicalName = $ColumnSchemaName.ToLower()
    $tableLogical = $TableSchema.ToLower()
    $existing = Find-Column -TableLogicalName $tableLogical -ColumnLogicalName $logicalName
    if ($existing) {
        Write-Host "    Lookup $logicalName already exists - skipping" -ForegroundColor DarkYellow
        return
    }
    $reqLevel = if ($Required) { "ApplicationRequired" } else { "None" }
    $relName = "${tableLogical}_${logicalName}".ToLower()
    if ($relName.Length -gt 100) { $relName = $relName.Substring(0, 100) }
    $body = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.OneToManyRelationshipMetadata"
        SchemaName    = $relName
        ReferencedEntity   = $ReferencedEntitySchema.ToLower()
        ReferencingEntity  = $tableLogical
        Lookup        = @{
            "@odata.type"      = "Microsoft.Dynamics.CRM.LookupAttributeMetadata"
            AttributeType      = "Lookup"
            AttributeTypeName  = @{ Value = "LookupType" }
            SchemaName         = $ColumnSchemaName
            DisplayName        = @{ LocalizedLabels = @(@{ Label = $ColumnDisplay; LanguageCode = 1033 }) }
            RequiredLevel      = @{ Value = $reqLevel; CanBeChanged = $true }
        }
        AssociatedMenuConfiguration = @{
            Behavior = "UseCollectionName"
            Group    = "Details"
            Order    = 10000
        }
        CascadeConfiguration = @{
            Assign   = "NoCascade"
            Delete   = "RemoveLink"
            Merge    = "NoCascade"
            Reparent = "NoCascade"
            Share    = "NoCascade"
            Unshare  = "NoCascade"
        }
    }
    Write-Host "    Adding lookup $ColumnSchemaName -> $ReferencedEntitySchema..." -ForegroundColor White
    Invoke-Dv -Method POST -Path "RelationshipDefinitions" -Body $body | Out-Null
    Write-Host "      Added" -ForegroundColor Green
}

# ============================================================================
# STEP 2: rma_plant
# ============================================================================
Write-Host "`n========== STEP 2: rma_plant ==========" -ForegroundColor Cyan
Create-Table `
    -LogicalName "rma_plant" `
    -SchemaName  "rma_Plant" `
    -DisplayName "Plant" `
    -DisplayCollectionName "Plants" `
    -Description "Manufacturing locations that process RMAs." `
    -PrimaryNameColumnSchema "rma_Name" `
    -PrimaryNameDisplay "Name" `
    -PrimaryNameMaxLength 100 | Out-Null

Add-Column -TableLogicalName "rma_plant" -ColumnLogicalName "rma_region" `
    -AttributeBody (New-PicklistAttribute -LogicalName "rma_Region" -DisplayName "Region" -Description "Plant region" `
        -Options @("North America", "Latin America", "Asia Pacific") -Required $true)

Add-Column -TableLogicalName "rma_plant" -ColumnLogicalName "rma_partprefixes" `
    -AttributeBody (New-StringAttribute -LogicalName "rma_PartPrefixes" -DisplayName "Part Prefixes" -MaxLength 200)

Add-Column -TableLogicalName "rma_plant" -ColumnLogicalName "rma_productlines" `
    -AttributeBody (New-StringAttribute -LogicalName "rma_ProductLines" -DisplayName "Product Lines" -MaxLength 500)

Add-Column -TableLogicalName "rma_plant" -ColumnLogicalName "rma_autocreditthreshold" `
    -AttributeBody (New-MoneyAttribute -LogicalName "rma_AutoCreditThreshold" -DisplayName "Auto Credit Threshold" -Required $true)

# ============================================================================
# STEP 3: rma_routingrule
# ============================================================================
Write-Host "`n========== STEP 3: rma_routingrule ==========" -ForegroundColor Cyan
Create-Table `
    -LogicalName "rma_routingrule" `
    -SchemaName  "rma_RoutingRule" `
    -DisplayName "Routing Rule" `
    -DisplayCollectionName "Routing Rules" `
    -Description "Configurable plant assignment logic." `
    -PrimaryNameColumnSchema "rma_Name" `
    -PrimaryNameDisplay "Rule Name" `
    -PrimaryNameMaxLength 100 | Out-Null

Add-Column -TableLogicalName "rma_routingrule" -ColumnLogicalName "rma_ruletype" `
    -AttributeBody (New-PicklistAttribute -LogicalName "rma_RuleType" -DisplayName "Rule Type" -Description "Type of routing rule" `
        -Options @("Part Prefix", "Customer Region", "Product Line") -Required $true)

Add-Column -TableLogicalName "rma_routingrule" -ColumnLogicalName "rma_matchvalue" `
    -AttributeBody (New-StringAttribute -LogicalName "rma_MatchValue" -DisplayName "Match Value" -MaxLength 200 -Required $true)

Add-Column -TableLogicalName "rma_routingrule" -ColumnLogicalName "rma_priority" `
    -AttributeBody (New-IntegerAttribute -LogicalName "rma_Priority" -DisplayName "Priority" -Required $true)

Add-Column -TableLogicalName "rma_routingrule" -ColumnLogicalName "rma_isactive" `
    -AttributeBody (New-BooleanAttribute -LogicalName "rma_IsActive" -DisplayName "Is Active" -Required $true)

Add-Lookup -TableSchema "rma_routingrule" -ColumnSchemaName "rma_AssignedPlant" `
    -ColumnDisplay "Assigned Plant" -ReferencedEntitySchema "rma_plant" -Required $true

# ============================================================================
# STEP 4: rma_claim
# ============================================================================
Write-Host "`n========== STEP 4: rma_claim ==========" -ForegroundColor Cyan
Create-Table `
    -LogicalName "rma_claim" `
    -SchemaName  "rma_Claim" `
    -DisplayName "RMA Claim" `
    -DisplayCollectionName "RMA Claims" `
    -Description "Core record tracking each return request." `
    -PrimaryNameColumnSchema "rma_ClaimNumber" `
    -PrimaryNameDisplay "Claim Number" `
    -PrimaryNameMaxLength 50 | Out-Null

Add-Column -TableLogicalName "rma_claim" -ColumnLogicalName "rma_customername" `
    -AttributeBody (New-StringAttribute -LogicalName "rma_CustomerName" -DisplayName "Customer Name" -MaxLength 200 -Required $true)

Add-Column -TableLogicalName "rma_claim" -ColumnLogicalName "rma_customeremail" `
    -AttributeBody (New-StringAttribute -LogicalName "rma_CustomerEmail" -DisplayName "Customer Email" -MaxLength 200 -Required $true -Format "Email")

Add-Column -TableLogicalName "rma_claim" -ColumnLogicalName "rma_customerregion" `
    -AttributeBody (New-PicklistAttribute -LogicalName "rma_CustomerRegion" -DisplayName "Customer Region" -Description "Customer region" `
        -Options @("Domestic", "Asia Pacific", "Europe", "Latin America") -Required $true)

Add-Column -TableLogicalName "rma_claim" -ColumnLogicalName "rma_partnumber" `
    -AttributeBody (New-StringAttribute -LogicalName "rma_PartNumber" -DisplayName "Part Number" -MaxLength 100 -Required $true)

Add-Column -TableLogicalName "rma_claim" -ColumnLogicalName "rma_quantity" `
    -AttributeBody (New-IntegerAttribute -LogicalName "rma_Quantity" -DisplayName "Quantity" -Required $true)

Add-Column -TableLogicalName "rma_claim" -ColumnLogicalName "rma_failuredescription" `
    -AttributeBody (New-MemoAttribute -LogicalName "rma_FailureDescription" -DisplayName "Failure Description" -Required $true)

Add-Column -TableLogicalName "rma_claim" -ColumnLogicalName "rma_failuremode" `
    -AttributeBody (New-PicklistAttribute -LogicalName "rma_FailureMode" -DisplayName "Failure Mode" -Description "Type of failure" `
        -Options @("Mechanical Failure", "Electrical Failure", "Cosmetic Damage", "Performance Issue", "DOA - Dead on Arrival", "Other") -Required $true)

Add-Column -TableLogicalName "rma_claim" -ColumnLogicalName "rma_creditamount" `
    -AttributeBody (New-MoneyAttribute -LogicalName "rma_CreditAmount" -DisplayName "Credit Amount")

Add-Column -TableLogicalName "rma_claim" -ColumnLogicalName "rma_warrantystatus" `
    -AttributeBody (New-PicklistAttribute -LogicalName "rma_WarrantyStatus" -DisplayName "Warranty Status" -Description "Warranty coverage status" `
        -Options @("In Warranty", "Out of Warranty", "Extended Warranty", "Unknown") -Required $true)

Add-Column -TableLogicalName "rma_claim" -ColumnLogicalName "rma_warrantyverifieddate" `
    -AttributeBody (New-DateTimeAttribute -LogicalName "rma_WarrantyVerifiedDate" -DisplayName "Warranty Verified Date")

Add-Column -TableLogicalName "rma_claim" -ColumnLogicalName "rma_status" `
    -AttributeBody (New-PicklistAttribute -LogicalName "rma_Status" -DisplayName "Status" -Description "Workflow status" `
        -Options @("New", "Triage", "Investigation", "Decision", "Closed") -Required $true)

Add-Column -TableLogicalName "rma_claim" -ColumnLogicalName "rma_resolution" `
    -AttributeBody (New-PicklistAttribute -LogicalName "rma_Resolution" -DisplayName "Resolution" -Description "Final resolution" `
        -Options @("Credit Issued", "Replacement Sent", "Repair Completed", "Claim Denied", "Pending") -Required $false)

Add-Column -TableLogicalName "rma_claim" -ColumnLogicalName "rma_sourceemailid" `
    -AttributeBody (New-StringAttribute -LogicalName "rma_SourceEmailId" -DisplayName "Source Email ID" -MaxLength 200)

Add-Column -TableLogicalName "rma_claim" -ColumnLogicalName "rma_createddate" `
    -AttributeBody (New-DateTimeAttribute -LogicalName "rma_CreatedDate" -DisplayName "Created Date" -Required $true)

Add-Column -TableLogicalName "rma_claim" -ColumnLogicalName "rma_closeddate" `
    -AttributeBody (New-DateTimeAttribute -LogicalName "rma_ClosedDate" -DisplayName "Closed Date")

Add-Lookup -TableSchema "rma_claim" -ColumnSchemaName "rma_AssignedPlant" `
    -ColumnDisplay "Assigned Plant" -ReferencedEntitySchema "rma_plant" -Required $false

# ============================================================================
# STEP 5: rma_claimnote
# ============================================================================
Write-Host "`n========== STEP 5: rma_claimnote ==========" -ForegroundColor Cyan
Create-Table `
    -LogicalName "rma_claimnote" `
    -SchemaName  "rma_ClaimNote" `
    -DisplayName "Claim Note" `
    -DisplayCollectionName "Claim Notes" `
    -Description "Activity log for investigation documentation." `
    -PrimaryNameColumnSchema "rma_NoteTitle" `
    -PrimaryNameDisplay "Note Title" `
    -PrimaryNameMaxLength 200 | Out-Null

Add-Column -TableLogicalName "rma_claimnote" -ColumnLogicalName "rma_notetext" `
    -AttributeBody (New-MemoAttribute -LogicalName "rma_NoteText" -DisplayName "Note Text" -Required $true)

Add-Column -TableLogicalName "rma_claimnote" -ColumnLogicalName "rma_notetype" `
    -AttributeBody (New-PicklistAttribute -LogicalName "rma_NoteType" -DisplayName "Note Type" -Description "Note category" `
        -Options @("Investigation", "Decision", "Customer Contact", "Internal", "Warranty Check") -Required $true)

Add-Column -TableLogicalName "rma_claimnote" -ColumnLogicalName "rma_createdby" `
    -AttributeBody (New-StringAttribute -LogicalName "rma_CreatedBy" -DisplayName "Created By" -MaxLength 200 -Required $true)

Add-Column -TableLogicalName "rma_claimnote" -ColumnLogicalName "rma_createddate" `
    -AttributeBody (New-DateTimeAttribute -LogicalName "rma_CreatedDate" -DisplayName "Created Date" -Required $true)

Add-Lookup -TableSchema "rma_claimnote" -ColumnSchemaName "rma_Claim" `
    -ColumnDisplay "RMA Claim" -ReferencedEntitySchema "rma_claim" -Required $true

# ============================================================================
# STEP 6: rma_approvalrecord
# ============================================================================
Write-Host "`n========== STEP 6: rma_approvalrecord ==========" -ForegroundColor Cyan
Create-Table `
    -LogicalName "rma_approvalrecord" `
    -SchemaName  "rma_ApprovalRecord" `
    -DisplayName "Approval Record" `
    -DisplayCollectionName "Approval Records" `
    -Description "Audit trail for credits exceeding thresholds." `
    -PrimaryNameColumnSchema "rma_Name" `
    -PrimaryNameDisplay "Approval Name" `
    -PrimaryNameMaxLength 200 | Out-Null

Add-Column -TableLogicalName "rma_approvalrecord" -ColumnLogicalName "rma_requestedamount" `
    -AttributeBody (New-MoneyAttribute -LogicalName "rma_RequestedAmount" -DisplayName "Requested Amount" -Required $true)

Add-Column -TableLogicalName "rma_approvalrecord" -ColumnLogicalName "rma_thresholdamount" `
    -AttributeBody (New-MoneyAttribute -LogicalName "rma_ThresholdAmount" -DisplayName "Threshold Amount" -Required $true)

Add-Column -TableLogicalName "rma_approvalrecord" -ColumnLogicalName "rma_approvalstatus" `
    -AttributeBody (New-PicklistAttribute -LogicalName "rma_ApprovalStatus" -DisplayName "Approval Status" -Description "Status of approval request" `
        -Options @("Pending", "Approved", "Denied") -Required $true)

Add-Column -TableLogicalName "rma_approvalrecord" -ColumnLogicalName "rma_approvername" `
    -AttributeBody (New-StringAttribute -LogicalName "rma_ApproverName" -DisplayName "Approver Name" -MaxLength 200)

Add-Column -TableLogicalName "rma_approvalrecord" -ColumnLogicalName "rma_approvaldate" `
    -AttributeBody (New-DateTimeAttribute -LogicalName "rma_ApprovalDate" -DisplayName "Approval Date")

Add-Column -TableLogicalName "rma_approvalrecord" -ColumnLogicalName "rma_approvalnotes" `
    -AttributeBody (New-MemoAttribute -LogicalName "rma_ApprovalNotes" -DisplayName "Approval Notes")

Add-Column -TableLogicalName "rma_approvalrecord" -ColumnLogicalName "rma_requestreason" `
    -AttributeBody (New-MemoAttribute -LogicalName "rma_RequestReason" -DisplayName "Request Reason" -Required $true)

Add-Lookup -TableSchema "rma_approvalrecord" -ColumnSchemaName "rma_Claim" `
    -ColumnDisplay "RMA Claim" -ReferencedEntitySchema "rma_claim" -Required $true

# ============================================================================
# STEP 7: Add tables to RMAReturnsMonitor solution
# ============================================================================
Write-Host "`n========== STEP 7: Add tables to RMAReturnsMonitor solution ==========" -ForegroundColor Cyan

$tableNames = @("rma_plant", "rma_routingrule", "rma_claim", "rma_claimnote", "rma_approvalrecord")
foreach ($t in $tableNames) {
    $tbl = Find-Table -LogicalName $t
    if (-not $tbl) {
        Write-Host "  Table $t NOT FOUND - skipping add to solution" -ForegroundColor Red
        continue
    }
    $body = @{
        ComponentId            = $tbl.MetadataId
        ComponentType          = 1   # Entity
        SolutionUniqueName     = "RMAReturnsMonitor"
        AddRequiredComponents  = $true
        DoNotIncludeSubcomponents = $false
    }
    try {
        Invoke-Dv -Method POST -Path "AddSolutionComponent" -Body $body | Out-Null
        Write-Host "  Added $t (and required components) to solution" -ForegroundColor Green
    } catch {
        Write-Host "  $t : $_" -ForegroundColor DarkYellow
    }
}

Write-Host "`n========== DONE ==========" -ForegroundColor Cyan
Write-Host ""
Write-Host "Next steps:"
Write-Host "  1. Open the app in Power Apps Studio"
Write-Host "  2. Tell Vibe (or in Studio):"
Write-Host "     - Add the new Dataverse tables: rma_plant, rma_routingrule, rma_claim, rma_claimnote, rma_approvalrecord"
Write-Host "     - Replace InMemory data sources with these"
Write-Host "  3. Save + Publish the app"
Write-Host "  4. Re-export the solution"
