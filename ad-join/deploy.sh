#!/usr/bin/env bash
# ============================================================
# deploy-ad-lab.sh
# Two-VPC AD domain-join lab (single AWS account)
#   VPC-A (onprem-sim):   DC01 - self-hosted Domain Controller
#   VPC-B (aws-workload): MEMBER01 + Route 53 Resolver outbound
#
# Usage (gitbash / Ubuntu / any bash):
#   ./deploy-ad-lab.sh [path/to/variables.env]
#
# All created resource IDs are appended to variables.env so
# decommission-ad-lab.sh can tear everything down later.
# ============================================================
set -euo pipefail

# gitbash: stop MSYS from rewriting arguments that look like paths
export MSYS_NO_PATHCONV=1

ENV_FILE="${1:-$(dirname "$0")/variables.env}"
[[ -f "$ENV_FILE" ]] || { echo "ERROR: env file not found: $ENV_FILE"; exit 1; }

# shellcheck source=/dev/null
source "$ENV_FILE"

# Refuse to deploy on top of an existing deployment
if grep -qE '^export VPC_A=' "$ENV_FILE"; then
  echo "ERROR: $ENV_FILE already contains deployed resource IDs."
  echo "Run decommission-ad-lab.sh first, or start from a clean variables.env."
  exit 1
fi

log()  { echo -e "\n[$(date +%H:%M:%S)] $*"; }
save() { echo "export $1=$2" >> "$ENV_FILE"; }   # persist ID for decommission

# ------------------------------------------------------------
log "STEP 0: Key pair"
# ------------------------------------------------------------
if ! aws ec2 describe-key-pairs --key-names "$KEY_NAME" >/dev/null 2>&1; then
  aws ec2 create-key-pair --key-name "$KEY_NAME" \
    --query 'KeyMaterial' --output text > "$HOME/${KEY_NAME}.pem"
  chmod 400 "$HOME/${KEY_NAME}.pem"
  save KEY_CREATED_BY_SCRIPT true
  log "Created key pair -> $HOME/${KEY_NAME}.pem"
else
  save KEY_CREATED_BY_SCRIPT false
  log "Key pair $KEY_NAME already exists - reusing"
fi

# ------------------------------------------------------------
log "STEP 1: VPCs, subnets, internet gateways, routes"
# ------------------------------------------------------------
VPC_A=$(aws ec2 create-vpc --cidr-block "$VPC_A_CIDR" \
  --tag-specifications 'ResourceType=vpc,Tags=[{Key=Name,Value=onprem-sim},{Key=Lab,Value=ad-lab}]' \
  --query 'Vpc.VpcId' --output text)
save VPC_A "$VPC_A"

VPC_B=$(aws ec2 create-vpc --cidr-block "$VPC_B_CIDR" \
  --tag-specifications 'ResourceType=vpc,Tags=[{Key=Name,Value=aws-workload},{Key=Lab,Value=ad-lab}]' \
  --query 'Vpc.VpcId' --output text)
save VPC_B "$VPC_B"

for V in "$VPC_A" "$VPC_B"; do
  aws ec2 modify-vpc-attribute --vpc-id "$V" --enable-dns-support
  aws ec2 modify-vpc-attribute --vpc-id "$V" --enable-dns-hostnames
done

SUBNET_A=$(aws ec2 create-subnet --vpc-id "$VPC_A" --cidr-block "$SUBNET_A_CIDR" \
  --availability-zone "${AWS_REGION}a" \
  --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=onprem-dc-subnet},{Key=Lab,Value=ad-lab}]' \
  --query 'Subnet.SubnetId' --output text)
save SUBNET_A "$SUBNET_A"

SUBNET_A2=$(aws ec2 create-subnet --vpc-id "$VPC_A" --cidr-block "$SUBNET_A2_CIDR" \
  --availability-zone "${AWS_REGION}b" \
  --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=onprem-subnet-2},{Key=Lab,Value=ad-lab}]' \
  --query 'Subnet.SubnetId' --output text)
