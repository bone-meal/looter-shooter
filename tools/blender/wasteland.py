# Purpose: developer-time script. Models the original wasteland enemies (the later arena waves) with tools/blender/kit.py into
# assets/models/creatures/<enemy model id>.gltf: five regular types (raider, feral, scav_gunner, marksman, brute) and
# five bosses (boss_butcher, boss_tyrant, boss_dome_beast, boss_warlord, boss_overseer). All come from one jointed
# humanoid builder (smooth lofted trunk, limbs and head) driven by the SPEC table below (build, head, gear, weapon),
# 1.8 m tall at scale 1, with the LegL / LegR / ArmL / ArmR joints game/enemy.gd swings. Gun carriers hold the gun
# in a fixed two-handed pose. Material names matter (game/character_models.gd): the game puts the enemy's own tintable
# material on "body" (clothes) or "hide" (bare creatures), glows "eye" in the accent colour and tints "cloth";
# "gear" and "metal" carry every other part, coloured per part (kit.Model colored=True), to keep draw calls low.
# Run: python3 tools/blender/wasteland.py   (from the project folder; needs pip packages bpy, numpy, pillow)
import math
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
import kit
from mathutils import Vector

OUT = os.path.join(os.path.dirname(__file__), "..", "..", "assets", "models", "creatures")
TEXTURES = {  # material: (texture kind, colour, seed)
    "body": ("fabric", (0.9, 0.89, 0.86), 31), "hide": ("hide", (0.92, 0.9, 0.86), 32), "gear": ("hide", (0.95, 0.95, 0.95), 33),
    "metal": ("scrap", (0.92, 0.92, 0.92), 34), "cloth": ("fabric", (0.85, 0.85, 0.85), 35),
}
PAINTS = {  # part colour name: (material, colour)
    "leather": ("gear", (0.3, 0.2, 0.13)), "strap": ("gear", (0.17, 0.13, 0.1)), "dark": ("gear", (0.06, 0.06, 0.065)), "wood": ("gear", (0.36, 0.24, 0.13)),
    "bone": ("gear", (0.86, 0.8, 0.66)), "flesh": ("gear", (0.74, 0.56, 0.46)), "bandage": ("gear", (0.74, 0.7, 0.6)), "gum": ("gear", (0.3, 0.1, 0.1)),
    "rust": ("metal", (0.5, 0.35, 0.27)), "iron": ("metal", (0.56, 0.56, 0.6)), "steel": ("metal", (0.82, 0.84, 0.87)),
    "sign": ("metal", (0.75, 0.16, 0.12)), "hazard": ("metal", (0.88, 0.66, 0.12)), "brass": ("metal", (0.85, 0.65, 0.3)),
}
SPEC = {
    "raider": {"head": "gasmask", "mohawk": True, "gloves": True, "pads": 1, "spikes": True, "knee_pads": True, "weapon": "machete", "sign": True, "wraps": True, "pouches": 2},
    "feral": {"bare": True, "head": "ghoul", "lean": 0.2, "thick": 0.78, "girth": 0.8, "arm_len": 1.2, "weapon": "claws", "ribs": True, "rags": True},
    "scav_gunner": {"head": "helmet", "gloves": True, "pads": 2, "weapon": "rifle", "pack": True, "knee_pads": True, "bandolier": True, "pouches": 4},
    "marksman": {"head": "hood", "gloves": True, "thick": 0.92, "weapon": "long_rifle", "cape": True, "coat": True, "pouches": 1},
    "brute": {"bare": True, "head": "ogre", "head_size": 0.8, "shoulders": 0.36, "thick": 1.55, "lean": 0.12, "arm_len": 1.15, "weapon": "club", "pads": 1, "rags": True, "chains": True, "scars": True},
    "boss_butcher": {"head": "welder", "shoulders": 0.32, "thick": 1.4, "gut": 1.45, "weapon": "cleaver", "apron": True, "pads": 1, "hooks": True, "gloves": True},
    "boss_tyrant": {"head": "helmet", "shoulders": 0.33, "thick": 1.4, "weapon": "minigun", "pads": 2, "spikes": True, "tank": True, "knee_pads": True, "plated": True, "gloves": True},
    "boss_dome_beast": {"bare": True, "head": "beast", "head_size": 1.25, "shoulders": 0.38, "thick": 1.6, "lean": 0.3, "arm_len": 1.38, "weapon": "claws", "back_spikes": True, "ribs": True, "rags": True, "scars": True},
    "boss_warlord": {"head": "horned", "shoulders": 0.3, "thick": 1.25, "arm_len": 1.15, "weapon": "rifle", "pads": 2, "spikes": True, "banner": True, "cape": True, "sign": True, "trophies": True, "gloves": True, "knee_pads": True},
    "boss_overseer": {"head": "sensor", "shoulders": 0.3, "thick": 1.2, "arm_len": 1.15, "weapon": "long_rifle", "plated": True, "tank": True, "antenna": True, "pads": 2, "gloves": True, "knee_pads": True, "coat": True},
}
TORSO = [(0.86, 0.1, 0.085, 0.0), (0.94, 0.165, 0.11, 0.0), (1.02, 0.172, 0.115, 0.0), (1.12, 0.15, 0.1, 0.005), (1.24, 0.172, 0.115, 0.012),
    (1.36, 0.2, 0.128, 0.018), (1.44, 0.195, 0.11, 0.008), (1.5, 0.12, 0.08, 0.0)]  # (height, half-width, half-depth, forward)
LEG = [(0.97, 0.082, 0.09, 0.0), (0.86, 0.092, 0.1, 0.005), (0.7, 0.08, 0.09, 0.012), (0.57, 0.064, 0.07, 0.016), (0.5, 0.06, 0.064, 0.022),
    (0.43, 0.056, 0.06, 0.012), (0.33, 0.058, 0.068, -0.01), (0.2, 0.046, 0.052, -0.004), (0.1, 0.04, 0.046, 0.0)]
