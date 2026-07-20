# Lab: Cross-VPC Domain Join with a Self-Hosted Domain Controller and Route 53 Resolver

**Goal:** In a single AWS account, simulate a hybrid environment using two VPCs:

- **VPC-A (`onprem-sim`)** — plays the role of the on-premises network. Hosts a Windows Server EC2 instance promoted to a **Domain Controller** (`corp.lab`).
- **VPC-B (`aws-workload`)** — plays the role of the AWS cloud environment. Hosts a Windows Server EC2 member instance that will **join (and re-join)** the domain across the VPC-to-VPC link, using **Route 53 Resolver** for DNS forwarding.

All CLI commands are written for **gitbash on Windows 11** with the AWS CLI v2 installed and a configured profile.

```
┌────────────────────────────────┐        ┌────────────────────────────────┐
│  VPC-A: onprem-sim             │        │  VPC-B: aws-workload           │
│  10.50.0.0/16                  │  VPC   │  10.60.0.0/16                  │
│                                │Peering │                                │
│  ┌──────────────────────────┐  │◄──────►│  ┌──────────────────────────┐  │
│  │ EC2: DC01                │  │        │  │ EC2: MEMBER01            │  │
│  │ AD DS + DNS (corp.lab)   │  │        │  │ Joins corp.lab           │  │
│  │ 10.50.1.10 (static)      │  │        │  └──────────────────────────┘  │
│  └──────────────────────────┘  │        │  ┌──────────────────────────┐  │
│  ┌──────────────────────────┐  │        │  │ R53 Resolver OUTBOUND    │  │
│  │ R53 Resolver INBOUND     │  │        │  │ forwards corp.lab ───────┼──┼──► 10.50.1.10
│  │ (optional, reverse demo) │  │        │  └──────────────────────────┘  │
│  └──────────────────────────┘  │        └────────────────────────────────┘
└────────────────────────────────┘
```

> **Cost note:** This lab uses 2× `t3.medium` Windows instances (Windows licensing included in hourly price) and Route 53 Resolver endpoints (~$0.125/hr per ENI). Tear it down when done (Step 10). Expect roughly $1–2/hour while running.

---

## Step 0: Set Variables (gitbash)

```bash
export AWS_PROFILE=default          # your profile
export AWS_REGION=us-east-1
export KEY_NAME=ad-lab-key          # existing EC2 key pair name, or create below
export DOMAIN_FQDN=corp.lab
export DC_IP=10.50.1.10

# Create a key pair if you don't have one
aws ec2 create-key-pair --key-name $KEY_NAME \
  --query 'KeyMaterial' --output text > ~/ad-lab-key.pem
chmod 400 ~/ad-lab-key.pem
```

> **gitbash tip:** If any command mangles paths (gitbash rewrites `/` arguments), prefix with `MSYS_NO_PATHCONV=1`.

---

## Step 1: Create the Two VPCs

```bash
# VPC-A: onprem-sim
VPC_A=$(aws ec2 create-vpc --cidr-block 10.50.0.0/16 \
  --tag-specifications 'ResourceType=vpc,Tags=[{Key=Name,Value=onprem-sim}]' \
  --query 'Vpc.VpcId' --output text)

# VPC-B: aws-workload
VPC_B=$(aws ec2 create-vpc --cidr-block 10.60.0.0/16 \
  --tag-specifications 'ResourceType=vpc,Tags=[{Key=Name,Value=aws-workload}]' \
  --query 'Vpc.VpcId' --output text)

# Enable DNS support/hostnames on both
for V in $VPC_A $VPC_B; do
  aws ec2 modify-vpc-attribute --vpc-id $V --enable-dns-support
  aws ec2 modify-vpc-attribute --vpc-id $V --enable-dns-hostnames
done

echo "VPC_A=$VPC_A  VPC_B=$VPC_B"
```

### Subnets

