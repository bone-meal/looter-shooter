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
    m.box(K("wood", RAIL), (1.6, 0.16, 1.2), (0.0, d + 0.08, -sp["mast"][1] - 2.4))  # hatch coaming
    m.box(K("timber", HULL_DARK), (1.4, 0.04, 1.0), (0.0, d + 0.17, -sp["mast"][1] - 2.4))  # hatch grating
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
    """Mast, bowsprit, yard + sail, pennant, stays and shrouds."""
    d = sp["deck"]
    mx, mz = sp["mast"]
    mf = -mz
    top = d + sp["mast_height"]
    m.rod(K("wood", HULL_WOOD), 0.17, (mx, d - 0.2, mf), (mx, top, mf), r2=0.1, segs=12)
    m.ball(K("wood", RAIL), (0.16, 0.12, 0.16), (mx, top, mf))  # truck
    bow = -sp["outline"][-1][0]
    sprit = (0.0, d + 1.9, bow + 3.2)
    m.rod(K("wood", HULL_WOOD), 0.11, (0.0, d + 0.6, bow - 1.2), sprit, r2=0.06, segs=10)
    yard_y = top - 1.3
    m.node("Yard", (mx, yard_y, mf))
    m.rod(K("wood", HULL_WOOD), 0.09, (mx - 3.3, yard_y, mf + 0.18), (mx + 3.3, yard_y, mf + 0.18), segs=10, node="Yard")
    m.node("Sail", (mx, yard_y, mf), parent="Yard")
    sail(m, mx, yard_y - 0.15, d + 2.3, mf + 0.3)
    m.node("Pennant", (mx, top + 0.1, mf))
    bm = bmesh.new()
    pts = [(0.0, 0.0), (0.0, -0.5), (-1.6, -0.25)]  # (along, down): pointing aft (game +z)
    a = [bm.verts.new((mx - 0.01, mf + p[0], top + 0.1 + p[1])) for p in pts]
    b = [bm.verts.new((mx + 0.01, mf + p[0], top + 0.1 + p[1])) for p in pts]
    bm.faces.new(a)
    bm.faces.new(b[::-1])
    for i in range(3):
        j = (i + 1) % 3
        bm.faces.new((a[i], b[i], b[j], a[j]))
    m._add(bm, K("cloth", (0.75, 0.12, 0.1)), "Pennant", 0)
    rope = K("leather", ROPE)
    m.rod(rope, 0.025, (mx, top - 0.4, mf), (0.0, sprit[1], sprit[2]), segs=5)  # forestay
    stern_f = -sp["outline"][0][0]
    m.rod(rope, 0.025, (mx, top - 0.4, mf), (0.0, d + sp["bulwark"], stern_f + 0.3), segs=5)  # backstay
    for side in (1, -1):
        for k, df in enumerate((-1.2, 0.0, 1.0)):
            f = mf + df
            hw = max(half(sp, -f), 0.3)
            m.rod(rope, 0.02, (mx, top - 1.6, mf), (side * (hw + 0.05), d + sp["bulwark"], f), segs=5)
        hw = max(half(sp, -mf), 0.3)
        m.box(K("timber", HULL_DARK), (0.12, 0.25, 2.6), (side * (hw + 0.06), d + sp["bulwark"] - 0.2, mf))  # chain plate


def half(sp, z):
    out = sp["outline"]
    for (z0, h0), (z1, h1) in zip(out, out[1:]):
        if z0 >= z >= z1:
            return h0 + (h1 - h0) * (z0 - z) / max(z0 - z1, 0.001)
    return 0.0


def sail(m, mx, y_top, y_bottom, f):
    """A square sail as a closed thin slab, bellied forward, wider at the foot."""
    cols, rows = 8, 7
    bm = bmesh.new()
    grid = []
    for side in (0, 1):
        layer = []
        for r in range(rows + 1):
            v = r / rows
            y = y_top + (y_bottom - y_top) * v
            w = 3.0 + 0.35 * v
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
    m._add(bm, K("cloth", SAILCLOTH), "Sail", 0)
    for side in (1, -1):  # bolt rope down the edges
        m.rod(K("leather", ROPE), 0.03, (mx + side * 3.0, y_top, f), (mx + side * 3.35, y_bottom, f), segs=5, node="Sail")


def helm(m, sp):
    """The wheel on its stand at the helm spot; the wheel turns about its axle (fore and aft)."""
    d = sp["deck"]
    hx, hz = sp["helm"]
    f = -hz
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
        for f in (-2.0, 0.0, 2.0):
            x = side * half(sp, -f)
            m.rod(K("wood", HULL_WOOD), 0.04, (x - side * 0.8, d + bul + 0.35, f), (x + side * 3.6, -0.05, f - 0.6), node=name, segs=6)
            m.box(K("wood", HULL_WOOD), (0.06, 0.5, 0.18), (x + side * 3.75, -0.12, f - 0.66), node=name)


def ladders(m, sp):
    """A rope ladder over each side at ladder_z, from the rail down into the water."""
    d, bul = sp["deck"], sp["bulwark"]
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


def build_ship(ship_id, sp):
    m = kit.Model("ship_" + ship_id, uv_scale=0.5, colored=True)
    hull(m, sp)
    deck(m, sp)
    rails(m, sp)
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
