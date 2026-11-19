# Purpose: developer-time script. Models region 1's super boss ABBOT SHELLBACK (sea step 10, design approved in
# diary/DESIGN_BOSSES.md) with tools/blender/kit.py into assets/models/fantasy/creatures/sea_abbot.gltf: a colossal
# hermit crab (~9 m with its shell) that took the Tidewater Temple's drowned BELL TOWER as its shell. Our own design.
#   Body: an orange-red carapace with pale spots and purple-banded legs; the soft pale abdomen curls up into the
#   tower's foot; three pairs of walking legs ("LegL1".."LegL3", "LegR1".."LegR3", pivots at the hips); a big right
#   claw ("ClawR") and a smaller left one ("ClawL"); two eye stalks with glowing amber eyes ("EyeL", "EyeR": weak
#   points); the soft underside ("Belly": a weak point when it rears).
#   Shell ("Shell", its own node so the game can leave it standing in the pool): a barnacled sandstone bell tower
#   leaning back off the crab's back, string courses, an open belfry of four corner piers under a broken cap, the
#   great bronze BELL hanging straight down inside ("Bell") with its CLAPPER below it ("Clapper", the hook target
#   once the shell is shed), coral crusts and weed; four BARNACLE CLUSTERS on its faces ("Barnacle1".."Barnacle4",
#   bright pink-orange crust with pale cones: the breakables of phase 2).
# Model space: x right, y up, f forward (the game's -z). Feet on y = 0, the head toward +f.
# Run: python3 tools/blender/sea_boss_abbot.py
# Dependencies: bpy, tools/blender/kit.py, tools/blender/fantasy_kit.py. No game code.
import math
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
import kit
import fantasy_kit as fk
from fantasy_kit import K

OUT = os.path.join(os.path.dirname(__file__), "..", "..", "assets", "models", "fantasy", "creatures")

SHELL_RED = (0.86, 0.34, 0.18)
SHELL_DARK = (0.56, 0.18, 0.12)
SPOT = (0.95, 0.82, 0.66)
LEG_BAND = (0.42, 0.26, 0.5)
SOFT = (0.9, 0.74, 0.62)
TIP = (0.2, 0.12, 0.1)
AMBER = (1.0, 0.7, 0.2)
SAND = (0.66, 0.52, 0.36)
SAND_DARK = (0.48, 0.38, 0.27)
BRONZE = (0.62, 0.42, 0.2)
VERDI = (0.3, 0.55, 0.45)
CORAL = (0.95, 0.45, 0.42)
BARN_CRUST = (0.98, 0.52, 0.3)
BARN = (0.95, 0.93, 0.86)
WEED = (0.22, 0.34, 0.14)

TILT = 40.0  # the tower leans back this many degrees
BASE = (0.0, 1.5, -0.6)  # the tower's foot (middle of its base)
UP = (-math.sin(math.radians(TILT)), math.cos(math.radians(TILT)))  # its axis in (f, y)
FWD = (math.cos(math.radians(TILT)), math.sin(math.radians(TILT)))  # across it, toward its front face (f, y)


def tw(h, x=0.0, p=0.0):
    """A point on the tower: h along its axis, x across, p toward its front face. Returns (x, y, f)."""
    return (BASE[0] + x, BASE[1] + UP[1] * h + FWD[1] * p, BASE[2] + UP[0] * h + FWD[0] * p)


def tbox(m, mat, size, h, x=0.0, p=0.0, node="Shell"):
    """A block on the tower (size = across, along the axis, front-back), centred at (h, x, p), leaning with it."""
    m.box(mat, size, tw(h, x, p), tilt=TILT, bevel=0.03, node=node)


