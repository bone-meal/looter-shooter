# Purpose: developer-time tool. The island kit's props (director: "plenty of props"): assets/models/sea/props/<id>.gltf,
# each one mesh node "Body" so the game can draw hundreds of copies in one call (game/sea_isle_props.gd). Coconut palms
# (two shapes), a broadleaf bush, a fern, three boulders, a sea stack, driftwood, a beach grass tuft, a shell and
# pebble scatter, a coconut pile, a ruined wall; for the bigger islands (director: plant zones, rocks + coast detail)
# broadleaf trees, a jungle giant, flowers, reeds, dune grass, hanging vines, three rock outcrops, reefs and coral;
# for region 2, the Fog Banks: two mangroves, a reed bed, a peat mound, glowing marsh mushrooms, a lantern post. Materials named after what they are made of (fantasy_kit kinds).
# Run: python3 tools/blender/sea_isle_props.py   (ONLY=palm_a builds just that one)
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

OUT = os.path.join(os.path.dirname(__file__), "..", "..", "assets", "models", "sea", "props")
TRUNK = (0.55, 0.45, 0.33)
FROND = (0.24, 0.42, 0.15)
FROND_DRY = (0.48, 0.44, 0.22)
LEAF = (0.28, 0.48, 0.2)
ROCK = (0.5, 0.47, 0.43)
DRIFT = (0.7, 0.66, 0.58)


def frond(m, base, yaw, length, droop, colour, seed, n=7):
    """A palm frond: one closed leaf strip arching out and down, its edge jagged like leaflets, folded down from the
    midrib (about 80 triangles, so a whole beach of palms stays cheap)."""
    rnd = random.Random(seed)
    fw = (math.cos(yaw), math.sin(yaw))
    side = (-math.sin(yaw), math.cos(yaw))
    centre, left, right = [], [], []
    for k in range(n + 1):
        t = k / n
        out = length * t
        y = base[1] + length * 0.35 * t - droop * t * t * length
        c = (base[0] + fw[0] * out, base[2] + fw[1] * out, y)  # Blender order (x, f, up)
        span = length * 0.3 * math.sin(math.pi * min(t * 1.1, 1.0)) * (1.25 if k % 2 else 0.75) * rnd.uniform(0.9, 1.1)
        fall = span * 0.5
        back = span * 0.25 if k % 2 else 0.0
        centre.append(c)
        left.append((c[0] + side[0] * span - fw[0] * back, c[1] + side[1] * span - fw[1] * back, c[2] - fall))
        right.append((c[0] - side[0] * span - fw[0] * back, c[1] - side[1] * span - fw[1] * back, c[2] - fall))
    bm = bmesh.new()
    def pair(p):
        return bm.verts.new(p), bm.verts.new((p[0], p[1], p[2] - 0.025))
    C = [pair(p) for p in centre]
    L = [pair(p) for p in left]
    R = [pair(p) for p in right]
    for k in range(n):
        for a, b in ((C, L), (R, C)):
            bm.faces.new((a[k][0], a[k + 1][0], b[k + 1][0], b[k][0]))
            bm.faces.new((b[k][1], b[k + 1][1], a[k + 1][1], a[k][1]))
    ring = [L[k] for k in range(n + 1)] + [R[k] for k in range(n, -1, -1)]
    ring = ring[:n + 1] + [C[n]] + ring[n + 1:] + [C[0]]
    for i in range(len(ring)):
        a, b = ring[i], ring[(i + 1) % len(ring)]
        bm.faces.new((a[0], a[1], b[1], b[0]))
    m._add(bm, K("leaf", colour), "Body", 0)


