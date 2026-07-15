# Application Takeover & Onboarding Checklist

**Purpose:** Structured plan for taking over lead ownership of an application with 4 flows (3 built, 1 in progress).
**How to use:** Work top to bottom. Each phase unblocks the next. Tick items as you go, and capture answers/links inline. Every phase should end with at least one artifact (diagram, table, or doc).

- [ ] Owner: _your name_
- [ ] Start date: _____
- [ ] Target "fully ramped" date: _____

---

## Guiding logic of the sequence

1. **Unblock yourself** (access) and **capture decaying knowledge** (people) first.
2. **See it run** before reading the code.
3. **Prove you can operate it** (observe + deploy + roll back) before going deep.
4. **Then decompose** architecture, cross-cutting concerns, and delivery machinery.
5. **Then take forward ownership** of the 4th flow, risks, and process.

Keep a running **Questions & Unknowns log** and a **Risk/Tech-debt register** open throughout.

---

## Phase 1 — Access & knowledge transfer (do these in parallel, week 1)

Everything downstream is blocked on access. The existing developers' knowledge is a decaying asset — book time with them *now*.

### Access
- [ ] GitHub org/repo access confirmed (read + write, and admin where appropriate)
- [ ] AWS account(s) access + correct IAM role/permissions
- [ ] CI/CD pipeline access (GitHub Actions or other)
- [ ] Docker Hub repository access
- [ ] IdP / identity platform admin or read access
- [ ] Ticketing / project board access (Jira, GitHub Projects, etc.)
- [ ] Documentation/wiki access (Confluence, repo `/docs`, Notion, etc.)
- [ ] Database access (read at minimum, per environment)
- [ ] Monitoring/logging tooling access

### Knowledge transfer (schedule before devs roll off)
- [ ] KT session booked with each dev who built flows 1–3
- [ ] KT session booked with owner of the in-flight 4th flow
- [ ] Sessions **recorded** and notes stored in the repo/wiki
- [ ] "Who to ask about X" contact map created

**Artifact:** Access matrix + KT recordings/notes index.

---

## Phase 2 — Functional understanding & run it locally

### Functional understanding
- [ ] Located where requirements are documented (and how current they are)
- [ ] Validated functional understanding against requirements
- [ ] Live step-through of the app as each **user persona**
- [ ] Identified a **demo flow** based on key requirements

### Local dev environment (the first honest test of "is this understandable?")
- [ ] Can build the full stack locally (docker-compose?)
- [ ] Time-to-run for a fresh developer measured/documented
- [ ] Local setup steps validated and gaps noted in README

**Artifact:** Persona walkthrough notes + working local-run instructions.

---

## Phase 3 — Can I operate it? (the two lead questions)

Answer these *before* deep code study. If either is "no," fixing it is your first priority.

### Observability
- [ ] Logging: what/where (CloudWatch, ELK, etc.), how to search it
- [ ] Metrics & dashboards (CloudWatch, Prometheus/Grafana)
- [ ] Tracing (X-Ray or similar)
- [ ] Alerting: what fires, and **who gets paged**
- [ ] Can I diagnose a prod issue tonight? (yes/no)

### Release & rollback
- [ ] Understood how a change is promoted to prod
- [ ] Understood how to **roll back** a bad release
- [ ] Feature flags in use? Where managed?
- [ ] Trivial safe change deployed end-to-end by me (yes/no)

### Testing & quality gates
- [ ] Test suites present (unit / integration / e2e) and actual coverage
- [ ] Tests run in the pipeline as a **merge gate**?
- [ ] Linting / static analysis / coding standards in place

**Artifact:** "Ops runbook v0" — how to observe, deploy, and roll back.

---

## Phase 4 — Decomposition of the as-built application

### Screens → API mapping
- [ ] Screen-to-API mapping documented
- [ ] API call sequences captured as **sequence diagrams**

### Frontend
- [ ] React version + key dependencies
- [ ] How the frontend is packaged
- [ ] How the frontend is deployed

### Backend (Spring Boot)
- [ ] Spring Boot class composition: Model (POJO) / Service / Repository — implementation details
- [ ] How the app is packaged (JAR?)
- [ ] How it's deployed (container?)
- [ ] How config parameters and secrets are supplied to the app

### Data
- [ ] Persistence: engine (MySQL) — RDS?
- [ ] ERD / schema captured
- [ ] Schema migration mechanism (Flyway / Liquibase?)
- [ ] Backup / restore & point-in-time recovery
- [ ] Seed / reference data
- [ ] Caching layer? (ElastiCache / Redis)

### External integrations
- [ ] Third-party APIs
- [ ] Message queues (SQS / Kafka)
- [ ] Object storage (S3), email/SMS providers, webhooks

**Artifact:** Component map + sequence diagrams + ERD.

---

## Phase 5 — Cross-cutting concerns

### Authentication & authorization
- [ ] AuthN mechanism and IdP used
- [ ] Identity protocol (OAuth2.0 / SAML / OIDC?)
- [ ] RBAC: where groups and group-role associations are created
- [ ] How RBAC selectively exposes functionality by role
- [ ] Is there an administrative UI?

### Broader security posture
- [ ] Encryption in transit and at rest
- [ ] Where secrets actually live (Secrets Manager / Parameter Store / env vars)
- [ ] Dependency vulnerability scanning (Dependabot / Snyk)
- [ ] WAF present?

**Artifact:** Auth flow diagram + secrets/security posture summary.

---

## Phase 6 — Source control & delivery machinery

### Source control
- [ ] Repository confirmed (GitHub) + access levels
- [ ] Branching policy (feature branch?)
- [ ] Pull request process and branch protection rules

### Pipeline
- [ ] Pipeline stages understood
- [ ] AWS auth from pipeline — **push for OIDC over long-lived access keys**
- [ ] SBOM: all dependent modules listed
- [ ] License terms reviewed for each dependency

### Hosting topology (AWS)
- [ ] Compute: EC2 single instance vs multi-AZ
- [ ] Load balancing (ALB?)
- [ ] Auto Scaling Group (ASG?)
- [ ] Account / organization structure
- [ ] Network configuration (VPC, subnets, security groups)
- [ ] Environments: dev / staging / prod and their parity

**Artifact:** Pipeline diagram + hosting/network topology diagram + SBOM.

---

## Phase 7 — Take forward ownership

- [ ] 4th flow: current design, owner, definition of "done", timeline
- [ ] 4th flow treated as your first delivery-risk workstream
- [ ] Risk / tech-debt register populated (known issues, TODOs)
- [ ] Rough AWS cost footprint understood
- [ ] Compliance constraints identified (GDPR / PCI / HIPAA / SOC2 as applicable)
- [ ] Process aligned with team: sprint cadence, Definition of Done, PR review culture
- [ ] Roadmap / next priorities agreed

**Artifact:** Risk register + 4th-flow delivery plan.

---

## Running logs (keep open throughout)

### Questions & Unknowns
| # | Question | Owner to ask | Status | Answer / link |
|---|----------|--------------|--------|---------------|
|   |          |              |        |               |

### Risk / Tech-debt register
| # | Item | Impact | Likelihood | Notes / mitigation |
|---|------|--------|------------|--------------------|
|   |      |        |            |                    |
