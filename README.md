# AMETEK HKP RMA Returns Monitor — Solution Accelerator

> A turnkey **Microsoft Dynamics 365** model-driven app for managing
> Return Material Authorization (RMA) workflows end-to-end —
> built for **AMETEK Haydon Kerk Pittman** on top of the
> existing `WarrantyandClaimOperations` Dataverse base.

## What it does

| Stage | Capability |
|---|---|
| **Intake** | Email-to-claim parsing, Quick Create form, customer ack email |
| **Triage** | Auto-assignment by plant, configurable routing rules, kanban + Pizza Tracker |
| **Approval** | Dollar-tier manager approvals via Microsoft Teams Approvals |
| **Resolution** | Credit / Replacement / Repair / Deny modals with template picker, editable amount, override-reason banner, email send, full audit trail |
| **ERP** | Pluggable stub flow that pushes resolutions to Navision / Business Central — ready to wire to your real ERP |
| **Insights** | Smart Insights dashboard, Email Inbox, Claims Board, in-app Help v5 |

## Quick start

1. Read [INSTALL.md](INSTALL.md) — covers prerequisites, the 4-step
   install sequence, smoke test, and connection-reference overrides.
2. Import [`solution/RMAReturnsMonitor_managed.zip`](solution/) into your
   target Dataverse environment.
3. Open each of the 5 included PA flows in
   [make.powerautomate.com](https://make.powerautomate.com) and click
   **Save** once (this registers the Dataverse trigger webhook — known
   Power Platform limitation).
4. Run the seed scripts in [`scripts/`](scripts/) to load reference data.
5. Open the `RMA Operations and Monitoring` app and start using it.

## What's in this repo

```
.
├── INSTALL.md                              ← step-by-step install guide
├── solution/
│   ├── RMAReturnsMonitor_managed.zip       ← prod install (recommended)
│   └── RMAReturnsMonitor_unmanaged.zip     ← dev / customization
├── scripts/                                ← idempotent deploy + seed scripts
│   ├── seed_resolution_templates.ps1
│   ├── seed_rma_routing_and_email.ps1
│   ├── replace_plants_with_ametek_hkp.ps1
│   ├── add_resolution_fields.ps1
│   └── clone_*.ps1                         ← rebuild PA flows from JSON source
├── ui/                                     ← HTML web-resource source
│   ├── rma_pizza_tracker.html
│   ├── rma_smart_insights.html
│   ├── rma_email_inbox.html
│   ├── rma_help.html                       ← in-app operator guide v5
│   └── …
├── d365/
│   └── hkp_rma_form_commands.js            ← form ribbon JS
├── agents/                                 ← 6 supporting RAPP agents (optional)
└── docs/                                   ← architecture + handoff notes
```

The **solution ZIPs in [`solution/`](solution/)** are the canonical install
artifacts. The other folders are kept for source control + future
customization — they are *not required* if you only want to install.

## Architecture highlights

- **9 custom tables** (`rma_*`): claim, approval record, approval history,
  plant, plant approver, routing rule, email template, email log, stage tracker
- **5 PA flows**: Email Monitor, Auto-Assign Plant, Stage Tracker,
  Request Manager Approval (with dollar-tier threshold filter),
  Push Resolution to ERP (stub)
- **10 web resources** + 12 fluent icons + 1 sitemap + 1 app module + app actions
- **Approval flow** filters approvers by `rma_plant`, `rma_isactive`, and
  `rma_notifywhen` (All Claims / High Value Only / Manual) with optional
  `rma_highvaluethreshold` dollar gate
- **Resolution modals** support amount override with mandatory reason banner,
  template-based email send, and write a full `rma_approvalhistory` audit
  row that triggers the ERP push flow asynchronously
- **ERP stub** generates `STUB-NAV-xxxxxxxxxxxx` references — swap the
  `Push_to_ERP_STUB` Compose action for a real Business Central / Navision
  connector to go live (see [INSTALL.md](INSTALL.md#swapping-the-erp-stub-for-real-navision))

## Customization

The unmanaged solution is fully customizable:

- Edit web resources via source in [`ui/`](ui/) → re-deploy with the
  matching `scripts/deploy_*.ps1`
- Edit PA flows in the Power Automate maker UI directly
- Add columns / picklist options via `scripts/add_*.ps1` (all idempotent)
- Re-pack the solution via `pac solution export --name RMAReturnsMonitor`

## Support

Delivered by the **Microsoft Manufacturing Industry** team.

- **Issues / feature requests:** file in this repo
- **Maintainer:** Bill Whalen — `bwhalen@microsoft.com`

## License

This solution accelerator is provided **as-is, without warranty**, as a
starter kit for AMETEK Haydon Kerk Pittman. Microsoft does not provide
production support for accelerator content; customer customizations
should follow standard Power Platform ALM practices.
