"""
HKP RMA Agent Set — shared utilities

All 6 HKP RMA agents read from the same `demo-data.json` at:
  customers/ametek/hkp_rma/d365/config/demo-data.json

This module centralizes that lookup so the agents work whether they live in:
  - customers/ametek/hkp_rma/agents/  (source of truth)
  - agents/                            (copies for function_app auto-load + RAPP UI)

Phase 1 = read demo data from local JSON.
Phase 2 = swap _load_demo_data() to query Dataverse cr74e_warrantyclaim etc.
         (the agent contracts don't change).
"""

import json
import logging
from pathlib import Path
from typing import Dict, Optional

logger = logging.getLogger(__name__)

# Search paths — relative to repo root, in order
_DEMO_JSON_CANDIDATES = [
    Path("customers/ametek/hkp_rma/d365/config/demo-data.json"),
    # If running from the CommunityRAPP-BillWhalen repo:
    Path(__file__).resolve().parents[3] / "customers" / "ametek" / "hkp_rma" / "d365" / "config" / "demo-data.json"
        if "__file__" in globals() else None,
    # If running from the agents/ folder (copy):
    Path(__file__).resolve().parents[1] / "customers" / "ametek" / "hkp_rma" / "d365" / "config" / "demo-data.json"
        if "__file__" in globals() else None,
]

_cache: Optional[Dict] = None


def load_demo_data() -> Dict:
    """Load + cache the HKP demo data JSON. Tries multiple paths so this works
    whether the agent file is in customers/ametek/hkp_rma/agents/ or agents/."""
    global _cache
    if _cache is not None:
        return _cache

    for candidate in _DEMO_JSON_CANDIDATES:
        if candidate is None:
            continue
        if candidate.is_file():
            try:
                with open(candidate, encoding="utf-8") as fh:
                    _cache = json.load(fh)
                logger.info("HKP demo data loaded from %s", candidate)
                return _cache
            except Exception as exc:
                logger.warning("Failed to read %s: %s", candidate, exc)

    # Fallback: empty shell so agents return errors gracefully instead of crashing
    logger.warning("HKP demo data NOT found in any candidate path. Agents will return empty.")
    _cache = {
        "products": [],
        "accounts": [],
        "productSerials": [],
        "warrantyClaims": [],
        "rootCauseHistorical": {},
        "_metadata": {"customer": "AMETEK HKP", "useCase": "hkp_rma"},
    }
    return _cache


def find_serial(serial_number: str) -> Optional[Dict]:
    """Look up a productSerial entry by serial number."""
    data = load_demo_data()
    serial_clean = (serial_number or "").strip().upper()
    for s in data.get("productSerials", []):
        if s.get("serial", "").upper() == serial_clean:
            return s
    return None


def find_product(sku: str) -> Optional[Dict]:
    """Look up a product by SKU."""
    data = load_demo_data()
    sku_clean = (sku or "").strip()
    for p in data.get("products", []):
        if p.get("sku") == sku_clean:
            return p
    return None


def find_claim(claim_number: str) -> Optional[Dict]:
    """Look up a warranty claim by claim number."""
    data = load_demo_data()
    cn_clean = (claim_number or "").strip()
    for c in data.get("warrantyClaims", []):
        if c.get("claimNumber") == cn_clean:
            return c
    return None


def days_between(iso_a: str, iso_b: str) -> int:
    """Naive integer days between two ISO date/datetime strings."""
    from datetime import datetime
    def parse(s: str):
        s = s.replace("Z", "+00:00")
        try:
            return datetime.fromisoformat(s)
        except ValueError:
            return datetime.fromisoformat(s + "T00:00:00+00:00")
    return (parse(iso_a) - parse(iso_b)).days
