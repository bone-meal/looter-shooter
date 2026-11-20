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
# The colosseum (D2b): en_skeleton_sword (rusty sword; kettle helm / hood / round shield), en_skeleton_archer (bow and
# quiver; hood / feathered cap / crown), en_raider (jerkin, chest plate, machete; tyre pauldron + mohawk / gas mask +
# hood / road-sign shield), en_feral (gaunt, clawed, ragged; dreadlocks / face paint + bone necklace / chain collar),
# en_scav_gunner (canvas coat, bandolier, drum gun, goggles; helmet / bandana / pack + bedroll), en_marksman (poncho,
# scoped long rifle; hood + scarf / boonie hat / ghillie strips), en_brute (2.7 m, apron, nailed club; scrap mask /
# chains / scrap plates). Guns and bows hang along the forearm at rest: the aim pose brings them level.
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


# ---------- weapons (in the hand of a hanging arm: x right, y up, f forward; the arm's poses lift them) ----------

def grip_at(b, side):
    wr = b.wrist(side)
    return (wr[0], wr[1] - 0.06, wr[2] + 0.02)


def sword(m, b, node, side=1, length=0.75, mat=None):
    g = grip_at(b, side)
    steel = mat or K("metal", (0.55, 0.55, 0.58))
    m.rod(K("leather", (0.25, 0.16, 0.1)), 0.016, (g[0], g[1] + 0.06, g[2] - 0.03), (g[0], g[1] - 0.05, g[2] + 0.02), node=node, segs=8)  # grip
    m.box(K("metal", (0.45, 0.4, 0.3)), (0.03, 0.03, 0.16), (g[0], g[1] - 0.06, g[2] + 0.02), node=node)  # cross guard
    tip = (g[0], g[1] - 0.06 - length * 0.55, g[2] + 0.02 + length * 0.8)
    m.loft(steel, [(g[0], g[1] - 0.07, g[2] + 0.03, 0.006, 0.026), ((g[0] + tip[0]) / 2, (g[1] + tip[1]) / 2, (g[2] + tip[2]) / 2, 0.005, 0.024), (tip[0], tip[1], tip[2], 0.002, 0.004)], node=node, segs=6, flat=True)


def club(m, b, node, side=1, length=0.9, nails=True):
    g = grip_at(b, side)
    tip = (g[0], g[1] - length * 0.75, g[2] + length * 0.6)  # hangs forward and down at rest
    m.loft(K("wood", (0.4, 0.28, 0.17)), [(g[0], g[1] + 0.06, g[2] - 0.03, 0.025, 0.025), (g[0], g[1] - 0.05, g[2] + 0.02, 0.03, 0.03), ((g[0] + tip[0]) / 2, (g[1] + tip[1]) / 2, (g[2] + tip[2]) / 2, 0.05, 0.05), (tip[0], tip[1], tip[2], 0.075, 0.075)], node=node, segs=10)
    if nails:
        for k in range(8):
            a = k * 0.8
            p = (tip[0] + math.cos(a) * 0.07, tip[1] + 0.05 * math.sin(a * 1.3), tip[2] - 0.04 + 0.03 * math.sin(a))
            m.rod(K("metal", RUST), 0.006, p, (p[0] + math.cos(a) * 0.05, p[1] + 0.01, p[2] + 0.01), node=node, segs=5)


def machete(m, b, node, side=1):
    g = grip_at(b, side)
    m.rod(K("leather", (0.2, 0.14, 0.1)), 0.017, (g[0], g[1] + 0.06, g[2] - 0.03), (g[0], g[1] - 0.04, g[2] + 0.02), node=node, segs=8)
    m.prof(K("metal", (0.48, 0.46, 0.44)), 0.006, [(g[2] + 0.02, g[1] - 0.04), (g[2] + 0.5, g[1] - 0.32), (g[2] + 0.56, g[1] - 0.26), (g[2] + 0.06, g[1] - 0.0)], x=g[0], node=node)


def gun(m, b, node, side=1, length=0.6, scope=False, drum=False):
    """A scrap gun held along the forearm (pointing down at rest: the aim pose brings the forearm level)."""
    g = grip_at(b, side)
    x, y, f = g[0], g[1] + 0.02, g[2] + 0.05
    metal, wood = K("metal", (0.25, 0.25, 0.27)), K("wood", (0.4, 0.27, 0.16))
    m.loft(wood, [(x, y + 0.24, f - 0.03, 0.025, 0.04), (x, y + 0.05, f, 0.024, 0.035)], node=node, segs=8)  # stock along the forearm
    m.box(metal, (0.05, 0.16, 0.07), (x, y - 0.04, f + 0.01), node=node)  # receiver
    m.rod(metal, 0.016, (x, y - 0.12, f + 0.01), (x, y - 0.12 - length * 0.6, f + 0.02), node=node, segs=10)  # barrel
    m.rod(K("leather", (0.2, 0.15, 0.1)), 0.02, (x, y - 0.02, f + 0.06), (x, y - 0.12, f + 0.06), node=node, segs=6)  # wrapped grip
    if scope:
        m.rod(metal, 0.022, (x, y - 0.0, f + 0.07), (x, y - 0.22, f + 0.07), node=node, segs=10)
        m.ball(K("ice", (0.3, 0.5, 0.6)), 0.018, (x, y - 0.225, f + 0.07), node=node, u=8, v=6)
    if drum:
        m.lathe(metal, [(0.0, -0.03), (0.06, -0.03), (0.065, 0.0), (0.06, 0.03), (0.0, 0.03)], (x, y - 0.08, f + 0.09), node=node, segs=14, axis="x")


def bow(m, b, node, side=-1):
    g = grip_at(b, side)
    x, y, f = g[0], g[1] + 0.03, g[2]
    wood = K("wood", (0.36, 0.24, 0.14))
    m.loft(wood, [(x, y, f - 0.62, 0.008, 0.012), (x, y - 0.06, f - 0.35, 0.014, 0.02), (x, y - 0.03, f, 0.02, 0.025), (x, y - 0.06, f + 0.35, 0.014, 0.02), (x, y, f + 0.62, 0.008, 0.012)], node=node, segs=8)
    m.rod(K("cloth", (0.85, 0.82, 0.72)), 0.003, (x, y + 0.0, f - 0.61), (x, y + 0.0, f + 0.61), node=node, segs=4)  # string


# ---------- bones ----------

def skeleton_body(m, b, bone):
    """A walking skeleton: skull with a hinged jaw, spine, ribcage, pelvis, limb bones, hands and feet of bones."""
    hn = b.hunch
    m.lathe(bone, [(0.0, -0.04), (0.08, -0.03), (0.11, 0.02), (0.09, 0.07), (0.0, 0.08)], (0.0, 0.94, 0.0), node="Hips", segs=12, squash=0.6)  # pelvis
    for k in range(7):  # spine
        m.ball(bone, (0.025, 0.02, 0.025), (0.0, 1.04 + k * 0.06, -0.03 + hn * k / 7.0), node="Spine", u=8, v=5)
    for k in range(6):  # ribs
        y = 1.2 + k * 0.045
        w = 0.15 - abs(k - 2) * 0.012
        m.loft(bone, [(-0.0, y, -0.04, 0.008, 0.008), (-w, y - 0.02, 0.02 + hn * 0.6, 0.009, 0.009), (-w * 0.6, y - 0.05, 0.1 + hn * 0.6, 0.008, 0.008), (0.0, y - 0.06, 0.11 + hn * 0.6, 0.008, 0.008), (w * 0.6, y - 0.05, 0.1 + hn * 0.6, 0.008, 0.008), (w, y - 0.02, 0.02 + hn * 0.6, 0.009, 0.009), (0.0, y, -0.04, 0.008, 0.008)], node="Spine", segs=6, steps=2)
    m.loft(bone, [(-b.sx, b.shoulder_y, hn, 0.012, 0.012), (0.0, b.shoulder_y + 0.02, hn + 0.06, 0.012, 0.012), (b.sx, b.shoulder_y, hn, 0.012, 0.012)], node="Spine", segs=6)  # collarbones
    m.rod(bone, 0.015, (0.0, b.neck_y - 0.05, hn), (0.0, b.head_y + 0.02, b.head_f), node="Spine", segs=6)
    y, f = b.head_y, b.head_f
    m.loft(bone, [(0.0, y + 0.06, f - 0.01, 0.07, 0.085), (0.0, y + 0.13, f, 0.085, 0.1), (0.0, y + 0.2, f - 0.01, 0.08, 0.095), (0.0, y + 0.25, f - 0.02, 0.03, 0.03)], node="Head", segs=14)  # cranium
    m.loft(bone, [(-0.05, y + 0.08, f + 0.06, 0.02, 0.02), (0.0, y + 0.05, f + 0.08, 0.035, 0.02), (0.05, y + 0.08, f + 0.06, 0.02, 0.02)], node="Head", segs=8)  # cheeks + upper teeth
    for side in (-1, 1):
        m.ball(K("paint", (0.03, 0.02, 0.02)), (0.026, 0.026, 0.015), (side * 0.035, y + 0.13, f + 0.085), node="Head", u=8, v=6)  # sockets
        m.ball((fk.GLOW, (1.0, 0.45, 0.2)), 0.009, (side * 0.035, y + 0.13, f + 0.09), node="Head", u=6, v=5)  # embers in them
    m.prof(K("paint", (0.03, 0.02, 0.02)), 0.01, [(f + 0.08, y + 0.11), (f + 0.1, y + 0.07), (f + 0.08, y + 0.07)], x=0.0, node="Head")  # nose hole
    m.loft(bone, [(-0.05, y + 0.06, f + 0.03, 0.012, 0.012), (0.0, y + 0.02, f + 0.075, 0.03, 0.015), (0.05, y + 0.06, f + 0.03, 0.012, 0.012)], node="Jaw", segs=8)
    for k in range(5):
        m.box(bone, (0.008, 0.012, 0.006), (-0.025 + k * 0.0125, y + 0.035, f + 0.075), node="Jaw", bevel=0.001)
    for side, s in ((-1, "L"), (1, "R")):
        sh, el, wr = b.shoulder(side), b.elbow(side), b.wrist(side)
        m.bone(bone, 0.016, sh, el, node="Arm" + s, knob=1.6)
        m.rod(bone, 0.011, el, wr, node="Fore" + s, segs=6)
        m.rod(bone, 0.009, (el[0] + side * 0.012, el[1], el[2]), (wr[0] + side * 0.012, wr[1], wr[2]), node="Fore" + s, segs=6)
        for i in range(4):  # finger bones
            fx = wr[2] + 0.02 - i * 0.013
            m.rod(bone, 0.005, (wr[0], wr[1] - 0.02, fx), (wr[0] + side * 0.004, wr[1] - 0.09, fx + 0.01), node="Fore" + s, segs=5)
        hp, kn = b.hip(side), b.knee(side)
        m.bone(bone, 0.02, (hp[0], hp[1] + 0.01, 0.0), kn, node="Leg" + s, knob=1.5)
        m.rod(bone, 0.015, kn, (kn[0], b.ankle_y + 0.02, 0.0), node="Shin" + s, segs=6)
        m.ball(bone, 0.024, kn, node="Shin" + s, u=8, v=6)  # kneecap
        for i in range(4):
            m.rod(bone, 0.007, (kn[0] - 0.02 + i * 0.013, 0.05, 0.0), (kn[0] - 0.02 + i * 0.013, 0.02, 0.14), node="Shin" + s, segs=5)
        m.ball(bone, (0.03, 0.025, 0.04), (kn[0], 0.06, -0.02), node="Shin" + s, u=8, v=5)  # heel


