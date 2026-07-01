# Joining AWS EC2 Windows Instances Directly to On-Premises Active Directory

This guide walks through **Option 1: Direct Domain Join**, where Windows EC2 instances in AWS join your existing on-premises Active Directory domain over an established hybrid network connection (Site-to-Site VPN or AWS Direct Connect). No AWS Directory Service components are required — the instances behave exactly like any other domain-joined machine in a remote branch office.

---

## Architecture Overview

```
┌─────────────────────────────┐          ┌──────────────────────────────┐
│         AWS VPC             │          │      On-Premises Network     │
│                             │          │                              │
│  ┌───────────────────────┐  │   VPN /  │   ┌──────────────────────┐   │
│  │  Windows EC2 Instance │  │  Direct  │   │  Domain Controllers  │   │
│  │  (Domain Member)      │◄─┼─Connect──┼──►│  (DNS + AD DS)       │   │
│  └───────────────────────┘  │          │   └──────────────────────┘   │
│                             │          │                              │
│  ┌───────────────────────┐  │          │                              │
│  │  Route 53 Resolver    │  │          │                              │
│  │  Outbound Endpoint    │──┼──DNS─────┼──► corp.example.com          │
│  └───────────────────────┘  │          │                              │
└─────────────────────────────┘          └──────────────────────────────┘
```

**How it works:**
1. The hybrid network link (VPN/Direct Connect) provides IP connectivity between the VPC and on-prem subnets.
2. DNS queries for the AD domain (e.g., `corp.example.com`) are forwarded from the VPC to on-prem DNS servers (hosted on the domain controllers).
3. The Windows instance locates domain controllers via DNS SRV records, then authenticates and joins using standard AD protocols (Kerberos, LDAP, SMB, RPC).

---

## Prerequisites

Before starting, confirm the following are in place:

- **Hybrid connectivity established** — AWS Site-to-Site VPN or Direct Connect with a Virtual Private Gateway (VGW) or Transit Gateway (TGW) attached to the VPC.
- **Routing configured** — VPC route tables send on-prem CIDR traffic to the VGW/TGW; on-prem routers send VPC CIDR traffic back over the tunnel. Verify with a simple ICMP ping or `Test-NetConnection` from an EC2 instance to a DC.
- **No overlapping CIDRs** — the VPC CIDR must not overlap with on-prem subnets.
- **AD credentials** — an account with permission to join computers to the domain (by default, authenticated users can join 10 machines; production should use a delegated service account).
- **Domain details** — FQDN of the domain (e.g., `corp.example.com`), IPs of at least two domain controllers/DNS servers, and (optionally) the target OU distinguished name.

---

## Step 1: Open Required Network Ports

Traffic must flow bidirectionally between the EC2 instances and the domain controllers. Configure **VPC security groups**, **network ACLs**, and **on-prem firewalls** to allow:

| Protocol/Port | Service | Direction |
|---|---|---|
| TCP/UDP 53 | DNS | Instance → DC |
| TCP/UDP 88 | Kerberos authentication | Instance → DC |
| UDP 123 | NTP (time sync) | Instance → DC |
| TCP 135 | RPC Endpoint Mapper | Instance → DC |
| TCP/UDP 389 | LDAP | Instance → DC |
| TCP 445 | SMB (Netlogon, SYSVOL, GPO) | Instance → DC |
| TCP/UDP 464 | Kerberos password change | Instance → DC |
| TCP 636 | LDAPS (if used) | Instance → DC |
| TCP 3268–3269 | Global Catalog / GC over SSL | Instance → DC |
| TCP 49152–65535 | RPC dynamic ports | Instance → DC |
| UDP 137–138, TCP 139 | NetBIOS (legacy only, usually skip) | Instance → DC |

**Security group example (outbound from EC2 to on-prem CIDR `10.50.0.0/16`):**

