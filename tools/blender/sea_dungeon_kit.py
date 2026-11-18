# Purpose: developer-time tool (sea step 9a): THE DUNGEON ROOM KIT, region 1's look ("sunlit shallows": a drowned
# sandstone sea-temple, teal weed at the foot of the walls, coral and shells, gilt trim). Tile T = 3 m, walls H = 4.5 m;
# a dungeon is drawn from these by game/sea_dungeon.gd (MultiMeshes for floor / wall / ceiling, nodes for the rest):
#   dk_floor (one tile of four flagstones), dk_wall (a solid wall cell, coursed on all four faces), dk_ceiling,
#   dk_door (portcullis gate, node "Leaf" slides up), dk_door_lock (banded door + node "Lock" padlock, "Leaf" swings),
#   dk_plate (pressure plate, node "Plate" sinks), dk_lever (node "Handle" pivots at its foot), dk_block (push block),
#   dk_torch (wall sconce, marker "Flame"), dk_key, dk_chest (node "Lid"), dk_gate (entrance / exit arch, marker "Door").
# Pieces face -z (kit "f" forward is -z in Godot); a cell piece is centred on its cell, floor top at y 0.
# -> assets/models/sea/dungeon/<name>.gltf.  Run: python3 tools/blender/sea_dungeon_kit.py  (ONLY=a,b to build some)
# Dependencies: bpy, tools/blender/kit.py, fantasy_kit.py, sea_town_parts.py (blk). No game code.
import math
import os
import random
import sys

sys.path.insert(0, os.path.dirname(__file__))
import bpy  # noqa: F401
import kit
import fantasy_kit as fk
from fantasy_kit import K
from sea_town_parts import blk

OUT = os.path.join(os.path.dirname(__file__), "..", "..", "assets", "models", "sea", "dungeon")
T = 3.0
H = 4.5
SAND = (0.8, 0.7, 0.52)
SAND_DARK = (0.62, 0.52, 0.38)
GROUT = (0.36, 0.3, 0.24)
WEED = (0.22, 0.45, 0.38)
CORAL = (0.86, 0.45, 0.42)
GILT = (0.86, 0.68, 0.3)
IRON = (0.24, 0.24, 0.26)
WOOD = (0.42, 0.28, 0.16)


def stone(rgb, k=1.0):
    return K("sandstone", tuple(min(v * k, 1.0) for v in rgb))


def shell(m, at, size, face=-1, node="Body"):
    """A scallop shell standing up on a face (face -1: its front toward -f): ribs fanning out over a pale back."""
    x0, y0, f0 = at
    m.ball(K("sandstone", (0.95, 0.72, 0.6)), (size * 0.6, size * 0.5, size * 0.08), (x0, y0 + size * 0.12, f0), node=node)
    for k in range(9):
        a = -64 + k * 16
        r = math.radians(a)
        blk(m, K("sandstone", CORAL), (size * 0.09, size * 0.6, size * 0.1), (x0 + math.sin(r) * size * 0.28, y0 + math.cos(r) * size * 0.28, f0 + face * size * 0.05), roll=-a, node=node)
    blk(m, K("sandstone", CORAL), (size * 0.4, size * 0.16, size * 0.12), (x0, y0 - size * 0.1, f0 + face * size * 0.05), node=node)


def floor(m):
    rnd = random.Random(1)
    blk(m, K("stone", GROUT), (T, 0.2, T), (0.0, -0.12, 0.0))
    for ix in range(2):
        for iz in range(2):
            k = rnd.uniform(0.9, 1.06)
            blk(m, stone(SAND, k * 0.92), (T / 2 - 0.03, 0.12, T / 2 - 0.03), ((ix - 0.5) * T / 2, -0.06 + rnd.uniform(-0.01, 0.01), (iz - 0.5) * T / 2), bevel=0.02)


