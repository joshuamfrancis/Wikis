# Jump Host Enablement for PIM-Managed, Auditable Access to Member Account EC2 Instances

## 1. Objective

Provide operations/DBA/support staff with a controlled way to run desktop tools (SQL Developer, DBeaver, RDP/DB clients, etc.) against EC2 instances in development, testing and production member accounts, without:

- Any Internet Gateway / NAT Gateway / direct internet egress
- Standing SSH/RDP network exposure between accounts
- Standing IAM privilege ("always-on" access)
- Untracked, non-auditable access

The design below uses **AWS Systems Manager Session Manager as the transport**, **AWS IAM Identity Center federated to the on-prem Active Directory as the identity layer**, and a **just-in-time (JIT) privilege elevation workflow** to deliver PIM-like behavior, all consistent with the existing hub-and-spoke TGW / Endpoint VPC / no-NAT design.

---

## 2. Why Session Manager (not classic bastion + SSH/RDP)

| Requirement | Classic SSH/RDP Bastion | SSM Session Manager |
|---|---|---|
| No inbound ports (22/3389) open across TGW attachments | ❌ requires explicit route + SG rules per spoke | ✅ outbound-only HTTPS (443) to SSM endpoints |
| No internet egress | ❌ needs NAT/IGW or proxy for agent/keys unless endpoints used | ✅ works entirely via VPC interface endpoints |
| Central audit of every session (keystrokes, session start/stop) | Requires custom sshd/proxy logging | ✅ native: CloudTrail (who/when) + Session logs to S3/CloudWatch (what) |
| No long-lived SSH keys / local admin credentials to manage | ❌ | ✅ IAM/SSO-based, ephemeral |
| Fits "explicit TGW routes, no propagation" model | Needs bastion subnet reachable from every spoke | ✅ no new TGW routes needed — session data flows over existing endpoint VPC interface endpoints already reachable from spokes |

This aligns with the existing pattern: the Endpoint VPC in the network account already centralizes Interface Endpoints with Private Hosted Zones — SSM, SSM Messages and EC2 Messages endpoints simply join that existing set.

---

## 3. Network Changes Required

### 3.1 Centralized VPC Interface Endpoints (Network Account – Endpoint VPC)

Add (if not already present) to the central Endpoint VPC, associated to the existing Private Hosted Zones pattern:

- `com.amazonaws.<region>.ssm`
- `com.amazonaws.<region>.ssmmessages`
- `com.amazonaws.<region>.ec2messages`
- `com.amazonaws.<region>.kms` (Session Manager can encrypt session data with a CMK)
- `com.amazonaws.<region>.logs` (CloudWatch Logs, for session logging)
- `com.amazonaws.<region>.s3` (Gateway or Interface, for session log/archival + tool packages held in an internal artifact bucket)
- `com.amazonaws.<region>.sts` (role assumption from Identity Center)
- Optionally `com.amazonaws.<region>.sso` / `identitystore` if Identity Center calls are made from the instance itself (rare)

These are shared via existing Private Hosted Zone association pattern so member account VPCs resolve them privately — **no change to the "no direct internet access" posture.**

### 3.2 Member Account VPC

- No new IGW/NAT.
- Security Group on target EC2 instances: **egress-only** to the Endpoint VPC's endpoint ENIs on 443 (or to `0.0.0.0/0`/443 if using existing east-west inspection via GWLB/Network Firewall, since traffic never leaves AWS).
- No inbound rule required for SSM (agent polls outbound).
- SSM Agent must be installed (pre-baked into golden AMIs — see §7).

### 3.3 Jump Host Placement

Recommended: **one jump host fleet per environment tier (dev/test/prod), inside a dedicated "Access" or "Bastion" account or subnet per project account**, given the stated "no network path across dev/test/prod." Two supported patterns:

**Pattern A – Per-account jump host (recommended given your segmentation)**
- Each member account has its own small jump host subnet.
- User connects via Session Manager directly into that account's jump host.
- Strongest isolation; matches "no network path across environments."

**Pattern B – Shared-services jump host per tier, reached via TGW**
- One jump host account per tier (dev, test, prod), attached to TGW with **explicit route only to the specific project VPCs it must reach** (consistent with "explicit routes per attachment, no propagation").
- User RDPs/SQL Developer's from the jump host to the target EC2 over the TGW.
- Slightly more central management, but re-introduces a TGW-routed network hop, so it must be explicitly whitelisted per target VPC.

Given your explicit-route/no-propagation model and dev/test/prod isolation requirement, **Pattern A (per-account jump host) is the better fit** — it avoids adding new TGW routes between environment tiers altogether.