BONE = (0.86, 0.82, 0.7)


def skeleton_sword(m):
    rnd = random.Random(61)
    b = Body(girth=0.8, hunch=0.03, arm=1.02, head=1.0)
    b.nodes(m)
    bone = K("bone", BONE)
    skeleton_body(m, b, bone)
    m.loft(K("cloth", (0.35, 0.18, 0.15)), [(0.0, 0.84, 0.0, 0.13, 0.1), (0.0, 0.97, 0.0, 0.12, 0.09)], node="Hips", segs=12, flat=True)  # loincloth band
    for k in range(5):
        a = -0.9 + k * 0.45
        m.prof(K("cloth", (0.35, 0.18, 0.15)), 0.006, [(math.sin(a) * 0.1 - 0.03, 0.86), (math.sin(a) * 0.1 + 0.03, 0.86), (math.sin(a) * 0.1, 0.62 + rnd.uniform(0, 0.08))], x=math.cos(a) * 0.12, node="Hips", bevel=0.0)
    sword(m, b, "ForeR", 1, 0.8, K("metal", (0.5, 0.42, 0.34)))
    y, f = b.head_y, b.head_f
    v = variant(m, "V1_Helm", "Head", (0.0, y, f))  # rusted kettle helm
    m.lathe(K("metal", RUST), [(0.0, 0.11), (0.06, 0.1), (0.1, 0.06), (0.105, 0.0), (0.16, -0.01), (0.16, -0.02), (0.0, -0.02)], (0.0, y + 0.17, f - 0.01), node=v, segs=16)
    v = variant(m, "V2_Hood", "Head", (0.0, y, f))
    m.loft(K("cloth", (0.25, 0.22, 0.2)), [(0.0, y + 0.0, f - 0.06, 0.11, 0.1), (0.0, y + 0.14, f - 0.02, 0.115, 0.12), (0.0, y + 0.24, f - 0.05, 0.07, 0.08), (0.0, y + 0.28, f - 0.1, 0.02, 0.02)], node=v, segs=14)
    v = variant(m, "V3_Shield", "ForeL", b.elbow(-1))
    el = b.elbow(-1)
    m.lathe(K("wood", (0.4, 0.3, 0.2)), [(0.0, 0.0), (0.24, 0.0), (0.25, 0.03), (0.0, 0.035)], (el[0] - 0.06, el[1] - 0.12, el[2]), node=v, segs=18, axis="x")
    m.lathe(K("metal", RUST), [(0.0, 0.03), (0.06, 0.035), (0.0, 0.07)], (el[0] - 0.06, el[1] - 0.12, el[2]), node=v, segs=12, axis="x")
    m.lathe(K("metal", RUST), [(0.24, -0.005), (0.26, 0.015), (0.24, 0.04)], (el[0] - 0.06, el[1] - 0.12, el[2]), node=v, segs=18, axis="x")


def skeleton_archer(m):
    rnd = random.Random(71)
    b = Body(girth=0.78, hunch=0.02, arm=1.04, head=0.98)
    b.nodes(m)
    bone = K("bone", (0.82, 0.8, 0.72))
    skeleton_body(m, b, bone)
    m.loft(K("cloth", (0.22, 0.3, 0.2)), [(0.0, 0.84, 0.0, 0.13, 0.1), (0.0, 0.97, 0.0, 0.12, 0.09)], node="Hips", segs=12, flat=True)
    bow(m, b, "ForeL", -1)
    for k in range(3):  # a quiver on the back
        pass
    m.lathe(K("leather", (0.35, 0.22, 0.12)), [(0.0, 0.0), (0.05, 0.0), (0.05, 0.42), (0.0, 0.42)], (0.1, 1.05, -0.12), node="Spine", segs=10)
    for k in range(5):
        p = (0.08 + rnd.uniform(-0.02, 0.03), 1.47, -0.12 + rnd.uniform(-0.02, 0.02))
        m.rod(K("wood", WOOD), 0.004, (p[0], 1.3, p[2]), p, node="Spine", segs=4)
        m.prof(K("cloth", (0.8, 0.25, 0.2)), 0.002, [(p[2] - 0.01, p[1]), (p[2] + 0.01, p[1]), (p[2], p[1] + 0.06)], x=p[0], node="Spine", bevel=0.0)
    m.rod(K("leather", (0.35, 0.22, 0.12)), 0.012, (-0.15, 1.45, 0.05), (0.15, 1.05, 0.1), node="Spine", segs=6)  # strap
    y, f = b.head_y, b.head_f
    v = variant(m, "V1_Hood", "Head", (0.0, y, f))
    m.loft(K("cloth", (0.2, 0.28, 0.18)), [(0.0, y + 0.0, f - 0.06, 0.11, 0.1), (0.0, y + 0.14, f - 0.02, 0.115, 0.12), (0.0, y + 0.24, f - 0.05, 0.07, 0.08), (0.0, y + 0.3, f - 0.12, 0.02, 0.02)], node=v, segs=14)
    v = variant(m, "V2_Cap", "Head", (0.0, y, f))
    m.lathe(K("cloth", (0.5, 0.3, 0.15)), [(0.0, 0.07), (0.07, 0.065), (0.1, 0.02), (0.11, 0.0), (0.0, 0.0)], (0.0, y + 0.19, f - 0.01), node=v, segs=14)
    m.prof(K("cloth", (0.9, 0.85, 0.75)), 0.004, [(f - 0.05, y + 0.24), (f - 0.2, y + 0.38), (f - 0.15, y + 0.4), (f - 0.03, y + 0.26)], x=0.07, node=v)  # feather
    v = variant(m, "V3_Crown", "Head", (0.0, y, f))
    m.lathe(K("metal", (0.6, 0.48, 0.22)), [(0.095, 0.0), (0.1, 0.03), (0.095, 0.035)], (0.0, y + 0.2, f - 0.01), node=v, segs=14)
    for k in range(6):
        a = k * math.tau / 6
        m.rod(K("metal", (0.6, 0.48, 0.22)), 0.01, (math.sin(a) * 0.097, y + 0.23, f - 0.01 + math.cos(a) * 0.097), (math.sin(a) * 0.1, y + 0.28, f - 0.01 + math.cos(a) * 0.1), r2=0.002, node=v, segs=5)


# ---------- the wasteland's people ----------

LEATHER = (0.3, 0.2, 0.13)
SCRAP = (0.4, 0.38, 0.35)
SKIN_W = (0.5, 0.37, 0.29)


def boots(m, b, mat):
    for side, s in ((-1, "L"), (1, "R")):
        kn = b.knee(side)
        m.loft(mat, [(kn[0], 0.32, 0.0, 0.058, 0.062), (kn[0], 0.1, 0.0, 0.05, 0.055)], node="Shin" + s, segs=10, flat=True)
        x = kn[0]
        m.loft(mat, [(x, 0.08, -0.045, 0.048, 0.045), (x, 0.06, 0.06, 0.052, 0.04), (x, 0.045, 0.17, 0.045, 0.03)], node="Shin" + s, segs=10)


