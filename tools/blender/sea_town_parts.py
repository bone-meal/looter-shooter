# Purpose: developer-time helpers for the HOME PORT TOWN's buildings (sea step 7, tools/blender/sea_town.py): one
# way of building per STYLE, the town's growth from weathered fishing shacks to a stone colonial port (director:
# "c": grows from fishing shacks to stone colonial; every upgrade visibly rebuilt, different at a glance):
#   0 SHACK      driftwood clapboards on stilts, palm thatch with a ragged fringe, cloth over the window holes
#   1 COTTAGE    dry-stone footing, painted board-and-batten, white trim, shuttered glass windows, shingle roof, porch
#   2 FRAMED     rubble plinth, timber frame with plaster panels, leaded windows, shingle roof, chimney (fantasy_house)
#   3 STONE      dressed-stone ground floor with quoins, framed upper floor with a balcony, red tile roof with dormers
#   4 COLONIAL   whitewashed stone, two tall storeys, arched windows with louvred shutters, cornice, hip roof of tiles
# plus RUINS (a building waiting to be repaired: broken walls, a fallen roof, planks and weeds), front steps,
# terraces (a building stands on a level terrace whose edge shows where the slope falls away), hanging signs with an
# emblem per trade, lanterns, crates, barrels, nets. Model space: x right, y up, f forward (the front, the door).
# Dependencies: bpy, bmesh, tools/blender/kit.py, fantasy_kit.py, fantasy_house.py. No game code.
import math
import random

import bmesh
from mathutils import Matrix

import fantasy_kit as fk
import fantasy_house as fh
from fantasy_kit import K, c
from fantasy_house import Face

GLASS = (0.13, 0.17, 0.23)
IRON = (0.2, 0.2, 0.22)
WHITE = (0.93, 0.91, 0.85)
DRIFT = (0.62, 0.59, 0.53)
THATCH = (0.66, 0.55, 0.32)
ROPE = (0.66, 0.56, 0.38)
GOLD = (0.88, 0.68, 0.25)
P_BRONZE = (0.62, 0.45, 0.22)
DEEP = -2.6  # foundations reach this far below the plot's ground (slopes are hidden by them)

SCHEMES = {  # the fantasy_house way of naming colours and what each part is made of, one per style
    0: {"kinds": {"wall": "wood", "roof": "thatch", "stone": "stone"}, "wall": DRIFT, "timber": (0.42, 0.36, 0.3), "roof": THATCH, "stone": (0.5, 0.48, 0.45), "trim": (0.45, 0.38, 0.3)},
    1: {"kinds": {"wall": "wood", "roof": "roof", "stone": "stone"}, "wall": (0.3, 0.52, 0.55), "timber": (0.4, 0.3, 0.22), "roof": (0.44, 0.38, 0.32), "stone": (0.55, 0.53, 0.5), "trim": WHITE},
    2: {"kinds": {"wall": "plaster", "roof": "roof", "stone": "stone"}, "wall": (0.92, 0.87, 0.74), "timber": (0.3, 0.2, 0.13), "roof": (0.48, 0.34, 0.25), "stone": (0.58, 0.56, 0.52), "trim": (0.2, 0.42, 0.48)},
    3: {"kinds": {"wall": "plaster", "roof": "roof", "stone": "stone"}, "wall": (0.94, 0.9, 0.8), "timber": (0.32, 0.22, 0.15), "roof": (0.72, 0.34, 0.2), "stone": (0.68, 0.63, 0.55), "trim": (0.16, 0.36, 0.42)},
    4: {"kinds": {"wall": "plaster", "roof": "roof", "stone": "stone"}, "wall": (0.96, 0.95, 0.91), "timber": (0.35, 0.25, 0.18), "roof": (0.74, 0.36, 0.22), "stone": (0.74, 0.69, 0.6), "trim": (0.16, 0.38, 0.3)},
}
FLOOR = {0: 0.55, 1: 0.45, 2: 0.6, 3: 0.75, 4: 0.9}  # the floor's height over the plot's ground per style
STOREY = {0: 2.3, 1: 2.6, 2: 2.5, 3: 2.8, 4: 3.3}


def scheme(style, wall=None, trim=None):
    s = dict(SCHEMES[style])
    s["kinds"] = dict(s["kinds"])
    if wall is not None:
        s["wall"] = wall
    if trim is not None:
        s["trim"] = trim
    return s


def tone(mat, k):
    return (mat[0], tuple(min(v * k, 1.0) for v in mat[1]))


def blk(m, mat, size, at, yaw=0.0, pitch=0.0, roll=0.0, bevel=0.0, node="Body"):
    """A block (x, y, f size) at (x, y, f), turned by yaw (about up, degrees), then pitch (about its own x), roll
    (about its own forward axis)."""
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0, matrix=Matrix.Translation((at[0], at[2], at[1])) @ Matrix.Rotation(math.radians(yaw), 4, "Z")
        @ Matrix.Rotation(math.radians(pitch), 4, "X") @ Matrix.Rotation(math.radians(roll), 4, "Y") @ Matrix.Diagonal((size[0], size[2], size[1], 1.0)))
    m._add(bm, mat, node, bevel)


def poly(m, mat, pts, faces, node="Body"):
    """A solid from corners (x, y, f) and faces (lists of corner indices)."""
    bm = bmesh.new()
    vs = [bm.verts.new((p[0], p[2], p[1])) for p in pts]
    for f in faces:
        bm.faces.new([vs[i] for i in f])
    m._add(bm, mat, node, 0)


def plate(m, mat, pts, f, t=0.02):
    """A flat shape [(x, y), ...] (convex, any winding) made `t` thick, centred on f."""
    n = len(pts)
    corners = [(x, y, f - t / 2) for x, y in pts] + [(x, y, f + t / 2) for x, y in pts]
    poly(m, mat, corners, [list(range(n)), list(range(2 * n - 1, n - 1, -1))] + [[k, (k + 1) % n, n + (k + 1) % n, n + k] for k in range(n)])


FACE_YAW = {"front": 0.0, "back": 180.0, "right": -90.0, "left": 90.0}


def faces_of(m, hw, hd):
    return [Face(m, "front", hd, hw), Face(m, "back", hd, hw), Face(m, "right", hw, hd), Face(m, "left", hw, hd)]


def fblk(face, mat, su, sy, sn, u, y, n=0.0, pitch=0.0):
    """A block on a wall face, tilted out at its foot by `pitch` degrees (clapboards)."""
    blk(face.m, mat, (su, sy, sn), face.at(u, y, n), yaw=FACE_YAW[face.name], pitch=pitch)


# --- walk-in storeys (director 2026-11-17: REAL INTERIORS in the trophy hall and the gallery) ---

WALL_T = 0.25  # a walk-in storey's walls
LINING = 0.04  # the plastered inside of them


def inside(wall=(0.86, 0.82, 0.72), wainscot=(0.34, 0.22, 0.14), floor=(0.46, 0.33, 0.21), ceiling=(0.42, 0.31, 0.2), flags=False, door=(1.6, 2.5), leaf=(0.35, 0.22, 0.14), plaster_ceiling=False):
    """What a walk-in storey looks like inside: plaster, a dark wood wainscot, a plank (or flagstone) floor, a boarded
    ceiling on beams, the doorway's size (width, height) and the door leaf's colour (it stands open against the wall)."""
    return {"wall": wall, "wainscot": wainscot, "floor": floor, "ceiling": ceiling, "flags": flags, "door": door, "leaf": leaf, "windows": [], "plaster_ceiling": plaster_ceiling}