```bash
# VPC-A: one public subnet for the DC (public = easy RDP for a lab; lock down in real life)
SUBNET_A=$(aws ec2 create-subnet --vpc-id $VPC_A --cidr-block 10.50.1.0/24 \
  --availability-zone ${AWS_REGION}a \
  --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=onprem-dc-subnet}]' \
  --query 'Subnet.SubnetId' --output text)

# Second subnet in VPC-A in another AZ (needed later for the optional inbound resolver)
SUBNET_A2=$(aws ec2 create-subnet --vpc-id $VPC_A --cidr-block 10.50.2.0/24 \
  --availability-zone ${AWS_REGION}b \
  --query 'Subnet.SubnetId' --output text)

# VPC-B: two subnets in different AZs (resolver outbound endpoint requires 2 for HA;
# it *can* run in one, but two is best practice)
SUBNET_B1=$(aws ec2 create-subnet --vpc-id $VPC_B --cidr-block 10.60.1.0/24 \
  --availability-zone ${AWS_REGION}a \
  --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=workload-subnet-1}]' \
  --query 'Subnet.SubnetId' --output text)

SUBNET_B2=$(aws ec2 create-subnet --vpc-id $VPC_B --cidr-block 10.60.2.0/24 \
  --availability-zone ${AWS_REGION}b \
  --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=workload-subnet-2}]' \
  --query 'Subnet.SubnetId' --output text)
```

### Internet Gateways and Routes (for RDP access to both instances)

```bash
for PAIR in "$VPC_A A" "$VPC_B B"; do
  set -- $PAIR
  IGW=$(aws ec2 create-internet-gateway --query 'InternetGateway.InternetGatewayId' --output text)
  aws ec2 attach-internet-gateway --internet-gateway-id $IGW --vpc-id $1
  RT=$(aws ec2 describe-route-tables --filters "Name=vpc-id,Values=$1" \
    --query 'RouteTables[0].RouteTableId' --output text)
  aws ec2 create-route --route-table-id $RT --destination-cidr-block 0.0.0.0/0 --gateway-id $IGW
  eval "RT_$2=$RT"
done
echo "RT_A=$RT_A  RT_B=$RT_B"
```

---

## Step 2: Peer the VPCs (simulates the VPN/Direct Connect link)

```bash
PEER_ID=$(aws ec2 create-vpc-peering-connection \
  --vpc-id $VPC_B --peer-vpc-id $VPC_A \
  --query 'VpcPeeringConnection.VpcPeeringConnectionId' --output text)

aws ec2 accept-vpc-peering-connection --vpc-peering-connection-id $PEER_ID

# Routes across the peering in both directions
aws ec2 create-route --route-table-id $RT_A --destination-cidr-block 10.60.0.0/16 \
  --vpc-peering-connection-id $PEER_ID
aws ec2 create-route --route-table-id $RT_B --destination-cidr-block 10.50.0.0/16 \
  --vpc-peering-connection-id $PEER_ID
```

> **Variation to try later:** Replace peering with a **Transit Gateway** to better mimic a hub-and-spoke hybrid design. The rest of the lab is unchanged.

---

## Step 3: Security Groups

