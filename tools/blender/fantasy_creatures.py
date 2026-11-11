# Purpose: developer-time script. Models the fantasy world's 27 creatures with tools/blender/kit.py into
# assets/models/fantasy/creatures/<enemy id>.gltf. A handful of body plans (two-legged, four-legged, shelled, floating
# robe, blob, worm, bird, tree-folk) are dressed differently per creature by the SPEC table at the bottom. All colours
# are per part; every part is also made of something (hide, fur, cloth, straw, bark, scale, bone, ice, metal ...): its
# material carries that name and the game gives it the matching textured surface (game/fantasy_models.gd), so a
# creature is a few draw calls. Eyes and embers are "glow".
# Joint names the game animates (game/enemy.gd): SwingA* and SwingB* swing against each other while walking (legs),
# ArmR strikes, FlapL / FlapR beat (wings), Pulse breathes (blobs, spirits). Model space: x right, y up, f forward.
# Run: python3 tools/blender/fantasy_creatures.py   (from the project folder; needs pip packages bpy, numpy, pillow)
import math
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
import kit
import fantasy_kit as fk

OUT = os.path.join(os.path.dirname(__file__), "..", "..", "assets", "models", "fantasy", "creatures")
GLOW = None
KIND = {}  # colour -> what that part is made of, for the creature being built (filled from its SPEC line)
# what each named colour of a SPEC line is made of unless the line says otherwise ("kinds")
ROLE = {"body": "leather", "limb": "leather", "skin": "leather", "face": "leather", "straw": "thatch", "hat": "cloth", "cloak": "cloth", "leaf": "leaf", "crystal": "ice", "horn": "bone", "beak": "bone", "wing": "leather", "trim": "metal", "crown": "metal", "glass": "paint", "weed": "leaf"}
# colours written into the body plans themselves: blades and anchors, handles and clubs, wheat, the dark of a visor
FIXED = {(0.8, 0.82, 0.86): "metal", (0.75, 0.78, 0.8): "metal", (0.3, 0.32, 0.35): "metal", (0.35, 0.25, 0.14): "wood", (0.4, 0.28, 0.16): "wood", (0.9, 0.75, 0.3): "thatch", (0.03, 0.03, 0.04): "paint", (0.2, 0.45, 0.3): "leaf"}


def kind_of(rgb):
    rgb = tuple(rgb)
    return KIND.get(rgb, FIXED.get(rgb, "leather"))


def c(rgb):
    return fk.K(kind_of(rgb), tuple(rgb))


def shade(rgb, k):
    out = tuple(min(1.0, v * k) for v in rgb)
    KIND.setdefault(out, kind_of(rgb))  # a darker or lighter part is still made of the same thing
    return out


def tube(m, col, pts, radii, node="Body", segs=9, flat=False):
    """A round limb through points [(x, y, f)] with one radius each."""
    m.loft(c(col), [p + (r, r) for p, r in zip(pts, radii)], node=node, segs=segs, steps=2, flat=flat)


def eyes(m, at, gap, size, node="Body"):
    for side in (-1, 1):
        m.ball(GLOW, size, (at[0] + side * gap, at[1], at[2]), node=node, u=7, v=5)


def horn(m, col, base, tip, r, node="Body"):
    m.rod(c(col), r, base, tip, r2=r * 0.12, node=node, segs=6)


def wing(m, col, side, root, span, drop, node, ribs=3):
    """A flat wing in the x-y plane hanging from `root`: a membrane with finger ribs."""
    x, y, f = root
    pts = [(0.0, 0.0), (span * 0.45, span * 0.28), (span, span * 0.1), (span * 0.85, -drop * 0.55), (span * 0.55, -drop * 0.8), (span * 0.25, -drop)]
    m.node(node, root)
    m.prof(c(col), 0.03, [(x + side * px, y + py) for px, py in pts], x=f, bevel=0.0, node=node, across="f")
    for k in range(ribs):
        t = (k + 1) / (ribs + 0.5)
        m.rod(c(shade(col, 0.6)), 0.025, (x, y, f + 0.02), (x + side * span * (1.0 - 0.3 * t), y + span * 0.1 - drop * t, f + 0.02), r2=0.008, node=node, segs=5)


# ---------- body plans ----------