def leg(m, name, side, f, reach, lift, red, band, tip):
    hip = (side * 1.05, 1.25, f)
    knee = (side * (1.05 + reach * 0.5), 1.25 + lift, f + 0.25)
    foot = (side * (1.05 + reach), 0.05, f + 0.55)
    m.node(name, hip)
    m.loft(red, [(hip[0], hip[1], hip[2], 0.26, 0.26), ((hip[0] + knee[0]) / 2, (hip[1] + knee[1]) / 2 + 0.1, (hip[2] + knee[2]) / 2, 0.24, 0.24), (knee[0], knee[1], knee[2], 0.2, 0.2)], segs=10, node=name)
    m.ball(band, (0.24, 0.24, 0.24), knee, u=10, v=6, node=name)
    m.loft(red, [(knee[0], knee[1], knee[2], 0.19, 0.19), ((knee[0] + foot[0]) / 2, (knee[1] + foot[1]) / 2, (knee[2] + foot[2]) / 2, 0.15, 0.15), (foot[0], foot[1] + 0.25, foot[2], 0.08, 0.08)], segs=10, node=name)
    for k in (0.3, 0.62):  # purple bands down the shin
        p = tuple(knee[i] + (foot[i] - knee[i]) * k for i in range(3))
        m.ball(band, (0.16, 0.12, 0.16), p, u=10, v=5, node=name)
    m.rod(tip, 0.07, (foot[0], foot[1] + 0.25, foot[2]), foot, r2=0.015, segs=6, node=name)


def claw(m, name, side, size, red, dark, spot, tip):
    s = size
    # folded in front of the face (a hermit crab's guard): out and up to the elbow, the wrist back in before the mouth
    shoulder = (side * 1.15, 1.45, 2.3)
    elbow = (side * (1.25 + 1.0 * s), 1.7 + 0.3 * s, 2.6 + 0.3 * s)
    wrist = (side * (0.55 + 0.45 * s), 1.45 + 0.2 * s, 3.2 + 0.45 * s)
    m.node(name, shoulder)
    m.loft(red, [(shoulder[0], shoulder[1], shoulder[2], 0.32 * s, 0.32 * s), (elbow[0], elbow[1], elbow[2], 0.36 * s, 0.34 * s)], segs=12, node=name)
    m.loft(red, [(elbow[0], elbow[1], elbow[2], 0.36 * s, 0.34 * s), (wrist[0], wrist[1], wrist[2], 0.42 * s, 0.38 * s)], segs=12, node=name)
    palm = (wrist[0] - side * 0.15 * s, wrist[1], wrist[2] + 0.7 * s)
    m.loft(red, [(wrist[0], wrist[1], wrist[2], 0.45 * s, 0.4 * s), (palm[0], palm[1] + 0.05, palm[2], 0.62 * s, 0.5 * s), (palm[0], palm[1], palm[2] + 0.55 * s, 0.5 * s, 0.4 * s)], segs=14, node=name)
    for k in range(5):  # pale knobbles on the palm
        m.ball(spot, (0.09 * s, 0.07 * s, 0.09 * s), (palm[0] + side * (0.1 - 0.06 * k) * s, palm[1] + 0.42 * s, palm[2] - 0.25 * s + 0.15 * k * s), u=8, v=5, node=name)
    # fixed finger (outer) and the moving finger (inner, slightly open)
    m.loft(dark, [(palm[0] + side * 0.12 * s, palm[1] - 0.1 * s, palm[2] + 0.5 * s, 0.24 * s, 0.2 * s), (palm[0] + side * 0.16 * s, palm[1] - 0.18 * s, palm[2] + 1.15 * s, 0.13 * s, 0.11 * s), (palm[0] + side * 0.05 * s, palm[1] - 0.12 * s, palm[2] + 1.55 * s, 0.05 * s, 0.05 * s)], segs=10, node=name)
    m.loft(dark, [(palm[0] - side * 0.1 * s, palm[1] + 0.12 * s, palm[2] + 0.45 * s, 0.22 * s, 0.18 * s), (palm[0] - side * 0.12 * s, palm[1] + 0.28 * s, palm[2] + 1.05 * s, 0.12 * s, 0.1 * s), (palm[0] - side * 0.02 * s, palm[1] + 0.22 * s, palm[2] + 1.45 * s, 0.05 * s, 0.05 * s)], segs=10, node=name)
    for k in range(4):  # teeth along the bite
        m.ball(tip, (0.05 * s, 0.05 * s, 0.07 * s), (palm[0], palm[1] + 0.02 * s, palm[2] + 0.6 * s + 0.2 * k * s), u=6, v=4, node=name)


