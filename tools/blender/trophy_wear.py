# Purpose: developer-time script. Models the head pieces of the boss TROPHIES (polish1 E4, item 131): one crown per
# Aurelind region boss, worn over any outfit (data/trophies.json), and the Spectral Circlet of the phantoms' set.
# Same space as tools/blender/wear.py: origin = the character's head anchor (brow about 0.15 m above it, skull top
# 0.23 m), front = +f. The mantles that go with the crowns are sewn by tools/tailor.py (data/wear.json).
# Output: assets/models/fantasy/wear/trophy_<id>.gltf, loaded by game/rigged_body.gd through game/fantasy_models.gd.
# Run: python3 tools/blender/trophy_wear.py   (from the project folder; needs pip packages bpy, numpy, pillow)
import math
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
import fantasy_kit as fk
from fantasy_kit import K

HEAD = (0, 0, 0.02)  # the skull's middle from the anchor, seen from above
LONG = 1.08  # a head is longer front to back than side to side
R = 0.113  # the band's radius at brow height


def ring_at(a, r=R, y=0.0):
    """A point on the band's ring: a = bearing (0 = straight ahead, turning to the left)."""
    return (r * math.sin(a), y, HEAD[2] + r * LONG * math.cos(a))


def band(m, mat, y0, y1, r=R, segs=16):
    m.lathe(mat, [(r - 0.002, y0), (r + 0.004, y0 + 0.004), (r + 0.004, y1 - 0.004), (r - 0.002, y1)], HEAD, segs=segs, squash=LONG)


def straw_crown(m):
    straw = (0.9, 0.74, 0.36)
    band(m, K("thatch", straw), 0.146, 0.193)
    m.lathe(K("cloth", (0.62, 0.16, 0.12)), [(R + 0.005, 0.158), (R + 0.006, 0.17)], HEAD, segs=16, squash=LONG)  # red ribbon
    for i in range(9):  # wheat ears standing up round the band, leaning out
        a = 2 * math.pi * i / 9
        low = ring_at(a, R + 0.004, 0.188)
        tip = ring_at(a, R + 0.04, 0.288 + (0.03 if i == 0 else 0.0))
        m.rod(K("thatch", (0.82, 0.66, 0.3)), 0.004, low, tip)
        for k in range(4):  # the grain head: little seeds stacked up the top of the stalk
            t = 0.55 + 0.11 * k
            p = tuple(low[j] + (tip[j] - low[j]) * t for j in range(3))
            m.ball(K("thatch", (0.95, 0.78, 0.38)), (0.009, 0.014, 0.009), p, u=6, v=4)
    for side in (-1, 1):  # twine knot at the front
        m.ball(K("leather", (0.55, 0.4, 0.22)), 0.012, (side * 0.014, 0.164, HEAD[2] + R * LONG + 0.006), u=6, v=4)


def root_circlet(m):
    bark = (0.36, 0.26, 0.16)
    for k in range(3):  # three roots twisting round each other
        rings = []
        for i in range(13):
            a = 2 * math.pi * i / 12
            p = ring_at(a, R + 0.006, 0.172 + 0.012 * math.sin(a * 3 + k * 2.1))
            rings.append((p[0], p[1], p[2], 0.007, 0.007))
        m.loft(K("bark", tuple(v * (0.9 + 0.08 * k) for v in bark)), rings, segs=6, steps=2)
    for side in (-1, 1):  # two root branches growing up at the temples like small antlers
        base = ring_at(side * 1.2, R + 0.006, 0.19)
        mid = (base[0] + side * 0.04, 0.27, base[2] - 0.01)
        top = (base[0] + side * 0.03, 0.34, base[2] - 0.04)
        m.loft(K("bark", bark), [(base[0], base[1], base[2], 0.01, 0.01), (mid[0], mid[1], mid[2], 0.007, 0.007), (top[0], top[1], top[2], 0.003, 0.003)], segs=6, steps=2)
        m.rod(K("bark", bark), 0.004, mid, (mid[0] + side * 0.04, mid[1] + 0.04, mid[2] + 0.01), r2=0.002)
    for i in range(10):  # leaves along the band
        a = 2 * math.pi * (i + 0.5) / 10
        p = ring_at(a, R + 0.016, 0.2)
        m.ball(K("leaf", (0.3, 0.5, 0.18) if i % 2 else (0.42, 0.58, 0.22)), (0.016, 0.004, 0.026), p, yaw=math.degrees(a), pitch=-35, u=6, v=4)


def coral_crown(m):
    coral = (0.92, 0.5, 0.42)
    band(m, K("stone", (0.85, 0.82, 0.74)), 0.158, 0.19)
    for i in range(7):  # branching coral points
        a = 2 * math.pi * i / 7
        low = ring_at(a, R + 0.003, 0.188)
        top = ring_at(a, R + 0.018, 0.27 + (0.04 if i == 0 else 0.0))
        m.rod(K("bone", coral), 0.006, low, top, r2=0.004)
        for side in (-1, 1):
            m.rod(K("bone", coral), 0.004, tuple((low[j] + top[j]) / 2 for j in range(3)), ring_at(a + side * 0.18, R + 0.03, 0.25), r2=0.002)
    for i in range(7):  # shells and pearls between them
        a = 2 * math.pi * (i + 0.5) / 7
        m.ball(K("bone", (0.95, 0.9, 0.82)), (0.012, 0.01, 0.008), ring_at(a, R + 0.008, 0.176), yaw=math.degrees(a), u=8, v=5)
        m.ball(fk.GLOW, 0.006, ring_at(a, R + 0.012, 0.19), u=6, v=4)


