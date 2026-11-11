# Purpose: developer-time script. Models the original creatures with tools/blender/kit.py and exports them to
# assets/models/creatures/: skeleton_sword, skeleton_bow (arena enemies), clockwork_bear (boss, an original
# brass wind-up bear: no hat, no bow tie), crow (the giant island crow). Each keeps the jointed parts, pivots and sizes
# the game already animates (see game/character_models.gd and game/crow_model.gd). Model space: x right, y up, f forward.
# Material names matter: the game swaps "bone" / "brass" for its own tintable material and "eye" / "cloth" by accent.
# Run: python3 tools/blender/creatures.py   (from the project folder; needs pip packages bpy, numpy, pillow)
import math
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
import kit

OUT = os.path.join(os.path.dirname(__file__), "..", "..", "assets", "models", "creatures")
SPECS = {  # name: (kind, colour, seed)
    "bone": ("matte", (0.9, 0.84, 0.7), 11), "cloth": ("wood", (0.8, 0.8, 0.8), 12), "steel": ("metal", (0.7, 0.72, 0.76), 13),
    "wood": ("wood", (0.36, 0.22, 0.1), 14), "dark": ("polymer", (0.03, 0.03, 0.03), 15), "brass": ("metal", (0.96, 0.93, 0.86), 16),
    "plate": ("metal", (0.86, 0.7, 0.36), 17), "iron": ("metal", (0.2, 0.19, 0.2), 18), "feather": ("paint", (0.03, 0.03, 0.045), 19),
    "beak": ("polymer", (0.07, 0.07, 0.075), 20), "leg": ("polymer", (0.13, 0.12, 0.11), 21), "ring": ("polymer", (0.5, 0.5, 0.52), 22),
}


