<#
.SYNOPSIS
    Seeds 5 realistic inbound RMA quality-support emails into rma_emaillogs.

    Each email mirrors the HKP Quality Support web-form submission body
    (Company, Email, Phone, PO, Qty, Part #, Manufacturing Date Code,
    Complaint reason, etc.) so the Email Assist pane has a queue to demo.

.NOTES
    - Idempotent: skips records whose rma_messageid already exists.
    - All emails are inbound (rma_direction = INBOUND = 100000000) and
      unprocessed (rma_isprocessed = false) so they show up in the
      "Next unprocessed" queue.
    - rma_fromaddress is set to noreply@ametek.com (the form notifier),
      but the body contains the real customer email so the Power Automate
      extraction flow can pull it out.
    - Auth: az login (Dataverse passwordless token).

.EXAMPLE
    pwsh -NoProfile -File customers/ametek/hkp_rma/scripts/seed_test_quality_emails.ps1
#>

[CmdletBinding()]
param(
    [string]$OrgUrl = "https://org6feab6b5.crm.dynamics.com"
)

$ErrorActionPreference = "Stop"
$ProgressPreference    = "SilentlyContinue"

Write-Host "`n=== Seeding test Quality Support emails ===" -ForegroundColor Cyan
Write-Host "Org: $OrgUrl`n" -ForegroundColor Gray

$token = (az account get-access-token --resource $OrgUrl --query accessToken -o tsv)
if (-not $token) { throw "Failed to get Dataverse token. Run 'az login' first." }

$hdr = @{
    Authorization      = "Bearer $token"
    Accept             = "application/json"
    "Content-Type"     = "application/json; charset=utf-8"
    "OData-Version"    = "4.0"
    "OData-MaxVersion" = "4.0"
}

function Invoke-Dv {
    param([string]$Method, [string]$Path, $Body = $null)
    $url = "$OrgUrl/api/data/v9.2/$Path"
    $params = @{ Uri = $url; Method = $Method; Headers = $hdr }
    if ($Body) { $params.Body = ($Body | ConvertTo-Json -Depth 20 -Compress) }
    return Invoke-RestMethod @params -ErrorAction Stop
}

# Build the form-body text in the canonical HKP Quality Support format
function Build-FormBody {
    param(
        [string]$Plant,
        [string]$Recipient,
        [string]$Company,
        [string]$Email,
        [string]$Phone,
        [string]$Address,
        [int]$Quantity,
        [string]$PoNumber,
        [string]$MfgCode,
        [string]$PartNumber,
        [string]$ComplaintReason,
        [string]$ComplaintDetails,
        [string]$SalesRep,
        [string]$Detection,
        [string]$ProductDescription,
        [string]$WhereDetected,
        [string]$NonConformance,
        [string]$OtherComments,
        [string]$Greeting,
        [int]$DaysAgo
    )
    # Build body in the canonical form-submission shape. Headers (From/To/Subject)
    # live in rma_fromaddress / rma_recipient / rma_subject and are NOT repeated here.
    $intro  = "***NOTICE*** This came from an external source. Use caution when replying, clicking links, or opening attachments.`r`n`r`n"
    $intro += "$Greeting, your form has been submitted. Our representatives will contact you.`r`n`r`n"
    $intro += "The information below was submitted using the Quality Support form found on www.haydonkerkpittman.com.`r`n`r`n"
    $body = @"
Company: $Company
Email: $Email
Phone: $Phone
Address returned parts will ship to:  $Address
Quantity of Suspect Parts: $Quantity
PO Number parts were ordered on: $PoNumber
Manufacturing Date Code/Serial Number, please see label on parts: $MfgCode
AMETEK Part Number: $PartNumber
MFG Location: $Plant
What is the complaint reason? With details (Please send photos/videos): $ComplaintReason
What is the complaint reason - Other: $ComplaintDetails
Please select your primary HKP sales representative: $SalesRep
How was the suspect part detected: $Detection
Product Description: $ProductDescription
Where in your process was the suspect part detected: $WhereDetected
Is there a Non-Conformance Report? What is the Non-Conformance Number: $NonConformance
Other Comments or explanation of your concern: $OtherComments
"@
    return $intro + $body
}

