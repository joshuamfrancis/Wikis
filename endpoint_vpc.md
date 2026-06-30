# Centralized Interface Endpoints — Single-Account Simulation

Simulates a central **Endpoint VPC** (VPC-A) serving interface endpoints for
**Secrets Manager** and **S3** to a **spoke VPC** (VPC-B) over a Transit Gateway,
with **Route 53 private hosted zones** providing transparent cross-VPC resolution.

All commands are AWS CLI v2, written for **git-bash on Windows 11**. Run top to bottom.
Variables chain resource IDs between steps, so run within a single shell session.

> Cost warning: interface endpoints (~$0.01/AZ/hr each), TGW (~$0.05/hr) and TGW
> attachments bill hourly. Run the **Teardown** section when finished.

---

## 0. Prerequisites and variables

```bash
export REGION="ap-southeast-2"          # set your region
export AWS_PAGER=""                     # stop the CLI opening a pager

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# Pick the first two AZs in the region
read -r AZ1 AZ2 <<< "$(aws ec2 describe-availability-zones --region $REGION \
  --query 'AvailabilityZones[0:2].ZoneName' --output text)"
echo "Region=$REGION  AZs=$AZ1,$AZ2  Account=$ACCOUNT_ID"
```

---

## 1. Create the two VPCs, subnets and DNS attributes

DNS support + hostnames must be ON in **both** VPCs or PHZ resolution silently fails.

```bash
# --- VPC-A : Endpoint VPC (10.0.0.0/16) ---
VPC_A=$(aws ec2 create-vpc --cidr-block 10.0.0.0/16 --region $REGION \
  --tag-specifications 'ResourceType=vpc,Tags=[{Key=Name,Value=endpoint-vpc}]' \
  --query 'Vpc.VpcId' --output text)
aws ec2 modify-vpc-attribute --vpc-id $VPC_A --enable-dns-support  --region $REGION
aws ec2 modify-vpc-attribute --vpc-id $VPC_A --enable-dns-hostnames --region $REGION

# Two subnets (interface endpoints are per-AZ)
SUBNET_A1=$(aws ec2 create-subnet --vpc-id $VPC_A --cidr-block 10.0.1.0/24 \
  --availability-zone $AZ1 --region $REGION --query 'Subnet.SubnetId' --output text)
SUBNET_A2=$(aws ec2 create-subnet --vpc-id $VPC_A --cidr-block 10.0.2.0/24 \
  --availability-zone $AZ2 --region $REGION --query 'Subnet.SubnetId' --output text)

# --- VPC-B : Spoke VPC (10.1.0.0/16) ---
VPC_B=$(aws ec2 create-vpc --cidr-block 10.1.0.0/16 --region $REGION \
  --tag-specifications 'ResourceType=vpc,Tags=[{Key=Name,Value=spoke-vpc}]' \
  --query 'Vpc.VpcId' --output text)
aws ec2 modify-vpc-attribute --vpc-id $VPC_B --enable-dns-support  --region $REGION
aws ec2 modify-vpc-attribute --vpc-id $VPC_B --enable-dns-hostnames --region $REGION

SUBNET_B1=$(aws ec2 create-subnet --vpc-id $VPC_B --cidr-block 10.1.1.0/24 \
  --availability-zone $AZ1 --region $REGION --query 'Subnet.SubnetId' --output text)

echo "VPC_A=$VPC_A  VPC_B=$VPC_B"
```

---

## 2. Transit Gateway, attachments and explicit static routes

TGW is created with **default association ON, default propagation OFF** so the
static routes you add are what actually carry traffic (matching your target design).

