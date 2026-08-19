# AWS Backup — Expanding the Central Vault to the Melbourne Region

**Context:** Multi-account AWS Organization, hybrid networking (Direct Connect → TGW → on-premises), no IGW/NAT, all egress via on-premises web proxy, central Network account with Network Firewall/GWLB, dev/test/prod account separation, member-account backup plans copying recovery points to a central backup account.

**Change:** Central backup vault moves from Sydney (`ap-southeast-2`) to Melbourne (`ap-southeast-4`).

---

## 1. Short answers

| Question | Answer |
|---|---|
| Can the central account have just **one** vault in Melbourne? | **Yes, technically.** One vault can receive copies from every member account, for every resource type. But a single vault for dev+test+prod is usually the wrong choice operationally — see §5. |
| Can member-account backup plans in Sydney copy directly to a Melbourne vault in another account? | **Yes.** AWS Backup supports a **combined cross-Region + cross-account copy in a single copy action**. The destination vault ARN encodes both the account and the Region, so `arn:aws:backup:ap-southeast-4:<central-acct>:backup-vault:<vault-name>` is a valid `CopyAction` destination from a plan running in `ap-southeast-2`. No intermediate hop or "copy of a copy" is required. |
| Are there specific considerations? | **Many.** The blockers most likely to bite you are: opt-in Region enablement, region-restriction SCPs, KMS (a CMK is mandatory — the AWS-managed `aws/backup` key will not work cross-account), per-resource-type copy support, and the fact that **restores happen in the vault's Region** — a Melbourne-only central copy means a DR restore back into Sydney needs a copy-back first. |

**Good news for your network team:** copy jobs are service-to-service operations on the AWS backbone. They **do not** traverse your VPCs, TGW, Network Firewall, GWLB, Direct Connect, or the on-premises proxy, and they do not require an IGW, NAT Gateway, or VPC endpoint. Your "no internet egress" posture is not a blocker for cross-Region copy.

---

## 2. How the copy actually works

```
Member account (ap-southeast-2)                Central backup account (ap-southeast-4)
┌──────────────────────────────┐               ┌──────────────────────────────────────┐
│ Backup plan                  │               │ Central vault                        │
│  └ Rule                      │               │  • CMK (customer managed)            │
│     ├ Backup → local vault   │  copy job     │  • Vault access policy allowing      │
│     └ CopyAction ────────────┼──────────────▶│    backup:CopyIntoBackupVault        │
│        dest = arn:aws:backup:│  (AWS backbone│  • Vault Lock (recommended)          │
│        ap-southeast-4:…      │   service     │                                      │
│        + its own lifecycle   │   managed)    │  Recovery points OWNED by this acct  │
└──────────────────────────────┘               └──────────────────────────────────────┘
```

Key behaviours:

- The **copy job is initiated and tracked in the source account/Region**, executed by the source account's AWS Backup service role.
- The **destination vault's access policy** is the authorisation mechanism for cross-account copy. The source account does not assume a role in the central account.
- Once copied, the recovery point is **owned by the central account** and is independent of the source. Deleting the source recovery point (or the entire source account) does not delete the copy. This is exactly the isolation property you want for ransomware/insider-threat resilience.
- The copy action carries its **own lifecycle/retention**, independent of the local vault's retention.

---

## 3. Prerequisites and setup checklist

### 3.1 Organization / account level

- [ ] **Enable `ap-southeast-4` (opt-in Region)** in the central backup account **and every member account** that will copy into it. Melbourne launched after March 2019, so it is disabled by default. Enable centrally via Organizations (Account settings → Regions) — it is not instantaneous and cannot be done by the member account if the Organization controls Region enablement.
- [ ] **Enable cross-account backup** in AWS Backup settings from the Organization management account (`backup:UpdateGlobalSettings` → `isCrossAccountBackupEnabled = true`). Without this, cross-account copy jobs fail regardless of policies.
- [ ] **Review region-restriction SCPs.** Landing zones commonly deny all actions outside `ap-southeast-2` via `aws:RequestedRegion`. A copy targeting Melbourne will be denied. Add `ap-southeast-4` to the allow-list — and think about whether you want a *narrow* exception (only `backup:*`, `kms:*` for the backup CMK) rather than opening the Region wholesale.
- [ ] **Service opt-in per Region.** AWS Backup's resource-type opt-in is per account **per Region**. Set it in the central account for `ap-southeast-4`, and confirm it in `ap-southeast-2` for the source accounts.
- [ ] **Extend guardrails to the new Region**: org CloudTrail, Config recorder, GuardDuty, Security Hub, and any Config/Backup Audit Manager conformance packs. Enabling an opt-in Region does not retroactively extend all of these.

