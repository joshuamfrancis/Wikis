# Oracle APEX — Specialist Interview Questionnaire

*Purpose:* capture the current state of Oracle APEX use across the manufacturing division and gather the input needed to set a strategic direction (continue / contain / consolidate / migrate).

*Audience:* APEX developers, DBAs, solution architects, application owners, and support leads.

*Related:* [Oracle APEX assessment](./oracle-apex.md)

---

## How to use this questionnaire

- **Structure:** 12 sections that widen progressively, from the interviewee, to the app portfolio, to the technical layers, to operations and people, to value and strategy.
- **Core vs probe:** each section has **Core** questions (ask everyone) and **Probe** questions (ask when the interviewee owns that area or a core answer opens a thread).
- **Timing:** about 90 minutes for a full interview. For a 45-minute slot, ask Sections 1–3 and 11–12 in full, plus the Core questions from the sections that match the person's role.
- **Ratings:** where a question asks for a 1–5 rating, use 1 = poor / ad hoc and 5 = strong / fully managed.
- **Evidence:** ask for artefacts as you go (see Appendix A). Facts beat recollection.
- **Tone:** the aim is an honest current state, not an audit. Reassure interviewees that pain points are the most useful answers.

### Role guide

| Role | Prioritise sections |
|---|---|
| APEX developer | 2, 3, 4, 6, 7, 10, 11 |
| DBA / platform | 4, 5, 8, 9 |
| Architect | 3, 4, 5, 6, 7, 12 |
| App owner / business | 2, 3, 11, 12 |
| Support / ops | 8, 9, 10 |

---

## 1. Interviewee context (5 min)

**Core**
1. What is your role, and how long have you worked with APEX here and overall?
2. Which APEX applications do you build, support, or own?
3. Roughly what share of your time goes to APEX: new build, enhancement, support, or upgrades?

**Probe**
4. Which other technologies do you work with (PL/SQL, Java, Python, JavaScript, integration tools)?
5. Have you used APEX at other organisations? How does our use compare?

---

## 2. Application portfolio (10 min)

**Core**
6. How many APEX applications exist today, and how many are actively used?
7. For each major app: what business process does it support, who uses it, and how many users?
8. Which apps are business-critical (production line, quality, supply chain, finance, compliance)?
9. Which apps extend a COTS product (e.g. EBS, a MES, or another Oracle-based system), and which are standalone?
10. Is there a register or catalogue of APEX apps with owners? Who maintains it?

**Probe**
11. Which apps are internal-only and which are used by suppliers, contractors, or plants in other regions?
12. Which apps have not changed in more than 12 months? Are any candidates for retirement?
13. Were any apps built by business users (citizen developers)? How are they governed?
14. Are there duplicate or overlapping apps solving the same problem in different plants or teams?
15. What is the typical size of an app (pages, tables, PL/SQL packages)?

---

## 3. Business value and demand (10 min)

**Core**
16. Why was APEX chosen originally, and do those reasons still hold?
17. What is the typical lead time from request to production for a new APEX app or major change?
18. How does that compare to delivering the same thing in the COTS product, another platform, or custom code?
19. What is the current backlog of APEX requests, and where does demand come from?

**Probe**
20. Can you point to a measurable benefit from an APEX app (time saved, errors reduced, cost avoided)?
21. Have any requests been turned down because APEX couldn't do them well? What were they?
22. How satisfied are users with APEX apps (look and feel, speed, mobile use on the shop floor)?

---

## 4. Platform and versions (10 min)

**Core**
23. Which APEX version(s) and ORDS version(s) are in use, and in which environments?
24. Which Oracle Database versions and editions host APEX? Single instance or RAC? Multitenant (CDB/PDB)?
25. Is APEX installed in one central database, inside each system's own database, or a mix? Why?
26. How many APEX instances and workspaces exist across dev, test, and production?

**Probe**
27. When was APEX last upgraded? How long did it take, and what broke?
28. Is there a defined upgrade and patching cadence (APEX patch set bundles, ORDS, DB RUs)?
29. Which theme is used (Universal Theme / Redwood)? Are any apps on legacy themes?
30. What plug-ins (Oracle or third-party) are used, and who maintains them?
31. Are any end-of-support components still in use (old APEX versions, Apache/mod_plsql, embedded PL/SQL gateway)?

---

## 5. Infrastructure and hosting (10 min)

