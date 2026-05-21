<#
.SYNOPSIS
    Phase B4: Create Power Automate flow that auto-assigns a plant to new
    rma_claim records based on routing rules.

    Logic:
      1. Trigger: when an rma_claim is created
      2. List rma_routingrule records where rma_isactive=true, ordered by priority
      3. For each rule, check if claim's rma_partnumber starts with rule's match value
      4. On first match, update rma_claim.rma_AssignedPlant to rule's plant
      5. Stop after first match

.NOTES
    The flow lives in the same environment as the rma tables.
    Connection reference used: bw_sharedcommondataserviceforapps_6fb4c
    (Bill's existing pre-authorized Dataverse connection)
#>

[CmdletBinding()]
param(
    [string]$EnvId = "2404ccaf-d7e5-e1ff-863a-3ecbe2f0f013"
)

$ErrorActionPreference = "Stop"

$paToken = (az account get-access-token --resource "https://service.flow.microsoft.com/" --query accessToken -o tsv)
if (-not $paToken) { throw "No PA token." }

# Get the rma_claim entity logical name + entitysetname
$orgUrl = "https://org6feab6b5.crm.dynamics.com"
$dvToken = (az account get-access-token --resource $orgUrl --query accessToken -o tsv)
$dvHdr = @{ Authorization = "Bearer $dvToken"; Accept = "application/json" }
$em = Invoke-RestMethod -Uri "$orgUrl/api/data/v9.2/EntityDefinitions(LogicalName='rma_claim')?`$select=LogicalName,LogicalCollectionName,ObjectTypeCode" -Headers $dvHdr
$rmaClaimEntitySet = $em.LogicalCollectionName    # rma_claims

# ---------------------------------------------------------------------------
# Build the flow definition
# ---------------------------------------------------------------------------
$flowName = "RMA Auto-Assign Plant"

$flowDefinition = @{
    "`$schema" = "https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#"
    contentVersion = "1.0.0.0"
    parameters = @{
        "`$connections" = @{
            defaultValue = @{}
            type = "Object"
        }
        "`$authentication" = @{
            defaultValue = @{}
            type = "SecureObject"
        }
    }
    triggers = @{
        "When_a_new_RMA_claim_is_created" = @{
            type = "OpenApiConnectionWebhook"
            inputs = @{
                host = @{
                    connectionName = "shared_commondataserviceforapps"
                    operationId    = "SubscribeWebhookTrigger"
                    apiId          = "/providers/Microsoft.PowerApps/apis/shared_commondataserviceforapps"
                }
                parameters = @{
                    subscriptionRequest = @{
                        message        = 1   # 1 = Create
                        entityname     = "rma_claim"
                        scope          = 4   # 4 = Organization
                        runas          = 1   # 1 = Owner (default flow owner)
                        filteringattributes = "rma_partnumber"
                    }
                }
                authentication = "@parameters('`$authentication')"
            }
        }
    }
    actions = @{
        "Initialize_PartNumber" = @{
            runAfter = @{}
            type = "InitializeVariable"
            inputs = @{
                variables = @(
                    @{
                        name  = "PartNumber"
                        type  = "string"
                        value = "@coalesce(triggerOutputs()?['body/rma_partnumber'], '')"
                    }
                )
            }
        }
        "Initialize_AssignedPlantId" = @{
            runAfter = @{ "Initialize_PartNumber" = @("Succeeded") }
            type = "InitializeVariable"
            inputs = @{
                variables = @(
                    @{
                        name  = "AssignedPlantId"
                        type  = "string"
                        value = ""
                    }
                )
            }
        }
        "List_Active_Routing_Rules" = @{
            runAfter = @{ "Initialize_AssignedPlantId" = @("Succeeded") }
            type = "OpenApiConnection"
            inputs = @{
                host = @{
                    connectionName = "shared_commondataserviceforapps"
                    operationId    = "ListRecords"
                    apiId          = "/providers/Microsoft.PowerApps/apis/shared_commondataserviceforapps"
                }
                parameters = @{
                    entityName    = "rma_routingrules"
                    "`$filter"    = "rma_isactive eq true"
                    "`$orderby"   = "rma_priority asc"
                    "`$select"    = "rma_name,rma_matchvalue,_rma_assignedplant_value"
                }
                authentication = "@parameters('`$authentication')"
            }
        }
        "For_each_rule" = @{
            runAfter = @{ "List_Active_Routing_Rules" = @("Succeeded") }
            type = "Foreach"
            foreach = "@outputs('List_Active_Routing_Rules')?['body/value']"
            actions = @{
                "Skip_if_already_matched" = @{
                    type = "If"
                    expression = @{
                        equals = @("@variables('AssignedPlantId')", "")
                    }
                    actions = @{
                        "Check_prefix_match" = @{
                            type = "If"
                            expression = @{
                                and = @(
                                    @{
                                        greater = @("@length(coalesce(items('For_each_rule')?['rma_matchvalue'], ''))", 0)
                                    },
                                    @{
                                        startsWith = @(
                                            "@toUpper(variables('PartNumber'))",
                                            "@toUpper(items('For_each_rule')?['rma_matchvalue'])"
                                        )
                                    }
                                )
                            }
                            actions = @{
                                "Set_AssignedPlantId" = @{
                                    type = "SetVariable"
                                    inputs = @{
                                        name  = "AssignedPlantId"
                                        value = "@items('For_each_rule')?['_rma_assignedplant_value']"
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        "Update_RMA_Claim" = @{
            runAfter = @{ "For_each_rule" = @("Succeeded") }
            type = "If"
            expression = @{
                and = @(
                    @{ not = @( @{ equals = @("@variables('AssignedPlantId')", "") } ) }
                )
            }
            actions = @{
                "Update_a_row" = @{
                    type = "OpenApiConnection"
                    inputs = @{
                        host = @{
                            connectionName = "shared_commondataserviceforapps"
                            operationId    = "UpdateRecord"
                            apiId          = "/providers/Microsoft.PowerApps/apis/shared_commondataserviceforapps"
                        }
                        parameters = @{
                            entityName = "rma_claims"
                            recordId   = "@triggerOutputs()?['body/rma_claimid']"
                            item       = @{
                                "rma_AssignedPlant@odata.bind" = "/rma_plants(@{variables('AssignedPlantId')})"
                            }
                        }
                        authentication = "@parameters('`$authentication')"
                    }
                }
            }
        }
    }
}

# ---------------------------------------------------------------------------
# Connection references
# ---------------------------------------------------------------------------
$connRefs = @{
    "shared_commondataserviceforapps" = @{
        connectionName                 = "shared-commondataser-9933c9ef-b98c-4170-8251-695bb41a22f2"
        connectionReferenceLogicalName = "bw_sharedcommondataserviceforapps_6fb4c"
        source                         = "Embedded"
        id                             = "/providers/Microsoft.PowerApps/apis/shared_commondataserviceforapps"
        displayName                    = "Microsoft Dataverse"
        iconUri                        = "https://connectoricons-prod.azureedge.net/releases/v1.0.1681/1.0.1681.3668/commondataserviceforapps/icon.png"
        brandColor                     = "#001B69"
        tier                           = "Standard"
        apiName                        = "commondataserviceforapps"
        isProcessSimpleApiReferenceConversionAlreadyDone = $false
    }
}

# ---------------------------------------------------------------------------
# Create the flow
# ---------------------------------------------------------------------------
Write-Host "`n=== Phase B4: RMA Auto-Assign Plant Power Automate flow ===`n" -ForegroundColor Cyan

$paHdr = @{ Authorization = "Bearer $paToken"; "Content-Type" = "application/json" }

$createBody = @{
    properties = @{
        displayName          = $flowName
        definition           = $flowDefinition
        connectionReferences = $connRefs
        state                = "Stopped"   # Create stopped; activate after
    }
}

$uri = "https://api.flow.microsoft.com/providers/Microsoft.ProcessSimple/environments/$EnvId/flows?api-version=2016-11-01"

try {
    $resp = Invoke-RestMethod -Uri $uri -Method Post -Headers $paHdr -Body ($createBody | ConvertTo-Json -Depth 50 -Compress) -ErrorAction Stop
    $flowId = $resp.name
    Write-Host "  [create] flow '$flowName' -> $flowId" -ForegroundColor Green
} catch {
    $m = $_.Exception.Message
    if ($_.ErrorDetails.Message) { $m = $_.ErrorDetails.Message }
    Write-Host "  [FAIL] $m" -ForegroundColor Red
    throw
}

# ---------------------------------------------------------------------------
# Turn it ON
# ---------------------------------------------------------------------------
Write-Host "  Activating flow..." -ForegroundColor Cyan
$turnOnUri = "https://api.flow.microsoft.com/providers/Microsoft.ProcessSimple/environments/$EnvId/flows/$flowId/start?api-version=2016-11-01"
try {
    Invoke-RestMethod -Uri $turnOnUri -Method Post -Headers $paHdr -Body "{}" -ErrorAction Stop | Out-Null
    Write-Host "  [ok] flow activated" -ForegroundColor Green
} catch {
    $m = $_.Exception.Message
    if ($_.ErrorDetails.Message) { $m = $_.ErrorDetails.Message }
    Write-Host "  [warn] could not activate via API — turn ON in the UI: $m" -ForegroundColor DarkYellow
}

Write-Host "`n=== DONE ===" -ForegroundColor Cyan
Write-Host "Flow URL:" -ForegroundColor Yellow
Write-Host "  https://make.powerautomate.com/environments/$EnvId/flows/$flowId/details"
Write-Host ""
Write-Host "Test:" -ForegroundColor Yellow
Write-Host "  Create a new RMA claim with part number 'WTB-MOTOR-1234'"
Write-Host "  → flow fires → claim should be auto-assigned to Waterbury CT"
