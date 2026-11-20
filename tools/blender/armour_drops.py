# Purpose: developer-time script (polish1 item 66). Models one small piece per equipment slot for ARMOUR DROPS lying on
# the ground (a helmet, boots ... instead of a floating cube) into assets/models/armour/<slot>.gltf. Each is about
# 0.4-0.6 m, centred on its middle, plain grey: game/loot_field.gd tints its "Body" node with the drop's tier colour and
# keeps the "Trim" node darker. Our own simple designs.
# Run: python3 tools/blender/armour_drops.py
# Dependencies: bpy, tools/blender/kit.py, tools/blender/fantasy_kit.py. Used by game/loot_field.gd (spawn_item).
import math
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
import kit
import fantasy_kit as fk
from fantasy_kit import K

OUT = os.path.join(os.path.dirname(__file__), "..", "..", "assets", "models", "armour")
BODY = (0.8, 0.8, 0.82)
TRIM = (0.35, 0.33, 0.32)


def hoop(m, mat, centre, radius, thick, segs=16, node="Body"):
    pts = [(centre[0] + math.cos(2 * math.pi * k / segs) * radius, centre[1] + math.sin(2 * math.pi * k / segs) * radius, centre[2]) for k in range(segs)]
    for k in range(segs):
        m.rod(mat, thick, pts[k], pts[(k + 1) % segs], node=node, segs=6)


def mats():
    return K("metal", BODY), K("leather", TRIM), K("cloth", BODY)


def head(m):
    metal, trim, _ = mats()
    m.lathe(metal, [(0.0, 0.3), (0.12, 0.29), (0.2, 0.22), (0.22, 0.1), (0.22, -0.08), (0.2, -0.1), (0.0, -0.1)], (0, 0, 0), segs=18)
    m.box(trim, (0.05, 0.22, 0.04), (0.0, 0.02, 0.21), node="Trim")  # nose guard
    m.lathe(trim, [(0.225, -0.1), (0.235, -0.07), (0.225, -0.04)], (0, 0, 0), segs=18, node="Trim")


def hat(m):
    _, trim, cloth = mats()
    m.lathe(cloth, [(0.0, 0.2), (0.12, 0.2), (0.15, 0.05), (0.32, 0.03), (0.33, 0.0), (0.0, 0.0)], (0, -0.08, 0), segs=20)
    m.lathe(trim, [(0.152, 0.05), (0.158, 0.09), (0.15, 0.1)], (0, -0.08, 0), segs=20, node="Trim")


def earrings(m):
    metal, trim, _ = mats()
    for x in (-0.09, 0.09):
        m.lathe(metal, [(0.05, 0.0), (0.06, 0.012), (0.05, 0.024), (0.04, 0.012)], (x, 0.05, 0), segs=14, axis="f")
        m.ball(trim, (0.03, 0.04, 0.03), (x, -0.04, 0.0), node="Trim")


def necklace(m):
    metal, trim, _ = mats()
    hoop(m, metal, (0.0, 0.05, 0.0), 0.16, 0.012, 20)
    m.ball(trim, (0.05, 0.065, 0.025), (0.0, -0.13, 0.0), node="Trim")


def glasses(m):
    metal, trim, _ = mats()
    for x in (-0.07, 0.07):
        m.lathe(metal, [(0.05, -0.006), (0.056, 0.0), (0.05, 0.006), (0.044, 0.0)], (x, 0, 0), segs=16, axis="f")
        m.lathe(trim, [(0.0, -0.003), (0.045, -0.003), (0.045, 0.003), (0.0, 0.003)], (x, 0, 0), segs=16, axis="f", node="Trim")
    m.rod(metal, 0.006, (-0.02, 0.01, 0.0), (0.02, 0.01, 0.0))
    for x in (-0.12, 0.12):
        m.rod(metal, 0.006, (x, 0.0, 0.0), (x, 0.0, -0.14))


def mouth(m):
    _, trim, cloth = mats()
    m.loft(cloth, [(0.0, 0.0, 0.0, 0.18, 0.1), (0.0, 0.0, 0.05, 0.16, 0.09), (0.0, -0.01, 0.08, 0.1, 0.07)], segs=12)
    for x in (-0.12, 0.12):
        m.rod(trim, 0.008, (x, 0.02, 0.0), (x * 1.2, 0.04, -0.1), node="Trim")


def shirt(m):
    _, trim, cloth = mats()
    m.box(cloth, (0.36, 0.42, 0.06), (0, 0, 0))
    for side in (-1, 1):
        m.box(cloth, (0.16, 0.12, 0.06), (side * 0.24, 0.13, 0), tilt=0.0)
    m.box(trim, (0.12, 0.03, 0.065), (0, 0.2, 0), node="Trim")


