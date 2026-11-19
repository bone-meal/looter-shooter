# Purpose: developer-time tool. The island kit's SET PIECES (director: "places to find" + landforms a height map cannot
# make): assets/models/sea/places/<id>.gltf, each placed once by an island's data (data/sea/isles/<island>.json
# "places") and made solid as it is (game/sea_isle_props.gd). A sea arch, a walk-in cave with glowing mushrooms, a
# lighthouse with the keeper's cottage, a beached wreck, a castaway camp, a wooden jetty, temple ruins on a stepped
# platform, a tide pool, a footbridge (where generated paths cross a river); the reef island's ruined SEA TEMPLE round the
# Tidewater Temple's gate and a broken lookout tower (sea step 9c-3); a small shrine round a puzzle vault's gate (9d);
# region 2 (R2a): Lanternwick's rest hall, the sunken chapel, the pitch works, the Hollow Mangrove, a barge, a bell buoy. Materials are named after what they are made of (fantasy_kit kinds); "glow" is drawn unshaded,
# "water" gets the game's water shader (game/isle_water.gd).
# Run: python3 tools/blender/sea_isle_places.py   (ONLY=lighthouse builds just that one)
# Dependencies: bpy, bmesh, tools/blender/kit.py, tools/blender/fantasy_kit.py. No game code.
import math
import os
import random
import sys

sys.path.insert(0, os.path.dirname(__file__))
import bpy  # noqa: F401
import bmesh
import kit
import fantasy_kit as fk
from fantasy_kit import K

OUT = os.path.join(os.path.dirname(__file__), "..", "..", "assets", "models", "sea", "places")
ROCK = (0.55, 0.52, 0.47)
STONE = (0.7, 0.67, 0.6)
WOOD = (0.5, 0.38, 0.26)
OLD_WOOD = (0.55, 0.5, 0.42)
LEAF = (0.25, 0.45, 0.18)
WATER = None


def sea_arch(m):
    """A natural rock arch 34 m wide and 22 m high, its legs standing in the sea (y 0 = sea level)."""
    rnd = random.Random(41)
    rings = []
    for k in range(13):
        a = math.pi * k / 12
        x = -17.0 * math.cos(a)
        y = -10.0 + 31.0 * math.sin(a) ** 0.8 if 0 < k < 12 else -12.0
        r = 6.5 - 2.2 * math.sin(a)
        rings.append((x, y, 0.0, r, r * 0.8))
    m.loft(K("rock", ROCK), rings, segs=7, steps=2)
    for k in range(48):  # rugged lumps all over it, so it reads as broken rock and not a tube
        a = rnd.uniform(0.0, math.pi)
        x = -17.0 * math.cos(a)
        y = -10.0 + 31.0 * max(math.sin(a), 0.05) ** 0.8
        r = 6.5 - 2.2 * math.sin(a)
        side = rnd.uniform(0, 6.28)
        off = (r * 0.55 * math.cos(side) * abs(math.cos(a)), r * 0.55 * math.sin(side), r * 0.6 * math.cos(side))
        fk.blob(m, K("rock", tuple(c * rnd.uniform(0.82, 1.05) for c in ROCK)), (rnd.uniform(3.0, 5.5), rnd.uniform(2.2, 4.0), rnd.uniform(3.0, 5.0)), (x + off[0], y + off[1], off[2]), seed=41 + k, rough=0.22, cuts=1)
    for k in range(16):  # the legs, rising out of the sea
        x = rnd.choice((-17.0, 17.0)) + rnd.uniform(-2.0, 2.0)
        fk.blob(m, K("rock", tuple(c * rnd.uniform(0.82, 1.05) for c in ROCK)), (rnd.uniform(3.5, 5.5), rnd.uniform(2.5, 4.0), rnd.uniform(3.5, 5.0)), (x * 1.08, rnd.uniform(-4.0, 8.0), rnd.uniform(-3.5, 3.5)), seed=100 + k, rough=0.22, cuts=1)
    for k in range(5):  # grass and shrubs on the crown
        x = rnd.uniform(-6, 6)
        fk.blob(m, K("leaf", LEAF), (2.4, 0.7, 2.0), (x, 21.5 - abs(x) * 0.25, rnd.uniform(-1.5, 1.5)), seed=60 + k, rough=0.3, cuts=1)


def _shell(m, mat, ro, ri, squash, door, seed):
    """A hollow dome (outer skin out, inner skin in) with a doorway: cells of (theta, phi) skipped by `door` are open,
    and every open or bottom edge is closed with a wall between the skins, so the shell is watertight."""
    rnd = random.Random(seed)
    nt, nph = 28, 9
    pmax = 1.5
    bm = bmesh.new()
    def r_at(i, j, base):
        return base * (1.0 + 0.08 * math.sin(i * 1.7 + seed) * math.cos(j * 2.3) + rnd.uniform(-0.03, 0.03))
    outer, inner = {}, {}
    for i in range(nt):
        th = 2 * math.pi * i / nt
        for j in range(nph + 1):
            ph = pmax * j / nph
            ro_ = r_at(i, j, ro)
            ri_ = ro_ - (ro - ri)
            for store, r in ((outer, ro_), (inner, ri_)):
                store[(i, j)] = bm.verts.new((r * math.cos(ph) * math.sin(th), r * math.cos(ph) * math.cos(th), r * math.sin(ph) * squash))
    top_o = bm.verts.new((0.0, 0.0, ro * squash))
    top_i = bm.verts.new((0.0, 0.0, ri * squash))
    def kept(i, j):
        return j >= 0 and not door(2 * math.pi * ((i % nt) + 0.5) / nt, pmax * (j + 0.5) / nph)
    for i in range(nt):
        n = (i + 1) % nt
        for j in range(nph):
            if not kept(i, j):
                continue
            bm.faces.new((outer[(i, j)], outer[(n, j)], outer[(n, j + 1)], outer[(i, j + 1)]))
            bm.faces.new((inner[(i, j + 1)], inner[(n, j + 1)], inner[(n, j)], inner[(i, j)]))
            edges = []
            if j == 0 or not kept(i, j - 1):
                edges.append(((i, j), (n, j)))
            if j + 1 < nph and not kept(i, j + 1):
                edges.append(((i, j + 1), (n, j + 1)))
            if not kept(i - 1, j):
                edges.append(((i, j), (i, j + 1)))
            if not kept(n, j):
                edges.append(((n, j), (n, j + 1)))
            for ea, eb in edges:  # a wall between the skins where the shell is open
                bm.faces.new((outer[ea], outer[eb], inner[eb], inner[ea]))
        bm.faces.new((outer[(i, nph)], outer[(n, nph)], top_o))
        bm.faces.new((top_i, inner[(n, nph)], inner[(i, nph)]))
    m._add(bm, mat, "Body", 0)


def cave(m):
    """A walk-in cave: a rocky dome 18 m across with a doorway facing +forward, stalagmites and glowing mushrooms."""
    rnd = random.Random(42)
    _shell(m, K("rock", ROCK), 9.0, 7.4, 0.72, lambda th, ph: abs(math.atan2(math.sin(th), math.cos(th))) < 0.42 and ph < 0.62, 42)
    for k in range(14):  # rubble over the outside
        a = rnd.uniform(0.6, 2 * math.pi - 0.6)
        fk.blob(m, K("rock", tuple(c * rnd.uniform(0.85, 1.05) for c in ROCK)), (rnd.uniform(1.5, 2.8), rnd.uniform(1.0, 2.0), rnd.uniform(1.5, 2.5)), (9.2 * math.sin(a), rnd.uniform(0.0, 2.0), 9.2 * math.cos(a)), seed=70 + k, rough=0.2, cuts=1)
    for k in range(4):
        fk.blob(m, K("leaf", LEAF), (2.5, 0.6, 2.2), (rnd.uniform(-4, 4), 6.0, rnd.uniform(-4, 4)), seed=90 + k, rough=0.3, cuts=1)
    for k in range(7):  # stalagmites inside
        a, d = rnd.uniform(0, 6.28), rnd.uniform(1.5, 5.5)
        if abs(math.atan2(math.sin(a - math.pi / 2), math.cos(a - math.pi / 2))) < 0.6:
            continue
        m.loft(K("rock", (0.5, 0.48, 0.44)), [(d * math.cos(a), 0.0, d * math.sin(a), 0.45, 0.45), (d * math.cos(a), rnd.uniform(1.0, 2.4), d * math.sin(a), 0.06, 0.06)], segs=6, steps=1)
    for k in range(10):  # glowing mushrooms
        a, d = rnd.uniform(0, 6.28), rnd.uniform(2.0, 6.5)
        x, z = d * math.cos(a), d * math.sin(a)
        h = rnd.uniform(0.15, 0.4)
        m.rod(K("paint", (0.85, 0.85, 0.78)), 0.03, (x, 0.0, z), (x, h, z), segs=4)
        m.ball(fk.GLOW, (0.12, 0.05, 0.12), (x, h, z), u=8, v=4)