```bash
TGW=$(aws ec2 create-transit-gateway --region $REGION \
  --description "sim-central-tgw" \
  --options DefaultRouteTableAssociation=enable,DefaultRouteTablePropagation=disable \
  --query 'TransitGateway.TransitGatewayId' --output text)

# Wait until the TGW is available (no built-in waiter)
until [ "$(aws ec2 describe-transit-gateways --transit-gateway-ids $TGW --region $REGION \
  --query 'TransitGateways[0].State' --output text)" = "available" ]; do
  echo "waiting for TGW..."; sleep 15; done

# Attachments (one subnet per VPC is fine for the sim)
ATT_A=$(aws ec2 create-transit-gateway-vpc-attachment --transit-gateway-id $TGW \
  --vpc-id $VPC_A --subnet-ids $SUBNET_A1 --region $REGION \
  --query 'TransitGatewayVpcAttachment.TransitGatewayAttachmentId' --output text)
ATT_B=$(aws ec2 create-transit-gateway-vpc-attachment --transit-gateway-id $TGW \
  --vpc-id $VPC_B --subnet-ids $SUBNET_B1 --region $REGION \
  --query 'TransitGatewayVpcAttachment.TransitGatewayAttachmentId' --output text)

for A in $ATT_A $ATT_B; do
  until [ "$(aws ec2 describe-transit-gateway-vpc-attachments \
    --transit-gateway-attachment-ids $A --region $REGION \
    --query 'TransitGatewayVpcAttachments[0].State' --output text)" = "available" ]; do
    echo "waiting for attachment $A..."; sleep 15; done
done

# Default TGW route table (attachments auto-associated to it)
TGW_RT=$(aws ec2 describe-transit-gateways --transit-gateway-ids $TGW --region $REGION \
  --query 'TransitGateways[0].Options.AssociationDefaultRouteTableId' --output text)

# Explicit static routes: traffic to each VPC CIDR -> that VPC's attachment
aws ec2 create-transit-gateway-route --transit-gateway-route-table-id $TGW_RT \
  --destination-cidr-block 10.0.0.0/16 --transit-gateway-attachment-id $ATT_A --region $REGION
aws ec2 create-transit-gateway-route --transit-gateway-route-table-id $TGW_RT \
  --destination-cidr-block 10.1.0.0/16 --transit-gateway-attachment-id $ATT_B --region $REGION
```

---

## 3. VPC route tables (forward path AND return path)

The return route in VPC-A is the step people forget — without it you get
one-way black-holing that looks like a DNS bug.

```bash
RT_A=$(aws ec2 describe-route-tables --region $REGION \
  --filters Name=vpc-id,Values=$VPC_A Name=association.main,Values=true \
  --query 'RouteTables[0].RouteTableId' --output text)
RT_B=$(aws ec2 describe-route-tables --region $REGION \
  --filters Name=vpc-id,Values=$VPC_B Name=association.main,Values=true \
  --query 'RouteTables[0].RouteTableId' --output text)

# Spoke -> endpoints (forward)
aws ec2 create-route --route-table-id $RT_B --destination-cidr-block 10.0.0.0/16 \
  --transit-gateway-id $TGW --region $REGION
# Endpoints -> spoke (return)
aws ec2 create-route --route-table-id $RT_A --destination-cidr-block 10.1.0.0/16 \
  --transit-gateway-id $TGW --region $REGION
```

---

## 4. Security group for the endpoints

Interface endpoints preserve the caller's source IP, so 443 must be allowed from
the spoke CIDR. `10.0.0.0/8` covers both VPCs in this sim.

```bash
EP_SG=$(aws ec2 create-security-group --group-name endpoint-sg \
  --description "Allow 443 to interface endpoints" --vpc-id $VPC_A --region $REGION \
  --query 'GroupId' --output text)
aws ec2 authorize-security-group-ingress --group-id $EP_SG \
  --protocol tcp --port 443 --cidr 10.0.0.0/8 --region $REGION
```

---

## 5. Create the interface endpoints (private DNS DISABLED)

Private DNS is left **off** so Route 53 PHZs are the single source of truth across
both VPCs. (If you left it on, the override would only apply inside VPC-A.)