SKULL = [(0.0, 0.03, 0.035, 0.035), (0.03, 0.055, 0.068, 0.02), (0.08, 0.07, 0.085, 0.012), (0.13, 0.076, 0.094, 0.008), (0.17, 0.078, 0.098, 0.004),
    (0.215, 0.07, 0.092, -0.002), (0.24, 0.045, 0.062, -0.006)]


class Build:
    """The measurements of one enemy, worked out from its SPEC entry."""

    def __init__(self, s):
        self.s = s
        self.W = s.get("shoulders", 0.21)  # half shoulder width
        self.ws = self.W / 0.21
        self.T = s.get("thick", 1.0)  # limb thickness
        self.D = s.get("girth", (self.ws + self.T) / 2.0)  # trunk depth
        self.reach = s.get("arm_len", 1.0)

    def lean(self, y):  # how far the spine has curved forward at height y
        return self.s.get("lean", 0.0) * max(0.0, (y - 0.9) / 0.75) ** 1.3

    def trunk(self, y, grow=0.0):  # (half-width, half-depth, forward centre) of the trunk at height y
        rows = list(zip(TORSO, TORSO[1:]))
        for (y0, w0, d0, f0), (y1, w1, d1, f1) in rows:
            if y <= y1 or (y1, w1, d1, f1) == TORSO[-1]:
                t = min(max((y - y0) / (y1 - y0), 0.0), 1.0)
                gut = 1.0 + (self.s.get("gut", 1.0) - 1.0) * max(0.0, 1.0 - abs(y - 1.12) / 0.3)
                return ((w0 + (w1 - w0) * t) * self.ws * gut + grow, (d0 + (d1 - d0) * t) * self.D * gut * (1.0 + 0.25 * (gut - 1.0)) + grow,
                    self.lean(y) + f0 + (f1 - f0) * t + 0.12 * (gut - 1.0))

    def around(self, y, angle, grow=0.0):  # a point on the trunk surface; angle 0 = front, 90 = the right side
        w, d, f = self.trunk(y, grow)
        return (w * math.sin(math.radians(angle)), y, f + d * math.cos(math.radians(angle)))

    def shell(self, m, mat, y0, y1, grow, segs=16):  # a layer worn over the trunk between two heights
        steps = max(2, int(abs(y1 - y0) / 0.07))
        m.loft(mat, [(0, y, self.trunk(y, grow)[2], self.trunk(y, grow)[0], self.trunk(y, grow)[1]) for y in (y0 + (y1 - y0) * k / steps for k in range(steps + 1))], segs=segs, steps=2, flat=True)


