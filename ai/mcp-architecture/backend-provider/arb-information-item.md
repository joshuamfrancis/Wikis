# D9 – ARB Information Item: Protecting Backend Systems for AI/MCP Consumers

> **Item type:** Information (no decision sought) · **Presenter:** `<name>`, Solutions Architect, Backend Systems · **Time:** 15 min (10 presentation + 5 questions)

## 1. Paper (one page)

**Purpose.** To inform ARB of the Backend Systems team's approach to giving the AI team's agents and MCP servers read-only access to backend systems, the standards consumers must meet, and the decisions that will come back to ARB.

**Background.** The AI team is building AI agents that read enterprise data through MCP (Model Context Protocol) servers. They own the AI clients, agents, MCP gateway and MCP servers. Those servers will call systems owned by Backend Systems. Most of these systems are legacy: many can't validate modern identity tokens, there's no API gateway, and the F5 load balancer is the only edge component available.

**Approach.**
1. **Provider stance.** The AI platform is treated as an external consumer. Anything that must be true about our systems is enforced on our side, not assumed from the consumer's design.
2. **Read-only only.** Writes are out of scope and would need a separate request and review.
3. **Capacity protection.** Each backend grants an explicit quota sized against measured headroom. It's enforced at the F5 (connection and rate limits) and in the backend (resource governors / WLM), with a kill switch. Replicas or ODS are preferred over production where available.
4. **Attribution.** Every request carries the end user's identity and a correlation ID, logged at the F5 and the backend, even where the system can't enforce access by user.
5. **Standards and process.** Conditions of connection, a shared responsibility matrix with the AI team, a per-backend readiness assessment with an eligible / not-eligible verdict, an OLA per backend, and a repeatable onboarding process.

**Plan.** Mobilise and standards (`<dates>`), discovery and assessment of `<n>` prioritised backends (`<dates>`), pilot on one or two low-complexity backends (`<dates>`), then re-estimate and scale.

**Effort.** Backend-team effort only, estimated as one-off work plus a scored per-backend estimate. The current range is `<x–y>` person-days at low confidence, to be re-estimated after discovery and again after the pilot.

**Decisions that will come to ARB.**
* Investment in read replicas / ODS for backends without capacity headroom.
* F5 module licensing (APM / Advanced WAF), if edge identity or API schema enforcement is needed.
* Access-control approach for sensitive systems (database row-level security vs restricting to coarse data).
* Any exception to the read-only principle.

**Requested of ARB.** Note the approach, and provide feedback, particularly on dependencies on other teams (Network/F5, Security, Data/Privacy).

## 2. Slide outline (6 slides)

| # | Title | Content | Key message |
|---|---|---|---|
| 1 | Why this is coming to ARB | AI agents will read our systems via MCP. Ownership split: AI team = agents/MCP, us = backends. Information item only. | "New type of consumer, same duty to protect our systems." |
| 2 | Constraints | Legacy systems that don't understand identity tokens. No API gateway, F5 only. Capacity headroom varies. Vendor terms. | "We design for what we have." |
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
| Why not wait for an API gateway? | The controls we need (allowlist, limits, read-only, audit) can be met with the F5 and native backend features now. A future gateway would replace some F5 rules, not the approach. |
| Can the AI see data a user isn't allowed to see? | Not where we use coarse access (only data all permitted users may see) or database row-level security on the passed user. For sensitive systems this is a per-backend decision that comes back to ARB. |
| What stops an agent overloading a system? | Hard quotas at the F5 and in the backend that hold regardless of consumer behaviour, tighter limits in batch windows, and a kill switch we control. Verified by load testing at 2× quota before go-live. |
| How do we know who did what? | Every request carries the end user and a correlation ID, logged at the F5 and the backend and sent to the SIEM, so it can be matched with the AI team's logs. |
| Does data leave our environment? | Only for data classes approved per backend through Security / privacy review, and only to LLM providers Security has approved. |
| What does it cost? | Backend-team effort as a range by confidence, refined after discovery. Possible additional costs: replicas/ODS, F5 modules, vendor licensing. These come back as decisions. |
| Why read-only only? | It removes the highest-impact risks while value is proven. Writes would need a separate design with human confirmation and stronger identity guarantees. |
