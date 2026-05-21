# clone_push_resolution_to_erp.ps1
#
# Creates the "RMA: Push Resolution to ERP (stub)" PA flow.
#
# Trigger:   rma_approvalhistory row added with rma_erpstatus = 100000001 (Pending)
# Actions:
#   1. Get the parent rma_claim for context
#   2. Compose a JSON payload (claim number, customer, plant, action, amounts, override info, operator)
#   3. STUB — generate a fake reference id (real implementation would HTTP POST to Navision /
#      Business Central / SAP / etc. — placeholder commented out below)
#   4. PATCH the rma_approvalhistory row -> rma_erpstatus = 100000002 (Sent),
#      rma_erpreference = <ref>, rma_erppayload = <json>
#
# How to swap stub for a real Navision push:
#   * In the action "Push_to_ERP_STUB", replace the Compose with an HTTP action
#   * Set Method = POST, URI = https://<your-bc-onprem-gateway>/api/v2.0/...
#   * Headers: Authorization = Bearer ... (use a connection reference for OAuth)
#   * Body = @{outputs('Build_ERP_payload')}
#   * Bind the returned doc id to the Update_history_row -> rma_erpreference field
#
# Reuses connection refs from existing RMA flows.

[CmdletBinding()]
param(
    [string]$OrgUrl  = "https://org6feab6b5.crm.dynamics.com",
    [switch]$Activate,
    [switch]$Force
)

$ErrorActionPreference = "Stop"

$token = az account get-access-token --resource $OrgUrl --query accessToken -o tsv
if (-not $token) { throw "Could not get Dataverse token. Run 'az login' first." }

$hdrGet = @{ Authorization = "Bearer $token"; Accept = "application/json" }
$hdrPP  = @{
    Authorization      = "Bearer $token"
    Accept             = "application/json"
    "Content-Type"     = "application/json"
    "OData-MaxVersion" = "4.0"
    "OData-Version"    = "4.0"
    Prefer             = "return=representation"
}

$flowName       = "RMA: Push Resolution to ERP (stub)"
$flowUniqueName = "rma_pushresolutiontoerpstub"

$existing = (Invoke-RestMethod -Uri "$OrgUrl/api/data/v9.2/workflows?`$filter=name eq '$flowName' or uniquename eq '$flowUniqueName'&`$select=name,workflowid,statecode" -Headers $hdrGet).value
if ($existing) {
    if ($Force) {
        foreach ($w in $existing) {
            Write-Host "Deleting existing flow $($w.name) [$($w.workflowid)]..." -ForegroundColor Yellow
            if ($w.statecode -eq 1) {
                Invoke-WebRequest -Method PATCH -Uri "$OrgUrl/api/data/v9.2/workflows($($w.workflowid))" -Headers $hdrPP -Body '{"statecode":0,"statuscode":1}' -UseBasicParsing | Out-Null
            }
            Invoke-WebRequest -Method DELETE -Uri "$OrgUrl/api/data/v9.2/workflows($($w.workflowid))" -Headers $hdrGet -UseBasicParsing | Out-Null
        }
    } else {
        Write-Host "Flow exists ($($existing[0].workflowid)). Re-run with -Force to recreate." -ForegroundColor Yellow
        return
    }
}