def palm(m, height, lean, seed):
    rnd = random.Random(seed)
    rings = []
    segs = 9
    for k in range(segs + 1):
        t = k / segs
        x = lean * height * t * t
        y = height * t
        r = 0.24 * (1.0 - 0.35 * t) + (0.08 if k == 0 else 0.0)
        rings.append((x, y, 0.0, r, r))
    m.loft(K("bark", TRUNK), rings, segs=8)
    for k in range(1, 5):  # ring scars
        t = k / 5.0
        x = lean * height * t * t
        r = 0.24 * (1.0 - 0.35 * t) + 0.012
        m.lathe(K("bark", tuple(c * 0.72 for c in TRUNK)), [(r, -0.04), (r, 0.04)], (x, height * t, 0.0), segs=8)
    top = (lean * height, height, 0.0)
    m.ball(K("bark", (0.42, 0.34, 0.22)), (0.3, 0.35, 0.3), top, u=8, v=6)
    n = rnd.randint(8, 10)
    for k in range(n):
        yaw = 2 * math.pi * k / n + rnd.uniform(-0.2, 0.2)
        frond(m, (top[0], top[1] + 0.15, top[2]), yaw, rnd.uniform(2.6, 3.6), rnd.uniform(0.5, 0.9), FROND if k % 4 else FROND_DRY, seed * 31 + k, n=6)
    for k in range(3):
        a = k * 2.1
        m.ball(K("paint", (0.36, 0.26, 0.12)), 0.13, (top[0] + 0.25 * math.cos(a), top[1] - 0.2, top[2] + 0.25 * math.sin(a)), u=6, v=4)


def bush(m, seed):
    rnd = random.Random(seed)
    for k in range(4):
        a = rnd.uniform(0, 6.28)
        d = rnd.uniform(0.2, 0.7)
        fk.blob(m, K("leaf", tuple(c * rnd.uniform(0.85, 1.15) for c in LEAF)), (rnd.uniform(0.55, 0.85), rnd.uniform(0.45, 0.7), rnd.uniform(0.55, 0.85)), (d * math.cos(a), 0.5 + rnd.uniform(0, 0.3), d * math.sin(a)), seed=seed + k, rough=0.2, cuts=2)


def fern(m, seed):
    rnd = random.Random(seed)
    for k in range(7):
        yaw = 2 * math.pi * k / 7 + rnd.uniform(-0.2, 0.2)
        frond(m, (0.0, 0.05, 0.0), yaw, rnd.uniform(0.7, 1.0), 0.9, LEAF, seed + k, n=4)


def boulder(m, size, seed, flat=1.0):
    fk.blob(m, K("rock", ROCK), (size, size * 0.7 * flat, size * 0.85), (0.0, size * 0.25, 0.0), seed=seed, rough=0.22, cuts=3)
    rnd = random.Random(seed)
    for k in range(3):
        a = rnd.uniform(0, 6.28)
        fk.blob(m, K("rock", tuple(c * 0.9 for c in ROCK)), (size * 0.35, size * 0.25, size * 0.3), (size * 0.8 * math.cos(a), size * 0.05, size * 0.8 * math.sin(a)), seed=seed + 10 + k, rough=0.25, cuts=2)


def sea_stack(m, seed):
    rnd = random.Random(seed)
    y = -20.0  # from the sea floor under the cliffs to 16 m above the water
    r = 6.0
    while y < 16.0:
        fk.blob(m, K("rock", tuple(c * rnd.uniform(0.85, 1.05) for c in ROCK)), (r, 2.6, r * 0.85), (rnd.uniform(-0.6, 0.6), y, rnd.uniform(-0.6, 0.6)), seed=seed + int(y * 10), rough=0.18, cuts=3)
        y += 2.8
        r *= rnd.uniform(0.9, 0.98) if y > 0.0 else 1.0
    fk.blob(m, K("leaf", LEAF), (r * 1.1, 0.6, r), (0.0, y - 0.6, 0.0), seed=seed + 99, rough=0.3, cuts=2)


def driftwood(m, seed):
    rnd = random.Random(seed)
    rings = [(-1.8, 0.18, 0.0, 0.16, 0.16), (-0.6, 0.2, 0.1, 0.2, 0.19), (0.7, 0.18, -0.05, 0.17, 0.16), (1.9, 0.14, 0.12, 0.11, 0.11)]
    m.loft(K("wood", DRIFT), rings, segs=8)
    m.rod(K("wood", DRIFT), 0.06, (-1.6, 0.2, 0.05), (-2.4, 0.5, 0.6), segs=6)
    m.rod(K("wood", DRIFT), 0.05, (0.4, 0.22, 0.0), (0.9, 0.7, -0.5), segs=6)


