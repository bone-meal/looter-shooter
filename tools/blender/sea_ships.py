# Purpose: developer-time tool. Builds the sea's ships (sea step 5a: the SLOOP first) as assets/models/sea/ship_<id>.gltf
# from the SAME numbers the game sails and collides with (data/sea/ships.json: outline, deck, draft, bulwark, mast,
# helm, anchor), so the hull drawn is the hull walked on. Materials are named after what a part is made of
# (tools/blender/fantasy_kit.py kinds; the game dresses them with game/fantasy_models.gd). Moving parts are their own
# nodes: Yard (+ Sail under it, furled by scaling from the yard down), Pennant (turned down-wind), Wheel (turns with
# the rudder), Anchor + AnchorRope (shown raised / let go), OarsL / OarsR (shown and swept when rowing).
# Run: python3 tools/blender/sea_ships.py   (bpy as a module; ONLY=ship_sloop builds just that one)
# Dependencies: bpy, bmesh, tools/blender/kit.py, tools/blender/fantasy_kit.py, data/sea/ships.json. No game code.
import json
import math
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
import bpy  # noqa: F401  (before bmesh)
import bmesh
import kit
import fantasy_kit as fk
from fantasy_kit import K

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, "assets", "models", "sea")
DATA = json.load(open(os.path.join(ROOT, "data", "sea", "ships.json")))

HULL_DARK = (0.24, 0.16, 0.1)
HULL_WOOD = (0.42, 0.28, 0.16)
STRIPE = (0.78, 0.66, 0.36)
BOTTOM = (0.42, 0.14, 0.1)
DECK = (0.66, 0.52, 0.34)
RAIL = (0.3, 0.2, 0.12)
SAILCLOTH = (0.92, 0.88, 0.76)
ROPE = (0.62, 0.52, 0.36)
IRON = (0.26, 0.26, 0.28)


def ring(hw, deck, bul, draft):
    """One cross-section of the hull (starboard half, top inner edge first, down to the keel): (x, y, colour band)."""
    hw = max(hw, 0.08)
    t = min(0.12, hw * 0.5)
    return [(hw - t, deck, "rail"), (hw - t, deck + bul, "rail"), (hw, deck + bul, "dark"), (hw * 0.995, deck + bul * 0.35, "stripe"),
            (hw * 0.985, deck * 0.55, "wood"), (hw * 0.93, 0.05, "bottom"), (hw * 0.72, -draft * 0.6, "bottom"), (min(0.12, hw), -draft, "bottom")]


COLOURS = {"rail": ("wood", RAIL), "dark": ("timber", HULL_DARK), "stripe": ("paint", STRIPE), "wood": ("timber", HULL_WOOD), "bottom": ("paint", BOTTOM)}


def hull(m, sp):
    """The hull shell from the outline: quads between neighbouring sections, one part per colour band, both sides."""
    deck, bul, draft = sp["deck"], sp["bulwark"], sp["draft"]
    stations = [(-z, hw) for z, hw in sp["outline"]]  # game z -> model forward (f = -z)
    sections = [ring(hw, deck, bul, draft) for _f, hw in stations]
    for side in (1, -1):
        bands = {}
        for (f0, _a), (f1, _b), r0, r1 in zip(stations, stations[1:], sections, sections[1:]):
            for k in range(len(r0) - 1):
                band = r0[k][2]
                quad = [(side * r0[k][0], r0[k][1], f0), (side * r0[k + 1][0], r0[k + 1][1], f0), (side * r1[k + 1][0], r1[k + 1][1], f1), (side * r1[k][0], r1[k][1], f1)]
                bands.setdefault(band, []).append(quad)
        for band, quads in bands.items():
            bm = bmesh.new()
            for q in quads:
                verts = [bm.verts.new((x, f, y)) for x, y, f in q]
                bm.faces.new(verts if side > 0 else verts[::-1])
            kind, colour = COLOURS[band]
            m._add(bm, K(kind, colour), "Body", 0)
    # keel strip along the bottom, the transom across the stern
    m.strip(K("timber", HULL_DARK), 0.2, 0.18, [(stations[0][0], -draft - 0.05), (stations[-1][0] - 0.2, -draft * 0.4), (stations[-1][0] + 0.25, deck + bul + 0.15)])
    stern = sections[0]
    bm = bmesh.new()
    pts = [(x, y) for x, y, _b in stern[1:]] + [(-x, y) for x, y, _b in reversed(stern[1:])]
    bm.faces.new([bm.verts.new((x, stations[0][0] - 0.02, y)) for x, y in pts])
    m._add(bm, K("timber", HULL_DARK), "Body", 0)


