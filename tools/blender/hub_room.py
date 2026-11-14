# Purpose: developer-time models of the safe hub (locked: diary/DECISIONS_HUB.md): a Victorian library turned subtle
# dungeon, 50 x 30 m, 14 m high. Writes assets/models/fantasy/hub_*.gltf (the fantasy loader game/fantasy_models.gd
# gives each part the texture of what it is made of and keeps its colour):
#   hub_hall      floor of flagstones (some cracked), stone walls with a doorway (trophy room) and an arch (staircase),
#                 bookshelves to the ceiling with rolling ladders, a balcony along both long walls (seen, not walked),
#                 the beamed ceiling, reading tables with chairs, two globes, a barred cell door, chains, cobwebs,
#                 damp stains, the high round moon window's stone ring (its glass and light: game/hub_room.gd)
#   hub_stage     the checkerboard stage with steps, two Corinthian pillars, the stone arch frame behind it
#   hub_stair     one turn of the spiral staircase seen through the arch (the game stacks copies up and down and turns it)
#   hub_pedestal  the sandstone pedestal and its gold top, carved with four bands of glyph figures running round all
#                 sides that tell the king's story (STORY below; stylised, nothing graphic)
#   hub_button    the big red button (a separate model: the game pushes it in)
#   hub_chandelier an iron ring of candles on chains
# Game axes in the helpers below: x across the hall, y up, z along it (+z = the front where players appear, -z = the
# stage). The kit wants (x, up, forward) with forward = -z.
# Run: python3 tools/blender/hub_room.py   (Blender's bpy module)
# Dependencies: tools/blender/kit.py, tools/blender/fantasy_kit.py.
import math
import os
import random
import sys

sys.path.insert(0, os.path.dirname(__file__))
import bpy  # noqa: F401 (must load before bmesh)
import bmesh
from mathutils import Matrix
import kit
import fantasy_kit
from fantasy_kit import K, init

HALL_W, HALL_D, HALL_H = 50.0, 30.0, 14.0
STONE, DARK_STONE, WOOD, DARK_WOOD, IRON, GOLD = (0.5, 0.48, 0.45), (0.3, 0.29, 0.28), (0.45, 0.3, 0.18), (0.24, 0.15, 0.09), (0.22, 0.22, 0.24), (0.95, 0.72, 0.25)
SAND = (0.86, 0.72, 0.5)
BOOKS = [(0.45, 0.12, 0.1), (0.12, 0.25, 0.18), (0.15, 0.18, 0.35), (0.55, 0.42, 0.22), (0.3, 0.1, 0.2), (0.35, 0.3, 0.25)]


def g(x, y, z):
    """Game point -> the kit's (x, up, forward)."""
    return (x, y, -z)


def box(m, mat, size, at, bevel=0.0):
    """A box in game axes: size (x, y, z), at = its middle."""
    m.box(mat, (size[0], size[1], size[2]), g(*at), bevel=bevel)


def many(m, mat, cubes):
    """Many boxes of one material and colour as one part: cubes = [(size, at, yaw degrees)] in game axes."""
    bm = bmesh.new()
    for size, at, yaw in cubes:
        mat4 = Matrix.Translation((at[0], -at[2], at[1])) @ Matrix.Rotation(math.radians(yaw), 4, "Z") @ Matrix.Diagonal((size[0], size[2], size[1], 1.0))
        bmesh.ops.create_cube(bm, size=1.0, matrix=mat4)
    m._add(bm, mat, "Body", 0)


# ---------------------------------------------------------------- the hall

def shelf_unit(cubes_by_color, boards, x0, z0, x1, z1, y0, y1, rnd, face):
    """A bookcase from (x0, z0) to (x1, z1) along a wall, y0..y1 high; `face` = the direction it faces (+1 / -1 on the
    wall's normal axis). Books are sorted into colour groups (one part each)."""
    along_x = abs(x1 - x0) > abs(z1 - z0)
    length = abs(x1 - x0) if along_x else abs(z1 - z0)
    depth = 0.45
    row = 0.46
    y = y0
    while y + row <= y1 + 0.01:
        # the board under this row
        if along_x:
            boards.append(((length, 0.05, depth), ((x0 + x1) / 2, y, z0 + face * depth / 2), 0))
        else:
            boards.append(((depth, 0.05, length), (x0 + face * depth / 2, y, (z0 + z1) / 2), 0))
        t = 0.03
        while t < length - 0.08:
            if rnd.random() < 0.06:  # a gap, or a book lying down
                t += rnd.uniform(0.08, 0.25)
                continue
            # eye level: single books; higher up: runs of books as one block (keeps the hall's triangles down)
            w = rnd.uniform(0.05, 0.12) if y < 2.0 else rnd.uniform(0.35, 0.9)
            h = rnd.uniform(0.26, 0.4) if y < 2.0 else rnd.uniform(0.3, 0.38)
            d = rnd.uniform(0.25, 0.36)
            col = rnd.randrange(len(BOOKS))
            if along_x:
                at = (min(x0, x1) + t + w / 2, y + 0.025 + h / 2, z0 + face * (depth - d / 2 - 0.03))
                cubes_by_color[col].append(((w, h, d), at, 0))
            else:
                at = (x0 + face * (depth - d / 2 - 0.03), y + 0.025 + h / 2, min(z0, z1) + t + w / 2)
                cubes_by_color[col].append(((d, h, w), at, 0))
            t += w + 0.004
        y += row
    # the sides and back of the case
    if along_x:
        for sx in (x0, x1):
            boards.append(((0.06, y1 - y0, depth), (sx, (y0 + y1) / 2, z0 + face * depth / 2), 0))
    else:
        for sz in (z0, z1):
            boards.append(((depth, y1 - y0, 0.06), (x0 + face * depth / 2, (y0 + y1) / 2, sz), 0))