def lighthouse(m):
    """A round stone lighthouse 20 m tall in white with red bands, gallery and lantern, and the keeper's cottage."""
    prof = []
    for k in range(9):
        t = k / 8
        prof.append((2.6 - 0.9 * t, 16.0 * t))
    for k, (a, b) in enumerate(zip(prof, prof[1:])):
        red = k in (2, 5)
        m.lathe(K("stone", (0.75, 0.22, 0.2) if red else (0.92, 0.9, 0.86)), [a, b], (0.0, 0.0, 0.0), segs=16)
    m.lathe(K("stone", (0.6, 0.58, 0.55)), [(3.2, -2.0), (3.2, 0.6), (2.9, 0.6)], (0.0, 0.0, 0.0), segs=16)  # plinth
    m.lathe(K("metal", (0.25, 0.25, 0.27)), [(2.4, 16.0), (2.4, 16.3)], (0.0, 0.0, 0.0), segs=16)  # gallery floor
    for k in range(16):  # railing
        a = 2 * math.pi * k / 16
        m.rod(K("metal", (0.25, 0.25, 0.27)), 0.035, (2.3 * math.cos(a), 16.3, 2.3 * math.sin(a)), (2.3 * math.cos(a), 17.3, 2.3 * math.sin(a)), segs=4)
    m.lathe(K("metal", (0.25, 0.25, 0.27)), [(2.32, 17.25), (2.32, 17.35)], (0.0, 0.0, 0.0), segs=16)
    m.lathe(fk.GLOW, [(1.25, 16.3), (1.25, 18.3)], (0.0, 0.0, 0.0), segs=12)  # the lamp room's glass
    for k in range(6):
        a = 2 * math.pi * k / 6
        m.rod(K("metal", (0.2, 0.2, 0.22)), 0.06, (1.3 * math.cos(a), 16.3, 1.3 * math.sin(a)), (1.3 * math.cos(a), 18.3, 1.3 * math.sin(a)), segs=4)
    m.lathe(K("metal", (0.65, 0.18, 0.15)), [(1.6, 18.3), (0.15, 19.8), (0.05, 20.3)], (0.0, 0.0, 0.0), segs=12)
    m.box(K("wood", (0.3, 0.22, 0.15)), (1.1, 2.1, 0.3), (0.0, 1.05, 2.55), bevel=0.02)  # door
    for y in (5.0, 9.5, 13.0):
        m.box(K("paint", (0.15, 0.18, 0.22)), (0.5, 0.8, 0.25), (0.0, y, 2.6 - 0.9 * y / 16.0 + 0.05), bevel=0.01)
    # keeper's cottage beside it
    m.box(K("stone", (0.88, 0.86, 0.8)), (5.0, 3.0, 4.0), (6.0, 1.5, 0.0), bevel=0.05)
    bm = bmesh.new()  # pitched roof (Blender order x, f, up)
    pts = [(3.3, -2.3, 3.0), (8.7, -2.3, 3.0), (8.7, 2.3, 3.0), (3.3, 2.3, 3.0), (3.3, 0.0, 4.8), (8.7, 0.0, 4.8)]
    v = [bm.verts.new(p) for p in pts]
    for f in ((v[0], v[1], v[5], v[4]), (v[2], v[3], v[4], v[5]), (v[0], v[4], v[3]), (v[1], v[2], v[5]), (v[0], v[3], v[2], v[1])):
        bm.faces.new(f)
    m._add(bm, K("slate", (0.5, 0.3, 0.25)), "Body", 0)
    m.box(K("wood", (0.3, 0.22, 0.15)), (1.0, 2.0, 0.2), (6.0, 1.0, 2.05), bevel=0.02)
    m.box(fk.GLOW, (0.8, 0.7, 0.1), (4.5, 1.8, 2.02), bevel=0.0)
    m.box(K("stone", (0.6, 0.58, 0.55)), (0.6, 2.2, 0.6), (7.6, 4.2, -1.0), bevel=0.03)  # chimney


def wreck(m):
    """A beached wreck: the ribs and torn planking of a two-masted ship lying on her side, a broken mast, cargo."""
    rnd = random.Random(44)
    L = 22.0
    tilt = 0.45  # how far she lies over
    def at(x, y, f):  # lay the hull over to starboard: rotate (x, y) about f
        c, s = math.cos(tilt), math.sin(tilt)
        return (x * c + y * s, -x * s + y * c + 1.2, f)
    keel = [at(0.0, -0.4, f) for f in (-L / 2, -L / 4, 0.0, L / 4, L / 2)]
    for a, b in zip(keel, keel[1:]):
        m.rod(K("wood", OLD_WOOD), 0.28, a, b, segs=6)
    for k in range(12):  # ribs
        f = -L / 2 + 1.5 + k * (L - 3.0) / 11
        w = 3.4 * math.sqrt(max(0.0, 1.0 - (f / (L * 0.55)) ** 2))
        broken = rnd.random() < 0.35
        pts = []
        for j in range(7):
            t = j / 6
            ang = math.pi * t
            pts.append(at(-w * math.cos(ang), -0.4 + 3.2 * math.sin(ang) * (1.0 if t < 0.5 or not broken else 0.6), f))
        last = 7 if not broken else 5
        for a, b in zip(pts[:last - 1], pts[1:last]):
            m.rod(K("wood", OLD_WOOD), 0.13, a, b, segs=5)
    for row in range(6):  # planking on the low side, torn on the high side
        t = row / 5
        for k in range(10):
            if row > 3 and rnd.random() < 0.6:
                continue
            f0 = -L / 2 + 1.0 + k * (L - 2.0) / 10
            f1 = f0 + (L - 2.0) / 10 + 0.05
            wd = 3.4 * math.sqrt(max(0.0, 1.0 - (((f0 + f1) / 2) / (L * 0.55)) ** 2))
            ang = math.pi * (0.06 + 0.4 * t)
            p = at(wd * math.cos(ang) * 1.02, -0.4 + 3.2 * math.sin(ang), 0.0)
            m.box(K("wood", tuple(c * rnd.uniform(0.85, 1.0) for c in OLD_WOOD)), (0.12, 0.5, f1 - f0), (p[0], p[1], (f0 + f1) / 2), bevel=0.01)
    m.rod(K("wood", OLD_WOOD), 0.25, at(0.5, 0.0, -3.0), (6.0, 0.3, -10.0), segs=8)  # the broken mast in the sand
    m.rod(K("wood", OLD_WOOD), 0.12, (4.0, 0.3, -7.6), (5.6, 0.25, -5.0), segs=6)
    for k in range(5):
        x, f = rnd.uniform(-6, 7), rnd.uniform(-8, 9)
        if k % 2:
            m.lathe(K("wood", (0.45, 0.32, 0.2)), [(0.32, 0.0), (0.38, 0.45), (0.32, 0.9)], (x, 0.0, f), segs=10)
        else:
            m.box(K("wood", (0.5, 0.38, 0.24)), (0.8, 0.7, 0.8), (x, 0.3, f), bevel=0.03)
    m.box(K("cloth", (0.82, 0.78, 0.68)), (3.0, 0.05, 2.2), (5.5, 0.08, 3.0), tilt=4.0, bevel=0.0)  # torn sail on the sand


def camp(m):
    """A castaway camp: a lean-to of poles and palm thatch, a canvas tent, a ringed fire pit with embers and a pot on a
    tripod, log seats, crates, barrels, a bedroll and a washing line."""
    rnd = random.Random(45)
    # canvas tent (A-frame), door to +forward
    bm = bmesh.new()
    w, d, h = 1.6, 2.4, 1.8
    pts = [(-w, -d, 0.0), (w, -d, 0.0), (0.0, -d, h), (-w, d, 0.0), (w, d, 0.0), (0.0, d, h)]
    v = [bm.verts.new((p[0] + 4.5, p[1] - 1.0, p[2])) for p in pts]
    for f in ((v[0], v[2], v[5], v[3]), (v[1], v[4], v[5], v[2]), (v[0], v[1], v[2])):
        bm.faces.new(f)
    # closed back + thickness: an inner skin
    vi = [bm.verts.new((p[0] * 0.95 + 4.5, p[1] * 0.98 - 1.0, p[2] * 0.95)) for p in pts]
    for f in ((vi[3], vi[5], vi[2], vi[0]), (vi[2], vi[5], vi[4], vi[1]), (vi[2], vi[1], vi[0])):
        bm.faces.new(f)
    for a, b in ((0, 3), (3, 5), (5, 4), (4, 1), (1, 0)):
        bm.faces.new((v[a], v[b], vi[b], vi[a]))
    m._add(bm, K("cloth", (0.78, 0.72, 0.58)), "Body", 0)
    for f in (-d - 1.0, d - 1.0):
        m.rod(K("wood", WOOD), 0.04, (4.5, 0.0, f), (4.5, h + 0.15, f), segs=5)
    # lean-to
    for x in (-5.5, -2.5):
        m.rod(K("wood", WOOD), 0.07, (x, 0.0, 1.5), (x, 2.4, 1.5), segs=6)
    m.rod(K("wood", WOOD), 0.06, (-5.7, 2.4, 1.5), (-2.3, 2.4, 1.5), segs=6)
    m.box(K("thatch", (0.6, 0.55, 0.3)), (3.8, 0.15, 3.2), (-4.0, 1.4, 0.2), tilt=40.0, bevel=0.02)
    m.box(K("cloth", (0.5, 0.35, 0.3)), (0.9, 0.12, 2.0), (-4.5, 0.06, 0.0), bevel=0.04)  # bedroll
    # fire pit
    for k in range(10):
        a = 2 * math.pi * k / 10
        fk.blob(m, K("rock", (0.45, 0.43, 0.4)), (0.25, 0.18, 0.22), (0.8 * math.cos(a), 0.08, 3.5 + 0.8 * math.sin(a)), seed=100 + k, rough=0.2, cuts=1)
    for k in range(4):
        a = k * math.pi / 4
        m.rod(K("wood", (0.25, 0.18, 0.12)), 0.07, (0.5 * math.cos(a), 0.08, 3.5 + 0.5 * math.sin(a)), (-0.5 * math.cos(a), 0.12, 3.5 - 0.5 * math.sin(a)), segs=5)
    m.ball(fk.GLOW, (0.35, 0.12, 0.35), (0.0, 0.1, 3.5), u=8, v=4)
    for k in range(3):  # tripod + pot
        a = 2 * math.pi * k / 3
        m.rod(K("wood", WOOD), 0.03, (0.9 * math.cos(a), 0.0, 3.5 + 0.9 * math.sin(a)), (0.0, 1.5, 3.5), segs=4)
    m.lathe(K("metal", (0.2, 0.2, 0.2)), [(0.05, 0.6), (0.28, 0.65), (0.3, 0.9), (0.26, 1.05)], (0.0, 0.0, 3.5), segs=10)
    for k in range(3):  # log seats
        a = 2 * math.pi * k / 3 + 0.4
        cx, cz = 2.0 * math.cos(a), 3.5 + 2.0 * math.sin(a)
        m.rod(K("bark", (0.42, 0.34, 0.26)), 0.22, (cx - 0.8 * math.sin(a), 0.2, cz + 0.8 * math.cos(a)), (cx + 0.8 * math.sin(a), 0.2, cz - 0.8 * math.cos(a)), segs=8)
    for k in range(4):  # cargo
        x, f = rnd.uniform(1.5, 3.5), rnd.uniform(-3.0, -1.0)
        if k % 2:
            m.lathe(K("wood", (0.45, 0.32, 0.2)), [(0.3, 0.0), (0.36, 0.45), (0.3, 0.9)], (x, 0.0, f), segs=10)
        else:
            m.box(K("wood", (0.5, 0.38, 0.24)), (0.7, 0.6, 0.7), (x, 0.3, f), bevel=0.03)
    for x in (-1.5, 1.5):  # washing line
        m.rod(K("wood", WOOD), 0.04, (x, 0.0, -4.0), (x, 1.9, -4.0), segs=4)
    m.rod(K("cloth", (0.8, 0.78, 0.7)), 0.01, (-1.5, 1.85, -4.0), (1.5, 1.85, -4.0), segs=3)
    for x, col in ((-0.8, (0.7, 0.3, 0.25)), (0.3, (0.35, 0.45, 0.7))):
        m.box(K("cloth", col), (0.6, 0.7, 0.02), (x, 1.5, -4.0), bevel=0.0)


