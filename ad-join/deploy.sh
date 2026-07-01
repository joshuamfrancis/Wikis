#!/usr/bin/env bash
# ============================================================
# deploy-ad-lab.sh  (idempotent version)
# Two-VPC AD domain-join lab (single AWS account)
#   VPC-A (onprem-sim):   DC01 - self-hosted Domain Controller
#   VPC-B (aws-workload): MEMBER01 + Route 53 Resolver outbound
#
# Usage (gitbash / Ubuntu / any bash):
#   ./deploy-ad-lab.sh [path/to/variables.env]
#
# IDEMPOTENT: every resource is looked up first (by Name tag /
# project=ad-connect tag / natural key) and only created if it
# does not already exist. Safe to re-run after a partial failure.
# All resource IDs are saved to variables.env for decommission.
# ============================================================
set -euo pipefail
export MSYS_NO_PATHCONV=1

ENV_FILE="${1:-$(dirname "$0")/variables.env}"
[[ -f "$ENV_FILE" ]] || { echo "ERROR: env file not found: $ENV_FILE"; exit 1; }

# shellcheck source=/dev/null
source "$ENV_FILE"

TAGS_KV="Key=Lab,Value=ad-lab Key=project,Value=ad-connect"
TAGS_SPEC="{Key=Lab,Value=ad-lab},{Key=project,Value=ad-connect}"

log()  { echo -e "\n[$(date +%H:%M:%S)] $*"; }

# save KEY VALUE - upsert into env file (replace existing line or append)
save() {
  local key="$1" val="$2"
  if grep -qE "^export ${key}=" "$ENV_FILE"; then
    sed -i "s|^export ${key}=.*|export ${key}=${val}|" "$ENV_FILE"
  else
    echo "export ${key}=${val}" >> "$ENV_FILE"
  fi
  export "${key}=${val}"
}

# Returns "None" -> empty string helper
notnone() { [[ "$1" == "None" || -z "$1" ]] && echo "" || echo "$1"; }

# ------------------------------------------------------------
log "STEP 0: Key pair"
# ------------------------------------------------------------
if aws ec2 describe-key-pairs --key-names "$KEY_NAME" >/dev/null 2>&1; then
  log "EXISTS: key pair $KEY_NAME - reusing"
  # don't overwrite a previously recorded 'true'
  grep -qE '^export KEY_CREATED_BY_SCRIPT=true' "$ENV_FILE" || save KEY_CREATED_BY_SCRIPT false
else
  aws ec2 create-key-pair --key-name "$KEY_NAME" \
    --tag-specifications "ResourceType=key-pair,Tags=[$TAGS_SPEC]" \
    --query 'KeyMaterial' --output text > "$HOME/${KEY_NAME}.pem"
  chmod 400 "$HOME/${KEY_NAME}.pem"
  save KEY_CREATED_BY_SCRIPT true
  log "CREATED: key pair -> $HOME/${KEY_NAME}.pem"
fi

# ------------------------------------------------------------
log "STEP 1: VPCs, subnets, internet gateways, routes"
# ------------------------------------------------------------

# --- find_or_create_vpc <NameTag> <CIDR> -> vpc-id
find_or_create_vpc() {
  local name="$1" cidr="$2" id
  id=$(notnone "$(aws ec2 describe-vpcs \
    --filters "Name=tag:Name,Values=$name" "Name=cidr,Values=$cidr" "Name=state,Values=available" \
    --query 'Vpcs[0].VpcId' --output text)")
  if [[ -n "$id" ]]; then
    echo "EXISTS: VPC $name ($id)" >&2
  else
    id=$(aws ec2 create-vpc --cidr-block "$cidr" \
      --tag-specifications "ResourceType=vpc,Tags=[{Key=Name,Value=$name},$TAGS_SPEC]" \
      --query 'Vpc.VpcId' --output text)
    echo "CREATED: VPC $name ($id)" >&2
  fi
  echo "$id"
}

VPC_A=$(find_or_create_vpc "onprem-sim"   "$VPC_A_CIDR"); save VPC_A "$VPC_A"
VPC_B=$(find_or_create_vpc "aws-workload" "$VPC_B_CIDR"); save VPC_B "$VPC_B"

for V in "$VPC_A" "$VPC_B"; do
  aws ec2 modify-vpc-attribute --vpc-id "$V" --enable-dns-support
  aws ec2 modify-vpc-attribute --vpc-id "$V" --enable-dns-hostnames
