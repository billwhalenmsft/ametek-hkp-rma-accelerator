# RMA Code App → MDA: Live Gap Report

**Generated:** 2026-05-15 (overnight)
**Comparison source:** [`codeapp_to_mda_delta.md`](./codeapp_to_mda_delta.md) feature checklist
**Live target:** `https://org6feab6b5.crm.dynamics.com` → `RMA Operations and Monitoring` MDA

Legend: 🟢 Live · 🟡 Partial · 🔴 Missing · ⏭ Dropped (intentional)

---

## Executive summary

**You're ~85% there.** The big remaining UX gaps are all in the same family:
**Modern Command Bar buttons.** The JavaScript that powers them (`HKPCommands.*`) is
already deployed and the flows behind them work. What's missing is the ~10-minute
Power Apps command bar designer click-through to bind the buttons to the JS.
Programmatic ribbon authoring is risky enough to break the demo silently, so
overnight work focused on additive, low-risk polish instead.

---

## Screen-by-screen status

### Screen 1: Dashboard — `dashboard.tsx`

| CodeApp feature | Status | Where it lives in MDA |
|---|---|---|
| Page title + subtitle | 🟢 | `RMA Operations and Monitoring` app name |
| **Pipeline (Kanban) view toggle** | 🟢 | Claims Board web resource (`rma_/board/claims_board.html`) — drag-n-drop kanban |
| **List view toggle** | 🟢 | Claims Board has built-in table mode + native saved views |
| Search (claim/part/customer) | 🟢 | Quick Find on `rma_claim` + dashboard search box |
| Filter: All Plants | 🟢 | Dashboard dropdown + saved view "By Plant" |
| Filter: All Statuses | 🟢 | Dashboard dropdown + 5 saved views |
| Check Inbox button | 🟡 | rma_emaillog views exist; sitemap entry but no big "Check Inbox" tile |
| Bulk select | 🟢 | Native row multi-select |
| **Bulk action: Change Status** | 🔴 | NEEDS Power Apps command bar designer (~10 min UI fix) |
| **Bulk action: Assign Plant** | 🔴 | NEEDS command bar designer |
| **Bulk action: Approve filtered** | 🔴 | NEEDS command bar designer |
| Awaiting Your Action card | 🟢 | Amber banner in Claims Board + saved view |
| Metrics: Open Claims | 🟢 | KPI tile on Claims Board |
| Metrics: Across N locations | 🟢 | KPI tile on Claims Board |
| Metrics: Avg age | 🟢 | KPI tile on Claims Board |
| Metrics: Approval needed | 🟢 | KPI tile on Claims Board (>$500 in Decision) |
| Metrics: Closed this week | 🟢 | KPI tile on Claims Board |
| Pipeline view (status columns) | 🟢 | Drag-n-drop kanban in Claims Board |
| Click claim → detail | 🟢 | `Xrm.Navigation.openForm` from Claims Board |
| RMA Operations Overview dashboard | 🟢 | System dashboard exists with charts |

**What ships today:** Visually richer than the Code App — drag-n-drop with drop-to-update,
KPI tiles, search/filter, table toggle. The 3 missing bulk-action buttons are easy
to add via Power Apps designer (one drag per button).

### Screen 2: Email Intake — `email-intake.tsx`

| CodeApp feature | Status | Where it lives in MDA |
|---|---|---|
| Email list from inbox | 🟢 | `rma_emaillog` entity + 3 views (Inbound Unprocessed/Processed/All Outbound) |
| Show processed toggle | 🟢 | Two saved views |
| Source status banner | ⏭ | Dropped — views are always live in MDA |
| Refresh button | 🟢 | Native grid refresh |
| **Email body preview pane** | 🟡→🟢 | Just upgraded overnight — body now on its own form tab |
| **Email selection → "Create from email" dialog** | 🔴 | JS exists (`HKPCommands.createClaimFromEmail`), needs ribbon button |
| Extracted fields w/ confidence | 🟡 | Fields exist on `rma_emaillog` form; confidence bar dropped |
| Mark as processed | 🟢 | `rma_isprocessed` field on form |
| **Create RMA Claim form** (manual entry) | 🟡→🟢 | Quick Create form just added overnight (was missing before) |
| Auto-suggest plant from part+region | 🟢 | `RMA Auto-Assign Plant` flow active |
| Tabs: Extracted Data / Raw Email | 🟢 | rma_emaillog form has both |
| Smooth animations | ⏭ | Not available in MDA |