save SUBNET_A2 "$SUBNET_A2"

SUBNET_B1=$(aws ec2 create-subnet --vpc-id "$VPC_B" --cidr-block "$SUBNET_B1_CIDR" \
  --availability-zone "${AWS_REGION}a" \
  --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=workload-subnet-1},{Key=Lab,Value=ad-lab}]' \
  --query 'Subnet.SubnetId' --output text)
save SUBNET_B1 "$SUBNET_B1"

SUBNET_B2=$(aws ec2 create-subnet --vpc-id "$VPC_B" --cidr-block "$SUBNET_B2_CIDR" \
  --availability-zone "${AWS_REGION}b" \
  --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=workload-subnet-2},{Key=Lab,Value=ad-lab}]' \
  --query 'Subnet.SubnetId' --output text)
save SUBNET_B2 "$SUBNET_B2"

# IGWs + default routes (public RDP access for the lab)
IGW_A=$(aws ec2 create-internet-gateway \
  --tag-specifications 'ResourceType=internet-gateway,Tags=[{Key=Lab,Value=ad-lab}]' \
  --query 'InternetGateway.InternetGatewayId' --output text)
aws ec2 attach-internet-gateway --internet-gateway-id "$IGW_A" --vpc-id "$VPC_A"
save IGW_A "$IGW_A"

IGW_B=$(aws ec2 create-internet-gateway \
  --tag-specifications 'ResourceType=internet-gateway,Tags=[{Key=Lab,Value=ad-lab}]' \
  --query 'InternetGateway.InternetGatewayId' --output text)
aws ec2 attach-internet-gateway --internet-gateway-id "$IGW_B" --vpc-id "$VPC_B"
save IGW_B "$IGW_B"

RT_A=$(aws ec2 describe-route-tables --filters "Name=vpc-id,Values=$VPC_A" \
  --query 'RouteTables[0].RouteTableId' --output text)
RT_B=$(aws ec2 describe-route-tables --filters "Name=vpc-id,Values=$VPC_B" \
  --query 'RouteTables[0].RouteTableId' --output text)
save RT_A "$RT_A"
save RT_B "$RT_B"

aws ec2 create-route --route-table-id "$RT_A" --destination-cidr-block 0.0.0.0/0 --gateway-id "$IGW_A" >/dev/null
aws ec2 create-route --route-table-id "$RT_B" --destination-cidr-block 0.0.0.0/0 --gateway-id "$IGW_B" >/dev/null

# ------------------------------------------------------------
log "STEP 2: VPC peering (simulated hybrid link)"
# ------------------------------------------------------------
PEER_ID=$(aws ec2 create-vpc-peering-connection \
  --vpc-id "$VPC_B" --peer-vpc-id "$VPC_A" \
  --tag-specifications 'ResourceType=vpc-peering-connection,Tags=[{Key=Lab,Value=ad-lab}]' \
  --query 'VpcPeeringConnection.VpcPeeringConnectionId' --output text)
save PEER_ID "$PEER_ID"

aws ec2 accept-vpc-peering-connection --vpc-peering-connection-id "$PEER_ID" >/dev/null
aws ec2 create-route --route-table-id "$RT_A" --destination-cidr-block "$VPC_B_CIDR" \
  --vpc-peering-connection-id "$PEER_ID" >/dev/null
aws ec2 create-route --route-table-id "$RT_B" --destination-cidr-block "$VPC_A_CIDR" \
  --vpc-peering-connection-id "$PEER_ID" >/dev/null

# ------------------------------------------------------------
log "STEP 3: Security groups"
# ------------------------------------------------------------
MY_IP="$(curl -s https://checkip.amazonaws.com)/32"
log "Allowing RDP from: $MY_IP"

SG_DC=$(aws ec2 create-security-group --vpc-id "$VPC_A" \
  --group-name dc-sg --description "Domain Controller SG" \
  --tag-specifications 'ResourceType=security-group,Tags=[{Key=Lab,Value=ad-lab}]' \
  --query 'GroupId' --output text)
