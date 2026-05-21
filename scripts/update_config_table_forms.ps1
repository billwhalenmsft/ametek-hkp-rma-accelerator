# =============================================================================
# update_config_table_forms.ps1
#
# Adds the full set of user-relevant fields to Main + Quick Create forms for
# the RMA config tables (Plant, Routing Rule, Plant Approver, Email Signature).
# Email Template already has its full form (see add_email_template_form_fields_v2.ps1).
#
# Pattern: PATCH systemforms({id}) with new formxml + null formjson,
#          then PublishXml on all touched entities.
# =============================================================================
$org='https://org6feab6b5.crm.dynamics.com'
$token=az account get-access-token --resource $org --query accessToken -o tsv
$hg=@{Authorization="Bearer $token";Accept='application/json'}
$hp=@{Authorization="Bearer $token";Accept='application/json';'Content-Type'='application/json; charset=utf-8';'If-Match'='*'}

# ---- Control class IDs (Dataverse standard) ----------------------------------
$TXT  = '{4273EDBD-AC1D-40d3-9FB2-095C621B552D}'  # SingleLineText
$MEMO = '{E0DECE4B-6FC8-4a8f-A065-082708572369}'  # Memo
$PICK = '{3EF39988-22BB-4f0b-BBBE-64B5A3748AEE}'  # OptionSet
$BOOL = '{67FAC785-CD58-4f9f-ABB3-4B7DDC6ED5ED}'  # TwoOption
$INT  = '{C6D124CA-7EDA-4a60-AEA9-7FB8D318B68F}'  # WholeNumber
$MONEY= '{533B9E00-756B-4312-95A0-DC888637AC78}'  # Money
$DT   = '{5B773807-9FB2-42db-97C3-7A91EFF8ADFF}'  # DateTime
$LOOK = '{270BD3DB-D9AF-4782-9025-509E298DEC0A}'  # Lookup

$anchor = 'datafieldname="ownerid" /></cell></row>'
$cellSeq = 0

