# Purpose: developer-time tool. Builds the sea's six ships as assets/models/sea/ship_<id>.gltf from the SAME numbers the
# game sails and collides with (data/sea/ships.json: outline, deck, draft, bulwark, masts, levels = raised decks with
# their stairs, helm, anchor, cannons, rigging, ladder), so the decks drawn are the decks walked on. Rework after the
# director's "too simple and similar ... look like their names ... the viking ship and junk need to look completely
# different": each ship has its own hull form and rig -
#   sloop     round hull, gaff mainsail + jib on a bowsprit, wheel
#   brig      round hull, two masts each with course / topsail / topgallant, jibs, quarterdeck with a cabin front
#   galleon   tumblehome hull, forecastle + quarterdeck + poop (walkable), two rows of gun ports, stern gallery,
#             lanterns, fore / main square rig + lateen mizzen + spritsail, beakhead figure
#   raft      lashed logs, small square sail, steering oar
#   longboat  clinker-built open Viking hull, sweeping stem and stern (dragon head and tail), shields, thwarts, oar
#             holes, one broad striped sail, side steering oar
#   junk      flat-bottomed slab-sided hull, blunt bow, towering overhanging stern castle, huge rudder and tiller,
#             raked masts with battened fan sails, painted eyes
# Materials are named after what a part is made of (tools/blender/fantasy_kit.py kinds; the game dresses them with
# game/fantasy_models.gd). Moving parts are their own nodes: Yard / Sail (Yard2 / Sail2 ...) per mast, Jib* head sails,
# Pennant, Wheel (wheel, tiller or steering oar), Anchor + AnchorRope, OarsL / OarsR. Solid parts are closed shapes so
# their faces point the right way (a single face's up / down is a guess: the old galleon deck faced down).
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

ROPE = (0.62, 0.52, 0.36)
IRON = (0.26, 0.26, 0.28)
SAILCLOTH = (0.92, 0.88, 0.76)
GOLD = (0.86, 0.68, 0.28)
GLASS = (1.0, 0.85, 0.5)

# Per ship: hull colours (bottom, hull, upper strake, rail / trim), deck colour, sheer rise at bow / stern (m).
LOOK = {
    "sloop": {"bottom": (0.62, 0.36, 0.18), "hull": (0.36, 0.25, 0.15), "strake": (0.18, 0.32, 0.5), "rail": (0.86, 0.82, 0.7), "deck": (0.72, 0.6, 0.42), "bow": 0.5, "stern": 0.25},
    "brig": {"bottom": (0.4, 0.42, 0.36), "hull": (0.12, 0.11, 0.1), "strake": (0.82, 0.68, 0.32), "rail": (0.12, 0.11, 0.1), "deck": (0.68, 0.56, 0.4), "bow": 0.8, "stern": 0.3},
    "galleon": {"bottom": (0.82, 0.78, 0.64), "hull": (0.32, 0.2, 0.12), "strake": (0.58, 0.12, 0.1), "rail": GOLD, "deck": (0.64, 0.5, 0.34), "bow": 1.0, "stern": 0.4},
    "longboat": {"hull": (0.38, 0.26, 0.15), "deck": (0.52, 0.4, 0.26), "bow": 1.6, "stern": 1.3},
    "junk": {"hull": (0.32, 0.2, 0.12), "strake": (0.6, 0.16, 0.1), "rail": (0.12, 0.1, 0.08), "deck": (0.6, 0.46, 0.3), "bottom": (0.2, 0.18, 0.16), "bow": 0.6, "stern": 0.0},
}


def half(sp, z):
    """Half the deck's width at game z (data outline, straight lines between)."""
    out = sp["outline"]
    for (z0, h0), (z1, h1) in zip(out, out[1:]):
        if z0 >= z >= z1:
            return h0 + (h1 - h0) * (z0 - z) / max(z0 - z1, 0.001)
    return 0.0


def deck_at(sp, z):
    """The walking height at game z: main deck or a raised deck over it (same rule as core/sea/ship_rules.gd)."""
    top = sp["deck"]
    for lv in sp.get("levels", []):
        if lv["from"] <= z <= lv["to"]:
            top = max(top, sp["deck"] + lv["height"])
    return top


def sheer(sp, look, z):
    """The rail's rise above the bulwark at game z: the ends sweep up."""
    stern, bow = sp["outline"][0][0], sp["outline"][-1][0]
    t = (z - (stern + bow) * 0.5) / max((stern - bow) * 0.5, 0.01)  # +1 stern .. -1 bow
    return look.get("stern", 0.0) * max(t, 0.0) ** 2 + look.get("bow", 0.0) * max(-t, 0.0) ** 2


def solid(m, mat, rings, node="Body"):
    """A closed shape skinned through rings of equal point counts (each ring a closed loop), capped at both ends."""
    bm = bmesh.new()
    vs = [[bm.verts.new(p) for p in r] for r in rings]
    n = len(rings[0])
    for a, b in zip(vs, vs[1:]):
        for i in range(n):
            j = (i + 1) % n
            bm.faces.new((a[i], a[j], b[j], b[i]))
    bm.faces.new(vs[0][::-1])
    bm.faces.new(vs[-1])
    m._add(bm, mat, node, 0)


def slab(m, mat, pts, y0, y1, node="Body"):
    """A flat closed slab over a polygon [(x, f), ...] from height y0 to y1."""
    solid(m, mat, [[(x, f, y0) for x, f in pts], [(x, f, y1) for x, f in pts]], node)


# ----------------------------------------------------------------------------------------------- hulls

def hull_round(m, sp, look, tumble=0.0):
    """A carvel-built round hull in colour bands (bottom, hull, upper strake, rail cap), a stem and stern post, wales."""
    d, bul, draft = sp["deck"], sp["bulwark"], sp["draft"]
    stations = sp["outline"]
    bands = [("bottom", -draft, 0.25), ("hull", 0.25, d * 0.75), ("strake", d * 0.75, d + bul * 0.6), ("rail", d + bul * 0.6, d + bul)]
    def ring(z, hw, top):
        hw = max(hw, 0.06)
        pts = []
        for frac in (0.0, 0.12, 0.3, 0.55, 0.8, 1.0):  # keel to rail, starboard side
            y = -draft + (top + draft) * frac
            k = math.sin(frac * math.pi * 0.5) ** 0.6  # full near the waterline, narrow at the keel
            w = hw * (0.15 + 0.85 * k)
            if y > d:
                w -= tumble * (y - d) / max(top - d, 0.01) * hw * 0.12
            pts.append((w, y))
        return pts
    for colour, y0, y1 in bands:
        for side in (1, -1):
            bm = bmesh.new()
            rows = []
            for z, hw in stations:
                top = d + bul + sheer(sp, look, z)
                prof = ring(z, hw, top)
                lo, hi = y0, (y1 if colour != "rail" else top)
                line = []
                for frac in range(4):
                    y = lo + (hi - lo) * frac / 3.0
                    w = _width_at(prof, y)
                    line.append(bm.verts.new((side * w, -z, y)))
                rows.append(line)
            for a, b in zip(rows, rows[1:]):
                for i in range(3):
                    q = (a[i], a[i + 1], b[i + 1], b[i])
                    bm.faces.new(q if side > 0 else q[::-1])
            m._add(bm, K("timber" if colour == "hull" else "paint", look[colour]), "Body", 0)
    stern_z = stations[0][0]
    hw_s = stations[0][1]
    top_s = d + bul + sheer(sp, look, stern_z)
    pts = [(x, y) for x, y in ring(stern_z, hw_s, top_s)]
    transom = [(w, -stern_z + 0.01, y) for w, y in pts] + [(-w, -stern_z + 0.01, y) for w, y in reversed(pts)]
    bm = bmesh.new()
    bm.faces.new([bm.verts.new(p) for p in transom[::-1]])
    bm.faces.new([bm.verts.new((p[0], p[1] - 0.06, p[2])) for p in transom])
    m._add(bm, K("timber", look["hull"]), "Body", 0)
    bow = -stations[-1][0]
    m.strip(K("timber", look["rail"]), 0.18, 0.2, [(-stern_z, -draft - 0.05), (bow - 0.6, -draft * 0.6), (bow + 0.1, d * 0.5), (bow + 0.05, d + bul + sheer(sp, look, stations[-1][0]) + 0.2)])
    for y, w in ((d * 0.55, 0.09), (d + bul * 0.25, 0.07)):  # wales: heavy planks running the length
        for side in (1, -1):
            prev = None
            for z, hw in stations:
                prof = ring(z, hw, d + bul + sheer(sp, look, z))
                p = (side * (_width_at(prof, y) + 0.03), y, -z)
                if prev:
                    m.rod(K("timber", look["rail"]), w, prev, p, segs=6)
                prev = p