def hollow(m, mat, w, h, d, y0, door_u, ins):
    """A walk-in storey in place of a solid block: walls WALL_T thick with a doorway in the front, lined inside,
    wainscot and dado rail, floor, ceiling on beams, the windows' glass seen from inside (ins["windows"] =
    (face, u, y, ww, wh) of the windows the style drew outside) and the door leaf swung back against the wall."""
    t, hw, hd = WALL_T, w / 2, d / 2
    dw, dh = ins["door"]
    blk(m, mat, (w, h, t), (0.0, y0 + h / 2, -hd + t / 2))
    for sx in (-1, 1):
        blk(m, mat, (t, h, d - 2 * t), (sx * (hw - t / 2), y0 + h / 2, 0.0))
    a, b = door_u - dw / 2, door_u + dw / 2
    blk(m, mat, (a + hw, h, t), ((a - hw) / 2, y0 + h / 2, hd - t / 2))
    blk(m, mat, (hw - b, h, t), ((b + hw) / 2, y0 + h / 2, hd - t / 2))
    blk(m, mat, (dw, h - dh, t), (door_u, y0 + dh + (h - dh) / 2, hd - t / 2))
    blk(m, K("stone", (0.6, 0.57, 0.52)), (dw, 0.06, t + 0.1), (door_u, y0 + 0.01, hd - t / 2))  # threshold
    lin, wain = K("plaster", ins["wall"]), K("wood", ins["wainscot"])
    iw, idep = w - 2 * t, d - 2 * t
    inner = [Face(m, "back", hd - t, hw - t), Face(m, "right", hw - t, hd - t), Face(m, "left", hw - t, hd - t), Face(m, "front", hd - t, hw - t)]
    for face in inner:  # n < 0 = into the room
        spans = [(-face.half, face.half)] if face.name != "front" else [(-face.half, a), (b, face.half)]
        for u0, u1 in spans:
            if u1 - u0 < 0.02:
                continue
            fblk(face, lin, u1 - u0, h, LINING, (u0 + u1) / 2, y0 + h / 2, -LINING / 2)
            fblk(face, wain, u1 - u0, 1.0, 0.03, (u0 + u1) / 2, y0 + 0.5, -LINING - 0.015)
            fblk(face, tone(wain, 0.8), u1 - u0, 0.07, 0.06, (u0 + u1) / 2, y0 + 1.02, -LINING - 0.03)  # dado rail
            fblk(face, tone(wain, 0.75), u1 - u0, 0.12, 0.04, (u0 + u1) / 2, y0 + 0.06, -LINING - 0.02)  # skirting
            fblk(face, tone(wain, 0.9), u1 - u0, 0.1, 0.08, (u0 + u1) / 2, y0 + h - 0.05, -LINING - 0.04)  # cornice
    floor = K("stone", ins["floor"]) if ins["flags"] else K("wood", ins["floor"])
    blk(m, floor, (iw, 0.08, idep), (0.0, y0 - 0.03, 0.0))
    if ins["flags"]:
        for i in range(int(iw / 0.9) + 1):
            blk(m, tone(floor, 0.82), (0.025, 0.012, idep), (-iw / 2 + i * 0.9, y0 + 0.012, 0.0))
        for j in range(int(idep / 0.9) + 1):
            blk(m, tone(floor, 0.82), (iw, 0.012, 0.025), (0.0, y0 + 0.012, -idep / 2 + j * 0.9))
    else:
        for i in range(int(iw / 0.22)):
            blk(m, tone(floor, 0.86 if i % 2 else 0.95), (0.012, 0.012, idep), (-iw / 2 + 0.11 + i * 0.22, y0 + 0.012, 0.0))
    ceil = K("plaster", ins["ceiling"]) if ins["plaster_ceiling"] else K("wood", ins["ceiling"])
    blk(m, ceil, (iw, 0.06, idep), (0.0, y0 + h - 0.03, 0.0))
    for k in range(1, int(idep / 2.2) + 1):
        blk(m, tone(ceil, 0.7), (iw, 0.22, 0.2), (0.0, y0 + h - 0.17, -idep / 2 + k * idep / (int(idep / 2.2) + 1)))
    for face, u, wy, ww, wh in ins["windows"]:
        back = Face(m, face.name, face.plane - t, face.half - t)
        fblk(back, K("wood", ins["wainscot"]), ww + 0.16, wh + 0.16, 0.05, u, wy, -LINING - 0.02)
        fblk(back, c(GLASS), ww, wh, 0.05, u, wy, -LINING - 0.035)
        fblk(back, K("wood", ins["wainscot"]), 0.04, wh, 0.06, u, wy, -LINING - 0.05)
    front = inner[3]
    if b + dw <= front.half:  # the door leaf, swung back flat against the wall right of the doorway
        fblk(front, K("wood", ins["leaf"]), dw - 0.1, dh - 0.06, 0.06, b + dw / 2, y0 + dh / 2, -LINING - 0.06)
        for dy in (0.5, dh - 0.5):
            fblk(front, K("metal", IRON), dw - 0.2, 0.06, 0.02, b + dw / 2, y0 + dy, -LINING - 0.1)


def door_frame(face, mat, u, y0, dw, dh, depth=0.08, n=0.04, bar=0.16):
    """The frame round an open doorway (jambs and a head), drawn on the outside wall."""
    for side in (-1, 1):
        fblk(face, mat, bar, dh + bar, depth, u + side * (dw / 2 + bar / 2), y0 + (dh + bar) / 2, n)
    fblk(face, mat, dw + 2 * bar, bar, depth, u, y0 + dh + bar / 2, n)


# --- ground: foundations, terraces, steps ---

def terrace(m, mat, w, d, y=0.0, f=0.0, x=0.0, cap=None):
    """A level terrace: its top at `y`, its body down to DEEP (where the slope falls away it shows as a wall), paved
    with flagstones of slightly different shades when `cap` is given."""
    blk(m, tone(mat, 0.8), (w, y - DEEP, d), (x, (y + DEEP) / 2, f))
    if cap is not None:
        rnd = random.Random(int(w * 10 + d))
        nx, nf = max(1, int(w / 1.3)), max(1, int(d / 1.3))
        for i in range(nx):
            for j in range(nf):
                blk(m, tone(cap, 0.82 + 0.22 * rnd.random()), (w / nx - 0.05, 0.1, d / nf - 0.05), (x - w / 2 + (i + 0.5) * w / nx, y + 0.01, f - d / 2 + (j + 0.5) * d / nf))


def steps(m, mat, x, f0, width, top, rise=0.18, run=0.32, down_to=-1.2, way=1.0):
    """Steps from `top` down and out (along f, way +1 = forward) to `down_to`; the lowest ones are buried in rising ground."""
    count = max(1, int(math.ceil((top - down_to) / rise)))
    for k in range(count):
        y = top - rise * (k + 1)
        blk(m, mat, (width, y - DEEP, run + 0.02), (x, (y + DEEP) / 2, f0 + way * (run * (k + 0.5))))


# --- style 0: the fishing shack ---

def stilts(m, w, d, fl):
    wood = K("wood", DRIFT)
    xs = [-w / 2, w / 2] if w < 5.5 else [-w / 2, 0.0, w / 2]
    for x in xs:
        for f in (-d / 2, d / 2):
            m.rod(tone(wood, 0.8), 0.1, (x, DEEP, f), (x, fl, f), segs=6)
    for f in (-d / 2, d / 2):  # cross braces under the floor
        m.rod(tone(wood, 0.7), 0.045, (-w / 2, -0.4, f), (w / 2, fl - 0.15, f), segs=4)
    rnd = random.Random(int(w * 100 + d))
    count = int((d + 0.8) / 0.28)
    for k in range(count):  # deck planks
        f = -d / 2 - 0.4 + (k + 0.5) * (d + 0.8) / count
        blk(m, tone(wood, 0.85 + 0.25 * rnd.random()), (w + 0.7 + 0.3 * rnd.random(), 0.07, 0.26), (0.0, fl - 0.035, f))