def scrap_plate(m, mat, at, size, node, tilt=0.0):
    m.box(mat, size, at, tilt=tilt, node=node, bevel=0.006)
    for dx in (-1, 1):
        m.ball(K("metal", (0.5, 0.48, 0.44)), 0.007, (at[0] + dx * size[0] * 0.38, at[1] + size[1] * 0.35, at[2] + size[2] * 0.5), node=node, u=6, v=4)


def raider(m):
    rnd = random.Random(81)
    b = Body(girth=1.02, shoulders=1.05, hunch=0.03)
    b.nodes(m)
    skin = K("leather", SKIN_W)
    flesh(m, b, skin, eye=(1.0, 0.5, 0.2), eyes_glow=False, brow=1.3)
    shirt(m, b, K("leather", LEATHER), sleeves=0.3, seed=11)  # leather jerkin
    trousers(m, b, K("cloth", (0.3, 0.27, 0.22)), seed=12)
    boots(m, b, K("leather", (0.18, 0.13, 0.09)))
    belt(m, b, K("leather", (0.15, 0.1, 0.07)), knot=False)
    m.box(K("metal", (0.6, 0.55, 0.4)), (0.05, 0.04, 0.02), (0.0, 1.015, 0.13), node="Hips")  # buckle
    for k in range(3):  # pouches
        m.box(K("leather", (0.25, 0.17, 0.11)), (0.06, 0.08, 0.04), (-0.14 + k * 0.05, 0.96, 0.08 - k * 0.06), node="Hips")
    scrap_plate(m, K("metal", SCRAP), (0.0, 1.28, b.hunch * 0.6 + 0.135), (0.22, 0.18, 0.02), "Spine", tilt=-6)  # chest plate
    for side, s in ((-1, "L"), (1, "R")):  # bracers
        el = b.elbow(side)
        m.loft(K("leather", (0.22, 0.15, 0.1)), [(el[0], el[1] - 0.05, el[2], 0.05, 0.05), (el[0], el[1] - 0.2, el[2] + 0.01, 0.042, 0.04)], node="Fore" + s, segs=10, flat=True)
    machete(m, b, "ForeR", 1)
    sh = b.shoulder(-1)
    v = variant(m, "V1_Tyre", "ArmL", sh)  # a tyre-tread pauldron + a mohawk
    m.lathe(K("leather", (0.08, 0.08, 0.09)), [(0.0, 0.0), (0.12, 0.0), (0.13, 0.05), (0.08, 0.1), (0.0, 0.1)], (sh[0] - 0.02, sh[1] - 0.02, sh[2]), node=v, segs=14, squash=0.8)
    y, f = b.head_y, b.head_f
    v2 = variant(m, "V1_Mohawk", "Head", (0.0, y, f))
    for k in range(8):
        m.prof(K("cloth", (0.75, 0.2, 0.15)), 0.02, [(f + 0.07 - k * 0.025, y + 0.24 - k * 0.006), (f + 0.06 - k * 0.025, y + 0.32 - abs(k - 3) * 0.008), (f + 0.04 - k * 0.025, y + 0.235 - k * 0.006)], x=0.0, node=v2)
    v = variant(m, "V2_Mask", "Head", (0.0, y, f))  # gas mask + hood
    m.lathe(K("leather", (0.15, 0.15, 0.14)), [(0.0, 0.0), (0.075, 0.0), (0.08, 0.05), (0.05, 0.08), (0.0, 0.085)], (0.0, y + 0.08, f + 0.07), node=v, segs=14, axis="f")
    for side in (-1, 1):
        m.lathe(K("ice", (0.5, 0.15, 0.1)), [(0.0, 0.0), (0.022, 0.0), (0.022, 0.01), (0.0, 0.011)], (side * 0.036, y + 0.13, f + 0.1), node=v, segs=10, axis="f")
    m.lathe(K("metal", SCRAP), [(0.0, 0.0), (0.03, 0.0), (0.035, 0.05), (0.0, 0.06)], (0.0, y + 0.05, f + 0.14), node=v, segs=10, axis="f")  # filter
    m.loft(K("cloth", (0.35, 0.3, 0.24)), [(0.0, y + 0.0, f - 0.06, 0.11, 0.1), (0.0, y + 0.14, f - 0.03, 0.12, 0.125), (0.0, y + 0.24, f - 0.05, 0.08, 0.09), (0.0, y + 0.28, f - 0.11, 0.02, 0.02)], node=v, segs=14)
    v = variant(m, "V3_Sign", "ForeL", b.elbow(-1))  # a road sign for a shield
    el = b.elbow(-1)
    m.lathe(K("paint", (0.8, 0.12, 0.1)), [(0.0, 0.0), (0.22, 0.0), (0.22, 0.012), (0.0, 0.012)], (el[0] - 0.06, el[1] - 0.12, el[2]), node=v, segs=8, axis="x")
    m.box(K("paint", (0.95, 0.95, 0.92)), (0.018, 0.05, 0.26), (el[0] - 0.07, el[1] - 0.12, el[2]), node=v)


def feral(m):
    rnd = random.Random(91)
    b = Body(girth=0.84, shoulders=0.95, hips=0.9, hunch=0.11, arm=1.16, arm_r=0.85, leg_r=0.88, head=0.95, neck=1.1)
    b.nodes(m)
    skin = K("leather", (0.42, 0.34, 0.27))
    flesh(m, b, skin, eye=(0.9, 0.95, 0.4), brow=1.6, gaunt=1.0)
    for side, s in ((-1, "L"), (1, "R")):
        hand(m, b, side, skin, "Fore" + s, claws=K("bone", (0.22, 0.2, 0.17)))
    for k in range(5):  # ribs and a long scar
        m.loft(K("leather", (0.46, 0.38, 0.3)), [(-0.11, 1.15 + k * 0.045, b.hunch * 0.5 + 0.09, 0.008, 0.006), (0.0, 1.16 + k * 0.045, b.hunch * 0.5 + 0.115, 0.009, 0.006), (0.11, 1.15 + k * 0.045, b.hunch * 0.5 + 0.09, 0.008, 0.006)], node="Spine", segs=6)
    m.loft(K("leather", (0.45, 0.15, 0.12)), [(-0.12, 1.38, b.hunch + 0.08, 0.006, 0.004), (0.05, 1.2, b.hunch * 0.5 + 0.12, 0.006, 0.004), (0.13, 1.05, 0.11, 0.005, 0.004)], node="Spine", segs=5)
    trousers(m, b, K("cloth", (0.33, 0.3, 0.24)), length=0.55, torn=1.0, seed=13)
    m.loft(K("cloth", (0.33, 0.3, 0.24)), [(0.0, 0.98, 0.0, 0.15, 0.11), (0.0, 1.04, 0.0, 0.145, 0.107)], node="Hips", segs=12, steps=1, flat=True)
    y, f = b.head_y, b.head_f
    v = variant(m, "V1_Dreads", "Head", (0.0, y, f))
    for k in range(12):
        a = -1.6 + k * 0.28
        start = (math.sin(a) * 0.085, y + 0.2, f - 0.02 + math.cos(a) * 0.06 - 0.04)
        m.loft(K("cloth", (0.15, 0.12, 0.1)), [(start[0], start[1], start[2], 0.012, 0.012), (start[0] * 1.3, start[1] - 0.12, start[2] - 0.05, 0.011, 0.011), (start[0] * 1.4, start[1] - 0.26, start[2] - 0.06, 0.008, 0.008)], node=v, segs=6)
    v = variant(m, "V2_Paint", "Head", (0.0, y, f))  # face paint + bone necklace
    for side in (-1, 1):
        m.prof(K("paint", (0.85, 0.82, 0.75)), 0.004, [(f + 0.085, y + 0.16), (f + 0.08, y + 0.08), (f + 0.07, y + 0.08), (f + 0.075, y + 0.16)], x=side * 0.04, node=v)
    v3 = variant(m, "V2_Necklace", "Spine", (0.0, b.neck_y, b.hunch))
    for k in range(9):
        a = -1.1 + k * 0.275
        p = (math.sin(a) * 0.09, b.neck_y - 0.07 - math.cos(a) * 0.03, b.hunch + math.cos(a) * 0.08)
        m.rod(K("bone", BONE), 0.006, p, (p[0], p[1] - 0.05, p[2] + 0.01), r2=0.002, node=v3, segs=5)
    v = variant(m, "V3_Collar", "Spine", (0.0, b.neck_y, b.hunch))
    m.lathe(K("metal", RUST), [(0.065, -0.02), (0.07, 0.0), (0.065, 0.02)], (0.0, b.neck_y - 0.02, b.hunch * 0.95), node=v, segs=14)
    chain(m, K("metal", RUST), [(0.0, b.neck_y - 0.06, b.hunch + 0.07), (0.0, b.neck_y - 0.14, b.hunch + 0.1), (0.02, b.neck_y - 0.22, b.hunch + 0.11), (0.03, b.neck_y - 0.3, b.hunch + 0.1)], v)