**Core**
32. Where does each tier run today: databases, ORDS, web server, load balancer (VMware hosts, physical, other)?
33. How is ORDS deployed (standalone, Tomcat, WebLogic, container) and how many nodes?
34. How are TLS certificates, DNS, and load balancing handled for APEX URLs?
35. What are the DR and backup arrangements for APEX databases and ORDS? Have they been tested?

**Probe**
36. What are the current RPO/RTO targets for APEX apps, and are they met?
37. What capacity headroom exists? Any performance problems at peak (shift changes, month-end)?
38. How much database CPU does APEX workload consume? Does it affect licensed cores?
39. Are static files (images, JS, CSS) served from the database, the web server, or a CDN?
40. What would need to change to run this on AWS (RDS for Oracle, EC2, ORDS in containers)? What blockers do you foresee?

---

## 6. Architecture and design practices (10 min)

**Core**
41. Where does business logic live: page processes, PL/SQL packages, triggers, or the COTS product's APIs?
42. Do APEX apps write directly to COTS base tables, or only through supported public APIs/interfaces?
43. How are schemas organised (one per app, shared, parse-as schemas, privileges)?
44. Are there coding standards, naming conventions, or reusable templates? Are they followed?

**Probe**
45. How much custom JavaScript, CSS, or dynamic SQL is used? Where and why?
46. Are there shared components or a master app used across apps (themes, auth, lists of values)?
47. Have COTS upgrades or patches broken APEX apps? What happened?
48. Which apps would be hardest to change or replace, and why?
49. How is reporting done: APEX reports, BI tools, exports to Excel?

---

## 7. Integration (10 min)

**Core**
50. Which systems do APEX apps integrate with? List Oracle and non-Oracle separately.
51. What integration methods are used: DB links, REST (`APEX_WEB_SERVICE`, REST Data Sources), ORDS APIs, files, queues?
52. Does APEX expose any APIs (ORDS) consumed by other systems? Who consumes them?
53. Is integration done point-to-point, or through an enterprise integration platform / API gateway?

**Probe**
54. How are file-based integrations handled (SFTP, shared drives, scheduled jobs)? Who monitors them?
55. How are credentials for outbound calls stored and rotated (wallets, web credentials, DB links)?
56. How are integration failures detected, alerted, and retried?
57. Are there integrations with shop-floor, MES, PLM, or quality systems? What latency is needed?
58. Which integrations are fragile or a frequent source of incidents?

---

## 8. Security, identity, and compliance (10 min)

**Core**
59. How do users sign in to APEX apps: SAML via Ping, LDAP/AD, APEX accounts, database accounts, or a mix?
60. How are roles and authorisation managed (APEX authorisation schemes, AD groups, Ping claims, ACL)?
61. Are any APEX apps or ORDS endpoints reachable from outside the corporate network?
62. Has APEX been included in security reviews or penetration tests? What were the findings?

**Probe**
63. Is session state protection enabled consistently? Are security settings checked (APEX Advisor) before release?
64. Is row-level security used (VPD, Real Application Security) for multi-plant or multi-region data?
65. How are ORDS REST APIs secured (OAuth2 clients, first-party auth, unprotected)?
66. Is data encrypted at rest (TDE) and in transit (TLS to ORDS and to the DB)?
67. What audit logging exists, and does it reach the SIEM?
68. Are there regulatory or customer requirements (e.g. quality records, export controls, SOX) affecting APEX apps?
69. How is privileged access to APEX workspaces and admin services controlled and reviewed?

---

## 9. DevOps, environments, and change management (10 min)

**Core**
70. Is APEX application source stored in GitLab? If so, how is it exported (full export, split export, SQLcl Projects, APEXlang)?
71. How are changes promoted from dev to test to production? Manual import or a GitLab pipeline?
72. Is Git or the development environment the source of truth? Are changes ever made directly in production?
73. How are database objects (tables, packages) versioned and deployed alongside the app?

**Probe**
74. How do multiple developers work on the same app without overwriting each other?
75. What testing exists: PL/SQL unit tests (utPLSQL), UI automation, UAT only?
76. Are code reviews or merge requests used for APEX changes?
77. How long does a typical release take, and how often do rollbacks happen?
78. Rate 1–5: source control, automated deployment, automated testing, environment consistency.
79. Have you looked at APEXlang or SQLcl Projects? What would it take to adopt them?

---

## 10. Operations and support (5 min)

**Core**
80. How are APEX apps monitored (availability, performance, errors)?
81. What is the incident volume for APEX apps, and what are the most common causes?
82. Who provides support out of hours, and is there an on-call arrangement?