def grass_tuft(m, seed):
    rnd = random.Random(seed)
    for k in range(7):
        a = rnd.uniform(0, 6.28)
        h = rnd.uniform(0.35, 0.7)
        base = (0.1 * math.cos(a), 0.0, 0.1 * math.sin(a))
        tip = (base[0] + 0.25 * math.cos(a) * h, h, base[2] + 0.25 * math.sin(a) * h)
        bm = bmesh.new()
        q = [(base[0] - 0.025 * math.sin(a), base[2] + 0.025 * math.cos(a), 0.0), (base[0] + 0.025 * math.sin(a), base[2] - 0.025 * math.cos(a), 0.0), (tip[0], tip[2], tip[1])]
        top = [bm.verts.new(v) for v in q]
        low = [bm.verts.new((v[0] + 0.01 * math.cos(a), v[1] + 0.01 * math.sin(a), v[2])) for v in q]
        bm.faces.new(top)
        bm.faces.new(low[::-1])
        for i in range(3):
            j = (i + 1) % 3
            bm.faces.new((top[i], low[i], low[j], top[j]))
        m._add(bm, K("leaf", (0.5, 0.58, 0.28) if k % 3 else (0.62, 0.6, 0.34)), "Body", 0)


def shells(m, seed):
    rnd = random.Random(seed)
    for k in range(10):
        a, d = rnd.uniform(0, 6.28), rnd.uniform(0.1, 0.9)
        x, z = d * math.cos(a), d * math.sin(a)
        if k % 3 == 0:
            m.ball(K("paint", (0.92, 0.85, 0.75)), (0.06, 0.025, 0.05), (x, 0.01, z), yaw=rnd.uniform(0, 180), u=8, v=4)
        else:
            m.ball(K("rock", (0.6, 0.58, 0.55)), (0.07, 0.04, 0.06), (x, 0.01, z), yaw=rnd.uniform(0, 180), u=6, v=4)


def coconuts(m, seed):
    rnd = random.Random(seed)
    for k in range(5):
        a = rnd.uniform(0, 6.28)
        m.ball(K("paint", (0.38, 0.27, 0.13)), 0.14, (0.25 * math.cos(a), 0.12 + (0.2 if k == 4 else 0.0), 0.25 * math.sin(a)), u=10, v=7)


def ruin_wall(m, seed):
    rnd = random.Random(seed)
    for row in range(5):
        x = -2.0
        while x < 2.0:
            w = rnd.uniform(0.5, 0.8)
            if row < 2 or rnd.random() > 0.25 * row:
                m.box(K("stone", tuple(c * rnd.uniform(0.85, 1.05) for c in (0.62, 0.6, 0.55))), (w - 0.04, 0.38, 0.5), (x + w * 0.5, 0.2 + row * 0.4, rnd.uniform(-0.04, 0.04)), bevel=0.04)
            x += w
    fk.blob(m, K("leaf", LEAF), (0.6, 0.4, 0.5), (1.4, 1.5, 0.0), seed=seed, rough=0.3, cuts=2)


BARK = (0.42, 0.34, 0.26)
CANOPY = [(0.2, 0.42, 0.16), (0.25, 0.48, 0.18), (0.3, 0.5, 0.2), (0.18, 0.36, 0.15)]


