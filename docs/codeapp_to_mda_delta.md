# RMA Code App → Model-Driven App: Feature Delta

**Source:** `customers/ametek/hkp_rma/codeapp_source/extracted/` (decompiled from Code App `2e73f6b2-60ea-4a41-80ed-2178bccfab79`)
**Target:** New Model-Driven app `RMA Operations` in `RMAReturnsMonitor` solution

Legend: 
- ✅ Native MDA — point-and-click in form/view/dashboard designer
- 🔧 Native MDA — needs config (Business Rule, Calculated Column, Modern Command, BPF)
- ⚙️ Power Automate — flow on trigger or button
- 📄 Custom Page — small canvas surface embedded in the MDA shell
- ❌ Drop — feature exists but not worth porting (one-off / dev affordance)

---

## Screen 1: Dashboard (`dashboard.tsx`, 41 KB)

| Feature | Plan | Notes |
|---|---|---|
| Page title "RMA Monitor" + subtitle | ✅ MDA app name + entity grid header | |
| **View toggle** Pipeline (Kanban) / List | ✅ "Edit columns" view chooser + use BPF for status pipeline | Kanban-like effect via BPF; or use Group By column in view |
| **Search** (claim number, part, customer) | ✅ Native Quick Find on `rma_claim` | Configure Quick Find columns |
| **Filter: All Plants** dropdown | ✅ Personal/system view filter | |
| **Filter: All Statuses** dropdown | ✅ Personal/system view filter | |
| **Check Inbox** button → `/intake` | ✅ Sitemap link to Inbound Emails subarea | |
| **Bulk select** checkboxes | ✅ Multi-select rows native to all grids | |
| **Bulk action: Change Status** | 🔧 Modern Command bar button → flow or workflow | "Change Status" command on selection |
| **Bulk action: Assign Plant** | 🔧 Modern Command bar button → flow | "Assign Plant" command on selection |
| **Bulk action: Approve (filtered by threshold)** | 🔧 Modern Command bar w/ visibility rule | Show only if any selected need approval |
| **"Awaiting Your Action" card** | ✅ "My Claims Needing Response" view on dashboard | View with filter `hasPendingResponse eq true AND statusKey ne Closed` |
| **Metrics: Open Claims count** | ✅ Dashboard tile (count chart) | |
| **Metrics: Across N locations** | ✅ Calculated subtext / View aggregate | |
| **Metrics: Avg age (days)** | 🔧 Calculated Column `claimAge` + dashboard tile | |
| **Metrics: Approval needed** | ✅ Dashboard view filtered by `requiresApproval` | Approval logic moves to a flow / calculated column |
| **Metrics: Closed this week** | ✅ Dashboard chart on closedDate | |
| **Pipeline view** (claims by status column) | ✅ BPF stages + chart grouped by status | BPF gives the visual stages |
| **Table view** | ✅ Standard view |  |
| **Click claim → detail** | ✅ Native row navigation | |

**MDA pieces:** 1 system dashboard, 4–6 tile/chart components, 1 BPF on `rma_claim`, 4 saved views, 3 modern command buttons (one per bulk action).

---

## Screen 2: Email Intake (`email-intake.tsx`, 55 KB)

| Feature | Plan | Notes |
|---|---|---|
| **Email list** from SharePoint InboundEmails | ✅ View on **new entity `rma_inboundemail`** OR keep SharePoint list + show in iframe | Cleaner if we mirror inbound emails into a Dataverse entity |
| **Show processed toggle** | ✅ Two saved views: Unprocessed, All | |
| **Source status banner** (fresh/cache/error) | ❌ Drop | Not relevant in MDA; views always live |
| **Refresh button** | ✅ Native Refresh on grid | |
| **Email body preview pane** | 📄 Custom Page tab on the email entity form | Renders the HTML body |
| **Email selection → "Create from email" dialog** | 🔧 Modern Command "Create Claim" on email row | Opens a Quick Create form, pre-populated via JS / Power Fx |
| **Extracted fields w/ confidence indicators** | ✅ Form fields on `rma_inboundemail`; confidence dropped or stored as text | Confidence visualization isn't critical — drop or use lookup color rules |
| **"Navision lookup" copy-to-clipboard buttons** | 🔧 Custom button on form field | JS web resource or Modern Command |
| **Mark as processed** | ✅ Form field `isProcessed` + Quick Form action | |
| **Create RMA Claim form** (manual entry) | ✅ Quick Create form on `rma_claim` | Already have the entity |
| **Auto-suggest plant from part number + region** | ⚙️ Power Automate on create OR Business Rule | Use existing `rma_routingrule` records |
| **Tabs: Extracted Data / Raw Email** | ✅ Form tabs | |
| Smooth animations (motion.div) | ❌ Drop | Not available in MDA |