def jetty(m):
    """A wooden jetty 30 m long out along +forward: deck 1.6 m above the sea, posts down into the sea bed, bollards,
    rope coils and a lantern post at the end. y 0 = sea level; its landward end at f 0."""
    rnd = random.Random(46)
    L, W, Y = 30.0, 3.2, 1.6
    for k in range(int(L / 0.55)):
        f = 0.3 + k * 0.55
        m.box(K("wood", tuple(c * rnd.uniform(0.85, 1.05) for c in WOOD)), (W, 0.12, 0.5), (rnd.uniform(-0.05, 0.05), Y, f), bevel=0.0)
    for k in range(7):
        f = 0.8 + k * (L - 1.0) / 6
        for x in (-W / 2 + 0.15, W / 2 - 0.15):
            m.rod(K("wood", (0.38, 0.3, 0.22)), 0.16, (x, -6.0, f), (x, Y + (0.9 if k % 2 == 0 else -0.06), f), segs=7)
        m.box(K("wood", (0.42, 0.32, 0.22)), (W + 0.2, 0.2, 0.25), (0.0, Y - 0.16, f), bevel=0.02)
    for x in (-W / 2 + 0.15, W / 2 - 0.15):  # stringers
        m.box(K("wood", (0.42, 0.32, 0.22)), (0.2, 0.25, L), (x, Y - 0.2, L / 2), bevel=0.02)
    for f in (10.0, 20.0, L - 1.0):  # bollards
        m.lathe(K("metal", (0.22, 0.22, 0.24)), [(0.18, Y), (0.14, Y + 0.45), (0.22, Y + 0.55), (0.0, Y + 0.6)], (W / 2 - 0.4, 0.0, f), segs=10)
    for f in (12.0, 22.0):
        m.lathe(K("cloth", (0.75, 0.68, 0.5)), [(0.15, Y + 0.06), (0.35, Y + 0.06), (0.35, Y + 0.2), (0.15, Y + 0.2)], (-W / 2 + 0.5, 0.0, f), segs=12)
    m.rod(K("wood", (0.3, 0.24, 0.18)), 0.07, (-W / 2 + 0.3, Y, L - 0.6), (-W / 2 + 0.3, Y + 2.6, L - 0.6), segs=6)
    m.box(K("metal", (0.2, 0.2, 0.2)), (0.32, 0.45, 0.32), (-W / 2 + 0.3, Y + 2.8, L - 0.6), bevel=0.02)
    m.box(fk.GLOW, (0.22, 0.32, 0.22), (-W / 2 + 0.3, Y + 2.8, L - 0.6), bevel=0.0)
    ramp = math.atan2(Y, 4.5)  # a ramp down to the shore at the land end (f 0 -> -4.5, deck height -> 0)
    m.box(K("wood", (0.48, 0.36, 0.25)), (W, 0.14, math.hypot(Y, 4.5)), (0.0, Y / 2.0 - 0.07, -2.25), tilt=math.degrees(ramp), bevel=0.0)
    for x in (-W / 2 + 0.15, W / 2 - 0.15):
        m.rod(K("wood", (0.38, 0.3, 0.22)), 0.12, (x, -0.5, -4.2), (x, 0.1, -4.2), segs=6)
    m.box(K("wood", WOOD), (1.2, 0.12, 0.5), (0.0, Y - 1.4, L + 0.2), bevel=0.01)  # boarding step
    m.box(K("wood", WOOD), (1.2, 0.12, 0.5), (0.0, Y - 0.7, L + 0.05), bevel=0.01)


def ruins_temple(m):
    """Temple ruins: a three-step platform 16 x 12 m, a ring of columns (several broken), fallen drums, a doorway arch
    and an altar with a carved bowl."""
    rnd = random.Random(47)
    for k, (w, d) in enumerate(((16.0, 12.0), (14.0, 10.0), (12.0, 8.0))):
        m.box(K("stone", tuple(c * (0.95 - 0.03 * k) for c in STONE)), (w, 0.6, d), (0.0, -0.3 + 0.6 * (k + 0.5) + (0.0 if k else 0.0), 0.0), bevel=0.06)
    top = 1.8
    cols = []
    for i in range(5):
        for side in (-1, 1):
            cols.append((-5.0 + i * 2.5, side * 3.4))
    for k, (x, f) in enumerate(cols):
        h = 5.5 if rnd.random() > 0.4 or (f > 0 and x < 0.5) else rnd.uniform(1.2, 3.5)  # the three under the lintel stand
        drums = max(1, int(h / 0.9))
        for j in range(drums):
            m.lathe(K("stone", tuple(c * rnd.uniform(0.92, 1.02) for c in STONE)), [(0.42, 0.0), (0.4, 0.86)], (x + rnd.uniform(-0.03, 0.03), top + j * 0.88, f), segs=10)
        if h > 5.0:
            m.box(K("stone", STONE), (1.1, 0.35, 1.1), (x, top + drums * 0.88 + 0.17, f), bevel=0.04)
    m.box(K("stone", STONE), (6.0, 0.6, 1.0), (-2.5, top + 5.4, 3.4), bevel=0.05)  # surviving lintel on one side
    for k in range(6):  # fallen drums
        x, f = rnd.uniform(-8, 8), rnd.uniform(-7, 7)
        if abs(x) < 6.5 and abs(f) < 5.5:
            continue
        m.lathe(K("stone", STONE), [(0.42, -0.43), (0.4, 0.43)], (x, 0.4, f), segs=10, axis="f")
    for x in (-1.4, 1.4):  # doorway arch at the back
        m.box(K("stone", STONE), (0.9, 4.2, 0.9), (x, top + 2.1, -3.0), bevel=0.04)
    m.box(K("stone", STONE), (3.8, 0.8, 1.0), (0.0, top + 4.6, -3.0), bevel=0.04)
    m.box(K("stone", (0.6, 0.57, 0.52)), (1.6, 1.0, 1.0), (0.0, top + 0.5, 0.5), bevel=0.05)  # altar
    m.lathe(K("stone", (0.55, 0.52, 0.48)), [(0.2, top + 1.0), (0.55, top + 1.25), (0.5, top + 1.3), (0.15, top + 1.12)], (0.0, 0.0, 0.5), segs=12)
    for k in range(6):  # moss and creepers
        fk.blob(m, K("leaf", LEAF), (rnd.uniform(0.8, 1.6), 0.25, rnd.uniform(0.6, 1.2)), (rnd.uniform(-7, 7), rnd.choice((0.6, 1.2, 1.8)), rnd.uniform(-5, 5)), seed=110 + k, rough=0.3, cuts=1)
    for k in range(3):  # steps up the front: solid blocks from the ground, 0.3 m rises between the tiers
        top_k = 0.3 + 0.6 * k
        m.box(K("stone", STONE), (3.0, top_k, 0.6), (0.0, top_k / 2.0, 6.3 - 1.0 * k), bevel=0.0)


