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