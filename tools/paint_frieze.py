# Purpose: developer-time script (polish1 item 9, locked story: diary/DECISIONS_HUB.md). Paints the hub pedestal's
# carved frieze as a picture: four bands running round all four sides, read from the top band down, each figure a
# clear Egyptian-style profile (head, wig, shoulders square to the viewer, striding legs, arms in a pose) cut into the
# stone as SUNK RELIEF (a dark cut with a shadowed upper-left edge and a lit lower-right edge), and short columns of
# small glyphs (the carved words) between the figures. Stylised, nothing graphic. The game lays the four faces on the
# pedestal (game/hub_room.gd _frieze), one draw.
# Atlas: 4 faces stacked (front, right, back, left), each 1024 x 640 px = 1.3 x 0.812 m of the face (u -0.65..0.65,
# height 0.41..1.222 m above the floor). Writes assets/ui/hub_frieze.png.
# Run: python3 tools/paint_frieze.py [preview.png]   (needs pillow)
import math
import os
import sys

from PIL import Image, ImageChops, ImageDraw, ImageFilter

SS = 2  # drawn at twice the size, then shrunk (smooth edges)
FACE_W, FACE_H = 1024, 640
PX_PER_M = FACE_W / 1.3
Y0 = 0.41  # metres above the floor at the picture's foot
BANDS = [1.03, 0.83, 0.63, 0.43]  # the foot of each band, top chapter first (the raised lines are in the model)
OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "ui", "hub_frieze.png")

# The story, one band per chapter, each band running round the four sides (front, right, back, left): a king is
# crowned under the rising sun; the sun goes dark and the fields die, he kneels to the sun-headed one and is given
# power; the little ones are led in a line up the temple steps, those left behind raise their arms; the temple is shut,
# the footprints go in and none come out, the sun blazes, the wheat stands tall and the king stands taller than his
# temple. A newcomer sees an ordinary ancient frieze; it tells itself to those who look.
STORY = [
    [["sun_rise", "crowning", "bow", "bow"], ["bearer", "bearer", "bow", "praise"], ["farmer", "wheat", "wheat", "farmer", "wheat"], ["jar", "jar", "bearer", "king", "sun"]],
    [["sun_dark", "wheat_dead", "wheat_dead", "grief"], ["grief", "grief", "jar_broken", "grief"], ["king_kneel", "god"], ["god", "king_given", "praise", "praise"]],
    [["priest", "small", "small", "small"], ["small", "small", "priest", "grief"], ["grief", "small", "small", "steps"], ["priest", "small", "temple"]],
    [["temple_shut", "feet", "feet", "feet"], ["sun_big", "king_big"], ["wheat", "wheat", "bow", "bow", "wheat"], ["glyph_bird", "temple", "king_big"]],
]
SMALL = ["glyph_eye", "glyph_bird", "glyph_reed", "glyph_water", "glyph_ankh", "glyph_jar"]


class Pen:
    """Draws one figure into the mask. Local units: u right (the way the figure faces), v up, 1 = a grown figure's
    height; `bend` turns everything above the hips forward (degrees) about the hip."""

    def __init__(self, d, x, base, h, bend=0.0, hip=(0.0, 0.47)):
        self.d, self.x, self.base, self.h = d, x, base, h
        self.bend, self.hip = math.radians(bend), hip
        self.upper = False
        self.flip = 1.0  # -1: the figure faces left

    def p(self, u, v):
        if self.upper and self.bend:
            du, dv = u - self.hip[0], v - self.hip[1]
            c, s = math.cos(-self.bend), math.sin(-self.bend)
            u, v = self.hip[0] + du * c - dv * s, self.hip[1] + du * s + dv * c
        return (self.x + u * self.h * self.flip, self.base - v * self.h)

    def poly(self, pts):
        self.d.polygon([self.p(u, v) for u, v in pts], fill=255)

    def circle(self, u, v, r):
        cx, cy = self.p(u, v)
        rr = r * self.h
        self.d.ellipse([cx - rr, cy - rr, cx + rr, cy + rr], fill=255)

    def ring(self, u, v, r, w):
        cx, cy = self.p(u, v)
        rr = r * self.h
        self.d.ellipse([cx - rr, cy - rr, cx + rr, cy + rr], outline=255, width=max(1, int(w * self.h)))

    def limb(self, pts, w):
        """A thick bent line (arm, leg) through pts, rounded at the joints."""
        for (u0, v0), (u1, v1) in zip(pts, pts[1:]):
            a, b = self.p(u0, v0), self.p(u1, v1)
            dx, dy = b[0] - a[0], b[1] - a[1]
            n = math.hypot(dx, dy) or 1.0
            ox, oy = -dy / n * w * self.h / 2, dx / n * w * self.h / 2
            self.d.polygon([(a[0] + ox, a[1] + oy), (b[0] + ox, b[1] + oy), (b[0] - ox, b[1] - oy), (a[0] - ox, a[1] - oy)], fill=255)
        for u, v in pts:
            self.circle(u, v, w / 2)


