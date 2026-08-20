# Amazon WorkSpaces as Per-Account Jump Servers with Entra ID PIM

**Context:** Hybrid AWS environment, Direct Connect to on-premises, no IGW/NAT, no internet egress from AWS, TGW hub in a Network account, central inspection (Network Firewall + GWLB), central Endpoint VPC with PHZs, Route 53 Resolver forwarding to on-prem AD, strict dev/test/prod network segregation, one account per project.

**Goal:** One jump server (WorkSpace) per account, used by privileged operators to reach EC2 VMs in that account, with access gated by Just-In-Time (JIT) privileged access.

---

## 1. Executive summary

| Question | Short answer |
|---|---|
| Can WorkSpaces work as a per-account jump server? | Yes, but each account needs its own directory registration (AD Connector or Managed AD) and its own WorkSpaces VPC subnets. This is the main cost/ops overhead of the "one per account" model. |
| Can access be routed through Entra ID PIM? | **Partially, and indirectly.** Entra PIM has no native integration with AWS WorkSpaces. The workable pattern is **PIM for Groups** → group drives (a) SAML app assignment for WorkSpaces login and (b) group writeback into on-prem AD to drive Windows logon rights on the WorkSpace and the target VMs. PIM gates *entitlement*, not the session. |
| AlwaysOn vs AutoStop | **AutoStop** for almost every jump server. Break-even vs AlwaysOn is roughly 80 connected hours/month. Keep at most one AlwaysOn break-glass desktop in production if cold-start latency (~90–120s) is unacceptable during an incident. |
| Cost Optimizer for WorkSpaces | Useful at scale (dozens+ of desktops). For 1–3 desktops per account it usually costs more (Fargate, S3, cross-account roles, and a network path it can't easily get in your no-egress environment) than it saves. Set AutoStop manually instead. |
| Pools vs Personal | **Pools is the better conceptual fit for JIT privileged access** (non-persistent, floating, native SAML/Entra auth, nothing left on the desktop). **Personal is the safer fit for your network constraints and per-account isolation model today.** See §7 for the decision matrix. |

> ⚠️ **The biggest risk in this design is not identity — it is egress.** WorkSpaces desktops need outbound access to a documented set of AWS public endpoints from their VPC ENI, and AWS does not support an HTTP proxy for the WorkSpaces agent. Your "no IGW, no NAT" rule will need a controlled exception. See §5.

---

## 2. Reference architecture

```
                         ON-PREMISES
   ┌──────────────────────────────────────────────────────────┐
   │  Admin workstation (WorkSpaces client)                    │
   │  Active Directory DCs                                     │
   │  Web proxy                                                │
   │  Entra Connect / Cloud Sync (group writeback)             │
   └────────────┬───────────────────────────┬──────────────────┘
                │ DX Private VIF            │ DX Public VIF
                │ (AD, DNS, target access)  │ (WorkSpaces streaming 4195/443)
   ┌────────────┴───────────────────────────┴──────────────────┐
   │                    NETWORK ACCOUNT                         │
   │  TGW (shared) • Network Firewall • GWLB • Endpoint VPC     │
   │  Route 53 Resolver rules (shared)                          │
   │  [NEW] Controlled egress VPC: NAT GW + NFW domain allowlist│
   └───────┬──────────────────┬──────────────────┬──────────────┘
           │ TGW              │ TGW              │ TGW
   ┌───────┴──────┐   ┌───────┴──────┐   ┌───────┴──────┐
   │ PROJECT-A    │   │ PROJECT-B    │   │ PROJECT-C    │
   │ (dev)        │   │ (test)       │   │ (prod)       │
   │              │   │              │   │              │
   │ AD Connector │   │ AD Connector │   │ AD Connector │
   │ WorkSpace    │   │ WorkSpace    │   │ WorkSpace    │
   │   (jump)     │   │   (jump)     │   │   (jump)     │
   │     ↓ 3389/22│   │     ↓        │   │     ↓        │
   │ Target EC2   │   │ Target EC2   │   │ Target EC2   │
   └──────────────┘   └──────────────┘   └──────────────┘
```

### Per-account components

| Component | Notes |
|---|---|
| 2 private subnets, 2 AZs | Required by the WorkSpaces directory registration. Small (/27–/26) is fine. |
| AD Connector (Small) | Proxies auth to your on-prem AD over DX; no directory data stored in AWS. **Free of charge while registered with WorkSpaces and carrying at least one active user** — but auto-deregisters (and starts billing at Directory Service rates) after 30 consecutive days with no WorkSpaces usage. Monitor this for low-use break-glass desktops. AD Connector cannot be shared across accounts and is not multi-VPC aware, so it must live in the same VPC as the WorkSpace. Requires DNS resolution of the AD domain — your shared Resolver rules cover this. See the AD addendum. |
| WorkSpaces directory registration | Bound to the AD Connector + the two subnets. One per account. |
| 1 WorkSpace (jump desktop) | AutoStop, DCV (WSP) protocol, encrypted volumes with an account-local KMS key. |
| IP Access Control Group | Restrict client source IPs to your on-prem internet egress ranges / DX public VIF ranges. Cheap, high-value control. |
| Security groups | WorkSpaces directory SG → target EC2 SGs on 3389/22 only. Target SGs reference the WorkSpaces SG, not CIDRs. |
| TGW attachment + explicit routes | Consistent with your no-propagation model. Jump WorkSpace subnet needs routes to: on-prem AD/DNS, in-account target subnets, central Endpoint VPC, and (see §5) the controlled egress path. |

### Consolidation option worth considering

"One jump server per account" multiplies AD Connectors and directory registrations. The *financial* cost of this is near zero (see the AD Connector note above), but the operational cost — N directories to build, monitor, rotate service accounts for, and keep out of the 30-day deregistration trap — is real. An alternative that preserves your segregation rule:

- **Three jump accounts** — `jump-dev`, `jump-test`, `jump-prod` — each with one directory and a small pool of WorkSpaces.
- TGW route tables permit `jump-prod → prod project VPCs` only, `jump-dev → dev project VPCs` only, etc. No cross-tier path, which matches your existing constraint.
- Reduces directories from N to 3, and makes WorkSpaces Pools viable (see §7).
- Trade-off: a lateral-movement blast radius within a tier, which you'd mitigate with per-project security groups and per-project AD groups on the targets.

I'd recommend modelling both and deciding on the AD Connector count and operational effort, not on the security delta — the security delta is small if SG and AD group scoping is done properly.

---

## 3. Identity and authentication chain

There are **three distinct authentications** and they are often conflated. You must design each one:

| # | Authentication | Who enforces it | Entra PIM applicable? |
|---|---|---|---|
| 1 | Launching the WorkSpaces client session | WorkSpaces directory — either AD credentials directly, or **SAML 2.0 federation to Entra ID** | ✅ Yes, via SAML app assignment |
| 2 | Windows logon *to the WorkSpace desktop* | On-prem AD (via AD Connector) | ⚠️ Indirectly, via AD group membership → "Allow log on locally" / directory user assignment |
| 3 | Logon *to the target EC2 VM* (RDP/SSH/SSM) | On-prem AD (Windows) or SSM/local (Linux) | ⚠️ Indirectly, via AD group → "Allow log on through Remote Desktop Services" / local admin |

**Enable SAML 2.0 authentication on the WorkSpaces directory.** This is what makes #1 an Entra-controlled event, which is the hook PIM needs. Requirements:

- WorkSpaces must use the **DCV (WSP)** protocol.
- The Entra user must map to a directory user — configure the SAML `NameID` / attribute to emit the on-prem AD `sAMAccountName` or UPN that AD Connector will resolve.
- Relay state URL is **per-directory and per-region**, so you need **one Entra enterprise application per WorkSpaces directory** — i.e. one per account in the "jump server per account" model. Factor this into your Entra app governance and naming standard.

**Optionally add certificate-based authentication (CBA)** with AWS Private CA so that #1 single-signs-on into #2 (no second AD password prompt at the Windows desktop). Caveats:
- Costs an AWS Private CA per directory-region (non-trivial monthly cost) — or one shared CA if you can cross-account share it.
- The WorkSpace must be able to reach the CRL distribution point. In a no-egress VPC this means an S3 CRL bucket reachable via a gateway/interface endpoint, or an on-prem CDP.
- Without CBA, users authenticate twice. For a jump server used a few times a month, double auth is honestly acceptable and simpler.

---

## 4. Routing access through Entra ID PIM

### 4.1 What PIM can and cannot do here

**Can:** JIT-activate membership of a group; that group can gate WorkSpaces SAML app assignment, Conditional Access, and (via writeback) Windows logon rights.

**Cannot:**
- PIM cannot JIT-*provision* a Personal WorkSpace. Personal desktops are statically assigned 1:1 to a directory user and continue to bill while assigned. PIM only gates whether the user may *log in*, not whether the desktop exists.
- PIM cannot terminate an already-established session. Expiry removes future entitlement; it does not kick anyone out.
- PIM is not a PAM product. No credential vaulting, no session brokering, no session recording, no keystroke capture.

### 4.2 Recommended flow

```
1. Operator requests activation in Entra PIM
      Group: PRIV-JUMP-<ACCOUNT>-<TIER>       (PIM for Groups, eligible assignment)
      Requires: justification, MFA, optional approver, max duration 4h
                 ↓
2. PIM activates membership (cloud group)
                 ↓
3a. Entra: group is assigned to enterprise app
    "AWS WorkSpaces – <ACCOUNT>"  →  user may now federate
                 ↓
3b. Entra Cloud Sync group writeback  →  on-prem AD group
    (latency: ~2 min Cloud Sync / ~30 min Connect Sync — measure it)
                 ↓
4. Conditional Access on the app:
   phishing-resistant MFA • compliant/hybrid-joined device
   named location = corporate egress • sign-in frequency 1h
                 ↓
5. WorkSpaces client → SAML assertion → session starts
                 ↓
6. AD group (written back) grants:
   - "Allow log on locally" on the jump WorkSpace
   - "Allow log on through Remote Desktop Services" on target EC2 (GPO)
   - local Administrators membership on target EC2 (GPO restricted groups / LAPS)
                 ↓
7. On expiry: PIM removes membership → writeback removes AD membership
   → next token / next logon denied.  EXISTING SESSIONS PERSIST (see 4.4)
```

### 4.3 Group design

Keep the PIM group and the AD-enforced group as **the same object** (cloud group written back), not two objects kept in sync by script. One group per account per privilege level:

```
PRIV-JUMP-<ACCOUNT>-LOGON      → may start a WorkSpaces session (jump box user)
PRIV-TGT-<ACCOUNT>-RDP         → may RDP to target VMs in that account
PRIV-TGT-<ACCOUNT>-ADMIN       → local admin on target VMs in that account
```

Splitting logon from privilege lets you grant "get to the jump box, read-only" separately from "become admin on the target", which is the more defensible model for prod.

### 4.4 Known gaps you must design around

| Gap | Impact | Mitigation |
|---|---|---|
| Group writeback latency | Activation may not take effect for several minutes; **de-activation is equally delayed** | You must use **Entra Cloud Sync group provisioning to AD** — Connect Sync's Group Writeback v2 was discontinued on 30 June 2024 and is not an option. Groups must be cloud-created and universal scope. Measure the cycle and publish the SLA to operators; set PIM max duration well above it. See IdC/Entra addendum for further constraints. |
| Existing sessions survive expiry | An operator can hold a session past the PIM window | GPO: max session time + idle disconnect on the WorkSpace and targets. Consider a scheduled job that queries PIM/Graph and force-logs-off users no longer in the group. |
| Kerberos/token caching | AD tokens and SAML tokens outlive membership changes | CA sign-in frequency 1h; short Kerberos ticket lifetime for the privileged group. |
| One Entra app per directory | App sprawl across N accounts | Automate app creation via Graph/Terraform; strict naming convention; use Entra app governance/access reviews. |
| IAM Identity Center SCIM latency | If you also use PIM groups for AWS *console* access, Entra→IdC SCIM syncs on a ~40-minute cycle — JIT will feel broken | Don't rely on PIM+SCIM for time-critical console access; pre-provision the group in IdC and let PIM control membership, accepting the sync delay, or use IdC's own session controls. |
| No session recording | Weak forensics for privileged actions | See §9. |

### 4.5 If you need true PAM

If your control requirement is "privileged session recording, credential injection, and session termination" (common for prod in regulated environments), Entra PIM + WorkSpaces will not satisfy an auditor on its own. Either:
- Put a PAM product (CyberArk PSM, BeyondTrust, Delinea) on the jump path and use PIM only for the entitlement layer, or
- Replace RDP-to-target with **AWS Systems Manager Session Manager**, which gives native session logging to S3/CloudWatch, no inbound ports, and IAM-based authorization. See §10.

---

## 5. Networking — the hard constraint

### 5.1 The two ENIs

Every WorkSpace has two network interfaces:

- **Management ENI** — AWS-owned address space, used by the WorkSpaces service for streaming and management. Not in your route tables, not your problem.
- **Primary ENI** — in *your* VPC subnet. Used for domain join, DNS, target VM access, and **outbound access to AWS service endpoints**.

### 5.2 What the primary ENI needs, and why it breaks your rules

The WorkSpaces agent on the desktop requires outbound access (typically 443, plus **TCP 1688 for Amazon KMS Windows activation**) to a documented set of AWS public endpoints — WorkSpaces service, S3 for agent/image updates, CloudWatch, and the regional activation hosts.

Two things matter for you:

1. **AWS does not support routing WorkSpaces agent traffic through an HTTP proxy.** Your on-prem web proxy will not solve this, and TCP 1688 is not HTTP anyway.
2. If activation fails, Windows on the WorkSpace will eventually enter a non-genuine/degraded state. This is a slow-burn failure that shows up months after go-live.

**Practical options, in order of preference:**

| Option | Description | Trade-off |
|---|---|---|
| **A. Controlled egress VPC (recommended)** | A dedicated egress VPC in the Network account with NAT GW, fronted by AWS Network Firewall with a **strict domain/IP allow-list** limited to the documented WorkSpaces endpoints + KMS activation IPs on 1688. Jump WorkSpace subnets route `0.0.0.0/0` → TGW → egress VPC. | Requires an exception to "no NAT/IGW". Defensible: it is a single, inspected, allow-listed path used only by WorkSpaces subnets, not general internet access. |
| **B. Per-account restricted NAT** | Same idea but NAT in each account. | Multiplies cost and drift risk. Avoid. |
| **C. Endpoint-only** | Use your central Endpoint VPC + S3 endpoints and hope it's sufficient. | Will not cover KMS activation on 1688. Will likely fail agent updates. Not viable alone — but do add S3/SSM/KMS/CloudWatch endpoints regardless. |

> **Action:** before committing to WorkSpaces, validate the current published endpoint/IP requirements for your region against Option A and get the egress exception approved. If that exception is refused outright, WorkSpaces is probably the wrong technology and you should look at §10 alternatives.

### 5.3 Client-side connectivity (admin workstation → WorkSpace)

- Native client uses **TCP 443** (registration/auth) and **UDP/TCP 4195** (DCV streaming). PCoIP uses 4172 — use DCV, not PCoIP.
- **Streaming should not traverse an HTTP proxy.** The client can be configured to use a proxy for HTTPS control traffic, but the streaming port needs a clean path. Expect to carve out a proxy bypass and a firewall rule for 4195.
- **Direct Connect public VIF** is the clean way to carry this traffic from on-prem to AWS public endpoints without going out to the internet — worth using given you already have DX. Validate the BGP/prefix filtering with your DX provider.
- **Web Access** (browser, 443 only) is a proxy-friendly fallback with reduced features (no USB redirection, limited peripherals). Useful as a break-glass path, not as the primary experience.
- Apply an **IP Access Control Group** on each directory limiting client source IPs to your corporate egress / DX public VIF ranges.

### 5.4 DNS

Your existing Resolver design covers this cleanly: the shared forwarding rule resolves the AD domain to on-prem DCs, and the central Endpoint VPC PHZs resolve AWS interface endpoints. Ensure the WorkSpaces VPC is associated with:
- the shared Resolver rule for the AD domain,
- the PHZs for the central endpoints,
- the account-local PHZ if targets are addressed by private DNS names.

---

## 6. Running modes: AlwaysOn vs AutoStop

### 6.1 The two modes (WorkSpaces Personal)

| | AlwaysOn | AutoStop |
|---|---|---|
| Billing | Flat monthly fee per WorkSpace | Small fixed monthly fee (storage/infra) **+ hourly rate for connected time** |
| State | Always running | Stops after N hours of user inactivity (configurable, 60 min minimum) |
| Time to first pixel | Immediate | ~90–120 seconds cold start |
| Best for | Daily-use desktops, break-glass where seconds matter | Intermittent use — **exactly the jump server profile** |

**Break-even is roughly 80 connected hours per month** (varies by bundle and region — check the pricing page for `ap-southeast-2`). A jump server used for change windows and incidents will be far below that.

### 6.2 Billing behaviour when switching modes

- Switching **AutoStop → AlwaysOn** mid-month bills the **full monthly rate for that month**. Don't flip modes casually.
- Switching **AlwaysOn → AutoStop** takes effect for the following billing month.
- This asymmetry is exactly why the Cost Optimizer solution makes its changes at month boundaries.

### 6.3 Recommendation

- **All jump servers: AutoStop, 60-minute inactivity timeout.**
- Consider **one AlwaysOn break-glass WorkSpace in the production tier** if your incident SLA cannot absorb a 2-minute cold start. Even then, question it — 2 minutes is rarely the constraint during a P1.
- Use the WorkSpaces API/CLI to force-stop a WorkSpace immediately after a PIM window closes, rather than waiting for the inactivity timer. This is a cheap automation and doubles as a cost and a security control.

---

## 7. Cost Optimizer for Amazon WorkSpaces

**What it is:** an AWS Solutions implementation (CloudFormation) that reads CloudWatch usage metrics for each WorkSpace and automatically converts between AlwaysOn and AutoStop at the month boundary, optionally flagging or terminating unused desktops. It runs as a scheduled ECS Fargate task in a hub account, supports multi-account via AWS Organizations and cross-account IAM roles, and writes reports to S3.

**Considerations for your environment:**

| Consideration | Detail |
|---|---|
| Network | The default template deploys its own VPC **with a NAT gateway**. In your environment you'd deploy into an existing VPC and supply VPC endpoints (ECR, ECS, CloudWatch, S3, STS) — or route it via the controlled egress VPC from §5.2. Plan for this; it is the most common deployment failure. |
| Permissions | Needs a cross-account role in every account holding WorkSpaces. That's N roles to deploy and govern — fits fine into your existing account-baseline pipeline. |
| Value threshold | The solution earns its keep when you have enough desktops that manual mode management is error-prone. With 1–3 WorkSpaces per account, **the savings are ~zero because you'd set AutoStop on day one and never change it.** |
| Alternative | A small scheduled 