def biped(m, s):
    """Two legs, two arms. s: body, limb, head colours; bulk (1 = slim); head kind; extras."""
    B = s.get("bulk", 1.0)
    body, limb, skin = s["body"], s.get("limb", s["body"]), s.get("skin", s["body"])
    hip, chest, neck = 0.92, 1.32, 1.5
    m.loft(c(body), [(0, hip - 0.1, 0, 0.17 * B, 0.12 * B), (0, 1.05, 0.0, 0.16 * B, 0.12 * B), (0, chest, 0.02, 0.21 * B, 0.14 * B), (0, neck, 0.01, 0.1 * B, 0.09 * B)], segs=12)
    for side, name in ((-1, "SwingA"), (1, "SwingB")):
        x = side * 0.1 * B
        m.node(name, (x, hip, 0))
        tube(m, limb, [(x, hip, 0), (x, 0.5, 0.02), (x, 0.08, 0.0)], [0.085 * B, 0.065 * B, 0.05 * B], node=name)
        m.loft(c(shade(limb, 0.7)), [(x, 0.05, -0.06, 0.055 * B, 0.045), (x, 0.045, 0.14, 0.06 * B, 0.04)], node=name, segs=8, steps=2)
    for side, name in ((-1, "ArmL"), (1, "ArmR")):
        x = side * 0.25 * B
        m.node(name, (x, chest + 0.1, 0))
        tube(m, limb, [(x, chest + 0.1, 0), (x + side * 0.05, 1.08, 0.0), (x + side * 0.04, 0.78, 0.04)], [0.065 * B, 0.05 * B, 0.045 * B], node=name)
        m.ball(c(skin), 0.055 * B, (x + side * 0.04, 0.74, 0.05), node=name, u=8, v=6)
    hy = neck + 0.16
    kind = s.get("head", "round")
    if kind == "sack":  # a stuffed sack tied at the neck
        m.loft(c(skin), [(0, neck - 0.02, 0, 0.07, 0.07), (0, hy - 0.02, 0.01, 0.15, 0.15), (0, hy + 0.14, 0.0, 0.13, 0.13), (0, hy + 0.24, -0.02, 0.05, 0.05)], segs=10)
        m.loft(c(shade(skin, 0.6)), [(0, neck + 0.02, 0, 0.085, 0.085), (0, neck + 0.05, 0, 0.085, 0.085)], segs=10, steps=1, flat=True)
    elif kind == "helm":  # a closed helmet with a slit
        m.loft(c(skin), [(0, neck, 0, 0.1, 0.1), (0, hy, 0.0, 0.14, 0.15), (0, hy + 0.16, 0.0, 0.12, 0.13), (0, hy + 0.25, 0.0, 0.04, 0.05)], segs=12)
        m.box(c((0.03, 0.03, 0.04)), (0.2, 0.035, 0.05), (0, hy + 0.04, 0.13), bevel=0.005)
    elif kind == "skull":
        m.ball(c(skin), (0.13, 0.15, 0.15), (0, hy + 0.04, 0.0))
        m.box(c(skin), (0.14, 0.08, 0.12), (0, hy - 0.1, 0.06), bevel=0.02)
    else:
        m.ball(c(skin), (0.14, 0.15, 0.15), (0, hy + 0.03, 0.0))
    if kind != "helm":
        eyes(m, (0, hy + 0.05, 0.13), 0.055, 0.028)
    return {"neck": neck, "head": hy, "chest": chest, "hip": hip, "B": B}


def quadruped(m, s):
    """Four legs, a head on a neck and a tail. Length runs along f."""
    body, limb = s["body"], s.get("limb", s["body"])
    L, H, W = s.get("len", 1.3), s.get("h", 0.75), s.get("w", 0.22)
    m.loft(c(body), [(0, H, -L * 0.5, W * 0.8, W * 0.8), (0, H + 0.02, -L * 0.2, W, W * 1.05), (0, H + 0.05, L * 0.25, W * 1.15, W * 1.2), (0, H + 0.08, L * 0.5, W * 0.75, W * 0.8)], segs=12)
    legs = [("SwingA1", -1, L * 0.36), ("SwingB1", 1, L * 0.36), ("SwingB2", -1, -L * 0.38), ("SwingA2", 1, -L * 0.38)]
    for name, side, f in legs:
        x = side * W * 0.75
        m.node(name, (x, H, f))
        tube(m, limb, [(x, H, f), (x, H * 0.5, f - 0.04), (x, 0.05, f + 0.02)], [W * 0.42, W * 0.3, W * 0.24], node=name)
        m.ball(c(shade(limb, 0.7)), (W * 0.3, 0.05, W * 0.38), (x, 0.05, f + 0.05), node=name, u=8, v=5)
    ny = H + s.get("neck", 0.25)
    nf = L * 0.5 + 0.18
    tube(m, body, [(0, H + 0.06, L * 0.42), (0, ny - 0.05, nf - 0.08), (0, ny, nf)], [W * 0.75, W * 0.6, W * 0.55])
    snout = s.get("snout", 0.28)
    m.loft(c(body), [(0, ny + 0.02, nf - 0.1, W * 0.62, W * 0.6), (0, ny, nf + 0.08, W * 0.55, W * 0.5), (0, ny - 0.04, nf + snout, W * 0.26, W * 0.22)], segs=10)
    m.ball(c((0.05, 0.04, 0.05)), W * 0.14, (0, ny - 0.02, nf + snout + 0.02), u=6, v=5)
    eyes(m, (0, ny + 0.07, nf + 0.1), W * 0.36, W * 0.13)
    for side in (-1, 1):  # ears
        horn(m, shade(body, 0.8), (side * W * 0.4, ny + W * 0.4, nf - 0.05), (side * W * 0.55, ny + W * 1.3, nf - 0.1), W * 0.22)
    tail = s.get("tail", 0.6)
    tube(m, body, [(0, H + 0.02, -L * 0.48), (0, H + 0.12, -L * 0.5 - tail * 0.5), (0, H - 0.05, -L * 0.5 - tail)], [W * 0.4, W * 0.34, W * 0.1])
    return {"H": H, "L": L, "W": W, "ny": ny, "nf": nf}


