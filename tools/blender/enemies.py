# Purpose: developer-time script (polish1 D2). Models the reworked island + colosseum enemies with tools/blender/kit.py
# into assets/models/fantasy/creatures/en_<id>.gltf, as rigid parts on named pivots that game/enemy_rig.gd turns every
# frame (its own gait, idle, blows and death per type, data/enemy_moves.json). The game dresses them like every creature
# (game/fantasy_models.gd: each part made of something - leather skin, cloth, bone, metal, leaf - with its own material;
# eyes "glow"). Each model holds 2-3 VARIANTS: nodes V1_..., V2_..., V3_... of which the game shows one.
# Pivot layout of a person: Hips (pelvis) > Spine (torso, neck) > Head > Jaw; Spine > ArmL > ForeL (hand), ArmR > ForeR;
# Hips > LegL > ShinL (foot), LegR > ShinR. The crab: Hips (its body) > LegL1..3 / LegR1..3, ClawL > PincerL, ClawR >
# PincerR, EyeL / EyeR. Model space: x right, y up, f forward (the game's -z); feet at y = 0, about 1.8 m tall.
#   en_drowned          a drowned sailor, waterlogged grey-green, torn striped shirt, rope belt, rags, barnacles and
#                       weed; V1 knit cap, V2 bandana + eye patch, V3 kelp hair + a hook for a hand
#   en_drowned_runner   a lean, long-armed brine runner, shirt torn open, hunched; V1 wrist shackles with broken chain,
#                       V2 a rope noose, V3 a broken oar blade stuck in its back
#   en_swimmer          half turned to sea: fin ridge down the back, gill slits, scaled patches, webbed hands; V1 an old
#                       diver's harness, V2 a fishing net with floats, V3 coral grown on shoulder and head
#   en_reef_crab        a big reef crab: ridged carapace, six jointed legs, two claws with moving pincers, eye stalks;
#                       V1 barnacles, V2 a clump of weed, V3 a broken bottle lodged in its shell
#   en_tide_brute       a 2.7 m hulking drowned: huge arms, small head sunk in the shoulders, plank armour; V1 an anchor
#                       chain wound round its arm, V2 a ship's plank shield on its back, V3 a net with floats over its head
# Run: python3 tools/blender/enemies.py   (ONLY=en_drowned builds just that one)
# Dependencies: bpy, tools/blender/kit.py, tools/blender/fantasy_kit.py. No game code.
import math
import os
import random
import sys

sys.path.insert(0, os.path.dirname(__file__))
import kit
import fantasy_kit as fk
from fantasy_kit import K as _K

# Every material a part is made of is one more draw call on every pivot that holds it: these bodies keep to a few
# (weed counts as cloth, dark paint as leather, barnacles as leather on people) so an enemy stays near 20 draw calls.
SAME_AS = {"leaf": "cloth", "paint": "leather", "ice": "bone"}


def K(kind, rgb):
    return _K(SAME_AS.get(kind, kind), rgb)

OUT = os.path.join(os.path.dirname(__file__), "..", "..", "assets", "models", "fantasy", "creatures")

DROWNED_SKIN = (0.45, 0.56, 0.52)
DROWNED_DARK = (0.28, 0.36, 0.34)
SHIRT_A, SHIRT_B = (0.78, 0.76, 0.68), (0.2, 0.26, 0.42)
RAGS = (0.32, 0.28, 0.22)
ROPE = (0.62, 0.52, 0.34)
WEED = (0.2, 0.36, 0.16)
BARNACLE = (0.82, 0.8, 0.72)
IRON = (0.3, 0.28, 0.27)
RUST = (0.45, 0.26, 0.14)
WOOD = (0.42, 0.32, 0.2)
EYE = (0.55, 0.95, 0.9)


# ---------- a person on pivots ----------

class Body:
    """Measures of one person; every place (x, y, f) on it comes from here so clothes and gear fit."""

    def __init__(self, girth=1.0, shoulders=1.0, hips=1.0, belly=0.0, hunch=0.0, arm=1.0, arm_r=1.0, leg_r=1.0, head=1.0, neck=1.0):
        self.g, self.sh, self.hp, self.belly, self.hunch = girth, shoulders, hips, belly, hunch
        self.arm, self.arm_r, self.leg_r, self.head, self.neck = arm, arm_r, leg_r, head, neck
        self.hip_y, self.knee_y, self.ankle_y = 0.95, 0.5, 0.085
        self.waist_y, self.chest_y, self.shoulder_y = 1.03, 1.26, 1.44
        self.sx = 0.19 * shoulders  # shoulder joint across
        self.hx = 0.095 * hips  # hip joint across
        self.neck_y = 1.47 + 0.04 * (neck - 1.0)
        self.head_f = hunch * 1.25 + 0.01
        self.head_y = self.neck_y + 0.06  # the head's pivot (top of the neck)
        self.elbow_y = self.shoulder_y - 0.29 * arm
        self.wrist_y = self.elbow_y - 0.27 * arm

    def shoulder(self, side):
        return (side * self.sx, self.shoulder_y - 0.01, self.hunch * 0.9)

    def elbow(self, side):
        return (side * (self.sx + 0.03), self.elbow_y, self.hunch * 0.9 + 0.01)

    def wrist(self, side):
        return (side * (self.sx + 0.04), self.wrist_y, self.hunch * 0.9 + 0.03)

    def hip(self, side):
        return (side * self.hx, self.hip_y, 0.0)

    def knee(self, side):
        return (side * (self.hx + 0.005), self.knee_y, 0.015)

    def nodes(self, m):
        m.node("Hips", (0.0, self.hip_y, 0.0))
        m.node("Spine", (0.0, self.waist_y, 0.0), parent="Hips")
        m.node("Head", (0.0, self.head_y, self.head_f), parent="Spine")
        m.node("Jaw", (0.0, self.head_y + 0.05 * self.head, self.head_f + 0.02), parent="Head")
        for side, s in ((-1, "L"), (1, "R")):
            m.node("Arm" + s, self.shoulder(side), parent="Spine")
            m.node("Fore" + s, self.elbow(side), parent="Arm" + s)
            m.node("Leg" + s, self.hip(side), parent="Hips")
            m.node("Shin" + s, self.knee(side), parent="Leg" + s)


