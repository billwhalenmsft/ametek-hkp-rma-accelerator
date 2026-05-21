# clone_request_manager_approval_for_rma.ps1
#
# Clones the existing "Request Manager Approval for Claim" PA flow
# (workflow 8ce6f8e5-196f-f011-b4cc-7ced8d6eb30e) and retargets it
# for the new RMA Returns Monitor schema:
#
#   trigger:  rma_approvalrecord row added
#   gets:     rma_claim (parent), active rma_plantapprovers for the claim's plant
#             honoring rma_notifywhen (All Claims | High Value Only) and rma_highvaluethreshold:
#               - All Claims (100000000)         -> always notified
#               - High Value Only (100000001)    -> notified only when requested amount >= threshold
#               - Manual Only (100000002)        -> never auto-notified by this flow
#   approval: Microsoft Approvals connector (Teams Approvals app + email)
#   approve:  set rma_approvalrecord -> Approved, close rma_claim, write rma_approvalhistory (Approved, viaTeams=true)
#   deny:     set rma_approvalrecord -> Denied, leave claim open at Decision, write rma_approvalhistory (Denied, viaTeams=true)
#
# Reuses the connection references from the source flow so connections work
# without further configuration:
#   shared_approvals                      -> cr74e_sharedapprovals_453c9
#   shared_commondataserviceforapps-1     -> cr74e_warrantyClaimProcessingForEmail.shared_commondataserviceforapps...

[CmdletBinding()]
param(
    [string]$OrgUrl    = "https://org6feab6b5.crm.dynamics.com",
    [string]$AppModuleId = "8661f960-1f4e-f111-bec6-000d3a5aed87",   # RMA Operations and Monitoring
    [string]$RequestorEmail = "admin@D365DemoTSCE30330346.onmicrosoft.com",
    [string]$FallbackApprover = "admin@D365DemoTSCE30330346.onmicrosoft.com",
    [switch]$Activate,
    [switch]$Force                # delete + recreate if already present
)

$ErrorActionPreference = "Stop"

$token = az account get-access-token --resource $OrgUrl --query accessToken -o tsv
if (-not $token) { throw "Could not get Dataverse token. Run 'az login' first." }

$hdrGet = @{ Authorization = "Bearer $token"; Accept = "application/json" }
$hdrPostPatch = @{
    Authorization      = "Bearer $token"
    Accept             = "application/json"
    "Content-Type"     = "application/json"
    "OData-MaxVersion" = "4.0"
    "OData-Version"    = "4.0"
    Prefer             = "return=representation"
}

$flowName       = "RMA: Request Manager Approval"
$flowUniqueName = "rma_requestmanagerapprovalforclaim"

# ---- 1. Look for an existing flow with the same name; delete if -Force ----
$existing = (Invoke-RestMethod -Uri "$OrgUrl/api/data/v9.2/workflows?`$filter=name eq '$flowName' or uniquename eq '$flowUniqueName'&`$select=name,workflowid,statecode" -Headers $hdrGet).value
if ($existing) {
    if ($Force) {
        foreach ($w in $existing) {
            Write-Host "Deleting existing flow $($w.name) [$($w.workflowid)] ..." -ForegroundColor Yellow
            if ($w.statecode -eq 1) {
                Invoke-WebRequest -Method PATCH -Uri "$OrgUrl/api/data/v9.2/workflows($($w.workflowid))" -Headers $hdrPostPatch -Body '{"statecode":0,"statuscode":1}' -UseBasicParsing | Out-Null
            }
            Invoke-WebRequest -Method DELETE -Uri "$OrgUrl/api/data/v9.2/workflows($($w.workflowid))" -Headers $hdrGet -UseBasicParsing | Out-Null
        }
    }
    else {
        Write-Host "Flow already exists ($($existing[0].workflowid)). Re-run with -Force to recreate." -ForegroundColor Yellow
        return
    }
}

