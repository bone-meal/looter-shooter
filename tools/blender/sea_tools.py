# Purpose: developer-time tool (sea step 9b): THE 7 TRAVERSAL TOOLS (LOCKED list) as held models, our own designs:
#   tl_grapple (brass launcher, reel, node "Hook" = the three-pronged hook at its muzzle),
#   tl_bell (the Fog Bell: a sea-green bronze handbell, node "Clapper"),
#   tl_gauntlet (the Ember Gauntlet: leather + bronze plates, node "Ember" = the coal-stone on its back),
#   tl_anchor (the Rime Anchor: a small frosted anchor on a chain), tl_glider (the Gale Glider: back frame with two
#   sail-cloth wings, nodes "WingL" / "WingR" pivot at the frame), tl_pearl (the Tide Pearl in a scallop clasp,
#   node "Pearl"), tl_compass (the Whorl Compass, node "Needle").
# Held at the origin (the grip); forward = kit +f (= Godot -z). Glider: worn on the back, wings along x.
# -> assets/models/sea/tools/<name>.gltf.  Run: python3 tools/blender/sea_tools.py  (ONLY=a,b)
# Dependencies: bpy, tools/blender/kit.py, fantasy_kit.py, sea_town_parts.py (blk). No game code.
import math
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
import bpy  # noqa: F401
import kit
import fantasy_kit as fk
from fantasy_kit import K
from sea_town_parts import blk

OUT = os.path.join(os.path.dirname(__file__), "..", "..", "assets", "models", "sea", "tools")
BRASS = (0.82, 0.62, 0.3)
BRONZE = (0.45, 0.62, 0.5)
LEATHER = (0.42, 0.26, 0.15)
WOOD = (0.45, 0.3, 0.17)
IRON = (0.3, 0.3, 0.33)
FROST = (0.78, 0.9, 0.98)
CLOTH = (0.9, 0.86, 0.74)
TEAL = (0.2, 0.5, 0.55)


def grapple(m):
    brass, dark = K("metal", BRASS), K("metal", IRON)
    m.cyl(brass, 0.035, 0.0, 0.32, y=0.06, segs=14)  # the barrel
    m.cyl(dark, 0.042, 0.28, 0.32, y=0.06, segs=14)
    m.lathe(dark, [(0.0, 0.0), (0.06, 0.0), (0.06, 0.05), (0.0, 0.05)], (0.0, 0.0, 0.12), segs=16, axis="x")  # the reel
    m.lathe(K("cloth", (0.75, 0.68, 0.5)), [(0.0, -0.035), (0.05, -0.035), (0.05, 0.035), (0.0, 0.035)], (0.0, 0.0, 0.12), segs=16, axis="x")
    m.box(K("wood", WOOD), (0.04, 0.13, 0.05), (0.0, -0.06, 0.02), tilt=-15.0)  # the grip
    m.box(brass, (0.012, 0.05, 0.05), (0.0, -0.01, 0.06))  # trigger guard
    m.node("Hook", (0.0, 0.06, 0.34))
    m.cyl(dark, 0.012, 0.32, 0.4, y=0.06, segs=8, node="Hook")
    for k in range(3):
        a = math.radians(k * 120)
        x, y = math.sin(a) * 0.045, 0.06 + math.cos(a) * 0.045
        m.rod(dark, 0.008, (0.0, 0.06, 0.4), (x, y, 0.43), node="Hook", segs=5)
        m.rod(dark, 0.007, (x, y, 0.43), (x * 0.8, y + (0.06 - y) * 0.2, 0.39), node="Hook", segs=5)