def flesh(m, b, skin, eye=EYE, eyes_glow=True, brow=1.0, gaunt=0.0, ears=True):
    """The bare body: pelvis, torso, neck, head with jaw and face, arms with hands, legs with feet."""
    g, hn = b.g, b.hunch
    m.loft(skin, [(0.0, 0.86, 0.0, 0.14 * b.hp * g, 0.1 * g), (0.0, 0.96, 0.0, 0.155 * b.hp * g, 0.11 * g), (0.0, 1.04, 0.0, 0.14 * g, 0.105 * g)], node="Hips", segs=14)
    m.loft(skin, [(0.0, 1.02, 0.0, 0.135 * g, (0.1 + b.belly) * g), (0.0, 1.12, hn * 0.3 + b.belly * 0.5, 0.145 * g, (0.11 + b.belly) * g),
                  (0.0, 1.27, hn * 0.55, 0.165 * b.sh * g, 0.12 * g), (0.0, 1.39, hn * 0.8, 0.175 * b.sh * g, 0.11 * g),
                  (0.0, 1.46, hn * 0.95, 0.13 * b.sh * g, 0.085 * g)], node="Spine", segs=16)
    for side in (-1, 1):  # shoulders and the chest's swell
        m.ball(skin, (0.07 * g * b.arm_r, 0.07 * g, 0.075 * g), (side * (b.sx - 0.01), b.shoulder_y - 0.02, hn * 0.88), node="Spine", u=10, v=7)
        m.ball(skin, (0.08 * g, 0.06 * g, 0.05 * g), (side * 0.075, 1.31, hn * 0.6 + 0.07 * g), node="Spine", u=10, v=7)
    m.loft(skin, [(0.0, b.neck_y - 0.06, hn * 0.95, 0.06 * g, 0.055 * g), (0.0, b.head_y + 0.02, b.head_f, 0.052 * g, 0.05 * g)], node="Spine", segs=10)
    head(m, b, skin, eye, eyes_glow, brow, gaunt, ears)
    for side, s in ((-1, "L"), (1, "R")):
        sh, el, wr = b.shoulder(side), b.elbow(side), b.wrist(side)
        r = b.arm_r * g
        m.loft(skin, [(sh[0], sh[1], sh[2], 0.055 * r, 0.058 * r), ((sh[0] + el[0]) / 2, (sh[1] + el[1]) / 2, sh[2] + 0.005, 0.05 * r, 0.052 * r), (el[0], el[1], el[2], 0.04 * r, 0.042 * r)], node="Arm" + s, segs=10)
        m.loft(skin, [(el[0], el[1], el[2], 0.042 * r, 0.044 * r), (el[0], el[1] - 0.08, el[2] + 0.005, 0.045 * r, 0.04 * r), (wr[0], wr[1], wr[2], 0.03 * r, 0.026 * r)], node="Fore" + s, segs=10)
        hand(m, b, side, skin, "Fore" + s)
        hp, kn = b.hip(side), b.knee(side)
        lr = b.leg_r * g
        m.loft(skin, [(hp[0], hp[1] + 0.02, 0.0, 0.085 * lr, 0.09 * lr), (hp[0], (hp[1] + kn[1]) / 2 + 0.05, 0.01, 0.075 * lr, 0.08 * lr), (kn[0], kn[1], kn[2], 0.05 * lr, 0.055 * lr)], node="Leg" + s, segs=12)
        m.loft(skin, [(kn[0], kn[1], kn[2], 0.052 * lr, 0.056 * lr), (kn[0], kn[1] - 0.12, kn[2] - 0.01, 0.055 * lr, 0.06 * lr), (kn[0], b.ankle_y + 0.02, 0.0, 0.035 * lr, 0.038 * lr)], node="Shin" + s, segs=12)
        foot(m, b, side, skin, "Shin" + s)


def head(m, b, skin, eye, eyes_glow, brow, gaunt, ears):
    y, f, k = b.head_y, b.head_f, b.head
    m.loft(skin, [(0.0, y + 0.02, f - 0.01, 0.07 * k, 0.08 * k), (0.0, y + 0.08, f, 0.088 * k, 0.1 * k), (0.0, y + 0.16, f - 0.005, 0.09 * k, 0.103 * k),
                  (0.0, y + 0.23, f - 0.012, 0.072 * k, 0.085 * k), (0.0, y + 0.26, f - 0.02, 0.02, 0.02)], node="Head", segs=16)
    fy = y + 0.13 * k  # eye line
    face = f + 0.085 * k
    m.loft(skin, [(-0.075 * k, fy + 0.02, face - 0.01, 0.014, 0.016), (0.0, fy + 0.03 * brow, face + 0.005, 0.02, 0.018), (0.075 * k, fy + 0.02, face - 0.01, 0.014, 0.016)], node="Head", segs=8)  # brow ridge
    m.loft(skin, [(0.0, fy + 0.005, face + 0.005, 0.012, 0.012), (0.0, fy - 0.04, face + 0.03, 0.017, 0.02), (0.0, fy - 0.05, face + 0.02, 0.022, 0.012)], node="Head", segs=8)  # nose
    for side in (-1, 1):
        m.ball(K("paint", (0.05, 0.06, 0.06)), (0.026 * k, 0.018 * k, 0.012), (side * 0.036 * k, fy, face - 0.008), node="Head", u=8, v=6)  # sunken sockets
        m.ball((fk.GLOW, eye) if eyes_glow else K("bone", (0.85, 0.85, 0.8)), (0.011 * k, 0.011 * k, 0.008), (side * 0.036 * k, fy, face - 0.002), node="Head", u=6, v=5)
        m.ball(skin, (0.028 * k, 0.022 * k * (1 - gaunt * 0.5), 0.03 * k), (side * 0.055 * k, fy - 0.045, face - 0.025), node="Head", u=8, v=6)  # cheekbones
        if ears:
            m.ball(skin, (0.012, 0.03 * k, 0.02 * k), (side * 0.088 * k, fy - 0.01, f + 0.0), node="Head", u=8, v=6)
    m.loft(skin, [(-0.06 * k, y + 0.05, face - 0.05, 0.02, 0.02), (0.0, y + 0.02, face - 0.005, 0.035 * k, 0.025), (0.06 * k, y + 0.05, face - 0.05, 0.02, 0.02)], node="Jaw", segs=8)  # chin + jaw line
    m.ball(K("paint", (0.12, 0.05, 0.05)), (0.03 * k, 0.008, 0.01), (0.0, y + 0.055, face - 0.012), node="Jaw", u=8, v=5)  # the open mouth's dark


