#!/usr/bin/env python3
"""
interfaces_to_drawio.py
Reads a YAML interface registry and generates a draw.io diagram.
Usage: python interfaces_to_drawio.py interfaces.yaml [--output out.drawio] [--layout layered|grid] [--summary]
Requirements: pip install pyyaml
"""
import argparse
import html
import re
import sys
import yaml
from pathlib import Path

# ---------------------------------------------------------------------------
# Palettes and constants
# ---------------------------------------------------------------------------
PALETTE = {
    "SaaS":            {"fill": "#dae8fc", "stroke": "#6c8ebf"},
    "Cloud Database":  {"fill": "#d5e8d4", "stroke": "#82b366"},
    "Microservice":    {"fill": "#fff2cc", "stroke": "#d6b656"},
    "On-Premise":      {"fill": "#f8cecc", "stroke": "#b85450"},
    "Web Application": {"fill": "#e1d5e7", "stroke": "#9673a6"},
    "Shared Drive":    {"fill": "#ffe6cc", "stroke": "#d79b00"},
    "default":         {"fill": "#f5f5f5", "stroke": "#666666"},
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
    "SMB":     "#d79b00",
    "NFS":     "#b46504",
    "File":    "#a0522d",
    "default": "#555555",
}

FREQUENCY_ICONS = {
    "realtime":     "\u26a1 realtime",
    "scheduled":    "\u29d6 scheduled",
    "event-driven": "\u27a4 event-driven",
    "batch":        "\u2630 batch",
    "manual":       "\u270e manual",
    "file-polling": "\u231a file-polling",
}

ICON_PROTOCOL = "\u21c4"
ICON_AUTH     = "\u26bf"
ICON_AUTHZ    = "\u2611"
ICON_FORMAT   = "\u2395"
ICON_EXEC     = "\u25a3"
ICON_POLL     = "\u231a"

STATUS_STYLES = {
    "active":   {"color": "#00a854", "width": 3, "dashed": False,
                 "icon": "\u25cf ACTIVE",   "html_color": "#00a854", "summary_icon": "\u25cf"},
    "inactive": {"color": "#555555", "width": 2, "dashed": True,
                 "icon": "\u25cb INACTIVE", "html_color": "#555555", "summary_icon": "\u25cb"},
    "broken":   {"color": "#e53935", "width": 3, "dashed": False,
                 "icon": "\u2716 BROKEN",   "html_color": "#e53935", "summary_icon": "\u2716"},
}
STATUS_DEFAULT = STATUS_STYLES["active"]

_REF_SYMBOLS = list("\u2460\u2461\u2462\u2463\u2464\u2465\u2466\u2467\u2468\u2469"
                    "\u246a\u246b\u246c\u246d\u246e\u246f\u2470\u2471\u2472\u2473")

NOTE_STYLE = ("shape=callout;whiteSpace=wrap;html=0;"
              "fillColor=#ffffc0;strokeColor=#999900;"
              "fontSize=9;align=left;perimeter=calloutPerimeter;")

NOTE_CONNECTOR_STYLE = ("edgeStyle=none;dashed=1;strokeColor=#999900;"
                        "strokeWidth=1;endArrow=none;startArrow=none;")

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
def _ref_symbol(index):
    return _REF_SYMBOLS[index] if index < len(_REF_SYMBOLS) else "(" + str(index+1) + ")"

def _sanitise(text):
    return "".join(c for c in str(text) if ord(c) <= 0xFFFF)

def _esc(text):
    return html.escape(_sanitise(str(text)))

def _htag(tag):
    return html.escape(tag)

def _clean_xml(xml):
    xml = xml.replace("\t", "").replace("\r", "").replace("\n", "")
    xml = re.sub(r">\s+<", "><", xml)
    return xml

