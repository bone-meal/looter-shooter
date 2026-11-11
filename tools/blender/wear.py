# Purpose: developer-time script. Models the rigid things the rigged characters wear on their heads (round 4, item
# 28): straw hat, kettle helmet, feathered cap, pointed hat, cook's cap. Origin = the character's head anchor
# (data/characters.json bodies.head_anchor: brow level is about 0.15 m above it, the skull's top 0.23 m), front = +f.
# Output: assets/models/fantasy/wear/<id>.gltf, loaded by game/rigged_body.gd through game/fantasy_models.gd (so the
# parts take the fantasy props' materials). Not written into data/fantasy/props.json: nobody bumps into a hat.
# Run: python3 tools/blender/wear.py   (from the project folder; needs pip packages bpy, numpy, pillow)
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
import fantasy_kit as fk
from fantasy_kit import K, c

HEAD = (0, 0, 0.02)  # the skull's middle from the anchor, seen from above
LONG = 1.08  # a head is longer front to back than side to side


def straw_hat(m):
    straw = (0.86, 0.72, 0.38)
    m.lathe(K("thatch", straw), [(0.104, 0.166), (0.3, 0.146), (0.305, 0.154), (0.104, 0.182)], HEAD, segs=14, squash=LONG)
    m.lathe(K("thatch", tuple(v * 0.94 for v in straw)), [(0.108, 0.166), (0.112, 0.215), (0.094, 0.262), (0.0, 0.274)], HEAD, segs=12, squash=LONG)
    m.lathe(K("cloth", (0.45, 0.16, 0.14)), [(0.113, 0.18), (0.116, 0.205)], HEAD, segs=12, squash=LONG)


def kettle_helmet(m):
    steel = (0.42, 0.44, 0.48)
    m.lathe(K("metal", steel), [(0.108, 0.125), (0.118, 0.19), (0.102, 0.248), (0.055, 0.276), (0.0, 0.283)], HEAD, segs=12, squash=LONG)
    m.lathe(K("metal", tuple(v * 0.85 for v in steel)), [(0.112, 0.15), (0.205, 0.108), (0.21, 0.116), (0.119, 0.166)], HEAD, segs=14, squash=LONG)
    m.box(K("metal", tuple(v * 0.75 for v in steel)), (0.016, 0.02, 0.24), (0, 0.276, 0.02), bevel=0.0)  # a low crest
    m.box(K("leather", (0.25, 0.16, 0.1)), (0.02, 0.2, 0.012), (0.1, 0.05, 0.03), bevel=0.0)  # chin strap, one side
    m.box(K("leather", (0.25, 0.16, 0.1)), (0.02, 0.2, 0.012), (-0.1, 0.05, 0.03), bevel=0.0)


def cap(m):
    cloth = (0.5, 0.13, 0.15)
    m.lathe(K("cloth", cloth), [(0.104, 0.158), (0.15, 0.192), (0.142, 0.226), (0.07, 0.25), (0.0, 0.253)], (0.012, 0, 0.02), segs=12, squash=LONG)
    m.lathe(K("cloth", tuple(v * 0.7 for v in cloth)), [(0.106, 0.15), (0.11, 0.172)], HEAD, segs=12, squash=LONG)
    m.loft(c((0.93, 0.9, 0.82)), [(0.1, 0.19, -0.01, 0.006, 0.012), (0.125, 0.25, -0.05, 0.008, 0.034), (0.15, 0.31, -0.1, 0.006, 0.026), (0.165, 0.345, -0.14, 0.002, 0.006)], segs=6, steps=2)  # a feather
    m.ball(K("metal", (0.85, 0.7, 0.3)), 0.018, (0.105, 0.185, 0.0), u=6, v=4)


def pointed_hat(m):
    cloth = (0.15, 0.17, 0.36)
    m.lathe(K("cloth", cloth), [(0.104, 0.166), (0.25, 0.148), (0.255, 0.156), (0.104, 0.18)], HEAD, segs=14, squash=LONG)
    m.loft(K("cloth", cloth), [(0, 0.17, 0.02, 0.11, 0.118), (0, 0.3, 0.0, 0.076, 0.08), (0.012, 0.43, -0.05, 0.04, 0.04), (0.03, 0.52, -0.12, 0.007, 0.007)], segs=10, steps=3)
    m.lathe(K("leather", (0.3, 0.2, 0.12)), [(0.112, 0.18), (0.113, 0.208)], HEAD, segs=12, squash=LONG)
    m.box(K("metal", (0.85, 0.7, 0.3)), (0.045, 0.04, 0.012), (0, 0.194, 0.143), bevel=0.0)


def cook_cap(m):
    white = (0.93, 0.92, 0.88)
    m.lathe(K("cloth", white), [(0.104, 0.158), (0.108, 0.2), (0.14, 0.24), (0.125, 0.29), (0.0, 0.305)], HEAD, segs=12, squash=LONG)
    m.lathe(K("cloth", tuple(v * 0.9 for v in white)), [(0.109, 0.156), (0.111, 0.196)], HEAD, segs=12, squash=LONG)


def build_all():
    fk.init()
    mk = fk.Maker()
    os.makedirs(os.path.join(fk.OUT, "wear"), exist_ok=True)
    for name, build in (("straw_hat", straw_hat), ("kettle_helmet", kettle_helmet), ("cap", cap), ("pointed_hat", pointed_hat), ("cook_cap", cook_cap)):
        mk.model("wear/" + name, build, solid=False, uv=2.0)


if __name__ == "__main__":
    build_all()