def broadleaf(m, seed, height, spread):
    """A broadleaf tree: a bending trunk, three branches and a crown of leafy lumps (the jungle and meadow trees)."""
    rnd = random.Random(seed)
    lean = rnd.uniform(-0.4, 0.4)
    rings = [(0.0, 0.0, 0.0, 0.32, 0.3), (lean * 0.3, height * 0.35, 0.05, 0.22, 0.21), (lean * 0.7, height * 0.7, -0.05, 0.16, 0.15), (lean, height, 0.0, 0.11, 0.1)]
    m.loft(K("bark", BARK), rings, segs=7, steps=2)
    for k in range(4):  # root flares
        a = k * math.pi / 2 + rnd.uniform(-0.3, 0.3)
        m.rod(K("bark", BARK), 0.12, (0.0, 0.5, 0.0), (0.7 * math.cos(a), -0.05, 0.7 * math.sin(a)), r2=0.05, segs=5)
    top = (lean, height, 0.0)
    for k in range(3):
        a = k * 2.1 + rnd.uniform(-0.3, 0.3)
        tip = (lean * 0.8 + spread * 0.6 * math.cos(a), height * rnd.uniform(0.82, 0.95), spread * 0.6 * math.sin(a))
        m.rod(K("bark", BARK), 0.09, (lean * 0.6, height * 0.6, 0.0), tip, r2=0.05, segs=5)
        fk.blob(m, K("leaf", rnd.choice(CANOPY)), (spread * 0.5, spread * 0.38, spread * 0.5), (tip[0], tip[1] + spread * 0.15, tip[2]), seed=seed + 10 + k, rough=0.25, cuts=1)
    fk.blob(m, K("leaf", rnd.choice(CANOPY)), (spread * 0.7, spread * 0.5, spread * 0.7), (top[0], top[1] + spread * 0.25, top[2]), seed=seed + 20, rough=0.22, cuts=2)


def jungle_giant(m, seed):
    """A tall jungle tree: buttress roots, a long straight trunk and a flat umbrella crown above the rest."""
    rnd = random.Random(seed)
    h = 16.0
    m.loft(K("bark", (0.5, 0.44, 0.36)), [(0.0, 0.0, 0.0, 0.55, 0.5), (0.0, 2.0, 0.0, 0.4, 0.38), (0.1, h * 0.6, 0.0, 0.3, 0.28), (0.2, h, 0.0, 0.2, 0.2)], segs=8, steps=2)
    for k in range(5):  # buttress fins
        a = k * 2 * math.pi / 5 + rnd.uniform(-0.2, 0.2)
        d = (math.cos(a), math.sin(a))
        m.loft(K("bark", (0.5, 0.44, 0.36)), [(d[0] * 0.3, 2.8, d[1] * 0.3, 0.06, 0.12), (d[0] * 0.9, 1.2, d[1] * 0.9, 0.08, 0.35), (d[0] * 1.6, 0.0, d[1] * 1.6, 0.06, 0.18)], segs=5, steps=2)
    for k in range(6):
        a = k * math.pi / 3 + rnd.uniform(-0.2, 0.2)
        r = rnd.uniform(2.0, 3.8)
        fk.blob(m, K("leaf", rnd.choice(CANOPY)), (2.6, 1.0, 2.6), (0.2 + r * math.cos(a), h + rnd.uniform(-0.4, 0.6), r * math.sin(a)), seed=seed + k, rough=0.25, cuts=1)
    fk.blob(m, K("leaf", rnd.choice(CANOPY)), (3.2, 1.3, 3.2), (0.2, h + 0.8, 0.0), seed=seed + 9, rough=0.2, cuts=2)
    for k in range(3):  # hanging lianas
        a = rnd.uniform(0, 6.28)
        top = (0.2 + 2.5 * math.cos(a), h - 0.4, 2.5 * math.sin(a))
        m.rod(K("leaf", (0.25, 0.35, 0.15)), 0.035, top, (top[0] * 1.1, h - rnd.uniform(5.0, 9.0), top[2] * 1.1), segs=4)


def flowers(m, seed):
    rnd = random.Random(seed)
    colours = [(0.85, 0.2, 0.25), (0.95, 0.8, 0.2), (0.95, 0.95, 0.92), (0.6, 0.35, 0.8), (0.95, 0.5, 0.2)]
    for k in range(9):
        a, d = rnd.uniform(0, 6.28), rnd.uniform(0.0, 0.7)
        x, z = d * math.cos(a), d * math.sin(a)
        h = rnd.uniform(0.25, 0.5)
        m.rod(K("leaf", (0.3, 0.5, 0.2)), 0.012, (x, 0.0, z), (x, h, z), segs=3)
        m.ball(K("paint", rnd.choice(colours)), (0.06, 0.035, 0.06), (x, h, z), u=6, v=3)


