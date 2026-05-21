# patch_email_flow_hybrid.ps1
# ----------------------------------------------------------------
# Upgrades the "RMA Email Monitor" flow to:
#   1. Compute confidence from AI extraction (count of populated critical fields / 6)
#   2. Branch: high confidence (>= 0.8) -> auto-create rma_claim
#                low confidence (< 0.8) -> land in rma_emaillog only (review queue)
#   3. Both paths: link rma_emaillog -> claim (high) and send ack
#   4. Drops the legacy SharePoint Create_item action
#
# Per-plant tuning lives on rma_plant.rma_autoclaimconfidence (seeded 0.8).
# This flow uses the global default (0.8) at the email gate. Per-plant
# threshold can be consumed later once plant context is known (e.g., for
# auto-credit decisions in the Auto-Assign Plant flow chain).
#
# Pre-req: backup at customers/ametek/hkp_rma/d365/rma_email_monitor_backup_*.json
# ----------------------------------------------------------------

$ErrorActionPreference = "Stop"
$orgUrl   = "https://org6feab6b5.crm.dynamics.com"
$flowId   = "6d9fc9b0-5e4d-f111-bec6-000d3a5aed87"
$threshold = 0.8

$token  = (az account get-access-token --resource $orgUrl --query accessToken -o tsv)
$hdr    = @{ Authorization="Bearer $token"; Accept="application/json" }
$pchHdr = @{ Authorization="Bearer $token"; Accept="application/json"; "Content-Type"="application/json; charset=utf-8"; "If-Match"="*" }

# ---------- Pull current clientdata ----------
Write-Host "[1/4] Loading flow..."
$wf = Invoke-RestMethod -Uri "$orgUrl/api/data/v9.2/workflows($flowId)?`$select=clientdata,name,statecode" -Headers $hdr
$cd = $wf.clientdata | ConvertFrom-Json
$actions = $cd.properties.definition.actions

# ---------- Build new actions ----------
Write-Host "[2/4] Building new action graph..."

# 1) Compute confidence: count non-empty critical fields / 6
$composeConfidence = @{
    runAfter = @{ Parse_RMA_Fields = @("Succeeded") }
    type     = "Compose"
    inputs   = "@div(add(add(add(add(add(if(greater(length(coalesce(body('Parse_RMA_Fields')?['Company'],'')),0),1,0),if(greater(length(coalesce(body('Parse_RMA_Fields')?['Email'],'')),0),1,0)),if(greater(length(coalesce(body('Parse_RMA_Fields')?['PartNumber'],'')),0),1,0)),if(greater(length(coalesce(body('Parse_RMA_Fields')?['ComplaintReason'],'')),0),1,0)),if(greater(length(coalesce(body('Parse_RMA_Fields')?['Quantity'],'')),0),1,0)),if(greater(length(coalesce(body('Parse_RMA_Fields')?['PONumber'],'')),0),1,0)),6.0)"
}

# 2) Add_to_rma_emaillog (KEEP existing; reset runAfter to depend on confidence)
$emailLog = $actions.Add_to_rma_emaillog
$emailLog.runAfter = @{ Compose_Confidence_Score = @("Succeeded") }

# 3) Condition: confidence >= 0.8
$createClaimAction = @{
    runAfter = @{}
    type     = "OpenApiConnection"
    inputs   = @{
        parameters = [ordered]@{
            entityName               = "rma_claims"
            "item/rma_claimnumber"   = "@concat('RMA-EM-', formatDateTime(utcNow(),'yyMMddHHmmss'))"
            "item/rma_customername"  = "@coalesce(body('Parse_RMA_Fields')?['Company'],'Unknown Customer')"
            "item/rma_customeremail" = "@coalesce(body('Parse_RMA_Fields')?['Email'], triggerOutputs()?['body/from'])"
            "item/rma_contactname"   = "@triggerOutputs()?['body/from']"
            "item/rma_customerregion" = 100000000
            "item/rma_partnumber"    = "@coalesce(body('Parse_RMA_Fields')?['PartNumber'],'UNKNOWN')"
            "item/rma_quantity"      = "@if(equals(coalesce(body('Parse_RMA_Fields')?['Quantity'],''),''),1,int(body('Parse_RMA_Fields')?['Quantity']))"
            "item/rma_failuredescription" = "@coalesce(body('Parse_RMA_Fields')?['ComplaintReason'],'(no description provided)')"
            "item/rma_failuremode"   = 100000005
            "item/rma_status"        = 100000000
            "item/rma_warrantystatus" = 100000003
            "item/rma_sourceemailid" = "@triggerOutputs()?['body/id']"
            "item/rma_createddate"   = "@triggerOutputs()?['body/receivedDateTime']"
        }
        host = @{
            apiId          = "/providers/Microsoft.PowerApps/apis/shared_commondataserviceforapps"
            connectionName = "shared_commondataserviceforapps"
            operationId    = "CreateRecord"
        }
        authentication = "@parameters('`$authentication')"
    }
}