---

## 4. Identity Layer (Federated to On-Prem AD)

1. **AWS IAM Identity Center** (successor to AWS SSO) is enabled in the Organization's management or a delegated admin account.
2. Identity source: federate to on-prem AD — either:
   - **AD Connector** (via Directory Service, using the existing Direct Connect path) proxying to on-prem AD, or
   - **SAML federation via existing on-prem AD FS / Entra Connect**, if already used for other enterprise apps.
3. AD security groups define role eligibility, e.g.:
   - `AWS-JumpHost-DBA-Prod-Eligible`
   - `AWS-JumpHost-AppSupport-Test-Eligible`
   These are **eligibility** groups, not standing access groups — membership means "can request," not "has."
4. IAM Identity Center **Permission Sets** are scoped per environment tier and mapped to these AD groups, each permission set:
   - Session duration capped (e.g., 1 hour, matching a maintenance window)
   - Scoped IAM policy allowing `ssm:StartSession` only against resource-tagged instances (`ssm:resourceTag/Environment = Prod`, `ssm:resourceTag/Project = X`)
   - No `AdministratorAccess`-type policies

---

## 5. Just-In-Time (PIM) Elevation Workflow

Native AWS has no direct equivalent to Azure AD PIM, so JIT elevation is implemented with existing AWS building blocks:

1. **Request**: User (already authenticated via Identity Center/AD) opens a self-service request (Service Catalog product, or a simple Slack/Teams-integrated Step Functions workflow) specifying: target account, target instance(s), business justification, duration (max e.g. 4h).
2. **Approval**: Request triggers an **SSM Automation runbook with an `aws:approve` step**, or a Step Functions state machine with an SNS/Teams approval action, routed to the resource owner / on-call lead.
3. **Grant**: On approval, an automation (Lambda/Automation document) does one of:
   - Adds the user's AD identity to a **time-boxed AD group** membership already mapped to the Permission Set (removed automatically by a scheduled cleanup Lambda / EventBridge Scheduler at expiry), or
   - Creates a **temporary IAM Identity Center assignment** on the target account's Permission Set for that user, and schedules its removal via EventBridge Scheduler.
4. **Session**: User logs into AWS access portal (Identity Center), assumes the just-granted permission set, and runs:
   ```
   aws ssm start-session --target <instance-id> --document-name AWS-StartPortForwardingSession \
     --parameters '{"portNumber":["1521"],"localPortNumber":["1521"]}'
   ```
   (port-forward to Oracle/SQL listener) **or** a full interactive/RDP session via `AWS-StartPortForwardingSessionToRemoteHost` for RDP-based tools, tunneled to the jump host's local desktop.
5. **Auto-revoke**: EventBridge Scheduler fires at expiry, removes AD group membership / Identity Center assignment. Any live session is also terminated via `ssm:TerminateSession` triggered from the same cleanup automation.
6. **Break-glass**: A separate, heavily logged/alerted emergency access path (pre-approved, notifies security immediately) for outages when the approver is unavailable.

This gives the three PIM pillars: **eligibility (AD group) → activation (approval + time-bound grant) → automatic expiry**, without needing a third-party PIM product. If your organization already runs CyberArk/BeyondTrust/Azure AD PIM on-prem, that tool can replace steps 1–3/6 above and simply write the temporary AD group membership; AWS-side mechanics (4–5) stay the same.

---

## 6. Auditability

| Layer | Mechanism |
|---|---|
| Who requested/approved | Step Functions/Automation execution history + SNS/Teams approval log |
| Who authenticated | IAM Identity Center sign-in logs → CloudTrail (`sso.amazonaws.com`) |
| Who started a session, against which instance, when | CloudTrail `ssm:StartSession` / `TerminateSession` events |
| What happened in the session (keystrokes/output) | Session Manager **session logging** to S3 (with SSE-KMS) and/or CloudWatch Logs, enabled at the SSM preferences level, non-optional (deny `StartSession` if logging disabled via SCP/IAM condition `ssm:SessionDocumentAccessCheck`) |
| Central retention | Aggregate CloudTrail + Session logs to the log-archive/security account (typical for a multi-account Control Tower/Landing Zone setup), retained per compliance policy |
| Alerting | EventBridge rule on `StartSession` for Prod → notify security/SOC channel in real time |
| Access review | Quarterly review of AD eligibility groups + Identity Center permission set assignments (Access Analyzer / IAM Identity Center reporting) |

