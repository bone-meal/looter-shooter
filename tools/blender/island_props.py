# Purpose: developer-time script (polish1 items 34 and 32). Models two island pieces into assets/models/fantasy/:
#   item_worm  the PINK EARTHWORM drop (it was a spinning pink box): a ribbed, S-curved worm about half a metre long
#              with its darker saddle band (game/loot_field.gd uses it for the "worm" item).
#   fire_pit   the FIRE PIT trap (it read as a random ring on the ground): a ring of rough stones round a floor of ash, a
#              stacked log pyre in the middle and three smaller charred heaps, embers ("Glow": the game lights them
#              faintly while cold, brightly while the trap runs). Built for a 6 m radius; game/traps.gd scales it to the
#              trap's radius.
# Our own designs. Run: python3 tools/blender/island_props.py
# Dependencies: bpy, tools/blender/kit.py, tools/blender/fantasy_kit.py.
import math
import os
import random
import sys

sys.path.insert(0, os.path.dirname(__file__))
import kit
import fantasy_kit as fk
from fantasy_kit import K

OUT = os.path.join(os.path.dirname(__file__), "..", "..", "assets", "models", "fantasy")


def worm(m):
    pink, band = K("paint", (0.93, 0.55, 0.6)), K("paint", (0.78, 0.36, 0.42))
    rings = []
    n = 34
    for i in range(n + 1):
        u = i / n
        x = (u - 0.5) * 0.46
        f = math.sin(u * math.pi * 2.0) * 0.07
        y = 0.04 + max(0.0, u - 0.82) * 0.5  # the head lifts a little
        taper = min(1.0, u * 6.0, (1.0 - u) * 8.0 + 0.25)
        rib = 1.0 + (0.09 if i % 2 == 0 else -0.04)
        r = 0.032 * taper * rib + 0.004
        rings.append((x, y, f, r, r))
    m.loft(pink, rings, segs=10, steps=1)
    for i in range(int(n * 0.3), int(n * 0.38) + 1):  # the saddle (clitellum): a thicker, darker band
        x, y, f, r, _ = rings[i]
        m.ball(band, (0.014, r * 1.18, r * 1.18), (x, y, f), u=10, v=6)


def fire_pit(m):
    rnd = random.Random(32)
    m.lathe(K("stone", (0.16, 0.15, 0.15)), [(0.0, 0.0), (5.6, 0.0), (5.55, 0.04), (0.0, 0.05)], (0, 0, 0), segs=40)  # ash
    m.lathe(K("stone", (0.3, 0.28, 0.26)), [(3.2, 0.051), (5.4, 0.051), (5.4, 0.055), (3.2, 0.055)], (0, 0, 0), segs=40)  # pale outer ash
    for k in range(46):  # the stone ring
        a = 2 * math.pi * (k + rnd.uniform(-0.2, 0.2)) / 46
        r = 5.75 + rnd.uniform(-0.1, 0.1)
        s = rnd.uniform(0.32, 0.5)
        grey = rnd.uniform(0.38, 0.52)
        fk.blob(m, K("rock", (grey, grey * 0.97, grey * 0.94)), (s, s * 0.7, s * 0.85), (math.cos(a) * r, s * 0.35, math.sin(a) * r), seed=k, rough=0.25, cuts=1)
    charred = K("bark", (0.12, 0.09, 0.07))

    def pyre(cx, cf, h, count, spread):
        for k in range(count):  # logs leaning in to a point (a teepee)
            a = 2 * math.pi * k / count + rnd.uniform(-0.15, 0.15)
            foot = (cx + math.cos(a) * spread, 0.05, cf + math.sin(a) * spread)
            m.rod(charred, rnd.uniform(0.09, 0.13), foot, (cx + math.cos(a) * 0.08, h, cf + math.sin(a) * 0.08), segs=7)
        for k in range(3):  # embers between them
            a = 2 * math.pi * k / 3
            fk.blob(m, K("paint", (1.0, 0.5, 0.15)), (spread * 0.35, 0.08, spread * 0.3), (cx + math.cos(a) * spread * 0.3, 0.08, cf + math.sin(a) * spread * 0.3), seed=90 + k, node="Glow", cuts=1)

    pyre(0.0, 0.0, 1.5, 8, 0.9)
    for k in range(3):
        a = 2 * math.pi * (k + 0.3) / 3
        pyre(math.cos(a) * 3.2, math.sin(a) * 3.2, 0.7, 5, 0.45)
    for k in range(9):  # loose half-burnt logs on the ash
        a = rnd.uniform(0, 2 * math.pi)
        r = rnd.uniform(1.4, 4.8)
        turn = rnd.uniform(0, math.pi)
        c = (math.cos(a) * r, 0.1, math.sin(a) * r)
        length = rnd.uniform(0.5, 0.9)
        m.rod(charred, 0.08, (c[0] - math.cos(turn) * length, 0.1, c[2] - math.sin(turn) * length), (c[0] + math.cos(turn) * length, 0.1, c[2] + math.sin(turn) * length), segs=6)


def main():
    fk.init()
    os.makedirs(OUT, exist_ok=True)
    for name, build in (("item_worm", worm), ("fire_pit", fire_pit)):
        m = kit.Model(name, uv_scale=2.0, colored=True)
        m.node("Glow", (0.0, 0.0, 0.0))
        build(m)
        print(name, m.export(OUT))


if __name__ == "__main__":
    main()
