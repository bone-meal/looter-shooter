# Purpose: developer-time script (polish1 D4f, item 39). Models the islands' main quest's things ("The Drowned Bell"),
# our own designs: the keeper's LOGBOOK half buried by a driftwood stump (pages: node "Pages", they flip), the BRINE JARS
# (three clay jars on a rack, roped; node "Fill" = the glowing brine inside, scaled up as the jars fill), an OLD LAMP POST
# (a crooked post with a crossarm and a hanging iron lantern: node "Lantern" swings, its glass "Glow" lights), the
# keeper's SPYGLASS on a brass tripod (node "Spin" turns the telescope toward Gull Rock), the BELL KEY (a long iron key
# with a glowing bit, forged at the Re-forge), and the DROWNED BELL on Gull Rock (a big barnacled bronze bell in a
# stone-and-timber belfry, node "Bell" swings from its top, node "Chain" = the chains and padlock that bind it, dropped
# when the key opens it). Into assets/models/fantasy/<name>.gltf. Faces +Z in the game (f < 0).
# Run: python3 tools/blender/quest_main.py [name ...]
# Dependencies: bpy, tools/blender/kit.py, tools/blender/fantasy_kit.py. Used by game/quest_things.gd.
import math
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
import kit
import fantasy_kit as fk
from fantasy_kit import K

HERE = os.path.dirname(__file__)
OUT = os.path.join(HERE, "..", "..", "assets", "models", "fantasy")
IRON = (0.2, 0.2, 0.22)
BRASS = (0.8, 0.54, 0.16)
BRONZE = (0.55, 0.36, 0.16)
VERDIGRIS = (0.3, 0.55, 0.48)
DRIFT = (0.6, 0.55, 0.47)
WOOD = (0.38, 0.27, 0.16)
LEATHER = (0.36, 0.2, 0.12)
PAPER = (0.86, 0.8, 0.64)
CLAY = (0.62, 0.38, 0.24)
STONE = (0.5, 0.49, 0.46)
ROPE = (0.7, 0.6, 0.42)


def logbook(m):
    m.loft(K("wood", DRIFT), [(0.0, -0.05, 0.25, 0.22, 0.22), (0.02, 0.25, 0.25, 0.2, 0.2), (-0.02, 0.48, 0.25, 0.17, 0.17)], segs=10, steps=1, flat=True)  # a driftwood stump
    for k in range(4):  # its roots into the sand
        a = k * math.pi / 2 + 0.4
        m.rod(K("wood", DRIFT), 0.05, (math.cos(a) * 0.15, 0.05, 0.25 + math.sin(a) * 0.15), (math.cos(a) * 0.42, -0.04, 0.25 + math.sin(a) * 0.42), r2=0.02, segs=6)
    m.box(K("stone", (0.85, 0.78, 0.6)), (0.9, 0.06, 0.7), (0.0, 0.0, -0.1), bevel=0.02)  # a mound of sand round it
    # the book lies open against the stump, tilted, covers of cracked leather with a brass clasp
    for side in (-1, 1):
        m.box(K("leather", LEATHER), (0.24, 0.025, 0.32), (side * 0.125, 0.12, -0.12), tilt=side * 4.0, bevel=0.006)
    m.box(K("leather", (0.25, 0.14, 0.08)), (0.03, 0.04, 0.32), (0.0, 0.11, -0.12), bevel=0.004)
    m.box(K("cloth", PAPER), (0.22, 0.03, 0.3), (-0.115, 0.145, -0.12), tilt=-3.0, bevel=0.003)
    for k in range(3):  # the pages that flip, standing up from the spine
        m.box(K("cloth", PAPER), (0.2, 0.004, 0.29), (0.1, 0.14 + k * 0.006, -0.12), node="Pages", tilt=8.0 + k * 6, bevel=0.0)
    m.box(K("metal", BRASS), (0.06, 0.03, 0.05), (0.25, 0.13, -0.12), bevel=0.004)
    m.box(K("paint", (0.85, 0.95, 1.0)), (0.08, 0.006, 0.06), (-0.12, 0.165, -0.05), node="Glow")  # the map on the last page, glints