def hall(m):
    rnd = random.Random(7)
    hw, hd = HALL_W / 2, HALL_D / 2
    # floor: 2 m flagstones in slightly different greys, a few cracked
    stones = {}
    cracks = []
    for ix in range(25):
        for iz in range(15):
            shade = rnd.choice([0, 1, 2, 3])
            stones.setdefault(shade, []).append(((1.96, 0.2, 1.96), (-hw + 1 + ix * 2, -0.1, -hd + 1 + iz * 2), 0))
            if rnd.random() < 0.12:
                cx, cz = -hw + 1 + ix * 2, -hd + 1 + iz * 2
                for _k in range(3):
                    cracks.append(((rnd.uniform(0.3, 0.9), 0.012, 0.025), (cx + rnd.uniform(-0.5, 0.5), 0.004, cz + rnd.uniform(-0.5, 0.5)), rnd.uniform(0, 180)))
    for shade, cubes in stones.items():
        v = 0.42 + shade * 0.04
        many(m, K("stone", (v, v * 0.97, v * 0.93)), cubes)
    many(m, K("paint", (0.08, 0.08, 0.08)), cracks)
    # walls (1 m thick, outside the hall), with the trophy room doorway (left, z 4.5..7.5) and the arch (back, x -3..3)
    wall = K("stone", DARK_STONE)
    door_z0, door_z1, door_h = 4.5, 7.5, 4.0
    arch_x0, arch_x1, arch_h = -3.0, 3.0, 9.0
    walls = [
        ((1.0, HALL_H, hd - door_z1 + 0.0), (-hw - 0.5, HALL_H / 2, (door_z1 + hd) / 2)),
        ((1.0, HALL_H, door_z0 + hd), (-hw - 0.5, HALL_H / 2, (door_z0 - hd) / 2)),
        ((1.0, HALL_H - door_h, door_z1 - door_z0), (-hw - 0.5, door_h + (HALL_H - door_h) / 2, (door_z0 + door_z1) / 2)),
        ((1.0, HALL_H, HALL_D + 2), (hw + 0.5, HALL_H / 2, 0)),
        ((HALL_W + 2, HALL_H, 1.0), (0, HALL_H / 2, hd + 0.5)),
        ((arch_x0 + hw + 1, HALL_H, 1.0), ((-hw - 1 + arch_x0) / 2, HALL_H / 2, -hd - 0.5)),
        ((hw + 1 - arch_x1, HALL_H, 1.0), ((hw + 1 + arch_x1) / 2, HALL_H / 2, -hd - 0.5)),
        ((arch_x1 - arch_x0, HALL_H - arch_h, 1.0), (0, arch_h + (HALL_H - arch_h) / 2, -hd - 0.5)),
    ]
    many(m, wall, [(s, a, 0) for s, a in walls])
    # wainscot: a dark wooden band round the hall's foot
    many(m, K("wood", DARK_WOOD), [((0.08, 1.1, HALL_D), (-hw + 0.04, 0.55, 0), 0), ((0.08, 1.1, HALL_D), (hw - 0.04, 0.55, 0), 0),
        ((HALL_W, 1.1, 0.08), (0, 0.55, hd - 0.04), 0)])
    # ceiling and beams
    many(m, K("wood", DARK_WOOD), [((HALL_W + 2, 0.4, HALL_D + 2), (0, HALL_H + 0.2, 0), 0)] + [((0.5, 0.6, HALL_D), (-hw + 2.5 + i * 5, HALL_H - 0.3, 0), 0) for i in range(10)])
    # bookcases: both long walls (two storeys, the balcony between), the front wall, the back wall beside the arch
    by_color = [[] for _ in BOOKS]
    boards = []
    for z0, z1 in [(-hd + 0.6, -10.8), (-7.2, -4.0), (-3.4, door_z0 - 0.3), (door_z1 + 0.3, hd - 0.6)]:  # left wall downstairs: gaps for the cell door (z -9) and the trophy room doorway
        shelf_unit(by_color, boards, -hw, z0, -hw, z1, 0.2, 5.6, rnd, 1)
    for z0, z1 in [(-hd + 0.6, -4.0), (-3.4, door_z0 - 0.3), (door_z1 + 0.3, hd - 0.6)]:  # left wall upstairs
        shelf_unit(by_color, boards, -hw, z0, -hw, z1, 6.6, 12.6, rnd, 1)
    for z0, z1 in [(-hd + 0.6, -2.8), (2.8, hd - 0.6)]:  # right wall (the Aurelind painting stands in the middle)
        shelf_unit(by_color, boards, hw, z0, hw, z1, 0.2, 5.6, rnd, -1)
    for z0, z1 in [(-hd + 0.6, -10.5), (-5.5, hd - 0.6)]:  # right wall upstairs (the moon window between)
        shelf_unit(by_color, boards, hw, z0, hw, z1, 6.6, 12.6, rnd, -1)
    shelf_unit(by_color, boards, -hw + 0.6, hd, hw - 0.6, hd, 0.2, 12.6, rnd, -1)  # front wall, floor to ceiling
    for x0, x1 in [(-hw + 0.6, -10.0), (10.0, hw - 0.6)]:  # back wall, either side of the stage
        shelf_unit(by_color, boards, x0, -hd, x1, -hd, 0.2, 12.6, rnd, 1)
    many(m, K("wood", WOOD), boards)
    leathers = ["leather", "cloth"]
    for i, cubes in enumerate(by_color):
        many(m, K(leathers[i % 2], BOOKS[i]), cubes)
    # balcony along both long walls at 6 m (seen, not walked): floor, posts, rail, brackets
    bal = []
    for side in (-1, 1):
        x = side * (hw - 1.2)
        bal.append(((1.5, 0.15, HALL_D - 2), (side * (hw - 0.75), 6.0, 0), 0))
        for i in range(29):
            z = -hd + 1.5 + i * 1.0
            bal.append(((0.07, 1.0, 0.07), (x - side * 0.3, 6.55, z), 0))
        bal.append(((0.12, 0.08, HALL_D - 2), (x - side * 0.3, 7.08, 0), 0))
        for i in range(8):
            bal.append(((0.6, 0.15, 0.2), (side * (hw - 0.6), 5.6, -hd + 2 + i * 3.7), 0))
    many(m, K("wood", DARK_WOOD), bal)
    # rolling ladders on brass rails
    rungs = []
    rails = []
    for side, z in [(-1, -13.0), (-1, 10.0), (1, -12.0), (1, 9.0)]:
        x = side * (hw - 1.3)
        for r in (-0.25, 0.25):
            rungs.append(((0.07, 5.6, 0.07), (x, 2.8, z + r), 0))
        for i in range(14):
            rungs.append(((0.05, 0.04, 0.5), (x, 0.4 + i * 0.38, z), 0))
        rails.append(((0.05, 0.05, HALL_D - 3), (side * (hw - 0.85), 5.55, 0), 0))
    many(m, K("wood", WOOD), rungs)
    many(m, K("metal", (0.8, 0.6, 0.25)), rails)
    # reading tables with chairs, two globes
    tables = []
    for tx, tz in [(-8.0, 6.0), (8.0, 6.0), (10.0, -2.0)]:
        tables.append(((3.2, 0.08, 1.2), (tx, 0.82, tz), 0))
        for lx in (-1.4, 1.4):
            for lz in (-0.45, 0.45):
                tables.append(((0.1, 0.8, 0.1), (tx + lx, 0.4, tz + lz), 0))
        for cx in (-0.9, 0.9):
            for cz in (-0.95, 0.95):
                tables.append(((0.45, 0.06, 0.45), (tx + cx, 0.46, tz + cz), 0))
                tables.append(((0.45, 0.6, 0.05), (tx + cx, 0.78, tz + cz + (0.2 if cz > 0 else -0.2)), 0))
                for lx in (-0.18, 0.18):
                    for lz in (-0.18, 0.18):
                        tables.append(((0.05, 0.45, 0.05), (tx + cx + lx, 0.22, tz + cz + lz), 0))
    many(m, K("wood", WOOD), tables)
    open_books = [((0.5, 0.03, 0.35), (-8.4, 0.88, 6.1), 12), ((0.5, 0.03, 0.35), (8.6, 0.88, 5.8), -20), ((0.5, 0.03, 0.35), (10.3, 0.88, -2.1), 5)]
    many(m, K("cloth", (0.92, 0.88, 0.75)), open_books)
    for gx, gz in [(-6.0, 9.0), (14.0, -6.0)]:
        m.lathe(K("wood", DARK_WOOD), [(0.35, 0.0), (0.35, 0.08), (0.06, 0.12), (0.05, 0.9), (0.08, 0.95)], (gx, 0.0, -gz), segs=12)
        m.ball(K("paint", (0.25, 0.4, 0.45)), 0.42, (gx, 1.4, -gz))
        m.rod(K("metal", (0.8, 0.6, 0.25)), 0.02, (gx - 0.47, 1.4, -gz), (gx + 0.47, 1.4, -gz))
    # the barred cell door in the left wall (z -9): a stone frame, dark inside, iron bars
    many(m, K("stone", STONE), [((0.4, 3.2, 0.4), (-hw + 0.2, 1.6, -10.4), 0), ((0.4, 3.2, 0.4), (-hw + 0.2, 1.6, -7.6), 0), ((0.4, 0.4, 3.2), (-hw + 0.2, 3.3, -9.0), 0)])
    many(m, K("paint", (0.02, 0.02, 0.03)), [((0.05, 3.0, 2.4), (-hw + 0.05, 1.5, -9.0), 0)])
    bars = [((0.05, 3.0, 0.05), (-hw + 0.25, 1.5, -9.0 + i * 0.25 - 1.0), 0) for i in range(9)]
    bars += [((0.05, 0.06, 2.4), (-hw + 0.25, y, -9.0), 0) for y in (0.4, 1.5, 2.7)]
    many(m, K("metal", IRON), bars)
    # chains hanging from a few upper shelves: alternating links
    links = []
    for x, z, n in [(-hw + 0.5, -12.5, 9), (-hw + 0.5, 12.0, 7), (hw - 0.5, -6.0, 8), (hw - 0.5, 13.0, 10)]:
        for i in range(n):
            links.append(((0.03, 0.14, 0.08 if i % 2 == 0 else 0.02), (x, 12.4 - i * 0.12, z), 0))
    many(m, K("metal", IRON), links)
    # damp stains and cobwebs
    stains = []
    for _i in range(18):
        side = rnd.choice([-1, 1])
        stains.append(((0.02, rnd.uniform(0.6, 2.0), rnd.uniform(0.8, 2.5)), (side * (hw - 0.01), rnd.uniform(0.3, 3.0), rnd.uniform(-hd + 1, hd - 1)), 0))
    many(m, K("plaster", (0.18, 0.2, 0.16)), stains)
    webs = []
    for cx, cz in [(-hw, -hd), (hw, -hd), (-hw, hd), (hw, hd)]:
        for k in range(6):
            a = k / 5.0 * 90.0
            webs.append(((0.01, 0.01, 1.6), (cx - math.copysign(0.4, cx), HALL_H - 0.6, cz - math.copysign(0.4, cz)), a + (0 if cx * cz > 0 else 90)))
    many(m, K("paint", (0.75, 0.75, 0.72)), webs)
    # the high round moon window in the right wall (cold glow; the game adds the moonlight)
    win = []
    for k in range(16):
        a = k / 16.0 * math.tau
        win.append(((0.3, 0.25, 0.4), (hw - 0.05, 9.5 + math.sin(a) * 1.6, -8.0 + math.cos(a) * 1.6), -math.degrees(a)))
    many(m, K("stone", STONE), win)
    # (the cold glass itself is made by the game: game/hub_room.gd _moon)
    many(m, K("metal", IRON), [((0.05, 3.0, 0.05), (hw - 0.12, 9.5, -8.0), 0), ((0.05, 0.05, 3.0), (hw - 0.12, 9.5, -8.0), 0)])


