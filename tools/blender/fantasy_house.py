# Purpose: developer-time helpers that build the fantasy world's houses in real detail (round 4, item 12): a stone
# plinth, floors that jut out over the one below on joist ends and brackets, a full timber frame (posts, sill and
# top beams, close studs, corner braces, a rail at sill height) with plaster panels that are never quite one
# colour, leaded windows with mullions, shutters and flower boxes, a plank door with strap hinges and steps, a roof
# of two sheets with bargeboards, a framed gable, courses, dormers and a chimney with pots. Stone-built regions get
# corner stones and string courses instead of the frame; the desert's flat-roofed houses get buttresses, roof beam
# ends and a parapet. Used by fantasy_kit.house (cottages, halls, townhouses, shops, the farmhouse) and by the
# walk-in houses of fantasy_inside.py. Model space: x right, y up, f forward (the front, where the door is).
# PLAIN = True builds the same houses for the low graphics tiers (fantasy_kit.Maker.plain_pass): same size and
# shape, but only every other stud and no braces, panels, lattice, joists, courses, straps or pots: about a
# quarter of the triangles.
import math

import fantasy_kit as fk
from fantasy_kit import K, S, c

GLASS = (0.13, 0.17, 0.23)
LEAD = (0.09, 0.09, 0.1)
IRON = (0.22, 0.22, 0.25)
POT = (0.66, 0.36, 0.24)
FLOWERS = [(0.86, 0.2, 0.22), (0.95, 0.8, 0.25), (0.92, 0.9, 0.92), (0.75, 0.35, 0.7)]
PLINTH = 0.6
STOREY = 2.5
PLAIN = False  # set by fantasy_kit.Maker.plain_pass while it builds the low graphics tiers' models


def soft(bevel):
    """A rounded edge costs about a hundred triangles a block: plain models have none."""
    return 0.0 if PLAIN else bevel


def tone(mat, k):
    """The same material a little darker or lighter."""
    return (mat[0], tuple(v * k for v in mat[1]))


class Face:
    """One outside wall seen from outside: u runs along it (left to right), n points out of it."""

    def __init__(self, m, name, plane, half):
        self.m, self.name, self.plane, self.half = m, name, plane, half

    def at(self, u, y, n=0.0):
        p = self.plane + n
        return {"front": (u, y, p), "back": (-u, y, -p), "right": (p, y, -u), "left": (-p, y, u)}[self.name]

    def box(self, mat, su, sy, sn, u, y, n=0.0, bevel=0.0):
        size = (su, sy, sn) if self.name in ("front", "back") else (sn, sy, su)
        self.m.box(mat, size, self.at(u, y, n), bevel=bevel)

    def rod(self, mat, r, a, b, n=0.05, segs=4):
        self.m.rod(mat, r, self.at(a[0], a[1], n), self.at(b[0], b[1], n), segs=segs)


def window(face, s, u, y, ww=0.95, wh=1.15, shutters=False, flowers=False, stone=False):
    """A leaded window: frame, dark glass, mullion and transom, a lattice of lead, a sill; shutters or a flower box."""
    timber = S(s, "stone") if stone else S(s, "timber")
    face.box(timber, ww + 0.24, wh + 0.24, 0.12, u, y, 0.05)
    face.box(c(GLASS), ww, wh, 0.1, u, y, 0.075)
    if PLAIN:  # frame and glass; shutters as bare boards
        for side in (-1, 1) if shutters else ():
            face.box(S(s, "trim"), 0.44, wh + 0.1, 0.05, u + side * (ww / 2 + 0.37), y, 0.06)
        return
    face.box(S(s, "timber"), 0.07, wh, 0.12, u, y, 0.085)
    face.box(S(s, "timber"), ww, 0.06, 0.12, u, y + wh * 0.2, 0.085)
    for k in range(3):  # three crossings of lead make the diamonds
        low = y - wh / 2 + wh * k / 3.0
        face.rod(c(LEAD), 0.011, (u - ww / 2, low), (u + ww / 2, low + wh / 3.0), 0.13, segs=3)
        face.rod(c(LEAD), 0.011, (u - ww / 2, low + wh / 3.0), (u + ww / 2, low), 0.13, segs=3)
    face.box(timber, ww + 0.4, 0.1, 0.24, u, y - wh / 2 - 0.15, 0.1)
    if shutters:
        for side in (-1, 1):
            face.box(S(s, "trim"), 0.44, wh + 0.1, 0.05, u + side * (ww / 2 + 0.37), y, 0.06)
            for dy in (-0.35, 0.35):
                face.box(S(s, "timber"), 0.4, 0.07, 0.03, u + side * (ww / 2 + 0.37), y + dy, 0.09)
    if flowers:
        face.box(S(s, "trim"), ww + 0.3, 0.2, 0.26, u, y - wh / 2 - 0.3, 0.2)
        face.box(K("leaf", (0.25, 0.5, 0.2)), ww + 0.2, 0.14, 0.2, u, y - wh / 2 - 0.16, 0.2)
        for k in range(4):
            at = face.at(u - ww / 2 + 0.12 + k * (ww - 0.24) / 3.0, y - wh / 2 - 0.06 + 0.04 * (k % 2), 0.22)
            face.m.ball(c(FLOWERS[(k + int(abs(u) * 3)) % len(FLOWERS)]), 0.085, at, u=4, v=2)