save SG_DC "$SG_DC"

aws ec2 authorize-security-group-ingress --group-id "$SG_DC" --ip-permissions \
  "IpProtocol=tcp,FromPort=3389,ToPort=3389,IpRanges=[{CidrIp=$MY_IP}]" \
  "IpProtocol=tcp,FromPort=53,ToPort=53,IpRanges=[{CidrIp=$VPC_B_CIDR}]" \
  "IpProtocol=udp,FromPort=53,ToPort=53,IpRanges=[{CidrIp=$VPC_B_CIDR}]" \
  "IpProtocol=tcp,FromPort=88,ToPort=88,IpRanges=[{CidrIp=$VPC_B_CIDR}]" \
  "IpProtocol=udp,FromPort=88,ToPort=88,IpRanges=[{CidrIp=$VPC_B_CIDR}]" \
  "IpProtocol=udp,FromPort=123,ToPort=123,IpRanges=[{CidrIp=$VPC_B_CIDR}]" \
  "IpProtocol=tcp,FromPort=135,ToPort=135,IpRanges=[{CidrIp=$VPC_B_CIDR}]" \
  "IpProtocol=tcp,FromPort=389,ToPort=389,IpRanges=[{CidrIp=$VPC_B_CIDR}]" \
  "IpProtocol=udp,FromPort=389,ToPort=389,IpRanges=[{CidrIp=$VPC_B_CIDR}]" \
  "IpProtocol=tcp,FromPort=445,ToPort=445,IpRanges=[{CidrIp=$VPC_B_CIDR}]" \
  "IpProtocol=tcp,FromPort=464,ToPort=464,IpRanges=[{CidrIp=$VPC_B_CIDR}]" \
  "IpProtocol=udp,FromPort=464,ToPort=464,IpRanges=[{CidrIp=$VPC_B_CIDR}]" \
  "IpProtocol=tcp,FromPort=636,ToPort=636,IpRanges=[{CidrIp=$VPC_B_CIDR}]" \
  "IpProtocol=tcp,FromPort=3268,ToPort=3269,IpRanges=[{CidrIp=$VPC_B_CIDR}]" \
  "IpProtocol=tcp,FromPort=49152,ToPort=65535,IpRanges=[{CidrIp=$VPC_B_CIDR}]" \
  "IpProtocol=icmp,FromPort=-1,ToPort=-1,IpRanges=[{CidrIp=$VPC_B_CIDR}]" >/dev/null

SG_MEMBER=$(aws ec2 create-security-group --vpc-id "$VPC_B" \
  --group-name member-sg --description "Member Server SG" \
  --tag-specifications 'ResourceType=security-group,Tags=[{Key=Lab,Value=ad-lab}]' \
  --query 'GroupId' --output text)
save SG_MEMBER "$SG_MEMBER"

aws ec2 authorize-security-group-ingress --group-id "$SG_MEMBER" \
  --protocol tcp --port 3389 --cidr "$MY_IP" >/dev/null

SG_RESOLVER=$(aws ec2 create-security-group --vpc-id "$VPC_B" \
  --group-name resolver-out-sg --description "R53 Resolver outbound SG" \
  --tag-specifications 'ResourceType=security-group,Tags=[{Key=Lab,Value=ad-lab}]' \
  --query 'GroupId' --output text)
save SG_RESOLVER "$SG_RESOLVER"

# Inbound DNS from VPC-A only needed for the optional inbound endpoint
if [[ "$CREATE_INBOUND_RESOLVER" == "true" ]]; then
  aws ec2 authorize-security-group-ingress --group-id "$SG_RESOLVER" --ip-permissions \
    "IpProtocol=tcp,FromPort=53,ToPort=53,IpRanges=[{CidrIp=$VPC_A_CIDR}]" \
    "IpProtocol=udp,FromPort=53,ToPort=53,IpRanges=[{CidrIp=$VPC_A_CIDR}]" >/dev/null
fi