```bash
MY_IP=$(curl -s https://checkip.amazonaws.com)/32

# SG for the DC in VPC-A: allow all AD ports from VPC-B, RDP from your IP
SG_DC=$(aws ec2 create-security-group --vpc-id $VPC_A \
  --group-name dc-sg --description "Domain Controller SG" \
  --query 'GroupId' --output text)

aws ec2 authorize-security-group-ingress --group-id $SG_DC --ip-permissions \
  "IpProtocol=tcp,FromPort=3389,ToPort=3389,IpRanges=[{CidrIp=$MY_IP}]" \
  'IpProtocol=tcp,FromPort=53,ToPort=53,IpRanges=[{CidrIp=10.60.0.0/16}]' \
  'IpProtocol=udp,FromPort=53,ToPort=53,IpRanges=[{CidrIp=10.60.0.0/16}]' \
  'IpProtocol=tcp,FromPort=88,ToPort=88,IpRanges=[{CidrIp=10.60.0.0/16}]' \
  'IpProtocol=udp,FromPort=88,ToPort=88,IpRanges=[{CidrIp=10.60.0.0/16}]' \
  'IpProtocol=udp,FromPort=123,ToPort=123,IpRanges=[{CidrIp=10.60.0.0/16}]' \
  'IpProtocol=tcp,FromPort=135,ToPort=135,IpRanges=[{CidrIp=10.60.0.0/16}]' \
  'IpProtocol=tcp,FromPort=389,ToPort=389,IpRanges=[{CidrIp=10.60.0.0/16}]' \
  'IpProtocol=udp,FromPort=389,ToPort=389,IpRanges=[{CidrIp=10.60.0.0/16}]' \
  'IpProtocol=tcp,FromPort=445,ToPort=445,IpRanges=[{CidrIp=10.60.0.0/16}]' \
  'IpProtocol=tcp,FromPort=464,ToPort=464,IpRanges=[{CidrIp=10.60.0.0/16}]' \
  'IpProtocol=udp,FromPort=464,ToPort=464,IpRanges=[{CidrIp=10.60.0.0/16}]' \
  'IpProtocol=tcp,FromPort=636,ToPort=636,IpRanges=[{CidrIp=10.60.0.0/16}]' \
  'IpProtocol=tcp,FromPort=3268,ToPort=3269,IpRanges=[{CidrIp=10.60.0.0/16}]' \
  'IpProtocol=tcp,FromPort=49152,ToPort=65535,IpRanges=[{CidrIp=10.60.0.0/16}]' \
  'IpProtocol=icmp,FromPort=-1,ToPort=-1,IpRanges=[{CidrIp=10.60.0.0/16}]'

# SG for the member server in VPC-B: RDP from your IP, all outbound (default)
SG_MEMBER=$(aws ec2 create-security-group --vpc-id $VPC_B \
  --group-name member-sg --description "Member Server SG" \
  --query 'GroupId' --output text)

aws ec2 authorize-security-group-ingress --group-id $SG_MEMBER \
  --protocol tcp --port 3389 --cidr $MY_IP

# SG for the Route 53 Resolver outbound endpoint in VPC-B: allow DNS egress
SG_RESOLVER=$(aws ec2 create-security-group --vpc-id $VPC_B \
  --group-name resolver-out-sg --description "R53 Resolver outbound SG" \
  --query 'GroupId' --output text)
# Outbound is open by default, nothing more needed for the lab
```

---

## Step 4: Launch the Domain Controller (VPC-A)

Get the latest Windows Server 2022 AMI and launch DC01 with a **static private IP** (`10.50.1.10`) and user data that installs AD DS and promotes the forest `corp.lab` automatically.

```bash
AMI_ID=$(aws ssm get-parameters \
  --names /aws/service/ami-windows-latest/Windows_Server-2022-English-Full-Base \
  --query 'Parameters[0].Value' --output text)

cat > /tmp/dc-userdata.txt << 'EOF'
<powershell>
# Set a known local admin password for the lab (also becomes DSRM-adjacent context)
$plain = "LabP@ssw0rd2026!"
net user Administrator $plain

# Install AD DS role
Install-WindowsFeature AD-Domain-Services -IncludeManagementTools

# Promote to a new forest: corp.lab
$safeModePwd = ConvertTo-SecureString "DsrmP@ssw0rd2026!" -AsPlainText -Force
Install-ADDSForest `
    -DomainName "corp.lab" `
    -DomainNetbiosName "CORP" `
    -SafeModeAdministratorPassword $safeModePwd `
    -InstallDns `
    -Force
# Instance reboots automatically after promotion
</powershell>
EOF

DC_INSTANCE=$(aws ec2 run-instances \
  --image-id $AMI_ID --instance-type t3.medium \
  --key-name $KEY_NAME \
  --subnet-id $SUBNET_A --private-ip-address $DC_IP \
  --security-group-ids $SG_DC \
  --associate-public-ip-address \
  --user-data file:///tmp/dc-userdata.txt \
  --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=DC01}]' \
  --query 'Instances[0].InstanceId' --output text)

