<#
.SYNOPSIS
    Replaces the placeholder plants in rma_plant with the real AMETEK HKP
    plants. Re-points all dependent records (rma_claim, rma_routingrule)
    to the closest geographic match before deactivating the old plants.

    New plants:
      Waterbury CT          (North America) — HKP HQ
      Milford NH            (North America) — motor assembly
      HLM - China           (Asia Pacific)
      Penang - Malaysia     (Asia Pacific)
      Reynosa - Mexico      (Latin America)

    Re-pointing map (old name -> new name):
      Austin Manufacturing       -> Milford NH
      Detroit Assembly           -> Waterbury CT
      Guadalajara Assembly       -> Reynosa - Mexico
      Sao Paulo Manufacturing    -> Reynosa - Mexico
      Shanghai Operations        -> HLM - China
      Shanghai Electronics       -> Penang - Malaysia
      Munich Precision           -> Waterbury CT  (no European plant; fall back to HQ)

.NOTES
    Idempotent. Old plants are DEACTIVATED (statecode=1), not deleted, so
    audit history is preserved and we can re-activate if needed.
#>

[CmdletBinding()]
param(
    [string]$OrgUrl = "https://org6feab6b5.crm.dynamics.com"
)

$ErrorActionPreference = "Stop"
$ProgressPreference    = "SilentlyContinue"

Write-Host "`n=== Replace placeholder plants with AMETEK HKP plants ===" -ForegroundColor Cyan
Write-Host "Org: $OrgUrl`n" -ForegroundColor Gray

$token = (az account get-access-token --resource $OrgUrl --query accessToken -o tsv)
if (-not $token) { throw "No Dataverse token." }

$hdr = @{
    Authorization      = "Bearer $token"
    Accept             = "application/json"
    "Content-Type"     = "application/json; charset=utf-8"
    "OData-Version"    = "4.0"
    "OData-MaxVersion" = "4.0"
    "MSCRM.SolutionUniqueName" = "RMAReturnsMonitor"
    "If-Match"         = "*"
}

function Invoke-Dv {
    param(
        [string]$Method,
        [string]$Path,
        $Body = $null,
        [switch]$ReturnHeaders,
        [int]$MaxRetries = 5
    )
    $url = "$OrgUrl/api/data/v9.2/$Path"
    # If-Match is only valid for PATCH/DELETE; strip it for GET/POST
    $h = $hdr.Clone()
    if ($Method -in @("GET","POST")) { $h.Remove("If-Match") | Out-Null }
    $params = @{ Uri = $url; Method = $Method; Headers = $h }
    if ($Body) { $params.Body = ($Body | ConvertTo-Json -Depth 10 -Compress) }
    $attempt = 0
    while ($true) {
        $attempt++
        try {
            if ($ReturnHeaders) { return Invoke-WebRequest @params -ErrorAction Stop }
            return Invoke-RestMethod @params -ErrorAction Stop
        } catch {
            $msg = $_.Exception.Message
            if ($_.ErrorDetails.Message) { $msg = $_.ErrorDetails.Message }
            $retriable = ($msg -match '0x80072324|Too many concurrent|Throttle|429|503')
            if ($retriable -and $attempt -lt $MaxRetries) {
                $wait = [Math]::Min(60, [Math]::Pow(2, $attempt) * 2)
                Write-Host "    [throttled] retry $attempt/$MaxRetries after ${wait}s..." -ForegroundColor DarkYellow
                Start-Sleep -Seconds $wait
                continue
            }
            throw "API [$Method $Path]: $msg"
        }
    }
}

function Get-PicklistOptions {
    param([string]$Entity, [string]$Attr)
    $r = Invoke-Dv -Method GET -Path ("EntityDefinitions(LogicalName='{0}')/Attributes(LogicalName='{1}')/Microsoft.Dynamics.CRM.PicklistAttributeMetadata?`$select=LogicalName&`$expand=OptionSet" -f $Entity, $Attr)
    $m = @{}
    foreach ($o in $r.OptionSet.Options) {
        $lbl = ($o.Label.LocalizedLabels | Where-Object { $_.LanguageCode -eq 1033 } | Select-Object -First 1).Label
        if ($lbl) { $m[$lbl] = [int]$o.Value }
    }
    return $m
}

