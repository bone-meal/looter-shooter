# Purpose: developer-time script. Models the shapes the chase guns' effects are drawn with (diary/DESIGN_UNIQUES.md,
# director 2026-11-15 "finish modeling": no more plain balls, cones and boxes) into assets/models/fx/<id>.gltf. The game
# gives them its own glowing / see-through materials (game/fx_kit.gd), so the colours here are only for previews.
#   flame_tongue: one licking flame ~1 m tall, curled and tapered, with a smaller bright core tongue inside (node "Core").
#   gas_cloud: a lumpy, puffed cloud ~1 m across (radius about 1), flattened at the bottom.
#   vortex: a whirlpool funnel ~1 m across: a sunken spiral surface with raised spiral ridges of foam (node "Foam").
#   shard: a long crystal splinter ~0.3 m (ice and ember shards of Split Decision).
#   egg_shell: half of a cracked egg shell, radius ~1 (Golden Goose's hatch), jagged rim.
#   x_mark: a painted X of two rough brush strokes ~1.6 m long, lying flat (Treasure Map).
#   dirt_mound: a small heap of dug-up earth ~0.8 m across.
# Run: python3 tools/blender/fx_models.py [ids]   (from the project folder)
import math
import os
import random
import sys

sys.path.insert(0, os.path.dirname(__file__))
import kit
import weapons

OUT = os.path.join(os.path.dirname(weapons.OUT), "fx")


def flame_tongue(m, M):
    rings = []
    for k in range(9):  # rises, curls and thins to a point
        t = k / 8.0
        r = 0.16 * (1.0 - t) ** 0.8 + 0.006
        rings.append((0.08 * math.sin(t * 3.4), t * 1.0, 0.05 * math.sin(t * 5.0 + 1.0), r, r * 0.75))
    m.loft(M["flame"], rings, segs=10, steps=2)
    m.node("Core", (0.0, 0.0, 0.0))
    core = []
    for k in range(7):
        t = k / 6.0
        r = 0.08 * (1.0 - t) ** 0.9 + 0.004
        core.append((0.05 * math.sin(t * 3.0), t * 0.62, 0.03 * math.sin(t * 4.0 + 1.0), r, r * 0.8))
    m.loft(M["core"], core, node="Core", segs=8, steps=2)


def gas_cloud(m, M):
    rnd = random.Random(7)
    m.ball(M["gas"], (0.9, 0.55, 0.85), (0.0, 0.0, 0.0), u=18, v=10)
    for _ in range(9):  # puffs round it, a few on top
        a = rnd.random() * math.tau
        r = 0.45 + rnd.random() * 0.3
        up = rnd.random() * 0.4
        m.ball(M["gas"], r * 0.75, (math.cos(a) * 0.65, up, math.sin(a) * 0.65), u=12, v=8)


def vortex(m, M):
    rings = 10
    segs = 24
    # the funnel: a lathe sinking toward the middle
    prof = []
    for k in range(rings + 1):
        t = k / rings
        prof.append((max(0.02, 1.0 - t), -0.35 * t * t))
    m.lathe(M["water"], prof, (0.0, 0.0, 0.0), segs=segs)
    m.node("Foam", (0.0, 0.0, 0.0))
    for arm in range(4):  # spiral foam ridges
        pts = []
        for k in range(14):
            t = k / 13.0
            a = arm * math.pi * 0.5 + t * math.pi * 1.6
            r = 1.0 - t * 0.85
            pts.append((math.cos(a) * r, -0.35 * t * t * 0.98 + 0.02, math.sin(a) * r))
        for a, b in zip(pts, pts[1:]):
            m.rod(M["foam"], 0.02, a, b, segs=5, node="Foam")


def shard(m, M):
    # an elongated, slightly twisted octahedron along f
    m.loft(M["ice"], [(0.0, 0.0, -0.15, 0.002, 0.002), (0.01, 0.0, -0.04, 0.035, 0.022), (-0.005, 0.004, 0.06, 0.028, 0.02), (0.0, 0.0, 0.16, 0.002, 0.002)], segs=5, steps=1)


def egg_shell(m, M):
    prof = [(0.001, -1.0), (0.45, -0.9), (0.7, -0.5), (0.75, 0.0), (0.72, 0.02)]
    m.lathe(M["gold"], prof, (0.0, 0.0, 0.0), segs=16)
    rnd = random.Random(3)
    for k in range(8):  # jagged teeth on the rim
        a = k / 8.0 * math.tau
        h = 0.08 + rnd.random() * 0.12
        x, f = math.cos(a) * 0.72, math.sin(a) * 0.72
        m.prof(M["gold"], 0.025, [(f - 0.15, 0.0), (f + 0.15, 0.0), (f, h)], x=x, bevel=0.0)


def x_mark(m, M):
    rnd = random.Random(11)
    for turn in (1.0, -1.0):  # two brush strokes, ragged
        pts = []
        for k in range(9):
            t = k / 8.0 - 0.5
            pts.append((t * 1.6 * 0.707, 0.012 + rnd.random() * 0.004, t * 1.6 * 0.707 * turn))
        for (a, b) in zip(pts, pts[1:]):
            w = 0.09 + rnd.random() * 0.05
            m.loft(M["paint"], [(a[0], a[1], a[2], w, 0.012), (b[0], b[1], b[2], w * (0.85 + rnd.random() * 0.3), 0.012)], segs=6, steps=1, flat=True)


def dirt_mound(m, M):
    rnd = random.Random(5)
    m.ball(M["dirt"], (0.4, 0.16, 0.34), (0.0, 0.0, 0.0), u=14, v=8)
    for _ in range(7):
        a = rnd.random() * math.tau
        m.ball(M["dirt"], 0.07 + rnd.random() * 0.06, (math.cos(a) * 0.38, 0.02, math.sin(a) * 0.32), u=8, v=6)  # clods


MODELS = {"flame_tongue": flame_tongue, "gas_cloud": gas_cloud, "vortex": vortex, "shard": shard, "egg_shell": egg_shell, "x_mark": x_mark, "dirt_mound": dirt_mound}
COLORS = {"flame": (1.0, 0.45, 0.1), "core": (1.0, 0.9, 0.5), "gas": (0.45, 0.62, 0.2), "water": (0.08, 0.3, 0.45), "foam": (0.85, 0.95, 1.0),
          "ice": (0.7, 0.9, 1.0), "gold": (0.95, 0.75, 0.2), "paint": (0.75, 0.08, 0.06), "dirt": (0.36, 0.26, 0.16)}

if __name__ == "__main__":
    import bpy
    bpy.ops.wm.read_factory_settings(use_empty=True)
    M = {name: kit.material(name, None, color) for name, color in COLORS.items()}
    for model_id, build in MODELS.items():
        if len(sys.argv) > 1 and model_id not in sys.argv[1:]:
            continue
        model = kit.Model(model_id)
        build(model, M)
        print("%s: %d triangles" % (model_id, model.export(OUT)))
