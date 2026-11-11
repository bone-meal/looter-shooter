# Purpose: developer-time script. Draws the game's icon sheet: one 64 x 64 picture per shape (items, skills, stations,
# armour slots, UI signs) in two layers that the game lays over each other (game/icon_art.gd):
#   assets/ui/icons_tint.png  the part that takes the item's own colour (white = full colour, grey = shaded) and the
#                             dark outline round the whole shape (black stays black under any colour)
#   assets/ui/icons_ink.png   the parts whose colour never changes (wooden handles, glass, cork, eyes ...)
# and data/icons.json (which cell each shape is in). Shapes are drawn on a 100 x 100 grid at four times the size
# and scaled down, so edges are smooth. To add an icon: write a function below, add it to SHAPES, run this script.
# Run: python3 tools/make_icons.py   (from the project folder; needs pip package pillow)
import json
import math
import os

from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.join(os.path.dirname(__file__), "..")
CELL = 64
BIG = 256
K = BIG / 100.0
COLUMNS = 12

WOOD = (120, 82, 48, 255)
WOOD_D = (84, 56, 34, 255)
STEEL = (176, 182, 192, 255)
STEEL_D = (110, 116, 128, 255)
CREAM = (236, 222, 190, 255)
GOLD = (232, 190, 84, 255)
DARK = (40, 36, 40, 255)
GREEN = (84, 140, 70, 255)
WHITE = (255, 255, 255, 255)
LIGHT = 255
MID = 200
SHADE = 150


class Icon:
    def __init__(self):
        self.tint = Image.new("RGBA", (BIG, BIG), (0, 0, 0, 0))
        self.ink = Image.new("RGBA", (BIG, BIG), (0, 0, 0, 0))
        self.t = ImageDraw.Draw(self.tint)
        self.i = ImageDraw.Draw(self.ink)

    @staticmethod
    def _pts(points):
        return [(x * K, y * K) for x, y in points]

    @staticmethod
    def _fill(value):
        return (value, value, value, 255) if isinstance(value, int) else value

    def _on(self, value):
        return self.t if isinstance(value, int) else self.i

    # a number = a shade of the tint layer (takes the item's colour); a colour tuple = ink (fixed colour)
    def poly(self, points, value=LIGHT):
        self._on(value).polygon(self._pts(points), fill=self._fill(value))

    def oval(self, x0, y0, x1, y1, value=LIGHT):
        self._on(value).ellipse([x0 * K, y0 * K, x1 * K, y1 * K], fill=self._fill(value))

    def ring(self, x0, y0, x1, y1, width, value=LIGHT):
        self._on(value).ellipse([x0 * K, y0 * K, x1 * K, y1 * K], outline=self._fill(value), width=int(width * K))

    def chord(self, x0, y0, x1, y1, a0, a1, value=LIGHT):
        self._on(value).chord([x0 * K, y0 * K, x1 * K, y1 * K], a0, a1, fill=self._fill(value))

    def pie(self, x0, y0, x1, y1, a0, a1, value=LIGHT):
        self._on(value).pieslice([x0 * K, y0 * K, x1 * K, y1 * K], a0, a1, fill=self._fill(value))

    def arc(self, x0, y0, x1, y1, a0, a1, width, value=LIGHT):
        self._on(value).arc([x0 * K, y0 * K, x1 * K, y1 * K], a0, a1, fill=self._fill(value), width=int(width * K))

    def line(self, points, width, value=LIGHT):
        d = self._on(value)
        pts = self._pts(points)
        d.line(pts, fill=self._fill(value), width=int(width * K), joint="curve")
        r = width * K / 2.0
        for x, y in (pts[0], pts[-1]):
            d.ellipse([x - r, y - r, x + r, y + r], fill=self._fill(value))

    def done(self):
        alpha = Image.new("L", (BIG, BIG), 0)
        alpha.paste(self.tint.getchannel("A"), (0, 0))
        alpha = Image.composite(Image.new("L", (BIG, BIG), 255), alpha, self.ink.getchannel("A").point(lambda v: 255 if v > 40 else 0))
        edge = alpha.filter(ImageFilter.MaxFilter(11)).filter(ImageFilter.GaussianBlur(1.2))
        under = Image.new("RGBA", (BIG, BIG), (0, 0, 0, 0))
        under.putalpha(edge.point(lambda v: int(v * 0.9)))
        tint = Image.alpha_composite(under, self.tint)
        return tint.resize((CELL, CELL), Image.LANCZOS), self.ink.resize((CELL, CELL), Image.LANCZOS)