def shelled(m, s):
    """A wide shell on six legs with two claws: crabs and scorpions."""
    shell, limb = s["body"], s.get("limb", s["body"])
    R = s.get("r", 0.6)
    m.ball(c(shell), (R, R * 0.42, R * 0.8), (0, R * 0.55, 0), u=14, v=8)
    m.ball(c(shade(shell, 0.75)), (R * 0.86, R * 0.2, R * 0.7), (0, R * 0.36, 0), u=12, v=6)
    for k in range(3):
        for side in (-1, 1):
            name = ("SwingA" if (k + (side > 0)) % 2 == 0 else "SwingB") + str(k * 2 + (1 if side > 0 else 0))
            f = (k - 1) * R * 0.5
            root = (side * R * 0.75, R * 0.45, f)
            m.node(name, root)
            tube(m, limb, [root, (side * R * 1.35, R * 0.7, f * 1.2), (side * R * 1.6, 0.03, f * 1.4)], [R * 0.11, R * 0.09, R * 0.03], node=name, segs=6)
    for side in (-1, 1):
        name = "ArmR" if side > 0 else "ArmL"
        root = (side * R * 0.6, R * 0.5, R * 0.6)
        m.node(name, root)
        tube(m, limb, [root, (side * R * 0.95, R * 0.6, R * 1.1), (side * R * 0.7, R * 0.55, R * 1.5)], [R * 0.13, R * 0.12, R * 0.14], node=name, segs=7)
        m.ball(c(shade(shell, 1.1)), (R * 0.22, R * 0.2, R * 0.34), (side * R * 0.62, R * 0.55, R * 1.72), node=name, u=9, v=6)
        horn(m, shade(shell, 0.6), (side * R * 0.55, R * 0.5, R * 1.9), (side * R * 0.42, R * 0.56, R * 2.25), R * 0.09, node=name)
    for side in (-1, 1):  # eye stalks
        m.rod(c(limb), R * 0.04, (side * R * 0.2, R * 0.75, R * 0.6), (side * R * 0.24, R * 1.05, R * 0.72), node="Body", segs=5)
        m.ball(GLOW, R * 0.08, (side * R * 0.24, R * 1.08, R * 0.73), u=7, v=5)
    return {"R": R}


def robe(m, s):
    """A floating hooded shape that narrows to a wisp: wraiths and spirits. The whole thing breathes ("Pulse")."""
    cloth, inner = s["body"], s.get("limb", (0.04, 0.04, 0.06))
    m.node("Pulse", (0, 0.9, 0))
    m.loft(c(cloth), [(0.05, 0.12, -0.12, 0.03, 0.03), (0, 0.5, -0.04, 0.16, 0.13), (0, 1.0, 0.0, 0.26, 0.2), (0, 1.4, 0.02, 0.24, 0.18), (0, 1.62, 0.03, 0.13, 0.12)], node="Pulse", segs=12)
    m.loft(c(cloth), [(0, 1.55, 0.0, 0.14, 0.15), (0, 1.74, 0.03, 0.18, 0.2), (0, 1.9, 0.0, 0.14, 0.17), (0, 1.99, -0.05, 0.04, 0.06)], node="Pulse", segs=12)  # hood
    m.ball(c(inner), (0.11, 0.13, 0.08), (0, 1.74, 0.13), node="Pulse", u=9, v=6)  # the dark inside the hood
    eyes(m, (0, 1.77, 0.19), 0.045, 0.024, node="Pulse")
    for side in (-1, 1):
        name = "ArmR" if side > 0 else "ArmL"
        root = (side * 0.24, 1.42, 0.0)
        m.node(name, root, parent="Pulse")
        tube(m, cloth, [root, (side * 0.36, 1.15, 0.1), (side * 0.3, 0.92, 0.3)], [0.08, 0.075, 0.09], node=name)
        for k in range(3):  # long fingers
            horn(m, inner, (side * 0.3 + (k - 1) * 0.03, 0.9, 0.34), (side * 0.3 + (k - 1) * 0.06, 0.78, 0.5), 0.016, node=name)
    for k in range(5):  # torn hem
        a = k * 2 * math.pi / 5 + 0.4
        horn(m, shade(cloth, 0.8), (math.cos(a) * 0.12, 0.42, math.sin(a) * 0.1 - 0.04), (math.cos(a) * 0.2, 0.05, math.sin(a) * 0.2 - 0.14), 0.05, node="Pulse")


def blob(m, s):
    """A jelly that breathes ("Pulse"), with something floating inside."""
    jelly = s["body"]
    m.node("Pulse", (0, 0.0, 0))
    m.loft(c(jelly), [(0, 0.02, 0, 0.5, 0.5), (0, 0.22, 0, 0.56, 0.56), (0, 0.5, 0.02, 0.44, 0.44), (0, 0.72, 0.03, 0.2, 0.2)], node="Pulse", segs=14)
    m.ball(c(shade(jelly, 1.25)), (0.16, 0.1, 0.14), (-0.14, 0.52, 0.2), node="Pulse", u=8, v=6)  # the shine
    eyes(m, (0, 0.36, 0.44), 0.14, 0.06, node="Pulse")
    m.ball(c(shade(jelly, 0.6)), (0.12, 0.03, 0.03), (0, 0.22, 0.52), node="Pulse", u=8, v=4)  # mouth
    for k in range(5):  # drips around the foot
        a = k * 2 * math.pi / 5
        m.ball(c(jelly), (0.14, 0.06, 0.14), (math.cos(a) * 0.52, 0.04, math.sin(a) * 0.52), node="Pulse", u=7, v=4)