def clapboards(m, face, y0, height, holes, rnd, color=DRIFT):
    """Weathered boards across one wall face, each overlapping the one below, broken round the holes [(u0, u1, y0, y1)]."""
    wood = K("wood", color)
    rows = int(height / 0.26)
    for r in range(rows):
        y = y0 + 0.13 + r * height / rows
        runs = [(-face.half, face.half)]
        for u0, u1, h0, h1 in holes:
            if h0 - 0.05 < y < h1 + 0.05:
                runs = [p for a, b in runs for p in ((a, min(b, u0)), (max(a, u1), b)) if p[1] - p[0] > 0.12]
        for a, b in runs:
            fblk(face, tone(wood, 0.78 + 0.32 * rnd.random()), b - a, 0.28, 0.035, (a + b) / 2, y, 0.03 + 0.012 * rnd.random(), pitch=7.0)


def shack(m, w, d, s, door_u=0.0, windows=None, roof_h=1.5, fringe=True):
    """A one-room shack on stilts. Returns the height of its walls. `windows` = {face name: [u, ...]}."""
    fl, h = FLOOR[0], STOREY[0]
    rnd = random.Random(int(w * 37 + d * 11))
    windows = windows if windows is not None else {"front": [w / 2 - 1.0] if abs(door_u) < 0.6 else [], "right": [0.0], "left": [0.0]}
    stilts(m, w, d, fl)
    blk(m, K("wood", (0.24, 0.21, 0.18)), (w - 0.12, h, d - 0.12), (0.0, fl + h / 2, 0.0))
    for face in faces_of(m, w / 2, d / 2):
        holes = [(u - 0.4, u + 0.4, fl + 1.05, fl + 1.75) for u in windows.get(face.name, [])]
        if face.name == "front":
            holes.append((door_u - 0.55, door_u + 0.55, fl, fl + 2.0))
        clapboards(m, face, fl, h, holes, rnd)
        for u in windows.get(face.name, []):  # a hole with a cloth flap tied up over it
            fblk(face, K("wood", (0.1, 0.09, 0.08)), 0.8, 0.7, 0.04, u, fl + 1.4, 0.0)
            fblk(face, K("wood", DRIFT), 0.95, 0.08, 0.1, u, fl + 1.02, 0.06)
            fblk(face, K("cloth", (0.6, 0.25, 0.2) if rnd.random() < 0.5 else (0.28, 0.4, 0.55)), 0.86, 0.32, 0.03, u, fl + 1.62, 0.09, pitch=25.0)
    front = Face(m, "front", d / 2, w / 2)
    fblk(front, K("wood", (0.08, 0.07, 0.06)), 1.1, 2.0, 0.03, door_u, fl + 1.0, 0.0)
    for k in range(4):  # a door of four uneven boards, a gap between each
        fblk(front, K("wood", tone(K("wood", DRIFT), 0.7 + 0.12 * k)[1]), 0.23, 1.92 - 0.04 * (k % 2), 0.05, door_u - 0.39 + k * 0.26, fl + 0.98, 0.05)
    for y in (fl + 0.45, fl + 1.5):
        fblk(front, K("wood", (0.4, 0.34, 0.27)), 1.0, 0.1, 0.04, door_u, y, 0.09)
    for x in (-w / 2, w / 2):  # corner posts of rough poles
        for f in (-d / 2, d / 2):
            m.rod(K("wood", tone(K("wood", DRIFT), 0.75)[1]), 0.08, (x, fl, f), (x, fl + h + 0.1, f), segs=6)
    fh.gable_roof(m, s, w / 2, d / 2, fl + h, roof_h, dormers=0, timbered=False, gable_window=False)
    if fringe:  # the thatch's ragged eaves
        half = d / 2 + 0.6
        for way in (-1, 1):
            for k in range(int((w + 1.0) / 0.22)):
                x = -w / 2 - 0.45 + k * 0.22
                blk(m, tone(K("thatch", THATCH), 0.85 + 0.2 * rnd.random()), (0.2, 0.32 + 0.12 * rnd.random(), 0.12), (x, fl + h - 0.42, way * (half - 0.02)), pitch=way * 18.0)
    return fl + h


def nets(m, x, y, f, w, h, yaw=0.0):
    """A fishing net hung out to dry from two poles."""
    for side in (-1, 1):
        px = x + side * w / 2 * math.cos(math.radians(yaw))
        pf = f - side * w / 2 * math.sin(math.radians(yaw))
        m.rod(K("wood", DRIFT), 0.05, (px, -0.6, pf), (px, y + h + 0.2, pf), segs=5)
    cy, sy = math.cos(math.radians(yaw)), math.sin(math.radians(yaw))
    net = K("cloth", (0.3, 0.33, 0.27))
    for k in range(9):  # the mesh: cords across and down, sagging a little
        u = -w / 2 + w * k / 8
        m.rod(net, 0.012, (x + u * cy, y + 0.1, f - u * sy), (x + u * cy, y + h + 0.1 - 0.12 * math.sin(math.pi * k / 8), f - u * sy), segs=3)
    for k in range(6):
        hy = y + 0.1 + h * k / 5
        m.rod(net, 0.012, (x - w / 2 * cy, hy, f + w / 2 * sy), (x + w / 2 * cy, hy, f - w / 2 * sy), segs=3)
    for k in range(5):  # cork floats along its top line
        u = -w / 2 + w * (k + 0.5) / 5
        m.ball(K("wood", (0.75, 0.6, 0.35)), 0.07, (x + u * math.cos(math.radians(yaw)), y + h + 0.1, f - u * math.sin(math.radians(yaw))), u=6, v=4)


# --- style 1: the painted cottage ---