def star(cx, cy, outer, inner, points=5, turn=-90.0):
    out = []
    for k in range(points * 2):
        r = outer if k % 2 == 0 else inner
        a = math.radians(turn + k * 180.0 / points)
        out.append((cx + math.cos(a) * r, cy + math.sin(a) * r))
    return out


def leaf(cx, cy, length, width, angle):
    a = math.radians(angle)
    ux, uy = math.cos(a), math.sin(a)
    vx, vy = -uy, ux
    return [(cx, cy), (cx + ux * length * 0.5 + vx * width, cy + uy * length * 0.5 + vy * width), (cx + ux * length, cy + uy * length),
            (cx + ux * length * 0.5 - vx * width, cy + uy * length * 0.5 - vy * width)]


# ---------------- fantasy items ----------------
def staff(c):
    c.line([(24, 90), (64, 34)], 6, DARK)
    c.line([(60, 38), (56, 20), (70, 8)], 5, DARK)
    c.line([(66, 40), (84, 34), (92, 18)], 5, DARK)
    c.oval(60, 12, 84, 36, LIGHT)
    c.oval(65, 16, 74, 25, WHITE)
    c.line([(27, 86), (31, 80)], 8, STEEL)

def robe(c):
    c.poly([(34, 14), (66, 14), (88, 40), (76, 50), (72, 44), (76, 90), (24, 90), (28, 44), (24, 50), (12, 40)], MID)
    c.poly([(40, 14), (60, 14), (50, 34)], SHADE)
    c.poly([(46, 34), (54, 34), (58, 90), (42, 90)], LIGHT)
    c.poly([(28, 52), (72, 52), (72, 60), (28, 60)], WOOD)
    c.oval(46, 51, 54, 61, GOLD)

def axe(c):
    c.line([(30, 90), (60, 24)], 7, WOOD)
    c.poly([(50, 18), (72, 10), (92, 26), (90, 50), (70, 42), (58, 38)], LIGHT)
    c.poly([(72, 10), (92, 26), (90, 50), (82, 30)], MID)

def pickaxe(c):
    c.line([(28, 90), (62, 26)], 7, WOOD)
    c.poly([(18, 40), (44, 18), (78, 12), (96, 30), (76, 24), (52, 28), (30, 44)], LIGHT)
    c.poly([(44, 18), (78, 12), (96, 30), (76, 24), (52, 28)], MID)

def rod(c):
    c.line([(16, 88), (84, 14)], 4, WOOD)
    c.line([(84, 14), (84, 58)], 1.4, (230, 230, 230, 255))
    c.oval(77, 56, 91, 70, LIGHT)
    c.chord(77, 56, 91, 70, 0, 180, WHITE)
    c.line([(18, 86), (30, 73)], 8, MID)
    c.oval(28, 60, 42, 74, STEEL_D)

def bread(c):
    c.oval(10, 36, 90, 80, SHADE)
    c.oval(10, 30, 90, 72, LIGHT)
    for x in (30, 46, 62):
        c.line([(x, 40), (x + 10, 58)], 3.5, (255, 240, 205, 230))

def _fish(c, x0=14, y0=32, x1=74, y1=68):
    mid = (y0 + y1) / 2
    c.poly([(x1 - 8, mid), (x1 + 18, y0 - 2), (x1 + 12, mid), (x1 + 18, y1 + 2)], MID)
    c.oval(x0, y0, x1, y1, LIGHT)
    c.chord(x0, y0, x1, y1, 20, 160, MID)
    c.poly([(x0 + 26, y0 + 2), (x0 + 40, y0 - 10), (x0 + 46, y0 + 4)], MID)

def fish(c):
    _fish(c)
    c.oval(24, 42, 34, 52, WHITE)
    c.oval(27, 45, 32, 50, DARK)

