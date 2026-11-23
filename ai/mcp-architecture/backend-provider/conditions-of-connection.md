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
| CoC-05a | **Tools that return user-specific data use a delegated user token (identity tier 1) wherever the backend path supports it:** an OAuth 2.0 access token from the **authorization code** grant (the user signs in interactively), requested with read-only scopes and presented to F5 BIG-IP. | Enforced – BIG-IP validates the token (issuer, audience, expiry, scope, client) |
| CoC-05c | **SAML:** where a system relies on SAML, the assertion is **exchanged for an OAuth access token** (RFC 7522) and only the OAuth token is presented to the API. The consumer **never automates browser-based SAML or SSO logins** (no headless browsers, form filling or IdP-page scraping). | Enforced – BIG-IP accepts OAuth tokens only; Attested – no browser automation |
| CoC-05d | **Client credentials** tokens identify the consumer application. They may be used for unattended jobs and non-user-specific data. For user-specific data, they may be used only with the end user asserted per request (CoC-15) **and** a backend that applies it (tier 2). | Enforced – BIG-IP allows only approved grants per backend and operation |
| CoC-05e | **Service-account PATs only where OAuth is unavailable** for that backend, registered as an exception: service account (never a person), read-only scope, expiry ≤ 90 days, source-IP bound where supported, rotated before expiry. | Enforced – issued only by us; Detected – usage monitoring |
| CoC-05b | The consumer **never collects, stores or replays end users' passwords, personal access tokens** or other primary credentials for our systems. | Attested + Detected |
| CoC-05 | Each consumer service authenticates as itself with **its own registered OAuth client** (or, under CoC-05e, its own service-account PAT), preferably using certificate-based client authentication (`private_key_jwt` or mTLS) rather than a shared secret. Not shared across consumer services, environments or other integrations. | Enforced – client registration per service |
| CoC-06 | Client secrets, keys, refresh tokens and PATs are kept in the consumer's secrets store, **never in code, config files, images or prompts**, and are rotated on our schedule (default 90 days, or on demand). | Attested + Detected – secret scanning, rotation |
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
| CoC-12 | Consumers meet the **retry and backoff requirements in §5.1**: retries in one layer only, limited attempts with backoff and jitter, no retry of timeouts, `Retry-After` honoured, circuit breaker, retry budget, clear errors to the model. | Attested + Detected – retry-rate and burst monitoring; verified in load test T21 |
| CoC-13 | Consumers **cache** stable or reference data for at least the published TTL rather than re-reading it. | Attested |
| CoC-14 | Consumers provide a **demand forecast** before onboarding and before any significant change in users or use cases. | Attested – onboarding (D7) |

### 5.1 Retry and backoff requirements (CoC-12)

Backoff is coded in the **consumer's MCP server**, the component that calls our backends. It's consumer behaviour, so it's attested and tested; our enforced controls are the F5 `429` response and backend resource caps (D2 §3.4, §3.5).

| ID | Requirement |
|---|---|
| CoC-12.1 | **Retry in one layer only: the MCP server.** The HTTP client library, gateway and agent don't add their own retries of backend calls, and the agent doesn't automatically re-run a tool that returned an error. (Three layers each retrying three times turns one failure into up to 27 calls.) |
| CoC-12.2 | **At most 3 attempts in total** per backend call (the first try plus 2 retries), with **exponential backoff and full jitter** starting at ≥ 1 s (e.g. 1 s, 2 s, randomised). |
| CoC-12.3 | **Retry only fast, transient failures:** connection refused or reset, `503`, `429`. **Never retry** `400`, `401`, `403`, `404` or other errors that will fail the same way again. |
| CoC-12.4 | **Don't retry timeouts on queries or long-running operations.** The work may still be running on the backend, so a retry adds load at the worst moment. Return the failure instead. |
| CoC-12.5 | **Honour `Retry-After`:** wait at least the time given on a `429` or `503` before any further request to that backend from that pod, not just before retrying the same request. |
| CoC-12.6 | **Circuit breaker per backend:** after repeated failures (e.g. 5 within 30 s, or ≥ 50% errors over 20 calls), stop calling the backend and fail fast for a cooling-off period (≥ 30 s), then test with a single request before resuming. With many pods, use conservative thresholds or shared breaker state. |
| CoC-12.7 | **Retry budget:** retries stay ≤ 10% of the consumer's requests to a backend over any 1-minute window. Once the budget is used up, fail without retrying. |
| CoC-12.8 | **Timeouts** on every backend call, no longer than the published per-operation timeout in the catalogue. |
| CoC-12.9 | **Clear errors to the model:** when the MCP server gives up, it returns a tool result with `isError: true` and a plain message that discourages an immediate re-call, e.g. *"The orders system is busy. Try again in a few minutes, or narrow the search."* It never suggests broadening the query. |
| CoC-12.10 | **Limits on the agent side:** the agent caps tool calls per turn and per session, so a model can't loop on a failing or slow tool. |

## 6. User context and audit

| ID | Condition | Assured by |
|---|---|---|
| CoC-15 | Every request carries the **end user's identity** and a **correlation ID**: HTTP headers `X-On-Behalf-Of: <employee_id>` and `X-Correlation-ID: <uuid>`; for database connections, the client identifier / session context set per request (e.g. Oracle `DBMS_SESSION.SET_IDENTIFIER`, SQL Server `sp_set_session_context`). In tier 1 the user comes from the validated token, and BIG-IP sets `X-On-Behalf-Of` from it, overwriting any client value; `X-Correlation-ID` is still sent by the consumer. | Enforced – requests without it are rejected (F5 iRule or database logon check) |
| CoC-16 | The end user's identity is **derived only from the consumer's verified authentication token**, never from tool arguments or anything the model generates. | Attested – evidence of the derivation and tests |
| CoC-17 | Unattended or scheduled agent runs use a **separately registered identity** for that job, never a previous interactive user's identity. | Attested + Detected |

> **Why CoC-16 matters.** In identity tiers 2 and 3, where we use the passed identity to *enforce* access (database row-level security, an application act-as API, entitlements), the consumer's service account can effectively act as any user. We then rely on the consumer setting the identity correctly, so it's assessed in onboarding, and misuse is a breach of these conditions.

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
