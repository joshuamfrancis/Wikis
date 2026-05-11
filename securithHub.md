# Security Hub — Nested Landing Zone Aggregation

**Pattern:** EventBridge cross-account bus  
**Constraint:** AWS Organizations permits only one Security Hub delegated admin per region — this pattern provides NLZ-scoped aggregation without conflicting with the org-wide admin.

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│  AWS Organization — Org-Wide Security Hub                       │
│                                                                 │
│  ┌──────────────────┐    ┌────────────────────────────────────┐ │
│  │ Management Acct  │    │ Central Security Account           │ │
│  │                  │    │  • Security Hub (Delegated Admin)  │ │
│  │  • Delegated     │    │  • EventBridge (org bus)           │ │
│  │    Admin Policy  │    │  • Aggregates ALL org findings     │ │
│  └──────────────────┘    └────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────┘
                              ↕
┌─────────────────────────────────────────────────────────────────┐
│  Nested Landing Zone OU — Member Accounts                       │
│                                                                 │
│  ┌────────────────┐  ┌────────────────┐  ┌──────────────────┐  │
│  │ NLZ Account A  │  │ NLZ Account B  │  │ NLZ Account N…   │  │
│  │                │  │                │  │                  │  │
│  │ • Security Hub │  │ • Security Hub │  │ • Security Hub   │  │
│  │   (member)     │  │   (member)     │  │   (member)       │  │
│  │ • EventBridge  │  │ • EventBridge  │  │ • EventBridge    │  │
│  │   (local bus)  │  │   (local bus)  │  │   (local bus)    │  │
│  │ • IAM Resource │  │ • IAM Resource │  │ • IAM Resource   │  │
│  │   Policy →     │  │   Policy →     │  │   Policy →       │  │
│  │   Hub Acct     │  │   Hub Acct     │  │   Hub Acct       │  │
│  └───────┬────────┘  └───────┬────────┘  └────────┬─────────┘  │
│          └──────────────────┬┘───────────────────┘            │
│                             │ PutEvents (cross-account)        │
└─────────────────────────────┼───────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│  NLZ Hub Account — Custom Aggregation Layer                     │
│                                                                 │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │ Custom EventBus: "nlz-secfindings"                       │   │
│  │  • Receives cross-account events from NLZ accounts only  │   │
│  │  • Resource policy scoped to NLZ OU via OrgPaths         │   │
│  └───────────────────────────┬──────────────────────────────┘   │
│                              │                                  │
│         ┌────────────────────┼─────────────────┐               │
│         ▼                    ▼                  ▼               │
│  ┌─────────────┐   ┌──────────────────┐  ┌──────────────────┐  │
│  │ EventBridge │   │ Lambda           │  │ Kinesis Firehose │  │
│  │ Rule        │──▶│ (optional)       │─▶│ (optional)       │  │
│  │             │   │ • Enrich/transform│  │ • Batch/buffer   │  │
│  │ Match all   │   │ • Tag with OU    │  │ • Parquet convert│  │
│  │ SH findings │   │ • Filter noise   │  │ • Partition by   │  │
│  └─────────────┘   │ • Alert critical │  │   account/date   │  │
│                    └──────────────────┘  └────────┬─────────┘  │
│                                                   ▼            │
│                                          ┌──────────────────┐  │
│                                          │ S3 Bucket        │  │
│                                          │ findings/        │  │
│                                          │   year=YYYY/     │  │
│                                          │   month=MM/      │  │
│                                          │   account=<id>/  │  │
│                                          └──────────────────┘  │
│                                                   │            │
│                              ┌────────────────────┘            │
│                              ▼                                  │
│                    ┌──────────────────────────────────────┐    │
│                    │ Glue Crawler → Athena → QuickSight   │    │
│                    │ NLZ-scoped dashboards & queries       │    │
│                    └──────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────────┘
```

---

## Event Flow

### 1. Source Account (each NLZ member account)

Each NLZ workload account has an EventBridge rule that captures Security Hub findings and forwards them cross-account to the NLZ Hub Account custom bus.

**EventBridge Rule — event pattern:**

```json
{
  "source": ["aws.securityhub"],
  "detail-type": ["Security Hub Findings - Imported"]
}
```

**EventBridge Rule — target:**

```
Target ARN: arn:aws:events:<region>:<nlz-hub-account-id>:event-bus/nlz-secfindings
Role:       arn:aws:iam::<source-account-id>:role/eb-cross-account-role
```

> **Note:** The rule has two targets — the NLZ hub bus for scoped aggregation, plus the org-wide Security Hub flow continues natively. Do not intercept the org-wide path.

---

### 2. NLZ Hub Account — Custom Bus Resource Policy

The custom event bus in the hub account permits `events:PutEvents` scoped to the NLZ OU only. New accounts added to the OU automatically inherit access without any policy changes.

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowNLZOUAccounts",
      "Effect": "Allow",
      "Principal": "*",
      "Action": "events:PutEvents",
      "Resource": "arn:aws:events:<region>:<nlz-hub-account-id>:event-bus/nlz-secfindings",
      "Condition": {
        "StringLike": {
          "aws:PrincipalOrgPaths": "o-<org-id>/r-<root-id>/ou-<nlz-ou-id>/*"
        }
      }
    }
  ]
}
```