```bash
SM_EP=$(aws ec2 create-vpc-endpoint --vpc-id $VPC_A --region $REGION \
  --vpc-endpoint-type Interface \
  --service-name com.amazonaws.$REGION.secretsmanager \
  --subnet-ids $SUBNET_A1 $SUBNET_A2 --security-group-ids $EP_SG \
  --no-private-dns-enabled \
  --query 'VpcEndpoint.VpcEndpointId' --output text)

S3_EP=$(aws ec2 create-vpc-endpoint --vpc-id $VPC_A --region $REGION \
  --vpc-endpoint-type Interface \
  --service-name com.amazonaws.$REGION.s3 \
  --subnet-ids $SUBNET_A1 $SUBNET_A2 --security-group-ids $EP_SG \
  --no-private-dns-enabled \
  --query 'VpcEndpoint.VpcEndpointId' --output text)

# Wait until both endpoints are available
for E in $SM_EP $S3_EP; do
  until [ "$(aws ec2 describe-vpc-endpoints --vpc-endpoint-ids $E --region $REGION \
    --query 'VpcEndpoints[0].State' --output text)" = "available" ]; do
    echo "waiting for endpoint $E..."; sleep 15; done
done
```

---

## 6. Capture each endpoint's regional DNS name

`DnsEntries[0]` is the **regional** record (no AZ) — the correct alias target.
Entries `[1..]` are zonal and should not be used here.

```bash
SM_DNS=$(aws ec2 describe-vpc-endpoints --vpc-endpoint-ids $SM_EP --region $REGION \
  --query 'VpcEndpoints[0].DnsEntries[0].DnsName' --output text)
SM_HZ=$(aws ec2 describe-vpc-endpoints --vpc-endpoint-ids $SM_EP --region $REGION \
  --query 'VpcEndpoints[0].DnsEntries[0].HostedZoneId' --output text)

S3_DNS=$(aws ec2 describe-vpc-endpoints --vpc-endpoint-ids $S3_EP --region $REGION \
  --query 'VpcEndpoints[0].DnsEntries[0].DnsName' --output text)
S3_HZ=$(aws ec2 describe-vpc-endpoints --vpc-endpoint-ids $S3_EP --region $REGION \
  --query 'VpcEndpoints[0].DnsEntries[0].HostedZoneId' --output text)

echo "SM_DNS=$SM_DNS"; echo "S3_DNS=$S3_DNS"
```

---

## 7. Private hosted zones + alias records, associated with BOTH VPCs

### 7a. Secrets Manager PHZ (apex record only)

```bash
SM_PHZ=$(aws route53 create-hosted-zone \
  --name "secretsmanager.$REGION.amazonaws.com" \
  --caller-reference "sm-$(date +%s)" \
  --hosted-zone-config Comment="sim secretsmanager",PrivateZone=true \
  --vpc VPCRegion=$REGION,VPCId=$VPC_A \
  --query 'HostedZone.Id' --output text)
SM_PHZ=${SM_PHZ#/hostedzone/}

aws route53 associate-vpc-with-hosted-zone --hosted-zone-id $SM_PHZ \
  --vpc VPCRegion=$REGION,VPCId=$VPC_B

cat > sm-record.json <<EOF
{ "Changes": [ {
  "Action": "CREATE",
  "ResourceRecordSet": {
    "Name": "secretsmanager.$REGION.amazonaws.com",
    "Type": "A",
    "AliasTarget": { "DNSName": "$SM_DNS", "HostedZoneId": "$SM_HZ", "EvaluateTargetHealth": false }
  } } ] }
EOF
aws route53 change-resource-record-sets --hosted-zone-id $SM_PHZ --change-batch file://sm-record.json
```

### 7b. S3 PHZ (apex for path-style + wildcard for virtual-hosted buckets)

