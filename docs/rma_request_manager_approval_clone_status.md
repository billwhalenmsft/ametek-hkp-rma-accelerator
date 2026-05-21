# RMA: Request Manager Approval — Cloned Flow Status

## What's done

Cloned `Request Manager Approval for Claim` (warranty schema) → `RMA: Request Manager Approval` (RMA schema).

| Item | Value |
|---|---|
| New workflow id | `5d730ad8-1750-f111-a824-0022480a5e8d` |
| Display name | `RMA: Request Manager Approval` |
| Unique name | `rma_requestmanagerapprovalforclaim` |
| Trigger | Dataverse **Create** on `rma_approvalrecord` (org-scoped) |
| Connection ref - approvals | `cr74e_sharedapprovals_453c9` (reused from source) |
| Connection ref - dataverse | `cr74e_warrantyChecker.shared_commondataserviceforapps.shared-commondataser-9933c9ef-b98c-4170-8251-695bb41a22f2` |
| State | activated (`statecode=1, statuscode=2`) |
| Source flow backed up to | [customers/ametek/hkp_rma/backup/source_flow_request_manager_approval_for_claim.json](customers/ametek/hkp_rma/backup/source_flow_request_manager_approval_for_claim.json) |

## Flow structure

1. **Trigger:** When an `rma_approvalrecord` row is added (org scope)
2. **Get_related_RMA_claim** — `GetItem` on `rma_claims` using `_rma_claim_value` from trigger
3. **List_active_plant_approvers** — query `rma_plantapprovers` filtered by `_rma_plant_value eq <claim plant>` and `rma_isactive eq true`
4. **Compose_Approver_List** — joins active approver `rma_teamsupn` values with `;` (or fallback `admin@`)
5. **Update_claim_status_to_Decision** — sets `rma_status = 100000003` (Decision)
6. **Start_and_wait_for_an_approval** — Microsoft Approvals connector (Basic), title contains claim# + amount, deep link to RMA Operations app form
7. **For_each_approver_response → If Approve:**
   - Mark approval record `rma_approvalstatus = 100000001` (Approved)
   - Close claim (`rma_status = 100000004`, `statuscode = 2`, `statecode = 1`)
   - Write `rma_approvalhistory` row (`rma_action = 100000001`, `rma_viateams = true`)
   - **Else (Deny):** Mark record Denied + write history row (claim left open at Decision so user can re-route)

## ⚠️ Manual step required (one-time)

The trigger webhook subscription does **not** auto-register when you POST a flow definition directly to the Dataverse `workflows` table. The Power Automate maker UI registers the trigger as a separate step on Save.

**Until you do this once, the flow will not fire when an approval record is created.**

**Steps:**

1. Open the flow: <https://make.powerautomate.com/environments/2404ccaf-d7e5-e1ff-863a-3ecbe2f0f013/solutions/Default/flows/5d730ad8-1750-f111-a824-0022480a5e8d/details>
2. Click **Edit**
3. (Don't change anything — or just open and re-close the trigger card)
4. Click **Save** in the top bar
5. The Power Automate runtime will register the Dataverse webhook subscription at that point

After this, every newly created `rma_approvalrecord` row will fire the flow → approver(s) get a Teams approvals card + email + Outlook actionable card.

## Verify after the save

Run [customers/ametek/hkp_rma/scripts/smoke_test_clone_flow.ps1](customers/ametek/hkp_rma/scripts/smoke_test_clone_flow.ps1) — it creates a test approval record on `RMA-SMOKE-WTB-SMOKE-05131216` for $1500. Then:

- Check Teams Approvals app (admin@ account, since admin is the wired plant approver)
- Run [customers/ametek/hkp_rma/scripts/check_flow_results.ps1](customers/ametek/hkp_rma/scripts/check_flow_results.ps1) to confirm claim status flipped to `100000003 = Decision`
- Or open the flow Run history in maker

## Files added this session

- [customers/ametek/hkp_rma/scripts/clone_request_manager_approval_for_rma.ps1](customers/ametek/hkp_rma/scripts/clone_request_manager_approval_for_rma.ps1) — the clone script (re-runnable; use `-Force` to recreate)
- [customers/ametek/hkp_rma/scripts/smoke_test_clone_flow.ps1](customers/ametek/hkp_rma/scripts/smoke_test_clone_flow.ps1) — creates a test approval record
- [customers/ametek/hkp_rma/scripts/check_flow_results.ps1](customers/ametek/hkp_rma/scripts/check_flow_results.ps1) — verifies side-effects on claim/approval/history
- [customers/ametek/hkp_rma/scripts/diagnose_flow_subscription.ps1](customers/ametek/hkp_rma/scripts/diagnose_flow_subscription.ps1) — checks webhook subscription state
- [customers/ametek/hkp_rma/scripts/cleanup_smoke_test.ps1](customers/ametek/hkp_rma/scripts/cleanup_smoke_test.ps1) — deletes test records
- [customers/ametek/hkp_rma/backup/source_flow_request_manager_approval_for_claim.json](customers/ametek/hkp_rma/backup/source_flow_request_manager_approval_for_claim.json) — full backup of source

## Lesson learned (add to skills)

POST to `/workflows` with a modern flow definition creates the workflow record and lets you `PATCH statecode=1` to mark it activated, but the **Dataverse trigger webhook subscription** is registered separately by the Power Automate runtime when the flow is saved via the maker UI (or via the `https://api.flow.microsoft.com` REST surface using the `?api-version=2016-11-01` PUT endpoint).

For programmatic deployment of trigger-on-Dataverse modern flows: either deploy via solution import (`pac solution import`), which handles trigger registration, or POST + then call Power Automate flow management API to "save" the flow. Direct Dataverse POST alone leaves the flow inert.