def skeleton(m, M, kind):
    B = M["bone"]
    for name, x in (("LegL", -0.09), ("LegR", 0.09)):
        m.node(name, (x, 0.9, 0))
        m.bone(B, 0.021, (x, 0.9, 0), (x, 0.5, 0.012), node=name)  # femur
        m.ball(B, (0.03, 0.03, 0.022), (x, 0.49, 0.03), node=name, u=8, v=6)  # knee cap
        m.bone(B, 0.016, (x - 0.008, 0.47, 0.004), (x - 0.004, 0.08, -0.004), node=name, knob=1.5)  # shin
        m.rod(B, 0.009, (x + 0.02, 0.46, -0.006), (x + 0.018, 0.09, -0.012), node=name)
        m.ball(B, (0.028, 0.03, 0.04), (x, 0.04, -0.035), node=name, u=8, v=6)  # heel
        for toe in (-1, 0, 1):
            m.rod(B, 0.011, (x + toe * 0.012, 0.045, 0.0), (x + toe * 0.028, 0.014, 0.13), r2=0.007, node=name, segs=6)
    for name, x in (("ArmL", -0.23), ("ArmR", 0.23)):
        m.node(name, (x, 1.5, 0))
        m.ball(B, 0.032, (x, 1.5, 0), node=name, u=8, v=6)
        m.bone(B, 0.017, (x, 1.48, 0), (x, 1.2, 0), node=name)  # upper arm
        m.rod(B, 0.011, (x - 0.011, 1.19, 0), (x - 0.008, 0.93, 0), node=name)  # forearm pair
        m.rod(B, 0.01, (x + 0.011, 1.19, 0), (x + 0.008, 0.93, 0), node=name)
        m.ball(B, (0.026, 0.02, 0.014), (x, 0.915, 0), node=name, u=8, v=6)  # wrist
        for finger in range(4):
            m.rod(B, 0.006, (x - 0.018 + finger * 0.012, 0.905, 0.004), (x - 0.022 + finger * 0.015, 0.83, 0.016), r2=0.004, node=name, segs=5)
    # pelvis, belt and loincloth
    for side in (-1, 1):
        m.ball(B, (0.085, 0.075, 0.045), (side * 0.085, 0.95, -0.01), yaw=side * 25, u=10, v=7)
        m.rod(B, 0.016, (side * 0.09, 0.9, 0.0), (0, 0.87, 0.06))
    m.ball(B, (0.05, 0.07, 0.04), (0, 0.93, -0.04), u=8, v=6)
    m.lathe(M["cloth"], [(0.155, 0.0), (0.16, 0.05)], (0, 0.9, 0), squash=0.7, segs=16)
    m.prof(M["cloth"], 0.012, [(-0.12, 0.92), (0.12, 0.92), (0.1, 0.66), (0.0, 0.6), (-0.1, 0.66)], x=0.108, bevel=0.003, across="f")
    m.prof(M["cloth"], 0.012, [(-0.11, 0.92), (0.11, 0.92), (0.09, 0.7), (-0.09, 0.7)], x=-0.108, bevel=0.003, across="f")
    m.ball(M["steel"], (0.035, 0.035, 0.012), (0, 0.925, 0.115), u=10, v=6)  # buckle
    # spine, ribs, chest
    for i in range(10):
        y = 0.99 + i * 0.056
        m.ball(B, (0.03, 0.024, 0.032), (0, y, -0.025 + 0.02 * math.sin(i * 0.5)), u=8, v=6)
    m.rod(B, 0.014, (0, 0.96, -0.02), (0, 1.56, -0.01))
    for i, (width, y) in enumerate(((0.105, 1.47), (0.135, 1.41), (0.155, 1.35), (0.16, 1.29), (0.15, 1.23), (0.13, 1.17))):
        for side in (-1, 1):
            arc = [(side * width * math.sin(t), y - 0.06 * t / math.pi, -0.03 + (0.062 + 0.004 * i) * (1 - math.cos(t))) for t in [math.pi * k / 7 for k in range(8)]]
            for p0, p1 in zip(arc, arc[1:]):
                m.rod(B, 0.0105, p0, p1, segs=6)
    m.prof(B, 0.03, [(-0.02, 1.47), (0.02, 1.47), (0.014, 1.2), (0.0, 1.16), (-0.014, 1.2)], x=0.098, bevel=0.004, across="f")
    for side in (-1, 1):
        m.rod(B, 0.012, (0, 1.5, 0.085), (side * 0.215, 1.515, 0.0))  # collar bone
        m.ball(B, (0.06, 0.085, 0.012), (side * 0.125, 1.41, -0.085), yaw=side * -18, u=10, v=7)  # shoulder blade
    # skull
    m.rod(B, 0.018, (0, 1.52, -0.01), (0, 1.62, 0.0))
    m.ball(B, (0.093, 0.1, 0.112), (0, 1.71, -0.005), u=16, v=10)
    m.ball(B, (0.07, 0.062, 0.058), (0, 1.655, 0.062), u=12, v=8)
    m.rod(B, 0.015, (-0.072, 1.73, 0.085), (0.072, 1.73, 0.085))  # brow
    for side in (-1, 1):
        m.ball(M["dark"], (0.03, 0.032, 0.022), (side * 0.04, 1.692, 0.098), u=10, v=7)
        m.ball(M["eye"], (0.016, 0.017, 0.012), (side * 0.04, 1.692, 0.112), u=8, v=6)
        m.ball(B, (0.022, 0.03, 0.03), (side * 0.07, 1.655, 0.07), u=8, v=6)  # cheek bone
    m.prof(M["dark"], 0.012, [(-0.012, 1.632), (0.012, 1.632), (0.0, 1.668)], x=0.118, bevel=0.002, across="f")
    for tooth in range(7):
        x = -0.036 + tooth * 0.012
        m.box(B, (0.01, 0.018, 0.012), (x, 1.598, 0.108 - abs(x) * 0.35), bevel=0.002)
        m.box(B, (0.009, 0.016, 0.011), (x, 1.578, 0.102 - abs(x) * 0.35), bevel=0.002)
    m.prof(B, 0.1, [(0.0, 1.575), (0.105, 1.575), (0.1, 1.545), (0.04, 1.54), (-0.03, 1.6)], bevel=0.012)  # jaw
    if kind == "sword":
        x = 0.23
        m.rod(M["wood"], 0.017, (x, 0.95, 0), (x, 0.83, 0), node="ArmR")
        m.ball(M["steel"], 0.024, (x, 0.955, 0), node="ArmR", u=8, v=6)
        m.box(M["steel"], (0.2, 0.028, 0.045), (x, 0.815, 0), bevel=0.008, node="ArmR")
        m.prof(M["steel"], 0.012, [(x - 0.028, 0.8), (x + 0.028, 0.8), (x + 0.024, 0.14), (x, 0.04), (x - 0.024, 0.14)], x=0.0, bevel=0.004, node="ArmR", across="f")
        m.rod(M["dark"], 0.004, (x, 0.79, 0.007), (x, 0.2, 0.007), node="ArmR", segs=4)  # fuller
    else:
        bx, by, bf = -0.23, 1.45, 0.6
        m.rod(M["wood"], 0.021, (bx, by - 0.07, bf), (bx, by + 0.07, bf))
        curve = [(0.07, 0.0), (0.2, -0.02), (0.33, -0.06), (0.45, -0.115), (0.5, -0.135)]
        for up in (-1, 1):
            for i, ((y0, f0), (y1, f1)) in enumerate(zip(curve, curve[1:])):
                m.rod(M["wood"], 0.017 - i * 0.0025, (bx, by + up * y0, bf + f0), (bx, by + up * y1, bf + f1), r2=0.0145 - i * 0.0025)
        m.rod(M["bone"], 0.003, (bx, by - 0.5, bf - 0.135), (bx, by + 0.5, bf - 0.135), segs=4)