def wall(m):
    rnd = random.Random(2)
    blk(m, K("stone", GROUT), (T - 0.08, H, T - 0.08), (0.0, H / 2, 0.0))
    courses = 3
    ch = (H - 0.5) / courses
    for side in range(4):
        yaw = side * 90.0
        for c in range(courses):
            n = 2 if c % 2 == 0 else 3
            w = T / n
            for i in range(n):
                u = -T / 2 + w * (i + 0.5)
                y = 0.35 + ch * (c + 0.5)
                rad = math.radians(yaw)
                out = T / 2 - 0.02
                x, f = u * math.cos(rad) + out * math.sin(rad), -u * math.sin(rad) + out * math.cos(rad)
                blk(m, stone(SAND, rnd.uniform(0.86, 1.05)), (w - 0.06, ch - 0.06, 0.1), (x, y, f), yaw=yaw)
        rad = math.radians(yaw)
        out = T / 2 + 0.03
        blk(m, stone(SAND_DARK), (T + 0.06, 0.35, 0.16), (out * math.sin(rad), 0.175, out * math.cos(rad)), yaw=yaw)  # plinth
        blk(m, stone(SAND, 1.05), (T + 0.06, 0.18, 0.18), (out * math.sin(rad), H - 0.09, out * math.cos(rad)), yaw=yaw)  # cornice


def ceiling(m):
    blk(m, stone(SAND_DARK, 0.8), (T, 0.4, T), (0.0, H + 0.2, 0.0))
    blk(m, stone(SAND_DARK, 0.9), (0.4, 0.3, T), (0.0, H - 0.15, 0.0), bevel=0.02)  # a rib along the cell


def jambs(m):
    for side in (-1, 1):
        blk(m, K("stone", GROUT), (0.5, H, T - 0.08), (side * (T / 2 - 0.25), H / 2, 0.0))
        for c in range(3):
            blk(m, stone(SAND, 0.95 + 0.04 * c), (0.56, 1.3, T - 0.02), (side * (T / 2 - 0.25), 0.4 + 1.38 * c + 0.65, 0.0), bevel=0.02)
    blk(m, stone(SAND, 1.04), (T - 0.08, H - 3.3, T - 0.08), (0.0, 3.3 + (H - 3.3) / 2, 0.0), bevel=0.02)  # the lintel block
    blk(m, K("metal", GILT), (2.1, 0.12, 0.08), (0.0, 3.36, -(T / 2 - 0.02)), bevel=0.01)  # gilt band over the way through
    blk(m, K("metal", GILT), (2.1, 0.12, 0.08), (0.0, 3.36, T / 2 - 0.02), bevel=0.01)
    for f, way in ((-(T / 2 - 0.02), -1), (T / 2 - 0.02, 1)):  # a shell carved over each face
        shell(m, (0.0, 3.85, f), 0.6, face=way)


def door(m):
    jambs(m)
    m.node("Leaf", (0.0, 0.0, 0.0))
    for i in range(9):  # the portcullis: iron bars and cross bands
        x = -0.96 + i * 0.24
        m.box(K("metal", IRON), (0.06, 3.3, 0.06), (x, 1.65, 0.0), node="Leaf", bevel=0.0)
        m.box(K("metal", IRON), (0.09, 0.14, 0.09), (x, 0.07, 0.0), node="Leaf", bevel=0.0)  # spikes at the foot
    for y in (0.6, 1.6, 2.6):
        m.box(K("metal", IRON), (2.0, 0.08, 0.08), (0.0, y, 0.0), node="Leaf", bevel=0.0)


