# Purpose: developer-time script. Models region 2's super boss THE LANTERN QUEEN (sea step 13 R2d, design approved
# in diary/DESIGN_BOSSES.md) with tools/blender/kit.py into assets/models/fantasy/creatures/sea_queen.gltf: a colossal
# anglerfish (~12 m) gone half-amphibious in the mangroves. Our own design.
#   "Body": a mottled bark-brown hide grown over with moss and hanging roots, a paler belly, small glowing eyes, the
#   upper jaw's fangs and the dark red mouth; "Jaw" (pivot at its hinge: the underbite opens down); "Crown": short
#   glowing spines over the head (the game brightens them for the flare burst); "LureStalk" (pivot on the brow) with
#   the lantern bulb "LureBulb" at its end (the real lure: a breakable in phase 2, hidden while broken); "GillL" /
#   "GillR" (the gill slits behind the head: weak points, live only in a lit circle); stubby fin-legs "FinL1",
#   "FinR1" (pectoral, the front pair she drags herself on) and "FinL2", "FinR2" (pelvic); "Tail" (pivot at its root).
# Also sea_lanternfry.gltf (the small hopping angler she spawns in phase 2: "Body", "Lure", ~0.9 m) and the trophy
# hall piece trophy_lure_lamp.gltf (the Queen's Lure Lamp).
# Model space: x right, y up, f forward (the game's -z). Fins on y = 0, the mouth toward +f.
# Run: python3 tools/blender/sea_boss_queen.py
# Dependencies: bpy, tools/blender/kit.py, tools/blender/fantasy_kit.py. No game code.
import math
import os
import random
import sys

sys.path.insert(0, os.path.dirname(__file__))
import kit
import fantasy_kit as fk
from fantasy_kit import K

OUT = os.path.join(os.path.dirname(__file__), "..", "..", "assets", "models", "fantasy", "creatures")

HIDE = (0.33, 0.23, 0.15)
HIDE_DARK = (0.17, 0.12, 0.08)
BELLY = (0.56, 0.47, 0.34)
MOSS = (0.26, 0.37, 0.12)
ROOT = (0.24, 0.18, 0.12)
TOOTH = (0.86, 0.83, 0.7)
MOUTH = (0.34, 0.07, 0.08)
LURE = (0.78, 1.0, 0.58)
GILL = (0.42, 0.1, 0.12)
BRASS = (0.8, 0.62, 0.3)


def fin(m, name, side, hip, foot, chord, hide, dark):
    """A stubby fin-leg from the hip down to a broad webbed foot on the ground."""
    knee = ((hip[0] + foot[0]) * 0.5 + side * 0.3, (hip[1] + foot[1]) * 0.5 + 0.25, (hip[2] + foot[2]) * 0.5)
    m.node(name, hip)
    m.loft(hide, [(hip[0], hip[1], hip[2], 0.55, 0.5), (knee[0], knee[1], knee[2], 0.42, 0.38), (foot[0], foot[1] + 0.25, foot[2], 0.3, 0.22)], segs=12, node=name)
    for k in range(5):  # webbed rays fanning forward from the foot
        a = math.radians(-50 + 25 * k)
        tip = (foot[0] + side * math.cos(a) * 0.25 + math.sin(a) * 0.2, 0.06, foot[2] + math.cos(a) * chord)
        m.rod(dark, 0.07, (foot[0], foot[1] + 0.2, foot[2]), tip, r2=0.03, segs=6, node=name)
    m.loft(hide, [(foot[0], foot[1] + 0.12, foot[2] - 0.1, 0.45, 0.08), (foot[0], foot[1] + 0.08, foot[2] + chord * 0.6, 0.6, 0.06), (foot[0], foot[1] + 0.05, foot[2] + chord, 0.25, 0.04)], segs=10, node=name)