ARMS = {  # (back arm, front arm) as joint paths from the shoulders, figure facing right
    "down": ([(-0.1, 0.78), (-0.13, 0.62), (-0.12, 0.47)], [(0.1, 0.78), (0.13, 0.62), (0.12, 0.47)]),
    "out": ([(-0.1, 0.78), (-0.13, 0.62), (-0.12, 0.47)], [(0.1, 0.78), (0.24, 0.72), (0.38, 0.72)]),
    "both_out": ([(-0.08, 0.78), (0.14, 0.7), (0.32, 0.68)], [(0.1, 0.78), (0.24, 0.74), (0.4, 0.76)]),
    "up": ([(-0.1, 0.78), (-0.02, 0.92), (0.06, 1.06)], [(0.1, 0.78), (0.2, 0.92), (0.28, 1.04)]),
    "grief": ([(-0.1, 0.78), (0.0, 0.9), (0.07, 0.93)], [(0.1, 0.78), (0.18, 0.88), (0.1, 0.94)]),  # hands to the face
    "bowl": ([(-0.1, 0.78), (0.08, 0.72), (0.22, 0.84)], [(0.1, 0.78), (0.22, 0.72), (0.28, 0.84)]),
    "hold": ([(-0.1, 0.78), (-0.13, 0.62), (-0.12, 0.47)], [(0.1, 0.78), (0.16, 0.64), (0.26, 0.6)]),
}


def person(pen, arms="down", robe=False, stride=True, head="wig"):
    """A profile figure facing right: striding legs, a kilt (or a long robe), square shoulders, a head with a nose and a
    wig. Returns nothing; the pen's bend tips the body above the hips."""
    if robe:
        pen.poly([(-0.09, 0.5), (0.09, 0.5), (0.14, 0.05), (-0.13, 0.05)])
        pen.limb([(-0.07, 0.06), (-0.07, 0.02)], 0.05)
        pen.poly([(0.0, 0.0), (0.14, 0.0), (0.14, 0.04), (0.0, 0.05)])
    else:
        back, front = ((-0.03, 0.46), (-0.12, 0.03)), ((0.03, 0.46), (0.13, 0.03)) if stride else ((0.02, 0.46), (0.03, 0.03))
        if not stride:
            back = ((-0.02, 0.46), (-0.03, 0.03))
        pen.limb([back[0], ((back[0][0] + back[1][0]) / 2, 0.24), back[1]], 0.055)
        pen.limb([front[0], ((front[0][0] + front[1][0]) / 2, 0.24), front[1]], 0.055)
        for f in (back[1], front[1]):  # feet, toes forward
            pen.poly([(f[0] - 0.03, f[1] + 0.02), (f[0] + 0.07, f[1] - 0.005), (f[0] + 0.07, f[1] - 0.03), (f[0] - 0.03, f[1] - 0.03)])
        pen.poly([(-0.08, 0.53), (0.08, 0.53), (0.13, 0.36), (-0.1, 0.36)])  # the kilt, flaring forward
    pen.upper = True
    pen.poly([(-0.12, 0.8), (0.12, 0.8), (0.07, 0.52), (-0.07, 0.52)])  # shoulders square to us, narrow waist
    pen.poly([(-0.025, 0.79), (0.03, 0.79), (0.03, 0.85), (-0.02, 0.85)])  # neck
    pen.circle(0.01, 0.91, 0.068)  # head
    pen.poly([(0.06, 0.93), (0.1, 0.89), (0.06, 0.88)])  # nose
    pen.poly([(0.05, 0.86), (0.07, 0.83), (0.04, 0.83)])  # chin / beard line
    if head == "wig":
        pen.poly([(-0.07, 0.97), (0.04, 0.99), (0.03, 0.92), (-0.02, 0.83), (-0.08, 0.84)])
    elif head == "lock":  # a child's side lock
        pen.limb([(-0.05, 0.93), (-0.09, 0.86), (-0.07, 0.8)], 0.03)
    back, front = ARMS[arms]
    pen.limb(back, 0.045)
    pen.limb(front, 0.045)
    pen.upper = False