def cottage(m, w, d, s, door_u=0.0, floors=1, roof_h=2.0, windows=None, porch=True, gable_front=False, storey=None, ins=None):
    """`ins` (inside()): a walk-in storey (one floor) instead of a solid body."""
    fl, h = FLOOR[1], (storey or STOREY[1]) * floors
    hw, hd = w / 2, d / 2
    stone = K("stone", s["stone"])
    blk(m, stone, (w + 0.3, fl - DEEP, d + 0.3), (0.0, (fl + DEEP) / 2, 0.0))
    rnd = random.Random(int(w * 13 + d * 7))
    for face in faces_of(m, hw + 0.15, hd + 0.15):  # stones standing out of the dry-stone footing
        for k in range(int(face.half * 2.2)):
            fblk(face, tone(stone, 0.8 + 0.35 * rnd.random()), 0.3 + 0.25 * rnd.random(), 0.16 + 0.1 * rnd.random(), 0.06, -face.half + 0.3 + k * 0.9 + 0.2 * rnd.random(), fl - 0.12 - 0.3 * (k % 2), 0.0)
    paint = K("wood", s["wall"])
    white = K("wood", s["trim"])
    windows = windows if windows is not None else {}
    for face in faces_of(m, hw, hd):
        spots = windows.get(face.name)
        if spots is None:
            spots = [-face.half + 1.3, face.half - 1.3] if face.name in ("front", "back") and face.half > 2.2 else ([0.0] if face.half > 1.6 else [])
        if face.name == "front":
            spots = [u for u in spots if abs(u - door_u) > 1.3]
        dhw = ins["door"][0] / 2 + 0.2 if ins is not None else 0.7
        holes = [(u - 0.6, u + 0.6) for u in spots] + ([(door_u - dhw, door_u + dhw)] if face.name == "front" else [])
        u = -face.half + 0.2
        while u < face.half - 0.1:  # battens, broken round the windows (they run above and below them)
            if not any(a < u < b for a, b in holes):
                fblk(face, tone(paint, 0.82), 0.07, h - 0.1, 0.05, u, fl + h / 2, 0.02)
            u += 0.42
        for side in (-1, 1):
            fblk(face, white, 0.2, h + 0.05, 0.06, side * (face.half - 0.08), fl + h / 2, 0.035)
        fblk(face, white, 2 * face.half + 0.05, 0.16, 0.07, 0.0, fl + 0.08, 0.04)
        fblk(face, white, 2 * face.half + 0.05, 0.18, 0.07, 0.0, fl + h - 0.09, 0.04)
        for fl_k in range(floors):
            for u in spots:
                glass_window(face, s, u, fl + fl_k * STOREY[1] + 1.45, 0.85, 1.05, shutters=True)
                if ins is not None:
                    ins["windows"].append((face, u, fl + 1.45, 0.85, 1.05))
    front = Face(m, "front", hd, hw)
    if ins is not None:
        hollow(m, paint, w, h, d, fl, door_u, ins)
        door_frame(front, white, door_u, fl, ins["door"][0], ins["door"][1])
    else:
        blk(m, paint, (w, h, d), (0.0, fl + h / 2, 0.0))
        fblk(front, white, 1.3, 2.25, 0.08, door_u, fl + 1.12, 0.04)
        fblk(front, K("wood", (0.42, 0.22, 0.16)), 1.0, 2.05, 0.06, door_u, fl + 1.03, 0.08)
        for k in (-1, 1):
            fblk(front, K("wood", (0.32, 0.17, 0.12)), 0.32, 0.7, 0.03, door_u + k * 0.22, fl + 1.5, 0.11)
            fblk(front, K("wood", (0.32, 0.17, 0.12)), 0.32, 0.6, 0.03, door_u + k * 0.22, fl + 0.55, 0.11)
        m.ball(K("metal", GOLD), 0.04, front.at(door_u + 0.35, fl + 1.0, 0.13), u=6, v=4)
    if porch:  # a little roof over the door on two posts
        top = fl + 2.55
        for side in (-1, 1):
            m.rod(white, 0.06, front.at(door_u + side * 0.8, fl, 1.3), front.at(door_u + side * 0.8, top, 1.3), segs=6)
        blk(m, K("roof", s["roof"]), (2.1, 0.08, 1.6), front.at(door_u, top + 0.22, 0.75), pitch=14.0)
        blk(m, white, (2.0, 0.14, 0.12), front.at(door_u, top, 1.3))
        blk(m, K("wood", (0.5, 0.42, 0.33)), (1.9, 0.12, 1.4), front.at(door_u, fl - 0.06, 0.7))
    fh.gable_roof(m, s, hw, hd, fl + h, roof_h, dormers=0, timbered=False, front=gable_front, gable_window=roof_h > 1.8)
    return fl + h


def glass_window(face, s, u, y, ww, wh, shutters=False, arch=False, frame=None):
    """A sash window: frame, glass, glazing bars, a sill, shutters in the trim colour; `arch` = a round head."""
    frame = frame if frame is not None else K("wood", WHITE)
    fblk(face, frame, ww + 0.2, wh + 0.2, 0.1, u, y, 0.04)
    fblk(face, c(GLASS), ww, wh, 0.1, u, y, 0.055)
    fblk(face, frame, 0.05, wh, 0.1, u, y, 0.07)
    for k in (1, 2):
        fblk(face, frame, ww, 0.045, 0.1, u, y - wh / 2 + wh * k / 3.0, 0.07)
    fblk(face, frame, ww + 0.36, 0.08, 0.2, u, y - wh / 2 - 0.12, 0.09)
    if arch:  # a half-round fanlight over it, with a keystone
        r = ww / 2 + 0.1
        pts = [(u + r * math.cos(math.pi * k / 10), y + wh / 2 + 0.1 + r * math.sin(math.pi * k / 10)) for k in range(11)]
        for (a0, b0), (a1, b1) in zip(pts, pts[1:]):
            face.rod(frame, 0.07, (a0, b0), (a1, b1), n=0.08, segs=4)
        fblk(face, c(GLASS), ww - 0.04, r * 0.85, 0.08, u, y + wh / 2 + 0.1 + r * 0.42, 0.05)
        fblk(face, frame, 0.22, 0.3, 0.14, u, y + wh / 2 + 0.1 + r, 0.08)
    if shutters:
        for side in (-1, 1):
            at_u = u + side * (ww / 2 + 0.3)
            fblk(face, K("wood", s["trim"] if s["trim"] != WHITE else (0.2, 0.36, 0.4)), 0.42, wh + 0.06, 0.05, at_u, y, 0.05)
            for k in range(int(wh / 0.14)):  # louvres
                fblk(face, K("wood", tone(K("wood", s["trim"] if s["trim"] != WHITE else (0.2, 0.36, 0.4)), 0.78)[1]), 0.36, 0.035, 0.03, at_u, y - wh / 2 + 0.1 + k * 0.14, 0.085)


# --- styles 2 and 3: framed, then stone below and framed above ---

def framed(m, w, d, s, floors=2, roof_h=2.6, door_u=0.0):
    """The framed house of the fantasy towns (fantasy_house.build) on a deep foundation."""
    blk(m, K("stone", s["stone"]), (w + 0.3, -DEEP, d + 0.3), (0.0, DEEP / 2, 0.0))
    return fk.house(m, s, w, d, floors, roof_h, chimney=True, frame=True, door_x=door_u)


