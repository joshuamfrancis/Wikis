# Software Catalogue — Queryable & Extensible Layer

## Design Document

---

## 1. Problem Statement

The organization maintains a catalogue of software applications and their metadata (description, actively-used flag, etc.) in a dedicated catalogue application. That system has two limitations:

1. **Weak search** — it cannot filter applications by arbitrary combinations of attributes.
2. **Rigid schema** — it does not easily support adding new attributes.

The goal is a catalogue that is **queryable** (combinations of attributes joined by `AND` / `OR`), **extensible** (custom attributes beyond what the source provides), and **updatable** (users can supply and maintain the extra attributes), without modifying the source system.

---

## 2. Solution Overview

The approach layers a queryable, enrichable store on top of the existing catalogue rather than altering the source:

1. **Replicate** the source catalogue into a dedicated database via periodic ETL.
2. **Extend** the replicated data with an extension table holding custom attributes.
3. **Unify** both tables through a database view that resolves overlapping attributes.
4. **Expose** the data through a REST API consumed by a user interface for query, administration, and attribute maintenance.
5. **Host** the application in containers.

```
+---------------------+        ETL         +-----------------------------+
|  Source Catalogue   | -----------------> |   Catalogue Database        |
|  (rigid, weak       |   (periodic,       |                             |
|   search)           |    upsert)         |   +---------------------+   |
+---------------------+                    |   |  base_application   |   |
                                           |   +---------------------+   |
                                           |   +---------------------+   |
                                           |   | extension_attributes|   |
                                           |   +---------------------+   |
                                           |   +---------------------+   |
                                           |   |  v_application      |   |
                                           |   |  (unified view)     |   |
                                           |   +---------------------+   |
                                           +--------------+--------------+
                                                          |
                                                   REST API (search,
                                                   read, update)
                                                          |
                                                  +-------+-------+
                                                  |  UI Application|
                                                  |  (containerized)|
                                                  +---------------+
```

---

## 3. Component Design

### 3.1 ETL — Periodic Replication

A scheduled job copies the source catalogue into the local `base_application` table.

- **Cadence:** Batch on a schedule appropriate to how often the source changes (e.g. nightly). Software catalogues change slowly, so near-real-time is generally unnecessary.
- **Idempotency:** The job upserts on the application's **stable natural key** (its identifier in the source system). Re-running the job is always safe.
- **Boundary:** ETL writes **only** to `base_application`. It never touches the extension table, so re-runs cannot clobber user-supplied attributes.

### 3.2 Extension Table — Custom Attributes

A separate table, keyed by the source application's stable ID, holds attributes the source system does not provide.

- Keeping custom attributes physically separate from replicated data means an ETL overwrite of the base table leaves enrichment data untouched.
- **Recommended shape:** a wide table of known custom columns, plus an optional `JSONB` column for overflow attributes added later. This supports multi-attribute `AND`/`OR` filtering far better than a pure entity-attribute-value (EAV) model, which forces a self-join per filter condition.
- **Audit trail:** include `created_by`, `created_at`, `updated_by`, `updated_at` so the provenance of every custom attribute is known.

### 3.3 Unified View — Source System Wins on Overlap

A view joins `base_application` and `extension_attributes` and presents a single queryable surface.

**Precedence decision:** the **source system attribute overrides** the extension when both are populated. The extension can therefore only:

- **fill gaps** — supply a value where the source has none, and
- **add net-new attributes** the source does not have.

The extension can never contradict a populated source field, which keeps the source authoritative.

Implemented with `COALESCE`, source first:

```sql
CREATE VIEW v_application AS
SELECT
    b.app_id,
    b.name,
    COALESCE(b.description,   e.description)   AS description,
    COALESCE(b.actively_used, e.actively_used) AS actively_used,
    -- net-new attributes that exist only in the extension:
    e.business_owner,
    e.cost_centre,
    e.review_date,
    e.custom_attributes            -- JSONB overflow
FROM base_application b
LEFT JOIN extension_attributes e ON e.app_id = b.app_id;
```

> **Known consequence:** if the source holds a *wrong* value, the UI cannot correct it through the extension, because the source always wins. If this ever becomes a problem, the escape hatch is an explicit `override` flag column on the extension row that the view checks before falling back to the source. This is intentionally **not** built now — base-wins-via-COALESCE is the agreed model.

### 3.4 REST API

