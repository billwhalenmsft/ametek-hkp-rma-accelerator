<#
.SYNOPSIS
    Seed resolution email templates for Credit, Replacement, Repair actions.
    Idempotent by rma_name.
#>
$ErrorActionPreference = "Stop"
$org = "https://org6feab6b5.crm.dynamics.com"
$token = (az account get-access-token --resource $org --query accessToken -o tsv)
$hdr = @{
    Authorization = "Bearer $token"
    Accept = "application/json"
    "Content-Type" = "application/json; charset=utf-8"
    "OData-Version" = "4.0"
    "OData-MaxVersion" = "4.0"
    "MSCRM.SolutionUniqueName" = "RMAReturnsMonitor"
    Prefer = "return=representation"
}

# rma_triggerresolution picklist values mirror the tracker RESOLUTION enum:
#   100000000 Credit, 100000001 Replacement, 100000002 Repair, 100000003 Denied
$templates = @(
    @{
        name = "Credit: Standard"; trigger = 100000000
        subject = "RMA {claimNumber} - Credit Approved"
        body = @"
Dear {firstName},

Good news - your claim RMA {claimNumber} has been approved for a credit.

Amount approved: {amount}
Reference: RMA {claimNumber}

The credit will be applied to your account within 5-7 business days. You will see it reflected on your next statement.

If you have any questions please reply to this email.

Regards,
HKP Returns Team
"@
    }
    @{
        name = "Credit: Goodwill"; trigger = 100000000
        subject = "RMA {claimNumber} - Goodwill Credit Issued"
        body = @"
Dear {firstName},

While the unit referenced in RMA {claimNumber} did not strictly qualify for warranty replacement, we value your business and are issuing a goodwill credit in this case.

Amount approved: {amount}

Please note that future claims of the same nature may not be eligible. Our team is happy to discuss preventative options or extended coverage if you'd like.

Regards,
HKP Returns Team
"@
    }
    @{
        name = "Replacement: Standard"; trigger = 100000001
        subject = "RMA {claimNumber} - Replacement Shipping"
        body = @"
Dear {firstName},

Your claim RMA {claimNumber} has been approved for a replacement unit.

A replacement of equivalent specification is being prepared and will ship via our standard carrier. You will receive tracking information once the shipment is in transit.

Estimated value: {amount}

Please return the defective unit using the included prepaid label within 30 days.

Regards,
HKP Returns Team
"@
    }
    @{
        name = "Replacement: Expedited"; trigger = 100000001
        subject = "RMA {claimNumber} - Expedited Replacement"
        body = @"
Dear {firstName},

Your claim RMA {claimNumber} has been approved for an expedited replacement.

We're shipping a replacement unit via overnight carrier today. Tracking information will follow within the next few hours.

Estimated value: {amount}

The defective unit should be returned using the included prepaid label within 30 days.

Regards,
HKP Returns Team
"@
    }
    @{
        name = "Repair: Standard"; trigger = 100000002
        subject = "RMA {claimNumber} - Repair Completed"
        body = @"
Dear {firstName},

The unit associated with RMA {claimNumber} has been repaired and is being returned to you.

Repair summary: covered under warranty - no charge.

You will receive shipment tracking information shortly. Please allow 3-5 business days for delivery.

Regards,
HKP Returns Team
"@
    }
)

foreach ($t in $templates) {
    $escapedName = $t.name.Replace("'", "''")
    $existing = Invoke-RestMethod -Uri "$org/api/data/v9.2/rma_emailtemplates?`$filter=rma_name eq '$escapedName'&`$select=rma_emailtemplateid" -Headers $hdr
    if ($existing.value.Count -gt 0) {
        Write-Host "  exists: $($t.name)" -ForegroundColor DarkYellow
        continue
    }
    $body = @{
        rma_name = $t.name
        rma_subject = $t.subject
        rma_body = $t.body
        rma_isactive = $true
        rma_isautosend = $false
    } | ConvertTo-Json -Depth 5
    try {
        Invoke-RestMethod -Uri "$org/api/data/v9.2/rma_emailtemplates" -Method POST -Headers $hdr -Body $body | Out-Null
        Write-Host "  + $($t.name)" -ForegroundColor Green
    } catch {
        Write-Host "  ! $($t.name): $($_.Exception.Message)" -ForegroundColor Red
    }
}

Write-Host "`nDONE." -ForegroundColor Green