def crown(pen, top=0.9):
    """The tall crown: a rounded cone with a knob, worn on the head."""
    pen.upper = True
    pen.poly([(-0.06, top), (0.06, top), (0.045, top + 0.12), (0.025, top + 0.2), (-0.015, top + 0.2), (-0.04, top + 0.12)])
    pen.circle(0.005, top + 0.215, 0.025)
    pen.upper = False


def staff(pen, u0=0.38, v0=0.72):
    pen.limb([(u0, 0.02), (u0, v0 + 0.32)], 0.022)
    pen.limb([(u0, v0 + 0.32), (u0 - 0.02, v0 + 0.37), (u0 - 0.07, v0 + 0.36)], 0.022)  # the crook


def sun_disc(pen, u, v, r, rays=0, ray_len=0.08, start=0.0, sweep=360.0):
    pen.circle(u, v, r)
    for k in range(rays):
        a = math.radians(start + sweep * (k + 0.5) / rays)
        pen.limb([(u + math.cos(a) * (r + 0.02), v + math.sin(a) * (r + 0.02)), (u + math.cos(a) * (r + ray_len), v + math.sin(a) * (r + ray_len))], 0.022)


def wheat(pen, u=0.0, dead=False):
    if dead:
        pen.limb([(u, 0.0), (u, 0.3), (u + 0.1, 0.36), (u + 0.18, 0.26)], 0.022)
        pen.limb([(u + 0.08, 0.0), (u + 0.1, 0.18), (u + 0.2, 0.12)], 0.022)
        for k in range(3):
            pen.circle(u + 0.2 + k * 0.03, 0.2 - k * 0.05, 0.02)
        return
    for du, top in ((0.0, 0.72), (0.08, 0.62)):
        pen.limb([(u + du, 0.0), (u + du + 0.01, top)], 0.02)
        for k in range(5):  # the ear: grains either side
            v = top - 0.03 - k * 0.045
            pen.poly([(u + du + 0.01, v), (u + du - 0.035, v + 0.05), (u + du - 0.01, v + 0.06)])
            pen.poly([(u + du + 0.01, v), (u + du + 0.055, v + 0.05), (u + du + 0.03, v + 0.06)])
        pen.limb([(u + du + 0.01, top), (u + du + 0.02, top + 0.06)], 0.012)
        pen.limb([(u + du, 0.2), (u + du + 0.08, 0.3)], 0.015)  # a leaf


def jar(pen, u=0.0, broken=False):
    pen.poly([(u - 0.06, 0.02), (u + 0.06, 0.02), (u + 0.09, 0.14), (u + 0.05, 0.24), (u - 0.05, 0.24), (u - 0.09, 0.14)])
    pen.poly([(u - 0.035, 0.24), (u + 0.035, 0.24), (u + 0.045, 0.29), (u - 0.045, 0.29)])
    if broken:  # tipped over, its mouth to the ground, a crack
        pass


def temple(pen, shut=False):
    pen.poly([(-0.02, 0.0), (0.62, 0.0), (0.62, 0.05), (-0.02, 0.05)])  # its platform
    for i in range(4):  # steps up the front
        pen.poly([(0.0 + i * 0.04, 0.05 + i * 0.04), (0.6 - i * 0.04, 0.05 + i * 0.04), (0.6 - i * 0.04, 0.09 + i * 0.04), (0.0 + i * 0.04, 0.09 + i * 0.04)])
    for side in (0.13, 0.45):  # the pylon towers, leaning in
        pen.poly([(side - 0.1, 0.21), (side + 0.1, 0.21), (side + 0.08, 0.78), (side - 0.08, 0.78)])
        pen.poly([(side - 0.1, 0.78), (side + 0.1, 0.78), (side + 0.11, 0.83), (side - 0.11, 0.83)])
    pen.poly([(0.21, 0.6), (0.37, 0.6), (0.37, 0.66), (0.21, 0.66)])  # the lintel over the gate
    if shut:
        pen.poly([(0.23, 0.21), (0.35, 0.21), (0.35, 0.6), (0.23, 0.6)])  # the gate blocked