$clientData = @'
{
  "properties": {
    "connectionReferences": {
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
        "When_approvalhistory_row_added_pending_ERP": {
          "metadata": { "operationMetadataId": "aaaa1111-bbbb-1111-cccc-111111111111" },
          "type": "OpenApiConnectionWebhook",
          "inputs": {
            "host": {
              "connectionName": "shared_commondataserviceforapps",
              "operationId": "SubscribeWebhookTrigger",
              "apiId": "/providers/Microsoft.PowerApps/apis/shared_commondataserviceforapps"
            },
            "parameters": {
              "subscriptionRequest/message": 1,
              "subscriptionRequest/entityname": "rma_approvalhistory",
              "subscriptionRequest/scope": 4,
              "subscriptionRequest/filteringattributes": "rma_erpstatus"
            },
            "authentication": "@parameters('$authentication')"
          }
        }
      },
      "actions": {
        "Only_if_status_is_Pending": {
          "runAfter": {},
          "type": "If",
          "expression": {
            "equals": [ "@triggerOutputs()?['body/rma_erpstatus']", 100000001 ]
          },
          "actions": {
            "Get_related_claim": {
              "runAfter": {},
              "metadata": { "operationMetadataId": "aaaa2222-bbbb-2222-cccc-222222222222" },
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
            "Build_ERP_payload": {
              "runAfter": { "Get_related_claim": [ "Succeeded" ] },
              "type": "Compose",
              "inputs": {
                "claimNumber": "@{outputs('Get_related_claim')?['body/rma_claimnumber']}",
                "customer": "@{outputs('Get_related_claim')?['body/rma_customername']}",
                "customerEmail": "@{outputs('Get_related_claim')?['body/rma_customeremail']}",
                "plant": "@{outputs('Get_related_claim')?['body/_rma_assignedplant_value@OData.Community.Display.V1.FormattedValue']}",
                "partNumber": "@{outputs('Get_related_claim')?['body/rma_partnumber']}",
                "actionCode": "@triggerOutputs()?['body/rma_action']",
                "actionLabel": "@{triggerOutputs()?['body/rma_action@OData.Community.Display.V1.FormattedValue']}",
                "amount": "@triggerOutputs()?['body/rma_amount']",
                "amountOriginal": "@triggerOutputs()?['body/rma_amountoriginal']",
                "amountOverridden": "@triggerOutputs()?['body/rma_amountoverridden']",
                "overrideReason": "@{triggerOutputs()?['body/rma_overridereason']}",
                "operator": "@{triggerOutputs()?['body/_createdby_value@OData.Community.Display.V1.FormattedValue']}",
                "timestamp": "@utcNow()"
              }
            },
            "Push_to_ERP_STUB": {
              "runAfter": { "Build_ERP_payload": [ "Succeeded" ] },
              "type": "Compose",
              "description": "STUB — replace with HTTP action targeting Navision / Business Central / SAP. See script header for the swap-out pattern.",
              "inputs": {
                "ref": "@{concat('STUB-NAV-', substring(replace(guid(), '-', ''), 0, 12))}",
                "status": "ok",
                "note": "Replace this Compose with an HTTP action that POSTs outputs('Build_ERP_payload') to the real ERP endpoint."
              }
            },
            "Update_history_row_Sent": {
              "runAfter": { "Push_to_ERP_STUB": [ "Succeeded" ] },
              "type": "OpenApiConnection",
              "inputs": {
                "host": {
                  "connectionName": "shared_commondataserviceforapps",
                  "operationId": "UpdateOnlyRecord",
                  "apiId": "/providers/Microsoft.PowerApps/apis/shared_commondataserviceforapps"
                },
                "parameters": {
                  "entityName": "rma_approvalhistories",
                  "recordId": "@triggerOutputs()?['body/rma_approvalhistoryid']",
                  "item/rma_erpstatus": 100000002,
                  "item/rma_erpreference": "@{outputs('Push_to_ERP_STUB')?['ref']}",
                  "item/rma_erppayload": "@{string(outputs('Build_ERP_payload'))}"
                },
                "authentication": "@parameters('$authentication')"
              }
            }
          },
          "else": {
            "actions": {}
          }
        }
      }
    }
  },
  "schemaVersion": "1.0.0.0"
}
'@

$body = @{
    name                = $flowName
    uniquename          = $flowUniqueName
    category            = 5  # Modern Cloud Flow
    type                = 1  # Definition
    primaryentity       = "none"
    clientdata          = $clientData
    statecode           = 0
    statuscode          = 1
} | ConvertTo-Json -Depth 50 -Compress

Write-Host "Creating flow '$flowName'..." -ForegroundColor Cyan
$resp = Invoke-RestMethod -Method POST -Uri "$OrgUrl/api/data/v9.2/workflows" -Headers $hdrPP -Body $body
$flowId = $resp.workflowid
Write-Host "Created workflow $flowId" -ForegroundColor Green

if ($Activate) {
    Write-Host "Activating..." -ForegroundColor Cyan
    Invoke-WebRequest -Method PATCH -Uri "$OrgUrl/api/data/v9.2/workflows($flowId)" -Headers $hdrPP -Body '{"statecode":1,"statuscode":2}' -UseBasicParsing | Out-Null
    Write-Host "Activated." -ForegroundColor Green
}

Write-Host ""
Write-Host "NEXT STEPS (REQUIRED for trigger to fire):" -ForegroundColor Yellow
Write-Host "  1. Open https://make.powerautomate.com -> My flows -> '$flowName'"
Write-Host "  2. Click Edit, then click Save (no changes needed)."
Write-Host "     This registers the Dataverse trigger webhook (REST POST does NOT)."
Write-Host "  3. Smoke test: in the pizza tracker, do an 'Issue Credit' action -> within ~30s"
Write-Host "     the new rma_approvalhistory row's rma_erpstatus should flip Pending -> Sent"
Write-Host "     and rma_erpreference should populate with STUB-NAV-xxxxxxxxxxxx."
Write-Host ""
Write-Host "To wire the real Navision call, see script header." -ForegroundColor DarkGray