def stone_timber(m, w, d, s, door_u=0.0, roof_h=3.0, balcony=True, dormers=2, arch_door=True, gable_front=False, storey=None, ins=None):
    """Ground floor of dressed stone with quoins, a framed and jettied upper floor with a balcony, a red tile roof.
    `storey`: the ground floor's height; `ins` (inside()): the ground floor is walk-in."""
    fl, st = FLOOR[3], storey or STOREY[3]
    stone = K("stone", s["stone"])
    sw = scheme(3)
    sw["kinds"]["wall"] = "stone"
    sw["wall"] = s["stone"]
    blk(m, tone(stone, 0.9), (w + 0.4, fl - DEEP, d + 0.4), (0.0, (fl + DEEP) / 2, 0.0))
    blk(m, tone(stone, 0.78), (w + 0.5, 0.12, d + 0.5), (0.0, fl - 0.06, 0.0))
    hw, hd = w / 2, d / 2
    with fk.weathered(0.8):
        if ins is None:
            blk(m, stone, (w, st, d), (0.0, fl + st / 2, 0.0))
        for face in faces_of(m, hw, hd):
            fh.stone_face(face, sw, fl, st)
            spots = [-face.half + 1.4, face.half - 1.4] if face.half > 2.6 else [0.0]
            if face.half > 5.0 and face.name in ("front", "back"):
                spots.append(0.0)
            for u in spots:
                if face.name == "front" and abs(u - door_u) < 1.5:
                    continue
                glass_window(face, s, u, fl + 1.45, 0.9, 1.25, shutters=True, arch=True, frame=K("stone", tone(stone, 1.12)[1]))
                if ins is not None:
                    ins["windows"].append((face, u, fl + 1.45, 0.9, 1.25))
        if ins is not None:
            hollow(m, stone, w, st, d, fl, door_u, ins)
        y1 = fl + st
        jetty = 0.3
        blk(m, K("plaster", s["wall"]), (w + 0.2, st, d + 2 * jetty), (0.0, y1 + st / 2, 0.0))
        for face in faces_of(m, hw + 0.1, hd + jetty):
            fh.timber_face(face, s, y1, st)
            spots = [-face.half + 1.4, face.half - 1.4] if face.half > 2.6 else [0.0]
            if face.half > 5.0 and face.name in ("front", "back"):
                spots.append(0.0)
            for u in spots:
                glass_window(face, s, u, y1 + 1.5, 0.85, 1.15, shutters=True, frame=K("wood", s["timber"]))
            if face.name in ("front", "back"):
                for k in range(int(2 * face.half / 0.7) + 1):  # joist ends under the jetty
                    fblk(face, K("wood", s["timber"]), 0.14, 0.18, jetty + 0.16, -face.half + 0.15 + k * 0.7, y1 - 0.1, -jetty / 2)
        front = Face(m, "front", hd, hw)
        if arch_door and ins is not None:  # an open arched doorway: dressed jambs and the arch over it
            door_frame(front, K("stone", tone(stone, 1.15)[1]), door_u, fl, ins["door"][0], ins["door"][1], depth=0.18, n=0.08, bar=0.22)
            r = ins["door"][0] / 2 + 0.11
            for k in range(10):
                a0, a1 = math.pi * k / 10, math.pi * (k + 1) / 10
                front.rod(K("stone", tone(stone, 1.2)[1]), 0.12, (door_u + r * math.cos(a0), fl + ins["door"][1] + 0.22 + r * math.sin(a0) * 0.6), (door_u + r * math.cos(a1), fl + ins["door"][1] + 0.22 + r * math.sin(a1) * 0.6), n=0.2, segs=4)
        elif arch_door:
            fblk(front, K("stone", tone(stone, 1.15)[1]), 1.9, 2.75, 0.18, door_u, fl + 1.37, 0.08)
            fblk(front, K("wood", (0.35, 0.2, 0.13)), 1.3, 2.3, 0.1, door_u, fl + 1.15, 0.14)
            r = 0.75
            for k in range(10):
                a0, a1 = math.pi * k / 10, math.pi * (k + 1) / 10
                front.rod(K("stone", tone(stone, 1.2)[1]), 0.12, (door_u + r * math.cos(a0), fl + 2.3 + r * math.sin(a0) * 0.6), (door_u + r * math.cos(a1), fl + 2.3 + r * math.sin(a1) * 0.6), n=0.2, segs=4)
            for dy in (0.6, 1.7):
                fblk(front, K("metal", IRON), 1.1, 0.07, 0.03, door_u, fl + dy, 0.2)
        if balcony:  # a balcony along the upper floor's front on brackets
            bf = hd + jetty
            blk(m, K("wood", s["timber"]), (w * 0.7, 0.14, 1.1), front.at(0.0, y1 - 0.05, jetty + 0.55))
            for k in range(int(w * 0.7 / 0.18) + 1):
                x = -w * 0.35 + k * 0.18
                m.rod(K("wood", s["timber"]), 0.025, (x, y1, bf + 1.05), (x, y1 + 0.95, bf + 1.05), segs=4)
            blk(m, K("wood", s["timber"]), (w * 0.7 + 0.1, 0.08, 0.1), (0.0, y1 + 0.98, bf + 1.05))
            for side in (-1, 1):
                blk(m, K("wood", s["timber"]), (0.1, 0.08, 1.1), (side * w * 0.35, y1 + 0.98, bf + 0.55))
                m.rod(K("wood", s["timber"]), 0.06, (side * w * 0.3, y1 - 0.8, bf), (side * w * 0.3, y1 - 0.08, bf + 1.0), segs=4)
            fblk(Face(m, "front", hd + jetty, hw), K("wood", (0.3, 0.18, 0.12)), 1.0, 2.1, 0.08, 0.0, y1 + 1.05, 0.03)
    fh.gable_roof(m, s, hw + 0.1, hd + jetty, y1 + st, roof_h, dormers=dormers, timbered=False, front=gable_front)
    if ins is None:  # (a walk-in ground floor keeps its room clear)
        fh.chimney_stack(m, s, hw - 1.0, -hd / 2, y1 + st + roof_h * 0.62 + 1.0)
    return y1 + st


# --- style 4: the colonial stone house ---

def hip_roof(m, s, hw, hd, wall_h, roof_h, eave=0.55):
    """Four tiled slopes meeting in a ridge (a pyramid when square), with tile courses and a cornice under the eaves."""
    roof = K("roof", s["roof"])
    ex, ef = hw + eave, hd + eave
    low, top = wall_h + 0.05, wall_h + roof_h
    ridge = max(ex - ef, 0.0)
    if ridge < 0.05:
        pts = [(-ex, low, -ef), (ex, low, -ef), (ex, low, ef), (-ex, low, ef), (0.0, top, 0.0),
            (-ex, low - 0.18, -ef), (ex, low - 0.18, -ef), (ex, low - 0.18, ef), (-ex, low - 0.18, ef)]
        poly(m, roof, pts, [[0, 3, 4], [1, 4, 2], [0, 4, 1], [3, 2, 4], [5, 6, 7, 8], [0, 1, 6, 5], [1, 2, 7, 6], [2, 3, 8, 7], [3, 0, 5, 8]])
    else:
        pts = [(-ex, low, -ef), (ex, low, -ef), (ex, low, ef), (-ex, low, ef), (-ridge, top, 0.0), (ridge, top, 0.0),
            (-ex, low - 0.18, -ef), (ex, low - 0.18, -ef), (ex, low - 0.18, ef), (-ex, low - 0.18, ef)]
        poly(m, roof, pts, [[0, 3, 4], [1, 5, 2], [0, 4, 5, 1], [3, 2, 5, 4], [6, 7, 8, 9], [0, 1, 7, 6], [1, 2, 8, 7], [2, 3, 9, 8], [3, 0, 6, 9]])
    for k in range(1, 6):  # tile courses: rings that step out of the slopes
        t = k / 6.0
        y = low + roof_h * t
        ax, af = ex - (ex - ridge) * t, ef - ef * t
        if af < 0.15:
            continue
        for way in (-1, 1):
            blk(m, tone(roof, 0.78), (2 * ax, 0.07, 0.12), (0.0, y + 0.02, way * af))
            blk(m, tone(roof, 0.78), (0.12, 0.07, 2 * af), (way * ax, y + 0.02, 0.0))
    for way in (-1, 1):  # hips
        for side in (-1, 1):
            m.rod(tone(roof, 0.7), 0.07, (side * ex, low + 0.04, way * ef), (side * ridge, top + 0.04, 0.0), segs=5)
    if ridge > 0.05:
        m.rod(tone(roof, 0.7), 0.08, (-ridge, top + 0.04, 0.0), (ridge, top + 0.04, 0.0), segs=5)
    cornice(m, s, hw, hd, wall_h)


def cornice(m, s, hw, hd, wall_h):
    stone = K("stone", s["stone"])
    for k, (out, hgt) in enumerate(((0.08, 0.22), (0.2, 0.12), (0.32, 0.1))):
        y = wall_h - 0.3 + sum(h for _o, h in ((0.08, 0.22), (0.2, 0.12), (0.32, 0.1))[:k]) + hgt / 2
        blk(m, tone(stone, 1.05 - 0.06 * k), (2 * (hw + out), hgt, 2 * (hd + out)), (0.0, y, 0.0))


def quoins(face, s, y0, height):
    stone = K("stone", s["stone"])
    for side in (-1, 1):
        for q in range(int(height / 0.42)):
            long = 0.62 if q % 2 == 0 else 0.4
            fblk(face, tone(stone, 1.0 + 0.08 * (q % 3)), long, 0.36, 0.08, side * (face.half - long / 2 + 0.04), y0 + 0.21 + q * 0.42, 0.03)