def jars(m):
    wood, rope = K("wood", WOOD), K("cloth", ROPE)
    for x in (-0.85, 0.85):
        for f in (-0.22, 0.22):
            m.rod(wood, 0.04, (x, 0.0, f), (x, 0.55, f), segs=6)
    m.box(wood, (1.9, 0.07, 0.6), (0.0, 0.55, 0.0), bevel=0.01)
    m.box(wood, (1.9, 0.05, 0.08), (0.0, 0.25, 0.25), bevel=0.01)
    for i, x in enumerate((-0.58, 0.0, 0.58)):
        h = 0.62 if i != 1 else 0.72
        m.lathe(K("stone", CLAY), [(0.0, 0.0), (0.16, 0.0), (0.24, 0.12), (0.25, h * 0.5), (0.2, h * 0.82), (0.11, h * 0.9), (0.12, h), (0.0, h)], (x, 0.59, 0.0), segs=16)
        ring_y(m, rope, 0.255, 0.59 + h * 0.5, 0.015, x=x)
        ring_y(m, rope, 0.2, 0.59 + h * 0.82, 0.012, x=x)
        m.lathe(K("paint", (0.4, 1.0, 0.9)), [(0.0, 0.0), (0.105, 0.0), (0.105, 0.03), (0.0, 0.03)], (x, 0.59 + h - 0.02, 0.0), node="Glow", segs=14)  # the brine's surface
        # the brine seen through a crack down the jar's front: a glowing strip that grows (node Fill, scaled up from the bottom)
        m.box(K("paint", (0.4, 1.0, 0.9)), (0.06, h * 0.7, 0.02), (x, 0.59 + 0.06 + h * 0.35, -0.245), node="Fill", bevel=0.0)


def ring_y(m, mat, r, y, thick, segs=16, x=0.0, f=0.0, node="Body"):
    pts = [(x + math.cos(2 * math.pi * k / segs) * r, y, f + math.sin(2 * math.pi * k / segs) * r) for k in range(segs)]
    for k in range(segs):
        m.rod(mat, thick, pts[k], pts[(k + 1) % segs], node=node, segs=5)


def lamp_post(m):
    wood, iron = K("wood", (0.33, 0.24, 0.15)), K("metal", IRON)
    m.loft(wood, [(0.0, 0.0, 0.0, 0.11, 0.11), (0.04, 1.5, 0.02, 0.09, 0.09), (-0.02, 3.3, 0.0, 0.08, 0.08)], segs=8, steps=2, flat=True)  # a crooked post
    m.box(wood, (0.08, 0.1, 0.95), (0.0, 3.1, -0.38), bevel=0.01)  # the crossarm out to the front
    m.rod(wood, 0.035, (0.0, 2.7, 0.0), (0.0, 3.06, -0.5), segs=6)  # its brace
    m.rod(iron, 0.012, (0.0, 3.05, -0.78), (0.0, 2.85, -0.78), node="Lantern", segs=5)  # the hook
    # the lantern: iron cage, glass, a cap with a ring
    m.lathe(iron, [(0.0, 2.84), (0.05, 2.84), (0.14, 2.74), (0.0, 2.72)], (0.0, 0.0, -0.78), node="Lantern", segs=8)
    m.lathe(K("paint", (1.0, 0.9, 0.6)), [(0.0, 2.72), (0.1, 2.72), (0.11, 2.5), (0.0, 2.5)], (0.0, 0.0, -0.78), node="GlowLamp", segs=8)
    for k in range(4):
        a = k * math.pi / 2 + math.pi / 4
        m.rod(iron, 0.01, (math.cos(a) * 0.12, 2.73, -0.78 + math.sin(a) * 0.12), (math.cos(a) * 0.12, 2.49, -0.78 + math.sin(a) * 0.12), node="Lantern", segs=4)
    m.lathe(iron, [(0.0, 2.47), (0.13, 2.47), (0.13, 2.5), (0.0, 2.5)], (0.0, 0.0, -0.78), node="Lantern", segs=8)


def spyglass(m):
    brass, wood = K("metal", BRASS), K("wood", WOOD)
    for k in range(3):  # tripod legs
        a = k * 2 * math.pi / 3 + math.pi / 2
        m.rod(wood, 0.025, (0.0, 1.05, 0.0), (math.cos(a) * 0.45, 0.0, math.sin(a) * 0.45), segs=6)
    m.lathe(brass, [(0.0, 1.0), (0.06, 1.0), (0.06, 1.12), (0.0, 1.12)], (0, 0, 0), segs=12)
    # the telescope (turns): three drawn tubes, looking along -f
    m.loft(brass, [(0.0, 1.2, 0.3, 0.035, 0.035), (0.0, 1.2, 0.05, 0.035, 0.035)], node="Spin", segs=12, steps=1, flat=True)
    m.loft(K("leather", LEATHER), [(0.0, 1.2, 0.05, 0.048, 0.048), (0.0, 1.2, -0.25, 0.048, 0.048)], node="Spin", segs=12, steps=1, flat=True)
    m.loft(brass, [(0.0, 1.2, -0.25, 0.06, 0.06), (0.0, 1.2, -0.55, 0.065, 0.065)], node="Spin", segs=12, steps=1, flat=True)
    m.lathe(K("paint", (0.75, 0.9, 1.0)), [(0.0, 0.0), (0.055, 0.0), (0.055, 0.01), (0.0, 0.01)], (0.0, 1.2, -0.56), node="GlowLens", segs=12, axis="f")
    m.rod(brass, 0.02, (0.0, 1.12, 0.0), (0.0, 1.2, 0.0), node="Spin", segs=6)