def hand(m, b, side, skin, node, claws=None, webbed=False):
    wr = b.wrist(side)
    x, y, f = wr[0], wr[1] - 0.04, wr[2] + 0.01
    m.ball(skin, (0.032 * b.g, 0.045, 0.024 * b.g), (x, y, f), node=node, u=8, v=6)  # palm
    for i in range(4):
        fx = f + 0.03 - i * 0.018
        tip = (x + side * 0.005, y - 0.085, fx + 0.012)
        m.rod(skin, 0.009 * b.g, (x, y - 0.035, fx), tip, r2=0.006, node=node, segs=6)
        if claws:
            m.rod(claws, 0.005, tip, (tip[0], tip[1] - 0.025, tip[2] + 0.012), r2=0.001, node=node, segs=5)
    m.rod(skin, 0.01 * b.g, (x - side * 0.015, y - 0.01, f + 0.03), (x - side * 0.02, y - 0.05, f + 0.06), r2=0.007, node=node, segs=6)  # thumb
    if webbed:
        m.prof(skin, 0.004, [(f + 0.035, y - 0.03), (f + 0.04, y - 0.075), (f - 0.035, y - 0.075), (f - 0.03, y - 0.03)], x=x + side * 0.004, node=node)


def foot(m, b, side, mat, node, bare=True):
    x = side * (b.hx + 0.005)
    m.loft(mat, [(x, 0.06, -0.035, 0.04, 0.035), (x, 0.04, 0.06, 0.045, 0.03), (x, 0.03, 0.15, 0.04, 0.022)], node=node, segs=10)
    if bare:
        for i in range(4):
            m.ball(mat, 0.011, (x + side * (-0.025 + i * 0.016), 0.022, 0.17), node=node, u=6, v=4)


# ---------- clothes and gear ----------

def shirt(m, b, mat, stripes=None, torn=0.0, sleeves=0.6, seed=1):
    """A shirt over the torso (+ sleeves to `sleeves` of the arm); stripes = (colour kind) bands round it; torn = ragged hem."""
    g, hn = b.g * 1.06, b.hunch
    rings = [(0.0, 0.98 - torn * 0.05, 0.0, 0.15 * g, (0.11 + b.belly) * g), (0.0, 1.12, hn * 0.3 + b.belly * 0.5, 0.155 * g, (0.12 + b.belly) * g),
             (0.0, 1.27, hn * 0.55, 0.175 * b.sh * g, 0.13 * g), (0.0, 1.4, hn * 0.8, 0.183 * b.sh * g, 0.118 * g), (0.0, 1.47, hn * 0.95, 0.12 * b.sh * g, 0.08 * g)]
    m.loft(mat, rings, node="Spine", segs=16, flat=True)
    if stripes:
        for k in range(5):
            yy = 1.05 + k * 0.08
            hn_k = hn * (0.2 + k * 0.17)
            m.loft(stripes, [(0.0, yy, hn_k, 0.163 * g * (1 + k * 0.04), 0.128 * g), (0.0, yy + 0.025, hn_k, 0.165 * g * (1 + k * 0.04), 0.13 * g)], node="Spine", segs=16, steps=1, flat=True)
    rnd = random.Random(seed)
    for k in range(int(torn * 10)):  # rag strips hanging from the hem
        a = rnd.uniform(0, math.tau)
        x, f = math.cos(a) * 0.15 * g, math.sin(a) * 0.11 * g
        m.prof(mat, 0.006, [(f, 0.99), (f + 0.02, 0.99), (f + 0.012, 0.99 - rnd.uniform(0.06, 0.14)), (f - 0.004, 0.99 - rnd.uniform(0.04, 0.1))], x=x, node="Spine", bevel=0.0)
    for side, s in ((-1, "L"), (1, "R")):
        sh, el = b.shoulder(side), b.elbow(side)
        r = b.arm_r * b.g * 1.12
        end = (sh[0] + (el[0] - sh[0]) * min(sleeves, 1.0) * 1.0, sh[1] + (el[1] - sh[1]) * min(sleeves, 1.0), sh[2])
        m.loft(mat, [(sh[0], sh[1] + 0.02, sh[2], 0.065 * r, 0.068 * r), (end[0], end[1], end[2], 0.054 * r, 0.056 * r)], node="Arm" + s, segs=10, flat=True)


