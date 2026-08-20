# Addendum 2 — Can AD be synced with IAM Identity Center federated to Entra ID?

Companion to `workspaces-jump-server-design.md`. Includes corrections to that document.

---

## 1. Short answer: no, on every reading of the question

| Reading | Answer |
|---|---|
| Can IdC use **AD as identity source** *and* be **federated to Entra ID** at the same time? | **No.** These are mutually exclusive identity sources. |
| Can IdC **write identities into AD** (i.e. IdC as the sync engine that lands Entra users/groups in your on-prem AD)? | **No.** IdC never writes to Active Directory. The flow is one-way *into* IdC. |
| Can IdC therefore act as the **bridge** that gets Entra identities into the AD your WorkSpaces directory depends on? | **No.** IdC is not in that path at all. |

<cite index="51-1">IAM Identity Center allows only one identity source per AWS Organization: an external IdP such as Entra ID, your on-premises or AWS-managed Active Directory, or the built-in Identity Center directory.</cite> <cite index="54-1">AWS states this directly: at any given time you can have only one directory or one SAML 2.0 identity provider connected to IAM Identity Center.</cite>

Switching between them is destructive, not a toggle: <cite index="46-1">changing your identity source to or from Active Directory deletes users and groups from the Identity Center directory and removes any assignments you configured, along with the permission set IAM roles in your accounts.</cite> Treat the choice as one-way.

---

## 2. The correct mental model: two separate identity planes

The reason the question feels like it should work is that "Entra", "IdC" and "AD" all look like they sit on the same line. They don't. **Your environment has two independent identity planes, and IdC only lives on one of them.**

```
PLANE 1 — AWS control plane (console, CLI, APIs, SSM)
   Entra ID ──SAML (authn)──▶ IAM Identity Center ──▶ Permission sets ──▶ AWS accounts
            └─SCIM (users/groups)─┘
   PIM works here.  Latency: Entra provisioning cycle ≈ every 40 min.

PLANE 2 — Windows desktop plane (WorkSpaces logon, RDP to VMs, GPO)
   On-prem AD ──AD Connector──▶ WorkSpaces directory ──▶ WorkSpace + target VMs
   PIM reaches here ONLY via:
      (a) SAML 2.0 federation on the WorkSpaces directory  → gates session start
      (b) Cloud Sync group writeback  → gates AD group membership

   ▲ IAM Identity Center is NOT on this plane.
```

The only sync relationships that actually exist:

| Direction | Mechanism | What moves |
|---|---|---|
| On-prem AD → Entra ID | Entra Connect Sync / Cloud Sync | Users and groups, upward. This is your existing hybrid sync. |
| Entra ID → on-prem AD | **Entra Cloud Sync group provisioning** ("group writeback") | Cloud-created security groups only. See §4. |
| Entra ID → IdC | SAML + SCIM | Users and groups, for AWS access only. |
| AD → IdC | IdC reads AD directly when AD is the identity source | Users and groups, for AWS access only. |
| IdC → AD | **Does not exist** | — |

---

## 3. The trade-off you're actually choosing between

Because IdC accepts only one source, picking one costs you something real:

