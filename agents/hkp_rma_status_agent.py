"""
HKP RMA Status Agent

Customer-facing status summary for an RMA claim.
Returns a short markdown blurb that customer service can paste into an email
or that surfaces in the bot when an OEM checks "Where's my RMA?".

Phase 1: derives status from demo-data.json + a status timeline simulation.
Phase 2: replace with Dataverse query against cr74e_warrantyclaim + cr74e_customerinteraction.
"""

import json
import logging
from datetime import datetime, timedelta, timezone
from typing import Dict
from agents.basic_agent import BasicAgent

try:
    from customers.ametek.hkp_rma.agents._hkp_rma_data import find_claim
except ImportError:
    from _hkp_rma_data import find_claim  # type: ignore

logger = logging.getLogger(__name__)


# Map status → next likely action + ETA so the customer message is useful
STATUS_PLAYBOOK = {
    "Submitted":                       ("Triage by HKP RMA agent", 0.5),
    "Triaged":                         ("Eligibility review",       1),
    "Pending Eligibility Review":      ("Disposition recommendation", 1),
    "Pending Engineer Review":         ("Quality engineer review", 3),
    "Approved - Repair":               ("Inbound RMA shipping label issued", 1),
    "Approved - Replace":              ("Outbound replacement shipped", 2),
    "Approved - Refund":               ("Credit memo issued", 5),
    "Rejected - Out of Warranty":      ("Customer notification + paid repair quote", 1),
    "Rejected - Misuse":               ("Customer notification with photos", 1),
    "Rejected - Insufficient Evidence":("Customer notification requesting more info", 1),
    "Closed - Resolved":               ("None — case closed", 0),
    "Closed - Customer Withdrew":      ("None — case closed", 0),
}


class HKPRMAStatusAgent(BasicAgent):
    """Return customer-facing status for an RMA claim."""

    def __init__(self):
        self.name = "HKPRMAStatus"
        self.metadata = {
            "name": self.name,
            "description": (
                "Get customer-facing status for an AMETEK HKP RMA. "
                "Returns a short markdown summary suitable for customer email or bot reply: "
                "current state, last action, next action, ETA. "
                "Action: get_status."
            ),
            "parameters": {
                "type": "object",
                "properties": {
                    "action": {"type": "string", "enum": ["get_status"]},
                    "claim_number": {"type": "string", "description": "RMA claim number, e.g. RMA-2026-0412."},
                    "audience": {
                        "type": "string",
                        "enum": ["customer", "internal"],
                        "description": "Customer-friendly tone or internal detailed tone (default: customer).",
                    },
                },
                "required": ["action", "claim_number"],
            },
        }
        super().__init__(self.name, self.metadata)

    def perform(self, **kwargs) -> str:
        action = kwargs.get("action", "get_status")
        if action != "get_status":
            return json.dumps({"status": "error", "message": f"Unknown action: {action}"})
        return self._get_status(kwargs)

    def _get_status(self, kwargs: Dict) -> str:
        claim_number = (kwargs.get("claim_number") or "").strip()
        audience     = (kwargs.get("audience") or "customer").lower()
        claim = find_claim(claim_number)
        if not claim:
            return json.dumps({
                "status": "not_found",
                "message": f"RMA '{claim_number}' not found.",
            })

        current = claim.get("status", "Submitted")
        next_action, eta_days = STATUS_PLAYBOOK.get(current, ("Triage", 1))

        submitted = claim.get("submittedOn")
        try:
            submitted_dt = datetime.fromisoformat(submitted.replace("Z", "+00:00"))
            eta_dt = datetime.now(timezone.utc) + timedelta(days=eta_days)
            eta_iso = eta_dt.date().isoformat()
        except Exception:
            submitted_dt = None
            eta_iso = "TBD"

        if audience == "customer":
            message = (
                f"**RMA {claim_number}** — current status: **{current}**\n\n"
                f"Subject: _{claim.get('subject')}_  \n"
                f"Submitted: {submitted}  \n"
                f"Next action: **{next_action}**  \n"
                f"Estimated completion: **{eta_iso}**\n\n"
                f"You will receive an email when there's an update or action required from your end."
            )
        else:
            message = (
                f"**RMA {claim_number}** [{claim.get('customerName')}]\n"
                f"- Status: {current}\n"
                f"- Subject: {claim.get('subject')}\n"
                f"- SKU: {claim.get('productSku')}\n"
                f"- Serial: {claim.get('serialNumber')}\n"
                f"- Submitted: {submitted}\n"
                f"- Next: {next_action} (ETA {eta_iso})\n"
                f"- Scenario: {claim.get('scenario', '(not categorized)')}"
            )

        return json.dumps({
            "status": "ok",
            "claimNumber":  claim_number,
            "currentState": current,
            "nextAction":   next_action,
            "etaIso":       eta_iso,
            "audience":     audience,
            "message":      message,
        }, indent=2)
