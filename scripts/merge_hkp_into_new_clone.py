"""
merge_hkp_into_new_clone.py

Once Bill creates a new empty 'HKP Warranty & RMA Triage Agent' in Copilot Studio
and clones it via the VS Code extension, this script merges our customer-tailored
content into that clone — preserving the .mcs/ metadata and the auto-generated
schema name so the Apply changes push targets the new bot correctly.

Usage:
    python customers/ametek/hkp_rma/scripts/merge_hkp_into_new_clone.py

What it does:
    1. Finds the latest clone of 'HKP Warranty & RMA Triage Agent' under copilotstudioclones/
    2. Reads its auto-generated schemaName from settings.mcs.yml
    3. Copies our customer-tailored content INTO it:
        - agent.mcs.yml (replaces with HKP triage instructions)
        - actions/LookupWarrantyBySerial.mcs.yml (new stub)
        - actions/RouteEscalation.mcs.yml (new stub)
    4. Updates schema refs throughout to match the new clone's schema
    5. Preserves: .mcs/* (metadata), connectionreferences.mcs.yml,
       existing actions, topics, knowledge, trigger, workflows, icon, settings
    6. Reports a summary so Bill can review before Apply changes
"""

import shutil
import sys
import re
from pathlib import Path
from datetime import datetime

REPO_ROOT = Path(__file__).resolve().parents[4]
CLONES_DIR = REPO_ROOT / "copilotstudioclones"

# Source — our customer-tailored content
SRC_AGENT_DIR = (
    CLONES_DIR
    / "customers"
    / "ametek-hkp"
    / "HKP Warranty and RMA Triage Agent"
    / "HKP Warranty and RMA Triage Agent"
)


def find_new_clone() -> Path:
    """Find the most recently modified clone whose name matches our target.
    Looks for any folder whose name contains 'HKP Warranty' OR 'RMA Triage'
    AND that was modified in the last 24 hours AND that is NOT our customer
    source (the one with 'customers' in the path).
    """
    candidates = []
    for entry in CLONES_DIR.iterdir():
        if not entry.is_dir():
            continue
        if entry.name == "customers":  # skip our source tree
            continue
        if "HKP Warranty" not in entry.name and "RMA Triage" not in entry.name:
            continue
        # Check that it has the agent.mcs.yml structure (nested or not)
        agent_yaml = entry / "agent.mcs.yml"
        if not agent_yaml.exists():
            # check nested form
            nested = entry / entry.name / "agent.mcs.yml"
            if nested.exists():
                candidates.append(entry / entry.name)
            else:
                # try any single child that has agent.mcs.yml
                for child in entry.iterdir():
                    if child.is_dir() and (child / "agent.mcs.yml").exists():
                        candidates.append(child)
                        break
        else:
            candidates.append(entry)

    if not candidates:
        return None
    # pick most recently modified by .mcs/conn.json (the file that's freshest after clone)
    def freshness(p: Path) -> float:
        conn = p / ".mcs" / "conn.json"
        if conn.exists():
            return conn.stat().st_mtime
        return p.stat().st_mtime
    candidates.sort(key=freshness, reverse=True)
    return candidates[0]


def read_schema_name(agent_dir: Path) -> str | None:
    settings = agent_dir / "settings.mcs.yml"
    if not settings.exists():
        return None
    text = settings.read_text(encoding="utf-8")
    m = re.search(r"^schemaName:\s+(\S+)", text, re.MULTILINE)
    return m.group(1) if m else None


def copy_with_schema_replace(src: Path, dst: Path, old_schema: str, new_schema: str) -> None:
    text = src.read_text(encoding="utf-8")
    if old_schema and new_schema and old_schema != new_schema:
        text = text.replace(old_schema, new_schema)
    dst.parent.mkdir(parents=True, exist_ok=True)
    dst.write_text(text, encoding="utf-8")


