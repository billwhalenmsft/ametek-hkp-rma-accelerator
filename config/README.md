# HKP RMA — Customer-Specific Configuration

This folder holds the **customer-specific config** for the HKP Warranty & RMA Triage Agent. The agent's logic (in `copilotstudioclones/customers/ametek-hkp/.../agent.mcs.yml`) is generic; everything that's HKP-specific lives here.

## The 6 config files

| File | Purpose | Calibration source |
|---|---|---|
| `failure_modes.json` | Defect / misuse / installation keyword libraries | Customer call — top-10 failure modes for iDEA motors |
| `product_families.json` | SKU prefix → family + warranty months | HKP product catalog + OEM contracts |
| `oem_tiers.json` | Account → tier for priority routing | HKP sales team — annual revenue / strategic-tier list |
| `engineer_roster.json` | Product family → Quality Engineer + Teams ID | HKP eng leadership — current QE assignments |
| `eligibility_rules.json` | Confidence thresholds + grace days | Warranty terms doc + customer-call decisions |
| `email_templates.json` | Per-disposition customer email content | HKP brand voice + legal review |

## Status

| File | State |
|---|---|
| `failure_modes.json` | 🟡 Starter content — replace after customer call captures real top failure modes |
| `product_families.json` | 🟡 Starter — confirm warranty months by SKU + OEM contract deviations |
| `oem_tiers.json` | 🟡 Starter — confirm tier list with sales |
| `engineer_roster.json` | ❌ MOCK — replace with real names + Teams user IDs |
| `eligibility_rules.json` | 🟡 Starter — confirm thresholds (especially borderline grace days) |
| `email_templates.json` | 🟡 Starter — confirm brand voice + signature, legal review |

## How the agent reads these in production

In dev: the agent's instructions block references these files by path (for documentation).

In production: each config maps to a **Dataverse environment variable** (or solution component) that the agent reads at runtime. We'd:
1. Convert each JSON to a Dataverse solution component (or env variable)
2. Update the agent's instructions to reference the env var name
3. Customer admins can update config via Power Platform admin center without touching the agent itself

## Reusing this pattern for other customers

To stand up the same agent for a different customer (e.g. `customers/abc-window-co/rma/config/`):

1. Copy the 6 JSON files
2. Customize each for the new customer (failure modes, products, tiers, engineers, rules, templates)
3. Deploy a fresh agent copy (clone from `copilotstudioclones/customers/ametek-hkp/...` and update `customers` path references)
4. Same logic, different config, different customer

This is the **"generic logic + per-customer config" pattern** — see `customers/ametek/hkp_rma/ui/warranty_bot_current_state_and_gaps.html` § 5 for the full reusability story.