def trousers(m, b, mat, length=1.0, torn=0.0, seed=2):
    g = b.g * 1.07
    m.loft(mat, [(0.0, 0.85, 0.0, 0.15 * b.hp * g, 0.108 * g), (0.0, 0.97, 0.0, 0.162 * b.hp * g, 0.115 * g), (0.0, 1.05, 0.0, 0.148 * g, 0.11 * g)], node="Hips", segs=14, flat=True)
    rnd = random.Random(seed)
    for side, s in ((-1, "L"), (1, "R")):
        hp, kn = b.hip(side), b.knee(side)
        lr = b.leg_r * g
        m.loft(mat, [(hp[0], hp[1] + 0.03, 0.0, 0.092 * lr, 0.096 * lr), (kn[0], kn[1] - 0.01, kn[2], 0.06 * lr, 0.064 * lr)], node="Leg" + s, segs=12, flat=True)
        bottom = kn[1] - (kn[1] - b.ankle_y - 0.06) * length
        m.loft(mat, [(kn[0], kn[1] + 0.02, kn[2], 0.062 * lr, 0.066 * lr), (kn[0], bottom, 0.0, 0.05 * lr, 0.052 * lr)], node="Shin" + s, segs=12, flat=True)
        for k in range(int(torn * 5)):  # frayed ends
            a = rnd.uniform(0, math.tau)
            x, f = kn[0] + math.cos(a) * 0.05 * lr, math.sin(a) * 0.05 * lr
            m.prof(mat, 0.005, [(f, bottom + 0.01), (f + 0.018, bottom + 0.01), (f + 0.01, bottom - rnd.uniform(0.03, 0.07))], x=x, node="Shin" + s, bevel=0.0)


def belt(m, b, mat, y=1.0, knot=True):
    m.loft(mat, [(0.0, y, b.belly * 0.4, 0.158 * b.g * 1.08, (0.118 + b.belly * 0.9) * b.g * 1.08), (0.0, y + 0.03, b.belly * 0.4, 0.157 * b.g * 1.08, (0.118 + b.belly * 0.9) * b.g * 1.08)], node="Hips", segs=16, steps=1, flat=True)
    if knot:
        m.ball(mat, (0.03, 0.025, 0.02), (0.06, y + 0.012, 0.125 * b.g + b.belly), node="Hips", u=8, v=6)
        m.rod(mat, 0.009, (0.06, y, 0.13 * b.g + b.belly), (0.075, y - 0.12, 0.135 * b.g + b.belly), node="Hips", segs=6)


def weeds(m, rnd, mat, spots, node, length=(0.08, 0.2)):
    """Strands of weed hanging from spots [(x, y, f)]."""
    for x, y, f in spots:
        n = rnd.randint(2, 4)
        for _ in range(n):
            dx, df = rnd.uniform(-0.03, 0.03), rnd.uniform(-0.02, 0.02)
            L = rnd.uniform(*length)
            m.loft(mat, [(x + dx, y, f + df, 0.012, 0.004), (x + dx * 1.5, y - L * 0.5, f + df + 0.01, 0.01, 0.003), (x + dx * 2, y - L, f + df, 0.004, 0.002)], node=node, segs=5, steps=2)


def barnacles(m, rnd, spots, node, size=1.0):
    for x, y, f in spots:
        for _ in range(rnd.randint(2, 5)):
            r = rnd.uniform(0.008, 0.016) * size
            p = (x + rnd.uniform(-0.025, 0.025), y + rnd.uniform(-0.025, 0.025), f + rnd.uniform(-0.01, 0.01))
            m.lathe(K("leather" if node != "Hips" else "bone", BARNACLE), [(r, 0.0), (r * 0.8, r * 0.9), (r * 0.35, r * 1.2), (0.001, r * 1.0)], p, node=node, segs=7, axis="f")


def chain(m, mat, pts, node, link=0.03):
    """Links along a path."""
    for (a, b), k in zip(zip(pts, pts[1:]), range(100)):
        mid = ((a[0] + b[0]) / 2, (a[1] + b[1]) / 2, (a[2] + b[2]) / 2)
        m.lathe(mat, [(link * 0.5, -0.006), (link * 0.55, 0.0), (link * 0.5, 0.006)], mid, node=node, segs=8, axis="x" if k % 2 else "f")


def variant(m, name, parent, pivot):
    m.node(name, pivot, parent=parent)
    return name


# ---------- the island's enemies ----------