def steps(pen):
    for i in range(5):
        pen.poly([(i * 0.09, 0.0), (0.5, 0.0), (0.5, 0.09 * (i + 1)), (i * 0.09, 0.09 * (i + 1))])


def footprints(pen):
    for k, (u, v) in enumerate([(0.0, 0.03), (0.12, 0.09), (0.24, 0.03), (0.36, 0.09)]):
        pen.poly([(u, v), (u + 0.07, v + 0.01), (u + 0.07, v + 0.04), (u, v + 0.04)])
        pen.circle(u + 0.08, v + 0.025, 0.018)


def bird(pen, u=0.0, v=0.0, s=1.0):
    q = lambda a, b: (u + a * s, v + b * s)  # noqa: E731
    pen.poly([q(0.0, 0.1), q(0.12, 0.16), q(0.2, 0.12), q(0.3, 0.12), q(0.2, 0.06), q(0.12, 0.0), q(0.02, 0.04)])  # body and wing
    pen.circle(*q(0.22, 0.2), 0.04 * s)  # head
    pen.poly([q(0.25, 0.21), q(0.33, 0.19), q(0.25, 0.18)])  # beak
    pen.limb([q(0.1, 0.02), q(0.1, -0.06)], 0.015 * s)
    pen.poly([q(-0.08, 0.14), q(0.02, 0.1), q(0.0, 0.05)])  # tail


GLYPH_SMALL = {  # the carved words: small signs, about a fifth of a figure's height
    "glyph_eye": lambda p, v: (p.poly([(0.0, v + 0.05), (0.07, v + 0.08), (0.15, v + 0.05), (0.07, v + 0.02)]), p.circle(0.075, v + 0.05, 0.02),
        p.limb([(0.0, v + 0.1), (0.15, v + 0.11)], 0.012), p.limb([(0.06, v + 0.02), (0.05, v - 0.03)], 0.012)),
    "glyph_bird": lambda p, v: bird(p, 0.0, v, 0.45),
    "glyph_reed": lambda p, v: (p.limb([(0.06, v - 0.02), (0.06, v + 0.1)], 0.018), p.poly([(0.06, v + 0.1), (0.13, v + 0.14), (0.07, v + 0.06)])),
    "glyph_water": lambda p, v: p.limb([(0.0, v + 0.03), (0.03, v + 0.06), (0.06, v + 0.03), (0.09, v + 0.06), (0.12, v + 0.03), (0.15, v + 0.06)], 0.016),
    "glyph_ankh": lambda p, v: (p.ring(0.075, v + 0.09, 0.028, 0.012), p.limb([(0.04, v + 0.055), (0.11, v + 0.055)], 0.014), p.limb([(0.075, v + 0.06), (0.075, v - 0.03)], 0.016)),
    "glyph_jar": lambda p, v: (p.poly([(0.04, v - 0.02), (0.11, v - 0.02), (0.12, v + 0.05), (0.03, v + 0.05)]), p.poly([(0.05, v + 0.05), (0.1, v + 0.05), (0.09, v + 0.08), (0.06, v + 0.08)])),
}