```bash
S3_PHZ=$(aws route53 create-hosted-zone \
  --name "s3.$REGION.amazonaws.com" \
  --caller-reference "s3-$(date +%s)" \
  --hosted-zone-config Comment="sim s3",PrivateZone=true \
  --vpc VPCRegion=$REGION,VPCId=$VPC_A \
  --query 'HostedZone.Id' --output text)
S3_PHZ=${S3_PHZ#/hostedzone/}

aws route53 associate-vpc-with-hosted-zone --hosted-zone-id $S3_PHZ \
  --vpc VPCRegion=$REGION,VPCId=$VPC_B

cat > s3-record.json <<EOF
{ "Changes": [
  { "Action": "CREATE",
    "ResourceRecordSet": {
      "Name": "s3.$REGION.amazonaws.com",
      "Type": "A",
      "AliasTarget": { "DNSName": "$S3_DNS", "HostedZoneId": "$S3_HZ", "EvaluateTargetHealth": false }
  } },
  { "Action": "CREATE",
    "ResourceRecordSet": {
      "Name": "*.s3.$REGION.amazonaws.com",
      "Type": "A",
      "AliasTarget": { "DNSName": "$S3_DNS", "HostedZoneId": "$S3_HZ", "EvaluateTargetHealth": false }
  } }
] }
EOF
aws route53 change-resource-record-sets --hosted-zone-id $S3_PHZ --change-batch file://s3-record.json
```

---

## 8. Create test resources (a secret and a bucket)

```bash
aws secretsmanager create-secret --name sim/test \
  --secret-string '{"hello":"world"}' --region $REGION

BUCKET="sim-endpoint-test-${ACCOUNT_ID}-$(date +%s)"
aws s3api create-bucket --bucket $BUCKET --region $REGION \
  --create-bucket-configuration LocationConstraint=$REGION
echo "hello from the endpoint" > sample.txt
aws s3 cp sample.txt s3://$BUCKET/sample.txt --region $REGION
echo "BUCKET=$BUCKET"
```

---

## 9. (Optional) Test host in the spoke VPC

Adds an IGW so the instance can join SSM, then verifies resolution. Internet
presence does **not** bypass the endpoints — the PHZ points the service names at
the private interface ENIs, which you confirm with `nslookup` returning `10.0.x.x`.

```bash
# IGW + public routing for VPC-B
IGW=$(aws ec2 create-internet-gateway --region $REGION --query 'InternetGateway.InternetGatewayId' --output text)
aws ec2 attach-internet-gateway --internet-gateway-id $IGW --vpc-id $VPC_B --region $REGION
aws ec2 create-route --route-table-id $RT_B --destination-cidr-block 0.0.0.0/0 \
  --gateway-id $IGW --region $REGION
aws ec2 modify-subnet-attribute --subnet-id $SUBNET_B1 --map-public-ip-on-launch --region $REGION

# SSM instance profile
aws iam create-role --role-name sim-ssm-role --assume-role-policy-document '{
  "Version":"2012-10-17","Statement":[{"Effect":"Allow",
  "Principal":{"Service":"ec2.amazonaws.com"},"Action":"sts:AssumeRole"}]}'
aws iam attach-role-policy --role-name sim-ssm-role --policy-arn arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore
aws iam attach-role-policy --role-name sim-ssm-role --policy-arn arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess
aws iam put-role-policy --role-name sim-ssm-role --policy-name sm-read \
  --policy-document '{"Version":"2012-10-17","Statement":[{"Effect":"Allow",
  "Action":"secretsmanager:GetSecretValue","Resource":"*"}]}'
aws iam create-instance-profile --instance-profile-name sim-ssm-profile
aws iam add-role-to-instance-profile --instance-profile-name sim-ssm-profile --role-name sim-ssm-role
sleep 15  # let the instance profile propagate

# Launch Amazon Linux 2023
AMI=$(aws ssm get-parameter --region $REGION \
  --name /aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64 \
  --query 'Parameter.Value' --output text)
INSTANCE=$(aws ec2 run-instances --image-id $AMI --instance-type t3.micro \
  --subnet-id $SUBNET_B1 --iam-instance-profile Name=sim-ssm-profile \
  --region $REGION --query 'Instances[0].InstanceId' --output text)
echo "INSTANCE=$INSTANCE  BUCKET=$BUCKET  REGION=$REGION"
```

