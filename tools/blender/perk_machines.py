# Purpose: developer-time script (polish1 item 37 + the 16th perk, batch 2-3 QUICK REVIVE). Models one machine per perk
# so each reads from across the map by SIZE, SHAPE and COLOUR (they were 15 identical cabinets): a lighthouse, a giant
# bullet, a windmill kiosk, a bomb, an iron stove, a scope obelisk, a treasure chest, a stopwatch, an hourglass, a claw
# machine, a kiln, a shield, ice crystals, a gun cabinet, a horseshoe arch and a heart. Our own designs. Into
# assets/models/fantasy/perk_<id>.gltf. Nodes: "Body" (its own colours: the perk's colour from data/perks.json mixed
# in), "Glow" (the game paints it in the perk's colour and lights it once the power is on), "Spin" (turns while
# powered; the windmill), an empty "Tag" (where the game writes the name and price). Faces +Z in the game (f < 0 here).
# Run: python3 tools/blender/perk_machines.py
# Dependencies: bpy, tools/blender/kit.py, tools/blender/fantasy_kit.py, data/perks.json. Used by game/perk_machine.gd.
import json
import math
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
import kit
import fantasy_kit as fk
from fantasy_kit import K

HERE = os.path.dirname(__file__)
OUT = os.path.join(HERE, "..", "..", "assets", "models", "fantasy")
PERKS = json.load(open(os.path.join(HERE, "..", "..", "data", "perks.json")))["perks"]
DARK = (0.16, 0.15, 0.17)
WHITE = (0.92, 0.91, 0.88)
BRASS = (0.85, 0.66, 0.3)
IRON = (0.24, 0.24, 0.27)


def tint(hexcode, mix=1.0, toward=(0.2, 0.2, 0.2)):
    h = hexcode.lstrip("#")
    rgb = tuple(int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4))
    return tuple(toward[i] + (rgb[i] - toward[i]) * mix for i in range(3))


def plinth(m, w, d, col=DARK):
    m.box(K("stone", col), (w, 0.12, d), (0.0, 0.06, 0.0))


def ring(m, mat, r, y, thick, segs=20, node="Body"):
    pts = [(math.cos(2 * math.pi * k / segs) * r, y, math.sin(2 * math.pi * k / segs) * r) for k in range(segs)]
    for k in range(segs):
        m.rod(mat, thick, pts[k], pts[(k + 1) % segs], node=node, segs=6)


def lighthouse(m, col):  # second_wind: tall striped tower, glowing lamp room
    plinth(m, 1.3, 1.3)
    white, red = K("paint", WHITE), K("paint", tint(col, 0.9))
    m.lathe(white, [(0.0, 0.12), (0.58, 0.12), (0.5, 1.2), (0.42, 2.3), (0.0, 2.3)], (0, 0, 0), segs=20)
    for y0, y1 in ((0.6, 0.9), (1.5, 1.8)):
        m.lathe(red, [(0.0, y0), (0.6 - y0 * 0.075, y0), (0.6 - y1 * 0.075, y1), (0.0, y1)], (0, 0, 0), segs=20)
    m.lathe(K("metal", IRON), [(0.0, 2.3), (0.62, 2.3), (0.62, 2.38), (0.0, 2.38)], (0, 0, 0), segs=20)
    ring(m, K("metal", IRON), 0.6, 2.62, 0.02, segs=16)
    m.lathe(K("paint", WHITE), [(0.0, 2.38), (0.32, 2.38), (0.32, 2.78), (0.0, 2.78)], (0, 0, 0), segs=16, node="Glow")
    m.lathe(red, [(0.0, 2.78), (0.42, 2.78), (0.0, 3.15)], (0, 0, 0), segs=16)
    m.box(K("wood", (0.3, 0.2, 0.12)), (0.36, 0.62, 0.06), (0.0, 0.43, -0.55))
    m.empty("Tag", 0.0, 1.25, -0.48)


