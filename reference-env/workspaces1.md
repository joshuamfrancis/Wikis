# Addendum — Does WorkSpaces (Windows Server) require Active Directory?

Companion to `workspaces-jump-server-design.md`. Includes corrections to that document.

---

## 1. Short answer

**The Windows Server OS is not what creates the AD requirement — the WorkSpaces *directory registration* is.** So the answer depends entirely on which WorkSpaces flavour you use:

| Flavour | AD required? | Detail |
|---|---|---|
| **WorkSpaces Personal**, AWS-provided Windows Server bundles | **Yes** | Personal always needs a registered directory. For license-included Windows Server bundles, your only options are AD-type directories: Simple AD, AWS Managed Microsoft AD, AD Connector, or a trust. |
| **WorkSpaces Personal**, Entra ID / Custom directory types | Yes-ish, but not AD | These directory types exist, but they **only support Windows 10/11 BYOL** — so they are not available to you on Windows Server bundles. |
| **WorkSpaces Pools** | **No — AD join is optional** | Users authenticate via SAML 2.0 / IAM Identity Center. Domain join is an opt-in configuration. |

Important nuance: **it does not have to be *your* on-premises AD.** Simple AD (Samba 4–based) or a standalone AWS Managed Microsoft AD both satisfy the requirement with zero dependency on your on-prem forest.

---

## 2. Why the confusion — Windows Server *is* the desktop

AWS's license-included Windows WorkSpaces bundles are **Windows Server with Desktop Experience**, skinned to present a Windows 10/11 desktop. Currently AWS provides Windows Server 2016, 2019, 2022 and 2025 (plus Amazon Linux 2, Ubuntu 22.04, Rocky Linux 8, RHEL 8). <cite index="18-1">Actual Windows 10 and Windows 11 client OS is only available via Bring Your Own License.</cite>

Two consequences worth knowing:

- <cite index="24-1">Every license-included Windows bundle for Personal and Pools includes a Microsoft RDS Subscriber Access License (SAL) per user. For Pools this is billed at a flat $4.19 per user per month, charged in full and not pro-rated, for any user who starts a session that month. BYOL licences carry no RDS SAL fee.</cite>
- BYOL (and therefore the Entra ID / Custom directory options) requires dedicated hardware and a minimum monthly WorkSpaces commitment per Region — AWS documentation currently cites 50, older material cites 100. **For a handful of per-account jump servers this is a hard blocker.** Assume you are on Windows Server bundles.

---

## 3. WorkSpaces Personal — the full directory option list

<cite index="45-1">Personal supports: Simple AD; AWS Managed Microsoft AD; AD Connector to an existing Microsoft AD; a trust between AWS Managed Microsoft AD and your on-premises domain; a dedicated Microsoft Entra ID directory; or a dedicated Custom directory. Shared directories are not supported with WorkSpaces.</cite>

<cite index="31-1">The Microsoft Entra ID directory type uses Entra ID as its identity source via IAM Identity Center — WorkSpaces are Entra-native joined and enrolled into Intune through Windows Autopilot user-driven mode — but it only supports Windows 10 and 11 BYOL WorkSpaces.</cite> The Custom directory type (IAM Identity Center + your own IdP) carries the same BYOL-only restriction and requires DCV.

**Net effect for you:** the tightest Entra integration AWS offers is off the table unless you commit to BYOL. Your realistic path stays AD Connector → on-prem AD, with SAML 2.0 federation to Entra layered on top for session start.

### Correction to the main design doc

<cite index="43-1">Simple AD and AD Connector are provided free of charge when registered with WorkSpaces. If no WorkSpaces are used with the directory for 30 consecutive days it is automatically deregistered and you begin paying standard AWS Directory Service rates.</cite> <cite index="44-1">The active-user requirement is at least 1 active user for small directories and at least 100 for large.</cite>

This **removes the per-account AD Connector cost objection** in §2 of the design doc — but introduces a subtler one: a per-account jump WorkSpace that goes unused for 30 days will silently trigger directory deregistration and start billing. That is a real operational trap for break-glass desktops used quarterly. Add monitoring for it.

<cite index="32-1">Note also that AD Connector cannot be shared with other AWS accounts and is not multi-VPC aware — AWS applications such as WorkSpaces must be provisioned into the same VPC as the AD Connector.</cite> This confirms the one-directory-per-account structure in the design doc; the cost is now operational, not financial.