def bulwark_walls(m, sp, look, colour, start=None, thick=0.13):
    """The inside of the ship's sides from the deck up to the rail: a closed wall just inside the hull skin (a hull band
    is one-sided and cannot be seen from the deck)."""
    d = sp["deck"] if start is None else start
    for side in (1, -1):
        rings = []
        for z, hw in sp["outline"]:
            hw = max(hw, 0.1)
            top = sp["deck"] + sp["bulwark"] + sheer(sp, look, z)
            rings.append([(side * (hw - 0.02), -z, d), (side * (hw - 0.02), -z, top), (side * (hw - 0.02 - thick), -z, top), (side * (hw - 0.02 - thick), -z, d)])
        solid(m, K("timber", colour), rings)
    z, hw = sp["outline"][0]
    top = sp["deck"] + sp["bulwark"] + sheer(sp, look, z)
    m.box(K("timber", colour), (hw * 2.0 - 0.1, top - d, thick), (0.0, (top + d) * 0.5, -z + 0.1))  # inside of the transom


def _width_at(prof, y):
    for (w0, y0), (w1, y1) in zip(prof, prof[1:]):
        if y0 <= y <= y1:
            return w0 + (w1 - w0) * (y - y0) / max(y1 - y0, 0.001)
    return prof[-1][0] if y > prof[-1][1] else prof[0][0]


def hull_clinker(m, sp, look):
    """The longboat: an open clinker hull - overlapping strakes, each a little further out than the one below, the
    ends sweeping up into a stem and stern post; no bulwark, floorboards inside."""
    d, draft = sp["deck"], sp["draft"]
    stations = sp["outline"]
    strakes = 6
    gunwale = d + sp["bulwark"]
    for k in range(strakes):
        f0, f1 = k / strakes, (k + 1) / strakes
        shade = 0.9 + 0.1 * (k % 2)
        colour = tuple(c * shade for c in look["hull"])
        for side in (1, -1):
            bm = bmesh.new()
            rows = []
            for z, hw in stations:
                rise = sheer(sp, look, z)
                top = gunwale + rise
                line = []
                for f in (f0, f1 + 0.04):
                    f = min(f, 1.0)
                    y = -draft * (1.0 - f) * (1.0 - rise / 3.0) + top * f
                    w = max(hw, 0.06) * (0.12 + 0.88 * math.sin(f * math.pi * 0.5) ** 0.7) + 0.025 * k
                    line.append(bm.verts.new((side * w, -z, y)))
                rows.append(line)
            for a, b in zip(rows, rows[1:]):
                q = (a[0], a[1], b[1], b[0])
                bm.faces.new(q if side > 0 else q[::-1])
            m._add(bm, K("timber", colour), "Body", 0)
    inner = [(max(max(hw, 0.08) - 0.08, 0.06), -z) for z, hw in stations]
    slab(m, K("wood", look["deck"]), [(x, f) for x, f in inner] + [(-x, f) for x, f in reversed(inner)], d - 0.1, d)  # floorboards
    for z in range(-6, 7, 2):  # thwarts (rowing benches)
        hw = half(sp, z) * 0.85
        m.box(K("wood", (0.5, 0.36, 0.22)), (hw * 2.0, 0.08, 0.32), (0.0, d + 0.38, -z))
        for side in (1, -1):
            m.cylx(K("paint", (0.08, 0.06, 0.05)), 0.07, side * (half(sp, z) + 0.06), side * (half(sp, z) + 0.12), -z, gunwale - 0.12, segs=10)  # oar hole
    for side in (1, -1):  # gunwale cap
        prev = None
        for z, hw in stations:
            p = (side * (hw + 0.13), gunwale + sheer(sp, look, z), -z)
            if prev:
                m.rod(K("wood", (0.3, 0.2, 0.12)), 0.06, prev, p, segs=6)
            prev = p


def hull_junk(m, sp, look):
    """The junk: slab sides and a flat bottom, a blunt transom bow, the stern rising high and hanging out over the
    rudder; red and black bands, rails like ladders along the top."""
    d, bul, draft = sp["deck"], sp["bulwark"], sp["draft"]
    stations = sp["outline"]
    for colour, y0, y1 in (("bottom", -draft, 0.3), ("hull", 0.3, d + 0.2), ("strake", d + 0.2, d + bul)):
        for side in (1, -1):
            bm = bmesh.new()
            rows = []
            for z, hw in stations:
                rise = sheer(sp, look, z)
                lo, hi = (y0, y1 + rise) if colour == "strake" else (y0, y1)
                line = []
                for y in (lo, hi):
                    w = max(hw, 0.06) * (0.86 if y < 0.0 else (0.97 if y < d else 1.0))
                    line.append(bm.verts.new((side * w, -z, y)))
                rows.append(line)
            for a, b in zip(rows, rows[1:]):
                q = (a[0], a[1], b[1], b[0])
                bm.faces.new(q if side > 0 else q[::-1])
            m._add(bm, K("timber" if colour == "hull" else "paint", look[colour]), "Body", 0)
    outer = [(max(hw, 0.06) * 0.86, -z) for z, hw in stations]
    slab(m, K("paint", look["bottom"]), [(x, f) for x, f in outer] + [(-x, f) for x, f in reversed(outer)], -draft - 0.05, -draft)  # flat bottom
    bow_z, bow_hw = stations[-1]
    top_b = d + bul + sheer(sp, look, bow_z)
    m.box(K("paint", look["strake"]), (bow_hw * 2.0 + 0.1, top_b + draft, 0.14), (0.0, (top_b - draft) * 0.5, -bow_z + 0.07))  # blunt bow board
    m.box(K("paint", (0.1, 0.08, 0.06)), (bow_hw * 2.0 + 0.14, 0.3, 0.16), (0.0, d * 0.6, -bow_z + 0.08))