def timber_face(face, s, y0, height, gap=None, panels=True):
    """The frame of one wall of one floor: end posts, sill and top beams, studs, a rail, braces; `gap` = (u, width)
    left free for a doorway. Plaster panels between the studs, each a shade of its own."""
    timber = S(s, "timber")
    long = face.half
    wide = face.name in ("front", "back")
    for side in (-1, 1):
        face.box(timber, 0.24, height, 0.1, side * (long - 0.1), y0 + height / 2, 0.03)
        if PLAIN:
            continue
        if wide:  # a foot brace, clear of the windows
            face.rod(timber, 0.075, (side * (long - 0.22), y0 + 0.95), (side * (long - 1.0), y0 + 0.22), 0.075)
        else:
            face.rod(timber, 0.075, (side * (long - 0.2), y0 + 0.3), (side * (long - 1.3), y0 + height - 0.25), 0.075)
    face.box(timber, 2 * long, 0.2, 0.1, 0, y0 + height - 0.1, 0.035)
    runs = [(-long, long)] if gap is None else [(-long, gap[0] - gap[1] / 2 - 0.02), (gap[0] + gap[1] / 2 + 0.02, long)]
    for a, b in runs:
        if b - a > 0.1:
            face.box(timber, b - a, 0.2, 0.1, (a + b) / 2, y0 + 0.1, 0.035)
            face.box(timber, b - a, 0.13, 0.08, (a + b) / 2, y0 + 1.0, 0.03)
    bays = max(2, int(round(2 * long / (0.85 if wide else 1.25))))
    edges = [-long + 2 * long * k / bays for k in range(bays + 1)]
    for k in range(bays):
        mid = (edges[k] + edges[k + 1]) / 2
        open_here = gap is not None and abs(mid - gap[0]) < gap[1] / 2 + 0.3
        if not open_here:
            shade = 0.8 + 0.2 * ((k * 37 + int(y0 * 10) + len(face.name) * 11) % 10) / 10.0
            if panels and not PLAIN:
                face.box(tone(S(s, "wall"), shade), edges[k + 1] - edges[k] - 0.12, height - 0.4, 0.03, mid, y0 + height / 2, 0.012)
        if 0 < k and (not PLAIN or k % 2 == 0) and not (gap is not None and abs(edges[k] - gap[0]) < gap[1] / 2 + 0.05):
            face.box(timber, 0.13, height - 0.4, 0.08, edges[k], y0 + height / 2, 0.028)


def stone_face(face, s, y0, height):
    """A stone wall of one floor: corner stones by turns long and short, and a course along its top."""
    for side in () if PLAIN else (-1, 1):
        for q in range(int(height / 0.5)):
            long = 0.56 if q % 2 == 0 else 0.36
            face.box(tone(S(s, "stone"), 1.18 if q % 2 == 0 else 1.08), long, 0.44, 0.07, side * (face.half - long / 2 + 0.03), y0 + 0.27 + q * 0.5, 0.03)
    face.box(tone(S(s, "stone"), 0.82), 2 * face.half + 0.1, 0.16, 0.1, 0, y0 + height - 0.08, 0.04)