def head(m, M, b, skin, at):
    s, kind, k = b.s, b.s.get("head", "ghoul"), b.s.get("head_size", 1.0) * 1.08
    x, y, f = at

    def p(dx, dy, df):
        return (x + dx * k, y + dy * k, f + df * k)

    def eyes(dy, df, gap=0.034, size=0.012, rim=None):
        for side in (-1, 1):
            if rim:
                m.lathe(rim, [(size * 1.9 * k, 0.0), (size * 2.1 * k, 0.03 * k)], p(side * gap, dy, df - 0.03), segs=12, axis="f")
            m.ball(M["dark"], (size * 1.7 * k, size * 1.5 * k, 0.012 * k), p(side * gap, dy, df - 0.006), u=8, v=6)
            m.ball(M["eye"], (size * k, size * k, 0.008 * k), p(side * gap, dy, df + 0.004), u=8, v=5)

    if kind == "sensor":  # a machine head: armoured ball with one big lens and side vents
        m.ball(M["iron"], 0.125 * k, p(0, 0.12, 0), u=18, v=12)
        m.lathe(M["rust"], [(0.07 * k, 0.09 * k), (0.08 * k, 0.14 * k)], p(0, 0.12, 0), segs=18, axis="f")
        m.ball(M["eye"], (0.062 * k, 0.062 * k, 0.03 * k), p(0, 0.12, 0.125), u=14, v=8)
        for side in (-1, 1):
            m.cylx(M["steel"], 0.04 * k, x + side * 0.11 * k, x + side * 0.15 * k, f, y + 0.12 * k, segs=12)
        m.loft(M["dark"], [(x, y - 0.06, f, 0.05, 0.05), (x, y + 0.03, f, 0.06, 0.06)], segs=10, steps=1, flat=True)
        return
    m.loft(skin, [(x, y + dy * k, f + df * k, w * k, d * k) for dy, w, d, df in SKULL], segs=14)
    if kind in ("ghoul", "ogre", "beast"):  # bare monster faces
        jaw = {"ghoul": 0.0, "ogre": 0.03, "beast": 0.07}[kind]
        if jaw > 0.0:  # heavy lower jaw or snout
            m.loft(skin, [p(0, 0.02, 0.02) + (0.06 * k, 0.045 * k), p(0, 0.035, 0.07 + jaw) + (0.058 * k, 0.04 * k), p(0, 0.05, 0.1 + jaw * 1.6) + (0.04 * k, 0.03 * k)], segs=10, steps=2)
        if kind == "beast":
            m.loft(skin, [p(0, 0.1, 0.05) + (0.055 * k, 0.045 * k), p(0, 0.095, 0.14) + (0.045 * k, 0.038 * k), p(0, 0.085, 0.215) + (0.03 * k, 0.026 * k)], segs=10, steps=2)
        front = 0.092 + jaw * 1.5
        eyes(0.15, 0.082, gap=0.036, size=0.011 if kind != "beast" else 0.014)
        m.loft(skin, [p(-0.07, 0.172, 0.07) + (0.02 * k, 0.014 * k), p(0, 0.176, 0.098) + (0.02 * k, 0.016 * k), p(0.07, 0.172, 0.07) + (0.02 * k, 0.014 * k)], segs=8, steps=2)  # brow
        m.box(M["gum"], (0.07 * k, 0.022 * k, 0.02 * k), p(0, 0.062, front - 0.012), bevel=0.003)
        teeth = 7 if kind != "ogre" else 5
        for i in range(teeth):
            tx = (i - (teeth - 1) / 2) * 0.011 * (7 / teeth)
            long = kind != "ghoul" and i in (0, teeth - 1)
            m.rod(M["bone"], 0.005 * k, p(tx, 0.052, front - 0.004), p(tx, 0.052 + (0.05 if long else 0.02), front), r2=0.002 * k, segs=5)
            if kind != "ogre":
                m.rod(M["bone"], 0.0045 * k, p(tx, 0.075, front - 0.006), p(tx, 0.058, front - 0.002), r2=0.002 * k, segs=5)
        if kind == "ghoul":
            for side in (-1, 1):
                m.ball(M["dark"], (0.006 * k, 0.012 * k, 0.006 * k), p(side * 0.01, 0.112, 0.1), u=6, v=4)  # nose slits
                m.ball(skin, (0.012 * k, 0.03 * k, 0.022 * k), p(side * 0.08, 0.14, 0.0), u=8, v=6)  # ears
        if kind == "beast":
            for side in (-1, 1):
                m.loft(M["bone"], [p(side * 0.07, 0.2, -0.01) + (0.03 * k, 0.03 * k), p(side * 0.16, 0.25, 0.0) + (0.024 * k, 0.024 * k), p(side * 0.2, 0.34, 0.05) + (0.014 * k, 0.014 * k), p(side * 0.18, 0.42, 0.11) + (0.004 * k, 0.004 * k)], segs=8, steps=3)
        return
    if kind == "gasmask":  # leather cowl, round goggles, filter can
        m.loft(M["leather"], [(x, y + dy, f + df, w + 0.006, d + 0.006) for dy, w, d, df in SKULL[1:]], segs=14)
        eyes(0.15, 0.1, gap=0.036, size=0.014, rim=M["rust"])
        m.loft(M["dark"], [p(0, 0.075, 0.07) + (0.045, 0.04), p(0, 0.065, 0.12) + (0.036, 0.034)], segs=10, steps=1, flat=True)
        m.cyl(M["rust"], 0.034, f + 0.11, f + 0.17, y=y + 0.06, x=x, segs=12)
        m.cyl(M["iron"], 0.03, f + 0.17, f + 0.185, y=y + 0.06, x=x, segs=12)
        m.strip(M["strap"], 0.02, 0.006, [(f + 0.09, y + 0.15), (f + 0.02, y + 0.252), (f - 0.07, y + 0.2), (f - 0.1, y + 0.12)], x=x)
    if kind == "welder":  # the butcher: a flat iron face plate with eye slits over a leather hood
        m.loft(M["leather"], [(x, y + dy, f + df, w + 0.008, d + 0.008) for dy, w, d, df in SKULL[1:]], segs=14)
        m.prof(M["iron"], 0.02, [(x - 0.07, y + 0.21), (x + 0.07, y + 0.21), (x + 0.085, y + 0.1), (x + 0.05, y - 0.01), (x - 0.05, y - 0.01), (x - 0.085, y + 0.1)], x=f + 0.1, bevel=0.005, across="f")
        for side in (-1, 1):
            m.box(M["eye"], (0.04, 0.012, 0.006), (x + side * 0.036, y + 0.15, f + 0.111), bevel=0)
            for dy in (0.04, 0.065, 0.09):
                m.cyl(M["dark"], 0.006, f + 0.108, f + 0.112, y=y + dy, x=x + side * 0.03, segs=6, bevel=0)
        for bx, by in ((-0.06, 0.19), (0.06, 0.19), (-0.045, 0.01), (0.045, 0.01)):
            m.ball(M["steel"], 0.008, (x + bx, y + by, f + 0.111), u=6, v=4)
    if kind in ("helmet", "horned"):
        m.loft(M["rust" if kind == "helmet" else "iron"], [(x, y + 0.14, f - 0.002, 0.094, 0.112), (x, y + 0.2, f - 0.004, 0.088, 0.106), (x, y + 0.25, f - 0.006, 0.06, 0.075)], segs=14, steps=3)
        m.loft(M["iron"], [(x, y + 0.135, f - 0.002, 0.1, 0.12), (x, y + 0.15, f - 0.002, 0.1, 0.12)], segs=14, steps=1, flat=True)  # rim
    if kind == "helmet":  # goggles and a scarf over the face
        eyes(0.15, 0.1, gap=0.036, size=0.014, rim=M["dark"])
        m.loft(M["cloth"], [p(0, 0.0, 0.02) + (0.062, 0.07), p(0, 0.06, 0.014) + (0.08, 0.094), p(0, 0.11, 0.01) + (0.08, 0.1)], segs=12, steps=2)
        m.strip(M["strap"], 0.018, 0.006, [(f + 0.1, y + 0.15), (f + 0.11, y + 0.19)], x=x)
    if kind == "horned":  # the warlord: full face plate with a glowing slit and bull horns
        m.prof(M["iron"], 0.022, [(x - 0.075, y + 0.15), (x + 0.075, y + 0.15), (x + 0.07, y + 0.05), (x + 0.03, y - 0.02), (x - 0.03, y - 0.02), (x - 0.07, y + 0.05)], x=f + 0.092, bevel=0.006, across="f")
        m.box(M["eye"], (0.1, 0.014, 0.006), (x, y + 0.13, f + 0.104), bevel=0)
        m.box(M["steel"], (0.016, 0.16, 0.012), (x, y + 0.08, f + 0.106), bevel=0.003)
        for side in (-1, 1):
            m.loft(M["bone"], [(x + side * 0.085, y + 0.2, f, 0.028, 0.028), (x + side * 0.17, y + 0.22, f + 0.01, 0.024, 0.024), (x + side * 0.23, y + 0.3, f + 0.04, 0.015, 0.015), (x + side * 0.22, y + 0.39, f + 0.08, 0.004, 0.004)], segs=8, steps=3)
    if kind == "hood":  # deep hood, dark inside, one scope eye
        m.loft(M["cloth"], [(x, y - 0.03, f - 0.02, 0.1, 0.1), (x, y + 0.08, f - 0.015, 0.106, 0.118), (x, y + 0.18, f - 0.012, 0.104, 0.122), (x, y + 0.26, f - 0.03, 0.06, 0.08)], segs=14, steps=3)
        m.ball(M["dark"], (0.072, 0.085, 0.03), (x, y + 0.12, f + 0.086), u=12, v=8)
        m.cyl(M["iron"], 0.022, f + 0.09, f + 0.135, y=y + 0.14, x=x + 0.03, segs=10)
        m.ball(M["eye"], (0.017, 0.017, 0.006), (x + 0.03, y + 0.14, f + 0.136), u=8, v=5)
        m.ball(M["eye"], (0.006, 0.006, 0.004), (x - 0.034, y + 0.14, f + 0.11), u=6, v=4)
    if s.get("mohawk"):
        for i in range(7):
            a = math.radians(-25 + i * 24)
            m.rod(M["cloth"], 0.014, (x, y + 0.13 + 0.105 * math.cos(a), f + 0.1 * math.sin(a)), (x, y + 0.13 + 0.19 * math.cos(a), f + 0.18 * math.sin(a)), r2=0.003, segs=6)