def door_lock(m):
    jambs(m)
    m.node("Leaf", (-1.0, 0.0, 0.0))  # hinged at its left edge
    for i in range(6):
        m.box(K("wood", (0.42 + 0.03 * (i % 2), 0.28, 0.16)), (0.33, 3.25, 0.12), (-0.83 + i * 0.335, 1.63, 0.0), node="Leaf", bevel=0.01)
    for y in (0.5, 1.6, 2.7):
        m.box(K("metal", IRON), (2.04, 0.12, 0.15), (0.0, y, 0.0), node="Leaf")
        for x in (-0.8, -0.2, 0.4):
            m.ball(K("metal", IRON), (0.035, 0.035, 0.035), (x, y, -0.08), node="Leaf")
    m.node("Lock", (0.0, 1.6, -0.12), parent="Leaf")
    m.box(K("metal", GILT), (0.36, 0.42, 0.14), (0.0, 1.5, -0.2), node="Lock", bevel=0.03)
    m.lathe(K("metal", IRON), [(0.0, 0.0), (0.04, 0.0), (0.04, 0.02), (0.0, 0.02)], (0.0, 1.48, -0.28), node="Lock", segs=10, axis="y")
    for side in (-1, 1):  # chains from the lock to the jambs
        for k in range(6):
            x = side * (0.25 + k * 0.13)
            m.ball(K("metal", IRON), (0.05, 0.03, 0.02), (x, 1.62, -0.22), node="Lock")


def plate(m):
    blk(m, K("stone", GROUT), (2.2, 0.08, 2.2), (0.0, 0.02, 0.0))
    for s in range(4):
        rad = math.radians(s * 90)
        blk(m, stone(SAND_DARK), (2.2, 0.06, 0.12), (math.sin(rad) * 1.04, 0.05, math.cos(rad) * 1.04), yaw=s * 90.0)
    m.node("Plate", (0.0, 0.0, 0.0))
    m.box(stone(SAND, 1.06), (1.9, 0.1, 1.9), (0.0, 0.1, 0.0), node="Plate", bevel=0.02)
    for k in range(7):  # a scallop shell carved on it: ribs fanning out
        a = math.radians(-60 + k * 20)
        m.box(K("sandstone", CORAL), (0.07, 0.03, 0.6), (math.sin(a) * 0.3, 0.165, math.cos(a) * 0.3 - 0.15), tilt=0.0, node="Plate")


def lever(m):
    blk(m, stone(SAND_DARK), (0.8, 0.9, 0.6), (0.0, 0.45, 0.0), bevel=0.03)
    blk(m, K("metal", GILT), (0.84, 0.08, 0.64), (0.0, 0.9, 0.0))
    blk(m, K("stone", GROUT), (0.12, 0.04, 0.5), (0.0, 0.94, 0.0))
    m.node("Handle", (0.0, 0.92, 0.0))
    m.rod(K("metal", IRON), 0.04, (0.0, 0.92, 0.0), (0.0, 1.75, 0.0), node="Handle", segs=8)
    m.ball(K("metal", GILT), (0.09, 0.09, 0.09), (0.0, 1.78, 0.0), node="Handle")


def push_block(m):
    s = 2.6
    blk(m, stone(SAND, 0.95), (s, s, s), (0.0, s / 2, 0.0), bevel=0.06)
    for side in range(4):  # a spiral (a nautilus) carved on each face
        rad = math.radians(side * 90)
        for k in range(14):
            a = k * 0.55
            r = 0.12 + k * 0.055
            u, y = math.cos(a) * r, 1.3 + math.sin(a) * r
            out = s / 2 + 0.01
            x, f = u * math.cos(rad) + out * math.sin(rad), -u * math.sin(rad) + out * math.cos(rad)
            blk(m, K("sandstone", CORAL), (0.1, 0.1, 0.03), (x, y, f), yaw=side * 90.0)


def torch(m):
    blk(m, K("metal", IRON), (0.12, 0.5, 0.08), (0.0, 2.6, 0.04))
    m.rod(K("metal", IRON), 0.03, (0.0, 2.7, 0.0), (0.0, 2.9, -0.32), segs=6)
    m.lathe(K("metal", GILT), [(0.0, 0.0), (0.06, 0.0), (0.16, 0.12), (0.17, 0.16), (0.0, 0.16)], (0.0, 2.86, -0.36), segs=12)
    m.empty("Flame", 0.0, 3.08, -0.36)