---

### 3. Hub Account — Processing Pipeline

| Stage | Service | Purpose |
|---|---|---|
| Ingest | EventBridge custom bus | Receive findings from all NLZ accounts |
| Route | EventBridge rule | Match all SH findings; fan-out to targets |
| Enrich *(optional)* | Lambda | Tag with OU path, normalize severity, suppress false positives, forward criticals to SNS |
| Buffer *(optional)* | Kinesis Data Firehose | Batch, buffer, convert to Parquet |
| Store | S3 | Partitioned findings store |
| Query | Glue + Athena | Partition-pruned SQL queries |
| Visualize | QuickSight | NLZ-scoped security dashboards |

---

## IAM Requirements

### Source Account — Cross-Account Role

Each NLZ source account needs an IAM role that EventBridge can assume to call `PutEvents` on the hub account bus.

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "events:PutEvents",
      "Resource": "arn:aws:events:<region>:<nlz-hub-account-id>:event-bus/nlz-secfindings"
    }
  ]
}
```

**Trust policy** — allow EventBridge service to assume the role:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": { "Service": "events.amazonaws.com" },
      "Action": "sts:AssumeRole"
    }
  ]
}
```

---

## S3 Partition Structure

```
s3://nlz-secfindings-bucket/
  findings/
    year=2025/
      month=06/
        account=111122223333/
          findings-<timestamp>.json.gz
        account=444455556666/
          findings-<timestamp>.json.gz
```

Enable a Glue Crawler on the `findings/` prefix. Athena queries stay cheap through partition pruning — filter by `account`, `year`, or `month` to avoid full-bucket scans.

Enable **S3 Object Lock** in Compliance mode if retention is required for audit purposes.

---

## Lambda Enrichment (Optional)

The Lambda enrichment function sits between EventBridge and Firehose/S3. Recommended transformations:

- Add `ou_path`, `account_alias`, and `environment` tags to each finding
- Normalize ASFF `Severity.Label` to internal severity tiers (e.g., `P1`/`P2`/`P3`)
- Suppress known false-positive finding types by `Types` field
- Forward `CRITICAL` and `HIGH` findings to SNS → PagerDuty / Slack

```python
import json
import boto3

sns = boto3.client('sns')

SUPPRESSED_TYPES = [
    "Software and Configuration Checks/AWS Security Best Practices/Runtime Behavior Analysis"
]

def handler(event, context):
    finding = event['detail']['findings'][0]

    # Enrich
    finding['UserDefinedFields'] = {
        'ou_path':      'o-xxxx/r-xxxx/ou-nlz-xxxx',
        'environment':  'nlz-production',
        'account_alias': get_account_alias(finding['AwsAccountId'])
    }

    # Suppress
    if any(t in finding.get('Types', []) for t in SUPPRESSED_TYPES):
        return {'statusCode': 200, 'body': 'suppressed'}

    # Alert on critical
    if finding['Severity']['Label'] in ('CRITICAL', 'HIGH'):
        sns.publish(
            TopicArn='arn:aws:sns:<region>:<account>:nlz-security-alerts',
            Message=json.dumps(finding),
            Subject=f"[{finding['Severity']['Label']}] {finding['Title']}"
        )

    return finding
```

---

## Deployment — CloudFormation StackSets

Deploy the EventBridge rule and IAM role to all NLZ accounts automatically using a StackSet targeting the NLZ OU. New accounts that join the OU receive the rule without manual intervention.