def scav_gunner(m):
    rnd = random.Random(101)
    b = Body(girth=1.04, shoulders=1.02, belly=0.02, hunch=0.03)
    b.nodes(m)
    skin = K("leather", (0.47, 0.35, 0.27))
    flesh(m, b, skin, eyes_glow=False, brow=1.1)
    shirt(m, b, K("cloth", (0.42, 0.4, 0.3)), sleeves=0.9, seed=14)  # canvas coat
    m.loft(K("cloth", (0.42, 0.4, 0.3)), [(0.0, 1.0, 0.0, 0.17, 0.13), (0.0, 0.7, 0.0, 0.2, 0.15)], node="Hips", segs=14, flat=True)  # coat skirt
    trousers(m, b, K("cloth", (0.25, 0.26, 0.22)), seed=15)
    boots(m, b, K("leather", (0.16, 0.12, 0.08)))
    for k in range(4):  # an ammo bandolier
        m.box(K("metal", (0.6, 0.5, 0.25)), (0.03, 0.05, 0.03), (-0.12 + k * 0.07, 1.42 - k * 0.09, b.hunch * 0.6 + 0.13), node="Spine")
    m.rod(K("leather", LEATHER), 0.018, (-0.16, 1.45, b.hunch * 0.6 + 0.11), (0.16, 1.05, 0.13), node="Spine", segs=6)
    scrap_plate(m, K("metal", SCRAP), (b.sx + 0.03, b.shoulder_y + 0.02, b.hunch), (0.12, 0.04, 0.14), "ArmR")
    gun(m, b, "ForeR", 1, 0.55, drum=True)
    y, f = b.head_y, b.head_f
    for side in (-1, 1):  # goggles up on the forehead (always)
        m.lathe(K("metal", (0.35, 0.33, 0.3)), [(0.0, 0.0), (0.025, 0.0), (0.025, 0.02), (0.0, 0.022)], (side * 0.035, y + 0.19, f + 0.075), node="Head", segs=10, axis="f")
    v = variant(m, "V1_Helmet", "Head", (0.0, y, f))
    m.lathe(K("metal", (0.33, 0.36, 0.3)), [(0.0, 0.1), (0.07, 0.095), (0.105, 0.05), (0.11, 0.0), (0.13, -0.01), (0.0, -0.01)], (0.0, y + 0.17, f - 0.01), node=v, segs=16)
    v = variant(m, "V2_Bandana", "Head", (0.0, y, f))
    m.loft(K("cloth", (0.6, 0.3, 0.15)), [(0.0, y + 0.03, f + 0.02, 0.09, 0.1), (0.0, y + 0.1, f + 0.01, 0.095, 0.105)], node=v, segs=14, flat=True)
    v = variant(m, "V3_Pack", "Spine", (0.0, 1.25, -0.15))
    m.box(K("cloth", (0.32, 0.3, 0.22)), (0.28, 0.34, 0.16), (0.0, 1.25, -0.2), node=v, bevel=0.03)
    m.lathe(K("cloth", (0.28, 0.26, 0.2)), [(0.0, 0.0), (0.06, 0.0), (0.06, 0.3), (0.0, 0.3)], (-0.15, 1.47, -0.2), node=v, segs=10, axis="x")  # bedroll


def marksman(m):
    rnd = random.Random(111)
    b = Body(girth=0.95, hunch=0.05, arm=1.02, leg_r=0.95)
    b.nodes(m)
    skin = K("leather", (0.42, 0.31, 0.24))
    flesh(m, b, skin, eyes_glow=False, brow=1.0)
    shirt(m, b, K("cloth", (0.3, 0.33, 0.26)), sleeves=0.95, seed=16)
    trousers(m, b, K("cloth", (0.28, 0.27, 0.22)), seed=17)
    boots(m, b, K("leather", (0.17, 0.12, 0.08)))
    # a long poncho over the shoulders
    m.loft(K("cloth", (0.36, 0.34, 0.26)), [(0.0, 1.48, b.hunch, 0.16, 0.11), (0.0, 1.3, b.hunch * 0.6, 0.26, 0.17), (0.0, 1.0, 0.0, 0.27, 0.18)], node="Spine", segs=16, flat=True)
    m.box(K("leather", LEATHER), (0.16, 0.05, 0.06), (0.0, 0.98, 0.14), node="Hips")
    gun(m, b, "ForeR", 1, 1.0, scope=True)
    y, f = b.head_y, b.head_f
    v = variant(m, "V1_Hood", "Head", (0.0, y, f))
    m.loft(K("cloth", (0.36, 0.34, 0.26)), [(0.0, y - 0.0, f - 0.06, 0.11, 0.1), (0.0, y + 0.14, f - 0.02, 0.12, 0.125), (0.0, y + 0.24, f - 0.05, 0.08, 0.09), (0.0, y + 0.28, f - 0.11, 0.02, 0.02)], node=v, segs=14)
    m.loft(K("cloth", (0.3, 0.28, 0.22)), [(0.0, y + 0.03, f + 0.02, 0.09, 0.1), (0.0, y + 0.1, f + 0.01, 0.095, 0.105)], node=v, segs=14, flat=True)  # scarf over the mouth
    v = variant(m, "V2_Boonie", "Head", (0.0, y, f))
    m.lathe(K("cloth", (0.35, 0.36, 0.25)), [(0.0, 0.08), (0.08, 0.075), (0.1, 0.02), (0.17, -0.01), (0.17, -0.02), (0.0, -0.02)], (0.0, y + 0.18, f - 0.01), node=v, segs=16)
    v = variant(m, "V3_Ghillie", "Spine", (0.0, 1.3, 0.0))
    for k in range(26):
        a = rnd.uniform(0, math.tau)
        p = (math.cos(a) * 0.24, rnd.uniform(1.05, 1.45), math.sin(a) * 0.16)
        m.loft(K("cloth", (0.3 + rnd.uniform(-0.05, 0.05), 0.36, 0.2)), [(p[0], p[1], p[2], 0.015, 0.004), (p[0] * 1.1, p[1] - 0.12, p[2] * 1.1, 0.01, 0.003)], node=v, segs=4)


def brute(m):
    rnd = random.Random(121)
    b = Body(girth=1.45, shoulders=1.5, hips=1.2, belly=0.09, hunch=0.1, arm=1.12, arm_r=1.3, leg_r=1.2, head=0.9, neck=0.7)
    b.nodes(m)
    skin = K("leather", (0.45, 0.34, 0.29))
    flesh(m, b, skin, eyes_glow=False, brow=1.8)
    trousers(m, b, K("leather", (0.25, 0.18, 0.12)), length=0.8, seed=18)
    boots(m, b, K("leather", (0.14, 0.1, 0.07)))
    m.loft(K("leather", (0.4, 0.3, 0.2)), [(0.0, 1.35, b.hunch * 0.75 + 0.16, 0.22, 0.02), (0.0, 0.85, 0.2, 0.24, 0.02)], node="Spine", segs=6, flat=True)  # a heavy apron
    belt(m, b, K("leather", (0.14, 0.1, 0.07)), knot=False)
    for k in range(4):  # stitched scars
        p = (rnd.uniform(-0.15, 0.15), rnd.uniform(1.15, 1.4), b.hunch * 0.6 + 0.17)
        for i in range(4):
            m.box(K("leather", (0.25, 0.12, 0.1)), (0.004, 0.02, 0.004), (p[0] + i * 0.012, p[1], p[2]), node="Spine", bevel=0.0)
    club(m, b, "ForeR", 1, 0.7)
    y, f = b.head_y, b.head_f
    v = variant(m, "V1_Mask", "Head", (0.0, y, f))  # a welded scrap mask
    m.loft(K("metal", SCRAP), [(0.0, y + 0.02, f + 0.06, 0.08, 0.04), (0.0, y + 0.12, f + 0.075, 0.09, 0.04), (0.0, y + 0.2, f + 0.065, 0.08, 0.035)], node=v, segs=12)
    for side in (-1, 1):
        m.box(K("paint", (0.05, 0.03, 0.03)), (0.03, 0.012, 0.01), (side * 0.035, y + 0.13, f + 0.11), node=v)
    v = variant(m, "V2_Chains", "Spine", (0.0, 1.3, 0.0))
    chain(m, K("metal", RUST), [(-0.25, 1.48, 0.0), (-0.15, 1.38, 0.18), (0.0, 1.28, 0.24), (0.15, 1.18, 0.22), (0.25, 1.08, 0.12), (0.27, 1.0, 0.0)], v, 0.045)
    v = variant(m, "V3_Plates", "Spine", (0.0, 1.3, 0.0))
    scrap_plate(m, K("metal", SCRAP), (-0.1, 1.32, b.hunch * 0.6 + 0.19), (0.18, 0.22, 0.025), v, tilt=-8)
    scrap_plate(m, K("metal", (0.45, 0.32, 0.22)), (0.1, 1.3, b.hunch * 0.6 + 0.19), (0.17, 0.2, 0.025), v, tilt=-6)
    for side, s in ((-1, "L"), (1, "R")):
        sh = b.shoulder(side)
        scrap_plate(m, K("metal", SCRAP), (sh[0] + side * 0.05, sh[1] + 0.06, sh[2]), (0.2, 0.05, 0.22), variant(m, "V3_Pad" + s, "Arm" + s, sh))


# ---------- the bosses (D2c) ----------