function New-Row {
    param([string]$Field, [string]$Label, [string]$ClassId, [int]$Colspan = 1, [int]$Rowspan = 1)
    $script:cellSeq++
    $cellId = '{a1f0' + ('{0:x4}' -f $script:cellSeq) + '-0000-0000-0000-0000000000' + ('{0:x2}' -f ($script:cellSeq % 256)) + '}'
    $span = ''
    if ($Colspan -gt 1) { $span += " colspan=`"$Colspan`"" }
    if ($Rowspan -gt 1) { $span += " rowspan=`"$Rowspan`"" }
    return "<row><cell id=`"$cellId`"$span><labels><label description=`"$Label`" languagecode=`"1033`" /></labels><control id=`"$Field`" classid=`"$ClassId`" datafieldname=`"$Field`" /></cell></row>"
}

function Update-Form {
    param([string]$EntityName, [string]$FormId, [string]$FormLabel, [string]$NewRows)
    Write-Host "  $FormLabel ($FormId)" -ForegroundColor Cyan
    $cur = Invoke-RestMethod -Uri "$org/api/data/v9.2/systemforms($FormId)?`$select=formxml" -Headers $hg
    if ($cur.formxml -notmatch [regex]::Escape($anchor)) {
        Write-Host "    ! anchor not found, skipping" -ForegroundColor Yellow
        return
    }
    # Idempotent: strip any prior insertion (look for our marker comment)
    $marker = '<!--CFG-FORM-BEGIN-->'
    $endMarker = '<!--CFG-FORM-END-->'
    $clean = $cur.formxml
    if ($clean.Contains($marker)) {
        $clean = ($clean -replace [regex]::Escape($marker) + '.*?' + [regex]::Escape($endMarker), '')
    }
    $payload = $marker + $NewRows + $endMarker
    $newXml = $clean.Replace($anchor, $anchor + $payload)
    $body = @{ formxml = $newXml; formjson = $null } | ConvertTo-Json -Depth 5 -Compress
    try {
        Invoke-WebRequest -Uri "$org/api/data/v9.2/systemforms($FormId)" -Method Patch -Headers $hp -Body $body -UseBasicParsing -ErrorAction Stop | Out-Null
        Write-Host "    PATCH ok (len $($newXml.Length))" -ForegroundColor Green
    } catch {
        Write-Host "    ERR: $($_.ErrorDetails.Message)" -ForegroundColor Red
    }
}

# =============================================================================
# Form IDs (Main = type 2, Quick Create = type 6)
# =============================================================================
$forms = @{
    'rma_plant'         = @{ main='0e6b2258-5c07-4eb1-8e16-a6228d249f12'; qc='8390b6fd-8528-4138-bdf1-6863b106c675' }
    'rma_routingrule'   = @{ main='7baee065-15eb-4890-9551-9cf3ca5e759d'; qc='7d28d580-628a-4ae1-812c-7e0f79e2c977' }
    'rma_plantapprover' = @{ main='814ab779-01fb-4da9-b23f-f27497fc0487'; qc='fd900448-15f1-4385-947b-a4a44c362637' }
    'rma_emailsignature'= @{ main='cea046ba-3bb7-4b26-9d4a-7e11395704fb'; qc='474504a3-e3c1-49a9-accb-1e0384b08985' }
}

# =============================================================================
# rma_plant
# =============================================================================
Write-Host "`n== rma_plant ==" -ForegroundColor Magenta
$plantMain = (New-Row 'rma_region'              'Region'                $PICK) +
             (New-Row 'rma_autocreditthreshold' 'Auto Credit Threshold' $MONEY) +
             (New-Row 'rma_partprefixes'        'Part Prefixes'         $TXT 2) +
             (New-Row 'rma_productlines'        'Product Lines'         $TXT 2)
Update-Form 'rma_plant' $forms['rma_plant'].main 'Main form' $plantMain

$plantQC = (New-Row 'rma_region'              'Region'                $PICK) +
           (New-Row 'rma_autocreditthreshold' 'Auto Credit Threshold' $MONEY) +
           (New-Row 'rma_partprefixes'        'Part Prefixes'         $TXT 2)
Update-Form 'rma_plant' $forms['rma_plant'].qc 'Quick Create' $plantQC

# =============================================================================
# rma_routingrule
# =============================================================================
Write-Host "`n== rma_routingrule ==" -ForegroundColor Magenta
$rrMain = (New-Row 'rma_ruletype'      'Rule Type'      $PICK) +
          (New-Row 'rma_priority'      'Priority'       $INT) +
          (New-Row 'rma_assignedplant' 'Assigned Plant' $LOOK) +
          (New-Row 'rma_isactive'      'Is Active'      $BOOL) +
          (New-Row 'rma_matchvalue'    'Match Value'    $TXT 2)
Update-Form 'rma_routingrule' $forms['rma_routingrule'].main 'Main form' $rrMain

$rrQC = (New-Row 'rma_ruletype'      'Rule Type'      $PICK) +
        (New-Row 'rma_matchvalue'    'Match Value'    $TXT) +
        (New-Row 'rma_assignedplant' 'Assigned Plant' $LOOK) +
        (New-Row 'rma_priority'      'Priority'       $INT) +
        (New-Row 'rma_isactive'      'Is Active'      $BOOL)
Update-Form 'rma_routingrule' $forms['rma_routingrule'].qc 'Quick Create' $rrQC

# =============================================================================
# rma_plantapprover  (plant routing + dollar-tier escalation)
# =============================================================================
Write-Host "`n== rma_plantapprover ==" -ForegroundColor Magenta
$paMain = (New-Row 'rma_plant'              'Plant'                 $LOOK) +
          (New-Row 'rma_role'               'Role / Title'          $TXT) +
          (New-Row 'rma_email'              'Email'                 $TXT) +
          (New-Row 'rma_teamsupn'           'Teams UPN'             $TXT) +
          (New-Row 'rma_assignmentmode'     'Assignment Mode'       $PICK) +
          (New-Row 'rma_notifywhen'         'Notify When'           $PICK) +
          (New-Row 'rma_highvaluethreshold' 'High Value Threshold'  $MONEY) +
          (New-Row 'rma_isactive'           'Is Active'             $BOOL)
Update-Form 'rma_plantapprover' $forms['rma_plantapprover'].main 'Main form' $paMain

$paQC = (New-Row 'rma_plant'              'Plant'                $LOOK) +
        (New-Row 'rma_role'               'Role / Title'         $TXT) +
        (New-Row 'rma_teamsupn'           'Teams UPN'            $TXT) +
        (New-Row 'rma_notifywhen'         'Notify When'          $PICK) +
        (New-Row 'rma_highvaluethreshold' 'High Value Threshold' $MONEY) +
        (New-Row 'rma_isactive'           'Is Active'            $BOOL)
Update-Form 'rma_plantapprover' $forms['rma_plantapprover'].qc 'Quick Create' $paQC

# =============================================================================
# rma_emailsignature
# =============================================================================
Write-Host "`n== rma_emailsignature ==" -ForegroundColor Magenta
$esMain = (New-Row 'rma_signername' 'Signer Name' $TXT) +
          (New-Row 'rma_title'      'Title'       $TXT) +
          (New-Row 'rma_phone'      'Phone'       $TXT) +
          (New-Row 'rma_email'      'Email'       $TXT) +
          (New-Row 'rma_isdefault'  'Is Default'  $BOOL) +
          (New-Row 'rma_imageurl'   'Image URL'   $TXT 2)
Update-Form 'rma_emailsignature' $forms['rma_emailsignature'].main 'Main form' $esMain

$esQC = (New-Row 'rma_signername' 'Signer Name' $TXT) +
        (New-Row 'rma_title'      'Title'       $TXT) +
        (New-Row 'rma_email'      'Email'       $TXT) +
        (New-Row 'rma_isdefault'  'Is Default'  $BOOL)
Update-Form 'rma_emailsignature' $forms['rma_emailsignature'].qc 'Quick Create' $esQC

# =============================================================================
# Publish all touched entities
# =============================================================================
Write-Host "`n== Publishing ==" -ForegroundColor Magenta
$entityXml = ($forms.Keys | ForEach-Object { "<entity>$_</entity>" }) -join ''
$px = "<importexportxml><entities>$entityXml</entities></importexportxml>"
Invoke-WebRequest -Uri "$org/api/data/v9.2/PublishXml" -Method Post -Headers $hp -Body (@{ParameterXml=$px}|ConvertTo-Json) -UseBasicParsing | Out-Null
Write-Host "  Published $($forms.Keys.Count) entities" -ForegroundColor Green
Write-Host "`nDone." -ForegroundColor Green
