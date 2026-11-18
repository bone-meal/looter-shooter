# Purpose: developer-time script. Models the sea's creatures (sea step 8c) with tools/blender/kit.py into
# assets/models/fantasy/creatures/<id>.gltf, so the game dresses them like every creature (game/fantasy_models.gd:
# each part made of something - scale, bone, leather - with its own textured material; eyes "glow").
#   sea_shark    a grey reef shark ~3.2 m: torpedo body, white belly, tall dorsal fin, pectorals, gill slits, a
#                crescent tail on node "Tail" (swishes), the lower jaw on node "Jaw" (opens to bite), rows of teeth
#   sea_serpent  our own TIDE WYRM: a long teal serpent with a gold-plated belly, a crest of fin-sails down its back,
#                a horned head with barbels, glowing sea-blue eyes and a hinged jaw ("Jaw"); its body is ten
#                separate segments "Seg1".."Seg10" (+ "Tail") that the game lays along a curve each frame
#                (game/sea_serpent.gd); in the file they lie straight out behind the head along -f.
#   sea_sunskate     region 1's SUNSKATE (sea step 8e): a giant manta ~5 m across, ink-blue back with pale spots,
#                    white belly, curled head fins, a whip tail; wings on nodes "WingL" / "WingR" (they flap).
#   sea_fogmaw       region 2's FOGMAW: a mottled moss-green eel ~7 m, a broad head with a hinged jaw ("Jaw") and a
#                    glowing lure on a stalk ("Lure"); its body is five segments "Seg1".."Seg5" behind the head
#                    (the game bends them) - only the lure shows while it lurks.
#   sea_cinder_turtle region 3's CINDER TURTLE: a ~5 m sea turtle whose basalt shell is split by glowing magma vents
#                    (node "Vents"), a beaked head ("Head") and four flippers ("FlipFL", "FlipFR", "FlipBL", "FlipBR").
# Model space: x right, y up, f forward (the game's -z). The shark's belly is at y = 0; the serpent's head centre
# is the origin (it swims at the surface, segments rise and dive).
# Run: python3 tools/blender/sea_creatures.py   (ONLY=sea_shark builds just that one)
# Dependencies: bpy, tools/blender/kit.py, tools/blender/fantasy_kit.py. No game code.
import math
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
import kit
import fantasy_kit as fk
from fantasy_kit import K

OUT = os.path.join(os.path.dirname(__file__), "..", "..", "assets", "models", "fantasy", "creatures")

SHARK_BACK = (0.4, 0.46, 0.52)
SHARK_BELLY = (0.9, 0.9, 0.86)
TOOTH = (0.96, 0.95, 0.9)
DARK = (0.03, 0.03, 0.04)
WYRM = (0.12, 0.42, 0.44)
WYRM_DARK = (0.06, 0.24, 0.28)
GOLD = (0.86, 0.66, 0.26)
SAIL = (0.86, 0.36, 0.22)
HORN = (0.88, 0.84, 0.7)


def fin(m, mat, pts, x, node="Body", t=0.04):
    """A flat fin standing in the y-f plane at x: pts [(f, y)]."""
    m.prof(mat, t, pts, x=x, bevel=0.01, node=node)


def side_fin(m, mat, root, span, back, drop, side, node="Body"):
    """A pectoral fin out to one side: a flat triangle in the x-f plane, swept back and down."""
    x, y, f = root
    import bmesh
    bm = bmesh.new()
    a = bm.verts.new((x, f + 0.16, y))
    b = bm.verts.new((x, f - 0.18, y))
    c = bm.verts.new((x + side * span, f - back, y - drop))
    a2 = bm.verts.new((x, f + 0.16, y + 0.03))
    b2 = bm.verts.new((x, f - 0.18, y + 0.03))
    c2 = bm.verts.new((x + side * span, f - back, y - drop + 0.02))
    for face in ((a, b, c), (a2, c2, b2), (a, a2, b2, b), (b, b2, c2, c), (c, c2, a2, a)):
        bm.faces.new(face)
    m._add(bm, mat, node, 0)