function Find-Plant {
    param([string]$Name)
    $esc = $Name -replace "'", "''"
    $r = Invoke-Dv -Method GET -Path "rma_plants?`$filter=rma_name eq '$esc'&`$select=rma_plantid,rma_name,statecode"
    if ($r.value.Count -gt 0) { return $r.value[0] }
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
# Step 1: Create / find new plants
# ---------------------------------------------------------------------------
Write-Host "Step 1: Create 5 AMETEK HKP plants..." -ForegroundColor Cyan
$regionMap = Get-PicklistOptions -Entity "rma_plant" -Attr "rma_region"

$newPlants = @(
    @{ Name="Waterbury CT";       Region="North America"; Prefixes="WTB-, CT-";    Lines="Lead Screws, Precision Assembly";       Threshold=2500 },
    @{ Name="Milford NH";         Region="North America"; Prefixes="MIL-, NH-";    Lines="Stepper Motors, Linear Actuators";      Threshold=2500 },
    @{ Name="HLM - China";        Region="Asia Pacific";  Prefixes="HLM-, CN-";    Lines="High Volume Motors, Components";        Threshold=1000 },
    @{ Name="Penang - Malaysia";  Region="Asia Pacific";  Prefixes="PEN-, MY-";    Lines="Electronic Subassemblies, Sensors";     Threshold=1000 },
    @{ Name="Reynosa - Mexico";   Region="Latin America"; Prefixes="REY-, MX-";    Lines="Assembly, Cable Harnesses";             Threshold=750 }
)

$newPlantIds = @{}
foreach ($p in $newPlants) {
    $ex = Find-Plant -Name $p.Name
    if ($ex) {
        # If deactivated, reactivate
        if ($ex.statecode -ne 0) {
            Write-Host "  [reactivate] $($p.Name)" -ForegroundColor Yellow
            Invoke-Dv -Method PATCH -Path "rma_plants($($ex.rma_plantid))" -Body @{ statecode=0; statuscode=1 } | Out-Null
        } else {
            Write-Host "  [skip] $($p.Name) exists ($($ex.rma_plantid))" -ForegroundColor DarkGray
        }
        $newPlantIds[$p.Name] = $ex.rma_plantid
        continue
    }
    if (-not $regionMap.ContainsKey($p.Region)) { throw "Region '$($p.Region)' not in picklist. Options: $(($regionMap.Keys | Sort-Object) -join ', ')" }
    $body = @{
        rma_name                = $p.Name
        rma_region              = $regionMap[$p.Region]
        rma_partprefixes        = $p.Prefixes
        rma_productlines        = $p.Lines
        rma_autocreditthreshold = $p.Threshold
    }
    $id = Create-Record -EntitySet "rma_plants" -Body $body
    $newPlantIds[$p.Name] = $id
    Write-Host ("  [create] {0,-24} {1}  ({2})" -f $p.Name, $id, $p.Region) -ForegroundColor Green
}

# ---------------------------------------------------------------------------
# Step 2: Re-point all dependent records
# ---------------------------------------------------------------------------
Write-Host "`nStep 2: Re-point claims + routing rules to new plants..." -ForegroundColor Cyan

# Mapping: old plant name -> new plant name
$repointMap = @{
    "Austin Manufacturing"       = "Milford NH"
    "Detroit Assembly"           = "Waterbury CT"
    "Guadalajara Assembly"       = "Reynosa - Mexico"
    "Sao Paulo Manufacturing"    = "Reynosa - Mexico"
    "Shanghai Operations"        = "HLM - China"
    "Shanghai Electronics"       = "Penang - Malaysia"
    "Munich Precision"           = "Waterbury CT"
}

# Resolve old plant IDs
$oldPlantIds = @{}
foreach ($oldName in $repointMap.Keys) {
    $p = Find-Plant -Name $oldName
    if ($p) { $oldPlantIds[$oldName] = $p.rma_plantid }
}

# 2a. Update claims
Write-Host "  Updating rma_claim records..." -ForegroundColor Cyan
$claims = (Invoke-Dv -Method GET -Path "rma_claims?`$select=rma_claimid,rma_claimnumber,_rma_assignedplant_value").value
$claimsRepointed = 0
foreach ($c in $claims) {
    $currentPlantId = $c._rma_assignedplant_value
    if (-not $currentPlantId) { continue }
    # Find which old plant this is
    $oldName = $oldPlantIds.GetEnumerator() | Where-Object { $_.Value -eq $currentPlantId } | Select-Object -First 1 -ExpandProperty Key
    if (-not $oldName) { continue }  # already pointing to a new plant
    $newName = $repointMap[$oldName]
    $newId   = $newPlantIds[$newName]
    Invoke-Dv -Method PATCH -Path "rma_claims($($c.rma_claimid))" -Body @{ "rma_AssignedPlant@odata.bind" = "/rma_plants($newId)" } | Out-Null
    Write-Host ("    {0}  {1} -> {2}" -f $c.rma_claimnumber, $oldName, $newName) -ForegroundColor Green
    $claimsRepointed++
}
Write-Host "  Re-pointed $claimsRepointed claims" -ForegroundColor DarkGray

# 2b. Update routing rules
Write-Host "`n  Updating rma_routingrule records..." -ForegroundColor Cyan
$rules = (Invoke-Dv -Method GET -Path "rma_routingrules?`$select=rma_routingruleid,rma_name,_rma_assignedplant_value").value
$rulesRepointed = 0
foreach ($r in $rules) {
    $currentPlantId = $r._rma_assignedplant_value
    if (-not $currentPlantId) { continue }
    $oldName = $oldPlantIds.GetEnumerator() | Where-Object { $_.Value -eq $currentPlantId } | Select-Object -First 1 -ExpandProperty Key
    if (-not $oldName) { continue }
    $newName = $repointMap[$oldName]
    $newId   = $newPlantIds[$newName]
    Invoke-Dv -Method PATCH -Path "rma_routingrules($($r.rma_routingruleid))" -Body @{ "rma_AssignedPlant@odata.bind" = "/rma_plants($newId)" } | Out-Null
    Write-Host ("    {0,-36}  {1} -> {2}" -f $r.rma_name, $oldName, $newName) -ForegroundColor Green
    $rulesRepointed++
}
Write-Host "  Re-pointed $rulesRepointed routing rules" -ForegroundColor DarkGray

# ---------------------------------------------------------------------------
# Step 3: Deactivate old plants
# ---------------------------------------------------------------------------
Write-Host "`nStep 3: Deactivate placeholder plants..." -ForegroundColor Cyan
foreach ($oldName in $oldPlantIds.Keys) {
    $id = $oldPlantIds[$oldName]
    try {
        Invoke-Dv -Method PATCH -Path "rma_plants($id)" -Body @{ statecode=1; statuscode=2 } | Out-Null
        Write-Host "  [deactivated] $oldName" -ForegroundColor DarkYellow
    } catch {
        Write-Host "  [warn] could not deactivate $oldName : $($_.Exception.Message)" -ForegroundColor Red
    }
}

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
Write-Host "`n=== DONE ===" -ForegroundColor Cyan
Write-Host "Active plants now:" -ForegroundColor Cyan
$active = (Invoke-Dv -Method GET -Path "rma_plants?`$filter=statecode eq 0&`$select=rma_name,rma_region,rma_partprefixes,rma_autocreditthreshold&`$orderby=rma_name").value
$active | Format-Table @{n='Name';e='rma_name'}, rma_partprefixes, @{n='Threshold';e='rma_autocreditthreshold'} -AutoSize

Write-Host "`nClaims now distributed across:" -ForegroundColor Cyan
$claimSummary = (Invoke-Dv -Method GET -Path "rma_claims?`$expand=rma_AssignedPlant(`$select=rma_name)&`$select=rma_claimnumber").value
$claimSummary | Group-Object { $_.rma_AssignedPlant.rma_name } | Select-Object @{n='Plant';e='Name'}, @{n='Claims';e='Count'} | Sort-Object Plant | Format-Table -AutoSize

Write-Host "Routing rules:" -ForegroundColor Cyan
$ruleSummary = (Invoke-Dv -Method GET -Path "rma_routingrules?`$expand=rma_AssignedPlant(`$select=rma_name)&`$select=rma_name,rma_matchvalue,rma_priority").value | Sort-Object rma_priority
$ruleSummary | Select-Object @{n='Priority';e='rma_priority'}, @{n='Rule';e='rma_name'}, @{n='Match';e='rma_matchvalue'}, @{n='Plant';e={$_.rma_AssignedPlant.rma_name}} | Format-Table -AutoSize