def barnacles(m, name, h, x, p, crust, cone, seed):
    import random
    rnd = random.Random(seed)
    at = tw(h, x, p)
    if x != 0.0:  # outward from the face it sits on: across (x) or toward the front / back face (along FWD)
        n, t1, t2 = (1.0 if x > 0 else -1.0, 0.0, 0.0), (0.0, UP[1], UP[0]), (0.0, FWD[1], FWD[0])
    else:
        sgn = 1.0 if p > 0 else -1.0
        n, t1, t2 = (0.0, FWD[1] * sgn, FWD[0] * sgn), (0.0, UP[1], UP[0]), (1.0, 0.0, 0.0)
    m.node(name, at, parent="Shell")
    fk.blob(m, crust, (0.8, 0.8, 0.8), at, seed=seed, rough=0.22, node=name, cuts=2)
    for k in range(13):
        a = rnd.uniform(0.0, 2 * math.pi)
        r = rnd.uniform(0.0, 0.55)
        base = tuple(at[i] + n[i] * 0.55 + (t1[i] * math.cos(a) + t2[i] * math.sin(a)) * r for i in range(3))
        length = rnd.uniform(0.2, 0.32)
        top = tuple(base[i] + n[i] * length for i in range(3))
        m.rod(cone, rnd.uniform(0.11, 0.16), base, top, r2=0.05, segs=8, node=name)
        m.ball(K("paint", (0.12, 0.1, 0.08)), (0.04, 0.04, 0.04), top, u=6, v=4, node=name)