def deck(m, sp):
    """The deck boards (inner edge of the rail all round) with a hatch, the mast step and the bow capstan."""
    d = sp["deck"]
    stations = [(-z, hw) for z, hw in sp["outline"]]
    inner = [(max(hw, 0.08) - min(0.12, max(hw, 0.08) * 0.5), f) for f, hw in stations]
    bm = bmesh.new()
    pts = [(x, f) for x, f in inner] + [(-x, f) for x, f in reversed(inner)]
    bm.faces.new([bm.verts.new((x, f, d)) for x, f in pts])
    m._add(bm, K("wood", DECK), "Body", 0)
    hatch = -sp["masts"][0][0] - 2.4
    m.box(K("wood", RAIL), (1.6, 0.16, 1.2), (0.0, d + 0.08, hatch))  # hatch coaming
    m.box(K("timber", HULL_DARK), (1.4, 0.04, 1.0), (0.0, d + 0.17, hatch))  # hatch grating
    for rx, rz in sp.get("rigging", []):  # pin rails where a crew member trims the sails (crew stations)
        side = 1 if rx > 0 else -1
        m.box(K("wood", RAIL), (0.14, 0.1, 1.4), (rx, d + 0.85, -rz))
        for k in range(5):
            m.rod(K("wood", HULL_WOOD), 0.025, (rx, d + 0.7, -rz - 0.55 + k * 0.275), (rx, d + 1.1, -rz - 0.55 + k * 0.275), segs=6)
            m.rod(K("leather", ROPE), 0.015, (rx, d + 1.0, -rz - 0.55 + k * 0.275), (side * 0.2, d + sp["masts"][0][1] * 0.6, -rz - 0.55 + k * 0.275 + 0.6), segs=4)
    ax, az = sp["anchor"]
    m.lathe(K("timber", HULL_DARK), [(0.32, 0.0), (0.26, 0.08), (0.2, 0.12), (0.2, 0.45), (0.28, 0.5), (0.3, 0.6)], (ax, d, -az))  # capstan
    for k in range(4):
        a = k * math.pi / 2
        m.rod(K("wood", RAIL), 0.035, (ax, d + 0.5, -az), (ax + 0.7 * math.cos(a), d + 0.52, -az + 0.7 * math.sin(a)))


def rails(m, sp):
    """A capping rail along the bulwark top and a few stanchions."""
    d, bul = sp["deck"], sp["bulwark"]
    stations = [(-z, max(hw, 0.08)) for z, hw in sp["outline"]]
    for side in (1, -1):
        for (f0, h0), (f1, h1) in zip(stations, stations[1:]):
            m.rod(K("wood", RAIL), 0.07, (side * (h0 - 0.05), d + bul + 0.03, f0), (side * (h1 - 0.05), d + bul + 0.03, f1), segs=6)