def worm(m, s):
    """A thick worm rising out of the ground with a ring of teeth: the Glassmaw."""
    hide, tooth = s["body"], s.get("limb", (0.9, 0.9, 0.8))
    spine = [(0, 0.0, -0.5, 0.75), (0, 1.2, -0.42, 0.72), (0, 2.4, -0.15, 0.66), (0, 3.2, 0.35, 0.6), (0, 3.55, 0.95, 0.62)]
    m.loft(c(hide), [(x, y, f, r, r) for x, y, f, r in spine], segs=14)
    for k, (x, y, f, r) in enumerate(spine[:-1]):  # armour rings
        m.loft(c(shade(hide, 0.7)), [(x, y + 0.3, f + 0.02, r * 1.07, r * 1.07), (x, y + 0.5, f + 0.06, r * 1.07, r * 1.07)], segs=14, steps=1, flat=True)
    hx, hy, hf = 0, 3.6, 1.2
    m.ball(c((0.25, 0.05, 0.08)), (0.5, 0.5, 0.2), (hx, hy, hf), pitch=-20, u=12, v=6)  # throat
    for k in range(10):
        a = k * 2 * math.pi / 10
        base = (hx + math.cos(a) * 0.52, hy + math.sin(a) * 0.5, hf)
        horn(m, tooth, base, (hx + math.cos(a) * 0.3, hy + math.sin(a) * 0.3, hf + 0.55), 0.09)
    for k in range(7):  # glass spines down the back
        t = k / 6.0
        y = 0.6 + t * 2.6
        f = -0.5 + t * 0.6 - 0.62
        horn(m, s.get("glass", (0.7, 0.95, 1.0)), (0, y, f + 0.1), (0, y + 0.35, f - 0.5), 0.1)
    eyes(m, (0, hy + 0.5, hf - 0.25), 0.3, 0.08)
    for k in range(8):  # the sand it bursts from
        a = k * 2 * math.pi / 8
        m.ball(c(s.get("sand", (0.8, 0.68, 0.42))), (0.45, 0.2, 0.45), (math.cos(a) * 0.95, 0.08, math.sin(a) * 0.95 - 0.5), u=7, v=4)


def bird(m, s):
    """A great bird: two taloned legs, wings that beat, a hooked beak. Harpies get a face instead (s["face"])."""
    feather, limb, beak = s["body"], s.get("limb", (0.85, 0.65, 0.2)), s.get("beak", (0.95, 0.75, 0.2))
    m.loft(c(feather), [(0, 0.75, -0.42, 0.1, 0.12), (0, 0.95, -0.15, 0.25, 0.26), (0, 1.15, 0.1, 0.3, 0.3), (0, 1.35, 0.28, 0.2, 0.2), (0, 1.6, 0.36, 0.13, 0.13)], segs=12)
    m.ball(c(shade(feather, 1.15)), (0.24, 0.26, 0.2), (0, 1.02, 0.2), u=10, v=7)  # breast
    for side, name in ((-1, "SwingA"), (1, "SwingB")):
        x = side * 0.14
        m.node(name, (x, 0.9, -0.05))
        tube(m, feather, [(x, 0.9, -0.05), (x, 0.6, 0.0)], [0.1, 0.07], node=name)
        tube(m, limb, [(x, 0.6, 0.0), (x, 0.3, -0.04), (x, 0.05, 0.0)], [0.035, 0.03, 0.035], node=name, segs=6)
        for k in (-1, 0, 1):
            horn(m, limb, (x, 0.05, 0.0), (x + k * 0.09, 0.02, 0.2), 0.03, node=name)
    hy, hf = 1.72, 0.42
    m.ball(c(shade(feather, 1.1) if "face" not in s else s["face"]), (0.15, 0.16, 0.17), (0, hy, hf), u=10, v=7)
    if "face" in s:
        m.loft(c(shade(feather, 0.8)), [(0, hy + 0.1, hf - 0.08, 0.16, 0.14), (0, hy - 0.1, hf - 0.2, 0.13, 0.1), (0, hy - 0.4, hf - 0.3, 0.05, 0.05)], segs=9)  # hair of feathers
        eyes(m, (0, hy + 0.02, hf + 0.15), 0.055, 0.026)
    else:
        m.loft(c(beak), [(0, hy - 0.02, hf + 0.12, 0.07, 0.07), (0, hy - 0.05, hf + 0.3, 0.05, 0.05), (0, hy - 0.16, hf + 0.4, 0.012, 0.015)], segs=8)
        eyes(m, (0, hy + 0.05, hf + 0.1), 0.1, 0.03)
        for k in range(3):  # crest
            horn(m, shade(feather, 0.75), (0, hy + 0.12, hf - 0.04 - k * 0.06), (0, hy + 0.36 - k * 0.04, hf - 0.2 - k * 0.1), 0.04)
    for side in (-1, 1):
        wing(m, shade(feather, 0.85), side, (side * 0.26, 1.3, 0.05), s.get("span", 1.5), 0.9, "FlapR" if side > 0 else "FlapL", ribs=4)
    for k in (-1, 0, 1):  # tail feathers
        m.loft(c(shade(feather, 0.7)), [(k * 0.08, 0.8, -0.4, 0.06, 0.02), (k * 0.2, 0.7, -0.95, 0.09, 0.015)], segs=6, steps=2)