def melee_weapon(m, M, s, x, y, f):
    """Held in the right hand at (x, y, f), built along the hanging arm so it points forward when game/enemy.gd raises ArmR."""
    kind, A = s.get("weapon", ""), "ArmR"
    if kind == "machete":
        m.rod(M["strap"], 0.018, (x, y + 0.06, f), (x, y - 0.07, f), node=A)
        m.box(M["iron"], (0.02, 0.016, 0.075), (x, y - 0.075, f), bevel=0.004, node=A)
        m.prof(M["steel"], 0.009, [(f - 0.03, y - 0.08), (f + 0.03, y - 0.08), (f + 0.05, y - 0.5), (f + 0.02, y - 0.66), (f - 0.022, y - 0.56)], x=x, bevel=0.003, node=A)
        m.prof(M["rust"], 0.011, [(f - 0.031, y - 0.2), (f - 0.012, y - 0.2), (f - 0.008, y - 0.5), (f - 0.024, y - 0.5)], x=x, bevel=0.002, node=A)
    elif kind == "club":  # a lamp post stump with bolts
        m.loft(M["rust"], [(x, y + 0.1, f, 0.028, 0.028), (x, y - 0.3, f, 0.034, 0.034), (x, y - 0.55, f, 0.07, 0.07), (x, y - 0.8, f, 0.085, 0.085)], node=A, segs=10, steps=2)
        for k in range(8):
            a = k * 0.8
            m.rod(M["steel"], 0.012, (x, y - 0.52 - 0.035 * k, f), (x + 0.13 * math.cos(a), y - 0.52 - 0.035 * k, f + 0.13 * math.sin(a)), r2=0.003, node=A, segs=5)
        m.loft(M["strap"], [(x, y + 0.06, f, 0.033, 0.033), (x, y - 0.08, f, 0.035, 0.035)], node=A, segs=10, steps=1, flat=True)
    elif kind == "cleaver":
        m.rod(M["wood"], 0.024, (x, y + 0.07, f), (x, y - 0.1, f), node=A)
        m.prof(M["steel"], 0.012, [(f - 0.02, y - 0.1), (f + 0.19, y - 0.1), (f + 0.21, y - 0.54), (f - 0.02, y - 0.58)], x=x, bevel=0.004, node=A)
        m.prof(M["sign"], 0.013, [(f + 0.08, y - 0.4), (f + 0.2, y - 0.36), (f + 0.208, y - 0.535), (f + 0.02, y - 0.572)], x=x, bevel=0.002, node=A)  # stained edge
        m.cylx(M["dark"], 0.014, x - 0.008, x + 0.008, f + 0.15, y - 0.17, node=A, bevel=0)
    elif kind == "claws":
        for k in (-1, 0, 1):
            m.rod(M["bone"], 0.012, (x + k * 0.022, y - 0.02, f + 0.02), (x + k * 0.03, y - 0.22, f + 0.07), r2=0.002, node=A, segs=6)