def rig(m, sp):
    """Every mast with its yard + sail (Yard / Sail, Yard2 / Sail2 ...), the bowsprit, the pennant on the tallest mast,
    stays and shrouds."""
    d = sp["deck"]
    style = sp.get("sail", "square")
    masts = sp["masts"]
    bow = -sp["outline"][-1][0]
    stern_f = -sp["outline"][0][0]
    rope = K("leather", ROPE)
    beam = max(hw for _z, hw in sp["outline"])
    sprit = None
    if style == "square" and sp.get("steer", "wheel") == "wheel":
        sprit = (0.0, d + 1.9, bow + 3.0 + 0.1 * len(masts) * 2)
        m.rod(K("wood", HULL_WOOD), 0.11 + 0.02 * len(masts), (0.0, d + 0.6, bow - 1.2), sprit, r2=0.06, segs=10)
    tallest = max(range(len(masts)), key=lambda i: masts[i][1])
    for i, (mz, height) in enumerate(masts):
        mf = -mz
        top = d + height
        suffix = "" if i == 0 else str(i + 1)
        m.rod(K("wood", HULL_WOOD), 0.12 + height * 0.005, (0.0, d - 0.2, mf), (0.0, top, mf), r2=0.08, segs=12)
        m.ball(K("wood", RAIL), (0.16, 0.12, 0.16), (0.0, top, mf))  # truck
        yard_y = top - 1.3
        half_w = min(beam * 1.1, 2.4 + height * 0.1)
        m.node("Yard" + suffix, (0.0, yard_y, mf))
        if style == "batten":
            m.node("Sail" + suffix, (0.0, yard_y, mf), parent="Yard" + suffix)
            batten_sail(m, yard_y, d + 2.2, mf, half_w * 1.2, "Sail" + suffix)
            m.rod(K("wood", HULL_WOOD), 0.07, (0.0, yard_y, mf + half_w * 0.4), (0.0, yard_y + 0.4, mf - half_w * 0.8), segs=8, node="Yard" + suffix)
        else:
            m.rod(K("wood", HULL_WOOD), 0.09, (-half_w - 0.3, yard_y, mf + 0.18), (half_w + 0.3, yard_y, mf + 0.18), segs=10, node="Yard" + suffix)
            m.node("Sail" + suffix, (0.0, yard_y, mf), parent="Yard" + suffix)
            sail(m, 0.0, yard_y - 0.15, d + 2.3, mf + 0.3, half_w, "Sail" + suffix, sp.get("stripes"))
        for side in (1, -1):  # shrouds to the rail
            for df in (-1.2, 0.0, 1.0):
                f = mf + df
                hw = max(half(sp, -f), 0.3)
                m.rod(rope, 0.02, (0.0, top - 1.6, mf), (side * (hw + 0.05), d + sp["bulwark"], f), segs=5)
            if sp["bulwark"] > 0.2:
                hw = max(half(sp, -mf), 0.3)
                m.box(K("timber", HULL_DARK), (0.12, 0.25, 2.6), (side * (hw + 0.06), d + sp["bulwark"] - 0.2, mf))  # chain plate
        if i == tallest:
            m.node("Pennant", (0.0, top + 0.1, mf))
            bm = bmesh.new()
            pts = [(0.0, 0.0), (0.0, -0.5), (-1.6, -0.25)]  # (along, down): pointing aft (game +z)
            a = [bm.verts.new((-0.01, mf + p[0], top + 0.1 + p[1])) for p in pts]
            b = [bm.verts.new((0.01, mf + p[0], top + 0.1 + p[1])) for p in pts]
            bm.faces.new(a)
            bm.faces.new(b[::-1])
            for k in range(3):
                j = (k + 1) % 3
                bm.faces.new((a[k], b[k], b[j], a[j]))
            m._add(bm, K("cloth", (0.75, 0.12, 0.1)), "Pennant", 0)
    fore = max(masts, key=lambda q: -q[0])  # the mast nearest the bow
    aft = min(masts, key=lambda q: -q[0])
    m.rod(rope, 0.025, (0.0, d + fore[1] - 0.4, -fore[0]), sprit if sprit else (0.0, d + sp["bulwark"], bow - 0.6), segs=5)  # forestay
    m.rod(rope, 0.025, (0.0, d + aft[1] - 0.4, -aft[0]), (0.0, d + sp["bulwark"], stern_f + 0.3), segs=5)  # backstay
    for (za, ha), (zb, hb) in zip(sorted(masts, key=lambda q: q[0]), sorted(masts, key=lambda q: q[0])[1:]):
        m.rod(rope, 0.02, (0.0, d + ha - 0.6, -za), (0.0, d + hb * 0.55, -zb), segs=5)  # stay between masts


