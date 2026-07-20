# Hybrid DNS Resolution Flows (Mermaid)

Two directions, two different mechanisms:

| Direction | Mechanism | Key object |
|---|---|---|
| On-prem → AWS | Conditional forwarder on on-prem DNS → **inbound** endpoint IPs | PHZ **associated to the inbound endpoint's VPC** |
| AWS → on-prem | **FORWARD resolver rule** associated to the VPC → **outbound** endpoint | Rule shared via **RAM** |

---

## 1) On-Premises Client → AWS (inbound)

Example: `myapp.apps.au.cloud.aws` (vanity URL → internal ALB in a member account).

```mermaid
sequenceDiagram
    autonumber
    participant C as On-prem Client
    participant AD as On-prem DNS / AD<br/>(conditional forwarder)
    participant DX as Direct Connect + TGW
    participant IN as Inbound Resolver Endpoint<br/>(ENIs in Central Endpoint VPC)
    participant R53 as Central DNS VPC Resolver<br/>(VPC .2)
    participant PHZ as Private Hosted Zone<br/>(member-owned, associated<br/>to central DNS VPC)
    participant ALB as Internal ALB<br/>(member VPC)

    C->>AD: Query myapp.apps.au.cloud.aws
    Note over AD: Match conditional forwarder<br/>for myapp.apps.au.cloud.aws
    AD->>DX: Forward query to inbound endpoint IPs<br/>(UDP/TCP 53)
    DX->>IN: Route over DX → TGW to ENI
    Note over IN: SG must allow 53 from<br/>on-prem DNS server IPs
    IN->>R53: Resolve in the context of<br/>the endpoint's own VPC
    R53->>PHZ: Zone is associated to this VPC → lookup
    PHZ-->>R53: ALIAS record → internal ALB private IPs
    R53-->>IN: Answer (private IPs)
    IN-->>DX: DNS response
    DX-->>AD: DNS response
    AD-->>C: myapp... = 10.x.x.x (private)

    rect rgb(235, 245, 235)
    Note over C,ALB: Data path (separate from DNS)
    C->>DX: HTTPS to 10.x.x.x
    DX->>ALB: DX → TGW → inspection → member VPC
    ALB-->>C: Response
    end
```

**Critical dependency:** the inbound endpoint has no resolution logic of its own — it answers using **its own VPC's resolver**. If the member PHZ is *not* associated to the central DNS VPC, this flow returns NXDOMAIN/SERVFAIL.

---

## 2) AWS Client → On-Premises DNS (outbound)

Example: a Windows member server resolving `corp.example.com` (Active Directory).

```mermaid
sequenceDiagram
    autonumber
    participant W as Member Workload<br/>(EC2 / ECS / EKS)
    participant VR as Member VPC Resolver<br/>(VPC .2)
    participant RULE as FORWARD Resolver Rule<br/>corp.example.com<br/>(shared via RAM,<br/>associated to member VPC)
    participant OUT as Outbound Resolver Endpoint<br/>(ENIs in Central Endpoint VPC)
    participant DX as TGW + Direct Connect
    participant AD as On-prem AD DNS Servers

    W->>VR: Query dc01.corp.example.com
    Note over VR: Rule evaluation:<br/>most-specific domain match
    VR->>RULE: Matches corp.example.com
    RULE->>OUT: Rule targets this outbound endpoint
    OUT->>DX: Query to configured target IPs<br/>(on-prem AD DNS)
    DX->>AD: Route over TGW → DX
    Note over AD: On-prem firewall must allow 53<br/>from outbound endpoint ENI IPs
    AD-->>DX: Answer (on-prem private IP)
    DX-->>OUT: DNS response
    OUT-->>VR: DNS response
    VR-->>W: dc01.corp.example.com = 192.168.x.x

    rect rgb(235, 245, 235)
    Note over W,AD: Data path (separate from DNS)
    W->>DX: LDAP / Kerberos / SMB to 192.168.x.x
    DX->>AD: TGW → DX → on-prem
    AD-->>W: AD authentication response
    end
```

**Critical dependency:** the **rule** must be associated to the *member* VPC (after the RAM share is accepted). Sharing alone does nothing — association is what activates it. The outbound endpoint stays in the central account and is never shared.

---

## 3) Resolution precedence in a member VPC

Useful for reasoning about which mechanism wins:

```mermaid
flowchart TD
    Q[Query from member VPC workload] --> A{Matches a FORWARD<br/>resolver rule domain?}
    A -- Yes, most specific --> B[Outbound endpoint → on-prem AD]
    A -- No --> C{Name in a PHZ<br/>associated to this VPC?}
    C -- Yes --> D[Answer from PHZ<br/>local PHZ, or central<br/>service-endpoint PHZ]
    C -- No --> E{AWS service /<br/>public name?}
    E -- Yes --> F[Route 53 Resolver<br/>public resolution]
    E -- No --> G[NXDOMAIN]

    style B fill:#F5EBFF,stroke:#9933CC
    style D fill:#EDE1F7,stroke:#9933CC
    style F fill:#DDEBF7,stroke:#2E75B6
    style G fill:#FFE0E0,stroke:#CC0000
```

> Note: with **no NAT/IGW**, branch **F** cannot reach the internet. This is exactly why service-endpoint PHZs must be associated to member VPCs — so AWS service names resolve to **interface endpoint private IPs** at branch **D** rather than falling through to public resolution.

---

## Common failure points

| Symptom | Likely cause |
|---|---|
| On-prem gets NXDOMAIN for AWS private name | PHZ not associated to the **inbound endpoint's VPC** |
| On-prem query times out | SG on inbound endpoint blocks 53; or no TGW/DX route back to on-prem |
| AWS workload can't resolve AD domain | Rule shared via RAM but **not associated** to the member VPC |
| AWS resolves AD name, can't connect | DNS fine — check TGW routes / firewall on the data path |
| AWS service name resolves to public IP | Service-endpoint PHZ not associated to member VPC (or endpoint private DNS misconfigured) |
| Wrong zone answers in shared DNS VPC | Overlapping PHZ namespaces — enforce unique per-project domains |