# ---- 2. Build the clientdata definition ----
# Substitution placeholders are replaced AFTER the here-string so PS doesn't try to expand $foo / $bar inside expressions.
$clientDataTemplate = @'
{
  "properties": {
    "connectionReferences": {
      "shared_approvals": {
        "runtimeSource": "embedded",
        "connection": { "connectionReferenceLogicalName": "cr74e_sharedapprovals_453c9" },
        "api": { "name": "shared_approvals" }
      },
      "shared_commondataserviceforapps": {
        "runtimeSource": "embedded",
        "connection": { "connectionReferenceLogicalName": "cr74e_warrantyChecker.shared_commondataserviceforapps.shared-commondataser-9933c9ef-b98c-4170-8251-695bb41a22f2" },
        "api": { "name": "shared_commondataserviceforapps" }
      }
    },
    "definition": {
      "$schema": "https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#",
      "contentVersion": "1.0.0.0",
      "parameters": {
        "$connections": { "defaultValue": {}, "type": "Object" },
        "$authentication": { "defaultValue": {}, "type": "SecureObject" }
      },
      "triggers": {
        "When_an_approval_record_is_added": {
          "metadata": { "operationMetadataId": "11111111-aaaa-1111-aaaa-111111111111" },
          "type": "OpenApiConnectionWebhook",
          "inputs": {
            "host": {
              "connectionName": "shared_commondataserviceforapps",
              "operationId": "SubscribeWebhookTrigger",
              "apiId": "/providers/Microsoft.PowerApps/apis/shared_commondataserviceforapps"
            },
            "parameters": {
              "subscriptionRequest/message": 1,
              "subscriptionRequest/entityname": "rma_approvalrecord",
              "subscriptionRequest/scope": 4
            },
            "authentication": "@parameters('$authentication')"
          }
        }
      },
      "actions": {
        "Get_related_RMA_claim": {
          "runAfter": {},
          "metadata": { "operationMetadataId": "22222222-aaaa-2222-aaaa-222222222222" },
          "type": "OpenApiConnection",
          "inputs": {
            "host": {
              "connectionName": "shared_commondataserviceforapps",
              "operationId": "GetItem",
              "apiId": "/providers/Microsoft.PowerApps/apis/shared_commondataserviceforapps"
            },
            "parameters": {
              "entityName": "rma_claims",
              "recordId": "@triggerOutputs()?['body/_rma_claim_value']"
            },
            "authentication": "@parameters('$authentication')"
          }
        },
        "List_active_plant_approvers": {
          "runAfter": { "Get_related_RMA_claim": [ "Succeeded" ] },
          "metadata": { "operationMetadataId": "33333333-aaaa-3333-aaaa-333333333333" },
          "type": "OpenApiConnection",
          "inputs": {
            "host": {
              "connectionName": "shared_commondataserviceforapps",
              "operationId": "ListRecords",
              "apiId": "/providers/Microsoft.PowerApps/apis/shared_commondataserviceforapps"
            },
            "parameters": {
              "entityName": "rma_plantapprovers",
              "$filter": "@{concat('_rma_plant_value eq ', coalesce(outputs('Get_related_RMA_claim')?['body/_rma_assignedplant_value'], '00000000-0000-0000-0000-000000000000'), ' and rma_isactive eq true and (rma_notifywhen eq 100000000 or (rma_notifywhen eq 100000001 and rma_highvaluethreshold le ', string(coalesce(triggerOutputs()?['body/rma_requestedamount'], 0)), '))')}",
              "$select": "rma_teamsupn,rma_email,rma_name,rma_role,rma_notifywhen,rma_highvaluethreshold"
            },
            "authentication": "@parameters('$authentication')"
          }
        },
        "Compose_Approver_List": {
          "runAfter": { "List_active_plant_approvers": [ "Succeeded" ] },
          "metadata": { "operationMetadataId": "44444444-aaaa-4444-aaaa-444444444444" },
          "type": "Compose",
          "inputs": "@if(greater(length(outputs('List_active_plant_approvers')?['body/value']), 0), join(xpath(xml(json(concat('{\"u\":', string(outputs('List_active_plant_approvers')?['body/value']), '}'))), '//rma_teamsupn/text()'), ';'), '__FALLBACK_APPROVER__')"
        },
        "Update_claim_status_to_Decision": {
          "runAfter": { "Compose_Approver_List": [ "Succeeded" ] },
          "metadata": { "operationMetadataId": "55555555-aaaa-5555-aaaa-555555555555" },
          "type": "OpenApiConnection",
          "inputs": {
            "host": {
              "connectionName": "shared_commondataserviceforapps",
              "operationId": "UpdateOnlyRecord",
              "apiId": "/providers/Microsoft.PowerApps/apis/shared_commondataserviceforapps"
            },
            "parameters": {
              "entityName": "rma_claims",
              "recordId": "@triggerOutputs()?['body/_rma_claim_value']",
              "item/rma_status": 100000003
            },
            "authentication": "@parameters('$authentication')"
          }
        },
        "Start_and_wait_for_an_approval": {
          "runAfter": { "Update_claim_status_to_Decision": [ "Succeeded" ] },
          "metadata": { "operationMetadataId": "66666666-aaaa-6666-aaaa-666666666666" },
          "type": "OpenApiConnectionWebhook",
          "inputs": {
            "host": {
              "connectionName": "shared_approvals",
              "operationId": "StartAndWaitForAnApproval",
              "apiId": "/providers/Microsoft.PowerApps/apis/shared_approvals"
            },
            "parameters": {
              "approvalType": "Basic",
              "WebhookApprovalCreationInput/title": "@{concat('RMA Claim ', coalesce(outputs('Get_related_RMA_claim')?['body/rma_claimnumber'], 'unknown'), ' needs approval - $', string(coalesce(triggerOutputs()?['body/rma_requestedamount'], 0)))}",
              "WebhookApprovalCreationInput/assignedTo": "@{outputs('Compose_Approver_List')}",
              "WebhookApprovalCreationInput/details": "@{concat('Please review this RMA claim:', decodeUriComponent('%0A%0A'), 'Claim: ', coalesce(outputs('Get_related_RMA_claim')?['body/rma_claimnumber'], ''), decodeUriComponent('%0A'), 'Requested credit: $', string(coalesce(triggerOutputs()?['body/rma_requestedamount'], 0)), decodeUriComponent('%0A'), 'Plant threshold: $', string(coalesce(triggerOutputs()?['body/rma_thresholdamount'], 0)), decodeUriComponent('%0A'), 'Reason: ', coalesce(triggerOutputs()?['body/rma_requestreason'], '(none provided)'))}",
              "WebhookApprovalCreationInput/itemLink": "@{concat('__ORG_URL__', '/main.aspx?appid=__APP_ID__&pagetype=entityrecord&etn=rma_claim&id=', triggerOutputs()?['body/_rma_claim_value'])}",
              "WebhookApprovalCreationInput/itemLinkDescription": "Open RMA Claim in D365",
              "WebhookApprovalCreationInput/requestor": "__REQUESTOR_EMAIL__",
              "WebhookApprovalCreationInput/enableNotifications": true,
              "WebhookApprovalCreationInput/enableReassignment": true
            },
            "authentication": "@parameters('$authentication')"
          }
        },
        "For_each_approver_response": {
          "foreach": "@outputs('Start_and_wait_for_an_approval')?['body/responses']",
          "actions": {
            "Approval_outcome": {
              "actions": {
                "Mark_record_Approved": {
                  "runAfter": {},
                  "metadata": { "operationMetadataId": "77777777-aaaa-7777-aaaa-777777777777" },
                  "type": "OpenApiConnection",
                  "inputs": {
                    "host": {
                      "connectionName": "shared_commondataserviceforapps",
                      "operationId": "UpdateOnlyRecord",
                      "apiId": "/providers/Microsoft.PowerApps/apis/shared_commondataserviceforapps"
                    },
                    "parameters": {
                      "entityName": "rma_approvalrecords",
                      "recordId": "@triggerOutputs()?['body/rma_approvalrecordid']",
                      "item/rma_approvalstatus": 100000001,
                      "item/rma_approvaldate": "@outputs('Start_and_wait_for_an_approval')?['body/completionDate']",
                      "item/rma_approvalnotes": "@items('For_each_approver_response')?['comments']",
                      "item/rma_approvername": "@items('For_each_approver_response')?['responder/displayName']"
                    },
                    "authentication": "@parameters('$authentication')"
                  }
                },
                "Close_claim_after_approval": {
                  "runAfter": { "Mark_record_Approved": [ "Succeeded" ] },
                  "metadata": { "operationMetadataId": "88888888-aaaa-8888-aaaa-888888888888" },
                  "type": "OpenApiConnection",
                  "inputs": {
                    "host": {
                      "connectionName": "shared_commondataserviceforapps",
                      "operationId": "UpdateOnlyRecord",
                      "apiId": "/providers/Microsoft.PowerApps/apis/shared_commondataserviceforapps"
                    },
                    "parameters": {
                      "entityName": "rma_claims",
                      "recordId": "@triggerOutputs()?['body/_rma_claim_value']",
                      "item/rma_status": 100000004,
                      "item/statuscode": 2,
                      "item/statecode": 1
                    },
                    "authentication": "@parameters('$authentication')"
                  }
                },
                "Write_history_Approved": {
                  "runAfter": { "Close_claim_after_approval": [ "Succeeded" ] },
                  "metadata": { "operationMetadataId": "99999999-aaaa-9999-aaaa-999999999999" },
                  "type": "OpenApiConnection",
                  "inputs": {
                    "host": {
                      "connectionName": "shared_commondataserviceforapps",
                      "operationId": "CreateRecord",
                      "apiId": "/providers/Microsoft.PowerApps/apis/shared_commondataserviceforapps"
                    },
                    "parameters": {
                      "entityName": "rma_approvalhistories",
                      "item/rma_name": "@{concat('Approved: ', coalesce(outputs('Get_related_RMA_claim')?['body/rma_claimnumber'], ''))}",
                      "item/rma_action": 100000001,
                      "item/rma_actionby": "@items('For_each_approver_response')?['responder/displayName']",
                      "item/rma_actionbyupn": "@items('For_each_approver_response')?['responder/userPrincipalName']",
                      "item/rma_actiondate": "@outputs('Start_and_wait_for_an_approval')?['body/completionDate']",
                      "item/rma_comments": "@items('For_each_approver_response')?['comments']",
                      "item/rma_previousstatus": "Decision",
                      "item/rma_newstatus": "Closed",
                      "item/rma_viateams": true,
                      "item/rma_Claim@odata.bind": "@{concat('/rma_claims(', triggerOutputs()?['body/_rma_claim_value'], ')')}"
                    },
                    "authentication": "@parameters('$authentication')"
                  }
                }
              },
              "runAfter": {},
              "else": {
                "actions": {
                  "Mark_record_Denied": {
                    "runAfter": {},
                    "metadata": { "operationMetadataId": "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa" },
                    "type": "OpenApiConnection",
                    "inputs": {
                      "host": {
                        "connectionName": "shared_commondataserviceforapps",
                        "operationId": "UpdateOnlyRecord",
                        "apiId": "/providers/Microsoft.PowerApps/apis/shared_commondataserviceforapps"
                      },
                      "parameters": {
                        "entityName": "rma_approvalrecords",
                        "recordId": "@triggerOutputs()?['body/rma_approvalrecordid']",
                        "item/rma_approvalstatus": 100000002,
                        "item/rma_approvaldate": "@outputs('Start_and_wait_for_an_approval')?['body/completionDate']",
                        "item/rma_approvalnotes": "@items('For_each_approver_response')?['comments']",
                        "item/rma_approvername": "@items('For_each_approver_response')?['responder/displayName']"
                      },
                      "authentication": "@parameters('$authentication')"
                    }
                  },
                  "Write_history_Denied": {
                    "runAfter": { "Mark_record_Denied": [ "Succeeded" ] },
                    "metadata": { "operationMetadataId": "bbbbbbbb-aaaa-bbbb-aaaa-bbbbbbbbbbbb" },
                    "type": "OpenApiConnection",
                    "inputs": {
                      "host": {
                        "connectionName": "shared_commondataserviceforapps",
                        "operationId": "CreateRecord",
                        "apiId": "/providers/Microsoft.PowerApps/apis/shared_commondataserviceforapps"
                      },
                      "parameters": {
                        "entityName": "rma_approvalhistories",
                        "item/rma_name": "@{concat('Denied: ', coalesce(outputs('Get_related_RMA_claim')?['body/rma_claimnumber'], ''))}",
                        "item/rma_action": 100000002,
                        "item/rma_actionby": "@items('For_each_approver_response')?['responder/displayName']",
                        "item/rma_actionbyupn": "@items('For_each_approver_response')?['responder/userPrincipalName']",
                        "item/rma_actiondate": "@outputs('Start_and_wait_for_an_approval')?['body/completionDate']",
                        "item/rma_comments": "@items('For_each_approver_response')?['comments']",
                        "item/rma_previousstatus": "Decision",
                        "item/rma_newstatus": "Decision",
                        "item/rma_viateams": true,
                        "item/rma_Claim@odata.bind": "@{concat('/rma_claims(', triggerOutputs()?['body/_rma_claim_value'], ')')}"
                      },
                      "authentication": "@parameters('$authentication')"
                    }
                  }
                }
              },
              "expression": {
                "equals": [ "@items('For_each_approver_response')?['approverResponse']", "Approve" ]
              },
              "metadata": { "operationMetadataId": "cccccccc-aaaa-cccc-aaaa-cccccccccccc" },
              "type": "If"
            }
          },
          "runAfter": { "Start_and_wait_for_an_approval": [ "Succeeded" ] },
          "metadata": { "operationMetadataId": "dddddddd-aaaa-dddd-aaaa-dddddddddddd" },
          "type": "Foreach"
        }
      }
    }
  },
  "schemaVersion": "1.0.0.0"
}
'@

