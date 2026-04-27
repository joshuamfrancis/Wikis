#!/usr/bin/env python3
"""
interfaces_to_drawio.py
-----------------------
Reads a YAML file describing system interfaces and generates a draw.io
(.drawio / .xml) diagram showing systems as nodes and interfaces as
labelled edges.

Usage:
    python interfaces_to_drawio.py interfaces.yaml [--output diagram.drawio]
                                                   [--layout {auto,grid,layered}]

Requirements:
    pip install pyyaml

Optional YAML fields
--------------------
source / target:
    environment   - omit if not relevant
    host          - omit if not relevant

transport:
    port          - omit for protocol-default or connectionless transports

security.authorization:
    permissions   - omit if not relevant; when present a callout note is
                    added to the diagram referencing the interface by symbol.
"""

import argparse
import html
import sys
import yaml
from pathlib import Path


# ---------------------------------------------------------------------------
# Colour palette  (draw.io fill / stroke hex values)
# ---------------------------------------------------------------------------
PALETTE = {
    "SaaS":           {"fill": "#dae8fc", "stroke": "#6c8ebf"},
    "Cloud Database": {"fill": "#d5e8d4", "stroke": "#82b366"},
    "Microservice":   {"fill": "#fff2cc", "stroke": "#d6b656"},
    "On-Premise":     {"fill": "#f8cecc", "stroke": "#b85450"},
    "Web Application":{"fill": "#e1d5e7", "stroke": "#9673a6"},
    "default":        {"fill": "#f5f5f5", "stroke": "#666666"},
}

PROTOCOL_COLORS = {
    "HTTPS":   "#007bff",
    "HTTP":    "#6c757d",
    "AMQP":    "#fd7e14",
    "MQTT":    "#20c997",
    "SFTP":    "#6f42c1",
    "Kafka":   "#dc3545",
    "gRPC":    "#17a2b8",
    "JDBC":    "#28a745",
    "S3":      "#ffc107",
    "default": "#555555",
}

FREQUENCY_ICONS = {
    "realtime":     "⚡",
    "scheduled":    "🕐",
    "event-driven": "📡",
    "batch":        "📦",
    "manual":       "👤",
}

# Symbols used to cross-reference permission notes → interfaces
_REF_SYMBOLS = list("①②③④⑤⑥⑦⑧⑨⑩⑪⑫⑬⑭⑮⑯⑰⑱⑲⑳")


def _ref_symbol(index: int) -> str:
    if index < len(_REF_SYMBOLS):
        return _REF_SYMBOLS[index]
    return f"({index + 1})"


# ---------------------------------------------------------------------------
# Geometry helpers
# ---------------------------------------------------------------------------

def grid_positions(systems: list, cols: int = 4,
                   x_gap: int = 220, y_gap: int = 160,
                   x_off: int = 60, y_off: int = 60) -> dict:
    positions = {}
    for i, name in enumerate(systems):
        col = i % cols
        row = i // cols
        positions[name] = (x_off + col * x_gap, y_off + row * y_gap)
    return positions


def layered_positions(interfaces: list,
                      x_gap: int = 280, y_gap: int = 160,
                      x_off: int = 60, y_off: int = 60) -> dict:
    sources = {i["source"]["system"] for i in interfaces}
    targets = {i["target"]["system"] for i in interfaces}
    only_src = sorted(sources - targets)
    only_tgt = sorted(targets - sources)
    both     = sorted(sources & targets)

    positions = {}
    for row, name in enumerate(only_src):
        positions[name] = (x_off, y_off + row * y_gap)
    for row, name in enumerate(both):
        positions[name] = (x_off + x_gap, y_off + row * y_gap)
    for row, name in enumerate(only_tgt):
        positions[name] = (x_off + x_gap * 2, y_off + row * y_gap)

    all_placed  = set(positions.keys())
    all_systems = sources | targets
    missed      = sorted(all_systems - all_placed)
    for row, name in enumerate(missed):
        positions[name] = (x_off + x_gap * 3, y_off + row * y_gap)

    return positions


