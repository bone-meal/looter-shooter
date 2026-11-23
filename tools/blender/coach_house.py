# Purpose: developer-time script (polish1 E5, item 126). Models the COACH HOUSE that stands in every walled town: an
# open-fronted timber shed with a shingle roof, a travelling coach parked in it (body with windows and a lamp, four
# wheels, a driver's bench, its pole), a hanging sign with a painted wheel, a hay bale, a water trough and a fare board.
# Front = +f (toward the town's middle when laid "face": "in"). Footprint written to data/fantasy/props.json; the layout
# rule's station 'coach' puts the coachman in front of it (game/fantasy_places.gd).
# Run: python3 tools/blender/coach_house.py   (from the project folder; needs pip packages bpy, numpy, pillow)
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
import fantasy_kit as fk
from fantasy_kit import K

WOOD, DARK, IRON = (0.55, 0.42, 0.27), (0.3, 0.22, 0.14), (0.25, 0.25, 0.28)
PAINT = (0.42, 0.14, 0.12)  # the coach's own deep red


def wheel(m, x, f, r):
    m.cylx(K("wood", DARK), r, x - 0.05, x + 0.05, f, r, segs=16)
    m.cylx(K("metal", IRON), r * 0.25, x - 0.09, x + 0.09, f, r, segs=8)


def coach(m, f0):
    body_y = 1.0
    m.box(K("paint", PAINT), (1.5, 1.35, 2.3), (0, body_y + 0.68, f0), bevel=0.05)
    m.box(K("wood", DARK), (1.6, 0.1, 2.45), (0, body_y + 1.4, f0), bevel=0.03)  # roof edge
    m.box(K("wood", DARK), (1.4, 0.08, 2.2), (0, body_y + 1.5, f0), bevel=0.02)
    for side in (-1, 1):
        m.box(K("wood", (0.12, 0.1, 0.1)), (0.04, 0.55, 0.7), (side * 0.76, body_y + 0.95, f0), bevel=0.0)  # windows
        m.box(K("cloth", (0.85, 0.7, 0.3)), (0.03, 0.08, 0.72), (side * 0.77, body_y + 1.25, f0), bevel=0.0)  # gilt trim
    m.box(K("cloth", (0.85, 0.7, 0.3)), (1.52, 0.06, 2.32), (0, body_y + 0.12, f0), bevel=0.0)
    for side in (-1, 1):
        wheel(m, side * 0.82, f0 - 0.75, 0.55)
        wheel(m, side * 0.82, f0 + 0.8, 0.45)
    m.box(K("wood", WOOD), (1.2, 0.12, 0.6), (0, body_y + 1.1, f0 + 1.45), bevel=0.02)  # driver's bench
    m.box(K("wood", WOOD), (1.2, 0.5, 0.08), (0, body_y + 0.9, f0 + 1.72), bevel=0.01)
    m.rod(K("wood", WOOD), 0.05, (0, 0.55, f0 + 1.3), (0, 0.2, f0 + 3.4), segs=6)  # the pole, resting on the ground
    m.rod(K("metal", IRON), 0.02, (0.65, body_y + 1.5, f0 + 1.3), (0.65, body_y + 1.8, f0 + 1.3), segs=5)
    m.ball(fk.GLOW, (0.07, 0.1, 0.07), (0.65, body_y + 1.9, f0 + 1.3), u=8, v=5)  # the coach lamp


def coach_house(m):
    w, d, h = 4.6, 5.2, 3.4
    for x in (-w / 2, w / 2):
        for f in (-d / 2, d / 2 - 0.2):
            m.box(K("timber", DARK), (0.22, h, 0.22), (x, h / 2, f), bevel=0.02)
    m.box(K("wood", WOOD), (w + 0.2, h * 0.75, 0.12), (0, h * 0.375, -d / 2), bevel=0.0)  # back wall (lower part)
    for side in (-1, 1):
        m.box(K("wood", WOOD), (0.12, h * 0.6, d - 0.4), (side * w / 2, h * 0.3, -0.1), bevel=0.0)  # side boards
    for side in (-1, 1):  # the two pitched halves of the shingle roof (a profile across, run the shed's depth)
        m.prof(K("roof", (0.46, 0.33, 0.22)), d + 0.8, [(0.0, h), (side * (w / 2 + 0.5), h - 0.15), (side * (w / 2 + 0.5), h - 0.02), (0.0, h + 1.2)], across="y")
    m.box(K("timber", DARK), (0.2, 0.2, d + 0.8), (0, h + 1.15, 0), bevel=0.01)  # ridge beam
    coach(m, -0.2)
    m.box(K("timber", DARK), (0.12, 0.6, 0.12), (w / 2 + 0.3, h - 0.3, d / 2 + 0.05), bevel=0.0)  # the sign's arm
    m.box(K("timber", DARK), (0.9, 0.08, 0.08), (w / 2 + 0.7, h, d / 2 + 0.05), bevel=0.0)
    m.box(K("wood", WOOD), (0.8, 0.6, 0.06), (w / 2 + 0.75, h - 0.45, d / 2 + 0.05), bevel=0.01)
    m.cylx(K("paint", (0.85, 0.7, 0.3)), 0.2, w / 2 + 0.72, w / 2 + 0.78, d / 2 + 0.05, h - 0.45, segs=12)  # painted wheel
    m.box(K("thatch", (0.88, 0.74, 0.38)), (0.9, 0.55, 0.6), (-w / 2 - 0.7, 0.28, d / 2 - 0.4), bevel=0.04)  # hay bale
    m.box(K("wood", DARK), (1.1, 0.45, 0.5), (-w / 2 - 0.7, 0.22, d / 2 - 1.4), bevel=0.02)  # trough
    m.box(K("paint", (0.28, 0.45, 0.58)), (1.0, 0.04, 0.4), (-w / 2 - 0.7, 0.43, d / 2 - 1.4), bevel=0.0)  # its water
    m.box(K("wood", WOOD), (0.9, 1.1, 0.06), (w / 2 + 0.4, 1.3, d / 2 - 1.0), bevel=0.01)  # the fare board
    m.box(K("timber", DARK), (0.08, 1.4, 0.08), (w / 2 + 0.4, 0.7, d / 2 - 0.98), bevel=0.0)
    for k in range(4):
        m.box(K("paint", (0.2, 0.15, 0.1)), (0.6, 0.03, 0.02), (w / 2 + 0.4, 1.6 - k * 0.2, d / 2 - 0.96), bevel=0.0)


def build_all():
    fk.init()
    mk = fk.Maker()
    mk.model("coach_house", coach_house, solid=True, uv=0.5)
    mk.save()


if __name__ == "__main__":
    build_all()