| IdC identity source = **Entra ID (external IdP)** | IdC identity source = **Active Directory** |
|---|---|
| ✅ Entra Conditional Access applies to AWS console/CLI sign-in | ❌ No Entra Conditional Access — IdC authenticates against AD directly |
| ✅ Entra PIM can gate AWS access via SCIM'd groups | ❌ PIM can't gate IdC groups (they're AD-sourced, and PIM for Groups is cloud-only) |
| ⚠️ SCIM provisioning cycle ≈ 40 min — JIT activation and, more importantly, **de-activation**, lag by up to that long | ✅ AD group changes reflect quickly |
| ❌ IdC identities have no relationship to the AD accounts your WorkSpaces use | ✅ Same AD accounts across IdC and WorkSpaces — one identity, two uses |
| ✅ MFA via Entra | ⚠️ MFA via RADIUS on AD Connector only |

**Recommendation for your environment: IdC identity source = Entra ID.** You lose the shared-account elegance, but you gain Conditional Access and PIM on the AWS control plane — and the WorkSpaces desktop plane was never going to run through IdC anyway.

Accept the consequence explicitly: **an operator will have two identities** — an Entra identity for AWS console/CLI/SSM, and an AD identity for the WorkSpace desktop and RDP. Document the mapping and make sure your SIEM can correlate them (match on UPN or employee ID), or your privileged-access audit trail will be split across two namespaces with nothing joining them.

---

## 4. The mechanism that *does* bridge Entra to AD — and its constraints

The bridge is **Entra Cloud Sync group provisioning to AD**, not IdC. Corrections to the main design doc:

<cite index="72-1">Entra Connect Sync's Group Writeback v2 was discontinued on 30 June 2024 and is no longer supported for provisioning cloud security groups to Active Directory. Microsoft's replacement is Cloud Sync's "Group Provision to Active Directory".</cite> The main document said to *prefer* Cloud Sync over Connect Sync for latency reasons — that was too soft. **Connect Sync is not an option for this at all.**

Constraints that will bite during build:

| Constraint | Detail |
|---|---|
| **Preview status** | Microsoft documentation describes Group Provision to Active Directory as **public preview** in places. For a control that gates production privileged access, confirm current GA status and support posture before you depend on it. If it's still preview, that is a genuine reason to keep a non-PIM break-glass path. |
| **Cloud-created groups only** | <cite index="61-1">Groups provisioned to AD DS via Cloud Sync can only contain on-premises synchronized users or other cloud-created security groups, and those users must have the `onPremisesObjectIdentifier` attribute set.</cite> Your operators sync up from on-prem AD, so they qualify — but verify the attribute is populated. |
| **Universal scope required** | Global security groups are rejected with `HybridSynchronizationActiveDirectoryInvalidGroupType`. Create the PIM groups as universal. |
| **Mixed-SOA membership is silently partial** | <cite index="66-1">If a cloud-SOA security group has some members whose source of authority is cloud and some on-premises, the job provisions only the on-premises-SOA member references and skips the cloud-SOA ones.</cite> A cloud-only operator account will activate in PIM and then **silently not appear in the AD group.** This is a failure mode that looks like success. Test it. |
| **PIM for Groups is cloud-only** | Existing AD-originated groups cannot be placed under PIM directly. To PIM an AD group you already use for RDP rights, you must convert its **Source of Authority** from AD to cloud, then write it back — also a newer, preview-era capability. Verify status. |
| **OU and naming** | Written-back groups land in a nominated OU and the CN may be rewritten. Plan the OU and your GPO scoping around this, not the other way round. |

---

## 5. Where IdC genuinely helps you

None of the above means IdC is irrelevant — it means it belongs to a different job:

- **AWS console and CLI access** to the dev/test/prod accounts, with permission sets scoped per account and per environment tier.
- **SSM Session Manager authorisation.** This is the strongest argument for IdC in your design: if you route target-VM access through Session Manager rather than RDP-from-the-jump-box, authorisation becomes an IAM decision driven by Entra groups via IdC — no AD group writeback, no preview features, no split identity for that path, and native session logging.
- **WorkSpaces Personal Entra ID / Custom directory types** are built on IdC — but remain Windows 10/11 BYOL-only, so still out of reach at your scale (see Addendum 1).

That last point is worth sitting with. **Every attempt to make Entra the authority for the WorkSpaces desktop runs into either BYOL commitments or preview-status group writeback.** If the PIM requirement is firm and the desktop requirement is soft, Session Manager over IdC is the path with no such compromises.

---

## 6. Revised recommendation

1. **IdC identity source: Entra ID (external IdP).** Accept ~40 min SCIM lag; do not rely on it for time-critical revocation.
2. **WorkSpaces directory: AD Connector to on-prem AD.** Unchanged — IdC cannot substitute.
3. **Entra → AD bridge: Cloud Sync group provisioning**, universal cloud-created security groups, with the mixed-SOA failure mode explicitly tested.
4. **Verify preview/GA status** of Cloud Sync group provisioning and Group SOA conversion before making them load-bearing for production privileged access.
5. **Seriously evaluate replacing jump-box RDP with SSM Session Manager**, which collapses this entire identity problem into a single Entra→IdC→IAM path.

---

*Microsoft preview/GA statuses and AWS identity source behaviour change; verify §4 and §5 against current vendor documentation before design sign-off.*