def treefolk(m, s):
    """A walking tree: trunk body on root legs, branch arms, a crown of leaves."""
    bark, leaf = s["body"], s.get("leaf", (0.25, 0.5, 0.2))
    m.loft(c(bark), [(0, 0.55, 0, 0.3, 0.26), (0.03, 1.0, 0.02, 0.24, 0.22), (-0.02, 1.5, 0.0, 0.27, 0.24), (0, 1.9, 0.02, 0.2, 0.2)], segs=10)
    for side, name in ((-1, "SwingA"), (1, "SwingB")):
        x = side * 0.2
        m.node(name, (x, 0.6, 0))
        tube(m, bark, [(x, 0.62, 0), (x * 1.3, 0.3, 0.03), (x * 1.5, 0.04, 0.08)], [0.14, 0.11, 0.13], node=name, segs=8)
        for k in (-1, 1):
            horn(m, shade(bark, 0.8), (x * 1.5, 0.06, 0.05), (x * 1.5 + k * 0.2, 0.01, 0.3), 0.06, node=name)
    for side in (-1, 1):
        name = "ArmR" if side > 0 else "ArmL"
        root = (side * 0.27, 1.55, 0)
        m.node(name, root)
        tube(m, bark, [root, (side * 0.55, 1.25, 0.06), (side * 0.6, 0.85, 0.2)], [0.1, 0.08, 0.07], node=name, segs=7)
        for k in range(3):
            horn(m, shade(bark, 0.8), (side * 0.6, 0.86, 0.2), (side * 0.6 + (k - 1) * 0.14, 0.62, 0.32), 0.035, node=name)
    eyes(m, (0, 1.55, 0.23), 0.09, 0.04)
    m.box(c((0.05, 0.03, 0.02)), (0.16, 0.05, 0.04), (0, 1.36, 0.23), bevel=0.01)
    for k in range(s.get("crown", 5)):
        a = k * 2 * math.pi / s.get("crown", 5)
        m.ball(c(shade(leaf, 0.85 + 0.1 * (k % 3))), (0.34, 0.26, 0.34), (math.cos(a) * 0.26, 2.05 + 0.08 * (k % 2), math.sin(a) * 0.26), u=8, v=6)
    m.ball(c(shade(leaf, 1.1)), (0.36, 0.3, 0.36), (0, 2.3, 0), u=9, v=6)
    for k in range(4):  # moss and knots on the trunk
        a = k * 1.7 + 0.5
        m.ball(c(shade(leaf, 0.7)), (0.09, 0.06, 0.05), (math.cos(a) * 0.24, 0.8 + k * 0.25, math.sin(a) * 0.22), u=6, v=4)


# ---------- dressing ----------

def straw(m, col, at, n=6, length=0.14, node="Body"):
    for k in range(n):
        a = k * 2 * math.pi / n
        m.rod(c(col), 0.012, at, (at[0] + math.cos(a) * length, at[1] - length * 0.5, at[2] + math.sin(a) * length), r2=0.004, node=node, segs=4)