# ----------------------------------------------------------------------------------------------- decks and castles

def deck(m, sp, look):
    """The main deck as a closed slab inside the rail, the hatch, the capstan at the anchor and pin rails at the rigging
    spots (crew stations)."""
    d = sp["deck"]
    inner = [(max(hw, 0.08) - min(0.12, max(hw, 0.08) * 0.5), -z) for z, hw in sp["outline"]]
    slab(m, K("wood", look["deck"]), [(x, f) for x, f in inner] + [(-x, f) for x, f in reversed(inner)], d - 0.12, d)
    for z in range(int(sp["outline"][-1][0]) + 1, int(sp["outline"][0][0])):  # deck seams
        hw = half(sp, z) - 0.2
        if hw > 0.3:
            m.box(K("wood", tuple(c * 0.7 for c in look["deck"])), (hw * 2.0, 0.01, 0.03), (0.0, d + 0.005, -z - 0.5))
    hatch = -sp["masts"][0][0] - 2.4
    if deck_at(sp, -hatch) == d:
        m.box(K("wood", look["rail"] if "rail" in look else (0.3, 0.2, 0.12)), (1.6, 0.16, 1.2), (0.0, d + 0.08, hatch))
        for k in range(5):
            m.box(K("timber", (0.2, 0.14, 0.08)), (0.06, 0.05, 1.0), (-0.56 + k * 0.28, d + 0.17, hatch))
    ax, az = sp["anchor"]
    ay = deck_at(sp, az)
    m.lathe(K("timber", (0.24, 0.16, 0.1)), [(0.32, 0.0), (0.26, 0.08), (0.2, 0.12), (0.2, 0.45), (0.28, 0.5), (0.3, 0.6)], (ax, ay, -az))  # capstan
    for k in range(4):
        a = k * math.pi / 2
        m.rod(K("wood", (0.3, 0.2, 0.12)), 0.035, (ax, ay + 0.5, -az), (ax + 0.7 * math.cos(a), ay + 0.52, -az + 0.7 * math.sin(a)))
    for rx, rz in sp.get("rigging", []):
        side = 1 if rx > 0 else -1
        ry = deck_at(sp, rz)
        m.box(K("wood", (0.4, 0.28, 0.16)), (0.14, 0.1, 1.4), (rx, ry + 0.85, -rz))
        for k in range(5):
            f = -rz - 0.55 + k * 0.275
            m.rod(K("wood", (0.36, 0.25, 0.15)), 0.025, (rx, ry + 0.7, f), (rx, ry + 1.1, f), segs=6)
            m.rod(K("leather", ROPE), 0.015, (rx, ry + 1.0, f), (side * 0.25, ry + 6.0, f + 0.6), segs=4)


def levels(m, sp, look, ship_id):
    """Raised decks (walkable in the game): a closed block up to the level, its own deck, a rail round it with
    turned balusters at the open edge, the stairs, and a cabin front with a door and windows facing the main deck."""
    d = sp["deck"]
    rail_c = look.get("rail", (0.3, 0.2, 0.12))
    for lv in sp.get("levels", []):
        z0, z1, h = lv["from"], lv["to"], lv["height"]
        top = d + h
        zs = [z0 + (z1 - z0) * k / 6.0 for k in range(7)]
        pts = [(max(half(sp, z) - 0.15, 0.2), -z) for z in zs]
        loop = [(x, f) for x, f in pts] + [(-x, f) for x, f in reversed(pts)]
        slab(m, K("timber", look["hull"]), loop, d - 0.05, top - 0.1)
        slab(m, K("wood", look["deck"]), loop, top - 0.1, top)
        front = z0 if abs(z0) < abs(z1) else z1  # the face looking at the main deck (towards midships)
        facing = 1 if front == z0 else -1  # +1: the level lies aft of the face (quarterdeck), -1: forward of it (forecastle)
        hw = max(half(sp, front) - 0.15, 0.3)
        for side in (1, -1):  # side rails on the level, following the hull
            prev = None
            for z in zs:
                p = (side * (half(sp, z) - 0.05), top + 0.95, -z)
                if prev:
                    m.rod(K("wood", rail_c), 0.05, prev, p, segs=6)
                    m.box(K("timber", look["hull"]), (0.1, 0.95, abs(prev[2] - p[2]) + 0.05), (side * (half(sp, z) - 0.07), top + 0.47, (prev[2] + p[2]) * 0.5))
                prev = p
        stairs_x = [st["x"] for st in lv["stairs"]]
        x = -hw + 0.1
        while x < hw - 0.05:  # balusters along the open front edge, gaps where the stairs arrive
            if all(abs(x - sx) > 0.6 for sx in stairs_x):
                m.lathe(K("wood", rail_c), [(0.05, 0.0), (0.07, 0.15), (0.04, 0.4), (0.07, 0.75), (0.05, 0.9)], (x, top, -front - facing * 0.05), segs=8)
            x += 0.28
        for sx in (-hw + 0.1, hw - 0.1):
            m.box(K("wood", rail_c), (0.12, 0.08, 0.12), (sx, top + 0.95, -front - facing * 0.05))
        m.box(K("wood", rail_c), (hw * 2.0, 0.08, 0.12), (0.0, top + 0.93, -front - facing * 0.05))
        if h >= 1.2:  # cabin front: door and windows under the rail
            m.box(K("wood", (0.24, 0.15, 0.09)), (0.9, min(h - 0.15, 1.9), 0.06), (0.0, d + min(h - 0.15, 1.9) * 0.5, -front + facing * 0.04))
            m.ball(K("metal", GOLD), 0.04, (0.3, d + 0.9, -front + facing * 0.08), u=6, v=4)
            for wx in (-hw * 0.6, hw * 0.6):
                m.box(K("timber", (0.15, 0.1, 0.06)), (0.62, 0.52, 0.08), (wx, d + h * 0.55, -front + facing * 0.03))
                m.box((fk.GLOW, GLASS), (0.48, 0.38, 0.04), (wx, d + h * 0.55, -front + facing * 0.07))
        for st in lv["stairs"]:  # the stairs: treads and two stringers
            n = max(int(h / 0.22), 3)
            for k in range(n):
                t = (k + 0.5) / n
                zf = -(st["low"] + (st["high"] - st["low"]) * t)
                m.box(K("wood", look["deck"]), (0.9, 0.06, abs(st["high"] - st["low"]) / n + 0.02), (st["x"], d + h * t, zf))
            for dx in (-0.47, 0.47):
                m.rod(K("wood", rail_c), 0.04, (st["x"] + dx, d, -st["low"]), (st["x"] + dx, top, -st["high"]), segs=6)
                m.rod(K("wood", rail_c), 0.03, (st["x"] + dx, d + 0.9, -st["low"]), (st["x"] + dx, top + 0.9, -st["high"]), segs=6)


def rails(m, sp, look):
    """A capping rail along the bulwark top (following the sheer)."""
    d, bul = sp["deck"], sp["bulwark"]
    for side in (1, -1):
        prev = None
        for z, hw in sp["outline"]:
            p = (side * (max(hw, 0.08) - 0.05), d + bul + sheer(sp, look, z) + 0.03, -z)
            if prev:
                m.rod(K("wood", look.get("rail", (0.3, 0.2, 0.12))), 0.07, prev, p, segs=6)
            prev = p