def tide_pool(m):
    """A tide pool on a rock shelf: a ring of low rocks round a still water disc with weed and a starfish."""
    rnd = random.Random(48)
    for k in range(14):
        a = 2 * math.pi * k / 14
        r = 2.2 + rnd.uniform(-0.3, 0.3)
        fk.blob(m, K("rock", tuple(c * rnd.uniform(0.85, 1.0) for c in (0.5, 0.48, 0.44))), (0.9, 0.45, 0.7), (r * math.cos(a), 0.1, r * math.sin(a)), seed=120 + k, rough=0.25, cuts=1)
    fk.blob(m, K("rock", (0.42, 0.4, 0.37)), (2.3, 0.3, 2.0), (0.0, -0.35, 0.0), seed=140, rough=0.15, cuts=2)
    m.lathe(WATER, [(0.0, 0.18), (2.1, 0.18), (2.1, 0.2), (0.0, 0.2)], (0.0, 0.0, 0.0), segs=16)
    for k in range(4):
        a = rnd.uniform(0, 6.28)
        m.rod(K("leaf", (0.3, 0.45, 0.25)), 0.03, (1.2 * math.cos(a), -0.1, 1.2 * math.sin(a)), (1.2 * math.cos(a), 0.12, 1.2 * math.sin(a)), segs=3)
    for k in range(5):  # starfish arms
        a = 2 * math.pi * k / 5
        m.rod(K("paint", (0.9, 0.45, 0.25)), 0.05, (0.6, 0.0, -0.4), (0.6 + 0.25 * math.cos(a), 0.0, -0.4 + 0.25 * math.sin(a)), r2=0.02, segs=4)


def bridge(m):
    """A wooden footbridge 14 m long along +forward (centred), 3.4 m wide, its deck flush with the ground at both ends
    (y 0) and arching 0.6 m in the middle; handrails on posts start 2 m in from each end (open, flared entries a walker
    coming in a little off-line still meets the deck, not a post); two trestles in the water."""
    rnd = random.Random(49)
    L, W = 14.0, 3.4
    def y_at(f):
        return 0.6 * (1.0 - (2.0 * f / L) ** 2)
    f = -L / 2 + 0.25
    while f < L / 2:  # planks, each tilted with the arch
        m.box(K("wood", tuple(c * rnd.uniform(0.85, 1.05) for c in WOOD)), (W, 0.1, 0.46), (0.0, y_at(f) - 0.05, f), tilt=math.degrees(math.atan(-4.8 * f / (L * L))), bevel=0.0)
        f += 0.5
    for x in (-W / 2 + 0.1, W / 2 - 0.1):  # stringers under the deck, end to end
        pts = [(x, y_at(-L / 2 + L * t / 6) - 0.2, -L / 2 + L * t / 6) for t in range(7)]
        for a, b in zip(pts, pts[1:]):
            m.rod(K("wood", (0.38, 0.28, 0.2)), 0.1, a, b, segs=5)
    for x in (-W / 2 + 0.12, W / 2 - 0.12):  # handrails from 2 m in
        rail = [(x, y_at(-L / 2 + 2.0 + (L - 4.0) * t / 4) + 1.05, -L / 2 + 2.0 + (L - 4.0) * t / 4) for t in range(5)]
        for a, b in zip(rail, rail[1:]):
            m.rod(K("wood", (0.42, 0.32, 0.22)), 0.05, a, b, segs=5)
        for p in rail:
            m.rod(K("wood", (0.38, 0.28, 0.2)), 0.06, (p[0], p[1] - 1.1, p[2]), (p[0], p[1] + 0.05, p[2]), segs=5)
    for f in (-2.5, 2.5):  # trestles down into the river bed
        for x in (-1.2, 1.2):
            m.rod(K("wood", (0.33, 0.25, 0.18)), 0.12, (x, -3.0, f), (x, y_at(f) - 0.2, f), segs=6)
        m.box(K("wood", (0.38, 0.28, 0.2)), (2.8, 0.18, 0.2), (0.0, y_at(f) - 0.3, f), bevel=0.0)


SAND = (0.66, 0.52, 0.36)  # (reads warm sandstone in the noon sun; lighter values went white)
CORAL = (0.88, 0.45, 0.42)
SHELL = (0.94, 0.86, 0.74)


def _conch(m, at, size, seed):
    """A great conch shell statue: a spire of whorls winding up, knobbed, its lip turned out."""
    rnd = random.Random(seed)
    x, y, f = at
    for i in range(10):
        t = i / 9
        r = (0.9 - 0.75 * t) * size
        m.lathe(K("stone", SHELL if i % 2 else tuple(c * 0.86 for c in SHELL)), [(r * 0.85, -0.16 * size), (r, 0.0), (r * 0.85, 0.16 * size)], (x + math.sin(t * 5) * 0.05 * size, y + (0.3 + 2.3 * t) * size, f), segs=12)
        if i % 2 == 0 and i < 8:
            for k in range(5):
                a = 2 * math.pi * k / 5 + i
                m.ball(K("stone", tuple(c * 0.82 for c in SHELL)), (0.12 * size, 0.16 * size, 0.12 * size), (x + math.cos(a) * r, y + (0.32 + 2.3 * t) * size, f + math.sin(a) * r), u=6, v=4)
    m.loft(K("stone", (0.95, 0.78, 0.7)), [(x, y + 0.2 * size, f + 0.4 * size, 0.6 * size, 0.2 * size), (x, y + 0.9 * size, f + 0.75 * size, 0.85 * size, 0.25 * size), (x, y + 1.5 * size, f + 0.55 * size, 0.5 * size, 0.2 * size)], segs=10, steps=2)
    fk.blob(m, K("leaf", (0.3, 0.45, 0.32)), (0.5 * size, 0.2, 0.4 * size), (x + rnd.uniform(-0.3, 0.3), y + 0.4 * size, f), seed=seed + 1, rough=0.3, cuts=1)


def sea_temple(m):
    """The ruined SEA TEMPLE round the Tidewater Temple's gate (sea step 9c-3). y 0 = the paved court, the gate (the
    dungeon kit's dk_gate, put up by the game, 6 m wide) stands at the origin facing +forward. A broken back wall 26 m wide with a
    great shell arch over the gate, two colonnades down the court (some columns fallen), cracked flagstones with sand in
    the joints, a dry basin, two conch statues on plinths at the way in, coral and weed grown over it all."""
    rnd = random.Random(61)
    stone = lambda k=1.0: K("sandstone", tuple(c * k for c in SAND))  # noqa: E731
    for i in range(-5, 6):  # the court: flagstones 2 m, some missing (sand), each a little tilted
        for j in range(0, 10):
            if rnd.random() < 0.12:
                continue
            m.box(stone(rnd.uniform(0.82, 1.0)), (1.9, 0.18, 1.9), (i * 2.0, -0.07 + rnd.uniform(-0.03, 0.03), 1.0 + j * 2.0), tilt=rnd.uniform(-1.5, 1.5), bevel=0.0)
    for side in (-1, 1):  # the back wall: courses of blocks, broken off higher toward the arch
        for k in range(7):
            x = side * (5.4 + k * 1.3)
            top = 7.5 - k * 0.55 - rnd.uniform(0.0, 1.6) * (k > 3)
            y = 0.0
            row = 0
            while y < top:
                h = rnd.uniform(0.7, 0.95)
                m.box(stone(rnd.uniform(0.85, 1.0)), (1.25 + (0.25 if row % 2 else 0.0), h, 1.4), (x + (0.1 if row % 2 else -0.1), y + h / 2, -1.6), bevel=0.0)
                y += h
                row += 1
        m.box(stone(0.9), (1.6, 8.0, 1.8), (side * 4.2, 4.0, -1.5), bevel=0.06)  # the arch's piers (the gate is 6 m wide)
    for k in range(9):  # the arch: a ring of voussoirs over the gate, a great scallop shell in its crown
        a = math.pi * k / 8
        m.box(stone(rnd.uniform(0.88, 1.0)), (1.3, 1.1, 1.8), (-4.2 * math.cos(a), 8.0 + 3.0 * math.sin(a), -1.5), tilt=0.0, bevel=0.05)
    for k in range(11):
        a = math.radians(-75 + k * 15)
        m.rod(K("stone", SHELL), 0.22, (0.0, 8.6, -0.5), (math.sin(a) * 2.4, 8.6 + math.cos(a) * 2.4, -0.45), r2=0.12, segs=6)
    m.ball(K("stone", (0.92, 0.82, 0.7)), (0.6, 0.45, 0.35), (0.0, 8.6, -0.5), u=10, v=6)
    for side in (-1, 1):  # colonnades down both sides of the court
        for k in range(5):
            f = 2.5 + k * 4.0
            x = side * 9.0
            fallen = (side, k) in ((-1, 2), (1, 3), (1, 0))
            m.box(stone(0.85), (1.6, 0.5, 1.6), (x, 0.25, f), bevel=0.05)
            h = rnd.uniform(1.0, 2.6) if fallen else rnd.uniform(4.5, 6.2)
            for j in range(max(1, int(h / 0.9))):
                m.lathe(stone(rnd.uniform(0.88, 1.0)), [(0.55, 0.0), (0.5, 0.88)], (x + rnd.uniform(-0.04, 0.04), 0.5 + j * 0.9, f), segs=10)
            if fallen:  # its drums in the sand beside it
                for j in range(3):
                    m.lathe(stone(0.9), [(0.52, -0.44), (0.5, 0.44)], (x - side * (2.0 + j * 0.95), 0.5, f + rnd.uniform(-0.6, 0.6)), segs=10, axis="x")
            elif rnd.random() < 0.6:
                m.box(stone(0.92), (1.5, 0.45, 1.5), (x, 0.5 + int(h / 0.9) * 0.9 + 0.22, f), bevel=0.04)
        m.box(stone(0.9), (1.4, 0.7, 5.5), (side * 9.0, 6.6, 4.5), tilt=side * 4.0, bevel=0.05)  # a surviving architrave
    # the dry basin in the court, a ring of kerb stones and a weed-grown bottom
    m.lathe(stone(0.88), [(2.6, 0.0), (2.7, 0.55), (2.3, 0.6), (2.2, 0.1)], (0.0, 0.0, 10.0), segs=20)
    fk.blob(m, K("leaf", (0.32, 0.42, 0.26)), (2.0, 0.15, 2.0), (0.0, 0.05, 10.0), seed=63, rough=0.3, cuts=1)
    for side in (-1, 1):  # conch statues on plinths at the way in
        m.box(stone(0.86), (2.4, 1.6, 2.4), (side * 5.5, 0.8, 19.5), bevel=0.06)
        _conch(m, (side * 5.5, 1.6, 19.5), 1.3, 64 + side)
    for k in range(26):  # coral and barnacle crusts, weed hanging off the wall tops
        x, f = rnd.uniform(-11, 11), rnd.uniform(-2, 20)
        if abs(x) < 6.5 and f > -1:
            continue
        fk.blob(m, K("paint", CORAL if k % 3 else (0.95, 0.9, 0.82)), (rnd.uniform(0.3, 0.7), rnd.uniform(0.2, 0.5), rnd.uniform(0.3, 0.7)), (x, rnd.uniform(0.1, 3.0), f), seed=70 + k, rough=0.4, cuts=1)
    for k in range(12):
        x = rnd.choice((-1, 1)) * rnd.uniform(3.8, 11.0)
        m.loft(K("leaf", (0.24, 0.42, 0.3)), [(x, 6.0 - rnd.uniform(0, 1.5), -0.8, 0.25, 0.05), (x + rnd.uniform(-0.2, 0.2), 3.5, -0.75, 0.15, 0.04), (x, rnd.uniform(1.0, 2.5), -0.72, 0.06, 0.03)], segs=4, steps=2)
    for k in range(10):  # fallen blocks in the sand round the ruin
        a = rnd.uniform(0, 2 * math.pi)
        d = rnd.uniform(13.0, 17.0)
        m.box(stone(rnd.uniform(0.8, 0.95)), (rnd.uniform(1.0, 1.8), rnd.uniform(0.6, 1.0), rnd.uniform(1.0, 1.6)), (math.cos(a) * d, 0.3, 9.0 + math.sin(a) * d * 0.8), tilt=rnd.uniform(-15, 15), bevel=0.05)


