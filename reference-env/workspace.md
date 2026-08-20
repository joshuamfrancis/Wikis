# Addendum 4 — The two-gate jump box, explained

Unpacking: *"domain-join the EC2 jump box to on-prem AD over Direct Connect for Kerberos and GPO, while the front door stays IAM-gated and logged."*

Companion to `workspaces-jump-server-design.md`.

---

## 1. The core idea: separate two decisions that are usually conflated

Most jump-server designs answer one question — *"is this person allowed in?"* — with one identity system. This design answers **two different questions with two independent identity systems**, in series:

| Question | Decided by | Enforced at |
|---|---|---|
| **Can this person reach the jump box at all?** | AWS IAM ← IAM Identity Center ← Entra ID ← PIM | The AWS API, before any network connection exists |
| **Who is this person on Windows, and what may they do here and onward?** | On-premises Active Directory (Kerberos + GPO) | The OS, at logon and throughout the session |

Neither gate can be satisfied by compromising the other. An attacker with valid AD credentials has no network path to the box. An attacker with a hijacked Entra session lands on a desktop where they are nobody and can do nothing.

```
Operator
   │
   │ ① FRONT DOOR — AWS control plane
   │    Entra ID (PIM activation, Conditional Access, MFA)
   │        └─SAML/SCIM─▶ IAM Identity Center ─▶ permission set
   │                            │
   │                            ▼
   │    ssm:StartSession  (CloudTrail: who, when, which instance)
   │    AWS-StartPortForwardingSession → localhost:13389
   │    Session transcript ─▶ S3 / CloudWatch Logs (KMS encrypted)
   │
   ▼
┌──────────────────────────────────────────────────┐
│  EC2 jump box — NO inbound security group rules   │
│  SSM Agent makes OUTBOUND calls only, to VPC      │
│  endpoints: ssm, ssmmessages, ec2messages         │
│                                                   │
│  ② OS LOGON — RDP over the tunnel                 │
│     Named AD user, Kerberos, GPO applied          │
└───────────────────┬──────────────────────────────┘
                    │ ③ ONWARD HOP — Kerberos SSO
                    │    Restricted Admin / Remote Credential Guard
                    ▼
            Target EC2 VMs in the same account
```

---

## 2. Gate ① — the IAM front door

### 2.1 What "no front door" actually means

The jump box has **no inbound security group rules at all**. Port 3389 is not open to anything — not to your on-prem CIDR, not to a bastion subnet, not to the Network account. The SSM Agent on the instance opens *outbound* connections to three VPC interface endpoints (`ssm`, `ssmmessages`, `ec2messages`) which you can host once in your central Endpoint VPC and share via the existing private hosted zones.

Consequences worth stating plainly:
- There is no port to scan, no RDP service exposed to any network, and no NLB/ALB in front of it.
- Network reachability is no longer a security control you have to get right — because there is no reachable listener.
- This works with **zero internet egress**, which is why it removes the NAT/Network Firewall exception from the main design.

### 2.2 How the operator actually connects

Three options, all over the same SSM channel:

| Method | Use |
|---|---|
| `aws ssm start-session` | PowerShell shell. Fastest, fully logged. |
| `AWS-StartPortForwardingSession` → `mstsc localhost:13389` | **The recommended one.** Tunnels 3389 through SSM to a local port, then you use a real RDP client. Full desktop, real AD logon. |
| Fleet Manager RDP (console) | Browser-based RDP. Convenient, good for break-glass, fewer features. |

The port-forwarding option is the key to "best of both": the *transport* is IAM-authorised and logged, while the *logon* inside the tunnel is a named AD user with Kerberos. You get AWS-side authorisation without giving up Windows identity.

### 2.3 What the IAM gate can express

The permission set attached to the PIM-activated group is where JIT actually bites:

```jsonc
{
  "Effect": "Allow",
  "Action": ["ssm:StartSession"],
  "Resource": "arn:aws:ec2:*:*:instance/*",
  "Condition": {
    "StringEquals": { "ssm:resourceTag/Role": "jumpbox" }
  }
}
```

Plus, typically:
- Restrict which SSM documents may be used (`AWS-StartPortForwardingSession` only, not `AWS-RunShellScript`).
- Scope `ssm:TerminateSession` to the caller's own sessions using `${aws:userid}`.
- Deny everything else in the account, so an activated operator can reach the jump box and nothing else via the API.

### 2.4 What gets logged, and why it matters