# ---------------------------------------------------------------- the stage, pillars and arch

def corinthian(m, x, z, h):
    """A Corinthian column standing at game (x, 0, z), h tall."""
    marble = K("stone", (0.85, 0.83, 0.78))
    box(m, marble, (1.6, 0.4, 1.6), (x, 0.2, z))
    m.lathe(marble, [(0.75, 0.4), (0.75, 0.55), (0.65, 0.62), (0.68, 0.72), (0.58, 0.8)], (x, 0.0, -z), segs=24)
    m.lathe(marble, [(0.55, 0.8), (0.47, h - 1.6)], (x, 0.0, -z), segs=24)  # the shaft, a little narrower at the top
    flutes = []
    for k in range(20):
        a = k / 20.0 * math.tau
        flutes.append(((0.06, h - 2.6, 0.06), (x + math.cos(a) * 0.52, (h - 1.6 + 0.8) / 2 + 0.1, z + math.sin(a) * 0.52), 0))
    many(m, K("stone", (0.72, 0.7, 0.66)), flutes)
    # the capital: a bell with two rows of leaves and corner scrolls, the square abacus on top
    m.lathe(marble, [(0.47, h - 1.6), (0.52, h - 1.2), (0.62, h - 0.7), (0.72, h - 0.35)], (x, 0.0, -z), segs=24)
    leaf = K("stone", (0.8, 0.78, 0.7))
    for row, (r, y) in enumerate([(0.55, h - 1.3), (0.66, h - 0.85)]):
        for k in range(8):
            a = (k + row * 0.5) / 8.0 * math.tau
            m.ball(leaf, (0.16, 0.32, 0.1), (x + math.cos(a) * r, y, -(z + math.sin(a) * r)), yaw=-math.degrees(a))
    for k in range(4):
        a = (k + 0.5) / 4.0 * math.tau
        m.ball(leaf, (0.16, 0.16, 0.16), (x + math.cos(a) * 0.82, h - 0.45, -(z + math.sin(a) * 0.82)))
    box(m, marble, (1.7, 0.3, 1.7), (x, h - 0.15, z))