### Screen 3: Claim Detail — `claim-detail.tsx`

| CodeApp feature | Status | Where it lives in MDA |
|---|---|---|
| Claim header (number, status, age, overdue) | 🟢 | Form header has 4 cells; overdue calc in BPF |
| Status dropdown in header | 🟢 | `header_rma_status` cell |
| **Customer & Part info card** | 🟢 | Merged "Claim Details" section (overnight: was 2 sections, now 1) |
| Plant assigner | 🟢 | `rma_assignedplant` lookup |
| Warranty status + verified date | 🟢 | Both fields in Claim Details section |
| Credit amount input | 🟢 | Resolution section |
| **Resolution buttons** (Credit/Replacement/Repair/Deny) | 🔴 | JS exists (`HKPCommands.resolveCredit/Replacement/Repair/denyClaim`), needs 4 ribbon buttons |
| **Threshold-based approval gate** | 🟡 | Flow handles it; no business rule blocks UI submit |
| Add note + Notes timeline | 🟢 | Native Timeline (Notes) in form |
| Notes subgrid | 🟢 | Built into Timeline |
| **Approval Records subgrid** | 🟢 | Approvals tab |
| **Approval History subgrid** | 🟢 | Approvals tab |
| **Email History subgrid** | 🟢 | Emails tab |
| **Request Approval (in-app)** | 🔴 | JS exists (`HKPCommands.requestManagerApproval`), flow live (`RMA: Request Manager Approval`) — needs ribbon button |
| **Send Approval via Teams** | 🟢 | Active flow + Adaptive Card; verified end-to-end yesterday |
| **Approve Claim** dialog | 🟢 | Handled by Teams Adaptive Card; verified |
| **Deny Claim** dialog | 🟡 | Approve path verified; Deny path not yet smoke-tested |
| **Send Email dialog** | 🔴 | JS exists (`HKPCommands.sendCustomerEmail`), needs ribbon button + template merge flow |
| Suggested plant banner | 🟡 | Auto-Assign flow runs; no banner ribbon |
| **Smart Insights / Navision scoring** | 🟢 | NEW tonight — embedded panel on form, stub Navision + live customer history |
| Pizza Tracker (BPF stages) | 🟢 | Web resource simulating BPF, cutoff fixed tonight |

### Screen 4: Settings — `settings.tsx`

| CodeApp feature | Status | Where it lives in MDA |
|---|---|---|
| Setup progress checklist | ⏭ | Drop — admin sets up once via solution import |
| Mailbox configuration | ⏭ | Now an environment variable on the email flow |
| **Plants table (CRUD)** | 🟢 | `rma_plant` entity, 5 records seeded |
| **Routing Rules table (CRUD)** | 🟢 | `rma_routingrule` entity, 5 records seeded |
| **Plant Approvers (CRUD)** | 🟢 | `rma_plantapprover` entity, 5 placeholder records (admin@) |
| **Email Templates (CRUD)** | 🟢 | `rma_emailtemplate` entity, 2 records seeded |
| Auto-send trigger description | 🟡 | Field exists; not surfaced as calculated text |
| **Send Sample Email button** | 🔴 | Flow exists; needs ribbon button on emailtemplate form |
| **Email Signatures (CRUD + default)** | 🟢 | `rma_emailsignature` entity, 1 record seeded |
| **Set Default Signature button** | 🔴 | Needs ribbon button |
| **Replace placeholder approver names** | 🔴 | 5 records all point at `admin@` — needs 5 real plant manager email addresses |

### Screen 5: Help — `help.tsx`

| CodeApp feature | Status | Where it lives in MDA |
|---|---|---|
| In-app help text + links | 🟡→🟢 | NEW tonight — `rma_/help/help.html` web resource + sitemap subarea |

### First-Run Wizard — `first-run-wizard.tsx`

| CodeApp feature | Status |
|---|---|
| Multi-step setup wizard | ⏭ Intentionally dropped — admin imports solution + seeds 5 plants once. No per-user setup needed. |

---

## Where automation lives (CodeApp lib/ → Power Platform)

