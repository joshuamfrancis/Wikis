# D3 – Backend Readiness Assessment: `<System name>`

> Copy this template once per backend, as `assessments/<system-name>.md`.
> **Assessor:** · **System owner:** · **Date:** · **Status:** Draft / Final

## 1. Summary

| Item | Value |
|---|---|
| **Verdict** | Ready / Ready with conditions / Not eligible |
| Conditions to meet before go-live | |
| Complexity score (from §8) | `__ / 27` → Simple / Medium / Complex |
| Where access rules live | None / data-driven / code-driven / external |
| Read path chosen | P1 replica / P2 ODS / P3 views & procedures / P4 application API (per entity type if split) |
| Access-control option | A / B / C / D / E / F / G / H |
| Acceptable revocation lag | |
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
| Data classes approved for LLM processing | (Security / privacy sign-off) |
| Masking or field exclusions required | |

### 6.1 Access rules

| Item | Value |
|---|---|
| **Where access rules live** | None / data-driven (permission tables) / code-driven (application logic) / external (AD/LDAP groups) |
| Entity types covered by user/role rules | List which entities are restricted and which are visible to all permitted users |
| Rule description | Owner, role, team, hierarchy, status, delegation, time-based, field-level? Source of the description (docs, SME, code) |
| Permission tables and group sources | Tables and columns, and where role/group membership comes from |
| Can the application act as a user for a service account? | Yes (mechanism: act-as parameter / proxy user / Kerberos / trusted header) / No |
| Can the backend enforce a passed user context? | No / database RLS possible / proxy user / APM SSO |
| **Acceptable revocation lag** | How long a revoked user may still see data through a copy: seconds / minutes / hours / none |
| Read path per entity type | P1 / P2 / P3 / P4 (backend-solution-design §3.2) |
| Access-control option per entity type and rationale | A–H (backend-solution-design §3.6) |
| Differential test plan (options B, G, H) | Test users per role/team/hierarchy level, entities compared, regression trigger (application upgrade) |

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
| Access-rule reproduction | | |
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