- **CloudTrail** records every `StartSession` with the IdC principal, source IP, instance ID, and timestamp. This is your "who opened the door, when" record — and it exists whether or not anything useful happens afterwards.
- **Session Manager transcripts** go to S3 and/or CloudWatch Logs, KMS-encrypted, with the bucket in a separate logging account your operators cannot write to.
- **Session preferences** are set centrally in an SSM document: idle timeout, maximum session duration, KMS encryption enforcement. These apply org-wide and cannot be overridden per-instance by whoever built the instance.

WorkSpaces has no equivalent to any of this. That was the open audit gap in §9 of the main document.

### 2.5 An honest caveat: `ssm-user`

If an operator uses a plain `start-session` shell (not the RDP tunnel), the Windows session runs as a **local `ssm-user` account**, not their AD identity. That looks like the `PhotonUser` problem from WorkSpaces Pools — but it isn't equivalent, because:

- CloudTrail attributes the session to the named IdC principal, and
- the session transcript captures everything typed.

So attribution survives at the session layer even though the OS account is shared. Still, for privileged work, **prefer the RDP-over-port-forward path** so that Windows event logs also carry the named AD user. Where you allow shell sessions, treat `ssm-user` as a shared account and rely on the transcript.

---

## 3. Gate ② — domain join, Kerberos, and GPO

### 3.1 Why bother joining at all, if IAM already gates access?

Because IAM controls *reaching* the box. It says nothing about identity *inside* Windows, and nothing at all about the target VMs. Domain join gives you four things IAM cannot:

**Named OS identity.** Windows Security event log records a real user SID, not a shared local account. Your on-prem SIEM correlates it with everything else that user does across the estate.

**Group Policy as the enforcement plane.** This is where the PIM group written back from Entra actually does work:
- `Allow log on through Remote Desktop Services` → scoped to the PIM group only.
- `Deny log on locally` / `Deny log on as a batch job` → everyone else.
- Idle disconnect and maximum session duration → **this is the mechanism that partially closes the "PIM expiry doesn't terminate live sessions" gap** from §4.4 of the main doc.
- Your existing server hardening baseline, AppLocker/WDAC, PowerShell script-block logging, advanced audit policy, Sysmon deployment — all inherited automatically, identical to on-prem.
- LAPS for the local Administrator account.

**Kerberos for the onward hop.** From the jump box, RDP/WinRM/SMB to target VMs uses Kerberos SSO. No credential re-entry, no NTLM. And critically, it enables:
- **Restricted Admin mode** and **Remote Credential Guard** for RDP to targets, so credential material is never left in memory on the target machine. This is exactly the protection a jump host exists to provide, and it requires domain-joined Windows with Kerberos.
- **Protected Users** group membership for privileged accounts (forces Kerberos, blocks NTLM, blocks delegation, disables credential caching). Requires 2012R2 domain functional level and will break some legacy scenarios — test before enforcing.
- Short Kerberos ticket lifetimes for the privileged group, which tightens how long a session outlives a PIM expiry.

**No AWS Directory Service object.** The instance joins your on-prem domain **directly over Direct Connect**. No AD Connector, no Managed AD, no WorkSpaces directory registration, no 30-day auto-deregistration trap, and nothing to build per account.

### 3.2 Mechanics of joining on-prem AD directly

There is no "seamless domain join" for raw on-prem AD — SSM's `AWS-JoinDirectoryServiceDomain` requires an AWS Directory Service object. For a direct join, use either:

- **Bootstrap script**: a domain-join service account retrieved from Secrets Manager at first boot, then `Add-Computer -DomainName ... -OUPath ...`. Delegate the service account minimum rights on a purpose-built OU (Create Computer Object, Change Password, Reset Password, Write Description).
- **Pre-staged djoin blob**: pre-create the computer object on-prem and inject an offline domain-join blob. Avoids putting any domain credential on the instance at all. More setup, better posture — worth it for production.

### 3.3 Network requirements over TGW/DX

Your explicit-route, no-propagation TGW model needs these opened from the jump subnets to the DC subnets, and permitted through Network Firewall east-west inspection:

| Port | Purpose |
|---|---|
| 53 TCP/UDP | DNS |
| 88 TCP/UDP | Kerberos |
| 123 UDP | NTP (clock skew >5 min breaks Kerberos) |
| 135 TCP | RPC endpoint mapper |
| 389 TCP/UDP, 636 TCP | LDAP / LDAPS |
| 445 TCP | SMB |
| 464 TCP/UDP | Kerberos password change |
| 3268/3269 TCP | Global Catalog |
| 49152–65535 TCP | RPC dynamic range |