def stage(m):
    x0, z0, x1, z1, top = -8.0, -14.0, 8.0, -8.5, 0.45
    white, black = K("stone", (0.92, 0.9, 0.86)), K("stone", (0.08, 0.08, 0.09))
    tiles = {0: [], 1: []}
    for ix in range(16):
        for iz in range(6):
            dz = (z1 - z0) / 6.0
            tiles[(ix + iz) % 2].append(((0.99, 0.06, dz - 0.01), (x0 + 0.5 + ix, top - 0.03, z0 + dz / 2 + iz * dz), 0))
    many(m, white, tiles[0])
    many(m, black, tiles[1])
    box(m, K("stone", DARK_STONE), (x1 - x0 + 0.3, top - 0.06, z1 - z0 + 0.15), (0, (top - 0.06) / 2, (z0 + z1) / 2))
    for i, h in enumerate([0.3, 0.15]):  # two steps up at the front
        box(m, K("stone", STONE), (10.0, h, 0.35), (0, h / 2, z1 + 0.17 + i * 0.35))
    for side in (-1, 1):
        corinthian(m, side * 8.9, -11.5, 11.0)
    # the arch frame round the opening in the back wall (x -3..3, up to 9 m): pilasters and voussoirs
    frame = K("stone", (0.62, 0.6, 0.56))
    for side in (-1, 1):
        box(m, frame, (0.8, 6.0, 0.6), (side * 3.4, 3.0, -15.2))
    vous = []
    for k in range(13):
        a = math.pi * k / 12.0
        vous.append(((0.8, 0.9, 0.6), (math.cos(a) * 3.4, 6.0 + math.sin(a) * 3.4, -15.2), math.degrees(a) - 90.0))
    bm = bmesh.new()
    for size, at, roll in vous:
        mat4 = Matrix.Translation((at[0], -at[2], at[1])) @ Matrix.Rotation(math.radians(roll), 4, "Y") @ Matrix.Diagonal((size[0], size[2], size[1], 1.0))
        bmesh.ops.create_cube(bm, size=1.0, matrix=mat4)
    m._add(bm, frame, "Body", 0)


