# interfaces-to-drawio

Generate a draw.io architecture diagram from a YAML interface registry. The
script reads `interfaces.yaml`, lays out the source/target systems, draws the
interface edges, builds a legend, and emits a single combined notes block at
the bottom.

## Requirements

```bash
pip install pyyaml
```

Python 3.9+ recommended.

## Running

```bash
# Default — writes interfaces.drawio next to the input file
python3 main.py interfaces.yaml

# Custom output path
python3 main.py interfaces.yaml --output diagrams/integration.drawio

# Grid layout instead of the default layered layout
python3 main.py interfaces.yaml --layout grid

# Print a text summary of every interface to stdout
python3 main.py interfaces.yaml --summary
```

### Options

| Flag | Default | Description |
|---|---|---|
| `yaml_file` | required | Path to the YAML interface registry |
| `--output` / `-o` | `<input>.drawio` | Output diagram file path |
| `--layout` | `layered` | `layered`, `grid`, or `auto` (= `layered`) |
| `--summary` | off | Print a per-interface text summary to stdout before writing the file |

## Opening the diagram

- **draw.io desktop**: File → Open
- **draw.io online**: <https://app.diagrams.net> → File → Open from Device
- **VS Code**: install the
  [draw.io extension](https://marketplace.visualstudio.com/items?itemName=hediet.vscode-drawio)
  and open `.drawio` files directly

## Supported values

These are the values the script knows about. Anything else falls back to a
neutral grey/default style — the diagram will still render, but it will not
be colour-coded.

### System / node types (`source.type`, `target.type`)

| Type | Fill | Stroke |
|---|---|---|
| `SaaS` | `#dae8fc` (blue) | `#6c8ebf` |
| `Database` | `#d5e8d4` (green) | `#82b366` |
| `Microservice` | `#fff2cc` (yellow) | `#d6b656` |
| `On-Premise` | `#f8cecc` (red) | `#b85450` |
| `Web Application` | `#e1d5e7` (purple) | `#9673a6` |
| `Shared Drive` | `#ffe6cc` (orange) | `#d79b00` |
| _(any other)_ | `#f5f5f5` (grey) | `#666666` |

### Transport protocols (`transport.protocol`)

The connector line colour is set from the protocol.

| Protocol | Line colour |
|---|---|
| `HTTPS` | `#007bff` |
| `HTTP`  | `#6c757d` |
| `AMQP`  | `#fd7e14` |
| `MQTT`  | `#20c997` |
| `SFTP`  | `#6f42c1` |
| `Kafka` | `#dc3545` |
| `gRPC`  | `#17a2b8` |
| `JDBC`  | `#28a745` |
| `S3`    | `#ffc107` |
| `SMB`   | `#d79b00` |
| `NFS`   | `#b46504` |
| `File`  | `#a0522d` |
| _(any other)_ | `#555555` |

### Direction (`transport.direction`)

| Value | Effect |
|---|---|
| `unidirectional` (default) | One arrowhead, source → target |
| `bidirectional` | Arrowheads on both ends |

### Status (`status`)

Status appears **only inside the connector label** as a coloured marker — it
no longer changes the line colour or stroke style.

| Value | Marker (in label) |
|---|---|
| `active` (default) | `● ACTIVE` (green) |
| `inactive` | `○ INACTIVE` (grey) |
| `broken` | `✖ BROKEN` (red) |

### Frequency (`scheduling.frequency`)

Free-form, but these are the conventional values:

`realtime`, `scheduled`, `event-driven`, `batch`, `manual`, `file-polling`

The value is rendered verbatim after `Schedule: ` in the connector label.

### Authentication / authorization (free-form text)

These render verbatim after `AuthN: ` and `AuthZ: ` in the connector label.
Conventional values:

- `authentication.method`: `OAuth2`, `API_Key`, `Basic`, `Certificate`,
  `SAML`, `None`
- `authorization.model`: `RBAC`, `ABAC`, `ACL`, `None`

### Data format (`data.format`)

Free-form. Rendered verbatim after `Format: ` in the connector label.
Conventional values: `JSON`, `CSV`, `XML`, `Parquet`, `Avro`, `Fixed-Width`,
`Binary`.

## YAML schema

Top-level keys:

```yaml
metadata:                 # optional, ignored by the renderer — useful for
  project: "..."          # humans/readers
  version: "..."
  owner: "..."
  last_updated: "YYYY-MM-DD"

interfaces:               # required; a list of interface objects
  - ...
```

Each entry under `interfaces` accepts:

```yaml
- id: IF-001                          # required, shown in the connector label
  name: "Human-readable name"         # required, shown in the connector label
  description: "Free-form text"       # optional

  status: "active"                    # active | inactive | broken (default: active)

  source:
    system: "Source System Name"      # required
    type: "SaaS"                      # see "System / node types" above
    environment: "Production"         # optional, shown inside the box
    host: "host.example.com"          # optional, shown inside the box
    owner: "Team Name"                # optional, ignored by the renderer

  target:
    system: "Target System Name"      # required
    type: "Database"
    environment: "Production"
    host: "host.example.com"
    owner: "Team Name"

  transport:
    protocol: "HTTPS"                 # see "Transport protocols" above
    port: 443                         # optional
    direction: "unidirectional"       # unidirectional | bidirectional
    # Free-form extras (broker, queue, topic, ...) are allowed but ignored.

  security:
    authentication:
      method: "OAuth2"                # free-form text
      # Any other keys (token_endpoint, header, key_path, ...) are ignored.
    authorization:
      model: "RBAC"                   # free-form text
      roles:                          # optional, ignored by the renderer
        - "etl_service_account"

  data:
    description: "What is transferred"
    entities: ["Account", "Contact"]  # optional, ignored by the renderer
    format: "JSON"
    sensitivity: "PII"                # optional, ignored by the renderer

  scheduling:
    frequency: "scheduled"            # see "Frequency" above
    cron: "0 2 * * *"                 # optional
    timezone: "UTC"                   # optional

  execution:
    container: "etl-salesforce-dwh"   # optional, shown in label as "Execution: <container> / <platform>"
    platform: "Docker"                # optional
    image: "user/image:tag"           # optional, ignored by the renderer
    orchestrator: "Airflow"           # optional, ignored by the renderer

  notes:                              # optional — triggers the bottom notes block
    - "Free-form note line one."
    - "Backfill before cutover."

  tags:                               # optional, ignored by the renderer
    - "etl"
    - "finance"
```

### What appears in the connector label

For each edge the script builds a multi-line, left-aligned label:

```
IF-001: CRM to Data Warehouse ETL  ①
● ACTIVE
Protocol: HTTPS:443
AuthN: OAuth2
AuthZ: RBAC
Format: JSON
Schedule: scheduled
Execution: etl-salesforce-dwh / Docker
```

Lines for `AuthZ`, `Format`, `Schedule`, `Execution` are skipped if the
underlying yaml field is missing. The `①` reference symbol only appears
when the interface has a `notes` list.

### Notes block

Any interface that has a non-empty `notes:` list contributes to a single
yellow rectangular block at the bottom of the diagram. Each contribution is
prefixed by its reference symbol so it can be matched to the connector:

```
Notes

① IF-001 — CRM to Data Warehouse ETL
    - Backfill needed before cutover.
    - Runs nightly at 02:00 UTC.

② IF-002 — Order Service to Notification Service
    - Uses RabbitMQ for delivery guarantees.
```

Reference symbols are assigned in interface order using ①–⑳; beyond 20 the
script falls back to `(21)`, `(22)`, …

### Layout modes

- **`layered`** (default): systems that only appear as a `source` are placed
  in the left column, systems that only appear as a `target` in the right
  column, and systems that appear as both sit in a middle column. Best for
  a left-to-right "data flow" reading.
- **`grid`**: systems are placed left-to-right, top-to-bottom in a uniform
  grid (4 columns by default). Best when the source/target distinction is
  not meaningful.
- **`auto`**: alias for `layered`.

### Legend

The top-right of the diagram shows a legend grouped under one outer
container (so you can move the whole legend as a unit). It currently has
three sections:

1. **System / Node types** — colour swatch + name for every entry in the
   palette table.
2. **Interface status** — coloured `●` / `○` / `✖` next to `Active` /
   `Inactive` / `Broken`.
3. **Interface / Protocol types** — line colour swatch + protocol name for
   every entry in the protocol table.

## Quick start

```bash
pip install pyyaml
python3 main.py interfaces.yaml --summary
```

The included `interfaces.yaml` shows three worked examples (CRM ETL,
order/notification messaging, and an SFTP report extract) covering most of
the supported fields.