def shark(m):
    back, belly = K("scale", SHARK_BACK), K("scale", SHARK_BELLY)
    cy = 0.45
    body = [(-1.25, 0.09, 0.11), (-0.9, 0.2, 0.25), (-0.4, 0.31, 0.38), (0.2, 0.36, 0.42), (0.75, 0.33, 0.37), (1.2, 0.24, 0.26), (1.5, 0.11, 0.13), (1.62, 0.03, 0.04)]
    m.loft(back, [(0.0, cy + 0.02, f, rx, ry) for f, rx, ry in body], segs=16)
    m.loft(belly, [(0.0, cy - ry * 0.35, f, rx * 0.93, ry * 0.68) for f, rx, ry in body[1:-1]], segs=14)  # the white underside
    fin(m, back, [(0.35, cy + 0.38), (-0.25, cy + 0.36), (-0.32, cy + 1.05), (-0.12, cy + 0.98)], 0.0)  # dorsal
    fin(m, back, [(-0.85, cy + 0.2), (-1.05, cy + 0.18), (-1.12, cy + 0.42)], 0.0, t=0.025)  # second dorsal
    fin(m, back, [(-0.75, cy - 0.22), (-0.95, cy - 0.2), (-1.0, cy - 0.38)], 0.0, t=0.025)  # anal fin
    for side in (-1, 1):
        side_fin(m, back, (side * 0.3, cy - 0.12, 0.65), 0.75, 0.55, 0.22, side)
        for k in range(5):  # gill slits
            f = 0.98 - k * 0.07
            m.box(K("paint", DARK), (0.012, 0.2, 0.018), (side * (0.3 - k * 0.005), cy + 0.02, f), bevel=0)
        m.ball(K("paint", DARK), (0.035, 0.035, 0.03), (side * 0.2, cy + 0.12, 1.3), u=8, v=6)  # eye
    # the tail: stalk and crescent fin on its own node (it swishes side to side)
    m.node("Tail", (0.0, cy, -1.15))
    m.loft(back, [(0.0, cy + 0.02, -1.1, 0.1, 0.12), (0.0, cy + 0.02, -1.45, 0.06, 0.08)], segs=10, node="Tail")
    fin(m, back, [(-1.38, cy + 0.06), (-1.5, cy + 0.0), (-1.95, cy + 0.85), (-1.8, cy + 0.88), (-1.62, cy + 0.2)], 0.0, node="Tail", t=0.03)
    fin(m, back, [(-1.4, cy - 0.02), (-1.52, cy + 0.02), (-1.8, cy - 0.5), (-1.68, cy - 0.5)], 0.0, node="Tail", t=0.03)
    # the jaw: lower jaw hinged under the snout, teeth both rows
    m.node("Jaw", (0.0, cy - 0.12, 1.12))
    m.loft(belly, [(0.0, cy - 0.16, 1.05, 0.22, 0.07), (0.0, cy - 0.15, 1.3, 0.14, 0.05), (0.0, cy - 0.12, 1.42, 0.06, 0.03)], segs=10, node="Jaw")
    m.loft(K("leather", (0.6, 0.22, 0.24)), [(0.0, cy - 0.06, 1.1, 0.2, 0.05), (0.0, cy - 0.06, 1.35, 0.11, 0.03)], segs=10)  # mouth
    for k in range(9):
        a = math.radians(-60 + k * 15)
        x, f = math.sin(a) * 0.16, 1.24 + math.cos(a) * 0.14
        m.rod(K("bone", TOOTH), 0.012, (x, cy - 0.04, f), (x, cy - 0.1, f + 0.01), r2=0.002, segs=4)
        m.rod(K("bone", TOOTH), 0.011, (x * 0.9, cy - 0.13, f - 0.02), (x * 0.9, cy - 0.07, f - 0.01), r2=0.002, segs=4, node="Jaw")