$clientData = $clientDataTemplate `
    -replace '__ORG_URL__', $OrgUrl `
    -replace '__APP_ID__', $AppModuleId `
    -replace '__REQUESTOR_EMAIL__', $RequestorEmail `
    -replace '__FALLBACK_APPROVER__', $FallbackApprover

# Sanity: ensure it's still valid JSON after substitution
try { $null = $clientData | ConvertFrom-Json -ErrorAction Stop } catch { Write-Host $clientData; throw "Generated clientdata is not valid JSON: $_" }

# ---- 3. POST as a draft modern flow ----
$body = @{
    name         = $flowName
    uniquename   = $flowUniqueName
    category     = 5                # 5 = Modern Flow / Cloud Flow
    type         = 1                # 1 = Definition
    primaryentity= "none"
    statecode    = 0
    statuscode   = 1
    clientdata   = $clientData
} | ConvertTo-Json -Depth 30 -Compress

Write-Host "Creating new flow '$flowName' ..." -ForegroundColor Cyan
$resp = Invoke-WebRequest -Method POST -Uri "$OrgUrl/api/data/v9.2/workflows" -Headers $hdrPostPatch -Body $body -UseBasicParsing
$newFlow = $resp.Content | ConvertFrom-Json
$newId = $newFlow.workflowid
Write-Host "  Created. workflowid = $newId" -ForegroundColor Green

# ---- 4. Activate if requested ----
if ($Activate) {
    Write-Host "Activating flow ..." -ForegroundColor Cyan
    Invoke-WebRequest -Method PATCH -Uri "$OrgUrl/api/data/v9.2/workflows($newId)" -Headers $hdrPostPatch -Body '{"statecode":1,"statuscode":2}' -UseBasicParsing | Out-Null
    $check = (Invoke-RestMethod -Uri "$OrgUrl/api/data/v9.2/workflows($newId)?`$select=name,statecode,statuscode" -Headers $hdrGet)
    Write-Host "  statecode=$($check.statecode) statuscode=$($check.statuscode) (expect 1/2)" -ForegroundColor Green
} else {
    Write-Host "Created as DRAFT. Re-run with -Activate to turn it on (or activate in maker UI)." -ForegroundColor Yellow
}

Write-Host ""
Write-Host "Direct link: https://make.powerautomate.com/environments/2404ccaf-d7e5-e1ff-863a-3ecbe2f0f013/solutions/Default/flows/$newId/details" -ForegroundColor DarkGray