done

# --- find_or_create_subnet <NameTag> <vpc-id> <CIDR> <AZ> -> subnet-id
find_or_create_subnet() {
  local name="$1" vpc="$2" cidr="$3" az="$4" id
  id=$(notnone "$(aws ec2 describe-subnets \
    --filters "Name=vpc-id,Values=$vpc" "Name=cidr-block,Values=$cidr" \
    --query 'Subnets[0].SubnetId' --output text)")
  if [[ -n "$id" ]]; then
    echo "EXISTS: subnet $name ($id)" >&2
  else
    id=$(aws ec2 create-subnet --vpc-id "$vpc" --cidr-block "$cidr" \
      --availability-zone "$az" \
      --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=$name},$TAGS_SPEC]" \
      --query 'Subnet.SubnetId' --output text)
    echo "CREATED: subnet $name ($id)" >&2
  fi
  echo "$id"
}

SUBNET_A=$(find_or_create_subnet  "onprem-dc-subnet"  "$VPC_A" "$SUBNET_A_CIDR"  "${AWS_REGION}a"); save SUBNET_A  "$SUBNET_A"
SUBNET_A2=$(find_or_create_subnet "onprem-subnet-2"   "$VPC_A" "$SUBNET_A2_CIDR" "${AWS_REGION}b"); save SUBNET_A2 "$SUBNET_A2"
SUBNET_B1=$(find_or_create_subnet "workload-subnet-1" "$VPC_B" "$SUBNET_B1_CIDR" "${AWS_REGION}a"); save SUBNET_B1 "$SUBNET_B1"
SUBNET_B2=$(find_or_create_subnet "workload-subnet-2" "$VPC_B" "$SUBNET_B2_CIDR" "${AWS_REGION}b"); save SUBNET_B2 "$SUBNET_B2"

# --- find_or_create_igw <vpc-id> -> igw-id (attached)
find_or_create_igw() {
  local vpc="$1" id
  id=$(notnone "$(aws ec2 describe-internet-gateways \
    --filters "Name=attachment.vpc-id,Values=$vpc" \
    --query 'InternetGateways[0].InternetGatewayId' --output text)")
  if [[ -n "$id" ]]; then
    echo "EXISTS: IGW attached to $vpc ($id)" >&2
  else
    id=$(aws ec2 create-internet-gateway \
      --tag-specifications "ResourceType=internet-gateway,Tags=[$TAGS_SPEC]" \
      --query 'InternetGateway.InternetGatewayId' --output text)
    aws ec2 attach-internet-gateway --internet-gateway-id "$id" --vpc-id "$vpc"
    echo "CREATED: IGW $id attached to $vpc" >&2
  fi
  echo "$id"
}

IGW_A=$(find_or_create_igw "$VPC_A"); save IGW_A "$IGW_A"
IGW_B=$(find_or_create_igw "$VPC_B"); save IGW_B "$IGW_B"

RT_A=$(aws ec2 describe-route-tables --filters "Name=vpc-id,Values=$VPC_A" \
  --query 'RouteTables[0].RouteTableId' --output text)
RT_B=$(aws ec2 describe-route-tables --filters "Name=vpc-id,Values=$VPC_B" \
  --query 'RouteTables[0].RouteTableId' --output text)
save RT_A "$RT_A"
save RT_B "$RT_B"

# Main route tables are created implicitly with the VPC - tag them (idempotent by nature)
aws ec2 create-tags --resources "$RT_A" "$RT_B" --tags $TAGS_KV

# --- ensure_route <rt-id> <dest-cidr> <gateway|pcx flag> <target-id>
ensure_route() {
  local rt="$1" dest="$2" kind="$3" target="$4" existing
  existing=$(notnone "$(aws ec2 describe-route-tables --route-table-ids "$rt" \
    --query "RouteTables[0].Routes[?DestinationCidrBlock=='$dest'] | [0].DestinationCidrBlock" \
    --output text)")
  if [[ -n "$existing" ]]; then
    echo "EXISTS: route $dest in $rt" >&2
  else
    if [[ "$kind" == "igw" ]]; then
      aws ec2 create-route --route-table-id "$rt" --destination-cidr-block "$dest" --gateway-id "$target" >/dev/null
    else
      aws ec2 create-route --route-table-id "$rt" --destination-cidr-block "$dest" --vpc-peering-connection-id "$target" >/dev/null
    fi
    echo "CREATED: route $dest -> $target in $rt" >&2
  fi
}