def serpent(m):
    body, dark, gold = K("scale", WYRM), K("scale", WYRM_DARK), K("metal", GOLD)
    sail, horn = K("leather", SAIL), K("bone", HORN)
    R = 0.62
    # the head: skull, snout, brow ridges, horns, barbels, glowing eyes; the jaw hinged under it
    m.node("Head", (0.0, 0.0, 0.0))
    m.loft(body, [(0.0, 0.05, -0.6, R * 0.95, R * 0.95), (0.0, 0.12, 0.0, R * 1.05, R * 0.9), (0.0, 0.1, 0.7, R * 0.8, R * 0.6), (0.0, 0.0, 1.4, R * 0.5, R * 0.36), (0.0, -0.05, 1.8, R * 0.3, R * 0.22)], segs=16, node="Head")
    for side in (-1, 1):
        m.loft(dark, [(side * 0.32, 0.45, 0.1, 0.12, 0.08), (side * 0.36, 0.42, 0.7, 0.1, 0.06)], segs=8, node="Head")  # brow ridge
        m.ball((fk.GLOW, (0.4, 0.9, 1.0)), (0.09, 0.07, 0.1), (side * 0.42, 0.33, 0.62), u=10, v=7, node="Head")  # eye
        m.rod(horn, 0.1, (side * 0.3, 0.5, -0.2), (side * 0.75, 1.05, -1.0), r2=0.015, segs=7, node="Head")  # swept-back horns
        m.rod(horn, 0.06, (side * 0.4, 0.35, -0.1), (side * 0.85, 0.5, -0.6), r2=0.01, segs=6, node="Head")
        m.loft(gold, [(side * 0.28, -0.18, 1.55, 0.03, 0.03), (side * 0.4, -0.55, 1.4, 0.022, 0.022), (side * 0.32, -0.95, 1.2, 0.012, 0.012)], segs=6, node="Head")  # barbels
        m.prof(sail, 0.03, [(-0.4, 0.2), (0.2, 0.25), (-0.1, 0.9), (-0.7, 0.75)], x=side * 0.55, bevel=0.005, node="Head")  # gill frills
    for k in range(4):  # crest on the skull
        f = 0.3 - k * 0.32
        m.prof(sail, 0.03, [(f + 0.12, 0.55), (f - 0.15, 0.5), (f - 0.25, 1.1 - k * 0.12)], x=0.0, bevel=0.005, node="Head")
    for k in range(7):  # upper teeth
        x = -0.24 + k * 0.08
        m.rod(K("bone", TOOTH), 0.025, (x, -0.1, 1.3 + 0.1 * (1 - abs(x) * 3)), (x, -0.3, 1.32 + 0.1 * (1 - abs(x) * 3)), r2=0.004, segs=5, node="Head")
    m.node("Jaw", (0.0, -0.15, 0.3), parent="Head")
    m.loft(gold, [(0.0, -0.3, 0.2, R * 0.7, R * 0.3), (0.0, -0.3, 0.9, R * 0.55, R * 0.25), (0.0, -0.25, 1.65, R * 0.25, R * 0.14)], segs=12, node="Jaw")
    for k in range(6):
        x = -0.2 + k * 0.08
        m.rod(K("bone", TOOTH), 0.022, (x, -0.2, 1.2 + 0.1 * (1 - abs(x) * 3)), (x, -0.02, 1.22 + 0.1 * (1 - abs(x) * 3)), r2=0.004, segs=5, node="Jaw")
    # ten body segments + the tail, each its own node, laid out straight behind the head (the game bends them)
    L = 1.8
    for i in range(10):
        name = "Seg%d" % (i + 1)
        f0 = -0.6 - i * L
        r = R * (1.0 - 0.055 * i)
        m.node(name, (0.0, 0.0, f0 - L * 0.5))
        m.loft(body, [(0.0, 0.0, f0 + 0.15, r, r), (0.0, 0.0, f0 - L * 0.5, r * 1.04, r * 1.04), (0.0, 0.0, f0 - L - 0.15, r * 0.97, r * 0.97)], segs=14, node=name)
        m.loft(gold, [(0.0, -r * 0.55, f0 + 0.1, r * 0.72, r * 0.5), (0.0, -r * 0.55, f0 - L - 0.1, r * 0.7, r * 0.48)], segs=12, steps=1, node=name)  # belly plates
        for k in range(3):  # dark bands
            f = f0 - 0.3 - k * 0.6
            m.loft(dark, [(0.0, 0.0, f, r * 1.06, r * 1.06), (0.0, 0.0, f - 0.12, r * 1.06, r * 1.06)], segs=14, steps=1, flat=True, node=name)
        m.prof(sail, 0.03, [(f0 - 0.1, r * 0.9), (f0 - L + 0.1, r * 0.9), (f0 - L + 0.35, r + 0.75 - i * 0.04), (f0 - 0.4, r + 0.95 - i * 0.05)], x=0.0, bevel=0.005, node=name)  # fin-sail
        for k in range(2):
            m.rod(dark, 0.025, (0.0, r * 0.9, f0 - 0.4 - k * 0.6), (0.0, r + 0.9 - i * 0.05, f0 - 0.55 - k * 0.6), r2=0.008, segs=5, node=name)  # sail spines
    m.node("Tail", (0.0, 0.0, -0.6 - 10 * L - 0.6))
    ft = -0.6 - 10 * L
    m.loft(body, [(0.0, 0.0, ft + 0.15, R * 0.42, R * 0.42), (0.0, 0.0, ft - 1.2, R * 0.12, R * 0.12)], segs=12, node="Tail")
    m.prof(sail, 0.04, [(ft - 0.4, 0.0), (ft - 1.4, 0.05), (ft - 2.4, 1.1), (ft - 2.2, -1.0), (ft - 1.4, -0.05)], x=0.0, bevel=0.005, node="Tail")  # tail fan


