# Patches the "RMA: Request Manager Approval" flow to:
#   1. Add Note_Approved (annotation on claim) after Write_history_Approved
#   2. Add Close_claim_after_denial after Mark_record_Denied
#   3. Add Note_Denied (annotation on claim) after Write_history_Denied
# All annotations have objectid_rma_claim@odata.bind, so they appear in the
# claim's Timeline natively.

$org    = 'https://org6feab6b5.crm.dynamics.com'
$flowId = '5d730ad8-1750-f111-a824-0022480a5e8d'
$token  = az account get-access-token --resource $org --query accessToken -o tsv
$h      = @{
  Authorization    = "Bearer $token"
  Accept           = 'application/json'
  'Content-Type'   = 'application/json'
  'OData-Version'  = '4.0'
  'OData-MaxVersion'= '4.0'
}

$wf = Invoke-RestMethod -Uri "$org/api/data/v9.2/workflows($flowId)?`$select=clientdata,statecode" -Headers $h
"Current state: $($wf.statecode)"

$cd = $wf.clientdata | ConvertFrom-Json -Depth 100
$loop = $cd.properties.definition.actions.For_each_approver_response.actions.Approval_outcome

# ── APPROVED BRANCH ─────────────────────────────────────────────
$noteApproved = [PSCustomObject]@{
  runAfter = @{ Write_history_Approved = @('Succeeded') }
  metadata = @{ operationMetadataId = 'cccccccc-aaaa-cccc-aaaa-cccccccccccc' }
  type     = 'OpenApiConnection'
  inputs   = @{
    host = @{
      connectionName = 'shared_commondataserviceforapps'
      operationId    = 'CreateRecord'
      apiId          = '/providers/Microsoft.PowerApps/apis/shared_commondataserviceforapps'
    }
    parameters = [ordered]@{
      entityName                          = 'annotations'
      'item/subject'                      = "@{concat('Approval response: APPROVED by ', coalesce(items('For_each_approver_response')?['responder/displayName'], 'manager'), ' - $', string(coalesce(triggerOutputs()?['body/rma_requestedamount'], 0)))}"
      'item/notetext'                     = "@{concat('Approval request APPROVED via Teams.', decodeUriComponent('%0A%0A'), 'Approver: ', coalesce(items('For_each_approver_response')?['responder/displayName'], 'unknown'), ' (', coalesce(items('For_each_approver_response')?['responder/userPrincipalName'], ''), ')', decodeUriComponent('%0A'), 'Decision date: ', string(outputs('Start_and_wait_for_an_approval')?['body/completionDate']), decodeUriComponent('%0A'), 'Amount: `$', string(coalesce(triggerOutputs()?['body/rma_requestedamount'], 0)), decodeUriComponent('%0A%0A'), 'Comments: ', coalesce(items('For_each_approver_response')?['comments'], '(no comments)'), decodeUriComponent('%0A%0A'), 'Claim has been closed automatically.')}"
      'item/objectid_rma_claim@odata.bind'= "@{concat('/rma_claims(', triggerOutputs()?['body/_rma_claim_value'], ')')}"
    }
    authentication = "@parameters('`$authentication')"
  }
}
$loop.actions | Add-Member -NotePropertyName 'Note_Approved' -NotePropertyValue $noteApproved -Force

# ── DENIED BRANCH ───────────────────────────────────────────────
$closeAfterDenial = [PSCustomObject]@{
  runAfter = @{ Mark_record_Denied = @('Succeeded') }
  metadata = @{ operationMetadataId = 'dddddddd-aaaa-dddd-aaaa-dddddddddddd' }
  type     = 'OpenApiConnection'
  inputs   = @{
    host = @{
      connectionName = 'shared_commondataserviceforapps'
      operationId    = 'UpdateOnlyRecord'
      apiId          = '/providers/Microsoft.PowerApps/apis/shared_commondataserviceforapps'
    }
    parameters = [ordered]@{
      entityName             = 'rma_claims'
      recordId               = "@triggerOutputs()?['body/_rma_claim_value']"
      'item/rma_status'      = 100000004   # Closed
      'item/rma_resolution'  = 100000003   # Denied
      'item/rma_closeddate'  = "@outputs('Start_and_wait_for_an_approval')?['body/completionDate']"
      'item/rma_haspendingresponse' = $false
      'item/statuscode'      = 2
      'item/statecode'       = 1
    }
    authentication = "@parameters('`$authentication')"
  }
}
$loop.else.actions | Add-Member -NotePropertyName 'Close_claim_after_denial' -NotePropertyValue $closeAfterDenial -Force

# Re-wire Write_history_Denied to run AFTER Close_claim_after_denial
$loop.else.actions.Write_history_Denied.runAfter = @{ Close_claim_after_denial = @('Succeeded') }

$noteDenied = [PSCustomObject]@{
  runAfter = @{ Write_history_Denied = @('Succeeded') }
  metadata = @{ operationMetadataId = 'eeeeeeee-aaaa-eeee-aaaa-eeeeeeeeeeee' }
  type     = 'OpenApiConnection'
  inputs   = @{
    host = @{
      connectionName = 'shared_commondataserviceforapps'
      operationId    = 'CreateRecord'
      apiId          = '/providers/Microsoft.PowerApps/apis/shared_commondataserviceforapps'
    }
    parameters = [ordered]@{
      entityName                          = 'annotations'
      'item/subject'                      = "@{concat('Approval response: DENIED by ', coalesce(items('For_each_approver_response')?['responder/displayName'], 'manager'), ' - $', string(coalesce(triggerOutputs()?['body/rma_requestedamount'], 0)))}"
      'item/notetext'                     = "@{concat('Approval request DENIED via Teams.', decodeUriComponent('%0A%0A'), 'Approver: ', coalesce(items('For_each_approver_response')?['responder/displayName'], 'unknown'), ' (', coalesce(items('For_each_approver_response')?['responder/userPrincipalName'], ''), ')', decodeUriComponent('%0A'), 'Decision date: ', string(outputs('Start_and_wait_for_an_approval')?['body/completionDate']), decodeUriComponent('%0A'), 'Amount: `$', string(coalesce(triggerOutputs()?['body/rma_requestedamount'], 0)), decodeUriComponent('%0A%0A'), 'Comments: ', coalesce(items('For_each_approver_response')?['comments'], '(no comments)'), decodeUriComponent('%0A%0A'), 'Claim has been closed as Denied.')}"
      'item/objectid_rma_claim@odata.bind'= "@{concat('/rma_claims(', triggerOutputs()?['body/_rma_claim_value'], ')')}"
    }
    authentication = "@parameters('`$authentication')"
  }
}
$loop.else.actions | Add-Member -NotePropertyName 'Note_Denied' -NotePropertyValue $noteDenied -Force

# ── PATCH workflow ──────────────────────────────────────────────
$newCd = $cd | ConvertTo-Json -Depth 100 -Compress
$body  = @{ clientdata = $newCd } | ConvertTo-Json -Compress -Depth 5
Invoke-RestMethod -Uri "$org/api/data/v9.2/workflows($flowId)" -Method Patch -Headers $h -Body $body
Write-Host "Flow PATCHed. Verify in maker UI:" -ForegroundColor Green
Write-Host "https://make.powerautomate.com/environments/<envid>/solutions" -ForegroundColor Cyan