# ------------------------------------------------------------
log "STEP 4: Launch DC01 (auto-promotes forest $DOMAIN_FQDN)"
# ------------------------------------------------------------
AMI_ID=$(aws ssm get-parameters \
  --names /aws/service/ami-windows-latest/Windows_Server-2022-English-Full-Base \
  --query 'Parameters[0].Value' --output text)
save AMI_ID "$AMI_ID"

DC_USERDATA=$(mktemp)
cat > "$DC_USERDATA" << EOF
<powershell>
net user Administrator "$LOCAL_ADMIN_PASSWORD"
Install-WindowsFeature AD-Domain-Services -IncludeManagementTools
\$safeModePwd = ConvertTo-SecureString "$DSRM_PASSWORD" -AsPlainText -Force

# Post-reboot task: create lab users + OU once AD is up
\$post = @'
Start-Sleep -Seconds 120
Import-Module ActiveDirectory
New-ADUser -Name "labuser" -SamAccountName labuser -AccountPassword (ConvertTo-SecureString "$LAB_USER_PASSWORD" -AsPlainText -Force) -Enabled \$true
New-ADUser -Name "join-svc" -SamAccountName join-svc -AccountPassword (ConvertTo-SecureString "$JOIN_SVC_PASSWORD" -AsPlainText -Force) -Enabled \$true -PasswordNeverExpires \$true
New-ADOrganizationalUnit -Name "AWS-Servers" -Path "DC=corp,DC=lab"
Unregister-ScheduledTask -TaskName "ADLabPostSetup" -Confirm:\$false
'@
Set-Content -Path C:\\post-setup.ps1 -Value \$post
\$action  = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-ExecutionPolicy Bypass -File C:\\post-setup.ps1"
\$trigger = New-ScheduledTaskTrigger -AtStartup
Register-ScheduledTask -TaskName "ADLabPostSetup" -Action \$action -Trigger \$trigger -User "SYSTEM" -RunLevel Highest