def dress(m, s, b):
    """Extras a creature wears, listed in its spec."""
    X = s.get("extras", [])
    body = s["body"]
    if "straw" in X:
        for name, (x, y) in (("ArmL", (-0.3, 0.76)), ("ArmR", (0.3, 0.76)), ("SwingA", (-0.1, 0.1)), ("SwingB", (0.1, 0.1))):
            straw(m, s["straw"], (x * b["B"], y, 0.03), node=name)
        straw(m, s["straw"], (0, b["neck"] + 0.03, 0), n=9, length=0.2)
        m.box(c(shade(body, 0.6)), (0.14, 0.12, 0.02), (0.06, 1.2, 0.15 * b["B"]), tilt=12, bevel=0.004)  # a patch
    if "hat" in X:
        m.lathe(c(s.get("hat", (0.3, 0.22, 0.12))), [(0.3, 0.0), (0.32, 0.02), (0.13, 0.06), (0.1, 0.24), (0.02, 0.34)], (0, b["head"] + 0.2, 0), segs=12)
    if "crown" in X:
        for k in range(7):
            a = k * 2 * math.pi / 7
            horn(m, s.get("crown", (0.95, 0.8, 0.3)), (math.cos(a) * 0.12, b["head"] + 0.16, math.sin(a) * 0.12), (math.cos(a) * 0.17, b["head"] + 0.42, math.sin(a) * 0.17), 0.03)
        m.loft(c(s.get("crown", (0.95, 0.8, 0.3))), [(0, b["head"] + 0.14, 0, 0.14, 0.15), (0, b["head"] + 0.2, 0, 0.14, 0.15)], segs=12, steps=1, flat=True)
    if "cloak" in X:
        m.loft(c(s.get("cloak", shade(body, 0.6))), [(0, b["neck"], -0.1, 0.24 * b["B"], 0.05), (0, 1.0, -0.2, 0.3 * b["B"], 0.05), (0, 0.3, -0.3, 0.36 * b["B"], 0.04)], segs=8, steps=3)
    if "scythe" in X or "sword" in X or "club" in X or "anchor" in X:
        x, y, f = 0.29 * b["B"], 0.74, 0.05
        if "scythe" in X:
            m.rod(c((0.35, 0.25, 0.14)), 0.022, (x, y - 0.5, f - 0.2), (x, y + 1.3, f + 0.5), node="ArmR", segs=6)
            m.loft(c((0.75, 0.78, 0.8)), [(x, y + 1.3, f + 0.5, 0.012, 0.05), (x, y + 1.4, f + 0.9, 0.012, 0.07), (x, y + 1.15, f + 1.25, 0.008, 0.02)], node="ArmR", segs=6, steps=3)
        elif "sword" in X:
            m.box(c((0.8, 0.82, 0.86)), (0.025, 0.07, 1.1), (x, y + 0.02, f + 0.68), bevel=0.006, node="ArmR")
            m.box(c(s.get("trim", (0.75, 0.6, 0.2))), (0.03, 0.26, 0.05), (x, y + 0.02, f + 0.12), bevel=0.006, node="ArmR")
        elif "club" in X:
            tube(m, (0.4, 0.28, 0.16), [(x, y, f - 0.05), (x, y + 0.02, f + 0.4), (x, y + 0.03, f + 0.75)], [0.03, 0.05, 0.1], node="ArmR")
        else:
            m.rod(c((0.3, 0.32, 0.35)), 0.035, (x, y, f - 0.1), (x, y, f + 1.0), node="ArmR", segs=6)
            m.loft(c((0.3, 0.32, 0.35)), [(x - 0.3, y + 0.16, f + 0.82, 0.03, 0.03), (x, y - 0.02, f + 1.05, 0.045, 0.045), (x + 0.3, y + 0.16, f + 0.82, 0.03, 0.03)], node="ArmR", segs=6, steps=3)
    if "shield" in X:
        m.lathe(c(s.get("trim", (0.6, 0.6, 0.65))), [(0.0, 0.0), (0.3, 0.03), (0.32, 0.06), (0.0, 0.09)], (-0.34 * b["B"], 0.95, 0.12), node="ArmL", segs=12, axis="f")
    if "horns" in X:
        for side in (-1, 1):
            horn(m, s.get("horn", (0.9, 0.85, 0.7)), (side * 0.1, b["head"] + 0.1, 0.0), (side * 0.24, b["head"] + 0.34, 0.06), 0.045)
    if "ears" in X:
        for side in (-1, 1):
            m.loft(c(s.get("skin", body)), [(side * 0.12, b["head"] + 0.04, 0, 0.03, 0.05), (side * 0.3, b["head"] + 0.1, -0.03, 0.02, 0.035), (side * 0.42, b["head"] + 0.18, -0.06, 0.004, 0.008)], segs=6, steps=2)
    if "tail" in X:
        tube(m, s.get("limb", body), [(0, b["hip"], -0.1), (0, 0.6, -0.4), (0, 0.8, -0.65)], [0.05, 0.035, 0.01])
        horn(m, s.get("horn", (0.2, 0.05, 0.05)), (0, 0.8, -0.65), (0, 0.95, -0.72), 0.04)
    if "small_wings" in X:
        for side in (-1, 1):
            wing(m, s.get("wing", shade(body, 0.6)), side, (side * 0.1, b["chest"] + 0.08, -0.12), 0.55, 0.4, "FlapR" if side > 0 else "FlapL", ribs=2)
    if "plume" in X:
        m.loft(c(s.get("trim", (0.8, 0.2, 0.2))), [(0, b["head"] + 0.24, 0.02, 0.02, 0.04), (0, b["head"] + 0.42, -0.08, 0.025, 0.09), (0, b["head"] + 0.3, -0.26, 0.012, 0.05)], segs=6, steps=3)
    if "plates" in X:  # shoulder and chest armour
        for side in (-1, 1):
            m.ball(c(s.get("trim", shade(body, 1.2))), (0.12 * b["B"], 0.09, 0.12 * b["B"]), (side * 0.26 * b["B"], b["chest"] + 0.14, 0), node="ArmR" if side > 0 else "ArmL", u=9, v=6)
        m.loft(c(s.get("trim", shade(body, 1.2))), [(0, 1.1, 0.03, 0.2 * b["B"], 0.15 * b["B"]), (0, b["chest"] + 0.06, 0.04, 0.23 * b["B"], 0.16 * b["B"])], segs=12, steps=2, flat=True)
    if "crystals" in X:
        spots = [(-0.2, b["chest"] + 0.16, -0.05), (0.22, b["chest"] + 0.18, -0.02), (0.0, b["chest"] + 0.1, -0.16), (-0.1, b["head"] + 0.16, -0.04), (0.12, 1.0, -0.14)]
        for k, (x, y, f) in enumerate(spots):
            horn(m, s.get("crystal", (0.7, 0.92, 1.0)), (x * b["B"], y, f), (x * b["B"] * 1.5, y + 0.3 + 0.08 * (k % 2), f - 0.12), 0.06)
    if "seaweed" in X:
        for k in range(5):
            x = (k - 2) * 0.09
            m.loft(c(s.get("weed", (0.2, 0.45, 0.3))), [(x, b["chest"] + 0.1, 0.13, 0.02, 0.008), (x * 1.2, 1.0, 0.16, 0.025, 0.008), (x * 1.3 + 0.03, 0.7, 0.14, 0.012, 0.006)], segs=5, steps=2)
    if "embers" in X:
        for k in range(6):
            a = k * 1.9
            m.ball(GLOW, 0.035, (math.cos(a) * 0.2 * b["B"], 0.9 + k * 0.12, math.sin(a) * 0.14 * b["B"] + 0.05), u=6, v=4)
    if "wheat_crown" in X:
        for k in range(9):
            a = k * 2 * math.pi / 9
            m.rod(c((0.9, 0.75, 0.3)), 0.018, (math.cos(a) * 0.1, b["head"] + 0.18, math.sin(a) * 0.1), (math.cos(a) * 0.2, b["head"] + 0.55, math.sin(a) * 0.2), r2=0.03, segs=5)