def draw(name, pen):
    """One figure or scene of the story. Returns its width in figure heights."""
    if name in ("person", "praise", "grief", "bearer", "farmer", "bow", "priest", "small"):
        robe = name == "priest"
        if name == "bow":
            pen.bend = math.radians(38.0)
        if name == "small":  # a little one: two thirds as tall
            pen.h *= 0.64
        arms = {"person": "down", "praise": "up", "grief": "grief", "bearer": "bowl", "farmer": "hold", "bow": "both_out", "priest": "out", "small": "up"}[name]
        person(pen, arms, robe=robe, head="lock" if name == "small" else ("cap" if robe else "wig"))
        if name == "bearer":
            pen.upper = True
            pen.poly([(0.16, 0.86), (0.34, 0.86), (0.3, 0.8), (0.2, 0.8)])  # the offering bowl
            pen.circle(0.25, 0.9, 0.04)
            pen.upper = False
        if name == "farmer":
            pen.limb([(0.26, 0.6), (0.3, 0.72), (0.38, 0.76), (0.44, 0.72)], 0.02)  # a sickle
        if name == "priest":
            pen.upper = True
            pen.poly([(-0.05, 0.95), (0.06, 0.96), (0.03, 1.06), (-0.03, 1.06)])  # a tall cap
            pen.upper = False
        return 0.5 if name in ("bow", "bearer", "farmer", "priest") else (0.27 if name == "small" else 0.4)
    if name in ("king", "king_given", "crowning", "king_big"):
        if name == "crowning":  # the king seated on his throne, the rising crown above
            pen.poly([(-0.16, 0.0), (-0.1, 0.0), (-0.1, 0.4), (-0.16, 0.75)])  # throne back
            pen.poly([(-0.16, 0.38), (0.14, 0.38), (0.14, 0.44), (-0.16, 0.44)])  # seat
            pen.limb([(-0.03, 0.44), (0.12, 0.44), (0.12, 0.03)], 0.06)  # thigh and shin
            pen.poly([(0.1, 0.0), (0.2, 0.0), (0.2, 0.03), (0.1, 0.05)])
            hip_v = 0.44
            pen.upper = True
            body = [(-0.12, 0.8 - 0.06), (0.12, 0.8 - 0.06), (0.07, hip_v), (-0.07, hip_v)]
            pen.poly(body)
            pen.circle(0.01, 0.85, 0.068)
            pen.poly([(0.06, 0.87), (0.1, 0.83), (0.06, 0.82)])
            pen.limb([(0.1, 0.72), (0.2, 0.62), (0.3, 0.68)], 0.045)
            pen.upper = False
            crown(pen, 0.88)
            return 0.45
        person(pen, "out" if name != "king_given" else "both_out")
        crown(pen)
        if name != "king_given":
            staff(pen)
        return 0.55
    if name == "king_kneel":
        pen.limb([(0.0, 0.3), (0.16, 0.06), (-0.12, 0.04)], 0.06)  # thigh down to the knee, shin back along the ground
        pen.poly([(-0.07, 0.33), (0.07, 0.33), (0.1, 0.22), (-0.06, 0.22)])
        pen.hip = (0.0, 0.3)
        pen.bend = math.radians(15)
        pen.upper = True
        pen.poly([(-0.12, 0.62), (0.12, 0.62), (0.07, 0.32), (-0.07, 0.32)])
        pen.circle(0.01, 0.73, 0.068)
        pen.poly([(0.06, 0.75), (0.1, 0.71), (0.06, 0.7)])
        pen.limb([(0.1, 0.6), (0.24, 0.62), (0.34, 0.7)], 0.045)  # hands up to the god
        pen.limb([(-0.08, 0.6), (0.12, 0.56), (0.3, 0.64)], 0.045)
        pen.upper = False
        crown(pen, 0.72)
        return 0.45
    if name == "god":  # the sun-headed one, facing left toward the king, holding the ankh of power out to him
        pen.x += 0.5 * pen.h
        pen.flip = -1.0  # faces left
        person(pen, "out", stride=True, head="none")
        sun_disc(pen, 0.01, 0.95, 0.11, rays=10, ray_len=0.07)
        pen.ring(0.44, 0.78, 0.04, 0.02)
        pen.limb([(0.4, 0.72), (0.48, 0.72)], 0.02)
        pen.limb([(0.44, 0.72), (0.44, 0.62)], 0.02)
        return 0.6
    if name == "sun":
        sun_disc(pen, 0.15, 0.6, 0.11, rays=12)
        return 0.32
    if name == "sun_big":  # the sun blazing, its rays falling to the right on the king
        sun_disc(pen, 0.2, 0.74, 0.15, rays=9, ray_len=0.12, start=200, sweep=140)
        for k in range(5):
            a = math.radians(-70 + k * 10)
            pen.limb([(0.2 + math.cos(a) * 0.2, 0.74 + math.sin(a) * 0.2), (0.2 + math.cos(a) * 0.62, 0.74 + math.sin(a) * 0.62)], 0.018)
        return 0.5
    if name == "sun_rise":
        pen.poly([(0.0, 0.0), (0.42, 0.0), (0.42, 0.03), (0.0, 0.03)])
        sun_disc(pen, 0.21, 0.04, 0.1, rays=7, ray_len=0.1, start=0, sweep=180)
        return 0.45
    if name == "sun_dark":  # an empty ring: no light, no rays
        pen.ring(0.15, 0.6, 0.11, 0.025)
        pen.ring(0.15, 0.6, 0.05, 0.02)
        return 0.32
    if name in ("wheat", "wheat_dead"):
        wheat(pen, 0.05, dead=name == "wheat_dead")
        return 0.25 if name == "wheat" else 0.3
    if name in ("jar", "jar_broken"):
        if name == "jar_broken":
            pen.poly([(0.0, 0.02), (0.22, 0.02), (0.24, 0.1), (0.04, 0.13)])
            pen.poly([(0.24, 0.0), (0.3, 0.0), (0.3, 0.05)])
            return 0.32
        jar(pen, 0.09)
        return 0.2
    if name in ("temple", "temple_shut"):
        temple(pen, shut=name == "temple_shut")
        return 0.64
    if name == "steps":
        steps(pen)
        return 0.52
    if name == "feet":
        pen.h *= 1.6
        footprints(pen)
        return 0.74
    if name == "glyph_bird":
        bird(pen, 0.0, 0.3, 1.0)
        return 0.36
    raise KeyError(name)


