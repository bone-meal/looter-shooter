# Purpose: developer-time tool (sea step 13d, the friendly / odd sea events of game/sea_events.gd):
#   merchant_raft   a trader's log raft ~6 x 4 m: nine lashed logs, a plank deck, a striped awning on four poles over
#                   a counter of crates with jars, cloth bolts and a scale, barrels at the corners, a short mast with a
#                   patched sail and a coin pennant, a lantern on a pole ("Lamp" glows), a string of drying fish.
#                   The merchant (a person, game code) stands behind the counter at the "Stand" marker.
#   castaway_spar   a broken mast floating: the stump of a yard across it, a torn sail rag, rope trailing; the castaway
#                   (game code) clings at the "Cling" marker.
#   flotsam_bottle  a big green bottle lying on its side with a cork and a rolled note tied to its neck (the message in
#                   a bottle; game/sea_flotsam.gd floats it like the other cargo).
# Each floats with its waterline at y = 0. Model space: x right, y up, f forward. -> assets/models/sea/<name>.gltf
# Run: python3 tools/blender/sea_events.py
# Dependencies: bpy, tools/blender/kit.py, fantasy_kit.py, sea_town_parts.py. No game code.
import math
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
import bpy  # noqa: F401
import kit
import fantasy_kit as fk
from fantasy_kit import K
import sea_town_parts as P
from sea_town_parts import blk

OUT = os.path.join(os.path.dirname(__file__), "..", "..", "assets", "models", "sea")
LOG = (0.45, 0.33, 0.21)
LOG_DARK = (0.33, 0.24, 0.15)
PLANK = (0.55, 0.42, 0.28)
RED = (0.72, 0.2, 0.16)
CREAM = (0.9, 0.84, 0.7)
SAIL = (0.84, 0.78, 0.62)
PATCH = (0.6, 0.48, 0.3)
GLASS = (0.18, 0.42, 0.24)
CORK = (0.62, 0.45, 0.26)
PAPER = (0.9, 0.85, 0.7)
FISH = (0.62, 0.66, 0.68)