```bash
# Using AWS CLI from gitbash
VPC_SG_ID="sg-0123456789abcdef0"
ONPREM_CIDR="10.50.0.0/16"

aws ec2 authorize-security-group-egress --group-id $VPC_SG_ID \
  --ip-permissions \
  'IpProtocol=tcp,FromPort=53,ToPort=53,IpRanges=[{CidrIp='$ONPREM_CIDR'}]' \
  'IpProtocol=udp,FromPort=53,ToPort=53,IpRanges=[{CidrIp='$ONPREM_CIDR'}]' \
  'IpProtocol=tcp,FromPort=88,ToPort=88,IpRanges=[{CidrIp='$ONPREM_CIDR'}]' \
  'IpProtocol=udp,FromPort=88,ToPort=88,IpRanges=[{CidrIp='$ONPREM_CIDR'}]' \
  'IpProtocol=udp,FromPort=123,ToPort=123,IpRanges=[{CidrIp='$ONPREM_CIDR'}]' \
  'IpProtocol=tcp,FromPort=135,ToPort=135,IpRanges=[{CidrIp='$ONPREM_CIDR'}]' \
  'IpProtocol=tcp,FromPort=389,ToPort=389,IpRanges=[{CidrIp='$ONPREM_CIDR'}]' \
  'IpProtocol=udp,FromPort=389,ToPort=389,IpRanges=[{CidrIp='$ONPREM_CIDR'}]' \
  'IpProtocol=tcp,FromPort=445,ToPort=445,IpRanges=[{CidrIp='$ONPREM_CIDR'}]' \
  'IpProtocol=tcp,FromPort=464,ToPort=464,IpRanges=[{CidrIp='$ONPREM_CIDR'}]' \
  'IpProtocol=udp,FromPort=464,ToPort=464,IpRanges=[{CidrIp='$ONPREM_CIDR'}]' \
  'IpProtocol=tcp,FromPort=636,ToPort=636,IpRanges=[{CidrIp='$ONPREM_CIDR'}]' \
  'IpProtocol=tcp,FromPort=3268,ToPort=3269,IpRanges=[{CidrIp='$ONPREM_CIDR'}]' \
  'IpProtocol=tcp,FromPort=49152,ToPort=65535,IpRanges=[{CidrIp='$ONPREM_CIDR'}]'
```

> **Note:** Security groups are stateful, so return traffic is allowed automatically. If you use NACLs, remember they are stateless — you must allow the ephemeral return ports in both directions.

On the **on-prem firewall**, allow the same ports inbound from the VPC CIDR to the domain controller subnet.

---

## Step 2: Configure DNS Resolution (Route 53 Resolver — Recommended)

The instance must resolve `_ldap._tcp.dc._msdcs.corp.example.com` SRV records to find DCs. The recommended pattern is **Route 53 Resolver outbound endpoints with conditional forwarding rules**, which keeps AWS-internal DNS (`.amazonaws.com`, VPC endpoints) working while forwarding only AD queries on-prem.

### 2a. Create the Resolver outbound endpoint

```bash
# Security group for the resolver endpoint (allow DNS out to on-prem)
aws route53resolver create-resolver-endpoint \
  --name "onprem-ad-outbound" \
  --direction OUTBOUND \
  --creator-request-id "outbound-$(date +%s)" \
  --security-group-ids sg-0resolverSGid \
  --ip-addresses SubnetId=subnet-0aaa111,SubnetId=subnet-0bbb222
```

Use two subnets in different Availability Zones for high availability.

### 2b. Create a forwarding rule for the AD domain

```bash
aws route53resolver create-resolver-rule \
  --name "forward-corp-example-com" \
  --creator-request-id "rule-$(date +%s)" \
  --rule-type FORWARD \
  --domain-name "corp.example.com" \
  --resolver-endpoint-id rslvr-out-0123456789abcdef \
  --target-ips "Ip=10.50.1.10,Port=53" "Ip=10.50.1.11,Port=53"
```

### 2c. Associate the rule with the VPC

```bash
aws route53resolver associate-resolver-rule \
  --resolver-rule-id rslvr-rr-0123456789abcdef \
  --vpc-id vpc-0123456789abcdef \
  --name "corp-domain-forwarding"
```