def gun(m, M, kind, x, y, f):
    """A scrap rifle, long rifle or minigun along the forward axis; (x, y) = the bore line, f = the butt end. Returns the two grip points."""
    if kind == "minigun":
        m.box(M["iron"], (0.16, 0.18, 0.34), (x, y, f + 0.17), bevel=0.02)
        m.cyl(M["hazard"], 0.1, f + 0.02, f + 0.2, y=y, x=x - 0.14, segs=14)  # ammo drum
        m.strip(M["iron"], 0.03, 0.012, [(f + 0.04, y + 0.09), (f + 0.08, y + 0.17), (f + 0.26, y + 0.17), (f + 0.3, y + 0.09)], x=x)  # carry handle
        m.cyl(M["rust"], 0.085, f + 0.34, f + 0.5, y=y, x=x, segs=14)
        for k in range(6):
            a = k * math.pi / 3
            m.cyl(M["steel"], 0.016, f + 0.4, f + 1.1, y=y + 0.05 * math.sin(a), x=x + 0.05 * math.cos(a), segs=8, bevel=0)
        m.cyl(M["dark"], 0.075, f + 1.04, f + 1.07, y=y, x=x, segs=14)
        return (x, y + 0.17, f + 0.17), None
    long = kind == "long_rifle"
    end = f + (1.2 if long else 0.9)
    m.prof(M["wood"], 0.036, [(f, y + 0.02), (f + 0.16, y + 0.022), (f + 0.16, y - 0.035), (f, y - 0.1)], x=x, bevel=0.008)  # stock
    m.box(M["iron"], (0.046, 0.075, 0.28), (x, y - 0.005, f + 0.28), bevel=0.008)  # receiver
    m.box(M["strap"], (0.034, 0.1, 0.045), (x, y - 0.085, f + 0.2), tilt=-14, bevel=0.008)  # grip
    m.box(M["rust"], (0.03, 0.15, 0.07), (x, y - 0.11, f + 0.33), tilt=10, bevel=0.006)  # magazine
    m.cyl(M["wood"], 0.03, f + 0.4, f + 0.66, y=y, x=x, segs=10)  # fore-end
    m.cyl(M["steel"], 0.013, f + 0.4, end, y=y, x=x, segs=8, bevel=0)
    m.cyl(M["dark"], 0.021, end - 0.08, end, y=y, x=x, segs=8)
    m.cyl(M["bandage"], 0.033, f + 0.52, f + 0.58, y=y, x=x, segs=10)  # rag wrap
    if long:
        m.cyl(M["dark"], 0.024, f + 0.18, f + 0.5, y=y + 0.07, x=x, segs=10)
        m.ball(M["eye"], (0.02, 0.02, 0.006), (x, y + 0.07, f + 0.502), u=8, v=4)
        for at in (0.24, 0.42):
            m.box(M["iron"], (0.016, 0.04, 0.02), (x, y + 0.04, f + at), bevel=0.003)
    return (x, y - 0.08, f + 0.2), (x, y - 0.035, f + 0.45)


def arm(m, M, b, name, side, limb, skin, hand_at=None):
    """One arm on its joint. hand_at = where the hand should be (two-bone reach, stretched a little when too far); None = hanging."""
    s, T = b.s, b.T ** 0.85 * 1.12
    S = Vector((side * (b.W + 0.04 * b.T), 1.44, b.lean(1.44)))
    a, c = 0.3 * b.reach, 0.32 * b.reach
    E, H = S + Vector((side * 0.02, -a, 0.0)), S + Vector((side * 0.03, -a - c, 0.03))
    if hand_at is not None:
        H = Vector(hand_at)
        d = (H - S).length
        stretch = max(1.0, d / ((a + c) * 0.98))
        a, c = a * stretch, c * stretch
        along = (H - S) / d
        x = (a * a - c * c + d * d) / (2 * d)
        pole = Vector((side * 0.5, -1.0, -0.35))  # elbows point down, out and a little back
        E = S + along * x + (pole - along * pole.dot(along)).normalized() * math.sqrt(max(a * a - x * x, 0.0))
    m.node(name, tuple(S))

    def ring(p, r):
        return (p.x, p.y, p.z, r * T, r * T)

    m.loft(limb, [ring(S + Vector((0, 0.01, 0)), 0.064), ring(S.lerp(E, 0.38), 0.058), ring(S.lerp(E, 0.85), 0.047), ring(E, 0.045), ring(E.lerp(H, 0.2), 0.048),
        ring(E.lerp(H, 0.6), 0.04), ring(E.lerp(H, 0.93), 0.032)], node=name, segs=10)
    if not s.get("bare"):
        m.loft(M["leather"], [ring(E.lerp(H, 0.5), 0.047), ring(E.lerp(H, 0.86), 0.039)], node=name, segs=10, steps=1, flat=True)  # bracer
    glove = M["leather"] if s.get("gloves") else skin
    m.ball(glove, (0.036 * T, 0.05 * T, 0.045 * T), H, node=name, u=10, v=7)
    m.ball(glove, 0.018 * T, (H.x - side * 0.03 * T, H.y + 0.01, H.z + 0.02 * T), node=name, u=6, v=5)  # thumb
    if s.get("pads", 0) >= (1 if side == 1 else 2):  # 1 = right shoulder only, 2 = both
        m.ball(M["rust"], (0.1 * T, 0.06 * T, 0.105 * T), (S.x + side * 0.012, 1.495, S.z), node=name, u=12, v=7)
        m.loft(M["iron"], [(S.x + side * 0.012, 1.47, S.z, 0.104 * T, 0.109 * T), (S.x + side * 0.012, 1.482, S.z, 0.104 * T, 0.109 * T)], node=name, segs=12, steps=1, flat=True)
        if s.get("spikes"):
            for k in (-1, 0, 1):
                m.rod(M["steel"], 0.015, (S.x + side * 0.03, 1.53, S.z + k * 0.05), (S.x + side * 0.1, 1.66, S.z + k * 0.07), r2=0.002, node=name, segs=6)
    return H


