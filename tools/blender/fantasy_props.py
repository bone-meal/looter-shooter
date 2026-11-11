# Purpose: developer-time script. Models the fantasy world's buildings, crafting stations and nature with
# tools/blender/kit.py into assets/models/fantasy/<id>.gltf: the large farmhouse of the painting, a windmill with turning
# "Sails", cottages and halls in one colour scheme per region, well, market stall, forge, workbench, cauldron, fence,
# haystack, signpost, standing stone, campfire, trees, ore rocks, herbs, wheat, a pond. Every part is named after what
# it is made of (plaster, timber, roof, stone, bark, leaf ...) and carries its own colour, see fantasy_kit.py.
# Model space: x right, y up, f forward. The things people own and use are in fantasy_life.py.
# Run: python3 tools/blender/fantasy_props.py   (from the project folder; needs pip packages bpy, numpy, pillow)
import math
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
import kit
import fantasy_kit
import fantasy_house as fh
from fantasy_kit import K, S, c, SCHEMES, house, init, Maker


def tree(m, trunk, leaves, height, spread, kind="round"):
    bark = K("pinebark" if kind == "pine" else "bark", trunk)
    if kind == "palm":
        pts = [(0.0, 0.0, 0.0, 0.2, 0.2), (0.15, height * 0.4, 0.05, 0.15, 0.15), (0.5, height * 0.8, 0.1, 0.12, 0.12), (0.8, height, 0.1, 0.1, 0.1)]
        m.loft(bark, pts, segs=7, steps=3)
        for k in range(7):
            a = k * 2 * math.pi / 7
            tip = (0.8 + math.cos(a) * spread, height - 0.9, 0.1 + math.sin(a) * spread)
            mid = (0.8 + math.cos(a) * spread * 0.55, height + 0.35, 0.1 + math.sin(a) * spread * 0.55)
            m.loft(K("leaf", leaves[k % len(leaves)]), [(0.8, height, 0.1, 0.1, 0.05), mid + (0.34, 0.05), tip + (0.08, 0.03)], segs=5, steps=3)
        return
    if kind == "pine":
        m.loft(bark, [(0, 0, 0, 0.22, 0.22), (0, height * 0.9, 0, 0.06, 0.06)], segs=7, steps=2)
        for k in range(4):
            y = height * (0.25 + 0.2 * k)
            r = spread * (1.0 - 0.2 * k)
            m.lathe(K("leaf", leaves[k % len(leaves)]), [(r, y), (r * 0.45, y + height * 0.18), (0.02, y + height * 0.34)], (0, 0, 0), segs=8)
        return
    m.loft(bark, [(0, 0, 0, 0.3, 0.3), (0.05, height * 0.3, 0.0, 0.2, 0.2), (0.0, height * 0.55, 0.05, 0.16, 0.16)], segs=8, steps=3)
    for k, (dx, df) in enumerate(((0.5, 0.1), (-0.45, 0.2), (0.1, -0.5))):
        m.rod(bark, 0.09, (0, height * 0.5, 0), (dx * spread, height * 0.72, df * spread), r2=0.04, segs=5)
    if kind == "dead":
        for k in range(5):
            a = k * 1.3
            m.rod(bark, 0.05, (0.4 * math.cos(a), height * 0.7, 0.4 * math.sin(a)), (1.2 * math.cos(a) * spread * 0.6, height * (0.85 + 0.05 * k), 1.2 * math.sin(a) * spread * 0.6), r2=0.01, segs=4)
        return
    puffs = [(0, 0.82, 0, 1.0), (0.55, 0.72, 0.15, 0.72), (-0.5, 0.74, 0.25, 0.7), (0.1, 0.7, -0.55, 0.68), (-0.15, 0.95, -0.1, 0.62), (0.3, 0.92, 0.35, 0.55),
        (0.75, 0.6, -0.3, 0.45), (-0.7, 0.62, -0.25, 0.48), (-0.2, 0.6, 0.7, 0.46), (0.45, 0.62, 0.6, 0.42), (0.0, 1.05, 0.2, 0.4), (-0.4, 0.9, -0.45, 0.44)]
    for k, (dx, hy, df, r) in enumerate(puffs):
        fantasy_kit.blob(m, K("leaf", leaves[k % len(leaves)]), (spread * r * 0.62, spread * r * 0.5, spread * r * 0.62), (dx * spread, height * hy, df * spread), seed=k * 7 + int(height * 10))
    for k in range(4):  # roots spreading at the foot
        a = k * 1.6 + 0.3
        m.rod(bark, 0.12, (0, 0.25, 0), (math.cos(a) * 0.7, -0.05, math.sin(a) * 0.7), r2=0.04, segs=5)


