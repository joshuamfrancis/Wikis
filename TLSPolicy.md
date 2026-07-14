# TLS 1.3 (preferred) / TLS 1.2 FIPS Post-Quantum PFS Policy — Multi-Account AWS Environment

**Standard:** Prefer TLS 1.3 with hybrid post-quantum key exchange (ML-KEM / FIPS 203); minimum TLS 1.2 with FIPS-validated crypto and Perfect Forward Secrecy (ECDHE-only ciphers). Applies across development, testing, and production OUs, the central network account, and the hybrid path to on-premises.

**Reference ELB policies (as of 2026):**

| Purpose | Policy name |
|---|---|
| Recommended PQ + backward compatible | `ELBSecurityPolicy-TLS13-1-2-Res-PQ-2025-09` |
| **FIPS + PQ (your stated requirement)** | `ELBSecurityPolicy-TLS13-1-2-FIPS-PQ-2025-09` |
| FIPS + PQ, extended cipher list | `ELBSecurityPolicy-TLS13-1-2-Ext2-FIPS-PQ-2025-09` |
| TLS 1.3 only + PQ (strictest) | `ELBSecurityPolicy-TLS13-1-3-PQ-2025-09` |

The PQ policies negotiate hybrid groups `X25519MLKEM768`, `SecP256r1MLKEM768`, `SecP384r1MLKEM1024`, falling back to classical ECDHE for clients that don't offer ML-KEM. All `TLS13-1-2-Res`/`FIPS` policies are ECDHE-only, so PFS is preserved on TLS 1.2 fallback.

---

## 1. Services in Scope

### 1.1 Services where YOU set the TLS policy (server side — full control)

| Service | Where it appears in your environment | PQ/FIPS support |
|---|---|---|
| **Application Load Balancer (ALB)** | Project accounts fronting web apps | PQ + FIPS-PQ policies (Nov 2025) |
| **Network Load Balancer (NLB, TLS listeners)** | Project accounts; NLBs behind PrivateLink endpoint services | PQ + FIPS-PQ policies |
| **PrivateLink Endpoint Services** | Cross-account service exposure (shared-services → project accounts) | Inherits the NLB TLS policy — set FIPS-PQ there |
| **API Gateway (REST, private endpoints)** | Private APIs consumed via interface endpoints | `securityPolicy: TLS_1_2` (minimum); TLS 1.3 negotiated on the endpoint; no customer-selectable PQ policy yet — track roadmap |
| **Amazon RDS / Aurora** | Databases in project accounts | Force TLS via parameter group; Postgres `ssl_min_protocol_version=TLSv1.3` (or 1.2), MySQL `require_secure_transport=ON` + `tls_version` |
| **Amazon Redshift** | Analytics | `require_ssl=true` in parameter group; TLS 1.2+ |
| **ElastiCache (Redis/Valkey)** | Caching | In-transit encryption enabled; TLS 1.2+ |
| **Amazon MSK** | Streaming | `client broker: TLS`, restrict `ssl.enabled.protocols=TLSv1.3,TLSv1.2` |
| **OpenSearch Service** | Search/logging | Domain endpoint policy `Policy-Min-TLS-1-2-PFS-2023-10` |
| **Self-managed workloads (EC2, ECS, EKS containers)** | Project apps (your Python/Java containers) | Terminate TLS with OpenSSL ≥ 3.5 (native ML-KEM), AWS-LC / AWS-LC-FIPS 3.0 (first FIPS 140-3 module with ML-KEM), or s2n-tls; TLS 1.3 preferred, TLS 1.2 ECDHE-only fallback |
| **Windows servers (AD-joined)** | Member accounts | Windows Server 2022+ Schannel: enable TLS 1.3, disable TLS 1.0/1.1, restrict TLS 1.2 to ECDHE cipher suites; LDAPS/LDAP signing + channel binding to on-prem AD; SMB 3.1.1 encryption |

### 1.2 AWS service API endpoints (client side — AWS controls the server, you control the client)

These are consumed through your **central Endpoint VPC interface endpoints**. AWS has already deployed ML-KEM on the security-critical endpoints; your obligation is client-side:

- **KMS, ACM, Secrets Manager** — ML-KEM hybrid PQ-TLS live in all commercial regions; CRYSTALS-Kyber is being removed during 2026, so clients still pinned to Kyber-era SDKs silently fall back to classical key exchange.
- **S3, Payment Cryptography** — PQ-TLS available.
- **Secrets Manager clients** — Secrets Manager Agent 2.0.0+, Lambda Extension v19+, Secrets Store CSI Driver 2.0.0+ negotiate ML-KEM automatically.
- **All other AWS APIs** (STS, EC2, DynamoDB, etc.) — TLS 1.2 minimum enforced by AWS since 2023, TLS 1.3 preferred; ML-KEM rollout continuing across all public endpoints per the AWS PQC migration plan.
- **FIPS endpoints** — use `*.us-east-1.amazonaws.com` FIPS variants where mandated; note ML-KEM landed on non-FIPS endpoints first — verify per-service FIPS-endpoint PQ availability before hard-coding an expectation.

> **Interface endpoint caveat:** an interface endpoint is a pass-through to the AWS service's TLS terminator, so PQ negotiation works through your central Endpoint VPC unchanged. You cannot attach a TLS policy to the interface endpoint itself.

### 1.3 Network / hybrid path components

| Component | Notes |
|---|---|
| **Direct Connect** | Not encrypted by itself. Options: MACsec (L2, FIPS-approvable AES-GCM-256) on supported DX locations, or IPsec VPN over DX. IKEv2/IPsec is not TLS — align it separately (AES-GCM-256, DH group 20+, PFS enabled). |
| **AWS Network Firewall (central account)** | If TLS inspection is enabled, its TLS-inspection engine must support TLS 1.3 and tolerate hybrid ClientHello (~1 KB larger). Do **not** downgrade-terminate inspected flows to TLS 1.2 non-PFS. |
| **Gateway Load Balancer** | Out of scope — GENEVE encapsulation at L3, no TLS termination. |
| **On-prem web proxy (egress path)** | All server-initiated internet traffic transits it. If it does TLS interception, it becomes the effective TLS policy for outbound traffic — it must support TLS 1.3 and pass/negotiate ML-KEM groups, otherwise your PQ posture ends at the proxy. Prefer CONNECT tunneling (no MITM) for AWS/PQ-critical destinations. |
| **Route 53 Resolver / AD DNS forwarding** | DNS itself is out of TLS scope, but LDAPS/Kerberos to on-prem AD (see Windows row above) is in scope. |

### 1.4 Not applicable in your environment

- **CloudFront, Global Accelerator, public API Gateway edge** — no internet ingress/egress in your design.
- **NAT/IGW** — not provisioned.

---

## 2. Configurations to Fulfil the Requirement

### 2.1 Load balancers (ALB/NLB) — the primary enforcement point

```yaml
# CloudFormation (equivalent in Terraform: ssl_policy attribute)
Listener:
  Type: AWS::ElasticLoadBalancingV2::Listener
  Properties:
    Protocol: HTTPS            # TLS for NLB
    Port: 443
    SslPolicy: ELBSecurityPolicy-TLS13-1-2-FIPS-PQ-2025-09
    Certificates:
      - CertificateArn: !Ref CertArn   # prefer ECDSA P-256/P-384 certs from ACM Private CA
```

- Standardize on `ELBSecurityPolicy-TLS13-1-2-FIPS-PQ-2025-09` org-wide; use `TLS13-1-3-PQ-2025-09` where every client is modern.
- Certificates from **ACM Private CA** in the shared-services account (no public CA reachability anyway); share via RAM. ECDSA keys give smaller handshakes alongside ML-KEM's +1 KB.

### 2.2 SDK / client-side PQ enablement (your Python & Java stacks)

**Java (SDK v2 + CRT client):**
```java
SdkAsyncHttpClient client = AwsCrtAsyncHttpClient.builder()
    .postQuantumTlsEnabled(true)
    .build();
KmsAsyncClient kms = KmsAsyncClient.builder().httpClient(client).build();
```

**Python (boto3):** PQ key exchange comes from the underlying TLS library. Build containers on a base image with **OpenSSL ≥ 3.5** (native `X25519MLKEM768`) — e.g. Ubuntu 25.04+/current LTS backport — and current `botocore`. Verify with:
```bash
python -c "import ssl; print(ssl.OPENSSL_VERSION)"
openssl s_client -connect kms.ap-southeast-2.amazonaws.com:443 -groups X25519MLKEM768
```

**Containers (Docker):** bake a hardened base image in your Docker Hub org with OpenSSL 3.5+, `MinProtocol = TLSv1.2`, ECDHE-only TLS 1.2 cipher string, and make it the mandatory `FROM` in CI.

