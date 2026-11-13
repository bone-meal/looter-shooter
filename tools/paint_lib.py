# Purpose: helpers for tools/paint_emblems.py: cairo layers, gradients, glow, grain, round clip.
# Dependencies: pycairo, numpy, Pillow.
import math, random
import cairo
import numpy as np
from PIL import Image, ImageFilter

S = 512
C = S / 2


def rgb(h, a=1.0):
    h = h.lstrip('#')
    return (int(h[0:2], 16) / 255, int(h[2:4], 16) / 255, int(h[4:6], 16) / 255, a)


def layer():
    surf = cairo.ImageSurface(cairo.FORMAT_ARGB32, S, S)
    ctx = cairo.Context(surf)
    ctx.set_line_cap(cairo.LINE_CAP_ROUND)
    ctx.set_line_join(cairo.LINE_JOIN_ROUND)
    return surf, ctx


def to_pil(surf):
    surf.flush()
    a = np.ndarray((S, S, 4), np.uint8, surf.get_data()).copy().astype(np.float32)
    b, g, r, al = a[..., 0], a[..., 1], a[..., 2], a[..., 3]
    safe = np.maximum(al, 1) / 255.0
    out = np.stack([r / safe, g / safe, b / safe, al], -1)
    out[al == 0] = 0
    return Image.fromarray(np.clip(out, 0, 255).astype(np.uint8), 'RGBA')


def lin(ctx, x0, y0, x1, y1, stops):
    g = cairo.LinearGradient(x0, y0, x1, y1)
    for t, c in stops:
        g.add_color_stop_rgba(t, *c)
    ctx.set_source(g)


def rad(ctx, x, y, r0, r1, stops, x1=None, y1=None):
    g = cairo.RadialGradient(x, y, r0, x if x1 is None else x1, y if y1 is None else y1, r1)
    for t, c in stops:
        g.add_color_stop_rgba(t, *c)
    ctx.set_source(g)


def glow(ctx, x, y, r, color, strength=1.0):
    c = color
    rad(ctx, x, y, 0, r, [(0, (c[0], c[1], c[2], 0.9 * strength)), (0.35, (c[0], c[1], c[2], 0.35 * strength)), (1, (c[0], c[1], c[2], 0))])
    ctx.arc(x, y, r, 0, math.tau)
    ctx.fill()


def poly(ctx, pts, close=True):
    ctx.move_to(*pts[0])
    for p in pts[1:]:
        ctx.line_to(*p)
    if close:
        ctx.close_path()


def smooth(ctx, pts, close=True):
    # Catmull-Rom through the points
    n = len(pts)
    ctx.move_to(*pts[0])
    rng = range(n if close else n - 1)
    for i in rng:
        p0 = pts[(i - 1) % n] if close or i > 0 else pts[0]
        p1 = pts[i]
        p2 = pts[(i + 1) % n]
        p3 = pts[(i + 2) % n] if close or i + 2 < n else pts[-1]
        c1 = (p1[0] + (p2[0] - p0[0]) / 6, p1[1] + (p2[1] - p0[1]) / 6)
        c2 = (p2[0] - (p3[0] - p1[0]) / 6, p2[1] - (p3[1] - p1[1]) / 6)
        ctx.curve_to(c1[0], c1[1], c2[0], c2[1], p2[0], p2[1])
    if close:
        ctx.close_path()


def stroke(ctx, color, width):
    ctx.set_source_rgba(*color)
    ctx.set_line_width(width)
    ctx.stroke()


def fill(ctx, color):
    ctx.set_source_rgba(*color)
    ctx.fill()


def blurred(surf, radius):
    return to_pil(surf).filter(ImageFilter.GaussianBlur(radius))


def finish(img, name, out_dir, seed=1, bloom=0.35, grain=5):
    """Bloom, painterly grain, round clip, 256 px."""
    rnd = np.random.default_rng(seed)
    base = img.convert('RGBA')
    arr = np.asarray(base).astype(np.float32)
    bright = arr.copy()
    lum = (arr[..., 0] * 0.3 + arr[..., 1] * 0.59 + arr[..., 2] * 0.11)
    bright[..., :3] *= np.clip((lum - 150) / 105, 0, 1)[..., None]
    bl = np.asarray(Image.fromarray(bright.astype(np.uint8)).filter(ImageFilter.GaussianBlur(14))).astype(np.float32)
    arr[..., :3] = np.clip(arr[..., :3] + bl[..., :3] * bloom, 0, 255)
    # painterly: soft brush grain + a little colour mottling
    noise = rnd.normal(0, grain, (S // 4, S // 4, 1))
    noise = np.asarray(Image.fromarray(np.clip(noise[..., 0] + 128, 0, 255).astype(np.uint8)).resize((S, S), Image.BICUBIC)).astype(np.float32)[..., None] - 128
    fine = rnd.normal(0, grain * 0.5, (S, S, 1))
    arr[..., :3] = np.clip(arr[..., :3] + noise + fine, 0, 255)
    # vignette
    yy, xx = np.mgrid[0:S, 0:S]
    d = np.sqrt((xx - C) ** 2 + (yy - C) ** 2) / C
    arr[..., :3] *= np.clip(1.15 - d * 0.35, 0.55, 1.0)[..., None]
    # round clip (soft edge)
    arr[..., 3] = np.clip((1.0 - d) * S * 0.5, 0, 1) * 255
    out = Image.fromarray(arr.astype(np.uint8), 'RGBA').resize((256, 256), Image.LANCZOS)
    out.save('%s/%s.png' % (out_dir, name))
    return out
