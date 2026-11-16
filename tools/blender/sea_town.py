# Purpose: developer-time tool. Builds the HOME PORT TOWN's buildings (sea step 7) into assets/models/sea/town/:
# <building>_<level>.gltf for every level of every building in data/sea/town.json, <building>_0.gltf = the plot as
# it waits to be repaired (director: "a hamlet stands, the rest you help them grow and repair"), and town_sign.gltf
# (the post every plot's sign hangs on). Levels climb the town's styles (tools/blender/sea_town_parts.py: fishing
# shack, painted cottage, framed house, stone and timber, stone colonial; director: every upgrade visibly rebuilt and
# different at a glance). Each building keeps its own trade sign, colours and things round it at every level.
# Markers (glTF empties the game reads): "Door" (the front door's foot), "Counter" and "Ledger" (the harbour
# master's shop counter and the town ledger, where the player stands), "Sign" (where the plot's sign post goes).
# Model space: x right, y up from the plot's ground, f forward = the street / the water (Godot -z).
# Run: python3 tools/blender/sea_town.py [building[_level] ...]   (bpy as a module)
# Dependencies: bpy, tools/blender/kit.py, fantasy_kit.py, fantasy_house.py, sea_town_parts.py. No game code.
import math
import os
import random
import sys

sys.path.insert(0, os.path.dirname(__file__))
import bpy  # noqa: F401
import kit
import fantasy_kit as fk
from fantasy_kit import K, c
import sea_town_parts as P
from sea_town_parts import blk, tone, scheme, Face

OUT = os.path.join(os.path.dirname(__file__), "..", "..", "assets", "models", "sea", "town")
WOOD = (0.5, 0.38, 0.25)
SOIL = (0.32, 0.24, 0.17)
TEAL = (0.3, 0.52, 0.55)


def counter(m, x, f, style, yaw=0.0):
    """The harbour master's counter (shop, money changer, ferry desk): a timber or stone counter with the ledger
    book open on it, a set of scales and a stack of coins; under a striped awning until the town is stone-built."""
    wood = K("wood", (0.42, 0.3, 0.2)) if style < 4 else K("stone", (0.82, 0.78, 0.7))
    blk(m, wood, (2.4, 1.0, 0.8), (x, 0.5, f))
    blk(m, K("wood", (0.3, 0.2, 0.13)), (2.6, 0.08, 0.95), (x, 1.04, f))
    blk(m, K("cloth", (0.9, 0.86, 0.72)), (0.4, 0.04, 0.3), (x - 0.6, 1.1, f))
    m.rod(K("metal", P.GOLD), 0.012, (x + 0.5, 1.08, f), (x + 0.5, 1.42, f), segs=6)
    m.rod(K("metal", P.GOLD), 0.01, (x + 0.32, 1.42, f), (x + 0.68, 1.42, f), segs=6)
    for dx in (0.32, 0.68):
        m.lathe(K("metal", P.GOLD), [(0.0, -0.01), (0.08, 0.0), (0.0, 0.01)], (x + dx, 1.28, f), segs=10)
    for k in range(5):
        m.lathe(K("metal", P.GOLD), [(0.0, -0.006), (0.035, -0.006), (0.035, 0.006), (0.0, 0.006)], (x + 0.95, 1.095 + 0.013 * k, f + 0.1), segs=10)
    if style < 4:
        for side in (-1, 1):
            m.rod(K("wood", (0.3, 0.2, 0.13)), 0.06, (x + side * 1.3, 0.0, f + 0.45), (x + side * 1.3, 2.35, f + 0.45), segs=6)
        for k in range(6):
            blk(m, K("cloth", TEAL if k % 2 == 0 else (0.94, 0.9, 0.78)), (2.8 / 6 + 0.01, 0.03, 1.4), (x - 1.4 + 2.8 * (k + 0.5) / 6, 2.45, f - 0.15), pitch=14.0)
    m.empty("Counter", x, 0.0, f + 1.0)


def ledger_stand(m, x, f, style):
    """The town ledger on a lectern: a big book open on a slanted top (the upgrade book for every building)."""
    wood = K("wood", (0.36, 0.24, 0.15)) if style < 3 else K("metal", (0.55, 0.45, 0.25))
    m.rod(wood, 0.06, (x, 0.0, f), (x, 1.0, f), segs=6)
    m.lathe(wood, [(0.0, 0.0), (0.28, 0.0), (0.2, 0.06), (0.0, 0.08)], (x, 0.0, f), segs=8)
    blk(m, K("wood", (0.36, 0.24, 0.15)), (0.62, 0.06, 0.46), (x, 1.05, f), pitch=-22.0)
    for side in (-1, 1):
        blk(m, K("cloth", (0.94, 0.9, 0.78)), (0.27, 0.05, 0.38), (x + side * 0.14, 1.1, f), pitch=-22.0, roll=side * 6.0)
    blk(m, K("leather", (0.45, 0.12, 0.1)), (0.6, 0.03, 0.42), (x, 1.07, f), pitch=-22.0)
    m.rod(K("cloth", (0.75, 0.15, 0.15)), 0.008, (x + 0.05, 1.14, f + 0.05), (x + 0.05, 0.9, f + 0.25), segs=3)
    if style >= 3:
        P.lantern(m, (x - 0.38, 1.12, f - 0.1), hang=False)
    m.empty("Ledger", x, 0.0, f + 0.9)


def sign_post_mark(m, x, f):
    m.empty("Sign", x, 0.0, f)


def door_mark(m, x, f, y):
    m.empty("Door", x, y, f)


def portico(m, s, w, hd, fl, height, cols=6):
    """A temple front: a row of columns carrying an entablature and a pediment, on a stepped base."""
    stone = K("stone", s["stone"])
    depth = 3.0
    f = hd + depth
    for k in range(4):  # the steps up to it
        blk(m, tone(stone, 1.0 - 0.04 * k), (w + 1.2 - k * 0.3, fl - P.DEEP - k * fl / 4, depth + 1.2 - k * 0.3), (0.0, (fl - k * fl / 4 + P.DEEP) / 2, hd + depth / 2 + 0.3))
    blk(m, stone, (w + 0.4, fl - P.DEEP, depth + 0.4), (0.0, (fl + P.DEEP) / 2, hd + depth / 2))
    for k in range(cols):
        x = -w / 2 + 0.5 + (w - 1.0) * k / (cols - 1)
        m.lathe(tone(stone, 1.12), [(0.0, 0.0), (0.42, 0.0), (0.42, 0.2), (0.32, 0.28), (0.3, height - 0.5), (0.36, height - 0.4), (0.44, height - 0.25), (0.44, height), (0.0, height)], (x, fl, f - 0.5), segs=14)
    top = fl + height
    blk(m, tone(stone, 1.05), (w + 0.5, 0.7, depth + 0.4), (0.0, top + 0.35, hd + depth / 2))
    blk(m, tone(stone, 0.95), (w + 0.7, 0.18, depth + 0.6), (0.0, top + 0.78, hd + depth / 2))
    ph = w * 0.2
    P.poly(m, tone(stone, 1.08), [(-w / 2 - 0.35, top + 0.87, f + 0.2), (w / 2 + 0.35, top + 0.87, f + 0.2), (0.0, top + 0.87 + ph, f + 0.2),
        (-w / 2 - 0.35, top + 0.87, hd - 0.2), (w / 2 + 0.35, top + 0.87, hd - 0.2), (0.0, top + 0.87 + ph, hd - 0.2)], [[0, 1, 2], [5, 4, 3], [0, 3, 4, 1], [1, 4, 5, 2], [2, 5, 3, 0]])
    P.poly(m, K("roof", s["roof"]), [(-w / 2 - 0.5, top + 0.85, f + 0.35), (w / 2 + 0.5, top + 0.85, f + 0.35), (0.0, top + 1.0 + ph, f + 0.35),
        (-w / 2 - 0.5, top + 0.85, hd - 0.2), (w / 2 + 0.5, top + 0.85, hd - 0.2), (0.0, top + 1.0 + ph, hd - 0.2)], [[0, 3, 5, 2], [1, 2, 5, 4], [0, 1, 4, 3], [0, 2, 1], [3, 4, 5]])
    return top


# --- the buildings, one function per building: build(m, level) where level 1.. (0 = ruin, made generically) ---

