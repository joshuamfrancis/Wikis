# interfaces-to-drawio

Generate draw.io architecture diagrams from a YAML interface registry.

## Requirements

```bash
pip install pyyaml
```

## Usage

```bash
python interfaces_to_drawio.py interfaces.yaml
python interfaces_to_drawio.py interfaces.yaml --output my_diagram.drawio
python interfaces_to_drawio.py interfaces.yaml --layout grid --summary
```

### Options

| Flag | Default | Description |
|---|---|---|
| `yaml_file` | required | Path to the YAML interface file |
| `--output` / `-o` | `<input>.drawio` | Output diagram file path |
| `--layout` | `layered` | `layered` (left→right by role) or `grid` |
| `--summary` | off | Print a summary table to stdout |

## YAML Structure

```yaml
metadata:
  project: "My Project"
  version: "1.0.0"

interfaces:
  - id: IF-001
    name: "Human-readable name"
    description: "What this interface does"

    source:
      system: "Source System Name"
      type: "SaaS | Microservice | On-Premise | Cloud Database | Web Application"
      environment: "Production"
      host: "hostname.example.com"
      owner: "Team Name"

    target:
      system: "Target System Name"
      type: "..."
      environment: "Production"
      host: "hostname.example.com"
      owner: "Team Name"

    transport:
      protocol: "HTTPS | AMQP | MQTT | SFTP | Kafka | gRPC | JDBC | S3"
      port: 443
      direction: "unidirectional | bidirectional"

    security:
      authentication:
        method: "OAuth2 | API_Key | Basic | Certificate | SAML | None"
      authorization:
        model: "RBAC | ABAC | ACL | None"

    data:
      description: "What data is transferred"
      entities: ["Entity1", "Entity2"]
      format: "JSON | CSV | XML | Parquet | Avro | Fixed-Width | Binary"
      sensitivity: "Public | Internal | Confidential | PII | PHI"

    scheduling:
      frequency: "realtime | scheduled | event-driven | batch | manual"
      cron: "0 2 * * *"           # if scheduled
      timezone: "UTC"

    execution:
      container: "container-name"
      image: "dockerhub-user/image:tag"
      platform: "Docker | Kubernetes | Lambda | ECS | Glue | Airflow"
      orchestrator: "Airflow | cron | Kubernetes"

    tags:
      - "etl"
      - "finance"
```

## Node colour coding

| System type | Colour |
|---|---|
| SaaS | Blue |
| Cloud Database | Green |
| Microservice | Yellow |
| On-Premise | Red |
| Web Application | Purple |

## Edge colour coding

Edge colours reflect the transport protocol so you can spot HTTP, SFTP, Kafka, gRPC etc at a glance.

## Opening the diagram

- **draw.io desktop**: File → Open
- **draw.io online**: https://app.diagrams.net → File → Open from Device
- **VS Code**: install the [draw.io VS Code extension](https://marketplace.visualstudio.com/items?itemName=hediet.vscode-drawio) and open `.drawio` files directly