# ---------------------------------------------------------------------------
# XML helpers
# ---------------------------------------------------------------------------

def _esc(text) -> str:
    return html.escape(str(text))


def _style_for_system(sys_type: str) -> str:
    c = PALETTE.get(sys_type, PALETTE["default"])
    return (
        f"rounded=1;whiteSpace=wrap;html=0;"
        f"fillColor={c['fill']};strokeColor={c['stroke']};"
        f"fontStyle=1;fontSize=11;"
    )


def _style_for_edge(protocol: str, direction: str) -> str:
    color       = PROTOCOL_COLORS.get(protocol, PROTOCOL_COLORS["default"])
    end_arrow   = "block"
    start_arrow = "block" if direction == "bidirectional" else "none"
    return (
        f"edgeStyle=orthogonalEdgeStyle;rounded=1;orthogonalLoop=1;"
        f"jettySize=auto;"
        f"strokeColor={color};strokeWidth=2;"
        f"startArrow={start_arrow};endArrow={end_arrow};"
        f"fontStyle=0;fontSize=9;"
    )


NOTE_STYLE = (
    "shape=callout;whiteSpace=wrap;html=0;"
    "fillColor=#ffffc0;strokeColor=#999900;"
    "fontSize=9;align=left;perimeter=calloutPerimeter;"
)

NOTE_CONNECTOR_STYLE = (
    "edgeStyle=none;dashed=1;strokeColor=#999900;"
    "strokeWidth=1;endArrow=none;startArrow=none;"
)


def _system_label(name: str, sys_type: str, env: str = "", host: str = "") -> str:
    """Build a plain-text multi-line label for a system node."""
    lines = [name, sys_type]
    if env:
        lines.append(env)
    if host:
        lines.append(host)
    return "&#xa;".join(_esc(l) for l in lines)


def _edge_label(iface: dict, ref_symbol: str = "") -> str:
    """Build a plain-text multi-line label for an interface edge."""
    t     = iface.get("transport", {})
    s     = iface.get("security", {})
    d     = iface.get("data", {})
    sched = iface.get("scheduling", {})

    protocol = t.get("protocol", "?")
    port     = t.get("port")                          # optional
    auth     = s.get("authentication", {}).get("method", "None")
    fmt      = d.get("format", "")
    freq     = sched.get("frequency", "")
    icon     = FREQUENCY_ICONS.get(freq, "")
    iid      = iface.get("id", "")

    proto_str = f"Protocol: {protocol}" + (f":{port}" if port is not None else "")

    # Append reference symbol to name line when a permissions note exists
    name_line = iface["name"]
    if ref_symbol:
        name_line = f"{name_line}  {ref_symbol}"

    lines = [
        name_line,
        iid,
        proto_str,
        f"Auth: {auth}",
    ]
    if fmt:
        lines.append(f"Format: {fmt}")
    if freq:
        lines.append(f"{icon} {freq}")

    return "&#xa;".join(_esc(l) for l in lines)


def _note_label(iface: dict, ref_symbol: str) -> str:
    """Build the permissions note label for an interface."""
    auth   = iface.get("security", {})
    authz  = auth.get("authorization", {})
    model  = authz.get("model", "")
    perms  = authz.get("permissions", [])
    roles  = authz.get("roles", [])

    lines = [f"Permissions {ref_symbol}", f"Ref: {iface.get('id', '')}"]
    if model:
        lines.append(f"Model: {model}")
    if roles:
        lines.append("Roles: " + ", ".join(str(r) for r in roles))
    if perms:
        lines.append("Permissions:")
        for p in perms:
            lines.append(f"  - {p}")

    return "&#xa;".join(_esc(l) for l in lines)


def _mxcell(cell_id, value, style, vertex=None, edge=None,
             source=None, target=None, x=None, y=None,
             width=None, height=None, relative=False) -> str:
    attrs = f'id="{cell_id}" value="{value}" style="{style}"'
    if vertex:
        attrs += ' vertex="1"'
    if edge:
        attrs += ' edge="1"'
    if source is not None:
        attrs += f' source="{source}"'
    if target is not None:
        attrs += f' target="{target}"'
    attrs += ' parent="1"'

    if relative:
        geo = '<mxGeometry relative="1" as="geometry"/>'
    else:
        geo = f'<mxGeometry x="{x}" y="{y}" width="{width}" height="{height}" as="geometry"/>'

    return f'    <mxCell {attrs}>{geo}</mxCell>'