echo "DC01: $DC_INSTANCE"
```

**Wait ~10–15 minutes** for the promotion + reboot. Then RDP to the DC's public IP as `Administrator` / `LabP@ssw0rd2026!` (after the reboot, log in as `CORP\Administrator`) and verify:

```powershell
Get-ADDomain | Select-Object DNSRoot, NetBIOSName
Get-Service ADWS, DNS, Netlogon, KDC | Select-Object Name, Status
Resolve-DnsName -Type SRV _ldap._tcp.dc._msdcs.corp.lab -Server 127.0.0.1
```

Create a lab user and a delegated join account while you're there:

```powershell
New-ADUser -Name "labuser" -SamAccountName labuser `
  -AccountPassword (ConvertTo-SecureString "LabUserP@ss1!" -AsPlainText -Force) `
  -Enabled $true

New-ADUser -Name "join-svc" -SamAccountName join-svc `
  -AccountPassword (ConvertTo-SecureString "JoinSvcP@ss1!" -AsPlainText -Force) `
  -Enabled $true -PasswordNeverExpires $true

New-ADOrganizationalUnit -Name "AWS-Servers" -Path "DC=corp,DC=lab"
```

> **Lab hygiene:** these are throwaway passwords for an isolated lab. Never do this in production — use Secrets Manager.

---

## Step 5: Route 53 Resolver Outbound Endpoint (VPC-B → DC DNS)

This is the piece that makes MEMBER01 able to *find* the domain without touching its NIC DNS settings — exactly like the recommended production hybrid pattern.

```bash
# 5a. Outbound endpoint across the two VPC-B subnets
OUT_EP=$(aws route53resolver create-resolver-endpoint \
  --name "lab-outbound" \
  --direction OUTBOUND \
  --creator-request-id "out-$(date +%s)" \
  --security-group-ids $SG_RESOLVER \
  --ip-addresses SubnetId=$SUBNET_B1 SubnetId=$SUBNET_B2 \
  --query 'ResolverEndpoint.Id' --output text)

# Wait for it to become OPERATIONAL (a few minutes)
aws route53resolver get-resolver-endpoint --resolver-endpoint-id $OUT_EP \
  --query 'ResolverEndpoint.Status'

# 5b. Forwarding rule: corp.lab → DC01
RULE_ID=$(aws route53resolver create-resolver-rule \
  --name "forward-corp-lab" \
  --creator-request-id "rule-$(date +%s)" \
  --rule-type FORWARD \
  --domain-name "corp.lab" \
  --resolver-endpoint-id $OUT_EP \
  --target-ips "Ip=$DC_IP,Port=53" \
  --query 'ResolverRule.Id' --output text)

# 5c. Associate the rule with VPC-B
aws route53resolver associate-resolver-rule \
  --resolver-rule-id $RULE_ID --vpc-id $VPC_B --name "corp-lab-assoc"
```

Now any instance in VPC-B using the default VPC resolver automatically forwards `*.corp.lab` queries to DC01, while everything else (AWS endpoints, internet names) resolves normally.

---

## Step 6: Launch the Member Server (VPC-B)

```bash
cat > /tmp/member-userdata.txt << 'EOF'
<powershell>
net user Administrator "LabP@ssw0rd2026!"
Rename-Computer -NewName "MEMBER01" -Force -Restart
</powershell>
EOF

MEMBER_INSTANCE=$(aws ec2 run-instances \
  --image-id $AMI_ID --instance-type t3.medium \
  --key-name $KEY_NAME \
  --subnet-id $SUBNET_B1 \
  --security-group-ids $SG_MEMBER \
  --associate-public-ip-address \
  --user-data file:///tmp/member-userdata.txt \
  --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=MEMBER01}]' \
  --query 'Instances[0].InstanceId' --output text)

echo "MEMBER01: $MEMBER_INSTANCE"
```

RDP into MEMBER01 (local `Administrator` / `LabP@ssw0rd2026!`) and verify the cross-VPC path **before** joining:

```powershell
# DNS via Route 53 Resolver forwarding — the key test
Resolve-DnsName corp.lab
Resolve-DnsName -Type SRV _ldap._tcp.dc._msdcs.corp.lab