### 3.2 Encryption (the most common failure cause)

- [ ] **Create a customer-managed KMS key in `ap-southeast-4`** in the central account for the vault. The AWS-managed `aws/backup` key **cannot** be used for cross-account copies.
- [ ] **Source recovery points must also be encrypted with customer-managed keys** for resource types where encryption is inherited from the source resource (EBS/EC2, RDS, Aurora, DocumentDB, Neptune, FSx). Snapshots encrypted with a default AWS-managed service key cannot be shared or copied cross-account.
- [ ] **Key policies both ways:**
  - Destination CMK: allow the org (`aws:PrincipalOrgID`) `kms:Encrypt`, `kms:Decrypt`, `kms:ReEncrypt*`, `kms:GenerateDataKey*`, `kms:DescribeKey`, `kms:CreateGrant` (with `kms:GrantIsForAWSResource`).
  - Source CMK: allow the central account to `kms:Decrypt`/`kms:CreateGrant` so the copy can be re-encrypted at the destination.
- [ ] **Consider KMS multi-Region keys (MRKs)** to simplify Sydney↔Melbourne copy-backs and restores, since KMS keys are Region-scoped and a Sydney restore of a Melbourne-encrypted copy needs a usable key in Sydney.
- [ ] Decide whether dev/test/prod share one CMK. Separate keys give you a clean cryptographic blast-radius boundary that mirrors your account separation.

### 3.3 Vault configuration (central account, Melbourne)

- [ ] **Vault access policy** granting `backup:CopyIntoBackupVault` to org principals:
  ```json
  {
    "Version": "2012-10-17",
    "Statement": [{
      "Effect": "Allow",
      "Principal": "*",
      "Action": "backup:CopyIntoBackupVault",
      "Resource": "*",
      "Condition": { "StringEquals": { "aws:PrincipalOrgID": "o-xxxxxxxxxx" } }
    }]
  }
  ```
  Tighten with `aws:PrincipalOrgPaths` if you want per-OU (dev/test/prod) vault targeting.
- [ ] **AWS Backup Vault Lock** — compliance mode for prod if this copy is your regulatory/immutable tier. Note the cooling-off period and that compliance mode is **irreversible**; test in governance mode first.
- [ ] Evaluate **logically air-gapped vaults** (if available in `ap-southeast-4` at build time). They can be shared via AWS RAM, letting a member account restore directly from the shared vault without a copy-back step.

### 3.4 Member account plan change

- [ ] Update the `CopyAction` destination ARN to the Melbourne vault. This is a plan/rule edit only — no change to the local vault, IAM service role (the managed `AWSBackupServiceRolePolicyForBackup` already covers `backup:CopyIntoBackupVault`), or networking.
- [ ] Keep the **local member-account vault in Sydney**. It is your fast-restore tier; Melbourne is the isolated DR/compliance tier.
- [ ] A rule can hold **multiple copy actions** — during migration you can copy to both the old Sydney central vault and the new Melbourne vault simultaneously.

---

## 4. Resource-type and feature considerations

These are the ones that actually break designs. Validate each against current AWS documentation and with a real copy job during a pilot — support changes over time.