# ---------------------------------------------------------------------------
# Main diagram builder
# ---------------------------------------------------------------------------

def build_drawio_xml(interfaces: list, layout: str = "layered") -> str:
    """Generate the full draw.io XML string."""

    # Collect unique systems
    systems = {}   # name -> type
    for iface in interfaces:
        src = iface["source"]
        tgt = iface["target"]
        systems.setdefault(src["system"], src.get("type", "default"))
        systems.setdefault(tgt["system"], tgt.get("type", "default"))

    system_names = list(systems.keys())

    if layout == "layered":
        positions = layered_positions(interfaces)
    else:
        cols = max(1, min(4, len(system_names)))
        positions = grid_positions(system_names, cols=cols)

    # Stable IDs
    base     = 10
    sys_ids  = {name: base + i for i, name in enumerate(system_names)}
    edge_base = base + len(system_names)
    note_base = edge_base + len(interfaces)
    conn_base = note_base + len(interfaces)  # connectors from notes → edges

    cells = []

    # ── System nodes ──────────────────────────────────────────────────────────
    for name, sys_type in systems.items():
        sid  = sys_ids[name]
        x, y = positions.get(name, (60, 60))

        src_info = next(
            (i["source"] for i in interfaces if i["source"]["system"] == name),
            next((i["target"] for i in interfaces if i["target"]["system"] == name), {})
        )
        env  = src_info.get("environment", "")
        host = src_info.get("host", "")

        label = _system_label(name, sys_type, env, host)
        style = _style_for_system(sys_type)
        cells.append(_mxcell(sid, label, style, vertex=True,
                              x=x, y=y, width=160, height=60))

    # ── Interface edges + optional permission notes ────────────────────────────
    # First pass: assign ref symbols only to interfaces that have permissions
    ref_map = {}   # interface index → symbol
    sym_counter = 0
    for i, iface in enumerate(interfaces):
        authz = iface.get("security", {}).get("authorization", {})
        perms = authz.get("permissions", [])
        roles = authz.get("roles", [])
        if perms or roles:
            ref_map[i] = _ref_symbol(sym_counter)
            sym_counter += 1

    # Determine a good Y offset for notes (below all system nodes)
    max_y = max((pos[1] for pos in positions.values()), default=60)
    note_y_base = max_y + 160   # place notes below the diagram

    for i, iface in enumerate(interfaces):
        eid       = edge_base + i
        src_id    = sys_ids[iface["source"]["system"]]
        tgt_id    = sys_ids[iface["target"]["system"]]
        t         = iface.get("transport", {})
        protocol  = t.get("protocol", "default")
        direction = t.get("direction", "unidirectional")
        ref_sym   = ref_map.get(i, "")

        style = _style_for_edge(protocol, direction)
        label = _edge_label(iface, ref_sym)
        cells.append(_mxcell(eid, label, style, edge=True,
                              source=src_id, target=tgt_id, relative=True))

        # Permission note for this interface (if any)
        if ref_sym:
            nid     = note_base + i
            note_x  = 60 + (i * 220)
            note_w  = 200
            note_h  = 80 + len(
                iface.get("security", {}).get("authorization", {}).get("permissions", [])
            ) * 14

            note_label = _note_label(iface, ref_sym)
            cells.append(_mxcell(nid, note_label, NOTE_STYLE, vertex=True,
                                  x=note_x, y=note_y_base,
                                  width=note_w, height=note_h))

            # Dashed connector: note → edge
            cid = conn_base + i
            cells.append(_mxcell(cid, "", NOTE_CONNECTOR_STYLE,
                                  edge=True, source=nid, target=eid, relative=True))

    cells_xml = "\n".join(cells)

    lines = [
        '<?xml version="1.0" encoding="UTF-8"?>',
        '<mxGraphModel dx="1422" dy="762" grid="1" gridSize="10" guides="1"'
        ' tooltips="1" connect="1" arrows="1" fold="1" page="1"'
        ' pageScale="1" pageWidth="1654" pageHeight="1169" math="0" shadow="0">',
        '  <root>',
        '    <mxCell id="0"/>',
        '    <mxCell id="1" parent="0"/>',
        cells_xml,
        '  </root>',
        '</mxGraphModel>',
    ]
    return "\n".join(lines) + "\n"