def colonial(m, w, d, s, floors=2, roof_h=3.0, door_u=0.0, arcade=False, iron_balconies=True, spots=None, storey=None, ins=None, blind=()):
    """Whitewashed stone, tall storeys, arched ground-floor windows, a string course, cornice and a hip roof.
    `arcade`: a row of arches before the front carrying a terrace with a balustrade. Returns the wall height.
    `storey`: each storey's height; `ins` (inside()): walk-in, ONE room the full height of the walls."""
    fl, st = FLOOR[4], storey or STOREY[4]
    stone = K("stone", s["stone"])
    plaster = K("plaster", s["wall"])
    hw, hd = w / 2, d / 2
    blk(m, stone, (w + 0.5, fl - DEEP, d + 0.5), (0.0, (fl + DEEP) / 2, 0.0))
    blk(m, tone(stone, 0.85), (w + 0.62, 0.14, d + 0.62), (0.0, fl - 0.07, 0.0))
    wall_h = fl + st * floors
    with fk.weathered(0.5):
        if ins is None:
            blk(m, plaster, (w, st * floors, d), (0.0, fl + st * floors / 2, 0.0))
        for face in faces_of(m, hw, hd):
            quoins(face, s, fl, st * floors)
            us = spots if spots is not None and face.name in ("front", "back") else None
            if us is None:
                n = max(1, int((2 * face.half - 1.0) / 2.3))
                us = [-face.half + 0.5 + (2 * face.half - 1.0) * (k + 0.5) / n for k in range(n)]
            if face.name in blind:  # a wall kept for pictures (the gallery is lit from above)
                continue
            for i in range(floors):
                y = fl + st * i
                if i > 0:  # string course between the storeys
                    fblk(face, tone(stone, 1.05), 2 * face.half + 0.12, 0.16, 0.1, 0.0, y, 0.04)
                for u in us:
                    if i == 0 and face.name == "front" and abs(u - door_u) < 1.3:
                        continue
                    glass_window(face, s, u, y + 1.6, 1.0, 1.75 if i else 1.55, shutters=True, arch=i == 0, frame=K("stone", tone(stone, 1.12)[1]))
                    if ins is not None:
                        ins["windows"].append((face, u, y + 1.6, 1.0, 1.75 if i else 1.55))
                    if i > 0 and iron_balconies and face.name == "front":  # a little iron balcony
                        blk(m, stone, (1.5, 0.1, 0.5), face.at(u, y + 0.62, 0.25) if face.name in ("front", "back") else face.at(u, y + 0.62, 0.25))
                        for k in range(8):
                            uu = u - 0.7 + k * 0.2
                            face.rod(K("metal", IRON), 0.015, (uu, y + 0.67), (uu, y + 1.55), n=0.48, segs=3)
                        fblk(face, K("metal", IRON), 1.5, 0.04, 0.04, u, y + 1.55, 0.48)
        front = Face(m, "front", hd, hw)
        # the door: panelled double leaves under a fanlight, pilasters and a pediment-like cap
        if ins is not None:
            hollow(m, plaster, w, st * floors, d, fl, door_u, ins)
            door_frame(front, tone(stone, 1.15), door_u, fl, ins["door"][0], ins["door"][1], depth=0.16, n=0.06, bar=0.25)
        else:
            fblk(front, tone(stone, 1.15), 2.3, 3.3, 0.16, door_u, fl + 1.65, 0.06)
            fblk(front, K("wood", (0.22, 0.32, 0.26)), 1.5, 2.5, 0.08, door_u, fl + 1.25, 0.12)
            m.ball(K("metal", GOLD), 0.05, front.at(door_u + 0.15, fl + 1.2, 0.2), u=6, v=4)
        for side in (-1, 1):
            if ins is None:
                for dy in (0.7, 1.75):
                    fblk(front, K("wood", (0.18, 0.27, 0.22)), 0.55, 0.75, 0.04, door_u + side * 0.37, fl + dy, 0.17)
            fblk(front, tone(stone, 1.2), 0.3, 3.4, 0.24, door_u + side * 1.2, fl + 1.7, 0.1)
        fblk(front, c(GLASS), 1.3, 0.55, 0.06, door_u, fl + 2.85, 0.1)
        fblk(front, tone(stone, 1.2), 2.9, 0.26, 0.36, door_u, fl + 3.45, 0.14)
        cornice(m, s, hw, hd, wall_h)
    if arcade:
        arcade_front(m, s, w, hd, fl, st)
    hip_roof(m, s, hw, hd, wall_h, roof_h)
    return wall_h


def arcade_front(m, s, w, hd, fl, st):
    """A row of round arches before the front (a loggia) with a terrace and balustrade on top."""
    stone = K("stone", s["stone"])
    plaster = K("plaster", s["wall"])
    depth = 2.4
    n = max(3, int(w / 2.6))
    span = w / n
    f = hd + depth
    blk(m, tone(stone, 0.95), (w + 0.4, fl - DEEP, depth), (0.0, (fl + DEEP) / 2, hd + depth / 2))
    for k in range(n + 1):  # piers
        x = -w / 2 + k * span
        blk(m, plaster, (0.5, st - 0.3, 0.5), (x, fl + (st - 0.3) / 2, f - 0.25))
        blk(m, tone(stone, 1.1), (0.62, 0.2, 0.62), (x, fl + 0.1, f - 0.25))
        blk(m, tone(stone, 1.1), (0.62, 0.16, 0.62), (x, fl + st - 0.38, f - 0.25))
    for k in range(n):  # arches between them: a half ring of stones
        x0 = -w / 2 + (k + 0.5) * span
        r = span / 2 - 0.25
        for j in range(8):
            a0, a1 = math.pi * j / 8, math.pi * (j + 1) / 8
            m.rod(tone(stone, 1.12), 0.13, (x0 + r * math.cos(a0), fl + st - 0.3 - r * 0.15 + r * math.sin(a0) * 0.55, f - 0.25),
                (x0 + r * math.cos(a1), fl + st - 0.3 - r * 0.15 + r * math.sin(a1) * 0.55, f - 0.25), segs=4)
    blk(m, plaster, (w + 0.2, 0.7, 0.5), (0.0, fl + st + 0.05, f - 0.25))  # spandrel band
    blk(m, tone(stone, 1.05), (w + 0.4, 0.22, depth + 0.3), (0.0, fl + st + 0.45, hd + depth / 2))  # the terrace floor
    for k in range(int(w / 0.3) + 1):  # balusters
        x = -w / 2 + k * (w / int(w / 0.3))
        m.lathe(tone(stone, 1.15), [(0.0, 0.0), (0.07, 0.0), (0.05, 0.1), (0.09, 0.35), (0.05, 0.6), (0.07, 0.68), (0.0, 0.7)], (x, fl + st + 0.56, f - 0.1), segs=6)
    blk(m, tone(stone, 1.1), (w + 0.3, 0.12, 0.3), (0.0, fl + st + 1.32, f - 0.1))