def reeds(m, seed):
    rnd = random.Random(seed)
    for k in range(10):
        a, d = rnd.uniform(0, 6.28), rnd.uniform(0.0, 0.5)
        x, z = d * math.cos(a), d * math.sin(a)
        h = rnd.uniform(1.2, 2.0)
        tip = (x + rnd.uniform(-0.15, 0.15), h, z + rnd.uniform(-0.15, 0.15))
        m.rod(K("leaf", (0.42, 0.52, 0.25)), 0.016, (x, -0.2, z), tip, r2=0.006, segs=3)
        if k % 3 == 0:
            m.rod(K("paint", (0.36, 0.24, 0.14)), 0.035, (tip[0], h * 0.8, tip[2]), (tip[0], h * 0.95, tip[2]), segs=5)


def dune_grass(m, seed):
    rnd = random.Random(seed)
    for k in range(9):
        a = rnd.uniform(0, 6.28)
        h = rnd.uniform(0.5, 0.9)
        lean = rnd.uniform(0.2, 0.45)
        m.rod(K("leaf", (0.68, 0.66, 0.42) if k % 2 else (0.56, 0.6, 0.34)), 0.014, (0.06 * math.cos(a), 0.0, 0.06 * math.sin(a)), (lean * math.cos(a), h, lean * math.sin(a)), r2=0.004, segs=3)


def vine(m, seed):
    """Vines hanging down a cliff face from its top edge, draping out along +forward (the game turns it downhill)."""
    rnd = random.Random(seed)
    for k in range(5):
        x = rnd.uniform(-1.5, 1.5)
        length = rnd.uniform(4.0, 8.0)
        prev = (x, 0.2, 0.0)
        for j in range(1, 5):
            t = j / 4.0
            cur = (x + rnd.uniform(-0.2, 0.2), 0.2 - length * t, 0.3 + 0.6 * t)
            m.rod(K("leaf", (0.22, 0.4, 0.16)), 0.03, prev, cur, segs=4)
            fk.blob(m, K("leaf", rnd.choice(CANOPY)), (0.3, 0.25, 0.18), cur, seed=seed + k * 10 + j, rough=0.3, cuts=1)
            prev = cur


def outcrop_slabs(m, seed):
    """Layered sedimentary rock: uneven flat slabs piled off-centre into a 6 m crag with a ledge."""
    rnd = random.Random(seed)
    y = -0.8
    w = 6.5
    x = z = 0.0
    while y < 5.5:
        fk.blob(m, K("rock", tuple(c * rnd.uniform(0.85, 1.05) for c in (0.62, 0.57, 0.5))), (w * rnd.uniform(0.45, 0.6), 0.55, w * rnd.uniform(0.3, 0.42)), (x, y, z), seed=seed + int(y * 10), rough=0.14, cuts=2)
        y += 0.8
        w *= rnd.uniform(0.78, 0.93)
        x += rnd.uniform(-0.6, 0.6)
        z += rnd.uniform(-0.4, 0.4)
    fk.blob(m, K("leaf", CANOPY[1]), (1.0, 0.35, 0.8), (x, y - 0.2, z), seed=seed, rough=0.3, cuts=1)


def outcrop_spires(m, seed):
    """A cluster of rock spires up to 9 m."""
    rnd = random.Random(seed)
    for k in range(5):
        a, d = rnd.uniform(0, 6.28), rnd.uniform(0.0, 2.2)
        h = rnd.uniform(3.5, 9.0)
        x, z = d * math.cos(a), d * math.sin(a)
        r = rnd.uniform(0.7, 1.3)
        m.loft(K("rock", tuple(c * rnd.uniform(0.85, 1.05) for c in ROCK)), [(x, -1.0, z, r * 1.2, r), (x + 0.2, h * 0.5, z, r * 0.8, r * 0.75), (x + 0.3, h, z + 0.1, r * 0.35, r * 0.3)], segs=6, steps=2)