# ---------------------------------------------------------------------------
# Summary report
# ---------------------------------------------------------------------------

def print_summary(interfaces: list) -> None:
    print("\n" + "=" * 60)
    print(f"  Interface Summary  ({len(interfaces)} interface(s))")
    print("=" * 60)
    for iface in interfaces:
        iid   = iface.get("id", "-")
        name  = iface.get("name", "-")
        src   = iface["source"]["system"]
        tgt   = iface["target"]["system"]
        t     = iface.get("transport", {})
        proto = t.get("protocol", "?")
        port  = t.get("port")
        auth  = iface.get("security", {}).get("authentication", {}).get("method", "None")
        fmt   = iface.get("data", {}).get("format", "-")
        freq  = iface.get("scheduling", {}).get("frequency", "-")
        ctr   = iface.get("execution", {}).get("container", "-")
        authz = iface.get("security", {}).get("authorization", {})
        perms = authz.get("permissions", [])

        port_str = f":{port}" if port is not None else ""
        print(f"\n  [{iid}] {name}")
        print(f"    {src}  ──{proto}{port_str}──▶  {tgt}")
        print(f"    Auth: {auth}   Format: {fmt}   Frequency: {freq}")
        print(f"    Container: {ctr}")
        if perms:
            print(f"    Permissions: {', '.join(str(p) for p in perms)}")
    print()


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main() -> None:
    parser = argparse.ArgumentParser(
        description="Convert a system-interface YAML file to a draw.io diagram."
    )
    parser.add_argument("yaml_file", help="Path to the interfaces YAML file.")
    parser.add_argument("--output", "-o", default=None,
                        help="Output .drawio file path (default: <yaml_name>.drawio)")
    parser.add_argument("--layout", choices=["auto", "grid", "layered"],
                        default="layered",
                        help="Diagram layout algorithm (default: layered)")
    parser.add_argument("--summary", action="store_true",
                        help="Print an interface summary table to stdout.")
    args = parser.parse_args()

    yaml_path = Path(args.yaml_file)
    if not yaml_path.exists():
        print(f"ERROR: File not found: {yaml_path}", file=sys.stderr)
        sys.exit(1)

    with open(yaml_path, encoding="utf-8") as fh:
        data = yaml.safe_load(fh)

    interfaces = data.get("interfaces", [])
    if not interfaces:
        print("WARNING: No interfaces found in the YAML file.", file=sys.stderr)
        sys.exit(0)

    if args.summary:
        print_summary(interfaces)

    output_path = Path(args.output) if args.output else yaml_path.with_suffix(".drawio")

    layout      = args.layout if args.layout != "auto" else "layered"
    diagram_xml = build_drawio_xml(interfaces, layout=layout)

    with open(output_path, "w", encoding="utf-8") as fh:
        fh.write(diagram_xml)

    print(f"✅  Diagram written to: {output_path}")
    print(f"    Systems   : {len({i['source']['system'] for i in interfaces} | {i['target']['system'] for i in interfaces})}")
    print(f"    Interfaces: {len(interfaces)}")
    notes_count = sum(
        1 for i in interfaces
        if i.get("security", {}).get("authorization", {}).get("permissions") or
           i.get("security", {}).get("authorization", {}).get("roles")
    )
    if notes_count:
        print(f"    Permission notes: {notes_count}")
    print(f"\nOpen in draw.io desktop or https://app.diagrams.net  ➜  File ▶ Open")


if __name__ == "__main__":
    main()