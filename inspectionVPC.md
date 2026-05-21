## Central Inspection VPC pattern

# Central ingress/egress — network reference

Single-account pattern: one **inspection VPC** (internet edge) and one **workload VPC**
(no internet edge), joined by a **Transit Gateway**. All north-south traffic from the
workload VPC is forced through the inspection VPC. Network Firewall is **not** provisioned
yet — workload egress routes straight to NAT. Spans two AZs.

---

## Topology

```
                              ( Internet )
                                   |
                                   v
+========================================================================+
|  INSPECTION VPC                                          10.0.0.0/16   |
|                                                                        |
|   +-------------------------------+   +----------------------------+   |
|   |  Public subnets               |   |  TGW attachment subnets    |   |
|   |  10.0.0.0/24  (az-a)          |   |  10.0.250.0/28  (az-a)     |   |
|   |  10.0.1.0/24  (az-b)          |   |  10.0.251.0/28  (az-b)     |   |
|   |                               |   |                            |   |
|   |   [ IGW ]  [ NAT-a / NAT-b ]  |<--|   [ TGW attach ENIs ]      |   |
|   |   [ ALB ]                     |   |                            |   |
|   +-------------------------------+   +-------------+--------------+   |
|                                                     |                  |
+=====================================================|==================+
                                                      |
                                            [ TRANSIT GATEWAY ]
                                              ASN 64512
                                                      |
+=====================================================|==================+
|  WORKLOAD VPC  (no IGW, no NAT)                      |   10.1.0.0/16   |
|                                                      |                 |
|   +----------------------------+   +----------------+-------------+    |
|   |  TGW attachment subnets    |   |  App subnets                 |    |
|   |  10.1.250.0/28  (az-a)     |   |  10.1.1.0/24  (az-a)         |    |
|   |  10.1.251.0/28  (az-b)     |-->|  10.1.2.0/24  (az-b)         |    |
|   |                            |   |   [ EC2 / ECS / Lambda ]     |    |
|   |   [ TGW attach ENIs ]      |   +--------------+---------------+    |
|   +----------------------------+                  |                    |
|                                                   | local              |
|                                    +--------------v---------------+    |
|                                    |  DB subnets (no egress)      |    |
|                                    |  10.1.11.0/24  (az-a)        |    |
|                                    |  10.1.12.0/24  (az-b)        |    |
|                                    |   [ RDS ]                    |    |
|                                    +------------------------------+    |
+========================================================================+
```

---

## Traffic flows

```
EGRESS  (app instance reaching the internet)

  app subnet
     |  0.0.0.0/0 -> tgw
     v
  workload TGW subnet ---> [ TGW ] ---> inspection TGW subnet
                                              |  0.0.0.0/0 -> nat
                                              v
                                          NAT gateway --> IGW --> Internet
  (return traffic reverses the path)


INGRESS  (internet reaching the app via ALB)

  Internet --> IGW --> ALB (public subnet)
                         |  targets registered as IPs in workload VPC
                         v
                   [ TGW ] ---> workload app subnet


APP -> DB  (stays inside the workload VPC)

  app subnet ---- local (10.1.0.0/16) ----> db subnet
  (never touches the TGW or the internet)
```

---

## CIDR allocation

### Inspection VPC — `10.0.0.0/16`

| Subnet            | AZ   | CIDR            | Purpose                       |
|-------------------|------|-----------------|-------------------------------|
| Public subnet A   | az-a | `10.0.0.0/24`   | NAT GW, IGW, ALB              |
| Public subnet B   | az-b | `10.0.1.0/24`   | NAT GW, IGW, ALB              |
| TGW subnet A      | az-a | `10.0.250.0/28` | TGW attachment ENI            |
| TGW subnet B      | az-b | `10.0.251.0/28` | TGW attachment ENI            |
| _(reserved)_      | az-a | `10.0.10.0/28`  | future firewall subnet        |
| _(reserved)_      | az-b | `10.0.11.0/28`  | future firewall subnet        |