The view is exposed through REST endpoints. REST keeps the backend reusable for future consumers (CLI, scheduled reports, other apps).

| Concern | Endpoint | Notes |
|---|---|---|
| Complex query | `POST /applications/search` | Accepts a structured filter tree in the body (see §4). POST-for-read is the standard workaround for arbitrary boolean filters. |
| Simple read | `GET /applications/{app_id}` | Single application by ID. |
| Update attributes | `PATCH /applications/{app_id}/extension` | Writes **only** to the extension table. |

**Hard rules:**

- Filter trees are validated server-side and translated to **parameterized SQL** — user filter input is never concatenated into a query string.
- Writes target the **extension table only**. The UI must prevent edits to base attributes, since ETL would overwrite them on the next sync.

### 3.5 User Interface

A single application covering three responsibilities, which carry **distinct authorization scopes** even though they share one codebase:

| Responsibility | Risk profile | Scope |
|---|---|---|
| Query the catalogue | Read-only, low risk | Viewer |
| Maintain the app (SSO, config) | Administrative | Admin |
| Update catalogue attributes | Audited write path | Editor |

Keeping these as separate scopes from day one avoids a painful retrofit of "who can edit vs. who can only view."

**SPA vs. server-rendered:** an SPA (e.g. React/Vue) backed by the REST API is the conventional fit for an interactive filter-and-edit tool and is a sound choice. For an internal tool in a Python-centric team, a server-rendered option (FastAPI + HTMX) delivers comparable interactivity with fewer moving parts (no separate frontend toolchain, simpler server-side auth). Either is valid; the REST API design is unchanged regardless of which is chosen.

**Authentication:** SSO via OIDC against the organization's identity provider.

### 3.6 Hosting

The application runs as a **container**, keeping the build and deployment workflow consistent (image-based, portable). The same image runs whether deployed to a VM or a managed container service, so the hosting substrate can change later without rebuilding the application.

---

## 4. Query Filter Model (AND / OR)

The headline requirement — arbitrary combinations of attributes joined by `AND`/`OR` — is handled by a structured filter tree sent to `POST /applications/search`. The tree has two node kinds:

- **Leaf:** `{ "field": "...", "op": "...", "value": ... }`
- **Branch:** `{ "and": [ ... ] }` or `{ "or": [ ... ] }`

Example — *(actively used) AND (owned by Finance OR cost centre = 4400)*:

```json
{
  "and": [
    { "field": "actively_used", "op": "eq", "value": true },
    {
      "or": [
        { "field": "business_owner", "op": "eq", "value": "Finance" },
        { "field": "cost_centre",    "op": "eq", "value": "4400" }
      ]
    }
  ]
}
```

The server walks this tree, validates each field and operator against an allow-list, and builds a parameterized `WHERE` clause against `v_application`.

---

## 5. Design Decisions Summary

| Decision | Choice | Rationale |
|---|---|---|
| Where to add custom attributes | Separate extension table | Survives ETL overwrites; no source modification. |
| Extension table shape | Wide columns + JSONB overflow | Friendlier to multi-attribute AND/OR filtering than EAV. |
| Overlap precedence | **Source system wins** (`COALESCE(base, extension)`) | Keeps source authoritative; extension is purely additive. |
| Query transport | `POST /search` with filter tree | Clean handling of arbitrary boolean filters. |
| SQL safety | Parameterized queries only | Prevents injection from user filter input. |
| API style | REST | Reusable backend for future consumers. |
| UI style | SPA or FastAPI+HTMX | Both viable; HTMX lower-friction for a Python team. |
| Authorization | Separate viewer / editor / admin scopes | Avoids retrofitting access control later. |
| Hosting | Containers | Portable, consistent workflow. |

---

## 6. Open Items / Future Considerations

- **Override capability:** add an `override` flag to the extension if correcting wrong source values ever becomes necessary (currently out of scope by design).
- **ETL freshness:** revisit cadence if the source catalogue begins changing more frequently than the batch interval.
- **Audit reporting:** the extension audit columns enable a "what changed, by whom" report if governance requires it.

---

## 7. Variation — Power BI as the Query Surface

This variation replaces the custom-developed query UI with **Power BI**, while keeping the entire data layer (ETL, base table, extension table, unified view) unchanged. It is a strong fit because the headline requirement — filtering by combinations of attributes with `AND`/`OR` — is native Power BI functionality.

