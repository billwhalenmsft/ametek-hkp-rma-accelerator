"""
HKP RMA Escalation Agent

Hands a claim off to a quality engineer with a structured evidence pack.
Outputs:
  - Suggested engineer (mock for Phase 1)
  - Priority (P1/P2/P3)
  - Summary for engineer
  - Evidence pack URL (mock SharePoint link for Phase 1)
"""

import json
import logging
from typing import Dict
from agents.basic_agent import BasicAgent

try:
    from customers.ametek.hkp_rma.agents._hkp_rma_data import find_claim, find_serial
except ImportError:
    from _hkp_rma_data import find_claim, find_serial  # type: ignore

logger = logging.getLogger(__name__)

# Phase 1 mock engineer routing — Phase 2 will read from cr74e_user/cr74e_department
ENGINEER_BY_PRODUCT = {
    "iDEA-57-101": ("Sarah Chen",   "Senior QE - 57mm Series",  "sarah.chen@ametek.com"),
    "iDEA-57-201": ("Sarah Chen",   "Senior QE - 57mm Series",  "sarah.chen@ametek.com"),
    "iDEA-43-105": ("Marcus Rivera","QE - Mid Frame Series",    "marcus.rivera@ametek.com"),
    "iDEA-35-080": ("Marcus Rivera","QE - Mid Frame Series",    "marcus.rivera@ametek.com"),
    "iDEA-28-050": ("Priya Patel",  "QE - Compact Series",      "priya.patel@ametek.com"),
}

DEFAULT_ENGINEER = ("RMA Triage Pool", "RMA Quality", "rma-triage@ametek.com")


class HKPRMAEscalationAgent(BasicAgent):
    """Hand a claim off to a quality engineer with structured context."""

    def __init__(self):
        self.name = "HKPRMAEscalation"
        self.metadata = {
            "name": self.name,
            "description": (
                "Escalate an AMETEK HKP RMA to a quality engineer with a structured "
                "evidence pack. Auto-assigns based on product family. Returns engineer "
                "details, priority, summary, and (mock) evidence pack URL. "
                "Action: escalate."
            ),
            "parameters": {
                "type": "object",
                "properties": {
                    "action": {"type": "string", "enum": ["escalate"]},
                    "claim_number": {"type": "string"},
                    "reason": {
                        "type": "string",
                        "description": "Why this is being escalated (e.g. 'Ambiguous failure mode + EMI suspected')."
                    },
                    "suspected_failure_mode": {
                        "type": "string",
                        "description": "Optional engineer-facing hint."
                    },
                    "priority_hint": {
                        "type": "string",
                        "enum": ["P1", "P2", "P3"],
                        "description": "Optional override; otherwise computed from customer tier + warranty status.",
                    },
                },
                "required": ["action", "claim_number", "reason"],
            },
        }
        super().__init__(self.name, self.metadata)

    def perform(self, **kwargs) -> str:
        action = kwargs.get("action", "escalate")
        if action != "escalate":
            return json.dumps({"status": "error", "message": f"Unknown action: {action}"})
        return self._escalate(kwargs)

    def _escalate(self, kwargs: Dict) -> str:
        claim_number = (kwargs.get("claim_number") or "").strip()
        reason       = (kwargs.get("reason") or "").strip()
        suspected    = (kwargs.get("suspected_failure_mode") or "").strip()
        priority_hint = (kwargs.get("priority_hint") or "").upper()

        claim = find_claim(claim_number)
        if not claim:
            return json.dumps({"status": "not_found", "message": f"Claim '{claim_number}' not found."})
        if not reason:
            return json.dumps({"status": "error", "message": "reason is required for escalation."})

        sku           = claim.get("productSku", "")
        serial_record = find_serial(claim.get("serialNumber", ""))
        engineer_name, engineer_role, engineer_email = ENGINEER_BY_PRODUCT.get(sku, DEFAULT_ENGINEER)

        # Priority: P1 if Tier-1 OEM + in-warranty; P2 default; P3 if old/low-tier
        priority = priority_hint or self._compute_priority(claim, serial_record)

        # Mock SharePoint evidence pack URL
        evidence_url = (
            f"https://demo.sharepoint.com/sites/AMETEK-HKP-RMA/Evidence/"
            f"{claim_number}/EvidencePack.aspx"
        )

        engineer_summary = self._build_engineer_summary(claim, serial_record, suspected, reason)

        return json.dumps({
            "status": "ok",
            "claimNumber":         claim_number,
            "assignedEngineer": {
                "name":  engineer_name,
                "role":  engineer_role,
                "email": engineer_email,
            },
            "priority":            priority,
            "reason":              reason,
            "suspectedFailureMode": suspected or "(none provided)",
            "engineerSummary":     engineer_summary,
            "evidencePackUrl":     evidence_url,
            "nextStep":            f"Engineer {engineer_name} reviews and replies via Customer Interaction agent.",
        }, indent=2)

    def _compute_priority(self, claim: Dict, serial_record) -> str:
        # Phase 1 heuristic — refine in Phase 2 when we have real cr74e_user/department
        customer = (claim.get("customerName") or "").lower()
        if "andersen" in customer or "marvin" in customer:
            tier = 1
        elif "pella" in customer or "velux" in customer:
            tier = 2
        else:
            tier = 3

        if not serial_record:
            return "P2"

        # In warranty + Tier 1 = P1
        from datetime import date
        try:
            warranty_end = date.fromisoformat(serial_record["warrantyEnd"][:10])
            in_warranty = warranty_end >= date.today()
        except Exception:
            in_warranty = False

        if tier == 1 and in_warranty:
            return "P1"
        if tier <= 2 and in_warranty:
            return "P2"
        return "P3"

    def _build_engineer_summary(self, claim, serial_record, suspected, reason) -> str:
        lines = [
            f"**RMA {claim['claimNumber']}** — engineer review required",
            "",
            f"**Customer:** {claim['customerName']}",
            f"**Subject:** {claim['subject']}",
            "",
            f"**Product:** {claim['productSku']}",
            f"**Serial:** {claim['serialNumber']}",
        ]
        if serial_record:
            lines.append(f"**Shipped:** {serial_record['shippedDate']}  •  **Warranty ends:** {serial_record['warrantyEnd']}")
        lines.append("")
        lines.append(f"**Customer description:**\n> {claim.get('description', '(none)')}")
        lines.append("")
        lines.append(f"**Why escalated:** {reason}")
        if suspected:
            lines.append(f"**Suspected failure mode (RMA agent guess):** {suspected}")
        lines.append("")
        lines.append("Please review the evidence pack and reply with disposition + root cause.")
        return "\n".join(lines)
