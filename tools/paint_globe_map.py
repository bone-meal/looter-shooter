# Purpose: developer-time script (polish1 item 12). Paints the hub globe's map, an antique 1916-style world in sepia:
# hand-drawn simplified continents (rough outlines, our own tracing from memory), aged-paper sea with a faint wash,
# a darker coast line, a graticule every 15 degrees, a red equator and tropics, and a little foxing. Equirectangular
# 1024 x 512 into assets/ui/hub_globe_map.png (a SphereMesh's UVs read it as is).
# Run: python3 tools/paint_globe_map.py   (needs numpy, pillow)
import math
import os

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

W, H = 1024, 512
OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "ui", "hub_globe_map.png")

LANDS = {
    "north_america": [(-168, 66), (-156, 71), (-140, 70), (-120, 72), (-95, 72), (-85, 68), (-80, 62), (-64, 60), (-56, 52), (-60, 46), (-67, 44), (-70, 41), (-76, 35), (-81, 31), (-80, 25), (-82, 29), (-90, 30), (-97, 26), (-98, 20), (-92, 18), (-87, 21), (-88, 15), (-83, 10), (-78, 8), (-83, 8), (-87, 12), (-92, 14), (-105, 20), (-110, 24), (-114, 30), (-117, 32), (-124, 40), (-125, 48), (-133, 56), (-140, 60), (-150, 60), (-158, 57), (-165, 60), (-166, 64)],
    "greenland": [(-55, 60), (-43, 60), (-35, 66), (-22, 70), (-18, 76), (-20, 81), (-35, 83), (-60, 82), (-72, 78), (-66, 75), (-56, 70), (-52, 65)],
    "south_america": [(-78, 8), (-70, 12), (-62, 11), (-52, 5), (-50, 0), (-44, -2), (-35, -6), (-39, -15), (-41, -22), (-48, -26), (-53, -33), (-58, -38), (-63, -42), (-66, -48), (-69, -52), (-68, -55), (-73, -52), (-75, -45), (-73, -37), (-71, -28), (-70, -18), (-76, -14), (-81, -6), (-80, 0), (-78, 2)],
    "europe": [(-9, 37), (-6, 36), (-2, 37), (3, 42), (-1, 44), (-2, 47), (-4, 48), (2, 50), (5, 53), (8, 54), (8, 57), (11, 58), (6, 62), (12, 66), (18, 70), (26, 71), (33, 70), (40, 67), (42, 64), (34, 63), (30, 60), (24, 60), (22, 57), (21, 55), (27, 56), (30, 59), (33, 55), (38, 47), (34, 46), (29, 45), (28, 42), (26, 40), (23, 38), (22, 36), (20, 40), (16, 41), (18, 40), (15, 38), (12, 42), (9, 44), (5, 43), (3, 42), (-2, 40), (-9, 42)],
    "britain": [(-5, 50), (1, 51), (1, 53), (-2, 56), (-3, 58), (-6, 58), (-5, 55), (-3, 54), (-5, 52)],
    "ireland": [(-10, 52), (-6, 52), (-6, 55), (-9, 55)],
    "scandinavia_south": [(5, 58), (11, 59), (16, 56), (19, 59), (18, 63), (14, 63)],
    "africa": [(-17, 21), (-16, 27), (-10, 30), (-6, 35), (10, 37), (11, 33), (20, 31), (25, 32), (32, 31), (34, 28), (38, 20), (43, 12), (51, 12), (48, 6), (42, -2), (40, -10), (40, -16), (35, -24), (32, -29), (27, -34), (20, -35), (17, -29), (14, -22), (12, -17), (13, -10), (9, -2), (9, 4), (4, 6), (-4, 5), (-8, 4), (-13, 8), (-17, 14)],
    "madagascar": [(44, -25), (47, -25), (50, -15), (49, -12), (44, -17)],
    "arabia": [(35, 28), (39, 22), (43, 13), (52, 16), (57, 19), (59, 22), (56, 26), (51, 25), (48, 29), (35, 32)],
    "asia": [(30, 70), (50, 70), (60, 75), (80, 73), (100, 78), (115, 74), (130, 72), (145, 72), (160, 70), (170, 70), (180, 66), (178, 63), (162, 60), (155, 58), (160, 54), (150, 50), (142, 52), (140, 47), (135, 43), (130, 42), (126, 38), (122, 40), (119, 36), (120, 31), (118, 25), (111, 21), (108, 21), (106, 16), (109, 12), (105, 9), (101, 13), (100, 7), (103, 2), (98, 9), (98, 16), (93, 18), (92, 22), (88, 22), (82, 16), (80, 10), (77, 8), (73, 17), (72, 22), (67, 25), (61, 25), (57, 27), (52, 30), (48, 30), (44, 37), (36, 37), (28, 37), (26, 40), (29, 41), (36, 41), (41, 41), (44, 43), (50, 45), (54, 41), (60, 45), (62, 50), (50, 53), (55, 60), (60, 65), (45, 67), (40, 66)],
    "japan": [(130, 31), (135, 34), (140, 35), (142, 40), (141, 45), (145, 44), (140, 41), (139, 37), (133, 35)],
    "borneo": [(109, 1), (113, -3), (117, -4), (119, 1), (117, 7), (114, 4)],
    "sumatra": [(95, 5), (98, 4), (104, -3), (106, -6), (102, -4), (96, 2)],
    "java": [(105, -6), (114, -7), (114, -9), (106, -8)],
    "new_guinea": [(131, -1), (141, -3), (150, -6), (147, -9), (141, -9), (137, -5)],
    "australia": [(114, -22), (122, -18), (126, -14), (130, -12), (136, -12), (137, -15), (140, -17), (142, -11), (145, -15), (146, -19), (150, -23), (153, -26), (153, -31), (150, -37), (146, -39), (140, -38), (137, -35), (132, -32), (124, -34), (115, -34), (114, -27)],
    "new_zealand": [(172, -34), (178, -38), (175, -42), (172, -41)],
    "new_zealand_south": [(172, -41), (174, -42), (170, -46), (166, -46)],
    "iceland": [(-24, 64), (-14, 64), (-14, 66), (-22, 66)],
    "cuba": [(-85, 22), (-74, 20), (-77, 22), (-82, 23)],
}