**Probe**
83. Are there runbooks for common issues (ORDS restarts, session issues, upgrades)?
84. Do you have Oracle Support access for APEX issues, and how often is it used?
85. How is APEX performance tuned (debug logs, AWR, activity log)?

---

## 11. People, skills, and sourcing (5 min)

**Core**
86. How many people can build and support APEX apps today, and where are they (internal, partner, offshore)?
87. Which apps depend on a single person's knowledge?
88. How easy is it to hire or contract APEX skills in our locations?

**Probe**
89. What training or certification has the team done? What gaps exist (security, JavaScript, REST, DevOps, AI features)?
90. Is documentation good enough for someone new to take over an app?
91. Would developers from the Python/Java teams be willing and able to pick up APEX, or vice versa?

---

## 12. Pain points, opportunities, and strategy (15 min)

**Core**
92. What are the top three things that work well with APEX here?
93. What are the top three problems or frustrations?
94. If you could change one thing about how APEX is used, governed, or hosted, what would it be?
95. Which types of requirements should go to APEX in future, and which should not?
96. How would moving to AWS change your view of APEX: opportunity, risk, or neutral?
97. Which strategy would you recommend, and why?
    - **Continue and invest:** grow APEX as the standard extension platform with stronger governance and DevOps.
    - **Contain:** keep existing apps, limit new build to defined use cases.
    - **Consolidate:** reduce instances and apps onto a central hub.
    - **Migrate away:** replace with another low-code platform or custom/container apps over time.

**Probe**
98. Are there newer APEX features (AI, workflow, APEXlang, vector search) you'd like to use but can't?
99. Which apps would you migrate first if the decision were to move off APEX, and which last?
100. What risks do you see in each strategy option for the business and the team?
101. Who else should we interview?
102. Is there anything we haven't asked that we should have?

---

## Appendix A — Evidence to request

| Item | Source |
|---|---|
| List of APEX instances, workspaces and apps (with last-modified dates) | `APEX_APPLICATIONS`, `APEX_WORKSPACES` views |
| Usage statistics per app (users, page views over 90 days) | `APEX_WORKSPACE_ACTIVITY_LOG` |
| APEX, ORDS and DB versions per environment | `APEX_RELEASE`, ORDS config, `V$INSTANCE` |
| Authentication and authorisation schemes per app | `APEX_APPLICATION_AUTH`, `APEX_APPLICATION_AUTHORIZATION` |
| Outbound network ACLs and web credentials | `DBA_HOST_ACES`, `APEX_WORKSPACE_CREDENTIALS` |
| DB links and remote dependencies | `DBA_DB_LINKS` |
| ORDS REST modules and privileges | `USER_ORDS_MODULES`, `USER_ORDS_PRIVILEGES` |
| Infrastructure diagram, DR plan and last DR test result | Platform team |
| GitLab repos and pipelines for APEX | GitLab |
| Incident and change records for APEX apps (12 months) | ITSM tool |
| Security review and pen-test reports | Security team |
| APEX Advisor results for critical apps | App Builder > Utilities > Advisor |

---

## Appendix B — Interview capture sheet

| Field | Notes |
|---|---|
| Interviewee / role | |
| Date / interviewer | |
| Apps owned or supported | |
| Key facts captured | |
| Ratings (Q78) | Source control: _ Deployment: _ Testing: _ Environments: _ |
| Top 3 strengths | |
| Top 3 pain points | |
| Recommended strategy (Q97) | |
| Risks raised | |
| Evidence requested / received | |
| Follow-ups and further interviewees | |

---

## Appendix C — Synthesis framework

After the interviews, score each dimension 1–5 from the combined evidence. This becomes the current-state baseline and feeds the strategy decision.

| Dimension | Questions | Score | Key finding |
|---|---|---|---|
| Portfolio clarity and governance | 6–15 | | |
| Business value and delivery speed | 16–22 | | |
| Platform currency and patching | 23–31 | | |
| Infrastructure resilience and cloud readiness | 32–40 | | |
| Architecture quality and COTS coupling | 41–49 | | |
| Integration maturity | 50–58 | | |
| Security and compliance | 59–69 | | |
| DevOps maturity | 70–79 | | |
| Operations and support | 80–85 | | |
| Skills and key-person risk | 86–91 | | |

**Reading the scores:** strong value (3–5) with weak engineering (DevOps, security, governance) points to *continue and invest*. Weak value plus high key-person risk points to *contain* or *migrate*. Many instances and duplicate apps point to *consolidate*.