Enforce via **SCP**: deny `ssm:StartSession` unless the calling principal's session tag matches an approved, time-bound tag set by the JIT automation, and deny disabling of SSM session logging preferences.

---

## 7. Jump Host Build (Tooling: SQL Developer, DBeaver, etc.)

- **Golden AMI pipeline**: Base Ubuntu (or Windows Server, if GUI tools require it) AMI, built with **Packer**, stored/versioned, with:
  - SSM Agent pre-installed and enabled
  - CloudWatch Agent for OS-level monitoring
  - Tooling installed as **Docker containers** where possible (e.g., SQL Developer/DBeaver run inside a container with a VNC/noVNC or NICE DCV web front end) — consistent with your Docker/Docker Hub preference and avoids reinstalling GUI tools per-instance
  - Pull tool images from an **internal registry mirror** (e.g., ECR pull-through cache or Nexus/Harbor) since there is no direct internet/Docker Hub access — configure an ECR pull-through cache for `docker.io` if you want to keep Docker Hub as the source of truth while respecting the no-internet-egress rule
- **IaC**: AMI build + jump host stack (subnet, SG, IAM instance profile, SSM associations) defined in **Terraform**, stored in **GitHub**, deployed via **GitHub Actions** (OIDC federation to AWS — no long-lived AWS keys in CI), one workspace/pipeline per account/tier.
- **Patch/lifecycle**: SSM Patch Manager + State Manager association keep jump hosts current; treat as ephemeral/immutable — rebuild from AMI rather than patch in place where feasible.
- **Local dev loop**: You can build/test the container images for the tools on your Windows 11 + Git Bash + VS Code + Ubuntu (WSL or EC2 dev box) setup, push to Docker Hub / internal registry via GitHub Actions, matching your existing workflow.

---

## 8. Summary Diagram (textual)

```
On-Prem AD/PIM tool ── Direct Connect ── Network Account
                                             │
                          ┌──────────────────┴──────────────────┐
                          │        Endpoint VPC (existing)        │
                          │  Interface Endpoints: ssm, ssmmessages,│
                          │  ec2messages, kms, logs, sts, s3        │
                          │  + Private Hosted Zones (existing)     │
                          └──────────────────┬──────────────────┘
                                             │ (private DNS resolution only,
                                             │  no new TGW routes required)
        ┌────────────────────────────────────┼────────────────────────────────────┐
        │ Dev Account                        │ Test Account                       │ Prod Account
        │  ┌───────────────┐                 │  ┌───────────────┐                 │  ┌───────────────┐
        │  │ Jump Host      │  ssm:StartSess. │  │ Jump Host      │  ssm:StartSess. │  │ Jump Host      │
        │  │ (Docker tools) │────────────────▶│  │ (Docker tools) │────────────────▶│  │ (Docker tools) │
        │  └───────────────┘   port-forward   │  └───────────────┘   port-forward   │  └───────────────┘
        │        │  to target EC2 (SSM, no    │        │                            │        │
        │        ▼  inbound SSH/RDP needed)   │        ▼                            │        ▼
        │  Target EC2s (App/DB)               │  Target EC2s                        │  Target EC2s
        └─────────────────────────────────────┴─────────────────────────────────────┴─────────────────

Identity: IAM Identity Center (federated to on-prem AD) → JIT Automation (approval + time-boxed grant)
Audit:    CloudTrail (StartSession/TerminateSession) + Session logs → S3/CloudWatch → Log-archive account
```

---

## 9. Implementation Checklist

- [ ] Add SSM/KMS/Logs/STS/S3 interface endpoints to central Endpoint VPC (if missing) and confirm Private Hosted Zone association to member VPCs
- [ ] Confirm SG egress-only rules on jump hosts and target EC2s (443 to endpoint ENIs)
- [ ] Build golden AMI (Packer) with SSM Agent, CloudWatch Agent, Docker
- [ ] Stand up ECR pull-through cache (or internal registry) for tool container images
- [ ] Enable IAM Identity Center, federate to on-prem AD (AD Connector or SAML)
- [ ] Define per-tier Permission Sets scoped by resource tags, capped session duration
- [ ] Build JIT request/approval automation (Step Functions/SSM Automation + EventBridge Scheduler for auto-revoke)
- [ ] Enforce SCP: mandatory session logging, deny disabling SSM preferences
- [ ] Wire CloudTrail + Session logs to central log-archive account; add SOC alert on Prod `StartSession`
- [ ] Terraform modules in GitHub, deployed via GitHub Actions with OIDC (no static AWS keys)
- [ ] Quarterly access review of AD eligibility groups and Identity Center assignments
