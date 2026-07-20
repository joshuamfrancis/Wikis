# Inbound Route 53 Resolver for Vanity URLs — Design Note

## TL;DR

- **Do you *need* an inbound Resolver endpoint?** Only if on‑premises must resolve names that live in a Route 53 **private hosted zone (PHZ)** or are otherwise only resolvable *inside* AWS. For a pure vanity record whose A/CNAME is held in your on‑prem DNS and points at a static private IP or a *publicly resolvable* `internal-*.elb.amazonaws.com` name, an inbound endpoint is **not strictly required**.
- **Should you build one anyway?** **Yes — recommended.** It future‑proofs the PHZ‑heavy pattern you already run, lets you use Route 53 **alias** records to internal ALBs (health‑checked, self‑updating, apex‑capable) instead of brittle static A records, and keeps DNS resolution on a single internal path consistent with how you already centralize the AD forwarding rule.
- **Centrally managed?** **Yes.** Deploy a single HA inbound endpoint in the central **network account**, expose it to on‑prem via conditional forwarders, and hook member‑account PHZs to it using **cross‑account VPC association** and/or **Route 53 Profiles shared over AWS RAM** — the same centralization philosophy you already apply to the TGW, endpoint VPC, and resolver rules.

---

## A necessary correction first: the "Elastic IP" case

Your environment has **no Internet Gateway and no NAT Gateway**. An Elastic IP is only reachable inbound through an Internet Gateway, so in this architecture on‑prem clients can **not** reach an EC2 instance by its EIP — that path doesn't exist. On‑prem reaches AWS **privately over Direct Connect → TGW using RFC1918 addresses**.

So the two realistic vanity targets are:

1. **A record → the EC2 instance's *private* IP** (static, brittle, no scaling/HA), or
2. **CNAME/alias → an *internal* ALB** (`scheme = internal`), which resolves to private IPs in the app VPC. This is the recommended target.

Everything below assumes internal, privately routed targets.

---

## Decision logic: is an inbound endpoint required?

The question is entirely **"where does the authoritative record live, and can on‑prem resolve it?"**

| Vanity record location | Target | On‑prem can resolve without inbound endpoint? |
|---|---|---|
| On‑prem DNS holds an **A** record | EC2 private IP | **Yes** — on‑prem answers locally; traffic routes over DX/TGW. |
| On‑prem DNS holds a **CNAME** | `internal-<alb>.<region>.elb.amazonaws.com` | **Yes** — internal‑ELB names are publicly resolvable and return private IPs, so on‑prem public recursion works. |
| Record is in a Route 53 **private hosted zone** | alias/CNAME to internal ALB, or PHZ A record | **No — inbound endpoint required.** PHZ records are *not* publicly resolvable; on‑prem must forward the query into AWS. |

So the trigger for needing an inbound endpoint is simple: **you want on‑prem to resolve something held in a Route 53 private hosted zone.**

Given that your platform already exposes services almost exclusively through PHZs (central Interface Endpoints with PHZs, per‑account PHZs for private services), standardizing vanity URLs on the same PHZ pattern is the natural choice — and that choice makes the inbound endpoint the right call.

### Why prefer the PHZ + inbound‑endpoint path over on‑prem records

- **Alias records to internal ALBs** live only in Route 53. They track the ALB's changing node IPs automatically, support the **zone apex**, and can be health‑checked. On‑prem CNAMEs and static A records can't do this.
- **One resolution path.** All internal names (endpoints, AD via the outbound path, and now vanity URLs) resolve through a single, auditable AWS/on‑prem DNS boundary rather than a mix of public recursion and internal lookups.
- **No internal names leaking into public recursion.** Even though `internal-*.elb` names are technically public, keeping resolution inside the private path is cleaner and consistent with "no direct internet access."
- **Consistency** with your existing centralized DNS design (the AD forwarding rule is already shared centrally over RAM).

---

## Recommended design: one centrally managed inbound endpoint

### 1. Placement

Create **one inbound Resolver endpoint in the central network account**, in a central DNS/shared‑services VPC (this can be the existing central Endpoint VPC or a dedicated small DNS VPC). Provision **at least two IP addresses across two AZs** for HA — on‑prem forwarders will target these IPs.

The inbound endpoint answers queries using **the resolver of the VPC it sits in**. That VPC resolves:

- Private hosted zones **associated to that VPC**, plus
- Resolver **forwarding rules** associated to that VPC, plus
- Native AWS/VPC DNS.

This is the key lever for central management: to let the central endpoint resolve a member account's PHZ, that PHZ must be **associated to the central DNS VPC**.

### 2. Routing and reachability

- Ensure the central DNS VPC has a **TGW attachment** with explicit routes (your model uses explicit routes, no propagation) so on‑prem CIDRs can reach the endpoint ENIs and return traffic can get back.
- On‑prem routing must send the endpoint's IPs (or the DNS VPC CIDR) over Direct Connect → TGW.
- **Security group** on the endpoint: allow **UDP/53 and TCP/53** from your on‑prem DNS server IPs/CIDRs only.

### 3. Hooking member‑account PHZs to the central endpoint

Pick one (or combine):

