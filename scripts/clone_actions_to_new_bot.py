#!/usr/bin/env python3
"""
clone_actions_to_new_bot.py

Read the 5 action botcomponents from the original 'Warranty Claim Processing for
Email' bot and POST clones of them onto our new 'HKP Warranty & RMA Triage Agent'
bot, with schemanames re-prefixed.

This is the missing piece — actions are componenttype=9 botcomponents (same as
topics) but with schemaname pattern '{bot_schema}.action.{Name}'.

Verified by reading the original bot's component list in Master CE.
"""

import subprocess
import sys
import requests

ORG_URL = "https://orgecbce8ef.crm.dynamics.com"

ORIG_BOT_ID = "5e16b1a5-ab89-f011-b4cc-7c1e525a3c6b"
ORIG_SCHEMA = "cra1f_agent"

NEW_BOT_ID = "e32ea13a-a248-f111-bec7-7ced8d18c8d7"
NEW_SCHEMA = "bw_HKPWarrantyRMATriageAgent"


def get_token() -> str:
    return subprocess.check_output(
        ["az", "account", "get-access-token", "--resource", ORG_URL,
         "--query", "accessToken", "-o", "tsv"],
        shell=True, text=True
    ).strip()


def dv_get(token: str, path: str) -> dict:
    r = requests.get(
        f"{ORG_URL}/api/data/v9.2/{path}",
        headers={"Authorization": f"Bearer {token}", "Accept": "application/json"},
        timeout=30,
    )
    r.raise_for_status()
    return r.json()


def dv_post(token: str, path: str, payload: dict) -> tuple[int, str]:
    r = requests.post(
        f"{ORG_URL}/api/data/v9.2/{path}",
        headers={
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json",
            "OData-MaxVersion": "4.0",
            "OData-Version": "4.0",
            "Prefer": "return=representation",
        },
        json=payload,
        timeout=30,
    )
    return r.status_code, r.text


def main():
    token = get_token()
    print(f"Source bot: {ORIG_BOT_ID} (schema {ORIG_SCHEMA})")
    print(f"Target bot: {NEW_BOT_ID} (schema {NEW_SCHEMA})")
    print()

    # 1. List action components on the original bot
    print("=== Reading actions from original bot ===")
    res = dv_get(
        token,
        f"botcomponents?$filter=_parentbotid_value eq {ORIG_BOT_ID} and componenttype eq 9 "
        f"and contains(schemaname, 'action.')&$select=botcomponentid,name,schemaname,data,componentidunique"
    )
    sources = res.get("value", [])
    print(f"  Found {len(sources)} actions on original bot")
    for s in sources:
        print(f"    - {s['name']}  (schema {s['schemaname']})")
    print()

    # 2. List existing components on new bot to skip dupes
    print("=== Reading existing actions on new bot (to skip dupes) ===")
    existing = dv_get(
        token,
        f"botcomponents?$filter=_parentbotid_value eq {NEW_BOT_ID} and componenttype eq 9 "
        f"and contains(schemaname, 'action.')&$select=schemaname"
    )
    existing_schemas = {c["schemaname"] for c in existing.get("value", [])}
    print(f"  Already on new bot: {len(existing_schemas)} action(s)")
    print()

    # 3. POST each action to the new bot
    print("=== Cloning actions to new bot ===")
    ok = 0
    fail = 0
    for src in sources:
        new_schema = src["schemaname"].replace(ORIG_SCHEMA, NEW_SCHEMA, 1)
        if new_schema in existing_schemas:
            print(f"  [skip] {src['name']} — already exists ({new_schema})")
            continue

        # Sometimes the data field references the old schema too; replace
        new_data = (src.get("data") or "").replace(ORIG_SCHEMA, NEW_SCHEMA)

        payload = {
            "name": src["name"],
            "componenttype": 9,
            "data": new_data,
            "schemaname": new_schema,
            "parentbotid@odata.bind": f"/bots({NEW_BOT_ID})",
        }
        status, body = dv_post(token, "botcomponents", payload)
        if 200 <= status < 300:
            print(f"  ✅ {src['name']}  →  {new_schema}  (HTTP {status})")
            ok += 1
        else:
            print(f"  ❌ {src['name']}  →  HTTP {status}")
            print(f"     body: {body[:300]}")
            fail += 1

    print()
    print(f"=== Summary: {ok} OK, {fail} failed ===")
    print()
    print("Now hard-refresh CS UI (Ctrl+F5) and re-run the test query.")
    print("If actions are wired correctly, the validation error should disappear.")
    return 0 if fail == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