def quad_dress(m, s, b):
    X = s.get("extras", [])
    H, L, W = b["H"], b["L"], b["W"]
    if "ice_spikes" in X or "back_spikes" in X:
        for k in range(5):
            f = L * 0.4 - k * L * 0.2
            horn(m, s.get("crystal", (0.75, 0.93, 1.0)), (0, H + W, f), (0, H + W + 0.28 - 0.03 * abs(k - 2), f - 0.12), W * 0.3)
    if "mane" in X:
        for k in range(6):
            a = (k - 2.5) * 0.4
            horn(m, shade(s["body"], 0.7), (math.sin(a) * W * 0.6, b["ny"] - 0.02, b["nf"] - 0.12), (math.sin(a) * W * 1.3, b["ny"] + 0.12, b["nf"] - 0.34), W * 0.22)
    if "wings" in X:
        for side in (-1, 1):
            wing(m, s.get("wing", shade(s["body"], 0.65)), side, (side * W * 0.7, H + W * 0.9, L * 0.15), s.get("span", 1.4), 0.8, "FlapR" if side > 0 else "FlapL", ribs=4)
    if "horns" in X:
        for side in (-1, 1):
            horn(m, s.get("horn", (0.9, 0.85, 0.7)), (side * W * 0.35, b["ny"] + W * 0.4, b["nf"] - 0.02), (side * W * 0.6, b["ny"] + W * 1.7, b["nf"] - 0.3), W * 0.2)
    if "embers" in X:
        for k in range(6):
            m.ball(GLOW, W * 0.16, ((k % 2 - 0.5) * W * 1.4, H + W * 0.6, L * 0.4 - k * L * 0.16), u=6, v=4)


SPEC = {
    # region 1: the wheat fields
    "strawling": dict(plan="biped", bulk=0.9, head="sack", body=(0.55, 0.36, 0.2), limb=(0.82, 0.68, 0.3), skin=(0.85, 0.74, 0.5), straw=(0.95, 0.82, 0.35), extras=["straw", "hat"], hat=(0.45, 0.3, 0.15), kinds={"body": "cloth", "limb": "thatch", "skin": "cloth"}),
    "field_slime": dict(plan="blob", body=(0.5, 0.85, 0.3), kinds={"body": "paint"}),
    "harvest_king": dict(plan="biped", bulk=1.25, head="sack", body=(0.42, 0.24, 0.12), limb=(0.8, 0.62, 0.25), skin=(0.9, 0.55, 0.15), straw=(0.95, 0.8, 0.3), extras=["straw", "wheat_crown", "cloak", "scythe"], cloak=(0.5, 0.16, 0.1), kinds={"body": "cloth", "limb": "thatch", "skin": "cloth"}),
    # region 2: the old forest
    "forest_wolf": dict(plan="quad", body=(0.42, 0.4, 0.38), limb=(0.3, 0.29, 0.28), extras=["mane"], kinds={"body": "fur", "limb": "fur"}),
    "mossgoblin": dict(plan="biped", bulk=0.85, body=(0.3, 0.26, 0.16), limb=(0.4, 0.55, 0.25), skin=(0.42, 0.6, 0.28), extras=["ears", "club"], kinds={"body": "cloth"}),
    "barkhide": dict(plan="tree", body=(0.36, 0.26, 0.16), leaf=(0.25, 0.48, 0.2), crown=4, kinds={"body": "bark"}),
    "rootmother": dict(plan="tree", body=(0.28, 0.2, 0.14), leaf=(0.2, 0.55, 0.25), crown=8, kinds={"body": "bark"}),
    # region 3: the coast
    "reef_crab": dict(plan="shell", body=(0.85, 0.4, 0.3), limb=(0.7, 0.3, 0.24), kinds={"body": "scale", "limb": "scale"}),
    "drowned_sailor": dict(plan="biped", head="skull", body=(0.16, 0.26, 0.36), limb=(0.25, 0.32, 0.36), skin=(0.6, 0.75, 0.72), extras=["seaweed", "hat", "sword"], hat=(0.1, 0.12, 0.2), kinds={"body": "cloth", "limb": "cloth", "skin": "bone"}),
    "tidewarden": dict(plan="biped", bulk=1.45, head="helm", body=(0.2, 0.42, 0.5), limb=(0.16, 0.3, 0.4), skin=(0.75, 0.82, 0.8), trim=(0.85, 0.5, 0.4), extras=["plates", "anchor", "seaweed", "crystals"], crystal=(0.95, 0.55, 0.45), kinds={"body": "cloth", "limb": "cloth", "skin": "metal", "crystal": "scale"}),
    # region 4: the desert
    "dune_scorpion": dict(plan="shell", body=(0.7, 0.52, 0.28), limb=(0.5, 0.36, 0.2), sting=True, kinds={"body": "scale", "limb": "scale"}),
    "sand_wraith": dict(plan="robe", body=(0.82, 0.7, 0.45), limb=(0.12, 0.08, 0.05), kinds={"body": "cloth", "limb": "paint"}),
    "glassmaw": dict(plan="worm", body=(0.72, 0.56, 0.34), glass=(0.6, 0.95, 0.9), kinds={"body": "scale"}),
    # region 5: the frozen north
    "frost_wolf": dict(plan="quad", body=(0.85, 0.9, 0.96), limb=(0.6, 0.7, 0.82), extras=["ice_spikes", "mane"], kinds={"body": "fur", "limb": "fur"}),
    "ice_golem": dict(plan="biped", bulk=1.5, head="round", body=(0.62, 0.8, 0.92), limb=(0.5, 0.68, 0.85), skin=(0.75, 0.9, 1.0), extras=["crystals", "plates"], trim=(0.85, 0.95, 1.0), kinds={"body": "ice", "limb": "ice", "skin": "ice", "trim": "ice"}),
    "rime_colossus": dict(plan="biped", bulk=1.7, head="helm", body=(0.5, 0.68, 0.86), limb=(0.4, 0.56, 0.78), skin=(0.8, 0.92, 1.0), extras=["crystals", "plates", "crown", "club"], crown=(0.8, 0.95, 1.0), trim=(0.9, 0.97, 1.0), kinds={"body": "ice", "limb": "ice", "skin": "ice", "trim": "ice", "crown": "ice"}),
    # region 6: the volcano
    "magma_imp": dict(plan="biped", bulk=0.8, body=(0.32, 0.1, 0.08), limb=(0.5, 0.14, 0.08), skin=(0.6, 0.16, 0.1), extras=["horns", "tail", "small_wings", "embers"], horn=(0.15, 0.1, 0.1), wing=(0.25, 0.06, 0.05), kinds={"crystal": "rock"}),
    "ash_drake": dict(plan="quad", len=1.7, h=0.85, w=0.26, neck=0.5, snout=0.4, tail=1.1, body=(0.3, 0.27, 0.27), limb=(0.22, 0.2, 0.2), extras=["wings", "horns", "back_spikes", "embers"], crystal=(0.9, 0.35, 0.1), wing=(0.45, 0.14, 0.08), kinds={"body": "scale", "limb": "scale", "crystal": "rock"}),
    "cinderwyrm": dict(plan="quad", len=2.4, h=0.9, w=0.3, neck=0.9, snout=0.5, tail=1.8, body=(0.36, 0.1, 0.08), limb=(0.22, 0.07, 0.06), extras=["wings", "horns", "back_spikes", "embers"], span=2.2, crystal=(1.0, 0.5, 0.1), wing=(0.6, 0.2, 0.06), horn=(0.12, 0.1, 0.1), kinds={"body": "scale", "limb": "scale", "crystal": "rock"}),
    # region 7: the storm peaks
    "storm_harpy": dict(plan="bird", body=(0.4, 0.42, 0.58), face=(0.8, 0.72, 0.68), span=1.3, kinds={"body": "feather"}),
    "gale_spirit": dict(plan="robe", body=(0.75, 0.86, 0.95), limb=(0.3, 0.4, 0.55), kinds={"body": "cloth", "limb": "paint"}),
    "tempest_roc": dict(plan="bird", body=(0.3, 0.3, 0.46), span=2.3, beak=(1.0, 0.8, 0.25), kinds={"body": "feather"}),
    # region 8: the colourless court
    "pale_knight": dict(plan="biped", bulk=1.15, head="helm", body=(0.8, 0.8, 0.82), limb=(0.66, 0.66, 0.7), skin=(0.9, 0.9, 0.92), trim=(0.95, 0.95, 0.97), extras=["plates", "sword", "shield", "plume"], kinds={"body": "metal", "limb": "metal", "skin": "metal"}),
    "hollow_shade": dict(plan="robe", body=(0.2, 0.2, 0.24), limb=(0.02, 0.02, 0.03), kinds={"body": "cloth", "limb": "paint"}),
    # the two desert tribes (people, not monsters: wrapped heads, tunics, shields)
    "red_warrior": dict(plan="biped", bulk=1.05, head="helm", body=(0.6, 0.22, 0.17), limb=(0.52, 0.38, 0.27), skin=(0.66, 0.26, 0.2), trim=(0.6, 0.45, 0.28), extras=["sword", "shield", "plume", "cloak"], cloak=(0.46, 0.16, 0.13), kinds={"body": "cloth", "skin": "cloth", "trim": "wood"}),
    "blue_warrior": dict(plan="biped", bulk=1.05, head="helm", body=(0.2, 0.32, 0.55), limb=(0.52, 0.38, 0.27), skin=(0.24, 0.36, 0.58), trim=(0.6, 0.45, 0.28), extras=["club", "shield", "plume", "cloak"], cloak=(0.15, 0.22, 0.42), kinds={"body": "cloth", "skin": "cloth", "trim": "wood"}),
    "pallid_king": dict(plan="biped", bulk=1.2, head="skull", body=(0.9, 0.9, 0.9), limb=(0.78, 0.78, 0.8), skin=(0.96, 0.96, 0.94), trim=(0.85, 0.75, 0.4), extras=["crown", "cloak", "sword", "plates"], cloak=(0.82, 0.82, 0.86), crown=(0.9, 0.8, 0.4), kinds={"body": "cloth", "limb": "cloth", "skin": "bone"}),
}