Once the instance shows under `aws ssm describe-instance-information`, connect and verify:

```bash
aws ssm start-session --target $INSTANCE --region $REGION
```

Inside the session (substitute your REGION and BUCKET values):

```bash
nslookup secretsmanager.<REGION>.amazonaws.com          # expect 10.0.x.x
aws secretsmanager get-secret-value --secret-id sim/test --region <REGION>

nslookup <BUCKET>.s3.<REGION>.amazonaws.com             # expect 10.0.x.x
aws s3 ls s3://<BUCKET> --region <REGION>
aws s3 cp s3://<BUCKET>/sample.txt - --region <REGION>
```

Private IPs in the `nslookup` output prove traffic is taking the endpoint path
across the TGW rather than the public service endpoint.

---

## 10. Teardown (run to stop charges)

```bash
aws ec2 terminate-instances --instance-ids $INSTANCE --region $REGION
aws ec2 wait instance-terminated --instance-ids $INSTANCE --region $REGION
aws iam remove-role-from-instance-profile --instance-profile-name sim-ssm-profile --role-name sim-ssm-role
aws iam delete-instance-profile --instance-profile-name sim-ssm-profile
aws iam delete-role-policy --role-name sim-ssm-role --policy-name sm-read
aws iam detach-role-policy --role-name sim-ssm-role --policy-arn arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess
aws iam detach-role-policy --role-name sim-ssm-role --policy-arn arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore
aws iam delete-role --role-name sim-ssm-role

aws ec2 delete-vpc-endpoints --vpc-endpoint-ids $SM_EP $S3_EP --region $REGION
aws route53 delete-hosted-zone --id $SM_PHZ
aws route53 delete-hosted-zone --id $S3_PHZ   # delete records first if API complains

aws ec2 delete-transit-gateway-vpc-attachment --transit-gateway-attachment-id $ATT_A --region $REGION
aws ec2 delete-transit-gateway-vpc-attachment --transit-gateway-attachment-id $ATT_B --region $REGION
# wait for attachments to delete, then:
aws ec2 delete-transit-gateway --transit-gateway-id $TGW --region $REGION

aws s3 rb s3://$BUCKET --force --region $REGION
aws secretsmanager delete-secret --secret-id sim/test --force-delete-without-recovery --region $REGION
aws ec2 detach-internet-gateway --internet-gateway-id $IGW --vpc-id $VPC_B --region $REGION
aws ec2 delete-internet-gateway --internet-gateway-id $IGW --region $REGION
# finally delete subnets, then the two VPCs
```

---

## Notes

- **S3 is the special case.** The S3 interface endpoint here works for cross-VPC
  use *because* private DNS is off and the PHZ wildcard handles bucket subdomains.
  If a spoke also had an **S3 gateway endpoint**, its route-table entry would win
  over the PHZ — keep that in mind when you move to the real multi-account build.
- **Cheaper alternative for a pure sim:** swap the Transit Gateway for VPC peering
  (`create-vpc-peering-connection` + a route in each table). The endpoint and PHZ
  steps are identical; only Sections 2–3 change. TGW is used here to reproduce the
  explicit-static-route behaviour of your target design.
- **Real multi-account version:** the only differences are cross-account PHZ
  association (`create-vpc-association-authorization` in the zone's account, then
  `associate-vpc-with-hosted-zone` from the spoke account) and a customer-managed
  prefix list referencing the Endpoint VPC CIDR(s) in place of hardcoded routes.