def bullet(m, col):  # hair_trigger: a giant brass cartridge standing on end
    plinth(m, 1.2, 1.2)
    brass = K("metal", BRASS)
    m.lathe(brass, [(0.0, 0.12), (0.5, 0.12), (0.5, 0.2), (0.44, 0.24), (0.46, 1.55), (0.0, 1.55)], (0, 0, 0), segs=24)
    m.lathe(K("metal", tint(col, 0.55, (0.6, 0.35, 0.2))), [(0.0, 1.55), (0.44, 1.55), (0.42, 1.9), (0.33, 2.2), (0.18, 2.42), (0.0, 2.5)], (0, 0, 0), segs=24)
    m.lathe(K("paint", WHITE), [(0.0, 1.46), (0.475, 1.46), (0.475, 1.56), (0.0, 1.56)], (0, 0, 0), segs=24, node="Glow")
    m.lathe(K("metal", (0.5, 0.4, 0.2)), [(0.0, 0.11), (0.18, 0.11), (0.18, 0.125), (0.0, 0.125)], (0, 0.0, 0), segs=16)
    m.empty("Tag", 0.0, 1.0, -0.47)


def windmill(m, col):  # trade_winds: a kiosk with a turning three-blade rotor on top
    plinth(m, 1.1, 0.9)
    body = K("paint", tint(col, 0.6))
    m.box(body, (0.9, 1.75, 0.7), (0.0, 0.95, 0.0))
    m.box(K("paint", WHITE), (0.7, 0.9, 0.03), (0.0, 1.2, -0.36), node="Glow")
    m.rod(K("metal", IRON), 0.05, (0.0, 1.8, 0.0), (0.0, 2.15, -0.25))
    m.cyl(K("metal", IRON), 0.09, -0.25, -0.42, y=2.15, x=0.0, node="Spin")
    for k in range(3):
        a = math.radians(90 + k * 120)
        tip = (math.cos(a) * 0.95, 2.15 + math.sin(a) * 0.95, -0.4)
        m.loft(K("wood", WHITE), [(math.cos(a) * 0.1, 2.15 + math.sin(a) * 0.1, -0.4, 0.04, 0.012), (math.cos(a) * 0.6, 2.15 + math.sin(a) * 0.6, -0.4, 0.13, 0.012), (tip[0], tip[1], tip[2], 0.07, 0.01)], node="Spin", segs=6, steps=1)
    m.empty("Tag", 0.0, 1.2, -0.39)


def bomb(m, col):  # blast_proof: a round black bomb with a lit fuse
    m.lathe(K("stone", DARK), [(0.0, 0.0), (0.55, 0.0), (0.45, 0.2), (0.0, 0.2)], (0, 0, 0), segs=20)
    m.ball(K("metal", (0.13, 0.12, 0.15)), (0.82, 0.82, 0.82), (0.0, 0.98, 0.0), u=20, v=14)
    m.lathe(K("metal", tint(col, 0.7, IRON)), [(0.0, 1.72), (0.22, 1.72), (0.22, 1.92), (0.0, 1.92)], (0, 0, 0), segs=14)
    m.rod(K("cloth", (0.75, 0.68, 0.5)), 0.035, (0.0, 1.92, 0.0), (0.12, 2.12, 0.05))
    m.rod(K("cloth", (0.75, 0.68, 0.5)), 0.035, (0.12, 2.12, 0.05), (0.28, 2.2, 0.12))
    m.ball(K("paint", WHITE), (0.1, 0.1, 0.1), (0.3, 2.22, 0.13), node="Glow")
    ring(m, K("paint", WHITE), 0.83, 0.98, 0.03, segs=24, node="Glow")
    m.empty("Tag", 0.0, 1.05, -0.86)


def stove(m, col):  # iron_gut: a wide squat iron stove with a tall chimney and a glowing fire door
    iron = K("metal", (0.2, 0.19, 0.2))
    for x in (-0.7, 0.7):
        for f in (-0.4, 0.4):
            m.rod(iron, 0.06, (x, 0.0, f), (x, 0.3, f))
    m.box(iron, (1.7, 0.95, 1.05), (0.0, 0.78, 0.0))
    m.box(K("metal", tint(col, 0.6, (0.2, 0.2, 0.2))), (1.8, 0.08, 1.15), (0.0, 1.29, 0.0))
    m.rod(iron, 0.15, (0.45, 1.3, 0.25), (0.45, 2.75, 0.25))
    m.rod(iron, 0.19, (0.45, 2.7, 0.25), (0.45, 2.8, 0.25))
    m.box(K("paint", WHITE), (0.7, 0.42, 0.03), (-0.2, 0.68, -0.54), node="Glow")
    m.box(iron, (0.78, 0.05, 0.05), (-0.2, 0.92, -0.55))
    m.empty("Tag", 0.0, 1.12, -0.55)