SKATE_BACK = (0.1, 0.16, 0.3)
SKATE_SPOT = (0.8, 0.86, 0.9)
SKATE_BELLY = (0.92, 0.92, 0.88)
EEL = (0.24, 0.32, 0.18)
EEL_DARK = (0.1, 0.14, 0.08)
EEL_BELLY = (0.62, 0.6, 0.42)
BASALT = (0.13, 0.12, 0.12)
BASALT_LIGHT = (0.28, 0.25, 0.23)
TURTLE_SKIN = (0.32, 0.28, 0.22)
MAGMA = (1.0, 0.45, 0.08)


def sunskate(m):
    back, belly, spot = K("leather", SKATE_BACK), K("leather", SKATE_BELLY), K("paint", SKATE_SPOT)
    # the body: a wide flat diamond, back above, belly below
    m.loft(back, [(0.0, 0.25, -0.9, 0.3, 0.12), (0.0, 0.3, -0.2, 0.62, 0.2), (0.0, 0.3, 0.5, 0.58, 0.2), (0.0, 0.26, 1.05, 0.38, 0.12)], segs=16)
    m.loft(belly, [(0.0, 0.18, -0.7, 0.28, 0.08), (0.0, 0.2, 0.4, 0.52, 0.12), (0.0, 0.2, 0.95, 0.32, 0.07)], segs=14)
    for side, name in ((-1, "WingL"), (1, "WingR")):
        m.node(name, (side * 0.55, 0.28, 0.2))
        # the wing: a thin swept blade out to the tip (chord along f, thickness up)
        m.loft(back, [(side * 0.5, 0.28, 0.35, 0.75, 0.1), (side * 1.2, 0.3, 0.05, 0.55, 0.07), (side * 1.9, 0.33, -0.3, 0.32, 0.04), (side * 2.5, 0.4, -0.62, 0.1, 0.02)], segs=10, node=name)
        m.loft(belly, [(side * 0.55, 0.22, 0.3, 0.68, 0.05), (side * 1.3, 0.25, 0.0, 0.48, 0.035), (side * 2.0, 0.29, -0.32, 0.25, 0.02)], segs=10, node=name)
        for k in range(4):  # pale spots on the back
            m.ball(spot, (0.09 - k * 0.012, 0.012, 0.08 - k * 0.01), (side * (0.75 + k * 0.38), 0.37 - k * 0.002, 0.25 - k * 0.2), u=8, v=4, node=name)
        # curled head fins and the eye
        m.loft(back, [(side * 0.32, 0.28, 1.0, 0.07, 0.05), (side * 0.36, 0.25, 1.35, 0.06, 0.04), (side * 0.26, 0.18, 1.55, 0.04, 0.03)], segs=8)
        m.ball(K("paint", DARK), (0.05, 0.05, 0.05), (side * 0.36, 0.33, 0.95), u=8, v=6)
    m.loft(K("leather", (0.08, 0.06, 0.08)), [(0.0, 0.22, 1.05, 0.26, 0.04), (0.0, 0.22, 1.12, 0.22, 0.03)], segs=10, flat=True)  # the wide mouth
    m.node("Tail", (0.0, 0.26, -0.85))
    m.loft(back, [(0.0, 0.26, -0.85, 0.06, 0.05), (0.0, 0.27, -1.8, 0.03, 0.03), (0.0, 0.3, -2.9, 0.01, 0.01)], segs=6, node="Tail")


