# =============================================================================
# enhance_routing_rule_ux.ps1
#
# (a) Pushes a clear Description to each rma_routingrule column so the (?) tooltip
#     in the form explains exactly what to enter.
# (b) Adds a help banner to the Quick Create form (renames the GENERAL section
#     label to explain how a routing rule works).
# =============================================================================
$org='https://org6feab6b5.crm.dynamics.com'
$token=az account get-access-token --resource $org --query accessToken -o tsv
$hg=@{Authorization="Bearer $token";Accept='application/json'}
$hp=@{Authorization="Bearer $token";Accept='application/json';'Content-Type'='application/json; charset=utf-8';'If-Match'='*'}

function Set-AttrDescription {
    param([string]$Entity, [string]$Attr, [string]$TypeCast, [string]$Text)
    # GET current metadata, modify Description, PUT back (PATCH not supported on metadata)
    try {
        $url = "$org/api/data/v9.2/EntityDefinitions(LogicalName='$Entity')/Attributes(LogicalName='$Attr')/Microsoft.Dynamics.CRM.$TypeCast"
        $meta = Invoke-RestMethod -Uri $url -Headers $hg
        # Strip OData annotations that PUT rejects
        $meta = $meta | Select-Object -Property * -ExcludeProperty '@odata.context','MetadataId'
        $clone = @{}
        $meta.PSObject.Properties | ForEach-Object { if ($null -ne $_.Value) { $clone[$_.Name] = $_.Value } }
        $clone['@odata.type'] = "#Microsoft.Dynamics.CRM.$TypeCast"
        $clone['Description'] = @{
            '@odata.type' = '#Microsoft.Dynamics.CRM.Label'
            LocalizedLabels = @(@{
                '@odata.type' = '#Microsoft.Dynamics.CRM.LocalizedLabel'
                Label = $Text
                LanguageCode = 1033
            })
        }
        $body = $clone | ConvertTo-Json -Depth 20 -Compress
        $headers = @{Authorization="Bearer $token";'Content-Type'='application/json';'MSCRM.MergeLabels'='true'}
        Invoke-WebRequest -Uri $url -Method Put -Headers $headers -Body $body -UseBasicParsing -ErrorAction Stop | Out-Null
        Write-Host "  $Attr -> tooltip set" -ForegroundColor Green
    } catch {
        Write-Host "  $Attr ERR: $($_.ErrorDetails.Message)" -ForegroundColor Red
    }
}

# ---- (a) Field tooltips ------------------------------------------------------
Write-Host "`n== (a) Setting field descriptions on rma_routingrule ==" -ForegroundColor Magenta

Set-AttrDescription 'rma_routingrule' 'rma_name' 'StringAttributeMetadata' `
    'Human label for this rule, e.g. "HKP parts -> Sanford" or "EMEA fallback".'

Set-AttrDescription 'rma_routingrule' 'rma_ruletype' 'PicklistAttributeMetadata' `
    'WHICH attribute of an incoming claim to evaluate: Part Prefix (matches the part number), Customer Region (NA/EMEA/APAC/etc.), or Product Line.'

Set-AttrDescription 'rma_routingrule' 'rma_matchvalue' 'StringAttributeMetadata' `
    'The literal string to match against the Rule Type. Examples: "HKP-" for Part Prefix, "EMEA" for Customer Region, "Pumps" for Product Line. Case-insensitive prefix match.'

Set-AttrDescription 'rma_routingrule' 'rma_priority' 'IntegerAttributeMetadata' `
    'Tiebreaker when multiple rules match. LOWER number wins (Priority 10 evaluates before Priority 50). Use 10/20/30 for primary rules and 90/99 for fallbacks.'

Set-AttrDescription 'rma_routingrule' 'rma_assignedplant' 'LookupAttributeMetadata' `
    'The plant the claim should be assigned to when this rule matches.'

Set-AttrDescription 'rma_routingrule' 'rma_isactive' 'BooleanAttributeMetadata' `
    'Toggle to disable a rule without deleting it. Inactive rules are skipped by the routing engine.'

# ---- (b) Quick Create banner -------------------------------------------------
Write-Host "`n== (b) Adding help banner to Quick Create form ==" -ForegroundColor Magenta
$qcId = '7d28d580-628a-4ae1-812c-7e0f79e2c977'
$banner = 'How this works: IF an incoming claim matches the Rule Type + Match Value below, THEN assign it to the chosen plant. Lower Priority numbers evaluate first.'

$cur = Invoke-RestMethod -Uri "$org/api/data/v9.2/systemforms($qcId)?`$select=formxml" -Headers $hg
$xml = $cur.formxml

# Replace the GENERAL section label with our banner (only the first one)
$pattern = '<label description="GENERAL" languagecode="1033" />'
$replacement = "<label description=`"$banner`" languagecode=`"1033`" />"
if ($xml.Contains($pattern)) {
    $newXml = ([regex]::new([regex]::Escape($pattern))).Replace($xml, $replacement, 1)
    # also force showlabel="true" on that section so the banner renders
    $newXml = $newXml -replace 'section showlabel="false" showbar="false"', 'section showlabel="true" showbar="false"'
    $body = @{ formxml = $newXml; formjson = $null } | ConvertTo-Json -Depth 5 -Compress
    Invoke-WebRequest -Uri "$org/api/data/v9.2/systemforms($qcId)" -Method Patch -Headers $hp -Body $body -UseBasicParsing | Out-Null
    Write-Host "  QC form banner set" -ForegroundColor Green
} else {
    Write-Host "  GENERAL label not found - banner skipped" -ForegroundColor Yellow
}

# ---- Publish -----------------------------------------------------------------
Write-Host "`n== Publishing rma_routingrule ==" -ForegroundColor Magenta
$px = '<importexportxml><entities><entity>rma_routingrule</entity></entities></importexportxml>'
Invoke-WebRequest -Uri "$org/api/data/v9.2/PublishXml" -Method Post -Headers $hp -Body (@{ParameterXml=$px}|ConvertTo-Json) -UseBasicParsing | Out-Null
Write-Host "Done." -ForegroundColor Green