# ---------------------------------------------------------------- the spiral staircase (one turn)

def stair(m):
    r_in, r_out, rise = 0.45, 2.6, 4.2
    steps = 16
    stone = K("stone", (0.4, 0.38, 0.36))
    m.lathe(stone, [(r_in, 0.0), (r_in, rise)], (0, 0.0, 0), segs=16)
    bm = bmesh.new()
    for i in range(steps):
        a = i / steps * math.tau
        y = i * rise / steps
        mid = (r_in + r_out) / 2
        mat4 = Matrix.Translation((math.cos(a) * mid, math.sin(a) * mid, y + 0.08)) @ Matrix.Rotation(a, 4, "Z") @ Matrix.Diagonal((r_out - r_in, 0.95, 0.16, 1.0))
        bmesh.ops.create_cube(bm, size=1.0, matrix=mat4)
    m._add(bm, stone, "Body", 0)
    posts = []
    for i in range(steps):
        a = i / steps * math.tau
        y = i * rise / steps
        posts.append(((0.05, 1.0, 0.05), (math.cos(a) * (r_out - 0.08), y + 0.66, -math.sin(a) * (r_out - 0.08)), 0))
    many(m, K("metal", IRON), posts)
    for i in range(steps):
        a0, a1 = i / steps * math.tau, (i + 1) / steps * math.tau
        y0, y1 = i * rise / steps + 1.16, (i + 1) * rise / steps + 1.16
        m.rod(K("wood", DARK_WOOD), 0.04, (math.cos(a0) * (r_out - 0.08), y0, math.sin(a0) * (r_out - 0.08)), (math.cos(a1) * (r_out - 0.08), y1, math.sin(a1) * (r_out - 0.08)), segs=6)


# ---------------------------------------------------------------- the pedestal and its carvings