def door(face, s, u, stone=False):
    """A plank door at street level, proud of the plinth: heavy frame, strap hinges, a ring, a lintel, a threshold."""
    frame = S(s, "stone") if stone else S(s, "timber")
    face.box(frame, 1.42, 2.36, 0.16, u, 1.26, 0.16)
    face.box(S(s, "trim"), 1.02, 2.04, 0.1, u, 1.16, 0.22)
    face.box(frame, 1.75, 0.26, 0.22, u, 2.5, 0.19)
    face.box(S(s, "stone"), 1.8, 0.14, 0.62, u, 0.07, 0.3, bevel=soft(0.03))
    if PLAIN:
        return
    for k in (-1, 0, 1):
        face.box(tone(S(s, "trim"), 0.6), 0.025, 1.96, 0.11, u + k * 0.26, 1.16, 0.22)
    for dy in (0.55, 1.75):
        face.box(K("metal", IRON), 0.82, 0.07, 0.03, u - 0.06, dy, 0.285)
    face.m.ball(K("metal", IRON), 0.065, face.at(u + 0.33, 1.15, 0.31), u=6, v=4)


def great_doors(face, s, u, y0, wide, high):
    """Two plank leaves, each braced corner to corner and strapped, under a heavy lintel: barns and coach houses."""
    leaf = wide / 2 - 0.04
    for side in (-1, 1):
        face.box(S(s, "trim"), leaf, high, 0.1, u + side * (leaf / 2 + 0.02), y0 + high / 2, 0.07)
        if PLAIN:
            continue
        face.rod(S(s, "timber"), 0.06, (u + side * 0.1, y0 + 0.15), (u + side * (leaf - 0.05), y0 + high - 0.1), 0.14)
        for y in (0.45, high - 0.4):
            face.box(K("metal", IRON), leaf - 0.14, 0.08, 0.03, u + side * (leaf / 2 + 0.02), y0 + y, 0.135)
    face.box(S(s, "timber"), wide + 0.5, 0.26, 0.2, u, y0 + high + 0.14, 0.08)


def chimney_stack(m, s, x, f, top):
    """A stone stack with a shoulder, a cap course and two clay pots."""
    m.box(S(s, "stone"), (0.95, top * 0.55, 0.9), (x, top * 0.275, f), bevel=soft(0.04))
    m.box(S(s, "stone"), (0.74, top - 0.2, 0.7), (x, (top - 0.2) / 2 + 0.2, f), bevel=soft(0.035))
    if PLAIN:
        return
    m.box(tone(S(s, "stone"), 0.8), (0.96, 0.16, 0.92), (x, top - 0.3, f), bevel=0.0)
    m.box(S(s, "stone"), (0.84, 0.16, 0.8), (x, top - 0.12, f), bevel=0.0)
    for dx in (-0.18, 0.18):
        m.lathe(c(POT), [(0.11, 0.0), (0.135, 0.08), (0.1, 0.4), (0.125, 0.45), (0.0, 0.45)], (x + dx, top - 0.04, f), segs=7)