def drowned(m):
    rnd = random.Random(11)
    b = Body(girth=1.08, belly=0.025, hunch=0.04, arm=1.04, head=1.0)
    b.nodes(m)
    skin = K("leather", DROWNED_SKIN)
    flesh(m, b, skin, brow=1.2, gaunt=0.3)
    shirt(m, b, K("cloth", SHIRT_A), stripes=K("cloth", SHIRT_B), torn=0.6, sleeves=0.8, seed=3)
    trousers(m, b, K("cloth", RAGS), length=0.75, torn=0.8)
    belt(m, b, K("cloth", ROPE))
    weeds(m, rnd, K("leaf", WEED), [(-0.15, 1.44, 0.05), (0.12, 1.42, -0.02), (0.0, 1.2, -0.13)], "Spine")
    weeds(m, rnd, K("leaf", WEED), [(-0.24, 1.2, 0.04)], "ArmL", (0.06, 0.12))
    barnacles(m, rnd, [(0.17, 1.3, 0.06), (-0.12, 1.06, 0.1), (0.1, 1.5, 0.0)], "Spine")
    barnacles(m, rnd, [(-0.13, 0.72, 0.05)], "LegL")
    y, f = b.head_y, b.head_f
    v = variant(m, "V1_Cap", "Head", (0.0, y, f))  # knit cap
    m.loft(K("cloth", (0.5, 0.14, 0.12)), [(0.0, y + 0.15, f - 0.01, 0.097, 0.108), (0.0, y + 0.22, f - 0.02, 0.085, 0.095), (0.0, y + 0.27, f - 0.03, 0.03, 0.03)], node=v, segs=14)
    m.loft(K("cloth", (0.42, 0.11, 0.1)), [(0.0, y + 0.14, f - 0.01, 0.1, 0.11), (0.0, y + 0.17, f - 0.01, 0.1, 0.11)], node=v, segs=14, steps=1, flat=True)
    v = variant(m, "V2_Bandana", "Head", (0.0, y, f))  # bandana + eye patch
    m.loft(K("cloth", (0.6, 0.18, 0.12)), [(0.0, y + 0.17, f - 0.01, 0.094, 0.106), (0.0, y + 0.24, f - 0.015, 0.075, 0.088), (0.0, y + 0.265, f - 0.025, 0.02, 0.02)], node=v, segs=14)
    m.loft(K("cloth", (0.6, 0.18, 0.12)), [(0.0, y + 0.18, f - 0.1, 0.02, 0.01), (0.03, y + 0.1, f - 0.13, 0.015, 0.006)], node=v, segs=6)
    m.ball(K("leather", (0.08, 0.07, 0.06)), (0.022, 0.018, 0.008), (0.036, y + 0.13, f + 0.085), node=v, u=8, v=6)
    v = variant(m, "V3_Kelp", "Head", (0.0, y, f))  # kelp hair
    weeds(m, rnd, K("leaf", WEED), [(-0.06, y + 0.22, f - 0.03), (0.05, y + 0.22, f - 0.04), (0.0, y + 0.2, f - 0.09), (-0.08, y + 0.17, f - 0.06), (0.08, y + 0.17, f - 0.06)], v, (0.1, 0.22))
    wr = b.wrist(1)
    v = variant(m, "V3_Hook", "ForeR", wr)
    m.loft(K("metal", IRON), [(wr[0], wr[1] - 0.02, wr[2], 0.025, 0.025), (wr[0], wr[1] - 0.09, wr[2], 0.012, 0.012)], node=v, segs=8)
    m.loft(K("metal", IRON), [(wr[0], wr[1] - 0.09, wr[2], 0.008, 0.008), (wr[0], wr[1] - 0.15, wr[2] + 0.03, 0.007, 0.007), (wr[0], wr[1] - 0.13, wr[2] + 0.07, 0.006, 0.006), (wr[0], wr[1] - 0.1, wr[2] + 0.065, 0.003, 0.003)], node=v, segs=6)


def drowned_runner(m):
    rnd = random.Random(21)
    b = Body(girth=0.86, shoulders=0.95, hips=0.92, hunch=0.09, arm=1.16, arm_r=0.85, leg_r=0.88, head=0.96, neck=1.15)
    b.nodes(m)
    skin = K("leather", (0.5, 0.58, 0.55))
    flesh(m, b, skin, brow=1.4, gaunt=0.9)
    for k in range(5):  # ribs showing through the waterlogged skin
        m.loft(K("leather", (0.4, 0.48, 0.46)), [(-0.12, 1.17 + k * 0.045, b.hunch * 0.5 + 0.09, 0.008, 0.006), (0.0, 1.18 + k * 0.045, b.hunch * 0.5 + 0.115, 0.009, 0.006), (0.12, 1.17 + k * 0.045, b.hunch * 0.5 + 0.09, 0.008, 0.006)], node="Spine", segs=6)
    shirt(m, b, K("cloth", (0.6, 0.56, 0.48)), torn=0.9, sleeves=0.35, seed=5)
    trousers(m, b, K("cloth", (0.25, 0.27, 0.3)), length=0.6, torn=1.0, seed=6)
    belt(m, b, K("leather", (0.25, 0.18, 0.12)), knot=False)
    weeds(m, rnd, K("leaf", WEED), [(0.1, 1.45, 0.02), (-0.05, 1.0, -0.12)], "Spine")
    for side, s in ((-1, "L"), (1, "R")):  # long nails
        hand(m, b, side, skin, "Fore" + s, claws=K("bone", (0.3, 0.3, 0.26)))
    for side, s in ((-1, "L"), (1, "R")):
        wr = b.wrist(side)
        v = variant(m, "V1_Shackle" + s, "Fore" + s, wr)
        m.lathe(K("metal", RUST), [(0.04, -0.025), (0.042, 0.0), (0.04, 0.025)], (wr[0], wr[1] + 0.03, wr[2]), node=v, segs=12)
        chain(m, K("metal", RUST), [(wr[0], wr[1] + 0.01, wr[2] - 0.03), (wr[0], wr[1] - 0.05, wr[2] - 0.05), (wr[0], wr[1] - 0.1, wr[2] - 0.05), (wr[0], wr[1] - 0.15, wr[2] - 0.04), (wr[0], wr[1] - 0.2, wr[2] - 0.03)], v)
    v = variant(m, "V2_Noose", "Spine", (0.0, b.neck_y, b.hunch))
    m.lathe(K("cloth", ROPE), [(0.062, -0.012), (0.066, 0.0), (0.062, 0.012)], (0.0, b.neck_y, b.hunch * 0.95), node=v, segs=14)
    m.loft(K("cloth", ROPE), [(0.03, b.neck_y, b.hunch + 0.05, 0.014, 0.014), (0.05, b.neck_y - 0.12, b.hunch + 0.1, 0.012, 0.012), (0.07, b.neck_y - 0.3, b.hunch + 0.12, 0.01, 0.01)], node=v, segs=6)
    v = variant(m, "V3_Oar", "Spine", (0.0, 1.3, -0.1))
    m.rod(K("wood", WOOD), 0.018, (0.05, 1.22, -0.08), (0.18, 1.62, -0.32), node=v, segs=8)
    m.loft(K("wood", WOOD), [(0.18, 1.62, -0.32, 0.05, 0.012), (0.24, 1.78, -0.42, 0.07, 0.012), (0.27, 1.86, -0.46, 0.04, 0.01)], node=v, segs=6)