BRASS = (0.72, 0.55, 0.24)
BRASS_DARK = (0.45, 0.33, 0.15)


def gear(m, mat, at, r, teeth, node, axis="f"):
    m.lathe(mat, [(0.0, -0.02), (r * 0.85, -0.02), (r * 0.85, 0.02), (0.0, 0.02)], at, node=node, segs=24, axis=axis)
    for k in range(teeth):
        a = k * math.tau / teeth
        if axis == "f":
            m.box(mat, (0.04 * r / 0.15, 0.04 * r / 0.15, 0.035), (at[0] + math.cos(a) * r * 0.9, at[1] + math.sin(a) * r * 0.9, at[2]), node=node, bevel=0.003)
        else:
            m.box(mat, (0.035, 0.04 * r / 0.15, 0.04 * r / 0.15), (at[0], at[1] + math.sin(a) * r * 0.9, at[2] + math.cos(a) * r * 0.9), node=node, bevel=0.003)


def clockwork_bear(m):
    rnd = random.Random(201)
    b = Body(girth=1.7, shoulders=1.45, hips=1.35, belly=0.12, hunch=0.04, arm=0.95, arm_r=1.5, leg_r=1.5, head=1.35, neck=0.5)
    b.nodes(m)
    brass, dark, steel = K("metal", BRASS), K("metal", BRASS_DARK), K("metal", (0.5, 0.5, 0.52))
    # the barrel body in riveted brass plates
    m.loft(brass, [(0.0, 0.84, 0.0, 0.25, 0.2), (0.0, 0.98, 0.0, 0.28, 0.24)], node="Hips", segs=18)
    m.loft(brass, [(0.0, 1.0, 0.0, 0.27, 0.24), (0.0, 1.15, 0.05, 0.31, 0.3), (0.0, 1.32, 0.06, 0.32, 0.29), (0.0, 1.45, 0.05, 0.26, 0.22), (0.0, 1.52, 0.04, 0.12, 0.1)], node="Spine", segs=20)
    for k in range(4):
        m.loft(dark, [(0.0, 1.06 + k * 0.12, 0.04, 0.3 + (0.02 if k in (1, 2) else 0), 0.29), (0.0, 1.075 + k * 0.12, 0.04, 0.305 + (0.02 if k in (1, 2) else 0), 0.295)], node="Spine", segs=20, steps=1, flat=True)
        for i in range(10):
            a = i * math.tau / 10
            m.ball(dark, 0.012, (math.sin(a) * 0.31, 1.07 + k * 0.12, 0.04 + math.cos(a) * 0.3), node="Spine", u=6, v=4)  # rivets
    # the chest window with its turning gear ("Gear") and a steel rim
    m.lathe(steel, [(0.11, -0.01), (0.14, 0.0), (0.14, 0.025), (0.11, 0.03)], (0.0, 1.26, 0.33), node="Spine", segs=20, axis="f")
    m.node("Gear", (0.0, 1.26, 0.34), parent="Spine")
    gear(m, K("metal", (0.85, 0.7, 0.3)), (0.0, 1.26, 0.34), 0.1, 10, "Gear")
    m.node("Key", (0.0, 1.25, -0.3), parent="Spine")  # the wind-up key on its back
    m.rod(steel, 0.025, (0.0, 1.25, -0.28), (0.0, 1.25, -0.42), node="Key", segs=8)
    m.prof(steel, 0.03, [(-0.42, 1.25), (-0.48, 1.42), (-0.56, 1.42), (-0.5, 1.25), (-0.56, 1.08), (-0.48, 1.08)], x=0.0, node="Key")
    # head: round brass bear head, round ears, muzzle with a hinged jaw, glass eyes
    y, f = b.head_y, b.head_f
    m.ball(brass, (0.2, 0.19, 0.19), (0.0, y + 0.15, f), node="Head", u=16, v=12)
    for side in (-1, 1):
        m.lathe(brass, [(0.0, -0.02), (0.07, -0.02), (0.075, 0.02), (0.0, 0.025)], (side * 0.15, y + 0.3, f - 0.02), node="Head", segs=14, axis="f")
        m.lathe(dark, [(0.0, 0.025), (0.045, 0.025), (0.0, 0.03)], (side * 0.15, y + 0.3, f - 0.02), node="Head", segs=12, axis="f")
        m.ball((fk.GLOW, (1.0, 0.75, 0.3)), 0.035, (side * 0.08, y + 0.2, f + 0.17), node="Head", u=10, v=8)
        m.lathe(steel, [(0.035, -0.01), (0.045, 0.0), (0.035, 0.01)], (side * 0.08, y + 0.2, f + 0.175), node="Head", segs=12, axis="f")
    m.ball(K("metal", (0.85, 0.7, 0.3)), (0.11, 0.08, 0.1), (0.0, y + 0.1, f + 0.15), node="Head", u=12, v=8)  # muzzle
    m.ball(K("leather", (0.08, 0.06, 0.05)), (0.035, 0.025, 0.03), (0.0, y + 0.13, f + 0.25), node="Head", u=8, v=6)  # nose
    m.ball(K("metal", (0.8, 0.65, 0.28)), (0.09, 0.04, 0.09), (0.0, y + 0.03, f + 0.14), node="Jaw", u=12, v=6)
    for k in range(4):
        m.rod(steel, 0.008, (-0.045 + k * 0.03, y + 0.06, f + 0.21), (-0.045 + k * 0.03, y + 0.03, f + 0.22), r2=0.002, node="Jaw", segs=5)
    # limbs: brass cylinders with ball joints and claws; the arms end in paw cannons
    for side, s in ((-1, "L"), (1, "R")):
        sh, el, wr = b.shoulder(side), b.elbow(side), b.wrist(side)
        m.ball(dark, 0.1, sh, node="Arm" + s, u=12, v=8)
        m.loft(brass, [(sh[0], sh[1] - 0.05, sh[2], 0.085, 0.085), (el[0], el[1], el[2], 0.075, 0.075)], node="Arm" + s, segs=14)
        m.ball(dark, 0.08, el, node="Fore" + s, u=10, v=8)
        m.loft(brass, [(el[0], el[1], el[2], 0.075, 0.075), (wr[0], wr[1], wr[2], 0.09, 0.09)], node="Fore" + s, segs=14)
        m.rod(steel, 0.04, (wr[0], wr[1] - 0.02, wr[2]), (wr[0], wr[1] - 0.2, wr[2] + 0.02), node="Fore" + s, segs=12)  # paw cannon barrel
        m.lathe(dark, [(0.045, 0.0), (0.06, 0.02), (0.045, 0.04)], (wr[0], wr[1] - 0.2, wr[2] + 0.02), node="Fore" + s, segs=12)
        for k in range(3):
            m.rod(K("bone", (0.9, 0.85, 0.7)), 0.012, (wr[0] + side * 0.02 - 0.03 + k * 0.03, wr[1] - 0.05, wr[2] + 0.08), (wr[0] + side * 0.02 - 0.03 + k * 0.03, wr[1] - 0.12, wr[2] + 0.13), r2=0.002, node="Fore" + s, segs=5)
        hp, kn = b.hip(side), b.knee(side)
        m.ball(dark, 0.11, hp, node="Leg" + s, u=12, v=8)
        m.loft(brass, [(hp[0], hp[1] - 0.05, 0.0, 0.11, 0.11), (kn[0], kn[1], kn[2], 0.09, 0.09)], node="Leg" + s, segs=14)
        m.ball(dark, 0.09, kn, node="Shin" + s, u=10, v=8)
        m.loft(brass, [(kn[0], kn[1], kn[2], 0.09, 0.09), (kn[0], 0.12, 0.0, 0.1, 0.1)], node="Shin" + s, segs=14)
        m.loft(brass, [(kn[0], 0.08, -0.06, 0.1, 0.08), (kn[0], 0.06, 0.1, 0.11, 0.07), (kn[0], 0.05, 0.2, 0.09, 0.05)], node="Shin" + s, segs=12)
        for k in range(3):
            m.rod(K("bone", (0.9, 0.85, 0.7)), 0.015, (kn[0] - 0.05 + k * 0.05, 0.05, 0.22), (kn[0] - 0.05 + k * 0.05, 0.02, 0.29), r2=0.003, node="Shin" + s, segs=5)
    v = variant(m, "V1_TopHat", "Head", (0.0, y, f))
    m.lathe(K("cloth", (0.1, 0.09, 0.1)), [(0.0, 0.0), (0.2, 0.0), (0.2, 0.02), (0.12, 0.025), (0.12, 0.25), (0.0, 0.26)], (0.0, y + 0.31, f - 0.02), node=v, segs=18)
    m.lathe(K("cloth", (0.5, 0.1, 0.1)), [(0.123, 0.03), (0.123, 0.07)], (0.0, y + 0.31, f - 0.02), node=v, segs=18)
    v = variant(m, "V2_Monocle", "Head", (0.0, y, f))
    m.lathe(K("metal", (0.85, 0.75, 0.35)), [(0.05, -0.006), (0.058, 0.0), (0.05, 0.006)], (0.08, y + 0.2, f + 0.185), node=v, segs=14, axis="f")
    m.rod(K("metal", (0.85, 0.75, 0.35)), 0.003, (0.13, y + 0.18, f + 0.18), (0.16, y + 0.0, f + 0.14), node=v, segs=4)
    v2 = variant(m, "V2_Bow", "Spine", (0.0, 1.5, 0.1))
    for side in (-1, 1):
        m.loft(K("cloth", (0.6, 0.08, 0.1)), [(0.0, 1.5, 0.17, 0.02, 0.02), (side * 0.07, 1.53, 0.16, 0.035, 0.012), (side * 0.12, 1.5, 0.15, 0.05, 0.01)], node=v2, segs=8)
    v = variant(m, "V3_Patches", "Spine", (0.0, 1.25, 0.0))
    for k in range(5):
        a = rnd.uniform(-1.2, 1.2)
        scrap_plate(m, K("metal", RUST), (math.sin(a) * 0.3, rnd.uniform(1.05, 1.42), math.cos(a) * 0.28 + 0.04), (0.12, 0.1, 0.02), v, tilt=rnd.uniform(-15, 15))