def gable_roof(m, s, hw, hd, wall_h, roof_h, dormers=0, timbered=True, front=False, gable_window=True):
    """Two roof sheets over a framed gable at each end: bargeboards, ridge, fascia, courses, dormers. `front`: the
    ridge runs front to back and a gable with a small window faces the street, as on a crowded town street."""
    roof = S(s, "roof")
    thatch = s.get("kinds", {}).get("roof") == "thatch"
    thick = 0.3 if thatch else 0.16
    eave, verge = 0.6, 0.45
    along, span = (hd, hw) if front else (hw, hd)  # half the length along the ridge, half the width across it
    half = span + eave
    low = wall_h - 0.22
    top = wall_h + roof_h
    slope = (top - low) / half
    deep = thick * math.hypot(1.0, slope)  # the sheet's thickness measured straight down
    across = "f" if front else "x"

    def at(a, y, b):  # a = along the ridge, b = across it
        return (b, y, a) if front else (a, y, b)

    def bar(mat, sa, sy, sb, a, y, b):
        m.box(mat, (sb, sy, sa) if front else (sa, sy, sb), at(a, y, b), bevel=0.0)

    def roof_y(b):
        return low + (half - abs(b)) * slope

    for way in (-1, 1):
        m.prof(roof, 2 * (along + verge), [(way * half, low), (0, top), (0, top - deep), (way * half, low - deep)], x=0, bevel=0.0, across=across)
        if PLAIN:
            continue
        bar(S(s, "timber"), 2 * (along + verge), 0.13, 0.08, 0, low - deep * 0.5, way * (half - 0.03))
        for k in range(1, 4 if thatch else 6):  # courses, so the big sheets are not blank
            b = way * half * k / (4.0 if thatch else 6.0)
            bar(tone(roof, 0.8), 2 * (along + verge) - 0.04, 0.1, 0.16, 0, roof_y(b), b)  # a step that stands out of the slope
    for side in (-1, 1):
        m.prof(S(s, "wall"), 0.12, [(-span, wall_h - 0.05), (-span, roof_y(span) - deep), (0, top - deep - 0.02), (span, roof_y(span) - deep), (span, wall_h - 0.05)], x=side * (along - 0.06), bevel=0.0, across=across)
        if timbered:  # tie beam, king post, struts and a collar
            out = side * (along + 0.02)
            post = roof_h - deep - 0.25
            bar(S(s, "timber"), 0.1, 0.22, 2 * span, out, wall_h + 0.02, 0)
            bar(S(s, "timber"), 0.1, post, 0.2, out, wall_h + post / 2, 0)
            for way in () if PLAIN else (-1, 1):
                m.rod(S(s, "timber"), 0.07, at(out, wall_h + 0.1, way * span * 0.72), at(out, wall_h + roof_h * 0.5, way * 0.12), segs=4)
            if not PLAIN:
                bar(S(s, "timber"), 0.1, 0.16, span * 0.9, out, wall_h + roof_h * 0.5, 0)
        edge = side * (along + verge - 0.05)
        for way in (-1, 1):  # bargeboards along the gable's two edges
            m.rod(S(s, "timber"), 0.085, at(edge, low - 0.02, way * half), at(edge, top + 0.02, 0), segs=4)
    if thatch:
        m.rod(tone(roof, 0.8), 0.24, at(-(along + verge), top + 0.02, 0), at(along + verge, top + 0.02, 0), segs=4 if PLAIN else 7)
    else:
        bar(tone(roof, 0.75), 2 * (along + verge) + 0.06, 0.14, 0.26, 0, top + 0.07, 0)
    if front and gable_window and roof_h >= 2.6:  # a little window in the street gable
        window(Face(m, "front", along, span), s, 0.0, wall_h + roof_h * 0.36, ww=0.7, wh=0.8)
    for k in range(0 if front else dormers):  # small gabled windows in the front sheet
        x = (k - (dormers - 1) / 2.0) * hw * 1.0
        f = half * 0.5
        base = roof_y(f) - 0.15
        m.box(tone(roof, 0.86), (1.3, 1.1, half * 0.5), (x, base + 0.55, f + half * 0.12), bevel=0.0)  # cheeks hung with the roof's own covering
        m.box(S(s, "wall"), (1.2, 1.05, 0.06), (x, base + 0.55, f + half * 0.37), bevel=0.0)
        window(Face(m, "front", f + half * 0.37, 0.65), s, x, base + 0.58, ww=0.7, wh=0.7)
        m.prof(roof, half * 0.62, [(x - 0.95, base + 1.05), (x, base + 1.6), (x + 0.95, base + 1.05)], x=f + half * 0.14, bevel=0.0, across="f")
        for way in () if PLAIN else (-1, 1):
            m.rod(S(s, "timber"), 0.06, (x + way * 0.95, base + 1.03, f + half * 0.455), (x, base + 1.6, f + half * 0.455), segs=4)


def flat_roof(m, s, hw, hd, wall_h):
    """The desert's roof: a slab, a parapet with raised corners, beam ends through the front wall, an awning."""
    m.box(S(s, "roof"), (2 * hw + 0.4, 0.3, 2 * hd + 0.4), (0, wall_h + 0.15, 0), bevel=soft(0.04))
    for side in (-1, 1):
        m.box(S(s, "wall"), (0.3, 0.5, 2 * hd + 0.4), (side * (hw + 0.05), wall_h + 0.5, 0), bevel=soft(0.05))
        m.box(S(s, "wall"), (2 * hw + 0.4, 0.5, 0.3), (0, wall_h + 0.5, side * (hd + 0.05)), bevel=soft(0.05))
        for way in (-1, 1):  # raised corners and a buttress under each
            m.box(S(s, "wall"), (0.6, 0.85, 0.6), (side * (hw - 0.05), wall_h + 0.62, way * (hd - 0.05)), bevel=soft(0.08))
            m.prof(tone(S(s, "wall"), 0.94), 0.7, [(way * hd, 0.0), (way * (hd + 0.75), 0.0), (way * (hd + 0.1), wall_h * 0.7), (way * hd, wall_h * 0.7)] if way > 0 else
                [(way * hd, 0.0), (way * hd, wall_h * 0.7), (way * (hd + 0.1), wall_h * 0.7), (way * (hd + 0.75), 0.0)], x=side * (hw - 0.3), bevel=soft(0.03))
    count = max(3, int(2 * hw / 1.1))
    for k in range(0 if PLAIN else count):  # roof beams poke through the front and back walls
        x = -hw + 0.6 + (2 * hw - 1.2) * k / (count - 1)
        m.rod(K("wood", (0.42, 0.3, 0.2)), 0.1, (x, wall_h - 0.25, -hd - 0.45), (x, wall_h - 0.25, hd + 0.45), segs=6)
    m.strip(S(s, "trim"), hw * 1.5, 0.05, [(hd + 0.3, wall_h - 0.55), (hd + 1.9, wall_h - 1.05)], x=0)
    for side in (-1, 1):
        m.rod(K("wood", (0.42, 0.3, 0.2)), 0.05, (side * hw * 0.7, 0.0, hd + 1.85), (side * hw * 0.7, wall_h - 1.05, hd + 1.85), segs=5)