def swimmer(m):
    rnd = random.Random(31)
    b = Body(girth=0.95, shoulders=1.05, hips=0.95, hunch=0.06, arm=1.08, head=1.0, neck=1.05)
    b.nodes(m)
    skin = K("leather", (0.32, 0.5, 0.56))
    scale = K("scale", (0.22, 0.42, 0.46))
    flesh(m, b, skin, eye=(0.95, 0.85, 0.35), brow=0.8, gaunt=0.4, ears=False)
    for side, s in ((-1, "L"), (1, "R")):
        hand(m, b, side, skin, "Fore" + s, claws=K("bone", (0.25, 0.3, 0.3)), webbed=True)
        for k in range(3):  # gill slits
            m.ball(K("paint", (0.25, 0.08, 0.1)), (0.004, 0.022, 0.012), (side * 0.05, b.neck_y - 0.01 - k * 0.018, b.hunch + 0.03), node="Spine", u=6, v=4)
        for k in range(4):  # scaled patches on the arms and flanks
            m.ball(scale, (0.035, 0.05, 0.03), (side * (0.15 + rnd.uniform(-0.01, 0.01)), 1.05 + k * 0.09, b.hunch * 0.4 - 0.02), node="Spine", u=8, v=6)
        m.prof(skin, 0.004, [(-0.02, b.elbow_y + 0.02), (-0.09, b.elbow_y - 0.04), (-0.03, b.elbow_y - 0.16)], x=side * (b.sx + 0.04), node="Fore" + s)  # forearm fin
        m.prof(skin, 0.004, [(-0.02, 0.4), (-0.08, 0.3), (-0.03, 0.18)], x=side * (b.hx + 0.05), node="Shin" + s)  # calf fin
    for k in range(7):  # the fin ridge down the back
        y0 = 1.46 - k * 0.07
        m.prof(K("leather", (0.6, 0.3, 0.3)), 0.006, [(-0.1 + k * 0.004, y0), (-0.17 + k * 0.006, y0 - 0.02), (-0.1 + k * 0.004, y0 - 0.07)], x=0.0, node="Spine")
    m.prof(K("leather", (0.6, 0.3, 0.3)), 0.006, [(b.head_f - 0.03, b.head_y + 0.26), (b.head_f - 0.12, b.head_y + 0.2), (b.head_f - 0.09, b.head_y + 0.1)], x=0.0, node="Head")  # head crest
    trousers(m, b, K("cloth", (0.15, 0.17, 0.2)), length=0.45, torn=0.7, seed=8)  # what is left of swimming trunks
    y, f = b.head_y, b.head_f
    v = variant(m, "V1_Harness", "Spine", (0.0, 1.2, 0.0))
    for side in (-1, 1):
        m.loft(K("leather", (0.18, 0.13, 0.09)), [(side * 0.08, 1.46, b.hunch + 0.07, 0.02, 0.008), (side * 0.11, 1.2, b.hunch * 0.5 + 0.13, 0.02, 0.008), (side * 0.12, 1.02, 0.125, 0.02, 0.008)], node=v, segs=6)
        m.loft(K("leather", (0.18, 0.13, 0.09)), [(side * 0.08, 1.46, b.hunch - 0.06, 0.02, 0.008), (side * 0.11, 1.2, -0.12, 0.02, 0.008), (side * 0.12, 1.02, -0.11, 0.02, 0.008)], node=v, segs=6)
    m.lathe(K("metal", (0.55, 0.42, 0.22)), [(0.04, -0.01), (0.045, 0.0), (0.04, 0.012)], (0.0, 1.22, b.hunch * 0.5 + 0.14), node=v, segs=12, axis="f")  # brass buckle
    m.lathe(K("metal", (0.4, 0.42, 0.44)), [(0.0, 0.0), (0.05, 0.02), (0.06, 0.2), (0.05, 0.26), (0.0, 0.27)], (0.0, 1.08, -0.17), node=v, segs=12)  # air tank
    v = variant(m, "V2_Net", "Spine", (0.0, 1.3, 0.0))
    for k in range(6):  # net cords draped over the shoulders
        a = -0.6 + k * 0.24
        m.loft(K("cloth", (0.58, 0.56, 0.48)), [(math.sin(a) * 0.2, 1.48, -0.04, 0.004, 0.004), (math.sin(a) * 0.22, 1.25, 0.14, 0.004, 0.004), (math.sin(a) * 0.2, 1.0, 0.13, 0.004, 0.004)], node=v, segs=4)
    for k in range(4):
        m.loft(K("cloth", (0.58, 0.56, 0.48)), [(-0.2, 1.42 - k * 0.12, 0.08, 0.004, 0.004), (0.0, 1.42 - k * 0.12, 0.15, 0.004, 0.004), (0.2, 1.42 - k * 0.12, 0.08, 0.004, 0.004)], node=v, segs=4)
    for x in (-0.18, 0.15):
        m.ball(K("paint", (0.85, 0.45, 0.15)), 0.04, (x, 1.0, 0.12), node=v, u=10, v=7)  # floats
    v = variant(m, "V3_Coral", "Spine", (0.0, 1.3, 0.0))
    for k in range(9):
        p = (0.16 + rnd.uniform(-0.02, 0.03), 1.42 + rnd.uniform(-0.05, 0.05), rnd.uniform(-0.05, 0.08))
        m.rod(K("bone", (0.95, 0.45, 0.4)), 0.012, p, (p[0] + rnd.uniform(0.0, 0.05), p[1] + rnd.uniform(0.04, 0.1), p[2] + rnd.uniform(-0.03, 0.03)), r2=0.005, node=v, segs=5)
    v2 = variant(m, "V3_CoralHead", "Head", (0.0, y, f))
    for k in range(5):
        p = (-0.06 + rnd.uniform(-0.02, 0.02), y + 0.2 + rnd.uniform(0, 0.05), f - 0.05 + rnd.uniform(-0.03, 0.03))
        m.rod(K("bone", (0.95, 0.45, 0.4)), 0.01, p, (p[0] - rnd.uniform(0.0, 0.04), p[1] + rnd.uniform(0.04, 0.08), p[2]), r2=0.004, node=v2, segs=5)