| Consideration | Detail |
|---|---|
| **Not all resource types support cross-account copy** | Historically constrained: FSx (cross-account not supported), Storage Gateway volumes, some VMware and specialty types. Cross-**Region** support is broader than cross-**account** support. Inventory your protected resource types before committing. |
| **Continuous backups (PITR)** | Continuous recovery points **cannot** be copied cross-Region or cross-account. Only periodic snapshot recovery points are copyable. If you rely on PITR for RDS/S3, that capability stays Region-local. |
| **DynamoDB** | Cross-Region/cross-account copy requires **AWS Backup advanced features for DynamoDB** to be enabled. |
| **Resource type must exist in `ap-southeast-4`** | Melbourne has a narrower service surface than Sydney. If a resource type (or an FSx file system type, engine version, or instance family) is not offered in Melbourne, its recovery points may not be copyable there — and even if they copy, they may not be **restorable** there. |
| **Incrementality** | Snapshot copies are incremental only relative to prior copies **into the same destination account+Region pair**. Cutting over to Melbourne means the first copy of every resource is a **full copy** — expect a large one-off data-transfer bill and a long first run. |
| **Concurrency/throttling** | Underlying services (EBS, RDS) enforce concurrent snapshot-copy limits per destination Region per account. A fleet-wide simultaneous cutover will serialise and may overrun your backup window. Stagger the schedules. |
| **Cold storage** | Cold-tier transition has a 90-day minimum retention; set the copy action's lifecycle deliberately rather than inheriting the local vault's. |
| **Backup Audit Manager** | Frameworks and reports are **Region-scoped**. A framework in Sydney will not audit the Melbourne vault. Deploy a framework/report plan in `ap-southeast-4` too. |
| **Existing Sydney central recovery points** | Cannot be "moved". Either let them age out under their existing retention while the Melbourne copies build up, or run on-demand `StartCopyJob` calls to backfill Sydney → Melbourne. Do not decommission the Sydney central vault until Melbourne retention depth meets your policy. |

---

## 5. Should it really be *one* vault?

One vault works, but consider splitting. Arguments for **multiple vaults in Melbourne**:

- **Environment separation.** You have deliberately built dev/test/prod with no network path between them. A single vault reunifies them at the data layer — one vault policy, one CMK, one Vault Lock configuration. A prod-only vault can carry compliance-mode Vault Lock and a stricter key policy without imposing that on dev.
- **Different retention/immutability requirements.** Vault Lock is configured **per vault**, so dev's 14-day retention and prod's 7-year retention cannot coexist under one lock configuration.
- **Blast radius.** Vault access policy misconfiguration or CMK compromise is scoped to one vault.
- **Quotas and operational hot-spotting.** Vault, recovery-point, and job quotas apply per account per Region. A single vault holding every recovery point for the entire estate is also painful to search, report on, and reason about during an incident.
- **Cost attribution.** Per-vault tagging/reporting makes chargeback to projects far simpler.

A reasonable pattern:

```
Central backup account (ap-southeast-4)
  ├── vault-central-prod   → CMK-prod, Vault Lock (compliance), long retention
  ├── vault-central-test   → CMK-nonprod, Vault Lock (governance)
  └── vault-central-dev    → CMK-nonprod, short retention
```
with member-account plans selecting the destination by environment (naturally handled if you deploy plans via an Organizations backup policy with per-OU overrides, or via a CloudFormation/Terraform StackSet parameterised by OU).

---

## 6. The restore problem — the biggest design consequence

**Recovery points can only be restored in the Region where they live.** A Melbourne-only central vault therefore means:

| Scenario | Path | Impact |
|---|---|---|
| Routine restore, source account healthy | Restore from the **local Sydney vault** in the member account | Unaffected — fast. This is why you keep the local vault. |
| Member account compromised / local vault destroyed | Copy Melbourne → a Sydney vault, then restore | Adds a full copy job to your RTO. For large volumes this can be hours. Rehearse and measure it. |
| Sydney Region unavailable (true DR) | Restore **in Melbourne** | Requires a Melbourne landing zone that does not currently exist. |

If Melbourne is intended as a genuine DR Region rather than just an off-Region copy, you need to plan the corresponding network and platform build-out:

- **VPC(s), subnets, and route tables** in `ap-southeast-4` — restores of EC2/RDS/EFS/FSx need target subnets and security groups.
- **TGW in Melbourne**, plus either **inter-Region TGW peering** to Sydney or a **Direct Connect gateway association** so Melbourne can reach on-premises. Your DX locations are likely Sydney-based; a Melbourne DX/second path may be needed for a credible DR posture.
- **Route 53 Resolver** endpoints and forwarding rules in Melbourne for AD domain resolution — your current resolver/forwarding rule is Sydney-scoped and shared from the Network account. Restored Windows servers cannot join/authenticate to on-premises AD without an equivalent Melbourne construct plus routing to the DCs.
- **Central Endpoint VPC equivalent** in Melbourne — interface endpoints and private hosted zones are Region-scoped. Note that Melbourne may not offer interface endpoints for every service Sydney does.
- **Network Firewall / GWLB inspection** stack replicated, or an explicit decision to run DR with reduced inspection.
- **AZ and instance-type availability** — Melbourne has fewer AZs and a narrower EC2/RDS family and engine-version selection than Sydney. Verify your production instance types and engine versions are restorable there.
- **Restore testing plans** (AWS Backup restore testing) are Region-scoped and need real subnets/SGs in Melbourne to execute. Without a Melbourne footprint you can only restore-test in Sydney after a copy-back.