### Workload VPC — `10.1.0.0/16` (no IGW, no NAT)

| Subnet            | AZ   | CIDR            | Purpose                       |
|-------------------|------|-----------------|-------------------------------|
| App subnet A      | az-a | `10.1.1.0/24`   | EC2 / ECS / Lambda            |
| App subnet B      | az-b | `10.1.2.0/24`   | EC2 / ECS / Lambda            |
| DB subnet A       | az-a | `10.1.11.0/24`  | RDS (subnet group member)     |
| DB subnet B       | az-b | `10.1.12.0/24`  | RDS (subnet group member)     |
| TGW subnet A      | az-a | `10.1.250.0/28` | TGW attachment ENI            |
| TGW subnet B      | az-b | `10.1.251.0/28` | TGW attachment ENI            |

---

## VPC route tables

### Inspection VPC

**Public subnet RT** (shared by both public subnets)

| Destination     | Target      |
|-----------------|-------------|
| `10.0.0.0/16`   | `local`     |
| `10.1.0.0/16`   | `tgw-xxxx`  |
| `0.0.0.0/0`     | `igw-xxxx`  |

**TGW subnet RT** (one per AZ — AZ-scoped to the same-AZ NAT)

| Destination     | Target              |
|-----------------|---------------------|
| `10.0.0.0/16`   | `local`             |
| `0.0.0.0/0`     | `nat-xxxx` (same AZ)|

> When Network Firewall is added, this `0.0.0.0/0` target changes from the
> NAT gateway to the same-AZ firewall endpoint. Nothing else moves.

### Workload VPC

**App subnet RT**

| Destination     | Target      |
|-----------------|-------------|
| `10.1.0.0/16`   | `local`     |
| `0.0.0.0/0`     | `tgw-xxxx`  |

**DB subnet RT** (no default route — local only)

| Destination     | Target      |
|-----------------|-------------|
| `10.1.0.0/16`   | `local`     |

**TGW subnet RT**

| Destination     | Target      |
|-----------------|-------------|
| `10.1.0.0/16`   | `local`     |
| `0.0.0.0/0`     | `tgw-xxxx`  |

---

## Transit Gateway route tables

**Workload TGW RT** (associated with the workload VPC attachment)

| Destination     | Target attachment        |
|-----------------|--------------------------|
| `10.0.0.0/16`   | inspection-VPC attachment|
| `0.0.0.0/0`     | inspection-VPC attachment|

**Inspection TGW RT** (associated with the inspection VPC attachment)

| Destination     | Target attachment        |
|-----------------|--------------------------|
| `10.1.0.0/16`   | workload-VPC attachment  |

> No `0.0.0.0/0` in the inspection TGW table — the workload VPC is unreachable
> except for established return flows.

---

## Build notes

- **Appliance mode** is enabled on the inspection VPC's TGW attachment from the
  start. Harmless with NAT-only routing; required for stateful inspection once
  the firewall is added. Enabling it later means re-learning AZ affinity, so set
  it now.
- **AZ-scoped** TGW/firewall route tables: the az-a TGW subnet routes to the az-a
  NAT (and later the az-a firewall endpoint), az-b to az-b. Mixing AZs creates
  asymmetric paths that break stateful inspection.
- **RDS subnet group** needs two subnets in different AZs — that's why there are
  two DB subnets even if only one is active. Both share the no-egress RT.
- **Two NAT gateways** (~USD 65/month in ap-southeast-2 before traffic). For a
  test environment, collapse to one NAT and point both inspection TGW route
  tables at it.

---

## Validating the data plane

1. Launch a test EC2 instance into an app subnet with the SSM managed-instance
   role attached (no bastion needed).
2. Open a Session Manager shell.
3. Run `curl https://checkip.amazonaws.com` — it should return one of the NAT
   Elastic IPs, confirming the full path:
   `app -> TGW -> inspection TGW subnet -> NAT -> IGW`.