def obelisk(m, col):  # steady_hand: a tall pale obelisk with a scope looking out
    plinth(m, 1.0, 1.0)
    stone = K("stone", tint(col, 0.9, (0.6, 0.6, 0.6)))
    m.lathe(stone, [(0.0, 0.12), (0.42, 0.12), (0.3, 2.6), (0.0, 2.6)], (0, 0, 0), segs=4)
    m.lathe(stone, [(0.0, 2.6), (0.31, 2.6), (0.0, 2.95)], (0, 0, 0), segs=4)
    m.cyl(K("metal", IRON), 0.12, -0.2, -0.8, y=2.0, x=0.0, segs=14)
    m.cyl(K("metal", IRON), 0.15, -0.72, -0.84, y=2.0, x=0.0, segs=14)
    m.cyl(K("paint", WHITE), 0.11, -0.84, -0.86, y=2.0, x=0.0, segs=14, node="Glow")
    m.empty("Tag", 0.0, 1.2, -0.31)


def chest(m, col):  # deep_pockets: a wide low treasure chest, light spilling out of the lid
    wood = K("wood", tint(col, 0.85, (0.3, 0.2, 0.1)))
    band = K("metal", BRASS)
    m.box(wood, (1.7, 0.75, 1.0), (0.0, 0.375, 0.0))
    m.cylx(wood, 0.5, -0.85, 0.85, 0.0, 0.8, segs=16)
    for x in (-0.6, 0.0, 0.6):
        m.box(band, (0.08, 0.77, 1.02), (x, 0.385, 0.0))
    m.box(K("paint", WHITE), (1.6, 0.06, 0.03), (0.0, 0.78, -0.51), node="Glow")
    m.box(band, (0.2, 0.22, 0.04), (0.0, 0.62, -0.52))
    m.empty("Tag", 0.0, 0.42, -0.52)


def stopwatch(m, col):  # run_and_gun: a huge stopwatch on a post
    plinth(m, 0.9, 0.9)
    metal = K("metal", (0.75, 0.75, 0.78))
    m.rod(metal, 0.09, (0.0, 0.12, 0.0), (0.0, 1.2, 0.0))
    m.cyl(K("metal", tint(col, 0.7, (0.5, 0.5, 0.5))), 0.78, -0.12, 0.12, y=1.95, x=0.0, segs=28)
    m.cyl(K("paint", WHITE), 0.66, -0.13, -0.15, y=1.95, x=0.0, segs=28, node="Glow")
    m.rod(K("metal", DARK), 0.025, (0.0, 1.95, -0.16), (0.0, 2.45, -0.16))
    m.rod(K("metal", DARK), 0.025, (0.0, 1.95, -0.16), (0.3, 2.1, -0.16))
    m.rod(metal, 0.08, (0.0, 2.72, 0.0), (0.0, 2.88, 0.0))
    m.cyl(metal, 0.13, -0.06, 0.06, y=2.95, x=0.0, segs=14)
    m.rod(metal, 0.06, (0.5, 2.5, 0.0), (0.62, 2.64, 0.0))
    m.empty("Tag", 0.0, 1.62, -0.17)


def hourglass(m, col):  # quickhands: an hourglass in a wooden frame
    wood = K("wood", tint(col, 0.5, (0.35, 0.25, 0.15)))
    m.box(wood, (1.05, 0.14, 1.05), (0.0, 0.07, 0.0))
    m.box(wood, (1.05, 0.14, 1.05), (0.0, 2.25, 0.0))
    for k in range(3):
        a = math.radians(90 + k * 120)
        m.rod(wood, 0.05, (math.cos(a) * 0.42, 0.14, math.sin(a) * 0.42), (math.cos(a) * 0.42, 2.18, math.sin(a) * 0.42))
    m.lathe(K("paint", WHITE), [(0.0, 0.14), (0.36, 0.14), (0.34, 0.5), (0.08, 1.12), (0.08, 1.2), (0.34, 1.82), (0.36, 2.18), (0.0, 2.18)], (0, 0, 0), segs=18, node="Glow")
    m.empty("Tag", 0.0, 0.07, -0.54)