def cooked_fish(c):
    c.oval(6, 64, 94, 94, (214, 214, 220, 255))
    c.oval(14, 68, 86, 90, (240, 240, 244, 255))
    _fish(c, 16, 34, 72, 66)
    for x in (30, 42, 54):
        c.line([(x, 38), (x + 8, 62)], 2.6, (70, 46, 30, 220))
    c.line([(26, 22), (22, 14), (28, 8)], 2, (255, 255, 255, 190))
    c.line([(50, 22), (46, 14), (52, 8)], 2, (255, 255, 255, 190))

def stew(c):
    c.oval(12, 36, 88, 66, LIGHT)  # the stew; the bowl (ink) covers its lower half
    c.oval(30, 40, 42, 47, MID)
    c.oval(54, 41, 66, 48, MID)
    c.chord(10, 10, 90, 92, 0, 180, WOOD)
    c.chord(10, 30, 90, 92, 0, 180, WOOD_D)
    c.line([(36, 30), (32, 20), (38, 12)], 2.4, (255, 255, 255, 200))
    c.line([(60, 30), (56, 20), (62, 12)], 2.4, (255, 255, 255, 200))

def potion(c):
    c.oval(22, 36, 78, 92, (205, 232, 255, 110))
    c.poly([(42, 18), (58, 18), (58, 44), (42, 44)], (205, 232, 255, 110))
    c.chord(26, 40, 74, 88, -20, 200, LIGHT)
    c.chord(26, 40, 74, 88, 30, 150, MID)
    c.poly([(40, 8), (60, 8), (58, 20), (42, 20)], WOOD)
    c.oval(34, 54, 42, 66, (255, 255, 255, 200))

def log(c):
    c.poly([(16, 36), (76, 36), (76, 70), (16, 70)], MID)
    c.oval(8, 36, 24, 70, MID)
    c.line([(24, 46), (58, 46)], 2.4, (0, 0, 0, 70))
    c.line([(30, 58), (66, 58)], 2.4, (0, 0, 0, 70))
    c.oval(64, 34, 90, 72, (232, 204, 156, 255))
    c.ring(70, 43, 84, 63, 1.6, (170, 132, 88, 255))
    c.oval(75, 50, 79, 56, (170, 132, 88, 255))

def ore(c):
    c.poly([(16, 72), (26, 40), (50, 20), (78, 32), (88, 64), (70, 86), (32, 88)], 95)  # the rock is a dark shade of the ore's colour
    c.poly([(26, 40), (50, 20), (56, 46), (36, 56)], 125)
    for x, y, r in ((40, 36, 7), (64, 46, 8), (46, 66, 9), (72, 68, 6), (28, 62, 5)):
        c.poly(star(x, y, r, r * 0.5, 4, 20), LIGHT)

def bar(c):
    c.poly([(20, 44), (64, 34), (86, 46), (42, 58)], LIGHT)
    c.poly([(42, 58), (86, 46), (82, 70), (38, 82)], MID)
    c.poly([(20, 44), (42, 58), (38, 82), (16, 66)], SHADE)

def crystal(c):
    c.poly([(50, 6), (68, 30), (62, 88), (40, 88), (32, 30)], MID)
    c.poly([(50, 6), (50, 88), (40, 88), (32, 30)], LIGHT)
    c.poly([(70, 50), (84, 62), (80, 88), (64, 88)], SHADE)
    c.poly([(22, 56), (32, 66), (34, 88), (20, 88), (14, 66)], MID)
    c.line([(42, 30), (44, 60)], 2, (255, 255, 255, 180))

def herb(c):
    c.line([(50, 92), (50, 40)], 3, GREEN)
    for cx, cy, ang in ((50, 60, 200), (50, 60, -20), (50, 44, 220), (50, 44, -40), (50, 40, -90)):
        c.poly(leaf(cx, cy, 34, 10, ang), LIGHT)
    c.poly(leaf(50, 40, 34, 4, -90), MID)

def mushroom(c):
    c.poly([(40, 52), (60, 52), (64, 90), (36, 90)], CREAM)
    c.pie(12, 14, 88, 96, 180, 360, LIGHT)
    c.chord(12, 44, 88, 66, 0, 180, MID)
    for x, y, r in ((34, 30, 6), (58, 26, 7), (70, 42, 4), (46, 42, 4)):
        c.oval(x - r, y - r, x + r, y + r, (255, 255, 255, 230))