def merchant_raft(m):
    # nine logs along f, lashed
    for i in range(9):
        x = -1.9 + i * 0.475
        r = 0.2 + (i * 37 % 5) * 0.012
        m.rod(K("bark", LOG if i % 2 else LOG_DARK), r, (x, 0.04, -3.0 - (i % 3) * 0.08), (x, 0.04, 3.0 + (i % 2) * 0.1), segs=10)
    for f in (-2.4, 0.0, 2.4):
        blk(m, K("cloth", P.ROPE), (4.4, 0.06, 0.12), (0.0, 0.26, f))
    blk(m, K("wood", PLANK), (3.6, 0.06, 4.4), (0.0, 0.27, -0.2))  # the plank deck
    for k in range(8):
        blk(m, K("wood", (0.4, 0.3, 0.2)), (3.6, 0.065, 0.03), (0.0, 0.275, -2.3 + k * 0.6))
    # the counter of crates at the front, the merchant behind it
    for x in (-1.0, 0.0, 1.0):
        blk(m, K("wood", (0.52, 0.38, 0.22)), (0.9, 0.85, 0.7), (x, 0.72, 1.35), yaw=(x * 3.0))
        blk(m, K("wood", (0.38, 0.27, 0.16)), (0.94, 0.06, 0.74), (x, 0.5, 1.35))
    blk(m, K("cloth", (0.35, 0.18, 0.4)), (3.1, 0.03, 0.82), (0.0, 1.16, 1.35))  # a cloth over the counter
    for k, (x, col) in enumerate(((-1.25, (0.62, 0.36, 0.2)), (-0.95, (0.25, 0.4, 0.55)), (-0.65, (0.5, 0.52, 0.3)))):  # jars
        m.lathe(K("adobe", col), [(0.0, 0.0), (0.1, 0.0), (0.13, 0.12), (0.08, 0.26), (0.06, 0.3), (0.0, 0.3)], (x, 1.18, 1.3 + k * 0.05), segs=10)
    for k in range(3):  # bolts of cloth
        m.rod(K("cloth", [(0.8, 0.3, 0.25), (0.3, 0.5, 0.7), (0.85, 0.75, 0.4)][k]), 0.09, (0.1 + k * 0.2, 1.27, 1.05), (0.1 + k * 0.2, 1.27, 1.65), segs=10)
    m.rod(K("metal", P.GOLD), 0.015, (1.1, 1.18, 1.35), (1.1, 1.55, 1.35), segs=6)  # a brass scale
    m.rod(K("metal", P.GOLD), 0.01, (0.9, 1.55, 1.35), (1.3, 1.55, 1.35), segs=6)
    for x in (0.9, 1.3):
        m.lathe(K("metal", P.GOLD), [(0.0, 0.0), (0.08, 0.0), (0.09, 0.03), (0.0, 0.03)], (x, 1.38, 1.35), segs=10)
    # the striped awning on four poles
    for x in (-1.7, 1.7):
        for f in (0.75, 2.0):
            m.rod(K("wood", LOG_DARK), 0.045, (x, 0.3, f), (x, 2.45 + (0.25 if f < 1 else 0.0), f), segs=6)
    for k in range(7):
        x = -1.75 + k * 0.5
        col = RED if k % 2 == 0 else CREAM
        blk(m, K("cloth", col), (0.5, 0.03, 1.5), (x + 0.25, 2.58, 1.38), pitch=-9.0)
        blk(m, K("cloth", col), (0.5, 0.25, 0.02), (x + 0.25, 2.36, 2.1))  # the scalloped front drop
    # barrels at the back corners, a coil of rope
    for x, f in ((-1.45, -2.2), (1.45, -2.25), (1.35, -1.55)):
        m.lathe(K("wood", (0.42, 0.29, 0.17)), [(0.0, 0.0), (0.26, 0.0), (0.31, 0.38), (0.26, 0.76), (0.0, 0.76)], (x, 0.3, f), segs=12)
        for y in (0.42, 0.88):
            m.lathe(K("metal", P.IRON), [(0.0, 0.0), (0.3, 0.0), (0.3, 0.04), (0.0, 0.04)], (x, y, f), segs=12)
    m.lathe(K("cloth", P.ROPE), [(0.12, 0.0), (0.32, 0.0), (0.32, 0.1), (0.12, 0.1)], (-1.2, 0.3, -1.4), segs=14)
    # the mast and its patched sail, a coin pennant at the top
    m.rod(K("wood", LOG_DARK), 0.08, (0.0, 0.3, -1.2), (0.0, 5.0, -1.2), r2=0.05, segs=8)
    m.rod(K("wood", LOG_DARK), 0.05, (-1.4, 4.4, -1.15), (1.4, 4.4, -1.15), segs=6)
    for side in (-1, 1):  # the sail bellied forward in two panels, with seams and a red band
        blk(m, K("cloth", SAIL), (1.32, 2.1, 0.03), (side * 0.64, 3.3, -1.0), yaw=side * -14.0)
        for y in (2.75, 3.85):
            blk(m, K("cloth", (0.66, 0.6, 0.46)), (1.32, 0.03, 0.04), (side * 0.64, y, -0.99), yaw=side * -14.0)
        blk(m, K("cloth", RED), (1.32, 0.22, 0.04), (side * 0.64, 3.3, -0.99), yaw=side * -14.0)
    blk(m, K("cloth", PATCH), (0.55, 0.5, 0.04), (0.65, 2.75, -0.88), yaw=-14.0)
    blk(m, K("cloth", (0.7, 0.62, 0.48)), (0.45, 0.4, 0.04), (-0.7, 3.85, -0.88), yaw=14.0)
    blk(m, K("cloth", P.GOLD), (0.9, 0.3, 0.02), (0.45, 4.9, -1.2))  # the pennant
    # a lantern on a pole at the front corner (glows)
    m.rod(K("wood", LOG_DARK), 0.04, (-1.7, 2.6, 2.0), (-2.1, 2.7, 2.4), segs=6)
    m.node("Lamp", (-2.1, 2.4, 2.4))
    blk(m, K("metal", P.IRON), (0.22, 0.04, 0.22), (-2.1, 2.55, 2.4), node="Lamp")
    m.ball((fk.GLOW, (1.0, 0.75, 0.35)), (0.09, 0.12, 0.09), (-2.1, 2.42, 2.4), u=8, v=6, node="Lamp")
    blk(m, K("metal", P.IRON), (0.2, 0.04, 0.2), (-2.1, 2.29, 2.4), node="Lamp")
    # a string of drying fish under the awning's back edge
    m.rod(K("cloth", P.ROPE), 0.01, (-1.7, 2.2, 0.8), (1.7, 2.2, 0.8), segs=5)
    for k in range(6):
        x = -1.4 + k * 0.55
        m.ball(K("scale", FISH), (0.05, 0.2, 0.025), (x, 1.98, 0.8), u=8, v=6)
    m.empty("Stand", 0.0, 0.3, 0.55)


