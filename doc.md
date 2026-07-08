# Solution Architecture — Digital Forms and Workflow Solution

*Based on the P200A Architecture Framework outline*

---

## 1. Requirements

This document describes the solution architecture for a digital forms and workflow solution delivered as a Software-as-a-Service (SaaS) offering. The solution enables the organization to digitize paper-based and manual form processes, route submissions through configurable approval workflows, and integrate with enterprise identity and logging services. Refer to P100S for the detailed requirements specification.

## 1.1 System Objectives

- Provide a centralized platform for designing, publishing, and managing digital forms.
- Automate workflow routing, approvals, and escalations for form submissions.
- Reduce manual handling, paper usage, and processing turnaround times.
- Meet all identified functional requirements as validated during solution evaluation.
- Provide a secure, compliant, and highly available service that meets Australian data sovereignty obligations.

## 1.2 System Scope

The system encompasses the SaaS-hosted digital forms and workflow platform, its administrative and end-user interfaces, and its integration points with enterprise services:

- **Users / client groups:** form designers, workflow administrators, approvers, general staff (form submitters), and platform administrators.
- **External systems:** enterprise identity provider (SAML 2.0 IdP), email relay for notifications, and external log aggregation services (e.g., Splunk).
- **Environments:** segregated development, test, and production environments, each with separate access URLs.
- **Boundary:** the vendor operates and maintains the underlying infrastructure, application platform, and scaling; the organization is responsible for configuration, form/workflow design, access governance, and integration endpoints.

## 1.3 Subject Scope

The primary data subjects of the system are:

- **Form definitions and workflow configurations** — organizational intellectual property authored within the platform.
- **Form instances (submissions)** — records created by users, potentially containing personal and business-sensitive information.
- **Workflow history and audit records** — traceability data covering submission lifecycle and user access events.
- **User identity attributes** — provisioned Just-In-Time from the enterprise IdP (name, email, group/role claims).

Relationships to broader organizational subjects (HR records, finance records, case management data) are established via workflow outputs and integrations rather than direct data-store coupling.

## 1.4 Principles

- **SaaS-first:** consume the vendor-managed service; avoid custom infrastructure.
- **Configuration over customization:** prefer native configuration of forms and workflows to code-level customization.
- **Least privilege:** access granted through role-based controls aligned to job function.
- **Sovereignty by design:** all data hosted and processed within Australia.
- **Auditability:** all significant user and workflow actions are logged and exportable.

### 1.4.1 Architecture alignment

Alignment with ACENT and the Enterprise Architecture Roadmap.

**Hosting model: SaaS.** The solution is a vendor-hosted, multi-tenant SaaS offering. The vendor is responsible for platform operations, patching, scaling, and availability under the subscribed SLA.

## 1.5 Identity and Access Management

### 1.5.1.1 WSSO integration

The platform supports **SAML 2.0** federation with the enterprise identity provider, enabling web single sign-on. Users authenticate against the corporate IdP; no separate platform credentials are required for federated users. **Just-In-Time (JIT) provisioning** creates and updates user accounts at first/subsequent login based on SAML assertions, removing the need for manual account creation or directory synchronization.

### 1.5.1.2 Vanity Domain mapping

Each environment is exposed on a separate access URL. Vanity/custom domain mapping can be applied to the production environment to present an organizational domain to end users (subject to vendor DNS/TLS configuration).

### 1.5.2 Authentication

- Primary authentication: SAML 2.0 via the enterprise IdP (inheriting enterprise MFA and conditional access policies).
- JIT provisioning maps IdP attributes to platform user profiles and group membership.
- Local/native accounts are limited to break-glass administrative use only (see 1.5.4).

### 1.5.3 Role-based access control

The platform enforces **RBAC** across its functionality. Permissions to design forms, configure workflows, administer the tenancy, approve submissions, and view reports are assigned via roles rather than to individual users.

#### 1.5.3.1 Application Groups and roles

- Roles are mapped from IdP group claims where possible, keeping access governance in the enterprise directory.
- Indicative roles: Platform Administrator, Form Designer, Workflow Administrator, Approver, Submitter/End User, Report Viewer.
- Role assignment and changes are captured in the user access audit trail (see 1.12.2).

### 1.5.4 Break Glass user

A small number of native (non-federated) emergency access accounts will be maintained to preserve administrative access if the SAML federation is unavailable. Break-glass credentials are vaulted, monitored, and their use is alerted and audited.

## 1.6 Data Persistence

### 1.6.1 Residency control

All customer data is hosted **within Australia**, satisfying data sovereignty requirements. Data at rest, backups, and processing remain within Australian regions; residency is contractually committed by the vendor.

### 1.6.2 Retention and lifecycle management

Form instances and workflow history are retained per configurable retention policies aligned to the organization's records management obligations. Configuration (forms, workflows, settings) can be **exported**, supporting backup of intellectual property, environment promotion, and exit/portability planning.

## 1.7 Security and Compliance

