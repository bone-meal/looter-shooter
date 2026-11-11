# Purpose: developer-time script. Models the things people in the fantasy world live with, so every place shows who
# lives there and what they do: town houses and shops per region, barn, granary, chapel, sheds, walls and gates, carts,
# barrels, crates, sacks, tools, benches, lamps, laundry, wood piles, ploughs, troughs, scarecrows, coops, hives,
# vegetable beds, fountain; boats, docks, nets and fish racks for the coast; tents, banners, palisades, weapon racks and
# pottery for the desert tribes; cabins, sleds and drying racks for the north; anvils and slag for the volcano; bells,
# flags and cairns for the heights; ruins, statues and easels for the colourless court. Output:
# assets/models/fantasy/<id>.gltf and data/fantasy/props.json. Model space: x right, y up, f forward.
# Run: python3 tools/blender/fantasy_life.py   (from the project folder; needs pip packages bpy, numpy, pillow)
import math
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
import fantasy_house
import fantasy_kit
import fantasy_walls
from fantasy_kit import K, S, c, SCHEMES, house, init, Maker, blob, WOOD, DARK, IRON, GREY, CLOTH, STRAW, ROPE


def ring(n, r, start=0.0):
    return [(math.cos(start + k * 2 * math.pi / n) * r, math.sin(start + k * 2 * math.pi / n) * r) for k in range(n)]


def post(m, mat, x, f, h, r=0.07, y0=0.0, node="Body"):
    m.rod(mat, r, (x, y0, f), (x, y0 + h, f), node=node, segs=6)


def barrel_at(m, x, f, y=0.0, s=1.0):
    m.lathe(K("wood", WOOD), [(0.3 * s, 0.0), (0.38 * s, 0.25 * s), (0.4 * s, 0.5 * s), (0.38 * s, 0.75 * s), (0.3 * s, 1.0 * s)], (x, y, f), segs=10)
    for h in (0.2, 0.8):
        m.lathe(K("metal", IRON), [(0.375 * s, (h - 0.03) * s), (0.385 * s, (h + 0.03) * s)], (x, y, f), segs=10)


def crate_at(m, x, f, y=0.0, s=0.7, yaw=0.0):
    m.box(K("wood", WOOD), (s, s, s), (x, y + s / 2, f), bevel=0.02)
    for sx in (-1, 1):
        m.box(K("wood", DARK), (0.06, s + 0.02, s + 0.02), (x + sx * (s / 2 - 0.05), y + s / 2, f), bevel=0.01)


def sack_at(m, x, f, y=0.0, col=CLOTH, seed=0):
    blob(m, K("cloth", col), (0.3, 0.22, 0.4), (x, y + 0.2, f), seed=seed, rough=0.12)