**Rust-based tooling / Secrets Manager Agent:** enable `rustls` `prefer-post-quantum`, or upgrade to Agent 2.0.0+ where it's on by default.

**FIPS endpoints:** set `AWS_USE_FIPS_ENDPOINT=true` (env/config) for workloads under FIPS mandate; confirm private DNS entries exist in the central Endpoint VPC for the FIPS endpoint names you use.

### 2.3 Data services

- **RDS Postgres:** `rds.force_ssl=1`, `ssl_min_protocol_version=TLSv1.2` (1.3 where engine version allows).
- **RDS MySQL/Aurora MySQL:** `require_secure_transport=ON`, `tls_version=TLSv1.2,TLSv1.3`.
- **S3:** enforce via bucket policy (see 3.2).
- **OpenSearch:** `TLSSecurityPolicy: Policy-Min-TLS-1-2-PFS-2023-10`.
- **MSK:** TLS-only client auth, restrict protocols/ciphers in cluster config.

### 2.4 Windows / AD estate

- Group Policy: disable TLS 1.0/1.1 and non-ECDHE TLS 1.2 suites in Schannel; enable TLS 1.3 (Server 2022+).
- Require LDAP signing + LDAPS (636/3269) and LDAP channel binding to on-prem DCs; SMB encryption on file shares.
- Bake into the golden AMI used across member accounts.

### 2.5 Network account specifics

- TGW attachments carry the traffic unchanged — no TLS config there, but confirm **MTU** headroom: TGW supports 8500-byte MTU intra-AWS but 1500 toward DX; the larger hybrid ClientHello can cross packet boundaries, so watch for middleboxes that drop fragmented/multi-record ClientHellos.
- Network Firewall TLS inspection configuration (if used): TLS 1.3-capable inspection cert from ACM Private CA; explicitly test ML-KEM pass-through.
- On-prem proxy: allowlist AWS FIPS endpoint FQDNs; validate PQ handshake survives the proxy (`keyExchange` in CloudTrail — see 4.2).

---

## 3. Preventive Controls

### 3.1 SCPs / Resource Control Policies (management account, applied per OU)

**RCP — deny non-TLS and old-TLS access to S3 org-wide:**
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "DenyInsecureTransport",
      "Effect": "Deny",
      "Principal": "*",
      "Action": "s3:*",
      "Resource": "*",
      "Condition": { "Bool": { "aws:SecureTransport": "false" } }
    },
    {
      "Sid": "DenyOldTLS",
      "Effect": "Deny",
      "Principal": "*",
      "Action": "s3:*",
      "Resource": "*",
      "Condition": { "NumericLessThan": { "s3:TlsVersion": "1.2" } }
    }
  ]
}
```

**SCP — only approved ELB security policies may be created/modified:**
```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Sid": "EnforceApprovedTlsPolicies",
    "Effect": "Deny",
    "Action": [
      "elasticloadbalancing:CreateListener",
      "elasticloadbalancing:ModifyListener"
    ],
    "Resource": "*",
    "Condition": {
      "StringNotEqualsIfExists": {
        "elasticloadbalancing:SecurityPolicy": [
          "ELBSecurityPolicy-TLS13-1-2-FIPS-PQ-2025-09",
          "ELBSecurityPolicy-TLS13-1-2-Ext2-FIPS-PQ-2025-09",
          "ELBSecurityPolicy-TLS13-1-3-PQ-2025-09"
        ]
      }
    }
  }]
}
```
AWS explicitly recommends IAM/RCP condition enforcement of PQ TLS policies for future resource creation and updates.

### 3.2 Pipeline (shift-left) controls — GitHub-centric

- **CloudFormation Guard / cfn-lint or OPA/Conftest for Terraform** rules in GitHub Actions: fail PRs where `SslPolicy` isn't in the approved list, RDS parameter groups lack `require_secure_transport`/`rds.force_ssl`, OpenSearch domains use pre-PFS policies, or API Gateway `securityPolicy != TLS_1_2`.
- **AWS Config proactive evaluation** (pre-provision hook via CloudFormation) for the same rules.
- **Base-image gate:** GitHub Actions job that inspects the Dockerfile `FROM` and blocks images not built from the approved OpenSSL-3.5 base in your Docker Hub org; Dependabot/Renovate to keep AWS SDK versions ≥ ML-KEM-capable minimums.
- **Service Catalog / CDK constructs** in the shared-services account with the TLS policy hard-coded, so project teams consume compliant patterns by default.

### 3.3 Network-layer prevention

- Network Firewall stateful rules in the central account: **drop TLS < 1.2** (SNI/TLS-version match) on east-west and north-south paths; alert on non-PFS TLS 1.2 cipher negotiation where inspection is enabled.
- VPC endpoint policies on interface endpoints restricting principals to org accounts (`aws:PrincipalOrgID`) — keeps enforcement scope authoritative.

---

## 4. Detective Controls

### 4.1 AWS Config (aggregated to a delegated admin / audit account)

- `elbv2-acm-certificate-required`
- `elb-tls-https-listeners-only` / `alb-http-to-https-redirection-check`
- **Custom Config rule (Lambda/Guard):** listener `SslPolicy` ∈ approved FIPS-PQ list — the managed predefined-policy rules predate the PQ policies, so a custom rule is the reliable check.
- `rds-instance-transport-encrypted`-style checks (custom for parameter-group values), `opensearch-https-required`, `s3-bucket-ssl-requests-only`, `api-gw-ssl-enabled`.
- Conformance pack deployed to all OUs; findings to **Security Hub** with the audit account as delegated admin.

### 4.2 CloudTrail `tlsDetails` — the PQ smoking gun

CloudTrail records `tlsDetails.tlsVersion`, `cipherSuite`, and the negotiated key exchange for API calls. Athena over the org trail:

```sql
SELECT useridentity.accountid, eventsource,
       tlsdetails.tlsversion, tlsdetails.ciphersuite, count(*) AS calls