### 7.1 What Power BI Covers

| UI Responsibility | Power BI? | Notes |
|---|---|---|
| Query the catalogue | **Yes** | Slicers, filter pane, and visual-level filters give point-and-click AND/OR filtering. Complex boolean logic via DAX. No filter DSL or search endpoint needed. |
| Authentication / SSO | **Yes** | Native integration with Entra ID (the org IdP). |
| Update catalogue attributes | **No** | Power BI is read-only by design. Requires a separate write mechanism (see §7.3). |

### 7.2 Connection to the Data Layer

Power BI connects directly to the **`v_application`** view. The source-wins `COALESCE` precedence stays in the database, so Power BI sees one clean, unified table and never needs to know about the base-vs-extension split.

**Connection mode matters:**

- **Import mode** — caches a snapshot, fast, but refreshed on a schedule. Stacks a second layer of staleness on top of the periodic ETL; a user's edit may not appear until the next Power BI refresh.
- **DirectQuery mode** — queries the view live, so ETL updates and edits appear immediately, at the cost of higher database load and slightly slower interactivity.

For a slowly-changing catalogue, Import mode with a sensible refresh schedule is usually adequate; choose DirectQuery if "I edited it but can't see my change yet" is unacceptable.

### 7.3 The Write Path (Power BI's Gap)

Because Power BI cannot write back, the **update attributes** responsibility needs one of:

- **Power Apps embedded in Power BI** — a Power Apps visual on the report page can write back. Most "native Microsoft stack" option, but introduces Power Platform (and likely Dataverse), its own licensing/learning curve, and sits off the preferred AWS/Python/container stack.
- **Minimal standalone write surface** — a small FastAPI + HTMX edit form that writes **only** to the extension table. Far smaller than the original full UI (write path only, no search UI), and stays in the preferred stack.
- **Indirect write** — edits routed through a ticketing/spreadsheet-sync process. Crude, acceptable only for low edit volume.

The write boundary is unchanged from the base design: **writes target the extension table only**, never the base table (ETL would overwrite base edits).

### 7.4 Impact on the Rest of the Design

- **Data layer:** completely unchanged (ETL, `base_application`, `extension_attributes`, `v_application`).
- **REST API:** the *read/search* endpoint is no longer required for the UI, since Power BI queries the view directly. Retain a **thin API for the write path** and any non-Power-BI consumer.
- **Custom UI:** eliminated for query; reduced to (at most) a minimal edit form.

### 7.5 When to Choose This Variation

- **Favoured** if the org already licenses, governs, and uses Power BI — leverages existing infrastructure and offloads the hard filtering problem to a purpose-built tool.
- **Weaker** if adopting Power BI means new licensing and a new tool for all users; in that case the original containerized app may be the lighter overall path.

**Recommended shape of this variation:** Power BI (connected to `v_application`) for query/read, plus a minimal extension-table edit form for writes — keeping the clean data layer and containing custom code to the write path only.

### 7.6 Architecture (Power BI Variation)

```
+---------------------+        ETL         +-----------------------------+
|  Source Catalogue   | -----------------> |   Catalogue Database        |
|  (rigid, weak       |   (periodic,       |                             |
|   search)           |    upsert)         |   +---------------------+   |
+---------------------+                    |   |  base_application   |   |
                                           |   +---------------------+   |
                                           |   +---------------------+   |
                                           |   | extension_attributes|   |
                                           |   +----------+----------+   |
                                           |   +----------v----------+   |
                                           |   |  v_application      |   |
                                           |   |  (unified view,     |   |
                                           |   |   source wins)      |   |
                                           |   +----------+----------+   |
                                           +--------+-----------+--------+
                                                    |           |
                              DirectQuery / Import  |           |  write (extension only)
                                                    |           |
                                          +---------v----+   +--v-------------------+
                                          |   Power BI   |   |  Minimal Write Surface|
                                          |  (query,     |   |  (FastAPI + HTMX, or  |
                                          |   filter,    |   |   Power Apps embed)   |
                                          |   SSO via    |   |                       |
                                          |   Entra ID)  |   +-----------------------+
                                          +------+-------+
                                                 |
                                          +------v-------+
                                          |    Users     |
                                          | (point-click |
                                          |  AND/OR      |
                                          |  filtering)  |
                                          +--------------+
```