def outcrop_tor(m, seed):
    """A granite tor: rounded boulders of mixed sizes piled and leaning, about 5 m high."""
    rnd = random.Random(seed)
    y = 0.0
    x = z = 0.0
    for k in range(5):
        r = rnd.uniform(1.4, 2.8) * (1.0 - k * 0.12)
        fk.blob(m, K("rock", tuple(c * rnd.uniform(0.9, 1.05) for c in (0.6, 0.58, 0.55))), (r * rnd.uniform(0.9, 1.2), r * 0.62, r * rnd.uniform(0.7, 0.95)), (x, y, z), seed=seed + k, rough=0.12, cuts=2)
        y += r * 0.7
        x += rnd.uniform(-0.9, 0.9)
        z += rnd.uniform(-0.7, 0.7)
    for k in range(3):
        a = rnd.uniform(0, 6.28)
        fk.blob(m, K("rock", (0.57, 0.55, 0.52)), (1.0, 0.6, 0.8), (3.0 * math.cos(a), 0.0, 3.0 * math.sin(a)), seed=seed + 20 + k, rough=0.15, cuts=1)


CORAL = [(0.92, 0.45, 0.45), (0.95, 0.6, 0.3), (0.65, 0.4, 0.75), (0.95, 0.85, 0.5), (0.4, 0.75, 0.7)]


def reef(m, seed, size):
    """Shallow reef: a low rock with branching coral, fans and brain corals."""
    rnd = random.Random(seed)
    fk.blob(m, K("rock", (0.5, 0.52, 0.5)), (size, size * 0.4, size * 0.8), (0.0, 0.0, 0.0), seed=seed, rough=0.25, cuts=2)
    for k in range(int(6 * size)):
        a, d = rnd.uniform(0, 6.28), rnd.uniform(0.0, size * 0.8)
        x, z = d * math.cos(a), d * math.sin(a)
        y = size * 0.3
        col = rnd.choice(CORAL)
        kind = k % 3
        if kind == 0:  # branching
            for b in range(3):
                bb = rnd.uniform(0, 6.28)
                m.rod(K("paint", col), 0.05, (x, y, z), (x + 0.3 * math.cos(bb), y + rnd.uniform(0.4, 0.8), z + 0.3 * math.sin(bb)), r2=0.025, segs=4)
        elif kind == 1:  # fan
            bm_y = rnd.uniform(0, 180)
            m.ball(K("paint", col), (0.45, 0.4, 0.04), (x, y + 0.35, z), yaw=bm_y, u=8, v=4)
        else:  # brain coral
            m.ball(K("paint", col), (0.3, 0.2, 0.3), (x, y, z), u=8, v=5)


def coral(m, seed):
    rnd = random.Random(seed)
    for k in range(5):
        a = rnd.uniform(0, 6.28)
        col = rnd.choice(CORAL)
        m.rod(K("paint", col), 0.04, (0.0, 0.0, 0.0), (0.4 * math.cos(a), rnd.uniform(0.4, 0.7), 0.4 * math.sin(a)), r2=0.02, segs=4)
    m.ball(K("paint", rnd.choice(CORAL)), (0.25, 0.18, 0.25), (0.2, 0.05, -0.1), u=8, v=5)


# --- region 2, the Fog Banks (sea step 13 R2a): mangroves, reed beds, peat, glowcaps, lantern posts ---
MANGROVE_LEAF = [(0.16, 0.3, 0.14), (0.2, 0.34, 0.15), (0.14, 0.27, 0.12)]
MANGROVE_BARK = (0.4, 0.34, 0.27)