- **Encryption at rest:** all data encrypted with **AES-256**.
- **Encryption in transit:** all connections secured with **TLS 1.2** (or higher).
- **Assurance:** the platform has been **IRAP assessed**, supporting alignment with the Australian Government ISM and PSPF expectations.
- **Least privilege:** access model aligned with the Principle of Least Privilege via RBAC and IdP-governed group membership.
- Audit trails cover user access management and workflow history (see 1.12.2).

## 1.8 Integrations

### 1.8.1 Email Integration

Outbound email notifications (task assignments, approvals, reminders, escalations) are delivered via the platform's email service or the organization's email relay. SPF/DKIM/DMARC alignment will be configured so notifications are trusted and deliverable.

Additional integration capability includes real-time log streaming to external services (see 1.12.2) over secure external connections.

## 1.9 System Scalability

The platform provides **built-in scalability based on load**. As a multi-tenant SaaS, compute and storage scale elastically with demand; the organization does not need to size or provision infrastructure for peak form-submission volumes (e.g., enrolment or end-of-quarter peaks).

## 1.10 System Resilience

### 1.10.1 Disaster Recovery and Backup

Vendor-managed backup and disaster recovery underpin the service. Data is replicated/backed up within Australian regions consistent with residency commitments. Configuration export provides an additional organizational-level safeguard for forms and workflow definitions.

### 1.10.2 AEC, RPO and RTO

- **Uptime SLA:** 99.99% or 99.5%, depending on the subscribed plan.
- **RPO:** 1 minute.
- **RTO:** 4 minutes or 21 minutes, depending on the subscribed plan.

The plan selection should be driven by the criticality assessment of the workflows hosted (recommend the 99.99% / 4-minute RTO tier for business-critical processes).

## 1.11 Customizations

Definition and pipeline management.

The solution is configuration-driven; no code-level customization of the platform is anticipated. Forms and workflows are defined in the **development** environment, validated in **test**, and promoted to **production** using configuration export/import, providing a controlled change pipeline across the segregated environments (each with separate access URLs).

## 1.12 Monitoring and Observability

### 1.12.1 Monitoring

Platform health and availability are monitored by the vendor against the published SLA. The organization monitors service status via vendor status channels and tracks tenancy-level usage and workflow throughput via built-in dashboards.

### 1.12.2 Logging

- The platform maintains an **audit trail of user access management** events (logins, provisioning, role changes) and **workflow history** (submission lifecycle, approvals, escalations).
- Logs can be **streamed in real time to external services such as Splunk** via a secure external connection, enabling integration with the enterprise SIEM for correlation, alerting, and long-term retention.

### 1.12.3 Alerting

Security and operational alerting is implemented in the enterprise SIEM using the streamed logs (e.g., break-glass account use, anomalous access, workflow failures). Vendor-side alerting covers platform availability and incident notification.

## 1.13 Reporting

Built-in reporting provides visibility of form volumes, workflow performance (cycle times, bottlenecks, outstanding approvals), and audit reporting. Data can be exported for analysis in enterprise reporting tools where required.

## 1.14 Support model and SLAs

Vendor support is provided under the subscribed plan with the associated availability SLA (99.99% or 99.5%). Internal Level 1 support handles user queries and access requests; platform issues are escalated to the vendor. Incident, problem, and change processes align with the organization's ITSM framework.

## 1.15 Cost Control

### 1.15.1 Capacity Planning and License Management

Licensing is consumption-based and monitored against:

- **Number of users** (provisioned via JIT — dormant account cleanup keeps license counts accurate).
- **Number of form instances** (submission volumes tracked against plan entitlements).

Usage is reviewed periodically to right-size the subscription tier and forecast growth.

## 1.16 Assumptions, Decisions, Risks and Alternatives

**Assumptions**
- The enterprise IdP supports SAML 2.0 and can release the attributes required for JIT provisioning and role mapping.
- Network connectivity permits secure log streaming from the SaaS platform to the enterprise SIEM.

**Decisions**
- Adopt the SaaS hosting model (no on-premises or IaaS deployment).
- Use SAML 2.0 SSO with JIT provisioning; no directory synchronization.
- Stream audit and workflow logs to Splunk for enterprise-side retention and alerting.

**Risks**
- Vendor lock-in — mitigated by configuration export capability and data export on exit.
- SaaS outage impacts all hosted workflows — mitigated by SLA tier selection (99.99%, 1-min RPO, 4-min RTO) for critical processes.
- Residency or assurance posture could change — mitigated by contractual residency commitments and periodic review of IRAP assessment currency.

**Alternatives considered**
- On-premises/IaaS-hosted forms platform — rejected due to higher operational overhead and slower scalability.
- Custom-built solution — rejected due to cost, time-to-value, and ongoing maintenance burden.

## 1.17 Key Issues

- Confirmation of the appropriate SLA tier (99.99% vs 99.5%) against business criticality and budget.
- Finalization of IdP attribute/claim mapping for JIT provisioning and RBAC group alignment.
- Validation that IRAP assessment scope covers the specific modules and Australian regions to be consumed.
- Agreement on retention periods for form instances and audit data to satisfy records management obligations.
