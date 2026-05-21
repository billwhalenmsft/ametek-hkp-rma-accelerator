/*
 * HKP RMA — Form command library
 *
 * Loaded onto rma_claim main form. Provides functions wired by modern
 * command buttons in the form ribbon.
 *
 * Web resource: rma_/scripts/hkp_rma_form_commands.js
 *
 * Public surface:
 *   HKPCommands.resolveCredit(formContext)
 *   HKPCommands.resolveReplacement(formContext)
 *   HKPCommands.resolveRepair(formContext)
 *   HKPCommands.denyClaim(formContext)
 *   HKPCommands.sendCustomerEmail(formContext)
 *   HKPCommands.requestManagerApproval(formContext)
 *
 * Convention: each handler is async, returns a promise. Modern command
 * buttons call them via "X is enabled" + "X is visible" rules + onClick.
 *
 * Picklist values (rma_claim):
 *   rma_status     100000000 New, 100000001 Triage, 100000002 Investigation,
 *                  100000003 Decision, 100000004 Closed
 *   rma_resolution 100000000 Credit Issued, 100000001 Replacement Sent,
 *                  100000002 Repair Completed, 100000003 Claim Denied
 */

"use strict";

if (typeof window.HKPCommands === "undefined") {
    window.HKPCommands = {};
}