def harbour_master(m, lv):
    st = [0, 0, 1, 2, 3, 4][lv]
    if st == 0:
        s = scheme(0)
        P.shack(m, 4.6, 3.6, s, door_u=0.6, windows={"front": [-1.3], "left": [0.0], "right": [0.0]})
        P.steps(m, K("wood", P.DRIFT), 0.6, 1.8, 1.1, P.FLOOR[0])
        counter(m, -3.2, 2.6, 0)
        ledger_stand(m, 3.0, 2.4, 0)
        P.sign(m, (2.3, 2.5, 1.85), "anchor", out=0.9)
        P.nets(m, -4.6, 0.0, -1.0, 2.2, 1.4, yaw=90.0)
        P.barrel(m, (2.9, 0.0, -1.6))
        P.rope_coil(m, (3.0, 0.0, 0.2))
        P.lantern(m, (-1.0, 2.4, 1.95))
        door_mark(m, 0.6, 3.6, 0.0)
        sign_post_mark(m, 4.4, 4.2)
    elif st == 1:
        s = scheme(1, wall=TEAL)
        P.cottage(m, 6.6, 5.0, s, door_u=0.0)
        P.steps(m, K("stone", s["stone"]), 0.0, 3.3, 1.6, P.FLOOR[1])
        counter(m, -4.4, 3.4, 1)
        ledger_stand(m, 4.3, 3.0, 1)
        P.sign(m, (3.3, 2.5, 2.55), "anchor", out=1.0)
        P.lantern(m, (-1.2, 2.5, 2.6))
        P.crate(m, (4.0, 0.0, -1.2))
        P.crate(m, (4.1, 0.0, -0.4), 0.5, yaw=15.0)
        door_mark(m, 0.0, 4.2, 0.0)
        sign_post_mark(m, 5.6, 5.2)
    elif st == 2:
        s = scheme(2)
        P.framed(m, 8.0, 6.4, s, floors=2, roof_h=2.8)
        counter(m, -5.0, 4.2, 2)
        ledger_stand(m, 5.0, 3.8, 2)
        P.sign(m, (4.0, 3.1, 3.4), "anchor", out=1.1)
        P.lantern(m, (-1.4, 2.6, 3.45))
        P.lantern(m, (1.4, 2.6, 3.45))
        P.terrace(m, K("stone", s["stone"]), 13.0, 4.0, y=0.02, f=5.0, cap=K("stone", (0.5, 0.48, 0.45)))
        door_mark(m, 0.0, 4.0, 0.0)
        sign_post_mark(m, 6.6, 6.6)
    elif st == 3:
        s = scheme(3)
        P.stone_timber(m, 10.0, 7.6, s, door_u=0.0)
        P.steps(m, K("stone", s["stone"]), 0.0, 4.0, 2.4, P.FLOOR[3])
        counter(m, -6.2, 5.2, 3)
        ledger_stand(m, 6.0, 4.8, 3)
        P.sign(m, (5.0, 3.0, 4.05), "anchor", out=1.2)
        P.terrace(m, K("stone", s["stone"]), 16.0, 4.6, y=0.02, f=6.2, cap=K("stone", (0.55, 0.52, 0.47)))
        for x in (-2.0, 2.0):
            P.lantern(m, (x, 2.9, 4.0))
        door_mark(m, 0.0, 5.0, 0.0)
        sign_post_mark(m, 8.2, 8.4)
    else:
        s = scheme(4)
        P.colonial(m, 13.0, 9.0, s, floors=2, roof_h=3.2, arcade=True)
        P.cupola(m, s, 0.0, P.FLOOR[4] + 2 * P.STOREY[4] + 2.0, 0.0, size=2.6)
        P.steps(m, K("stone", s["stone"]), 0.0, 7.0, 4.0, P.FLOOR[4])
        counter(m, -4.6, 8.8, 4)
        ledger_stand(m, 4.6, 8.6, 4)
        P.terrace(m, K("stone", s["stone"]), 19.0, 5.0, y=0.02, f=9.4, cap=K("stone", (0.58, 0.55, 0.5)))
        P.sign(m, (6.5, 4.6, 7.1), "anchor", out=1.2)
        for x in (-8.2, 8.2):  # lamp posts at the corners of the forecourt
            m.rod(K("metal", P.IRON), 0.07, (x, 0.0, 10.8), (x, 3.4, 10.8), segs=8)
            P.lantern(m, (x, 3.4, 10.8), hang=False)
        door_mark(m, 0.0, 7.4, 0.0)
        sign_post_mark(m, 9.4, 11.2)


def tavern(m, lv):
    st = [0, 0, 1, 2, 3, 4][lv]
    red = (0.62, 0.26, 0.2)
    if st == 0:  # a beach bar: a shack, an awning on poles over barrel tables
        s = scheme(0)
        P.shack(m, 4.4, 3.4, s, door_u=-1.0, windows={"front": [1.0], "left": [0.0], "right": []})
        P.steps(m, K("wood", P.DRIFT), -1.0, 1.7, 1.1, P.FLOOR[0])
        for x in (-2.6, 2.6):
            for f in (2.2, 5.4):
                m.rod(K("wood", P.DRIFT), 0.07, (x, 0.0, f), (x, 2.4, f), segs=6)
        for k in range(8):
            blk(m, K("cloth", (0.85, 0.75, 0.55) if k % 2 else (0.75, 0.35, 0.25)), (5.6 / 8 + 0.01, 0.03, 3.6), (-2.8 + 5.6 * (k + 0.5) / 8, 2.45, 3.8), pitch=-4.0)
        for x in (-1.4, 1.4):
            P.barrel(m, (x, 0.0, 4.0), h=0.9)
            for dx in (-0.6, 0.6):
                P.barrel(m, (x + dx, 0.0, 4.6), h=0.5)
        P.sign(m, (-2.2, 2.5, 1.75), "tankard", out=-0.9)
        P.lantern(m, (0.0, 2.0, 3.8))
        door_mark(m, -1.0, 3.4, 0.0)
        sign_post_mark(m, 3.6, 6.2)
    elif st == 1:
        s = scheme(1, wall=red, trim=P.WHITE)
        P.cottage(m, 7.4, 5.4, s, door_u=-1.2, roof_h=2.2)
        P.steps(m, K("stone", s["stone"]), -1.2, 3.5, 1.6, P.FLOOR[1])
        for x in (1.0, 3.0):
            P.table(m, (x, 0.0, 4.5))
            P.bench(m, (x, 0.0, 5.3), 1.4)
        P.sign(m, (-3.7, 2.6, 2.75), "tankard", out=-1.0)
        P.barrel(m, (4.3, 0.0, 2.8))
        P.lantern(m, (0.2, 2.6, 2.8))
        door_mark(m, -1.2, 4.4, 0.0)
        sign_post_mark(m, 5.0, 6.4)
    elif st == 2:
        s = scheme(2, trim=(0.55, 0.22, 0.18))
        P.framed(m, 9.0, 7.0, s, floors=2, roof_h=3.0, door_u=-1.5)
        P.terrace(m, K("stone", s["stone"]), 13.0, 5.0, y=0.02, f=6.0, cap=K("stone", (0.5, 0.48, 0.45)))
        for x in (1.2, 3.6):
            P.table(m, (x, 0.0, 5.4))
            P.bench(m, (x, 0.0, 6.2), 1.4)
            P.bench(m, (x, 0.0, 4.6), 1.4)
        P.sign(m, (-4.5, 3.4, 3.7), "tankard", out=-1.2)
        for x in (-2.6, 0.0, 2.6):
            P.lantern(m, (x, 2.6, 3.7))
        P.barrel(m, (-5.0, 0.0, 2.0))
        P.barrel(m, (-5.0, 0.0, 1.2))
        door_mark(m, -1.5, 4.2, 0.0)
        sign_post_mark(m, 6.2, 8.0)
    elif st == 3:
        s = scheme(3, wall=(0.92, 0.8, 0.62), trim=(0.55, 0.22, 0.18))
        P.stone_timber(m, 11.0, 8.0, s, door_u=-2.0)
        P.steps(m, K("stone", s["stone"]), -2.0, 4.2, 2.2, P.FLOOR[3])
        P.terrace(m, K("stone", s["stone"]), 15.0, 6.0, y=0.02, f=7.2, cap=K("stone", (0.55, 0.52, 0.47)))
        for x in (2.0, 5.0):  # a pergola with a vine over the outdoor tables
            for f in (5.0, 9.0):
                m.rod(K("wood", (0.4, 0.3, 0.2)), 0.08, (x - 1.4, 0.0, f), (x - 1.4, 2.6, f), segs=6)
                m.rod(K("wood", (0.4, 0.3, 0.2)), 0.08, (x + 1.4, 0.0, f), (x + 1.4, 2.6, f), segs=6)
            P.table(m, (x, 0.0, 7.0))
            P.bench(m, (x, 0.0, 7.8), 1.4)
            P.bench(m, (x, 0.0, 6.2), 1.4)
        for k in range(9):
            blk(m, K("wood", (0.4, 0.3, 0.2)), (6.6, 0.1, 0.12), (3.5, 2.65, 5.0 + k * 0.5))
        rnd = random.Random(5)
        for _k in range(16):
            m.ball(K("leaf", (0.24, 0.4, 0.16)), (0.5, 0.2, 0.4), (rnd.uniform(0.6, 6.4), 2.8, rnd.uniform(5.0, 9.0)), u=7, v=4)
        P.sign(m, (-5.5, 3.2, 4.0), "tankard", out=-1.2)
        door_mark(m, -2.0, 5.3, 0.0)
        sign_post_mark(m, -7.6, 9.8)
    else:
        s = scheme(4, wall=(0.93, 0.78, 0.66), trim=(0.55, 0.2, 0.16))
        P.colonial(m, 14.0, 10.0, s, floors=2, roof_h=3.4, arcade=True, door_u=-2.3)
        P.steps(m, K("stone", s["stone"]), -2.3, 7.4, 3.0, P.FLOOR[4])
        P.terrace(m, K("stone", s["stone"]), 20.0, 7.0, y=0.02, f=10.9, cap=K("stone", (0.58, 0.55, 0.5)))
        for x in (1.5, 4.5):
            P.table(m, (x, 0.0, 10.4))
            P.bench(m, (x, 0.0, 11.2), 1.4)
            P.bench(m, (x, 0.0, 9.6), 1.4)
        for k in range(5):  # strings of lanterns along the arcade
            P.lantern(m, (-6.0 + k * 3.0, 3.2, 7.2))
        P.sign(m, (7.0, 4.6, 7.4), "tankard", out=1.3)
        door_mark(m, -2.3, 7.6, 0.0)
        sign_post_mark(m, -9.6, 12.8)