def rock(m, base, ore, n=5, size=0.6):
    for k in range(n):
        a = k * 2.4
        r = size * (0.5 + 0.5 * ((k * 37) % 10) / 10.0)
        m.ball(K("rock", base), (r, r * 0.8, r * 0.9), (math.cos(a) * size * 0.6 * (k > 0), r * 0.5, math.sin(a) * size * 0.6 * (k > 0)), yaw=k * 40, u=7, v=5)
    for k in range(6):
        a = k * 1.1
        m.ball(c(ore), (0.1, 0.07, 0.1), (math.cos(a) * size * 0.75, size * (0.35 + 0.1 * (k % 3)), math.sin(a) * size * 0.75), u=5, v=4)


def crystal(m, color, n=5, size=1.0):
    m.ball(c((0.5, 0.52, 0.6)), (0.7 * size, 0.3 * size, 0.7 * size), (0, 0.1, 0), u=8, v=5)
    for k in range(n):
        a = k * 2 * math.pi / n
        tip = (math.cos(a) * 0.5 * size, size * (0.9 + 0.5 * (k % 2)), math.sin(a) * 0.5 * size)
        m.rod(c(color), 0.16 * size, (math.cos(a) * 0.25 * size, 0.1, math.sin(a) * 0.25 * size), tip, r2=0.02, segs=5)