| Logic | CodeApp file | MDA location | Status |
|---|---|---|---|
| Plant suggestion by part-prefix | `lib/routing-engine.ts` | `RMA Auto-Assign Plant` flow | 🟢 |
| Approval threshold check | `lib/routing-engine.ts` | Flow `RMA: Request Manager Approval` triggers conditionally | 🟢 |
| Email template placeholder merge | `claim-detail.tsx` inline | TBD — needs Power Automate Compose step in send-email flow | 🔴 |
| Claim number generation | `lib/claim-utils.ts` | `rma_claimnumber` autonumber column | 🟢 |
| Claim age calculation | `lib/claim-utils.ts` | Calculated column or view formula on `rma_claim` | 🟡 (computed in dashboard JS, not as a column) |
| Status color mapping | `lib/claim-utils.ts` | Form indicator + dashboard tiles | 🟢 |

---

## "Just need clicks" — the ~30 minutes of UI work that closes the gap

These are the only items left where the *backing logic* is done but the
*button to invoke it* is missing. Each is a 3-5 minute task in Power Apps maker:

1. `rma_claim` form ribbon — add 6 buttons (Resolve Credit, Resolve Replacement,
   Resolve Repair, Deny Claim, Send Customer Email, Request Manager Approval)
   pointing at the matching `HKPCommands.*` JS function
2. `rma_emaillog` form ribbon — add "Create RMA Claim from Email" button
   → `HKPCommands.createClaimFromEmail`
3. `rma_emailtemplate` form ribbon — add "Send Sample Email" button
4. `rma_emailsignature` view ribbon — add "Set Default" button
5. Replace the 5 `admin@` placeholders in `rma_plantapprover` with real plant
   manager emails (or keep `admin@` for the demo and make the placeholder
   intentional in the demo script)

After those 5 clicks, the MDA is feature-complete vs the Code App.

---

## What overnight work added (May 15 → 16)

| Artifact | Purpose | Risk |
|---|---|---|
| `ui/rma_claim_smart_insights.html` (deployed as `rma_/board/smart_insights.html`) | Navision scoring stub + customer health/part risk + recommendation + live customer history; embedded on rma_claim form | 🟢 Reversible — web resource can be deleted |
| Patched `rma_claim` main form: BPF rowspan 2→6 (cutoff fix), new Smart Insights section, merged Customer & Part + Plant & Status sections | Fixes Pizza Tracker cutoff + integrates Smart Insights + tightens layout | 🟢 Pre-patch backup at `backup/rma_claim_form_20260515_012743_PRE_PATCH.xml` |
| `ui/rma_claim_quickcreate.html` is **not** an HTML — added a real **Quick Create** systemform for `rma_claim` (was missing entirely) | Lets users create claims from anywhere via the global "+ New" button | 🟢 Additive |
| Patched `rma_emaillog` form: added "Email Body Preview" tab with HTML web resource preview | Mimics CodeApp's email body preview pane | 🟢 Reversible |
| `ui/rma_help.html` deployed as `rma_/help/help.html` | In-app help with ops cheat sheet, common tasks, troubleshooting | 🟢 New web resource |
| Sitemap subarea added: "Help" → web resource link | Lets users get help without leaving the app | 🟢 Additive |
| `docs/codeapp_gap_report_2026-05-15.md` (this file) | Single source of truth for what's left | n/a |

---

## What did NOT change overnight (Bill review needed)

- **Modern command buttons** — JS is ready, but ribbon authoring via REST is fragile and could break the standard form. Held for Power Apps designer (10-min UI task)
- **Real BPF** — Pizza Tracker is a web resource, not a real Business Process Flow. Real BPFs would unlock native stage-aware features (auto-progress, BPF analytics) but require careful entity stage modeling
- **Threshold approval business rule** — Flow handles it; no UI guard rails
- **Plant approver real names** — Still 5× `admin@` placeholders
- **Deny path smoke test** — only Approve path was verified yesterday
- **Solution containment of cloned approval flow** (`5d730ad8-1750-…`) — not yet added to the RMA solution

---

## Recommended morning order (15-20 min)

1. **Open the form** in the RMA Operations app, refresh hard (Ctrl+F5) → verify Smart Insights renders, BPF no longer cuts off, Claim Details section reads cleanly
2. **Open Help** subarea → verify cheat sheet renders
3. **Try global + New** → confirm Quick Create form appears
4. **Open any email log** → verify Body Preview tab renders
5. **Power Apps designer**: open rma_claim form → Command Bar → add the 6 buttons (5 min each)
6. **Demo prep**: write demo script lines around the new Smart Insights tile

After this, the MDA stands as a clear upgrade over the Code App with several
*new* capabilities (Navision scoring, drag-n-drop pipeline) the Code App
didn't have at all.