def batten_sail(m, y_top, y_bottom, f, length, node):
    """A junk's lug sail: a flat panel along the ship (fore and aft) stiffened by battens, deep red."""
    import bmesh as bmm
    rows = 6
    bm = bmm.new()
    front, back = [], []
    for r in range(rows + 1):
        v = r / rows
        y = y_top + (y_bottom - y_top) * v
        aft_end = f - length * (0.55 + 0.25 * v)
        fore_end = f + length * (0.3 + 0.12 * v)
        front.append((bm.verts.new((0.03, fore_end, y)), bm.verts.new((0.03, aft_end, y))))
        back.append((bm.verts.new((-0.03, fore_end, y)), bm.verts.new((-0.03, aft_end, y))))
    for r in range(rows):
        bm.faces.new((front[r][0], front[r][1], front[r + 1][1], front[r + 1][0]))
        bm.faces.new((back[r][0], back[r + 1][0], back[r + 1][1], back[r][1]))
        bm.faces.new((front[r][0], front[r + 1][0], back[r + 1][0], back[r][0]))
        bm.faces.new((front[r][1], back[r][1], back[r + 1][1], front[r + 1][1]))
    bm.faces.new((front[0][0], back[0][0], back[0][1], front[0][1]))
    bm.faces.new((front[rows][0], front[rows][1], back[rows][1], back[rows][0]))
    m._add(bm, K("cloth", (0.66, 0.26, 0.16)), node, 0)
    for r in range(rows + 1):
        v = r / rows
        y = y_top + (y_bottom - y_top) * v
        m.rod(K("wood", HULL_DARK), 0.035, (0.0, y, f + length * (0.3 + 0.12 * v) + 0.1), (0.0, y, f - length * (0.55 + 0.25 * v) - 0.1), segs=6, node=node)


def half(sp, z):
    out = sp["outline"]
    for (z0, h0), (z1, h1) in zip(out, out[1:]):
        if z0 >= z >= z1:
            return h0 + (h1 - h0) * (z0 - z) / max(z0 - z1, 0.001)
    return 0.0


def sail(m, mx, y_top, y_bottom, f, half_w=3.0, node="Sail", stripes=None):
    """A square sail as a closed thin slab, bellied forward, wider at the foot."""
    cols, rows = 8, 7
    bm = bmesh.new()
    grid = []
    for side in (0, 1):
        layer = []
        for r in range(rows + 1):
            v = r / rows
            y = y_top + (y_bottom - y_top) * v
            w = half_w + 0.35 * v
            row = []
            for c in range(cols + 1):
                u = c / cols
                x = mx - w + 2 * w * u
                belly = 0.75 * math.sin(math.pi * u) * math.sin(math.pi * min(v * 1.1, 1.0))
                row.append(bm.verts.new((x, f + belly + (0.035 if side else 0.0), y)))
            layer.append(row)
        grid.append(layer)
    for side in (0, 1):
        g = grid[side]
        for r in range(rows):
            for c in range(cols):
                q = (g[r][c], g[r][c + 1], g[r + 1][c + 1], g[r + 1][c])
                bm.faces.new(q if side else q[::-1])
    a, b = grid
    edge = [(0, c) for c in range(cols)] + [(r, cols) for r in range(rows)] + [(rows, c) for c in range(cols, 0, -1)] + [(r, 0) for r in range(rows, 0, -1)]
    for k in range(len(edge)):
        r0, c0 = edge[k]
        r1, c1 = edge[(k + 1) % len(edge)]
        bm.faces.new((a[r0][c0], a[r1][c1], b[r1][c1], b[r0][c0]))
    m._add(bm, K("cloth", SAILCLOTH), node, 0)
    if stripes:  # painted bands on the sail (the longboat's red stripes): thin slabs just in front of the cloth
        for k in range(1, cols, 2):
            u0, u1 = k / cols, (k + 1) / cols
            for r in range(rows):
                v0, v1 = r / rows, (r + 1) / rows
                quad = []
                for u, v in ((u0, v0), (u1, v0), (u1, v1), (u0, v1)):
                    w = half_w + 0.35 * v
                    belly = 0.75 * math.sin(math.pi * u) * math.sin(math.pi * min(v * 1.1, 1.0))
                    quad.append((mx - w + 2 * w * u, f + belly + 0.04, y_top + (y_bottom - y_top) * v))
                sb = bmesh.new()
                vs = [sb.verts.new(q) for q in quad]
                sb.faces.new(vs)
                sb.faces.new([sb.verts.new((q[0], q[1] - 0.075, q[2])) for q in reversed(quad)])
                m._add(sb, K("cloth", tuple(stripes)), node, 0)
    for side in (1, -1):  # bolt rope down the edges
        m.rod(K("leather", ROPE), 0.03, (mx + side * half_w, y_top, f), (mx + side * (half_w + 0.35), y_bottom, f), segs=5, node=node)