def flower(c):
    c.line([(50, 54), (46, 92)], 3.4, GREEN)
    c.poly(leaf(47, 78, 22, 7, -30), GREEN)
    for k in range(5):
        a = math.radians(-90 + k * 72)
        x, y = 50 + math.cos(a) * 18, 36 + math.sin(a) * 18
        c.oval(x - 13, y - 13, x + 13, y + 13, LIGHT if k % 2 == 0 else MID)
    c.oval(41, 27, 59, 45, GOLD)

def wheat(c):
    c.line([(50, 94), (50, 30)], 2.6, (190, 160, 80, 255))
    for k in range(5):
        y = 62 - k * 11
        c.poly(leaf(50, y, 18, 6, -140), LIGHT)
        c.poly(leaf(50, y, 18, 6, -40), MID)
    c.poly(leaf(50, 20, 16, 6, -90), LIGHT)

def straw(c):
    c.poly([(28, 12), (72, 12), (62, 48), (78, 90), (22, 90), (38, 48)], LIGHT)
    for x0, x1 in ((36, 30), (46, 42), (56, 58), (66, 70)):
        c.line([(x0, 16), (50 + (x0 - 50) * 0.5, 48), (x1, 86)], 1.6, (0, 0, 0, 60))
    c.poly([(36, 42), (64, 42), (64, 54), (36, 54)], WOOD)

def jelly(c):
    c.chord(12, 22, 88, 142, 180, 360, LIGHT)
    c.chord(12, 62, 88, 102, 0, 180, MID)
    c.oval(30, 36, 44, 50, (255, 255, 255, 210))
    c.oval(60, 52, 66, 58, (255, 255, 255, 170))

def pelt(c):
    c.poly([(28, 10), (50, 20), (72, 10), (88, 28), (72, 46), (88, 74), (68, 90), (50, 78), (32, 90), (12, 74), (28, 46), (12, 28)], LIGHT)
    c.poly([(40, 26), (60, 26), (64, 70), (50, 66), (36, 70)], MID)

def shell(c):
    c.pie(6, 16, 94, 104, 200, 340, LIGHT)
    c.poly([(38, 62), (62, 62), (58, 82), (42, 82)], MID)
    for ang in (215, 240, 270, 300, 325):
        a = math.radians(ang)
        c.line([(50, 62), (50 + math.cos(a) * 40, 60 + math.sin(a) * 40)], 1.8, (0, 0, 0, 80))

def sting(c):
    c.poly([(28, 90), (20, 62), (34, 34), (62, 14), (86, 12), (64, 30), (50, 50), (46, 72), (44, 90)], LIGHT)
    c.poly([(62, 14), (86, 12), (64, 30)], SHADE)
    c.line([(32, 60), (40, 40), (56, 26)], 2, (255, 255, 255, 170))

def pigment(c):
    c.oval(22, 30, 78, 60, LIGHT)  # the paint; the pot (ink) covers its lower half like a rim
    c.oval(34, 36, 50, 44, WHITE)
    c.poly([(22, 48), (78, 48), (70, 90), (30, 90)], (156, 112, 80, 255))
    c.poly([(22, 48), (40, 48), (42, 90), (30, 90)], (126, 88, 62, 255))

def root(c):
    c.poly([(40, 10), (60, 10), (64, 36), (84, 52), (78, 60), (62, 50), (64, 76), (56, 92), (50, 74), (44, 60), (28, 76), (20, 70), (36, 50), (38, 30)], LIGHT)
    c.poly([(40, 10), (50, 10), (50, 74), (44, 60), (38, 30)], MID)
    c.poly(leaf(50, 12, 16, 5, -120), GREEN)
    c.poly(leaf(50, 12, 16, 5, -60), GREEN)

# ---------------- skills, stations ----------------
def flame(c):
    c.poly([(50, 6), (70, 34), (82, 60), (70, 86), (50, 94), (30, 86), (18, 60), (30, 40), (38, 52), (42, 30)], LIGHT)
    c.poly([(50, 40), (62, 60), (60, 80), (50, 88), (40, 80), (38, 62)], (255, 226, 120, 255))
    c.poly([(50, 60), (56, 72), (50, 84), (44, 72)], WHITE)