def build_all():
    init()
    maker = Maker()
    glow = fantasy_kit.GLOW
    SOFT = ("laundry", "rug", "veg_patch", "prayer_flags", "bone_pile", "nets", "banner_", "crop_rows", "path_stones")

    def model(name, build):
        maker.model(name, build, solid=not name.startswith(SOFT))

    # ---------- town houses and shops, one per region scheme ----------
    def townhouse(m, s):  # tall and narrow, its gable to the street, each floor jutting out over the one below
        house(m, s, 5.2, 6.2, 3, 3.0, door_x=-1.0, gable_front=True)
        m.box(S(s, "timber"), (0.2, 0.24, 1.3), (0, 10.55, 4.3), bevel=0.0)  # a hoist beam out of the gable
        m.rod(K("cloth", ROPE), 0.02, (0, 10.45, 4.85), (0, 8.9, 4.85), segs=4)
        m.ball(K("metal", IRON), 0.07, (0, 8.85, 4.85), u=5, v=3)

    def shop(m, s):  # a workshop with an open counter, a hanging sign and goods outside
        house(m, s, 7.2, 5.6, 2, 2.8, door_x=-2.2)
        m.box(S(s, "timber"), (2.8, 0.1, 0.8), (1.7, 1.5, 3.3), bevel=0.0)  # counter under the window
        for sx in (0.5, 2.9):
            m.rod(S(s, "timber"), 0.05, (sx, 0.9, 2.95), (sx, 1.45, 3.6), segs=4)
        m.strip(K("cloth", s["trim"]), 3.2, 0.04, [(3.2, 3.0), (4.4, 2.45)], x=1.7)  # awning
        for sx in (0.2, 3.2):
            post(m, S(s, "timber"), sx, 4.35, 2.45, 0.05)
        m.rod(K("metal", IRON), 0.03, (-3.4, 4.6, 3.15), (-3.4, 4.6, 4.15), segs=4)  # sign bracket
        m.box(S(s, "trim"), (0.08, 0.7, 0.9), (-3.4, 4.15, 3.7), bevel=0.0)
        m.box(K("paint", (0.95, 0.85, 0.5)), (0.1, 0.4, 0.5), (-3.4, 4.15, 3.7), bevel=0.0)
        barrel_at(m, 3.3, 3.5)
        crate_at(m, 0.5, 4.0, s=0.6)
        sack_at(m, 2.4, 4.1, seed=3)
        m.walls.append([1.75, -3.7, 3.6, 1.5])  # the goods under the awning are in the way too

    for scheme, s in SCHEMES.items():
        model("townhouse_" + scheme, lambda m, s=s: townhouse(m, s))
        model("shop_" + scheme, lambda m, s=s: shop(m, s))

    amber = SCHEMES["amber"]

    # ---------- farm and village buildings ----------
    def barn(m):  # framed in oak, boarded between the posts, its gable and great doors to the yard
        with fantasy_kit.weathered():
            m.box(K("stone", GREY), (9.2, 0.6, 12.2), (0, 0.3, 0), bevel=0.04)
            m.box(S(fantasy_walls.BARN, "wall"), (9.0, 4.2, 12.0), (0, 2.7, 0), bevel=0.0)
            for name, plane, half in (("front", 6.0, 4.5), ("back", 6.0, 4.5), ("right", 4.5, 6.0), ("left", 4.5, 6.0)):
                face = fantasy_house.Face(m, name, plane, half)
                fantasy_house.timber_face(face, fantasy_walls.BARN, 0.6, 4.2, gap=(0.0, 3.7) if name == "front" else None)
                face.box(K("timber", DARK), 2 * half - (3.9 if name == "front" else 0.0), 0.14, 0.08, (half - 1.3) if name == "front" else 0.0, 3.4, 0.03)  # a second rail high up
            front = fantasy_house.Face(m, "front", 6.0, 4.5)
            fantasy_house.great_doors(front, fantasy_walls.BARN, 0.0, 0.15, 3.5, 3.6)
            fantasy_house.gable_roof(m, fantasy_walls.BARN, 4.5, 6.0, 4.8, 3.2, front=True, gable_window=False)
            front.box(K("wood", DARK), 1.3, 1.3, 0.1, 0.0, 5.9, 0.07)  # hay loft door
            front.box(K("timber", DARK), 1.5, 0.14, 0.12, 0.0, 6.62, 0.08)
            m.box(K("timber", DARK), (0.2, 0.22, 1.5), (0, 7.05, 6.6), bevel=0.0)  # hoist beam
            m.rod(K("cloth", ROPE), 0.02, (0, 6.95, 7.25), (0, 5.6, 7.25), segs=4)
        blob(m, K("thatch", STRAW), (1.4, 0.9, 1.2), (3.2, 0.7, 7.2), seed=5)
        m.walls = [[0.0, 0.0, 9.2, 12.2]]
    model("barn", barn)

    def granary(m):
        m.lathe(K("stone", GREY), [(2.3, 0.0), (2.2, 1.0)], (0, 0, 0), segs=12)
        m.lathe(K("plaster", (0.9, 0.86, 0.74)), [(2.1, 1.0), (2.1, 4.6)], (0, 0, 0), segs=12)
        m.lathe(K("thatch", (0.7, 0.58, 0.3)), [(2.7, 4.3), (1.6, 5.8), (0.1, 7.2)], (0, 0, 0), segs=12)
        m.box(K("wood", DARK), (1.0, 1.8, 0.2), (0, 1.9, 2.1), bevel=0.03)
        for k in range(5):
            m.box(K("wood", WOOD), (1.0, 0.08, 0.5), (0, 0.2 + k * 0.2, 2.5 + (4 - k) * 0.25), bevel=0.01)  # steps
    model("granary", granary)

    model("chapel", fantasy_walls.chapel)

    def shed(m):  # open-sided: smithy, stable, market cover
        for sx in (-1, 1):
            for sf in (-1, 1):
                post(m, K("timber", DARK), sx * 2.6, sf * 1.9, 2.6 + (0.6 if sf < 0 else 0.0), 0.11)
        m.prof(K("slate", (0.4, 0.38, 0.4)), 6.2, [(-2.4, 3.3), (2.4, 2.6), (2.45, 2.5), (-2.4, 3.2)], x=0, bevel=0.01)
        m.box(K("timber", DARK), (5.6, 0.16, 0.16), (0, 2.55, 1.9), bevel=0.02)
        m.box(K("wood", WOOD), (5.4, 1.2, 0.08), (0, 0.7, -1.9), bevel=0.01)
    model("shed", shed)

    def watchtower(m):
        for x, f in ring(4, 2.0, math.pi / 4):
            m.rod(K("timber", DARK), 0.16, (x, 0, f), (x * 0.75, 7.0, f * 0.75), segs=6)
        m.box(K("wood", WOOD), (3.6, 0.16, 3.6), (0, 7.0, 0), bevel=0.02)
        for x, f in ring(4, 1.7, math.pi / 4):
            post(m, K("timber", DARK), x, f, 2.2, 0.08, y0=7.0)
        for a in (0, 1, 2, 3):
            dx, df = math.cos(a * math.pi / 2), math.sin(a * math.pi / 2)
            m.box(K("wood", WOOD), (3.4 if df else 0.08, 0.9, 0.08 if df else 3.4), (dx * 1.7, 7.5, df * 1.7), bevel=0.01)
        m.lathe(K("thatch", (0.66, 0.55, 0.3)), [(2.9, 9.0), (0.1, 10.8)], (0, 0, 0), segs=4)
        for k in range(8):  # ladder
            m.box(K("wood", WOOD), (0.6, 0.05, 0.05), (0, 0.5 + k * 0.8, 1.8 - k * 0.06), bevel=0)
    model("watchtower", watchtower)

    model("town_wall", fantasy_walls.town_wall)  # one 6 m stretch with a walk and teeth along the top
    maker.sizes["town_wall"]["w"] = 6.0  # stretches stand 6 m apart; the end piers reach a little further so a curve closes up
    model("town_gate", fantasy_walls.town_gate)
    maker.sizes["town_gate"].update({"walls": [[3.6, 0, 2.6, 2.6], [-3.6, 0, 2.6, 2.6]], "wall_h": 6.0})  # only the two towers are solid: the arch is open

    # ---------- what stands in yards and streets ----------
    model("barrel", lambda m: (barrel_at(m, 0, 0), barrel_at(m, 0.85, 0.2), barrel_at(m, 0.4, 0.15, y=1.0, s=0.8)))
    model("crate", lambda m: (crate_at(m, 0, 0), crate_at(m, 0.8, 0.1, s=0.6), crate_at(m, 0.1, 0.05, y=0.7, s=0.55)))
    model("sacks", lambda m: [sack_at(m, (k % 3) * 0.5 - 0.5, (k // 3) * 0.45, y=0.0 if k < 5 else 0.35, seed=k) for k in range(7)])

    def cart(m, broken=False):
        m.box(K("wood", WOOD), (1.6, 0.12, 2.8), (0, 0.9, 0), tilt=8 if broken else 0, bevel=0.02)
        for sx in (-1, 1):
            m.box(K("wood", WOOD), (0.08, 0.6, 2.8), (sx * 0.8, 1.25, 0), tilt=8 if broken else 0, bevel=0.01)
        for sx in (-1, 1):
            if broken and sx > 0:
                m.lathe(K("wood", DARK), [(0.6, 0.0), (0.6, 0.1)], (1.6, 0, -0.4), segs=12)  # the lost wheel lies beside it
                continue
            m.cylx(K("wood", DARK), 0.62, sx * 0.9, sx * 1.0, 0.0, 0.62, segs=14)
            m.cylx(K("metal", IRON), 0.12, sx * 0.86, sx * 1.04, 0.0, 0.62, segs=8)
        for sx in (-0.5, 0.5):
            m.rod(K("wood", WOOD), 0.05, (sx, 0.9, 1.4), (sx, 0.5 if not broken else 0.1, 3.4), segs=5)
        sack_at(m, -0.3, -0.5, y=0.95, seed=2)
        sack_at(m, 0.3, 0.2, y=0.95, col=STRAW, seed=4)
    model("cart", cart)
    model("cart_broken", lambda m: cart(m, True))

    def wheelbarrow(m):
        m.prof(K("wood", WOOD), 0.7, [(-0.5, 0.45), (0.6, 0.45), (0.8, 0.9), (-0.6, 0.9)], x=0, bevel=0.02)
        m.cylx(K("wood", DARK), 0.25, -0.06, 0.06, 0.9, 0.25, segs=10)
        for sx in (-0.3, 0.3):
            m.rod(K("wood", WOOD), 0.035, (sx, 0.5, -0.4), (sx, 0.75, -1.4), segs=5)
            post(m, K("wood", WOOD), sx, -0.45, 0.45, 0.03)
    model("wheelbarrow", wheelbarrow)

    def bench(m):
        m.box(K("wood", WOOD), (1.8, 0.08, 0.45), (0, 0.5, 0), bevel=0.02)
        m.box(K("wood", WOOD), (1.8, 0.4, 0.06), (0, 0.9, -0.22), bevel=0.02)
        for sx in (-0.75, 0.75):
            m.box(K("wood", DARK), (0.08, 0.5, 0.4), (sx, 0.25, 0), bevel=0.01)
    model("bench", bench)

    def table(m):
        m.box(K("wood", WOOD), (1.8, 0.08, 0.9), (0, 0.8, 0), bevel=0.02)
        for sx in (-0.75, 0.75):
            for sf in (-0.35, 0.35):
                post(m, K("wood", DARK), sx, sf, 0.8, 0.04)
        for x, f in ((-1.3, 0), (1.3, 0), (0, 0.85), (0, -0.85)):
            m.lathe(K("wood", WOOD), [(0.2, 0.0), (0.2, 0.45), (0.22, 0.5)], (x, 0, f), segs=8)
        for x, f in ((-0.5, 0.1), (0.4, -0.2), (0.1, 0.25)):
            m.lathe(K("metal", (0.5, 0.45, 0.35)), [(0.05, 0.84), (0.06, 0.98)], (x, 0, f), segs=6)  # mugs
        m.lathe(K("paint", (0.8, 0.6, 0.3)), [(0.18, 0.84), (0.2, 0.88), (0.02, 0.96)], (-0.1, 0, -0.1), segs=8)  # a loaf
    model("table", table)

    def lamp_post(m):
        post(m, K("metal", IRON), 0, 0, 3.0, 0.05)
        m.rod(K("metal", IRON), 0.03, (0, 2.9, 0), (0.5, 3.1, 0), segs=4)
        m.box(K("metal", IRON), (0.22, 0.06, 0.22), (0.5, 2.98, 0), bevel=0.01)
        m.box(glow, (0.16, 0.26, 0.16), (0.5, 2.82, 0), bevel=0.02)
    model("lamp_post", lamp_post)

    def laundry(m):
        for sx in (-2.0, 2.0):
            post(m, K("wood", WOOD), sx, 0, 2.1, 0.05)
        m.rod(K("cloth", ROPE), 0.012, (-2.0, 2.0, 0), (2.0, 2.0, 0), segs=4)
        for k, col in enumerate(((0.9, 0.9, 0.86), (0.7, 0.3, 0.25), (0.35, 0.45, 0.65), (0.9, 0.85, 0.7), (0.5, 0.6, 0.4))):
            m.box(K("cloth", col), (0.55, 0.7 + 0.15 * (k % 2), 0.02), (-1.5 + k * 0.75, 1.62 - 0.07 * (k % 2), 0), bevel=0)
    model("laundry", laundry)

    def woodpile(m):
        for row in range(3):
            for k in range(6 - row):
                m.cyl(K("bark", (0.42, 0.32, 0.22)), 0.14, -0.6, 0.6, y=0.14 + row * 0.25, x=-0.75 + k * 0.3 + row * 0.15, segs=7)
        for sx in (-1.0, 1.0):
            post(m, K("wood", DARK), sx, 0, 1.0, 0.04)
    model("woodpile", woodpile)

    def chopping_block(m):
        m.lathe(K("bark", (0.45, 0.34, 0.24)), [(0.35, 0.0), (0.33, 0.5)], (0, 0, 0), segs=9)
        m.rod(K("wood", WOOD), 0.025, (0.05, 0.5, 0.0), (0.4, 1.1, 0.1), segs=5)  # axe left in the block
        m.box(K("metal", IRON), (0.05, 0.2, 0.28), (0.07, 0.55, 0.02), tilt=20, bevel=0.01)
        for k in range(4):
            m.cyl(K("bark", (0.5, 0.4, 0.28)), 0.1, 0.5 + k * 0.05, 0.9 + k * 0.05, y=0.1, x=0.6 + k * 0.22, segs=6)
    model("chopping_block", chopping_block)

    def tool_rack(m):  # the tools of a field: scythe, pitchfork, hoe, rake
        for sx in (-0.9, 0.9):
            post(m, K("wood", DARK), sx, 0, 1.5, 0.05)
        m.box(K("wood", DARK), (1.9, 0.08, 0.06), (0, 1.35, 0), bevel=0.01)
        for k, x in enumerate((-0.6, -0.2, 0.2, 0.6)):
            m.rod(K("wood", WOOD), 0.022, (x, 0.02, 0.35), (x, 1.9, 0.02), segs=5)
        m.loft(K("metal", IRON), [(-0.6, 1.9, 0.02, 0.01, 0.03), (-0.35, 2.0, 0.0, 0.01, 0.045), (-0.05, 1.85, 0.0, 0.006, 0.015)], segs=5, steps=3)  # scythe blade
        for dx in (-0.06, 0.0, 0.06):
            m.rod(K("metal", IRON), 0.01, (-0.2 + dx, 1.9, 0.02), (-0.2 + dx, 2.2, 0.0), segs=4)  # pitchfork
        m.box(K("metal", IRON), (0.18, 0.04, 0.1), (0.2, 1.92, 0.04), bevel=0.005)  # hoe
        m.box(K("wood", WOOD), (0.4, 0.04, 0.04), (0.6, 1.9, 0.02), bevel=0.005)  # rake
        for k in range(5):
            m.rod(K("wood", WOOD), 0.008, (0.44 + k * 0.08, 1.9, 0.02), (0.44 + k * 0.08, 1.9, 0.14), segs=3)
    model("tool_rack", tool_rack)

    def plough(m):
        m.rod(K("wood", WOOD), 0.05, (0, 0.5, -0.9), (0, 0.7, 1.4), segs=6)
        for sx in (-0.25, 0.25):
            m.rod(K("wood", WOOD), 0.035, (0, 0.55, -0.6), (sx, 1.1, -1.5), segs=5)
        m.loft(K("metal", IRON), [(0, 0.5, -0.2, 0.03, 0.2), (0.08, 0.2, 0.05, 0.03, 0.18), (0.12, 0.02, 0.4, 0.01, 0.05)], segs=5, steps=3)
        m.cylx(K("wood", DARK), 0.28, -0.05, 0.05, 1.3, 0.28, segs=10)
    model("plough", plough)

    def trough(m):
        m.prof(K("wood", WOOD), 2.2, [(-0.35, 0.6), (-0.25, 0.15), (0.25, 0.15), (0.35, 0.6), (0.28, 0.6), (0.2, 0.22), (-0.2, 0.22), (-0.28, 0.6)], x=0, bevel=0.01)
        m.box(K("paint", (0.2, 0.36, 0.5)), (2.1, 0.04, 0.5), (0, 0.5, 0), bevel=0)
        for sx in (-0.9, 0.9):
            m.box(K("wood", DARK), (0.1, 0.25, 0.7), (sx, 0.12, 0), bevel=0.01)
    model("trough", trough)

    def scarecrow(m):
        post(m, K("wood", DARK), 0, 0, 2.0, 0.045)
        m.rod(K("wood", DARK), 0.035, (-0.8, 1.5, 0), (0.8, 1.5, 0), segs=5)
        m.loft(K("cloth", (0.5, 0.36, 0.22)), [(0, 0.8, 0, 0.3, 0.16), (0, 1.3, 0, 0.26, 0.15), (0, 1.6, 0, 0.14, 0.1)], segs=8, steps=2)
        blob(m, K("cloth", (0.8, 0.7, 0.5)), (0.17, 0.2, 0.17), (0, 1.82, 0), seed=1, rough=0.08)
        m.lathe(K("thatch", STRAW), [(0.34, 1.96), (0.12, 2.02), (0.02, 2.2)], (0, 0, 0), segs=8)
        for sx in (-0.8, 0.8):
            for k in range(4):
                m.rod(K("thatch", STRAW), 0.012, (sx, 1.5, 0), (sx * 1.15, 1.35 - 0.05 * k, 0.05 * (k - 1.5)), segs=3)
    model("scarecrow", scarecrow)

    def coop(m):
        m.box(K("wood", WOOD), (1.6, 0.9, 1.2), (0, 0.95, 0), bevel=0.02)
        m.prof(K("thatch", (0.66, 0.55, 0.3)), 1.9, [(-0.8, 1.35), (0, 1.9), (0.8, 1.35)], x=0, bevel=0.03)
        for sx in (-0.7, 0.7):
            for sf in (-0.5, 0.5):
                post(m, K("wood", DARK), sx, sf, 0.5, 0.04)
        m.box(K("paint", (0.08, 0.06, 0.05)), (0.35, 0.4, 0.05), (0, 0.8, 0.6), bevel=0.01)
        m.box(K("wood", WOOD), (0.35, 0.04, 0.9), (0, 0.3, 1.0), tilt=-28, bevel=0.01)
        for x, f in ((0.9, 0.9), (-0.6, 1.2), (0.3, 1.5)):  # hens
            blob(m, K("paint", (0.85, 0.8, 0.7)), (0.11, 0.1, 0.16), (x, 0.16, f), seed=int(x * 10), rough=0.06)
            m.ball(K("paint", (0.8, 0.2, 0.15)), 0.035, (x, 0.3, f + 0.13), u=5, v=4)
    model("coop", coop)

    def beehive(m):
        m.box(K("wood", DARK), (0.7, 0.4, 0.7), (0, 0.2, 0), bevel=0.02)
        m.lathe(K("thatch", STRAW), [(0.3, 0.4), (0.34, 0.6), (0.3, 0.85), (0.16, 1.05), (0.03, 1.12)], (0, 0, 0), segs=10)
        m.box(K("paint", (0.1, 0.08, 0.05)), (0.1, 0.06, 0.05), (0, 0.46, 0.31), bevel=0)
    model("beehive", beehive)

    def veg_patch(m):
        for row in range(3):
            m.loft(K("paint", (0.3, 0.22, 0.15)), [(-1.6, 0.0, row * 0.8 - 0.8, 0.28, 0.12), (1.6, 0.0, row * 0.8 - 0.8, 0.28, 0.12)], segs=6, steps=1)
            for k in range(6):
                col = ((0.3, 0.6, 0.25), (0.5, 0.7, 0.3), (0.25, 0.5, 0.3))[row]
                blob(m, K("leaf", col), (0.16, 0.14 + 0.05 * (k % 2), 0.16), (-1.35 + k * 0.54, 0.2, row * 0.8 - 0.8), seed=row * 10 + k, rough=0.25, cuts=1)
    model("veg_patch", veg_patch)

    def crop_rows(m):  # a square of standing wheat, for fields seen from far
        for row in range(5):
            for k in range(5):
                x, f = -2.0 + k * 1.0 + 0.2 * (row % 2), -2.0 + row * 1.0
                blob(m, K("thatch", (0.9, 0.76, 0.34)), (0.42, 0.5, 0.42), (x, 0.5, f), seed=row * 7 + k, rough=0.2, cuts=1)
    model("crop_rows", crop_rows)

    def fountain(m):
        m.lathe(K("stone", GREY), [(2.2, 0.0), (2.2, 0.7), (1.9, 0.7), (1.9, 0.2)], (0, 0, 0), segs=14)
        m.lathe(K("paint", (0.22, 0.42, 0.6)), [(0.0, 0.5), (1.9, 0.5)], (0, 0, 0), segs=14)
        m.lathe(K("stone", (0.66, 0.64, 0.6)), [(0.5, 0.2), (0.3, 1.2), (0.9, 1.7), (0.9, 1.85), (0.25, 1.9), (0.2, 2.6), (0.5, 2.9), (0.05, 3.2)], (0, 0, 0), segs=10)
    model("fountain", fountain)

    def shrine(m):
        post(m, K("stone", GREY), 0, 0, 1.4, 0.22)
        m.box(K("wood", DARK), (0.7, 0.6, 0.5), (0, 1.7, 0), bevel=0.02)
        m.prof(K("slate", (0.4, 0.38, 0.4)), 0.9, [(-0.4, 2.0), (0, 2.4), (0.4, 2.0)], x=0, bevel=0.02)
        m.box(glow, (0.3, 0.3, 0.05), (0, 1.7, 0.26), bevel=0.02)
    model("shrine", shrine)

    def mine_entrance(m):
        for sx in (-1.3, 1.3):
            post(m, K("timber", DARK), sx, 0, 2.6, 0.15)
        m.box(K("timber", DARK), (3.2, 0.3, 0.3), (0, 2.7, 0), bevel=0.03)
        m.box(K("paint", (0.03, 0.03, 0.04)), (2.4, 2.5, 0.2), (0, 1.25, -0.3), bevel=0)
        for k in range(5):
            blob(m, K("rock", (0.5, 0.48, 0.45)), (1.0, 0.9, 0.9), (-2.4 + k * 1.2, 0.8 + (k % 2) * 1.6, -1.0), seed=k)
        m.box(K("metal", IRON), (0.06, 0.04, 3.0), (-0.4, 0.04, 1.4), bevel=0)  # cart rails
        m.box(K("metal", IRON), (0.06, 0.04, 3.0), (0.4, 0.04, 1.4), bevel=0)
        crate_at(m, 1.9, 1.2, s=0.6)
    model("mine_entrance", mine_entrance)

    # ---------- the coast ----------
    def boat(m):
        m.loft(K("wood", (0.5, 0.36, 0.24)), [(0, 0.5, -2.0, 0.05, 0.25), (0, 0.32, -1.0, 0.65, 0.34), (0, 0.3, 0.3, 0.75, 0.36), (0, 0.4, 1.5, 0.4, 0.3), (0, 0.6, 2.1, 0.04, 0.2)], segs=8, steps=3)
        m.box(K("paint", (0.12, 0.09, 0.07)), (1.1, 0.06, 2.6), (0, 0.6, -0.1), bevel=0)
        for f in (-0.8, 0.5):
            m.box(K("wood", WOOD), (1.25, 0.06, 0.25), (0, 0.55, f), bevel=0.01)
        for sx in (-1, 1):
            m.rod(K("wood", WOOD), 0.03, (sx * 0.3, 0.6, -0.2), (sx * 1.6, 0.5, 0.9), segs=5)
    model("boat", boat)

    def dock(m):
        m.box(K("wood", WOOD), (3.0, 0.14, 8.0), (0, 1.0, 0), bevel=0.02)
        for f in (-3.6, -1.2, 1.2, 3.6):
            for sx in (-1.3, 1.3):
                post(m, K("bark", DARK), sx, f, 2.2, 0.12, y0=-0.8)
        barrel_at(m, 0.9, 3.0, y=1.07, s=0.8)
        m.lathe(K("cloth", ROPE), [(0.25, 1.07), (0.25, 1.2), (0.12, 1.2)], (-0.9, 0, 2.6), segs=10)  # coiled rope
    model("dock", dock)

    def fish_rack(m):
        for sx in (-1.2, 1.2):
            for sf in (-0.4, 0.4):
                m.rod(K("wood", DARK), 0.04, (sx, 0, sf), (sx, 1.9, 0), segs=5)
        m.rod(K("wood", DARK), 0.03, (-1.3, 1.85, 0), (1.3, 1.85, 0), segs=5)
        for k in range(7):
            m.loft(K("paint", (0.62, 0.66, 0.7)), [(-1.0 + k * 0.33, 1.82, 0, 0.02, 0.03), (-1.0 + k * 0.33, 1.55, 0, 0.06, 0.03), (-1.0 + k * 0.33, 1.25, 0, 0.01, 0.05)], segs=5, steps=2)
    model("fish_rack", fish_rack)

    def nets(m):
        blob(m, K("cloth", (0.45, 0.5, 0.42)), (0.9, 0.25, 0.7), (0, 0.2, 0), seed=3, rough=0.25)
        for x, f in ((0.6, 0.5), (-0.7, 0.3), (0.1, -0.6)):
            m.ball(K("paint", (0.8, 0.3, 0.2)), 0.12, (x, 0.3, f), u=6, v=5)  # floats
    model("nets", nets)

    def anchor(m):
        m.rod(K("metal", IRON), 0.06, (0, 0.2, 0), (0.3, 1.4, 0), segs=6)
        m.loft(K("metal", IRON), [(-0.5, 0.5, 0, 0.05, 0.05), (0, 0.15, 0, 0.07, 0.07), (0.6, 0.35, 0, 0.05, 0.05)], segs=6, steps=3)
        m.rod(K("metal", IRON), 0.04, (0.0, 1.25, 0), (0.6, 1.25, 0), segs=5)
    model("anchor", anchor)

    # ---------- the desert tribes ----------
    def tent(m, band):
        m.lathe(K("leather", (0.62, 0.48, 0.32)), [(2.4, 0.0), (0.25, 3.2)], (0, 0, 0), segs=9)
        m.lathe(K("cloth", band), [(1.75, 0.9), (1.35, 1.45)], (0, 0, 0), segs=9)
        for x, f in ring(3, 0.2):
            m.rod(K("wood", DARK), 0.035, (x * 3, 2.9, f * 3), (-x * 2, 3.8, -f * 2), segs=4)
        m.prof(K("paint", (0.05, 0.04, 0.03)), 0.9, [(2.0, 0.0), (1.2, 1.7), (2.05, 0.0)], x=0, bevel=0)  # the opening
    model("tent_red", lambda m: tent(m, (0.7, 0.16, 0.1)))
    model("tent_blue", lambda m: tent(m, (0.12, 0.3, 0.62)))

    def banner(m, col):
        post(m, K("wood", DARK), 0, 0, 4.2, 0.05)
        m.rod(K("wood", DARK), 0.03, (0, 4.0, 0), (0.9, 4.0, 0), segs=4)
        m.prof(K("cloth", col), 0.02, [(0.05, 4.0), (0.85, 4.0), (0.85, 2.4), (0.45, 2.75), (0.05, 2.4)], x=0, bevel=0, across="f")
        m.ball(K("paint", (0.9, 0.86, 0.7)), 0.12, (0, 4.3, 0), u=6, v=5)
    model("banner_red", lambda m: banner(m, (0.72, 0.14, 0.1)))
    model("banner_blue", lambda m: banner(m, (0.12, 0.28, 0.65)))

    def palisade(m):
        for k in range(7):
            h = 2.2 + 0.25 * ((k * 3) % 4)
            m.rod(K("bark", (0.42, 0.32, 0.22)), 0.16, (-1.5 + k * 0.5, 0, 0.04 * (k % 2)), (-1.5 + k * 0.5, h, 0), r2=0.13, segs=6)
            m.rod(K("wood", (0.75, 0.62, 0.42)), 0.13, (-1.5 + k * 0.5, h, 0), (-1.5 + k * 0.5, h + 0.4, 0), r2=0.01, segs=6)
        m.rod(K("cloth", ROPE), 0.025, (-1.6, 1.5, 0.17), (1.6, 1.5, 0.17), segs=4)
    model("palisade", palisade)

    def weapon_rack(m):
        for sx in (-0.8, 0.8):
            m.rod(K("wood", DARK), 0.04, (sx, 0, 0.4), (sx, 1.5, 0), segs=5)
            m.rod(K("wood", DARK), 0.04, (sx, 0, -0.4), (sx, 1.5, 0), segs=5)
        m.rod(K("wood", DARK), 0.035, (-0.9, 1.45, 0), (0.9, 1.45, 0), segs=5)
        for k, x in enumerate((-0.5, 0.0, 0.5)):
            m.rod(K("wood", WOOD), 0.02, (x, 0.02, 0.45), (x, 2.3, -0.1), segs=5)
            m.rod(K("metal", IRON), 0.04, (x, 2.3, -0.1), (x, 2.65, -0.15), r2=0.004, segs=5)
        for x, col in ((-0.9, (0.7, 0.2, 0.15)), (0.95, (0.2, 0.3, 0.6))):
            m.lathe(K("wood", col), [(0.0, 0.0), (0.4, 0.03), (0.42, 0.08), (0.0, 0.12)], (x, 0.6, 0.5), segs=10, axis="f")
    model("weapon_rack", weapon_rack)

    def pottery(m):
        for x, f, s, col in ((0, 0, 1.0, (0.7, 0.42, 0.26)), (0.6, 0.2, 0.7, (0.78, 0.55, 0.32)), (0.25, 0.6, 0.5, (0.6, 0.36, 0.24))):
            m.lathe(K("adobe", col), [(0.16 * s, 0.0), (0.34 * s, 0.35 * s), (0.3 * s, 0.7 * s), (0.14 * s, 0.9 * s), (0.18 * s, 1.0 * s)], (x, 0, f), segs=10)
    model("pottery", pottery)

    def rug(m):
        m.box(K("cloth", (0.62, 0.2, 0.16)), (2.4, 0.03, 1.6), (0, 0.02, 0), bevel=0)
        m.box(K("cloth", (0.9, 0.78, 0.45)), (1.8, 0.035, 1.0), (0, 0.022, 0), bevel=0)
        m.box(K("cloth", (0.15, 0.3, 0.5)), (1.0, 0.04, 0.4), (0, 0.024, 0), bevel=0)
    model("rug", rug)

    def bone_pile(m):
        for k in range(6):
            a = k * 1.1
            m.rod(K("paint", (0.88, 0.85, 0.75)), 0.04, (math.cos(a) * 0.5, 0.06, math.sin(a) * 0.5), (math.cos(a + 2.0) * 0.6, 0.12, math.sin(a + 2.0) * 0.6), segs=5)
        blob(m, K("paint", (0.9, 0.87, 0.78)), (0.16, 0.14, 0.2), (0.1, 0.18, 0.0), seed=2, rough=0.1)
        m.lathe(K("wood", (0.6, 0.2, 0.15)), [(0.0, 0.0), (0.38, 0.03), (0.4, 0.07), (0.0, 0.1)], (-0.5, 0.05, 0.4), segs=10)  # a split shield
        m.rod(K("wood", WOOD), 0.02, (0.7, 0.05, -0.5), (-0.3, 0.3, 0.6), segs=4)  # a broken spear
    model("bone_pile", bone_pile)

    def totem(m):
        m.lathe(K("bark", (0.4, 0.3, 0.2)), [(0.3, 0.0), (0.26, 3.0)], (0, 0, 0), segs=8)
        for k, col in enumerate(((0.7, 0.2, 0.15), (0.9, 0.8, 0.5), (0.15, 0.3, 0.55))):
            m.lathe(K("paint", col), [(0.3, 0.8 + k * 0.7), (0.3, 1.0 + k * 0.7)], (0, 0, 0), segs=8)
        blob(m, K("paint", (0.9, 0.87, 0.78)), (0.22, 0.24, 0.26), (0, 3.2, 0), seed=4, rough=0.08)
        for sx in (-1, 1):
            m.rod(K("paint", (0.9, 0.87, 0.78)), 0.05, (sx * 0.15, 3.3, 0), (sx * 0.6, 3.7, 0), r2=0.01, segs=5)
    model("totem", totem)

    # ---------- the north ----------
    def log_cabin(m):
        for k in range(9):
            y = 0.25 + k * 0.34
            for sf in (-1, 1):
                m.cylx(K("pinebark", (0.45, 0.33, 0.22)), 0.18, -3.4, 3.4, sf * 2.4, y, segs=7)
            for sx in (-1, 1):
                m.cyl(K("pinebark", (0.45, 0.33, 0.22)), 0.18, -2.8, 2.8, y=y + 0.17, x=sx * 3.0, segs=7)
        m.prof(K("slate", (0.9, 0.93, 0.97)), 7.4, [(-3.1, 3.2), (0, 5.2), (3.1, 3.2)], x=0, bevel=0.05)  # snow on the roof
        m.prof(K("wood", DARK), 6.0, [(-2.4, 3.2), (0, 4.75), (2.4, 3.2)], x=0, bevel=0.0)
        m.box(K("wood", DARK), (1.0, 1.9, 0.2), (-1.0, 1.1, 2.5), bevel=0.02)
        m.box(glow, (0.8, 0.7, 0.1), (1.3, 1.8, 2.55), bevel=0.02)
        m.box(K("stone", GREY), (0.9, 5.6, 0.9), (2.2, 2.8, -1.4), bevel=0.04)
    model("log_cabin", log_cabin)

    def sled(m):
        for sx in (-0.4, 0.4):
            m.loft(K("wood", WOOD), [(sx, 0.05, -1.0, 0.03, 0.04), (sx, 0.05, 0.8, 0.03, 0.04), (sx, 0.4, 1.25, 0.03, 0.03)], segs=5, steps=3)
            for f in (-0.6, 0.4):
                post(m, K("wood", WOOD), sx, f, 0.3, 0.025, y0=0.05)
        m.box(K("wood", WOOD), (0.9, 0.05, 1.5), (0, 0.38, -0.1), bevel=0.01)
        sack_at(m, 0, -0.2, y=0.4, col=(0.5, 0.4, 0.3), seed=6)
    model("sled", sled)

    def drying_rack(m):
        for sx in (-1.0, 1.0):
            m.rod(K("wood", DARK), 0.04, (sx, 0, 0.5), (sx, 1.8, 0), segs=5)
            m.rod(K("wood", DARK), 0.04, (sx, 0, -0.5), (sx, 1.8, 0), segs=5)
        m.rod(K("wood", DARK), 0.03, (-1.1, 1.75, 0), (1.1, 1.75, 0), segs=5)
        for k, col in enumerate(((0.5, 0.36, 0.24), (0.75, 0.72, 0.68), (0.4, 0.3, 0.22))):
            m.box(K("leather", col), (0.55, 0.9, 0.03), (-0.65 + k * 0.65, 1.28, 0), bevel=0)  # hides
    model("drying_rack", drying_rack)

    # ---------- the volcano ----------
    def anvil(m):
        m.lathe(K("bark", (0.4, 0.3, 0.2)), [(0.32, 0.0), (0.3, 0.55)], (0, 0, 0), segs=8)
        m.prof(K("metal", (0.28, 0.28, 0.32)), 0.26, [(-0.3, 0.55), (0.3, 0.55), (0.22, 0.7), (0.5, 0.86), (0.5, 0.95), (-0.42, 0.95), (-0.7, 0.86), (-0.25, 0.72)], x=0, bevel=0.015)
        m.rod(K("wood", WOOD), 0.02, (0.1, 0.97, 0.0), (0.45, 1.0, 0.25), segs=5)
        m.box(K("metal", IRON), (0.1, 0.1, 0.18), (0.1, 0.99, 0.0), bevel=0.01)
    model("anvil", anvil)

    def slag_heap(m):
        for k in range(5):
            a = k * 1.3
            blob(m, K("rock", (0.16, 0.14, 0.15)), (0.9 - 0.1 * k, 0.5 + 0.1 * (k % 2), 0.8), (math.cos(a) * 0.7, 0.3, math.sin(a) * 0.7), seed=k + 20, rough=0.3)
        for k in range(4):
            m.ball(glow, 0.07, (math.cos(k * 1.7) * 0.6, 0.55, math.sin(k * 1.7) * 0.6), u=5, v=4)
    model("slag_heap", slag_heap)

    # ---------- the heights ----------
    def bell_frame(m):
        for sx in (-1.0, 1.0):
            post(m, K("timber", DARK), sx, 0, 3.0, 0.12)
        m.box(K("timber", DARK), (2.6, 0.22, 0.22), (0, 3.0, 0), bevel=0.02)
        m.prof(K("slate", (0.36, 0.34, 0.5)), 3.0, [(-0.6, 3.2), (0, 3.7), (0.6, 3.2)], x=0, bevel=0.03)
        m.lathe(K("metal", (0.7, 0.55, 0.25)), [(0.1, 2.8), (0.3, 2.5), (0.42, 2.0), (0.5, 1.9)], (0, 0, 0), segs=10)
        m.rod(K("cloth", ROPE), 0.02, (0, 2.0, 0), (0.1, 1.0, 0), segs=4)
    model("bell_frame", bell_frame)

    def prayer_flags(m):
        for sx in (-3.0, 3.0):
            post(m, K("wood", DARK), sx, 0, 3.0, 0.05)
        m.rod(K("cloth", ROPE), 0.012, (-3.0, 2.9, 0), (3.0, 2.9, 0), segs=4)
        for k in range(11):
            col = ((0.75, 0.2, 0.2), (0.9, 0.8, 0.3), (0.3, 0.55, 0.35), (0.3, 0.4, 0.75), (0.92, 0.92, 0.9))[k % 5]
            x = -2.7 + k * 0.54
            m.prof(K("cloth", col), 0.02, [(x - 0.2, 2.88), (x + 0.2, 2.88), (x, 2.35)], x=0, bevel=0, across="f")
    model("prayer_flags", prayer_flags)

    def cairn(m):
        for k, (r, y) in enumerate(((0.55, 0.25), (0.42, 0.7), (0.32, 1.05), (0.22, 1.33), (0.13, 1.53))):
            blob(m, K("rock", (0.52, 0.52, 0.56)), (r, 0.26, r * 0.9), (0.04 * (k % 2), y, 0), seed=k + 40, rough=0.12, cuts=1)
    model("cairn", cairn)

    # ---------- the colourless court ----------
    def ruin_wall(m):
        m.prof(K("stone", (0.8, 0.8, 0.82)), 0.9, [(-3.0, 0.0), (3.0, 0.0), (3.0, 1.2), (1.8, 1.5), (1.2, 2.9), (0.2, 3.3), (-0.8, 2.2), (-2.0, 2.6), (-3.0, 1.4)], x=0, bevel=0.04, across="f")
        for k in range(4):
            blob(m, K("stone", (0.78, 0.78, 0.8)), (0.4, 0.3, 0.35), (-2.0 + k * 1.3, 0.2, 1.0 + 0.3 * (k % 2)), seed=k + 60, rough=0.2, cuts=1)
    model("ruin_wall", ruin_wall)

    def ruin_arch(m):
        for sx in (-1.6, 1.6):
            m.lathe(K("stone", (0.82, 0.82, 0.84)), [(0.5, 0.0), (0.42, 0.4), (0.4, 3.6), (0.5, 3.9)], (sx, 0, 0), segs=8)
        m.loft(K("stone", (0.82, 0.82, 0.84)), [(-1.6, 3.9, 0, 0.35, 0.35), (-0.9, 5.0, 0, 0.33, 0.33), (0.2, 5.3, 0, 0.33, 0.33)], segs=6, steps=3)
        blob(m, K("stone", (0.8, 0.8, 0.82)), (0.6, 0.4, 0.5), (1.9, 0.3, 1.0), seed=71, cuts=1)
    model("ruin_arch", ruin_arch)

    def statue(m):  # a figure with no face on a plinth: the court erased it
        m.box(K("stone", (0.8, 0.8, 0.82)), (1.4, 1.0, 1.4), (0, 0.5, 0), bevel=0.05)
        m.loft(K("stone", (0.88, 0.88, 0.9)), [(0, 1.0, 0, 0.42, 0.3), (0, 2.0, 0, 0.3, 0.24), (0, 2.8, 0, 0.36, 0.24), (0, 3.2, 0, 0.14, 0.13)], segs=10, steps=3)
        blob(m, K("stone", (0.9, 0.9, 0.92)), (0.2, 0.24, 0.2), (0, 3.45, 0), seed=80, rough=0.03)
        m.rod(K("stone", (0.88, 0.88, 0.9)), 0.09, (0.34, 2.75, 0), (0.6, 2.0, 0.3), segs=6)
    model("statue", statue)

    def easel(m):
        for x, f in ((-0.4, 0.2), (0.4, 0.2), (0, -0.6)):
            m.rod(K("wood", WOOD), 0.03, (x, 0, f), (0, 1.9, 0.0), segs=5)
        m.box(K("wood", WOOD), (1.0, 0.05, 0.08), (0, 0.8, 0.2), bevel=0.01)
        m.box(K("cloth", (0.94, 0.94, 0.92)), (0.9, 0.7, 0.03), (0, 1.2, 0.2), tilt=-10, bevel=0.01)
    model("easel", easel)

    def path_stones(m):  # flat stepping stones, laid where people walk
        for k in range(6):
            blob(m, K("stone", (0.6, 0.58, 0.55)), (0.35, 0.05, 0.3), (0.25 * (k % 2) - 0.12, 0.03, -1.6 + k * 0.65), seed=k + 90, rough=0.12, cuts=1)
    model("path_stones", path_stones)
    maker.save()


if __name__ == "__main__":
    import bpy
    bpy.ops.wm.read_factory_settings(use_empty=True)
    build_all()