def fogmaw(m):
    skin, dark, belly = K("scale", EEL), K("scale", EEL_DARK), K("leather", EEL_BELLY)
    R = 0.42
    m.node("Head", (0.0, 0.0, 0.0))
    m.loft(skin, [(0.0, 0.0, -0.5, R, R * 0.9), (0.0, 0.08, 0.2, R * 1.2, R * 0.85), (0.0, 0.06, 0.9, R * 1.05, R * 0.6), (0.0, 0.0, 1.35, R * 0.7, R * 0.4)], segs=14, node="Head")
    for side in (-1, 1):
        m.ball((fk.GLOW, (0.85, 1.0, 0.55)), (0.06, 0.05, 0.07), (side * 0.36, 0.25, 0.85), u=8, v=6, node="Head")  # small pale eyes
        m.prof(dark, 0.02, [(-0.3, 0.1), (0.1, 0.15), (-0.1, 0.55), (-0.45, 0.4)], x=side * 0.48, bevel=0.004, node="Head")  # gill frills
    for k in range(8):  # needle teeth along the upper jaw
        x = -0.28 + k * 0.08
        m.rod(K("bone", TOOTH), 0.018, (x, -0.06, 1.0 + 0.2 * (1 - abs(x) * 3)), (x, -0.24, 1.02 + 0.2 * (1 - abs(x) * 3)), r2=0.003, segs=5, node="Head")
    m.node("Jaw", (0.0, -0.12, 0.2), parent="Head")
    m.loft(belly, [(0.0, -0.25, 0.1, R * 0.9, R * 0.3), (0.0, -0.25, 0.8, R * 0.75, R * 0.25), (0.0, -0.2, 1.3, R * 0.35, R * 0.15)], segs=12, node="Jaw")
    for k in range(7):
        x = -0.24 + k * 0.08
        m.rod(K("bone", TOOTH), 0.016, (x, -0.16, 0.95 + 0.2 * (1 - abs(x) * 3)), (x, 0.0, 0.97 + 0.2 * (1 - abs(x) * 3)), r2=0.003, segs=5, node="Jaw")
    # the lure: a stalk from the brow bent forward with a glowing bulb
    m.node("Lure", (0.0, 0.35, 0.5), parent="Head")
    m.rod(dark, 0.03, (0.0, 0.32, 0.5), (0.0, 1.1, 0.75), r2=0.02, segs=6, node="Lure")
    m.rod(dark, 0.02, (0.0, 1.1, 0.75), (0.0, 1.2, 1.25), r2=0.014, segs=6, node="Lure")
    m.ball((fk.GLOW, (0.7, 1.0, 0.6)), (0.13, 0.13, 0.13), (0.0, 1.1, 1.35), u=12, v=8, node="Lure")
    L = 1.3
    for i in range(5):
        name = "Seg%d" % (i + 1)
        f0 = -0.45 - i * L
        r = R * (1.0 - 0.13 * i)
        m.node(name, (0.0, 0.0, f0 - L * 0.5))
        m.loft(skin, [(0.0, 0.0, f0 + 0.12, r, r * 0.92), (0.0, 0.0, f0 - L * 0.5, r * 1.04, r * 0.95), (0.0, 0.0, f0 - L - 0.12, r * 0.95, r * 0.88)], segs=12, node=name)
        m.loft(belly, [(0.0, -r * 0.55, f0, r * 0.7, r * 0.4), (0.0, -r * 0.55, f0 - L, r * 0.68, r * 0.38)], segs=10, steps=1, node=name)
        for k in range(2):  # dark mottling bands
            f = f0 - 0.3 - k * 0.6
            m.ball(dark, (r * 0.6, r * 0.25, 0.2), (0.0, r * 0.75, f), u=8, v=5, node=name)
        m.prof(dark, 0.025, [(f0, r * 0.85), (f0 - L, r * 0.85), (f0 - L + 0.1, r + 0.22), (f0 - 0.1, r + 0.3)], x=0.0, bevel=0.004, node=name)  # back fin


