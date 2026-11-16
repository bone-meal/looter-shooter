# Purpose: developer-time tool. Builds the SWIFT SAIL of sea step 5e (director: "Swift sail needs new model") into
# assets/models/sea/swift_sail.gltf: a full-bellied sail of crimson and cream panels (stitched seams as raised strips),
# a gold boltrope round its edge, reef bands, corner rings, and on its face a painted-on emblem in gold and sky blue:
# a ring with three sweeping gusts curling out of it (the wind at your back). Unit size: 2 m wide, 2 m tall, centred,
# bellying 0.42 m towards +f (the bow); the game (game/sea_ship.gd) stretches one over each of a ship's sails while
# the Swift stage is set. Both faces are built (it is seen from the deck and from the sea).
# Run: python3 tools/blender/sea_swift_sail.py   (bpy as a module)
# Dependencies: bpy, bmesh, tools/blender/kit.py, tools/blender/fantasy_kit.py. No game code.
import math
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
import bpy  # noqa: F401
import bmesh
import kit
import fantasy_kit as fk
from fantasy_kit import K

OUT = os.path.join(os.path.dirname(__file__), "..", "..", "assets", "models", "sea")
CRIMSON = (0.72, 0.12, 0.12)
CREAM = (0.95, 0.9, 0.78)
GOLD = (0.92, 0.7, 0.22)
SKY = (0.36, 0.7, 0.95)
COLS = 8
ROWS = 10
BELLY = 0.42


def belly(x, y):
    """How far the cloth bellies out at (x, y) in -1..1: most in the middle, none at the edges."""
    return BELLY * (1.0 - x * x) * (1.0 - 0.7 * y * y) * (1.0 - 0.25 * (y + 1.0) * 0.5)


def at(x, y, out=0.0):
    """A point of the sail (kit order x, up, f), `out` metres further out than the cloth."""
    return (x, y, belly(x, y) + out)


def panel(m, col, mat):
    """One vertical cloth panel, both faces."""
    bm = bmesh.new()
    x0 = -1.0 + 2.0 * col / COLS
    x1 = x0 + 2.0 / COLS
    for face_out, flip in ((0.0, False), (-0.012, True)):
        grid = []
        for r in range(ROWS + 1):
            y = -1.0 + 2.0 * r / ROWS
            row = []
            for c in range(3):
                x = x0 + (x1 - x0) * c / 2
                p = at(x, y, face_out)
                row.append(bm.verts.new((p[0], p[2], p[1])))
            grid.append(row)
        for r in range(ROWS):
            for c in range(2):
                quad = (grid[r][c], grid[r][c + 1], grid[r + 1][c + 1], grid[r + 1][c])
                bm.faces.new(quad[::-1] if flip else quad)
    m._add(bm, mat, "Body", 0)


def seam_line(m, mat, points, r=0.012):
    for p0, p1 in zip(points, points[1:]):
        m.rod(mat, r, p0, p1, segs=6)


def swift_sail(m):
    for col in range(COLS):
        panel(m, col, K("cloth", CRIMSON if col % 2 == 0 else CREAM))
    for col in range(1, COLS):  # stitched seams between the panels, on both faces
        x = -1.0 + 2.0 * col / COLS
        for out in (0.008, -0.02):
            seam_line(m, K("cloth", CREAM if col % 2 else CRIMSON), [at(x, -1.0 + 0.2 * k, out) for k in range(11)], r=0.006)
    for y in (0.35, 0.6):  # reef bands with their points
        seam_line(m, K("cloth", CREAM), [at(-1.0 + 0.1 * k, y, 0.01) for k in range(21)], r=0.01)
        for k in range(1, 10):
            p = at(-1.0 + 0.2 * k, y, 0.012)
            m.rod(K("cloth", CREAM), 0.006, p, (p[0], p[1] - 0.12, p[2] + 0.005), segs=4)
    edge = [at(-1.0 + 0.1 * k, 1.0) for k in range(21)] + [at(1.0, 1.0 - 0.1 * k) for k in range(1, 21)]
    edge += [at(1.0 - 0.1 * k, -1.0) for k in range(1, 21)] + [at(-1.0, -1.0 + 0.1 * k) for k in range(1, 21)]
    seam_line(m, K("cloth", GOLD), edge, r=0.025)  # boltrope
    for cx, cy in ((-1, -1), (1, -1), (-1, 1), (1, 1)):  # corner rings (cringles)
        p = at(cx * 0.97, cy * 0.97, 0.01)
        m.ball(K("metal", GOLD), (0.05, 0.05, 0.02), p, u=10, v=6)
    # the emblem: a gold ring and three sky-blue gusts sweeping out of it
    centre = (0.0, 0.05)
    ring = [at(centre[0] + 0.32 * math.cos(2 * math.pi * k / 24), centre[1] + 0.32 * math.sin(2 * math.pi * k / 24), 0.02) for k in range(25)]
    seam_line(m, K("paint", GOLD), ring, r=0.03)
    inner = [at(centre[0] + 0.2 * math.cos(2 * math.pi * k / 18), centre[1] + 0.2 * math.sin(2 * math.pi * k / 18), 0.02) for k in range(19)]
    seam_line(m, K("paint", GOLD), inner, r=0.012)
    for g in range(3):
        start = g * 2 * math.pi / 3 + 0.3
        gust = []
        for k in range(14):
            t = k / 13
            a = start + t * 2.4
            rad = 0.34 + 0.55 * t
            gust.append(at(centre[0] + rad * math.cos(a), centre[1] + rad * 0.8 * math.sin(a), 0.022))
        for p0, p1, k in zip(gust, gust[1:], range(13)):
            m.rod(K("paint", SKY), 0.045 * (1.0 - k / 15), p0, p1, segs=8)
    m.ball(K("paint", SKY), (0.09, 0.09, 0.02), at(centre[0], centre[1], 0.02), u=12, v=6)


if __name__ == "__main__":
    fk.init()
    m = kit.Model("swift_sail", uv_scale=0.6, colored=True)
    swift_sail(m)
    print("swift_sail", m.export(OUT))