def pot(c):
    c.oval(16, 22, 84, 50, LIGHT)  # what is cooking; the pot (ink) covers its lower half
    c.oval(34, 26, 46, 32, WHITE)
    c.chord(12, 0, 88, 92, 10, 170, (52, 50, 56, 255))
    c.poly([(8, 38), (92, 38), (88, 46), (12, 46)], (84, 82, 90, 255))
    c.line([(26, 88), (20, 96)], 5, (52, 50, 56, 255))
    c.line([(74, 88), (80, 96)], 5, (52, 50, 56, 255))
    c.line([(40, 22), (36, 12), (42, 4)], 2.4, (255, 255, 255, 190))
    c.line([(60, 22), (56, 12), (62, 4)], 2.4, (255, 255, 255, 190))

def anvil(c):
    c.poly([(10, 32), (72, 32), (94, 42), (72, 50), (64, 62), (68, 78), (84, 90), (20, 90), (34, 78), (38, 62), (26, 50), (10, 44)], STEEL_D)
    c.poly([(10, 32), (72, 32), (94, 42), (72, 40), (10, 38)], STEEL)

def hammer(c):
    c.line([(26, 90), (58, 40)], 7, WOOD)
    c.poly([(36, 28), (72, 8), (88, 32), (52, 52)], STEEL)
    c.poly([(36, 28), (72, 8), (76, 14), (40, 34)], WHITE)
    c.poly([(52, 52), (88, 32), (86, 28), (50, 48)], STEEL_D)

def spark(c):
    c.poly(star(46, 52, 40, 12, 4), LIGHT)
    c.poly(star(46, 52, 18, 6, 4, -45), MID)
    c.poly(star(80, 20, 14, 4, 4), LIGHT)
    c.poly(star(82, 82, 10, 3, 4), MID)

# ---------------- UI signs ----------------
def bag(c):
    c.poly([(30, 36), (70, 36), (88, 70), (76, 92), (24, 92), (12, 70)], LIGHT)
    c.poly([(30, 36), (44, 36), (36, 92), (24, 92), (12, 70)], MID)
    c.poly([(36, 14), (64, 14), (70, 36), (30, 36)], MID)
    c.line([(30, 36), (70, 36)], 5, WOOD)

def scroll(c):
    c.poly([(24, 18), (76, 18), (76, 82), (24, 82)], CREAM)
    c.oval(16, 10, 84, 26, (214, 196, 160, 255))
    c.oval(16, 74, 84, 90, (214, 196, 160, 255))
    for y in (36, 46, 56, 66):
        c.line([(34, y), (66 if y != 66 else 54, y)], 2.4, (90, 70, 50, 255))

def book(c):
    c.poly([(18, 14), (76, 14), (84, 22), (84, 90), (26, 90), (18, 82)], MID)
    c.poly([(18, 14), (76, 14), (76, 82), (18, 82)], LIGHT)
    c.poly([(26, 84), (82, 84), (82, 88), (28, 88)], CREAM)
    c.poly(star(47, 46, 18, 7, 4), GOLD)
    c.poly([(18, 14), (26, 14), (26, 82), (18, 82)], SHADE)

def map_sign(c):
    c.poly([(10, 24), (36, 14), (64, 24), (90, 14), (90, 78), (64, 88), (36, 78), (10, 88)], CREAM)
    c.poly([(36, 14), (64, 24), (64, 88), (36, 78)], (214, 198, 164, 255))
    c.line([(22, 60), (34, 48), (50, 56), (62, 42)], 2.4, (120, 92, 60, 255))
    c.line([(70, 34), (82, 46)], 3.4, (190, 50, 44, 255))
    c.line([(82, 34), (70, 46)], 3.4, (190, 50, 44, 255))

def talk(c):
    c.oval(8, 12, 92, 70, LIGHT)
    c.poly([(28, 60), (20, 90), (50, 66)], LIGHT)
    for x in (32, 50, 68):
        c.oval(x - 5, 36, x + 5, 46, (60, 54, 50, 255))

def sword(c):
    c.poly([(80, 8), (90, 10), (88, 20), (44, 66), (34, 56)], STEEL)
    c.poly([(80, 8), (90, 10), (40, 62), (34, 56)], WHITE)
    c.line([(26, 52), (48, 74)], 6, GOLD)
    c.line([(36, 64), (20, 80)], 6, WOOD)
    c.oval(10, 78, 24, 92, GOLD)