def sea_lookout(m):
    """A broken round watchtower of the same sandstone on the reef island's knoll: 5 m across, broken off at 5-9 m, a
    doorway facing +forward, rubble round its foot, a weed-grown top."""
    rnd = random.Random(66)
    for k in range(18):  # the wall: 18 staves of courses, the doorway left open, broken off unevenly
        a = 2 * math.pi * k / 18
        if abs(math.atan2(math.sin(a - math.pi / 2), math.cos(a - math.pi / 2))) < 0.3:
            continue  # (the doorway, toward +forward)
        top = 9.0 - 3.5 * (0.5 + 0.5 * math.sin(a * 2 + 1.0)) + rnd.uniform(-0.6, 0.6)
        y = 0.0
        while y < top:
            h = rnd.uniform(0.6, 0.85)
            m.box(K("sandstone", tuple(c * rnd.uniform(0.82, 1.0) for c in SAND)), (0.95, h, 0.8), (2.4 * math.cos(a), y + h / 2, 2.4 * math.sin(a)), tilt=0.0, bevel=0.0)
            y += h
    m.box(K("sandstone", SAND), (1.8, 0.6, 0.9), (0.0, 3.0, 2.4), bevel=0.04)  # the lintel over the door
    for k in range(9):
        a = rnd.uniform(0, 2 * math.pi)
        d = rnd.uniform(3.2, 5.5)
        if abs(math.atan2(math.sin(a - math.pi / 2), math.cos(a - math.pi / 2))) < 0.5:
            continue
        m.box(K("sandstone", tuple(c * 0.88 for c in SAND)), (rnd.uniform(0.7, 1.2), 0.6, rnd.uniform(0.6, 1.0)), (d * math.cos(a), 0.3, d * math.sin(a)), tilt=rnd.uniform(-20, 20), bevel=0.04)
    for k in range(5):
        a = rnd.uniform(0, 2 * math.pi)
        fk.blob(m, K("leaf", LEAF), (0.9, 0.3, 0.7), (2.3 * math.cos(a), rnd.uniform(4.5, 6.0), 2.3 * math.sin(a)), seed=67 + k, rough=0.3, cuts=1)


def sea_shrine(m):
    """A small ruined sea shrine round a puzzle vault's gate (sea step 9d): the temple's arch with a scallop crown in a
    short broken wall, a paved apron 14 x 12 m, two columns, a conch statue, coral and weed. Gate at the origin facing
    +forward, as at the temple."""
    rnd = random.Random(68)
    stone = lambda k=1.0: K("sandstone", tuple(c * k for c in SAND))  # noqa: E731
    for i in range(-3, 4):
        for j in range(0, 6):
            if rnd.random() < 0.15:
                continue
            m.box(stone(rnd.uniform(0.82, 1.0)), (1.9, 0.18, 1.9), (i * 2.0, -0.07, 1.0 + j * 2.0), tilt=rnd.uniform(-1.5, 1.5), bevel=0.0)
    for side in (-1, 1):
        for k in range(3):
            x = side * (5.4 + k * 1.3)
            top = 6.0 - k * 1.1 - rnd.uniform(0.0, 0.8)
            y = 0.0
            row = 0
            while y < top:
                h = rnd.uniform(0.7, 0.95)
                m.box(stone(rnd.uniform(0.85, 1.0)), (1.25, h, 1.4), (x, y + h / 2, -1.6), bevel=0.0)
                y += h
                row += 1
        m.box(stone(0.9), (1.6, 8.0, 1.8), (side * 4.2, 4.0, -1.5), bevel=0.06)
        for j in range(5):  # a column each side of the apron
            m.lathe(stone(rnd.uniform(0.88, 1.0)), [(0.5, 0.0), (0.46, 0.88)], (side * 6.0, 0.1 + j * 0.9, 6.0), segs=10)
        m.box(stone(0.92), (1.3, 0.4, 1.3), (side * 6.0, 4.7, 6.0), bevel=0.04)
    for k in range(9):
        a = math.pi * k / 8
        m.box(stone(rnd.uniform(0.88, 1.0)), (1.3, 1.1, 1.8), (-4.2 * math.cos(a), 8.0 + 3.0 * math.sin(a), -1.5), tilt=0.0, bevel=0.05)
    for k in range(11):
        a = math.radians(-75 + k * 15)
        m.rod(K("stone", SHELL), 0.22, (0.0, 8.6, -0.5), (math.sin(a) * 2.4, 8.6 + math.cos(a) * 2.4, -0.45), r2=0.12, segs=6)
    m.ball(K("stone", (0.92, 0.82, 0.7)), (0.6, 0.45, 0.35), (0.0, 8.6, -0.5), u=10, v=6)
    m.box(stone(0.86), (2.0, 1.4, 2.0), (-5.0, 0.7, 11.0), bevel=0.06)
    _conch(m, (-5.0, 1.4, 11.0), 1.1, 69)
    for k in range(14):
        x, f = rnd.uniform(-8, 8), rnd.uniform(-2, 12)
        if abs(x) < 4.5 and f > -1:
            continue
        fk.blob(m, K("paint", CORAL if k % 3 else (0.95, 0.9, 0.82)), (rnd.uniform(0.3, 0.6), rnd.uniform(0.2, 0.4), rnd.uniform(0.3, 0.6)), (x, rnd.uniform(0.1, 2.5), f), seed=90 + k, rough=0.4, cuts=1)
    for k in range(6):
        x = rnd.choice((-1, 1)) * rnd.uniform(5.0, 8.0)
        m.loft(K("leaf", (0.24, 0.42, 0.3)), [(x, 5.0 - rnd.uniform(0, 1.0), -0.8, 0.25, 0.05), (x, 3.0, -0.75, 0.15, 0.04), (x, rnd.uniform(1.0, 2.0), -0.72, 0.06, 0.03)], segs=4, steps=2)