def px(lon, lat):
    return ((lon + 180.0) / 360.0 * W, (90.0 - lat) / 180.0 * H)


def main():
    rng = np.random.default_rng(1916)
    sea = np.zeros((H, W, 3), np.float32)
    y = np.linspace(0, 1, H)[:, None]
    sea[...] = np.array([0.66, 0.66, 0.52])  # aged paper with a greenish sea wash
    noise = rng.normal(0, 1, (H // 8, W // 8))
    noise = np.array(Image.fromarray(((noise - noise.min()) / np.ptp(noise) * 255).astype(np.uint8)).resize((W, H), Image.BICUBIC)) / 255.0
    sea *= (0.92 + 0.12 * noise[..., None])
    img = Image.fromarray((np.clip(sea, 0, 1) * 255).astype(np.uint8))
    land = Image.new("L", (W, H), 0)
    d = ImageDraw.Draw(land)
    for poly in LANDS.values():
        d.polygon([px(lon, lat) for lon, lat in poly], fill=255)
    d.rectangle([0, px(0, -72)[1], W, H], fill=255)  # the southern ice
    mask = np.array(land) > 0
    arr = np.array(img).astype(np.float32) / 255.0
    paper = np.array([0.88, 0.79, 0.58]) * (0.9 + 0.12 * noise[..., None])
    arr[mask] = paper[mask]
    # a soft halo of shallow water round every coast, then the coast line itself
    edge = Image.fromarray((mask * 255).astype(np.uint8)).filter(ImageFilter.FIND_EDGES)
    halo = np.array(edge.filter(ImageFilter.GaussianBlur(4))).astype(np.float32) / 255.0
    arr = arr * (1 - 0.35 * halo[..., None] * (~mask)[..., None]) + np.array([0.45, 0.5, 0.42]) * 0.35 * halo[..., None] * (~mask)[..., None]
    out = Image.fromarray((np.clip(arr, 0, 1) * 255).astype(np.uint8))
    d2 = ImageDraw.Draw(out)
    e = np.array(edge) > 0
    ys, xs = np.nonzero(e)
    for x0, y0 in zip(xs, ys):
        d2.point((x0, y0), fill=(70, 50, 30))
    for lon in range(-180, 181, 15):  # the graticule
        x0, _ = px(lon, 0)
        d2.line([(x0, 0), (x0, H)], fill=(110, 90, 60), width=1)
    for lat in range(-75, 76, 15):
        _, y0 = px(0, lat)
        d2.line([(0, y0), (W, y0)], fill=(110, 90, 60), width=1)
    for lat, w in ((0, 2), (23.4, 1), (-23.4, 1)):  # equator and tropics in faded red
        _, y0 = px(0, lat)
        d2.line([(0, y0), (W, y0)], fill=(150, 50, 35), width=w)
    for _k in range(30):  # foxing: little brown spots of age
        x0, y0, r = rng.integers(0, W), rng.integers(0, H), rng.integers(1, 4)
        d2.ellipse([x0 - r, y0 - r, x0 + r, y0 + r], fill=(int(140 + rng.integers(0, 30)), int(110 + rng.integers(0, 20)), 70))
    out = out.filter(ImageFilter.GaussianBlur(0.6))
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    out.save(OUT)
    print("globe map", OUT)


if __name__ == "__main__":
    main()