Now any instance using the default VPC DNS (`.2` resolver / `169.254.169.253`) automatically forwards `corp.example.com` queries to the on-prem DCs.

### Alternative: DHCP Option Set (simpler, less flexible)

You can instead create a DHCP option set pointing all VPC DNS at the on-prem DCs:

```bash
aws ec2 create-dhcp-options \
  --dhcp-configurations \
  "Key=domain-name-servers,Values=10.50.1.10,10.50.1.11" \
  "Key=domain-name,Values=corp.example.com"

aws ec2 associate-dhcp-options --dhcp-options-id dopt-0123456789 --vpc-id vpc-0123456789abcdef
```

> **Caution:** This routes *all* DNS (including AWS service endpoints) through on-prem, adding latency and a hard dependency on the WAN link. Prefer Route 53 Resolver for production. If you must use DHCP options, configure the on-prem DNS servers to forward non-AD queries appropriately.

---

## Step 3: Verify Connectivity from the EC2 Instance

Launch (or use an existing) Windows Server EC2 instance in the VPC, connect via RDP or SSM Session Manager, and run in PowerShell:

```powershell
# Verify DNS resolves domain SRV records
Resolve-DnsName -Type SRV _ldap._tcp.dc._msdcs.corp.example.com

# Verify reachability of key ports on a DC
Test-NetConnection -ComputerName 10.50.1.10 -Port 389
Test-NetConnection -ComputerName 10.50.1.10 -Port 445
Test-NetConnection -ComputerName 10.50.1.10 -Port 88

# Comprehensive prerequisite check (built into Windows Server)
# Run after installing RSAT-AD tools, or use nltest:
nltest /dsgetdc:corp.example.com
```

If `Resolve-DnsName` fails, revisit Step 2. If ports are unreachable, revisit Step 1 and routing.

**Time sync check:** Kerberos requires clocks within 5 minutes. EC2 defaults to Amazon Time Sync (`169.254.169.123`), which is fine, but confirm on-prem DCs are also properly synced:

```powershell
w32tm /query /status
```

---

## Step 4: Join the Domain

### Method A: Manual join via PowerShell

```powershell
$domain = "corp.example.com"
$ou = "OU=AWS-Servers,OU=Servers,DC=corp,DC=example,DC=com"  # optional
$credential = Get-Credential  # enter CORP\join-svc-account

Add-Computer -DomainName $domain -OUPath $ou -Credential $credential -Restart
```

The instance reboots and comes back as a domain member.

### Method B: Automated join via EC2 user data (at launch)

Add this to the instance user data. **Do not hardcode credentials** — pull them from AWS Secrets Manager:

```powershell
<powershell>
# Retrieve join credentials from Secrets Manager
$secret = Get-SECSecretValue -SecretId "ad/domain-join-account" | 
    Select-Object -ExpandProperty SecretString | ConvertFrom-Json

$securePass = ConvertTo-SecureString $secret.password -AsPlainText -Force
$credential = New-Object System.Management.Automation.PSCredential($secret.username, $securePass)

Add-Computer -DomainName "corp.example.com" `
    -OUPath "OU=AWS-Servers,DC=corp,DC=example,DC=com" `
    -Credential $credential -Restart -Force
</powershell>
```

The instance profile (IAM role) needs `secretsmanager:GetSecretValue` on that secret.

Create the secret first:

```bash
aws secretsmanager create-secret \
  --name "ad/domain-join-account" \
  --secret-string '{"username":"CORP\\join-svc","password":"REPLACE_ME"}'
```

### Method C: Fleet-wide join via SSM Run Command

For joining many existing instances, use `AWS-RunPowerShellScript` targeting by tag:

```bash
aws ssm send-command \
  --document-name "AWS-RunPowerShellScript" \
  --targets "Key=tag:Domain,Values=pending-join" \
  --parameters 'commands=[
    "$secret = Get-SECSecretValue -SecretId ad/domain-join-account | Select-Object -ExpandProperty SecretString | ConvertFrom-Json",
    "$pass = ConvertTo-SecureString $secret.password -AsPlainText -Force",
    "$cred = New-Object System.Management.Automation.PSCredential($secret.username, $pass)",
    "Add-Computer -DomainName corp.example.com -Credential $cred -Restart -Force"
  ]'
```

---

## Step 5: Post-Join Validation

After the reboot, verify from the instance:

```powershell
# Confirm domain membership
(Get-WmiObject Win32_ComputerSystem).Domain     # → corp.example.com

# Verify secure channel to a DC
Test-ComputerSecureChannel -Verbose             # → True

# Confirm which DC the instance authenticated against
nltest /dsgetdc:corp.example.com

# Verify Group Policy applies
gpupdate /force
gpresult /r
```

Then log in with a domain account (`CORP\username`) via RDP to confirm end-to-end authentication.

---

## Step 6 (Optional): AD Sites and Services Optimization

Without site configuration, instances may authenticate against a random DC. Create an **AD Site** for the AWS VPC:

1. Open **Active Directory Sites and Services** on a DC.
2. Create a new site, e.g., `AWS-us-east-1`.
3. Add the VPC CIDR(s) as subnets assigned to that site.
4. Link the site to the on-prem site with an appropriate site link cost.

If you later place read-only or writable DCs in AWS (Option 4), this site becomes their home. Even without DCs in AWS, correct subnet-to-site mapping ensures deterministic DC selection and cleaner Kerberos referrals.

---

## Operational Considerations

- **WAN dependency:** All authentication, GPO processing, and DNS for the domain traverse the hybrid link. If the link fails, cached credentials allow existing logons, but new authentications and Kerberos ticket renewals fail. For resilience, consider Option 2 (Managed AD + trust) or Option 4 (DCs in AWS).
- **Latency:** Keep the link latency low (<100 ms ideally); logon and GPO processing are chatty over RPC/SMB.
- **Computer account hygiene:** Terminated instances leave stale computer objects in AD. Automate cleanup with a Lambda function triggered by EC2 termination events (EventBridge → Lambda → LDAP delete), or a scheduled on-prem script.
- **Naming:** EC2 default hostnames (`EC2AMAZ-XXXXXXX`) are ugly in AD. Rename before joining (`Rename-Computer`) or set the hostname in user data.
- **Security:** Restrict the join service account with delegated permissions (create/delete computer objects in the target OU only). Rotate its password via Secrets Manager rotation.
- **Least-privilege joins:** Pre-stage computer accounts in the target OU if your security policy requires it, then join with `-Options JoinWithNewName,AccountCreate` omitted.

---

## Troubleshooting Quick Reference

| Symptom | Likely Cause | Fix |
|---|---|---|
| `The specified domain either does not exist or could not be contacted` | DNS not resolving SRV records | Verify Resolver rule / DHCP options; test with `Resolve-DnsName -Type SRV` |
| Join hangs then fails with RPC error | Dynamic RPC ports (49152–65535) blocked | Open the range on SGs, NACLs, and on-prem firewall |
| `The trust relationship between this workstation and the primary domain failed` | Stale/reset computer account | `Test-ComputerSecureChannel -Repair -Credential CORP\admin` |
| Kerberos errors (KRB_AP_ERR_SKEW) | Clock drift > 5 minutes | Check `w32tm /query /status` on instance and DCs |
| GPOs not applying | TCP 445 blocked (SYSVOL access) | Open SMB; run `gpresult /r` to confirm DC reachability |
| Slow logons | High WAN latency or wrong-site DC selection | Configure AD Sites (Step 6); check link latency |

---

## Summary

Direct domain join is the simplest architecture conceptually: open the AD ports, forward DNS for the domain to on-prem, and join as usual. Its main trade-off is total dependence on the hybrid network link. It fits well for small fleets, dev/test workloads, or as a first step before evolving to AWS Managed Microsoft AD with a trust, or self-managed DCs in the VPC, as your AWS footprint grows.