ensure_route "$RT_A" "0.0.0.0/0" igw "$IGW_A"
ensure_route "$RT_B" "0.0.0.0/0" igw "$IGW_B"

# ------------------------------------------------------------
log "STEP 2: VPC peering (simulated hybrid link)"
# ------------------------------------------------------------
PEER_ID=$(notnone "$(aws ec2 describe-vpc-peering-connections \
  --filters "Name=requester-vpc-info.vpc-id,Values=$VPC_B" \
            "Name=accepter-vpc-info.vpc-id,Values=$VPC_A" \
            "Name=status-code,Values=active,pending-acceptance,provisioning" \
  --query 'VpcPeeringConnections[0].VpcPeeringConnectionId' --output text)")

if [[ -n "$PEER_ID" ]]; then
  log "EXISTS: peering $PEER_ID"
else
  PEER_ID=$(aws ec2 create-vpc-peering-connection \
    --vpc-id "$VPC_B" --peer-vpc-id "$VPC_A" \
    --tag-specifications "ResourceType=vpc-peering-connection,Tags=[$TAGS_SPEC]" \
    --query 'VpcPeeringConnection.VpcPeeringConnectionId' --output text)
  log "CREATED: peering $PEER_ID"
fi
save PEER_ID "$PEER_ID"

# Accept if still pending (idempotent: accepting an active peering is a no-op error we tolerate)
PEER_STATUS=$(aws ec2 describe-vpc-peering-connections --vpc-peering-connection-ids "$PEER_ID" \
  --query 'VpcPeeringConnections[0].Status.Code' --output text)
if [[ "$PEER_STATUS" == "pending-acceptance" ]]; then
  aws ec2 accept-vpc-peering-connection --vpc-peering-connection-id "$PEER_ID" >/dev/null
  log "ACCEPTED: peering $PEER_ID"
fi

ensure_route "$RT_A" "$VPC_B_CIDR" pcx "$PEER_ID"
ensure_route "$RT_B" "$VPC_A_CIDR" pcx "$PEER_ID"

# ------------------------------------------------------------
log "STEP 3: Security groups"
# ------------------------------------------------------------
MY_IP="$(curl -s https://checkip.amazonaws.com)/32"
log "RDP will be allowed from: $MY_IP"

# --- find_or_create_sg <group-name> <vpc-id> <description> -> sg-id
find_or_create_sg() {
  local name="$1" vpc="$2" desc="$3" id
  id=$(notnone "$(aws ec2 describe-security-groups \
    --filters "Name=vpc-id,Values=$vpc" "Name=group-name,Values=$name" \
    --query 'SecurityGroups[0].GroupId' --output text)")
  if [[ -n "$id" ]]; then
    echo "EXISTS: SG $name ($id)" >&2
  else
    id=$(aws ec2 create-security-group --vpc-id "$vpc" \
      --group-name "$name" --description "$desc" \
      --tag-specifications "ResourceType=security-group,Tags=[$TAGS_SPEC]" \
      --query 'GroupId' --output text)
    echo "CREATED: SG $name ($id)" >&2
  fi
  echo "$id"
}

# --- ensure_ingress: tolerate InvalidPermission.Duplicate on re-runs
ensure_ingress() {
  local out
  if out=$(aws ec2 authorize-security-group-ingress "$@" 2>&1); then
    return 0
  elif echo "$out" | grep -q "InvalidPermission.Duplicate"; then
    return 0
  else
    echo "$out" >&2; return 1
  fi
}

SG_DC=$(find_or_create_sg dc-sg "$VPC_A" "Domain Controller SG"); save SG_DC "$SG_DC"

ensure_ingress --group-id "$SG_DC" --ip-permissions \
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
  "IpProtocol=icmp,FromPort=-1,ToPort=-1,IpRanges=[{CidrIp=$VPC_B_CIDR}]"

SG_MEMBER=$(find_or_create_sg member-sg "$VPC_B" "Member Server SG"); save SG_MEMBER "$SG_MEMBER"
ensure_ingress --group-id "$SG_MEMBER" --protocol tcp --port 3389 --cidr "$MY_IP"