$linkEmailLogToClaim = @{
    runAfter = @{ Create_RMA_Claim = @("Succeeded") }
    type     = "OpenApiConnection"
    inputs   = @{
        parameters = [ordered]@{
            entityName    = "rma_emaillogs"
            recordId      = "@outputs('Add_to_rma_emaillog')?['body/rma_emaillogid']"
            "item/rma_Claim@odata.bind" = "@concat('/rma_claims(', outputs('Create_RMA_Claim')?['body/rma_claimid'], ')')"
            "item/rma_isprocessed" = $true
        }
        host = @{
            apiId          = "/providers/Microsoft.PowerApps/apis/shared_commondataserviceforapps"
            connectionName = "shared_commondataserviceforapps"
            operationId    = "UpdateRecord"
        }
        authentication = "@parameters('`$authentication')"
    }
}

$conditionAction = @{
    runAfter = @{ Add_to_rma_emaillog = @("Succeeded") }
    type     = "If"
    expression = @{
        and = @(
            @{ greaterOrEquals = @( "@outputs('Compose_Confidence_Score')", $threshold ) }
        )
    }
    actions = @{
        Create_RMA_Claim          = $createClaimAction
        Link_EmailLog_To_Claim    = $linkEmailLogToClaim
    }
    else = @{
        actions = @{
            Mark_For_Review = @{
                runAfter = @{}
                type     = "OpenApiConnection"
                inputs   = @{
                    parameters = [ordered]@{
                        entityName = "rma_emaillogs"
                        recordId   = "@outputs('Add_to_rma_emaillog')?['body/rma_emaillogid']"
                        "item/rma_isprocessed" = $false
                    }
                    host = @{
                        apiId          = "/providers/Microsoft.PowerApps/apis/shared_commondataserviceforapps"
                        connectionName = "shared_commondataserviceforapps"
                        operationId    = "UpdateRecord"
                    }
                    authentication = "@parameters('`$authentication')"
                }
            }
        }
    }
}

# 4) Send acknowledgement (always, after the gate completes either way)
$sendAck = @{
    runAfter = @{ Check_Confidence_Threshold = @("Succeeded","Failed","Skipped") }
    type     = "OpenApiConnection"
    inputs   = @{
        parameters = [ordered]@{
            emailMessage = [ordered]@{
                To       = "@coalesce(body('Parse_RMA_Fields')?['Email'], triggerOutputs()?['body/from'])"
                Subject  = "Your RMA request has been received"
                Body     = @"
<p>Hi,</p>
<p>Thanks for your email regarding part <b>@{coalesce(body('Parse_RMA_Fields')?['PartNumber'],'(part not detected)')}</b>.</p>
<p>We've logged your request and our team will review it shortly. You'll either receive confirmation that an RMA claim has been opened, or we'll reach back out with questions/updates.</p>
<p>— RMA Team<br/>HKP / Ametek</p>
"@
                Importance = "Normal"
            }
        }
        host = @{
            apiId          = "/providers/Microsoft.PowerApps/apis/shared_office365"
            connectionName = "shared_office365"
            operationId    = "SendEmailV2"
        }
        authentication = "@parameters('`$authentication')"
    }
}

# ---------- Reassemble actions object ----------
# Keep: Run_RMA_Prompt, Parse_RMA_Fields, Add_to_rma_emaillog (modified runAfter)
# Add:  Compose_Confidence_Score, Check_Confidence_Threshold, Send_Acknowledgement
# Drop: Create_item (SharePoint)

$newActions = [ordered]@{
    Run_RMA_Prompt              = $actions.Run_RMA_Prompt
    Parse_RMA_Fields            = $actions.Parse_RMA_Fields
    Compose_Confidence_Score    = $composeConfidence
    Add_to_rma_emaillog         = $emailLog
    Check_Confidence_Threshold  = $conditionAction
    Send_Acknowledgement        = $sendAck
}

# Replace actions in clientdata
$cd.properties.definition.actions = $newActions

# (Description bump skipped — property may not exist on definition shape; not required for deploy.)

# ---------- PATCH ----------
Write-Host "[3/4] Patching workflow..."
$newClientdata = $cd | ConvertTo-Json -Depth 50 -Compress
$body = @{ clientdata = $newClientdata } | ConvertTo-Json -Depth 50

try {
    Invoke-WebRequest -Uri "$orgUrl/api/data/v9.2/workflows($flowId)" -Method Patch -Headers $pchHdr -Body $body | Out-Null
    Write-Host "[ok] Flow patched."
} catch {
    Write-Host "[ERR] PATCH failed: $($_.ErrorDetails.Message)"
    throw
}

# ---------- Verify ----------
Write-Host "[4/4] Verifying..."
$wf2 = Invoke-RestMethod -Uri "$orgUrl/api/data/v9.2/workflows($flowId)?`$select=clientdata,statecode,name" -Headers $hdr
$cd2 = $wf2.clientdata | ConvertFrom-Json
"Flow:    $($wf2.name)"
"State:   $($wf2.statecode) (1 = Activated)"
"Actions: $(($cd2.properties.definition.actions | Get-Member -MemberType NoteProperty | Select-Object -ExpandProperty Name) -join ', ')"
""
"Done. Send test email to rmarequest@D365DemoTSCE30330346.onmicrosoft.com to validate."