# Carved figures for the pedestal's bands: each glyph = boxes [(w, h, u, v, roll degrees)] about its foot (u along
# the band, v up, metres at scale 1 = a 0.15 m tall adult). Stylised like an ancient frieze; nothing graphic.
def _person(h=0.15, arms="down", lean=0.0):
    b = [(0.05, h * 0.6, 0.0, h * 0.3, lean), (0.04, h * 0.22, 0.0, h * 0.72, 0.0)]  # robe and shoulders
    b.append((0.04, 0.04, 0.0, h * 0.92, 0.0))  # head
    if arms == "up":  # praise or grief: both arms raised
        b += [(0.013, h * 0.32, -0.034, h * 0.88, 20.0), (0.013, h * 0.32, 0.034, h * 0.88, -20.0)]
    elif arms == "out":  # reaching ahead (giving, leading)
        b.append((h * 0.36, 0.013, 0.06, h * 0.66, 0.0))
    elif arms == "bowl":  # an offering held up
        b += [(0.013, h * 0.27, 0.035, h * 0.84, -15.0), (0.06, 0.02, 0.045, h * 1.0, 0.0)]
    return b


GLYPHS = {
    "king": _person(0.17, "out") + [(0.026, 0.05, 0.0, 0.195, 0.0), (0.006, 0.19, 0.08, 0.095, 0.0)],  # tall crown, staff
    "king_big": [(w * 1.5, h * 1.5, u * 1.5, v * 1.5, r) for w, h, u, v, r in _person(0.17, "out") + [(0.026, 0.05, 0.0, 0.195, 0.0), (0.006, 0.19, 0.08, 0.095, 0.0)]],
    "king_kneel": [(0.04, 0.06, 0.0, 0.03, 0.0), (0.035, 0.06, 0.0, 0.085, 25.0), (0.03, 0.03, -0.02, 0.125, 0.0), (0.022, 0.035, -0.02, 0.155, 0.0)],
    "throne": [(0.07, 0.04, 0.0, 0.05, 0.0), (0.015, 0.12, -0.035, 0.06, 0.0), (0.012, 0.05, 0.03, 0.025, 0.0)],
    "person": _person(),
    "praise": _person(arms="up"),
    "bow": [(0.035, 0.08, 0.0, 0.04, 0.0), (0.035, 0.06, 0.02, 0.095, -55.0), (0.03, 0.03, 0.05, 0.11, 0.0)],
    "bearer": _person(arms="bowl"),
    "priest": _person(0.16, "out") + [(0.055, 0.03, 0.0, 0.015, 0.0), (0.02, 0.04, 0.0, 0.17, 0.0)],  # wide hem, tall cap
    "small": [(w * 0.6, h * 0.6, u * 0.6, v * 0.6, r) for w, h, u, v, r in _person(arms="up")],  # a little one, hand raised to the next
    "farmer": _person(arms="out") + [(0.006, 0.12, 0.09, 0.06, -30.0)],  # with a sickle's long handle
    "god": [(0.045, 0.16, 0.0, 0.08, 0.0), (0.03, 0.04, 0.0, 0.18, 0.0), (0.06, 0.06, 0.0, 0.23, 0.0), (0.05, 0.008, 0.05, 0.12, 0.0)],  # sun-headed figure, hand out
    "sun": [(0.06, 0.06, 0.0, 0.11, 0.0)] + [(0.008, 0.035, 0.05 * math.cos(math.radians(a)), 0.11 + 0.05 * math.sin(math.radians(a)), a - 90.0) for a in range(0, 360, 45)],
    "sun_big": [(0.08, 0.08, 0.0, 0.11, 0.0)] + [(0.01, 0.06, 0.07 * math.cos(math.radians(a)), 0.11 + 0.07 * math.sin(math.radians(a)), a - 90.0) for a in range(0, 360, 30)],
    "sun_rise": [(0.07, 0.035, 0.0, 0.017, 0.0), (0.12, 0.006, 0.0, 0.0, 0.0)] + [(0.007, 0.03, 0.055 * math.cos(math.radians(a)), 0.02 + 0.055 * math.sin(math.radians(a)), a - 90.0) for a in (30, 60, 90, 120, 150)],
    "sun_dark": [(0.06, 0.008, 0.0, 0.08, 0.0), (0.06, 0.008, 0.0, 0.14, 0.0), (0.008, 0.06, -0.03, 0.11, 0.0), (0.008, 0.06, 0.03, 0.11, 0.0)],  # an empty ring: no light
    "wheat": [(0.006, 0.12, 0.0, 0.06, 0.0), (0.016, 0.03, 0.0, 0.13, 0.0), (0.006, 0.1, 0.03, 0.05, 6.0), (0.014, 0.028, 0.035, 0.11, 6.0)],
    "wheat_dead": [(0.006, 0.07, 0.0, 0.035, 0.0), (0.006, 0.05, 0.015, 0.075, -70.0), (0.006, 0.06, 0.04, 0.03, 30.0)],
    "temple": [(0.18, 0.015, 0.0, 0.007, 0.0), (0.15, 0.015, 0.0, 0.022, 0.0), (0.12, 0.015, 0.0, 0.037, 0.0), (0.012, 0.11, -0.05, 0.1, 0.0), (0.012, 0.11, 0.05, 0.1, 0.0), (0.14, 0.02, 0.0, 0.165, 0.0)],
    "temple_shut": [(0.18, 0.015, 0.0, 0.007, 0.0), (0.15, 0.015, 0.0, 0.022, 0.0), (0.12, 0.015, 0.0, 0.037, 0.0), (0.012, 0.11, -0.05, 0.1, 0.0), (0.012, 0.11, 0.05, 0.1, 0.0), (0.14, 0.02, 0.0, 0.165, 0.0), (0.085, 0.11, 0.0, 0.1, 0.0)],
    "steps": [(0.05, 0.015 * (i + 1), 0.05 * i, 0.0075 * (i + 1), 0.0) for i in range(4)],
    "feet": [(0.012, 0.02, 0.0, 0.01, 0.0), (0.012, 0.02, 0.018, 0.022, 0.0)],  # footprints, all going one way
    "jar": [(0.03, 0.04, 0.0, 0.02, 0.0), (0.015, 0.012, 0.0, 0.046, 0.0)],
    "rays_down": [(0.006, 0.12, 0.03 * k, 0.1, 10.0 * k) for k in (-2, -1, 0, 1, 2)],  # light falling on whoever stands below
    "glyph_eye": [(0.04, 0.012, 0.0, 0.02, 0.0), (0.012, 0.012, 0.0, 0.02, 0.0), (0.006, 0.018, -0.01, 0.005, 20.0)],
    "glyph_bird": [(0.035, 0.018, 0.0, 0.02, -10.0), (0.012, 0.012, 0.02, 0.035, 0.0), (0.004, 0.015, 0.0, 0.006, 0.0)],
    "glyph_reed": [(0.006, 0.05, 0.0, 0.025, 0.0), (0.012, 0.018, 0.004, 0.05, 25.0)],
    "glyph_water": [(0.012, 0.006, 0.012 * k, 0.01 + 0.004 * (k % 2), 30.0 * (1 - 2 * (k % 2))) for k in range(4)],
    "glyph_ankh": [(0.006, 0.035, 0.0, 0.018, 0.0), (0.025, 0.006, 0.0, 0.035, 0.0), (0.016, 0.016, 0.0, 0.048, 0.0)],
}