def key(m):
    gold = K("metal", GILT)
    m.lathe(gold, [(0.07, -0.02), (0.11, -0.02), (0.11, 0.02), (0.07, 0.02)], (0.0, 0.32, 0.0), segs=14, axis="x")  # the bow: a ring
    m.ball(K("sandstone", CORAL), (0.06, 0.05, 0.02), (0.0, 0.32, 0.0))
    m.box(gold, (0.035, 0.32, 0.035), (0.0, 0.07, 0.0))  # the shank
    for y, w in ((-0.05, 0.1), (-0.0, 0.07)):  # the bit
        m.box(gold, (0.02, 0.04, w), (0.0, y, w / 2), bevel=0.0)


def chest(m):
    w, d, h = 1.3, 0.8, 0.6
    blk(m, K("wood", WOOD), (w, h, d), (0.0, h / 2, 0.0), bevel=0.02)
    for x in (-w / 2 + 0.06, w / 2 - 0.06):
        blk(m, K("metal", GILT), (0.06, h + 0.02, d + 0.03), (x, h / 2, 0.0))
    m.node("Lid", (0.0, h, d / 2))
    m.box(K("wood", (0.48, 0.32, 0.18)), (w, 0.22, d), (0.0, h + 0.11, 0.0), node="Lid", bevel=0.03)
    m.box(K("wood", (0.5, 0.34, 0.2)), (w - 0.06, 0.12, d - 0.2), (0.0, h + 0.27, 0.0), node="Lid", bevel=0.03)
    for x in (-w / 2 + 0.06, w / 2 - 0.06):
        m.box(K("metal", GILT), (0.06, 0.36, d + 0.03), (x, h + 0.16, 0.0), node="Lid")
    m.box(K("metal", GILT), (0.18, 0.2, 0.05), (0.0, h + 0.02, -d / 2 - 0.02), node="Lid", bevel=0.01)


def gate(m):
    """A sea-temple door: two thick piers, a stepped lintel with a great shell, three steps up to it, a dark way in."""
    sand = stone(SAND)
    for side in (-1, 1):
        blk(m, sand, (1.4, 5.0, 1.8), (side * 2.0, 2.5, 0.0), bevel=0.04)
        blk(m, stone(SAND_DARK), (1.6, 0.5, 2.0), (side * 2.0, 0.25, 0.0), bevel=0.03)
        blk(m, stone(SAND, 1.05), (1.6, 0.3, 2.0), (side * 2.0, 5.15, 0.0), bevel=0.03)
        fk.blob(m, K("leaf", WEED), (0.5, 0.4, 0.3), (side * 2.0, 0.6, -0.9), seed=side + 5, rough=0.4, cuts=1)
    blk(m, sand, (5.6, 1.0, 1.9), (0.0, 5.8, 0.0), bevel=0.04)
    blk(m, stone(SAND, 1.06), (6.0, 0.35, 2.1), (0.0, 6.45, 0.0), bevel=0.04)
    shell(m, (0.0, 5.75, -1.0), 1.6)
    blk(m, K("metal", GILT), (2.8, 0.14, 0.1), (0.0, 5.3, -0.96))
    for i in range(3):  # steps up to the threshold
        blk(m, stone(SAND_DARK, 1.0 - 0.04 * i), (3.2, 0.2, 0.8), (0.0, 0.1 + 0.2 * i, -1.5 + 0.4 * i), bevel=0.02)
    blk(m, K("stone", (0.04, 0.05, 0.06)), (2.6, 4.6, 0.1), (0.0, 2.9, 0.4))  # the dark way in
    m.empty("Door", 0.0, 0.6, -1.2)


PIECES = {"dk_floor": floor, "dk_wall": wall, "dk_ceiling": ceiling, "dk_door": door, "dk_door_lock": door_lock, "dk_plate": plate,
    "dk_lever": lever, "dk_block": push_block, "dk_torch": torch, "dk_key": key, "dk_chest": chest, "dk_gate": gate}

if __name__ == "__main__":
    fk.init()
    only = [s for s in os.environ.get("ONLY", "").split(",") if s]
    os.makedirs(OUT, exist_ok=True)
    for name, build in PIECES.items():
        if only and name not in only:
            continue
        m = kit.Model(name, uv_scale=0.5, colored=True)
        build(m)
        print(name, m.export(OUT))
