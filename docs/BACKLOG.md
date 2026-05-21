# HKP RMA Agent Set — Backlog

> **Status legend:** ⏸ not started · 🟡 in progress · 🚧 partial · ✅ done · ❌ blocked

## Phase 1 — Local Python agents (this session)

| Item | Status | Notes |
|---|---|---|
| Folder scaffold + README + transcripts path | ✅ | OneDrive: `MSFT Corporate\Customers\AMETEK\Transcripts\HKP-RMA\` |
| `d365/config/environment.json` | ⏳ | Mfg Gold Template + solution `WarrantyandClaimOperations` v1.0.0.14 |
| `d365/config/demo-data.json` | ✅ | 6 RMA scenarios including real Roche Diagnostics batch case |
| 6 BasicAgent Python files in `agents/` | ⏳ | Source of truth here; copied to repo `/agents/` once ready to demo |
| Demo data loader script | ⏳ | Populates `cr74e_WarrantyClaim` + `cr74e_ProductSerial` + `msdyn_Warranty` |
| `ui/hkp_rma_tester.html` | ⏳ | Single-page tester for all 6 agents (Run + Run All + sample inputs) |
| Local validation via `function_app.py` | ⏳ | Copy 6 agents to `/agents/`, restart, test from `index.html` |

## Phase 2 — Copilot Studio integration

| Item | Status | Notes |
|---|---|---|
| Transpile 6 agents → 6 CS topic `.mcs.yml` files | ⏸ | Reuse v1 syntax conventions from `customers/ametek/copilot-studio/topics/` |
| Reuse one of 3 orphan bot IDs in v1.0.0.14 | ⏸ | `b66a3b41-…`, `cd160965-…`, `f85c69af-…` (or delete + create fresh) |
| `load_topics.py` for HKP — same pattern as AMETEK SFMS | ⏸ | PATCH/POST botcomponents direct |
| `fix_topics.py` for HKP — same 8 transforms | ⏸ | Reuse from AMETEK SFMS |

## Phase 3 — Power Automate wiring (reuse-first per Bill: option Z)

| Existing flow in v1.0.0.14 | Reuse for? | Status |
|---|---|---|
| `CreateWarrantyClaim` | Intake topic — write claim to Dataverse | ⏸ |
| `When a new email arrives for a warranty claim` | Trigger intake agent | ⏸ activate |
| `Capture each incoming and outgoing email` | Customer interaction logging | ⏸ activate |
| `Claim Routing Automation` | Route after disposition | ⏸ |
| `Request Manager Approval for Claim` | Approval after agent recommends | ⏸ |
| `Send Shipping Label` | Trigger when disposition = approve + replace | ⏸ |
| `When a Claim is added or modified` | Status notifications to customer | ⏸ |
| `New Claims Notifications` | Notify ops on intake | ⏸ |
| `Customer Interaction Agent Flow` | Touch log per claim | ⏸ |
| **Stub gaps?** | TBD — review schemas | ⏸ |

## Phase 4 — Demo polish

| Item | Status |
|---|---|
| Demo guide HTML (3-column, printable, per `demo-guide-style-standard`) | ⏸ |
| 3 storyline arcs (in-warranty repair, out-of-warranty rejection, ambiguous escalation) | ⏸ |
| Capture `pac solution export` of working agent + commit canonical .zip | ⏸ |
| Promote v1.0.0.14 → Master CE Mfg (only after Bill review) | ⏸ |
| Transcripts integrated into agent instructions block | ⏸ awaits drop |

---

_Last updated: 2026-04-28_
