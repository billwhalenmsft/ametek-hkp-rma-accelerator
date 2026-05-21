<#
.SYNOPSIS
    Seeds sample data into the RMA Returns Monitor Dataverse tables.

    Tables: rma_plant, rma_claim, rma_claimnote, rma_approvalrecord
    Org:    org6feab6b5.crm.dynamics.com (Mfg Gold Template)

.NOTES
    Idempotent: queries by primary name / claim number first, skips if found.

    Schema mismatches handled here:
      * rma_plant.rma_region picklist: adds 'Europe' option if missing.
        'Domestic' is mapped to 'North America' (Austin = Domestic to AMETEK).
      * rma_claimnote.rma_notetype: 'Communication' -> 'Customer Contact',
                                    'Approval' -> 'Decision'.
      * rma_claim.rma_failuredescription / rma_approvalrecord.rma_requestreason
        are REQUIRED but not in input. Synthesized from other fields.
      * rma_claim.rma_has_pending_response column does not exist. Skipped
        (flag would have applied to RMA-2026-0007).
#>

[CmdletBinding()]
param(
    [string]$OrgUrl = "https://org6feab6b5.crm.dynamics.com"
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

Write-Host "`n=== RMA Returns Monitor — Sample Data Seed ===" -ForegroundColor Cyan
Write-Host "Org: $OrgUrl`n" -ForegroundColor Gray

# ---------------------------------------------------------------------------
# Auth
# ---------------------------------------------------------------------------
$token = (az account get-access-token --resource $OrgUrl --query accessToken -o tsv)
if (-not $token) { throw "Failed to get Dataverse access token. Run 'az login' first." }

$hdr = @{
    Authorization      = "Bearer $token"
    Accept             = "application/json"
    "Content-Type"     = "application/json; charset=utf-8"
    "OData-Version"    = "4.0"
    "OData-MaxVersion" = "4.0"
    "MSCRM.SolutionUniqueName" = "RMAReturnsMonitor"
}

function Invoke-Dv {
    param(
        [string]$Method,
        [string]$Path,
        $Body = $null,
        [hashtable]$ExtraHeaders = @{},
        [switch]$ReturnHeaders,
        [int]$MaxRetries = 5
    )
    $h = $hdr.Clone()
    foreach ($k in $ExtraHeaders.Keys) { $h[$k] = $ExtraHeaders[$k] }
    $url = "$OrgUrl/api/data/v9.2/$Path"
    $params = @{
        Uri     = $url
        Method  = $Method
        Headers = $h
    }
    if ($Body) {
        $params.Body = ($Body | ConvertTo-Json -Depth 20 -Compress)
    }
    $attempt = 0
    while ($true) {
        $attempt++
        try {
            if ($ReturnHeaders) {
                return Invoke-WebRequest @params -ErrorAction Stop
            }
            return Invoke-RestMethod @params -ErrorAction Stop
        }
        catch {
            $msg = $_.Exception.Message
            if ($_.ErrorDetails.Message) { $msg = $_.ErrorDetails.Message }
            $retriable = ($msg -match '0x80072324' -or $msg -match 'Too many concurrent' -or $msg -match 'Throttle' -or $msg -match '429' -or $msg -match '503' -or $msg -match 'Service Unavailable')
            if ($retriable -and $attempt -lt $MaxRetries) {
                $waitSec = [Math]::Min(60, [Math]::Pow(2, $attempt) * 2)
                Write-Host "    [throttled] retry $attempt/$MaxRetries after ${waitSec}s..." -ForegroundColor DarkYellow
                Start-Sleep -Seconds $waitSec
                continue
            }
            throw "API call failed [$Method $Path]: $msg"
        }
    }
}

# ---------------------------------------------------------------------------
# Picklist option helpers
# ---------------------------------------------------------------------------
function Get-PicklistOptions {
    param([string]$EntityLogical, [string]$AttributeLogical)
    $resp = Invoke-Dv -Method GET -Path ("EntityDefinitions(LogicalName='{0}')/Attributes(LogicalName='{1}')/Microsoft.Dynamics.CRM.PicklistAttributeMetadata?`$select=LogicalName&`$expand=OptionSet" -f $EntityLogical, $AttributeLogical)
    $map = @{}
    foreach ($opt in $resp.OptionSet.Options) {
        $label = ($opt.Label.LocalizedLabels | Where-Object { $_.LanguageCode -eq 1033 } | Select-Object -First 1).Label
        if ($label) { $map[$label] = [int]$opt.Value }
    }
    return $map
}

function Add-PicklistOption {
    param([string]$EntityLogical, [string]$AttributeLogical, [string]$Label)
    $body = @{
        AttributeLogicalName = $AttributeLogical
        EntityLogicalName    = $EntityLogical
        Label = @{ LocalizedLabels = @(@{ Label = $Label; LanguageCode = 1033 }) }
    }
    Write-Host "  + Adding option '$Label' to $EntityLogical.$AttributeLogical" -ForegroundColor Yellow
    Invoke-Dv -Method POST -Path "InsertOptionValue" -Body $body | Out-Null
    # Re-fetch
    return (Get-PicklistOptions -EntityLogical $EntityLogical -AttributeLogical $AttributeLogical)
}

# ---------------------------------------------------------------------------
# Generic create-or-find
# ---------------------------------------------------------------------------
function Find-One {
    param([string]$EntitySet, [string]$Filter, [string]$IdField)
    $resp = Invoke-Dv -Method GET -Path ("{0}?`$filter={1}&`$select={2}" -f $EntitySet, $Filter, $IdField)
    if ($resp.value.Count -gt 0) { return $resp.value[0].$IdField }
    return $null
}

function Create-Record {
    param([string]$EntitySet, [hashtable]$Body)
    $resp = Invoke-Dv -Method POST -Path $EntitySet -Body $Body -ReturnHeaders
    $loc = $resp.Headers['OData-EntityId']
    if ($loc -is [array]) { $loc = $loc[0] }
    if ($loc -match '\(([0-9a-fA-F\-]{36})\)') { return $matches[1] }
    throw "No OData-EntityId returned for $EntitySet"
}

# ---------------------------------------------------------------------------
# Step 1: Ensure 'Europe' option exists on rma_plant.rma_region
# ---------------------------------------------------------------------------
Write-Host "Step 1: Verify rma_plant.rma_region picklist options..." -ForegroundColor Cyan
$regionMap = Get-PicklistOptions -EntityLogical "rma_plant" -AttributeLogical "rma_region"
Write-Host ("  Existing options: {0}" -f (($regionMap.Keys | Sort-Object) -join ", ")) -ForegroundColor Gray
if (-not $regionMap.ContainsKey("Europe")) {
    $regionMap = Add-PicklistOption -EntityLogical "rma_plant" -AttributeLogical "rma_region" -Label "Europe"
}

# Picklists on rma_claim
Write-Host "`nStep 2: Load rma_claim picklist option maps..." -ForegroundColor Cyan
$claimRegionMap     = Get-PicklistOptions -EntityLogical "rma_claim" -AttributeLogical "rma_customerregion"
$claimFailureMap    = Get-PicklistOptions -EntityLogical "rma_claim" -AttributeLogical "rma_failuremode"
$claimWarrantyMap   = Get-PicklistOptions -EntityLogical "rma_claim" -AttributeLogical "rma_warrantystatus"
$claimStatusMap     = Get-PicklistOptions -EntityLogical "rma_claim" -AttributeLogical "rma_status"
$claimResolutionMap = Get-PicklistOptions -EntityLogical "rma_claim" -AttributeLogical "rma_resolution"
$noteTypeMap        = Get-PicklistOptions -EntityLogical "rma_claimnote" -AttributeLogical "rma_notetype"
$approvalStatusMap  = Get-PicklistOptions -EntityLogical "rma_approvalrecord" -AttributeLogical "rma_approvalstatus"

# Note type aliases (input label -> existing option)
$noteTypeAlias = @{
    "Communication" = "Customer Contact"
    "Approval"      = "Decision"
    "Investigation" = "Investigation"
    "Decision"      = "Decision"
    "Internal"      = "Internal"
    "Warranty Check"= "Warranty Check"
}

function Get-OptionValue {
    param([hashtable]$Map, [string]$Label, [string]$Field)
    if ([string]::IsNullOrEmpty($Label)) { return $null }
    if ($Map.ContainsKey($Label)) { return $Map[$Label] }
    throw "Option '$Label' not found for field '$Field'. Available: $(($Map.Keys | Sort-Object) -join ', ')"
}

# ---------------------------------------------------------------------------
# Step 3: Plants
# ---------------------------------------------------------------------------
Write-Host "`nStep 3: Seed rma_plant (4 records)..." -ForegroundColor Cyan
$plants = @(
    @{ Name="Austin Manufacturing";   Region="North America"; Prefixes="AUS-, TX-"; Lines="Power Tools, Hand Tools";              Threshold=500 },
    @{ Name="Guadalajara Assembly";   Region="Latin America"; Prefixes="GDL-, MX-"; Lines="Electronics, Sensors";                 Threshold=750 },
    @{ Name="Shanghai Operations";    Region="Asia Pacific";  Prefixes="SH-, CN-";  Lines="Motors, Actuators";                    Threshold=1000 },
    @{ Name="Munich Precision";       Region="Europe";        Prefixes="MUN-, DE-"; Lines="Precision Instruments, Calibration";   Threshold=1500 }
)

$plantIds = @{}
foreach ($p in $plants) {
    $existing = Find-One -EntitySet "rma_plants" -Filter "rma_name eq '$($p.Name -replace `"'`", `"''`")'" -IdField "rma_plantid"
    if ($existing) {
        Write-Host "  [skip] $($p.Name) exists ($existing)" -ForegroundColor DarkGray
        $plantIds[$p.Name] = $existing
        continue
    }
    $body = @{
        rma_name                  = $p.Name
        rma_region                = (Get-OptionValue -Map $regionMap -Label $p.Region -Field "rma_plant.rma_region")
        rma_partprefixes          = $p.Prefixes
        rma_productlines          = $p.Lines
        rma_autocreditthreshold   = $p.Threshold
    }
    $id = Create-Record -EntitySet "rma_plants" -Body $body
    $plantIds[$p.Name] = $id
    Write-Host ("  [create] {0,-26} {1}" -f $p.Name, $id) -ForegroundColor Green
}

# Map for "Domestic" -> Austin (per user's source data)
$plantByLabel = @{
    "Austin"        = $plantIds["Austin Manufacturing"]
    "Guadalajara"   = $plantIds["Guadalajara Assembly"]
    "Shanghai"      = $plantIds["Shanghai Operations"]
    "Munich"        = $plantIds["Munich Precision"]
}

# ---------------------------------------------------------------------------
# Step 4: Claims
# ---------------------------------------------------------------------------
Write-Host "`nStep 4: Seed rma_claim (12 records)..." -ForegroundColor Cyan
$claims = @(
    @{ N="RMA-2026-0001"; Cust="Acme Industrial";        Email="warranty@acmeindustrial.com";    Part="AUS-PWR-4500"; Qty=3;  Status="New";          FM="Mechanical Failure"; Warr="In Warranty";       Region="Domestic";      Plant="Austin";      Created="2026-05-01"; Closed=$null;        Credit=$null; Res=$null },
    @{ N="RMA-2026-0002"; Cust="TechCorp Solutions";     Email="returns@techcorp.io";            Part="GDL-SEN-2200"; Qty=10; Status="Triage";       FM="Electrical Failure"; Warr="In Warranty";       Region="Latin America"; Plant="Guadalajara"; Created="2026-04-28"; Closed=$null;        Credit=$null; Res=$null },
    @{ N="RMA-2026-0003"; Cust="Global Motors Ltd";      Email="claims@globalmotors.de";         Part="SH-MOT-8800";  Qty=2;  Status="Investigation";FM="Performance Issue";  Warr="Extended Warranty"; Region="Europe";        Plant="Shanghai";    Created="2026-04-25"; Closed=$null;        Credit=2400;  Res=$null },
    @{ N="RMA-2026-0004"; Cust="Pacific Automation";     Email="rma@pacificauto.com.au";         Part="MUN-CAL-1100"; Qty=1;  Status="Decision";     FM="Cosmetic Damage";    Warr="Out of Warranty";   Region="Asia Pacific";  Plant="Munich";      Created="2026-04-20"; Closed=$null;        Credit=850;   Res=$null },
    @{ N="RMA-2026-0005"; Cust="Midwest Manufacturing";  Email="warranty@midwestmfg.com";        Part="AUS-HND-3300"; Qty=5;  Status="Closed";       FM="Mechanical Failure"; Warr="In Warranty";       Region="Domestic";      Plant="Austin";      Created="2026-04-15"; Closed="2026-05-02"; Credit=1250;  Res="Credit Issued" },
    @{ N="RMA-2026-0006"; Cust="EuroTech Industries";    Email="support@eurotech.eu";            Part="MUN-PRE-7700"; Qty=1;  Status="Closed";       FM="DOA - Dead on Arrival"; Warr="In Warranty";    Region="Europe";        Plant="Munich";      Created="2026-04-10"; Closed="2026-04-28"; Credit=$null; Res="Replacement Sent" },
    @{ N="RMA-2026-0007"; Cust="SouthWest Electric";     Email="claims@swelectric.com";          Part="TX-PWR-5500";  Qty=8;  Status="New";          FM="Electrical Failure"; Warr="In Warranty";       Region="Domestic";      Plant="Austin";      Created="2026-05-05"; Closed=$null;        Credit=$null; Res=$null },
    @{ N="RMA-2026-0008"; Cust="Asia Pacific Tools";     Email="rma@aptools.sg";                 Part="SH-ACT-4400";  Qty=4;  Status="Triage";       FM="Performance Issue";  Warr="Unknown";           Region="Asia Pacific";  Plant="Shanghai";    Created="2026-05-03"; Closed=$null;        Credit=$null; Res=$null },
    @{ N="RMA-2026-0009"; Cust="Canadian Equipment Co";  Email="warranty@canequip.ca";           Part="AUS-PWR-4501"; Qty=2;  Status="Investigation";FM="Other";              Warr="In Warranty";       Region="Domestic";      Plant="Austin";      Created="2026-04-22"; Closed=$null;        Credit=680;   Res=$null },
    @{ N="RMA-2026-0010"; Cust="Mexico Industrial";      Email="reclamos@mexind.mx";             Part="MX-ELC-6600";  Qty=15; Status="Decision";     FM="Electrical Failure"; Warr="In Warranty";       Region="Latin America"; Plant="Guadalajara"; Created="2026-04-18"; Closed=$null;        Credit=3750;  Res=$null },
    @{ N="RMA-2026-0011"; Cust="Berlin Precision GmbH";  Email="reklamation@berlinprec.de";      Part="DE-CAL-1200";  Qty=1;  Status="Closed";       FM="Cosmetic Damage";    Warr="Out of Warranty";   Region="Europe";        Plant="Munich";      Created="2026-04-05"; Closed="2026-04-25"; Credit=$null; Res="Claim Denied" },
    @{ N="RMA-2026-0012"; Cust="Tokyo Robotics";         Email="returns@tokyorobo.jp";           Part="CN-MOT-8801";  Qty=6;  Status="New";          FM="Mechanical Failure"; Warr="Extended Warranty"; Region="Asia Pacific";  Plant="Shanghai";    Created="2026-05-07"; Closed=$null;        Credit=$null; Res=$null }
)

# Note: RMA-2026-0007 has a "has_pending_response=true" flag in source data,
# but rma_claim.rma_has_pending_response column does not exist. Skipped.
Write-Host "  [info] Skipping has_pending_response on RMA-2026-0007 (column does not exist)" -ForegroundColor DarkYellow

$claimIds = @{}
foreach ($c in $claims) {
    $existing = Find-One -EntitySet "rma_claims" -Filter "rma_claimnumber eq '$($c.N)'" -IdField "rma_claimid"
    if ($existing) {
        Write-Host "  [skip] $($c.N) exists ($existing)" -ForegroundColor DarkGray
        $claimIds[$c.N] = $existing
        continue
    }
    $plantId = $plantByLabel[$c.Plant]
    if (-not $plantId) { throw "No plant id found for label '$($c.Plant)' on claim $($c.N)" }

    $body = [ordered]@{
        rma_claimnumber                       = $c.N
        rma_customername                      = $c.Cust
        rma_customeremail                     = $c.Email
        rma_customerregion                    = (Get-OptionValue -Map $claimRegionMap   -Label $c.Region -Field "rma_customerregion")
        rma_partnumber                        = $c.Part
        rma_quantity                          = $c.Qty
        rma_failuredescription                = "Customer reports $($c.FM.ToLower()) on $($c.Part) (qty $($c.Qty)). See attached communication for details."
        rma_failuremode                       = (Get-OptionValue -Map $claimFailureMap  -Label $c.FM     -Field "rma_failuremode")
        rma_warrantystatus                    = (Get-OptionValue -Map $claimWarrantyMap -Label $c.Warr   -Field "rma_warrantystatus")
        rma_status                            = (Get-OptionValue -Map $claimStatusMap   -Label $c.Status -Field "rma_status")
        rma_createddate                       = ([DateTime]::Parse($c.Created)).ToUniversalTime().ToString("o")
        "rma_AssignedPlant@odata.bind"        = "/rma_plants($plantId)"
    }
    if ($null -ne $c.Credit) { $body.rma_creditamount = $c.Credit }
    if ($c.Closed)           { $body.rma_closeddate   = ([DateTime]::Parse($c.Closed)).ToUniversalTime().ToString("o") }
    if ($c.Res)              { $body.rma_resolution   = (Get-OptionValue -Map $claimResolutionMap -Label $c.Res -Field "rma_resolution") }

    $id = Create-Record -EntitySet "rma_claims" -Body $body
    $claimIds[$c.N] = $id
    Write-Host ("  [create] {0}  ({1})  -> {2}" -f $c.N, $c.Cust, $id) -ForegroundColor Green
}

# ---------------------------------------------------------------------------
# Step 5: Claim notes
# ---------------------------------------------------------------------------
Write-Host "`nStep 5: Seed rma_claimnote (6 records)..." -ForegroundColor Cyan
$notes = @(
    @{ Title="Initial inspection complete"; Type="Investigation"; By="Maria Santos";      Date="2026-04-27"; Claim="RMA-2026-0003" },
    @{ Title="Engineering report received"; Type="Investigation"; By="James Chen";        Date="2026-05-01"; Claim="RMA-2026-0003" },
    @{ Title="Credit approved";             Type="Approval";      By="Sarah Johnson";     Date="2026-05-01"; Claim="RMA-2026-0005" },
    @{ Title="Customer contact";            Type="Communication"; By="Mike Thompson";     Date="2026-04-24"; Claim="RMA-2026-0009" },
    @{ Title="High value review";           Type="Approval";      By="Carlos Rodriguez";  Date="2026-04-20"; Claim="RMA-2026-0010" },
    @{ Title="Warranty verification";       Type="Investigation"; By="Lisa Park";         Date="2026-04-22"; Claim="RMA-2026-0004" }
)

foreach ($n in $notes) {
    $titleEsc = $n.Title -replace "'", "''"
    $claimId = $claimIds[$n.Claim]
    if (-not $claimId) { throw "Claim $($n.Claim) not found for note '$($n.Title)'" }

    $existing = Find-One -EntitySet "rma_claimnotes" -Filter "rma_notetitle eq '$titleEsc' and _rma_claim_value eq $claimId" -IdField "rma_claimnoteid"
    if ($existing) {
        Write-Host "  [skip] $($n.Title) on $($n.Claim) exists" -ForegroundColor DarkGray
        continue
    }

    $mappedType = $noteTypeAlias[$n.Type]
    if (-not $mappedType) { $mappedType = $n.Type }

    $body = [ordered]@{
        rma_notetitle              = $n.Title
        rma_notetext               = "$($n.Title) — recorded by $($n.By) on $($n.Date)."
        rma_notetype               = (Get-OptionValue -Map $noteTypeMap -Label $mappedType -Field "rma_notetype")
        rma_createdby              = $n.By
        rma_createddate            = ([DateTime]::Parse($n.Date)).ToUniversalTime().ToString("o")
        "rma_Claim@odata.bind"     = "/rma_claims($claimId)"
    }
    $id = Create-Record -EntitySet "rma_claimnotes" -Body $body
    Write-Host ("  [create] {0,-32} -> {1}  (type: {2})" -f $n.Title, $n.Claim, $mappedType) -ForegroundColor Green
}

# ---------------------------------------------------------------------------
# Step 6: Approval records
# ---------------------------------------------------------------------------
Write-Host "`nStep 6: Seed rma_approvalrecord (3 records)..." -ForegroundColor Cyan
$approvals = @(
    @{ Name="High Value Credit Approval";    Req=3750; Thr=2500; Status="Pending";  Approver=$null;                Date=$null;        Claim="RMA-2026-0010" },
    @{ Name="Credit Approval Request";       Req=2400; Thr=1000; Status="Approved"; Approver="Regional Manager Kim"; Date="2026-05-02"; Claim="RMA-2026-0003" },
    @{ Name="Goodwill Exception Request";    Req=850;  Thr=500;  Status="Pending";  Approver=$null;                Date=$null;        Claim="RMA-2026-0004" }
)

foreach ($a in $approvals) {
    $nameEsc = $a.Name -replace "'", "''"
    $claimId = $claimIds[$a.Claim]
    if (-not $claimId) { throw "Claim $($a.Claim) not found for approval '$($a.Name)'" }

    $existing = Find-One -EntitySet "rma_approvalrecords" -Filter "rma_name eq '$nameEsc' and _rma_claim_value eq $claimId" -IdField "rma_approvalrecordid"
    if ($existing) {
        Write-Host "  [skip] $($a.Name) on $($a.Claim) exists" -ForegroundColor DarkGray
        continue
    }

    $body = [ordered]@{
        rma_name                   = $a.Name
        rma_requestedamount        = $a.Req
        rma_thresholdamount        = $a.Thr
        rma_approvalstatus         = (Get-OptionValue -Map $approvalStatusMap -Label $a.Status -Field "rma_approvalstatus")
        rma_requestreason          = "Requested credit `$$($a.Req) exceeds plant threshold `$$($a.Thr) — manual approval required."
        "rma_Claim@odata.bind"     = "/rma_claims($claimId)"
    }
    if ($a.Approver) { $body.rma_approvername = $a.Approver }
    if ($a.Date)     { $body.rma_approvaldate = ([DateTime]::Parse($a.Date)).ToUniversalTime().ToString("o") }

    $id = Create-Record -EntitySet "rma_approvalrecords" -Body $body
    Write-Host ("  [create] {0,-32} -> {1}  ({2}, requested `${3})" -f $a.Name, $a.Claim, $a.Status, $a.Req) -ForegroundColor Green
}

Write-Host "`n=== DONE ===" -ForegroundColor Cyan
Write-Host "Plants:    $($plantIds.Count)"
Write-Host "Claims:    $($claimIds.Count)"
Write-Host "Notes:     6 (or skipped if pre-existing)"
Write-Host "Approvals: 3 (or skipped if pre-existing)`n"