def clockwork_bear(m, M):
    R, P, I = M["brass"], M["plate"], M["iron"]
    m.lathe(R, [(0.27, 0.72), (0.38, 0.8), (0.43, 1.0), (0.44, 1.2), (0.41, 1.4), (0.3, 1.55), (0.18, 1.6)], (0, 0, 0), squash=0.68, segs=28)
    m.ball(P, (0.3, 0.28, 0.06), (0, 1.12, 0.27), u=20, v=10)  # belly plate
    for y, r in ((0.8, 0.39), (1.5, 0.345)):
        m.lathe(I, [(r, y - 0.035), (r + 0.02, y - 0.02), (r + 0.02, y + 0.02), (r, y + 0.035)], (0, 0, 0), squash=0.68, segs=28)
        for k in range(14):
            a = 2 * math.pi * k / 14
            m.ball(P, 0.022, ((r + 0.02) * math.cos(a), y, (r + 0.02) * 0.68 * math.sin(a)), u=6, v=4)
    for k in range(10):  # gear on the belly
        a = 2 * math.pi * k / 10
        m.box(I, (0.045, 0.045, 0.03), (0.17 * math.cos(a), 1.12 + 0.17 * math.sin(a), 0.315), bevel=0.006)
    m.lathe(I, [(0.15, 0.3), (0.16, 0.335)], (0, 1.12, 0), segs=20, axis="f")
    m.lathe(P, [(0.06, 0.33), (0.05, 0.36)], (0, 1.12, 0), segs=12, axis="f")
    for side in (-1, 1):
        m.rod(I, 0.03, (side * 0.2, 1.52, -0.2), (side * 0.3, 0.85, -0.25), segs=10)  # back pipes
    m.lathe(I, [(0.2, 1.5), (0.21, 1.56), (0.19, 1.6)], (0, 0, 0), segs=20)  # collar
    m.ball(R, (0.3, 0.29, 0.29), (0, 1.74, 0), u=24, v=14)
    m.ball(P, (0.1, 0.03, 0.1), (0, 2.02, 0), u=12, v=6)  # top plate with a bolt
    m.ball(I, 0.03, (0, 2.05, 0), u=8, v=5)
    for side in (-1, 1):
        m.ball(R, (0.11, 0.11, 0.05), (side * 0.22, 1.96, 0), u=14, v=8)
        m.ball(I, (0.065, 0.065, 0.03), (side * 0.22, 1.96, 0.035), u=12, v=6)
        m.lathe(I, [(0.062, 0.235), (0.066, 0.275)], (side * 0.12, 1.8, 0), segs=14, axis="f")  # eye rims
        m.ball(M["eye"], (0.046, 0.046, 0.025), (side * 0.12, 1.8, 0.268), u=12, v=6)
        m.ball(I, 0.018, (side * 0.26, 1.66, 0.14), u=6, v=4)  # jaw bolts
    m.ball(P, (0.125, 0.095, 0.12), (0, 1.66, 0.28), u=16, v=10)  # snout
    m.ball(I, (0.045, 0.032, 0.03), (0, 1.71, 0.39), u=10, v=6)
    m.rod(I, 0.009, (-0.075, 1.625, 0.37), (0.075, 1.625, 0.37), segs=6)
    for k in range(5):
        m.rod(I, 0.006, (-0.05 + k * 0.025, 1.625, 0.375), (-0.05 + k * 0.025, 1.59, 0.36), segs=5)  # mouth grille
    m.node("Key", (0, 1.25, -0.3))
    m.rod(I, 0.028, (0, 1.25, -0.28), (0, 1.25, -0.5), node="Key", segs=10)
    for side in (-1, 1):
        m.lathe(P, [(0.085, -0.52), (0.09, -0.5), (0.085, -0.48)], (side * 0.095, 1.25, 0), node="Key", segs=18, axis="f")
        m.lathe(I, [(0.04, -0.525), (0.04, -0.475)], (side * 0.095, 1.25, 0), node="Key", segs=12, axis="f")
    m.box(P, (0.07, 0.07, 0.04), (0, 1.25, -0.5), bevel=0.01, node="Key")
    for name, x in (("LegL", -0.22), ("LegR", 0.22)):
        m.node(name, (x, 0.8, 0))
        m.ball(R, (0.17, 0.24, 0.19), (x, 0.62, 0), node=name, u=16, v=10)
        m.cylx(I, 0.1, x - 0.16, x + 0.16, 0.0, 0.4, segs=16, bevel=0.01, node=name)
        m.rod(R, 0.13, (x, 0.4, 0), (x, 0.1, 0.0), r2=0.16, node=name, segs=16)
        m.prof(I, 0.32, [(-0.21, 0.0), (0.26, 0.0), (0.28, 0.06), (0.1, 0.14), (-0.21, 0.12)], x=x, bevel=0.02, node=name)
        for toe in (-1, 0, 1):
            m.rod(P, 0.03, (x + toe * 0.1, 0.05, 0.24), (x + toe * 0.11, 0.02, 0.33), r2=0.006, node=name, segs=6)
    for name, x in (("ArmL", -0.56), ("ArmR", 0.56)):
        m.node(name, (x, 1.5, 0))
        m.ball(I, 0.165, (x, 1.5, 0), node=name, u=16, v=10)
        m.rod(R, 0.125, (x, 1.45, 0), (x, 1.12, 0), r2=0.11, node=name, segs=16)
        m.cylx(I, 0.095, x - 0.13, x + 0.13, 0.0, 1.08, segs=14, bevel=0.01, node=name)
        m.rod(R, 0.105, (x, 1.06, 0), (x, 0.8, 0.01), r2=0.13, node=name, segs=16)
        m.ball(R, (0.14, 0.12, 0.15), (x, 0.72, 0.02), node=name, u=14, v=9)
        for claw in (-1, 0, 1):
            m.rod(I, 0.03, (x + claw * 0.07, 0.66, 0.12), (x + claw * 0.08, 0.56, 0.2), r2=0.005, node=name, segs=6)