# The story, one band per chapter, each band running round all four sides (front, right, back, left) and read from
# the top band down: a king is crowned under the rising sun; the sun goes dark and the fields die, he kneels to the
# sun-headed one and is given power; the little ones are led in a line up the temple steps, those left behind raise
# their arms; the temple is shut, the footprints go in and none come out, the sun blazes, the wheat stands tall and
# the king stands taller than his temple. A newcomer sees an ordinary ancient frieze; it tells itself to those who
# look.
STORY = [
    [["sun_rise", "glyph_eye", "throne", "king", "bow", "bow"], ["bearer", "bearer", "bow", "praise", "glyph_reed"], ["farmer", "wheat", "wheat", "farmer", "wheat"], ["jar", "jar", "person", "glyph_bird", "king", "sun"]],
    [["sun_dark", "wheat_dead", "wheat_dead", "wheat_dead", "praise"], ["praise", "person", "praise", "glyph_water", "jar"], ["king_kneel", "glyph_ankh", "god"], ["god", "king", "glyph_eye", "praise", "praise"]],
    [["priest", "small", "small", "small", "small"], ["small", "small", "priest", "praise", "praise"], ["praise", "small", "small", "steps", "small"], ["priest", "small", "temple", "glyph_reed"]],
    [["temple_shut", "feet", "feet", "feet"], ["sun_big", "rays_down", "king_big"], ["wheat", "wheat", "bow", "bow", "wheat"], ["glyph_bird", "temple", "king_big", "glyph_ankh"]],
]
# Between the figures stand short columns of small glyphs (the carved words beside the pictures), each column
# different.
_SMALL = ["glyph_eye", "glyph_bird", "glyph_reed", "glyph_water", "glyph_ankh", "jar"]
for _k in range(6):
    GLYPHS["col_%d" % _k] = [(w * 0.75, h * 0.75, u * 0.75, v * 0.75 + 0.058 * i, r) for i in range(3) for w, h, u, v, r in GLYPHS[_SMALL[(_k + i * 2) % 6]]]
FACES = [(0, 1), (1, 0), (0, -1), (-1, 0)]  # front (toward the spawns), right, back, left: the bands read round clockwise


def carve(parts, face, u, v, glyph, scale=1.0):
    nx, nz = face
    for w, h, gu, gv, roll in GLYPHS[glyph]:
        pu, pv = u + gu * scale, v + gv * scale
        at = (nx * 0.72 + (-nz) * pu, pv, nz * 0.72 + nx * pu)
        parts.append(((max(w * scale, 0.011), max(h * scale, 0.011), 0.026), at, nx, nz, roll))


