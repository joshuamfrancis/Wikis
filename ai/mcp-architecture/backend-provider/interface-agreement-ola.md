# D6 – Interface Agreement / OLA: `<Backend>` ↔ AI Platform

> One agreement per backend, or one master agreement with a schedule per backend. Values in `<>` are placeholders.
> **Parties:** Backend Systems (provider) · AI team (consumer) · **Review:** quarterly, and on any quota change.

## 1. Service description
* **Backend:** `<system>`, read-only operations listed in the catalogue (Schedule A).
* **Consumer services:** `<MCP server names>`, source IPs `<list>`.
* **Conditions:** the consumer agrees to the Conditions of Connection (D1).

## 2. Quota and limits (Schedule B)

| Item | Value |
|---|---|
| Requests per second (sustained / burst) | `<n>` / `<n>` |
| Concurrent connections | `<n>` |
| Allowed time windows | `<e.g. 07:00–19:00 AEST business days>` |
| Reduced limits during batch windows | `<window, limits>` |
| Maximum page size, required filters | Per catalogue |
| Behaviour when exceeded | HTTP 429 / connection refused. Consumer backs off. |

## 3. Service levels

| Item | Provider commitment |
|---|---|
| Availability of the read interface | `<%>` during `<hours>`, excluding maintenance |
| Planned maintenance | Notified `<5>` business days ahead |
| Data freshness (if replica / ODS) | `<≤ n minutes>` |
| Support hours | `<hours>`, contact `<queue>` |

## 4. Change management
* **Consumer changes:** ≥ 10 business days' notice for changes affecting load, operations used or user numbers (CoC-25). New operations go through onboarding (D7).
* **Provider changes:** notice of interface changes `<20>` business days ahead. Breaking changes keep the old version for `<n>` weeks.

## 5. Incidents

| Severity | Example | Response |
|---|---|---|
| P1 | Backend degradation caused by consumer load; suspected data exposure | Provider may throttle or disconnect immediately (CoC-24). Notify within 15 min. Data exposure reported within 1 hour (CoC-26). |
| P2 | Repeated quota breaches; missing user context | Throttle; joint review within 2 business days |
| P3 | Consumer-side errors, no backend impact | Business hours |

## 6. Right to throttle or disconnect
The provider may throttle or disconnect the consumer at any time to protect the backend or its data. Reconnection follows the non-compliance process in D1 §10.

## 7. Reporting
Monthly: usage against quota, throttling events, incidents, anomalies investigated.

## 8. Sign-off

| Role | Name | Date |
|---|---|---|
| Backend system owner | | |
| AI platform owner | | |