# 5 test submissions covering different plants / customers / failure modes
$tests = @(
    @{
        Plant              = "Penang, MY"
        Recipient          = "Rath.Feil@roche.com"
        Company            = "Roche Diagnostics International AG"
        Email              = "Rath.Feil@roche.com"
        Phone              = "+41 - 41 - 792 3660"
        Address            = "Rotkreuz, Zug 6343 Switzerland"
        Quantity           = 13
        PoNumber           = "7100328936"
        MfgCode            = "P2550-00xxx and P2608-00xxx"
        PartNumber         = "LC1574W-05-B25"
        ComplaintReason    = "Quality Complaint"
        ComplaintDetails   = "We sorted through the defective units and found the following issues since Feb.2026: - Four motors do not move at all. - Nine motors fail to perform the pull function. Specifically, the hardware drawer cannot be moved using the motor's force, whereas the functional units handle this task without issue."
        SalesRep           = "Istvan Nagy"
        Detection          = "Check failed: Motor does not move [4 pieces] and Motor move with low force [9 pieces]"
        ProductDescription = "09287868001 STEPPER MOTOR LC1574W-05 13mm PPS Nut"
        WhereDetected      = "Test before use in the production line"
        NonConformance     = "ROCHE-NCR-26-0488"
        OtherComments      = "Please check the stock to ensure that next delivery has no issues."
        Greeting           = "Rath"
        DaysAgo            = 0
    },
    @{
        Plant              = "Waterbury, CT"
        Recipient          = "Maria.Hansen@medtronic.com"
        Company            = "Medtronic plc"
        Email              = "Maria.Hansen@medtronic.com"
        Phone              = "+1 - 763 - 514 4000"
        Address            = "710 Medtronic Pkwy, Minneapolis, MN 55432 USA"
        Quantity           = 6
        PoNumber           = "4502987114"
        MfgCode            = "WTB-2025-1142 thru WTB-2025-1147"
        PartNumber         = "21H4U-2.33-907"
        ComplaintReason    = "Premature Failure"
        ComplaintDetails   = "Lead screws are exhibiting axial play of 0.18mm after only 80 hours of operation in an insulin pump assembly. Specification calls for <0.05mm over the 5000-hour life. We have lot WTB-2025 isolated; please advise on disposition."
        SalesRep           = "Tim Schoenfeld"
        Detection          = "Incoming inspection plus 80-hour bench durability test"
        ProductDescription = "Lead Screw Assembly 21H4U-2.33 with anti-backlash nut"
        WhereDetected      = "Final assembly QA bench test"
        NonConformance     = "MDT-NCR-26-0418"
        OtherComments      = "Production line is currently on hold awaiting your disposition. Need an RMA within 48 hours please."
        Greeting           = "Maria"
        DaysAgo            = 1
    },
    @{
        Plant              = "Penang, MY"
        Recipient          = "Chen.Wei@siemens-healthineers.com"
        Company            = "Siemens Healthineers AG"
        Email              = "Chen.Wei@siemens-healthineers.com"
        Phone              = "+49 - 9131 - 84 0"
        Address            = "Henkestrasse 127, 91052 Erlangen, Germany"
        Quantity           = 22
        PoNumber           = "PO-2026-449120"
        MfgCode            = "P2601-04xxx through P2603-04xxx"
        PartNumber         = "LC1574E-07-N16"
        ComplaintReason    = "Quality Complaint"
        ComplaintDetails   = "Stepper motors are producing audible grinding noise at low-speed RPM (<200 RPM) which is unacceptable for our analytical instrument application. Failure rate observed at 22 of 250 units (8.8%) in Q1 production lot."
        SalesRep           = "Istvan Nagy"
        Detection          = "End-of-line acoustic noise test (>52dB)"
        ProductDescription = "STEPPER MOTOR LC1574E-07 16mm Hybrid"
        WhereDetected      = "End-of-line functional test"
        NonConformance     = "SH-EU-NCR-26-0312"
        OtherComments      = "Requesting full lot containment plus 8D root-cause analysis. Photos and acoustic recordings available on request."
        Greeting           = "Chen"
        DaysAgo            = 2
    },
    @{
        Plant              = "Waterbury, CT"
        Recipient          = "Janet.Park@thermofisher.com"
        Company            = "Thermo Fisher Scientific Inc"
        Email              = "Janet.Park@thermofisher.com"
        Phone              = "+1 - 781 - 622 1000"
        Address            = "168 Third Avenue, Waltham, MA 02451 USA"
        Quantity           = 3
        PoNumber           = "TF-PO-7782341"
        MfgCode            = "WTB-2025-2098, WTB-2025-2103, WTB-2025-2107"
        PartNumber         = "G4-2105-PM-001"
        ComplaintReason    = "Dimensional Out-of-Spec"
        ComplaintDetails   = "Three precision gear assemblies received with backlash measured at 12 arc-min versus spec of <4 arc-min. Discovered during incoming inspection before installation into our centrifuge product line."
        SalesRep           = "Tim Schoenfeld"
        Detection          = "Incoming inspection per ASME B89.4.10"
        ProductDescription = "Precision Planetary Gear G4-2105 ratio 10:1"
        WhereDetected      = "Incoming receiving inspection"
        NonConformance     = "TF-NCR-2026-0517"
        OtherComments      = "All three units quarantined. Please ship replacements expedited and let us know return shipping address for failed units."
        Greeting           = "Janet"
        DaysAgo            = 3
    },
    @{
        Plant              = "Penang, MY"
        Recipient          = "Daniel.Okafor@bsci.com"
        Company            = "Boston Scientific Corporation"
        Email              = "Daniel.Okafor@bsci.com"
        Phone              = "+1 - 508 - 683 4000"
        Address            = "300 Boston Scientific Way, Marlborough, MA 01752 USA"
        Quantity           = 8
        PoNumber           = "BSC-MFG-26-7714"
        MfgCode            = "P2607-02xxx"
        PartNumber         = "AK57H4U-1.8-216"
        ComplaintReason    = "Vibration / Resonance Issue"
        ComplaintDetails   = "Linear actuator units exhibit excessive vibration at the 60-80 Hz operating range, causing image-quality issues in our endoscopy positioning system. Eight units pulled from production after customer-reported field issues."
        SalesRep           = "Istvan Nagy"
        Detection          = "Field customer complaint plus reproduced on lab fixture"
        ProductDescription = "Captive Linear Actuator AK57H4U 1.8deg step 216 lead"
        WhereDetected      = "Customer field site (endoscopy lab)"
        NonConformance     = "BSC-NCR-26-1019"
        OtherComments      = "These units shipped 6-8 weeks ago. Please confirm if a broader recall sweep of P2607 date code is warranted."
        Greeting           = "Daniel"
        DaysAgo            = 5
    }
)