**The RPC dynamic range is the usual blocker.** A stateful firewall rule permitting 16,000 ports is a hard sell. Restrict the AD RPC dynamic port range on your DCs to a narrow band (registry-configurable) and open only that. Do this before you build, not after the domain join fails.

### 3.4 DNS

Your shared Route 53 Resolver forwarding rule already covers the AD domain, and rules match subdomains — so `_msdcs.<domain>` SRV lookups resolve through the same rule. **Verify this specifically**, because if `_msdcs` is a separately delegated zone in your DNS design, domain join will fail in a way that looks like a network problem.

### 3.5 Computer object lifecycle

If you rebuild jump boxes monthly from a golden AMI (and you should — see §6 of the cost addendum), you will accumulate stale AD computer objects. Add an ASG lifecycle hook or termination event → Lambda → remove the computer object, or a scheduled stale-object cleanup on-prem. Left alone, this becomes an audit finding within a year.

---

## 4. Why the two gates compose well

The genuine architectural argument is **defence in depth across two independent trust domains**:

| Compromise scenario | What the attacker gets |
|---|---|
| Entra account + session token stolen | Can call `ssm:StartSession` — but has no AD credential, so cannot log on to Windows. Lands nowhere. Session is recorded. |
| AD credential stolen (phishing, on-prem breach) | Has a valid Windows identity — but no AWS access, so no network path to the jump box at all. |
| PIM group writeback fails or is delayed | The IAM gate still holds. Access to the box is denied even if AD rights linger. |
| DX link drops | AD auth fails — **but SSM still works**, because it depends on VPC endpoints, not on-prem. Break-glass via LAPS local account remains available. |

That last row is worth dwelling on. **A WorkSpace whose AD Connector cannot reach the domain controllers is completely inaccessible** — you cannot log in, full stop. The EC2 design degrades gracefully: you lose the AD identity, you keep an IAM-authorised, logged path to a local break-glass account. For a jump server whose whole purpose is incident response, that resilience difference is not a footnote.

Note the trade-off: for security you'd normally set cached logon count to 0 on a jump box, which means a DX outage removes AD logon entirely. That makes the LAPS + SSM break-glass path essential rather than optional. Document it and test it.

---

## 5. Correcting myself: "strictly better" was too strong

I said this arrangement is *strictly better* than the WorkSpaces one. That holds for the **identity and access-control architecture** — every control WorkSpaces gives you here, EC2 also gives you, plus an independent second gate, plus session transcripts, plus no egress requirement, plus graceful degradation.

It does **not** hold for the product overall. WorkSpaces is better at:

- **Managed image lifecycle** — AWS publishes updated bundles; with EC2 you own a golden AMI pipeline.
- **RDS SAL included** — matters if you need 3+ concurrent operators per box (see §4 of the cost addendum).
- **Streaming quality over a poor WAN** — DCV/WSP tuning in WorkSpaces is better than what you'd get from RDP over an SSM tunnel on a high-latency link. If your operators are remote over ordinary internet rather than on a good corporate link, test this before committing.

So: strictly better on the security architecture, a real trade on operations and user experience.

---

## 6. Build order

1. SSM interface endpoints (`ssm`, `ssmmessages`, `ec2messages`) in the central Endpoint VPC, PHZs associated to the jump subnets.
2. Golden AMI: hardened Windows Server, SSM Agent, no domain join baked in, LAPS configured.
3. Launch one jump instance in a dev account. **Confirm SSM Session Manager works with no inbound rules and no internet route** — this is the proof point for dropping the egress exception.
4. Configure session logging to a locked-down S3 bucket in the logging account, plus central session preferences (idle timeout, max duration, KMS).
5. Open the AD ports to DCs, with the RPC range restricted. Domain-join via pre-staged djoin blob.
6. Link the GPOs: RDS logon rights scoped to the PIM group, session limits, audit policy, Sysmon, WEF to on-prem SIEM.
7. Create the IdC permission set with the tag-scoped `ssm:StartSession` policy; assign the PIM group.
8. Test the full path: PIM activation → AWS portal → port forward → RDP as AD user → Kerberos hop to a target with Restricted Admin.
9. **Test the failure modes**: PIM expiry mid-session, DX outage, break-glass via LAPS, stale computer object cleanup.
10. Codify in Terraform, then replicate to test and prod.

---

*Verify Session Manager Windows `ssm-user` behaviour, Run As support, and Fleet Manager RDP credential handling against current AWS documentation — these have changed before and may change again.*