def gunports(m, sp, look, rows=1):
    """Gun ports at the cannon places: a dark opening in the side with its lid swung up; a second row below on the
    galleon (lids shut, painted)."""
    d = sp["deck"]
    for cx, cz in sp.get("cannons", []):
        side = 1 if cx > 0 else -1
        w = half(sp, cz) + 0.04
        for row in range(rows):
            y = d + 0.45 if row == 0 else d - 0.95
            m.box(K("paint", (0.05, 0.04, 0.03)), (0.05, 0.5, 0.55), (side * w, y, -cz))
            if row == 0:
                m.box(K("paint", look["strake"]), (0.05, 0.08, 0.6), (side * (w + 0.18), y + 0.42, -cz), tilt=0)
                m.box(K("paint", look["strake"]), (0.4, 0.05, 0.6), (side * (w + 0.2), y + 0.3, -cz))
            else:
                m.box(K("paint", look["strake"]), (0.06, 0.5, 0.55), (side * (w + 0.01), y, -cz))


# ----------------------------------------------------------------------------------------------- rigs

def _sheet(m, mat, corners, node, belly=0.0, cols=6, rows=5):
    """A sail as a closed thin sheet over four corners (x, y, f) [top-left, top-right, bottom-right, bottom-left],
    bellied along +f (forward) by `belly`."""
    bm = bmesh.new()
    tl, tr, br, bl = corners
    across = [tr[i] - tl[i] + br[i] - bl[i] for i in range(3)]
    down = [bl[i] - tl[i] + br[i] - tr[i] for i in range(3)]
    n = [across[1] * down[2] - across[2] * down[1], across[2] * down[0] - across[0] * down[2], across[0] * down[1] - across[1] * down[0]]
    ln = math.sqrt(sum(c * c for c in n)) or 1.0
    n = [c / ln for c in n]
    if abs(n[2]) > 0.5 and n[2] < 0.0 or abs(n[2]) <= 0.5 and n[0] < 0.0:
        n = [-c for c in n]  # square sails belly forward (+f), fore-and-aft sails to starboard
    def at(u, v, off):
        top = [tl[i] + (tr[i] - tl[i]) * u for i in range(3)]
        low = [bl[i] + (br[i] - bl[i]) * u for i in range(3)]
        p = [top[i] + (low[i] - top[i]) * v for i in range(3)]
        push = belly * math.sin(math.pi * u) * math.sin(math.pi * min(v * 1.1, 1.0)) + off  # along the sail's normal
        return (p[0] + n[0] * push, p[2] + n[2] * push, p[1] + n[1] * push)  # kit order (x, up, f) -> Blender (x, f, up)
    layers = []
    for off in (0.0, 0.035):
        layers.append([[bm.verts.new(at(c / cols, r / rows, off)) for c in range(cols + 1)] for r in range(rows + 1)])
    a, b = layers
    for r in range(rows):
        for c in range(cols):
            bm.faces.new((a[r][c], a[r][c + 1], a[r + 1][c + 1], a[r + 1][c])[::-1])
            bm.faces.new((b[r][c], b[r][c + 1], b[r + 1][c + 1], b[r + 1][c]))
    edge = [(0, c) for c in range(cols)] + [(r, cols) for r in range(rows)] + [(rows, c) for c in range(cols, 0, -1)] + [(r, 0) for r in range(rows, 0, -1)]
    for k in range(len(edge)):
        r0, c0 = edge[k]
        r1, c1 = edge[(k + 1) % len(edge)]
        bm.faces.new((a[r0][c0], a[r1][c1], b[r1][c1], b[r0][c0]))
    m._add(bm, mat, node, 0)


def mast(m, sp, mz, height, rake=0.0, base=None):
    d = deck_at(sp, mz) if base is None else base
    top = (0.0, sp["deck"] + height, -mz + rake)
    m.rod(K("wood", (0.4, 0.28, 0.16)), 0.13 + height * 0.006, (0.0, d - 0.2, -mz), top, r2=0.07, segs=12)
    m.ball(K("wood", (0.3, 0.2, 0.12)), (0.15, 0.1, 0.15), top)
    return top


def square_stack(m, sp, mz, height, suffix, tiers, wide, stripes=None):
    """A square-rigged mast: yards and sails stacked (course, topsail, topgallant), each smaller, tops between."""
    d = sp["deck"]
    top = mast(m, sp, mz, height)
    yard_node, sail_node = "Yard" + suffix, "Sail" + suffix
    pivot = (0.0, top[1] - 1.0, -mz)
    m.node(yard_node, pivot)
    m.node(sail_node, pivot, parent=yard_node)
    low = deck_at(sp, mz) + 2.4
    span = (top[1] - 1.0 - low)
    for k in range(tiers):
        y_hi = low + span * (k + 1) / tiers
        y_lo = low + span * k / tiers + (0.25 if k else 0.0)
        w = wide * (1.0 - 0.18 * k)
        m.rod(K("wood", (0.4, 0.28, 0.16)), 0.08 - 0.012 * k, (-w - 0.3, y_hi, -mz + 0.18), (w + 0.3, y_hi, -mz + 0.18), segs=8, node=yard_node)
        colour = SAILCLOTH if not stripes or k % 2 == 0 else stripes
        _sheet(m, K("paint", colour), [(-w, y_hi - 0.1, -mz + 0.3), (w, y_hi - 0.1, -mz + 0.3), (w * 1.08, y_lo, -mz + 0.3), (-w * 1.08, y_lo, -mz + 0.3)], sail_node, belly=0.5)
        if k < tiers - 1:
            m.box(K("wood", (0.3, 0.2, 0.12)), (1.2, 0.1, 0.9), (0.0, y_hi + 0.1, -mz))  # top (platform)
    _shrouds(m, sp, mz, top[1] - 1.0)
    return top


def _shrouds(m, sp, mz, y_top):
    d = deck_at(sp, mz)
    for side in (1, -1):
        for df in (-1.0, 0.0, 1.0):
            f = -mz + df
            hw = max(half(sp, -f), 0.3)
            m.rod(K("leather", ROPE), 0.018, (0.0, y_top, -mz), (side * (hw + 0.05), d + sp["bulwark"], f), segs=4)
        for k in range(1, 7):  # ratlines
            t = k / 7.0
            y = d + sp["bulwark"] + (y_top - d - sp["bulwark"]) * t
            hw = max(half(sp, mz), 0.3) * (1.0 - t)
            m.rod(K("leather", ROPE), 0.01, (side * hw, y, -mz - 1.0 * (1 - t)), (side * hw, y, -mz + 1.0 * (1 - t)), segs=3)