$created = 0; $updated = 0
foreach ($t in $tests) {
    $subject = "$($t.Plant) | New Quality Support Submission"
    # Stable message id so re-runs are idempotent (per-recipient + part + qty)
    $msgId = ("hkp-qs-{0}-{1}-{2}" -f $t.Recipient, $t.PartNumber, $t.Quantity).ToLower() -replace '[^a-z0-9-]','-'
    $msgId = "<$msgId@form.haydonkerkpittman.com>"

    # Upsert: if a row with this messageid exists, PATCH the body fields so re-runs refresh content.
    $msgIdEsc = $msgId.Replace("'", "''")
    $existing = Invoke-Dv -Method GET -Path "rma_emaillogs?`$select=rma_emaillogid,rma_isprocessed&`$filter=rma_messageid eq '$msgIdEsc'&`$top=1"

    $body    = Build-FormBody @t
    $preview = ($body -split "`r`n`r`n", 5)[-1].Substring(0, [Math]::Min(200, ($body -split "`r`n`r`n", 5)[-1].Length))
    $received = (Get-Date).AddDays(-$t.DaysAgo).ToUniversalTime().ToString("o")

    $record = @{
        rma_subject       = $subject
        rma_fromaddress   = "noreply@ametek.com"
        rma_recipient     = $t.Recipient
        rma_body          = $body
        rma_bodypreview   = $preview
        rma_receiveddate  = $received
        rma_messageid     = $msgId
        rma_direction     = 100000000      # INBOUND
        rma_isprocessed   = $false
    }

    try {
        if ($existing.value -and $existing.value.Count -gt 0) {
            $existingId = $existing.value[0].rma_emaillogid
            # PATCH body/preview/subject so the extractor sees the fully-populated standard pairs.
            # Don't reset rma_isprocessed if user already processed it during testing.
            $patchBody = @{
                rma_subject     = $subject
                rma_body        = $body
                rma_bodypreview = $preview
            }
            Invoke-Dv -Method PATCH -Path "rma_emaillogs($existingId)" -Body $patchBody | Out-Null
            Write-Host "  [~] updated: $subject  ($($t.Recipient))" -ForegroundColor Yellow
            $updated++
        } else {
            $resp = Invoke-Dv -Method POST -Path "rma_emaillogs" -Body $record
            Write-Host "  [+] created: $subject  ($($t.Recipient))" -ForegroundColor Green
            $created++
        }
    } catch {
        Write-Host "  [!] FAILED: $subject -- $($_.Exception.Message)" -ForegroundColor Red
    }
}

Write-Host ""
Write-Host "=== Done ===" -ForegroundColor Cyan
Write-Host "Created: $created  |  Updated (refreshed body): $updated" -ForegroundColor Green
Write-Host ""
Write-Host "Verify in D365:" -ForegroundColor Yellow
Write-Host "  Sales Hub -> RMA Operations -> Email Logs (unprocessed inbound)" -ForegroundColor Gray
Write-Host ""