def stilt_hut(m):
    """A fisherman's hut on stilts (sea step 13b, Turtleback's hamlet): a plank floor 1.8 m up on eight posts, woven
    walls with a door toward +forward and a shuttered window, a steep palm-thatch roof with a ridge pole, a ladder down
    to the sand, a porch with a bench, nets hung on the rail, a clay pot and a fish basket."""
    rnd = random.Random(61)
    fl = 1.8
    for x in (-2.0, -0.7, 0.7, 2.0):
        for z in (-1.8, 1.8):
            m.rod(K("wood", (0.42, 0.32, 0.22)), 0.09, (x, -1.0, z), (x, fl, z), segs=6)
    m.box(K("wood", OLD_WOOD), (4.6, 0.12, 4.2), (0.0, fl, 0.3), bevel=0.02)  # floor + porch
    wall = K("thatch", (0.66, 0.56, 0.36))
    m.box(wall, (4.0, 2.0, 0.1), (0.0, fl + 1.0, -1.8), bevel=0.01)
    m.box(wall, (0.1, 2.0, 3.6), (-2.0, fl + 1.0, 0.0), bevel=0.01)
    m.box(wall, (0.1, 2.0, 3.6), (2.0, fl + 1.0, 0.0), bevel=0.01)
    m.box(wall, (1.4, 2.0, 0.1), (-1.3, fl + 1.0, 1.8), bevel=0.01)  # front wall with the door gap in the middle
    m.box(wall, (1.4, 2.0, 0.1), (1.3, fl + 1.0, 1.8), bevel=0.01)
    m.box(wall, (1.2, 0.3, 0.1), (0.0, fl + 1.85, 1.8), bevel=0.01)
    m.box(K("wood", (0.35, 0.26, 0.18)), (0.7, 0.6, 0.06), (2.04, fl + 1.2, 0.0), tilt=0.0, bevel=0.01)  # shutter
    roof = K("thatch", (0.6, 0.5, 0.28))
    for side in (-1.0, 1.0):
        m.box(roof, (5.0, 0.18, 3.0), (0.0, fl + 2.85, side * 1.15), tilt=side * 48.0, bevel=0.03)
    m.rod(K("wood", WOOD), 0.07, (-2.5, fl + 3.95, 0.0), (2.5, fl + 3.95, 0.0), segs=6)
    for k in range(7):  # ladder
        y = k * fl / 6.0 - 0.3
        m.rod(K("wood", WOOD), 0.03, (-0.35, y, 2.6 + (fl - y) * 0.3), (0.35, y, 2.6 + (fl - y) * 0.3), segs=3)
    for x in (-0.35, 0.35):
        m.rod(K("wood", WOOD), 0.04, (x, -0.4, 3.2), (x, fl, 2.45), segs=4)
    for x in (-2.2, 2.2):  # porch rail with nets
        m.rod(K("wood", WOOD), 0.05, (x, fl, 2.35), (x, fl + 1.0, 2.35), segs=4)
    m.rod(K("wood", WOOD), 0.04, (-2.2, fl + 1.0, 2.35), (-0.6, fl + 1.0, 2.35), segs=4)
    m.rod(K("wood", WOOD), 0.04, (0.6, fl + 1.0, 2.35), (2.2, fl + 1.0, 2.35), segs=4)
    net = K("cloth", (0.55, 0.5, 0.38))
    for k in range(6):
        x = -2.1 + 0.25 * k
        m.rod(net, 0.012, (x, fl + 1.0, 2.38), (x + 0.1, fl + 0.25, 2.42), segs=3)
    m.box(K("wood", WOOD), (1.2, 0.08, 0.35), (1.3, fl + 0.45, 2.0), bevel=0.01)  # bench
    m.lathe(K("adobe", (0.62, 0.36, 0.22)), [(0.0, 0.0), (0.22, 0.05), (0.26, 0.3), (0.12, 0.5), (0.14, 0.55)], (-1.6, fl + 0.06, 2.0), segs=10)
    m.lathe(K("thatch", (0.55, 0.45, 0.25)), [(0.0, 0.0), (0.3, 0.02), (0.36, 0.35)], (rnd.uniform(-0.6, -0.2), 0.0, 3.6), segs=10)


def drying_rack(m):
    """A fish-drying rack: two A-frames, three poles, split fish hanging in a row, a basket below."""
    for x in (-2.0, 2.0):
        for f in (-0.6, 0.6):
            m.rod(K("wood", WOOD), 0.05, (x, 0.0, f), (x, 2.0, 0.0), segs=4)
    for y in (1.9, 1.5):
        m.rod(K("wood", OLD_WOOD), 0.035, (-2.1, y, 0.0), (2.1, y, 0.0), segs=6)
    fish = K("cloth", (0.72, 0.6, 0.45))
    for k in range(10):
        x = -1.8 + 0.4 * k
        m.box(fish, (0.18, 0.45, 0.03), (x, 1.62 if k % 2 else 1.22, 0.0), bevel=0.01)
    m.lathe(K("thatch", (0.55, 0.45, 0.25)), [(0.0, 0.0), (0.35, 0.02), (0.42, 0.4)], (0.8, 0.0, 0.9), segs=10)


def salt_pans(m):
    """Salt pans (Saltpan Key): a grid of 4 x 3 shallow pans, 5 x 4 m each, between low clay walls 0.3 m high and
    0.5 m wide; most pans crusted white with salt, two with brine (water), a few heaps of raked salt and wooden rakes.
    y 0 = the ground the pans are dug into (their walls stand on it)."""
    rnd = random.Random(63)
    wall = K("adobe", (0.66, 0.58, 0.48))
    for i in range(5):
        m.box(wall, (0.5, 0.3, 12.5), (-10.0 + 5.0 * i, 0.15, 0.0), bevel=0.04)
    for j in range(4):
        m.box(wall, (20.5, 0.3, 0.5), (0.0, 0.15, -6.0 + 4.0 * j), bevel=0.04)
    for i in range(4):
        for j in range(3):
            cx, cz = -7.5 + 5.0 * i, -4.0 + 4.0 * j
            if (i, j) in ((1, 2), (3, 0)):
                m.box(WATER, (4.5, 0.02, 3.5), (cx, 0.08, cz), bevel=0.0)
            else:
                m.box(K("plaster", (0.95, 0.94, 0.9)), (4.5, 0.04, 3.5), (cx, 0.04, cz), bevel=0.0)
                if rnd.random() < 0.5:
                    fk.blob(m, K("plaster", (0.97, 0.96, 0.93)), (0.6, 0.45, 0.6), (cx + rnd.uniform(-1, 1), 0.2, cz + rnd.uniform(-0.8, 0.8)), seed=200 + i * 3 + j, rough=0.15, cuts=1)
    for k in range(3):
        x, z = rnd.uniform(-9, 9), rnd.uniform(-5, 5)
        m.rod(K("wood", WOOD), 0.03, (x, 0.05, z), (x + 1.4, 0.05, z + 0.4), segs=4)
        m.box(K("wood", WOOD), (0.08, 0.1, 0.5), (x + 1.4, 0.08, z + 0.4), bevel=0.01)


def salt_works(m):
    """The ruined SALT WORKS (Saltpan Key): a brick boiling house 12 x 8 m with its roof fallen in (a few rafters
    left), arched windows, a tall square brick chimney (14 m) at the back, two rusted iron boiling pans on their
    hearths, a wooden door frame toward +forward with the CELLAR STAIR going down beside it (dark), salt sacks, a
    broken cart. y 0 = its floor."""
    rnd = random.Random(67)
    brick = K("adobe", (0.62, 0.36, 0.28))
    w, d, h = 12.0, 8.0, 4.2
    m.box(K("stone", (0.6, 0.58, 0.54)), (w + 0.6, 0.3, d + 0.6), (0.0, 0.0, 0.0), bevel=0.05)  # plinth / floor
    for side in (-1.0, 1.0):  # long walls with three arched window gaps each
        for k in range(4):
            m.box(brick, (1.6, h, 0.45), (-5.2 + k * 3.47, h / 2, side * d / 2), bevel=0.02)
        m.box(brick, (w, 0.9, 0.45), (0.0, h - 0.45, side * d / 2), bevel=0.02)
        m.box(brick, (w, 1.0, 0.45), (0.0, 0.5, side * d / 2), bevel=0.02)
    m.box(brick, (0.45, h, d), (-w / 2, h / 2, 0.0), bevel=0.02)  # back wall (the chimney side)
    for f in (-1.0, 1.0):  # front wall either side of the doorway
        m.box(brick, (0.45, h, 2.8), (w / 2, h / 2, f * 2.6), bevel=0.02)
    m.box(brick, (0.45, 1.0, 2.4), (w / 2, h - 0.5, 0.0), bevel=0.02)
    for k in range(4):  # broken top course: jagged
        m.box(brick, (rnd.uniform(1.0, 2.5), rnd.uniform(0.3, 1.0), 0.45), (rnd.uniform(-5, 5), h + 0.3, (-1) ** k * d / 2), bevel=0.02)
    m.box(brick, (1.8, 14.0, 1.8), (-w / 2 - 0.9, 7.0, -2.0), bevel=0.03)  # chimney
    m.box(K("stone", (0.5, 0.48, 0.45)), (2.1, 0.4, 2.1), (-w / 2 - 0.9, 14.0, -2.0), bevel=0.03)
    for k in range(3):  # rafters left
        x = -3.0 + k * 3.0
        m.box(K("wood", (0.3, 0.24, 0.18)), (0.2, 0.25, d + 0.4), (x, h + 0.7, 0.0), tilt=rnd.uniform(-12, 12), bevel=0.02)
    for x in (-3.0, 1.5):  # hearths with iron pans
        m.box(brick, (3.0, 0.8, 2.6), (x, 0.55, -1.0), bevel=0.04)
        m.lathe(K("metal", (0.36, 0.22, 0.14)), [(0.0, 0.0), (1.3, 0.02), (1.4, 0.35)], (x, 0.95, -1.0), segs=14)
    m.box(K("stone", (0.12, 0.12, 0.12)), (1.6, 0.05, 2.2), (w / 2 - 1.6, 0.17, 2.4), bevel=0.0)  # the dark stairwell (cellar)
    for k in range(4):
        m.box(K("stone", (0.4, 0.38, 0.36)), (1.6, 0.2, 0.4), (w / 2 - 1.6, 0.05 - 0.25 * k, 1.5 + 0.45 * k), bevel=0.02)
    for k in range(5):  # salt sacks
        m.box(K("cloth", (0.82, 0.78, 0.68)), (0.6, 0.45, 0.4), (rnd.uniform(-4.5, 4.5), 0.45, rnd.uniform(1.6, 3.2)), tilt=rnd.uniform(-20, 20), bevel=0.12)
    for k in range(2):  # cart wheels (broken cart)
        m.lathe(K("wood", WOOD), [(0.0, -0.05), (0.55, -0.05), (0.55, 0.05), (0.0, 0.05)], (w / 2 + 2.5, 0.55, -2.5 + k * 1.4), segs=12, axis="x")
    m.box(K("wood", OLD_WOOD), (2.4, 0.12, 1.2), (w / 2 + 3.2, 0.7, -1.8), tilt=14.0, bevel=0.02)


# --- region 2, the Fog Banks (sea step 13 R2a) ---
TAR_WOOD = (0.3, 0.24, 0.18)
MOSS = (0.3, 0.38, 0.2)


