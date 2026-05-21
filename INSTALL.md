# HKP RMA Returns Monitor — Install Guide

> Customer-ready install for the **AMETEK Haydon Kerk Pittman (HKP) RMA Returns Monitor**
> model-driven app, on top of the existing `WarrantyandClaimOperations` Dataverse base.

## What you get

A complete Dynamics 365 model-driven app that runs the end-to-end RMA workflow:

- **Intake** (email-to-claim parser, Quick Create form, ack email)
- **Triage** (auto-assignment by plant, routing rules, kanban board)
- **Approval** (dollar-tier threshold approvals via Teams Approvals)
- **Resolution** (Credit / Replacement / Repair / Deny modals with editable
  amount + override-reason banner + email templates + ERP/Navision audit trail)
- **Dashboards** (Pizza Tracker, Smart Insights, Email Inbox, Claims Board)
- **In-app Help** (`Help` group in sitemap — full operator guide v5)

All packaged as the `RMAReturnsMonitor` Power Platform solution.

---

## Prerequisites

1. **Power Platform environment** with Dataverse, the existing
   `WarrantyandClaimOperations` v1.0.0.14 solution already installed, and
   **System Administrator** role for the installing identity.
2. **Approvals app** enabled in Teams (used by the manager-approval flow).
3. **Tooling on your machine:**
   - PowerShell 7+
   - [Power Platform CLI](https://learn.microsoft.com/en-us/power-platform/developer/cli/introduction)
     ```powershell
     dotnet tool install --global Microsoft.PowerApps.CLI.Tool
     ```
   - [Azure CLI](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli)
     (`az login` — scripts use Azure CLI to acquire Dataverse tokens)
4. **Two connections** ready in your target environment (the scripts re-use
   the connection-reference logical names from this repo; if your env names
   differ, see *Connection refs* below):
   - Microsoft Dataverse — service principal or admin account
   - Approvals — same identity as Dataverse

---

## Install in 4 steps

### 1. Authenticate

```powershell
az login
pac auth create --url https://<your-org>.crm.dynamics.com
```

### 2. Import the solution

Pick **one**:

**A. Managed (recommended for customer envs):**
```powershell
pac solution import `
  --path customers/ametek/hkp_rma/solution/RMAReturnsMonitor_managed.zip `
  --activate-plugins --publish-changes
```

**B. Unmanaged (dev / further customization):**
```powershell
pac solution import `
  --path customers/ametek/hkp_rma/solution/RMAReturnsMonitor_unmanaged.zip `
  --activate-plugins --publish-changes
```

This installs:
- All `rma_*` tables (claim, approval record/history, plant, plant approver,
  routing rule, email template, email log, …)
- The `RMA Operations and Monitoring` model-driven app + sitemap
- Web resources (pizza tracker, smart insights, kanban, email inbox, help)
- 5 PA flows (Email Monitor, Auto-Assign Plant, Stage Tracker, Request
  Manager Approval, Push Resolution to ERP stub)
- 4 fluent icons + ribbon JS

### 3. Register flow trigger webhooks (one-time, per environment)

> Known Power Platform behavior: flows imported via `pac solution import`
> get installed and activated, but their Dataverse trigger webhooks are
> **not registered until they are opened + saved once** in the maker UI.

For **each** of these flows, in [make.powerautomate.com](https://make.powerautomate.com):

1. `RMA Email Monitor`
2. `RMA Auto-Assign Plant`
3. `RMA Stage Tracker`
4. `RMA: Request Manager Approval`
5. `RMA: Push Resolution to ERP (stub)`

…open, click **Edit** → **Save** (no changes needed). After saving once, the
flow fires automatically on the configured Dataverse trigger forever after.

### 4. Seed reference data

From the repo root, in this order:

```powershell
# Plants + routing rules + email templates (denial)
.\customers\ametek\hkp_rma\scripts\seed_rma_routing_and_email.ps1
.\customers\ametek\hkp_rma\scripts\replace_plants_with_ametek_hkp.ps1

# Resolution email templates (Credit / Replacement / Repair)
.\customers\ametek\hkp_rma\scripts\seed_resolution_templates.ps1

# (Optional) demo serials + sample claims for smoke testing
.\customers\ametek\hkp_rma\scripts\seed_hkp_serials.ps1
.\customers\ametek\hkp_rma\scripts\seed_rma_sample_data.ps1
```

Each seed script is idempotent — safe to re-run.

---

## Smoke test (5 minutes)

1. Open the `RMA Operations and Monitoring` app.
2. **Intake**: create a new claim via *+ New Claim* (Quick Create). Confirm
   the claim auto-assigns to the right plant + CSR by routing rules within ~30s.
3. **Approval**: open a claim, click *Request Approval* with $1500. Approver
   gets a Teams Approvals card → approve. Claim closes, `rma_approvalhistory`
   row written.
4. **Resolution**: on a different claim, click *Issue Credit*. Modal pre-fills
   approved amount; override to a different value → override-reason banner
   appears → confirm reason → email body re-merges → Send. Confirm a
   `rma_approvalhistory` row appears with `rma_erpstatus = Pending`, then
   within ~30s flips to `Sent` with `rma_erpreference = STUB-NAV-xxxxxxxxxxxx`.
5. **Help**: click the *Help* group in the sitemap → full operator guide
   should render with TOC §1 – §13.

---

## Connection refs

Out-of-the-box, the solution references these connection-reference logical
names (matching the Mfg Gold Template source env):

| Connector | Connection ref logical name |
|---|---|
| Microsoft Dataverse | `cr74e_warrantyChecker.shared_commondataserviceforapps.shared-commondataser-9933c9ef-b98c-4170-8251-695bb41a22f2` |
| Microsoft Approvals | `cr74e_sharedapprovals_453c9` |

If your target environment uses different conn-ref names, after import:

1. Open each flow in the maker UI
2. Replace the broken/red connection on each action with one bound to the
   right account in the target env
3. Save the flow

---

## Swapping the ERP stub for real Navision

The `RMA: Push Resolution to ERP (stub)` flow currently writes a fake
`STUB-NAV-xxxxxxxxxxxx` reference. To wire it to real Microsoft Dynamics 365
Business Central / Navision:

1. Open the flow in the maker UI.
2. After the `Build_ERP_payload` Compose, **replace** the `Push_to_ERP_STUB`
   Compose with the real connector action:
   - **Business Central** connector → *Create item*, or
   - **HTTP** action → Navision OData endpoint, or
   - **Custom connector** to your Navision instance.
3. Map the returned ERP reference back into the *Update history row* PATCH
   `rma_erpreference` field (instead of the stub-generated GUID).
4. Save.

Full reference: open the in-app **Help** → §13 *Resolution & ERP*.

---

## Folder layout in this delivery

```
customers/ametek/hkp_rma/
├── INSTALL.md                  ← this file
├── README.md                   ← internal architecture notes
├── solution/
│   ├── RMAReturnsMonitor_managed.zip       ← prod install
│   └── RMAReturnsMonitor_unmanaged.zip     ← dev/customize install
├── scripts/                                ← deploy + seed PowerShell
│   ├── seed_resolution_templates.ps1
│   ├── seed_rma_routing_and_email.ps1
│   ├── replace_plants_with_ametek_hkp.ps1
│   ├── add_resolution_fields.ps1           ← idempotent schema patcher
│   └── clone_*.ps1                         ← rebuild PA flows from source
├── ui/                                     ← HTML web resources (source)
│   ├── rma_pizza_tracker.html
│   ├── rma_smart_insights.html
│   ├── rma_email_inbox.html
│   ├── rma_help.html
│   └── …
└── d365/
    └── hkp_rma_form_commands.js
```

The **solution ZIPs** are the canonical install artifacts. The `scripts/`,
`ui/`, and `d365/` folders are kept for source-control + auditability + future
customization — they are **not** required for install if you use the ZIPs.

---

## Support / contact

This solution accelerator is delivered by the **Microsoft Manufacturing
Industry team** as a starter kit. Customer customizations welcome — solution
is unmanaged-import friendly. File issues at:

https://github.com/billwhalenmsft/CommunityRAPP-BillWhalen/issues

— Bill Whalen, Microsoft (bwhalen@microsoft.com)