def workshop(m, lv):
    st = [0, 0, 1, 2, 4][lv]
    green = (0.34, 0.45, 0.3)

    def anvil(x, f):
        P.blk(m, K("wood", (0.4, 0.3, 0.2)), (0.5, 0.55, 0.5), (x, 0.27, f))
        P.blk(m, K("metal", P.IRON), (0.62, 0.22, 0.26), (x, 0.66, f))
        m.rod(K("metal", P.IRON), 0.09, (x + 0.3, 0.66, f), (x + 0.6, 0.7, f), r2=0.02, segs=6)

    def workbench(x, f, yaw=0.0):
        blk(m, K("wood", (0.5, 0.36, 0.22)), (2.0, 0.1, 0.8), (x, 0.9, f), yaw=yaw)
        for dx in (-0.85, 0.85):
            for df in (-0.3, 0.3):
                blk(m, K("wood", (0.42, 0.3, 0.2)), (0.1, 0.9, 0.1), (x + dx, 0.45, f + df), yaw=yaw)
        blk(m, K("metal", P.IRON), (0.2, 0.15, 0.25), (x + 0.7, 1.02, f), yaw=yaw)
        m.rod(K("wood", (0.6, 0.45, 0.3)), 0.02, (x - 0.4, 0.97, f - 0.1), (x - 0.1, 0.97, f + 0.15), segs=4)

    if st == 0:  # a lean-to against a rock wall: thatch on poles, a bench, an anvil on a stump
        for x in (-2.2, 0.0, 2.2):
            m.rod(K("wood", P.DRIFT), 0.08, (x, 0.0, 1.4), (x, 2.2, 1.4), segs=6)
            m.rod(K("wood", P.DRIFT), 0.08, (x, 0.0, -1.2), (x, 2.8, -1.2), segs=6)
        m.prof(K("thatch", P.THATCH), 5.4, [(-1.7, 3.05), (1.9, 2.2), (1.9, 1.9), (-1.7, 2.75)], x=0.0, bevel=0.0)
        blk(m, K("wood", P.DRIFT), (4.6, 2.6, 0.12), (0.0, 1.3, -1.3))
        workbench(-1.0, 0.0)
        anvil(1.3, 2.0)
        P.crate(m, (2.6, 0.0, -0.4), 0.5)
        P.sign(m, (2.4, 2.2, 1.45), "hammer", out=0.8)
        door_mark(m, 0.0, 2.2, 0.0)
        sign_post_mark(m, 3.4, 3.0)
    elif st == 1:
        s = scheme(1, wall=green)
        P.cottage(m, 6.0, 5.0, s, door_u=-1.0, porch=False)
        for x in (3.2, 5.2):  # an open lean-to on its side with a bench under it
            m.rod(K("wood", (0.4, 0.3, 0.2)), 0.08, (x, 0.0, 2.2), (x, 2.4, 2.2), segs=6)
        blk(m, K("roof", s["roof"]), (2.6, 0.1, 4.8), (4.3, 2.6, 0.0), roll=-10.0)
        workbench(4.2, 0.4, yaw=90.0)
        anvil(-1.5, 3.4)
        m.rod(K("metal", P.IRON), 0.12, (2.2, 2.5, -1.0), (2.2, 5.2, -1.0), segs=8)  # the stove pipe of a small forge
        P.steps(m, K("stone", s["stone"]), -1.0, 3.3, 1.4, P.FLOOR[1])
        P.sign(m, (-3.0, 2.4, 2.55), "hammer", out=-1.0)
        door_mark(m, -1.0, 4.0, 0.0)
        sign_post_mark(m, -4.4, 5.0)
    elif st == 2:
        s = scheme(2)
        P.framed(m, 8.0, 6.4, s, floors=1, roof_h=3.2, door_u=-1.8)
        P.fh.chimney_stack(m, s, -3.0, 1.6, 7.0)  # the forge's tall stack beside the house's own chimney
        anvil(1.5, 4.6)
        workbench(-1.6, 5.2)
        P.terrace(m, K("stone", s["stone"]), 11.0, 4.4, y=0.02, f=5.4, cap=K("stone", (0.5, 0.48, 0.45)))
        P.sign(m, (4.0, 2.4, 3.4), "hammer", out=1.0)
        P.lantern(m, (0.0, 2.4, 3.45))
        door_mark(m, -1.8, 4.0, 0.0)
        sign_post_mark(m, 5.4, 7.2)
    else:  # a colonial workshop hall: three arched bays, a tall forge stack with a cap
        s = scheme(4, wall=(0.88, 0.82, 0.68), trim=(0.3, 0.38, 0.28))
        P.colonial(m, 14.0, 9.0, s, floors=1, roof_h=3.0, spots=[-4.6, 0.0, 4.6], door_u=0.0)
        P.fh.chimney_stack(m, scheme(3), -5.0, -2.0, 9.8)
        for x in (-4.6, 4.6):  # big arched cart doors either side of the door
            face = Face(m, "front", 4.5, 7.0)
            P.fblk(face, K("wood", (0.3, 0.24, 0.18)), 2.4, 2.8, 0.1, x, P.FLOOR[4] + 1.4, 0.1)
            for k in range(9):
                a0, a1 = math.pi * k / 9, math.pi * (k + 1) / 9
                face.rod(K("stone", (0.86, 0.82, 0.74)), 0.12, (x + 1.35 * math.cos(a0), P.FLOOR[4] + 2.8 + 0.7 * math.sin(a0)), (x + 1.35 * math.cos(a1), P.FLOOR[4] + 2.8 + 0.7 * math.sin(a1)), n=0.16, segs=4)
        P.terrace(m, K("stone", s["stone"]), 18.0, 5.0, y=0.02, f=7.0, cap=K("stone", (0.58, 0.55, 0.5)))
        P.steps(m, K("stone", s["stone"]), 0.0, 4.5, 3.0, P.FLOOR[4])
        anvil(-3.0, 7.0)
        workbench(3.4, 7.6)
        P.sign(m, (7.0, 3.0, 4.6), "hammer", out=1.2)
        door_mark(m, 0.0, 6.6, 0.0)
        sign_post_mark(m, 8.6, 9.0)


def storage(m, lv):
    st = [0, 0, 1, 3, 4][lv]
    barn = (0.5, 0.2, 0.16)

    def goods(x, f, n=4, seed=1):
        rnd = random.Random(seed)
        for k in range(n):
            if k % 3 == 2:
                P.barrel(m, (x + rnd.uniform(-1.0, 1.0), 0.0, f + rnd.uniform(-0.5, 0.5)))
            else:
                P.crate(m, (x + rnd.uniform(-1.2, 1.2), 0.0, f + rnd.uniform(-0.6, 0.6)), rnd.uniform(0.5, 0.75), yaw=rnd.uniform(-20, 20))

    def hoist(x, y, f):
        blk(m, K("wood", (0.35, 0.25, 0.17)), (0.18, 0.18, 1.6), (x, y, f + 0.6))
        m.lathe(K("wood", (0.4, 0.3, 0.2)), [(0.0, -0.05), (0.13, -0.05), (0.13, 0.05), (0.0, 0.05)], (x, y - 0.22, f + 1.25), segs=10, axis="x")
        m.rod(K("cloth", P.ROPE), 0.015, (x, y - 0.22, f + 1.38), (x, y - 2.6, f + 1.38), segs=4)
        m.ball(K("metal", P.IRON), (0.05, 0.08, 0.05), (x, y - 2.65, f + 1.38), u=6, v=4)

    if st == 0:  # crates under a tarred tarpaulin on poles
        for x in (-2.0, 2.0):
            for f in (-1.4, 1.4):
                m.rod(K("wood", P.DRIFT), 0.07, (x, 0.0, f), (x, 1.9, f), segs=6)
        blk(m, K("cloth", (0.3, 0.28, 0.24)), (4.6, 0.04, 3.4), (0.0, 2.0, 0.0), roll=4.0)
        goods(0.0, 0.0, 6, seed=3)
        P.rope_coil(m, (2.6, 0.0, 1.8))
        P.sign(m, (2.0, 1.9, 1.4), "barrel", out=0.8)
        door_mark(m, 0.0, 1.8, 0.0)
        sign_post_mark(m, 3.4, 3.0)
    elif st == 1:
        s = scheme(1, wall=barn)
        P.cottage(m, 6.0, 8.0, s, door_u=0.0, roof_h=2.8, porch=False, windows={"front": [], "back": [], "left": [-2.0, 2.0], "right": [-2.0, 2.0]})
        front = Face(m, "front", 4.0, 3.0)
        for side in (-1, 1):  # two wide barn doors with a Z brace
            P.fblk(front, K("wood", (0.42, 0.18, 0.14)), 1.2, 2.3, 0.08, side * 0.62, P.FLOOR[1] + 1.15, 0.1)
            front.rod(K("wood", P.WHITE), 0.04, (side * 0.15, P.FLOOR[1] + 0.2), (side * 1.1, P.FLOOR[1] + 2.1), n=0.16, segs=4)
        hoist(0.0, 5.4, 3.6)
        P.terrace(m, K("rock", (0.45, 0.4, 0.33)), 6.0, 2.0, y=P.FLOOR[1] - 0.05, f=5.0)
        goods(-2.0, 6.4, 4, seed=4)
        P.sign(m, (2.6, 2.4, 4.05), "barrel", out=1.0)
        door_mark(m, 0.0, 6.0, 0.0)
        sign_post_mark(m, 3.8, 6.8)
    elif st == 3:
        s = scheme(3, wall=(0.86, 0.84, 0.8), trim=(0.45, 0.2, 0.16))
        P.stone_timber(m, 8.0, 11.0, s, door_u=0.0, balcony=False, dormers=0, gable_front=True)
        front = Face(m, "front", 5.5, 4.0)
        P.fblk(front, K("wood", (0.33, 0.22, 0.15)), 1.8, 2.0, 0.08, 0.0, P.FLOOR[3] + P.STOREY[3] + 1.0, 0.36)  # loading door upstairs
        hoist(0.0, P.FLOOR[3] + 2 * P.STOREY[3] + 1.4, 5.8)
        P.terrace(m, K("stone", s["stone"]), 11.0, 4.4, y=0.02, f=7.8, cap=K("stone", (0.55, 0.52, 0.47)))
        goods(2.8, 8.2, 5, seed=6)
        P.sign(m, (-4.0, 3.0, 5.6), "barrel", out=-1.2)
        door_mark(m, 0.0, 8.0, 0.0)
        sign_post_mark(m, -5.6, 10.0)
    else:
        s = scheme(4, wall=(0.76, 0.72, 0.66), trim=(0.45, 0.2, 0.16))
        P.colonial(m, 12.0, 14.0, s, floors=2, roof_h=3.4, spots=[-3.8, 0.0, 3.8], door_u=0.0)
        face = Face(m, "front", 7.0, 6.0)
        for x in (-3.8, 3.8):  # arched cargo doors
            P.fblk(face, K("wood", (0.3, 0.24, 0.18)), 2.0, 2.6, 0.1, x, P.FLOOR[4] + 1.3, 0.1)
        hoist(0.0, P.FLOOR[4] + 2 * P.STOREY[4] + 0.6, 7.0)
        P.fblk(face, K("wood", (0.3, 0.24, 0.18)), 1.6, 2.2, 0.1, 0.0, P.FLOOR[4] + P.STOREY[4] + 1.3, 0.1)
        P.terrace(m, K("stone", s["stone"]), 16.0, 5.0, y=0.02, f=9.5, cap=K("stone", (0.58, 0.55, 0.5)))
        P.steps(m, K("stone", s["stone"]), 0.0, 7.0, 2.6, P.FLOOR[4])
        goods(-4.0, 10.0, 6, seed=8)
        goods(4.2, 10.4, 4, seed=9)
        P.sign(m, (6.0, 3.6, 7.05), "barrel", out=1.2)
        door_mark(m, 0.0, 9.0, 0.0)
        sign_post_mark(m, 7.6, 11.6)