def reef_crab(m):
    rnd = random.Random(41)
    shell, dark, pale = K("scale", (0.72, 0.28, 0.16)), K("scale", (0.45, 0.14, 0.08)), K("bone", (0.92, 0.82, 0.68))
    cy = 0.32
    m.node("Hips", (0.0, cy, 0.0))
    # the carapace: a wide, low dome with a ridged front edge, knobs and a pale belly plate
    m.loft(shell, [(0.0, cy - 0.04, -0.3, 0.26, 0.08), (0.0, cy + 0.02, -0.15, 0.38, 0.12), (0.0, cy + 0.03, 0.05, 0.42, 0.13), (0.0, cy, 0.22, 0.36, 0.1), (0.0, cy - 0.04, 0.3, 0.22, 0.06)], node="Hips", segs=16)
    m.loft(pale, [(0.0, cy - 0.1, -0.22, 0.2, 0.04), (0.0, cy - 0.11, 0.0, 0.3, 0.05), (0.0, cy - 0.09, 0.2, 0.2, 0.04)], node="Hips", segs=14)
    for k in range(7):  # spiny front edge
        x = -0.3 + k * 0.1
        m.rod(dark, 0.02, (x, cy + 0.02, 0.26 - abs(x) * 0.25), (x * 1.05, cy + 0.03, 0.33 - abs(x) * 0.3), r2=0.004, node="Hips", segs=6)
    for k in range(10):  # knobs on the back
        m.ball(dark, 0.025 + rnd.uniform(0, 0.012), (rnd.uniform(-0.25, 0.25), cy + 0.14 + rnd.uniform(-0.02, 0.01), rnd.uniform(-0.2, 0.15)), node="Hips", u=8, v=5)
    m.loft(dark, [(-0.2, cy + 0.12, 0.08, 0.01, 0.006), (0.0, cy + 0.15, 0.12, 0.012, 0.006), (0.2, cy + 0.12, 0.08, 0.01, 0.006)], node="Hips", segs=6)  # groove
    for side, s in ((-1, "L"), (1, "R")):
        m.node("Eye" + s, (side * 0.06, cy + 0.08, 0.28), parent="Hips")
        m.rod(dark, 0.014, (side * 0.06, cy + 0.06, 0.27), (side * 0.07, cy + 0.17, 0.3), node="Eye" + s, segs=6)
        m.ball((fk.GLOW, (0.2, 0.15, 0.1)), 0.022, (side * 0.07, cy + 0.18, 0.3), node="Eye" + s, u=8, v=6)
        m.ball(K("paint", (0.03, 0.03, 0.03)), 0.016, (side * 0.072, cy + 0.185, 0.315), node="Eye" + s, u=6, v=5)
        for i in range(3):  # walking legs: upper joint up, then down to a sharp tip
            name = "Leg%s%d" % (s, i + 1)
            f0 = 0.08 - i * 0.14
            root = (side * 0.33, cy - 0.02, f0)
            m.node(name, root, parent="Hips")
            knee = (side * 0.55, cy + 0.12, f0 - 0.03)
            tip = (side * 0.72, 0.0, f0 - 0.06)
            m.loft(shell, [(root[0], root[1], root[2], 0.035, 0.03), (knee[0], knee[1], knee[2], 0.03, 0.026)], node=name, segs=8)
            m.loft(shell, [(knee[0], knee[1], knee[2], 0.03, 0.026), ((knee[0] + tip[0]) / 2, (knee[1] + tip[1]) / 2 + 0.02, (knee[2] + tip[2]) / 2, 0.022, 0.02), (tip[0], tip[1] + 0.02, tip[2], 0.008, 0.008)], node=name, segs=8)
            m.ball(dark, 0.03, knee, node=name, u=8, v=6)
        # the claws: an arm forward, a big hand with a fixed finger and a moving pincer ("Pincer")
        arm, claw = "Claw" + s, "Pincer" + s
        m.node(arm, (side * 0.22, cy, 0.25), parent="Hips")
        elbow, hand_at = (side * 0.38, cy + 0.03, 0.4), (side * 0.36, cy + 0.08, 0.6)
        m.loft(shell, [(side * 0.22, cy, 0.25, 0.04, 0.035), (elbow[0], elbow[1], elbow[2], 0.045, 0.04), (hand_at[0], hand_at[1] - 0.04, hand_at[2] - 0.1, 0.055, 0.05)], node=arm, segs=10)
        m.loft(shell, [(hand_at[0], hand_at[1] - 0.04, hand_at[2] - 0.12, 0.07, 0.06), (hand_at[0], hand_at[1], hand_at[2], 0.085, 0.07), (hand_at[0], hand_at[1] - 0.02, hand_at[2] + 0.12, 0.03, 0.025), (hand_at[0] - side * 0.01, hand_at[1] - 0.04, hand_at[2] + 0.2, 0.008, 0.008)], node=arm, segs=10)
        for k in range(4):
            m.ball(dark, 0.012, (hand_at[0] + side * 0.02, hand_at[1] - 0.03, hand_at[2] + 0.06 + k * 0.03), node=arm, u=6, v=4)  # teeth
        m.node(claw, (hand_at[0], hand_at[1] + 0.03, hand_at[2] + 0.04), parent=arm)
        m.loft(dark, [(hand_at[0], hand_at[1] + 0.03, hand_at[2] + 0.04, 0.03, 0.025), (hand_at[0], hand_at[1] + 0.05, hand_at[2] + 0.14, 0.022, 0.018), (hand_at[0] - side * 0.01, hand_at[1] + 0.01, hand_at[2] + 0.21, 0.006, 0.006)], node=claw, segs=8)
    v = variant(m, "V1_Barnacles", "Hips", (0.0, cy, 0.0))
    barnacles(m, rnd, [(-0.15, cy + 0.15, -0.1), (0.12, cy + 0.15, 0.0), (0.0, cy + 0.14, -0.2), (0.2, cy + 0.1, -0.15)], v, 1.6)
    v = variant(m, "V2_Weed", "Hips", (0.0, cy, 0.0))
    weeds(m, rnd, K("leaf", WEED), [(-0.1, cy + 0.15, -0.05), (0.08, cy + 0.15, -0.12), (0.18, cy + 0.12, 0.05)], v, (0.12, 0.25))
    v = variant(m, "V3_Bottle", "Hips", (0.0, cy, 0.0))
    m.lathe(K("ice", (0.35, 0.6, 0.4)), [(0.0, 0.0), (0.06, 0.01), (0.065, 0.14), (0.025, 0.2), (0.02, 0.27), (0.024, 0.28)], (0.08, cy + 0.08, -0.15), node=v, segs=12)


