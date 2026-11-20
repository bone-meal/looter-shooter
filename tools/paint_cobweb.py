# Purpose: developer-time script (polish1 item 15). Paints one corner cobweb for the hub's trophy room doorway: threads
# fanning out from the top-left corner (the anchor), sagging cross threads between them, a few broken loose ends, a
# faint haze of fine silk near the corner. White on transparent, 512 x 512. Writes assets/ui/hub_cobweb.png.
# Run: python3 tools/paint_cobweb.py   (needs pillow)
import math
import os
import random

from PIL import Image, ImageChops, ImageDraw, ImageFilter

N = 512
SS = 2
OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "ui", "hub_cobweb.png")


def main():
    rnd = random.Random(15)
    w = N * SS
    img = Image.new("L", (w, w), 0)
    d = ImageDraw.Draw(img)
    spokes = []
    for k in range(9):  # spokes from the corner, from along the top edge round to down the side
        a = math.radians(4 + k * 82 / 8 + rnd.uniform(-3, 3))
        length = w * rnd.uniform(0.78, 1.0) / max(math.cos(a), math.sin(a), 0.7)
        spokes.append((a, min(length, w * 1.25)))
    for a, length in spokes:
        d.line([(0, 0), (math.cos(a) * length, math.sin(a) * length)], fill=210, width=3 * SS)
    for ring in range(14):  # cross threads, sagging toward the corner between spokes
        r = w * (0.07 + ring * 0.068) * rnd.uniform(0.95, 1.05)
        for (a0, l0), (a1, l1) in zip(spokes, spokes[1:]):
            if r > min(l0, l1) * 0.97 or rnd.random() < 0.08:  # a few gaps (broken threads)
                continue
            p0 = (math.cos(a0) * r, math.sin(a0) * r)
            p1 = (math.cos(a1) * r, math.sin(a1) * r)
            mid = ((p0[0] + p1[0]) / 2, (p0[1] + p1[1]) / 2)
            sag = 0.12 * r * (a1 - a0)  # toward the corner
            m = (mid[0] - math.cos((a0 + a1) / 2) * sag, mid[1] - math.sin((a0 + a1) / 2) * sag)
            pts = [((1 - t) ** 2 * p0[0] + 2 * (1 - t) * t * m[0] + t * t * p1[0], (1 - t) ** 2 * p0[1] + 2 * (1 - t) * t * m[1] + t * t * p1[1]) for t in [i / 8 for i in range(9)]]
            d.line(pts, fill=170, width=2 * SS)
    for _k in range(5):  # loose ends hanging down
        x = rnd.uniform(0.2, 0.8) * w
        y = rnd.uniform(0.05, 0.3) * w
        d.line([(x, y), (x + rnd.uniform(-20, 20) * SS, y + rnd.uniform(60, 160) * SS)], fill=150, width=SS)
    haze = Image.new("L", (w, w), 0)  # dense silk near the corner
    hd = ImageDraw.Draw(haze)
    hd.pieslice([-w * 0.3, -w * 0.3, w * 0.3, w * 0.3], 0, 90, fill=60)
    haze = haze.filter(ImageFilter.GaussianBlur(30 * SS))
    alpha = ImageChops.lighter(img, haze)
    alpha = alpha.resize((N, N), Image.LANCZOS)
    out = Image.new("RGBA", (N, N), (240, 238, 232, 0))
    out.putalpha(alpha)
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    out.save(OUT)
    print("cobweb", OUT)


if __name__ == "__main__":
    main()