**Recommendation:** be explicit about which of these two the Melbourne vault is:

1. **An isolated, off-Region, cross-account immutable copy** (data resilience / ransomware / compliance). Minimal build: vault + CMK + policies. Accept that restore requires a copy-back to Sydney and document the RTO impact. This is a valid, low-cost, high-value posture.
2. **A DR Region** (service resilience). Requires the network and platform build-out above, and should be driven by a documented RTO/RPO per workload — not by the backup design alone.

---

## 7. Cost considerations

- **Cross-Region data transfer** for every copy job (charged on the source side, per GB).
- **First-copy full transfer** for the entire estate at cutover.
- **Duplicate warm storage** during the dual-run period (Sydney central vault + Melbourne central vault + local member vaults).
- **Restore/copy-back egress** charges when you exercise DR.
- **Melbourne pricing differs from Sydney** for storage and transfer — model it rather than assuming parity.
- Config recorder, GuardDuty, and CloudTrail costs in the newly enabled Region.

---

## 8. Monitoring and operations

- Copy job failures are **silent unless you instrument them** — the local backup succeeds and the plan reports success while the copy fails. Wire EventBridge rules on `Copy Job State Change` (`FAILED`, `PARTIAL`) in the **source account and source Region** to SNS/your alerting pipeline.
- Add **cross-Region** monitoring: EventBridge rules and SNS topics are Region-scoped; create them in `ap-southeast-4` for vault-level events (e.g., recovery point deletion, vault access policy change) in the central account.
- **CloudTrail** for `backup:DeleteRecoveryPoint`, `backup:PutBackupVaultAccessPolicy`, and KMS key policy changes on the central CMK — these are the actions an attacker would need.
- **Reconciliation report**: periodically compare recovery point counts/ages between local vaults and the central Melbourne vault. Do not trust job status alone.
- Track **copy job duration** against your backup window; the first-full-copy cutover is where windows blow out.

---

## 9. Suggested rollout sequence

1. Enable `ap-southeast-4` across the Organization; update region-restriction SCPs (narrowly).
2. Confirm cross-account backup is enabled at the Organization level.
3. Build the Melbourne CMK(s) and vault(s) in the central account via IaC (CloudFormation StackSet or Terraform); apply vault access policies; leave Vault Lock in **governance** mode initially.
4. Pilot with **one non-production account and one resource type per family** (EBS, RDS, EFS, DynamoDB, FSx if used). Verify the copy lands, is encrypted with the destination CMK, and — critically — **perform a real restore** (copy back to Sydney and restore).
5. Roll out to remaining test accounts, then production, in staggered schedule waves to avoid snapshot-copy throttling.
6. Run Sydney and Melbourne central copies in parallel until Melbourne retention depth satisfies policy.
7. Switch prod vault to Vault Lock **compliance** mode only after the cooling-off period and a successful restore test.
8. Decommission the Sydney central vault (or repurpose it as a warm restore staging vault — worth keeping for copy-back speed).
9. Document the copy-back RTO and add it to your DR runbook.

---

## 10. Open items to confirm before build

- [ ] Which resource types are in scope, and does each support cross-account **and** cross-Region copy today?
- [ ] Are all in-scope resource types and engine/instance versions available in `ap-southeast-4` for restore?
- [ ] Is Backup Vault Lock (compliance mode) and, if desired, logically air-gapped vault available in `ap-southeast-4`?
- [ ] Are any workloads relying on continuous backup/PITR that will lose off-Region protection?
- [ ] Is Melbourne an isolated copy tier or a DR Region? (Determines whether the network build-out is in scope.)
- [ ] Documented RTO/RPO per workload tier, including copy-back time.
- [ ] Data sovereignty/regulatory sign-off — both Regions are in-country, so this should be straightforward, but confirm any contractual Region commitments.

---

*Prepared as a design note. Verify AWS service and feature availability in `ap-southeast-4` and current resource-type copy support against AWS documentation at build time — regional feature parity and copy support both change.*