def pin(c):
    c.poly([(26, 40), (74, 40), (50, 92)], MID)
    c.oval(22, 8, 78, 64, LIGHT)
    c.oval(38, 24, 62, 48, WHITE)

def lock(c):
    c.arc(28, 10, 72, 62, 180, 360, 7, STEEL)
    c.poly([(20, 44), (80, 44), (80, 90), (20, 90)], GOLD)
    c.oval(43, 56, 57, 70, DARK)
    c.poly([(47, 66), (53, 66), (55, 80), (45, 80)], DARK)

def check(c):
    c.line([(16, 54), (40, 78), (86, 22)], 12, LIGHT)

def cross(c):
    c.line([(20, 20), (80, 80)], 12, LIGHT)
    c.line([(80, 20), (20, 80)], 12, LIGHT)

def heart(c):
    c.oval(10, 16, 54, 60, LIGHT)
    c.oval(46, 16, 90, 60, LIGHT)
    c.poly([(14, 48), (86, 48), (50, 92)], LIGHT)
    c.oval(22, 24, 36, 38, WHITE)

def drop(c):
    c.poly([(50, 6), (76, 52), (24, 52)], LIGHT)
    c.oval(20, 36, 80, 94, LIGHT)
    c.chord(20, 36, 80, 94, 20, 160, MID)
    c.oval(34, 52, 44, 66, WHITE)

def shield(c):
    c.poly([(14, 14), (86, 14), (86, 52), (50, 94), (14, 52)], LIGHT)
    c.poly([(50, 14), (86, 14), (86, 52), (50, 94)], MID)
    c.oval(40, 34, 60, 54, GOLD)

def clock(c):
    c.oval(10, 10, 90, 90, STEEL_D)
    c.oval(16, 16, 84, 84, CREAM)
    c.line([(50, 50), (50, 26)], 4, DARK)
    c.line([(50, 50), (68, 58)], 4, DARK)

def star_sign(c):
    c.poly(star(50, 52, 44, 18), LIGHT)

def arrow(c):
    c.poly([(10, 38), (56, 38), (56, 18), (92, 50), (56, 82), (56, 62), (10, 62)], LIGHT)

def skull(c):
    c.oval(14, 8, 86, 72, CREAM)
    c.poly([(30, 60), (70, 60), (66, 90), (34, 90)], CREAM)
    c.oval(26, 32, 46, 54, DARK)
    c.oval(54, 32, 74, 54, DARK)
    c.poly([(50, 54), (56, 66), (44, 66)], DARK)
    for x in (42, 50, 58):
        c.line([(x, 74), (x, 90)], 2, DARK)

def coin(c):
    c.oval(10, 10, 90, 90, MID)
    c.oval(18, 18, 82, 82, LIGHT)
    c.poly(star(50, 50, 22, 9, 4), MID)

def exclaim(c):
    c.poly([(40, 8), (60, 8), (56, 64), (44, 64)], LIGHT)
    c.oval(40, 74, 60, 94, LIGHT)

def dots(c):
    for x in (22, 50, 78):
        c.oval(x - 11, 39, x + 11, 61, LIGHT)

def empty(c):
    c.ring(14, 14, 86, 86, 6, LIGHT)
    c.line([(26, 74), (74, 26)], 6, LIGHT)

# ---------------- armour slots (the gun side's equipment) ----------------
def hat(c):
    c.chord(22, 16, 78, 88, 180, 360, LIGHT)
    c.oval(6, 46, 94, 70, MID)
    c.poly([(22, 48), (78, 48), (78, 56), (22, 56)], SHADE)

def helm(c):
    c.chord(14, 8, 86, 100, 180, 360, LIGHT)
    c.poly([(14, 52), (86, 52), (86, 80), (62, 92), (62, 62), (38, 62), (38, 92), (14, 80)], LIGHT)
    c.poly([(46, 8), (54, 8), (54, 52), (46, 52)], MID)
    c.poly([(24, 46), (76, 46), (76, 54), (24, 54)], DARK)

def earrings(c):
    for x in (30, 70):
        c.line([(x, 8), (x, 26)], 3, LIGHT)
        c.ring(x - 18, 24, x + 18, 68, 6, LIGHT)
        c.oval(x - 7, 62, x + 7, 76, MID)