FROM cloudtrail_logs
WHERE tlsdetails.tlsversion IN ('TLSv1', 'TLSv1.1')
   OR (eventsource IN ('kms.amazonaws.com','secretsmanager.amazonaws.com')
       AND tlsdetails.keyexchange <> 'X25519MLKEM768')
GROUP BY 1,2,3,4
ORDER BY calls DESC;
```
`keyExchange = X25519MLKEM768` confirms hybrid PQ is active; a classical value flags an outdated SDK/OpenSSL or a proxy stripping PQ groups. Schedule this as a weekly Athena query with SNS/EventBridge alerting.

### 4.3 Access logs and flow evidence

- **ALB access logs** → S3 → Athena: `ssl_protocol` / `ssl_cipher` columns; alert on anything below TLS 1.2 or non-ECDHE TLS 1.2 suites (clients hitting fallback).
- **NLB TLS listener access logs**: same fields for TLS listeners.
- **S3 server access logs / CloudTrail data events**: TLS version per request to spot legacy clients before tightening the RCP from deny `<1.2` to deny `<1.3`.
- **Network Firewall alert logs** (central account) → CloudWatch/S3: fired rules for legacy-TLS drops give you east-west visibility that per-account logs miss.

### 4.4 Security Hub & posture reporting

- Enable **AWS Foundational Security Best Practices** + **NIST 800-53** standards; TLS-related controls (ELB.17-class, ES.8, S3.5, etc.) roll into a single org score.
- Custom insight: "Resources negotiating classical key exchange to KMS/Secrets Manager/ACM" from the Athena query via custom findings (`BatchImportFindings`).
- Quarterly **PQ readiness report**: % of API calls negotiating ML-KEM per account/OU — this is your measurable HNDL-risk burn-down and catches the 2026 Kyber-removal fallback issue.

### 4.5 Active scanning

- Internal scanner (e.g., `sslyze`/`testssl.sh` in a scheduled ECS task per VPC) against internal ALBs/NLBs/private APIs and Windows endpoints (LDAPS, RDP, WinRM) — validates the deployed handshake, not just the declared config.

---

## 5. Rollout Order (suggested)

1. **Detect first:** deploy CloudTrail `tlsDetails` analytics + ALB log queries org-wide; baseline current TLS 1.0/1.1 and non-PQ usage.
2. **Dev OU:** switch ELB policies to FIPS-PQ, roll PQ-enabled base images/SDKs, fix breakage (proxy/firewall ClientHello handling is the usual culprit).
3. **Preventive gates:** enable pipeline checks, then SCP/RCP in dev → test → prod.
4. **Prod OU:** flip policies during change windows; keep `TLS13-1-2-*` (dual-version) policies until legacy clients are gone, then move hot paths to `TLS13-1-3-PQ`.
5. **2026 housekeeping:** upgrade any Java CRT clients still negotiating CRYSTALS-Kyber before AWS removes it from endpoints this year, or they silently fall back to classical key exchange.