**Option A — Member‑account PHZ, cross‑account associated (recommended).**
Keep each project's vanity zone in the same account as its ALB, so alias records stay local to the resource, then associate that PHZ to the central DNS VPC:

```bash
# In the PHZ-owner (member) account:
aws route53 create-vpc-association-authorization \
  --hosted-zone-id <PHZ_ID> \
  --vpc VPCRegion=<region>,VPCId=<central-dns-vpc-id>

# In the central network account:
aws route53 associate-vpc-with-hosted-zone \
  --hosted-zone-id <PHZ_ID> \
  --vpc VPCRegion=<region>,VPCId=<central-dns-vpc-id>

# Optional cleanup in the member account:
aws route53 delete-vpc-association-authorization \
  --hosted-zone-id <PHZ_ID> \
  --vpc VPCRegion=<region>,VPCId=<central-dns-vpc-id>
```

Note: cross‑account PHZ association can't be done from the console — use CLI/API/IaC. Respect your dev/test/prod isolation: don't cross those boundaries with a single shared PHZ; either run a DNS VPC per environment or keep associations within‑environment.

**Option B — Central vanity PHZ in the network account.**
Create one org‑wide zone (e.g. `apps.internal.company.aws`) as a PHZ in the network account, associated to the central DNS VPC, and put every vanity record there as an **alias to the internal ALB** (supply the ALB DNS name + the ELB service hosted‑zone ID for the region — this works cross‑account) or a plain CNAME. Gives a flat namespace but concentrates change management in one account.

### 4. Centralize the wiring with Route 53 Profiles + RAM

**Route 53 Profiles** let you bundle PHZ associations, Resolver forwarding rules, and DNS settings into a profile and **share it across accounts via AWS RAM**, then attach it to many VPCs — so you don't script `associate-vpc-with-hosted-zone` per account by hand. This is the cleanest "central management" mechanism for a fleet and complements what you already do (you share the AD forwarding rule over RAM today). Use a Profile to consistently attach the vanity PHZ(s) and any forwarding rules to member VPCs and the central DNS VPC.

### 5. On‑prem conditional forwarding

You **cannot delegate** (NS) to a private hosted zone — a PHZ has no public NS records. Instead, configure **conditional forwarders** on your on‑prem DNS servers for the AWS vanity domain(s), pointing at the inbound endpoint's two IPs:

```
# Example (concept):
zone "apps.internal.company.aws"  ->  forward to  10.x.x.10, 10.x.y.10  (inbound endpoint IPs)
```

This is the mirror image of your existing outbound path (AWS → on‑prem AD via the outbound endpoint + forwarding rule).

### 6. HA, security, and observability

- **Two AZs / two IPs** minimum; size for query volume (each ENI has a soft QPS limit — add IPs if needed).
- Restrict inbound 53 to on‑prem resolver IPs only.
- Enable **Resolver query logging** for audit, and consider **DNS Firewall** on the DNS VPC for consistency with your firewall‑centric posture.

---

## End‑to‑end resolution flow (target design)

**On‑prem user hits `myapp.apps.internal.company.aws`:**

1. On‑prem DNS matches the conditional forwarder for `apps.internal.company.aws` → forwards to the **inbound endpoint IPs** over DX/TGW.
2. Inbound endpoint resolves against the central DNS VPC's resolver, which sees the **associated PHZ** and returns the **alias → internal ALB → private IP(s)**.
3. On‑prem client connects to the ALB **private IP over Direct Connect → TGW**, through your east‑west/north‑south firewall inspection as configured.

No IGW, no NAT, no public exposure — fully consistent with your "consume everything internally" model.

---

## Practical notes for your stack

- **IaC:** manage the endpoint, security group, PHZs, cross‑account associations, and Route 53 Profiles as Terraform (or CloudFormation) in the **network account**, versioned in **GitHub**, deployed via GitHub Actions — matching your preferred toolchain. Cross‑account association is a two‑account apply, so structure the pipeline to assume roles in both the owner and central accounts.
- **Keep environment isolation:** because there is no network path across dev/test/prod, keep DNS association scoping within each environment (per‑environment DNS VPC/endpoint, or per‑environment Profiles) rather than one global PHZ spanning all three.
- **Cost/ops:** an inbound endpoint is a small, fixed monthly cost per ENI plus query charges — negligible relative to the operational benefit of alias‑based, self‑healing vanity resolution.

---

## Summary

| Question | Answer |
|---|---|
| Is an inbound endpoint strictly required? | Only if on‑prem must resolve **private hosted zone** records. Not required for on‑prem‑held A records or publicly resolvable internal‑ELB CNAMEs. |
| Should you create one? | **Yes**, to standardize on PHZ + alias‑to‑internal‑ALB and keep resolution internal and consistent. |
| Centrally managed? | **Yes** — single HA endpoint in the **network account**. |
| How centrally managed? | Central DNS VPC → **cross‑account PHZ association** and/or **Route 53 Profiles shared via RAM**; on‑prem **conditional forwarders** point at the endpoint IPs; all defined as IaC in GitHub. |
| Watch‑out | The "EIP of EC2" path doesn't work with no IGW — use **internal ALB / private IP** targets instead. |