# Confirm the instance is still using the VPC default resolver (not the DC directly)
Get-DnsClientServerAddress -AddressFamily IPv4

# Port reachability across the peering
Test-NetConnection $env:DC_IP -Port 389   # replace with 10.50.1.10
Test-NetConnection 10.50.1.10 -Port 445
Test-NetConnection 10.50.1.10 -Port 88
nltest /dsgetdc:corp.lab
```

If SRV resolution works while your DNS server is still the VPC `.2` resolver — the Route 53 Resolver forwarding chain is proven.

---

## Step 7: Join the Domain (First Join)

On MEMBER01:

```powershell
$cred = New-Object System.Management.Automation.PSCredential(
  "CORP\join-svc",
  (ConvertTo-SecureString "JoinSvcP@ss1!" -AsPlainText -Force))

Add-Computer -DomainName "corp.lab" `
  -OUPath "OU=AWS-Servers,DC=corp,DC=lab" `
  -Credential $cred -Restart -Force
```

After reboot, log in as `CORP\labuser` and validate:

```powershell
(Get-WmiObject Win32_ComputerSystem).Domain     # corp.lab
Test-ComputerSecureChannel -Verbose             # True
nltest /sc_query:corp.lab                       # shows the secure channel DC
klist                                           # Kerberos tickets issued by DC01
gpupdate /force ; gpresult /r
```

On DC01, confirm the computer object:

```powershell
Get-ADComputer MEMBER01 -Properties whenCreated, OperationalOU |
  Select-Object Name, DistinguishedName, whenCreated
```

---

## Step 8: Re-Join Scenarios (the core of the lab)

These exercises simulate the real-world "trust relationship broken / instance re-provisioned" cases and how to recover across the VPC link.

### Scenario A: Broken secure channel → repair without full rejoin

Simulate by resetting the computer account **on the DC**:

```powershell
# On DC01
Get-ADComputer MEMBER01 | Set-ADAccountPassword -Reset `
  -NewPassword (ConvertTo-SecureString "Bogus$(Get-Random)!" -AsPlainText -Force)
```

Reboot MEMBER01 and try to log in with `CORP\labuser` — you'll hit:
`The trust relationship between this workstation and the primary domain failed.`

**Repair** (log in with the *local* Administrator, no rejoin/reboot needed):

```powershell
# On MEMBER01, as local admin
$cred = Get-Credential CORP\join-svc
Test-ComputerSecureChannel -Repair -Credential $cred -Verbose
Test-ComputerSecureChannel     # should now return True
```

Alternative one-liner repair:

```powershell
Reset-ComputerMachinePassword -Server DC01.corp.lab -Credential $cred
```

### Scenario B: Full unjoin / rejoin cycle

```powershell
# On MEMBER01 — leave the domain
Remove-Computer -UnjoinDomainCredential (Get-Credential CORP\join-svc) `
  -WorkgroupName "WORKGROUP" -Restart -Force

# After reboot, rejoin (same command as Step 7)
Add-Computer -DomainName "corp.lab" -OUPath "OU=AWS-Servers,DC=corp,DC=lab" `
  -Credential (Get-Credential CORP\join-svc) -Restart -Force
```

Observe on DC01: the existing computer object is **reused** (same DN, `whenCreated` unchanged, `pwdLastSet` updated).

### Scenario C: Instance replacement (cloud-native rejoin)

Terminate MEMBER01 and launch a new instance with the same hostname in its user data, joining at boot. This simulates immutable-infrastructure workflows:

```powershell
<powershell>
Rename-Computer -NewName "MEMBER01" -Force
$pwd = ConvertTo-SecureString "JoinSvcP@ss1!" -AsPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential("CORP\join-svc", $pwd)
Add-Computer -DomainName "corp.lab" -OUPath "OU=AWS-Servers,DC=corp,DC=lab" `
  -Credential $cred -Options AccountCreate -Restart -Force