def abbot(m):
    red, dark, spot = K("scale", SHELL_RED), K("scale", SHELL_DARK), K("scale", SPOT)
    band, soft, tip = K("scale", LEG_BAND), K("leather", SOFT), K("bone", TIP)
    sand, sand_dark = K("sandstone", SAND), K("sandstone", SAND_DARK)
    bronze, verdi = K("metal", BRONZE), K("metal", VERDI)
    coral, weed = K("rock", CORAL), K("leaf", WEED)
    # --- the crab ---
    # carapace: a broad shield over the front body, ridged, with pale spots
    m.loft(red, [(0.0, 1.5, 0.5, 1.0, 0.7), (0.0, 1.75, 1.4, 1.35, 0.85), (0.0, 1.8, 2.3, 1.25, 0.8), (0.0, 1.6, 3.0, 0.8, 0.55), (0.0, 1.45, 3.25, 0.4, 0.3)], segs=16)
    m.loft(dark, [(0.0, 2.35, 0.8, 0.5, 0.2), (0.0, 2.55, 1.8, 0.7, 0.22), (0.0, 2.3, 2.8, 0.4, 0.15)], segs=12)  # the ridge
    for k in range(12):
        a = 2 * math.pi * k / 12
        m.ball(spot, (0.16, 0.06, 0.16), (math.cos(a) * 0.95, 2.05 + 0.25 * math.sin(a * 2), 1.8 + math.sin(a) * 0.9), u=8, v=4)
    # the soft underside (a weak point when it rears)
    m.node("Belly", (0.0, 0.95, 2.0))
    m.loft(soft, [(0.0, 1.0, 0.8, 0.85, 0.4), (0.0, 0.95, 1.9, 1.0, 0.45), (0.0, 1.05, 2.8, 0.6, 0.35)], segs=14, node="Belly")
    # the soft abdomen curling up into the tower's foot
    m.loft(soft, [(0.0, 1.45, 0.4, 0.95, 0.75), (0.0, 1.55, -0.2, 1.1, 0.85), tuple(list(tw(0.4)) + [1.2, 1.0])], segs=14)
    # mouthparts and antennae
    for side in (-1, 1):
        m.loft(dark, [(side * 0.25, 1.3, 3.2, 0.12, 0.1), (side * 0.3, 1.05, 3.55, 0.08, 0.07)], segs=8)
        m.rod(dark, 0.05, (side * 0.3, 1.7, 3.15), (side * 1.4, 3.3, 5.6), r2=0.015, segs=6)
        m.rod(dark, 0.04, (side * 0.18, 1.6, 3.2), (side * 0.7, 2.4, 4.4), r2=0.012, segs=6)
    # eye stalks with glowing amber eyes (weak points)
    for name, side in (("EyeL", -1), ("EyeR", 1)):
        base = (side * 0.42, 1.95, 2.95)
        top = (side * 0.62, 3.0, 3.25)
        m.node(name, top)
        m.rod(red, 0.12, base, top, r2=0.1, segs=10, node=name)
        m.ball(dark, (0.2, 0.18, 0.2), top, u=12, v=8, node=name)
        m.ball((fk.GLOW, AMBER), (0.22, 0.2, 0.2), (top[0], top[1] + 0.06, top[2] + 0.1), u=14, v=10, node=name)
        m.ball(K("paint", (0.05, 0.03, 0.02)), (0.05, 0.12, 0.04), (top[0], top[1] + 0.06, top[2] + 0.29), u=8, v=6, node=name)
    claw(m, "ClawR", 1, 1.2, red, dark, spot, tip)
    claw(m, "ClawL", -1, 0.85, red, dark, spot, tip)
    for i, f in enumerate((1.9, 1.1, 0.35)):
        reach = 2.4 - 0.2 * i
        leg(m, "LegL%d" % (i + 1), -1, f, reach, 1.0, red, band, tip)
        leg(m, "LegR%d" % (i + 1), 1, f, reach, 1.0, red, band, tip)
    # --- the bell tower shell ---
    m.node("Shell", BASE)
    tbox(m, sand, (3.0, 4.0, 3.0), 2.0)  # the shaft
    tbox(m, sand_dark, (3.3, 0.3, 3.3), 0.15)  # plinth course at the foot
    tbox(m, sand_dark, (3.25, 0.25, 3.25), 4.05)  # string course under the belfry
    for k in range(4):  # coursing lines on the shaft
        tbox(m, sand_dark, (3.04, 0.06, 3.04), 0.8 + k * 0.85)
    for sx in (-1, 1):  # belfry piers at the four corners
        for sp in (-1, 1):
            tbox(m, sand, (0.6, 1.85, 0.6), 5.1, x=sx * 1.2, p=sp * 1.2)
    tbox(m, sand_dark, (3.2, 0.3, 3.2), 6.15)  # the cap (one corner broken off)
    tbox(m, sand, (2.2, 0.5, 2.2), 6.55, x=-0.35, p=0.3)
    tbox(m, sand, (1.0, 0.7, 0.9), 6.9, x=-0.6, p=0.6)
    # arch heads over each belfry opening
    for p in (-1.38, 1.38):
        tbox(m, sand_dark, (1.9, 0.35, 0.3), 5.85, p=p)
    for x in (-1.38, 1.38):
        tbox(m, sand_dark, (0.3, 0.35, 1.9), 5.85, x=x)
    # the great bell hanging straight down from the cap (gravity, not the tower's lean)
    hang = tw(5.95)
    m.node("Bell", hang, parent="Shell")
    m.rod(K("metal", (0.22, 0.2, 0.18)), 0.07, hang, (hang[0], hang[1] - 0.25, hang[2]), segs=8, node="Bell")
    m.lathe(bronze, [(0.0, -0.25), (0.28, -0.28), (0.42, -0.45), (0.5, -0.8), (0.6, -1.2), (0.78, -1.45), (0.8, -1.55), (0.66, -1.5), (0.5, -1.2), (0.38, -0.5), (0.0, -0.45)], (hang[0], hang[1], hang[2]), segs=20, node="Bell")
    m.lathe(verdi, [(0.62, -1.18), (0.66, -1.24), (0.64, -1.3), (0.6, -1.26)], (hang[0], hang[1], hang[2]), segs=20, node="Bell")  # verdigris band
    m.node("Clapper", (hang[0], hang[1] - 0.45, hang[2]), parent="Bell")
    m.rod(K("metal", (0.25, 0.22, 0.2)), 0.06, (hang[0], hang[1] - 0.45, hang[2]), (hang[0], hang[1] - 1.75, hang[2]), segs=8, node="Clapper")
    m.ball(K("metal", (0.3, 0.27, 0.24)), (0.18, 0.2, 0.18), (hang[0], hang[1] - 1.8, hang[2]), u=10, v=8, node="Clapper")
    m.lathe(bronze, [(0.0, -2.0), (0.16, -2.02), (0.2, -2.08), (0.16, -2.14), (0.0, -2.16)], (hang[0], hang[1], hang[2]), segs=12, node="Clapper")  # a ring on the clapper's end
    # coral crusts and weed on the tower
    for k, (h, x, p) in enumerate(((0.8, 1.5, 0.6), (1.6, -1.52, -0.4), (2.9, 0.4, -1.52), (3.4, 1.52, -0.9), (0.6, -0.6, 1.52), (2.2, 0.8, 1.52))):
        fk.blob(m, coral, (0.35, 0.3, 0.35), tw(h, x, p), seed=40 + k, rough=0.3, node="Shell", cuts=1)
    for k in range(10):
        h = 1.0 + 0.45 * k
        x = (-1.0 + 0.22 * k) if k % 2 else 1.4
        top = tw(h, x, 1.55)
        m.rod(weed, 0.05, top, (top[0] + 0.05, top[1] - 0.9 - 0.1 * (k % 3), top[2] + 0.15), r2=0.02, segs=5, node="Shell")
    # the four barnacle clusters (breakables)
    barnacles(m, "Barnacle1", 1.6, 1.62, 0.2, K("rock", BARN_CRUST), K("bone", BARN), 11)
    barnacles(m, "Barnacle2", 2.4, -1.62, 0.0, K("rock", BARN_CRUST), K("bone", BARN), 12)
    barnacles(m, "Barnacle3", 3.1, 0.0, 1.62, K("rock", BARN_CRUST), K("bone", BARN), 13)
    barnacles(m, "Barnacle4", 1.2, 0.0, -1.62, K("rock", BARN_CRUST), K("bone", BARN), 14)