SG_RESOLVER=$(find_or_create_sg resolver-out-sg "$VPC_B" "R53 Resolver outbound SG"); save SG_RESOLVER "$SG_RESOLVER"

if [[ "$CREATE_INBOUND_RESOLVER" == "true" ]]; then
  ensure_ingress --group-id "$SG_RESOLVER" --ip-permissions \
    "IpProtocol=tcp,FromPort=53,ToPort=53,IpRanges=[{CidrIp=$VPC_A_CIDR}]" \
    "IpProtocol=udp,FromPort=53,ToPort=53,IpRanges=[{CidrIp=$VPC_A_CIDR}]"
fi

# ------------------------------------------------------------
log "STEP 4: Launch DC01 (auto-promotes forest $DOMAIN_FQDN)"
# ------------------------------------------------------------
AMI_ID=$(aws ssm get-parameters \
  --names /aws/service/ami-windows-latest/Windows_Server-2022-English-Full-Base \
  --query 'Parameters[0].Value' --output text)
save AMI_ID "$AMI_ID"

# --- find_instance <NameTag> -> instance-id of pending/running instance with that name
find_instance() {
  notnone "$(aws ec2 describe-instances \
    --filters "Name=tag:Name,Values=$1" "Name=tag:project,Values=ad-connect" \
              "Name=instance-state-name,Values=pending,running,stopping,stopped" \
    --query 'Reservations[0].Instances[0].InstanceId' --output text)"
}

DC_INSTANCE=$(find_instance DC01)
if [[ -n "$DC_INSTANCE" ]]; then
  log "EXISTS: DC01 ($DC_INSTANCE) - skipping launch"
else
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
if (-not (Get-ADUser -Filter "SamAccountName -eq 'labuser'")) {
  New-ADUser -Name "labuser" -SamAccountName labuser -AccountPassword (ConvertTo-SecureString "$LAB_USER_PASSWORD" -AsPlainText -Force) -Enabled \$true
}
if (-not (Get-ADUser -Filter "SamAccountName -eq 'join-svc'")) {
  New-ADUser -Name "join-svc" -SamAccountName join-svc -AccountPassword (ConvertTo-SecureString "$JOIN_SVC_PASSWORD" -AsPlainText -Force) -Enabled \$true -PasswordNeverExpires \$true
}
if (-not (Get-ADOrganizationalUnit -Filter "Name -eq 'AWS-Servers'")) {
  New-ADOrganizationalUnit -Name "AWS-Servers" -Path "DC=corp,DC=lab"
}
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
    --tag-specifications \
      "ResourceType=instance,Tags=[{Key=Name,Value=DC01},$TAGS_SPEC]" \
      "ResourceType=volume,Tags=[{Key=Name,Value=DC01},$TAGS_SPEC]" \
      "ResourceType=network-interface,Tags=[$TAGS_SPEC]" \
    --query 'Instances[0].InstanceId' --output text)
  rm -f "$DC_USERDATA"
  log "CREATED: DC01 ($DC_INSTANCE)"
fi
save DC_INSTANCE "$DC_INSTANCE"

# ------------------------------------------------------------
log "STEP 5: Route 53 Resolver outbound endpoint + rule"
# ------------------------------------------------------------
OUT_EP=$(notnone "$(aws route53resolver list-resolver-endpoints \
  --filters Name=Name,Values=lab-outbound Name=Direction,Values=OUTBOUND \
  --query 'ResolverEndpoints[?Status!=`DELETING`] | [0].Id' --output text)")

if [[ -n "$OUT_EP" ]]; then
  log "EXISTS: outbound resolver endpoint ($OUT_EP)"
else
  OUT_EP=$(aws route53resolver create-resolver-endpoint \
    --name "lab-outbound" \
    --direction OUTBOUND \
    --creator-request-id "out-$(date +%s)" \
    --security-group-ids "$SG_RESOLVER" \
    --ip-addresses "SubnetId=$SUBNET_B1" "SubnetId=$SUBNET_B2" \
    --tags $TAGS_KV \
    --query 'ResolverEndpoint.Id' --output text)
  log "CREATED: outbound resolver endpoint ($OUT_EP)"
fi
save OUT_EP "$OUT_EP"

log "Waiting for outbound resolver endpoint to become OPERATIONAL..."
while true; do
  STATUS=$(aws route53resolver get-resolver-endpoint --resolver-endpoint-id "$OUT_EP" \
    --query 'ResolverEndpoint.Status' --output text)
  [[ "$STATUS" == "OPERATIONAL" ]] && break
  echo "  status: $STATUS ..."; sleep 20
