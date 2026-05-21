"""
HKP RMA Intake Agent

Parses inbound email or web-form text into a structured RMA record.
Source: discovery transcripts indicate "shared inbox" intake is the #1 pain point.

Phase 1: Demo from JSON (matches incoming text against known sample claims by
         keyword + serial extraction).
Phase 2: Replace with Azure OpenAI extraction or call to existing
         "When a new email arrives for a warranty claim" PA flow.
"""

import json
import logging
import re
from typing import Dict, Optional
from agents.basic_agent import BasicAgent

# Try import as customer-folder module first, then as flat agents/ module
try:
    from customers.ametek.hkp_rma.agents._hkp_rma_data import (
        load_demo_data, find_serial, find_product
    )
except ImportError:
    from _hkp_rma_data import load_demo_data, find_serial, find_product  # type: ignore

logger = logging.getLogger(__name__)

SERIAL_RE = re.compile(r"IDEA-\d{2}-\d{4}-\d{6}", re.IGNORECASE)
SKU_RE    = re.compile(r"iDEA-\d{2}-\d{3}", re.IGNORECASE)


class HKPRMAIntakeAgent(BasicAgent):
    """Normalize raw email / form text into structured RMA fields."""

    def __init__(self):
        self.name = "HKPRMAIntake"
        self.metadata = {
            "name": self.name,
            "description": (
                "Parse incoming email or form text into a structured AMETEK HKP RMA "
                "(Return Material Authorization) request. Extracts: customer, "
                "serial number, product SKU, subject summary, failure description. "
                "Use this as the FIRST step when an RMA email arrives in the shared "
                "inbox or when a customer submits an RMA web form. "
                "Actions: parse_email, parse_form, list_pending."
            ),
            "parameters": {
                "type": "object",
                "properties": {
                    "action": {
                        "type": "string",
                        "enum": ["parse_email", "parse_form", "list_pending"],
                        "description": "Operation to perform.",
                    },
                    "subject":      {"type": "string", "description": "Email or form subject line."},
                    "body":         {"type": "string", "description": "Full email body or form description."},
                    "from_email":   {"type": "string", "description": "Sender email address (for parse_email)."},
                    "customer_name":{"type": "string", "description": "Customer / account name if known."},
                    "serial_hint":  {"type": "string", "description": "Optional serial number if already extracted."},
                },
                "required": ["action"],
            },
        }
        super().__init__(self.name, self.metadata)

    def perform(self, **kwargs) -> str:
        action = kwargs.get("action", "parse_email")
        try:
            if action == "list_pending":
                return self._list_pending()
            if action in ("parse_email", "parse_form"):
                return self._parse(kwargs)
            return json.dumps({"status": "error", "message": f"Unknown action: {action}"})
        except Exception as exc:
            logger.exception("HKPRMAIntakeAgent error")
            return json.dumps({"status": "error", "message": str(exc)})

    # ---------------------------------------------------------------------
    def _parse(self, kwargs: Dict) -> str:
        subject = (kwargs.get("subject") or "").strip()
        body    = (kwargs.get("body") or "").strip()
        text    = f"{subject}\n{body}"
        from_email     = (kwargs.get("from_email") or "").strip().lower()
        customer_hint  = (kwargs.get("customer_name") or "").strip()
        serial_hint    = (kwargs.get("serial_hint") or "").strip().upper()

        # 1. Extract serial number
        serial = serial_hint
        if not serial:
            m = SERIAL_RE.search(text)
            if m:
                serial = m.group(0).upper()
        serial_record = find_serial(serial) if serial else None

        # 2. Extract / infer SKU
        sku = serial_record["sku"] if serial_record else None
        if not sku:
            m = SKU_RE.search(text)
            if m:
                sku = m.group(0)
        product = find_product(sku) if sku else None

        # 3. Resolve customer
        customer = customer_hint or (serial_record["owner"] if serial_record else None)
        if not customer:
            customer = self._infer_customer_from_email(from_email)

        # 4. Confidence + missing fields
        missing = []
        if not serial:   missing.append("serial_number")
        if not sku:      missing.append("product_sku")
        if not customer: missing.append("customer_name")
        if not body:     missing.append("failure_description")

        confidence = 1.0 - (0.20 * len(missing))
        confidence = max(0.0, round(confidence, 2))

        result = {
            "status": "ok" if not missing else "needs_more_info",
            "confidence": confidence,
            "extracted": {
                "subject":     subject or "(no subject)",
                "description": body or "(no description provided)",
                "customer":    customer or "(unknown)",
                "fromEmail":   from_email or "(unknown)",
                "serialNumber": serial or "(not found)",
                "productSku":  sku or "(not identified)",
                "productName": product["name"] if product else "(not identified)",
            },
            "missingFields": missing,
            "nextStep": (
                "Call HKPWarrantyLookup with the serial number"
                if serial else
                "Reply to customer asking for serial number + photo of failure mode"
            ),
        }
        return json.dumps(result, indent=2)

    # ---------------------------------------------------------------------
    def _list_pending(self) -> str:
        """Return the demo claims that are in 'Submitted' state — the inbox queue."""
        data = load_demo_data()
        pending = [
            {
                "claimNumber": c["claimNumber"],
                "customer":    c["customerName"],
                "subject":     c["subject"],
                "submittedOn": c["submittedOn"],
                "scenario":    c.get("scenario", ""),
            }
            for c in data.get("warrantyClaims", [])
            if c.get("status") == "Submitted"
        ]
        return json.dumps({
            "status": "ok",
            "totalPending": len(pending),
            "queue": pending,
            "summary": (
                f"{len(pending)} RMA requests in the shared inbox awaiting triage. "
                "Run HKPWarrantyLookup → HKPRMAEligibility → HKPRMADisposition for each."
            ),
        }, indent=2)

    # ---------------------------------------------------------------------
    def _infer_customer_from_email(self, from_email: str) -> Optional[str]:
        if not from_email or "@" not in from_email:
            return None
        domain = from_email.split("@", 1)[1].lower()
        # Cheap heuristic for demo accounts
        mapping = {
            "andersenwindows.com": "Andersen Windows OEM",
            "marvin.com":          "Marvin Holdings",
            "pella.com":            "Pella Corporation",
            "velux.com":            "Velux Group",
            "acmewindowdist.com":  "Acme Window Distribution",
        }
        return mapping.get(domain)