</powershell>
```

> If the join fails because the old computer account still exists with a mismatched password, this is the classic stale-object problem. Fix on DC01 with `Get-ADComputer MEMBER01 | Remove-ADObject -Recursive -Confirm:$false` before the new instance boots — and note this as the automation gap you'd close with an EventBridge→Lambda cleanup in production.

### Scenario D: Break DNS on purpose

Disassociate the resolver rule and watch domain operations fail — great for building troubleshooting intuition:

```bash
ASSOC_ID=$(aws route53resolver list-resolver-rule-associations \
  --filters Name=ResolverRuleId,Values=$RULE_ID \
  --query 'ResolverRuleAssociations[0].Id' --output text)
aws route53resolver disassociate-resolver-rule \
  --vpc-id $VPC_B --resolver-rule-id $RULE_ID
```

On MEMBER01: `nltest /dsgetdc:corp.lab` now fails (DNS SRV lookup dies), Kerberos ticket renewal eventually fails, but cached logons still work. Re-associate the rule to restore:

```bash
aws route53resolver associate-resolver-rule --resolver-rule-id $RULE_ID --vpc-id $VPC_B
```

---

## Step 9 (Optional): Inbound Resolver — Reverse Direction Demo

To simulate on-prem resolving AWS-private names (e.g., VPC-B private hosted zones), add an **inbound endpoint** in VPC-B and a conditional forwarder on DC01's DNS:

```bash
IN_EP=$(aws route53resolver create-resolver-endpoint \
  --name "lab-inbound" \
  --direction INBOUND \
  --creator-request-id "in-$(date +%s)" \
  --security-group-ids $SG_RESOLVER \
  --ip-addresses SubnetId=$SUBNET_B1 SubnetId=$SUBNET_B2 \
  --query 'ResolverEndpoint.Id' --output text)

# Get the two inbound IPs
aws route53resolver list-resolver-endpoint-ip-addresses \
  --resolver-endpoint-id $IN_EP --query 'IpAddresses[].Ip'
```

Allow TCP/UDP 53 from `10.50.0.0/16` on `$SG_RESOLVER`, create a private hosted zone (e.g., `apps.internal`) associated with VPC-B, then on DC01:

```powershell
Add-DnsServerConditionalForwarderZone -Name "apps.internal" `
  -MasterServers <inbound-ip-1>, <inbound-ip-2>
Resolve-DnsName test.apps.internal    # resolves from the "on-prem" DC
```

You now have the full bidirectional hybrid DNS pattern in one account.

---

## Step 10: Teardown

```bash
# Instances
aws ec2 terminate-instances --instance-ids $DC_INSTANCE $MEMBER_INSTANCE

# Resolver (disassociate rule, delete rule, delete endpoints)
aws route53resolver disassociate-resolver-rule --vpc-id $VPC_B --resolver-rule-id $RULE_ID
aws route53resolver delete-resolver-rule --resolver-rule-id $RULE_ID
aws route53resolver delete-resolver-endpoint --resolver-endpoint-id $OUT_EP
# aws route53resolver delete-resolver-endpoint --resolver-endpoint-id $IN_EP   # if created

# Wait for instances/endpoints to fully delete, then:
aws ec2 delete-vpc-peering-connection --vpc-peering-connection-id $PEER_ID
# Delete SGs, subnets, detach+delete IGWs, then delete both VPCs
# (console cleanup is fastest for the leftovers)
```

---

## Extensions to Try

- **Transit Gateway** instead of peering, with Route 53 Resolver rules shared via **AWS RAM** — the multi-VPC enterprise pattern.
- **Second DC** in VPC-A plus **AD Sites and Services** (`Site: onprem`, `Site: aws`) to observe DC selection with `nltest /dsgetdc:corp.lab /force`.
- **SSM Automation** document for the domain join (swap RDP-driven joins for `AWS-RunPowerShellScript`).
- **AD Connector** pointed at DC01 to compare "seamless domain join" against manual joins — same lab topology works.
- **Query logging:** enable Route 53 Resolver query logs to CloudWa