def bell_clapper_trophy(m):
    """The trophy hall's piece for Abbot Shellback (assets/models/fantasy/trophy_bell_clapper.gltf, ~0.55 m): the
    great bell's iron clapper hung in a little bronze bell under a brass yoke on a dark wood stand, a barnacle crust
    and the tip of his claw laid at its foot."""
    wood, brass, bronze = K("wood", (0.24, 0.15, 0.09)), K("metal", (0.8, 0.62, 0.3)), K("metal", BRONZE)
    iron, verdi = K("metal", (0.25, 0.23, 0.22)), K("metal", VERDI)
    m.box(wood, (0.42, 0.06, 0.3), (0.0, 0.03, 0.0), bevel=0.01)
    m.box(wood, (0.36, 0.03, 0.24), (0.0, 0.075, 0.0), bevel=0.008)
    for x in (-0.15, 0.15):
        m.rod(brass, 0.014, (x, 0.08, 0.0), (x, 0.5, 0.0), segs=10)
        m.ball(brass, 0.024, (x, 0.51, 0.0), u=10, v=6)
    m.rod(brass, 0.016, (-0.16, 0.48, 0.0), (0.16, 0.48, 0.0), segs=10)
    m.lathe(bronze, [(0.0, 0.47), (0.04, 0.465), (0.07, 0.43), (0.08, 0.37), (0.1, 0.32), (0.115, 0.3), (0.1, 0.305), (0.07, 0.34), (0.0, 0.35)], (0.0, 0.0, 0.0), segs=20)
    m.lathe(verdi, [(0.096, 0.318), (0.104, 0.31), (0.1, 0.302)], (0.0, 0.0, 0.0), segs=20)
    m.rod(iron, 0.008, (0.0, 0.44, 0.0), (0.0, 0.2, 0.0), segs=8)
    m.ball(iron, (0.03, 0.035, 0.03), (0.0, 0.19, 0.0), u=10, v=8)
    m.lathe(brass, [(0.0, 0.15), (0.025, 0.152), (0.03, 0.16), (0.025, 0.168), (0.0, 0.17)], (0.0, 0.0, 0.0), segs=12)
    fk.blob(m, K("rock", BARN_CRUST), (0.06, 0.04, 0.05), (-0.13, 0.11, 0.07), seed=3, rough=0.25, cuts=1)
    for k in range(4):
        m.rod(K("bone", BARN), 0.012, (-0.15 + 0.02 * k, 0.13, 0.06 + 0.01 * k), (-0.15 + 0.02 * k, 0.16, 0.065 + 0.01 * k), r2=0.005, segs=6)
    red = K("scale", SHELL_RED)
    m.loft(red, [(0.12, 0.1, -0.08, 0.035, 0.03), (0.16, 0.1, 0.0, 0.03, 0.025), (0.14, 0.095, 0.08, 0.012, 0.01)], segs=8)
    m.loft(K("scale", SHELL_DARK), [(0.1, 0.1, -0.06, 0.02, 0.018), (0.08, 0.1, 0.03, 0.008, 0.008)], segs=8)


def main():
    fk.init()
    m = kit.Model("sea_abbot", uv_scale=0.5, colored=True)
    abbot(m)
    print("sea_abbot", m.export(OUT))
    t = kit.Model("trophy_bell_clapper", uv_scale=4.0, colored=True)
    bell_clapper_trophy(t)
    print("trophy_bell_clapper", t.export(os.path.join(os.path.dirname(__file__), "..", "..", "assets", "models", "fantasy")))


if __name__ == "__main__":
    main()