def queen(m):
    hide, dark, belly = K("leather", HIDE), K("leather", HIDE_DARK), K("leather", BELLY)
    moss, root, tooth = K("leaf", MOSS), K("wood", ROOT), K("bone", TOOTH)
    mouth, gill = K("leather", MOUTH), K("leather", GILL)
    glow = (fk.GLOW, LURE)
    rnd = random.Random(7)
    # --- the body: a great round head-body tapering to the tail ---
    m.loft(hide, [(0.0, 1.7, -4.6, 0.85, 0.75), (0.0, 2.0, -3.2, 1.6, 1.3), (0.0, 2.3, -1.2, 2.45, 1.95), (0.0, 2.5, 0.8, 2.9, 2.2), (0.0, 2.45, 2.6, 2.8, 2.05), (0.0, 2.35, 4.0, 2.4, 1.6), (0.0, 2.25, 4.9, 1.7, 1.0)], segs=20)
    m.loft(belly, [(0.0, 0.95, -3.0, 1.2, 0.5), (0.0, 0.75, -0.8, 2.0, 0.7), (0.0, 0.8, 1.2, 2.2, 0.7)], segs=16)
    # mottling and warts over the hide
    for k in range(34):
        a = rnd.uniform(-1.2, 1.2)
        f = rnd.uniform(-3.5, 3.6)
        r = 2.6 - abs(f) * 0.25
        m.ball(dark, (rnd.uniform(0.25, 0.55), 0.08, rnd.uniform(0.25, 0.55)), (math.sin(a) * r, 2.45 + math.cos(a) * r * 0.75, f), yaw=rnd.uniform(0, 3), pitch=a * 0.8, u=8, v=4)
    # moss over the back and the brow, roots hanging off her flanks
    for k in range(9):
        f = -3.2 + k * 0.85
        fk.blob(m, moss, (0.75, 0.25, 0.6), (rnd.uniform(-0.8, 0.8), 4.25 - abs(f - 1.0) * 0.18, f), seed=20 + k, rough=0.35, cuts=1)
    for k in range(14):
        side = -1 if k % 2 else 1
        f = -3.0 + (k // 2) * 0.95
        top = (side * (2.3 - abs(f) * 0.12), 2.6 + rnd.uniform(-0.3, 0.3), f)
        m.rod(root, 0.09, top, (top[0] + side * 0.2, top[1] - 1.6 - rnd.uniform(0.0, 0.8), top[2] + rnd.uniform(-0.3, 0.3)), r2=0.025, segs=6)
    # the mouth: dark red inside, the upper jaw's fangs hanging down
    m.ball(mouth, (2.0, 0.7, 1.3), (0.0, 1.45, 4.1), u=14, v=8)
    for k in range(13):
        a = math.radians(-70 + k * (140 / 12))
        x, f = math.sin(a) * 1.75, 4.1 + math.cos(a) * 1.15
        length = 0.5 + 0.45 * math.cos(a)
        m.rod(tooth, 0.09, (x, 1.75, f), (x * 1.04, 1.75 - length, f + 0.12), r2=0.015, segs=6)
    # small glowing eyes high on the head
    for side in (-1, 1):
        m.ball(dark, (0.32, 0.3, 0.32), (side * 1.55, 3.35, 3.4), u=10, v=8)
        m.ball(glow, (0.2, 0.2, 0.2), (side * 1.68, 3.42, 3.55), u=10, v=8)
    # --- the jaw: a jutting underbite with fangs pointing up ---
    m.node("Jaw", (0.0, 1.2, 1.6))
    m.loft(hide, [(0.0, 1.0, 1.6, 2.45, 0.85), (0.0, 0.85, 3.4, 2.4, 0.75), (0.0, 1.0, 5.0, 2.0, 0.55), (0.0, 1.25, 5.55, 1.4, 0.35)], segs=18, node="Jaw")
    m.loft(belly, [(0.0, 0.55, 2.0, 1.9, 0.35), (0.0, 0.5, 4.2, 1.6, 0.3)], segs=12, node="Jaw")
    for k in range(11):
        a = math.radians(-65 + k * 13)
        x, f = math.sin(a) * 1.9, 4.5 + math.cos(a) * 1.05
        length = 0.55 + 0.5 * math.cos(a)
        m.rod(tooth, 0.1, (x, 1.35, f), (x * 1.05, 1.35 + length, f + 0.2), r2=0.018, segs=6, node="Jaw")
    # --- the crown of short glowing spines ---
    m.node("Crown", (0.0, 4.4, 2.0))
    for k in range(9):
        f = 0.6 + k * 0.38
        for side in (-1, 1):
            x = side * (0.35 + 0.08 * k)
            base = (x, 4.45 - (f - 2.0) ** 2 * 0.08, f)
            tip = (x * 1.6, base[1] + 0.7 - 0.04 * k, f + 0.25)
            m.rod(dark, 0.08, base, tip, r2=0.03, segs=6, node="Crown")
            m.ball(glow, (0.1, 0.1, 0.1), tip, u=8, v=6, node="Crown")
    # --- the lure: a long stalk from the brow arching forward, the lantern bulb at its end ---
    m.node("LureStalk", (0.0, 4.3, 3.4))
    pts = [(0.0, 4.3, 3.4), (0.0, 5.7, 3.7), (0.0, 6.7, 4.6), (0.0, 6.9, 5.9), (0.0, 6.4, 6.9), (0.0, 5.9, 7.2)]
    for i in range(len(pts) - 1):
        m.rod(dark, 0.17 - 0.022 * i, pts[i], pts[i + 1], r2=0.15 - 0.022 * i, segs=8, node="LureStalk")
    m.node("LureBulb", (0.0, 5.45, 7.25), parent="LureStalk")
    m.ball(glow, (0.48, 0.55, 0.48), (0.0, 5.45, 7.25), u=16, v=12, node="LureBulb")
    m.ball(dark, (0.22, 0.12, 0.22), (0.0, 5.95, 7.22), u=10, v=6, node="LureBulb")  # the cap it hangs from
    for k in range(6):  # glowing filaments under the bulb
        a = 2 * math.pi * k / 6
        m.rod(glow, 0.025, (math.cos(a) * 0.3, 5.1, 7.25 + math.sin(a) * 0.3), (math.cos(a) * 0.45, 4.6, 7.25 + math.sin(a) * 0.45), r2=0.01, segs=4, node="LureBulb")
    # --- the gill slits (weak points) ---
    for name, side in (("GillL", -1), ("GillR", 1)):
        m.node(name, (side * 2.75, 2.2, 0.4))
        for k in range(4):
            f = -0.2 + k * 0.42
            m.box(gill, (0.2, 1.5 - 0.12 * k, 0.16), (side * (2.82 - 0.03 * k), 2.2, f), bevel=0.04, node=name)
            m.box(dark, (0.12, 1.6 - 0.12 * k, 0.07), (side * (2.92 - 0.03 * k), 2.2, f + 0.13), bevel=0.02, node=name)
    # --- the fin-legs ---
    fin(m, "FinL1", -1, (-2.2, 1.4, 1.2), (-3.7, 0.0, 2.0), 1.3, hide, dark)
    fin(m, "FinR1", 1, (2.2, 1.4, 1.2), (3.7, 0.0, 2.0), 1.3, hide, dark)
    fin(m, "FinL2", -1, (-1.4, 1.0, -2.3), (-2.4, 0.0, -2.0), 0.9, hide, dark)
    fin(m, "FinR2", 1, (1.4, 1.0, -2.3), (2.4, 0.0, -2.0), 0.9, hide, dark)
    # --- the tail ---
    m.node("Tail", (0.0, 1.7, -4.5))
    m.loft(hide, [(0.0, 1.7, -4.4, 0.85, 0.75), (0.0, 1.6, -5.6, 0.55, 0.55), (0.0, 1.55, -6.6, 0.3, 0.38)], segs=14, node="Tail")
    m.prof(dark, 0.06, [(-6.3, 1.1), (-6.4, 2.0), (-7.8, 3.1), (-8.0, 1.6), (-7.8, 0.2), (-6.4, 0.9)], x=0.0, bevel=0.01, node="Tail")
    m.prof(dark, 0.05, [(-1.5, 4.0), (0.6, 4.35), (-0.6, 5.0), (-2.6, 4.6)], x=0.0, bevel=0.01)  # the dorsal fin


def lanternfry(m):
    hide, dark, belly = K("leather", HIDE), K("leather", HIDE_DARK), K("leather", BELLY)
    glow, tooth = (fk.GLOW, LURE), K("bone", TOOTH)
    m.loft(hide, [(0.0, 0.3, -0.35, 0.12, 0.12), (0.0, 0.38, -0.1, 0.26, 0.26), (0.0, 0.4, 0.15, 0.3, 0.28), (0.0, 0.36, 0.33, 0.24, 0.2)], segs=12)
    m.loft(belly, [(0.0, 0.2, -0.1, 0.18, 0.08), (0.0, 0.18, 0.25, 0.2, 0.08)], segs=10)
    m.ball(K("leather", MOUTH), (0.18, 0.08, 0.06), (0.0, 0.3, 0.38), u=10, v=6)
    for k in range(6):
        x = -0.15 + k * 0.06
        m.rod(tooth, 0.012, (x, 0.36, 0.38), (x, 0.27, 0.4), r2=0.003, segs=4)
    for side in (-1, 1):
        m.ball(glow, (0.035, 0.035, 0.035), (side * 0.2, 0.52, 0.22), u=6, v=5)
        m.loft(hide, [(side * 0.2, 0.25, 0.05, 0.06, 0.05), (side * 0.32, 0.03, 0.12, 0.08, 0.02)], segs=8)  # stubby fins
    m.prof(dark, 0.02, [(-0.35, 0.3), (-0.5, 0.48), (-0.52, 0.15)], x=0.0, bevel=0.004)  # tail fin
    m.node("Lure", (0.0, 0.62, 0.1))
    m.rod(dark, 0.015, (0.0, 0.62, 0.1), (0.0, 0.85, 0.3), r2=0.01, segs=5, node="Lure")
    m.ball(glow, (0.07, 0.07, 0.07), (0.0, 0.8, 0.42), u=10, v=8, node="Lure")


def lure_lamp_trophy(m):
    """The trophy hall's piece for the Lantern Queen (~0.6 m): her lure bulb, still faintly glowing, hung from a
    length of its stalk on a brass hook arm over a dark wood stand, a crown spine laid at its foot."""
    wood, brass = K("wood", (0.24, 0.15, 0.09)), K("metal", BRASS)
    dark, glow = K("leather", HIDE_DARK), (fk.GLOW, LURE)
    m.box(wood, (0.36, 0.06, 0.28), (0.0, 0.03, 0.0), bevel=0.01)
    m.box(wood, (0.3, 0.03, 0.22), (0.0, 0.075, 0.0), bevel=0.008)
    m.rod(brass, 0.014, (-0.12, 0.08, 0.0), (-0.12, 0.56, 0.0), segs=10)
    m.rod(brass, 0.012, (-0.12, 0.55, 0.0), (0.06, 0.58, 0.0), segs=10)
    m.ball(brass, 0.022, (-0.12, 0.57, 0.0), u=10, v=6)
    m.rod(dark, 0.012, (0.06, 0.58, 0.0), (0.08, 0.46, 0.0), r2=0.009, segs=6)
    m.ball(glow, (0.07, 0.08, 0.07), (0.08, 0.38, 0.0), u=14, v=10)
    m.ball(dark, (0.035, 0.02, 0.035), (0.08, 0.455, 0.0), u=8, v=5)
    for k in range(5):  # a thin brass cage round the bulb
        a = 2 * math.pi * k / 5
        m.rod(brass, 0.004, (0.08 + math.cos(a) * 0.04, 0.45, math.sin(a) * 0.04), (0.08 + math.cos(a) * 0.09, 0.36, math.sin(a) * 0.09), segs=4)
    m.rod(dark, 0.012, (-0.05, 0.1, 0.06), (0.1, 0.12, 0.08), r2=0.004, segs=6)
    m.ball(glow, 0.012, (0.1, 0.12, 0.08), u=6, v=5)


def main():
    fk.init()
    m = kit.Model("sea_queen", uv_scale=0.5, colored=True)
    queen(m)
    print("sea_queen", m.export(OUT))
    f = kit.Model("sea_lanternfry", uv_scale=2.0, colored=True)
    lanternfry(f)
    print("sea_lanternfry", f.export(OUT))
    t = kit.Model("trophy_lure_lamp", uv_scale=4.0, colored=True)
    lure_lamp_trophy(t)
    print("trophy_lure_lamp", t.export(os.path.join(os.path.dirname(__file__), "..", "..", "assets", "models", "fantasy")))


if __name__ == "__main__":
    main()
