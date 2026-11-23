# D9 – ARB Information Item: Protecting Backend Systems for AI/MCP Consumers

> **Item type:** Information (no decision sought) · **Presenter:** `<name>`, Solutions Architect, Backend Systems · **Time:** 15 min (10 presentation + 5 questions)

## 1. Paper (one page)

**Purpose.** To inform ARB of the Backend Systems team's approach to giving the AI team's agents and MCP servers read-only access to backend systems, the standards consumers must meet, and the decisions that will come back to ARB.

**Background.** The AI team is building AI agents that read enterprise data through MCP (Model Context Protocol) servers. They own the AI clients, agents, MCP gateway and MCP servers. Those servers will call systems owned by Backend Systems. Most of these systems are legacy and many can't validate modern identity tokens. F5 BIG-IP is the API gateway, and credentials follow the organisation's OAuth 2.0 standard.

**Approach.**
1. **Provider stance.** The AI platform is treated as an external consumer. Anything that must be true about our systems is enforced on our side, not assumed from the consumer's design.
2. **Read-only only.** Writes are out of scope and would need a separate request and review.
3. **Capacity protection.** Each backend grants an explicit quota sized against measured headroom. It's enforced at the F5 (connection and rate limits) and in the backend (resource governors / WLM), with a kill switch. Load moves to replicas or an ODS where that doesn't bypass access rules the application enforces in code. Otherwise the application's own API is used, under quota.
4. **Act as the end user.** The target is a delegated, read-only user token (OAuth authorization code grant, or SAML exchanged for OAuth), so each system applies its own access rules for that user. Where a legacy system can't accept that, a tightly restricted service account acts for the user with compensating controls. Every request carries the end user's identity and a correlation ID, logged at the F5 and the backend.
5. **Standards and process.** Conditions of connection, a shared responsibility matrix with the AI team, a per-backend readiness assessment with an eligible / not-eligible verdict, an OLA per backend, and a repeatable onboarding process.

**Plan.** Mobilise and standards (`<dates>`), discovery and assessment of `<n>` prioritised backends (`<dates>`), pilot on one or two low-complexity backends (`<dates>`), then re-estimate and scale.

**Effort.** Backend-team effort only, estimated as one-off work plus a scored per-backend estimate. The current range is `<x–y>` person-days at low confidence, to be re-estimated after discovery and again after the pilot.

**Decisions that will come to ARB.**
* Investment in read replicas / ODS for backends without capacity headroom.
* F5 module licensing (APM / Advanced WAF), if edge identity or API schema enforcement is needed.
* Access-control approach for systems whose access rules are enforced in application code (application API acting as the user, reproducing the rules in a copy, or restricting to coarse data).
* Identity tier per system: where systems can't accept delegated end-user identity, whether to invest (e.g. F5 APM, application features) or accept the service-account fallback with compensating controls.
* Any exception to the read-only principle.

**Requested of ARB.** Note the approach, and provide feedback, particularly on dependencies on other teams (Network/F5, Security, Data/Privacy).

## 2. Slide outline (6 slides)

| # | Title | Content | Key message |
|---|---|---|---|
| 1 | Why this is coming to ARB | AI agents will read our systems via MCP. Ownership split: AI team = agents/MCP, us = backends. Information item only. | "New type of consumer, same duty to protect our systems." |
| 2 | Constraints | Legacy systems that don't understand identity tokens. F5 BIG-IP as the API gateway. OAuth 2.0 credential standard (client credentials / authorization code; SAML exchanged for OAuth; PATs as fallback). Capacity headroom varies. Vendor terms. | "We design for what we have." |
| 3 | Our approach | The five principles as a simple diagram: AI platform → F5 (allowlist, limits, kill switch) → read-only interface → backend (resource caps), with monitoring alongside. | "Protection is enforced on our side." |
| 4 | What consumers must do / what we do | Two columns from the shared responsibility matrix (headline rows only). Link to conditions of connection. | "Clear ownership, no gaps." |
| 5 | How we'll roll out | Phases, pilot criteria (headroom, low sensitivity, coarse access), readiness verdicts, onboarding flow. | "Start small, measure, then scale." |
| 6 | Effort and decisions to come | Estimation method (one-off + scored per backend, ranges by confidence), current range, the list of upcoming ARB decisions. | "We'll be back with specific decisions." |

**Tips**
* **Pre-align with the AI team lead.** Ideally they endorse D1 and D5 before ARB, or co-present slide 4. ARB will look for agreement between the teams.
* **Don't present the AI team's architecture.** Reference it, and keep your slides to the backend side.
* **Talk in risks the board recognises:** outage from load, data exposure, untraceable access, licence breach.
* **Bring one worked example,** e.g. one real backend's readiness verdict and quota. It makes the approach concrete.

## 3. Likely questions

| Question | Answer |
|---|---|
| What is the API gateway? | F5 BIG-IP. It validates OAuth tokens, applies allowlists, quotas and the kill switch, and signs in onward to legacy backends as the user where they support Kerberos or trusted headers. |
| Why not use client credentials everywhere? | A client-credentials token identifies the AI application, not the person. For user-specific data, every user would see what the application can see. So user-facing tools use the authorization code grant, or client credentials only where the backend applies an asserted user. |
| Can the AI see data a user isn't allowed to see? | Many of our systems enforce access to entities by user or role in application code, and a replica or ODS bypasses those rules. So we first establish where each system's access rules live. Then we either use the application's own API acting as the user, reproduce data-driven rules in the copy and prove they match through differential testing against the application, or expose only data every permitted user may see. For sensitive systems this is a per-backend decision that comes back to ARB. |
| What stops an agent overloading a system? | Hard quotas at the F5 and in the backend that hold regardless of consumer behaviour, tighter limits in batch windows, and a kill switch we control. Verified by load testing at 2× quota before go-live. |
| How do we know who did what? | Every request carries the end user and a correlation ID, logged at the F5 and the backend and sent to the SIEM, so it can be matched with the AI team's logs. |
| Does data leave our environment? | Only for data classes approved per backend through Security / privacy review, and only to LLM providers Security has approved. |
| What does it cost? | Backend-team effort as a range by confidence, refined after discovery. Possible additional costs: replicas/ODS, F5 modules, vendor licensing. These come back as decisions. |
| Why not always call our systems as the end user? | That's the target, and we use it wherever a system can verify a delegated credential. Many legacy systems can't, so a restricted service account acts for the user instead, with the user's identity passed, logged, and enforced where the system allows. Each system's tier is recorded in its assessment. |
| Why read-only only? | It removes the highest-impact risks while value is proven. Writes would need a separate design with human confirmation and stronger identity guarantees. |
