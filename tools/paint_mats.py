# Purpose: paints the play mats of "You got me Lobster?" (data/tcg/mats.json) into assets/tcg/mats/<id>.jpg, 1024 x 608
# (the table's mat is 1.42 x 0.84 m). Each mat: its own surface (felt, water, rusted plates, stone, wheat, neon, wood,
# velvet ...), a rim, a faint logo on the centre line, and on each half the spots of data/tcg/mat_layout.json: seven
# creature spots on an arc, the leader's round portrait at the back, a deck and a discard spot. The near half (bottom of the picture) is the owner's: the table shows each player's
# own mat on their half. Developer-time (Pillow + numpy).
# Usage: python3 tools/paint_mats.py [mat ids ...]
# Dependencies: Pillow, numpy; data/tcg/mats.json, data/tcg/mat_layout.json, assets/tcg/logo.png, assets/fonts/Cinzel.ttf.
import json
import math
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
OUT = os.path.join(ROOT, "assets", "tcg", "mats")
W, H = 1024, 608
RNG = np.random.default_rng(5)


def noise(scale, octaves=4, seed=0):
    """Smooth value noise 0..1 at the mat size."""
    rng = np.random.default_rng(seed)
    out = np.zeros((H, W), np.float32)
    amp, total = 1.0, 0.0
    for o in range(octaves):
        s = max(2, int(scale * (2 ** o)))
        small = rng.random((s * H // W + 2, s + 2)).astype(np.float32)
        img = Image.fromarray((small * 255).astype(np.uint8)).resize((W, H), Image.BICUBIC)
        out += np.asarray(img, np.float32) / 255.0 * amp
        total += amp
        amp *= 0.5
    return out / total


def colour(base, var, n):
    """A colour field: base colour moved by var times noise n (-0.5..0.5)."""
    img = np.zeros((H, W, 3), np.float32)
    for i in range(3):
        img[..., i] = base[i] + var[i] * (n - 0.5)
    return img


def to_img(a):
    return Image.fromarray(np.clip(a, 0, 255).astype(np.uint8)).convert("RGB")


def surface(kind):
    y, x = np.mgrid[0:H, 0:W].astype(np.float32)
    if kind == "felt":
        return to_img(colour((22, 92, 60), (30, 40, 30), noise(60, 3, 1) * 0.6 + noise(8, 3, 2) * 0.4))
    if kind == "water":
        n = noise(6, 4, 3)
        waves = np.sin(x / 22.0 + n * 14.0 + y / 40.0) * 0.5 + 0.5
        a = colour((18, 70, 120), (40, 60, 70), n)
        a += (waves ** 10)[..., None] * np.array([40, 70, 80], np.float32)  # soft caustic ripples
        return to_img(a)
    if kind == "rust":
        n = noise(10, 5, 4)
        a = colour((120, 66, 34), (90, 60, 40), n)
        img = to_img(a)
        d = ImageDraw.Draw(img)
        for px in range(0, W, 256):  # plates and rivets
            for py in range(0, H, 152):
                d.rectangle([px + 3, py + 3, px + 253, py + 149], outline=(60, 34, 20), width=4)
                for rx, ry in ((14, 14), (240, 14), (14, 138), (240, 138)):
                    d.ellipse([px + rx - 6, py + ry - 6, px + rx + 6, py + ry + 6], fill=(150, 110, 80), outline=(50, 30, 20))
        return img
    if kind == "stone":
        n = noise(14, 4, 5)
        img = to_img(colour((92, 90, 96), (50, 50, 55), n))
        d = ImageDraw.Draw(img)
        for row, py in enumerate(range(0, H, 76)):
            off = 0 if row % 2 == 0 else 64
            for px in range(-off, W, 128):
                d.rectangle([px, py, px + 126, py + 74], outline=(48, 46, 52), width=3)
        return img
    if kind == "wheat":
        n = noise(5, 4, 6)
        img = to_img(colour((170, 150, 70), (60, 60, 40), n))
        d = ImageDraw.Draw(img)
        rng = np.random.default_rng(7)
        for i in range(2600):  # stalks
            sx, sy = rng.random() * W, rng.random() * H
            ln = 10 + rng.random() * 18
            ang = -1.3 + rng.random() * 0.5
            c = (int(200 + rng.random() * 40), int(170 + rng.random() * 40), int(80 + rng.random() * 30))
            d.line([sx, sy, sx + math.cos(ang) * ln, sy + math.sin(ang) * ln], fill=c, width=2)
        return img
    if kind == "neon":
        img = to_img(colour((10, 6, 18), (10, 6, 16), noise(8, 3, 8)))
        glow = Image.new("RGB", (W, H), (0, 0, 0))
        d = ImageDraw.Draw(glow)
        for i in range(0, W, 64):
            d.line([i, 0, i - 200, H], fill=(255, 40, 170), width=3)
        for i in range(0, H, 64):
            d.line([0, i, W, i], fill=(40, 220, 255), width=2)
        return Image.blend(img, Image.composite(glow.filter(ImageFilter.GaussianBlur(4)), img, glow.convert("L")), 0.85)
    if kind == "wood":
        n = noise(4, 3, 9)
        grain = np.sin(y / 3.0 + n * 30.0) * 0.5 + 0.5
        a = colour((150, 112, 72), (50, 40, 30), n)
        a -= (grain ** 3)[..., None] * 35
        img = to_img(a)
        d = ImageDraw.Draw(img)
        for py in range(0, H, 101):  # planks
            d.line([0, py, W, py], fill=(70, 48, 30), width=4)
        return img
    if kind == "velvet":
        n = noise(40, 3, 10) * 0.5 + noise(5, 3, 11) * 0.5
        sheen = np.clip(1.0 - np.abs((x / W - 0.5) * 2.0), 0, 1) * 0.5
        return to_img(colour((70, 20, 90), (50, 30, 60), n) + sheen[..., None] * 40)
    if kind == "red":
        n = noise(40, 3, 12) * 0.5 + noise(5, 3, 13) * 0.5
        img = to_img(colour((150, 24, 28), (60, 20, 20), n))
        d = ImageDraw.Draw(img)
        for py in range(40, H, 120):  # gold claw rings in a pattern
            for px in range(40 + (60 if (py // 120) % 2 else 0), W, 120):
                d.arc([px - 18, py - 18, px + 18, py + 18], 200, 520, fill=(220, 170, 70), width=3)
        return img
    if kind == "spades":
        img = to_img(colour((14, 26, 60), (20, 25, 40), noise(8, 3, 14)))
        d = ImageDraw.Draw(img)
        for py in range(30, H, 90):
            for px in range(30 + (45 if (py // 90) % 2 else 0), W, 90):
                d.polygon([(px, py - 12), (px + 11, py + 4), (px, py + 2), (px - 11, py + 4)], fill=(150, 160, 185))
                d.rectangle([px - 2, py + 2, px + 2, py + 12], fill=(150, 160, 185))
        return img
    if kind == "gold":
        img = to_img(colour((18, 16, 14), (14, 12, 10), noise(8, 3, 15)))
        d = ImageDraw.Draw(img)
        for py in range(0, H, 76):
            for px in range(0 if (py // 76) % 2 == 0 else 38, W, 76):
                d.polygon([(px, py - 20), (px + 20, py), (px, py + 20), (px - 20, py)], outline=(200, 160, 70), width=2)
        return img
    if kind == "dusk":
        t = y / H
        a = np.zeros((H, W, 3), np.float32)
        top, bottom = np.array([60, 30, 80], np.float32), np.array([230, 170, 100], np.float32)
        a[:] = top + (bottom - top) * t[..., None]
        a += (noise(6, 4, 16) - 0.5)[..., None] * 40
        return to_img(a)
    return Image.new("RGB", (W, H), (40, 40, 40))


KIND = {"beach_felt": ("felt", (220, 180, 90)), "tide_pool": ("water", (230, 220, 180)), "scrapyard": ("rust", (210, 190, 160)),
        "crypt_floor": ("stone", (200, 190, 150)), "wheat_field": ("wheat", (90, 60, 20)), "neon_club": ("neon", (255, 90, 200)),
        "driftwood": ("wood", (240, 225, 190)), "royal_velvet": ("velvet", (230, 190, 90)), "lobster_red": ("red", (240, 200, 110)),
        "card_sharp": ("spades", (190, 200, 225)), "table_boss": ("gold", (220, 180, 80)), "lion_of_the_sand": ("dusk", (255, 220, 140))}


def _spot(d, cx, cy, ang, w, h, ink, width):
    pts = []
    a = math.radians(ang)
    for dx, dy in ((-1, -1), (1, -1), (1, 1), (-1, 1)):
        x, y = dx * w / 2, dy * h / 2
        pts.append((cx + x * math.cos(a) - y * math.sin(a), cy + x * math.sin(a) + y * math.cos(a)))
    d.line(pts + [pts[0]], fill=ink, width=width, joint="curve")


def zones(d, ink):
    """The spots of data/tcg/mat_layout.json on each half: creatures on an arc, the leader's portrait at the back
    nearest the player, deck and discard. The bottom half is the owner's; the top half is the same turned round."""
    lay = json.load(open(os.path.join(ROOT, "data", "tcg", "mat_layout.json")))
    cw, ch = lay["card"]
    for half in (0, 1):
        def place(x, y):  # near-half spot -> picture pixels
            return (x, H / 2 + y) if half == 0 else (W - x, H / 2 - y)
        for x, y, ang in lay["creatures"]:
            px, py = place(x, y)
            _spot(d, px, py, ang, cw, ch, ink, 2)
        for key in ("deck", "discard"):
            x, y, ang = lay[key]
            px, py = place(x, y)
            _spot(d, px, py, ang, cw, ch, ink, 3)
        lx, ly = place(*lay["leader"]["at"])
        lw, lh = lay["leader"]["size"]
        d.ellipse([lx - lw / 2, ly - lh / 2, lx + lw / 2, ly + lh / 2], outline=ink, width=3)  # the leader's portrait
        d.ellipse([lx - lw / 2 - 8, ly - lh / 2 - 8, lx + lw / 2 + 8, ly + lh / 2 + 8], outline=ink, width=1)


def paint(mid, name):
    kind, ink = KIND.get(mid, ("felt", (220, 180, 90)))
    img = surface(kind).convert("RGBA")
    over = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(over)
    a = (*ink, 110)
    d.rectangle([10, 10, W - 11, H - 11], outline=(*ink, 230), width=8)  # rim
    d.rectangle([26, 26, W - 27, H - 27], outline=a, width=2)
    d.line([40, H // 2, W - 40, H // 2], fill=a, width=2)  # centre line
    zones(d, a)
    logo = Image.open(os.path.join(ROOT, "assets", "tcg", "logo.png")).convert("RGBA")
    size = 220 if mid == "lion_of_the_sand" else 84
    logo = logo.resize((size, size), Image.LANCZOS)
    alpha = logo.split()[3].point(lambda v: int(v * (0.85 if mid == "lion_of_the_sand" else 0.3)))
    logo.putalpha(alpha)
    over.alpha_composite(logo, ((W - size) // 2, (H - size) // 2))
    font = ImageFont.truetype(os.path.join(ROOT, "assets", "fonts", "Cinzel.ttf"), 26)
    d.text((44, H - 60), name.upper(), font=font, fill=(*ink, 200))  # bottom left: the leader portrait owns the middle
    img.alpha_composite(over)
    # a soft darker edge, as cloth over a table edge
    y, x = np.mgrid[0:H, 0:W].astype(np.float32)
    edge = np.minimum(np.minimum(x, W - x), np.minimum(y, H - y))
    shade = np.clip(edge / 60.0, 0, 1) * 0.25 + 0.75
    out = np.asarray(img.convert("RGB"), np.float32) * shade[..., None]
    to_img(out).save(os.path.join(OUT, mid + ".jpg"), quality=90)


def main():
    os.makedirs(OUT, exist_ok=True)
    mats = json.load(open(os.path.join(ROOT, "data", "tcg", "mats.json")))["mats"]
    ids = sys.argv[1:] or list(mats)
    for mid in ids:
        paint(mid, mats[mid]["name"])
        print("MAT", mid)


if __name__ == "__main__":
    main()
