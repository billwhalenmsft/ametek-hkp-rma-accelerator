<#
.SYNOPSIS
    Seeds routing rules, email templates, and email signature into the
    RMA Returns Monitor solution.

    Tables: rma_plant (creates 3 missing plants), rma_routingrule (4),
            rma_emailtemplate (2), rma_emailsignature (1)

    Org:    org6feab6b5.crm.dynamics.com (Mfg Gold Template)

.NOTES
    Idempotent: queries by primary name first, skips if found.

    Plants required by routing rules but missing from prior batch:
      * Detroit Assembly (region: North America)
      * Shanghai Electronics (region: Asia Pacific)
      * Sao Paulo Manufacturing (region: Latin America)
    These are created here with placeholder thresholds + part prefixes.

    Munich Precision already exists from prior seed.
#>

[CmdletBinding()]
param(
    [string]$OrgUrl = "https://org6feab6b5.crm.dynamics.com"
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

Write-Host "`n=== RMA Returns Monitor — Routing/Email Seed ===" -ForegroundColor Cyan
Write-Host "Org: $OrgUrl`n" -ForegroundColor Gray

$token = (az account get-access-token --resource $OrgUrl --query accessToken -o tsv)
if (-not $token) { throw "Failed to get Dataverse token. Run 'az login' first." }

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
    $params = @{ Uri = $url; Method = $Method; Headers = $h }
    if ($Body) { $params.Body = ($Body | ConvertTo-Json -Depth 20 -Compress) }
    $attempt = 0
    while ($true) {
        $attempt++
        try {
            if ($ReturnHeaders) { return Invoke-WebRequest @params -ErrorAction Stop }
            return Invoke-RestMethod @params -ErrorAction Stop
        }
        catch {
            $msg = $_.Exception.Message
            if ($_.ErrorDetails.Message) { $msg = $_.ErrorDetails.Message }
            $retriable = ($msg -match '0x80072324' -or $msg -match 'Too many concurrent' -or $msg -match 'Throttle' -or $msg -match '429' -or $msg -match '503')
            if ($retriable -and $attempt -lt $MaxRetries) {
                $wait = [Math]::Min(60, [Math]::Pow(2, $attempt) * 2)
                Write-Host "    [throttled] retry $attempt/$MaxRetries after ${wait}s..." -ForegroundColor DarkYellow
                Start-Sleep -Seconds $wait
                continue
            }
            throw "API call failed [$Method $Path]: $msg"
        }
    }
}

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

function Get-OptionValue {
    param([hashtable]$Map, [string]$Label, [string]$Field)
    if ([string]::IsNullOrEmpty($Label)) { return $null }
    if ($Map.ContainsKey($Label)) { return $Map[$Label] }
    throw "Option '$Label' not found for '$Field'. Available: $(($Map.Keys | Sort-Object) -join ', ')"
}

# ---------------------------------------------------------------------------
# Step 1: Resolve / create plants needed by routing rules
# ---------------------------------------------------------------------------
Write-Host "Step 1: Ensure plants referenced by routing rules exist..." -ForegroundColor Cyan
$plantRegionMap = Get-PicklistOptions -EntityLogical "rma_plant" -AttributeLogical "rma_region"

$requiredPlants = @(
    @{ Name="Detroit Assembly";        Region="North America"; Prefixes="DET-";        Lines="Assembly Components";     Threshold=600 },
    @{ Name="Munich Precision";        Region="Europe";        Prefixes="MUN-, DE-";   Lines="Precision Instruments";   Threshold=1500 },
    @{ Name="Shanghai Electronics";    Region="Asia Pacific";  Prefixes="SHG-";        Lines="Electronics";             Threshold=900 },
    @{ Name="Sao Paulo Manufacturing"; Region="Latin America"; Prefixes="SAO-";        Lines="General Manufacturing";   Threshold=700 }
)

$plantIds = @{}
foreach ($p in $requiredPlants) {
    $nameEsc = $p.Name -replace "'", "''"
    $existing = Find-One -EntitySet "rma_plants" -Filter "rma_name eq '$nameEsc'" -IdField "rma_plantid"
    if ($existing) {
        Write-Host "  [skip] $($p.Name) exists ($existing)" -ForegroundColor DarkGray
        $plantIds[$p.Name] = $existing
        continue
    }
    $body = @{
        rma_name                = $p.Name
        rma_region              = (Get-OptionValue -Map $plantRegionMap -Label $p.Region -Field "rma_plant.rma_region")
        rma_partprefixes        = $p.Prefixes
        rma_productlines        = $p.Lines
        rma_autocreditthreshold = $p.Threshold
    }
    $id = Create-Record -EntitySet "rma_plants" -Body $body
    $plantIds[$p.Name] = $id
    Write-Host ("  [create] {0,-26} {1}" -f $p.Name, $id) -ForegroundColor Green
}

# ---------------------------------------------------------------------------
# Step 2: Routing rules
# ---------------------------------------------------------------------------
Write-Host "`nStep 2: Seed rma_routingrule (4 records)..." -ForegroundColor Cyan
$ruleTypeMap = Get-PicklistOptions -EntityLogical "rma_routingrule" -AttributeLogical "rma_ruletype"