(function (HKP) {

    var RESOLUTION = {
        CREDIT:      100000000,
        REPLACEMENT: 100000001,
        REPAIR:      100000002,
        DENIED:      100000003
    };
    var STATUS_CLOSED = 100000004;

    // ------------------------------------------------------------------
    // Helpers
    // ------------------------------------------------------------------

    function getXrm() {
        if (typeof Xrm !== "undefined") return Xrm;
        if (typeof window.parent !== "undefined" && window.parent.Xrm) return window.parent.Xrm;
        return null;
    }

    function alertDialog(msg, title) {
        var xrm = getXrm();
        if (!xrm) { alert(msg); return Promise.resolve(); }
        return xrm.Navigation.openAlertDialog({ text: msg, title: title || "RMA" });
    }

    function confirmDialog(msg, title) {
        var xrm = getXrm();
        if (!xrm) return Promise.resolve({ confirmed: window.confirm(msg) });
        return xrm.Navigation.openConfirmDialog({ text: msg, title: title || "Confirm", confirmButtonLabel: "Yes", cancelButtonLabel: "No" });
    }

    function promptDialog(label, title) {
        var xrm = getXrm();
        if (!xrm) return Promise.resolve(window.prompt(label));
        return xrm.Navigation.openErrorDialog({ message: label, details: title }).then(function () { return null; });
    }

    function getPlantThreshold(plantId) {
        var xrm = getXrm();
        if (!xrm || !plantId) return Promise.resolve(0);
        var id = plantId.replace(/[{}]/g, "");
        return xrm.WebApi.retrieveRecord("rma_plant", id, "?$select=rma_autocreditthreshold,rma_name")
            .then(function (r) {
                return { threshold: r.rma_autocreditthreshold || 0, plantName: r.rma_name || "Unknown plant" };
            })
            .catch(function () { return { threshold: 0, plantName: "Unknown plant" }; });
    }

    function setResolutionFields(formContext, resolutionValue, resolutionLabel) {
        formContext.getAttribute("rma_resolution").setValue(resolutionValue);
        formContext.getAttribute("rma_status").setValue(STATUS_CLOSED);
        formContext.getAttribute("rma_closeddate").setValue(new Date());
        formContext.getAttribute("rma_haspendingresponse").setValue(false);

        formContext.ui.setFormNotification(
            "Claim resolved: " + resolutionLabel + ". Save to commit.",
            "INFO",
            "rma_resolution_set"
        );
        // Auto-clear notification after 6s
        setTimeout(function () {
            try { formContext.ui.clearFormNotification("rma_resolution_set"); } catch (e) {}
        }, 6000);
    }

    function createApprovalRecord(formContext, requestedAmount, reason) {
        var xrm = getXrm();
        if (!xrm) return Promise.reject("No Xrm");
        var claimId = formContext.data.entity.getId().replace(/[{}]/g, "");
        var plant = formContext.getAttribute("rma_assignedplant").getValue();
        var data = {
            "rma_name": "Approval for " + (formContext.getAttribute("rma_claimnumber").getValue() || "claim"),
            "rma_claim@odata.bind": "/rma_claims(" + claimId + ")",
            "rma_requestedamount": requestedAmount,
            "rma_reason": reason || "Auto-requested from claim form"
        };
        if (plant && plant.length > 0) {
            data["rma_plant@odata.bind"] = "/rma_plants(" + plant[0].id.replace(/[{}]/g, "") + ")";
        }
        return xrm.WebApi.createRecord("rma_approvalrecord", data);
    }

    // ------------------------------------------------------------------
    // Commands
    // ------------------------------------------------------------------

    HKP.resolveCredit = function (executionContext) {
        var fc = executionContext.getFormContext ? executionContext.getFormContext() : executionContext;
        var creditAttr = fc.getAttribute("rma_creditamount");
        var creditAmount = creditAttr ? (creditAttr.getValue() || 0) : 0;
        var plant = fc.getAttribute("rma_assignedplant").getValue();
        var plantId = (plant && plant.length > 0) ? plant[0].id : null;

        return getPlantThreshold(plantId).then(function (info) {
            var threshold = info.threshold || 0;
            var doResolve = function () {
                setResolutionFields(fc, RESOLUTION.CREDIT, "Credit Issued — $" + creditAmount);
            };

            if (creditAmount > threshold && threshold > 0) {
                return confirmDialog(
                    "Credit amount $" + creditAmount.toFixed(2) +
                    " exceeds " + info.plantName + " auto-approval threshold ($" + threshold.toFixed(2) +
                    "). An approval request will be created. Continue?",
                    "Approval Required"
                ).then(function (r) {
                    if (!r.confirmed) return;
                    return createApprovalRecord(fc, creditAmount, "Credit above plant auto-approval threshold")
                        .then(function () {
                            fc.ui.setFormNotification(
                                "Approval request created. Claim will close once manager approves.",
                                "WARNING",
                                "rma_approval_pending"
                            );
                            // Don't set resolution yet — wait for approval
                        });
                });
            } else {
                return confirmDialog("Resolve this claim with credit of $" + creditAmount.toFixed(2) + "?", "Resolve — Credit Issued")
                    .then(function (r) { if (r.confirmed) doResolve(); });
            }
        });
    };

    HKP.resolveReplacement = function (executionContext) {
        var fc = executionContext.getFormContext ? executionContext.getFormContext() : executionContext;
        return confirmDialog("Resolve this claim with a replacement?", "Resolve — Replacement Sent")
            .then(function (r) { if (r.confirmed) setResolutionFields(fc, RESOLUTION.REPLACEMENT, "Replacement Sent"); });
    };

    HKP.resolveRepair = function (executionContext) {
        var fc = executionContext.getFormContext ? executionContext.getFormContext() : executionContext;
        return confirmDialog("Resolve this claim with a repair?", "Resolve — Repair Completed")
            .then(function (r) { if (r.confirmed) setResolutionFields(fc, RESOLUTION.REPAIR, "Repair Completed"); });
    };

    HKP.denyClaim = function (executionContext) {
        var fc = executionContext.getFormContext ? executionContext.getFormContext() : executionContext;
        return confirmDialog("Deny this claim?  An approval-history record will be created.", "Deny Claim")
            .then(function (r) {
                if (!r.confirmed) return;
                setResolutionFields(fc, RESOLUTION.DENIED, "Claim Denied");
                // Optional: create approval history record
                var xrm = getXrm();
                if (!xrm) return;
                var claimId = fc.data.entity.getId().replace(/[{}]/g, "");
                xrm.WebApi.createRecord("rma_approvalhistory", {
                    "rma_name": "Denied by " + xrm.Utility.getGlobalContext().userSettings.userName,
                    "rma_claim@odata.bind": "/rma_claims(" + claimId + ")",
                    "rma_action": 100000001 // assumes Deny = 100000001
                }).catch(function () { /* swallow — entity may not have rma_action option */ });
            });
    };

    HKP.sendCustomerEmail = function (executionContext) {
        var fc = executionContext.getFormContext ? executionContext.getFormContext() : executionContext;
        var customerEmail = fc.getAttribute("rma_customeremail") ? fc.getAttribute("rma_customeremail").getValue() : "";
        var claimNum = fc.getAttribute("rma_claimnumber").getValue() || "(unsaved)";

        // For v1, we open an email log Quick Create with prefilled values.
        // Phase 2 will swap this for a Custom Page with template picker.
        var xrm = getXrm();
        if (!xrm) return;

        var claimId = fc.data.entity.getId().replace(/[{}]/g, "");
        return xrm.Navigation.openForm({
            entityName: "rma_emaillog",
            useQuickCreateForm: true,
            createFromEntity: {
                entityType: "rma_claim",
                id: "{" + claimId + "}",
                name: claimNum
            }
        }, {
            "rma_subject":     "RMA " + claimNum + " — update from HKP",
            "rma_recipient":   customerEmail,
            "rma_direction":   100000001,    // Outbound
            "rma_sentdate":    new Date().toISOString(),
            "rma_claim":       claimId
        });
    };

    HKP.requestManagerApproval = function (executionContext) {
        var fc = executionContext.getFormContext ? executionContext.getFormContext() : executionContext;
        var creditAttr = fc.getAttribute("rma_creditamount");
        var amount = creditAttr ? (creditAttr.getValue() || 0) : 0;

        return confirmDialog(
            "Create approval request for $" + amount.toFixed(2) + "?  Plant approvers will be notified.",
            "Request Approval"
        ).then(function (r) {
            if (!r.confirmed) return;
            return createApprovalRecord(fc, amount, "Manual request from claim form")
                .then(function () {
                    return alertDialog("Approval request created. Plant approvers will be notified via the approval flow.", "Approval Requested");
                });
        });
    };

    // ------------------------------------------------------------------
    // EMAIL LOG → CREATE RMA CLAIM
    // Lives on rma_emaillog form.  Opens rma_claim Quick Create prefilled
    // from extracted email fields, then on save links email -> claim and
    // flips email.rma_isprocessed = true.
    // ------------------------------------------------------------------

    HKP.createClaimFromEmail = function (executionContext) {
        var fc = executionContext.getFormContext ? executionContext.getFormContext() : executionContext;
        var xrm = getXrm();
        if (!xrm) return;

        var emailId = fc.data.entity.getId().replace(/[{}]/g, "");
        var subject = fc.getAttribute("rma_subject") ? fc.getAttribute("rma_subject").getValue() : "";
        var fromAddr = fc.getAttribute("rma_fromaddress") ? fc.getAttribute("rma_fromaddress").getValue() : "";
        var bodyPreview = fc.getAttribute("rma_bodypreview") ? fc.getAttribute("rma_bodypreview").getValue() : "";

        // Best-effort parsing of common AI-extracted fields from the subject/body
        var customerName = fromAddr ? fromAddr.split("@")[0].replace(/\./g, " ") : "";

        return xrm.Navigation.openForm({
            entityName: "rma_claim",
            useQuickCreateForm: true
        }, {
            "rma_customername":     customerName,
            "rma_customeremail":    fromAddr,
            "rma_failuredescription": bodyPreview,
            "rma_sourceemailid":    emailId
        }).then(function (result) {
            if (result && result.savedEntityReference && result.savedEntityReference.length > 0) {
                var claimRef = result.savedEntityReference[0];
                var claimId = claimRef.id.replace(/[{}]/g, "");
                // Link email -> claim + mark processed
                return xrm.WebApi.updateRecord("rma_emaillog", emailId, {
                    "rma_claim@odata.bind": "/rma_claims(" + claimId + ")",
                    "rma_isprocessed": true
                }).then(function () {
                    return alertDialog("RMA Claim created and linked. Email marked as processed.", "Done");
                }).then(function () {
                    fc.data.refresh(false);
                });
            }
        });
    };

})(window.HKPCommands);