def gaff_rig(m, sp, mz, height):
    """The sloop: one mast with a boom and gaff and a four-sided mainsail behind it (fore and aft), a jib on the
    forestay to the bowsprit."""
    d = sp["deck"]
    top = mast(m, sp, mz, height)
    pivot = (0.0, d + 1.6, -mz)
    m.node("Yard", pivot)
    m.node("Sail", (0.0, top[1] - 1.4, -mz), parent="Yard")
    boom_len = (sp["outline"][0][0] - mz) * 0.95
    boom_end = (0.0, d + 1.6, -mz - boom_len)
    m.rod(K("wood", (0.4, 0.28, 0.16)), 0.08, (0.0, d + 1.6, -mz - 0.2), boom_end, segs=8, node="Yard")
    gaff_end = (0.0, top[1] - 0.4, -mz - boom_len * 0.75)
    m.rod(K("wood", (0.4, 0.28, 0.16)), 0.06, (0.0, top[1] - 1.6, -mz - 0.2), gaff_end, segs=8, node="Yard")
    _sheet(m, K("paint", SAILCLOTH), [(0.0, top[1] - 1.7, -mz - 0.3), gaff_end, (0.0, boom_end[1] + 0.1, boom_end[2] + 0.2), (0.0, d + 1.75, -mz - 0.3)], "Sail", belly=0.0)
    bow = -sp["outline"][-1][0]
    sprit = (0.0, d + 1.5, bow + 3.0)
    m.rod(K("wood", (0.4, 0.28, 0.16)), 0.1, (0.0, d + 0.7, bow - 1.2), sprit, r2=0.06, segs=10)
    m.node("Jib", (0.0, top[1] - 1.0, -mz))
    _sheet(m, K("paint", SAILCLOTH), [(0.0, top[1] - 1.1, -mz + 0.3), (0.0, top[1] - 1.1, -mz + 0.3), (0.0, sprit[1] + 0.2, sprit[2] - 0.3), (0.0, d + 1.6, -mz + 1.2)], "Jib", belly=0.0, cols=2, rows=5)
    m.rod(K("leather", ROPE), 0.02, (0.0, top[1] - 1.0, -mz), sprit, segs=4)
    m.rod(K("leather", ROPE), 0.02, (0.0, top[1] - 1.0, -mz), (0.0, d + sp["bulwark"], -sp["outline"][0][0] + 0.3), segs=4)
    _shrouds(m, sp, mz, top[1] - 1.2)
    return top


def lateen(m, sp, mz, height, suffix):
    """The galleon's mizzen: a long yard slung at a slant with a triangular sail under it."""
    top = mast(m, sp, mz, height)
    yard_node, sail_node = "Yard" + suffix, "Sail" + suffix
    pivot = (0.0, top[1] - 2.5, -mz)
    m.node(yard_node, pivot)
    m.node(sail_node, pivot, parent=yard_node)
    fore = (0.0, top[1] - 5.5, -mz + 3.5)
    aft = (0.0, top[1] + 0.5, -mz - 6.0)
    m.rod(K("wood", (0.4, 0.28, 0.16)), 0.07, fore, aft, segs=8, node=yard_node)
    foot = (0.0, deck_at(sp, mz) + 2.2, -mz - 4.5)
    _sheet(m, K("paint", SAILCLOTH), [fore, aft, foot, (0.0, fore[1] - 0.2, fore[2] - 0.1)], sail_node, cols=6, rows=5)
    _shrouds(m, sp, mz, top[1] - 2.0)


def batten_rig(m, sp, mz, height, suffix, rake):
    """A junk mast raked forward with a battened lug sail fanning out aft of it, deep red with dark battens."""
    top = mast(m, sp, mz, height, rake=rake)
    yard_node, sail_node = "Yard" + suffix, "Sail" + suffix
    d = deck_at(sp, mz)
    pivot = (0.0, top[1] - 0.6, -mz + rake)
    m.node(yard_node, pivot)
    m.node(sail_node, pivot, parent=yard_node)
    length = height * 0.55
    rows = 7
    lines = []
    for r in range(rows + 1):
        v = r / rows
        y = top[1] - 0.6 - (top[1] - 0.6 - d - 2.0) * v
        mast_f = -mz + rake * (1.0 - v)
        fore = mast_f + length * (0.22 + 0.05 * v)
        aft = mast_f - length * (0.55 + 0.45 * v ** 0.8)  # fans out towards the foot
        lines.append((y + 0.5 * (1.0 - v) * 0.0, fore, aft))
    for r in range(rows):
        y0, f0, a0 = lines[r]
        y1, f1, a1 = lines[r + 1]
        _sheet(m, K("paint", (0.62, 0.24, 0.14) if r % 2 == 0 else (0.56, 0.21, 0.12)), [(0.0, y0, f0), (0.0, y0 + (a0 - f0) * -0.08, a0), (0.0, y1 + (a1 - f1) * -0.08, a1), (0.0, y1, f1)], sail_node, cols=4, rows=1)
    for y, f, a in lines:
        m.rod(K("wood", (0.12, 0.1, 0.08)), 0.035, (0.0, y, f + 0.1), (0.0, y + (a - f) * -0.08, a - 0.1), segs=5, node=sail_node)
    for y, f, a in lines[1:]:  # sheets fanning from the battens' ends to the deck
        m.rod(K("leather", ROPE), 0.01, (0.0, y + (a - f) * -0.08, a), (0.0, d + 0.9, -mz - length * 0.9), segs=3)


def pennant(m, at):
    m.node("Pennant", at)
    bm = bmesh.new()
    pts = [(0.0, 0.0), (0.0, -0.5), (-1.6, -0.25)]
    a = [bm.verts.new((at[0] - 0.01, at[2] + p[0], at[1] + p[1])) for p in pts]
    b = [bm.verts.new((at[0] + 0.01, at[2] + p[0], at[1] + p[1])) for p in pts]
    bm.faces.new(a)
    bm.faces.new(b[::-1])
    for k in range(3):
        j = (k + 1) % 3
        bm.faces.new((a[k], b[k], b[j], a[j]))
    m._add(bm, K("cloth", (0.75, 0.12, 0.1)), "Pennant", 0)


def bowsprit_jibs(m, sp, fore_z, fore_top, count, spritsail=False):
    d = sp["deck"]
    bow = -sp["outline"][-1][0]
    base = deck_at(sp, sp["outline"][-1][0] + 1.0)
    sprit = (0.0, base + 2.4, bow + 5.0)
    m.rod(K("wood", (0.4, 0.28, 0.16)), 0.16, (0.0, base + 0.6, bow - 1.6), sprit, r2=0.08, segs=10)
    m.node("Jib", (0.0, fore_top - 1.0, -fore_z))
    for k in range(count):
        t = (k + 1) / (count + 0.5)
        tip = (0.0, base + 0.6 + (sprit[1] - base - 0.6) * t, bow - 1.6 + (sprit[2] - bow + 1.6) * t)
        head = (0.0, fore_top - 1.5 - k * 1.2, -fore_z + 0.3)
        _sheet(m, K("paint", SAILCLOTH), [head, head, tip, (0.0, base + 1.4 + k * 0.2, -fore_z + 2.5 + k)], "Jib", cols=2, rows=4)
        m.rod(K("leather", ROPE), 0.018, head, tip, segs=4)
    if spritsail:
        y = sprit[1] - 1.0
        f = sprit[2] - 1.4
        m.rod(K("wood", (0.4, 0.28, 0.16)), 0.06, (-2.2, y + 0.6, f), (2.2, y + 0.6, f), segs=6)
        _sheet(m, K("paint", SAILCLOTH), [(-2.0, y + 0.5, f + 0.1), (2.0, y + 0.5, f + 0.1), (2.2, y - 1.6, f + 0.1), (-2.2, y - 1.6, f + 0.1)], "Jib", belly=0.3, cols=4, rows=3)
    return sprit


