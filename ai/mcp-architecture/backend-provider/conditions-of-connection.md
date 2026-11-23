# D1 – Conditions of Connection for AI/MCP Consumers

> **Owner:** Backend Systems (IT) · **Status:** Draft · **Applies to:** any AI agent, MCP server or MCP gateway reading from a backend system owned by this team.

Each condition states **how it's assured**:
- **Enforced** – our controls make it impossible to breach.
- **Detected** – we monitor for breaches and act.
- **Attested** – the consumer provides evidence and we review it.

Our controls are designed so that the conditions protecting backend integrity and capacity are *enforced*, not merely attested.

## 1. Scope

* **In scope:** read-only access to approved operations on approved backends, by approved consumer services.
* **Out of scope:** writes of any kind, bulk extraction or replication, and access by anything other than a registered consumer service.

## 2. Access path

| ID | Condition | Assured by |
|---|---|---|
| CoC-01 | Consumers connect **only via the F5 virtual server** published for that backend, never directly to a backend host or database. | Enforced – network firewall rules |
| CoC-02 | Connections originate **only from registered source IPs or subnets** of the consumer's MCP servers. | Enforced – F5 and firewall allowlist |
| CoC-03 | Consumers call **only operations listed in the published catalogue** for that backend (specific API paths/methods, views, or stored procedures). No free-form SQL, query strings or generic "execute" operations. | Enforced – F5 method/path allowlist, database grants |
| CoC-04 | All connections use **TLS 1.2+**. Where a legacy protocol can't, the F5 terminates TLS and the remaining leg stays on a segmented network. | Enforced – F5 TLS profile |

## 3. Identity and credentials

| ID | Condition | Assured by |
|---|---|---|
| CoC-05 | Each consumer service uses **its own service account issued by us**. Accounts are not shared across consumer services, environments or other integrations. | Enforced – account per service |
| CoC-06 | Credentials are kept in the consumer's secrets store, **never in code, config files, images or prompts**, and are rotated on our schedule (default 90 days, or on demand). | Attested + Detected – secret scanning, rotation |
| CoC-07 | Service accounts are **non-interactive** and can't log in through user interfaces. | Enforced – account policy |

## 4. Read-only

| ID | Condition | Assured by |
|---|---|---|
| CoC-08 | Consumers perform **read operations only**. | Enforced – read-only role/views or replica, F5 method allowlist |
| CoC-09 | Any write attempt by a consumer account is treated as a **security incident**. | Detected – alert on write or denied-permission events |

## 5. Capacity and load behaviour

| ID | Condition | Assured by |
|---|---|---|
| CoC-10 | Consumers stay within the **allocated quota** per backend (requests per second, concurrent connections, allowed time windows) set in the quota register. | Enforced – F5 connection/rate limits, backend resource caps |
| CoC-11 | Every list or search request uses **filters and pagination** within the published maximum page size. Unbounded queries are rejected. | Enforced where the interface allows (view/procedure parameters), otherwise Detected |
| CoC-12 | Consumers apply **timeouts, exponential backoff and circuit breaking**. No automatic retry of timed-out requests without backoff; no retry storms. | Attested + Detected – error-rate and burst monitoring |
| CoC-13 | Consumers **cache** stable or reference data for at least the published TTL rather than re-reading it. | Attested |
| CoC-14 | Consumers provide a **demand forecast** before onboarding and before any significant change in users or use cases. | Attested – onboarding (D7) |

## 6. User context and audit

| ID | Condition | Assured by |
|---|---|---|
| CoC-15 | Every request carries the **end user's identity** and a **correlation ID**: HTTP headers `X-On-Behalf-Of: <employee_id>` and `X-Correlation-ID: <uuid>`; for database connections, the client identifier / session context set per request (e.g. Oracle `DBMS_SESSION.SET_IDENTIFIER`, SQL Server `sp_set_session_context`). | Enforced – requests without it are rejected (F5 iRule or database logon check) |
| CoC-16 | The end user's identity is **derived only from the consumer's verified authentication token**, never from tool arguments or anything the model generates. | Attested – evidence of the derivation and tests |
| CoC-17 | Unattended or scheduled agent runs use a **separately registered identity** for that job, never a previous interactive user's identity. | Attested + Detected |

> **Why CoC-16 matters.** Where we use the passed identity to *enforce* access (database row-level security, access-control option B), the consumer's service account can effectively act as any user. We then rely on the consumer setting the identity correctly, so it's assessed in onboarding, and misuse is a breach of these conditions.

## 7. Data handling

| ID | Condition | Assured by |
|---|---|---|
| CoC-18 | Consumers request **only the fields needed** for the use case. Data classified above the level approved for a backend isn't exposed through the catalogue. | Enforced – views/masking; Attested – field mapping |
| CoC-19 | Data may be sent to an LLM provider **only for the data classes approved** in that backend's readiness assessment, and only to providers approved by Security. | Attested – privacy assessment |
| CoC-20 | Consumers **don't persist** backend data beyond the session or cache TTL, except where approved (e.g. audit logs, with masking). | Attested |
| CoC-21 | Consumers treat **free-text fields as untrusted** (possible prompt injection) and don't let content read from our systems trigger other actions without user confirmation. | Attested |

## 8. Security evidence (before go-live)

| ID | Condition | Assured by |
|---|---|---|
| CoC-22 | The consumer provides: architecture overview, threat model, list of tools and the backend operations each one calls, how user identity is derived (CoC-16), and recent security test results. | Attested – onboarding (D7) |
| CoC-23 | The consumer's MCP servers run in an environment with **restricted egress**, so data read from our systems can only reach approved destinations. | Attested |

## 9. Operations

| ID | Condition | Assured by |
|---|---|---|
| CoC-24 | We may **throttle or disconnect** a consumer at any time to protect a backend, notifying them as soon as practical. | Enforced – F5 kill-switch rule, account disable |
| CoC-25 | Consumers give **≥ 10 business days' notice** of changes that affect load or the operations used, and ask through onboarding (D7) for any new operation. | Attested – OLA (D6) |
| CoC-26 | Both parties follow the incident process in the OLA. Suspected data exposure is reported within **1 hour**. | Attested – OLA (D6) |

## 10. Non-compliance

A breach of an enforced or detected condition triggers throttling or disconnection under CoC-24, then a joint review. Reconnection needs a corrective action plan agreed by the system owner and Security.