def build(m, s, w, d, floors, roof_h, chimney=True, frame=True, door_x=0.0, gable_front=False):
    """A whole house. Returns the height of its walls. Its solid part (`m.walls`, for data/fantasy/props.json) is
    the plinth alone, so people walk under the eaves and the overhanging floors."""
    kind = s.get("kinds", {}).get("wall", "plaster")
    flat = bool(s.get("flat"))
    timbered = frame and kind == "plaster"
    stone = kind == "stone"
    jetty = 0.35 if timbered else 0.0
    wall_h = PLINTH + STOREY * floors
    m.walls = getattr(m, "walls", []) + [[0.0, 0.0, round(w + 0.3, 2), round(d + 0.3, 2)]]
    with fk.weathered():
        m.box(S(s, "stone"), (w + 0.3, PLINTH, d + 0.3), (0, PLINTH / 2, 0), bevel=soft(0.05))
        if not PLAIN:
            m.box(tone(S(s, "stone"), 0.8), (w + 0.36, 0.1, d + 0.36), (0, PLINTH - 0.05, 0), bevel=0.0)
        hw, hd = w / 2, d / 2
        for i in range(floors):
            y0 = PLINTH + STOREY * i
            hw = w / 2 + (0.1 * i if timbered else 0.0)
            hd = d / 2 + jetty * i
            m.box(S(s, "wall"), (2 * hw, STOREY, 2 * hd), (0, y0 + STOREY / 2, 0), bevel=0.0)
            for name, plane, half in (("front", hd, hw), ("back", hd, hw), ("right", hw, hd), ("left", hw, hd)):
                face = Face(m, name, plane, half)
                ground_front = name == "front" and i == 0
                if timbered:
                    timber_face(face, s, y0, STOREY, gap=(door_x, 1.4) if ground_front else None)
                elif stone:
                    stone_face(face, s, y0, STOREY)
                if name in ("front", "back"):
                    spots = [-half + 1.3, half - 1.3] + ([0.0] if 2 * half >= 8.5 else [])
                    if 2 * half < 4.6:
                        spots = [0.0]
                else:
                    spots = [0.0] if 2 * half >= 4.0 else []
                for u in spots:
                    if ground_front and abs(u - door_x) < 1.45:
                        continue
                    window(face, s, u, y0 + 1.6, shutters=i == 0 and not flat, flowers=i > 0 and name == "front", stone=stone or flat)
                if i > 0 and timbered and not PLAIN and name in ("front", "back"):  # the jetty: joist ends and brackets under the overhang
                    count = max(3, int(2 * half / 0.7))
                    for k in range(count + 1):
                        u = -half + 0.12 + (2 * half - 0.24) * k / count
                        face.box(S(s, "timber"), 0.14, 0.18, jetty + 0.16, u, y0 - 0.1, -jetty / 2 + 0.02)
                    for side in (-1, 1):
                        m.rod(S(s, "timber"), 0.07, face.at(side * (half - 0.25), y0 - 0.75, -jetty + 0.04), face.at(side * (half - 0.25), y0 - 0.12, 0.04), segs=4)
                if ground_front:
                    door(face, s, door_x, stone=stone or flat)
        if flat:
            flat_roof(m, s, hw, hd, wall_h)
        else:
            gable_roof(m, s, hw, hd, wall_h, roof_h, dormers=2 if w >= 9.5 else (1 if floors >= 2 and roof_h >= 2.8 else 0), timbered=timbered, front=gable_front)
        if chimney:
            chimney_stack(m, s, w / 2 - 1.15, -d / 4, wall_h + (1.2 if flat else roof_h * 0.62 + 1.0))
    return wall_h