def butcher(m):
    rnd = random.Random(211)
    b = Body(girth=1.6, shoulders=1.5, hips=1.3, belly=0.14, hunch=0.09, arm=1.1, arm_r=1.4, leg_r=1.3, head=1.0, neck=0.6)
    b.nodes(m)
    skin = K("leather", (0.5, 0.36, 0.32))
    flesh(m, b, skin, eyes_glow=False, brow=1.8)
    trousers(m, b, K("cloth", (0.22, 0.2, 0.2)), length=0.85, seed=21)
    boots(m, b, K("leather", (0.12, 0.09, 0.07)))
    apron = K("leather", (0.62, 0.58, 0.5))
    m.loft(apron, [(0.0, 1.42, b.hunch * 0.8 + 0.19, 0.2, 0.02), (0.0, 1.15, b.hunch * 0.4 + 0.3, 0.26, 0.02), (0.0, 0.95, 0.27, 0.27, 0.02)], node="Spine", segs=6, flat=True)
    m.loft(apron, [(0.0, 0.98, 0.28, 0.27, 0.02), (0.0, 0.55, 0.2, 0.25, 0.02)], node="Hips", segs=6, flat=True)
    for k in range(7):
        y0 = rnd.uniform(0.75, 1.3)
        node = "Spine" if y0 > 1.0 else "Hips"
        fz = (0.3 if y0 > 1.0 else 0.25)
        m.ball(K("leather", (0.38, 0.04, 0.04)), (rnd.uniform(0.03, 0.07), rnd.uniform(0.04, 0.1), 0.012), (rnd.uniform(-0.18, 0.18), y0, fz), node=node, u=8, v=5)
    belt(m, b, K("leather", (0.14, 0.1, 0.07)), y=0.98, knot=False)
    # a cleaver in the right hand, a meat hook in the left
    g = grip_at(b, 1)
    m.rod(K("wood", (0.3, 0.2, 0.12)), 0.022, (g[0], g[1] + 0.07, g[2] - 0.03), (g[0], g[1] - 0.06, g[2] + 0.02), node="ForeR", segs=8)
    m.prof(K("metal", (0.55, 0.55, 0.57)), 0.012, [(g[2] + 0.0, g[1] - 0.05), (g[2] + 0.42, g[1] - 0.3), (g[2] + 0.42, g[1] - 0.58), (g[2] + 0.08, g[1] - 0.38)], x=g[0], node="ForeR")
    gl = grip_at(b, -1)
    m.rod(K("wood", (0.3, 0.2, 0.12)), 0.02, (gl[0], gl[1] + 0.06, gl[2] - 0.02), (gl[0], gl[1] - 0.05, gl[2] + 0.02), node="ForeL", segs=8)
    m.loft(K("metal", RUST), [(gl[0], gl[1] - 0.05, gl[2] + 0.02, 0.012, 0.012), (gl[0], gl[1] - 0.25, gl[2] + 0.04, 0.012, 0.012), (gl[0], gl[1] - 0.33, gl[2] + 0.13, 0.01, 0.01), (gl[0], gl[1] - 0.25, gl[2] + 0.2, 0.007, 0.007), (gl[0], gl[1] - 0.18, gl[2] + 0.18, 0.003, 0.003)], node="ForeL", segs=6)
    y, f = b.head_y, b.head_f
    v = variant(m, "V1_Sack", "Head", (0.0, y, f))
    m.loft(K("cloth", (0.55, 0.47, 0.34)), [(0.0, y - 0.0, f, 0.1, 0.11), (0.0, y + 0.12, f + 0.005, 0.105, 0.12), (0.0, y + 0.22, f - 0.01, 0.09, 0.1), (0.0, y + 0.29, f - 0.02, 0.03, 0.03)], node=v, segs=14)
    for side in (-1, 1):
        m.ball(K("leather", (0.04, 0.02, 0.02)), (0.022, 0.018, 0.01), (side * 0.036, y + 0.13, f + 0.11), node=v, u=8, v=6)
    m.lathe(K("cloth", ROPE), [(0.09, -0.01), (0.1, 0.0), (0.09, 0.01)], (0.0, y + 0.02, f), node=v, segs=14)
    v = variant(m, "V2_Cage", "Head", (0.0, y, f))
    for k in range(8):
        a = k * math.tau / 8
        m.loft(K("metal", RUST), [(math.sin(a) * 0.11, y + 0.0, f + math.cos(a) * 0.12, 0.008, 0.008), (math.sin(a) * 0.115, y + 0.15, f + math.cos(a) * 0.125, 0.008, 0.008), (math.sin(a) * 0.05, y + 0.27, f + math.cos(a) * 0.05, 0.008, 0.008), (0.0, y + 0.29, f, 0.008, 0.008)], node=v, segs=5)
    for yy in (y + 0.02, y + 0.16):
        m.lathe(K("metal", RUST), [(0.115, -0.008), (0.122, 0.0), (0.115, 0.008)], (0.0, yy, f), node=v, segs=16)
    v = variant(m, "V3_PigSkull", "Head", (0.0, y, f))
    m.ball(K("bone", BONE), (0.11, 0.1, 0.12), (0.0, y + 0.15, f + 0.04), node=v, u=12, v=9)
    m.loft(K("bone", BONE), [(0.0, y + 0.12, f + 0.12, 0.06, 0.05), (0.0, y + 0.1, f + 0.22, 0.05, 0.045)], node=v, segs=10)
    for side in (-1, 1):
        m.ball(K("leather", (0.03, 0.02, 0.02)), 0.025, (side * 0.045, y + 0.17, f + 0.14), node=v, u=8, v=6)
        m.ball(K("leather", (0.03, 0.02, 0.02)), (0.012, 0.016, 0.006), (side * 0.018, y + 0.1, f + 0.265), node=v, u=6, v=5)
        m.prof(K("bone", BONE), 0.015, [(f - 0.02, y + 0.25), (f - 0.05, y + 0.34), (f + 0.02, y + 0.27)], x=side * 0.08, node=v)


def dome_beast(m):
    rnd = random.Random(221)
    b = Body(girth=1.75, shoulders=1.7, hips=1.15, belly=0.04, hunch=0.22, arm=1.45, arm_r=1.55, leg_r=1.3, head=1.15, neck=0.5)
    b.nodes(m)
    hide, plate, horn = K("leather", (0.32, 0.3, 0.26)), K("bone", (0.72, 0.68, 0.58)), K("bone", (0.85, 0.8, 0.66))
    flesh(m, b, hide, eye=(0.6, 1.0, 0.4), brow=2.0, ears=False)
    y, f = b.head_y, b.head_f
    m.lathe(plate, [(0.0, 0.0), (0.13, -0.02), (0.15, 0.05), (0.12, 0.12), (0.06, 0.16), (0.0, 0.17)], (0.0, y + 0.15, f - 0.01), node="Head", segs=18)  # the bony dome
    for k in range(9):  # spikes down the spine
        yy = 1.48 - k * 0.07
        m.rod(plate, 0.035 - k * 0.002, (0.0, yy, -0.12 + b.hunch * (1.0 - k / 9) * 0.7), (0.0, yy + 0.08, -0.24 + b.hunch * (1.0 - k / 9) * 0.7), r2=0.004, node="Spine", segs=6)
    for side, s in ((-1, "L"), (1, "R")):  # huge knuckles for walking on, plated forearms
        hand(m, b, side, hide, "Fore" + s, claws=horn)
        el, wr = b.elbow(side), b.wrist(side)
        for k in range(3):
            scrap_plate(m, plate, (el[0] + side * 0.02, el[1] - 0.06 - k * 0.08, el[2] - 0.05), (0.09, 0.07, 0.03), "Fore" + s, tilt=10)
        m.ball(hide, (0.07, 0.06, 0.08), (wr[0], wr[1] - 0.06, wr[2] + 0.03), node="Fore" + s, u=10, v=7)
    for k in range(6):  # fur tufts on the shoulders
        p = (rnd.uniform(-0.25, 0.25), rnd.uniform(1.38, 1.5), rnd.uniform(-0.05, 0.15))
        m.loft(K("fur", (0.25, 0.22, 0.18)), [(p[0], p[1], p[2], 0.06, 0.04), (p[0] * 1.1, p[1] - 0.1, p[2] - 0.05, 0.04, 0.02)], node="Spine", segs=6)
    m.loft(K("cloth", (0.3, 0.25, 0.18)), [(0.0, 0.86, 0.0, 0.2, 0.15), (0.0, 1.0, 0.0, 0.19, 0.14)], node="Hips", segs=14, flat=True)
    v = variant(m, "V1_Chains", "Spine", (0.0, 1.3, 0.0))
    chain(m, K("metal", RUST), [(-0.3, 1.45, 0.05), (-0.1, 1.32, 0.3), (0.1, 1.2, 0.3), (0.3, 1.1, 0.1)], v, 0.05)
    for side, s in ((-1, "L"), (1, "R")):
        wr = b.wrist(side)
        v2 = variant(m, "V1_Cuff" + s, "Fore" + s, wr)
        m.lathe(K("metal", RUST), [(0.08, -0.04), (0.085, 0.0), (0.08, 0.04)], (wr[0], wr[1] + 0.05, wr[2]), node=v2, segs=14)
    v = variant(m, "V2_Armour", "Spine", (0.0, 1.3, 0.0))
    for k in range(3):
        scrap_plate(m, K("metal", SCRAP), (-0.12 + k * 0.12, 1.3, 0.34), (0.11, 0.2, 0.03), v, tilt=-10)
    v = variant(m, "V3_Horns", "Head", (0.0, y, f))
    for side in (-1, 1):
        m.loft(horn, [(side * 0.11, y + 0.2, f, 0.04, 0.04), (side * 0.2, y + 0.25, f + 0.06, 0.03, 0.03), (side * 0.22, y + 0.35, f + 0.16, 0.015, 0.015), (side * 0.18, y + 0.42, f + 0.2, 0.003, 0.003)], node=v, segs=8)