```yaml
# stackset-nlz-eb-rule.yaml
AWSTemplateFormatVersion: '2010-09-09'
Description: NLZ Security Hub findings forwarding rule

Parameters:
  NLZHubAccountId:
    Type: String
  NLZHubBusArn:
    Type: String

Resources:

  CrossAccountRole:
    Type: AWS::IAM::Role
    Properties:
      RoleName: eb-nlz-secfindings-cross-account
      AssumeRolePolicyDocument:
        Version: '2012-10-17'
        Statement:
          - Effect: Allow
            Principal:
              Service: events.amazonaws.com
            Action: sts:AssumeRole
      Policies:
        - PolicyName: PutEventsToNLZBus
          PolicyDocument:
            Version: '2012-10-17'
            Statement:
              - Effect: Allow
                Action: events:PutEvents
                Resource: !Ref NLZHubBusArn

  SecurityHubForwardingRule:
    Type: AWS::Events::Rule
    Properties:
      Name: nlz-securityhub-to-hub-account
      Description: Forward Security Hub findings to NLZ Hub Account aggregation bus
      EventPattern:
        source:
          - aws.securityhub
        detail-type:
          - Security Hub Findings - Imported
      State: ENABLED
      Targets:
        - Id: NLZHubBus
          Arn: !Ref NLZHubBusArn
          RoleArn: !GetAtt CrossAccountRole.Arn
          DeadLetterConfig:
            Arn: !GetAtt DLQ.Arn

  DLQ:
    Type: AWS::SQS::Queue
    Properties:
      QueueName: nlz-eb-secfindings-dlq
      MessageRetentionPeriod: 1209600  # 14 days
```

**Deploy via AWS CLI targeting the NLZ OU:**

```bash
aws cloudformation create-stack-set \
  --stack-set-name nlz-securityhub-forwarding \
  --template-body file://stackset-nlz-eb-rule.yaml \
  --parameters \
      ParameterKey=NLZHubAccountId,ParameterValue=<hub-account-id> \
      ParameterKey=NLZHubBusArn,ParameterValue=arn:aws:events:<region>:<hub-account-id>:event-bus/nlz-secfindings \
  --capabilities CAPABILITY_NAMED_IAM \
  --permission-model SERVICE_MANAGED \
  --auto-deployment Enabled=true,RetainStacksOnAccountRemoval=false

aws cloudformation create-stack-instances \
  --stack-set-name nlz-securityhub-forwarding \
  --deployment-targets OrganizationalUnitIds=ou-<nlz-ou-id> \
  --regions us-east-1
```

---

## Key Design Decisions

| Decision | Rationale |
|---|---|
| `aws:PrincipalOrgPaths` condition | Scopes bus access to NLZ OU; new accounts auto-inherit without policy updates |
| Two EventBridge targets per source account | NLZ hub aggregation runs in parallel — org-wide Security Hub flow is not intercepted |
| Dead-letter queue on EB rule | Captures failed `PutEvents` calls for replay; prevents silent finding loss |
| Firehose over direct Lambda→S3 | Handles batching, retry, and Parquet conversion without custom code |
| StackSet with `SERVICE_MANAGED` + auto-deploy | New accounts in the OU receive the rule automatically via AWS Organizations integration |

---

## What This Does NOT Conflict With

- The org-wide Security Hub delegated admin in the Central Security Account remains intact
- NLZ accounts stay as standard Security Hub members — no separate Security Hub admin designation
- The Central Security Account continues to aggregate findings from all accounts including NLZ
- No Security Hub configuration changes are required in any account

---

## Services Referenced

| Service | Role |
|---|---|
| AWS Security Hub | Finding generation (member accounts) and org-wide aggregation (central account) |
| Amazon EventBridge | Cross-account event routing from NLZ accounts to hub account |
| AWS Lambda | Optional finding enrichment, filtering, and alerting |
| Amazon Kinesis Data Firehose | Optional buffering, batching, and format conversion |
| Amazon S3 | Findings storage with time/account partitioning |
| AWS Glue | Schema discovery and partition management |
| Amazon Athena | SQL queries over partitioned findings |
| Amazon QuickSight | NLZ-scoped security dashboards |
| AWS CloudFormation StackSets | Automated rule deployment across NLZ OU accounts |
| Amazon SQS | Dead-letter queue for failed EventBridge deliveries |