Install-ADDSForest -DomainName "$DOMAIN_FQDN" -DomainNetbiosName "$DOMAIN_NETBIOS" \`
  -SafeModeAdministratorPassword \$safeModePwd -InstallDns -Force
</powershell>
EOF

DC_INSTANCE=$(aws ec2 run-instances \
  --image-id "$AMI_ID" --instance-type "$INSTANCE_TYPE" \
  --key-name "$KEY_NAME" \
  --subnet-id "$SUBNET_A" --private-ip-address "$DC_IP" \
  --security-group-ids "$SG_DC" \
  --associate-public-ip-address \
  --user-data "file://$DC_USERDATA" \
  --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=DC01},{Key=Lab,Value=ad-lab}]' \
  --query 'Instances[0].InstanceId' --output text)
save DC_INSTANCE "$DC_INSTANCE"
rm -f "$DC_USERDATA"

# ------------------------------------------------------------
log "STEP 5: Route 53 Resolver outbound endpoint + rule"
# ------------------------------------------------------------
OUT_EP=$(aws route53resolver create-resolver-endpoint \
  --name "lab-outbound" \
  --direction OUTBOUND \
  --creator-request-id "out-$(date +%s)" \
  --security-group-ids "$SG_RESOLVER" \
  --ip-addresses "SubnetId=$SUBNET_B1" "SubnetId=$SUBNET_B2" \
  --tags Key=Lab,Value=ad-lab \
  --query 'ResolverEndpoint.Id' --output text)
save OUT_EP "$OUT_EP"

log "Waiting for outbound resolver endpoint to become OPERATIONAL..."
while true; do
  STATUS=$(aws route53resolver get-resolver-endpoint --resolver-endpoint-id "$OUT_EP" \
    --query 'ResolverEndpoint.Status' --output text)
  [[ "$STATUS" == "OPERATIONAL" ]] && break
  echo "  status: $STATUS ..."; sleep 20
done

RULE_ID=$(aws route53resolver create-resolver-rule \
  --name "forward-corp-lab" \
  --creator-request-id "rule-$(date +%s)" \
  --rule-type FORWARD \
  --domain-name "$DOMAIN_FQDN" \
  --resolver-endpoint-id "$OUT_EP" \
  --target-ips "Ip=$DC_IP,Port=53" \
  --tags Key=Lab,Value=ad-lab \
  --query 'ResolverRule.Id' --output text)
save RULE_ID "$RULE_ID"

aws route53resolver associate-resolver-rule \
  --resolver-rule-id "$RULE_ID" --vpc-id "$VPC_B" --name "corp-lab-assoc" >/dev/null

# Optional inbound endpoint (reverse-direction demo)
if [[ "$CREATE_INBOUND_RESOLVER" == "true" ]]; then
  IN_EP=$(aws route53resolver create-resolver-endpoint \
    --name "lab-inbound" \
    --direction INBOUND \
    --creator-request-id "in-$(date +%s)" \
    --security-group-ids "$SG_RESOLVER" \
    --ip-addresses "SubnetId=$SUBNET_B1" "SubnetId=$SUBNET_B2" \
    --tags Key=Lab,Value=ad-lab \
    --query 'ResolverEndpoint.Id' --output text)
  save IN_EP "$IN_EP"
  log "Inbound endpoint created: $IN_EP (configure conditional forwarder on DC01 manually)"
fi

# ------------------------------------------------------------
log "STEP 6: Launch MEMBER01"
# ------------------------------------------------------------
MEMBER_USERDATA=$(mktemp)
cat > "$MEMBER_USERDATA" << EOF
<powershell>
net user Administrator "$LOCAL_ADMIN_PASSWORD"
Rename-Computer -NewName "MEMBER01" -Force -Restart
</powershell>
EOF

MEMBER_INSTANCE=$(aws ec2 run-instances \
  --image-id "$AMI_ID" --instance-type "$INSTANCE_TYPE" \
  --key-name "$KEY_NAME" \
  --subnet-id "$SUBNET_B1" \
  --security-group-ids "$SG_MEMBER" \
  --associate-public-ip-address \
  --user-data "file://$MEMBER_USERDATA" \
  --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=MEMBER01},{Key=Lab,Value=ad-lab}]' \
  --query 'Instances[0].InstanceId' --output text)
save MEMBER_INSTANCE "$MEMBER_INSTANCE"
rm -f "$MEMBER_USERDATA"

# ------------------------------------------------------------
log "STEP 7: Summary"
# ------------------------------------------------------------
aws ec2 wait instance-running --instance-ids "$DC_INSTANCE" "$MEMBER_INSTANCE"

DC_PUBLIC=$(aws ec2 describe-instances --instance-ids "$DC_INSTANCE" \
  --query 'Reservations[0].Instances[0].PublicIpAddress' --output text)
MEMBER_PUBLIC=$(aws ec2 describe-instances --instance-ids "$MEMBER_INSTANCE" \
  --query 'Reservations[0].Instances[0].PublicIpAddress' --output text)
save DC_PUBLIC_IP "$DC_PUBLIC"
save MEMBER_PUBLIC_IP "$MEMBER_PUBLIC"

cat << SUMMARY

============================================================
 DEPLOYMENT COMPLETE - resource IDs saved to: $ENV_FILE
============================================================
 DC01      : $DC_INSTANCE  public: $DC_PUBLIC  private: $DC_IP
 MEMBER01  : $MEMBER_INSTANCE  public: $MEMBER_PUBLIC
 Domain    : $DOMAIN_FQDN  (allow ~10-15 min for AD promotion)
 RDP login : Administrator / <LOCAL_ADMIN_PASSWORD from env file>

 Next steps (manual, on MEMBER01 after DC promotion finishes):
   Resolve-DnsName -Type SRV _ldap._tcp.dc._msdcs.$DOMAIN_FQDN
   Add-Computer -DomainName $DOMAIN_FQDN -OUPath "OU=AWS-Servers,DC=corp,DC=lab" -Credential CORP\\join-svc -Restart -Force

 Decommission later with:
   ./decommission-ad-lab.sh $ENV_FILE
============================================================
SUMMARY