def helm(m, sp):
    """The wheel on its stand at the helm spot (it turns about its axle), or for steer = tiller a steering oar over
    the stern quarter that swings about its oarlock."""
    d = sp["deck"]
    hx, hz = sp["helm"]
    f = -hz
    if sp.get("steer", "wheel") == "tiller":
        side = 1 if hx >= 0 else -1
        pivot = (side * max(half(sp, hz + 0.6), 0.4), d + sp["bulwark"] + 0.1, f - 0.6)
        m.node("Wheel", pivot)
        m.rod(K("wood", HULL_WOOD), 0.06, (pivot[0] - side * 1.4, d + 1.0, f + 0.6), (pivot[0] + side * 0.6, -0.8, f - 2.6), segs=8, node="Wheel")
        m.box(K("wood", HULL_WOOD), (0.08, 0.9, 0.35), (pivot[0] + side * 0.62, -0.95, f - 2.75), node="Wheel")  # blade
        m.box(K("timber", HULL_DARK), (0.2, 0.25, 0.25), pivot)  # oarlock
        return
    m.box(K("timber", HULL_DARK), (0.35, 1.0, 0.3), (hx, d + 0.5, f - 0.15))
    axle = d + 1.05
    m.node("Wheel", (hx, axle, f + 0.05))
    m.cyl(K("timber", HULL_DARK), 0.09, f - 0.05, f + 0.15, y=axle, x=hx, segs=12, node="Wheel")
    rim = K("wood", HULL_WOOD)
    n = 16
    for k in range(n):
        a0, a1 = 2 * math.pi * k / n, 2 * math.pi * (k + 1) / n
        m.rod(rim, 0.035, (hx + 0.55 * math.cos(a0), axle + 0.55 * math.sin(a0), f + 0.05), (hx + 0.55 * math.cos(a1), axle + 0.55 * math.sin(a1), f + 0.05), segs=6, node="Wheel")
    for k in range(8):
        a = 2 * math.pi * k / 8
        m.rod(rim, 0.025, (hx, axle, f + 0.05), (hx + 0.78 * math.cos(a), axle + 0.78 * math.sin(a), f + 0.05), segs=6, node="Wheel")
        m.ball(K("wood", RAIL), 0.045, (hx + 0.8 * math.cos(a), axle + 0.8 * math.sin(a), f + 0.05), node="Wheel", u=6, v=4)


def anchor(m, sp):
    """The anchor hung at the starboard bow (shown while raised) and its cable going down (shown while let go)."""
    d = sp["deck"]
    ax, az = sp["anchor"]
    f = -az + 0.4
    x = half(sp, -f) + 0.12
    iron = K("metal", IRON)
    m.node("Anchor", (x, d - 0.1, f))
    m.rod(iron, 0.05, (x, d + 0.5, f), (x, d - 1.1, f), node="Anchor", segs=8)
    m.rod(iron, 0.04, (x, d - 1.1, f - 0.55), (x, d - 1.1, f + 0.55), node="Anchor", segs=8)
    for s in (1, -1):
        m.rod(iron, 0.045, (x, d - 1.1, f), (x, d - 0.55, f + s * 0.6), node="Anchor", segs=8)
        m.ball(iron, (0.05, 0.1, 0.12), (x, d - 0.55, f + s * 0.6), node="Anchor", u=6, v=4)
    m.lathe(iron, [(0.13, -0.02), (0.13, 0.02)], (x, d + 0.58, f), node="Anchor", segs=12)
    m.box(K("wood", HULL_WOOD), (0.08, 0.08, 0.9), (x, d + 0.42, f), node="Anchor")  # stock
    m.node("AnchorRope", (x, d + 0.4, f))
    m.rod(K("leather", ROPE), 0.04, (x, d + 0.4, f), (x + 0.6, -8.0, f + 2.5), node="AnchorRope", segs=6)


