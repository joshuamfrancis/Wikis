# D3 – Backend Readiness Assessment: `<System name>`

> Copy this template once per backend, as `assessments/<system-name>.md`.
> **Assessor:** · **System owner:** · **Date:** · **Status:** Draft / Final

## 1. Summary

| Item | Value |
|---|---|
| **Verdict** | Ready / Ready with conditions / Not eligible |
| Conditions to meet before go-live | |
| Complexity score (from §8) | `__ / 24` → Simple / Medium / Complex |
| Read-only path chosen | Replica / ODS / views & procedures / read-only app role |
| Access-control option | A / B / C / D / E |
| Quota granted | `__` req/s · `__` concurrent · windows `__` |

## 2. System profile

| Item | Value |
|---|---|
| Business function and criticality | |
| Platform and version | e.g. Oracle 19c on RHEL, z/OS CICS, vendor package `x` |
| Vendor support status | Supported / extended / unsupported |
| Interfaces available | REST / SOAP / JDBC / MQ / file / screen |
| Authentication methods supported | Basic / Kerberos / SAML / JWT / certificate / none |
| TLS supported natively | Yes / No |
| Existing integrations / consumers | |

## 3. Requested use cases (from the AI team)

| Use case | Data needed | Operations | Est. calls per user per hour |
|---|---|---|---|
| | | | |

## 4. Capacity

| Item | Value | Source |
|---|---|---|
| Peak utilisation (CPU, IO, connections) | | Monitoring, dates |
| Peak periods and batch windows | | |
| Hard limits (connections, sessions, licences) | | |
| Per-use charges (MIPS, licence by transaction) | | |
| **Measured headroom at peak** | `__` req/s | |
| Consumer demand forecast at peak | `__` req/s | AI team |
| Replica / ODS available | Yes / No | |
| Resource caps possible on consumer account | Yes (mechanism) / No | |

## 5. Read-only and side effects

| Operation | Read-only path | Side effects found | Mitigation |
|---|---|---|---|
| | | None / stamps / locks / logs / jobs | |

## 6. Data and access control

| Item | Value |
|---|---|
| Data classification of fields requested | Internal / Confidential / PII / regulated |
| Where object-level access rules live | Application code / database tables / database RLS / none |
| Can the backend enforce a passed user context? | No / database RLS possible / proxy user / APM SSO |
| Access-control option chosen and rationale | |
| Data classes approved for LLM processing | (Security / privacy sign-off) |
| Masking or field exclusions required | |

## 7. Constraints

| Item | Value |
|---|---|
| Non-production environment with realistic data | Yes / Partial / No |
| SME availability | |
| Vendor terms on indirect / API access | Checked: Yes / No, outcome |
| Change constraints (freeze, change board, vendor notification) | |

## 8. Complexity score

| Factor | Score (1–3) | Notes |
|---|---|---|
| Interface exposure | | |
| Read-only path | | |
| Access-control option | | |
| Capacity controls | | |
| Data sensitivity | | |
| Operations published | | |
| Environments & support | | |
| Change / vendor constraints | | |
| **Total** | | Copy into the effort model |

Scoring guide: [README §4.2](README.md#42-complexity-scoring-backend-team-work-only).

## 9. Risks, exceptions and sign-off

| Risk / exception | Compensating control | Risk owner |
|---|---|---|
| | | |

| Role | Name | Date |
|---|---|---|
| System owner | | |
| Security | | |