# ----------------------------------------------------------------------------------------------- helm, anchor, oars, ladders

def wheel(m, sp):
    hx, hz = sp["helm"]
    d = deck_at(sp, hz)
    f = -hz
    m.box(K("timber", (0.24, 0.16, 0.1)), (0.35, 1.0, 0.3), (hx, d + 0.5, f - 0.15))
    axle = d + 1.05
    m.node("Wheel", (hx, axle, f + 0.05))
    m.cyl(K("timber", (0.24, 0.16, 0.1)), 0.09, f - 0.05, f + 0.15, y=axle, x=hx, segs=12, node="Wheel")
    n = 16
    for k in range(n):
        a0, a1 = 2 * math.pi * k / n, 2 * math.pi * (k + 1) / n
        m.rod(K("wood", (0.42, 0.28, 0.16)), 0.035, (hx + 0.55 * math.cos(a0), axle + 0.55 * math.sin(a0), f + 0.05), (hx + 0.55 * math.cos(a1), axle + 0.55 * math.sin(a1), f + 0.05), segs=6, node="Wheel")
    for k in range(8):
        a = 2 * math.pi * k / 8
        m.rod(K("wood", (0.42, 0.28, 0.16)), 0.025, (hx, axle, f + 0.05), (hx + 0.78 * math.cos(a), axle + 0.78 * math.sin(a), f + 0.05), segs=6, node="Wheel")
        m.ball(K("wood", (0.3, 0.2, 0.12)), 0.045, (hx + 0.8 * math.cos(a), axle + 0.8 * math.sin(a), f + 0.05), node="Wheel", u=6, v=4)


def steering_oar(m, sp):
    hx, hz = sp["helm"]
    d = deck_at(sp, hz)
    f = -hz
    side = 1 if hx >= 0 else -1
    pivot = (side * max(half(sp, hz + 0.6), 0.4), d + sp["bulwark"] + 0.1, f - 0.6)
    m.node("Wheel", pivot)
    m.rod(K("wood", (0.42, 0.28, 0.16)), 0.06, (pivot[0] - side * 1.4, d + 1.0, f + 0.6), (pivot[0] + side * 0.6, -0.8, f - 2.6), segs=8, node="Wheel")
    m.box(K("wood", (0.42, 0.28, 0.16)), (0.08, 0.9, 0.35), (pivot[0] + side * 0.62, -0.95, f - 2.75), node="Wheel")
    m.box(K("timber", (0.24, 0.16, 0.1)), (0.2, 0.25, 0.25), pivot)


def junk_rudder(m, sp):
    """The junk's huge rudder hanging below the stern and its long tiller across the stern castle (the Wheel node)."""
    hx, hz = sp["helm"]
    d = deck_at(sp, hz)
    stern = -sp["outline"][0][0]
    m.box(K("timber", (0.2, 0.14, 0.09)), (0.18, sp["draft"] + d + 1.0, 1.9), (0.0, (d + 1.0 - sp["draft"] - 0.6) * 0.5, stern - 1.2))  # blade
    m.rod(K("timber", (0.2, 0.14, 0.09)), 0.12, (0.0, -sp["draft"], stern - 0.4), (0.0, d + 0.4, stern - 0.4), segs=8)  # stock
    m.node("Wheel", (0.0, d + 0.6, stern - 0.4))
    m.rod(K("wood", (0.42, 0.28, 0.16)), 0.07, (0.0, d + 0.6, stern - 0.4), (0.0, d + 0.85, -hz + 0.2), segs=8, node="Wheel")


def anchor(m, sp):
    ax, az = sp["anchor"]
    d = deck_at(sp, az)
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
    m.box(K("wood", (0.42, 0.28, 0.16)), (0.08, 0.08, 0.9), (x, d + 0.42, f), node="Anchor")
    m.node("AnchorRope", (x, d + 0.4, f))
    m.rod(K("leather", ROPE), 0.04, (x, d + 0.4, f), (x + 0.6, -8.0, f + 2.5), node="AnchorRope", segs=6)


def oars(m, sp):
    d, bul = sp["deck"], sp["bulwark"]
    length = sp["outline"][0][0] - sp["outline"][-1][0]
    n = max(3, int(length / 2.6))
    for name, side in (("OarsR", 1), ("OarsL", -1)):
        m.node(name, (side * half(sp, 0.0), d + bul, 0.0))
        for k in range(n):
            f = -length * 0.32 + k * length * 0.64 / (n - 1)
            x = side * half(sp, -f)
            reach = 2.0 + d * 1.2
            m.rod(K("wood", (0.42, 0.28, 0.16)), 0.04, (x - side * 0.8, d + bul + 0.35, f), (x + side * reach, -0.05, f - 0.6), node=name, segs=6)
            m.box(K("wood", (0.42, 0.28, 0.16)), (0.06, 0.5, 0.18), (x + side * (reach + 0.15), -0.12, f - 0.66), node=name)


def ladders(m, sp):
    d, bul = sp["deck"], sp["bulwark"]
    if d < 0.6:
        return
    f = -sp["ladder_z"]
    for side in (1, -1):
        x = side * (half(sp, sp["ladder_z"]) + 0.1)
        top, low = d + bul + 0.05, -0.8
        for df in (-0.24, 0.24):
            m.rod(K("leather", ROPE), 0.022, (x, top + 0.1, f + df), (x + side * 0.05, low, f + df), segs=5)
        y = top - 0.25
        while y > low + 0.1:
            m.rod(K("wood", (0.42, 0.28, 0.16)), 0.025, (x + side * 0.03, y, f - 0.26), (x + side * 0.03, y, f + 0.26), segs=6)
            y -= 0.32


# ----------------------------------------------------------------------------------------------- the six ships

def build_sloop(m, sp):
    look = LOOK["sloop"]
    hull_round(m, sp, look)
    bulwark_walls(m, sp, look, (0.42, 0.32, 0.2))
    deck(m, sp, look)
    rails(m, sp, look)
    gunports(m, sp, look)
    top = gaff_rig(m, sp, sp["masts"][0][0], sp["masts"][0][1])
    pennant(m, (0.0, top[1] + 0.1, top[2]))
    m.box(K("timber", (0.3, 0.22, 0.14)), (1.6, 0.6, 2.2), (0.0, sp["deck"] + 0.3, -3.2))  # cabin trunk aft
    for wx in (-0.81, 0.81):
        m.box((fk.GLOW, GLASS), (0.02, 0.22, 0.4), (wx, sp["deck"] + 0.38, -3.2))
    m.loft(K("paint", look["strake"]), [(0.0, sp["deck"] - 0.2, -sp["outline"][-1][0] - 0.2, 0.08, 0.1), (0.0, sp["deck"] + 0.5, -sp["outline"][-1][0] + 0.4, 0.1, 0.12)], segs=8)  # scroll head
    wheel(m, sp)