def oars(m, sp):
    """Three oars a side through the rail, swept by the game while rowing."""
    d, bul = sp["deck"], sp["bulwark"]
    for name, side in (("OarsR", 1), ("OarsL", -1)):
        hw = half(sp, 0.0)
        m.node(name, (side * hw, d + bul, 0.0))
        length = sp["outline"][0][0] - sp["outline"][-1][0]
        n = max(3, int(length / 4))
        for f in [(-length * 0.32 + k * length * 0.64 / (n - 1)) for k in range(n)]:
            x = side * half(sp, -f)
            reach = 2.0 + d * 1.2
            m.rod(K("wood", HULL_WOOD), 0.04, (x - side * 0.8, d + bul + 0.35, f), (x + side * reach, -0.05, f - 0.6), node=name, segs=6)
            m.box(K("wood", HULL_WOOD), (0.06, 0.5, 0.18), (x + side * (reach + 0.15), -0.12, f - 0.66), node=name)


def ladders(m, sp):
    """A rope ladder over each side at ladder_z, from the rail down into the water."""
    d, bul = sp["deck"], sp["bulwark"]
    if d < 0.6:
        return  # a raft is climbed straight onto
    f = -sp["ladder_z"]
    rope, rung = K("leather", ROPE), K("wood", HULL_WOOD)
    for side in (1, -1):
        x = side * (half(sp, sp["ladder_z"]) + 0.1)
        top, low = d + bul + 0.05, -0.8
        for df in (-0.24, 0.24):
            m.rod(rope, 0.022, (x, top + 0.1, f + df), (x + side * 0.05, low, f + df), segs=5)
        y = top - 0.25
        while y > low + 0.1:
            m.rod(rung, 0.025, (x + side * 0.03, y, f - 0.26), (x + side * 0.03, y, f + 0.26), segs=6)
            y -= 0.32


def raft_body(m, sp):
    """A log raft: logs side by side lashed with rope, a few cross beams on top; the deck the game walks on is their top."""
    d = sp["deck"]
    stern, bow = -sp["outline"][0][0], -sp["outline"][-1][0]
    hw = sp["outline"][0][1]
    n = 7
    r = hw / n
    for k in range(n):
        x = -hw + r + k * 2 * r
        tip = 0.35 * (1.0 - abs(x) / hw)  # the middle logs reach a little further forward
        m.cyl(K("bark", (0.42, 0.32, 0.22)), r * 0.98, stern + 0.1 * (k % 2), bow + tip, y=d - r, x=x, segs=10)
    for f in (stern + 0.6, (stern + bow) * 0.5, bow - 0.6):
        m.box(K("wood", HULL_WOOD), (hw * 2.0 + 0.1, 0.12, 0.22), (0.0, d + 0.02, f))
        for side in (1, -1):
            m.ball(K("leather", ROPE), (0.06, 0.16, 0.14), (side * (hw - 0.05), d - 0.1, f), u=6, v=4)


