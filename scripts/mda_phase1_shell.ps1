<#
.SYNOPSIS
    Phase 1 of Code App -> Model-Driven app migration.

    1. Extends rma_emaillog with 6 columns to support inbound emails.
    2. Creates Model-Driven app "RMA Operations" via appmodule + sitemap.
    3. Adds all 10 RMA tables + dashboard placeholder as sitemap nav.

.NOTES
    Idempotent. Re-run safely.
    Org: org6feab6b5 (Mfg Gold Template)
    Solution: RMAReturnsMonitor
#>

[CmdletBinding()]
param(
    [string]$OrgUrl = "https://org6feab6b5.crm.dynamics.com"
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

Write-Host "`n=== Phase 1: Extend emaillog + create MDA shell ===" -ForegroundColor Cyan

$token = (az account get-access-token --resource $OrgUrl --query accessToken -o tsv)
if (-not $token) { throw "No Dataverse token. az login first." }

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
    if ($Body) { $params.Body = ($Body | ConvertTo-Json -Depth 20 -Compress) }
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

function Find-Column {
    param([string]$Table, [string]$Column)
    try {
        return Invoke-Dv -Method GET -Path "EntityDefinitions(LogicalName='$Table')/Attributes(LogicalName='$Column')?`$select=LogicalName"
    } catch { return $null }
}

function Add-StringColumn {
    param([string]$Table, [string]$Schema, [string]$Display, [int]$MaxLength = 200, [string]$Format = "Text")
    $logical = $Schema.ToLower()
    if (Find-Column -Table $Table -Column $logical) {
        Write-Host "    [skip] $logical exists" -ForegroundColor DarkGray
        return
    }
    $body = @{
        "@odata.type"       = "Microsoft.Dynamics.CRM.StringAttributeMetadata"
        AttributeType       = "String"
        AttributeTypeName   = @{ Value = "StringType" }
        SchemaName          = $Schema
        DisplayName         = @{ LocalizedLabels = @(@{ Label = $Display; LanguageCode = 1033 }) }
        RequiredLevel       = @{ Value = "None"; CanBeChanged = $true }
        MaxLength           = $MaxLength
        FormatName          = @{ Value = $Format }
    }
    Invoke-Dv -Method POST -Path "EntityDefinitions(LogicalName='$Table')/Attributes" -Body $body | Out-Null
    Write-Host "    [add] $logical (String $MaxLength)" -ForegroundColor Green
}

function Add-BoolColumn {
    param([string]$Table, [string]$Schema, [string]$Display)
    $logical = $Schema.ToLower()
    if (Find-Column -Table $Table -Column $logical) {
        Write-Host "    [skip] $logical exists" -ForegroundColor DarkGray
        return
    }
    $body = @{
        "@odata.type"      = "Microsoft.Dynamics.CRM.BooleanAttributeMetadata"
        AttributeType      = "Boolean"
        AttributeTypeName  = @{ Value = "BooleanType" }
        SchemaName         = $Schema
        DisplayName        = @{ LocalizedLabels = @(@{ Label = $Display; LanguageCode = 1033 }) }
        RequiredLevel      = @{ Value = "None"; CanBeChanged = $true }
        DefaultValue       = $false
        OptionSet          = @{
            "@odata.type"  = "Microsoft.Dynamics.CRM.BooleanOptionSetMetadata"
            TrueOption     = @{ Value = 1; Label = @{ LocalizedLabels = @(@{ Label = "Yes"; LanguageCode = 1033 }) } }
            FalseOption    = @{ Value = 0; Label = @{ LocalizedLabels = @(@{ Label = "No"; LanguageCode = 1033 }) } }
        }
    }
    Invoke-Dv -Method POST -Path "EntityDefinitions(LogicalName='$Table')/Attributes" -Body $body | Out-Null
    Write-Host "    [add] $logical (Boolean)" -ForegroundColor Green
}

function Add-DateTimeColumn {
    param([string]$Table, [string]$Schema, [string]$Display)
    $logical = $Schema.ToLower()
    if (Find-Column -Table $Table -Column $logical) {
        Write-Host "    [skip] $logical exists" -ForegroundColor DarkGray
        return
    }
    $body = @{
        "@odata.type"      = "Microsoft.Dynamics.CRM.DateTimeAttributeMetadata"
        AttributeType      = "DateTime"
        AttributeTypeName  = @{ Value = "DateTimeType" }
        SchemaName         = $Schema
        DisplayName        = @{ LocalizedLabels = @(@{ Label = $Display; LanguageCode = 1033 }) }
        RequiredLevel      = @{ Value = "None"; CanBeChanged = $true }
        Format             = "DateAndTime"
        DateTimeBehavior   = @{ Value = "UserLocal" }
    }
    Invoke-Dv -Method POST -Path "EntityDefinitions(LogicalName='$Table')/Attributes" -Body $body | Out-Null
    Write-Host "    [add] $logical (DateTime)" -ForegroundColor Green
}

function Add-PicklistColumn {
    param([string]$Table, [string]$Schema, [string]$Display, [string[]]$Options)
    $logical = $Schema.ToLower()
    if (Find-Column -Table $Table -Column $logical) {
        Write-Host "    [skip] $logical exists" -ForegroundColor DarkGray
        return
    }
    $optionList = @()
    $val = 100000000
    foreach ($o in $Options) {
        $optionList += @{
            Value = $val
            Label = @{ LocalizedLabels = @(@{ Label = $o; LanguageCode = 1033 }) }
        }
        $val++
    }
    $body = @{
        "@odata.type"      = "Microsoft.Dynamics.CRM.PicklistAttributeMetadata"
        AttributeType      = "Picklist"
        AttributeTypeName  = @{ Value = "PicklistType" }
        SchemaName         = $Schema
        DisplayName        = @{ LocalizedLabels = @(@{ Label = $Display; LanguageCode = 1033 }) }
        RequiredLevel      = @{ Value = "None"; CanBeChanged = $true }
        OptionSet          = @{
            "@odata.type"  = "Microsoft.Dynamics.CRM.OptionSetMetadata"
            OptionSetType  = "Picklist"
            IsGlobal       = $false
            Options        = $optionList
        }
    }
    Invoke-Dv -Method POST -Path "EntityDefinitions(LogicalName='$Table')/Attributes" -Body $body | Out-Null
    Write-Host "    [add] $logical (Picklist: $($Options -join ', '))" -ForegroundColor Green
}

# ============================================================================
# STEP 1: Extend rma_emaillog
# ============================================================================
Write-Host "`nStep 1: Extend rma_emaillog with inbound-email columns" -ForegroundColor Cyan
Add-PicklistColumn -Table "rma_emaillog" -Schema "rma_Direction" -Display "Direction" -Options @("Inbound","Outbound")
Add-BoolColumn     -Table "rma_emaillog" -Schema "rma_IsProcessed" -Display "Is Processed"
Add-StringColumn   -Table "rma_emaillog" -Schema "rma_FromAddress" -Display "From Address" -MaxLength 200 -Format "Email"
Add-DateTimeColumn -Table "rma_emaillog" -Schema "rma_ReceivedDate" -Display "Received Date"
Add-StringColumn   -Table "rma_emaillog" -Schema "rma_BodyPreview" -Display "Body Preview" -MaxLength 500
Add-StringColumn   -Table "rma_emaillog" -Schema "rma_SourceSharePointId" -Display "Source SharePoint ID" -MaxLength 100

# ============================================================================
# STEP 2: Build sitemap XML
# ============================================================================
Write-Host "`nStep 2: Build sitemap XML" -ForegroundColor Cyan

$sitemapXml = @"
<SiteMap IntroducedVersion="9.0.0.0">
  <Area Id="rma_operations" ResourceId="Area_Service" ShowGroups="true" Title="RMA Operations">
    <Group Id="rma_group_work" Title="Work">
      <SubArea Id="rma_subarea_dashboards" Entity="" Title="Dashboards" ResourceId="" Icon="/_imgs/imagestrips/transparent_spacer.gif" Url="" GetStartedPagePath="">
        <Privilege Entity="dashboard" Privilege="Read" />
      </SubArea>
      <SubArea Id="rma_subarea_claims" Entity="rma_claim" Title="RMA Claims">
        <Privilege Entity="rma_claim" Privilege="Read" />
      </SubArea>
      <SubArea Id="rma_subarea_inbound" Entity="rma_emaillog" Title="Email Inbox">
        <Privilege Entity="rma_emaillog" Privilege="Read" />
      </SubArea>
      <SubArea Id="rma_subarea_approvals" Entity="rma_approvalrecord" Title="Approvals">
        <Privilege Entity="rma_approvalrecord" Privilege="Read" />
      </SubArea>
    </Group>
    <Group Id="rma_group_admin" Title="Configuration">
      <SubArea Id="rma_subarea_plants" Entity="rma_plant" Title="Plants">
        <Privilege Entity="rma_plant" Privilege="Read" />
      </SubArea>
      <SubArea Id="rma_subarea_routing" Entity="rma_routingrule" Title="Routing Rules">
        <Privilege Entity="rma_routingrule" Privilege="Read" />
      </SubArea>
      <SubArea Id="rma_subarea_approvers" Entity="rma_plantapprover" Title="Plant Approvers">
        <Privilege Entity="rma_plantapprover" Privilege="Read" />
      </SubArea>
      <SubArea Id="rma_subarea_templates" Entity="rma_emailtemplate" Title="Email Templates">
        <Privilege Entity="rma_emailtemplate" Privilege="Read" />
      </SubArea>
      <SubArea Id="rma_subarea_signatures" Entity="rma_emailsignature" Title="Email Signatures">
        <Privilege Entity="rma_emailsignature" Privilege="Read" />
      </SubArea>
    </Group>
    <Group Id="rma_group_audit" Title="Audit">
      <SubArea Id="rma_subarea_claimnotes" Entity="rma_claimnote" Title="Claim Notes">
        <Privilege Entity="rma_claimnote" Privilege="Read" />
      </SubArea>
      <SubArea Id="rma_subarea_approvalhistory" Entity="rma_approvalhistory" Title="Approval History">
        <Privilege Entity="rma_approvalhistory" Privilege="Read" />
      </SubArea>
    </Group>
  </Area>
</SiteMap>
"@

# ============================================================================
# STEP 3: Create / update appmodule + sitemap
# ============================================================================
Write-Host "`nStep 3: Create / update Model-Driven App" -ForegroundColor Cyan

$appUniqueName = "rma_operations_app"
$appDisplayName = "RMA Operations"

# Find or create the appmodule
$existing = Invoke-Dv -Method GET -Path "appmodules?`$filter=uniquename eq '$appUniqueName'&`$select=appmoduleid,name,uniquename"
$appModuleId = $null
if ($existing.value.Count -gt 0) {
    $appModuleId = $existing.value[0].appmoduleid
    Write-Host "  [exists] appmodule $appUniqueName -> $appModuleId" -ForegroundColor DarkGray
} else {
    $body = @{
        name                    = $appDisplayName
        uniquename              = $appUniqueName
        descriptor              = '{"appId":"' + [Guid]::NewGuid().ToString() + '"}'
        clienttype              = 4   # Unified Interface
        navigationtype          = 1
        publishedon             = (Get-Date).ToString("o")
        description             = "Model-Driven app for RMA claim operations across HKP plants"
    }
    $resp = Invoke-Dv -Method POST -Path "appmodules" -Body $body -ReturnHeaders
    $loc = $resp.Headers['OData-EntityId']
    if ($loc -is [array]) { $loc = $loc[0] }
    if ($loc -match '\(([0-9a-fA-F\-]{36})\)') { $appModuleId = $matches[1] }
    Write-Host "  [create] appmodule $appUniqueName -> $appModuleId" -ForegroundColor Green
}

# Find or create the sitemap, link to appmodule
$smName = "$appUniqueName" + "_sitemap"
$smExisting = Invoke-Dv -Method GET -Path "sitemaps?`$filter=sitemapnameunique eq '$smName'&`$select=sitemapid,sitemapname,sitemapnameunique"
$sitemapId = $null
if ($smExisting.value.Count -gt 0) {
    $sitemapId = $smExisting.value[0].sitemapid
    Write-Host "  [exists] sitemap $smName -> $sitemapId — updating XML" -ForegroundColor DarkGray
    Invoke-Dv -Method PATCH -Path "sitemaps($sitemapId)" -Body @{ sitemapxml = $sitemapXml } | Out-Null
} else {
    $body = @{
        sitemapname        = $appDisplayName
        sitemapnameunique  = $smName
        sitemapxml         = $sitemapXml
    }
    $resp = Invoke-Dv -Method POST -Path "sitemaps" -Body $body -ReturnHeaders
    $loc = $resp.Headers['OData-EntityId']
    if ($loc -is [array]) { $loc = $loc[0] }
    if ($loc -match '\(([0-9a-fA-F\-]{36})\)') { $sitemapId = $matches[1] }
    Write-Host "  [create] sitemap $smName -> $sitemapId" -ForegroundColor Green
}

# Link sitemap to appmodule via N:N relationship
try {
    Invoke-Dv -Method POST -Path "appmodules($appModuleId)/appmodulecomponents/`$ref" -Body @{
        "@odata.id" = "$OrgUrl/api/data/v9.2/sitemaps($sitemapId)"
    } | Out-Null
    Write-Host "  [link] sitemap linked to appmodule" -ForegroundColor Green
} catch {
    $m = $_.Exception.Message
    if ($_.ErrorDetails.Message) { $m = $_.ErrorDetails.Message }
    if ($m -match 'already exists' -or $m -match 'duplicate') {
        Write-Host "  [skip] sitemap already linked" -ForegroundColor DarkGray
    } else {
        Write-Host "  [warn] link sitemap: $m" -ForegroundColor DarkYellow
    }
}

# ============================================================================
# STEP 4: Add entity components to the appmodule
# ============================================================================
Write-Host "`nStep 4: Add 10 entities to the app" -ForegroundColor Cyan

$entities = @(
    "rma_claim", "rma_emaillog", "rma_approvalrecord",
    "rma_plant", "rma_routingrule", "rma_plantapprover",
    "rma_emailtemplate", "rma_emailsignature",
    "rma_claimnote", "rma_approvalhistory"
)

foreach ($e in $entities) {
    try {
        $em = Invoke-Dv -Method GET -Path "EntityDefinitions(LogicalName='$e')?`$select=ObjectTypeCode,LogicalName"
        # AddAppComponents action
        $body = @{
            Components = @(
                @{
                    "@odata.type"        = "Microsoft.Dynamics.CRM.appcomponent"
                    objectid             = $em.MetadataId
                    componenttype        = 1  # Entity
                }
            )
            AppId = $appModuleId
        }
        # Use AddAppComponents bound action
        Invoke-Dv -Method POST -Path "appmodules($appModuleId)/Microsoft.Dynamics.CRM.AddAppComponents" -Body @{
            Components = @(
                @{
                    "@odata.id" = "$OrgUrl/api/data/v9.2/EntityDefinitions($($em.MetadataId))"
                }
            )
        } | Out-Null
        Write-Host "  [add] $e" -ForegroundColor Green
    } catch {
        $m = $_.Exception.Message
        if ($_.ErrorDetails.Message) { $m = $_.ErrorDetails.Message }
        if ($m -match 'already exists|duplicate|already a component') {
            Write-Host "  [skip] $e already in app" -ForegroundColor DarkGray
        } else {
            Write-Host "  [warn] $e : $m" -ForegroundColor DarkYellow
        }
    }
}

# ============================================================================
# STEP 5: Publish + summary
# ============================================================================
Write-Host "`nStep 5: Publish appmodule + sitemap" -ForegroundColor Cyan
try {
    $publishXml = @"
<importexportxml>
  <entities />
  <nodes>
    <node id="appmodule" />
  </nodes>
  <appmodules>
    <appmodule id="$appModuleId" />
  </appmodules>
  <sitemaps>
    <sitemap id="$sitemapId" />
  </sitemaps>
</importexportxml>
"@
    Invoke-Dv -Method POST -Path "PublishXml" -Body @{ ParameterXml = $publishXml } | Out-Null
    Write-Host "  [publish] OK" -ForegroundColor Green
} catch {
    $m = $_.Exception.Message
    if ($_.ErrorDetails.Message) { $m = $_.ErrorDetails.Message }
    Write-Host "  [warn] publish: $m" -ForegroundColor DarkYellow
}

Write-Host "`n=== DONE ===" -ForegroundColor Cyan
Write-Host ""
Write-Host "Open the app:" -ForegroundColor Yellow
Write-Host "  https://make.powerapps.com/environments/2404ccaf-d7e5-e1ff-863a-3ecbe2f0f013/apps"
Write-Host "  Look for 'RMA Operations'. Click Play."
Write-Host ""
Write-Host "What you should see:" -ForegroundColor Yellow
Write-Host "  - Sitemap with 3 groups: Work / Configuration / Audit"
Write-Host "  - 10 entities accessible from nav"
Write-Host "  - Each entity shows its existing data (claims, plants, routing rules, etc.)"
Write-Host "  - Default forms/views from Dataverse (we customize next phase)"
Write-Host ""
Write-Host "If something looks broken, the appmodule id is:  $appModuleId" -ForegroundColor DarkGray