$rules = @(
    @{ Name="Route DET parts to Detroit";   Type="Part Prefix"; Match="DET-"; Plant="Detroit Assembly";        Priority=1; Active=$true },
    @{ Name="Route MUN parts to Munich";    Type="Part Prefix"; Match="MUN-"; Plant="Munich Precision";        Priority=2; Active=$true },
    @{ Name="Route SHG parts to Shanghai";  Type="Part Prefix"; Match="SHG-"; Plant="Shanghai Electronics";    Priority=3; Active=$true },
    @{ Name="Route SAO parts to Sao Paulo"; Type="Part Prefix"; Match="SAO-"; Plant="Sao Paulo Manufacturing"; Priority=4; Active=$true }
)

foreach ($r in $rules) {
    $nameEsc = $r.Name -replace "'", "''"
    $existing = Find-One -EntitySet "rma_routingrules" -Filter "rma_name eq '$nameEsc'" -IdField "rma_routingruleid"
    if ($existing) {
        Write-Host "  [skip] $($r.Name) exists" -ForegroundColor DarkGray
        continue
    }
    $plantId = $plantIds[$r.Plant]
    if (-not $plantId) { throw "Plant id not found for '$($r.Plant)'" }
    $body = [ordered]@{
        rma_name                       = $r.Name
        rma_ruletype                   = (Get-OptionValue -Map $ruleTypeMap -Label $r.Type -Field "rma_ruletype")
        rma_matchvalue                 = $r.Match
        rma_priority                   = $r.Priority
        rma_isactive                   = $r.Active
        "rma_AssignedPlant@odata.bind" = "/rma_plants($plantId)"
    }
    $id = Create-Record -EntitySet "rma_routingrules" -Body $body
    Write-Host ("  [create] {0,-36} -> {1}  (priority {2})" -f $r.Name, $r.Plant, $r.Priority) -ForegroundColor Green
}

# ---------------------------------------------------------------------------
# Step 3: Email templates
# ---------------------------------------------------------------------------
Write-Host "`nStep 3: Seed rma_emailtemplate (2 records)..." -ForegroundColor Cyan
$tmplTypeMap = Get-PicklistOptions -EntityLogical "rma_emailtemplate" -AttributeLogical "rma_templatetype"

$confirmBody = @"
Hello {customer_name},

Thank you for submitting RMA request {rma_number}. We have received your request and our team is reviewing it.

What happens next:
  - A specialist will be assigned within 1 business day.
  - You will receive a status update once your warranty is verified.
  - Expect a resolution decision within 5 business days.

If you have additional information to share, simply reply to this email.

Best regards,
RMA Support Team
"@

$updateBody = @"
Hello {customer_name},

We have an update on your RMA request {rma_number}.

Current status: {status}
{notes}

We will continue to keep you informed as we make progress.

If you have questions, simply reply to this email.

Best regards,
RMA Support Team
"@

$templates = @(
    @{ Name="RMA Submission Confirmation"; Type="Submission Confirmation"; Subject="Your RMA Request {rma_number} Has Been Received"; Auto=$true;  Active=$true; Body=$confirmBody },
    @{ Name="Status Update";               Type="Status Update";           Subject="Update on Your RMA {rma_number}";                Auto=$false; Active=$true; Body=$updateBody  }
)

foreach ($t in $templates) {
    $nameEsc = $t.Name -replace "'", "''"
    $existing = Find-One -EntitySet "rma_emailtemplates" -Filter "rma_name eq '$nameEsc'" -IdField "rma_emailtemplateid"
    if ($existing) {
        Write-Host "  [skip] $($t.Name) exists" -ForegroundColor DarkGray
        continue
    }
    $body = [ordered]@{
        rma_name         = $t.Name
        rma_templatetype = (Get-OptionValue -Map $tmplTypeMap -Label $t.Type -Field "rma_templatetype")
        rma_subject      = $t.Subject
        rma_body         = $t.Body
        rma_isautosend   = $t.Auto
        rma_isactive     = $t.Active
    }
    $id = Create-Record -EntitySet "rma_emailtemplates" -Body $body
    Write-Host ("  [create] {0,-32} (auto-send: {1})" -f $t.Name, $t.Auto) -ForegroundColor Green
}

# ---------------------------------------------------------------------------
# Step 4: Email signature
# ---------------------------------------------------------------------------
Write-Host "`nStep 4: Seed rma_emailsignature (1 record)..." -ForegroundColor Cyan

$sig = @{
    Name="RMA Team Standard"; SignerName="RMA Support Team"; Title="Returns Department";
    Phone="1-800-RMA-HELP"; Email="rma-support@company.com"; IsDefault=$true
}
$nameEsc = $sig.Name -replace "'", "''"
$existing = Find-One -EntitySet "rma_emailsignatures" -Filter "rma_name eq '$nameEsc'" -IdField "rma_emailsignatureid"
if ($existing) {
    Write-Host "  [skip] $($sig.Name) exists" -ForegroundColor DarkGray
} else {
    $body = [ordered]@{
        rma_name       = $sig.Name
        rma_signername = $sig.SignerName
        rma_title      = $sig.Title
        rma_phone      = $sig.Phone
        rma_email      = $sig.Email
        rma_isdefault  = $sig.IsDefault
    }
    $id = Create-Record -EntitySet "rma_emailsignatures" -Body $body
    Write-Host ("  [create] {0}  (default: {1})" -f $sig.Name, $sig.IsDefault) -ForegroundColor Green
}

Write-Host "`n=== DONE ===" -ForegroundColor Cyan
Write-Host "Plants:        $($plantIds.Count) (3 created if not pre-existing)"
Write-Host "Routing rules: 4"
Write-Host "Templates:     2"
Write-Host "Signature:     1`n"