def necklace(c):
    c.arc(12, -30, 88, 64, 10, 170, 3.4, GOLD)
    c.poly([(50, 54), (64, 70), (50, 94), (36, 70)], LIGHT)
    c.poly([(50, 54), (64, 70), (50, 76)], WHITE)

def glasses(c):
    c.oval(8, 34, 46, 72, LIGHT)
    c.oval(54, 34, 92, 72, LIGHT)
    c.ring(8, 34, 46, 72, 4, DARK)
    c.ring(54, 34, 92, 72, 4, DARK)
    c.line([(44, 48), (56, 48)], 4, DARK)
    c.line([(18, 44), (26, 40)], 3, (255, 255, 255, 170))
    c.line([(64, 44), (72, 40)], 3, (255, 255, 255, 170))

def shirt(c):
    c.poly([(30, 12), (42, 18), (58, 18), (70, 12), (94, 32), (82, 48), (72, 40), (72, 90), (28, 90), (28, 40), (18, 48), (6, 32)], LIGHT)
    c.poly([(42, 18), (58, 18), (50, 30)], SHADE)
    c.poly([(28, 78), (72, 78), (72, 90), (28, 90)], MID)

def chestplate(c):
    c.poly([(26, 10), (40, 18), (60, 18), (74, 10), (90, 30), (78, 44), (80, 76), (50, 94), (20, 76), (22, 44), (10, 30)], LIGHT)
    c.poly([(50, 18), (60, 18), (74, 10), (90, 30), (78, 44), (80, 76), (50, 94)], MID)
    c.line([(26, 52), (50, 62), (74, 52)], 2.6, (0, 0, 0, 90))
    c.line([(24, 68), (50, 78), (76, 68)], 2.6, (0, 0, 0, 90))

def gauntlets(c):
    c.poly([(30, 92), (28, 56), (22, 36), (30, 30), (36, 44), (36, 14), (46, 12), (48, 38), (50, 10), (60, 10), (60, 38), (64, 14), (73, 16), (72, 42), (78, 28), (86, 32), (80, 58), (72, 72), (72, 92)], LIGHT)
    c.poly([(28, 70), (74, 70), (72, 92), (30, 92)], MID)
    c.line([(30, 72), (72, 72)], 2.4, (0, 0, 0, 90))

def ring(c):
    c.ring(18, 30, 82, 94, 10, LIGHT)
    c.arc(18, 30, 82, 94, 20, 160, 10, MID)
    c.poly([(50, 6), (66, 22), (50, 40), (34, 22)], (120, 220, 255, 255))
    c.poly([(50, 6), (66, 22), (50, 22)], WHITE)

def bracelet(c):
    c.ring(10, 26, 90, 82, 14, LIGHT)
    c.arc(10, 26, 90, 82, 10, 170, 14, MID)
    for x, y in ((26, 68), (50, 76), (74, 68)):
        c.oval(x - 6, y - 6, x + 6, y + 6, GOLD)

def pants(c):
    c.poly([(22, 10), (78, 10), (84, 92), (58, 92), (50, 40), (42, 92), (16, 92)], LIGHT)
    c.poly([(22, 10), (78, 10), (79, 22), (21, 22)], MID)
    c.poly([(50, 22), (78, 22), (84, 92), (58, 92), (50, 40)], MID)

def leg_armor(c):
    for x in (14, 54):
        c.poly([(x, 10), (x + 32, 10), (x + 30, 50), (x + 34, 92), (x - 2, 92), (x + 2, 50)], LIGHT)
        c.oval(x + 3, 38, x + 29, 62, MID)
        c.line([(x + 2, 74), (x + 30, 74)], 2.4, (0, 0, 0, 90))

def cape(c):
    c.poly([(30, 10), (70, 10), (78, 28), (92, 90), (70, 82), (50, 94), (30, 82), (8, 90), (22, 28)], LIGHT)
    c.poly([(50, 14), (70, 10), (78, 28), (92, 90), (70, 82), (50, 94)], MID)
    c.line([(32, 14), (68, 14)], 5, GOLD)