def mangrove(m, seed, height, spread):
    """A mangrove: the trunk stands 1.6 m up on a cage of arching prop roots, a few roots drop from the branches,
    a low dark crown of leafy lumps."""
    rnd = random.Random(seed)
    base = 1.6
    m.loft(K("bark", MANGROVE_BARK), [(0.0, base, 0.0, 0.26, 0.24), (0.15, base + height * 0.45, 0.0, 0.2, 0.19), (0.25, height, 0.05, 0.12, 0.11)], segs=7, steps=2)
    n = 7 + seed % 3
    for k in range(n):  # prop roots: out and down in an arch
        a = 2 * math.pi * k / n + rnd.uniform(-0.25, 0.25)
        reach = rnd.uniform(1.3, 2.3)
        mid = (0.55 * reach * math.cos(a), base + rnd.uniform(0.3, 0.7), 0.55 * reach * math.sin(a))
        m.rod(K("bark", MANGROVE_BARK), 0.09, (0.12 * math.cos(a), base + 0.2, 0.12 * math.sin(a)), mid, r2=0.07, segs=5)
        m.rod(K("bark", MANGROVE_BARK), 0.07, mid, (reach * math.cos(a), -0.3, reach * math.sin(a)), r2=0.05, segs=5)
    for k in range(3):  # branches with crowns
        a = k * 2.1 + rnd.uniform(-0.3, 0.3)
        tip = (0.2 + spread * 0.55 * math.cos(a), height * rnd.uniform(0.8, 0.95), spread * 0.55 * math.sin(a))
        m.rod(K("bark", MANGROVE_BARK), 0.07, (0.2, height * 0.6, 0.0), tip, r2=0.04, segs=5)
        fk.blob(m, K("leaf", rnd.choice(MANGROVE_LEAF)), (spread * 0.5, spread * 0.3, spread * 0.5), (tip[0], tip[1] + spread * 0.1, tip[2]), seed=seed + 10 + k, rough=0.28, cuts=1)
        if k < 2:  # an aerial root hanging down from the branch
            m.rod(K("bark", (0.36, 0.3, 0.24)), 0.025, (tip[0] * 0.8, tip[1] - 0.3, tip[2] * 0.8), (tip[0] * 0.85, rnd.uniform(0.4, 1.2), tip[2] * 0.85), segs=3)
    fk.blob(m, K("leaf", rnd.choice(MANGROVE_LEAF)), (spread * 0.65, spread * 0.38, spread * 0.65), (0.25, height + spread * 0.15, 0.05), seed=seed + 20, rough=0.25, cuts=2)


def reed_bed(m, seed):
    """A thick bed of tall reeds and bulrushes about 2.5 m across (the marsh edges)."""
    rnd = random.Random(seed)
    for k in range(26):
        a, d = rnd.uniform(0, 6.28), rnd.uniform(0.0, 1.25)
        x, z = d * math.cos(a), d * math.sin(a)
        h = rnd.uniform(1.4, 2.4)
        tip = (x + rnd.uniform(-0.2, 0.2), h, z + rnd.uniform(-0.2, 0.2))
        m.rod(K("leaf", rnd.choice([(0.4, 0.48, 0.24), (0.5, 0.5, 0.3), (0.34, 0.42, 0.2)])), 0.017, (x, -0.2, z), tip, r2=0.006, segs=3)
        if k % 4 == 0:
            m.rod(K("paint", (0.32, 0.22, 0.13)), 0.04, (tip[0], h * 0.78, tip[2]), (tip[0], h * 0.93, tip[2]), segs=5)


def peat_mound(m, seed):
    """A low mound of dark peat and moss with a few grass tufts."""
    rnd = random.Random(seed)
    fk.blob(m, K("rock", (0.26, 0.2, 0.15)), (1.6, 0.55, 1.3), (0.0, 0.05, 0.0), seed=seed, rough=0.2, cuts=2)
    fk.blob(m, K("leaf", (0.3, 0.38, 0.18)), (1.2, 0.35, 1.0), (0.2, 0.3, -0.1), seed=seed + 1, rough=0.3, cuts=1)
    for k in range(5):
        a = rnd.uniform(0, 6.28)
        x, z = 0.9 * math.cos(a), 0.7 * math.sin(a)
        m.rod(K("leaf", (0.45, 0.5, 0.26)), 0.015, (x, 0.2, z), (x * 1.15, 0.75, z * 1.15), r2=0.004, segs=3)