def castaway_spar(m):
    m.rod(K("bark", LOG), 0.24, (-3.2, 0.05, 0.0), (3.0, 0.05, 0.1), r2=0.18, segs=12)  # the broken mast
    for k in range(5):  # splinters at the break
        a = k * 1.25
        m.rod(K("wood", PLANK), 0.04, (3.0, 0.05 + math.sin(a) * 0.12, 0.1 + math.cos(a) * 0.12), (3.35 + k * 0.05, 0.08 + math.sin(a) * 0.15, 0.12 + math.cos(a) * 0.16), r2=0.005, segs=5)
    m.rod(K("wood", LOG_DARK), 0.09, (-1.0, 0.1, -1.4), (-1.3, 0.12, 1.6), segs=8)  # the yard's stump across it
    for f in (-1.0, 1.0):
        blk(m, K("cloth", P.ROPE), (0.08, 0.32, 0.3), (-1.0, 0.1, f * 0.25))
    blk(m, K("cloth", SAIL), (1.8, 0.03, 1.2), (-2.0, 0.22, 0.5), yaw=12.0, roll=6.0)  # a torn sail rag over it
    blk(m, K("cloth", PATCH), (0.6, 0.03, 0.5), (-2.4, 0.24, 0.9), yaw=-20.0)
    m.rod(K("cloth", P.ROPE), 0.025, (1.6, 0.1, 0.0), (2.4, -0.1, -1.6), segs=5)  # rope trailing in the water
    m.rod(K("cloth", P.ROPE), 0.025, (2.4, -0.1, -1.6), (2.0, -0.15, -2.6), segs=5)
    m.empty("Cling", 0.6, 0.0, -0.45)


def bottle(m):
    # lying along x: a fat green bottle 0.62 m, cork, a rolled note tied at the neck
    m.lathe(K("paint", GLASS), [(0.0, 0.0), (0.15, 0.0), (0.16, 0.05), (0.16, 0.38), (0.12, 0.46), (0.05, 0.52), (0.045, 0.62), (0.0, 0.62)], (-0.3, 0.0, 0.0), segs=16, axis="x")
    m.lathe(K("wood", CORK), [(0.0, 0.0), (0.042, 0.0), (0.046, 0.09), (0.0, 0.09)], (0.31, 0.0, 0.0), segs=10, axis="x")
    m.rod(K("cloth", PAPER), 0.05, (0.0, 0.0, 0.0), (0.24, 0.0, 0.0), segs=10)  # the note seen inside (the glass is dark)
    m.rod(K("cloth", PAPER), 0.035, (0.36, 0.06, -0.06), (0.36, 0.06, 0.12), segs=8)  # a second note tied outside
    m.lathe(K("cloth", (0.6, 0.18, 0.15)), [(0.05, 0.0), (0.058, 0.0), (0.058, 0.025), (0.05, 0.025)], (0.24, 0.0, 0.0), segs=10, axis="x")  # red string
    m.rod(K("cloth", (0.6, 0.18, 0.15)), 0.008, (0.25, 0.05, 0.0), (0.36, 0.06, 0.03), segs=4)


if __name__ == "__main__":
    fk.init()
    for name, job in (("merchant_raft", merchant_raft), ("castaway_spar", castaway_spar), ("flotsam_bottle", bottle)):
        mdl = kit.Model(name, uv_scale=0.5, colored=True)
        job(mdl)
        print(name, mdl.export(OUT))
