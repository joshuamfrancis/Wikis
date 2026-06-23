# Multi-Account Route 53 Private Hosted Zones — Centralized DNS

## Topology assumptions
- **Central network account** handles centralized ingress/egress control.
- **Direct Connect** established between on-premises data center and the network account.
- **Transit Gateway (TGW)** lives in the network account and is shared to all other accounts via AWS RAM.

## Where to put the Private Hosted Zone (PHZ)
Create the PHZs in the **central network account** (alongside the TGW and Direct Connect), or in a dedicated **shared-services / DNS account** if you want stronger separation of concerns. Both work. Co-locating with the network account is simpler since ingress/egress is already centralized there; a dedicated DNS account pays off at scale by isolating Route 53 blast radius and IAM from routing/firewall config.

Then associate each PHZ with:
- the **central resolver VPC**, and
- **every spoke VPC** that needs to resolve those records.

## Key concept
**TGW routes IP packets — it does not resolve DNS.** Sharing the TGW via RAM provides connectivity only. Route 53 PHZ resolution is driven entirely by **VPC-to-PHZ associations**, evaluated at each VPC's `.2` resolver. A record in a PHZ resolves inside a VPC only if that VPC is explicitly associated with the PHZ. Account boundaries and TGW are irrelevant to that step.

## Resolution flows

### ① AWS spoke → AWS private domains
Cross-account associate the central PHZ with each spoke VPC. The spoke's `.2` resolver then resolves the records locally.

### ② On-prem → AWS private domains
Put an **inbound** Route 53 Resolver endpoint in the central VPC. On-prem DNS conditionally forwards the AWS private domains to those endpoint IPs over Direct Connect. The inbound endpoint resolves against PHZs associated with the central VPC — so the PHZ must be associated with that central resolver VPC.

### ③ AWS → on-prem domains
Put an **outbound** Resolver endpoint in the central VPC, create forwarding rules for the on-prem zones, and share those rules to all accounts via AWS RAM. Each spoke associates the shared rules so its `.2` forwards on-prem lookups out over Direct Connect.

This is the standard AWS "centralized DNS" pattern: endpoints and rules live once in the central account, PHZs live there too, and resolution fans out through associations rather than through the TGW.

## Cross-account PHZ association (CLI)
This cannot be done fully in the console. Authorize from the PHZ account, then associate from the spoke account.

```bash
# In the central (PHZ-owning) account
aws route53 create-vpc-association-authorization \
  --hosted-zone-id Z0123456789ABC \
  --vpc VPCRegion=us-east-1,VPCId=vpc-spoke111

# In the spoke (VPC-owning) account
aws route53 associate-vpc-with-hosted-zone \
  --hosted-zone-id Z0123456789ABC \
  --vpc VPCRegion=us-east-1,VPCId=vpc-spoke111

# Back in the central account, clean up the one-time auth
aws route53 delete-vpc-association-authorization \
  --hosted-zone-id Z0123456789ABC \
  --vpc VPCRegion=us-east-1,VPCId=vpc-spoke111
```

At scale, drive these through Terraform / CloudFormation (`aws_route53_vpc_association_authorization` + `aws_route53_zone_association`) rather than by hand. Every new spoke VPC needs the authorize-then-associate pair for each PHZ it should see.

## Summary table

| Flow | Mechanism | Lives in | Crosses Direct Connect? |
|------|-----------|----------|------------------------|
| ① AWS spoke → AWS private | Cross-account PHZ association | PHZ (central), spoke `.2` | No |
| ② On-prem → AWS private | Inbound Resolver endpoint + on-prem conditional forwarder | Central VPC | Yes (inbound) |
| ③ AWS → on-prem | Outbound Resolver endpoint + RAM-shared forwarding rules | Central VPC, assoc. in spokes | Yes (outbound) |

> **Key point:** TGW (shared via RAM) carries IP packets only. DNS resolution is driven entirely by VPC-to-PHZ associations and RAM-shared Resolver rules — independent of TGW routing.
