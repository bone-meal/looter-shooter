# Purpose: paints the LOGO of "You got me Lobster?" (director's design, locked): a snake shaped like an "S", raising
# itself up from its coiled tail, with the HEAD OF A LION and TWO WINGS MADE OF LARGE OAK LEAVES, in embossed gold.
# Writes assets/tcg/logo.png (1024 x 1024, transparent) and lays it into the medallion of the card back
# (assets/tcg/frames/back.png, made by tools/blender/card_frames.py). Also used later by the binder cover, the
# vending machine and the packs. Developer-time (pycairo), never run by the game.
# Usage: python3 tools/paint_logo.py
# Dependencies: pycairo, numpy, Pillow.
import math
import os

import cairo
import numpy as np
from PIL import Image, ImageFilter

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
N = 1024
GOLD = [(0.0, (1.0, 0.95, 0.7)), (0.45, (1.0, 0.8, 0.32)), (0.8, (0.8, 0.52, 0.15)), (1.0, (0.5, 0.3, 0.07))]
DARK = (0.18, 0.08, 0.02)


def grad(ctx, x0, y0, x1, y1, stops, alpha=1.0):
    g = cairo.LinearGradient(x0, y0, x1, y1)
    for t, c in stops:
        g.add_color_stop_rgba(t, *c, alpha)
    ctx.set_source(g)


def radial(ctx, x, y, r, stops):
    g = cairo.RadialGradient(x - r * 0.3, y - r * 0.35, r * 0.05, x, y, r)
    for t, c in stops:
        g.add_color_stop_rgba(t, *c, 1)
    ctx.set_source(g)


def smooth(ctx, pts, close=True):
    n = len(pts)
    ctx.move_to(*pts[0])
    for i in range(n if close else n - 1):
        p0 = pts[(i - 1) % n] if close or i > 0 else pts[0]
        p1, p2 = pts[i], pts[(i + 1) % n]
        p3 = pts[(i + 2) % n] if close or i + 2 < n else pts[-1]
        ctx.curve_to(p1[0] + (p2[0] - p0[0]) / 6, p1[1] + (p2[1] - p0[1]) / 6, p2[0] - (p3[0] - p1[0]) / 6, p2[1] - (p3[1] - p1[1]) / 6, p2[0], p2[1])
    if close:
        ctx.close_path()


def bezier(p0, p1, p2, p3, t):
    u = 1 - t
    return (u ** 3 * p0[0] + 3 * u * u * t * p1[0] + 3 * u * t * t * p2[0] + t ** 3 * p3[0],
            u ** 3 * p0[1] + 3 * u * u * t * p1[1] + 3 * u * t * t * p2[1] + t ** 3 * p3[1])


def spine():
    """The S from the tail coil (bottom) up to the neck (top): three joined cubic curves."""
    segs = [((520, 905), (330, 915), (300, 790), (420, 735)),   # tail tip curling in
            ((420, 735), (700, 600), (720, 470), (520, 420)),   # lower bowl of the S
            ((520, 420), (330, 370), (340, 250), (505, 215))]   # upper bowl up to the neck
    pts = []
    for k, s in enumerate(segs):
        for i in range(60):
            pts.append(bezier(*s, i / 60.0))
    pts.append(segs[-1][3])
    return pts


def oak_leaf(ctx, base, tip, width, lobes=4):
    bx, by = base
    tx, ty = tip
    L = math.hypot(tx - bx, ty - by)
    ux, uy = (tx - bx) / L, (ty - by) / L
    nx, ny = -uy, ux
    left, right = [], []
    for i in range(1, lobes * 2 + 1):
        f = i / (lobes * 2 + 1)
        w = width * math.sin(math.pi * f) ** 0.7 * (1.0 if i % 2 else 0.55)
        left.append((bx + ux * L * f + nx * w, by + uy * L * f + ny * w))
        right.append((bx + ux * L * f - nx * w, by + uy * L * f - ny * w))
    outline = [(bx, by)] + left + [(tx, ty)] + right[::-1]
    # shadow, body, vein
    ctx.save(); ctx.translate(6, 8); smooth(ctx, outline); ctx.set_source_rgba(0, 0, 0, 0.35); ctx.fill(); ctx.restore()
    smooth(ctx, outline)
    g = cairo.LinearGradient(bx + nx * width, by + ny * width, bx - nx * width, by - ny * width)
    for t, c in [(0, (0.95, 0.85, 0.45)), (0.5, (0.78, 0.6, 0.2)), (1, (0.42, 0.3, 0.08))]:
        g.add_color_stop_rgba(t, *c, 1)
    ctx.set_source(g); ctx.fill_preserve()
    ctx.set_source_rgba(*DARK, 1); ctx.set_line_width(5); ctx.stroke()
    ctx.move_to(bx, by); ctx.line_to(tx - ux * 20, ty - uy * 20)
    ctx.set_source_rgba(0.35, 0.2, 0.05, 0.9); ctx.set_line_width(5); ctx.stroke()
    for i in range(1, lobes * 2 + 1, 2):  # side veins to each lobe
        f = i / (lobes * 2 + 1)
        mx, my = bx + ux * L * f, by + uy * L * f
        for side in (1, -1):
            ctx.move_to(mx, my)
            ctx.line_to(mx + ux * L * 0.06 + nx * side * width * 0.7, my + uy * L * 0.06 + ny * side * width * 0.7)
            ctx.set_source_rgba(0.35, 0.2, 0.05, 0.6); ctx.set_line_width(3); ctx.stroke()


