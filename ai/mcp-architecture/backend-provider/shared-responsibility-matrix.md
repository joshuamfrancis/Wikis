# D5 – Shared Responsibility Matrix

> **Owner:** Backend Systems (IT), agreed with the AI team · **Status:** Draft
> **O** = owns (accountable and does it) · **C** = contributes · **–** = no role

| Area | Control | AI team | Backend team | Evidence |
|---|---|---|---|---|
| **End users** | Authenticate end users (SSO, MFA) | O | – | Consumer architecture |
| | Decide which users may use which tools (per-tool authorisation) | O | C (defines which data each use case may get) | Gateway policy, D3 use cases |
| | Obtain a delegated, down-scoped user credential per request where the backend supports it (tier 1, CoC-05a) | O | C (defines audience, scopes, accepted issuers) | Token exchange config, F5 APM / backend logs |
| | Validate delegated credentials (signature, issuer, audience, expiry, scope) | – | O | Backend / F5 APM config, negative tests |
| | Derive end-user identity from verified tokens only (CoC-16) | O | C (verifies in onboarding) | Design evidence, two-user test |
| | Pass user context and correlation ID on every request (CoC-15) | O | C (rejects requests without it) | F5 logs |
| **AI platform** | Tool metadata review and pinning, prompt-injection defences | O | – | Consumer architecture |
| | Human confirmation for consequential actions | O | – | n/a while read-only |
| | MCP server isolation and egress restriction (CoC-23) | O | – | Attestation |
| | Consumer credentials in a secrets store, never in code or prompts (CoC-06) | O | C (issues, rotates) | Secret scanning |
| **Backend access** | Publish the operation catalogue, side-effect checks | C (requests operations) | O | Catalogue |
| | Read-only enforcement (role, views, replica, F5 methods) | – | O | T20 test evidence |
| | Network access path and source allowlist | C (registers IPs) | O | F5 and firewall config |
| | Identity tier per backend (aim for tier 1) | C | O | D3 assessment |
| | Service accounts, least privilege | – | O | Account review |
| | Object-level access control | C (option B: sets user context, option C: filters) | O (chooses option, builds RLS or views) | D3, contract tests |
| **Capacity** | Demand forecast | O | – | Intake (T02) |
| | Quota allocation | C | O | Quota register (D4) |
| | Quota enforcement (F5 limits, backend resource caps) | – | O | T21 load test |
| | Client-side limits, pagination, backoff, caching (CoC-11–13) | O | C (publishes limits) | Attestation, monitoring |
| **Data** | Data classification and approved data classes for LLM processing | C | O (with Security / privacy) | D3 |
| | Field minimisation and masking at source | C | O | Catalogue, views |
| | Handling and retention of data after retrieval (CoC-20) | O | – | Attestation |
| | Choice of LLM provider and its data terms | O (with Security) | – | Security approval |
| **Operations** | Monitoring of backend usage and anomalies | C | O | Dashboards, SIEM |
| | Monitoring of agent behaviour and tool use | O | – | Consumer audit logs |
| | Kill switch on the backend side | – | O | T22 test |
| | Incident response | O for platform incidents | O for backend incidents | OLA (D6) |
| | Change notice affecting load or operations (CoC-25) | O | O (backend changes affecting consumers) | OLA (D6) |
| | Credential rotation | C | O | Rotation log |