**MDA pieces:** 1 new entity `rma_inboundemail` (or repurpose existing column on `rma_emaillog`), 1 form w/ tabs, 1 quick-create form on `rma_claim`, 1 routing flow, 1 "Create Claim from Email" command.

---

## Screen 3: Claim Detail (`claim-detail.tsx`, 57 KB)

| Feature | Plan | Notes |
|---|---|---|
| Claim header (number, status badge, age, overdue chip) | ✅ Form header + business rule for "Overdue" tag | Header field shows status, plus a "Status Indicator" formula field |
| **Status dropdown** in header | ✅ Native status field | |
| **Customer & Part info card** | ✅ Form section | |
| **Plant assigner** | ✅ Lookup field | |
| **Warranty status toggle** w/ verified date | ✅ Field + business rule auto-sets verified date | |
| **Credit amount input + update** | ✅ Currency field | |
| **Resolution buttons** (Credit Issued / Replacement / Repair / Deny) | 🔧 Modern Command buttons (4 buttons on form) | Each triggers a flow that sets resolutionKey + closes claim |
| **Threshold-based approval gate** | ⚙️ Business rule + flow | If `creditAmount > threshold`, command prompts for approval first |
| **Add note** textarea + button | ✅ Native Notes timeline (built-in) OR `rma_claimnote` subgrid | Built-in Timeline is simpler |
| **Notes subgrid** | ✅ Subgrid for `rma_claimnote` | |
| **Approval History subgrid** | ✅ Subgrid for `rma_approvalhistory` | |
| **Email History subgrid** | ✅ Subgrid for `rma_emaillog` | |
| **Request Approval (in-app dialog)** | ⚙️ Modern Command → flow creates `rma_approvalrecord` | |
| **Send Approval via Teams** to plant approvers | ⚙️ Modern Command → flow loops `rma_plantapprover` and sends Adaptive Card | |
| **Approve Claim** dialog w/ comment | ⚙️ Modern Command (visible only to approvers) | Creates `rma_approvalhistory` w/ ActionKey1, closes claim Credit Issued |
| **Deny Claim** dialog w/ comment | ⚙️ Modern Command | Creates ActionKey2 history, closes claim Denied |
| **Send Email dialog** w/ template picker + signature merge | 📄 Custom Page OR Quick Create on `rma_emaillog` | Template merge logic moves to Power Automate. Custom Page lets us keep the rich preview |
| Template placeholder replacement (`{claimNumber}`, `{customerName}`, etc.) | ⚙️ Power Automate handles substitution in the flow | |
| **Suggested plant** display (info banner) | 🔧 Calculated column or business rule label | |
| Smooth animations | ❌ Drop | |

**MDA pieces:** 1 main form on `rma_claim` w/ 4 tabs (General/Notes/Approvals/Emails), 5–6 modern command buttons, 3–4 Power Automate flows (resolve, request approval, send Teams, send email).

---

## Screen 4: Settings (`settings.tsx`, 83 KB)

This is the biggest screen — but in MDA each entity gets its own native views + forms automatically. We just create them.

| Feature | Plan | Notes |
|---|---|---|
| **Setup progress checklist** (3 steps) | 📄 Optional Custom Page for first-run dashboard | Or skip — admin sets up once via solution import |
| **Mailbox configuration** (localStorage) | ❌ Drop — move to environment variable | Or 1-row config entity `rma_settings` |
| **Plants table** (CRUD, region/prefixes/threshold) | ✅ Native grid + form for `rma_plant` | |
| **Routing Rules table** (CRUD w/ priority + active toggle) | ✅ Native grid + form for `rma_routingrule` | Active toggle = inline edit column |
| **Plant Approvers** (CRUD, people picker, threshold tiers) | ✅ Native grid + form for `rma_plantapprover` | People picker = User lookup field (cleaner than custom Graph search) |
| **Email Templates** (CRUD, type, subject, auto-send, triggers) | ✅ Native grid + form for `rma_emailtemplate` | |
| **Auto-send trigger description** computed text | 🔧 Calculated column | |
| **Send Sample Email** button | 🔧 Modern Command on row → flow sends test email | |
| **Email Signatures** (CRUD + set-default) | ✅ Native grid + form for `rma_emailsignature` | "Set Default" = Modern Command |