def _pretty_xml(xml, indent="  "):
    """Pretty-print XML with space indentation (no tabs)."""
    minified = _clean_xml(xml)
    out = []
    depth = 0
    i = 0
    n = len(minified)
    while i < n:
        if minified[i] == "<":
            j = minified.index(">", i)
            tag = minified[i:j + 1]
            if tag.startswith("<?") or tag.startswith("<!"):
                out.append(tag)
                out.append("\n")
            elif tag.startswith("</"):
                depth -= 1
                out.append(indent * depth)
                out.append(tag)
                out.append("\n")
            elif tag.endswith("/>"):
                out.append(indent * depth)
                out.append(tag)
                out.append("\n")
            else:
                out.append(indent * depth)
                out.append(tag)
                out.append("\n")
                depth += 1
            i = j + 1
        else:
            j = minified.index("<", i)
            text = minified[i:j]
            if text.strip():
                if out and out[-1] == "\n":
                    out.pop()
                out.append(text)
                out.append("\n")
            i = j
    return "".join(out)

# ---------------------------------------------------------------------------
# Layout
# ---------------------------------------------------------------------------
def grid_positions(systems, cols=4, x_gap=220, y_gap=160, x_off=60, y_off=60):
    positions = {}
    for i, name in enumerate(systems):
        positions[name] = (x_off + (i % cols) * x_gap, y_off + (i // cols) * y_gap)
    return positions

def layered_positions(interfaces, x_gap=280, y_gap=160, x_off=60, y_off=60):
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
    missed = sorted((sources | targets) - set(positions.keys()))
    for row, name in enumerate(missed):
        positions[name] = (x_off + x_gap * 3, y_off + row * y_gap)
    return positions

# ---------------------------------------------------------------------------
# Cell builder
# ---------------------------------------------------------------------------
def _mxcell(cell_id, value, style, vertex=None, edge=None,
            source=None, target=None, x=None, y=None,
            width=None, height=None, relative=False, parent="1",
            source_point=None, target_point=None):
    attrs = 'id="' + str(cell_id) + '" value="' + str(value) + '" style="' + str(style) + '"'
    if vertex:
        attrs += ' vertex="1"'
    if edge:
        attrs += ' edge="1"'
    if source is not None:
        attrs += ' source="' + str(source) + '"'
    if target is not None:
        attrs += ' target="' + str(target) + '"'
    attrs += ' parent="' + str(parent) + '"'
    if relative:
        if source_point is not None or target_point is not None:
            geo = '<mxGeometry relative="1" as="geometry">'
            if source_point is not None:
                geo += ('<mxPoint x="' + str(source_point[0]) + '" y="' +
                        str(source_point[1]) + '" as="sourcePoint"/>')
            if target_point is not None:
                geo += ('<mxPoint x="' + str(target_point[0]) + '" y="' +
                        str(target_point[1]) + '" as="targetPoint"/>')
            geo += '</mxGeometry>'
        else:
            geo = '<mxGeometry relative="1" as="geometry"/>'
    else:
        geo = ('<mxGeometry x="' + str(x) + '" y="' + str(y) +
               '" width="' + str(width) + '" height="' + str(height) + '" as="geometry"/>')
    return '<mxCell ' + attrs + '>' + geo + '</mxCell>'

# ---------------------------------------------------------------------------
# Style builders
# ---------------------------------------------------------------------------
def _style_for_system(sys_type):
    c = PALETTE.get(sys_type, PALETTE["default"])
    return ("rounded=1;whiteSpace=wrap;html=0;"
            "fillColor=" + c["fill"] + ";strokeColor=" + c["stroke"] + ";"
            "fontStyle=1;fontSize=11;")

def _style_for_edge(protocol, direction, status="active"):
    proto_color = PROTOCOL_COLORS.get(protocol, PROTOCOL_COLORS["default"])
    st = STATUS_STYLES.get(status, STATUS_DEFAULT)
    stroke_color = proto_color if status == "active" else st["color"]
    start_arrow = "block" if direction == "bidirectional" else "none"
    style = ("edgeStyle=orthogonalEdgeStyle;rounded=1;orthogonalLoop=1;"
             "jettySize=auto;html=1;"
             "strokeColor=" + stroke_color + ";strokeWidth=" + str(st["width"]) + ";"
             "startArrow=" + start_arrow + ";endArrow=block;"
             "fontStyle=0;fontSize=9;")
    if st["dashed"]:
        style += "dashed=1;"
    return style

# ---------------------------------------------------------------------------
# Label builders
# ---------------------------------------------------------------------------
def _system_label(name, sys_type, env="", host=""):
    lines = [name, sys_type]
    if env:
        lines.append(env)
    if host:
        lines.append(host)
    return "&#xa;".join(_esc(l) for l in lines)

def _edge_label(iface, ref_symbol=""):
    t     = iface.get("transport", {})
    s     = iface.get("security", {})
    d     = iface.get("data", {})
    sched = iface.get("scheduling", {})
    exe   = iface.get("execution", {})

    protocol = t.get("protocol", "?")
    port     = t.get("port")
    auth     = s.get("authentication", {}).get("method", "None")
    authz    = s.get("authorization", {}).get("model", "")
    fmt      = d.get("format", "")
    freq     = sched.get("frequency", "")
    iid      = iface.get("id", "")
    status   = iface.get("status", "active").lower()
    st       = STATUS_STYLES.get(status, STATUS_DEFAULT)
    container = exe.get("container", "")
    platform  = exe.get("platform", "")
    exe_parts = [p for p in [container, platform] if p]
    exe_str   = " / ".join(exe_parts)

    BR     = _htag("<br>")
    B_O    = _htag("<b>")
    B_C    = _htag("</b>")
    FONT_O = _htag('<font color="' + st["html_color"] + '">')
    FONT_C = _htag("</font>")

    proto_str = _esc(ICON_PROTOCOL) + "&#160;" + _esc(protocol) + (":" + str(port) if port is not None else "")
    name_part = _esc(iid) + ": " + _esc(iface["name"])
    if ref_symbol:
        name_part += "&#160;&#160;" + _esc(ref_symbol)
    name_line   = B_O + name_part + B_C
    status_line = FONT_O + _esc(st["icon"]) + FONT_C

    lines = [name_line, status_line, proto_str, _esc(ICON_AUTH) + "&#160;" + _esc(auth)]
    if authz:
        lines.append(_esc(ICON_AUTHZ) + "&#160;" + _esc(authz))
    if fmt:
        lines.append(_esc(ICON_FORMAT) + "&#160;" + _esc(fmt))
    if freq:
        lines.append(_esc(FREQUENCY_ICONS.get(freq, freq.upper())))
    if exe_str:
        lines.append(_esc(ICON_EXEC) + "&#160;" + _esc(exe_str))

    return BR.join(lines)

def _note_label(iface, ref_symbol):
    authz = iface.get("security", {}).get("authorization", {})
    model = authz.get("model", "")
    perms = authz.get("permissions", [])
    roles = authz.get("roles", [])
    lines = ["Permissions " + ref_symbol, "Ref: " + iface.get("id", "")]
    if model:
        lines.append("Model: " + model)
    if roles:
        lines.append("Roles: " + ", ".join(str(r) for r in roles))
    if perms:
        lines.append("Permissions:")
        for p in perms:
            lines.append("  - " + str(p))
    return "&#xa;".join(_esc(l) for l in lines)

# ---------------------------------------------------------------------------
# Legend
# ---------------------------------------------------------------------------
def _build_legend(legend_x, legend_y, id_base):
    cells = []
    cid_holder = [id_base]

    def next_id():
        v = cid_holder[0]
        cid_holder[0] = v + 1
        return v

    box_w        = 240
    row_h        = 26
    sw           = 28
    title_h      = 26
    bottom_pad   = 6
    label_x      = sw + 16
    label_w      = box_w - label_x - 8

    lbl_style = ("text;html=0;strokeColor=none;fillColor=none;"
                 "align=left;verticalAlign=middle;fontSize=9;")
    container_style = ("rounded=1;whiteSpace=wrap;html=0;"
                       "fillColor=#ffffff;strokeColor=#aaaaaa;"
                       "verticalAlign=top;align=left;fontStyle=1;fontSize=9;"
                       "container=1;collapsible=0;")

    # Title bar (drawn first, sits above first group)
    cells.append(_mxcell(next_id(), "LEGEND",
                         ("rounded=1;whiteSpace=wrap;html=0;"
                          "fillColor=#dae8fc;strokeColor=#6c8ebf;"
                          "fontStyle=1;fontSize=11;verticalAlign=middle;align=center;"),
                         vertex=True,
                         x=legend_x, y=legend_y - 34, width=box_w, height=28))

    row_y = legend_y

    def open_container(title, item_count):
        nonlocal row_y
        box_id = next_id()
        box_y  = row_y
        box_h  = title_h + item_count * row_h + bottom_pad
        cells.append(_mxcell(box_id, title, container_style, vertex=True,
                             x=legend_x, y=box_y,
                             width=box_w, height=box_h))
        row_y = box_y + box_h + 10
        return box_id

    # ── Group 1: System / Node types ─────────────────────────────────────────
    sys_types = [
        ("SaaS",            PALETTE["SaaS"]),
        ("Cloud Database",  PALETTE["Cloud Database"]),
        ("Microservice",    PALETTE["Microservice"]),
        ("On-Premise",      PALETTE["On-Premise"]),
        ("Web Application", PALETTE["Web Application"]),
        ("Shared Drive",    PALETTE["Shared Drive"]),
        ("Other",           PALETTE["default"]),
    ]
    box_id = open_container("System / Node types", len(sys_types))
    inner_y = title_h
    for lbl, c in sys_types:
        sw_style = ("rounded=1;whiteSpace=wrap;html=0;"
                    "fillColor=" + c["fill"] + ";strokeColor=" + c["stroke"] + ";fontSize=8;")
        cells.append(_mxcell(next_id(), "", sw_style, vertex=True, parent=box_id,
                             x=8, y=inner_y, width=sw, height=row_h - 4))
        cells.append(_mxcell(next_id(), lbl, lbl_style, vertex=True, parent=box_id,
                             x=label_x, y=inner_y, width=label_w, height=row_h - 4))
        inner_y += row_h

    # ── Group 2: Interface status ─────────────────────────────────────────────
    statuses = list(STATUS_STYLES.items())
    box_id = open_container("Interface status", len(statuses))
    inner_y = title_h
    for key, st in statuses:
        ls = ("endArrow=block;startArrow=none;html=0;"
              "strokeColor=" + st["color"] + ";strokeWidth=3;"
              + ("dashed=1;" if st["dashed"] else ""))
        line_y = inner_y + (row_h - 4) // 2
        cells.append(_mxcell(next_id(), "", ls, edge=True, relative=True, parent=box_id,
                             source_point=(8, line_y),
                             target_point=(8 + sw, line_y)))
        cells.append(_mxcell(next_id(), st["icon"] + " " + key.capitalize(),
                             lbl_style, vertex=True, parent=box_id,
                             x=label_x, y=inner_y, width=label_w, height=row_h - 4))
        inner_y += row_h

    # ── Group 3: Protocol / Interface types ───────────────────────────────────
    proto_items = [
        ("HTTPS / HTTP",  PROTOCOL_COLORS["HTTPS"]),
        ("AMQP / MQTT",   PROTOCOL_COLORS["AMQP"]),
        ("SFTP",          PROTOCOL_COLORS["SFTP"]),
        ("Kafka",         PROTOCOL_COLORS["Kafka"]),
        ("gRPC",          PROTOCOL_COLORS["gRPC"]),
        ("JDBC",          PROTOCOL_COLORS["JDBC"]),
        ("S3",            PROTOCOL_COLORS["S3"]),
        ("SMB / NFS",     PROTOCOL_COLORS["SMB"]),
        ("File polling",  PROTOCOL_COLORS["File"]),
    ]
    box_id = open_container("Interface / Protocol types", len(proto_items))
    inner_y = title_h
    for lbl, color in proto_items:
        ls = ("endArrow=block;startArrow=none;html=0;"
              "strokeColor=" + color + ";strokeWidth=2;")
        line_y = inner_y + (row_h - 4) // 2
        cells.append(_mxcell(next_id(), "", ls, edge=True, relative=True, parent=box_id,
                             source_point=(8, line_y),
                             target_point=(8 + sw, line_y)))
        cells.append(_mxcell(next_id(), lbl, lbl_style, vertex=True, parent=box_id,
                             x=label_x, y=inner_y, width=label_w, height=row_h - 4))
        inner_y += row_h

    # ── Group 4: Connector field icons ────────────────────────────────────────
    field_icons = [
        (ICON_PROTOCOL, "Protocol / Port"),
        (ICON_AUTH,     "Authentication"),
        (ICON_AUTHZ,    "Authorization model"),
        (ICON_FORMAT,   "Data format"),
        (ICON_EXEC,     "Execution environment"),
        (ICON_POLL,     "File polling"),
    ]
    box_id = open_container("Connector field icons", len(field_icons))
    inner_y = title_h
    for icon, desc in field_icons:
        cells.append(_mxcell(next_id(), icon, lbl_style, vertex=True, parent=box_id,
                             x=8, y=inner_y, width=sw, height=row_h - 4))
        cells.append(_mxcell(next_id(), desc, lbl_style, vertex=True, parent=box_id,
                             x=label_x, y=inner_y, width=label_w, height=row_h - 4))
        inner_y += row_h

    return cells

# ---------------------------------------------------------------------------
# Main diagram builder
# ---------------------------------------------------------------------------
def build_drawio_xml(interfaces, layout="layered"):
    systems = {}
    for iface in interfaces:
        systems.setdefault(iface["source"]["system"], iface["source"].get("type", "default"))
        systems.setdefault(iface["target"]["system"], iface["target"].get("type", "default"))

    system_names = list(systems.keys())
    positions = (layered_positions(interfaces) if layout == "layered"
                 else grid_positions(system_names, cols=max(1, min(4, len(system_names)))))

    base       = 10
    sys_ids    = {name: base + i for i, name in enumerate(system_names)}
    edge_base  = base + len(system_names)
    note_base  = edge_base + len(interfaces)
    conn_base  = note_base + len(interfaces)

    cells = []

    for name, sys_type in systems.items():
        sid = sys_ids[name]
        x, y = positions.get(name, (60, 60))
        info = next((i["source"] for i in interfaces if i["source"]["system"] == name),
                    next((i["target"] for i in interfaces if i["target"]["system"] == name), {}))
        label = _system_label(name, sys_type, info.get("environment", ""), info.get("host", ""))
        cells.append(_mxcell(sid, label, _style_for_system(sys_type),
                             vertex=True, x=x, y=y, width=160, height=60))

    ref_map = {}
    sym_counter = 0
    for i, iface in enumerate(interfaces):
        authz = iface.get("security", {}).get("authorization", {})
        if authz.get("permissions") or authz.get("roles"):
            ref_map[i] = _ref_symbol(sym_counter)
            sym_counter += 1

    max_y       = max((pos[1] for pos in positions.values()), default=60)
    note_y_base = max_y + 160

    for i, iface in enumerate(interfaces):
        eid       = edge_base + i
        src_id    = sys_ids[iface["source"]["system"]]
        tgt_id    = sys_ids[iface["target"]["system"]]
        t         = iface.get("transport", {})
        protocol  = t.get("protocol", "default")
        direction = t.get("direction", "unidirectional")
        status    = iface.get("status", "active").lower()
        ref_sym   = ref_map.get(i, "")

        cells.append(_mxcell(eid, _edge_label(iface, ref_sym),
                             _style_for_edge(protocol, direction, status),
                             edge=True, source=src_id, target=tgt_id, relative=True))

        if ref_sym:
            nid    = note_base + i
            note_x = 60 + i * 220
            note_h = 80 + len(iface.get("security", {}).get("authorization", {}).get("permissions", [])) * 14
            cells.append(_mxcell(nid, _note_label(iface, ref_sym), NOTE_STYLE,
                                 vertex=True, x=note_x, y=note_y_base, width=200, height=note_h))
            cells.append(_mxcell(conn_base + i, "", NOTE_CONNECTOR_STYLE,
                                 edge=True, source=nid, target=eid, relative=True))

    max_x    = max((pos[0] for pos in positions.values()), default=60)
    min_y    = min((pos[1] for pos in positions.values()), default=60)
    legend_x = max_x + 220
    legend_y = min_y + 34
    leg_id   = conn_base + len(interfaces) + 100
    cells.extend(_build_legend(legend_x, legend_y, leg_id))

    inner = "".join(cells)
    body  = ('<mxGraphModel dx="1422" dy="762" grid="1" gridSize="10" guides="1"'
             ' tooltips="1" connect="1" arrows="1" fold="1" page="1"'
             ' pageScale="1" pageWidth="1654" pageHeight="1169" math="0" shadow="0">'
             '<root>'
             '<mxCell id="0"/>'
             '<mxCell id="1" parent="0"/>'
             + inner +
             '</root>'
             '</mxGraphModel>')
    return _clean_xml('<?xml version="1.0" encoding="UTF-8"?>' + body)

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
def print_summary(interfaces):
    print("\n" + "=" * 60)
    print("  Interface Summary  (" + str(len(interfaces)) + " interface(s))")
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
        perms = iface.get("security", {}).get("authorization", {}).get("permissions", [])
        status = iface.get("status", "active").lower()
        icon   = STATUS_STYLES.get(status, STATUS_DEFAULT)["summary_icon"]
        port_s = ":" + str(port) if port is not None else ""
        print("\n  " + icon + " [" + iid + "] " + name + "  [" + status.upper() + "]")
        print("    " + src + "  --" + proto + port_s + "-->  " + tgt)
        print("    Auth: " + auth + "   Format: " + fmt + "   Frequency: " + freq)
        print("    Container: " + ctr)
        if perms:
            print("    Permissions: " + ", ".join(str(p) for p in perms))
    print()

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
def main():
    parser = argparse.ArgumentParser(description="Convert interface YAML to draw.io diagram.")
    parser.add_argument("yaml_file")
    parser.add_argument("--output", "-o", default=None)
    parser.add_argument("--layout", choices=["auto", "grid", "layered"], default="layered")
    parser.add_argument("--summary", action="store_true")
    args = parser.parse_args()

    yaml_path = Path(args.yaml_file)
    if not yaml_path.exists():
        print("ERROR: File not found: " + str(yaml_path), file=sys.stderr)
        sys.exit(1)

    with open(yaml_path, encoding="utf-8") as fh:
        data = yaml.safe_load(fh)

    interfaces = data.get("interfaces", [])
    if not interfaces:
        print("WARNING: No interfaces found.", file=sys.stderr)
        sys.exit(0)

    if args.summary:
        print_summary(interfaces)

    output_path = Path(args.output) if args.output else yaml_path.with_suffix(".drawio")
    layout      = args.layout if args.layout != "auto" else "layered"
    diagram_xml = build_drawio_xml(interfaces, layout=layout)

    with open(output_path, "wb") as fh:
        fh.write(_pretty_xml(diagram_xml).encode("utf-8"))

    print("Done: " + str(output_path))
    print("  Systems   : " + str(len({i["source"]["system"] for i in interfaces} | {i["target"]["system"] for i in interfaces})))
    print("  Interfaces: " + str(len(interfaces)))
    for s_val in ("active", "inactive", "broken"):
        count = sum(1 for i in interfaces if i.get("status", "active").lower() == s_val)
        if count:
            print("    " + STATUS_STYLES[s_val]["summary_icon"] + " " + s_val + ": " + str(count))
    notes = sum(1 for i in interfaces
                if i.get("security", {}).get("authorization", {}).get("permissions")
                or i.get("security", {}).get("authorization", {}).get("roles"))
    if notes:
        print("  Permission notes: " + str(notes))
    print("\nOpen in draw.io desktop or https://app.diagrams.net")

if __name__ == "__main__":
    main()