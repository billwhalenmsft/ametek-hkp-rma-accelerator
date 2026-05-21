"""
HKP RMA Eligibility Agent

Applies RMA eligibility rules to a claim and returns:
  - verdict: eligible | ineligible | unclear
  - reasoning: short string the engineer can audit
  - evidence_gaps: list of missing inputs that would change the verdict

Rules used (Phase 1 — demo):
  R1. In warranty + manufacturing-defect symptom keywords  → eligible
  R2. Out of warranty + no goodwill flag                   → ineligible
  R3. Borderline warranty (within 90 days expired)         → unclear (request usage data)
  R4. Description too short / no failure mode              → unclear (request more info)
  R5. Misuse keywords (impact, drop, water, lightning)     → ineligible (warranty exclusion)
"""

import json
import logging
from datetime import date, datetime, timezone
from typing import Dict, List, Tuple
from agents.basic_agent import BasicAgent

try:
    from customers.ametek.hkp_rma.agents._hkp_rma_data import find_serial, find_claim
except ImportError:
    from _hkp_rma_data import find_serial, find_claim  # type: ignore

logger = logging.getLogger(__name__)

DEFECT_KEYWORDS = [
    "lead screw", "thread", "bearing", "encoder", "stepper", "stator", "rotor",
    "winding", "manufacturing defect", "premature", "failed at", "seized",
    "stripped", "shear", "shorted", "open circuit",
]

MISUSE_KEYWORDS = [
    "dropped", "impact", "fell", "water damage", "submerged", "flood",
    "lightning", "power surge", "exceeded rated", "wrong voltage", "tampered",
    "modified", "disassembled", "burned", "fire damage",
]

INSTALLATION_KEYWORDS = [
    "vfd", "emi", "electrical noise", "neighbouring drive", "shielding", "ground loop",
]

BORDERLINE_DAYS = 90  # within +/- 90 days of warranty end = unclear


class HKPRMAEligibilityAgent(BasicAgent):
    """Apply warranty + condition rules to an RMA claim."""

    def __init__(self):
        self.name = "HKPRMAEligibility"
        self.metadata = {
            "name": self.name,
            "description": (
                "Decide whether an AMETEK HKP RMA is eligible for warranty coverage. "
                "Returns one of: eligible / ineligible / unclear, plus reasoning and "
                "evidence gaps. Use this AFTER HKPWarrantyLookup. Action: check_eligibility."
            ),
            "parameters": {
                "type": "object",
                "properties": {
                    "action": {
                        "type": "string",
                        "enum": ["check_eligibility"],
                    },
                    "claim_number": {
                        "type": "string",
                        "description": "Existing claim # — eligibility computed from stored fields.",
                    },
                    "serial_number": {
                        "type": "string",
                        "description": "Product serial (use if no claim_number).",
                    },
                    "failure_description": {
                        "type": "string",
                        "description": "Customer's description of the failure (use if no claim_number).",
                    },
                },
                "required": ["action"],
            },
        }
        super().__init__(self.name, self.metadata)

    def perform(self, **kwargs) -> str:
        action = kwargs.get("action", "check_eligibility")
        if action != "check_eligibility":
            return json.dumps({"status": "error", "message": f"Unknown action: {action}"})
        return self._check_eligibility(kwargs)

    def _check_eligibility(self, kwargs: Dict) -> str:
        # Resolve claim record (either by claim# or compose synthetic from serial+desc)
        claim_number = (kwargs.get("claim_number") or "").strip()
        if claim_number:
            claim = find_claim(claim_number)
            if not claim:
                return json.dumps({
                    "status": "not_found",
                    "message": f"Claim '{claim_number}' not found.",
                })
            serial      = claim.get("serialNumber", "")
            description = claim.get("description", "")
        else:
            serial      = (kwargs.get("serial_number") or "").strip().upper()
            description = (kwargs.get("failure_description") or "").strip()

        # Warranty lookup
        serial_record = find_serial(serial) if serial else None
        if not serial_record:
            return json.dumps({
                "status": "error",
                "verdict": "unclear",
                "reasoning": "Cannot evaluate eligibility without a valid serial number.",
                "evidenceGaps": ["serial_number"],
            }, indent=2)

        warranty_end = date.fromisoformat(serial_record["warrantyEnd"][:10])
        today = datetime.now(timezone.utc).date()
        days_past_warranty = (today - warranty_end).days  # negative if still in warranty

        # Apply rules
        verdict, reasoning, gaps = self._apply_rules(
            description, days_past_warranty
        )

        return json.dumps({
            "status": "ok",
            "claimNumber":  claim_number or None,
            "serialNumber": serial,
            "verdict":      verdict,
            "reasoning":    reasoning,
            "evidenceGaps": gaps,
            "daysPastWarranty": days_past_warranty,
            "warrantyEnd":  serial_record["warrantyEnd"],
        }, indent=2)

    def _apply_rules(self, description: str, days_past_warranty: int) -> Tuple[str, str, List[str]]:
        d_lower = description.lower()
        has_defect_kw      = any(kw in d_lower for kw in DEFECT_KEYWORDS)
        has_misuse_kw      = any(kw in d_lower for kw in MISUSE_KEYWORDS)
        has_install_kw     = any(kw in d_lower for kw in INSTALLATION_KEYWORDS)
        too_short          = len(description) < 60

        # R5 first — misuse trumps everything
        if has_misuse_kw:
            return (
                "ineligible",
                "Description contains misuse keywords (water/impact/surge/etc.) — warranty exclusion under HKP terms.",
                [],
            )

        # R4 — too vague to decide
        if too_short:
            return (
                "unclear",
                "Description too short to evaluate failure mode. Need more detail.",
                ["failure_mode_detail", "photos_or_video", "error_codes_if_any", "duty_cycle_history"],
            )

        # R2 — well past warranty (>BORDERLINE_DAYS) = ineligible
        if days_past_warranty > BORDERLINE_DAYS:
            return (
                "ineligible",
                f"Out of warranty by {days_past_warranty} days (more than {BORDERLINE_DAYS}-day grace). Recommend offering paid repair quote.",
                [],
            )

        # R3 — borderline (within 90 days past warranty)
        if 0 <= days_past_warranty <= BORDERLINE_DAYS:
            return (
                "unclear",
                f"Just past warranty (+{days_past_warranty} days, within {BORDERLINE_DAYS}-day grace). Need usage data + duty cycle to decide goodwill repair vs paid.",
                ["customer_usage_logs", "duty_cycle", "install_environment"],
            )

        # In warranty
        if has_defect_kw:
            return (
                "eligible",
                "In warranty + failure mode matches known manufacturing-defect category.",
                [],
            )

        if has_install_kw:
            return (
                "unclear",
                "In warranty but description suggests installation environment (EMI / VFD / grounding) — could be defect or installation issue. Need engineer review.",
                ["installation_photos", "wiring_diagram", "neighbouring_equipment_list"],
            )

        return (
            "unclear",
            "In warranty but failure mode unclear — could be defect or expected wear. Need additional evidence.",
            ["photos_of_failure", "duty_cycle_history", "operating_environment"],
        )