def cupola(m, s, x, y, f, size=2.4, flag=True):
    """A small square lantern tower with arched openings and a tiled pyramid roof (the landmark of a grand building)."""
    stone = K("stone", s["stone"])
    plaster = K("plaster", s["wall"])
    h = size * 1.1
    blk(m, tone(stone, 0.95), (size + 0.3, 0.3, size + 0.3), (x, y + 0.15, f))
    for sx in (-1, 1):
        for sf in (-1, 1):
            blk(m, plaster, (0.35, h, 0.35), (x + sx * (size / 2 - 0.17), y + 0.3 + h / 2, f + sf * (size / 2 - 0.17)))
    blk(m, c((0.3, 0.3, 0.32)), (size - 0.9, 0.12, size - 0.9), (x, y + 0.32 + h - 0.3, f))
    m.lathe(K("metal", P_BRONZE), [(0.0, 0.0), (0.55, 0.0), (0.42, 0.25), (0.3, 0.8), (0.18, 0.95), (0.0, 1.0)], (x, y + 0.3 + h * 0.3, f), segs=14)
    for sx in (-1, 1):  # arches over the openings
        for k in range(6):
            a0, a1 = math.pi * k / 6, math.pi * (k + 1) / 6
            r = size / 2 - 0.35
            for pts in (((x + r * math.cos(a0), f + sx * (size / 2 - 0.17)), (x + r * math.cos(a1), f + sx * (size / 2 - 0.17))), ((x + sx * (size / 2 - 0.17), f + r * math.cos(a0)), (x + sx * (size / 2 - 0.17), f + r * math.cos(a1)))):
                m.rod(plaster, 0.1, (pts[0][0], y + 0.3 + h - 0.45 + r * 0.45 * math.sin(a0), pts[0][1]), (pts[1][0], y + 0.3 + h - 0.45 + r * 0.45 * math.sin(a1), pts[1][1]), segs=4)
    blk(m, tone(stone, 1.05), (size + 0.25, 0.25, size + 0.25), (x, y + 0.3 + h + 0.12, f))
    top = y + 0.3 + h + 0.25
    rh = size * 0.9
    e = size / 2 + 0.2
    poly(m, K("roof", s["roof"]), [(x - e, top, f - e), (x + e, top, f - e), (x + e, top, f + e), (x - e, top, f + e), (x, top + rh, f)],
        [[0, 1, 2, 3], [0, 4, 1], [1, 4, 2], [2, 4, 3], [3, 4, 0]])
    m.ball(K("metal", GOLD), 0.14, (x, top + rh + 0.12, f), u=8, v=6)
    if flag:
        m.rod(K("metal", IRON), 0.035, (x, top + rh, f), (x, top + rh + 2.4, f), segs=5)
        blk(m, K("cloth", (0.14, 0.32, 0.55)), (1.2, 0.75, 0.02), (x + 0.62, top + rh + 2.0, f))
        blk(m, K("cloth", (0.95, 0.9, 0.75)), (0.5, 0.3, 0.025), (x + 0.62, top + rh + 2.0, f))


# --- things round a building ---

def sign(m, at, kind, board=(0.95, 0.6), out=1.0, face_yaw=0.0, wood=(0.3, 0.42, 0.45)):
    """A hanging sign: an iron bracket out from the wall at `at` (x, y, f), a board, the trade's emblem on both sides.
    face_yaw 0 = the bracket sticks out to the right (+x) and the board faces the front."""
    x, y, f = at
    m.rod(K("metal", IRON), 0.03, (x, y, f), (x + out, y, f), segs=5)
    m.rod(K("metal", IRON), 0.02, (x, y - 0.4, f), (x + out * 0.7, y, f), segs=4)
    for dx in (out * 0.25, out * 0.85):
        m.rod(K("metal", IRON), 0.008, (x + dx, y, f), (x + dx, y - 0.12, f), segs=3)
    bx = x + out * 0.55
    by = y - 0.12 - board[1] / 2
    blk(m, K("wood", wood), (board[0], board[1], 0.06), (bx, by, f))
    blk(m, K("wood", tone(K("wood", wood), 0.7)[1]), (board[0] + 0.08, 0.06, 0.08), (bx, by + board[1] / 2, f))
    for side in (-1, 1):
        emblem(m, kind, (bx, by, f + side * 0.04), min(board) * 0.8, side)


def emblem(m, kind, at, size, way=1):
    """The trade's picture in gold, flat on a sign board (facing +f when way = 1)."""
    x, y, f = at
    g = K("paint", GOLD)
    s = size
    t = 0.012 * way
    if kind == "anchor":
        m.rod(g, s * 0.04, (x, y + s * 0.32, f + t), (x, y - s * 0.3, f + t), segs=5)
        m.rod(g, s * 0.035, (x - s * 0.18, y + s * 0.24, f + t), (x + s * 0.18, y + s * 0.24, f + t), segs=5)
        for side in (-1, 1):
            m.rod(g, s * 0.035, (x, y - s * 0.3, f + t), (x + side * s * 0.26, y - s * 0.1, f + t), segs=5)
        m.ball(g, (s * 0.06, s * 0.06, s * 0.02), (x, y + s * 0.38, f + t), u=8, v=4)
    elif kind == "tankard":
        blk(m, g, (s * 0.34, s * 0.48, 0.02), (x - s * 0.04, y - s * 0.02, f + t))
        blk(m, K("paint", (0.96, 0.94, 0.88)), (s * 0.4, s * 0.1, 0.022), (x - s * 0.04, y + s * 0.24, f + t))
        for k in range(6):
            a0, a1 = -math.pi / 2 + math.pi * k / 6, -math.pi / 2 + math.pi * (k + 1) / 6
            m.rod(g, s * 0.035, (x + s * 0.13 + s * 0.14 * math.cos(a0), y + s * 0.14 * math.sin(a0), f + t), (x + s * 0.13 + s * 0.14 * math.cos(a1), y + s * 0.14 * math.sin(a1), f + t), segs=4)
    elif kind == "hammer":
        m.rod(K("paint", (0.6, 0.45, 0.3)), s * 0.035, (x - s * 0.25, y - s * 0.3, f + t), (x + s * 0.12, y + s * 0.18, f + t), segs=5)
        blk(m, g, (s * 0.36, s * 0.13, 0.02), (x + s * 0.12, y + s * 0.2, f + t), roll=-38.0)
        blk(m, g, (s * 0.5, s * 0.1, 0.02), (x, y - s * 0.38, f + t))
    elif kind == "barrel":
        m.ball(g, (s * 0.24, s * 0.3, 0.012), (x, y, f + t), u=12, v=6)
        for dy in (-0.16, 0.16):
            blk(m, K("paint", (0.3, 0.2, 0.12)), (s * 0.44, s * 0.04, 0.022), (x, y + s * dy, f + t))
    elif kind == "cup":
        m.ball(g, (s * 0.2, s * 0.17, 0.012), (x, y + s * 0.12, f + t), u=12, v=6)
        blk(m, g, (s * 0.06, s * 0.2, 0.02), (x, y - s * 0.1, f + t))
        blk(m, g, (s * 0.3, s * 0.07, 0.02), (x, y - s * 0.24, f + t))
        for side in (-1, 1):
            m.ball(g, (s * 0.07, s * 0.09, 0.01), (x + side * s * 0.21, y + s * 0.16, f + t), u=8, v=4)
    elif kind == "frame":
        for dx, dy, sx, sy in ((0, 0.26, 0.6, 0.06), (0, -0.26, 0.6, 0.06), (0.27, 0, 0.06, 0.5), (-0.27, 0, 0.06, 0.5)):
            blk(m, g, (s * sx, s * sy, 0.02), (x + s * dx, y + s * dy, f + t))
        blk(m, K("paint", (0.35, 0.55, 0.75)), (s * 0.48, s * 0.22, 0.016), (x, y + s * 0.08, f + t))
        blk(m, K("paint", (0.35, 0.6, 0.3)), (s * 0.48, s * 0.2, 0.016), (x, y - s * 0.12, f + t))
    elif kind == "leaf":
        m.ball(K("paint", (0.4, 0.7, 0.3)), (s * 0.16, s * 0.3, 0.012), (x - s * 0.1, y + s * 0.02, f + t), u=10, v=6)
        m.ball(K("paint", (0.4, 0.7, 0.3)), (s * 0.16, s * 0.28, 0.012), (x + s * 0.12, y + s * 0.04, f + t), u=10, v=6)
        m.rod(K("paint", (0.3, 0.5, 0.2)), s * 0.025, (x, y - s * 0.34, f + t), (x, y + s * 0.1, f + t), segs=4)
    elif kind == "ship":
        plate(m, g, [(x - s * 0.34, y - s * 0.12), (x + s * 0.34, y - s * 0.12), (x + s * 0.24, y - s * 0.3), (x - s * 0.26, y - s * 0.3)], f + t)
        m.rod(g, s * 0.025, (x, y - s * 0.12, f + t), (x, y + s * 0.36, f + t), segs=4)
        plate(m, K("paint", (0.96, 0.94, 0.88)), [(x + s * 0.02, y + s * 0.32), (x + s * 0.26, y - s * 0.06), (x + s * 0.02, y - s * 0.06)], f + t)