def paint():
    surf = cairo.ImageSurface(cairo.FORMAT_ARGB32, N, N)
    ctx = cairo.Context(surf)
    ctx.set_line_cap(cairo.LINE_CAP_ROUND); ctx.set_line_join(cairo.LINE_JOIN_ROUND)
    # WINGS: three big oak leaves a side, spreading up and out from behind the upper bowl
    for side in (-1, 1):
        root = (512 + side * 40, 470)
        for i, (ang, length, width) in enumerate([(-15, 330, 70), (12, 360, 80), (40, 300, 70)]):
            a = math.radians(ang)
            tip = (root[0] + side * math.cos(a) * length, root[1] - math.sin(a) * length - 60)
            oak_leaf(ctx, root, tip, width)
    # SNAKE BODY: dark outline pass, then gold, then scales and a highlight line
    pts = spine()
    n = len(pts)
    def radius(i):
        t = i / (n - 1)
        return 10 + 46 * min(1.0, t * 1.4) - 8 * max(0.0, t - 0.85) / 0.15
    for i in range(n):
        ctx.arc(pts[i][0] + 7, pts[i][1] + 9, radius(i) + 6, 0, math.tau); ctx.set_source_rgba(0, 0, 0, 0.3); ctx.fill()
    for i in range(n):
        ctx.arc(pts[i][0], pts[i][1], radius(i) + 5, 0, math.tau); ctx.set_source_rgba(*DARK, 1); ctx.fill()
    for i in range(n):
        x, y = pts[i]; r = radius(i)
        radial(ctx, x, y, r, GOLD)
        ctx.arc(x, y, r, 0, math.tau); ctx.fill()
    for i in range(4, n - 2, 4):  # belly scales: little arcs across the body
        x, y = pts[i]; r = radius(i)
        dx, dy = pts[i + 1][0] - pts[i - 1][0], pts[i + 1][1] - pts[i - 1][1]
        a = math.atan2(dy, dx)
        ctx.arc(x, y, r * 0.75, a + math.pi * 0.6, a + math.pi * 1.4)
        ctx.set_source_rgba(0.45, 0.25, 0.06, 0.55); ctx.set_line_width(max(2, r * 0.12)); ctx.stroke()
    ctx.set_line_width(6)
    for i in range(0, n - 1, 1):  # a highlight running along the body
        x, y = pts[i]; r = radius(i)
        ctx.arc(x - r * 0.35, y - r * 0.4, 2.2 + r * 0.06, 0, math.tau); ctx.set_source_rgba(1, 0.97, 0.8, 0.5); ctx.fill()
    # LION HEAD on the neck: mane of flame-shaped locks, ears, face, muzzle, eyes, nose
    hx, hy = 505, 175
    for ring_r, count, length, shade in ((150, 22, 95, 0.75), (120, 18, 80, 0.95)):
        for i in range(count):
            a = 2 * math.pi * i / count + (0.15 if shade > 0.8 else 0)
            bx, by = hx + math.cos(a) * ring_r * 0.55, hy + math.sin(a) * ring_r * 0.55
            tx, ty = hx + math.cos(a) * (ring_r + length * 0.5), hy + math.sin(a) * (ring_r + length * 0.5)
            nx, ny = -math.sin(a) * 34, math.cos(a) * 34
            lock = [(bx + nx, by + ny), ((bx + tx) / 2 + nx * 1.1, (by + ty) / 2 + ny * 1.1), (tx + nx * 0.4 + math.cos(a + 0.6) * 18, ty + ny * 0.4 + math.sin(a + 0.6) * 18), (tx, ty), ((bx + tx) / 2 - nx * 0.4, (by + ty) / 2 - ny * 0.4), (bx - nx, by - ny)]
            smooth(ctx, lock)
            g = cairo.LinearGradient(bx, by, tx, ty)
            for t, c in [(0, (0.95 * shade, 0.62 * shade, 0.18 * shade)), (1, (0.55 * shade, 0.3 * shade, 0.06 * shade))]:
                g.add_color_stop_rgba(t, *c, 1)
            ctx.set_source(g); ctx.fill_preserve(); ctx.set_source_rgba(*DARK, 0.9); ctx.set_line_width(4); ctx.stroke()
    for side in (-1, 1):  # ears
        ctx.arc(hx + side * 78, hy - 70, 26, 0, math.tau); radial(ctx, hx + side * 78, hy - 70, 26, GOLD); ctx.fill_preserve()
        ctx.set_source_rgba(*DARK, 1); ctx.set_line_width(5); ctx.stroke()
    face = [(hx, hy - 105), (hx + 70, hy - 80), (hx + 92, hy - 10), (hx + 70, hy + 70), (hx + 30, hy + 108), (hx, hy + 115), (hx - 30, hy + 108), (hx - 70, hy + 70), (hx - 92, hy - 10), (hx - 70, hy - 80)]
    smooth(ctx, face); radial(ctx, hx, hy, 120, GOLD); ctx.fill_preserve(); ctx.set_source_rgba(*DARK, 1); ctx.set_line_width(6); ctx.stroke()
    smooth(ctx, [(hx, hy + 5), (hx + 50, hy + 30), (hx + 45, hy + 85), (hx, hy + 100), (hx - 45, hy + 85), (hx - 50, hy + 30)])  # muzzle
    radial(ctx, hx, hy + 55, 60, [(0, (1.0, 0.95, 0.75)), (1, (0.85, 0.6, 0.25))]); ctx.fill_preserve(); ctx.set_source_rgba(*DARK, 0.8); ctx.set_line_width(4); ctx.stroke()
    smooth(ctx, [(hx - 22, hy + 22), (hx + 22, hy + 22), (hx + 10, hy + 42), (hx, hy + 46), (hx - 10, hy + 42)])  # nose
    ctx.set_source_rgba(0.25, 0.1, 0.03, 1); ctx.fill()
    ctx.move_to(hx, hy + 46); ctx.line_to(hx, hy + 64); ctx.curve_to(hx - 10, hy + 76, hx - 28, hy + 72, hx - 32, hy + 62)
    ctx.move_to(hx, hy + 64); ctx.curve_to(hx + 10, hy + 76, hx + 28, hy + 72, hx + 32, hy + 62)
    ctx.set_source_rgba(0.25, 0.1, 0.03, 1); ctx.set_line_width(5); ctx.stroke()
    for side in (-1, 1):  # fierce eyes
        ex, ey = hx + side * 38, hy - 22
        smooth(ctx, [(ex - side * 22, ey + 4), (ex, ey - 10), (ex + side * 24, ey - 4), (ex, ey + 9)])
        ctx.set_source_rgba(1.0, 0.85, 0.2, 1); ctx.fill_preserve(); ctx.set_source_rgba(*DARK, 1); ctx.set_line_width(4); ctx.stroke()
        ctx.arc(ex + side * 2, ey, 5, 0, math.tau); ctx.set_source_rgba(0.1, 0.03, 0, 1); ctx.fill()
        ctx.move_to(ex - side * 30, ey - 22); ctx.line_to(ex + side * 22, ey - 14)  # brow
        ctx.set_source_rgba(*DARK, 1); ctx.set_line_width(6); ctx.stroke()
    # forked tongue below the snake's lion jaw? no: a lion head keeps a lion mouth. A small shine on the forehead:
    ctx.arc(hx - 25, hy - 60, 14, 0, math.tau); ctx.set_source_rgba(1, 1, 0.9, 0.35); ctx.fill()
    surf.flush()
    a = np.ndarray((N, N, 4), np.uint8, surf.get_data()).copy().astype(np.float32)
    b, g, r, al = a[..., 0], a[..., 1], a[..., 2], a[..., 3]
    safe = np.maximum(al, 1) / 255.0
    img = Image.fromarray(np.clip(np.stack([r / safe, g / safe, b / safe, al], -1), 0, 255).astype(np.uint8), "RGBA")
    # a soft golden glow behind it
    glow = img.split()[3].filter(ImageFilter.GaussianBlur(18))
    halo = Image.new("RGBA", img.size, (255, 200, 90, 0)); halo.putalpha(glow.point(lambda v: int(v * 0.45)))
    out = Image.alpha_composite(halo, img)
    return out


def main():
    logo = paint()
    os.makedirs(os.path.join(ROOT, "assets", "tcg"), exist_ok=True)
    logo.save(os.path.join(ROOT, "assets", "tcg", "logo.png"))
    back_path = os.path.join(ROOT, "assets", "tcg", "frames", "back.png")
    if os.path.exists(back_path):
        back = Image.open(back_path).convert("RGBA")
        size = int(back.width * 0.62)
        small = logo.resize((size, size), Image.LANCZOS)
        back.alpha_composite(small, ((back.width - size) // 2, (back.height - size) // 2 - 6))
        back.save(back_path)
    print("LOGO done")


if __name__ == "__main__":
    main()
