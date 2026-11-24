# Azure DevOps as a Ticket Management Platform

A work item workflow with attribute gating, manager approval, team member assignment, review, and closure.

---

## The design

**States** (add to your work item type in an inherited process):

| State | Category | Meaning |
|---|---|---|
| New | Proposed | Draft, being filled in |
| Pending Approval | Proposed | Submitted to manager |
| Approved | InProgress | Manager OK'd, ready to assign |
| Active | InProgress | Team member working |
| In Review | InProgress | Sent back to manager |
| Rework | InProgress | Manager rejected, back to member |
| Closed | Completed | Done |
| Rejected | Removed | Killed at approval |

---

## 1. Create the inherited process

Org Settings → Process → right-click Agile → **Create inherited process** → change your project to use it (Project Settings → Overview → Process).

---

## 2. Add states

Process → your work item type → **States** tab → New state.

Put each in the right category — the category drives board columns, burndown, and "is this closed?" logic. Anything in Completed/Removed counts as done.

---

## 3. Add custom fields

On the work item type → New field:

- `Requester` (Identity)
- `Approver` (Identity)
- `Business Justification` (Text, multiline)
- `Target Date` (DateTime)
- `Cost Center` (Picklist)
- `Approval Decision` (Picklist: Approved / Rejected)
- `Rejection Reason` (Text)
- `Completion Notes` (Text)

Swap in whatever attributes actually matter for your engagement.

---

## 4. Rules — the attribute gate

Process → work item type → **Rules** → New rule. Each is condition → action.

### Gate A — can't submit for approval without the attributes

- **Condition:** When a work item state changes to `Pending Approval`
- **Actions:** Make required → `Requester`, `Business Justification`, `Target Date`, `Cost Center`, `Approver`

One rule holds up to 10 actions, so this is usually a single rule.

### Gate B — approval must be recorded

- Condition: state changes to `Approved` → make `Approval Decision` required
- Condition: state changes to `Rejected` → make `Rejection Reason` required

### Gate C — must be assigned before work starts

- Condition: state changes to `Active` → make `Assigned To` required

### Gate D — member must document before review

- Condition: state changes to `In Review` → make `Completion Notes` required

### Gate E — manager sends it back

- Condition: state changes to `Rework` → make `Rejection Reason` required

### Lock the approved fields

- Condition: state changes to `Approved` → make `Business Justification`, `Cost Center` read-only

---

## 5. Restricting who can approve

This is the weak spot. Inherited processes cannot block a specific state transition by group. What you can do:

1. Create an AAD/ADO group `Managers`.
2. Rule: *When current user is not a member of* `Managers` → *make read-only* the fields `Approval Decision` and `Approver`.

A team member can still drag the card to Approved, but they can't fill the required `Approval Decision` field, so the save fails. Combined with the History audit trail, that's enough for most engagements. If you need hard enforcement, see section 9.

---

## 6. The round trip in practice

1. Anyone creates the item (**New**), fills attributes, sets `Approver`, moves to **Pending Approval**. Rules block them if anything's missing.
2. Manager gets notified (see section 7), sets `Approval Decision`, moves to **Approved** or **Rejected**.
3. Manager or lead sets `Assigned To` and moves to **Active**.
4. Member works, adds attachments, fills `Completion Notes`, moves to **In Review**.
5. Manager reviews: **Closed** with a Closed Reason, or **Rework** with a `Rejection Reason` — which bounces to the member, who fixes and returns to In Review.

---

## 7. Notifications

Project Settings → Notifications → New subscription:

- "A work item state changes" with filter `State = Pending Approval` → deliver to the `Managers` group.
- "A work item is assigned to a user" → default subscription already covers step 3.
- Filter by Area Path if you have multiple teams.

---

## 8. Board setup

- Boards → team settings → **Columns**: map your states to columns so the flow is drag-and-drop.
- Add a **split column** (Doing/Done) on In Review to make the handoff explicit.
- Set **WIP limits** on Active.
- Add **Definition of Done** text per column — it shows on the column header and cuts down on premature transitions.

---

## 9. Hard enforcement, if you need it

Two options, both Python-friendly:

- **Service hook + Azure Function** — Project Settings → Service Hooks → "Work item updated" → HTTP POST to a function. The function checks `revisedBy` against your Managers group via the Graph API, and if unauthorized, reverts the state with a PATCH and posts a comment. Reactive, not preventive — the bad transition exists for a second.
- **Custom rules via the API** — same limitation set as the UI, so no gain.

Sample of the reverting call:

```python
from azure.devops.connection import Connection
from msrest.authentication import BasicAuthentication

creds = BasicAuthentication('', PAT)
conn = Connection(base_url=f"https://dev.azure.com/{ORG}", creds=creds)
wit = conn.clients.get_work_item_tracking_client()

patch = [
    {"op": "add", "path": "/fields/System.State", "value": "Pending Approval"},
    {"op": "add", "path": "/fields/System.History",
     "value": "Reverted: approver not in Managers group."}
]
wit.update_work_item(document=patch, id=work_item_id, project=PROJECT)
```

Package that as a container, push to Docker Hub, run it on ECS or as a Function App — either works, though keeping the function in Azure next to the DevOps org saves you a cross-cloud auth hop.

---

## Attachments

- Open the work item → **Attachments** tab → drag and drop, or paste an image straight into Discussion.
- Limit is 60 MB per file. For bigger artifacts, store elsewhere and add a hyperlink under Links.

---

## Two things to know before you build

- **Deleting a custom state is destructive.** Work items sitting in it get orphaned. Prototype in a throwaway project first.
- **Any-to-any transitions are allowed.** Inherited processes don't let you define a transition graph, so a member could jump New → Closed. The required-field rules make most illegal jumps fail, but audit the History tab periodically or add the service hook.