def lantern_hall(m):
    """LANTERNWICK's rest house (region 2's outpost): a long stilt hall 10 x 6 m, its plank floor 1.8 m up on posts,
    plank walls with a wide door toward +forward and lit windows, a steep shingle roof, a porch with lanterns on
    poles, steps down to the boardwalk, barrels and a bench."""
    fl = 1.8
    for x in (-4.6, -1.5, 1.5, 4.6):
        for z in (-2.8, 0.0, 2.8):
            m.rod(K("wood", TAR_WOOD), 0.12, (x, -1.2, z), (x, fl, z), segs=6)
    m.box(K("wood", OLD_WOOD), (10.4, 0.14, 8.0), (0.0, fl, 0.9), bevel=0.02)  # floor + porch
    wall = K("timber", (0.42, 0.33, 0.24))
    h = 2.6
    m.box(wall, (9.6, h, 0.14), (0.0, fl + h / 2, -2.9), bevel=0.01)
    for x in (-4.8, 4.8):
        m.box(wall, (0.14, h, 5.8), (x, fl + h / 2, 0.0), bevel=0.01)
    for x in (-3.3, 3.3):  # front wall either side of the door
        m.box(wall, (3.0, h, 0.14), (x, fl + h / 2, 2.9), bevel=0.01)
    m.box(wall, (3.6, 0.6, 0.14), (0.0, fl + h - 0.3, 2.9), bevel=0.01)
    for x in (-3.3, 3.3):  # lit windows
        m.box(fk.GLOW, (1.0, 0.7, 0.05), (x, fl + 1.5, 2.98), bevel=0.0)
    for z in (-1.5, 1.2):
        m.box(fk.GLOW, (0.05, 0.7, 0.9), (-4.88, fl + 1.5, z), bevel=0.0)
    roof = K("slate", (0.32, 0.3, 0.28))
    for side in (-1.0, 1.0):
        m.box(roof, (10.6, 0.16, 4.1), (0.0, fl + h + 1.25, side * 1.55), tilt=side * 38.0, bevel=0.03)
    m.rod(K("wood", TAR_WOOD), 0.09, (-5.3, fl + h + 2.5, 0.0), (5.3, fl + h + 2.5, 0.0), segs=6)
    for x in (-4.9, 4.9):  # porch lanterns on poles
        m.rod(K("wood", TAR_WOOD), 0.06, (x, fl, 4.7), (x, fl + 2.4, 4.7), segs=5)
        m.box(fk.GLOW, (0.22, 0.3, 0.22), (x, fl + 2.2, 4.7), bevel=0.01)
    for k in range(6):  # steps down to the boardwalk
        m.box(K("wood", OLD_WOOD), (2.4, 0.1, 0.4), (0.0, fl - 0.3 * k - 0.15, 5.1 + 0.4 * k), bevel=0.01)
    for k in range(3):
        m.lathe(K("wood", (0.42, 0.3, 0.18)), [(0.3, 0.0), (0.36, 0.45), (0.3, 0.9)], (-3.8 + 0.75 * k, fl + 0.07, 4.1), segs=10)
    m.box(K("wood", WOOD), (2.0, 0.1, 0.45), (3.2, fl + 0.5, 4.2), bevel=0.01)


def chapel_ruin(m):
    """The SUNKEN CHAPEL on Greywater Bog (region 2 mini-dungeon 1's way in): a small stone chapel 9 x 6 m sunk a
    metre into the peat and leaning, mossy walls, a pointed-arch doorway toward +forward, a broken bell-cote, the roof
    gone but for two ribs, and inside a stair going down into the dark crypt. y 0 = its floor (the bog's surface)."""
    rnd = random.Random(71)
    st = K("stone", (0.5, 0.5, 0.46))
    w, d, h = 9.0, 6.0, 4.0
    m.box(K("stone", (0.42, 0.42, 0.38)), (w + 0.4, 0.3, d + 0.4), (0.0, -0.1, 0.0), bevel=0.04)
    for side in (-1.0, 1.0):  # side walls, broken along the top
        for k in range(4):
            top = h - rnd.uniform(0.0, 1.6)
            m.box(st, (2.2, top, 0.6), (-3.3 + 2.2 * k, top / 2, side * d / 2), bevel=0.03)
    m.box(st, (0.6, h + 1.2, d), (-w / 2, (h + 1.2) / 2, 0.0), bevel=0.03)  # back gable
    for f in (-1.0, 1.0):  # front wall either side of the arched door
        m.box(st, (0.6, h, 2.0), (w / 2, h / 2, f * 2.0), bevel=0.03)
    for k in range(6):  # the pointed arch over the door
        a = math.pi * k / 5
        m.box(st, (0.6, 0.45, 0.5), (w / 2, 2.6 + 0.9 * math.sin(a) ** 0.7, -1.05 * math.cos(a)), bevel=0.03)
    m.box(st, (0.9, 1.6, 1.2), (w / 2, h + 0.6, 0.0), bevel=0.03)  # broken bell-cote
    for x in (-1.5, 1.8):  # two roof ribs left
        for side in (-1.0, 1.0):
            m.box(K("wood", (0.28, 0.24, 0.2)), (0.25, 0.25, 3.6), (x, h + 0.9, side * 1.3), tilt=side * 30.0, bevel=0.02)
    for k in range(9):  # moss over the walls
        fk.blob(m, K("leaf", MOSS), (rnd.uniform(0.6, 1.3), 0.25, rnd.uniform(0.6, 1.2)), (rnd.uniform(-4, 4), rnd.uniform(1.5, 3.8), rnd.choice((-1, 1)) * d / 2), seed=300 + k, rough=0.3, cuts=1)
    m.box(K("stone", (0.08, 0.08, 0.08)), (1.6, 0.05, 2.4), (-2.6, 0.06, 0.0), bevel=0.0)  # the crypt stair's dark well
    for k in range(4):
        m.box(K("stone", (0.36, 0.36, 0.33)), (1.6, 0.2, 0.45), (-2.6 + 0.0, -0.25 * k, -0.9 + 0.5 * k), bevel=0.02)
    for k in range(5):  # fallen stones
        fk.blob(m, st, (rnd.uniform(0.3, 0.6), 0.25, rnd.uniform(0.3, 0.5)), (rnd.uniform(-4, 6), 0.15, rnd.uniform(-4.5, 4.5)), seed=320 + k, rough=0.2, cuts=1)


def pitch_works(m):
    """The ruined PITCH WORKS on The Knots (region 2 mini-dungeon 2's way in): a brick furnace with a great iron
    kettle, a broken timber shed frame over it, tar barrels, a pitch-black spill, a tall tapping ladder against a
    dead mangrove trunk and a hatch going down toward +forward (the works' cellars). y 0 = its yard."""
    rnd = random.Random(73)
    brick = K("adobe", (0.44, 0.26, 0.2))
    m.box(K("stone", (0.36, 0.34, 0.32)), (12.0, 0.25, 9.0), (0.0, 0.0, 0.0), bevel=0.05)
    m.box(brick, (3.4, 1.4, 3.0), (-2.5, 0.7, -1.5), bevel=0.05)  # furnace
    m.box(brick, (0.9, 6.0, 0.9), (-3.8, 3.0, -2.6), bevel=0.03)  # its chimney
    m.lathe(K("metal", (0.18, 0.16, 0.15)), [(0.0, 0.0), (1.3, 0.1), (1.5, 0.9), (1.4, 1.2)], (-2.5, 1.4, -1.5), segs=16)
    m.lathe(K("paint", (0.05, 0.05, 0.05)), [(0.0, 0.0), (1.3, 0.0)], (-2.5, 2.45, -1.5), segs=16)  # the pitch inside
    for x in (-5.5, 0.5, 5.5):  # shed frame: posts and a few rafters
        for z in (-4.0, 4.0):
            m.rod(K("wood", TAR_WOOD), 0.12, (x, 0.0, z), (x, 4.0 + (0.5 if z < 0 else 0.0), z), segs=6)
    for k in range(3):
        m.box(K("wood", TAR_WOOD), (0.18, 0.2, 8.6), (-5.0 + 4.5 * k, 4.4, 0.0), tilt=rnd.uniform(-10, 10), bevel=0.02)
    m.box(K("wood", TAR_WOOD), (11.4, 0.2, 0.2), (0.0, 4.4, -4.0), bevel=0.02)
    for k in range(7):  # tar barrels
        x, z = rnd.uniform(1.0, 5.0), rnd.uniform(-3.5, 0.5)
        if k == 6:
            m.lathe(K("wood", (0.22, 0.17, 0.12)), [(0.32, 0.0), (0.38, 0.45), (0.32, 0.9)], (x, 0.45, z), segs=10, axis="x")
        else:
            m.lathe(K("wood", (0.22, 0.17, 0.12)), [(0.32, 0.0), (0.38, 0.45), (0.32, 0.9)], (x, 0.12, z), segs=10)
    m.lathe(K("paint", (0.04, 0.04, 0.04)), [(0.0, 0.0), (1.6, 0.0)], (4.2, 0.14, 1.6), segs=12, squash=0.6)  # the spill
    m.loft(K("bark", (0.3, 0.27, 0.24)), [(-5.0, 0.0, 3.0, 0.5, 0.48), (-5.1, 5.0, 3.1, 0.35, 0.34), (-5.3, 8.0, 3.0, 0.2, 0.2)], segs=7, steps=2)  # dead trunk
    for k in range(9):  # its tapping ladder
        y = 0.6 * k
        m.rod(K("wood", WOOD), 0.03, (-4.7, y, 2.2), (-4.0, y, 2.3), segs=3)
    for x in (-4.7, -4.0):
        m.rod(K("wood", WOOD), 0.04, (x, 0.0, 2.25), (x - 0.4, 5.2, 2.75), segs=4)
    m.box(K("wood", (0.24, 0.18, 0.12)), (2.0, 0.08, 1.6), (2.5, 0.16, 3.4), bevel=0.01)  # the hatch, propped open
    m.box(K("stone", (0.06, 0.06, 0.06)), (1.6, 0.03, 1.4), (2.5, 0.13, 3.4), bevel=0.0)
    m.box(K("wood", (0.24, 0.18, 0.12)), (2.0, 1.4, 0.08), (2.5, 0.85, 2.6), tilt=-15.0, bevel=0.01)