def trophy_hall(m, lv):
    st = [0, 1, 2, 3, 4][lv]
    blue = (0.26, 0.34, 0.55)
    if st == 1:
        s = scheme(1, wall=blue)
        P.cottage(m, 7.0, 9.0, s, door_u=0.0, roof_h=3.2, windows={"front": [-2.3, 2.3], "left": [-2.6, 0.0, 2.6], "right": [-2.6, 0.0, 2.6]})
        P.steps(m, K("stone", s["stone"]), 0.0, 5.1, 1.8, P.FLOOR[1])
        P.sign(m, (3.5, 2.5, 4.55), "cup", out=1.0)
        door_mark(m, 0.0, 6.0, 0.0)
        sign_post_mark(m, 4.6, 6.8)
    elif st == 2:
        s = scheme(2, trim=(0.25, 0.32, 0.55))
        P.framed(m, 8.0, 11.0, s, floors=2, roof_h=3.6)
        P.terrace(m, K("stone", s["stone"]), 12.0, 4.0, y=0.02, f=7.4, cap=K("stone", (0.5, 0.48, 0.45)))
        P.sign(m, (4.0, 3.1, 5.9), "cup", out=1.1)
        for x in (-1.4, 1.4):
            P.lantern(m, (x, 2.6, 5.95))
        door_mark(m, 0.0, 6.5, 0.0)
        sign_post_mark(m, 5.6, 9.0)
    elif st == 3:
        s = scheme(3, wall=(0.84, 0.86, 0.9), trim=(0.25, 0.32, 0.55))
        P.stone_timber(m, 10.0, 12.0, s, door_u=0.0, dormers=0, gable_front=True)
        P.steps(m, K("stone", s["stone"]), 0.0, 6.3, 2.6, P.FLOOR[3])
        P.terrace(m, K("stone", s["stone"]), 14.0, 4.6, y=0.02, f=8.6, cap=K("stone", (0.55, 0.52, 0.47)))
        for x in (-5.2, 5.2):  # buttresses up the long walls
            for f in (-3.5, 0.0, 3.5):
                P.poly(m, K("stone", s["stone"]), [(x, 0.0, f - 0.35), (x, 0.0, f + 0.35), (x, 3.4, f + 0.35), (x, 3.4, f - 0.35),
                    (x + (1.0 if x > 0 else -1.0), 0.0, f - 0.35), (x + (1.0 if x > 0 else -1.0), 0.0, f + 0.35), (x + (0.2 if x > 0 else -0.2), 3.0, f + 0.35), (x + (0.2 if x > 0 else -0.2), 3.0, f - 0.35)],
                    [[0, 1, 2, 3], [4, 7, 6, 5], [0, 4, 5, 1], [1, 5, 6, 2], [2, 6, 7, 3], [3, 7, 4, 0]])
        P.sign(m, (5.0, 3.0, 6.05), "cup", out=1.2)
        door_mark(m, 0.0, 7.2, 0.0)
        sign_post_mark(m, 6.8, 10.4)
    else:  # a hall of honour: colonial walls, a temple front of six columns, a dome on a drum
        s = scheme(4, trim=(0.2, 0.28, 0.5))
        P.colonial(m, 12.0, 14.0, s, floors=1, roof_h=2.6, iron_balconies=False, spots=[-3.6, 3.6])
        top = portico(m, s, 12.0, 7.0, P.FLOOR[4], 5.0, cols=6)
        y = P.FLOOR[4] + P.STOREY[4] + 1.6
        m.lathe(K("plaster", s["wall"]), [(0.0, 0.0), (3.0, 0.0), (3.0, 2.0), (0.0, 2.0)], (0.0, y, -1.0), segs=20)
        for k in range(10):
            a = 2 * math.pi * k / 10
            blk(m, c(P.GLASS), (0.6, 1.2, 0.1), (3.02 * math.cos(a), y + 1.0, -1.0 + 3.02 * math.sin(a)), yaw=-math.degrees(a) + 90.0)
        m.lathe(K("metal", (0.45, 0.62, 0.55)), [(3.3, 0.0)] + [(3.3 * math.cos(math.pi / 2 * k / 8), 2.8 * math.sin(math.pi / 2 * k / 8)) for k in range(1, 9)], (0.0, y + 2.0, -1.0), segs=24)
        m.ball(K("metal", P.GOLD), 0.25, (0.0, y + 5.0, -1.0), u=10, v=8)
        P.steps(m, K("stone", s["stone"]), 0.0, 10.5, 9.0, P.FLOOR[4])
        P.sign(m, (6.6, 3.4, 7.1), "cup", out=1.2)
        door_mark(m, 0.0, 11.4, 0.0)
        sign_post_mark(m, 8.8, 12.0)


def gallery(m, lv):
    st = [0, 1, 3, 4][lv]
    yellow = (0.78, 0.66, 0.36)
    if st == 1:
        s = scheme(1, wall=yellow, trim=P.WHITE)
        P.cottage(m, 6.0, 7.0, s, door_u=0.0, roof_h=2.4, gable_front=True)
        for x in (-1.6, 1.6):  # skylights in the roof
            blk(m, c(P.GLASS), (1.1, 0.06, 1.4), (x * 0.9, P.FLOOR[1] + P.STOREY[1] + 1.0, 0.0), roll=-38.0 if x < 0 else 38.0)
        P.steps(m, K("stone", s["stone"]), 0.0, 3.6, 1.6, P.FLOOR[1])
        P.sign(m, (3.5, 2.5, 3.05), "frame", out=1.0)
        door_mark(m, 0.0, 4.4, 0.0)
        sign_post_mark(m, 4.8, 5.4)
    elif st == 3:
        s = scheme(3, wall=(0.95, 0.88, 0.6), trim=(0.45, 0.35, 0.15))
        P.stone_timber(m, 9.0, 9.0, s, door_u=0.0, gable_front=True, dormers=0)
        P.steps(m, K("stone", s["stone"]), 0.0, 4.8, 2.4, P.FLOOR[3])
        P.terrace(m, K("stone", s["stone"]), 14.0, 4.0, y=0.02, f=6.2, cap=K("stone", (0.55, 0.52, 0.47)))
        P.sign(m, (5.0, 3.0, 4.05), "frame", out=1.2)
        door_mark(m, 0.0, 5.2, 0.0)
        sign_post_mark(m, 6.8, 7.8)
    else:
        s = scheme(4, wall=(0.95, 0.88, 0.62), trim=(0.45, 0.35, 0.15))
        P.colonial(m, 13.0, 10.0, s, floors=2, roof_h=2.4, door_u=0.0)
        y = P.FLOOR[4] + 2 * P.STOREY[4] + 1.2
        for x in (-3.0, 3.0):  # glass lanterns lighting the galleries from above
            blk(m, K("stone", s["stone"]), (2.6, 0.3, 2.6), (x, y, 0.0))
            for side in (-1, 1):
                blk(m, c(P.GLASS), (2.2, 1.0, 0.06), (x, y + 0.65, side * 1.1))
                blk(m, c(P.GLASS), (0.06, 1.0, 2.2), (x + side * 1.1, y + 0.65, 0.0))
            P.poly(m, K("metal", (0.3, 0.32, 0.3)), [(x - 1.25, y + 1.15, -1.25), (x + 1.25, y + 1.15, -1.25), (x + 1.25, y + 1.15, 1.25), (x - 1.25, y + 1.15, 1.25), (x, y + 1.9, 0.0)],
                [[0, 1, 2, 3], [0, 4, 1], [1, 4, 2], [2, 4, 3], [3, 4, 0]])
        P.steps(m, K("stone", s["stone"]), 0.0, 5.0, 3.0, P.FLOOR[4])
        P.terrace(m, K("stone", s["stone"]), 17.0, 4.6, y=0.02, f=7.3, cap=K("stone", (0.58, 0.55, 0.5)))
        P.sign(m, (6.5, 3.6, 5.1), "frame", out=1.2)
        door_mark(m, 0.0, 6.4, 0.0)
        sign_post_mark(m, 8.6, 9.2)


