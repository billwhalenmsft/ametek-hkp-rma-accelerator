# Seeds 5 HKP iDEA product serials into cr74e_productserial in Master CE Mfg.
# Each serial is designed to demonstrate a different disposition path.

$ErrorActionPreference = "Stop"

$org = "https://orgecbce8ef.crm.dynamics.com"
$token = (az account get-access-token --resource $org --query accessToken -o tsv)
$hdr = @{
    Authorization     = "Bearer $token"
    Accept            = "application/json"
    "Content-Type"    = "application/json"
    "OData-Version"   = "4.0"
    "OData-MaxVersion"= "4.0"
    Prefer            = "return=representation"
}

# Today is 2026-05-05 per system clock
$today = [datetime]"2026-05-05"

# 5 serials covering 4 demo scenarios
$serials = @(
    @{
        # SCENARIO 1: Andersen / lead screw / IN warranty → auto-approve_replace
        cr74e_serialnumber          = "IDEA-57-2025-104872"
        cr74e_productname           = "iDEA 57mm Linear Actuator (HKP)"
        cr74e_originalordernumber   = "PO-AND-2025-0814"
        cr74e_warrantystart         = $today.AddMonths(-6).ToString("yyyy-MM-dd")
        cr74e_warrantyend           = $today.AddMonths(18).ToString("yyyy-MM-dd")  # 18 months remaining
        _scenario                   = "in-warranty / Andersen / Tier 1"
    }
    @{
        # SCENARIO 2: Pella / well past warranty → reject + paid quote
        cr74e_serialnumber          = "IDEA-43-2022-087221"
        cr74e_productname           = "iDEA 43mm Linear Actuator (HKP)"
        cr74e_originalordernumber   = "PO-PEL-2022-1144"
        cr74e_warrantystart         = $today.AddMonths(-42).ToString("yyyy-MM-dd")
        cr74e_warrantyend           = $today.AddMonths(-24).ToString("yyyy-MM-dd")  # 720 days past
        _scenario                   = "out-of-warranty / Pella / Tier 2"
    }
    @{
        # SCENARIO 3: Borderline / 60 days past → unclear / engineer escalation
        cr74e_serialnumber          = "IDEA-35-2024-093311"
        cr74e_productname           = "iDEA 35mm Linear Actuator Compact (HKP)"
        cr74e_originalordernumber   = "PO-MAR-2024-0512"
        cr74e_warrantystart         = $today.AddMonths(-20).ToString("yyyy-MM-dd")
        cr74e_warrantyend           = $today.AddDays(-60).ToString("yyyy-MM-dd")  # 60 days past
        _scenario                   = "borderline / Marvin / Tier 1"
    }
    @{
        # SCENARIO 4: Distributor / misuse keywords (any warranty status, gets rejected)
        cr74e_serialnumber          = "IDEA-28-2025-201155"
        cr74e_productname           = "iDEA 28mm Linear Actuator (HKP)"
        cr74e_originalordernumber   = "PO-ACME-2025-2200"
        cr74e_warrantystart         = $today.AddMonths(-3).ToString("yyyy-MM-dd")
        cr74e_warrantyend           = $today.AddMonths(9).ToString("yyyy-MM-dd")  # in warranty but doesn't matter
        _scenario                   = "in-warranty BUT misuse keywords / Acme / Tier 3"
    }
    @{
        # SCENARIO 5: Repeat-claim signature (same SKU, multiple recent claims) - high cost replace, manager approval
        cr74e_serialnumber          = "IDEA-57-2025-104880"
        cr74e_productname           = "iDEA 57mm Linear Actuator (HKP)"
        cr74e_originalordernumber   = "PO-AND-2025-0820"
        cr74e_warrantystart         = $today.AddMonths(-4).ToString("yyyy-MM-dd")
        cr74e_warrantyend           = $today.AddMonths(20).ToString("yyyy-MM-dd")
        _scenario                   = "in-warranty / Andersen / cost > Tier 1 cap requires Manager Approval"
    }
)

Write-Host "Seeding $($serials.Count) HKP product serials into cr74e_productserial..." -ForegroundColor Cyan

foreach ($s in $serials) {
    $scenario = $s._scenario
    $payload = $s.Clone()
    $payload.Remove("_scenario") | Out-Null

    Write-Host ""
    Write-Host "--- $($s.cr74e_serialnumber) ---" -ForegroundColor Yellow
    Write-Host "    Scenario: $scenario" -ForegroundColor Gray
    Write-Host "    Warranty: $($s.cr74e_warrantystart) → $($s.cr74e_warrantyend)" -ForegroundColor Gray

    # Check if exists
    $existing = $null
    try {
        $existing = (Invoke-RestMethod -Uri "$org/api/data/v9.2/cr74e_productserials?`$filter=cr74e_serialnumber eq '$($s.cr74e_serialnumber)'&`$select=cr74e_productserialid" -Headers $hdr -ErrorAction Stop).value
    } catch {
        Write-Host "    Lookup error: $_" -ForegroundColor Red
        continue
    }

    if ($existing -and $existing.Count -gt 0) {
        $id = $existing[0].cr74e_productserialid
        Write-Host "    EXISTS → updating ($id)" -ForegroundColor DarkYellow
        try {
            Invoke-RestMethod -Uri "$org/api/data/v9.2/cr74e_productserials($id)" -Method Patch -Headers $hdr -Body ($payload | ConvertTo-Json) -ErrorAction Stop | Out-Null
            Write-Host "    ✅ Updated" -ForegroundColor Green
        } catch {
            Write-Host "    ❌ Update failed: $_" -ForegroundColor Red
        }
    }
    else {
        Write-Host "    NEW → creating" -ForegroundColor Green
        try {
            $created = Invoke-RestMethod -Uri "$org/api/data/v9.2/cr74e_productserials" -Method Post -Headers $hdr -Body ($payload | ConvertTo-Json) -ErrorAction Stop
            Write-Host "    ✅ Created ($($created.cr74e_productserialid))" -ForegroundColor Green
        } catch {
            Write-Host "    ❌ Create failed: $_" -ForegroundColor Red
        }
    }
}

Write-Host ""
Write-Host "Done. Verifying..." -ForegroundColor Cyan
$result = (Invoke-RestMethod -Uri "$org/api/data/v9.2/cr74e_productserials?`$filter=startswith(cr74e_serialnumber,'IDEA-')&`$select=cr74e_serialnumber,cr74e_productname,cr74e_warrantystart,cr74e_warrantyend,cr74e_originalordernumber" -Headers $hdr).value
$result | Format-Table cr74e_serialnumber, cr74e_productname, cr74e_warrantystart, cr74e_warrantyend, cr74e_originalordernumber -AutoSize