def bell(m):
    bronze = K("metal", BRONZE)
    m.lathe(K("wood", WOOD), [(0.0, 0.0), (0.02, 0.0), (0.024, 0.12), (0.03, 0.14), (0.0, 0.15)], (0.0, -0.02, 0.0), segs=10)
    m.lathe(bronze, [(0.0, 0.0), (0.03, 0.0), (0.04, -0.02), (0.05, -0.08), (0.075, -0.16), (0.08, -0.18), (0.0, -0.17)], (0.0, -0.02, 0.0), segs=20)
    m.lathe(K("metal", BRASS), [(0.074, 0.0), (0.084, 0.0), (0.084, 0.012), (0.074, 0.012)], (0.0, -0.21, 0.0), segs=20)
    m.node("Clapper", (0.0, -0.05, 0.0))
    m.rod(K("metal", IRON), 0.005, (0.0, -0.05, 0.0), (0.0, -0.15, 0.0), node="Clapper", segs=5)
    m.ball(K("metal", IRON), (0.016, 0.016, 0.016), (0.0, -0.16, 0.0), node="Clapper")


def gauntlet(m):
    lea, bronze = K("leather", LEATHER), K("metal", BRASS)
    m.loft(lea, [(0.0, 0.0, -0.18, 0.05, 0.045), (0.0, 0.0, -0.05, 0.055, 0.04), (0.0, 0.0, 0.05, 0.06, 0.03)], segs=12)  # the cuff and the back of the hand
    for k in range(4):  # fingers
        x = -0.035 + k * 0.023
        m.rod(lea, 0.011, (x, 0.0, 0.05), (x, -0.015, 0.13), segs=6)
    m.rod(lea, 0.012, (0.05, -0.01, 0.0), (0.075, -0.02, 0.06), segs=6)
    for k in range(3):
        m.box(bronze, (0.1, 0.012, 0.045), (0.0, 0.035 + 0.003 * k, -0.15 + k * 0.05), bevel=0.003)
    m.lathe(bronze, [(0.0, 0.0), (0.03, 0.0), (0.03, 0.012), (0.0, 0.012)], (0.0, 0.03, 0.02), segs=12)
    m.node("Ember", (0.0, 0.045, 0.02))
    m.ball(K("paint", (1.0, 0.45, 0.12)), (0.022, 0.016, 0.022), (0.0, 0.048, 0.02), node="Ember")


def anchor(m):
    ice, frost = K("ice", FROST), K("metal", (0.62, 0.72, 0.8))
    m.rod(frost, 0.013, (0.0, 0.02, 0.0), (0.0, -0.22, 0.0), segs=8)  # the shank
    m.rod(frost, 0.01, (-0.06, -0.01, 0.0), (0.06, -0.01, 0.0), segs=8)  # the stock
    m.lathe(frost, [(0.018, -0.006), (0.03, -0.006), (0.03, 0.006), (0.018, 0.006)], (0.0, 0.04, 0.0), segs=12, axis="x")  # the ring
    for side in (-1, 1):
        m.rod(frost, 0.012, (0.0, -0.22, 0.0), (side * 0.07, -0.17, 0.0), segs=6)
        m.rod(frost, 0.01, (side * 0.07, -0.17, 0.0), (side * 0.085, -0.12, 0.0), segs=6)
        m.box(frost, (0.03, 0.03, 0.01), (side * 0.088, -0.11, 0.0), bevel=0.003)
    for k in range(6):  # frost crystals clinging to it
        m.ball(ice, (0.012, 0.02, 0.012), (0.012 * (k % 2 * 2 - 1), -0.04 - k * 0.03, 0.01), u=6, v=4)
    for k in range(5):  # a short chain up from the ring
        m.lathe(K("metal", IRON), [(0.008, -0.003), (0.013, -0.003), (0.013, 0.003), (0.008, 0.003)], (0.0, 0.065 + k * 0.02, 0.0), segs=8, axis="x" if k % 2 else "y")