def hollow_mangrove(m):
    """THE HOLLOW MANGROVE (region 2's main dungeon island): one giant mangrove. Its trunk (about 9 m thick) stands
    6 m up on a cage of 18 great arching roots spanning 36 m, rises to 34 m and spreads a dark crown 50 m wide; hanging
    roots drop from the boughs; between two roots toward +forward a dark doorway leads down into the trunk (the
    dungeon's way in), marked by lantern posts and the Marsh Beacon's iron hook. y 0 = the mud at the roots' feet."""
    rnd = random.Random(79)
    bark = K("bark", (0.34, 0.29, 0.23))
    base = 6.0
    m.loft(bark, [(0.0, base - 1.0, 0.0, 4.8, 4.6), (0.3, base + 8.0, 0.2, 4.2, 4.0), (0.8, base + 18.0, 0.4, 3.4, 3.2), (1.0, 34.0, 0.5, 2.4, 2.3)], segs=18, steps=3)
    for k in range(18):  # the root cage: out from the trunk's foot in arches down into the mud
        a = 2 * math.pi * k / 18 + rnd.uniform(-0.08, 0.08)
        if abs(math.atan2(math.sin(a - math.pi / 2), math.cos(a - math.pi / 2))) < 0.15:
            continue  # the doorway gap (toward +forward = +z)
        reach = rnd.uniform(15.0, 18.0)
        top = (4.0 * math.cos(a), base + rnd.uniform(1.5, 3.5), 4.0 * math.sin(a))
        mid = (reach * 0.55 * math.cos(a), base + rnd.uniform(2.5, 4.5), reach * 0.55 * math.sin(a))
        m.loft(bark, [(top[0], top[1], top[2], 1.1, 1.0), (mid[0], mid[1], mid[2], 0.9, 0.85), (reach * 0.85 * math.cos(a), 2.0, reach * 0.85 * math.sin(a), 0.75, 0.7), (reach * math.cos(a), -1.0, reach * math.sin(a), 0.6, 0.6)], segs=8, steps=3)
    for side in (-1.0, 1.0):  # the two roots framing the doorway
        a = math.pi / 2 + side * 0.24
        m.loft(bark, [(4.2 * math.cos(a), base + 1.0, 4.2 * math.sin(a), 1.3, 1.2), (9.0 * math.cos(a), base, 9.0 * math.sin(a), 1.1, 1.0), (14.0 * math.cos(a), 1.0, 14.0 * math.sin(a), 0.85, 0.8), (16.0 * math.cos(a), -1.0, 16.0 * math.sin(a), 0.7, 0.7)], segs=8, steps=3)
    m.box(K("stone", (0.04, 0.04, 0.04)), (3.2, 4.2, 0.4), (0.0, 2.1, 4.6), bevel=0.0)  # the dark doorway into the trunk
    for k in range(8):  # steps up to it
        m.box(K("wood", TAR_WOOD), (3.4, 0.2, 0.7), (0.0, 0.1 + 0.25 * k, 12.0 - 0.9 * k), bevel=0.02)
    for x in (-2.6, 2.6):
        m.rod(K("wood", TAR_WOOD), 0.1, (x, 0.0, 13.0), (x, 3.0, 13.0), segs=5)
        m.box(fk.GLOW, (0.3, 0.4, 0.3), (x, 2.8, 13.0), bevel=0.01)
    m.rod(K("metal", (0.2, 0.19, 0.18)), 0.06, (1.9, 3.2, 5.0), (1.9, 4.2, 5.6), segs=5)  # the beacon's hook
    for k in range(7):  # boughs with crown lumps
        a = 2 * math.pi * k / 7 + rnd.uniform(-0.2, 0.2)
        r = rnd.uniform(14.0, 20.0)
        tip = (1.0 + r * math.cos(a), rnd.uniform(28.0, 34.0), 0.5 + r * math.sin(a))
        m.loft(bark, [(1.0, rnd.uniform(24.0, 30.0), 0.5, 1.4, 1.3), (tip[0], tip[1], tip[2], 0.5, 0.5)], segs=6, steps=2)
        for j in range(2):
            fk.blob(m, K("leaf", rnd.choice([(0.15, 0.28, 0.13), (0.19, 0.32, 0.15), (0.13, 0.25, 0.12)])), (rnd.uniform(7.0, 9.5), rnd.uniform(3.0, 4.2), rnd.uniform(7.0, 9.5)), (tip[0] * (0.75 + 0.25 * j), tip[1] + 2.0 + j, tip[2] * (0.75 + 0.25 * j)), seed=400 + k * 2 + j, rough=0.25, cuts=2)
        for j in range(3):  # hanging roots
            f = rnd.uniform(0.4, 0.9)
            hx, hz = 1.0 + (tip[0] - 1.0) * f, 0.5 + (tip[2] - 0.5) * f
            m.rod(K("bark", (0.3, 0.26, 0.21)), 0.12, (hx, tip[1] - 1.0, hz), (hx * 1.02, rnd.uniform(-0.5, 8.0), hz * 1.02), segs=4)
    fk.blob(m, K("leaf", (0.16, 0.29, 0.13)), (14.0, 5.0, 14.0), (1.0, 37.0, 0.5), seed=430, rough=0.2, cuts=2)


def barge(m):
    """A stranded marsh barge: a flat-bottomed hull 12 x 4 m listing on a mudbank, a broken deckhouse, crates and a
    pole. y 0 = the mud."""
    rnd = random.Random(83)
    hull = K("wood", (0.32, 0.26, 0.2))
    for side in (-1.0, 1.0):
        m.box(hull, (12.0, 1.4, 0.2), (0.0, 0.6 + side * 0.25, side * 2.0), tilt=0.0, bevel=0.02)
    for x in (-6.0, 6.0):
        m.box(hull, (0.2, 1.4, 4.2), (x, 0.6, 0.0), bevel=0.02)
    m.box(K("wood", OLD_WOOD), (11.8, 0.12, 3.9), (0.0, 0.4, 0.0), tilt=6.0, bevel=0.01)
    m.box(K("timber", (0.4, 0.33, 0.25)), (3.0, 1.8, 2.8), (-3.0, 1.3, 0.0), tilt=6.0, bevel=0.02)
    m.box(K("wood", TAR_WOOD), (3.4, 0.15, 3.2), (-3.0, 2.3, 0.2), tilt=20.0, bevel=0.02)
    for k in range(4):
        m.box(K("wood", (0.5, 0.38, 0.24)), (0.7, 0.6, 0.7), (rnd.uniform(0.5, 4.5), 0.8, rnd.uniform(-1.2, 1.2)), tilt=rnd.uniform(-15, 15), bevel=0.03)
    m.rod(K("wood", WOOD), 0.06, (5.0, 0.4, 1.0), (7.5, 4.5, 2.5), segs=4)


def bell_buoy(m):
    """A marsh bell buoy: a tarred float with an iron cage and a bell, leaning in the water. y 0 = the water."""
    m.lathe(K("wood", TAR_WOOD), [(0.0, -0.8), (1.1, -0.6), (1.2, 0.0), (0.9, 0.4), (0.0, 0.45)], (0.0, 0.0, 0.0), segs=14)
    for k in range(4):
        a = k * math.pi / 2
        m.rod(K("metal", (0.25, 0.22, 0.2)), 0.05, (0.7 * math.cos(a), 0.4, 0.7 * math.sin(a)), (0.0, 3.0, 0.0), segs=4)
    m.lathe(K("metal", (0.55, 0.42, 0.22)), [(0.0, 2.9), (0.25, 2.85), (0.42, 2.3), (0.5, 2.1)], (0.0, 0.0, 0.0), segs=12)
    m.box(fk.GLOW, (0.2, 0.25, 0.2), (0.0, 3.2, 0.0), bevel=0.01)


PLACES = {
    "lantern_hall": lantern_hall,
    "chapel_ruin": chapel_ruin,
    "pitch_works": pitch_works,
    "hollow_mangrove": hollow_mangrove,
    "barge": barge,
    "bell_buoy": bell_buoy,
    "stilt_hut": stilt_hut,
    "drying_rack": drying_rack,
    "salt_pans": salt_pans,
    "salt_works": salt_works,
    "sea_shrine": sea_shrine,
    "sea_temple": sea_temple,
    "sea_lookout": sea_lookout,
    "sea_arch": sea_arch,
    "cave": cave,
    "lighthouse": lighthouse,
    "wreck": wreck,
    "camp": camp,
    "jetty": jetty,
    "ruins_temple": ruins_temple,
    "tide_pool": tide_pool,
    "bridge": bridge,
}

if __name__ == "__main__":
    fk.init()
    WATER = kit.material("water", None, (0.3, 0.55, 0.6))
    for name, build in PLACES.items():
        if fk.ONLY and name not in fk.ONLY:
            continue
        m = kit.Model(name, uv_scale=0.6, colored=True)
        build(m)
        print(name, m.export(OUT))