def power_armour(m, b, metal, trim):
    """Scrap power armour over a big body: chest, back plate, shoulder pauldrons, thigh and shin plates."""
    m.loft(metal, [(0.0, 1.02, 0.0, 0.17 * b.g, 0.14 * b.g), (0.0, 1.2, b.hunch * 0.4, 0.2 * b.g, 0.17 * b.g), (0.0, 1.4, b.hunch * 0.8, 0.21 * b.g * b.sh, 0.15 * b.g), (0.0, 1.5, b.hunch, 0.14 * b.g, 0.1 * b.g)], node="Spine", segs=16)
    m.loft(trim, [(0.0, 1.27, b.hunch * 0.6, 0.205 * b.g * b.sh, 0.17 * b.g), (0.0, 1.31, b.hunch * 0.65, 0.207 * b.g * b.sh, 0.172 * b.g)], node="Spine", segs=16, steps=1, flat=True)
    for side, s in ((-1, "L"), (1, "R")):
        sh = b.shoulder(side)
        m.lathe(metal, [(0.0, 0.1), (0.12, 0.08), (0.17, 0.0), (0.17, -0.06), (0.0, -0.06)], (sh[0] + side * 0.03, sh[1] + 0.04, sh[2]), node="Arm" + s, segs=16, squash=0.9)
        hp, kn = b.hip(side), b.knee(side)
        m.loft(metal, [(hp[0], hp[1] - 0.02, 0.0, 0.1 * b.leg_r, 0.105 * b.leg_r), (kn[0], kn[1] + 0.06, kn[2], 0.08 * b.leg_r, 0.085 * b.leg_r)], node="Leg" + s, segs=12, flat=True)
        m.loft(metal, [(kn[0], kn[1] - 0.02, kn[2], 0.075 * b.leg_r, 0.08 * b.leg_r), (kn[0], 0.13, 0.0, 0.07 * b.leg_r, 0.075 * b.leg_r)], node="Shin" + s, segs=12, flat=True)
        m.ball(trim, 0.06 * b.leg_r, (kn[0], kn[1], kn[2] + 0.05), node="Shin" + s, u=10, v=7)
        m.loft(metal, [(kn[0], 0.09, -0.07, 0.07, 0.06), (kn[0], 0.06, 0.08, 0.075, 0.05), (kn[0], 0.05, 0.19, 0.06, 0.03)], node="Shin" + s, segs=12)


def tyrant(m):
    rnd = random.Random(231)
    b = Body(girth=1.55, shoulders=1.55, hips=1.25, belly=0.05, hunch=0.06, arm=1.05, arm_r=1.45, leg_r=1.35, head=0.95, neck=0.6)
    b.nodes(m)
    metal, trim = K("metal", (0.38, 0.4, 0.42)), K("metal", (0.6, 0.45, 0.2))
    skin = K("leather", (0.45, 0.33, 0.27))
    flesh(m, b, skin, eyes_glow=False, brow=1.5)
    power_armour(m, b, metal, trim)
    y, f = b.head_y, b.head_f
    m.loft(metal, [(0.0, y - 0.0, f - 0.02, 0.11, 0.12), (0.0, y + 0.14, f, 0.115, 0.125), (0.0, y + 0.25, f - 0.02, 0.08, 0.09), (0.0, y + 0.29, f - 0.03, 0.02, 0.02)], node="Head", segs=14)  # the helmet
    m.box(K("leather", (0.05, 0.05, 0.06)), (0.15, 0.03, 0.03), (0.0, y + 0.14, f + 0.12), node="Head")  # visor slit
    m.box((fk.GLOW, (1.0, 0.3, 0.15)), (0.13, 0.012, 0.01), (0.0, y + 0.14, f + 0.135), node="Head")
    # the gatling arm (right): a drum of six barrels on node "Barrels" that spins, a feed belt to the back drum
    g = grip_at(b, 1)
    m.lathe(metal, [(0.0, 0.0), (0.09, 0.0), (0.1, 0.25), (0.0, 0.26)], (g[0], g[1] - 0.12, g[2]), node="ForeR", segs=14)
    m.node("Barrels", (g[0], g[1] - 0.3, g[2]), parent="ForeR")
    for k in range(6):
        a = k * math.tau / 6
        m.rod(K("metal", (0.2, 0.2, 0.22)), 0.018, (g[0] + math.cos(a) * 0.05, g[1] - 0.2, g[2] + math.sin(a) * 0.05), (g[0] + math.cos(a) * 0.05, g[1] - 0.75, g[2] + math.sin(a) * 0.05), node="Barrels", segs=8)
    for yy in (g[1] - 0.35, g[1] - 0.7):
        m.lathe(trim, [(0.07, -0.015), (0.08, 0.0), (0.07, 0.015)], (g[0], yy, g[2]), node="Barrels", segs=14)
    m.lathe(metal, [(0.0, 0.0), (0.16, 0.0), (0.16, 0.36), (0.0, 0.36)], (0.0, 1.18, -0.28), node="Spine", segs=16, axis="x")  # ammo drum on the back
    m.loft(trim, [(0.18, 1.3, -0.22, 0.03, 0.01), (0.3, 1.3, 0.0, 0.03, 0.01), (0.33, 1.18, 0.12, 0.03, 0.01)], node="Spine", segs=6)
    gl = b.elbow(-1)  # a riot shield on the left forearm
    m.box(metal, (0.04, 0.6, 0.36), (gl[0] - 0.08, gl[1] - 0.2, gl[2] + 0.02), node="ForeL", bevel=0.02)
    m.box(K("ice", (0.3, 0.4, 0.45)), (0.045, 0.06, 0.2), (gl[0] - 0.08, gl[1] - 0.02, gl[2] + 0.02), node="ForeL")
    v = variant(m, "V1_Stacks", "Spine", (0.0, 1.4, -0.2))
    for side in (-1, 1):
        m.lathe(K("metal", RUST), [(0.0, 0.0), (0.045, 0.0), (0.045, 0.4), (0.055, 0.42), (0.055, 0.47), (0.0, 0.47)], (side * 0.12, 1.35, -0.3), node=v, segs=12)
    v = variant(m, "V2_Skulls", "Spine", (0.0, 1.3, 0.0))
    for k in range(4):
        p = (-0.18 + k * 0.12, 0.98, 0.2)
        m.ball(K("bone", BONE), (0.04, 0.045, 0.045), p, node=v, u=10, v=8)
    v = variant(m, "V3_Banner", "Spine", (0.0, 1.4, -0.3))
    m.rod(K("wood", WOOD), 0.02, (0.15, 1.2, -0.32), (0.15, 2.3, -0.32), node=v, segs=8)
    m.prof(K("cloth", (0.55, 0.1, 0.1)), 0.008, [(-0.33, 2.28), (-0.33, 1.8), (-0.75, 1.92), (-0.62, 2.1), (-0.75, 2.28)], x=0.15, node=v)