def tide_brute(m):
    rnd = random.Random(51)
    b = Body(girth=1.5, shoulders=1.55, hips=1.2, belly=0.07, hunch=0.13, arm=1.18, arm_r=1.35, leg_r=1.2, head=0.85, neck=0.6)
    b.nodes(m)
    skin = K("leather", (0.36, 0.48, 0.47))
    flesh(m, b, skin, brow=1.8, gaunt=0.0, ears=False)
    m.ball(skin, (0.17, 0.09, 0.13), (0.0, 1.47, b.hunch * 0.6 - 0.05), node="Spine", u=12, v=8)  # the hump between the shoulders
    for side, s in ((-1, "L"), (1, "R")):
        hand(m, b, side, skin, "Fore" + s, claws=K("bone", (0.3, 0.32, 0.3)))
        el = b.elbow(side)
        m.ball(skin, (0.08, 0.1, 0.08), (el[0], el[1] - 0.09, el[2]), node="Fore" + s, u=10, v=7)  # swollen forearm
        # plank armour strapped to the shoulder
        sh = b.shoulder(side)
        for k in range(3):
            m.box(K("wood", (0.38, 0.3, 0.22)), (0.05, 0.14, 0.2), (sh[0] + side * 0.07, sh[1] + 0.02 - k * 0.06, sh[2] - 0.04 + k * 0.03), node="Arm" + s, tilt=10)
        barnacles(m, rnd, [(sh[0] + side * 0.1, sh[1], sh[2])], "Arm" + s, 1.4)
    trousers(m, b, K("cloth", (0.22, 0.22, 0.2)), length=0.7, torn=0.9, seed=9)
    belt(m, b, K("cloth", ROPE), y=1.0)
    weeds(m, rnd, K("leaf", WEED), [(-0.2, 1.48, 0.0), (0.22, 1.48, 0.05), (0.0, 1.3, -0.2), (0.0, 1.1, 0.22)], "Spine", (0.12, 0.28))
    barnacles(m, rnd, [(-0.1, 1.3, 0.2), (0.15, 1.15, 0.2), (0.0, 1.45, -0.15)], "Spine", 1.5)
    wr = b.wrist(-1)
    v = variant(m, "V1_Chain", "ForeL", b.elbow(-1))
    pts = [(wr[0] + 0.06 * math.cos(a), wr[1] + 0.1 + a * 0.012, wr[2] + 0.06 * math.sin(a)) for a in [k * 0.9 for k in range(12)]]
    chain(m, K("metal", RUST), pts + [(wr[0] - 0.02, wr[1] - 0.05, wr[2] + 0.05), (wr[0] - 0.03, wr[1] - 0.15, wr[2] + 0.07), (wr[0] - 0.03, wr[1] - 0.25, wr[2] + 0.07)], v, 0.04)
    v = variant(m, "V2_Shield", "Spine", (0.0, 1.25, -0.2))
    for k in range(4):
        m.box(K("wood", (0.4, 0.31, 0.2)), (0.12, 0.6, 0.04), (-0.18 + k * 0.12, 1.25, -0.24), node=v, tilt=-8)
    m.box(K("metal", RUST), (0.5, 0.05, 0.05), (0.0, 1.42, -0.27), node=v)
    m.box(K("metal", RUST), (0.5, 0.05, 0.05), (0.0, 1.08, -0.21), node=v)
    y, f = b.head_y, b.head_f
    v = variant(m, "V3_Net", "Head", (0.0, y, f))
    m.loft(K("cloth", (0.55, 0.52, 0.44)), [(0.0, y + 0.02, f, 0.1, 0.11), (0.0, y + 0.12, f, 0.11, 0.12), (0.0, y + 0.2, f - 0.01, 0.06, 0.07), (0.0, y + 0.24, f - 0.02, 0.015, 0.015)], node=v, segs=10)
    for x in (-0.09, 0.08):
        m.ball(K("paint", (0.85, 0.5, 0.15)), 0.035, (x, y + 0.04, f - 0.08), node=v, u=10, v=7)


MODELS = (("en_drowned", drowned), ("en_drowned_runner", drowned_runner), ("en_swimmer", swimmer), ("en_reef_crab", reef_crab), ("en_tide_brute", tide_brute))


def main():
    fk.init()
    only = set(filter(None, os.environ.get("ONLY", "").split(",")))
    for name, maker in MODELS:
        if only and name not in only:
            continue
        m = kit.Model(name, uv_scale=0.5, colored=True)
        maker(m)
        print(name, m.export(OUT), "triangles")


if __name__ == "__main__":
    main()
