# Cost Projection — Hybrid AWS Landing Zone

> **Rate disclaimer:** All unit rates below are indicative `us-east-1` on-demand list prices and must be
> re-validated against the AWS Pricing Calculator and your EDP/PPA discounts before the figures are
> committed to a budget. Data-transfer-out to on-premises over Direct Connect is priced separately and
> is excluded unless stated.

---

## 1. Scope and Sizing Assumptions

These drive every number in this section. Change them here and the model recalculates.

| # | Assumption | Value | Notes |
|---|---|---|---|
| A1 | Member accounts (Dev / Test / Prod) | 10 / 10 / 10 = **30** | Excludes Network + shared-service accounts |
| A2 | Platform accounts | **3** | Network, Log Archive, Shared Services |
| A3 | Availability Zones in use | **2** | Applies to every AZ-priced resource |
| A4 | Interface endpoints in central Endpoint VPC | **15** | e.g. ssm, ssmmessages, ec2messages, kms, logs, monitoring, sts, secretsmanager, ecr.api, ecr.dkr, s3 (interface), sqs, sns, events, elasticloadbalancing |
| A5 | TGW VPC attachments | **1 per account VPC = 33** | Attachment priced per attachment, not per AZ |
| A6 | Private hosted zones | **1 per account = 33** | Plus 1 per interface endpoint service in Network account |
| A7 | Route 53 Resolver outbound endpoints | **1 endpoint × 2 IPs** | In Network account, forwarding to on-prem AD |
| A8 | Additional CloudTrail trails | **1 per account beyond the org trail** | Management events only unless noted |
| A9 | Monthly hours | **730** | |
| A10 | East-west traffic through TGW | **20 TB/month** | Aggregate across all attachments |
| A11 | Traffic through Endpoint VPC interface endpoints | **8 TB/month** | Aggregate |

---

## 2. Cost Line Items

### 2.1 Additional CloudTrail Trails (per account)

| Component | Unit Rate | Driver | Monthly Qty | Monthly Cost |
|---|---|---|---|---|
| First trail (org trail, management events) | $0 | Per account | 33 | $0.00 |
| **Additional** trail — management events | $2.00 / 100k events | Events delivered | 33 accts × 150k = 4.95M | $99.00 |
| Data events (S3 / Lambda), if enabled | $0.10 / 100k events | Events delivered | 20M | $200.00 |
| S3 storage for trail logs | $0.023 / GB-month | Log volume | 500 GB | $11.50 |
| S3 PUT requests for log delivery | $0.005 / 1,000 | Deliveries | 1.5M | $7.50 |
| CloudWatch Logs ingestion (if trail → CWL) | $0.50 / GB | Ingested | 300 GB | $150.00 |
| **Subtotal** | | | | **≈ $468 / month** |

**Cost levers:** only the *second and subsequent* copies of management events are billed — consolidate
per-account trails into the organization trail wherever the account team only needs read access.
Data events are the dominant term; scope them to specific buckets/prefixes, not "all S3".

---

### 2.2 Endpoint VPC and Interface Endpoints

Interface endpoints are billed **per endpoint, per AZ, per hour**, plus data processed.

| Component | Unit Rate | Calculation | Monthly Cost |
|---|---|---|---|
| Interface endpoint ENIs | $0.01 / hr / AZ | 15 endpoints × 2 AZ × 730 hr | $219.00 |
| Interface endpoint data processing | $0.01 / GB (first 1 PB) | 8,000 GB | $80.00 |
| Gateway endpoints (S3, DynamoDB) | $0.00 | 2 | $0.00 |
| Route 53 PHZ per endpoint service | $0.50 / zone / month | 15 zones | $7.50 |
| **Subtotal** | | | **≈ $307 / month** |

**Cost levers:**
- Each additional interface endpoint adds ~$14.60/month at 2 AZ before any traffic. Curate the
  endpoint catalogue — publish on demand rather than pre-provisioning the full service list.
- Use **gateway** endpoints for S3/DynamoDB where the access pattern allows; they are free but are
  per-VPC and cannot be centralised, so they trade off against the hub-and-spoke design.
- A third AZ adds 50% to the ENI-hour line. Confirm 2-AZ resilience is accepted by the risk owner.

---

### 2.3 Transit Gateway and Attachments

| Component | Unit Rate | Calculation | Monthly Cost |
|---|---|---|---|
| VPC attachments | $0.05 / hr / attachment | 33 × 730 | $1,204.50 |
| Direct Connect gateway attachment | $0.05 / hr | 1 × 730 (×2 if resilient pair) | $73.00 |
| TGW data processing | $0.02 / GB | 20,000 GB | $400.00 |
| TGW Flow Logs → S3 | $0.25 / GB ingested (vended) | 200 GB | $50.00 |
| **Subtotal** | | | **≈ $1,728 / month** |

**Notes and cost levers:**
- An attachment is billed **once per VPC**, not per AZ — but each attachment should still land subnets
  in both AZs for resilience, which costs nothing extra. Do not create one attachment per AZ.
- Data processed is charged **once per TGW hop**. Spoke-to-spoke via an inspection VPC traverses the
  TGW twice and is therefore billed twice ($0.04/GB effective) — this is the single most
  underestimated line in this design.
- Attachment hours accrue whether or not the VPC carries traffic. Reclaim attachments from dormant
  Dev/Test VPCs; a decommission process is worth ~$36.50/month per account.