def crow(m, M):
    F, K = M["feather"], M["beak"]
    for x in (-0.4, 0.4):  # legs stay on the ground while the body bobs
        m.ball(F, (0.24, 0.4, 0.28), (x, 1.62, -0.1), node="Legs", u=12, v=8)
        m.rod(M["leg"], 0.075, (x, 1.3, -0.1), (x, 0.14, -0.08), r2=0.06, node="Legs", segs=10)
        m.ball(M["leg"], 0.1, (x, 0.12, -0.08), node="Legs", u=10, v=6)
        for toe, (dx, df) in enumerate(((-0.22, 0.42), (0.0, 0.52), (0.22, 0.42), (0.0, -0.34))):
            m.rod(M["leg"], 0.055, (x, 0.1, -0.08), (x + dx, 0.05, -0.08 + df), r2=0.035, node="Legs", segs=8)
            m.rod(K, 0.035, (x + dx, 0.05, -0.08 + df), (x + dx * 1.3, 0.0, -0.08 + df * 1.3), r2=0.004, node="Legs", segs=6)
    m.node("Body")
    m.lathe(F, [(0.08, -1.75), (0.42, -1.35), (0.74, -0.7), (0.88, 0.0), (0.82, 0.5), (0.6, 0.95), (0.4, 1.25)], (0, 2.4, 0), node="Body", segs=24, squash=0.92, axis="f")
    for k in range(4):  # neck up to the head
        t = k / 3.0
        m.ball(F, 0.55 - 0.08 * t, (0, 2.62 + 0.55 * t, 0.75 + 0.3 * t), node="Body", u=16, v=10)
    for row in range(3):  # back feathers lying over each other
        for k in range(7):
            m.ball(F, (0.17, 0.035, 0.34), ((k - 3) * 0.21, 3.12 - row * 0.12 - abs(k - 3) * 0.085, -0.25 - row * 0.5), node="Body", pitch=-8, u=10, v=5)
    for k in range(7):  # tail fan
        m.ball(F, (0.15, 0.03, 0.8), ((k - 3) * 0.2, 2.3 + 0.02 * abs(k - 3), -2.05 + 0.05 * abs(k - 3)), node="Body", yaw=(k - 3) * 9.0, pitch=10, u=10, v=5)
    m.node("Head", (0, 3.3, 1.1), "Body")
    m.ball(F, (0.52, 0.5, 0.56), (0, 3.3, 1.1), node="Head", u=20, v=12)
    m.ball(F, (0.3, 0.16, 0.3), (0, 3.36, 1.52), node="Head", u=12, v=6)  # bristles over the beak
    m.lathe(K, [(0.21, 1.45), (0.19, 1.75), (0.13, 2.1), (0.05, 2.38), (0.012, 2.48)], (0, 3.26, 0), node="Head", segs=14, squash=0.8, axis="f")
    m.lathe(K, [(0.17, 1.45), (0.13, 1.8), (0.06, 2.2), (0.012, 2.36)], (0, 3.15, 0), node="Head", segs=12, squash=0.55, axis="f")
    for side in (-1, 1):
        m.ball(M["ring"], (0.035, 0.105, 0.105), (side * 0.445, 3.42, 1.42), node="Head", u=12, v=8)
        m.ball(M["eye"], (0.04, 0.085, 0.085), (side * 0.46, 3.42, 1.42), node="Head", u=12, v=8)
    for name, side in (("WingL", -1), ("WingR", 1)):
        m.node(name, (side * 0.95, 2.9, -0.1), "Body")
        m.rod(F, 0.16, (side * 0.9, 2.9, 0.1), (side * 2.4, 2.9, 0.25), r2=0.11, node=name, segs=10)  # arm
        m.rod(F, 0.11, (side * 2.4, 2.9, 0.25), (side * 3.5, 2.9, 0.0), r2=0.05, node=name, segs=10)
        m.ball(F, (0.95, 0.07, 0.42), (side * 1.75, 2.93, -0.05), node=name, u=14, v=6)  # coverts
        for k in range(8):  # inner flight feathers point back
            m.ball(F, (0.17, 0.028, 0.62 + 0.03 * k), (side * (1.0 + k * 0.24), 2.88, -0.62 - 0.02 * k), node=name, yaw=side * -(2 + k * 2.0), u=10, v=5)
        for k in range(7):  # outer flight feathers fan out to the tip
            m.ball(F, (0.15, 0.025, 0.72 - 0.04 * k), (side * (2.9 + k * 0.2), 2.87, -0.5 + 0.06 * k), node=name, yaw=side * -(22 + k * 10.0), u=10, v=5)


if __name__ == "__main__":
    import bpy
    bpy.ops.wm.read_factory_settings(use_empty=True)
    textures = os.path.join(OUT, "textures")
    M = {name: kit.material(name, kit.make_textures(textures, name, kind, color, seed)) for name, (kind, color, seed) in SPECS.items()}
    M["eye"] = kit.material("eye", None, (0.01, 0.01, 0.012))
    jobs = {"skeleton_sword": lambda m: skeleton(m, M, "sword"), "skeleton_bow": lambda m: skeleton(m, M, "bow"),
        "clockwork_bear": lambda m: clockwork_bear(m, M), "crow": lambda m: crow(m, M)}
    for name, build in jobs.items():
        model = kit.Model(name, uv_scale=2.0 if name != "crow" else 0.8)
        build(model)
        print("%s: %d triangles" % (name, model.export(OUT)))