def leg(m, M, b, name, side, limb):
    s, T = b.s, b.T ** 0.85 * 1.1
    x = side * (0.095 * (0.6 + 0.4 * b.ws) + 0.02 * (b.T - 1.0))
    m.node(name, (x, 0.92, 0))
    m.loft(limb, [(x, y, fo, rx * T, rf * T) for y, rx, rf, fo in LEG], node=name, segs=12)
    foot = T ** 0.7
    if s.get("bare"):
        m.loft(limb, [(x, 0.06, -0.06, 0.04 * foot, 0.05 * foot), (x, 0.06, 0.02, 0.05 * foot, 0.055 * foot), (x, 0.04, 0.12, 0.058 * foot, 0.036 * foot), (x, 0.03, 0.19, 0.045 * foot, 0.026 * foot)], node=name, segs=10, steps=2)
        for k in (-1, 0, 1):
            m.rod(M["bone"], 0.012, (x + k * 0.03 * foot, 0.03, 0.19), (x + k * 0.036 * foot, 0.012, 0.27), r2=0.002, node=name, segs=5)
    else:
        m.loft(M["leather"], [(x, 0.35, -0.008, 0.068 * T, 0.076 * T), (x, 0.3, -0.008, 0.063 * T, 0.071 * T), (x, 0.2, -0.004, 0.053 * T, 0.059 * T), (x, 0.08, 0.0, 0.05 * T, 0.056 * T)], node=name, segs=12, steps=2)
        m.loft(M["leather"], [(x, 0.07, -0.07, 0.042 * foot, 0.05 * foot), (x, 0.074, 0.0, 0.052 * foot, 0.06 * foot), (x, 0.058, 0.09, 0.056 * foot, 0.047 * foot), (x, 0.048, 0.16, 0.052 * foot, 0.038 * foot),
            (x, 0.043, 0.205, 0.036 * foot, 0.03 * foot)], node=name, segs=10, steps=2)
        m.prof(M["dark"], 0.11 * foot, [(-0.105, 0.0), (0.235, 0.0), (0.24, 0.024), (-0.11, 0.024)], x=x, bevel=0.006, node=name)
        m.loft(M["strap"], [(x, 0.3, -0.008, 0.066 * T, 0.074 * T), (x, 0.285, -0.008, 0.066 * T, 0.074 * T)], node=name, segs=12, steps=1, flat=True)
        m.ball(M["steel"], 0.012, (x + side * 0.066 * T, 0.292, 0.0), node=name, u=6, v=4)
    if s.get("knee_pads"):
        m.ball(M["rust"], (0.058 * T, 0.072 * T, 0.036 * T), (x, 0.5, 0.062 * T), node=name, u=10, v=6)
        m.loft(M["strap"], [(x, 0.46, 0.016, 0.062 * T, 0.066 * T), (x, 0.445, 0.014, 0.061 * T, 0.065 * T)], node=name, segs=12, steps=1, flat=True)
    if s.get("wraps") and side == -1:
        m.loft(M["bandage"], [(x, 0.74, 0.01, 0.088 * T, 0.097 * T), (x, 0.64, 0.014, 0.076 * T, 0.085 * T)], node=name, segs=12, steps=2)
    if s.get("pouches", 0) >= 4 and side == 1:  # thigh holster
        m.box(M["leather"], (0.05, 0.16, 0.1), (x + 0.09 * T, 0.76, 0.01), bevel=0.012, node=name)
        m.loft(M["strap"], [(x, 0.8, 0.008, 0.094 * T, 0.102 * T), (x, 0.785, 0.008, 0.093 * T, 0.101 * T)], node=name, segs=12, steps=1, flat=True)