def build_all():
    init()
    maker = Maker()
    glow = fantasy_kit.GLOW
    SOFT = ("fence", "haystack", "signpost", "campfire", "herb_", "wheat_sheaf", "ripples")  # things you can walk through or step over

    def model(name, build, uv=0.5, plain=False):  # plain: a building, which also gets its plain model for the low graphics tiers
        maker.model(name, build, solid=not name.startswith(SOFT), uv=uv, plain=plain)

    amber = SCHEMES["amber"]
    # --- the painting's farmhouse: L-shaped, two floors, with a barn wing ---
    def farmhouse(m):
        house(m, amber, 11.0, 7.0, 2, 3.4, door_x=-2.0)
        # barn wing at a right angle, framed like the house, its gable and great doors to the yard
        m.shift = (8.4, 0.0, 2.5)
        with fantasy_kit.weathered():
            m.box(S(amber, "stone"), (6.2, 0.6, 9.2), (0, 0.3, 0), bevel=0.04)
            m.box(S(amber, "wall"), (6.0, 3.6, 9.0), (0, 2.4, 0), bevel=0.0)
            for name, plane, half in (("front", 4.5, 3.0), ("back", 4.5, 3.0), ("right", 3.0, 4.5), ("left", 3.0, 4.5)):
                fh.timber_face(fh.Face(m, name, plane, half), amber, 0.6, 3.6, gap=(0.0, 2.9) if name == "front" else None)
            fh.gable_roof(m, amber, 3.0, 4.5, 4.2, 2.6, front=True)
            fh.great_doors(fh.Face(m, "front", 4.5, 3.0), amber, 0.0, 0.15, 2.8, 3.2)
        m.shift = None
        m.walls.append([8.4, -2.5, 6.2, 9.2])
        m.cyl(S(amber, "timber"), 0.5, 3.9, 4.8, y=0.5, x=3.2, segs=10)  # rain barrel on its side... a trough
    model("farmhouse", farmhouse, plain=True)

    def windmill(m):
        m.lathe(S(amber, "stone"), [(2.6, 0.0), (2.5, 1.2)], (0, 0, 0), segs=12)
        m.lathe(S(amber, "wall"), [(2.4, 1.2), (1.7, 8.0)], (0, 0, 0), segs=12)
        m.lathe(S(amber, "roof"), [(2.0, 8.0), (1.2, 9.2), (0.05, 10.2)], (0, 0, 0), segs=12)
        m.box(S(amber, "trim"), (0.9, 1.9, 0.2), (0, 1.5, 2.45), bevel=0.03)
        for y in (4.0, 6.4):
            m.box(c((0.35, 0.5, 0.65)), (0.6, 0.8, 0.2), (0, y, 2.12 - (y - 1.2) * 0.103), bevel=0.02)
        m.cyl(S(amber, "timber"), 0.22, 1.2, 2.6, y=8.3, x=0, segs=8)
        m.node("Sails", (0, 8.3, 2.5))
        m.cyl(S(amber, "timber"), 0.35, 2.4, 2.7, y=8.3, x=0, segs=8, node="Sails")
        for k in range(4):
            a = k * math.pi / 2
            dx, dy = math.cos(a), math.sin(a)
            m.rod(S(amber, "timber"), 0.09, (0, 8.3, 2.6), (dx * 6.2, 8.3 + dy * 6.2, 2.6), node="Sails", segs=4)
            for j in range(1, 6):
                t = 1.0 + j
                px, py = dx * t, dy * t
                m.rod(c((0.92, 0.9, 0.82)), 0.5, (px - dy * 0.0, 8.3 + py, 2.62), (px - dy * 1.2, 8.3 + py + dx * 1.2, 2.62), node="Sails", segs=4)
    model("windmill", windmill)

    for scheme, s in SCHEMES.items():
        model("cottage_" + scheme, lambda m, s=s: house(m, s, 6.0, 5.0, 1, 2.6), plain=True)
        model("hall_" + scheme, lambda m, s=s: house(m, s, 10.0, 6.5, 2, 3.2, door_x=1.5), plain=True)

    def well(m):
        m.lathe(S(amber, "stone"), [(1.0, 0.0), (1.0, 0.9), (0.8, 0.9), (0.8, 0.1)], (0, 0, 0), segs=10)
        m.ball(c((0.2, 0.4, 0.6)), (0.78, 0.05, 0.78), (0, 0.5, 0), u=10, v=4)
        for sx in (-1, 1):
            m.box(S(amber, "timber"), (0.14, 2.2, 0.14), (sx * 0.95, 1.1, 0), bevel=0.02)
        m.prof(S(amber, "roof"), 2.4, [(-0.9, 2.1), (0, 2.8), (0.9, 2.1)], x=0, bevel=0.04)
        m.cylx(S(amber, "timber"), 0.1, -0.95, 0.95, 0, 1.8, segs=6)
    model("well", well)

    def stall(m):
        for sx in (-1, 1):
            for sf in (-1, 1):
                m.box(S(amber, "timber"), (0.1, 2.3 + 0.3 * (sf < 0), 0.1), (sx * 1.3, 1.15 + 0.15 * (sf < 0), sf * 0.8), bevel=0.015)
        m.box(S(amber, "timber"), (2.8, 0.1, 1.8), (0, 0.95, 0), bevel=0.02)
        for k in range(6):  # striped awning
            col = (0.85, 0.3, 0.3) if k % 2 else (0.95, 0.92, 0.85)
            m.box(K("cloth", col), (0.47, 0.06, 2.0), (-1.18 + k * 0.47, 2.42, 0.0), tilt=-9, bevel=0.01)
        for k, col in enumerate(((0.9, 0.3, 0.2), (0.95, 0.75, 0.2), (0.4, 0.7, 0.3), (0.85, 0.5, 0.2))):
            m.box(S(amber, "timber"), (0.55, 0.3, 0.5), (-0.95 + k * 0.63, 1.15, 0.2), bevel=0.02)
            for j in range(4):
                m.ball(c(col), 0.1, (-1.1 + k * 0.63 + 0.14 * (j % 2), 1.36, 0.1 + 0.16 * (j // 2)), u=6, v=4)
    model("stall", stall)

    def forge(m):
        m.box(S(amber, "stone"), (2.2, 1.0, 1.6), (0, 0.5, 0), bevel=0.05)
        m.box(S(amber, "stone"), (1.0, 3.4, 1.0), (-0.5, 1.7, -0.25), bevel=0.05)
        m.box(c((0.1, 0.08, 0.08)), (1.0, 0.25, 1.0), (0.45, 1.05, 0.1), bevel=0.02)
        m.box(glow, (0.8, 0.12, 0.8), (0.45, 1.16, 0.1), bevel=0.02)
        m.box(S(amber, "timber"), (0.5, 0.6, 0.5), (1.9, 0.3, 0.6), bevel=0.04)  # anvil block
        m.prof(c((0.25, 0.26, 0.3)), 0.3, [(0.25, 0.6), (1.0, 0.6), (1.15, 0.78), (0.3, 0.86), (0.05, 0.8)], x=1.9, bevel=0.02)
    model("forge", forge)

    def workbench(m):
        m.box(S(amber, "timber"), (2.2, 0.12, 0.9), (0, 0.95, 0), bevel=0.02)
        for sx in (-1, 1):
            for sf in (-1, 1):
                m.box(S(amber, "timber"), (0.12, 0.9, 0.12), (sx * 0.95, 0.45, sf * 0.35), bevel=0.02)
        m.box(c((0.7, 0.7, 0.72)), (0.5, 0.06, 0.08), (-0.4, 1.04, 0.1), bevel=0.01)  # saw
        m.rod(c((0.6, 0.45, 0.25)), 0.05, (0.2, 1.03, -0.2), (0.9, 1.03, 0.15), segs=6)  # a staff in the making
        m.ball(c((0.4, 0.8, 1.0)), 0.07, (0.92, 1.05, 0.16), u=6, v=4)
    model("workbench", workbench)

    def cauldron(m):
        m.lathe(K("metal", (0.2, 0.2, 0.22)), [(0.3, 0.25), (0.62, 0.5), (0.66, 0.9), (0.55, 1.05), (0.6, 1.1)], (0, 0, 0), segs=12)
        m.ball(glow, (0.52, 0.04, 0.52), (0, 1.02, 0), u=10, v=4)
        for k in range(3):
            a = k * 2.1
            m.rod(c((0.12, 0.12, 0.14)), 0.05, (math.cos(a) * 0.4, 0.4, math.sin(a) * 0.4), (math.cos(a) * 0.6, 0.0, math.sin(a) * 0.6), segs=5)
        for k in range(4):
            a = k * 1.57
            m.rod(S(amber, "timber"), 0.07, (math.cos(a) * 0.7, 0.05, math.sin(a) * 0.7), (-math.cos(a) * 0.5, 0.12, -math.sin(a) * 0.5), segs=5)
    model("cauldron", cauldron)

    def campfire(m):
        for k in range(8):
            a = k * 0.785
            m.ball(S(amber, "stone"), (0.16, 0.12, 0.16), (math.cos(a) * 0.55, 0.08, math.sin(a) * 0.55), u=6, v=4)
        for k in range(4):
            a = k * 1.57 + 0.4
            m.rod(c((0.3, 0.2, 0.12)), 0.08, (math.cos(a) * 0.45, 0.06, math.sin(a) * 0.45), (-math.cos(a) * 0.1, 0.4, -math.sin(a) * 0.1), segs=5)
        m.loft(glow, [(0, 0.1, 0, 0.3, 0.3), (0.03, 0.5, 0.0, 0.2, 0.2), (0, 1.0, 0.02, 0.03, 0.03)], segs=7, steps=3)
    model("campfire", campfire)

    def fence(m):
        for sx in (-1, 1):
            m.box(S(amber, "timber"), (0.12, 1.1, 0.12), (sx * 1.4, 0.55, 0), bevel=0.02)
        for y in (0.45, 0.85):
            m.box(S(amber, "timber"), (3.0, 0.1, 0.06), (0, y, 0), bevel=0.015)
    model("fence", fence)
    model("haystack", lambda m: m.lathe(K("thatch", (0.86, 0.72, 0.3)), [(1.3, 0.0), (1.35, 0.7), (1.0, 1.5), (0.4, 2.0), (0.05, 2.15)], (0, 0, 0), segs=10))

    def signpost(m):
        m.box(S(amber, "timber"), (0.12, 2.4, 0.12), (0, 1.2, 0), bevel=0.02)
        m.prof(c((0.8, 0.68, 0.45)), 0.06, [(-0.1, 2.0), (0.9, 2.0), (1.1, 2.15), (0.9, 2.3), (-0.1, 2.3)], x=0, bevel=0.01)
        m.prof(c((0.8, 0.68, 0.45)), 0.06, [(0.1, 1.55), (-0.9, 1.55), (-1.1, 1.7), (-0.9, 1.85), (0.1, 1.85)], x=0.07, bevel=0.01)
    model("signpost", signpost)

    def standing_stone(m):
        m.loft(K("rock", (0.5, 0.5, 0.56)), [(0, 0, 0, 0.7, 0.45), (0.05, 1.6, 0, 0.6, 0.4), (0.1, 3.2, 0.05, 0.4, 0.3)], segs=6, steps=2)
        for k in range(3):
            m.box(glow, (0.3, 0.06, 0.03), (0.05, 1.2 + 0.5 * k, 0.4 - 0.03 * k), bevel=0)
    model("standing_stone", standing_stone)

    def arena_pillar(m):
        m.lathe(K("stone", (0.6, 0.58, 0.54)), [(0.8, 0.0), (0.6, 0.4), (0.5, 3.6), (0.7, 4.0), (0.7, 4.3)], (0, 0, 0), segs=8)
        m.ball(glow, 0.3, (0, 4.6, 0), u=8, v=6)
    model("arena_pillar", arena_pillar)

    # --- trees, one model each (instanced many times) ---
    model("tree_ash", lambda m: tree(m, (0.5, 0.42, 0.32), [(0.62, 0.74, 0.25), (0.72, 0.78, 0.28), (0.52, 0.66, 0.22)], 5.0, 2.4))
    model("tree_oak", lambda m: tree(m, (0.33, 0.24, 0.16), [(0.18, 0.42, 0.16), (0.24, 0.5, 0.2), (0.14, 0.36, 0.14)], 8.5, 4.2))
    model("tree_palm", lambda m: tree(m, (0.6, 0.48, 0.32), [(0.25, 0.6, 0.25), (0.3, 0.66, 0.3)], 6.5, 2.6, "palm"))
    model("tree_pine", lambda m: tree(m, (0.35, 0.26, 0.2), [(0.2, 0.4, 0.34), (0.8, 0.9, 0.96), (0.24, 0.46, 0.38), (0.86, 0.93, 1.0)], 8.0, 2.4, "pine"))
    model("tree_ember", lambda m: tree(m, (0.14, 0.1, 0.1), [(0.9, 0.35, 0.1), (1.0, 0.55, 0.15), (0.7, 0.2, 0.08)], 6.0, 2.8))
    model("tree_dead", lambda m: tree(m, (0.7, 0.7, 0.7), [(0.8, 0.8, 0.8)], 5.5, 2.4, "dead"))
    # --- ore, herbs, crops, water ---
    model("rock_copper", lambda m: rock(m, (0.5, 0.46, 0.42), (0.85, 0.45, 0.25)))
    model("rock_iron", lambda m: rock(m, (0.42, 0.42, 0.44), (0.62, 0.3, 0.2)))
    model("rock_sunstone", lambda m: rock(m, (0.75, 0.6, 0.4), (1.0, 0.85, 0.3)))
    model("rock_obsidian", lambda m: rock(m, (0.1, 0.09, 0.12), (0.5, 0.1, 0.6)))
    model("rock_skysteel", lambda m: rock(m, (0.45, 0.47, 0.55), (0.6, 0.8, 1.0)))
    model("rock_plain", lambda m: rock(m, (0.55, 0.54, 0.5), (0.5, 0.5, 0.46), n=4, size=1.0))
    model("rock_crystal", lambda m: crystal(m, (0.6, 0.9, 1.0)))

    def herb(m, leaf, flower):
        for k in range(6):
            a = k * 1.05
            m.loft(c(leaf), [(0, 0.02, 0, 0.03, 0.02), (math.cos(a) * 0.14, 0.2, math.sin(a) * 0.14, 0.07, 0.02), (math.cos(a) * 0.3, 0.26, math.sin(a) * 0.3, 0.02, 0.01)], segs=4, steps=2)
        for k in range(3):
            a = k * 2.1 + 0.5
            m.rod(c(leaf), 0.012, (0, 0.05, 0), (math.cos(a) * 0.08, 0.42, math.sin(a) * 0.08), segs=4)
            m.ball(c(flower), 0.06, (math.cos(a) * 0.08, 0.45, math.sin(a) * 0.08), u=6, v=4)
    model("herb_green", lambda m: herb(m, (0.3, 0.65, 0.3), (0.75, 0.95, 0.8)))
    model("herb_yellow", lambda m: herb(m, (0.5, 0.6, 0.25), (1.0, 0.85, 0.2)))
    model("herb_blue", lambda m: herb(m, (0.6, 0.75, 0.8), (0.5, 0.75, 1.0)))
    model("herb_red", lambda m: herb(m, (0.3, 0.2, 0.18), (1.0, 0.35, 0.15)))

    def mushroom(m):
        for k, (dx, df, s) in enumerate(((0, 0, 1.0), (0.18, 0.1, 0.7), (-0.12, 0.16, 0.55))):
            m.rod(c((0.9, 0.88, 0.8)), 0.035 * s, (dx, 0, df), (dx, 0.22 * s, df), segs=5)
            m.ball(glow, (0.12 * s, 0.07 * s, 0.12 * s), (dx, 0.25 * s, df), u=7, v=4)
    model("herb_mushroom", mushroom)

    def sheaf(m):
        for k in range(9):
            a = k * 0.7
            r = 0.05 + 0.03 * (k % 3)
            m.rod(c((0.86, 0.7, 0.28)), 0.012, (math.cos(a) * r, 0, math.sin(a) * r), (math.cos(a) * r * 2.6, 0.95, math.sin(a) * r * 2.6), segs=3)
            m.ball(c((0.95, 0.8, 0.35)), (0.03, 0.09, 0.03), (math.cos(a) * r * 2.8, 1.02, math.sin(a) * r * 2.8), u=4, v=3)
    model("wheat_sheaf", sheaf)

    def ripples(m):  # rings on the water where fish rise (floats on real water: lakes, ponds, the sea)
        for r in (0.35, 0.7, 1.05):
            m.lathe(c((0.85, 0.95, 1.0)), [(r, 0.0), (r + 0.05, 0.012), (r + 0.1, 0.0)], (0.0, 0, 0.0), segs=14)
    model("ripples", ripples)
    maker.plain_pass()
    maker.save()


if __name__ == "__main__":
    import bpy
    bpy.ops.wm.read_factory_settings(use_empty=True)
    build_all()