def garden(m, lv):
    st = [0, 0, 2, 4][lv]
    rnd = random.Random(40 + lv)

    def rows(x0, x1, f0, f1, n, raised=False):
        for k in range(n):
            f = f0 + (f1 - f0) * (k + 0.5) / n
            if raised:
                blk(m, K("wood", (0.42, 0.3, 0.2)), (x1 - x0 + 0.2, 0.35, (f1 - f0) / n * 0.7 + 0.1), ((x0 + x1) / 2, 0.17, f))
            blk(m, K("rock", SOIL), (x1 - x0, 0.2 if not raised else 0.38, (f1 - f0) / n * 0.6), ((x0 + x1) / 2, 0.1 if not raised else 0.22, f))
            for j in range(int((x1 - x0) / 0.55)):
                x = x0 + 0.3 + j * 0.55
                kind = (k + j // 3) % 3
                col = [(0.24, 0.42, 0.16), (0.32, 0.46, 0.18), (0.2, 0.36, 0.2)][kind]
                P.plant(m, (x, 0.28 if not raised else 0.48, f), 0.17 + 0.06 * rnd.random(), col)
                if kind == 1 and rnd.random() < 0.5:
                    m.ball(K("paint", (0.85, 0.25, 0.2)), 0.05, (x + 0.05, 0.42 if not raised else 0.62, f + 0.05), u=5, v=3)

    def tree(x, f, h=3.2):
        m.rod(K("bark", (0.4, 0.3, 0.22)), 0.12, (x, 0.0, f), (x, h * 0.55, f), r2=0.08, segs=7)
        for k in range(4):
            m.ball(K("leaf", (0.22, 0.38, 0.16)), (0.9, 0.7, 0.9), (x + rnd.uniform(-0.5, 0.5), h * 0.7 + rnd.uniform(-0.2, 0.4), f + rnd.uniform(-0.5, 0.5)), u=9, v=6)
        for _k in range(6):
            m.ball(K("paint", (0.85, 0.5, 0.15)), 0.07, (x + rnd.uniform(-0.8, 0.8), h * 0.6 + rnd.uniform(0, 0.6), f + rnd.uniform(-0.8, 0.8)), u=6, v=4)

    if st == 0:  # a dug patch with a stick fence and a scarecrow
        rows(-3.0, 3.0, -2.5, 2.5, 5)
        for k in range(14):
            a = 2 * math.pi * k / 14
            m.rod(K("wood", P.DRIFT), 0.04, (4.0 * math.cos(a), 0.0, 3.4 * math.sin(a)), (4.0 * math.cos(a), 0.9 + 0.2 * rnd.random(), 3.4 * math.sin(a)), segs=4)
        m.rod(K("wood", P.DRIFT), 0.05, (0.0, 0.0, -0.2), (0.0, 2.0, -0.2), segs=5)
        m.rod(K("wood", P.DRIFT), 0.04, (-0.8, 1.55, -0.2), (0.8, 1.55, -0.2), segs=4)
        blk(m, K("cloth", (0.5, 0.35, 0.3)), (0.7, 0.7, 0.25), (0.0, 1.35, -0.2))
        m.ball(K("cloth", (0.8, 0.72, 0.5)), 0.2, (0.0, 1.95, -0.2), u=8, v=6)
        m.lathe(K("thatch", P.THATCH), [(0.0, 0.0), (0.42, 0.0), (0.18, 0.08), (0.12, 0.25), (0.0, 0.28)], (0.0, 2.05, -0.2), segs=10)
        sign_post_mark(m, 4.4, 4.0)
        door_mark(m, 0.0, 3.6, 0.0)
    elif st == 2:  # a picket fence round raised beds, two fruit trees, a well
        stone = K("stone", (0.55, 0.53, 0.5))
        rows(-4.5, 0.5, -3.5, 3.0, 4, raised=True)
        tree(3.2, -2.4)
        tree(3.4, 1.6, h=2.8)
        for side in (-1, 1):
            for k in range(26):
                x = -5.5 + k * 0.44
                m.box(K("wood", P.WHITE), (0.07, 0.9, 0.04), (x, 0.45, side * 4.6), bevel=0.0)
            blk(m, K("wood", P.WHITE), (11.4, 0.06, 0.05), (0.15, 0.7, side * 4.6))
        for side in (-1, 1):
            for k in range(21):
                f = -4.6 + k * 0.44
                if side > 0 and abs(f) < 0.8:
                    continue
                m.box(K("wood", P.WHITE), (0.04, 0.9, 0.07), (side * 5.6, 0.45, f), bevel=0.0)
        m.lathe(stone, [(0.0, 0.0), (0.8, 0.0), (0.8, 0.8), (0.62, 0.8), (0.62, 0.1), (0.0, 0.1)], (-0.2, 0.0, 4.0 - 4.8), segs=14)
        for side in (-1, 1):
            m.rod(K("wood", (0.4, 0.3, 0.2)), 0.06, (-0.2 + side * 0.7, 0.8, -0.8), (-0.2 + side * 0.7, 2.1, -0.8), segs=5)
        m.prof(K("roof", (0.44, 0.38, 0.32)), 1.6, [(-0.8 - 0.6, 2.0), (-0.8, 2.6), (-0.8 + 0.6, 2.0)], x=-0.2, bevel=0.0)
        sign_post_mark(m, 6.4, 5.6)
        door_mark(m, 5.6, 0.0, 0.0)
    else:  # a walled garden: stone walls with a gate, clipped hedges, a fountain, an arbour, flower beds, benches
        stone = K("stone", (0.6, 0.55, 0.47))
        for side in (-1, 1):
            blk(m, stone, (14.0, 1.5 - P.DEEP, 0.5), (0.0, (1.5 + P.DEEP) / 2, side * 6.0))
            if side < 0:
                blk(m, stone, (0.5, 1.5 - P.DEEP, 12.0), (-7.0, (1.5 + P.DEEP) / 2, 0.0))
            else:
                for f0, f1 in ((-6.0, -1.3), (1.3, 6.0)):
                    blk(m, stone, (0.5, 1.5 - P.DEEP, f1 - f0), (7.0, (1.5 + P.DEEP) / 2, (f0 + f1) / 2))
                for f in (-1.4, 1.4):
                    blk(m, tone(stone, 1.1), (0.7, 2.3, 0.7), (7.0, 1.15, f))
                    m.ball(tone(stone, 1.15), 0.3, (7.0, 2.55, f), u=8, v=6)
        for x, f in ((-6.75, -5.75), (-6.75, 5.75), (6.75, -5.75), (6.75, 5.75)):
            blk(m, tone(stone, 1.1), (0.7, 1.8, 0.7), (x, 0.9, f))
        blk(m, K("rock", (0.55, 0.5, 0.42)), (13.5, 0.12, 11.5), (0.0, 0.03, 0.0))
        for side in (-1, 1):  # coping along the walls
            blk(m, tone(stone, 1.15), (14.3, 0.12, 0.7), (0.0, 1.56, side * 6.0))
        for x, f, w, d in ((-4.0, -3.4, 4.5, 1.0), (-4.0, 3.4, 4.5, 1.0), (3.4, -3.4, 4.0, 1.0), (3.4, 3.4, 4.0, 1.0)):
            blk(m, K("leaf", (0.22, 0.4, 0.2)), (w, 0.9, d), (x, 0.5, f), bevel=0.0)
        m.lathe(stone, [(0.0, 0.0), (2.0, 0.0), (2.0, 0.55), (1.8, 0.55), (1.8, 0.2), (0.0, 0.2)], (0.0, 0.0, 0.0), segs=24)
        m.lathe(c((0.25, 0.42, 0.5)), [(0.0, 0.0), (1.8, 0.0), (1.8, 0.05), (0.0, 0.05)], (0.0, 0.42, 0.0), segs=24)
        m.lathe(tone(stone, 1.1), [(0.0, 0.0), (0.25, 0.0), (0.18, 0.6), (0.7, 0.75), (0.7, 0.85), (0.12, 0.9), (0.1, 1.5), (0.0, 1.6)], (0.0, 0.2, 0.0), segs=14)
        m.lathe(c((0.55, 0.75, 0.85)), [(0.0, 0.0), (0.05, 0.0), (0.28, 0.5), (0.0, 0.55)], (0.0, 1.6, 0.0), segs=10)
        for side in (-1, 1):  # flower beds along the walls
            for k in range(18):
                x = -5.8 + k * 0.6
                col = P.fh.FLOWERS[(k + side) % 4]
                P.plant(m, (x, 0.25, side * 5.3), 0.3)
                m.ball(K("paint", col), 0.09, (x, 0.48, side * 5.3), u=5, v=3)
        for k in range(5):  # the arbour over a bench at the back wall
            x = -6.0
            f = -2.0 + k * 1.0
            for side in (-1, 1):
                m.rod(K("wood", (0.42, 0.32, 0.22)), 0.06, (x + side * 0.0 + 0.3, 0.0, f), (x + 0.3, 2.4, f), segs=5)
            m.rod(K("wood", (0.42, 0.32, 0.22)), 0.05, (x - 0.3, 2.4, f), (x + 1.6, 2.4, f), segs=5)
        for _k in range(14):
            m.ball(K("leaf", (0.24, 0.4, 0.16)), (0.45, 0.2, 0.4), (rnd.uniform(-6.3, -4.6), 2.55, rnd.uniform(-2.2, 2.2)), u=7, v=4)
        P.bench(m, (-5.4, 0.0, 0.0), 2.4, yaw=90.0)
        P.bench(m, (2.6, 0.0, 0.0), 1.8, yaw=90.0)
        sign_post_mark(m, 8.6, 3.0)
        door_mark(m, 7.4, 0.0, 0.0)


def dock(m, lv):
    """Model origin = where the pier leaves the bank at the sea's level; +f runs out over the water."""
    st = [0, 0, 1, 2, 3, 4][lv]
    rnd = random.Random(70 + lv)
    if st == 0:  # crooked poles and gappy planks, a rowboat tied alongside
        L, W, y = 12.0, 2.0, 1.2
        for k in range(5):
            f = k * L / 4
            for side in (-1, 1):
                x = side * (W / 2) + rnd.uniform(-0.1, 0.1)
                m.rod(K("wood", P.DRIFT), 0.1, (x, -4.0, f), (x + rnd.uniform(-0.15, 0.15), y + 0.5 + rnd.uniform(0, 0.4), f), segs=6)
        for k in range(int(L / 0.32)):
            if rnd.random() < 0.08:
                continue
            blk(m, tone(K("wood", P.DRIFT), 0.7 + 0.35 * rnd.random()), (W + 0.2 * rnd.random(), 0.06, 0.26), (rnd.uniform(-0.05, 0.05), y, -1.5 + k * 0.32), yaw=rnd.uniform(-3, 3))
        for side in (-1, 1):
            blk(m, K("wood", tone(K("wood", P.DRIFT), 0.6)[1]), (0.12, 0.14, L + 1.5), (side * (W / 2 - 0.1), y - 0.12, L / 2 - 0.75))
        boat(m, 2.6, L * 0.6)
        P.rope_coil(m, (0.3, y + 0.03, L - 0.6), r=0.25)
        P.crate(m, (-0.4, y + 0.03, 1.0), 0.5)
        sign_post_mark(m, 2.0, -2.4)
    elif st == 1:
        L, W, y = 20.0, 3.0, 1.4
        wood = K("wood", (0.5, 0.4, 0.3))
        for k in range(6):
            f = k * L / 5
            for side in (-1, 1):
                blk(m, tone(wood, 0.75), (0.25, y + 6.0, 0.25), (side * (W / 2 - 0.1), (y - 6.0) / 2, f))
                m.lathe(tone(wood, 0.7), [(0.0, 0.0), (0.16, 0.0), (0.16, 0.5), (0.2, 0.55), (0.0, 0.6)], (side * (W / 2 - 0.15), y, f), segs=8)
        for k in range(int((L + 2) / 0.3)):
            blk(m, tone(wood, 0.85 + 0.2 * rnd.random()), (W, 0.07, 0.28), (0.0, y, -2.0 + k * 0.3))
        for k in range(8):  # a ladder down to the water
            blk(m, tone(wood, 0.8), (0.6, 0.05, 0.05), (W / 2 + 0.05, y - 0.3 - k * 0.3, L - 1.0))
        for side in (-1, 1):
            blk(m, tone(wood, 0.8), (0.06, 2.4, 0.06), (W / 2 + 0.05, y - 1.1, L - 1.0 + side * 0.3))
        m.rod(K("metal", P.IRON), 0.06, (-W / 2 + 0.2, y, L - 0.4), (-W / 2 + 0.2, y + 2.6, L - 0.4), segs=6)
        P.lantern(m, (-W / 2 + 0.2, y + 2.6, L - 0.4), hang=False)
        boat(m, -3.4, L * 0.5)
        P.crate(m, (0.6, y + 0.03, 2.0), 0.6)
        P.barrel(m, (-0.6, y + 0.03, 3.0))
        sign_post_mark(m, 2.6, -2.6)
    elif st == 2:  # a wider wharf with a T-head and a timber derrick
        L, W, y = 26.0, 4.0, 1.5
        wood = K("wood", (0.48, 0.37, 0.27))
        for k in range(8):
            f = k * L / 7
            for side in (-1, 0, 1):
                blk(m, tone(wood, 0.7), (0.3, y + 6.0, 0.3), (side * (W / 2 - 0.2), (y - 6.0) / 2, f))
        for k in range(int((L + 2) / 0.3)):
            blk(m, tone(wood, 0.85 + 0.2 * rnd.random()), (W, 0.08, 0.28), (0.0, y, -2.0 + k * 0.3))
        blk(m, wood, (14.0, 0.3, 4.0), (0.0, y - 0.1, L + 1.6))
        for x in (-6.5, -3.0, 3.0, 6.5):
            for f in (L, L + 3.4):
                blk(m, tone(wood, 0.7), (0.3, y + 6.0, 0.3), (x, (y - 6.0) / 2, f))
        for x in (-6.4, -2.0, 2.0, 6.4):
            m.lathe(K("metal", P.IRON), [(0.0, 0.0), (0.16, 0.0), (0.12, 0.4), (0.2, 0.48), (0.0, 0.52)], (x, y + 0.15, L + 3.3), segs=10)
        mx, mf = 5.0, L + 1.2  # the derrick: a mast, a boom, ropes
        m.rod(K("wood", (0.4, 0.3, 0.2)), 0.16, (mx, y, mf), (mx, y + 7.0, mf), segs=8)
        m.rod(K("wood", (0.4, 0.3, 0.2)), 0.11, (mx, y + 0.6, mf), (mx - 3.2, y + 5.4, mf + 3.0), segs=8)
        m.rod(K("cloth", P.ROPE), 0.02, (mx, y + 7.0, mf), (mx - 3.2, y + 5.4, mf + 3.0), segs=4)
        m.rod(K("cloth", P.ROPE), 0.02, (mx - 3.2, y + 5.4, mf + 3.0), (mx - 3.2, y + 2.0, mf + 3.0), segs=4)
        P.crate(m, (mx - 3.4, y + 0.15, mf + 1.6), 0.8)
        for k in range(4):
            P.crate(m, (-4.0 + k * 0.9, y + 0.15, L + 0.6), 0.7, yaw=10.0 * k)
        for f in (6.0, 16.0):
            m.rod(K("metal", P.IRON), 0.06, (-W / 2 + 0.2, y, f), (-W / 2 + 0.2, y + 2.8, f), segs=6)
            P.lantern(m, (-W / 2 + 0.2, y + 2.8, f), hang=False)
        sign_post_mark(m, 3.2, -2.8)
    elif st == 3:  # a stone mole running out, then a timber pier with a T-head
        s = scheme(3)
        stone = K("stone", s["stone"])
        y = 1.7
        blk(m, stone, (6.0, y + 6.0, 12.0), (0.0, (y - 6.0) / 2, 4.0))
        for k in range(12):
            P.blk(m, tone(stone, 0.85 + 0.25 * ((k * 7) % 5) / 5), (6.1, 0.4, 0.95), (0.0, y - 0.6 - 0.45 * (k % 3), -1.5 + k * 1.0))
        blk(m, tone(stone, 1.1), (6.3, 0.2, 12.2), (0.0, y + 0.1, 4.0))
        wood = K("wood", (0.48, 0.37, 0.27))
        for k in range(7):
            f = 10.0 + k * 3.6
            for side in (-1, 1):
                blk(m, tone(wood, 0.7), (0.3, y + 6.0, 0.3), (side * 1.8, (y - 6.0) / 2, f))
        for k in range(int(24 / 0.3)):
            blk(m, tone(wood, 0.85 + 0.2 * rnd.random()), (4.0, 0.08, 0.28), (0.0, y + 0.1, 10.0 + k * 0.3))
        blk(m, wood, (16.0, 0.3, 4.4), (0.0, y, 34.4))
        for x in (-7.2, -3.0, 3.0, 7.2):
            m.lathe(K("metal", P.IRON), [(0.0, 0.0), (0.18, 0.0), (0.13, 0.45), (0.22, 0.55), (0.0, 0.6)], (x, y + 0.15, 36.2), segs=10)
        for f in (2.0, 9.0, 20.0, 32.0):
            for side in (-1, 1):
                if f > 9.5 and side < 0:
                    continue
                m.rod(K("metal", P.IRON), 0.07, (side * 2.6 if f < 10 else 1.8, y + 0.2, f), (side * 2.6 if f < 10 else 1.8, y + 3.4, f), segs=8)
                P.lantern(m, (side * 2.6 if f < 10 else 1.8, y + 3.4, f), hang=False)
        for k in range(5):
            P.crate(m, (-2.0, y + 0.2, 3.0 + k * 0.8), 0.7, yaw=7.0 * k)
        P.barrel(m, (2.0, y + 0.2, 6.0))
        P.barrel(m, (2.0, y + 0.2, 6.8))
        sign_post_mark(m, 4.2, -2.6)
    else:  # a stone quay: granite blocks, steps down to the water, iron bollards, lamps, a harbour light at the end
        s = scheme(4)
        stone = K("stone", (0.52, 0.5, 0.47))
        y, L, W = 1.8, 36.0, 7.0
        blk(m, stone, (W, y + 7.0, L + 3.0), (0.0, (y - 7.0) / 2, L / 2 - 1.5))
        for k in range(int(L / 1.2) + 2):  # coursed blocks on its sides
            for row in range(3):
                for side in (-1, 1):
                    blk(m, tone(stone, 0.85 + 0.25 * (((k + row) * 7) % 5) / 5), (0.1, 0.55, 1.15), (side * (W / 2 + 0.03), y - 0.4 - row * 0.6, -1.5 + k * 1.2 + (0.6 if row % 2 else 0.0)))
        blk(m, tone(stone, 1.12), (W + 0.3, 0.25, L + 3.2), (0.0, y + 0.12, L / 2 - 1.5))
        for k in range(8):  # steps down to the water on the left side
            blk(m, tone(stone, 0.95), (1.4, 0.3, 3.0), (-W / 2 - 0.7 - 0.0, y - 0.3 * (k + 1) + 0.15, 10.0 + k * 0.35))
        for f in range(4, int(L), 6):
            for side in (-1, 1):
                m.lathe(K("metal", (0.18, 0.18, 0.2)), [(0.0, 0.0), (0.2, 0.0), (0.15, 0.5), (0.26, 0.62), (0.0, 0.68)], (side * (W / 2 - 0.4), y + 0.25, float(f)), segs=10)
        for f in (6.0, 18.0, 30.0):
            for side in (-1, 1):
                m.rod(K("metal", (0.15, 0.15, 0.17)), 0.08, (side * (W / 2 - 0.5), y + 0.25, f + 3.0), (side * (W / 2 - 0.5), y + 4.0, f + 3.0), segs=8)
                P.lantern(m, (side * (W / 2 - 0.5), y + 4.0, f + 3.0), hang=False)
        # the harbour light: a round tower of stone with a lantern room
        m.lathe(K("plaster", s["wall"]), [(0.0, 0.0), (1.4, 0.0), (1.1, 6.0), (0.0, 6.0)], (0.0, y + 0.25, L - 0.5), segs=16)
        for k in range(3):
            m.lathe(K("paint", (0.7, 0.2, 0.18)), [(1.36 - k * 0.1, 0.0), (1.33 - k * 0.1, 0.6), (0.0, 0.6), (0.0, 0.0)], (0.0, y + 0.5 + k * 2.0, L - 0.5), segs=16)
        m.lathe(fk.GLOW, [(0.0, 0.0), (0.8, 0.0), (0.8, 1.2), (0.0, 1.2)], (0.0, y + 6.35, L - 0.5), segs=12)
        m.lathe(K("metal", (0.2, 0.2, 0.2)), [(0.0, 0.0), (1.1, 0.0), (0.0, 1.0)], (0.0, y + 7.55, L - 0.5), segs=12)
        for k in range(6):
            P.crate(m, (2.0, y + 0.25, 2.0 + k * 0.85), 0.75, yaw=5.0 * k)
        sign_post_mark(m, 5.0, -2.6)


def boat(m, x, f):
    """A little clinker rowboat moored alongside."""
    m.loft(K("wood", (0.45, 0.32, 0.22)), [(x, 0.1, f - 1.8, 0.05, 0.05), (x, 0.0, f - 1.2, 0.5, 0.3), (x, 0.0, f, 0.65, 0.35), (x, 0.05, f + 1.3, 0.5, 0.3), (x, 0.25, f + 1.9, 0.05, 0.05)], segs=10)
    blk(m, K("wood", (0.6, 0.48, 0.32)), (1.1, 0.06, 0.25), (x, 0.32, f + 0.3))
    m.rod(K("wood", (0.5, 0.4, 0.28)), 0.03, (x - 0.3, 0.35, f - 0.8), (x + 0.9, 0.2, f + 1.2), segs=4)


def shipyard(m, lv):
    """Model origin = the plot by the slipway; +f faces the slipway."""
    st = [0, 0, 1, 2, 3, 4][lv]
    rnd = random.Random(90 + lv)

    def timber_stack(x, f, n=8, yaw=0.0):
        for k in range(n):
            m.rod(K("bark", (0.45, 0.33, 0.24)), 0.16, (x - 2.0, 0.16 + (k // 3) * 0.3, f + (k % 3) * 0.34 - 0.34), (x + 2.0, 0.16 + (k // 3) * 0.3, f + (k % 3) * 0.34 - 0.34), segs=7)

    def sawpit(x, f):
        for side in (-1, 1):
            blk(m, K("wood", (0.4, 0.3, 0.2)), (0.12, 1.0, 1.2), (x + side * 1.4, 0.5, f))
        m.rod(K("bark", (0.5, 0.38, 0.27)), 0.28, (x - 2.0, 1.25, f), (x + 2.0, 1.25, f), segs=8)
        blk(m, K("metal", (0.6, 0.6, 0.62)), (0.04, 1.4, 0.2), (x + 0.6, 1.25, f))

    if st == 0:
        for x in (-2.4, 0.0, 2.4):
            m.rod(K("wood", P.DRIFT), 0.08, (x, 0.0, 1.6), (x, 2.3, 1.6), segs=6)
            m.rod(K("wood", P.DRIFT), 0.08, (x, 0.0, -1.4), (x, 2.9, -1.4), segs=6)
        m.prof(K("thatch", P.THATCH), 5.8, [(-1.9, 3.15), (2.1, 2.3), (2.1, 2.0), (-1.9, 2.85)], x=0.0, bevel=0.0)
        blk(m, K("wood", P.DRIFT), (5.0, 2.8, 0.12), (0.0, 1.4, -1.5))
        timber_stack(0.0, 0.0, 6)
        sawpit(0.0, 4.2)
        P.sign(m, (2.6, 2.2, 1.65), "ship", out=0.8)
        sign_post_mark(m, 4.0, 3.4)
    elif st == 1:  # an open shed on posts with a shingle roof, a steam box for bending planks, timber racks
        for x in (-4.0, -1.3, 1.3, 4.0):
            for f in (-2.0, 2.0):
                m.rod(K("wood", (0.4, 0.3, 0.2)), 0.1, (x, 0.0, f), (x, 2.8, f), segs=6)
        m.prof(K("roof", (0.44, 0.38, 0.32)), 9.0, [(-2.8, 2.7), (0.0, 4.4), (2.8, 2.7), (2.8, 2.55), (0.0, 4.25), (-2.8, 2.55)], x=0.0, bevel=0.0)
        timber_stack(0.0, 0.0, 9)
        blk(m, K("wood", (0.42, 0.3, 0.2)), (3.0, 0.6, 0.6), (-3.0, 1.0, 4.6))
        m.rod(K("metal", P.IRON), 0.12, (-4.2, 0.0, 4.6), (-4.2, 2.2, 4.6), segs=8)
        sawpit(2.5, 4.6)
        P.sign(m, (4.0, 2.6, 2.0), "ship", out=1.0)
        sign_post_mark(m, 5.4, 4.2)
    elif st == 2:
        s = scheme(2)
        P.framed(m, 9.0, 7.0, s, floors=1, roof_h=3.4, door_u=-2.0)
        front = Face(m, "front", 3.5, 4.5)
        P.fblk(front, K("wood", (0.33, 0.22, 0.15)), 2.6, 2.4, 0.08, 1.8, P.FLOOR[2] + 1.2, 0.14)
        timber_stack(-1.0, 5.2, 9)
        sawpit(3.4, 5.6)
        P.sign(m, (4.5, 2.6, 3.7), "ship", out=1.1)
        sign_post_mark(m, 5.8, 6.0)
    elif st == 3:  # a mould loft: stone below with great arched doors, framed loft above
        s = scheme(3)
        P.stone_timber(m, 12.0, 8.0, s, door_u=-3.6, balcony=False)
        front = Face(m, "front", 4.0, 6.0)
        P.fblk(front, K("wood", (0.3, 0.2, 0.14)), 3.2, 2.6, 0.1, 2.4, P.FLOOR[3] + 1.3, 0.12)
        timber_stack(-1.5, 6.4, 12)
        sawpit(3.6, 6.8)
        P.terrace(m, K("stone", s["stone"]), 15.0, 5.0, y=0.02, f=6.4, cap=K("stone", (0.55, 0.52, 0.47)))
        P.sign(m, (6.0, 3.0, 4.05), "ship", out=1.2)
        sign_post_mark(m, 7.6, 7.6)
    else:  # the shipwright's hall: colonial, an arcade of stores, a timber gantry crane over the yard
        s = scheme(4)
        P.colonial(m, 15.0, 10.0, s, floors=2, roof_h=3.0, door_u=-4.0, spots=[-4.0, 0.0, 4.0])
        timber_stack(-2.0, 7.4, 15)
        for x in (-6.5, 6.5):
            m.rod(K("wood", (0.4, 0.3, 0.2)), 0.22, (x, 0.0, 9.0), (x, 7.0, 9.0), segs=8)
        blk(m, K("wood", (0.4, 0.3, 0.2)), (13.6, 0.5, 0.5), (0.0, 7.0, 9.0))
        blk(m, K("metal", P.IRON), (0.6, 0.4, 0.7), (2.0, 6.6, 9.0))
        m.rod(K("cloth", P.ROPE), 0.025, (2.0, 6.4, 9.0), (2.0, 2.0, 9.0), segs=4)
        m.ball(K("metal", P.IRON), (0.08, 0.12, 0.08), (2.0, 1.95, 9.0), u=6, v=4)
        P.terrace(m, K("stone", s["stone"]), 18.0, 6.0, y=0.02, f=8.0, cap=K("stone", (0.58, 0.55, 0.5)))
        P.steps(m, K("stone", s["stone"]), -4.0, 5.0, 2.6, P.FLOOR[4])
        P.sign(m, (7.5, 3.6, 5.1), "ship", out=1.2)
        sign_post_mark(m, 9.4, 10.6)


# --- residents' houses (sea step 7b, director: streets + houses that appear as the town grows): four kinds of
# house in every style; the game shows more of them and rebuilds them in newer styles as the town grows ---
HOUSE_KINDS = [  # width, depth, door, gable to the street, colours by style 1..4
    (6.0, 5.0, 0.0, False, [(0.78, 0.62, 0.32), (0.9, 0.82, 0.62), (0.9, 0.8, 0.58), (0.96, 0.9, 0.72)]),
    (7.5, 6.0, -1.3, False, [(0.34, 0.5, 0.42), (0.86, 0.86, 0.78), (0.86, 0.9, 0.86), (0.84, 0.92, 0.88)]),
    (5.5, 7.0, 0.0, True, [(0.62, 0.28, 0.22), (0.9, 0.8, 0.7), (0.94, 0.82, 0.74), (0.96, 0.84, 0.78)]),
    (9.0, 6.0, 1.6, False, [(0.3, 0.38, 0.55), (0.88, 0.86, 0.8), (0.84, 0.86, 0.92), (0.88, 0.9, 0.96)]),
]
SHUTTERS = [(0.2, 0.36, 0.4), (0.55, 0.22, 0.18), (0.24, 0.4, 0.26), (0.18, 0.28, 0.5)]


def house(m, kind, st):
    w, d, door, gable, colours = HOUSE_KINDS[kind]
    trim = SHUTTERS[kind]
    rnd = random.Random(kind * 10 + st)
    if st == 0:
        s = scheme(0)
        P.shack(m, w * 0.75, d * 0.75, s, door_u=door * 0.6, windows={"front": [-w * 0.25] if door >= 0 else [w * 0.25], "left": [0.0], "right": [0.0]})
        P.steps(m, K("wood", P.DRIFT), door * 0.6, d * 0.375 + 0.05, 1.1, P.FLOOR[0])
        if kind % 2 == 0:
            P.nets(m, w * 0.55, 0.0, 0.0, 2.0, 1.3, yaw=90.0)
        else:  # a rack of fish drying
            for x in (-1.0, 1.0):
                m.rod(K("wood", P.DRIFT), 0.04, (w * 0.5 + 0.6, 0.0, x), (w * 0.5 + 0.6, 1.6, x), segs=4)
            m.rod(K("wood", P.DRIFT), 0.03, (w * 0.5 + 0.6, 1.55, -1.1), (w * 0.5 + 0.6, 1.55, 1.1), segs=4)
            for k in range(6):
                m.ball(K("leather", (0.62, 0.55, 0.42)), (0.04, 0.2, 0.08), (w * 0.5 + 0.6, 1.32, -0.9 + k * 0.36), u=6, v=4)
        P.barrel(m, (-w * 0.45, 0.0, d * 0.45))
    elif st == 1:
        s = scheme(1, wall=colours[0], trim=P.WHITE)
        P.cottage(m, w, d, s, door_u=door, roof_h=1.9, gable_front=gable, porch=kind != 2)
        P.steps(m, K("stone", s["stone"]), door, d / 2 + (1.45 if kind != 2 else 0.2), 1.4, P.FLOOR[1])
        P.bench(m, (w / 2 - 1.2 if door <= 0 else -w / 2 + 1.2, 0.0, d / 2 + 0.6), 1.3)
        for k in range(2):
            m.lathe(K("paint", (0.66, 0.36, 0.24)), [(0.0, 0.0), (0.16, 0.0), (0.2, 0.3), (0.0, 0.3)], (door + (k * 2 - 1) * 1.0, 0.0, d / 2 + 0.9), segs=8)
            P.plant(m, (door + (k * 2 - 1) * 1.0, 0.42, d / 2 + 0.9), 0.2)
    elif st == 2:
        s = scheme(2, wall=colours[1], trim=trim)
        fk.house(m, s, w, d, 2 if kind in (1, 3) else 1, 2.4 if kind != 2 else 3.0, chimney=True, frame=True, door_x=door, gable_front=gable)
        blk(m, K("stone", s["stone"]), (w + 0.3, -P.DEEP, d + 0.3), (0.0, P.DEEP / 2, 0.0))
        for x in (-w / 2 - 0.4, w / 2 + 0.4):  # a washing line along the side
            m.rod(K("wood", (0.42, 0.32, 0.22)), 0.04, (x, 0.0, d / 2 + 2.2), (x, 1.9, d / 2 + 2.2), segs=4)
        m.rod(K("cloth", P.ROPE), 0.008, (-w / 2 - 0.4, 1.85, d / 2 + 2.2), (w / 2 + 0.4, 1.85, d / 2 + 2.2), segs=3)
        for k in range(4):
            col = [(0.9, 0.9, 0.86), (0.5, 0.6, 0.8), (0.85, 0.5, 0.45), (0.9, 0.85, 0.6)][(k + kind) % 4]
            blk(m, K("cloth", col), (0.5, 0.65, 0.02), (-w / 2 + 0.8 + k * (w / 4), 1.5, d / 2 + 2.2))
    elif st == 3:
        s = scheme(3, wall=colours[2], trim=trim)
        P.stone_timber(m, w, d, s, door_u=door, roof_h=2.6 if kind != 2 else 3.2, balcony=kind in (1, 3), dormers=1 if kind == 3 else 0, gable_front=gable)
        P.steps(m, K("stone", s["stone"]), door, d / 2 + 0.2, 1.8, P.FLOOR[3])
        P.lantern(m, (door + 1.1, 2.6, d / 2 + 0.25))
    else:
        s = scheme(4, wall=colours[3], trim=trim)
        P.colonial(m, w, d, s, floors=2, roof_h=2.4, door_u=door, spots=[u for u in ([-w / 2 + 1.4, 0.0, w / 2 - 1.4] if w > 7 else [-w / 2 + 1.3, w / 2 - 1.3])])
        P.steps(m, K("stone", s["stone"]), door, d / 2 + 0.25, 2.4, P.FLOOR[4])
        for k in (-1, 1):
            m.lathe(K("stone", s["stone"]), [(0.0, 0.0), (0.3, 0.0), (0.35, 0.5), (0.0, 0.5)], (door + k * 1.6, 0.0, d / 2 + 1.4), segs=10)
            P.plant(m, (door + k * 1.6, 0.75, d / 2 + 1.4), 0.32, (0.22, 0.4, 0.18))
    m.empty("Door", door, 0.0, d / 2 + 1.0)


BUILDERS = {"harbour_master": harbour_master, "tavern": tavern, "workshop": workshop, "storage": storage,
    "trophy_hall": trophy_hall, "gallery": gallery, "garden": garden, "dock": dock, "shipyard": shipyard}
RUIN = {"harbour_master": (4.6, 3.6), "tavern": (4.4, 3.4), "workshop": (4.6, 3.0), "storage": (4.4, 3.0),
    "trophy_hall": (6.0, 7.0), "gallery": (5.6, 4.6), "garden": None, "dock": None, "shipyard": (5.0, 3.0)}


def overgrown_garden(m):
    rnd = random.Random(3)
    for k in range(12):  # a broken fence, half the posts down
        a = 2 * math.pi * k / 12
        x, f = 4.0 * math.cos(a), 3.4 * math.sin(a)
        if k % 3 == 1:
            P.blk(m, K("wood", P.DRIFT), (0.06, 0.06, 1.0), (x, 0.05, f), yaw=rnd.uniform(0, 180), pitch=90.0)
        else:
            m.rod(K("wood", P.DRIFT), 0.04, (x, 0.0, f), (x + rnd.uniform(-0.2, 0.2), 0.7, f), segs=4)
    P.weeds(m, rnd, -3.5, 3.5, -3.0, 3.0, 26)
    for _k in range(3):
        fk.blob(m, K("rock", (0.5, 0.48, 0.45)), (0.4, 0.25, 0.35), (rnd.uniform(-3, 3), 0.1, rnd.uniform(-2.5, 2.5)), seed=rnd.randint(0, 99), rough=0.3, cuts=1)
    m.empty("Sign", 4.4, 0.0, 4.0)
    m.empty("Door", 0.0, 0.0, 3.6)


def ruin_of(m, building):
    size = RUIN[building]
    if building == "garden":
        overgrown_garden(m)
        return
    P.ruin(m, size[0], size[1], seed=len(building) * 7)
    m.empty("Sign", size[0] / 2 + 1.6, 0.0, size[1] / 2 + 2.0)
    m.empty("Door", 0.0, 0.0, size[1] / 2 + 1.0)


def town_sign(m):
    """The post every plot's sign hangs from: a squared post on a stone, an arm, a hanging board (the game writes the
    building's name and level on it) and a little roof to keep it dry."""
    m.lathe(K("stone", (0.55, 0.53, 0.5)), [(0.0, 0.0), (0.32, 0.0), (0.26, 0.25), (0.0, 0.28)], (0.0, -0.1, 0.0), segs=8)
    blk(m, K("wood", (0.4, 0.29, 0.19)), (0.14, 2.5, 0.14), (0.0, 1.25, 0.0))
    blk(m, K("wood", (0.4, 0.29, 0.19)), (1.3, 0.1, 0.1), (0.55, 2.3, 0.0))
    m.rod(K("wood", (0.4, 0.29, 0.19)), 0.035, (0.0, 1.9, 0.0), (0.4, 2.27, 0.0), segs=4)
    for x in (0.25, 1.05):
        m.rod(K("metal", P.IRON), 0.008, (x, 2.25, 0.0), (x, 2.08, 0.0), segs=3)
    blk(m, K("wood", (0.72, 0.6, 0.42)), (1.06, 0.6, 0.05), (0.65, 1.77, 0.0))
    blk(m, K("wood", (0.36, 0.25, 0.16)), (1.14, 0.06, 0.07), (0.65, 2.1, 0.0))
    blk(m, K("wood", (0.36, 0.25, 0.16)), (1.14, 0.06, 0.07), (0.65, 1.45, 0.0))
    m.prof(K("roof", (0.44, 0.38, 0.32)), 1.5, [(-0.28, 2.38), (0.0, 2.58), (0.28, 2.38), (0.28, 2.34), (0.0, 2.52), (-0.28, 2.34)], x=0.55, bevel=0.0)
    m.empty("Board", 0.65, 1.77, 0.0)


def levels_of(building):
    import json
    data = json.load(open(os.path.join(os.path.dirname(__file__), "..", "..", "data", "sea", "town.json")))
    for plot in data["plots"]:
        if plot["building"] == building:
            return len(plot["levels"])
    return 0


if __name__ == "__main__":
    fk.init()
    only = set(sys.argv[1:])
    made = []
    jobs = [("town_sign", town_sign)]
    for kind in range(len(HOUSE_KINDS)):
        for st in range(5):
            jobs.append(("house_%d_%d" % (kind, st), lambda m, k=kind, st=st: house(m, k, st)))
    for building, build in BUILDERS.items():
        if RUIN.get(building) is not None or building == "garden":
            jobs.append((building + "_0", lambda m, b=building: ruin_of(m, b)))
        for lv in range(1, levels_of(building) + 1):
            jobs.append(("%s_%d" % (building, lv), lambda m, b=build, lv=lv: b(m, lv)))
    for name, job in jobs:
        if only and name not in only and name.rsplit("_", 1)[0] not in only:
            continue
        m = kit.Model(name, uv_scale=0.5, colored=True)
        job(m)
        tris = m.export(OUT)
        made.append((name, tris))
        print(name, tris)
    print("TOTAL", sum(t for _n, t in made), "triangles in", len(made), "models")