def belt(c):
    c.poly([(4, 36), (96, 36), (96, 64), (4, 64)], LIGHT)
    c.poly([(4, 56), (96, 56), (96, 64), (4, 64)], MID)
    c.poly([(36, 28), (64, 28), (64, 72), (36, 72)], GOLD)
    c.poly([(43, 36), (57, 36), (57, 64), (43, 64)], DARK)

def boots(c):
    c.poly([(30, 8), (60, 8), (60, 56), (88, 68), (92, 90), (28, 90)], LIGHT)
    c.poly([(28, 82), (92, 82), (92, 92), (28, 92)], DARK)
    c.poly([(30, 8), (60, 8), (60, 20), (30, 20)], MID)

def sabatons(c):
    c.poly([(30, 8), (60, 8), (60, 50), (84, 62), (96, 84), (92, 90), (28, 90)], LIGHT)
    for y0, y1 in ((30, 30), (48, 48)):
        c.line([(30, y0), (60, y1)], 2.6, (0, 0, 0, 90))
    c.line([(60, 52), (50, 88)], 2.6, (0, 0, 0, 90))
    c.line([(76, 60), (66, 88)], 2.6, (0, 0, 0, 90))
    c.poly([(28, 84), (94, 84), (92, 92), (28, 92)], MID)


SHAPES = [("staff", staff), ("robe", robe), ("axe", axe), ("pickaxe", pickaxe), ("rod", rod), ("bread", bread), ("fish", fish), ("cooked_fish", cooked_fish),
    ("stew", stew), ("potion", potion), ("log", log), ("ore", ore), ("bar", bar), ("crystal", crystal), ("herb", herb), ("mushroom", mushroom), ("flower", flower),
    ("wheat", wheat), ("straw", straw), ("jelly", jelly), ("pelt", pelt), ("shell", shell), ("sting", sting), ("pigment", pigment), ("root", root),
    ("flame", flame), ("pot", pot), ("anvil", anvil), ("hammer", hammer), ("spark", spark),
    ("bag", bag), ("scroll", scroll), ("book", book), ("map", map_sign), ("talk", talk), ("sword", sword), ("pin", pin), ("lock", lock), ("check", check),
    ("cross", cross), ("heart", heart), ("drop", drop), ("shield", shield), ("clock", clock), ("star", star_sign), ("arrow", arrow), ("skull", skull),
    ("coin", coin), ("exclaim", exclaim), ("dots", dots), ("empty", empty),
    ("hat", hat), ("helm", helm), ("earrings", earrings), ("necklace", necklace), ("glasses", glasses), ("shirt", shirt), ("chestplate", chestplate),
    ("gauntlets", gauntlets), ("ring", ring), ("bracelet", bracelet), ("pants", pants), ("leg_armor", leg_armor), ("cape", cape), ("belt", belt),
    ("boots", boots), ("sabatons", sabatons)]


def main():
    rows = (len(SHAPES) + COLUMNS - 1) // COLUMNS
    tint_sheet = Image.new("RGBA", (COLUMNS * CELL, rows * CELL), (0, 0, 0, 0))
    ink_sheet = Image.new("RGBA", (COLUMNS * CELL, rows * CELL), (0, 0, 0, 0))
    cells = {}
    for index, (name, draw) in enumerate(SHAPES):
        icon = Icon()
        draw(icon)
        tint, ink = icon.done()
        at = ((index % COLUMNS) * CELL, (index // COLUMNS) * CELL)
        tint_sheet.paste(tint, at)
        ink_sheet.paste(ink, at)
        cells[name] = index
    os.makedirs(os.path.join(ROOT, "assets", "ui"), exist_ok=True)
    tint_sheet.save(os.path.join(ROOT, "assets", "ui", "icons_tint.png"))
    ink_sheet.save(os.path.join(ROOT, "assets", "ui", "icons_ink.png"))
    about = "The icon sheet (made by tools/make_icons.py, drawn by game/icon_art.gd): cell = size of one icon in pixels, columns = icons per row, shapes = name -> which cell (counted along the rows from 0)."
    json.dump({"version": 1, "_about": about, "cell": CELL, "columns": COLUMNS, "shapes": cells}, open(os.path.join(ROOT, "data", "icons.json"), "w"), indent=1)
    print(len(SHAPES), "icons", tint_sheet.size)


if __name__ == "__main__":
    main()