def claw(m, col):  # scavenger: a claw machine: cabinet, glass case with a heap and a claw, lit marquee
    body = K("paint", tint(col, 0.7))
    m.box(body, (1.1, 0.95, 1.0), (0.0, 0.475, 0.0))
    for x in (-0.52, 0.52):
        for f in (-0.47, 0.47):
            m.rod(K("metal", IRON), 0.03, (x, 0.95, f), (x, 1.9, f))
    fk.blob(m, K("cloth", (0.8, 0.5, 0.4)), (0.4, 0.15, 0.35), (0.0, 1.05, 0.05), seed=3)
    m.rod(K("metal", IRON), 0.015, (0.0, 1.9, 0.0), (0.0, 1.55, 0.0))
    for k in range(3):
        a = math.radians(k * 120)
        m.rod(K("metal", IRON), 0.02, (0.0, 1.55, 0.0), (math.cos(a) * 0.12, 1.42, math.sin(a) * 0.12))
    m.box(body, (1.14, 0.42, 1.04), (0.0, 2.11, 0.0))
    m.box(K("paint", WHITE), (1.0, 0.3, 0.03), (0.0, 2.11, -0.53), node="Glow")
    m.empty("Tag", 0.0, 2.11, -0.55)


def kiln(m, col):  # backdraft: a brick beehive kiln with a glowing mouth
    brick = K("stone", tint(col, 0.55, (0.45, 0.3, 0.25)))
    m.lathe(brick, [(0.0, 0.0), (0.9, 0.0), (0.88, 0.6), (0.72, 1.3), (0.42, 1.8), (0.0, 1.95)], (0, 0, 0), segs=20)
    m.rod(brick, 0.14, (0.0, 1.85, 0.2), (0.0, 2.4, 0.2))
    m.box(K("paint", WHITE), (0.6, 0.55, 0.04), (0.0, 0.38, -0.86), node="Glow")
    m.box(K("stone", DARK), (0.76, 0.08, 0.1), (0.0, 0.7, -0.87))
    m.empty("Tag", 0.0, 1.1, -0.74)


def shield(m, col):  # thick_skin: a great heater shield standing on a post
    plinth(m, 1.0, 0.7)
    m.rod(K("wood", (0.35, 0.25, 0.15)), 0.07, (0.0, 0.12, 0.12), (0.0, 2.0, 0.12))
    steel = K("metal", tint(col, 0.8, (0.5, 0.5, 0.55)))
    rings = []
    for y, w in ((0.35, 0.02), (0.6, 0.32), (0.95, 0.55), (1.4, 0.7), (1.9, 0.75), (2.35, 0.75)):
        rings.append((0.0, y, -0.02 + (0.06 * (w / 0.75)), w, 0.07))
    m.loft(steel, rings, segs=12, steps=2)
    m.ball(K("paint", WHITE), (0.18, 0.18, 0.08), (0.0, 1.55, -0.08), node="Glow")
    m.empty("Tag", 0.0, 1.05, -0.1)


def crystals(m, col):  # cold_blood: a cluster of tall ice crystals on a rock
    fk.blob(m, K("rock", (0.4, 0.42, 0.46)), (0.75, 0.3, 0.65), (0.0, 0.15, 0.0), seed=5)
    ice = K("ice", tint(col, 0.6, (0.85, 0.9, 0.95)))
    for x, f, h, lean, r in ((0.0, 0.0, 2.7, 0.0, 0.26), (-0.35, 0.15, 1.9, -0.25, 0.2), (0.38, 0.1, 2.1, 0.22, 0.2), (0.15, -0.3, 1.4, 0.12, 0.15), (-0.2, -0.25, 1.2, -0.15, 0.14)):
        top = (x + math.sin(lean) * h, 0.2 + math.cos(lean) * h, f)
        m.rod(ice, r, (x, 0.2, f), top, segs=6)
        m.rod(ice, r * 0.98, top, (top[0] + math.sin(lean) * r * 1.6, top[1] + math.cos(lean) * r * 1.6, f), r2=0.005, segs=6)
    m.rod(K("paint", WHITE), 0.1, (0.0, 0.4, 0.0), (0.0, 2.2, 0.0), segs=6, node="Glow")
    m.empty("Tag", 0.0, 0.35, -0.66)