def extras(m, ship_id, sp):
    """What makes each ship its own: the longboat's dragon prow, stern curl and shields, the junk's high stern and bow
    eyes, the galleon's stern lanterns and windows, the brig's figurehead."""
    d, bul = sp["deck"], sp["bulwark"]
    stern, bow = -sp["outline"][0][0], -sp["outline"][-1][0]
    if ship_id == "longboat":
        neck = [(0.0, d + 0.4, bow - 0.3, 0.32, 0.36), (0.0, d + 1.6, bow + 0.4, 0.26, 0.3), (0.0, d + 2.8, bow + 0.5, 0.22, 0.25), (0.0, d + 3.5, bow + 0.9, 0.24, 0.28)]
        m.loft(K("wood", (0.36, 0.22, 0.12)), neck, segs=10)
        m.ball(K("wood", (0.36, 0.22, 0.12)), (0.28, 0.25, 0.45), (0.0, d + 3.6, bow + 1.25))  # head
        m.ball(K("paint", (0.9, 0.75, 0.2)), 0.06, (0.17, d + 3.72, bow + 1.35), u=6, v=4)
        m.ball(K("paint", (0.9, 0.75, 0.2)), 0.06, (-0.17, d + 3.72, bow + 1.35), u=6, v=4)
        for side in (1, -1):
            m.rod(K("wood", (0.36, 0.22, 0.12)), 0.04, (side * 0.12, d + 3.8, bow + 1.1), (side * 0.2, d + 4.2, bow + 0.8), segs=5)  # horns
        curl = [(0.0, d + 0.4, stern + 0.3, 0.3, 0.32), (0.0, d + 1.8, stern - 0.3, 0.22, 0.26), (0.0, d + 2.6, stern + 0.2, 0.16, 0.2), (0.0, d + 2.4, stern + 0.7, 0.12, 0.14)]
        m.loft(K("wood", (0.36, 0.22, 0.12)), curl, segs=10)
        colours = [(0.72, 0.16, 0.12), (0.9, 0.82, 0.55), (0.2, 0.32, 0.55)]
        for side in (1, -1):  # shields along the rail
            for k in range(9):
                f = -6.0 + k * 1.5
                x = side * (half(sp, -f) + 0.04)
                m.cylx(K("paint", colours[k % 3]), 0.42, x, x + side * 0.06, f, d + bul - 0.05, segs=16)
                m.cylx(K("metal", IRON), 0.09, x + side * 0.06, x + side * 0.12, f, d + bul - 0.05, segs=10)
    elif ship_id == "junk":
        hw = sp["outline"][0][1]
        m.box(K("paint", (0.62, 0.18, 0.12)), (hw * 2.0, 1.4, 0.18), (0.0, d + bul + 0.7, stern - 0.05))  # high stern board
        m.box(K("wood", (0.25, 0.16, 0.1)), (hw * 2.1, 0.12, 0.3), (0.0, d + bul + 1.45, stern - 0.05))
        for side in (1, -1):
            for z in (stern - 0.05,):
                m.rod(K("wood", (0.25, 0.16, 0.1)), 0.06, (side * hw, d + bul, z), (side * (hw + 0.2), d + bul + 1.6, z + 0.3), segs=6)
            x = side * (half(sp, -(bow - 1.2)) + 0.03)
            m.cylx(K("paint", (0.95, 0.95, 0.9)), 0.32, x, x + side * 0.03, bow - 1.2, d * 0.6, segs=16)  # painted eye
            m.cylx(K("paint", (0.05, 0.05, 0.05)), 0.15, x + side * 0.03, x + side * 0.05, bow - 1.15, d * 0.6, segs=12)
    elif ship_id == "galleon":
        hw = sp["outline"][0][1]
        for k in range(5):  # stern windows lit at night
            x = -hw * 0.7 + k * hw * 0.35
            m.box(fk.GLOW and (fk.GLOW, (1.0, 0.85, 0.5)) or K("paint", (1.0, 0.85, 0.5)), (0.42, 0.5, 0.06), (x, d - 0.2, stern - 0.08))
        for side in (1, -1):  # stern lanterns on brackets out past the quarters, clear of the helm
            m.rod(K("metal", IRON), 0.03, (side * (hw - 0.1), d + bul, stern - 0.1), (side * (hw + 0.5), d + bul + 1.4, stern + 0.4), segs=6)
            m.ball((fk.GLOW, (1.0, 0.8, 0.45)), (0.12, 0.18, 0.12), (side * (hw + 0.55), d + bul + 1.25, stern + 0.45), u=8, v=6)
        m.loft(K("paint", (0.85, 0.7, 0.3)), [(0.0, d - 0.2, bow - 0.4, 0.2, 0.22), (0.0, d + 0.6, bow + 0.4, 0.22, 0.24), (0.0, d + 1.2, bow + 0.6, 0.16, 0.18)], segs=10)
    elif ship_id == "brig":
        m.loft(K("paint", (0.86, 0.84, 0.78)), [(0.0, d - 0.3, bow - 0.3, 0.16, 0.18), (0.0, d + 0.4, bow + 0.3, 0.18, 0.2), (0.0, d + 0.9, bow + 0.45, 0.14, 0.16)], segs=10)


def build_ship(ship_id, sp):
    m = kit.Model("ship_" + ship_id, uv_scale=0.5, colored=True)
    if ship_id == "raft":
        raft_body(m, sp)
    else:
        hull(m, sp)
        deck(m, sp)
        rails(m, sp)
    extras(m, ship_id, sp)
    rig(m, sp)
    helm(m, sp)
    anchor(m, sp)
    oars(m, sp)
    ladders(m, sp)
    print("ship_" + ship_id, m.export(OUT))


if __name__ == "__main__":
    fk.init()
    for ship_id, sp in DATA["ships"].items():
        if fk.ONLY and "ship_" + ship_id not in fk.ONLY:
            continue
        build_ship(ship_id, sp)