def pedestal(m):
    sand = K("sandstone", SAND)
    face = K("plaster", SAND)  # the carved faces: smooth dressed stone, so the figures read
    deep = K("paint", (0.36, 0.24, 0.13))
    box(m, sand, (1.9, 0.25, 1.9), (0, 0.125, 0))
    box(m, sand, (1.6, 0.12, 1.6), (0, 0.31, 0))
    box(m, face, (1.42, 0.85, 1.42), (0, 0.79, 0))
    box(m, sand, (1.62, 0.1, 1.62), (0, 1.26, 0))
    box(m, sand, (1.5, 0.08, 1.5), (0, 1.35, 0))
    box(m, K("metal", GOLD), (1.3, 0.06, 1.3), (0, 1.42, 0))
    parts = []
    bands = [1.03, 0.83, 0.63, 0.43]  # the foot of each band, top chapter first
    for face_i, face in enumerate(FACES):
        nx, nz = face
        for v in bands + [1.21]:  # raised lines between the bands
            parts.append(((1.38, 0.014, 0.02), (nx * 0.716, v - 0.014, nz * 0.716), nx, nz, 0.0))
        for chapter, v in enumerate(bands):
            row = []
            for k, name in enumerate(STORY[chapter][face_i]):  # a column of words after every figure
                row += [name, "col_%d" % ((k + chapter * 2 + face_i) % 6)]
            widths = [max(0.07, max(abs(g[2]) + g[0] / 2 for g in GLYPHS[name]) * 2 + 0.03) for name in row]
            scale = min(1.0, 1.3 / sum(widths))
            u = -0.65
            for name, w in zip(row, widths):
                u += w * scale / 2
                tall = max(g[3] + abs(g[1]) / 2 for g in GLYPHS[name])
                carve(parts, face, u, v, name, min(scale, 0.17 / tall))  # nothing reaches into the band above
                u += w * scale / 2 + (1.3 - sum(widths) * scale) / max(len(row) - 1, 1)
    bm = bmesh.new()
    for size, at, nx, nz, roll in parts:
        yaw = math.degrees(math.atan2(nx, nz))
        mat4 = Matrix.Translation((at[0], -at[2], at[1])) @ Matrix.Rotation(math.radians(-yaw), 4, "Z") @ Matrix.Rotation(math.radians(roll), 4, "Y") @ Matrix.Diagonal((size[0], size[2], size[1], 1.0))
        bmesh.ops.create_cube(bm, size=1.0, matrix=mat4)
    m._add(bm, deep, "Body", 0)


def button(m):
    m.lathe(K("metal", GOLD), [(0.28, 0.0), (0.28, 0.06), (0.24, 0.08)], (0, 0.0, 0), segs=24)
    m.lathe(K("paint", (0.85, 0.05, 0.04)), [(0.22, 0.06), (0.22, 0.12), (0.2, 0.17), (0.14, 0.21), (0.0, 0.23)], (0, 0.0, 0), segs=24)


def chandelier(m):
    iron = K("metal", IRON)
    m.lathe(iron, [(1.2, 0.0), (1.25, 0.04), (1.2, 0.08)], (0, 0.0, 0), segs=24)
    m.lathe(iron, [(0.15, -0.3), (0.2, 0.0), (0.12, 0.25)], (0, 0.0, 0), segs=12)
    for k in range(4):
        a = k / 4.0 * math.tau
        m.rod(iron, 0.02, (math.cos(a) * 1.2, 0.06, math.sin(a) * 1.2), (0, 1.6, 0), segs=5)
    m.rod(iron, 0.025, (0, 1.6, 0), (0, 3.0, 0), segs=5)
    for k in range(10):
        a = k / 10.0 * math.tau
        x, f = math.cos(a) * 1.2, math.sin(a) * 1.2
        m.lathe(K("metal", IRON), [(0.07, 0.06), (0.07, 0.09)], (x, 0.0, f), segs=8)  # the drip pan
        m.lathe(K("cloth", (0.95, 0.9, 0.78)), [(0.035, 0.08), (0.035, 0.32)], (x, 0.0, f), segs=8)
        m.ball((fantasy_kit.GLOW, (1.0, 0.75, 0.35)), (0.025, 0.06, 0.025), (x, 0.38, f))


if __name__ == "__main__":
    init()
    fantasy_kit.OUT = os.path.join(os.path.dirname(__file__), "..", "..", "assets", "models", "fantasy")
    for name, build, uv in [("hub_hall", hall, 0.5), ("hub_stage", stage, 0.6), ("hub_stair", stair, 0.8), ("hub_pedestal", pedestal, 1.2),
            ("hub_button", button, 2.0), ("hub_chandelier", chandelier, 2.0)]:
        if len(sys.argv) > 1 and name not in sys.argv[1:]:
            continue
        m = kit.Model(name, uv_scale=uv, colored=True)
        build(m)
        print(name, m.export(fantasy_kit.OUT))