def glowcap(m, seed):
    """A cluster of pale marsh mushrooms whose caps glow faintly (the Fog Banks' night lights)."""
    rnd = random.Random(seed)
    for k in range(7):
        a, d = rnd.uniform(0, 6.28), rnd.uniform(0.0, 0.45)
        x, z = d * math.cos(a), d * math.sin(a)
        h = rnd.uniform(0.12, 0.38)
        m.rod(K("paint", (0.82, 0.8, 0.72)), 0.025, (x, 0.0, z), (x, h, z), segs=4)
        m.ball(fk.GLOW, (rnd.uniform(0.06, 0.12), 0.04, rnd.uniform(0.06, 0.12)), (x, h, z), u=8, v=4)


def lantern_post(m, seed):
    """A marsh lantern post: a tarred pole, a crook arm and a hanging lantern (the Fog Banks' way markers)."""
    m.rod(K("wood", (0.24, 0.19, 0.14)), 0.08, (0.0, -0.4, 0.0), (0.0, 2.7, 0.0), r2=0.06, segs=6)
    m.rod(K("wood", (0.24, 0.19, 0.14)), 0.04, (0.0, 2.55, 0.0), (0.6, 2.75, 0.0), segs=4)
    m.rod(K("metal", (0.2, 0.2, 0.2)), 0.008, (0.6, 2.75, 0.0), (0.6, 2.45, 0.0), segs=3)
    m.box(K("metal", (0.18, 0.17, 0.16)), (0.26, 0.04, 0.26), (0.6, 2.44, 0.0), bevel=0.01)
    m.box(fk.GLOW, (0.18, 0.24, 0.18), (0.6, 2.3, 0.0), bevel=0.01)
    m.box(K("metal", (0.18, 0.17, 0.16)), (0.24, 0.04, 0.24), (0.6, 2.16, 0.0), bevel=0.01)


PROPS = {
    "palm_a": lambda m: palm(m, 7.5, 0.18, 1),
    "palm_b": lambda m: palm(m, 9.5, 0.32, 2),
    "bush": lambda m: bush(m, 3),
    "fern": lambda m: fern(m, 4),
    "boulder_a": lambda m: boulder(m, 1.2, 5),
    "boulder_b": lambda m: boulder(m, 2.4, 6, flat=0.8),
    "boulder_c": lambda m: boulder(m, 0.6, 7),
    "sea_stack": lambda m: sea_stack(m, 8),
    "driftwood": lambda m: driftwood(m, 9),
    "grass_tuft": lambda m: grass_tuft(m, 10),
    "shells": lambda m: shells(m, 11),
    "coconuts": lambda m: coconuts(m, 12),
    "ruin_wall": lambda m: ruin_wall(m, 13),
    "broadleaf_a": lambda m: broadleaf(m, 21, 7.0, 4.0),
    "broadleaf_b": lambda m: broadleaf(m, 22, 10.0, 5.5),
    "jungle_giant": lambda m: jungle_giant(m, 23),
    "flowers": lambda m: flowers(m, 24),
    "reeds": lambda m: reeds(m, 25),
    "dune_grass": lambda m: dune_grass(m, 26),
    "vine": lambda m: vine(m, 27),
    "outcrop_slabs": lambda m: outcrop_slabs(m, 28),
    "outcrop_spires": lambda m: outcrop_spires(m, 29),
    "outcrop_tor": lambda m: outcrop_tor(m, 30),
    "reef_a": lambda m: reef(m, 31, 1.6),
    "reef_b": lambda m: reef(m, 32, 2.6),
    "coral": lambda m: coral(m, 33),
    "mangrove_a": lambda m: mangrove(m, 41, 6.5, 4.0),
    "mangrove_b": lambda m: mangrove(m, 42, 9.0, 5.5),
    "reed_bed": lambda m: reed_bed(m, 43),
    "peat_mound": lambda m: peat_mound(m, 44),
    "glowcap": lambda m: glowcap(m, 45),
    "lantern_post": lambda m: lantern_post(m, 46),
}

if __name__ == "__main__":
    fk.init()
    for name, build in PROPS.items():
        if fk.ONLY and name not in fk.ONLY:
            continue
        m = kit.Model(name, uv_scale=0.6, colored=True)
        build(m)
        print(name, m.export(OUT))