def build_brig(m, sp):
    look = LOOK["brig"]
    hull_round(m, sp, look, tumble=0.4)
    bulwark_walls(m, sp, look, (0.36, 0.26, 0.16))
    deck(m, sp, look)
    rails(m, sp, look)
    levels(m, sp, look, "brig")
    gunports(m, sp, look)
    tops = []
    for i, (mz, h) in enumerate(sp["masts"]):
        tops.append(square_stack(m, sp, mz, h, "" if i == 0 else str(i + 1), 3, 3.2 - 0.2 * i))
    fore = max(sp["masts"], key=lambda q: -q[0])
    bowsprit_jibs(m, sp, fore[0], sp["deck"] + fore[1], 2)
    pennant(m, (0.0, max(t[1] for t in tops) + 0.1, tops[1][2]))
    m.loft(K("paint", (0.9, 0.88, 0.82)), [(0.0, sp["deck"] - 0.4, -sp["outline"][-1][0] - 0.3, 0.16, 0.2), (0.0, sp["deck"] + 0.4, -sp["outline"][-1][0] + 0.35, 0.2, 0.24), (0.0, sp["deck"] + 1.0, -sp["outline"][-1][0] + 0.5, 0.15, 0.17)], segs=10)  # figurehead
    wheel(m, sp)


def build_galleon(m, sp):
    look = LOOK["galleon"]
    hull_round(m, sp, look, tumble=1.0)
    bulwark_walls(m, sp, look, (0.42, 0.26, 0.16))
    deck(m, sp, look)
    rails(m, sp, look)
    levels(m, sp, look, "galleon")
    gunports(m, sp, look, rows=2)
    stern = -sp["outline"][0][0]
    hw = sp["outline"][0][1]
    d = sp["deck"]
    top = d + 3.8
    m.box(K("timber", look["hull"]), (hw * 2.0, top - d + 1.2, 0.2), (0.0, (top + d) * 0.5 + 0.6, stern - 0.05))  # high transom
    for row, y in enumerate((d + 1.0, d + 2.8)):  # stern gallery windows
        for k in range(5):
            x = -hw * 0.72 + k * hw * 0.36
            m.box(K("paint", GOLD), (0.6, 0.72, 0.06), (x, y, stern - 0.17))
            m.box((fk.GLOW, GLASS), (0.48, 0.58, 0.04), (x, y, stern - 0.21))
        m.box(K("paint", GOLD), (hw * 2.1, 0.12, 0.6), (0.0, y - 0.5, stern - 0.3))  # balcony
    for side in (1, -1):  # quarter galleries
        m.box(K("timber", look["strake"]), (0.7, 2.6, 2.6), (side * (hw + 0.2), d + 2.0, stern + 1.6))
        m.box((fk.GLOW, GLASS), (0.04, 0.7, 1.4), (side * (hw + 0.56), d + 2.2, stern + 1.6))
        m.rod(K("metal", IRON), 0.03, (side * (hw - 0.1), top + 1.0, stern - 0.1), (side * (hw + 0.5), top + 2.4, stern + 0.4), segs=6)
        m.ball((fk.GLOW, (1.0, 0.8, 0.45)), (0.16, 0.24, 0.16), (side * (hw + 0.55), top + 2.25, stern + 0.45), u=8, v=6)
    tops = []
    masts = sorted(sp["masts"], key=lambda q: q[0])  # fore first (most negative z)
    for i, (mz, h) in enumerate(sp["masts"]):
        suffix = "" if i == 0 else str(i + 1)
        if mz == max(q[0] for q in masts):
            lateen(m, sp, mz, h, suffix)
        else:
            tops.append(square_stack(m, sp, mz, h, suffix, 2, 4.2))
    fore = masts[0]
    bowsprit_jibs(m, sp, fore[0], d + fore[1], 0, spritsail=True)
    pennant(m, (0.0, max(t[1] for t in tops) + 0.1, tops[0][2]))
    m.rod(K("wood", (0.3, 0.2, 0.12)), 0.05, (0.0, top + 1.0, stern), (0.0, top + 4.0, stern + 1.0), segs=6)  # ensign staff
    _sheet(m, K("paint", (0.62, 0.1, 0.1)), [(0.0, top + 3.9, stern + 0.95), (0.0, top + 3.9, stern - 1.4), (0.0, top + 2.6, stern - 1.4), (0.0, top + 2.6, stern + 0.6)], "Body", cols=3, rows=2)
    bow = -sp["outline"][-1][0]
    m.loft(K("paint", GOLD), [(0.0, d - 0.3, bow - 0.6, 0.25, 0.3), (0.0, d + 0.6, bow + 0.7, 0.28, 0.32), (0.0, d + 1.0, bow + 1.3, 0.22, 0.28)], segs=10)  # lion
    m.ball(K("paint", GOLD), (0.3, 0.32, 0.36), (0.0, d + 1.15, bow + 1.45))
    wheel(m, sp)


def build_raft(m, sp):
    d = sp["deck"]
    stern, bow = -sp["outline"][0][0], -sp["outline"][-1][0]
    hw = sp["outline"][0][1]
    n = 7
    r = hw / n
    for k in range(n):
        x = -hw + r + k * 2 * r
        tip = 0.35 * (1.0 - abs(x) / hw)
        m.cyl(K("bark", (0.42, 0.32, 0.22)), r * 0.98, stern + 0.1 * (k % 2), bow + tip, y=d - r, x=x, segs=10)
    for f in (stern + 0.6, (stern + bow) * 0.5, bow - 0.6):
        m.box(K("wood", (0.45, 0.32, 0.2)), (hw * 2.0 + 0.1, 0.12, 0.22), (0.0, d + 0.02, f))
        for side in (1, -1):
            m.ball(K("leather", ROPE), (0.06, 0.16, 0.14), (side * (hw - 0.05), d - 0.1, f), u=6, v=4)
    top = square_stack(m, sp, sp["masts"][0][0], sp["masts"][0][1], "", 1, 1.6)
    pennant(m, (0.0, top[1] + 0.1, top[2]))
    m.box(K("wood", (0.45, 0.32, 0.2)), (0.7, 0.4, 0.5), (0.8, d + 0.2, stern + 0.8))  # a crate lashed on
    steering_oar(m, sp)