def glider(m):
    frame, cloth = K("wood", WOOD), K("cloth", CLOTH)
    m.box(K("leather", LEATHER), (0.32, 0.4, 0.06), (0.0, 0.0, 0.0), bevel=0.01)  # the back plate
    for side, name in ((-1, "WingL"), (1, "WingR")):
        m.node(name, (side * 0.14, 0.15, 0.0))
        m.rod(frame, 0.015, (side * 0.14, 0.15, 0.0), (side * 1.4, 0.3, 0.05), node=name, segs=6)  # the spar
        for k in range(4):  # ribs and the cloth panels between them
            t0, t1 = 0.2 + k * 0.3, 0.2 + (k + 1) * 0.3
            m.rod(frame, 0.008, (side * (0.14 + t0), 0.15 + 0.11 * t0, 0.03), (side * (0.14 + t0 * 0.9), -0.45 + 0.05 * k, 0.05), node=name, segs=5)
            blk(m, K("cloth", TEAL if k % 2 else CLOTH), (0.3, 0.55 - 0.04 * k, 0.01), (side * (0.14 + (t0 + t1) / 2 * 0.95), -0.1 + 0.06 * k, 0.04), node=name)


def pearl(m):
    shell = K("paint", (0.95, 0.75, 0.68))
    for k in range(7):  # the lower valve: ribs fanning
        a = -54 + k * 18
        r = math.radians(a)
        blk(m, shell, (0.022, 0.012, 0.11), (math.sin(r) * 0.04, -0.01, math.cos(r) * 0.04), yaw=a)
    m.lathe(K("metal", BRASS), [(0.035, -0.005), (0.045, -0.005), (0.045, 0.005), (0.035, 0.005)], (0.0, 0.0, 0.0), segs=16)
    m.node("Pearl", (0.0, 0.03, 0.0))
    m.ball(K("paint", (0.93, 0.95, 0.97)), (0.035, 0.035, 0.035), (0.0, 0.03, 0.0), node="Pearl", u=16, v=12)
    m.rod(K("leather", LEATHER), 0.004, (0.0, 0.0, -0.05), (0.0, 0.0, -0.18), segs=5)


def compass(m):
    brass = K("metal", BRASS)
    m.lathe(brass, [(0.0, 0.0), (0.06, 0.0), (0.065, 0.005), (0.065, 0.022), (0.058, 0.024), (0.0, 0.02)], (0.0, 0.0, 0.0), segs=24)
    m.lathe(K("paint", (0.92, 0.88, 0.76)), [(0.0, 0.0), (0.055, 0.0), (0.055, 0.002), (0.0, 0.002)], (0.0, 0.016, 0.0), segs=24)  # the face
    for k in range(8):  # a whorl drawn on the face
        a = k * 0.8
        r = 0.008 + k * 0.005
        blk(m, K("paint", (0.4, 0.3, 0.5)), (0.006, 0.001, 0.006), (math.cos(a) * r, 0.019, math.sin(a) * r))
    m.lathe(brass, [(0.0, 0.0), (0.01, 0.0), (0.01, 0.015), (0.0, 0.015)], (0.0, 0.0, 0.07), segs=10)  # the bow
    m.node("Needle", (0.0, 0.02, 0.0))
    m.box(K("paint", (0.75, 0.15, 0.15)), (0.006, 0.003, 0.045), (0.0, 0.021, 0.02), node="Needle", bevel=0.0)
    m.box(K("paint", (0.2, 0.2, 0.25)), (0.006, 0.003, 0.04), (0.0, 0.021, -0.02), node="Needle", bevel=0.0)


PIECES = {"tl_grapple": grapple, "tl_bell": bell, "tl_gauntlet": gauntlet, "tl_anchor": anchor, "tl_glider": glider, "tl_pearl": pearl, "tl_compass": compass}

if __name__ == "__main__":
    fk.init()
    only = [s for s in os.environ.get("ONLY", "").split(",") if s]
    os.makedirs(OUT, exist_ok=True)
    for name, build in PIECES.items():
        if only and name not in only:
            continue
        m = kit.Model(name, uv_scale=4.0, colored=True)
        build(m)
        print(name, m.export(OUT))