4. Test the app -> DB path with a connection to RDS on its port; this stays
   inside the workload VPC via the `local` route.

---

## Adding Network Firewall later (the delta)

1. Create firewall subnets `10.0.10.0/28` (az-a) and `10.0.11.0/28` (az-b).
2. Add a firewall subnet RT per AZ: `0.0.0.0/0 -> same-AZ NAT`.
3. Repoint each inspection TGW subnet RT `0.0.0.0/0` from the NAT gateway to the
   same-AZ firewall VPC endpoint.

Resulting egress path becomes:
`app -> TGW -> inspection TGW subnet -> firewall endpoint -> NAT -> IGW`.


```yaml
AWSTemplateFormatVersion: "2010-09-09"
Description: >
  Centralized ingress/egress pattern in a single account. One inspection VPC
  (public subnets with IGW + NAT, plus TGW attachment subnets) and one workload
  VPC (app + db subnets, plus TGW attachment subnets, no IGW/NAT). A Transit
  Gateway joins them with static TGW route tables. Network Firewall is NOT
  provisioned yet -- workload egress routes straight to NAT. Adding the firewall
  later is a route-table change only (see Outputs / comments).

# ---------------------------------------------------------------------------
# Parameters
# ---------------------------------------------------------------------------
Parameters:
  AzA:
    Type: AWS::EC2::AvailabilityZone::Name
    Description: First Availability Zone (e.g. ap-southeast-2a).
  AzB:
    Type: AWS::EC2::AvailabilityZone::Name
    Description: Second Availability Zone (e.g. ap-southeast-2b).

  InspectionVpcCidr:
    Type: String
    Default: 10.0.0.0/16
  WorkloadVpcCidr:
    Type: String
    Default: 10.1.0.0/16

  # Inspection VPC subnets
  InspectionPublicSubnetACidr:
    Type: String
    Default: 10.0.0.0/24
  InspectionPublicSubnetBCidr:
    Type: String
    Default: 10.0.1.0/24
  InspectionTgwSubnetACidr:
    Type: String
    Default: 10.0.250.0/28
  InspectionTgwSubnetBCidr:
    Type: String
    Default: 10.0.251.0/28

  # Workload VPC subnets
  WorkloadAppSubnetACidr:
    Type: String
    Default: 10.1.1.0/24
  WorkloadAppSubnetBCidr:
    Type: String
    Default: 10.1.2.0/24
  WorkloadDbSubnetACidr:
    Type: String
    Default: 10.1.11.0/24
  WorkloadDbSubnetBCidr:
    Type: String
    Default: 10.1.12.0/24
  WorkloadTgwSubnetACidr:
    Type: String
    Default: 10.1.250.0/28
  WorkloadTgwSubnetBCidr:
    Type: String
    Default: 10.1.251.0/28

Resources:

  # =========================================================================
  # INSPECTION VPC
  # =========================================================================
  InspectionVpc:
    Type: AWS::EC2::VPC
    Properties:
      CidrBlock: !Ref InspectionVpcCidr
      EnableDnsSupport: true
      EnableDnsHostnames: true
      Tags:
        - { Key: Name, Value: inspection-vpc }

  InternetGateway:
    Type: AWS::EC2::InternetGateway
    Properties:
      Tags:
        - { Key: Name, Value: inspection-igw }

  IgwAttachment:
    Type: AWS::EC2::VPCGatewayAttachment
    Properties:
      VpcId: !Ref InspectionVpc
      InternetGatewayId: !Ref InternetGateway

  # ---- Public subnets ----
  InspectionPublicSubnetA:
    Type: AWS::EC2::Subnet
    Properties:
      VpcId: !Ref InspectionVpc
      CidrBlock: !Ref InspectionPublicSubnetACidr
      AvailabilityZone: !Ref AzA
      MapPublicIpOnLaunch: true
      Tags:
        - { Key: Name, Value: inspection-public-a }

  InspectionPublicSubnetB:
    Type: AWS::EC2::Subnet
    Properties:
      VpcId: !Ref InspectionVpc
      CidrBlock: !Ref InspectionPublicSubnetBCidr
      AvailabilityZone: !Ref AzB
      MapPublicIpOnLaunch: true
      Tags:
        - { Key: Name, Value: inspection-public-b }

  # ---- TGW attachment subnets ----
  InspectionTgwSubnetA:
    Type: AWS::EC2::Subnet
    Properties:
      VpcId: !Ref InspectionVpc
      CidrBlock: !Ref InspectionTgwSubnetACidr
      AvailabilityZone: !Ref AzA
      Tags:
        - { Key: Name, Value: inspection-tgw-a }

  InspectionTgwSubnetB:
    Type: AWS::EC2::Subnet
    Properties:
      VpcId: !Ref InspectionVpc
      CidrBlock: !Ref InspectionTgwSubnetBCidr
      AvailabilityZone: !Ref AzB
      Tags:
        - { Key: Name, Value: inspection-tgw-b }

  # ---- NAT gateways (one per AZ) ----
  NatEipA:
    Type: AWS::EC2::EIP
    DependsOn: IgwAttachment
    Properties:
      Domain: vpc
      Tags:
        - { Key: Name, Value: inspection-nat-eip-a }

  NatEipB:
    Type: AWS::EC2::EIP
    DependsOn: IgwAttachment
    Properties:
      Domain: vpc
      Tags:
        - { Key: Name, Value: inspection-nat-eip-b }

  NatGatewayA:
    Type: AWS::EC2::NatGateway
    Properties:
      AllocationId: !GetAtt NatEipA.AllocationId
      SubnetId: !Ref InspectionPublicSubnetA
      Tags:
        - { Key: Name, Value: inspection-nat-a }

  NatGatewayB:
    Type: AWS::EC2::NatGateway
    Properties:
      AllocationId: !GetAtt NatEipB.AllocationId
      SubnetId: !Ref InspectionPublicSubnetB
      Tags:
        - { Key: Name, Value: inspection-nat-b }

  # ---- Public route table (shared by both public subnets) ----
  InspectionPublicRt:
    Type: AWS::EC2::RouteTable
    Properties:
      VpcId: !Ref InspectionVpc
      Tags:
        - { Key: Name, Value: inspection-public-rt }

  InspectionPublicDefaultRoute:
    Type: AWS::EC2::Route
    DependsOn: IgwAttachment
    Properties:
      RouteTableId: !Ref InspectionPublicRt
      DestinationCidrBlock: 0.0.0.0/0
      GatewayId: !Ref InternetGateway

  # Return traffic to the workload VPC goes back via the TGW
  InspectionPublicToWorkloadRoute:
    Type: AWS::EC2::Route
    DependsOn: TgwInspectionAttachment
    Properties:
      RouteTableId: !Ref InspectionPublicRt
      DestinationCidrBlock: !Ref WorkloadVpcCidr
      TransitGatewayId: !Ref TransitGateway

  InspectionPublicAssocA:
    Type: AWS::EC2::SubnetRouteTableAssociation
    Properties:
      SubnetId: !Ref InspectionPublicSubnetA
      RouteTableId: !Ref InspectionPublicRt

  InspectionPublicAssocB:
    Type: AWS::EC2::SubnetRouteTableAssociation
    Properties:
      SubnetId: !Ref InspectionPublicSubnetB
      RouteTableId: !Ref InspectionPublicRt

  # ---- TGW subnet route tables (one per AZ, AZ-scoped NAT) ----
  # When you add Network Firewall later, change the 0.0.0.0/0 target here
  # from the NAT gateway to the firewall VPC endpoint in the same AZ.
  InspectionTgwRtA:
    Type: AWS::EC2::RouteTable
    Properties:
      VpcId: !Ref InspectionVpc
      Tags:
        - { Key: Name, Value: inspection-tgw-rt-a }

  InspectionTgwDefaultRouteA:
    Type: AWS::EC2::Route
    Properties:
      RouteTableId: !Ref InspectionTgwRtA
      DestinationCidrBlock: 0.0.0.0/0
      NatGatewayId: !Ref NatGatewayA

  InspectionTgwAssocA:
    Type: AWS::EC2::SubnetRouteTableAssociation
    Properties:
      SubnetId: !Ref InspectionTgwSubnetA
      RouteTableId: !Ref InspectionTgwRtA

  InspectionTgwRtB:
    Type: AWS::EC2::RouteTable
    Properties:
      VpcId: !Ref InspectionVpc
      Tags:
        - { Key: Name, Value: inspection-tgw-rt-b }

  InspectionTgwDefaultRouteB:
    Type: AWS::EC2::Route
    Properties:
      RouteTableId: !Ref InspectionTgwRtB
      DestinationCidrBlock: 0.0.0.0/0
      NatGatewayId: !Ref NatGatewayB

  InspectionTgwAssocB:
    Type: AWS::EC2::SubnetRouteTableAssociation
    Properties:
      SubnetId: !Ref InspectionTgwSubnetB
      RouteTableId: !Ref InspectionTgwRtB

  # =========================================================================
  # WORKLOAD VPC  (no IGW, no NAT)
  # =========================================================================
  WorkloadVpc:
    Type: AWS::EC2::VPC
    Properties:
      CidrBlock: !Ref WorkloadVpcCidr
      EnableDnsSupport: true
      EnableDnsHostnames: true
      Tags:
        - { Key: Name, Value: workload-vpc }

  # ---- App subnets ----
  WorkloadAppSubnetA:
    Type: AWS::EC2::Subnet
    Properties:
      VpcId: !Ref WorkloadVpc
      CidrBlock: !Ref WorkloadAppSubnetACidr
      AvailabilityZone: !Ref AzA
      Tags:
        - { Key: Name, Value: workload-app-a }

  WorkloadAppSubnetB:
    Type: AWS::EC2::Subnet
    Properties:
      VpcId: !Ref WorkloadVpc
      CidrBlock: !Ref WorkloadAppSubnetBCidr
      AvailabilityZone: !Ref AzB
      Tags:
        - { Key: Name, Value: workload-app-b }

  # ---- DB subnets ----
  WorkloadDbSubnetA:
    Type: AWS::EC2::Subnet
    Properties:
      VpcId: !Ref WorkloadVpc
      CidrBlock: !Ref WorkloadDbSubnetACidr
      AvailabilityZone: !Ref AzA
      Tags:
        - { Key: Name, Value: workload-db-a }

  WorkloadDbSubnetB:
    Type: AWS::EC2::Subnet
    Properties:
      VpcId: !Ref WorkloadVpc
      CidrBlock: !Ref WorkloadDbSubnetBCidr
      AvailabilityZone: !Ref AzB
      Tags:
        - { Key: Name, Value: workload-db-b }

  # ---- TGW attachment subnets ----
  WorkloadTgwSubnetA:
    Type: AWS::EC2::Subnet
    Properties:
      VpcId: !Ref WorkloadVpc
      CidrBlock: !Ref WorkloadTgwSubnetACidr
      AvailabilityZone: !Ref AzA
      Tags:
        - { Key: Name, Value: workload-tgw-a }

  WorkloadTgwSubnetB:
    Type: AWS::EC2::Subnet
    Properties:
      VpcId: !Ref WorkloadVpc
      CidrBlock: !Ref WorkloadTgwSubnetBCidr
      AvailabilityZone: !Ref AzB
      Tags:
        - { Key: Name, Value: workload-tgw-b }

  # ---- App subnet route table (default route -> TGW) ----
  WorkloadAppRt:
    Type: AWS::EC2::RouteTable
    Properties:
      VpcId: !Ref WorkloadVpc
      Tags:
        - { Key: Name, Value: workload-app-rt }

  WorkloadAppDefaultRoute:
    Type: AWS::EC2::Route
    DependsOn: TgwWorkloadAttachment
    Properties:
      RouteTableId: !Ref WorkloadAppRt
      DestinationCidrBlock: 0.0.0.0/0
      TransitGatewayId: !Ref TransitGateway

  WorkloadAppAssocA:
    Type: AWS::EC2::SubnetRouteTableAssociation
    Properties:
      SubnetId: !Ref WorkloadAppSubnetA
      RouteTableId: !Ref WorkloadAppRt

  WorkloadAppAssocB:
    Type: AWS::EC2::SubnetRouteTableAssociation
    Properties:
      SubnetId: !Ref WorkloadAppSubnetB
      RouteTableId: !Ref WorkloadAppRt

  # ---- DB subnet route table (local only -- no egress) ----
  WorkloadDbRt:
    Type: AWS::EC2::RouteTable
    Properties:
      VpcId: !Ref WorkloadVpc
      Tags:
        - { Key: Name, Value: workload-db-rt }

  WorkloadDbAssocA:
    Type: AWS::EC2::SubnetRouteTableAssociation
    Properties:
      SubnetId: !Ref WorkloadDbSubnetA
      RouteTableId: !Ref WorkloadDbRt

  WorkloadDbAssocB:
    Type: AWS::EC2::SubnetRouteTableAssociation
    Properties:
      SubnetId: !Ref WorkloadDbSubnetB
      RouteTableId: !Ref WorkloadDbRt

  # ---- TGW subnet route table (default route -> TGW) ----
  WorkloadTgwRt:
    Type: AWS::EC2::RouteTable
    Properties:
      VpcId: !Ref WorkloadVpc
      Tags:
        - { Key: Name, Value: workload-tgw-rt }

  WorkloadTgwDefaultRoute:
    Type: AWS::EC2::Route
    DependsOn: TgwWorkloadAttachment
    Properties:
      RouteTableId: !Ref WorkloadTgwRt
      DestinationCidrBlock: 0.0.0.0/0
      TransitGatewayId: !Ref TransitGateway

  WorkloadTgwAssocA:
    Type: AWS::EC2::SubnetRouteTableAssociation
    Properties:
      SubnetId: !Ref WorkloadTgwSubnetA
      RouteTableId: !Ref WorkloadTgwRt

  WorkloadTgwAssocB:
    Type: AWS::EC2::SubnetRouteTableAssociation
    Properties:
      SubnetId: !Ref WorkloadTgwSubnetB
      RouteTableId: !Ref WorkloadTgwRt

  # =========================================================================
  # TRANSIT GATEWAY
  # =========================================================================
  TransitGateway:
    Type: AWS::EC2::TransitGateway
    Properties:
      AmazonSideAsn: 64512
      Description: Central ingress/egress transit gateway
      # Disable default tables so we control association/propagation explicitly
      DefaultRouteTableAssociation: disable
      DefaultRouteTablePropagation: disable
      DnsSupport: enable
      Tags:
        - { Key: Name, Value: central-tgw }

  # ---- VPC attachments ----
  # Appliance mode is enabled on the inspection attachment so that both
  # directions of a flow stick to the same AZ -- required for stateful
  # inspection once Network Firewall is added, harmless before then.
  TgwInspectionAttachment:
    Type: AWS::EC2::TransitGatewayVpcAttachment
    Properties:
      TransitGatewayId: !Ref TransitGateway
      VpcId: !Ref InspectionVpc
      SubnetIds:
        - !Ref InspectionTgwSubnetA
        - !Ref InspectionTgwSubnetB
      Options:
        ApplianceModeSupport: enable
      Tags:
        - { Key: Name, Value: tgw-attach-inspection }

  TgwWorkloadAttachment:
    Type: AWS::EC2::TransitGatewayVpcAttachment
    Properties:
      TransitGatewayId: !Ref TransitGateway
      VpcId: !Ref WorkloadVpc
      SubnetIds:
        - !Ref WorkloadTgwSubnetA
        - !Ref WorkloadTgwSubnetB
      Tags:
        - { Key: Name, Value: tgw-attach-workload }

  # ---- TGW route tables ----
  TgwWorkloadRt:
    Type: AWS::EC2::TransitGatewayRouteTable
    Properties:
      TransitGatewayId: !Ref TransitGateway
      Tags:
        - { Key: Name, Value: tgw-workload-rt }

  TgwInspectionRt:
    Type: AWS::EC2::TransitGatewayRouteTable
    Properties:
      TransitGatewayId: !Ref TransitGateway
      Tags:
        - { Key: Name, Value: tgw-inspection-rt }

  # Associate each attachment with its TGW route table
  TgwWorkloadAssoc:
    Type: AWS::EC2::TransitGatewayRouteTableAssociation
    Properties:
      TransitGatewayAttachmentId: !Ref TgwWorkloadAttachment
      TransitGatewayRouteTableId: !Ref TgwWorkloadRt

  TgwInspectionAssoc:
    Type: AWS::EC2::TransitGatewayRouteTableAssociation
    Properties:
      TransitGatewayAttachmentId: !Ref TgwInspectionAttachment
      TransitGatewayRouteTableId: !Ref TgwInspectionRt

  # Workload TGW table: send everything (incl. 0/0) to the inspection VPC
  TgwWorkloadDefaultRoute:
    Type: AWS::EC2::TransitGatewayRoute
    Properties:
      TransitGatewayRouteTableId: !Ref TgwWorkloadRt
      DestinationCidrBlock: 0.0.0.0/0
      TransitGatewayAttachmentId: !Ref TgwInspectionAttachment

  TgwWorkloadToInspectionRoute:
    Type: AWS::EC2::TransitGatewayRoute
    Properties:
      TransitGatewayRouteTableId: !Ref TgwWorkloadRt
      DestinationCidrBlock: !Ref InspectionVpcCidr
      TransitGatewayAttachmentId: !Ref TgwInspectionAttachment

  # Inspection TGW table: only return traffic to the workload VPC.
  # No 0.0.0.0/0 here -- workload VPC is not reachable except via this route.
  TgwInspectionToWorkloadRoute:
    Type: AWS::EC2::TransitGatewayRoute
    Properties:
      TransitGatewayRouteTableId: !Ref TgwInspectionRt
      DestinationCidrBlock: !Ref WorkloadVpcCidr
      TransitGatewayAttachmentId: !Ref TgwWorkloadAttachment

# ---------------------------------------------------------------------------
# Outputs
# ---------------------------------------------------------------------------
Outputs:
  TransitGatewayId:
    Value: !Ref TransitGateway
    Export: { Name: central-tgw-id }
  InspectionVpcId:
    Value: !Ref InspectionVpc
  WorkloadVpcId:
    Value: !Ref WorkloadVpc
  NatEipA:
    Description: Egress IP for AZ-a (verify with curl from an app instance)
    Value: !Ref NatEipA
  NatEipB:
    Description: Egress IP for AZ-b
    Value: !Ref NatEipB
  FirewallInsertionNote:
    Description: How to add Network Firewall later
    Value: >
      Create firewall subnets 10.0.10.0/28 (AzA) and 10.0.11.0/28 (AzB),
      a firewall RT per AZ with 0.0.0.0/0 -> same-AZ NAT, then repoint
      InspectionTgwDefaultRouteA/B from the NAT gateway to the same-AZ
      firewall VPC endpoint.
```