done

RULE_ID=$(notnone "$(aws route53resolver list-resolver-rules \
  --filters Name=Name,Values=forward-corp-lab \
  --query 'ResolverRules[?Status==`COMPLETE`] | [0].Id' --output text)")

if [[ -n "$RULE_ID" ]]; then
  log "EXISTS: resolver rule forward-corp-lab ($RULE_ID)"
else
  RULE_ID=$(aws route53resolver create-resolver-rule \
    --name "forward-corp-lab" \
    --creator-request-id "rule-$(date +%s)" \
    --rule-type FORWARD \
    --domain-name "$DOMAIN_FQDN" \
    --resolver-endpoint-id "$OUT_EP" \
    --target-ips "Ip=$DC_IP,Port=53" \
    --tags $TAGS_KV \
    --query 'ResolverRule.Id' --output text)
  log "CREATED: resolver rule ($RULE_ID)"
fi
save RULE_ID "$RULE_ID"

# Associate rule with VPC-B only if not already associated
ASSOC=$(notnone "$(aws route53resolver list-resolver-rule-associations \
  --filters Name=ResolverRuleId,Values="$RULE_ID" Name=VPCId,Values="$VPC_B" \
  --query 'ResolverRuleAssociations[0].Id' --output text)")
if [[ -n "$ASSOC" ]]; then
  log "EXISTS: rule association with VPC-B ($ASSOC)"
else
  aws route53resolver associate-resolver-rule \
    --resolver-rule-id "$RULE_ID" --vpc-id "$VPC_B" --name "corp-lab-assoc" >/dev/null
  log "CREATED: rule association with VPC-B"
fi

# Optional inbound endpoint (reverse-direction demo)
if [[ "$CREATE_INBOUND_RESOLVER" == "true" ]]; then
  IN_EP=$(notnone "$(aws route53resolver list-resolver-endpoints \
    --filters Name=Name,Values=lab-inbound Name=Direction,Values=INBOUND \
    --query 'ResolverEndpoints[?Status!=`DELETING`] | [0].Id' --output text)")
  if [[ -n "$IN_EP" ]]; then
    log "EXISTS: inbound resolver endpoint ($IN_EP)"
  else
    IN_EP=$(aws route53resolver create-resolver-endpoint \
      --name "lab-inbound" \
      --direction INBOUND \
      --creator-request-id "in-$(date +%s)" \
      --security-group-ids "$SG_RESOLVER" \
      --ip-addresses "SubnetId=$SUBNET_B1" "SubnetId=$SUBNET_B2" \
      --tags $TAGS_KV \
      --query 'ResolverEndpoint.Id' --output text)
    log "CREATED: inbound resolver endpoint ($IN_EP)"
  fi
  save IN_EP "$IN_EP"
fi

# ------------------------------------------------------------
log "STEP 6: Launch MEMBER01"
# ------------------------------------------------------------
MEMBER_INSTANCE=$(find_instance MEMBER01)
if [[ -n "$MEMBER_INSTANCE" ]]; then
  log "EXISTS: MEMBER01 ($MEMBER_INSTANCE) - skipping launch"
else
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
    --tag-specifications \
      "ResourceType=instance,Tags=[{Key=Name,Value=MEMBER01},$TAGS_SPEC]" \
      "ResourceType=volume,Tags=[{Key=Name,Value=MEMBER01},$TAGS_SPEC]" \
      "ResourceType=network-interface,Tags=[$TAGS_SPEC]" \
    --query 'Instances[0].InstanceId' --output text)
  rm -f "$MEMBER_USERDATA"
  log "CREATED: MEMBER01 ($MEMBER_INSTANCE)"
fi
save MEMBER_INSTANCE "$MEMBER_INSTANCE"

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
 DEPLOYMENT COMPLETE (idempotent) - IDs saved to: $ENV_FILE
============================================================
 DC01      : $DC_INSTANCE  public: $DC_PUBLIC  private: $DC_IP
 MEMBER01  : $MEMBER_INSTANCE  public: $MEMBER_PUBLIC
 Domain    : $DOMAIN_FQDN  (allow ~10-15 min for AD promotion on first deploy)
 RDP login : Administrator / <LOCAL_ADMIN_PASSWORD from