def glass_diadem(m):
    bronze = (0.7, 0.5, 0.26)
    band(m, K("metal", bronze), 0.165, 0.185)
    for i, (a, h) in enumerate(((0.0, 0.1), (0.42, 0.06), (-0.42, 0.06), (0.85, 0.04), (-0.85, 0.04), (1.3, 0.03), (-1.3, 0.03))):
        low = ring_at(a, R + 0.006, 0.183)
        m.lathe(K("ice", (0.95, 0.72, 0.36)), [(0.014 if i == 0 else 0.01, 0.0), (0.008 if i == 0 else 0.006, h * 0.6), (0.0, h)], (low[0], low[1], low[2]), segs=4)
    m.ball(fk.GLOW, 0.008, ring_at(0.0, R + 0.012, 0.176), u=6, v=4)  # the sun stone at the front


def rime_crown(m):
    band(m, K("ice", (0.8, 0.9, 1.0)), 0.158, 0.19)
    for i in range(12):  # ice spikes, tall at the front, short behind
        a = 2 * math.pi * i / 12
        h = 0.05 + 0.07 * (0.5 + 0.5 * math.cos(a))
        low = ring_at(a, R + 0.002, 0.186)
        m.lathe(K("ice", (0.86, 0.94, 1.0) if i % 2 else (0.74, 0.86, 0.98)), [(0.011, 0.0), (0.006, h * 0.5), (0.0, h)], (low[0], low[1], low[2]), segs=5)


def wyrm_horns(m):
    scale = (0.3, 0.12, 0.1)
    band(m, K("scale", scale), 0.16, 0.19)
    for side in (-1, 1):  # two horns sweeping back from the temples
        start = ring_at(side * 1.15, R + 0.004, 0.19)
        path = [start, (start[0] + side * 0.03, 0.26, start[2] - 0.03), (start[0] + side * 0.045, 0.3, start[2] - 0.1), (start[0] + side * 0.04, 0.29, start[2] - 0.17)]
        sizes = [0.022, 0.016, 0.009, 0.002]
        m.loft(K("bone", (0.2, 0.16, 0.15)), [(p[0], p[1], p[2], s, s) for p, s in zip(path, sizes)], segs=8, steps=3)
    for i in range(5):  # embers glowing in the band's cracks
        a = (i - 2) * 0.35
        m.box(fk.GLOW, (0.012, 0.004, 0.003), ring_at(a, R + 0.0055, 0.175), bevel=0.0)


def roc_crest(m):
    band(m, K("leather", (0.22, 0.22, 0.3)), 0.16, 0.185)
    for i in range(7):  # a fan of storm feathers rising over the crown and back
        t = (i - 3) / 3.0
        root = (t * 0.05, 0.2, HEAD[2] - 0.04)
        tip = (t * 0.12, 0.36 - abs(t) * 0.06, HEAD[2] - 0.16 - abs(t) * 0.02)
        m.loft(K("feather", (0.34, 0.36, 0.52) if i % 2 else (0.5, 0.52, 0.66)), [(root[0], root[1], root[2], 0.012, 0.003), ((root[0] + tip[0]) / 2, (root[1] + tip[1]) / 2 + 0.02, (root[2] + tip[2]) / 2, 0.022, 0.003), (tip[0], tip[1], tip[2], 0.004, 0.002)], segs=6, steps=2)
    m.ball(fk.GLOW, 0.009, ring_at(0.0, R + 0.01, 0.173), u=6, v=4)  # a storm stone at the front


def pallid_crown(m):
    bone = (0.88, 0.86, 0.8)
    band(m, K("bone", bone), 0.158, 0.2)
    for i in range(8):  # tall points like finger bones
        a = 2 * math.pi * i / 8
        h = 0.08 if i % 2 == 0 else 0.055
        low = ring_at(a, R + 0.002, 0.198)
        top = ring_at(a, R + 0.012, 0.198 + h)
        m.bone(K("bone", bone), 0.005, low, top, knob=1.6)
    m.ball(K("metal", (0.25, 0.25, 0.28)), (0.016, 0.02, 0.008), ring_at(0.0, R + 0.008, 0.18), u=8, v=6)  # the hollow eye set at the front
    m.ball(fk.GLOW, 0.006, ring_at(0.0, R + 0.014, 0.18), u=6, v=4)


def spectral_circlet(m):
    band(m, K("metal", (0.6, 0.8, 1.0)), 0.168, 0.18)
    for a in (-0.35, 0.0, 0.35):  # three slim points over the brow
        low = ring_at(a, R + 0.005, 0.18)
        m.lathe(K("metal", (0.6, 0.8, 1.0)), [(0.007, 0.0), (0.0, 0.06 if a == 0.0 else 0.035)], (low[0], low[1], low[2]), segs=4)
    m.ball(fk.GLOW, 0.008, ring_at(0.0, R + 0.01, 0.174), u=6, v=4)


PIECES = (("straw_crown", straw_crown), ("root_circlet", root_circlet), ("coral_crown", coral_crown), ("glass_diadem", glass_diadem),
    ("rime_crown", rime_crown), ("wyrm_horns", wyrm_horns), ("roc_crest", roc_crest), ("pallid_crown", pallid_crown), ("spectral_circlet", spectral_circlet))


def build_all():
    fk.init()
    mk = fk.Maker()
    os.makedirs(os.path.join(fk.OUT, "wear"), exist_ok=True)
    for name, build in PIECES:
        mk.model("wear/trophy_" + name, build, solid=False, uv=2.0)


if __name__ == "__main__":
    build_all()