def humanoid(m, M, s):
    b = Build(s)
    W, T = b.W, b.T
    skin = M["hide"] if s.get("bare") else M["flesh"]
    limb = M["hide"] if s.get("bare") else M["body"]
    leg(m, M, b, "LegL", -1, limb)
    leg(m, M, b, "LegR", 1, limb)
    m.loft(limb, [(0, y, b.trunk(y)[2], b.trunk(y)[0], b.trunk(y)[1]) for y, _w, _d, _f in TORSO], segs=16)
    neck = min(T, 1.5) ** 0.8
    top = 1.575 - (0.05 if s.get("head") == "ogre" else 0.0)
    m.loft(skin, [(0, 1.46, b.lean(1.46), 0.062 * neck, 0.064 * neck), (0, top - 0.03, b.lean(top), 0.052 * neck, 0.056 * neck), (0, top + 0.03, b.lean(top + 0.04), 0.05 * neck, 0.055 * neck)], segs=10, steps=2)
    head(m, M, b, skin, (0, top, b.lean(top + 0.08) + 0.012))
    # belt, buckle, pouches
    b.shell(m, M["strap"], 1.0, 1.045, 0.006)
    m.box(M["brass"], (0.05, 0.04, 0.014), b.around(1.022, 0, 0.008), bevel=0.004)
    for k in range(s.get("pouches", 0)):
        m.box(M["leather"], (0.07, 0.09, 0.07), b.around(0.99, (55, -55, 125, -125)[k], 0.03), bevel=0.014)
    if not s.get("bare"):  # jacket: collar, hem, front seam, chest pockets
        b.shell(m, M["body"], 1.0, 0.9, 0.014)
        m.loft(M["body"], [(0, 1.47, b.lean(1.47), 0.085 * neck, 0.085 * neck), (0, 1.535, b.lean(1.53) - 0.004, 0.068 * neck, 0.07 * neck)], segs=12, steps=1, flat=True)
        m.loft(M["strap"], [b.around(y, 0, 0.003) + (0.013, 0.006) for y in (1.07, 1.16, 1.26, 1.36, 1.44)], segs=6, steps=2)
        if not (s.get("sign") or s.get("plated") or s.get("apron")):
            for side in (-1, 1):
                m.box(M["body"], (0.075 * b.ws, 0.075, 0.022), b.around(1.33, side * 30, 0.006), bevel=0.008)
                m.box(M["strap"], (0.08 * b.ws, 0.02, 0.024), b.around(1.362, side * 30, 0.007), bevel=0.006)
    if s.get("bare"):
        for side in (-1, 1):  # chest muscles and collar bones
            m.ball(M["hide"], (0.095 * b.ws, 0.05, 0.035 * b.D), b.around(1.35, side * 25, -0.026), u=12, v=8)
            m.loft(M["hide"], [b.around(1.445, side * 8, -0.004) + (0.012, 0.012), b.around(1.455, side * 50, -0.004) + (0.012, 0.012)], segs=6, steps=2)
        if s.get("scars"):
            for y0, a0, y1, a1 in ((1.36, -34, 1.2, -8), (1.1, 20, 1.02, 44)):
                m.loft(M["gum"], [b.around(y0, a0, 0.001) + (0.007, 0.004), b.around((y0 + y1) / 2, (a0 + a1) / 2, 0.003) + (0.009, 0.004), b.around(y1, a1, 0.001) + (0.007, 0.004)], segs=6, steps=3)
                for k in range(4):
                    t = (k + 0.5) / 4
                    c = b.around(y0 + (y1 - y0) * t, a0 + (a1 - a0) * t, 0.006)
                    m.rod(M["steel"], 0.003, (c[0] - 0.014, c[1] - 0.012, c[2]), (c[0] + 0.014, c[1] + 0.012, c[2]), segs=4)
        if s.get("rags"):  # torn loincloth, front and back
            w, d, f = b.trunk(0.98)
            m.prof(M["cloth"], 0.012, [(-w * 0.62, 1.0), (w * 0.62, 1.0), (w * 0.4, 0.66), (0.0, 0.72), (-w * 0.5, 0.6)], x=f + d + 0.012, bevel=0.003, across="f")
            m.prof(M["cloth"], 0.012, [(-w * 0.62, 1.0), (w * 0.62, 1.0), (w * 0.5, 0.62), (-w * 0.3, 0.7)], x=f - d - 0.012, bevel=0.003, across="f")
        if s.get("ribs"):
            for k in range(4):
                y = 1.36 - k * 0.055
                for side in (-1, 1):
                    m.loft(M["hide"], [b.around(y, side * 12, 0.002) + (0.012, 0.012), b.around(y - 0.012, side * 45, 0.004) + (0.014, 0.014), b.around(y - 0.03, side * 85, 0.002) + (0.012, 0.012)], segs=6, steps=2)
            for k in range(7):  # spine knobs
                m.ball(M["hide"], (0.02, 0.022, 0.02), b.around(1.0 + k * 0.07, 180, 0.004), u=8, v=5)
    if s.get("plated"):  # scrap cuirass with a chest light
        b.shell(m, M["iron"], 1.1, 1.46, 0.016)
        m.prof(M["rust"], 0.02, [(-W * 0.62, 1.42), (W * 0.62, 1.42), (W * 0.5, 1.18), (-W * 0.5, 1.18)], x=b.around(1.3, 0, 0.022)[2], bevel=0.006, across="f")
        m.ball(M["eye"], (0.03, 0.03, 0.012), b.around(1.32, 0, 0.035), u=10, v=6)
        for bx, by in ((-0.5, 1.4), (0.5, 1.4), (-0.4, 1.2), (0.4, 1.2)):
            m.ball(M["steel"], 0.011, (W * bx, by, b.around(by, 0, 0.034)[2]), u=6, v=4)
    if s.get("sign"):  # a road sign strapped on as a chest plate
        r, c = 0.125 * b.ws, b.around(1.3, 0, 0.012)
        m.prof(M["sign"], 0.012, [(r * math.cos(math.radians(22.5 + 45 * k)), 1.3 + r * math.sin(math.radians(22.5 + 45 * k))) for k in range(8)], x=c[2] + 0.004, bevel=0.003, across="f")
        m.box(M["bandage"], (r * 1.3, 0.035, 0.004), (0, 1.3, c[2] + 0.012), bevel=0)
        for y in (1.39, 1.21):
            m.loft(M["strap"], [b.around(y, angle, 0.008) + (0.012, 0.008) for angle in range(30, 331, 30)], segs=6, steps=2)
    if s.get("bandolier"):  # shoulder to hip, with shells on the front
        pts = [b.around(1.44 - 0.42 * (k / 10.0), -62 + 124 * (k / 10.0), 0.012) for k in range(11)] + [b.around(1.02 + 0.42 * (k / 8.0), 118 + 180 * (k / 8.0), 0.012) for k in range(1, 8)]
        m.loft(M["leather"], [p + (0.02, 0.012) for p in pts], segs=6, steps=2)
        for k in range(2, 9):
            m.cyl(M["brass"], 0.009, pts[k][2] + 0.004, pts[k][2] + 0.03, y=pts[k][1], x=pts[k][0], segs=6, bevel=0)
    if s.get("apron"):  # leather vest and a stained apron over the belly
        b.shell(m, M["leather"], 1.0, 1.42, 0.012)
        w, d, f = b.trunk(1.0)
        m.prof(M["leather"], 0.016, [(-w * 0.75, 1.02), (w * 0.75, 1.02), (w * 0.66, 0.56), (-w * 0.66, 0.56)], x=f + d + 0.02, bevel=0.004, across="f")
        m.prof(M["sign"], 0.017, [(-w * 0.4, 0.9), (w * 0.3, 0.94), (w * 0.44, 0.66), (-w * 0.2, 0.6)], x=f + d + 0.021, bevel=0.002, across="f")
    if s.get("coat"):  # long coat skirt below the belt
        m.loft(M["body"], [(0, 1.04, b.trunk(1.04)[2], b.trunk(1.04, 0.012)[0], b.trunk(1.04, 0.012)[1]), (0, 0.9, 0.0, 0.176 * b.ws + 0.012, 0.118 * b.D + 0.014), (0, 0.74, 0.0, 0.19 * b.ws + 0.012, 0.135 * b.D + 0.02)], segs=16, steps=3)
    if s.get("pack"):
        w, d, f = b.trunk(1.25)
        m.box(M["leather"], (w * 1.5, 0.36, 0.16), (0, 1.25, f - d - 0.07), bevel=0.035)
        m.box(M["strap"], (w * 0.8, 0.14, 0.05), (0, 1.17, f - d - 0.16), bevel=0.016)
        m.loft(M["cloth"], [(-w * 0.8, 1.47, f - d - 0.06, 0.05, 0.05), (w * 0.8, 1.47, f - d - 0.06, 0.05, 0.05)], segs=10, steps=1)  # bedroll
        for side in (-1, 1):
            m.loft(M["strap"], [(side * w * 0.55, 1.36, f - d - 0.01, 0.018, 0.01), (side * w * 0.6, 1.475, f, 0.018, 0.01), (side * w * 0.55, 1.36, f + d * 0.93, 0.018, 0.01), (side * w * 0.6, 1.12, f + d * 0.85, 0.018, 0.01)], segs=6, steps=3)
    if s.get("tank"):
        w, d, f = b.trunk(1.25)
        for side in (-1, 1):
            m.loft(M["hazard"], [(side * 0.09 * T, 1.02, f - d - 0.075, 0.07 * T, 0.07 * T), (side * 0.09 * T, 1.46, f - d - 0.075, 0.07 * T, 0.07 * T)], segs=12, steps=1)
            m.cyl(M["steel"], 0.02, f - d - 0.085, f - d - 0.065, y=1.55, x=side * 0.09 * T, segs=8)
        m.loft(M["dark"], [(0.09 * T, 1.54, f - d - 0.07, 0.014, 0.014), (W * 0.9, 1.56, f - d * 0.3, 0.014, 0.014), (W + 0.02, 1.42, f + d * 0.6, 0.014, 0.014)], segs=6, steps=4)  # hose
    if s.get("cape"):
        w, d, f = b.trunk(1.4)
        m.prof(M["cloth"], 0.014, [(-w * 0.95, 1.47), (w * 0.95, 1.47), (w * 1.2, 0.56), (w * 0.4, 0.5), (0.0, 0.6), (-w * 0.5, 0.48), (-w * 1.2, 0.58)], x=f - d - 0.035, bevel=0.004, across="f")
    if s.get("back_spikes"):
        for k in range(6):
            y = 0.98 + k * 0.1
            p0 = b.around(y, 180, -0.02)
            m.loft(M["bone"], [p0 + (0.034, 0.034), (0, y + 0.08, p0[2] - 0.14, 0.02, 0.02), (0, y + 0.18, p0[2] - 0.24, 0.004, 0.004)], segs=7, steps=2)
    if s.get("chains"):  # a chain slung across the chest
        for k in range(13):
            m.ball(M["iron"], (0.02, 0.014, 0.012) if k % 2 else (0.012, 0.02, 0.012), b.around(1.44 - 0.4 * (k / 12.0), -70 + 140 * (k / 12.0), 0.016), u=6, v=4)
    if s.get("banner"):
        w, d, f = b.trunk(1.3)
        m.rod(M["wood"], 0.016, (0.07, 1.1, f - d - 0.05), (0.07, 2.6, f - d - 0.05), segs=7)
        m.prof(M["cloth"], 0.01, [(0.08, 2.56), (0.52, 2.5), (0.48, 2.26), (0.54, 2.0), (0.3, 2.06), (0.08, 1.98)], x=f - d - 0.05, bevel=0.002, across="f")
        m.ball(M["bone"], (0.05, 0.058, 0.055), (0.07, 2.64, f - d - 0.05), u=10, v=7)  # skull on the pole
    if s.get("trophies"):
        for angle in (-40, 40, 140):
            p = b.around(0.93, angle, 0.04)
            m.ball(M["bone"], (0.04, 0.046, 0.044), p, u=10, v=7)
            m.ball(M["dark"], (0.022, 0.012, 0.01), (p[0] * 1.08, p[1] + 0.006, p[2] + (0.03 if abs(angle) < 90 else -0.03)), u=6, v=4)
    if s.get("antenna"):
        m.rod(M["steel"], 0.008, (-W * 0.6, 1.5, b.lean(1.5) - 0.05), (-W * 0.6, 2.25, b.lean(1.5) - 0.05), segs=5)
        m.ball(M["eye"], 0.02, (-W * 0.6, 2.25, b.lean(1.5) - 0.05), u=6, v=4)
    if s.get("hooks"):
        for side in (-1, 1):
            p = b.around(1.0, side * 60, 0.02)
            m.strip(M["steel"], 0.014, 0.01, [(p[2], 0.98), (p[2] + 0.02, 0.84), (p[2] + 0.07, 0.8), (p[2] + 0.1, 0.86)], x=p[0])
    kind = s.get("weapon", "")
    if kind in ("rifle", "long_rifle"):  # held at the chest in both hands
        w, d, f = b.trunk(1.38)
        right, left = gun(m, M, kind, 0.04 * b.ws, 1.4, f + d * 0.97 - 0.01)
        arm(m, M, b, "ArmR", 1, limb, skin, right)
        arm(m, M, b, "ArmL", -1, limb, skin, left)
    elif kind == "minigun":  # carried low on the right side by its handle
        right, left = gun(m, M, kind, W + 0.05 * T + 0.07, 0.98, b.lean(1.2) - 0.12)
        arm(m, M, b, "ArmR", 1, limb, skin, right)
        arm(m, M, b, "ArmL", -1, limb, skin)
    else:
        hand = arm(m, M, b, "ArmR", 1, limb, skin)
        melee_weapon(m, M, s, hand.x, hand.y, hand.z)
        if kind == "claws":  # the other arm reaches forward, claws out
            other = arm(m, M, b, "ArmL", -1, limb, skin, (-W * 0.7, 1.2, b.lean(1.4) + 0.48 * b.reach))
            for k in (-1, 0, 1):
                m.rod(M["bone"], 0.012, (other.x + k * 0.022, other.y, other.z + 0.03), (other.x + k * 0.03, other.y - 0.07, other.z + 0.2), r2=0.002, node="ArmL", segs=6)
        else:
            arm(m, M, b, "ArmL", -1, limb, skin)


if __name__ == "__main__":
    import bpy
    bpy.ops.wm.read_factory_settings(use_empty=True)
    textures = os.path.join(OUT, "textures")
    made = {name: kit.material(name, kit.make_textures(textures, "wl_" + name, kind, color, seed)) for name, (kind, color, seed) in TEXTURES.items()}
    M = {name: (made[material], color) for name, (material, color) in PAINTS.items()}
    M.update({name: made[name] for name in ("body", "hide", "cloth")})
    M["eye"] = kit.material("eye", None, (0.01, 0.01, 0.012))
    for name, spec in SPEC.items():
        model = kit.Model(name, uv_scale=2.0, colored=True)
        humanoid(model, M, spec)
        print("%s: %d triangles" % (name, model.export(OUT)))