def gun_cabinet(m, col):  # third_holster: a tall gun cabinet with three lit slots
    wood = K("wood", tint(col, 0.45, (0.3, 0.2, 0.12)))
    m.box(wood, (1.0, 2.2, 0.55), (0.0, 1.1, 0.0))
    m.box(wood, (1.12, 0.14, 0.62), (0.0, 2.27, 0.0))
    for x in (-0.3, 0.0, 0.3):
        m.box(K("paint", WHITE), (0.2, 1.3, 0.03), (x, 1.05, -0.28), node="Glow")
        m.box(K("metal", DARK), (0.06, 0.9, 0.04), (x, 1.05, -0.3))
    m.empty("Tag", 0.0, 1.95, -0.29)


def horseshoe(m, col):  # lucky_strike: a giant horseshoe arch, nail holes lit, on a stone step
    plinth(m, 1.8, 0.6)
    iron = K("metal", tint(col, 0.5, (0.3, 0.3, 0.32)))
    pts = []
    for k in range(15):
        a = math.radians(-20 + k * 220 / 14)
        pts.append((math.cos(a) * 0.72, 1.55 + math.sin(a) * 0.95, 0.0))
    pts = [(0.62, 0.12, 0.0)] + [(x, y, f) for x, y, f in reversed(pts)][::-1]
    pts = [(0.66, 0.12, 0.0)] + [(math.cos(math.radians(a)) * 0.72, 1.4 + math.sin(math.radians(a)) * 1.0, 0.0) for a in range(-15, 196, 15)] + [(-0.66, 0.12, 0.0)]
    for p0, p1 in zip(pts, pts[1:]):
        m.rod(iron, 0.13, p0, p1, segs=8)
    for k in range(7):
        a = math.radians(5 + k * 170 / 6)
        m.cyl(K("paint", WHITE), 0.045, -0.12, -0.15, y=1.4 + math.sin(a) * 1.0, x=math.cos(a) * 0.72, segs=8, node="Glow")
    m.box(K("wood", (0.55, 0.42, 0.27)), (0.7, 0.32, 0.05), (0.0, 1.0, 0.0))
    m.empty("Tag", 0.0, 1.0, -0.04)


def heart(m, col):  # quick_revive: a big heart with a white cross on a pedestal
    plinth(m, 0.9, 0.9, (0.9, 0.9, 0.9))
    m.rod(K("metal", (0.8, 0.8, 0.82)), 0.1, (0.0, 0.12, 0.0), (0.0, 1.05, 0.0))
    red = K("paint", tint(col, 0.9))
    for x in (-0.3, 0.3):
        m.ball(red, (0.45, 0.45, 0.3), (x, 1.95, 0.0), u=16, v=12)
    m.loft(red, [(0.0, 1.05, 0.0, 0.02, 0.05), (0.0, 1.4, 0.0, 0.4, 0.22), (0.0, 1.8, 0.0, 0.72, 0.29)], segs=12, steps=2)
    m.box(K("paint", WHITE), (0.14, 0.46, 0.03), (0.0, 1.78, -0.32), node="Glow")
    m.box(K("paint", WHITE), (0.42, 0.14, 0.03), (0.0, 1.8, -0.32), node="Glow")
    m.empty("Tag", 0.0, 0.8, -0.13)


SHAPES = {
    "second_wind": lighthouse, "hair_trigger": bullet, "trade_winds": windmill, "blast_proof": bomb, "iron_gut": stove,
    "steady_hand": obelisk, "deep_pockets": chest, "run_and_gun": stopwatch, "quickhands": hourglass, "scavenger": claw,
    "backdraft": kiln, "thick_skin": shield, "cold_blood": crystals, "third_holster": gun_cabinet, "lucky_strike": horseshoe,
    "quick_revive": heart,
}


def main():
    fk.init()
    os.makedirs(OUT, exist_ok=True)
    only = sys.argv[1:]
    for pid, build in SHAPES.items():
        if only and pid not in only:
            continue
        m = kit.Model("perk_" + pid, uv_scale=2.0, colored=True)
        m.node("Glow", (0.0, 0.0, 0.0))
        if pid == "trade_winds":
            m.node("Spin", (0.0, 2.15, -0.4))
        build(m, PERKS[pid]["color"])
        print("perk_" + pid, m.export(OUT))


if __name__ == "__main__":
    main()
