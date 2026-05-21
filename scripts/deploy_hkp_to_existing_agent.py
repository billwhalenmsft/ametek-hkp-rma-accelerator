#!/usr/bin/env python3
"""
deploy_hkp_to_existing_agent.py

Direct Dataverse PATCH/POST to push our customer-tailored content into the
existing HKP Warranty & RMA Triage Agent bot in Master CE Mfg.

Why direct REST: VS Code Copilot Studio extension Clone keeps failing with
"Server was requested to shut down" so we bypass the extension entirely.

What this does:
1. Reads our customer-tailored agent.mcs.yml (HKP triage instructions)
2. Extracts the instructions block + conversationStarters
3. PATCHes the bot's componenttype=15 GPT component with this content
4. Reports

What it does NOT do (yet):
- Add the 2 new stub actions (LookupWarrantyBySerial, RouteEscalation) — those
  need real PA flow GUIDs first. We can add them as componenttype=11 components
  in a follow-up once flows exist.

This pattern is documented in /memories/power-platform-deploy.md.
Verified working for AMETEK SFMS (commit a55d16006-ish) — same approach.
"""

import json
import re
import subprocess
import sys
from pathlib import Path

import requests

ORG_URL = "https://orgecbce8ef.crm.dynamics.com"
BOT_ID = "e32ea13a-a248-f111-bec7-7ced8d18c8d7"
GPT_COMPONENT_ID = "3e3eb030-1d24-48cb-97cd-f5f1382c4249"
BOT_SCHEMA = "bw_HKPWarrantyRMATriageAgent"

REPO_ROOT = Path(__file__).resolve().parents[4]
SOURCE_AGENT = (
    REPO_ROOT
    / "copilotstudioclones"
    / "customers"
    / "ametek-hkp"
    / "HKP Warranty and RMA Triage Agent"
    / "HKP Warranty and RMA Triage Agent"
    / "agent.mcs.yml"
)


def get_token() -> str:
    return subprocess.check_output(
        ["az", "account", "get-access-token", "--resource", ORG_URL,
         "--query", "accessToken", "-o", "tsv"],
        shell=True, text=True
    ).strip()


def dv_patch(token: str, path: str, payload: dict) -> tuple[int, str]:
    r = requests.patch(
        f"{ORG_URL}/api/data/v9.2/{path}",
        headers={
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json",
            "OData-MaxVersion": "4.0",
            "OData-Version": "4.0",
            "If-Match": "*",
        },
        json=payload,
        timeout=60,
    )
    return r.status_code, r.text


def main():
    if not SOURCE_AGENT.exists():
        print(f"ERROR: source not found: {SOURCE_AGENT}")
        return 1

    raw = SOURCE_AGENT.read_text(encoding="utf-8")
    print(f"Source: {SOURCE_AGENT.name} ({len(raw)} chars)")

    # The source uses placeholder schema cra1f_agent_hkp; swap to the real one
    raw = raw.replace("cra1f_agent_hkp", BOT_SCHEMA)
    raw = raw.replace("cra1f_agent", BOT_SCHEMA)  # safety belt

    # The PATCH target's `data` field expects exactly the GptComponentMetadata
    # YAML — same shape as what's there now. Our agent.mcs.yml IS that shape.
    # We can send it as-is.
    new_data = raw

    print(f"Bot: {BOT_ID}")
    print(f"GPT component: {GPT_COMPONENT_ID}")
    print(f"New data: {len(new_data)} chars")
    print()

    print("=== PATCH botcomponents({GPT_COMPONENT_ID}) ===")
    token = get_token()
    status, body = dv_patch(
        token,
        f"botcomponents({GPT_COMPONENT_ID})",
        {"data": new_data},
    )

    if 200 <= status < 300:
        print(f"  ✅ HTTP {status} — pushed")
        print()
        print("=== Verify ===")
        r = requests.get(
            f"{ORG_URL}/api/data/v9.2/botcomponents({GPT_COMPONENT_ID})?$select=name,data",
            headers={"Authorization": f"Bearer {token}", "Accept": "application/json"},
            timeout=30,
        )
        if r.ok:
            j = r.json()
            d = j.get("data", "")
            has_step6 = "Step 6 — Look up warranty status" in d
            has_step9 = "Step 10 — Branch on disposition" in d
            has_starters = "Triage New RMA Email" in d
            print(f"  HKP Step 6 in bot data?     {'✅' if has_step6 else '❌'}")
            print(f"  HKP Step 9 in bot data?     {'✅' if has_step9 else '❌'}")
            print(f"  HKP starter prompts?        {'✅' if has_starters else '❌'}")
        print()
        print("=== Next steps ===")
        print(f"1. Browser: https://copilotstudio.microsoft.com → Master CE Mfg")
        print(f"2. Open: HKP Warranty & RMA Triage Agent")
        print(f"3. Hard refresh (Ctrl+F5) — instructions should now show the 10-step flow")
        print(f"4. Test pane → try: 'What's the warranty status of serial IDEA-57-2025-104872?'")
        print(f"5. Click Publish in CS UI when ready")
        return 0
    else:
        print(f"  ❌ HTTP {status}")
        print(f"  Body: {body[:600]}")
        return 1


if __name__ == "__main__":
    sys.exit(main())