def lantern(m, at, hang=True):
    x, y, f = at
    if hang:
        m.rod(K("metal", IRON), 0.012, (x, y + 0.42, f), (x, y + 0.26, f), segs=4)
    m.lathe(K("metal", IRON), [(0.0, 0.0), (0.1, 0.0), (0.11, 0.04), (0.0, 0.05)], (x, y - 0.02, f), segs=8)
    m.lathe(fk.GLOW, [(0.0, 0.0), (0.08, 0.0), (0.085, 0.2), (0.0, 0.2)], (x, y + 0.02, f), segs=8)
    m.lathe(K("metal", IRON), [(0.0, 0.0), (0.12, 0.0), (0.06, 0.1), (0.0, 0.14)], (x, y + 0.22, f), segs=8)


def crate(m, at, s=0.6, yaw=0.0, wood=(0.55, 0.42, 0.28)):
    x, y, f = at
    blk(m, K("wood", wood), (s, s, s), (x, y + s / 2, f), yaw=yaw)
    for dy in (0.08, s - 0.08):
        blk(m, K("wood", tone(K("wood", wood), 0.7)[1]), (s + 0.03, 0.07, s + 0.03), (x, y + dy, f), yaw=yaw)


def barrel(m, at, h=0.85, wood=(0.45, 0.3, 0.18)):
    x, y, f = at
    m.lathe(K("wood", wood), [(0.0, 0.0), (0.27, 0.0), (0.33, h / 2), (0.27, h), (0.0, h)], (x, y, f), segs=12)
    for dy in (0.12, h - 0.12):
        m.lathe(K("metal", IRON), [(0.0, -0.02), (0.29, -0.02), (0.29, 0.02), (0.0, 0.02)], (x, y + dy, f), segs=12)


def rope_coil(m, at, r=0.3):
    x, y, f = at
    for k in range(4):
        m.lathe(K("cloth", ROPE), [(r - k * 0.05, 0.0), (r - k * 0.05 + 0.04, 0.02), (r - k * 0.05, 0.04), (r - k * 0.05 - 0.04, 0.02)], (x, y + k * 0.035, f), segs=12)


def bench(m, at, length=1.8, yaw=0.0, wood=(0.45, 0.33, 0.22)):
    x, y, f = at
    blk(m, K("wood", wood), (length, 0.07, 0.35), (x, y + 0.45, f), yaw=yaw)
    for side in (-1, 1):
        dx = side * (length / 2 - 0.15) * math.cos(math.radians(yaw))
        df = -side * (length / 2 - 0.15) * math.sin(math.radians(yaw))
        blk(m, K("wood", tone(K("wood", wood), 0.8)[1]), (0.08, 0.45, 0.3), (x + dx, y + 0.22, f + df), yaw=yaw)


def table(m, at, r=0.5, wood=(0.48, 0.34, 0.22)):
    x, y, f = at
    m.lathe(K("wood", wood), [(0.0, 0.0), (r, 0.0), (r, 0.06), (0.0, 0.06)], (x, y + 0.74, f), segs=12)
    m.rod(K("wood", tone(K("wood", wood), 0.8)[1]), 0.05, (x, y, f), (x, y + 0.74, f), segs=6)
    m.lathe(K("wood", tone(K("wood", wood), 0.8)[1]), [(0.0, 0.0), (0.3, 0.0), (0.0, 0.05)], (x, y, f), segs=8)


def weeds(m, rnd, x0, x1, f0, f1, count, y=0.0):
    """Tufts of rough grass and dock leaves: a few thin blades fanned out from one spot."""
    for _k in range(count):
        x, f = rnd.uniform(x0, x1), rnd.uniform(f0, f1)
        col = (0.26 + 0.1 * rnd.random(), 0.36 + 0.1 * rnd.random(), 0.15)
        h = 0.35 + 0.35 * rnd.random()
        for j in range(4):
            blk(m, K("leaf", col), (0.09, h, 0.015), (x, y + h * 0.45, f), yaw=j * 47.0 + rnd.uniform(0, 30), pitch=rnd.uniform(-25, 25))


def plant(m, at, r=0.22, col=(0.24, 0.4, 0.17)):
    """A round leafy plant (smooth, not faceted)."""
    m.ball(K("leaf", col), (r, r * 0.85, r), at, u=8, v=5)


def ruin(m, w, d, seed=1, stone=False):
    """A building waiting to be repaired (director: the rest of the town "you help them grow and repair"): a footing
    of old stones, two broken walls of grey boards, a roof fallen in at one end, loose planks, a smashed crate, weeds."""
    rnd = random.Random(seed)
    base = K("stone", (0.5, 0.48, 0.45))
    blk(m, base, (w + 0.3, 0.35 - DEEP, d + 0.3), (0.0, (0.35 + DEEP) / 2, 0.0))
    for face in faces_of(m, w / 2 + 0.15, d / 2 + 0.15):  # tumbled stones round the footing
        for k in range(int(face.half * 1.5)):
            fk.blob(m, tone(base, 0.75 + 0.4 * rnd.random()), (0.25, 0.18, 0.22), face.at(-face.half + 0.4 + k * 1.3 * rnd.uniform(0.8, 1.2), 0.3, 0.2 + 0.3 * rnd.random()), seed=rnd.randint(0, 99), rough=0.3, cuts=1)
    wood = K("wood", (0.5, 0.48, 0.44))
    for face in faces_of(m, w / 2, d / 2)[1:3]:  # back and right wall stand part way, broken off raggedly
        u = -face.half
        while u < face.half - 0.1:
            hgt = max(0.3, 2.2 * (0.6 + 0.4 * math.sin(u * 1.3 + seed)) * rnd.uniform(0.5, 1.0))
            fblk(face, tone(wood, 0.65 + 0.35 * rnd.random()), 0.22, hgt, 0.05, u + 0.11, 0.35 + hgt / 2, 0.0, pitch=rnd.uniform(-6, 6))
            u += 0.25
        for x in (-face.half, face.half):
            m.rod(tone(wood, 0.6), 0.08, face.at(x, 0.35, 0.0), face.at(x, 0.35 + rnd.uniform(1.2, 2.6), 0.0), segs=6)
    # the roof's fallen half: thatch and rafters lying slantwise into the room
    blk(m, K("thatch", (0.45, 0.4, 0.3)), (w * 0.8, 0.22, d * 0.7), (-w * 0.1, 0.9, -d * 0.05), pitch=22.0, roll=-8.0)
    for k in range(4):
        m.rod(tone(wood, 0.55), 0.06, (-w / 2 + 0.5 + k * w / 4.5, 0.35, -d / 2 + 0.3), (-w / 2 + 0.9 + k * w / 4.5, 1.7, d * 0.2), segs=5)
    for _k in range(9):  # loose planks on the ground about the plot
        x, f = rnd.uniform(-w / 2 - 1.0, w / 2 + 1.0), rnd.uniform(d / 2, d / 2 + 2.5)
        blk(m, tone(wood, 0.6 + 0.4 * rnd.random()), (rnd.uniform(1.2, 2.4), 0.05, 0.2), (x, 0.05 + 0.05 * rnd.random(), f), yaw=rnd.uniform(0, 180), roll=rnd.uniform(-5, 5))
    crate(m, (w / 2 + 0.6, 0.0, d / 2 + 0.9), 0.55, yaw=20.0, wood=(0.45, 0.4, 0.33))
    blk(m, tone(wood, 0.7), (0.6, 0.06, 0.55), (w / 2 + 1.3, 0.05, d / 2 + 0.3), yaw=40.0, roll=12.0)
    weeds(m, rnd, -w / 2, w / 2 + 1.5, -d / 2, d / 2 + 2.5, int(w * d / 3) + 6, y=0.2)