def build_longboat(m, sp):
    look = LOOK["longboat"]
    hull_clinker(m, sp, look)
    bulwark_walls(m, sp, look, (0.32, 0.22, 0.13), start=sp["deck"] - 0.1, thick=0.08)
    d = sp["deck"]
    stern, bow = -sp["outline"][0][0], -sp["outline"][-1][0]
    wood = (0.34, 0.22, 0.12)
    gun = d + sp["bulwark"]
    neck = [(0.0, gun + 1.2, bow - 0.2, 0.18, 0.22), (0.0, gun + 2.2, bow + 0.3, 0.16, 0.2), (0.0, gun + 3.0, bow + 0.25, 0.15, 0.18), (0.0, gun + 3.5, bow + 0.7, 0.16, 0.2)]
    m.loft(K("wood", wood), [(0.0, -0.2, bow - 0.9, 0.12, 0.2), (0.0, gun, bow - 0.5, 0.14, 0.22)] + neck, segs=10)  # stem up into the neck
    m.ball(K("wood", wood), (0.22, 0.2, 0.42), (0.0, gun + 3.6, bow + 1.05))  # head
    m.box(K("wood", wood), (0.16, 0.1, 0.36), (0.0, gun + 3.42, bow + 1.32))  # jaw
    for side in (1, -1):
        m.ball(K("paint", (0.95, 0.78, 0.2)), 0.05, (side * 0.15, gun + 3.72, bow + 1.2), u=6, v=4)
        m.rod(K("wood", wood), 0.035, (side * 0.1, gun + 3.75, bow + 0.85), (side * 0.22, gun + 4.15, bow + 0.55), segs=5)
        m.rod(K("wood", wood), 0.025, (side * 0.18, gun + 3.3, bow + 0.7), (side * 0.32, gun + 3.0, bow + 0.4), segs=4)  # whiskers
    tail = [(0.0, -0.2, stern + 0.9, 0.12, 0.2), (0.0, gun, stern + 0.5, 0.14, 0.22), (0.0, gun + 1.5, stern + 0.1, 0.12, 0.16), (0.0, gun + 2.4, stern + 0.4, 0.1, 0.12), (0.0, gun + 2.5, stern + 0.9, 0.08, 0.09), (0.0, gun + 2.1, stern + 1.1, 0.06, 0.07)]
    m.loft(K("wood", wood), tail, segs=10)  # stern post curling over
    colours = [(0.72, 0.16, 0.12), (0.92, 0.84, 0.58), (0.18, 0.3, 0.55), (0.25, 0.42, 0.24)]
    for side in (1, -1):  # shields hung over the gunwale, overlapping
        for k in range(11):
            z = -6.5 + k * 1.3
            x = side * (half(sp, z) + 0.16)
            y = gun + sheer(sp, look, z) - 0.15
            m.cylx(K("paint", colours[k % 4]), 0.45, x, x + side * 0.05, -z, y, segs=18)
            m.cylx(K("metal", IRON), 0.1, x + side * 0.05, x + side * 0.12, -z, y, segs=10)
            m.rod(K("paint", (0.1, 0.08, 0.06)), 0.02, (x + side * 0.055, y - 0.42, -z), (x + side * 0.055, y + 0.42, -z), segs=4)
    top = square_stack(m, sp, sp["masts"][0][0], sp["masts"][0][1], "", 1, 3.4, stripes=None)
    stripes = sp.get("stripes")
    if stripes:  # broad red stripes over the sail (they furl with it)
        mz = sp["masts"][0][0]
        y_hi, y_lo = top[1] - 1.1, d + 2.4
        for k in (-2, 0, 2):
            x0 = k * 0.62
            _sheet(m, K("paint", tuple(stripes)), [(x0 - 0.3, y_hi, -mz + 0.36), (x0 + 0.3, y_hi, -mz + 0.36), (x0 * 1.08 + 0.32, y_lo, -mz + 0.36), (x0 * 1.08 - 0.32, y_lo, -mz + 0.36)], "Sail", belly=0.5, cols=2, rows=5)
    pennant(m, (0.0, top[1] + 0.1, top[2]))
    oars(m, sp)
    steering_oar(m, sp)


def build_junk(m, sp):
    look = LOOK["junk"]
    hull_junk(m, sp, look)
    bulwark_walls(m, sp, look, (0.36, 0.22, 0.14))
    deck(m, sp, look)
    levels(m, sp, look, "junk")
    d = sp["deck"]
    stern = -sp["outline"][0][0]
    hw = sp["outline"][0][1]
    castle = sp["levels"][0]
    ctop = d + castle["height"]
    # the towering stern: side walls rising and hanging out aft, a curved top, painted panels
    for side in (1, -1):
        solid(m, K("paint", look["strake"]), [[(side * (hw - 0.1), stern + 4.8, ctop), (side * hw, stern + 4.8, ctop), (side * hw, stern + 4.8, ctop + 1.2), (side * (hw - 0.1), stern + 4.8, ctop + 1.2)],
            [(side * (hw - 0.1), stern - 1.0, ctop + 1.0), (side * (hw + 0.05), stern - 1.0, ctop + 1.0), (side * (hw + 0.05), stern - 1.0, ctop + 2.6), (side * (hw - 0.1), stern - 1.0, ctop + 2.6)]])
    m.box(K("paint", look["strake"]), (hw * 2.1, 2.6, 0.18), (0.0, ctop + 1.0, stern - 1.0))  # overhanging stern board
    m.box(K("paint", (0.92, 0.75, 0.25)), (hw * 1.2, 0.9, 0.04), (0.0, ctop + 1.4, stern - 1.1))  # painted panel
    m.box(K("paint", look["rail"]), (hw * 2.3, 0.16, 0.5), (0.0, ctop + 2.35, stern - 1.0))
    for side in (1, -1):  # ladder-like rails along the waist
        for z in range(-8, 5):
            x = side * (half(sp, z) - 0.05)
            m.rod(K("paint", look["rail"]), 0.03, (x, d + sp["bulwark"] - 0.4, -z), (x, d + sp["bulwark"] + 0.05, -z), segs=4)
        prev = None
        for z, hw2 in sp["outline"]:
            p = (side * (max(hw2, 0.08) - 0.05), d + sp["bulwark"] + sheer(sp, look, z) + 0.05, -z)
            if prev:
                m.rod(K("paint", look["rail"]), 0.06, prev, p, segs=6)
            prev = p
        bow_z = sp["outline"][-1][0]
        x = side * (half(sp, bow_z + 1.4) + 0.04)
        m.cylx(K("paint", (0.96, 0.96, 0.9)), 0.42, x, x + side * 0.03, -(bow_z + 1.4), d * 0.62, segs=18)  # painted eye
        m.cylx(K("paint", (0.05, 0.05, 0.05)), 0.2, x + side * 0.03, x + side * 0.05, -(bow_z + 1.35), d * 0.62, segs=12)
    for i, (mz, h) in enumerate(sp["masts"]):
        batten_rig(m, sp, mz, h, "" if i == 0 else str(i + 1), 0.6 if i == 1 else 0.2)
    pennant(m, (0.0, d + max(q[1] for q in sp["masts"]) + 0.1, -sp["masts"][1][0] + 0.6))
    for k in range(3):  # lanterns along the stern
        m.ball((fk.GLOW, (1.0, 0.45, 0.2)), (0.18, 0.26, 0.18), (-1.2 + k * 1.2, ctop + 2.1, stern - 1.35), u=8, v=6)
    junk_rudder(m, sp)


BUILDERS = {"sloop": build_sloop, "brig": build_brig, "galleon": build_galleon, "raft": build_raft, "longboat": build_longboat, "junk": build_junk}


def build_ship(ship_id, sp):
    m = kit.Model("ship_" + ship_id, uv_scale=0.5, colored=True)
    BUILDERS[ship_id](m, sp)
    anchor(m, sp)
    if ship_id not in ("raft", "longboat"):  # the longboat's own oars come with its builder
        oars(m, sp)
    ladders(m, sp)
    print("ship_" + ship_id, m.export(OUT))


if __name__ == "__main__":
    fk.init()
    for ship_id, sp in DATA["ships"].items():
        if fk.ONLY and "ship_" + ship_id not in fk.ONLY:
            continue
        build_ship(ship_id, sp)