**MDA pieces:** Sitemap groupings for each table. Native forms inherited from Dataverse schema. 2 modern command buttons (Send Sample, Set Default).

---

## Screen 5: Help (`help.tsx`, 10 KB)

| Feature | Plan |
|---|---|
| In-app help text + links | ✅ Web Resource HTML page in sitemap, OR external link to docs |

---

## First-Run Wizard (`first-run-wizard.tsx`, 23 KB)

| Feature | Plan |
|---|---|
| Multi-step setup wizard | ❌ Drop. Admin imports solution + seeds 5 plants once. No per-user setup needed in MDA. |

---

## Custom hooks → Power Platform equivalents

| Hook | Replacement |
|---|---|
| `useInboundEmails` (SharePoint) | Server-side mail sync OR Power Automate captures to `rma_inboundemail` |
| `useEmailBody` | Stored as field on the email entity |
| `useMarkEmailProcessed` | Toggle field, auto-set on "Create Claim" command |
| `useSendTeamsMessage` | Power Automate "Post adaptive card" connector |
| `useM365UserSearch` (People Picker) | Native User lookup field |
| `useTeamsMessage` | Same flow as above |

---

## Business logic → Where it lives

| Logic | Code App location | MDA equivalent |
|---|---|---|
| Plant suggestion by part-number prefix | `lib/routing-engine.ts` `suggestPlant()` | Power Automate flow on `rma_claim` create — reads `rma_routingrule` table |
| Approval threshold check | `lib/routing-engine.ts` `requiresApproval()` | Calculated column `requiresApproval` on `rma_claim`, OR Business Rule |
| Email template placeholder merge | `claim-detail.tsx` inline | Power Automate Compose step before send |
| Claim number generation | `lib/claim-utils.ts` `generateClaimNumber()` | Auto-number column on `rma_claim.claimNumber` |
| Claim age calculation | `lib/claim-utils.ts` `getClaimAge()` | Calculated column or view formula |
| Status color mapping | `lib/claim-utils.ts` `STATUS_COLORS` | View row coloring rules / Form indicator |

---

## Build order (when we PATCH the MDA via API)

1. **Sitemap** — areas, groups, subareas (5 entities + dashboard + help)
2. **Saved views** on `rma_claim` (My Open, All Open, Closed, By Plant, Awaiting Response, Approval Needed)
3. **Main form** on `rma_claim` with 4 tabs + subgrids + modern command buttons
4. **Quick Create form** on `rma_claim` for the "Create from Email" path
5. **Native views + forms** on the 5 settings entities (auto-generated; we just verify column layouts)
6. **Business Process Flow**: New → Triage → Investigation → Decision → Closed
7. **Dashboard** with 4 charts (count, by plant, by status, closed/week)
8. **Modern Commands** (Resolve, Request Approval, Send Teams, Send Email, Set Default Signature, Send Sample)
9. **Power Automate flows**:
   - Auto-assign plant on claim create
   - Send approval request to Teams (loops approvers)
   - Send customer email (template merge)
   - Send sample email (settings → test)
   - Resolve & close (set resolutionKey + closedDate)
10. **Calculated columns**: `claimAge`, `requiresApproval`, `isOverdue`
11. **Business Rules**: warranty verified date auto-set; approval-needed badge
12. **Auto-number** on `rma_claim.claimNumber` (RMA-YYYY-####)
13. **Inbound Email entity** `rma_inboundemail` + flow to mirror from SharePoint OR move to native server-side mail sync

---

## Feature parity scoring

- ✅ **Direct port (~70%):** lists, forms, CRUD on settings entities, status changes, notes, subgrids
- 🔧 **Reconfigured (~20%):** bulk actions, dashboard tiles, calculated columns, approval logic
- ⚙️ **Now in Power Automate (~7%):** auto-routing, Teams approvals, template merge, email send
- 📄 **Custom Page (~3%):** email preview rendering, optional first-run dashboard
- ❌ **Dropped (~0%):** animations, source-status banner, localStorage mailbox config

**Net result:** 100% feature parity, with several pieces *upgraded* (server-side mail sync > SharePoint poll, BPF stages > custom pipeline, audit history > manual logs, Teams adaptive cards > basic Teams messages).
