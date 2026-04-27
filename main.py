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
"""

import argparse
import html
import sys
import textwrap
import yaml
from pathlib import Path


# ---------------------------------------------------------------------------
# Colour palette  (draw.io fill / stroke hex values)
# ---------------------------------------------------------------------------
PALETTE = {
    "SaaS":           {"fill": "#dae8fc", "stroke": "#6c8ebf"},   # light blue
    "Cloud Database": {"fill": "#d5e8d4", "stroke": "#82b366"},   # light green
    "Microservice":   {"fill": "#fff2cc", "stroke": "#d6b656"},   # light yellow
    "On-Premise":     {"fill": "#f8cecc", "stroke": "#b85450"},   # light red
    "Web Application":{"fill": "#e1d5e7", "stroke": "#9673a6"},   # light purple
    "default":        {"fill": "#f5f5f5", "stroke": "#666666"},
}

PROTOCOL_COLORS = {
    "HTTPS":  "#007bff",
    "HTTP":   "#6c757d",
    "AMQP":   "#fd7e14",
    "MQTT":   "#20c997",
    "SFTP":   "#6f42c1",
    "Kafka":  "#dc3545",
    "gRPC":   "#17a2b8",
    "JDBC":   "#28a745",
    "S3":     "#ffc107",
    "default":"#555555",
}

FREQUENCY_ICONS = {
    "realtime":     "⚡",
    "scheduled":    "🕐",
    "event-driven": "📡",
    "batch":        "📦",
    "manual":       "👤",
}


# ---------------------------------------------------------------------------
# Geometry helpers
# ---------------------------------------------------------------------------

def grid_positions(systems: list[str], cols: int = 4,
                   x_gap: int = 220, y_gap: int = 160,
                   x_off: int = 60, y_off: int = 60) -> dict[str, tuple[int, int]]:
    """Return {system_name: (x, y)} laid out in a grid."""
    positions = {}
    for i, name in enumerate(systems):
        col = i % cols
        row = i // cols
        positions[name] = (x_off + col * x_gap, y_off + row * y_gap)
    return positions


def layered_positions(interfaces: list[dict],
                      x_gap: int = 240, y_gap: int = 160,
                      x_off: int = 60, y_off: int = 60) -> dict[str, tuple[int, int]]:
    """
    Attempt a simple left-to-right layering: systems that only appear as
    sources are on the left, systems that only appear as targets are on the
    right, the rest in the middle.
    """
    sources = {i["source"]["system"] for i in interfaces}
    targets = {i["target"]["system"] for i in interfaces}
    only_src  = sorted(sources - targets)
    only_tgt  = sorted(targets - sources)
    both      = sorted(sources & targets)

    positions: dict[str, tuple[int, int]] = {}
    for row, name in enumerate(only_src):
        positions[name] = (x_off, y_off + row * y_gap)
    for row, name in enumerate(both):
        positions[name] = (x_off + x_gap, y_off + row * y_gap)
    for row, name in enumerate(only_tgt):
        positions[name] = (x_off + x_gap * 2, y_off + row * y_gap)

    # anything missed (shouldn't happen)
    all_placed = set(positions.keys())
    all_systems = sources | targets
    missed = sorted(all_systems - all_placed)
    for row, name in enumerate(missed):
        positions[name] = (x_off + x_gap * 3, y_off + row * y_gap)

    return positions


# ---------------------------------------------------------------------------
# draw.io XML builders
# ---------------------------------------------------------------------------

def _esc(text: str) -> str:
    return html.escape(str(text))


def _style_for_system(sys_type: str) -> str:
    c = PALETTE.get(sys_type, PALETTE["default"])
    return (
        f"rounded=1;whiteSpace=wrap;html=1;"
        f"fillColor={c['fill']};strokeColor={c['stroke']};"
        f"fontStyle=1;fontSize=11;"
    )


def _style_for_edge(protocol: str, direction: str) -> str:
    color = PROTOCOL_COLORS.get(protocol, PROTOCOL_COLORS["default"])
    end_arrow   = "block"
    start_arrow = "block" if direction == "bidirectional" else "none"
    return (
        f"edgeStyle=orthogonalEdgeStyle;rounded=1;orthogonalLoop=1;"
        f"jettySize=auto;exitX=1;exitY=0.5;exitDx=0;exitDy=0;"
        f"entryX=0;entryY=0.5;entryDx=0;entryDy=0;"
        f"strokeColor={color};strokeWidth=2;"
        f"startArrow={start_arrow};endArrow={end_arrow};"
        f"fontStyle=0;fontSize=9;"
    )


def _edge_label(iface: dict) -> str:
    """Build a compact HTML label for the edge."""
    t = iface.get("transport", {})
    s = iface.get("security", {})
    d = iface.get("data", {})
    sched = iface.get("scheduling", {})

    protocol  = t.get("protocol", "?")
    port      = t.get("port", "")
    auth      = s.get("authentication", {}).get("method", "None")
    fmt       = d.get("format", "")
    freq      = sched.get("frequency", "")
    icon      = FREQUENCY_ICONS.get(freq, "")
    iid       = iface.get("id", "")

    lines = [
        f"<b>{_esc(iface['name'])}</b>",
        f"{_esc(iid)}",
        f"🔌 {_esc(protocol)}{(':' + str(port)) if port else ''}",
        f"🔐 {_esc(auth)}",
    ]
    if fmt:
        lines.append(f"📄 {_esc(fmt)}")
    if freq:
        lines.append(f"{icon} {_esc(freq)}")

    return "<br>".join(lines)


def build_drawio_xml(interfaces: list[dict], layout: str = "layered") -> str:
    """Generate the full draw.io XML string."""

    # Collect unique systems
    systems: dict[str, str] = {}   # name -> type
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

    # Assign stable integer IDs
    base = 10
    sys_ids: dict[str, int] = {name: base + i for i, name in enumerate(system_names)}
    edge_base = base + len(system_names)

    cells = []

    # --- system nodes ---
    for name, sys_type in systems.items():
        sid   = sys_ids[name]
        x, y  = positions.get(name, (60, 60))
        style = _style_for_system(sys_type)
        label = f"<b>{_esc(name)}</b><br/><i>{_esc(sys_type)}</i>"
        cells.append(
            f'    <mxCell id="{sid}" value="{label}" style="{style}" '
            f'vertex="1" parent="1">\n'
            f'      <mxGeometry x="{x}" y="{y}" width="160" height="60" as="geometry"/>\n'
            f'    </mxCell>'
        )

    # --- interface edges ---
    for i, iface in enumerate(interfaces):
        eid      = edge_base + i
        src_id   = sys_ids[iface["source"]["system"]]
        tgt_id   = sys_ids[iface["target"]["system"]]
        t        = iface.get("transport", {})
        protocol = t.get("protocol", "default")
        direction= t.get("direction", "unidirectional")
        style    = _style_for_edge(protocol, direction)
        label    = _edge_label(iface)

        cells.append(
            f'    <mxCell id="{eid}" value="{label}" style="{style}" '
            f'edge="1" source="{src_id}" target="{tgt_id}" parent="1">\n'
            f'      <mxGeometry relative="1" as="geometry"/>\n'
            f'    </mxCell>'
        )

    cells_xml = "\n".join(cells)

    return textwrap.dedent(f"""\
        <?xml version="1.0" encoding="UTF-8"?>
        <mxGraphModel dx="1422" dy="762" grid="1" gridSize="10" guides="1"
                      tooltips="1" connect="1" arrows="1" fold="1" page="1"
                      pageScale="1" pageWidth="1654" pageHeight="1169"
                      math="0" shadow="0">
          <root>
            <mxCell id="0"/>
            <mxCell id="1" parent="0"/>
        {cells_xml}
          </root>
        </mxGraphModel>
        """)


# ---------------------------------------------------------------------------
# Legend page
# ---------------------------------------------------------------------------

def build_legend_xml() -> str:
    items = list(PALETTE.items())
    legend_cells = []
    lid_base = 1000
    for i, (sys_type, colors) in enumerate(items):
        y = 20 + i * 50
        style = (f"rounded=1;whiteSpace=wrap;html=1;"
                 f"fillColor={colors['fill']};strokeColor={colors['stroke']};"
                 f"fontStyle=1;fontSize=10;")
        legend_cells.append(
            f'    <mxCell id="{lid_base + i}" value="{_esc(sys_type)}" '
            f'style="{style}" vertex="1" parent="1">\n'
            f'      <mxGeometry x="20" y="{y}" width="160" height="34" as="geometry"/>\n'
            f'    </mxCell>'
        )

    p_base = lid_base + len(items)
    for j, (proto, color) in enumerate(PROTOCOL_COLORS.items()):
        if proto == "default":
            continue
        y = 20 + j * 50
        style = (f"edgeStyle=orthogonalEdgeStyle;strokeColor={color};"
                 f"strokeWidth=2;endArrow=block;fontStyle=0;fontSize=10;")
        # just a label box for legend purposes
        label = f"🔌 {_esc(proto)}"
        legend_cells.append(
            f'    <mxCell id="{p_base + j}" value="{label}" '
            f'style="text;html=1;strokeColor=none;fillColor=none;fontSize=10;" '
            f'vertex="1" parent="1">\n'
            f'      <mxGeometry x="200" y="{y}" width="120" height="34" as="geometry"/>\n'
            f'    </mxCell>'
        )

    cells_xml = "\n".join(legend_cells)
    return textwrap.dedent(f"""\
        <?xml version="1.0" encoding="UTF-8"?>
        <mxGraphModel>
          <root>
            <mxCell id="0"/>
            <mxCell id="1" parent="0"/>
        {cells_xml}
          </root>
        </mxGraphModel>
        """)


# ---------------------------------------------------------------------------
# Summary report (plain text)
# ---------------------------------------------------------------------------

def print_summary(interfaces: list[dict]) -> None:
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
        port  = t.get("port", "")
        auth  = iface.get("security", {}).get("authentication", {}).get("method", "None")
        fmt   = iface.get("data", {}).get("format", "-")
        freq  = iface.get("scheduling", {}).get("frequency", "-")
        ctr   = iface.get("execution", {}).get("container", "-")
        print(f"\n  [{iid}] {name}")
        print(f"    {src}  ──{proto}{(':' + str(port)) if port else ''}──▶  {tgt}")
        print(f"    Auth: {auth}   Format: {fmt}   Frequency: {freq}")
        print(f"    Container: {ctr}")
    print()


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main() -> None:
    parser = argparse.ArgumentParser(
        description="Convert a system-interface YAML file to a draw.io diagram."
    )
    parser.add_argument("yaml_file",
                        help="Path to the interfaces YAML file.")
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

    layout = args.layout if args.layout != "auto" else "layered"
    diagram_xml = build_drawio_xml(interfaces, layout=layout)

    with open(output_path, "w", encoding="utf-8") as fh:
        fh.write(diagram_xml)

    print(f"✅  Diagram written to: {output_path}")
    print(f"    Systems  : {len({i['source']['system'] for i in interfaces} | {i['target']['system'] for i in interfaces})}")
    print(f"    Interfaces: {len(interfaces)}")
    print(f"\nOpen in draw.io desktop or https://app.diagrams.net  ➜  File ▶ Open")


if __name__ == "__main__":
    main()