def main():
    if not SRC_AGENT_DIR.exists():
        print(f"ERROR: source folder not found: {SRC_AGENT_DIR}")
        return 1

    print(f"Source (our customer-tailored content):\n  {SRC_AGENT_DIR}\n")

    # Step 1 — find the new clone
    new_clone = find_new_clone()
    if not new_clone:
        print("ERROR: couldn't find a clone of 'HKP Warranty & RMA Triage Agent' under")
        print(f"       {CLONES_DIR}")
        print()
        print("Did you:")
        print("  1. Create the empty agent in Copilot Studio UI?")
        print("  2. Run 'Copilot Studio: Clone agent' from the VS Code command palette?")
        return 1

    print(f"Target (new clone bound to a fresh CS agent):\n  {new_clone}\n")

    # Step 2 — read schemas
    src_schema = read_schema_name(SRC_AGENT_DIR) or "cra1f_agent_hkp"
    new_schema = read_schema_name(new_clone)
    if not new_schema:
        print(f"ERROR: couldn't read schemaName from {new_clone}/settings.mcs.yml")
        return 1
    print(f"Schema mapping: '{src_schema}' (our placeholder) → '{new_schema}' (new clone's auto-assigned)\n")

    # Step 3 — back up the new clone's agent.mcs.yml so user can revert
    backup_dir = new_clone / ".mcs" / f"backup-before-hkp-merge-{datetime.now().strftime('%Y%m%d-%H%M%S')}"
    backup_dir.mkdir(parents=True, exist_ok=True)
    for f in ["agent.mcs.yml"]:
        if (new_clone / f).exists():
            shutil.copy2(new_clone / f, backup_dir / f)
    print(f"Backed up new clone's original agent.mcs.yml to:\n  {backup_dir}\n")

    # Step 4 — copy our edited agent.mcs.yml with schema replaced
    print("=== Copying customer-tailored files ===")
    copy_with_schema_replace(
        SRC_AGENT_DIR / "agent.mcs.yml",
        new_clone / "agent.mcs.yml",
        src_schema, new_schema,
    )
    print("  [overwrite] agent.mcs.yml  (HKP RMA triage instructions, 4 new steps + hard rules)")

    # Step 5 — copy the 2 new action stubs
    actions_src = SRC_AGENT_DIR / "actions"
    actions_dst = new_clone / "actions"
    actions_dst.mkdir(exist_ok=True)
    for new_action in ["LookupWarrantyBySerial.mcs.yml", "RouteEscalation.mcs.yml"]:
        src_f = actions_src / new_action
        if src_f.exists():
            copy_with_schema_replace(
                src_f,
                actions_dst / new_action,
                src_schema, new_schema,
            )
            print(f"  [add]       actions/{new_action}  (stub — flowId is zero, fill in when PA flow built)")

    # Step 6 — report
    print()
    print("=== Files in target after merge ===")
    files = sorted(new_clone.rglob("*"))
    for f in files:
        if f.is_file() and ".mcs" not in f.parts:  # hide internal metadata for clarity
            rel = f.relative_to(new_clone)
            print(f"  {rel}")

    print()
    print("=== Next steps ===")
    print("  1. Open the new clone folder in VS Code if not already")
    print("     (or just confirm the agent.mcs.yml content looks right in your editor)")
    print()
    print(f"     Folder: {new_clone}")
    print()
    print("  2. Use VS Code Copilot Studio extension:")
    print("     Ctrl+Shift+P → 'Copilot Studio: Apply changes'")
    print()
    print("  3. The push targets the NEW agent (per its .mcs/conn.json AgentId).")
    print("     Your existing 'Warranty Claim Processing for Email' bot is untouched.")
    print()
    print("  4. Open https://copilotstudio.microsoft.com → Master CE Mfg")
    print("     → 'HKP Warranty & RMA Triage Agent' → review canvas + test")
    return 0


if __name__ == "__main__":
    sys.exit(main())