def chestplate(m):
    metal, trim, _ = mats()
    m.loft(metal, [(0.0, -0.22, 0.0, 0.17, 0.06), (0.0, 0.0, 0.02, 0.2, 0.08), (0.0, 0.18, 0.01, 0.21, 0.07), (0.0, 0.24, 0.0, 0.15, 0.05)], segs=14)
    for side in (-1, 1):
        m.ball(metal, (0.09, 0.05, 0.08), (side * 0.2, 0.2, -0.01))
    m.box(trim, (0.03, 0.38, 0.02), (0, 0.0, 0.09), node="Trim")


def gauntlets(m):
    metal, trim, _ = mats()
    for x in (-0.1, 0.1):
        m.lathe(metal, [(0.05, -0.15), (0.07, -0.05), (0.08, 0.05), (0.06, 0.12)], (x, 0, 0), segs=12)
        m.lathe(trim, [(0.081, 0.04), (0.09, 0.06), (0.081, 0.08)], (x, 0, 0), segs=12, node="Trim")
        m.box(metal, (0.09, 0.06, 0.08), (x, -0.18, 0.0))


def ring(m):
    metal, trim, _ = mats()
    hoop(m, metal, (0.0, 0.0, 0.0), 0.075, 0.018, 16)
    m.ball(trim, (0.035, 0.035, 0.035), (0.0, 0.085, 0.0), node="Trim")


def bracelet(m):
    metal, trim, _ = mats()
    hoop(m, metal, (0.0, 0.0, 0.0), 0.1, 0.025, 18)
    for k in range(4):
        a = 2 * math.pi * k / 4
        m.ball(trim, (0.02, 0.02, 0.02), (math.cos(a) * 0.1, math.sin(a) * 0.1, 0.0), node="Trim")


def pants(m):
    _, trim, cloth = mats()
    m.box(cloth, (0.3, 0.1, 0.07), (0, 0.18, 0))
    for side in (-1, 1):
        m.box(cloth, (0.13, 0.36, 0.07), (side * 0.08, -0.05, 0))
    m.box(trim, (0.31, 0.03, 0.075), (0, 0.22, 0), node="Trim")


def leg_armor(m):
    metal, trim, _ = mats()
    for side in (-1, 1):
        m.loft(metal, [(side * 0.09, -0.2, 0.0, 0.1, 0.08), (side * 0.09, 0.0, 0.02, 0.12, 0.1), (side * 0.09, 0.2, 0.0, 0.13, 0.1)], segs=10)
        m.ball(trim, (0.06, 0.05, 0.05), (side * 0.09, 0.02, 0.07), node="Trim")


def cape(m):
    _, trim, cloth = mats()
    m.loft(cloth, [(0.0, 0.22, 0.0, 0.3, 0.03), (0.0, 0.0, -0.03, 0.4, 0.03), (0.0, -0.25, -0.02, 0.48, 0.03)], segs=8, flat=True)
    m.ball(trim, (0.04, 0.04, 0.03), (0.0, 0.22, 0.02), node="Trim")


def waist(m):
    _, trim, cloth = mats()
    hoop(m, cloth, (0.0, 0.0, 0.0), 0.17, 0.025, 22)
    m.box(trim, (0.08, 0.07, 0.02), (0.0, -0.17, 0.0), node="Trim")


def boots(m):
    _, trim, _ = mats()
    leather = K("leather", BODY)
    for x in (-0.08, 0.08):
        m.box(leather, (0.1, 0.22, 0.12), (x, 0.03, -0.02))
        m.box(leather, (0.1, 0.07, 0.26), (x, -0.1, 0.05))
        m.box(trim, (0.105, 0.025, 0.27), (x, -0.14, 0.05), node="Trim")


def foot_armor(m):
    metal, trim, _ = mats()
    for x in (-0.08, 0.08):
        m.loft(metal, [(x, -0.12, -0.08, 0.1, 0.08), (x, -0.08, 0.05, 0.11, 0.09), (x, -0.12, 0.17, 0.06, 0.04)], segs=10)
        m.lathe(metal, [(0.06, -0.06), (0.065, 0.12)], (x, 0, -0.08), segs=10)
        m.box(trim, (0.11, 0.02, 0.24), (x, -0.15, 0.04), node="Trim")


PIECES = {"head": head, "hat": hat, "earrings": earrings, "necklace": necklace, "glasses": glasses, "mouth": mouth,
          "shirt": shirt, "chestplate": chestplate, "gauntlets": gauntlets, "ring": ring, "bracelet": bracelet,
          "pants": pants, "leg_armor": leg_armor, "cape": cape, "waist": waist, "boots": boots, "foot_armor": foot_armor}


def main():
    fk.init()
    os.makedirs(OUT, exist_ok=True)
    for name, build in PIECES.items():
        m = kit.Model(name, uv_scale=2.0, colored=True)
        m.node("Trim", (0.0, 0.0, 0.0))
        build(m)
        print(name, m.export(OUT))


if __name__ == "__main__":
    main()