---

### 2.4 Private Hosted Zones and Resolver Rule Sharing

| Component | Unit Rate | Calculation | Monthly Cost |
|---|---|---|---|
| Private hosted zones (first 25) | $0.50 / zone / month | 25 | $12.50 |
| Private hosted zones (beyond 25) | $0.10 / zone / month | 8 | $0.80 |
| Additional VPC associations to a PHZ | $0.00 | — | $0.00 |
| Resolver outbound endpoint | $0.125 / hr / IP | 2 IPs × 730 | $182.50 |
| Resolver inbound endpoint (if on-prem → AWS resolution needed) | $0.125 / hr / IP | 2 IPs × 730 | $182.50 |
| Resolver outbound queries (to on-prem AD) | $0.40 / million | 60M | $24.00 |
| DNS queries against PHZs | $0.40 / million | 100M | $40.00 |
| RAM sharing of resolver rules / TGW | $0.00 | — | $0.00 |
| **Subtotal** | | | **≈ $442 / month** |

**Cost levers:**
- **Resolver endpoints are the cost, not the rules.** Rule sharing via RAM is free and unlimited —
  centralising one outbound endpoint in the Network account and sharing the AD forwarding rule to all
  30 accounts is the correct pattern; the anti-pattern (an endpoint per account) would cost
  ~$5,475/month.
- Resolver endpoint IPs must be in separate AZs; 2 IPs is the enforced minimum, so $182.50/month is
  the floor per endpoint.
- Zone count, not query volume, is trivial. Do not over-engineer PHZ consolidation.

---

### 2.5 Related Inspection Layer (context — size separately)

Included for completeness because these dominate the Network account bill and are often mis-attributed
to TGW.

| Component | Unit Rate | Calculation | Monthly Cost |
|---|---|---|---|
| Network Firewall endpoints | $0.395 / hr / endpoint | 2 AZ × 730 | $576.70 |
| Network Firewall data processing | $0.065 / GB | 20,000 GB | $1,300.00 |
| Gateway Load Balancer | $0.0125 / hr / AZ + LCU | 2 × 730 | $18.25 |
| GWLB endpoints | $0.01 / hr / endpoint | 2 × 730 | $14.60 |
| GWLB endpoint data processing | $0.0035 / GB | 20,000 GB | $70.00 |
| **Subtotal** | | | **≈ $1,980 / month** |

---

## 3. Rolled-Up Projection

| Cost Group | Monthly | Annual |
|---|---|---|
| Additional CloudTrail trails | $468 | $5,616 |
| Endpoint VPC + interface endpoints | $307 | $3,684 |
| Transit Gateway + attachments | $1,728 | $20,736 |
| Private hosted zones + resolver | $442 | $5,304 |
| Inspection layer (NFW + GWLB) | $1,980 | $23,760 |
| **Total shared network platform** | **$4,925** | **$59,100** |
| Contingency @ 15% | $739 | $8,865 |
| **Budget ask** | **$5,664** | **$67,965** |

*Excludes:* Direct Connect port hours and DTO, EC2/EKS workloads, S3/EBS storage, and any on-premises
proxy or AD infrastructure.

---

## 4. Growth Sensitivity

Marginal cost of scale — use these for onboarding business cases.

| Change | Marginal Monthly Cost |
|---|---|
| +1 member account (VPC, TGW attachment, PHZ, extra trail) | ≈ $52 + traffic |
| +1 interface endpoint in the Endpoint VPC (2 AZ) | $14.60 + $0.01/GB |
| +1 AZ across the estate (endpoints, NFW, GWLB, resolver) | ≈ $600 |
| +1 TB/month east-west through inspection | ≈ $107 (TGW ×2 hops + NFW + GWLB) |
| +1 shared resolver rule / RAM share | $0.00 |

---

## 5. Chargeback and Tagging Model

| Cost Group | Allocation Method |
|---|---|
| TGW attachment hours | Direct — attachment is per member VPC, tag with `project` and `environment` |
| TGW / NFW / GWLB data processing | Split by VPC Flow Log bytes per attachment |
| Interface endpoint ENI hours | Even split across consuming accounts, or weighted by endpoint DNS query counts |
| Resolver endpoints and PHZ | Platform overhead — absorb centrally, do not chargeback |
| Additional CloudTrail trails | Direct to the owning account |

Enforce `CostCenter`, `Project`, `Environment`, and `Owner` tags via SCP on TGW attachments, endpoints,
and hosted zones so Cost Explorer and CUR splits are reliable from day one.

---

## 6. Assumptions, Exclusions, and Risks

- **Assumed:** no NAT/IGW anywhere, so no NAT Gateway hours ($0.045/hr) or NAT data processing
  ($0.045/GB) appear — a material saving versus a typical landing zone, offset by Direct Connect DTO
  for all internet-bound traffic via the on-premises proxy.
- **Assumed:** Dev/Test/Prod network separation means no cross-environment TGW routes; this does not
  change unit costs but does prevent attachment consolidation.
- **Risk — double-billed TGW hops:** the single largest variance driver. Validate with 30 days of Flow
  Logs before finalising.
- **Risk — endpoint sprawl:** interface endpoints are cheap individually and expensive collectively.
  Gate new endpoints through architecture review.
- **Excluded:** Direct Connect port and DTO charges, on-premises proxy capacity, AD licensing,
  third-party appliance licences behind the GWLB.