---

## 4. WorkSpaces Pools — AD is genuinely optional

<cite index="12-1">You can join Windows WorkSpaces in Pools to Microsoft Active Directory domains — cloud-based or on-premises — or use AWS Managed Microsoft AD. Doing so lets users reach AD resources such as printers and file shares from streaming sessions, apply Group Policy from the GPMC, stream applications requiring AD credential authentication, and apply enterprise compliance and security policies.</cite> <cite index="6-1">Domain join is explicitly optional in the pool configuration.</cite>

### The catch that matters for your PIM design

In a **non-domain-joined** pool, Entra ID is used only for SAML authentication into the session. <cite index="3-1">The Windows account that actually logs in is a built-in local account called `PhotonUser`, which has no administrator rights by default. Making an Entra user a local administrator on the session requires domain-joining the pool and configuring a GPO; alternatively you can grant `PhotonUser` itself admin rights, which applies regardless of which user is connected.</cite>

That is a significant finding for a jump-server use case:

| Consequence | Impact on the PIM design |
|---|---|
| Session identity is `PhotonUser`, not the operator | Windows event logs on the jump box attribute actions to a shared account. Your only per-operator attribution is the Entra SAML sign-in log. **Weak audit trail for privileged access.** |
| Cannot grant per-user local admin without domain join | Any privilege you grant is granted to every pool user. The PIM `PRIV-…-ADMIN` tier collapses. |
| No Kerberos identity for the session | RDP from the jump box to domain-joined target VMs requires manual credential entry (no seamless SSO), and those credentials are typed into a shared-account desktop. |
| Group Policy does not apply | You lose GPO as the enforcement point for session timeouts, logon rights, and hardening. |

**So: for a PIM-gated privileged jump server, "Pools without AD" is a false economy.** The non-persistence benefit is real, but you lose per-user attribution and per-user privilege — the two things a privileged-access control is supposed to give you. If you go Pools, **domain-join it** (which then requires certificate-based authentication for the Windows SSO, and an AWS Private CA).

<cite index="15-1">Note also that domain-joined WorkSpaces Pools require SAML 2.0 user federation</cite>, and <cite index="11-1">a domain service account with permissions to create and manage computer objects, plus a purpose-built OU — the default Computers container is not an OU and cannot be used.</cite> <cite index="13-1">The minimum OU permissions for that service account are Create Computer Object, Change Password, Reset Password, and Write Description.</cite>

---

## 5. Revised recommendation

| Scenario | Directory choice |
|---|---|
| **Personal jump server per account (your stated design)** | AD Connector → on-prem AD. Free while actively used. Gives you AD identity, GPO, Kerberos to targets, and the group-writeback hook for Entra PIM. Add SAML 2.0 federation to Entra for session start. |
| **If you wanted to avoid on-prem AD dependency entirely** | Simple AD or a standalone AWS Managed Microsoft AD per account. Works, but the accounts on it are isolated islands — no Entra PIM writeback path, no on-prem GPO, and separate credential lifecycle. **Not recommended for privileged access.** |
| **Pools jump server** | Domain-join it. Non-domain-joined Pools give you `PhotonUser` and no per-operator attribution. |
| **Entra ID / Custom directory (native Entra join + Intune)** | Only if you can meet BYOL commitments. Attractive on paper — closest thing to real Entra-native integration — but the Windows 10/11 BYOL minimum-commitment and dedicated-hardware requirements almost certainly rule it out at jump-server scale. |

---

## 6. Reframing the question

If the driver behind "does it need AD?" is *"can I avoid standing up a directory in every account?"*, the honest answer is that WorkSpaces will always cost you a directory object per account, and the alternatives that avoid it (non-domain-joined Pools) cost you the audit and privilege model instead.

That trade-off is one of the stronger arguments for the §10 alternative in the main document: **SSM Session Manager needs no directory at all**, authorises per-IAM-principal, logs sessions natively, and works entirely over VPC endpoints — which also sidesteps the egress problem in §5. If the requirement is privileged access to VMs rather than a full Windows desktop, that path avoids this entire question.

---

*Verify BYOL minimum commitment figures, current OS bundle availability, and WorkSpaces Pools regional availability in `ap-southeast-2` against current AWS documentation before design sign-off.*