def words(pen, k):
    """A column of three small signs (the carved words beside the pictures)."""
    pen.h *= 1.45
    for i in range(3):
        GLYPH_SMALL[SMALL[(k + i * 2) % 6]](pen, 0.52 - i * 0.2)
    return 0.23


def paint_face(face_i):
    w, h = FACE_W * SS, FACE_H * SS
    mask = Image.new("L", (w, h), 0)
    d = ImageDraw.Draw(mask)
    ppm = PX_PER_M * SS
    for chapter, foot in enumerate(BANDS):
        base = h - (foot + 0.012 - Y0) * ppm  # just above the raised line at the band's foot
        tall = 0.165 * ppm
        row = []
        for k, name in enumerate(STORY[chapter][face_i]):
            row.append(("fig", name))
            row.append(("words", (k + chapter * 2 + face_i) % 6))
        widths = []
        for kind, what in row:  # measure on a scratch canvas
            scratch = ImageDraw.Draw(Image.new("L", (8, 8)))
            pen = Pen(scratch, 0, 0, 1.0)
            widths.append(draw(what, pen) if kind == "fig" else words(pen, what))
        scale = min(tall, (w - 0.06 * ppm) / sum(widths))
        gap = ((w - 0.06 * ppm) - sum(widths) * scale) / max(len(row) - 1, 1)
        x = 0.03 * ppm
        for (kind, what), wd in zip(row, widths):
            pen = Pen(d, x + (0.12 * scale if kind == "fig" else 0.0), base, scale)
            if kind == "fig":
                draw(what, pen)
            else:
                words(pen, what)
            x += wd * scale + gap
    return mask


def carve(mask):
    """Sunk relief: the cut's floor a shade darker than the stone, its upper-left wall in shadow, lower-right wall lit."""
    off = 3 * SS
    shadow = ImageChops.subtract(mask, ImageChops.offset(mask, off, off))
    light = ImageChops.subtract(mask, ImageChops.offset(mask, -off, -off))
    floor = Image.new("RGBA", mask.size, (120, 88, 52, 0))
    floor.putalpha(mask.point(lambda a: int(a * 0.85)))
    dark = Image.new("RGBA", mask.size, (52, 34, 18, 0))
    dark.putalpha(shadow.filter(ImageFilter.GaussianBlur(SS)))
    lit = Image.new("RGBA", mask.size, (236, 210, 160, 0))
    lit.putalpha(light.filter(ImageFilter.GaussianBlur(SS)).point(lambda a: int(a * 0.8)))
    out = Image.alpha_composite(floor, dark)
    out = Image.alpha_composite(out, lit)
    return out.resize((FACE_W, FACE_H), Image.LANCZOS)


def main():
    atlas = Image.new("RGBA", (FACE_W, FACE_H * 4), (0, 0, 0, 0))
    for face_i in range(4):
        atlas.paste(carve(paint_face(face_i)), (0, FACE_H * face_i))
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    atlas.save(OUT)
    print("frieze", OUT)
    if len(sys.argv) > 1:  # a preview on sandstone
        bg = Image.new("RGBA", atlas.size, (219, 184, 128, 255))
        Image.alpha_composite(bg, atlas).convert("RGB").save(sys.argv[1])


if __name__ == "__main__":
    main()