def warlord(m):
    rnd = random.Random(241)
    b = Body(girth=1.35, shoulders=1.45, hips=1.15, belly=0.03, hunch=0.03, arm=1.05, arm_r=1.25, leg_r=1.2, head=1.0, neck=0.8)
    b.nodes(m)
    skin = K("leather", (0.45, 0.32, 0.25))
    flesh(m, b, skin, eyes_glow=False, brow=1.4)
    coat = K("leather", (0.32, 0.22, 0.15))
    shirt(m, b, coat, sleeves=0.95, seed=31)
    m.loft(coat, [(0.0, 1.0, 0.0, 0.2, 0.16), (0.0, 0.7, 0.0, 0.25, 0.2), (0.0, 0.45, -0.02, 0.27, 0.22)], node="Hips", segs=16, flat=True)  # long coat skirt
    trousers(m, b, K("cloth", (0.2, 0.2, 0.22)), seed=32)
    boots(m, b, K("leather", (0.1, 0.08, 0.06)))
    for k in range(10):  # the fur mantle
        a = -1.6 + k * 0.36
        m.ball(K("fur", (0.35, 0.3, 0.25)), (0.09, 0.07, 0.08), (math.sin(a) * 0.24, 1.47, b.hunch + math.cos(a) * 0.12 - 0.02), node="Spine", u=8, v=6)
    m.box(K("metal", (0.7, 0.55, 0.25)), (0.06, 0.06, 0.02), (0.0, 1.0, 0.18), node="Hips")
    gun(m, b, "ForeR", 1, 0.85, scope=True)
    m.lathe(K("metal", (0.7, 0.55, 0.25)), [(0.025, -0.02), (0.028, 0.0), (0.025, 0.02)], (b.wrist(1)[0], b.wrist(1)[1] - 0.25, b.wrist(1)[2] + 0.07), node="ForeR", segs=10)  # gilded bands
    y, f = b.head_y, b.head_f
    m.lathe(K("metal", (0.45, 0.42, 0.4)), [(0.0, 0.11), (0.07, 0.1), (0.11, 0.04), (0.115, -0.02), (0.0, -0.02)], (0.0, y + 0.16, f - 0.01), node="Head", segs=16)  # helmet
    m.box(K("metal", (0.45, 0.42, 0.4)), (0.02, 0.1, 0.02), (0.0, y + 0.1, f + 0.115), node="Head")  # nose guard
    for side in (-1, 1):  # the horns
        m.loft(K("bone", (0.85, 0.8, 0.66)), [(side * 0.1, y + 0.2, f, 0.03, 0.03), (side * 0.2, y + 0.24, f + 0.02, 0.025, 0.025), (side * 0.25, y + 0.34, f + 0.04, 0.012, 0.012), (side * 0.24, y + 0.4, f + 0.02, 0.003, 0.003)], node="Head", segs=8)
    v = variant(m, "V1_Flag", "Spine", (0.0, 1.4, -0.2))
    m.rod(K("wood", WOOD), 0.018, (0.0, 1.1, -0.2), (0.0, 2.4, -0.22), node=v, segs=8)
    m.prof(K("cloth", (0.15, 0.15, 0.17)), 0.008, [(-0.22, 2.38), (-0.22, 1.9), (-0.7, 2.0), (-0.56, 2.18), (-0.7, 2.38)], x=0.0, node=v)
    m.ball(K("bone", BONE), (0.07, 0.08, 0.07), (0.0, 2.17, -0.45), node=v, u=10, v=8)
    v = variant(m, "V2_Skulls", "Spine", (0.0, 1.45, 0.0))
    for side in (-1, 1):
        m.ball(K("bone", BONE), (0.07, 0.08, 0.075), (side * (b.sx + 0.06), b.shoulder_y + 0.08, b.hunch), node=v, u=10, v=8)
    v = variant(m, "V3_Spears", "Spine", (0.0, 1.3, -0.2))
    for k in range(3):
        m.rod(K("wood", WOOD), 0.012, (-0.1 + k * 0.1, 0.9, -0.2), (-0.25 + k * 0.15, 2.2, -0.35), node=v, segs=6)
        m.rod(K("metal", RUST), 0.02, (-0.25 + k * 0.15, 2.2, -0.35), (-0.27 + k * 0.155, 2.38, -0.37), r2=0.002, node=v, segs=6)


def overseer(m):
    rnd = random.Random(251)
    b = Body(girth=1.15, shoulders=1.25, hips=1.05, hunch=0.12, arm=1.25, arm_r=1.1, leg_r=1.1, head=1.0, neck=1.3)
    b.nodes(m)
    coat, brass, steel = K("cloth", (0.2, 0.18, 0.22)), K("metal", (0.66, 0.5, 0.25)), K("metal", (0.4, 0.4, 0.42))
    skin = K("leather", (0.4, 0.38, 0.4))
    flesh(m, b, skin, eyes_glow=False)
    shirt(m, b, coat, sleeves=1.0, seed=41)
    m.loft(coat, [(0.0, 1.0, 0.0, 0.18, 0.15), (0.0, 0.6, -0.02, 0.24, 0.19), (0.0, 0.2, -0.05, 0.28, 0.22)], node="Hips", segs=16, flat=True)  # a long coat to the shins
    boots(m, b, K("leather", (0.1, 0.08, 0.07)))
    y, f = b.head_y, b.head_f
    m.ball(brass, (0.16, 0.17, 0.16), (0.0, y + 0.15, f), node="Head", u=16, v=12)  # the brass helm
    m.lathe(steel, [(0.16, -0.02), (0.18, 0.0), (0.16, 0.02)], (0.0, y + 0.02, f), node="Head", segs=18)  # collar ring
    m.lathe(steel, [(0.07, -0.01), (0.085, 0.0), (0.085, 0.03), (0.07, 0.035)], (0.0, y + 0.16, f + 0.15), node="Head", segs=16, axis="f")
    m.ball((fk.GLOW, (0.95, 0.3, 0.95)), (0.06, 0.06, 0.02), (0.0, y + 0.16, f + 0.175), node="Head", u=12, v=8)  # the single lamp eye
    for side in (-1, 1):
        m.lathe(steel, [(0.04, -0.01), (0.045, 0.0), (0.045, 0.02), (0.04, 0.025)], (side * 0.13, y + 0.16, f + 0.06), node="Head", segs=10, axis="x")
    # a harness on the back with two arms of cable and a lamp mast
    m.box(steel, (0.3, 0.42, 0.16), (0.0, 1.25, -0.2), node="Spine", bevel=0.03)
    for k in range(3):
        m.lathe(brass, [(0.0, 0.0), (0.035, 0.0), (0.035, 0.08), (0.0, 0.08)], (-0.1 + k * 0.1, 1.45, -0.2), node="Spine", segs=10)
    m.loft(K("leather", (0.08, 0.08, 0.08)), [(0.12, 1.4, -0.22, 0.02, 0.02), (0.2, 1.55, -0.1, 0.02, 0.02), (0.12, b.head_y + 0.05, b.head_f - 0.12, 0.02, 0.02)], node="Spine", segs=6)
    # the arm cannon (left forearm) and a long scatter gun (right)
    gl = b.elbow(-1)
    m.lathe(steel, [(0.0, 0.0), (0.08, 0.0), (0.09, 0.3), (0.06, 0.32), (0.06, 0.45), (0.0, 0.46)], (gl[0], gl[1] - 0.48, gl[2]), node="ForeL", segs=14)
    gun(m, b, "ForeR", 1, 0.7, drum=True)
    v = variant(m, "V1_Antenna", "Head", (0.0, y, f))
    m.rod(steel, 0.008, (0.08, y + 0.26, f - 0.05), (0.12, y + 0.6, f - 0.12), node=v, segs=6)
    m.ball((fk.GLOW, (1.0, 0.2, 0.2)), 0.02, (0.12, y + 0.61, f - 0.12), node=v, u=8, v=6)
    v = variant(m, "V2_Drone", "Spine", (0.0, 1.9, -0.1))
    m.node("Drone", (0.25, 2.0, -0.1), parent=v)
    m.ball(steel, (0.09, 0.05, 0.09), (0.25, 2.0, -0.1), node="Drone", u=10, v=7)
    m.ball((fk.GLOW, (0.95, 0.3, 0.95)), 0.025, (0.25, 1.99, -0.02), node="Drone", u=8, v=6)
    for side in (-1, 1):
        m.lathe(steel, [(0.0, 0.0), (0.06, 0.0), (0.06, 0.008), (0.0, 0.01)], (0.25 + side * 0.12, 2.04, -0.1), node="Drone", segs=12)
    v = variant(m, "V3_Lamps", "Spine", (0.0, 1.45, 0.0))
    for side in (-1, 1):
        sh = b.shoulder(side)
        m.lathe(brass, [(0.0, 0.0), (0.05, 0.0), (0.06, 0.08), (0.0, 0.085)], (sh[0], sh[1] + 0.08, sh[2] + 0.04), node=v, segs=12, axis="f")
        m.ball((fk.GLOW, (1.0, 0.9, 0.6)), (0.045, 0.045, 0.015), (sh[0], sh[1] + 0.08, sh[2] + 0.125), node=v, u=10, v=6)


MODELS = (("en_drowned", drowned), ("en_drowned_runner", drowned_runner), ("en_swimmer", swimmer), ("en_reef_crab", reef_crab), ("en_tide_brute", tide_brute),
          ("en_skeleton_sword", skeleton_sword), ("en_skeleton_archer", skeleton_archer), ("en_raider", raider), ("en_feral", feral),
          ("en_scav_gunner", scav_gunner), ("en_marksman", marksman), ("en_brute", brute),
          ("en_clockwork_bear", clockwork_bear), ("en_boss_butcher", butcher), ("en_boss_dome_beast", dome_beast), ("en_boss_tyrant", tyrant),
          ("en_boss_warlord", warlord), ("en_boss_overseer", overseer))


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
