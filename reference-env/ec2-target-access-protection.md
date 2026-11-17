# Protecting EC2 Target Instances from Direct Access

Design summary: target EC2 instances are reachable only from the designated jump servers in their own account, or from the GitLab pipeline job execution environment. Every other path is closed.

Related: [jumphosts.md](jumphosts.md), [jumpserver.md](jumpserver.md).

---

## 1. Scope and requirements

- EC2 instances are created **without key pairs**.
- Each account has jump servers. Administrators reach them with SSM Session Manager (Linux) or Fleet Manager RDP (Windows), after activating access through Entra ID PIM.
- From a jump server, administrators connect to target instances by SSM session or RDP.
- The GitLab pipeline connects to target instances for deployment and configuration. Runners are EC2 instances with the Docker executor, in a VPC in a dedicated deployment account.
- **Goal:** nobody and nothing reaches a target instance except through a jump server or a pipeline job.

## 2. The key point

Security groups alone cannot meet the goal. SSM sessions and Run Command do not use an inbound network path (the SSM agent dials out), so any principal holding `ssm:StartSession` or `ssm:SendCommand` on a target can bypass the jump server entirely. The design therefore needs three layers: network, IAM, and SCP guardrails.

## 3. Access paths

```mermaid
flowchart LR
    subgraph ID["Identity"]
        ADMIN["Administrator"]
        PIM["Entra ID PIM"]
        IDC["IAM Identity Center<br/>admin permission set"]
    end

    subgraph DEP["Deployment account"]
        subgraph RVPC["Runner VPC"]
            RUNNER["GitLab runner EC2<br/>Docker executor"]
            STSVPCE["STS VPC endpoint"]
        end
    end

    subgraph WL["Workload account"]
        ROLE["gitlab-deploy role"]
        SSM["Systems Manager"]
        subgraph VPC["Workload VPC, private subnets"]
            JUMP["Jump server<br/>AccessTier=jump"]
            TARGET["Target EC2<br/>AccessTier=target<br/>no key pair, no public IP"]
        end
    end

    ADMIN --> PIM --> IDC
    IDC -->|"StartSession or Fleet Manager RDP"| SSM
    SSM -->|"session"| JUMP
    JUMP -->|"RDP 3389 or SSH 22, SG reference"| TARGET
    JUMP -->|"SSM session via VPC endpoint"| TARGET

    RUNNER -->|"job OIDC token"| STSVPCE
    STSVPCE -->|"AssumeRoleWithWebIdentity"| ROLE
    ROLE -->|"SendCommand, named documents"| SSM
    SSM -->|"Run Command"| TARGET

    IDC -.->|"direct access denied by IAM and SCP"| TARGET
```

Editable draw.io version of this diagram: [ec2-target-access-protection.drawio](ec2-target-access-protection.drawio).

## 4. Layer 1: Network (RDP, SSH, WinRM)

- Targets sit in private subnets with no public IP and no key pair.
- The target security group allows inbound 3389/22 **only from the jump server security group** in the same account (security group reference, not CIDR).
- No inbound rule exists for the pipeline. It uses SSM Run Command, so no network path is needed between the runner VPC and the workload VPCs.

## 5. Layer 2: IAM (SSM sessions and commands)

Instances are tagged `AccessTier=jump` or `AccessTier=target`. Policies use the `ssm:resourceTag/AccessTier` condition.

| Principal | Allowed |
|---|---|
| Admin permission set (activated via PIM) | `ssm:StartSession` and Fleet Manager RDP on `jump` instances only |
| Jump to target hop | See the two options below |
| `gitlab-deploy` role (one per workload account) | `ssm:SendCommand` with named documents on `target` instances only |

**Jump to target, two options:**

1. **Jump instance role** holds `ssm:StartSession` on `target` instances. Simple, but sessions are recorded as the instance role rather than the individual user.
2. **Administrator's own role** may start target sessions only when the request arrives through the account's SSM interface endpoint (`aws:SourceVpce`). The call must then originate inside the VPC, and per-user attribution is kept.

**Pipeline identity chain:**

- The GitLab job presents an OIDC ID token and calls `AssumeRoleWithWebIdentity` for `gitlab-deploy` in the target account.
- The role trust policy pins the token `sub` claim to a specific project and protected branch, so only that pipeline can deploy.
- The trust policy also requires `aws:SourceVpce` to be the STS endpoint in the runner VPC, so the role can only be assumed from the job execution environment.
- The runner's own instance role holds no deployment rights.

**Runner settings that protect this chain (Docker executor):**

- `privileged = false`, and the Docker socket is never mounted into jobs.
- Host networking is not allowed, and the IMDSv2 hop limit is 1, so job containers cannot read the instance role credentials.
- Deploy runners are registered as protected runners, usable only by protected branches and environments.

## 6. Layer 3: SCP guardrails

These stop layers 1 and 2 from being undone inside an account.

- Deny `ssm:StartSession` and `ssm:SendCommand` on `target` instances unless `aws:PrincipalArn` is the jump role or `gitlab-deploy`.
- Deny the side doors: EC2 Instance Connect, EC2 serial console, and `ec2:GetPasswordData`.
- Deny `ec2:RunInstances` on resource `arn:aws:ec2:*:*:key-pair/*`, which blocks launching with any key pair.
- Deny changes to the `AccessTier` tag, the target security groups, and the two exempt roles, except by the account provisioning role. Without this, an administrator could retag a target as a jump server or create a look-alike role.

## 7. Resulting access matrix

| Path to target | Outcome | Enforced by |
|---|---|---|
| Administrator, direct SSM session or RDP | Blocked | IAM, SCP, security group |
| Administrator, via jump server | Allowed | Security group reference, IAM |
| GitLab job, via `gitlab-deploy` | Allowed | OIDC trust policy, IAM |
| Any other role | Blocked | SCP |
| Any other network source | Blocked | Security group |
| SSH with key pair, Instance Connect, serial console | Blocked | No key pair, SCP |

## 8. Detection

- Session Manager logs go to S3 or CloudWatch Logs.
- CloudTrail alert on any `StartSession` or `SendCommand` against a `target` instance from a principal other than the jump role or `gitlab-deploy`.
- CloudTrail alert on changes to the `AccessTier` tag or the target security groups.

## 9. Open decisions

- Which jump-to-target option to use (section 5). Option 2 is preferred if per-user audit is required.
- Whether any workload needs direct network access from the pipeline (WinRM, SSH, Ansible). That would need Transit Gateway or peering from the runner VPC and a CIDR-based security group rule on targets, and it weakens the "no inbound path from outside the account" property.
- For self-managed GitLab, AWS must be able to reach the OIDC discovery and JWKS endpoints publicly for `AssumeRoleWithWebIdentity` to work.