def build(m, s):
    plan = s["plan"]
    if plan == "biped":
        dress(m, s, biped(m, s))
    elif plan == "quad":
        quad_dress(m, s, quadruped(m, s))
    elif plan == "shell":
        b = shelled(m, s)
        if s.get("sting"):  # the scorpion's tail arcs over its back
            R = b["R"]
            pts = [(0, R * 0.6, -R * 0.7), (0, R * 1.3, -R * 1.3), (0, R * 2.1, -R * 0.9), (0, R * 2.3, -R * 0.1)]
            tube(m, s["body"], pts, [R * 0.2, R * 0.17, R * 0.14, R * 0.12], segs=8)
            horn(m, (0.25, 0.1, 0.08), pts[-1], (0, R * 1.95, R * 0.35), R * 0.11)
    elif plan == "robe":
        robe(m, s)
    elif plan == "blob":
        blob(m, s)
    elif plan == "worm":
        worm(m, s)
    elif plan == "bird":
        bird(m, s)
    elif plan == "tree":
        treefolk(m, s)


def build_all():
    global GLOW
    fk.init()
    GLOW = fk.GLOW
    for name, s in SPEC.items():
        KIND.clear()
        for role, kind in {**ROLE, **s.get("kinds", {})}.items():
            if isinstance(s.get(role), tuple):
                KIND[s[role]] = kind
        m = kit.Model(name, uv_scale=0.5, colored=True)
        build(m, s)
        print(name, m.export(OUT))


if __name__ == "__main__":
    build_all()