def cinder_turtle(m):
    shell, light, skin = K("stone", BASALT), K("stone", BASALT_LIGHT), K("leather", TURTLE_SKIN)
    # the shell: a low basalt dome of plates with a rim
    m.lathe(shell, [(0.0, 1.35), (0.9, 1.25), (1.6, 0.95), (2.0, 0.55), (2.15, 0.3), (2.1, 0.15), (0.0, 0.15)], (0.0, 0.0, 0.0), segs=22, squash=1.25)
    for k in range(9):  # raised plates
        a = 2 * math.pi * k / 9
        m.ball(light, (0.55, 0.12, 0.5), (math.cos(a) * 1.1, 1.18 - 0.1, math.sin(a) * 1.35), u=8, v=5)
    m.ball(light, (0.6, 0.16, 0.7), (0.0, 1.32, 0.0), u=10, v=6)
    m.lathe(skin, [(0.0, 0.15), (1.9, 0.15), (1.95, 0.0), (0.0, -0.05)], (0.0, 0.0, 0.0), segs=20, squash=1.25)  # the belly plate
    # magma vents: glowing cracks between the plates (their own node, so the game can pulse them)
    m.node("Vents", (0.0, 1.1, 0.0))
    for k in range(9):
        a = 2 * math.pi * (k + 0.5) / 9
        x, f = math.cos(a), math.sin(a) * 1.25
        m.rod((fk.GLOW, MAGMA), 0.06, (x * 0.7, 1.24, f * 0.7), (x * 1.75, 0.72, f * 1.75), r2=0.04, segs=5, node="Vents")
    m.ball((fk.GLOW, MAGMA), (0.25, 0.1, 0.25), (0.0, 1.45, 0.0), u=10, v=5, node="Vents")
    # the head: neck, beaked skull, small eyes
    m.node("Head", (0.0, 0.45, 2.3))
    m.loft(skin, [(0.0, 0.45, 2.0, 0.42, 0.36), (0.0, 0.55, 2.7, 0.38, 0.34), (0.0, 0.6, 3.15, 0.34, 0.3), (0.0, 0.52, 3.45, 0.18, 0.16)], segs=12, node="Head")
    m.loft(K("bone", (0.3, 0.27, 0.22)), [(0.0, 0.48, 3.35, 0.16, 0.1), (0.0, 0.42, 3.6, 0.07, 0.06)], segs=8, node="Head")  # beak
    for side in (-1, 1):
        m.ball((fk.GLOW, MAGMA), (0.05, 0.05, 0.05), (side * 0.24, 0.7, 3.1), u=8, v=6, node="Head")
    # flippers: front ones long and swept, back ones short
    for name, side, f, span, chord in (("FlipFL", -1, 1.2, 2.0, 0.55), ("FlipFR", 1, 1.2, 2.0, 0.55), ("FlipBL", -1, -1.3, 1.0, 0.45), ("FlipBR", 1, -1.3, 1.0, 0.45)):
        m.node(name, (side * 1.7, 0.3, f))
        m.loft(skin, [(side * 1.6, 0.3, f, chord, 0.12), (side * (1.6 + span * 0.5), 0.25, f - 0.35, chord * 0.75, 0.09), (side * (1.6 + span), 0.2, f - 0.8, chord * 0.3, 0.05)], segs=10, node=name)


def main():
    fk.init()
    only = set(filter(None, os.environ.get("ONLY", "").split(",")))
    for name, maker in (("sea_shark", shark), ("sea_serpent", serpent), ("sea_sunskate", sunskate), ("sea_fogmaw", fogmaw), ("sea_cinder_turtle", cinder_turtle)):
        if only and name not in only:
            continue
        m = kit.Model(name, uv_scale=0.5, colored=True)
        maker(m)
        print(name, m.export(OUT))


if __name__ == "__main__":
    main()
