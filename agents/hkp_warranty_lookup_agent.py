"""
HKP Warranty Lookup Agent

Given a product serial number (or order number), returns the warranty status:
  - SKU + product name
  - Owner / OEM
  - Shipped date
  - Warranty end date
  - in_warranty (bool)
  - days_remaining (int; negative if expired)

Phase 1: Serves from demo-data.json `productSerials`.
Phase 2: Replace with Dataverse query against cr74e_productserial + msdyn_warranty.
"""

import json
import logging
from datetime import date, datetime, timezone
from typing import Dict
from agents.basic_agent import BasicAgent

try:
    from customers.ametek.hkp_rma.agents._hkp_rma_data import find_serial, find_product
except ImportError:
    from _hkp_rma_data import find_serial, find_product  # type: ignore

logger = logging.getLogger(__name__)


class HKPWarrantyLookupAgent(BasicAgent):
    """Look up warranty status for an HKP product serial."""

    def __init__(self):
        self.name = "HKPWarrantyLookup"
        self.metadata = {
            "name": self.name,
            "description": (
                "Look up the warranty status of an AMETEK HKP product by serial number. "
                "Returns SKU, owner, shipped date, warranty end, in-warranty boolean, "
                "and days remaining (negative if expired). Use this BEFORE deciding RMA "
                "eligibility. Action: lookup_by_serial."
            ),
            "parameters": {
                "type": "object",
                "properties": {
                    "action": {
                        "type": "string",
                        "enum": ["lookup_by_serial"],
                        "description": "Operation to perform.",
                    },
                    "serial_number": {
                        "type": "string",
                        "description": "HKP product serial, e.g. IDEA-57-2025-104872.",
                    },
                    "as_of_date": {
                        "type": "string",
                        "description": "ISO date to evaluate warranty status against (default = today).",
                    },
                },
                "required": ["action", "serial_number"],
            },
        }
        super().__init__(self.name, self.metadata)

    def perform(self, **kwargs) -> str:
        action = kwargs.get("action", "lookup_by_serial")
        if action != "lookup_by_serial":
            return json.dumps({"status": "error", "message": f"Unknown action: {action}"})
        return self._lookup_by_serial(kwargs)

    def _lookup_by_serial(self, kwargs: Dict) -> str:
        serial = (kwargs.get("serial_number") or "").strip().upper()
        if not serial:
            return json.dumps({
                "status": "error",
                "message": "serial_number is required.",
            })

        record = find_serial(serial)
        if not record:
            return json.dumps({
                "status": "not_found",
                "serialNumber": serial,
                "message": (
                    f"No record found for serial '{serial}'. "
                    "Verify the serial with the customer or check the OEM PO history."
                ),
            }, indent=2)

        product = find_product(record["sku"])

        # Compute warranty status
        as_of_str = kwargs.get("as_of_date") or datetime.now(timezone.utc).date().isoformat()
        as_of = date.fromisoformat(as_of_str[:10])
        warranty_end = date.fromisoformat(record["warrantyEnd"][:10])
        days_remaining = (warranty_end - as_of).days
        in_warranty = days_remaining >= 0

        if in_warranty:
            warranty_message = f"In warranty — {days_remaining} days remaining (expires {record['warrantyEnd']})."
        else:
            warranty_message = f"Out of warranty by {-days_remaining} days (warranty expired {record['warrantyEnd']})."

        result = {
            "status": "ok",
            "asOf": as_of_str,
            "serialNumber": serial,
            "productSku":   record["sku"],
            "productName":  product["name"] if product else "(unknown product)",
            "owner":        record["owner"],
            "shippedDate":  record["shippedDate"],
            "warrantyEnd":  record["warrantyEnd"],
            "inWarranty":   in_warranty,
            "daysRemaining": days_remaining,
            "warrantyMessage": warranty_message,
        }
        return json.dumps(result, indent=2)