def bell_key(m):
    iron = K("metal", (0.28, 0.27, 0.3))
    ring_y(m, iron, 0.08, 0.0, 0.018, segs=14)  # the bow, lying flat
    m.rod(iron, 0.022, (0.0, 0.0, -0.08), (0.0, 0.0, -0.5), segs=8)  # the shank
    m.box(K("paint", (0.4, 1.0, 0.9)), (0.09, 0.03, 0.12), (0.05, 0.0, -0.44), node="Glow", bevel=0.005)  # the bit, brine-blue
    m.box(iron, (0.03, 0.035, 0.03), (0.0, 0.0, -0.36), bevel=0.003)


def drowned_bell(m):
    stone, wood, bronze, iron = K("stone", STONE), K("wood", DRIFT), K("metal", BRONZE), K("metal", IRON)
    m.box(stone, (3.2, 0.5, 2.0), (0.0, 0.25, 0.0), bevel=0.06)  # a stone plinth
    for x in (-1.3, 1.3):  # two stone piers and a timber beam
        m.box(stone, (0.5, 3.4, 0.6), (x, 2.2, 0.0), bevel=0.05)
    m.box(wood, (3.3, 0.35, 0.4), (0.0, 4.05, 0.0), bevel=0.03)
    m.box(wood, (0.3, 0.25, 0.3), (0.0, 3.75, 0.0), bevel=0.02)
    # the bell (swings about its top): flared bronze, a verdigris band, barnacles, the clapper
    m.lathe(bronze, [(0.0, 3.62), (0.3, 3.62), (0.42, 3.4), (0.48, 2.95), (0.6, 2.6), (0.82, 2.38), (0.84, 2.3), (0.0, 2.3)], (0, 0, 0), node="Bell", segs=24)
    m.lathe(K("metal", VERDIGRIS), [(0.0, 2.9), (0.505, 2.9), (0.53, 2.98), (0.0, 2.98)], (0, 0, 0), node="Bell", segs=24)
    for k in range(9):
        a = k * 0.83
        y = 2.5 + (k % 3) * 0.3
        r = 0.62 - (k % 3) * 0.08
        m.ball(K("stone", (0.82, 0.8, 0.74)), 0.045, (math.cos(a) * r, y, math.sin(a) * r), node="Bell", u=6, v=4)
    m.rod(iron, 0.04, (0.0, 3.5, 0.0), (0.0, 2.35, 0.0), node="Bell", segs=6)
    m.ball(iron, 0.11, (0.0, 2.32, 0.0), node="Bell", u=8, v=6)
    # the chains that bind it shut to the piers, and the padlock on the front
    for side in (-1, 1):
        for k in range(6):
            t0, t1 = k / 6.0, (k + 1) / 6.0
            p0 = (side * (0.5 + 0.55 * t0), 2.9 - 0.9 * t0, -0.1)
            p1 = (side * (0.5 + 0.55 * t1), 2.9 - 0.9 * t1, -0.1)
            m.rod(iron, 0.025, p0, p1, node="Chain", segs=5)
    m.box(iron, (0.22, 0.24, 0.1), (0.0, 2.75, -0.55), node="Chain", bevel=0.02)
    ring_y(m, iron, 0.08, 2.9, 0.018, segs=10, f=-0.55, node="Chain")
    m.box(K("paint", (0.4, 1.0, 0.9)), (0.05, 0.08, 0.02), (0.0, 2.72, -0.61), node="GlowLock", bevel=0.0)  # the keyhole, brine-blue


MODELS = {"quest_logbook": logbook, "quest_jars": jars, "quest_lamp_post": lamp_post, "quest_spyglass": spyglass, "quest_bell_key": bell_key, "quest_drowned_bell": drowned_bell}
CHILDREN = {"quest_lamp_post": [("GlowLamp", (0.0, 3.05, -0.78), "Lantern")], "quest_drowned_bell": [("GlowLock", (0.0, 2.9, 0.0), "Chain")],
            "quest_spyglass": [("GlowLens", (0.0, 1.2, 0.0), "Spin")]}
PIVOTS = {"quest_logbook": {"Pages": (0.0, 0.14, -0.12)}, "quest_jars": {"Fill": (0.0, 0.65, 0.0)}, "quest_lamp_post": {"Lantern": (0.0, 3.05, -0.78)},
          "quest_spyglass": {"Spin": (0.0, 1.2, 0.0)}, "quest_drowned_bell": {"Bell": (0.0, 3.75, 0.0), "Chain": (0.0, 2.9, 0.0)}}


def main():
    fk.init()
    os.makedirs(OUT, exist_ok=True)
    only = sys.argv[1:]
    for name, build in MODELS.items():
        if only and name not in only:
            continue
        m = kit.Model(name, uv_scale=2.0, colored=True)
        m.node("Glow", (0.0, 0.0, 0.0))
        for pivot, at in PIVOTS.get(name, {}).items():
            m.node(pivot, at)
        for child, at, parent in CHILDREN.get(name, []):
            m.node(child, at, parent)
        build(m)
        print(name, m.export(OUT))


if __name__ == "__main__":
    main()
