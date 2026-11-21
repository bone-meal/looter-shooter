#!/usr/bin/env python3
"""Purpose: draws the skinned knives' finish SHEETS (polish1 D5b art pass 3, diary/DESIGN_KNIVES.md): one big designed
sheet per finish like CS's pattern sheets; the knife's pattern number picks the window of it that lands on the blade.
Each sheet is 2560 x 384 px = 284 x 43 mm at 9 px/mm (x = along the blade, y = spine at the top to edge at the bottom).
Two pictures per finish in assets/knives/skins/: <id>_col.jpg (colour) and <id>_fx.png at half size (R = height for
relief, G = glow, B = metal, A = coat: 0 bare metal .. 1 lacquer / paint / glass), plus .import files (VRAM
compression + mipmaps). Each finish has its own drawing function (layers + motifs).
Run: python3 tools/make_knife_sheets.py [ids...]   (no ids = every finish that has a drawing)
Dependencies: numpy, Pillow; assets/fonts/*.ttf.
"""
import math
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont
from scipy import ndimage
from scipy.spatial import cKDTree

W, H = 2560, 384
PX = 9.0  # px per mm
SS = 2  # supersampling for drawn shapes
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "knives", "skins")


# ------------------------------------------------------------------ noise
def _lattice(seed, gw, gh):
    return np.random.default_rng(seed).random((gh + 2, gw + 2))


def vnoise(scale_mm, seed=0, sx=1.0, sy=1.0):
    """Smooth value noise over the sheet, features ~scale_mm (stretched by sx along x, sy along y)."""
    cell_x = scale_mm * PX * sx
    cell_y = scale_mm * PX * sy
    gw, gh = int(W / cell_x) + 2, int(H / cell_y) + 2
    lat = _lattice(seed, gw, gh)
    xs = np.arange(W) / cell_x
    ys = np.arange(H) / cell_y
    xi = np.floor(xs).astype(int)
    yi = np.floor(ys).astype(int)
    xf = xs - xi
    yf = ys - yi
    xf = xf * xf * (3 - 2 * xf)
    yf = yf * yf * (3 - 2 * yf)
    a = lat[np.ix_(yi, xi)]
    b = lat[np.ix_(yi, xi + 1)]
    c = lat[np.ix_(yi + 1, xi)]
    d = lat[np.ix_(yi + 1, xi + 1)]
    top = a + (b - a) * xf[None, :]
    bot = c + (d - c) * xf[None, :]
    return top + (bot - top) * yf[:, None]


def fbm(scale_mm, seed=0, octaves=5, sx=1.0, sy=1.0, gain=0.5):
    s = np.zeros((H, W))
    amp = 0.5
    tot = 0.0
    sc = scale_mm
    for o in range(octaves):
        s += amp * vnoise(sc, seed + o * 101, sx, sy)
        tot += amp
        amp *= gain
        sc *= 0.5
        if sc * PX < 1.2:
            break
    return s / tot


def warp_sample(field, dx, dy):
    """field sampled at (x + dx, y + dy) (pixels)."""
    yy, xx = np.mgrid[0:H, 0:W]
    x2 = np.clip(xx + dx, 0, W - 1).astype(int)
    y2 = np.clip(yy + dy, 0, H - 1).astype(int)
    return field[y2, x2]


def smooth(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0, 1)
    return t * t * (3 - 2 * t)


def grid():
    yy, xx = np.mgrid[0:H, 0:W].astype(float)
    return xx / PX, yy / PX  # mm


def hexc(h):
    h = h.lstrip("#")
    return np.array([int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4)])


def mix(a, b, t):
    t = np.asarray(t)
    if t.ndim == 2:
        t = t[..., None]
    return a * (1 - t) + b * t


def voronoi(cell_mm, seed=0, jitter=1.0, sx=1.0, sy=1.0):
    """Cells over the sheet: (cell id, distance to nearest point, distance to second, nearest point xy) in mm."""
    rng = np.random.default_rng(seed)
    cw, ch = cell_mm * sx, cell_mm * sy
    nx, ny = int(WMM / cw) + 3, int(HMM / ch) + 3
    gx, gy = np.meshgrid(np.arange(-1, nx - 1), np.arange(-1, ny - 1))
    px = (gx + 0.5 + (rng.random(gx.shape) - 0.5) * jitter) * cw
    py = (gy + 0.5 + (rng.random(gy.shape) - 0.5) * jitter) * ch
    pts = np.stack([px.ravel() / sx, py.ravel() / sy], 1)
    x, y = grid()
    q = np.stack([(x / sx).ravel(), (y / sy).ravel()], 1)
    d, i = cKDTree(pts).query(q, k=2)
    return i[:, 0].reshape(H, W), d[:, 0].reshape(H, W), d[:, 1].reshape(H, W), pts


def inside_mm(mask):
    """Distance (mm) from each inside pixel to the mask's edge."""
    return ndimage.distance_transform_edt(mask > 0.5) / PX


def slugify(name):
    return "".join(c if c.isalnum() else "_" for c in name.lower()).strip("_")


# ------------------------------------------------------------------ the canvas a finish is built on
class Sheet:
    def __init__(self):
        self.col = np.zeros((H, W, 3))
        self.coat = np.zeros((H, W))
        self.height = np.full((H, W), 0.5)
        self.glow = np.zeros((H, W))
        self.metal = np.zeros((H, W))
        self.anim = np.zeros((H, W))

    # paint a colour (and other channels) where `mask` is (0..1)
    def put(self, mask, color=None, coat=None, height=None, glow=None, metal=None, anim=None, add_height=None):
        m = np.clip(mask, 0, 1)
        if color is not None:
            c = np.asarray(color, dtype=float)
            if c.ndim == 1:
                c = c[None, None, :]
            self.col = self.col * (1 - m[..., None]) + c * m[..., None]
        for name, val in (("coat", coat), ("height", height), ("glow", glow), ("metal", metal), ("anim", anim)):
            if val is not None:
                cur = getattr(self, name)
                setattr(self, name, cur * (1 - m) + np.asarray(val) * m)
        if add_height is not None:
            self.height = self.height + m * add_height

    def save(self, fid):
        """<id>_col.jpg = colour (RGB); <id>_fx.png at half size = height, glow, metal, coat (glow phase is worked out in the shader)."""
        os.makedirs(OUT, exist_ok=True)
        for old in ("_col.png", "_fx.png", "_col.png.import", "_fx.png.import"):
            if os.path.exists(os.path.join(OUT, fid + old)) and old.startswith("_col.png"):
                os.remove(os.path.join(OUT, fid + old))
        col = Image.fromarray((np.clip(self.col, 0, 1) * 255 + 0.5).astype(np.uint8), "RGB")
        path = os.path.join(OUT, "%s_col.jpg" % fid)
        col.save(path, quality=92, subsampling=0)
        write_import(path)
        fx = np.dstack([np.clip(self.height, 0, 1), np.clip(self.glow, 0, 1), np.clip(self.metal, 0, 1), np.clip(self.coat, 0, 1)])
        img = Image.fromarray((fx * 255 + 0.5).astype(np.uint8), "RGBA").resize((W // 2, H // 2), Image.LANCZOS)
        path = os.path.join(OUT, "%s_fx.png" % fid)
        img.save(path, optimize=True)
        write_import(path)
        os.makedirs(os.path.join(ROOT, "tools", "shots"), exist_ok=True)
        col.save(os.path.join(ROOT, "tools", "shots", "sheet_%s.jpg" % fid), quality=90)


def write_import(path):
    rel = "res://" + os.path.relpath(path, ROOT).replace(os.sep, "/")
    with open(path + ".import", "w") as f:
        f.write('[remap]\n\nimporter="texture"\ntype="CompressedTexture2D"\n\n[deps]\n\nsource_file="%s"\n\n[params]\n\n'
                "compress/mode=2\ncompress/high_quality=false\ncompress/lossy_quality=0.7\ncompress/hdr_compression=1\n"
                "compress/normal_map=2\ncompress/channel_pack=0\nmipmaps/generate=true\nmipmaps/limit=-1\nroughness/mode=0\n"
                'roughness/src_normal=""\nprocess/fix_alpha_border=false\nprocess/premult_alpha=false\nprocess/size_limit=0\n'
                "detect_3d/compress_to=0\n" % rel)


# ------------------------------------------------------------------ drawing shapes (supersampled masks)
class Shapes:
    """Draw anti-aliased masks with PIL at 2x and get them back as float arrays."""

    def __init__(self):
        self.img = Image.new("L", (W * SS, H * SS), 0)
        self.d = ImageDraw.Draw(self.img)

    def p(self, x_mm, y_mm):
        return (x_mm * PX * SS, y_mm * PX * SS)

    def poly(self, pts_mm, fill=255):
        self.d.polygon([self.p(x, y) for x, y in pts_mm], fill=fill)

    def ellipse(self, cx, cy, rx, ry, fill=255):
        a = self.p(cx - rx, cy - ry)
        b = self.p(cx + rx, cy + ry)
        self.d.ellipse([a, b], fill=fill)

    def line(self, pts_mm, width_mm, fill=255):
        self.d.line([self.p(x, y) for x, y in pts_mm], fill=fill, width=max(1, int(width_mm * PX * SS)), joint="curve")

    def text(self, x, y, s, size_mm, font="LilitaOne.ttf", fill=255, anchor="mm"):
        f = ImageFont.truetype(os.path.join(ROOT, "assets", "fonts", font), int(size_mm * PX * SS))
        self.d.text(self.p(x, y), s, font=f, fill=fill, anchor=anchor)

    def mask(self, blur_mm=0.0):
        img = self.img.resize((W, H), Image.LANCZOS)
        if blur_mm > 0:
            img = img.filter(ImageFilter.GaussianBlur(blur_mm * PX))
        return np.asarray(img, dtype=float) / 255.0


def rot(pts, ang, cx, cy):
    c, s = math.cos(ang), math.sin(ang)
    return [(cx + (x - cx) * c - (y - cy) * s, cy + (x - cx) * s + (y - cy) * c) for x, y in pts]


def leaf_pts(cx, cy, length, width, ang, spikes=0, spike_depth=0.25):
    """A leaf outline (pointed both ends); spikes > 0 = holly-like points along the sides."""
    pts = []
    n = 40
    for i in range(n + 1):
        t = i / n
        x = (t - 0.5) * length
        w = math.sin(math.pi * t) ** 0.8 * width / 2
        if spikes:
            ph = (t * spikes) % 1.0
            w *= 1.0 - spike_depth * (1 - abs(ph * 2 - 1)) if 0.05 < t < 0.95 else 1.0
        pts.append((x, -w))
    for i in range(n, -1, -1):
        t = i / n
        x = (t - 0.5) * length
        w = math.sin(math.pi * t) ** 0.8 * width / 2
        if spikes:
            ph = (t * spikes + 0.5) % 1.0
            w *= 1.0 - spike_depth * (1 - abs(ph * 2 - 1)) if 0.05 < t < 0.95 else 1.0
        pts.append((x, w))
    c, s = math.cos(ang), math.sin(ang)
    return [(cx + x * c - y * s, cy + x * s + y * c) for x, y in pts]


def dist_to_shape(mask, max_mm=3.0):
    """Approximate inside-depth (0 at the edge .. 1 at max_mm inside) by repeated blur."""
    img = Image.fromarray((mask * 255).astype(np.uint8))
    b = np.asarray(img.filter(ImageFilter.GaussianBlur(max_mm * PX * 0.5)), dtype=float) / 255.0
    return np.clip((b - 0.5) * 2.0, 0, 1) * mask


def bump_of(mask, mm=0.8):
    """A soft dome over a mask (for relief)."""
    img = Image.fromarray((np.clip(mask, 0, 1) * 255).astype(np.uint8))
    return np.asarray(img.filter(ImageFilter.GaussianBlur(mm * PX)), dtype=float) / 255.0


WMM, HMM = W / PX, H / PX  # sheet size in mm


# ================================================================== FINISHES
def candy_cane(s, rng):
    x, y = grid()
    # twisted stripes that bend a little, like a pulled cane
    warp = (fbm(30, 3) - 0.5) * 9.0 + np.sin(x / 40.0) * 3.0
    k = (x + y * 0.9 + warp) / 14.0
    f = k - np.floor(k)
    aa = 0.035
    red = smooth(0.0, aa, f) * (1 - smooth(0.42 - aa, 0.42, f))
    thin_g = smooth(0.52, 0.52 + aa, f) * (1 - smooth(0.6 - aa, 0.6, f))
    thin_r = smooth(0.7, 0.7 + aa, f) * (1 - smooth(0.74 - aa, 0.74, f))
    cream = hexc("#fbf3e8")
    s.put(np.ones((H, W)), cream, coat=1.0, metal=0.0)
    s.col = s.col * (0.95 + 0.07 * fbm(4, 11))[..., None]
    red_c = mix(hexc("#c3101e"), hexc("#ff3b3b"), smooth(0.0, 0.42, f) * (1 - smooth(0.2, 0.42, f)) * 1.6)
    s.put(red, red_c)
    s.put(thin_g, hexc("#1f8a3a"))
    s.put(thin_r, hexc("#e8323a"))
    # candy relief: each stripe rounded, glossy
    s.height = 0.5 + 0.18 * np.cos(f * 2 * math.pi * 1.0) + 0.05 * fbm(3, 5)
    # pulled-sugar streaks inside the white
    streak = smooth(0.62, 0.8, fbm(8, 21, sx=4.0, sy=0.5)) * (1 - red)
    s.put(streak * 0.35, hexc("#ffffff"))
    # sugar crystals: tiny glints
    g = rng.random((H, W))
    glints = (g > 0.9975).astype(float)
    glints = np.asarray(Image.fromarray((glints * 255).astype(np.uint8)).filter(ImageFilter.MaxFilter(3)), dtype=float) / 255
    s.put(glints * 0.9, hexc("#ffffff"), add_height=0.25)
    # icing along the spine: wavy lower edge with drips
    sh = Shapes()
    pts = [(0, 0)]
    xx = 0.0
    while xx <= WMM + 2:
        depth = 4.2 + 1.3 * math.sin(xx / 7.0) + 0.8 * math.sin(xx / 2.3 + 1)
        pts.append((xx, depth))
        xx += 0.6
    pts.append((WMM + 2, 0))
    sh.poly(pts)
    xx = 3.0
    while xx < WMM:
        dl = rng.uniform(2.0, 8.0)
        wd = rng.uniform(1.4, 2.6)
        top = 4.0 + 1.3 * math.sin(xx / 7.0)
        sh.poly([(xx - wd / 2, top - 0.5), (xx + wd / 2, top - 0.5), (xx + wd * 0.4, top + dl * 0.7), (xx, top + dl), (xx - wd * 0.4, top + dl * 0.7)])
        sh.ellipse(xx, top + dl, wd * 0.48, wd * 0.5)
        xx += rng.uniform(6.0, 15.0)
    icing = sh.mask()
    s.put(icing, hexc("#fffaf4") * 1.0, coat=0.5, height=None)
    s.height += bump_of(icing, 0.7) * 0.35
    s.col = s.col - (bump_of(icing, 0.5) - icing).clip(0, 1)[..., None] * 0.25  # its soft shadow
    # holly clusters + peppermints along the icing
    holly = Shapes()
    veins = Shapes()
    berries = Shapes()
    mint = Shapes()
    wedge = Shapes()
    mints = []
    xx = 12.0
    while xx < WMM - 6:
        cy = 5.0 + rng.uniform(-0.5, 1.0)
        for a in (-0.5, 0.45, 2.6):
            ang = a + rng.uniform(-0.15, 0.15)
            lx = xx + math.cos(ang) * 4.3
            ly = cy + math.sin(ang) * 3.2
            holly.poly(leaf_pts(lx, ly, 9.0, 4.4, ang, spikes=4, spike_depth=0.55))
            veins.line([(xx + math.cos(ang) * 0.5, cy + math.sin(ang) * 0.5), (xx + math.cos(ang) * 8.4, cy + math.sin(ang) * 6.0)], 0.22)
        for bx, by in ((-0.9, 0.3), (0.9, 0.5), (0.0, -0.8)):
            berries.ellipse(xx + bx, cy + by, 1.15, 1.15)
        if rng.random() < 0.7:
            mints.append((xx + rng.uniform(14, 22), rng.uniform(17, 31), rng.uniform(4.2, 5.4)))
        xx += rng.uniform(26, 38)
    for mx, my, mr in mints:  # peppermint swirls: a white disc with curved red wedges
        mint.ellipse(mx, my, mr, mr)
        for i in range(8):
            a0 = i / 8 * 2 * math.pi
            pts = [(mx, my)]
            for j in range(13):
                t = j / 12
                a = a0 + t * (math.pi / 8) + t * t * 0.9
                pts.append((mx + math.cos(a) * mr * t ** 0.6 * 0.92, my + math.sin(a) * mr * t ** 0.6 * 0.92))
            for j in range(12, -1, -1):
                t = j / 12
                a = a0 + math.pi / 8 * 0.0 + t * t * 0.9 + 0.01
                pts.append((mx + math.cos(a) * mr * t * 0.92, my + math.sin(a) * mr * t * 0.92))
            wedge.poly(pts)
    mm_ = mint.mask()
    s.put(mm_, hexc("#fffaf6"), coat=1.0)
    s.height += bump_of(mm_, 1.0) * 0.4
    s.col = s.col - (bump_of(mm_, 0.8) - mm_).clip(0, 1)[..., None] * 0.3
    s.put(wedge.mask() * mm_, hexc("#d8142a"))
    hm = holly.mask()
    shade = 0.75 + 0.35 * fbm(2, 31)
    s.put(hm, (hexc("#0f5a24")[None, None, :] * shade[..., None]), coat=1.0)
    s.height += bump_of(hm, 0.6) * 0.3
    s.put(veins.mask() * hm, hexc("#6fbf5a"))
    bm = berries.mask()
    s.put(bm, hexc("#d5102a"), coat=1.0)
    s.height += bump_of(bm, 0.5) * 0.45
    hlm = np.clip(bump_of(bm, 0.25) - 0.75, 0, 1) * 3
    s.put(hlm * bm, hexc("#ffd0d0"))


def mossback(s, rng):
    x, y = grid()
    # BARK: long fibres along the blade, deep crevices
    fib = fbm(10, 41, sx=6.0, sy=0.6)
    crev = 1 - np.abs(fbm(14, 43, sx=5.0, sy=0.7) * 2 - 1)
    crev = smooth(0.78, 0.95, crev)
    bark = mix(hexc("#5a3f28"), hexc("#8a6a48"), fib)
    bark = mix(bark, hexc("#2a1c12"), crev)
    s.put(np.ones((H, W)), bark, coat=0.15, metal=0.0)
    s.height = 0.55 + 0.25 * fib - 0.4 * crev
    # LICHEN rosettes: pale lobed patches with rings
    lic = Shapes()
    for _ in range(26):
        cx, cy = rng.uniform(0, WMM), rng.uniform(0, HMM)
        r = rng.uniform(1.5, 4.0)
        pts = []
        lobes = rng.integers(6, 11)
        for i in range(48):
            a = i / 48 * 2 * math.pi
            rr = r * (0.75 + 0.25 * math.cos(a * lobes + rng.uniform(0, 0.4)))
            pts.append((cx + math.cos(a) * rr, cy + math.sin(a) * rr))
        lic.poly(pts)
    lm = lic.mask()
    lic_c = mix(hexc("#a9b89a"), hexc("#d8dcc4"), fbm(1.2, 51))
    s.put(lm * 0.95, lic_c, coat=0.0)
    s.height += bump_of(lm, 0.3) * 0.12
    # MOSS: clumps with fuzzy edges and fine pile
    cover = fbm(16, 61) + (fbm(4, 63) - 0.5) * 0.25
    clump = smooth(0.5, 0.56, cover)
    pile = fbm(0.7, 65, octaves=3)
    moss_c = mix(hexc("#2f5a1c"), hexc("#7aa83a"), smooth(0.3, 0.8, pile))
    moss_c = mix(moss_c, hexc("#a6c84a"), smooth(0.72, 0.9, fbm(6, 67)) * 0.6)
    moss_c = mix(moss_c, hexc("#1a3612"), smooth(0.5, 0.53, cover) * (1 - smooth(0.53, 0.6, cover)) * 0.6)  # darker rim
    fuzz = clump * smooth(0.25, 0.6, pile + (cover - 0.5) * 4)
    s.put(fuzz, moss_c, coat=0.0)
    s.height += fuzz * (0.25 + 0.2 * pile)
    # moss sporophytes: thin red-brown stalks with capsules near clump tops
    sp = Shapes()
    caps = Shapes()
    for _ in range(420):
        cx, cy = rng.uniform(0, WMM), rng.uniform(0, HMM)
        if clump[min(int(cy * PX), H - 1), min(int(cx * PX), W - 1)] < 0.9:
            continue
        a = rng.uniform(-0.6, 0.6) - math.pi / 2
        ln_ = rng.uniform(1.5, 3.2)
        ex, ey = cx + math.cos(a) * ln_, cy + math.sin(a) * ln_
        sp.line([(cx, cy), (ex, ey)], 0.13)
        caps.ellipse(ex, ey, 0.32, 0.22)
    s.put(sp.mask() * 0.9, hexc("#8a3a1a"))
    cm = caps.mask()
    s.put(cm, hexc("#c9893a"), coat=0.3)
    s.height += cm * 0.15
    # FERNS: a few fronds lying along the blade, each with alternating pinnae and a fiddlehead
    fern = Shapes()
    rach = Shapes()
    for i in range(6):
        x0 = rng.uniform(10, WMM - 70)
        y0 = rng.uniform(10, HMM - 10)
        length = rng.uniform(45, 70)
        bend = rng.uniform(-0.25, 0.25)
        pts = []
        n = 60
        for j in range(n + 1):
            t = j / n
            px_ = x0 + t * length
            py_ = y0 + math.sin(t * math.pi) * bend * length * 0.35 + (t * t) * bend * 8
            pts.append((px_, py_))
        rach.line(pts, 0.45)
        for j in range(4, n - 2, 3):
            t = j / n
            px_, py_ = pts[j]
            dx = pts[j + 1][0] - pts[j - 1][0]
            dy = pts[j + 1][1] - pts[j - 1][1]
            base = math.atan2(dy, dx)
            plen = 6.5 * (1 - t) ** 0.7 + 1.2
            for side in (-1, 1):
                ang = base + side * 1.05
                cx = px_ + math.cos(ang) * plen * 0.5
                cy = py_ + math.sin(ang) * plen * 0.5
                fern.poly(leaf_pts(cx, cy, plen, plen * 0.32, ang))
        # fiddlehead curl at the base
        cx, cy = x0 - 2.0, y0
        curl = []
        for j in range(60):
            a = j / 60 * 3.6 * math.pi
            r = 2.6 * (1 - j / 60) + 0.3
            curl.append((cx + math.cos(a) * r, cy + math.sin(a) * r))
        rach.line(curl, 0.5)
    fm = fern.mask()
    rm = rach.mask()
    fern_c = mix(hexc("#3f8a2a"), hexc("#8ccf4a"), fbm(2, 71))
    s.put(fm, fern_c, coat=0.35)
    s.height += bump_of(fm, 0.25) * 0.25
    s.put(rm, hexc("#2c5a18"), coat=0.35)
    s.height += rm * 0.12
    vein = fm * smooth(0.55, 0.75, fbm(0.5, 73, sx=0.3, sy=1.5)) * 0.25
    s.put(vein, hexc("#b9e86a"))
    # FLOWERS: forget-me-not clusters on the moss
    fl = Shapes()
    ctr = Shapes()
    for _ in range(60):
        cx, cy = rng.uniform(0, WMM), rng.uniform(0, HMM)
        if clump[min(int(cy * PX), H - 1), min(int(cx * PX), W - 1)] < 0.95:
            continue
        for k in range(rng.integers(2, 5)):
            fx = cx + rng.uniform(-2.5, 2.5)
            fy = cy + rng.uniform(-2.0, 2.0)
            r = rng.uniform(0.9, 1.3)
            ph = rng.uniform(0, 1)
            pts = []
            for i in range(50):
                a = i / 50 * 2 * math.pi
                rr = r * (0.55 + 0.45 * abs(math.cos(a * 2.5 + ph)))
                pts.append((fx + math.cos(a) * rr, fy + math.sin(a) * rr))
            fl.poly(pts)
            ctr.ellipse(fx, fy, r * 0.25, r * 0.25)
    flm = fl.mask()
    s.put(flm, mix(hexc("#5a8cff"), hexc("#a8c4ff"), fbm(0.8, 81)), coat=0.4)
    s.height += bump_of(flm, 0.2) * 0.2
    s.put(ctr.mask(), hexc("#ffd84a"))
    # DEW: glossy beads with a highlight and a dark rim
    dew = Shapes()
    hi = Shapes()
    for _ in range(140):
        cx, cy = rng.uniform(0, WMM), rng.uniform(0, HMM)
        r = rng.uniform(0.35, 0.9)
        dew.ellipse(cx, cy, r, r)
        hi.ellipse(cx - r * 0.3, cy - r * 0.35, r * 0.28, r * 0.22)
    dm = dew.mask()
    s.col = s.col * (1 - dm[..., None] * 0.35) + dm[..., None] * np.array([0.55, 0.7, 0.62]) * 0.35
    s.put(dm, None, coat=1.0)
    s.height += bump_of(dm, 0.3) * 0.5
    s.put(hi.mask(), hexc("#ffffff"))


def quartermasters_hook(s, rng):
    x, y = grid()
    brass = mix(hexc("#a0782a"), hexc("#e8c26a"), fbm(20, 91) * 0.6 + 0.2)
    brush = fbm(30, 93, sx=12.0, sy=0.04, octaves=3)
    brass = brass * (0.9 + 0.15 * brush)[..., None]
    s.put(np.ones((H, W)), brass, coat=0.0, metal=1.0)
    s.height = 0.5 + 0.03 * brush
    # navy enamel field between two rope borders
    top_b, bot_b = 6.5, HMM - 6.5
    field = smooth(top_b + 1.6, top_b + 1.8, y) * (1 - smooth(bot_b - 1.8, bot_b - 1.6, y))
    navy = mix(hexc("#0c2440"), hexc("#1a3c64"), fbm(8, 95))
    navy = navy * (0.9 + 0.12 * fbm(1, 97))[..., None]
    s.put(field, navy, coat=1.0, metal=0.0)
    s.height -= field * 0.15
    # twisted ropes along both borders
    for cy in (top_b, bot_b):
        band = 1 - smooth(1.2, 1.6, np.abs(y - cy))
        strand = ((x * 0.9 + (y - cy) * 1.6) / 2.6) % 1.0
        ridge = np.sin(strand * math.pi)
        rope_c = mix(hexc("#8a6a2a"), hexc("#f0d080"), ridge)
        s.put(band, rope_c, metal=0.85, coat=0.0)
        s.height += band * (0.15 + 0.35 * ridge - 0.25 * smooth(0.0, 0.08, 1 - np.abs(strand * 2 - 1)) * 0)
        s.put(band * smooth(0.9, 1.0, 1 - np.abs(strand * 2 - 1)) * 0.0, None)
        groove = band * (1 - smooth(0.0, 0.12, np.minimum(strand, 1 - strand)))
        s.put(groove * 0.7, hexc("#3a2810"))
        s.height -= groove * 0.3
    # engraved motifs in brass inside the field: compass roses, anchors, ship's wheels, waves, stars
    eng = Shapes()
    fill = Shapes()
    xx = 18.0
    kinds = ["compass", "anchor", "wheel", "compass", "anchor", "wheel"]
    k = 0
    cy = HMM / 2
    while xx < WMM - 14:
        kind = kinds[k % len(kinds)]
        if kind == "compass":
            r = 11.0
            eng.ellipse(xx, cy, r, r)
            eng.ellipse(xx, cy, r - 0.5, r - 0.5, fill=0)
            eng.ellipse(xx, cy, r - 2.0, r - 2.0)
            eng.ellipse(xx, cy, r - 2.4, r - 2.4, fill=0)
            for i in range(32):
                a = i / 32 * 2 * math.pi
                l0 = r - 2.0 if i % 4 else r - 3.0
                eng.line([(xx + math.cos(a) * l0, cy + math.sin(a) * l0), (xx + math.cos(a) * (r - 0.5), cy + math.sin(a) * (r - 0.5))], 0.18)
            for i in range(8):
                a = i / 8 * 2 * math.pi - math.pi / 2
                L = r - 1.0 if i % 2 == 0 else r - 4.5
                wdt = 1.6 if i % 2 == 0 else 1.1
                tip = (xx + math.cos(a) * L, cy + math.sin(a) * L)
                lft = (xx + math.cos(a - math.pi / 2) * wdt, cy + math.sin(a - math.pi / 2) * wdt)
                rgt = (xx + math.cos(a + math.pi / 2) * wdt, cy + math.sin(a + math.pi / 2) * wdt)
                fill.poly([(xx, cy), lft, tip])
                eng.poly([(xx, cy), tip, rgt])
                eng.poly([(xx + (rgt[0] - xx) * 0.75, cy + (rgt[1] - cy) * 0.75), tip, (xx, cy)], fill=0)
            eng.text(xx, cy - r - 2.6, "N", 3.6, font="Cinzel.ttf")
            xx += 34
        elif kind == "anchor":
            eng.ellipse(xx, cy - 9.5, 1.8, 1.8)
            eng.ellipse(xx, cy - 9.5, 1.0, 1.0, fill=0)
            eng.line([(xx, cy - 7.8), (xx, cy + 9.0)], 1.0)
            eng.line([(xx - 5.0, cy - 5.2), (xx + 5.0, cy - 5.2)], 0.9)
            arc = [(xx + math.cos(a) * 8.0, cy + 1.6 + math.sin(a) * 8.0) for a in np.linspace(0.2, math.pi - 0.2, 30)]
            eng.line(arc, 1.0)
            for sx_ in (-1, 1):
                ex, ey = arc[0] if sx_ > 0 else arc[-1]
                eng.poly([(ex, ey - 2.2), (ex + sx_ * 2.0, ey + 0.4), (ex - sx_ * 0.6, ey + 0.6)])
            rope = [(xx + 1.6 * math.sin(t * 9) + t * 3 - 4, cy - 7 + t * 16) for t in np.linspace(0, 1, 50)]
            eng.line(rope, 0.35)
            xx += 26
        else:  # ship's wheel
            r = 8.5
            eng.ellipse(xx, cy, r, r)
            eng.ellipse(xx, cy, r - 1.1, r - 1.1, fill=0)
            eng.ellipse(xx, cy, 2.2, 2.2)
            eng.ellipse(xx, cy, 1.2, 1.2, fill=0)
            for i in range(8):
                a = i / 8 * 2 * math.pi
                eng.line([(xx + math.cos(a) * 2.2, cy + math.sin(a) * 2.2), (xx + math.cos(a) * (r + 3.0), cy + math.sin(a) * (r + 3.0))], 0.8)
                eng.ellipse(xx + math.cos(a) * (r + 3.2), cy + math.sin(a) * (r + 3.2), 0.9, 0.9)
            xx += 30
        # little stars and wave curls between motifs
        for _ in range(3):
            sx2, sy2 = xx - rng.uniform(4, 9), rng.uniform(top_b + 4, bot_b - 4)
            pts = []
            for i in range(10):
                a = i / 10 * 2 * math.pi - math.pi / 2
                rr = 1.2 if i % 2 == 0 else 0.5
                pts.append((sx2 + math.cos(a) * rr, sy2 + math.sin(a) * rr))
            eng.poly(pts)
        k += 1
    # waves along the bottom of the field
    for row in range(2):
        wy = bot_b - 4.5 - row * 2.2
        pts = []
        xx2 = 0.0
        while xx2 < WMM:
            pts.append((xx2, wy + math.sin(xx2 / 3.2 + row) * 0.9))
            xx2 += 0.4
        eng.line(pts, 0.3)
    em = eng.mask()
    fm = fill.mask()
    lines = np.clip(em, 0, 1) * field
    s.put(lines, brass * 1.08, metal=1.0, coat=0.0)
    s.height += lines * 0.2
    s.put(fm * field, hexc("#7a1a1a"), coat=1.0)  # red enamel half of the compass points
    # scrimshaw hatching inside motifs
    s.col = s.col * (1 - (lines * 0.08)[..., None])


def blast_furnace(s, rng):
    x, y = grid()
    # DAMASCUS: many thin folded layers (etched light / dark steel), twisted with a ladder ripple and a few rosettes
    wx = (fbm(22, 101) - 0.5) * 10.0 + np.sin(x / 11.0) * 1.6
    ladder = np.sin(x / 4.2) * 0.9 * smooth(0.45, 0.65, fbm(28, 103))
    ros = np.zeros((H, W))
    for _ in range(9):
        cx, cy = rng.uniform(0, WMM), rng.uniform(8, HMM - 8)
        d = np.sqrt((x - cx) ** 2 + ((y - cy) * 1.3) ** 2)
        ros += np.exp(-(d / 7.0) ** 2) * np.sin(d / 0.9) * 1.6
    spacing = 0.55 + 0.4 * fbm(15, 121)
    layer = (y + wx + ladder + ros) / spacing
    band = 0.5 + 0.5 * np.sin(layer * math.pi + fbm(3, 123) * 2.0)
    band = smooth(0.15, 0.85, band) * 0.7 + 0.3 * smooth(0.35, 0.65, fbm(1.5, 125))
    grain = fbm(0.6, 105, octaves=2)
    steel = mix(hexc("#4c4f54"), hexc("#b9bcc0"), band * 0.85 + grain * 0.15)
    s.put(np.ones((H, W)), steel, coat=0.0, metal=1.0)
    s.height = 0.5 + 0.12 * band
    # LAVA: veins that follow the layers and break across them, flowing along the blade
    sel = smooth(0.52, 0.62, fbm(26, 107))
    along = 1 - smooth(0.0, 0.22, np.abs(np.sin(layer * math.pi / 3.0)))
    across = 1 - smooth(0.0, 0.06, np.abs(fbm(6, 109, sx=0.4, sy=2.0) - 0.5))
    seam = along * sel * smooth(0.35, 0.7, fbm(2.0, 115) + 0.2) * 0.8
    # big branching fissures splitting the steel open
    fis = Shapes()
    for _ in range(7):
        px_, py_ = rng.uniform(0, WMM), rng.uniform(4, HMM - 4)
        ang = rng.uniform(-0.4, 0.4) + (math.pi if rng.random() < 0.5 else 0)
        width = rng.uniform(0.45, 0.8)
        pts = [(px_, py_)]
        for step in range(70):
            ang += rng.uniform(-0.35, 0.35)
            ang = ang * 0.92 + (0 if math.cos(ang) > 0 else math.pi) * 0.08
            px_ += math.cos(ang) * 1.6
            py_ = py_ + math.sin(ang) * 1.6
            if py_ < 0.5 or py_ > HMM - 0.5:
                ang = -ang
                py_ = min(max(py_, 0.5), HMM - 0.5)
            pts.append((px_, py_))
            if rng.random() < 0.07:  # a branch
                bx, by, ba = px_, py_, ang + rng.choice([-1, 1]) * rng.uniform(0.6, 1.1)
                bp = [(bx, by)]
                for _b in range(rng.integers(6, 16)):
                    ba += rng.uniform(-0.3, 0.3)
                    bx += math.cos(ba) * 1.3
                    by += math.sin(ba) * 1.3
                    bp.append((bx, by))
                fis.line(bp, width * 0.45)
        fis.line(pts, width)
    fm = fis.mask()
    core = np.clip(bump_of(fm, 0.25) * 1.6 - 0.3, 0, 1) * fm
    seam = np.clip(np.maximum(seam * 0.7, fm * (0.45 + 0.55 * core) * smooth(0.2, 0.55, fbm(1.2, 127) + 0.25)), 0, 1)
    halo = smooth(0.08, 0.5, bump_of(seam, 2.0))
    heat = mix(hexc("#3a2a7a"), hexc("#d89a30"), smooth(0.15, 0.85, halo))
    s.put(halo * 0.9 * (1 - seam), heat, coat=0.0)
    lava = mix(hexc("#c81800"), hexc("#ff7a10"), smooth(0.2, 0.6, seam))
    lava = mix(lava, hexc("#fff2b0"), smooth(0.75, 1.0, seam))
    s.put(seam, lava, coat=0.7, metal=0.0)
    s.glow = np.clip(seam * 1.1 + halo * 0.3, 0, 1)
    s.anim = (x / 45.0 + fbm(10, 117) * 0.5) % 1.0
    s.height -= seam * 0.3
    # crust on the lava: dark cooling flakes
    crust = smooth(0.62, 0.7, fbm(1.4, 119)) * seam
    s.put(crust * 0.8, hexc("#2a0e06"), glow=0.0)


def quench(s, rng):
    """CASE HARDENED: heat-coloured oxide on grey steel, thin-film bands at the edges of each colour, a blue left end (Bluegem)."""
    x, y = grid()
    w1 = fbm(26, 201)
    wx = (fbm(14, 203) - 0.5) * 22
    wy = (fbm(14, 205) - 0.5) * 22
    n = warp_sample(fbm(16, 207), wx * PX, wy * PX)
    m = warp_sample(fbm(9, 209), wy * PX * 0.6, wx * PX * 0.6)
    grain = fbm(0.5, 211, octaves=2)
    steel = mix(hexc("#5f6266"), hexc("#a3a6a9"), grain * 0.5 + fbm(6, 213) * 0.5)
    s.put(np.ones((H, W)), steel, coat=0.0, metal=1.0)
    blue_bias = smooth(190, 20, x) * 0.22  # the left end goes blue (the Bluegem window)
    blue = smooth(0.58 - blue_bias, 0.61 - blue_bias, n)
    gold = smooth(0.46, 0.52, m) * (1 - blue)
    purple = (1 - smooth(0.0, 0.03, np.abs(n - (0.585 - blue_bias)))) * 0.9
    bronze = smooth(0.6, 0.66, m) * (1 - blue)
    bc = mix(hexc("#123a9a"), hexc("#3c7cf0"), fbm(3, 215))
    bc = mix(bc, hexc("#0a1f5a"), smooth(0.7, 0.85, n) * 0.6)
    gc = mix(hexc("#a8822a"), hexc("#e9c968"), fbm(2.5, 217))
    s.put(gold * 0.9, gc)
    s.put(bronze * 0.7, hexc("#8a4f22"))
    s.put(blue, bc)
    s.put(purple, hexc("#7a3aa8"))
    # thin-film ripples: many fine contour lines round each pool
    film = np.abs(np.sin(n * 140.0)) * (1 - blue) * smooth(0.4, 0.5, n) * 0.25
    s.col = s.col + film[..., None] * np.array([0.15, 0.05, 0.25])
    speck = (rng.random((H, W)) > 0.996).astype(float)
    s.put(speck * 0.6, hexc("#1a1a1e"))
    s.height = 0.5 + 0.05 * grain + 0.04 * blue


def heat_fade(s, rng):
    """Heat-tinted steel: straw, gold, bronze, magenta, violet, blue bands that lick along the blade like a flame; hammered dimples."""
    x, y = grid()
    flame = x / WMM + (fbm(20, 221) - 0.5) * 0.25 + (fbm(5, 223) - 0.5) * 0.06 + (y / HMM - 0.5) * 0.12
    stops = [(0.0, "#9fa3a8"), (0.12, "#d9c58a"), (0.26, "#e6a640"), (0.4, "#b8642a"), (0.52, "#a8306a"), (0.64, "#6a2aa0"), (0.78, "#2a4ad0"), (0.9, "#3aa0e8"), (1.0, "#b8e8ff")]
    col = np.zeros((H, W, 3)) + hexc(stops[0][1])
    for (a, ca), (b, cb) in zip(stops, stops[1:]):
        t = smooth(a, b, flame)
        col = mix(col, hexc(cb), t)
    s.put(np.ones((H, W)), col, coat=0.15, metal=1.0)
    # fine bands inside the gradient
    band = np.abs(np.sin(flame * 90.0)) * 0.06
    s.col = s.col * (1 - band[..., None])
    # hammered dimples
    cid, d1, d2, pts = voronoi(3.2, 225, jitter=0.9)
    dimple = np.clip(d1 / 2.0, 0, 1)
    s.height = 0.35 + 0.35 * dimple
    rim = 1 - smooth(0.0, 0.18, d2 - d1)
    s.col = s.col * (0.9 + 0.12 * dimple[..., None]) + rim[..., None] * 0.04
    # mill scale lines
    scale = smooth(0.82, 0.9, fbm(30, 227, sx=8, sy=0.2)) * 0.3
    s.put(scale, hexc("#2a2a30"))


def slag(s, rng):
    """Cooled slag: rough dark crust plates, dull glowing cracks between them, bright metal beads, rust blooms, soot."""
    x, y = grid()
    cid, d1, d2, pts = voronoi(9.0, 231, jitter=1.0)
    edge = d2 - d1 + (fbm(1.5, 233) - 0.5) * 0.9
    crack = 1 - smooth(0.05, 0.45, edge)
    plate_tone = (np.random.default_rng(235).random(cid.max() + 1))[cid]
    rough = fbm(1.0, 237) * 0.6 + fbm(4, 239) * 0.4
    crust = mix(hexc("#1e1b1a"), hexc("#4a4038"), plate_tone * 0.6 + rough * 0.4)
    crust = mix(crust, hexc("#6a5a4a"), smooth(0.7, 0.9, rough) * 0.5)
    s.put(np.ones((H, W)), crust, coat=0.4, metal=0.1)
    s.height = 0.45 + 0.3 * rough + 0.25 * smooth(0.0, 1.5, edge)
    rust = smooth(0.66, 0.74, fbm(7, 241)) * (1 - crack)
    s.put(rust * 0.7, mix(hexc("#7a3a12"), hexc("#b8601e"), fbm(1, 243)))
    hot = mix(hexc("#7a1a04"), hexc("#ff7a1a"), crack ** 2)
    hot = mix(hot, hexc("#ffd070"), smooth(0.85, 1.0, crack))
    s.put(crack, hot, coat=0.6)
    s.glow = crack ** 1.5 * smooth(0.3, 0.6, fbm(15, 245) + 0.2)
    s.anim = (x / 50.0 + fbm(8, 247)) % 1.0
    s.height -= crack * 0.4
    beads = Shapes()
    hi = Shapes()
    for _ in range(90):
        cx, cy, r = rng.uniform(0, WMM), rng.uniform(0, HMM), rng.uniform(0.4, 1.4)
        beads.ellipse(cx, cy, r, r)
        hi.ellipse(cx - r * 0.3, cy - r * 0.3, r * 0.3, r * 0.25)
    bm = beads.mask()
    s.put(bm, hexc("#8a8c90"), coat=0.0, metal=1.0)
    s.height += bump_of(bm, 0.4) * 0.5
    s.put(hi.mask(), hexc("#f0f0f0"))
    soot = smooth(0.4, 0.8, fbm(30, 249)) * 0.35
    s.col = s.col * (1 - soot[..., None])


def temper_line(s, rng):
    """A sword-maker's blade: wood-grain folded steel above a misty wavy temper line, bright crystals along it, temper colours at the spine and a groove."""
    x, y = grid()
    # hada: wood grain of folded steel
    gw = (fbm(18, 251) - 0.5) * 9 + (fbm(5, 253) - 0.5) * 2
    rings = 0.5 + 0.5 * np.sin((y * 1.7 + gw * 2.0 + np.sin(x / 6.0) * 0.6) * 2.4)
    hada = mix(hexc("#6a6d72"), hexc("#9a9da2"), rings * 0.6 + fbm(0.8, 255) * 0.4)
    s.put(np.ones((H, W)), hada, coat=0.0, metal=1.0)
    # hamon: misty white wavy band in the lower third
    line_y = HMM * 0.68 + np.sin(x / 7.5) * 2.2 + np.sin(x / 2.9 + 1.3) * 0.9 + (fbm(6, 257) - 0.5) * 2.5
    below = smooth(line_y - 1.2, line_y + 0.8, y)
    mist = np.exp(-((y - line_y) / 1.4) ** 2)
    s.put(below * 0.9, mix(hexc("#d8dbe0"), hexc("#f2f4f6"), fbm(1.5, 259)))
    s.put(mist * 0.6, hexc("#ffffff"))
    nie = (rng.random((H, W)) > 0.985).astype(float) * mist
    s.put(nie, hexc("#ffffff"), add_height=0.3)
    # temper colours along the spine
    spine = 1 - smooth(4.0, 11.0, y + (fbm(10, 261) - 0.5) * 3)
    tc = mix(hexc("#c8a040"), hexc("#3a5ad0"), smooth(1.5, 6.0, y + (fbm(6, 263) - 0.5) * 2))
    s.put(spine * 0.85, tc)
    # bo-hi: a groove under the spine
    groove = (1 - smooth(1.1, 1.5, np.abs(y - 9.5))) * smooth(10, 25, x)
    s.put(groove * 0.55, hexc("#2a2c30"))
    s.height = 0.5 + 0.06 * rings - groove * 0.4 + below * 0.03
    # a small engraved emblem: a flaming jewel in a circle near the guard
    e = Shapes()
    for k in range(int(WMM / 140) + 1):
        cx, cy = 22 + k * 140, HMM * 0.38
        e.ellipse(cx, cy, 5.5, 5.5)
        e.ellipse(cx, cy, 5.0, 5.0, fill=0)
        e.poly([(cx, cy - 4.0), (cx + 2.4, cy + 0.5), (cx, cy + 3.6), (cx - 2.4, cy + 0.5)])
        for a in range(6):
            ang = a / 6 * 2 * math.pi
            e.line([(cx + math.cos(ang) * 3.2, cy + math.sin(ang) * 3.2), (cx + math.cos(ang + 0.5) * 4.6, cy + math.sin(ang + 0.5) * 4.6)], 0.35)
    em = e.mask()
    s.put(em, hexc("#d8b860"), metal=1.0)
    s.height -= em * 0.25


def anvil_king(s, rng):
    """Hammered gold cooling to ember red, royal scrollwork and a crown engraved near the guard."""
    x, y = grid()
    t = x / WMM + (fbm(25, 271) - 0.5) * 0.2
    col = mix(hexc("#ffe9a0"), hexc("#f0b030"), smooth(0.0, 0.35, t))
    col = mix(col, hexc("#d8541e"), smooth(0.35, 0.7, t))
    col = mix(col, hexc("#5a160c"), smooth(0.7, 1.0, t))
    s.put(np.ones((H, W)), col, coat=0.0, metal=1.0)
    cid, d1, d2, pts = voronoi(4.5, 273, jitter=0.95)
    facet = np.clip(d1 / 2.6, 0, 1)
    s.height = 0.35 + 0.4 * facet
    s.col = s.col * (0.93 + 0.1 * facet[..., None])
    glowing = smooth(0.62, 0.95, t)
    s.glow = glowing * (0.25 + 0.5 * (1 - smooth(0.0, 0.25, d2 - d1)))
    s.anim = (x / 30.0) % 1.0
    # scrollwork: a continuous acanthus vine along the spine band: a waving stem, a curl at each crest, leaves on the curls
    e = Shapes()
    band_y, amp, per = 9.0, 4.5, 24.0
    stem = [(xx, band_y + math.sin(xx / per * 2 * math.pi) * amp) for xx in np.arange(-5, WMM + 5, 0.4)]
    e.line(stem, 0.55)
    xx = per * 0.25
    up = True
    while xx < WMM + per:
        cy = band_y + (amp if not up else -amp)
        sgn = -1 if up else 1
        curl = []
        r0 = 5.2
        ccx, ccy = xx, cy - sgn * r0  # the spiral starts on the stem's crest and winds inward
        for j in range(80):
            a_ = j / 80 * 2.6 * math.pi
            rr = r0 * (1 - a_ / (3.2 * math.pi))
            curl.append((ccx + math.sin(a_) * rr, ccy + sgn * math.cos(a_) * rr))
        e.line(curl, 0.42)
        for j in (8, 20, 34):
            px_, py_ = curl[j]
            ang = math.atan2(curl[j + 1][1] - curl[j - 1][1], curl[j + 1][0] - curl[j - 1][0]) + sgn * 0.9
            e.poly(leaf_pts(px_ + math.cos(ang) * 1.6, py_ + math.sin(ang) * 1.6, 3.6, 1.3, ang, spikes=3, spike_depth=0.3))
        e.ellipse(curl[-1][0], curl[-1][1], 0.7, 0.7)
        xx += per / 2
        up = not up
    # the same vine mirrored along the edge band, finer
    stem2 = [(xx, HMM - 7 + math.sin(xx / 16 * 2 * math.pi + 1) * 2) for xx in np.arange(-5, WMM + 5, 0.4)]
    e.line(stem2, 0.35)
    for xx in np.arange(4, WMM, 8):
        yy = HMM - 7 + math.sin(xx / 16 * 2 * math.pi + 1) * 2
        e.poly(leaf_pts(xx + 1.2, yy - 1.0, 2.8, 1.0, -0.7))
        e.poly(leaf_pts(xx + 1.2, yy + 1.0, 2.8, 1.0, 0.7))
    # crowns in cartouches every so often
    for k in range(int(WMM / 120) + 1):
        cx, cy = 60 + k * 120, 24
        e.ellipse(cx, cy, 9.5, 7.5)
        e.ellipse(cx, cy, 8.9, 6.9, fill=0)
        e.poly([(cx - 6, cy + 3.5), (cx - 6, cy - 2.5), (cx - 3.4, cy + 0.5), (cx - 1.2, cy - 4.5), (cx + 1.2, cy - 4.5), (cx + 3.4, cy + 0.5), (cx + 6, cy - 2.5), (cx + 6, cy + 3.5)])
        e.poly([(cx - 5, cy + 2.2), (cx + 5, cy + 2.2), (cx + 5, cy + 2.9), (cx - 5, cy + 2.9)], fill=0)
        for gx, gy in ((-6, -3.3), (0, -5.3), (6, -3.3)):
            e.ellipse(cx + gx, cy + gy, 0.8, 0.8)
    em = e.mask()
    s.put(em, s.col * 0.45)
    s.height -= em * 0.35
    s.glow = s.glow * (1 - em)


def molten_core(s, rng):
    """Obsidian glass with conchoidal ripples, split by rivers of molten metal with floating crust; glowing runes along the spine."""
    x, y = grid()
    cid, d1, d2, pts = voronoi(14, 281, jitter=1.0)
    ripple = 0.5 + 0.5 * np.sin(d1 * 5.0 + fbm(4, 283) * 3)
    obs = mix(hexc("#07060a"), hexc("#2a2238"), ripple * 0.35 + fbm(2, 285) * 0.2)
    s.put(np.ones((H, W)), obs, coat=0.95, metal=0.0)
    s.height = 0.5 + 0.12 * ripple
    # rivers: organic flows that swell and narrow, splitting round islands
    river = np.zeros((H, W))
    for i, (yc, amp, wd) in enumerate([(HMM * 0.55, 9, 3.6), (HMM * 0.25, 6, 2.0), (HMM * 0.82, 4, 1.4)]):
        cy = yc + (fbm(40, 287 + i) - 0.5) * amp * 3 + (fbm(9, 291 + i) - 0.5) * amp
        width = wd * (0.45 + 1.1 * fbm(22, 295 + i))
        r_i = 1 - smooth(width * 0.55, width, np.abs(y - cy))
        island = smooth(0.66, 0.72, fbm(5, 299 + i)) * r_i
        river = np.maximum(river, r_i * (1 - island))
    drips = (1 - smooth(0.0, 0.05, np.abs(fbm(7, 301, sx=0.25, sy=2.5) - 0.5))) * smooth(0.6, 0.7, fbm(25, 303)) * 0.8
    river = np.maximum(river, drips)
    core = np.clip(inside_mm(river) / 1.6, 0, 1)
    lava = mix(hexc("#a01000"), hexc("#ff5a08"), smooth(0.0, 0.4, core))
    lava = mix(lava, hexc("#ffb030"), smooth(0.4, 0.8, core))
    lava = mix(lava, hexc("#fff4c0"), smooth(0.85, 1.0, core))
    s.put(river, lava, coat=0.7)
    crust = smooth(0.58, 0.64, warp_sample(fbm(2.2, 289), -x * 0.0, 0) ) * river * (1 - smooth(0.85, 1.0, core))
    s.put(crust, mix(hexc("#1a0a06"), hexc("#3a1a10"), fbm(0.8, 291)), coat=0.3)
    s.glow = np.clip(river * (1 - crust) * 1.1 + bump_of(river, 2.5) * 0.35, 0, 1)
    s.anim = (x / 25.0 + (y / HMM) * 0.2) % 1.0
    s.height -= river * 0.25
    halo = smooth(0.05, 0.6, bump_of(river, 2.5)) * (1 - river)
    s.put(halo * 0.6, hexc("#5a1a08"))
    # runes along the spine, engraved and glowing
    r = Shapes()
    xx = 8.0
    while xx < WMM - 6:
        k = rng.integers(0, 6)
        cx, cy, hgt = xx, 5.0, 4.0
        stems = [[(cx, cy - hgt / 2), (cx, cy + hgt / 2)]]
        if k == 0: stems += [[(cx, cy - 2), (cx + 1.6, cy - 0.6)], [(cx, cy - 0.4), (cx + 1.6, cy + 1.0)]]
        if k == 1: stems += [[(cx, cy - 2), (cx + 1.6, cy)], [(cx + 1.6, cy), (cx, cy + 2)]]
        if k == 2: stems += [[(cx - 1.4, cy - 1), (cx + 1.4, cy + 1)], [(cx + 1.4, cy - 1), (cx - 1.4, cy + 1)]]
        if k == 3: stems += [[(cx, cy - 2), (cx + 1.5, cy - 0.5)], [(cx + 1.5, cy - 0.5), (cx, cy + 1)]]
        if k == 4: stems = [[(cx - 1.4, cy - 2), (cx + 1.4, cy + 2)], [(cx + 1.4, cy - 2), (cx - 1.4, cy + 2)], [(cx - 1.6, cy), (cx + 1.6, cy)]]
        if k == 5: stems += [[(cx - 1.5, cy - 2), (cx, cy - 0.5)], [(cx + 1.5, cy - 2), (cx, cy - 0.5)]]
        for st in stems:
            r.line(st, 0.42)
        xx += rng.uniform(4.0, 6.0)
    rm = r.mask()
    s.put(rm, hexc("#ff9a30"), coat=0.5)
    s.glow = np.maximum(s.glow, rm * 0.9)
    s.height -= rm * 0.3


def melt(palette, gem=None, venom=False):
    """PRISM / VENOM MELT: liquid colour marbled through black chrome with ink veins and star sparkles (one phase or gem per sheet)."""
    def draw(s, rng):
        x, y = grid()
        wx = (fbm(16, 301) - 0.5) * 30
        wy = (fbm(16, 303) - 0.5) * 30
        a = warp_sample(fbm(12, 305), wx * PX, wy * PX)
        wx2 = (a - 0.5) * 26 + wx * 0.5
        b = warp_sample(fbm(7, 307), wx2 * PX, (wy * 0.5 + (a - 0.5) * 20) * PX)
        n = np.clip((b - 0.5) * 2.4 + 0.5, 0, 1)
        flow = np.clip(a * 0.6 + b * 0.4, 0, 1)
        cols = [hexc(c) for c in palette]
        liquid = mix(cols[0], cols[1], smooth(0.25, 0.55, flow))
        liquid = mix(liquid, cols[2], smooth(0.55, 0.8, n))
        if len(cols) > 3:
            liquid = mix(liquid, cols[3], smooth(0.7, 0.9, flow) * 0.8)
        liquid = liquid * (0.65 + 0.55 * fbm(3, 309))[..., None]
        ink = smooth(0.32, 0.5, n) * smooth(0.0, 0.15, flow)
        black = np.array([0.015, 0.012, 0.025])
        col = mix(black, liquid, 0.12 + 0.88 * ink)
        veins = 1 - smooth(0.0, 0.03, np.abs(n - 0.42))
        col = mix(col, black, veins * 0.85)
        s.put(np.ones((H, W)), col, coat=0.0, metal=1.0)
        if venom:  # faint scale texture under the colour
            cid, d1, d2, pts = voronoi(2.2, 311, jitter=0.5, sx=1.3, sy=1.0)
            scl = smooth(0.0, 0.25, d2 - d1)
            s.col = s.col * (0.85 + 0.15 * scl[..., None])
            s.height += (scl - 0.5) * 0.12
        sp = (rng.random((H, W)) > 0.994).astype(float)
        sp = np.asarray(Image.fromarray((sp * 255).astype(np.uint8)).filter(ImageFilter.MaxFilter(3)), dtype=float) / 255 * 0.8
        s.put(sp, np.clip(liquid * 1.8 + 0.3, 0, 1))
        s.glow = sp * 0.8
        s.anim = rng.random((H, W))
        s.height = s.height + 0.08 * flow
    return draw


def sea_glass(s, rng):
    """Frosted sea-glass pebbles set in wet sand: each pebble its own glass colour, frosted, rounded at the edge; a few shells and a starfish."""
    x, y = grid()
    cid, d1, d2, pts = voronoi(5.5, 401, jitter=0.95)
    edge = d2 - d1
    peb = smooth(0.35, 0.75, edge + (fbm(1.2, 403) - 0.5) * 0.3)
    sand = mix(hexc("#c8b48a"), hexc("#e8dcc0"), fbm(0.5, 405, octaves=2))
    s.put(np.ones((H, W)), sand * (0.85 + 0.15 * fbm(4, 407))[..., None], coat=0.1)
    r_ = np.random.default_rng(409).random(cid.max() + 1)
    palette = np.array([hexc(c) for c in ["#7fd6c2", "#5ab88a", "#bfe8de", "#9ad0ff", "#e8f4ee", "#3a8a6a", "#2a5ab8", "#d8a050", "#6ac0d0"]])
    weights = np.array([0.2, 0.16, 0.14, 0.1, 0.14, 0.1, 0.03, 0.03, 0.1])
    pick = np.searchsorted(np.cumsum(weights / weights.sum()), r_)
    glass = palette[np.clip(pick, 0, len(palette) - 1)][cid]
    depth = np.clip(edge / 1.6, 0, 1)
    frost = fbm(0.35, 411, octaves=2)
    gcol = glass * (0.72 + 0.35 * depth[..., None]) + (frost[..., None] - 0.5) * 0.12
    gcol = mix(gcol, np.clip(glass * 1.25 + 0.15, 0, 1), (1 - smooth(0.0, 0.25, depth)) * 0.5)  # light caught in the rounded rim
    s.put(peb, gcol, coat=0.75)
    s.height = 0.35 + peb * (0.3 + 0.35 * np.sqrt(depth))
    caust = (1 - np.abs(np.sin(fbm(3, 413) * 18))) ** 6 * peb
    s.glow = caust * 0.35
    s.anim = (x / 20.0 + fbm(4, 415)) % 1.0
    sh = Shapes()
    for _ in range(10):  # spiral shells
        cx, cy, r = rng.uniform(0, WMM), rng.uniform(4, HMM - 4), rng.uniform(1.6, 2.6)
        pts_ = [(cx + math.cos(t) * r * (1 - t / 15), cy + math.sin(t) * r * (1 - t / 15)) for t in np.linspace(0, 12, 120)]
        sh.line(pts_, 0.5)
    shm = sh.mask()
    s.put(shm, hexc("#f4e8dc"), coat=0.5)
    s.height += shm * 0.3
    st = Shapes()
    for _ in range(3):
        cx, cy, r = rng.uniform(10, WMM - 10), rng.uniform(10, HMM - 10), rng.uniform(4, 6)
        a0 = rng.uniform(0, 1)
        pts_ = []
        for i in range(10):
            a = a0 + i / 10 * 2 * math.pi
            rr = r if i % 2 == 0 else r * 0.38
            pts_.append((cx + math.cos(a) * rr, cy + math.sin(a) * rr))
        st.poly(pts_)
    stm = st.mask()
    s.put(stm, mix(hexc("#e86a3a"), hexc("#ffa060"), fbm(0.6, 417)), coat=0.3)
    bumps = (rng.random((H, W)) > 0.97).astype(float) * stm
    s.put(bumps, hexc("#ffd8b0"))
    s.height += bump_of(stm, 0.5) * 0.4


def brine(s, rng):
    """Deep-sea blue fading up to a salt crust: cubic salt crystals creeping down from the spine, frost dendrites at the crust's edge."""
    x, y = grid()
    g = y / HMM
    col = mix(hexc("#e8fbff"), hexc("#5ad0e8"), smooth(0.0, 0.35, g))
    col = mix(col, hexc("#2a6ad0"), smooth(0.35, 0.7, g))
    col = mix(col, hexc("#0e1a4a"), smooth(0.7, 1.0, g))
    s.put(np.ones((H, W)), col, coat=0.3, metal=0.8)
    reach = 12 + (fbm(30, 421) - 0.5) * 18 + (fbm(6, 423) - 0.5) * 6
    crust = 1 - smooth(reach - 1.5, reach + 0.5, y)
    cr = Shapes()
    lit = Shapes()
    for _ in range(1400):
        cx = rng.uniform(0, WMM)
        cy = rng.uniform(0, 26) ** 1.2 / 26 ** 0.2
        if cy > reach[min(int(cy * PX), H - 1), min(int(cx * PX), W - 1)] + 2:
            continue
        r = rng.uniform(0.5, 1.8) * (1.2 - cy / 30)
        a = rng.uniform(0, math.pi / 2)
        sq = [(cx + math.cos(a + k * math.pi / 2) * r, cy + math.sin(a + k * math.pi / 2) * r) for k in range(4)]
        cr.poly(sq)
        lit.poly([(cx, cy), sq[0], sq[1]])  # the lit face of the cube
    cm = cr.mask()
    lm = lit.mask()
    s.put(np.maximum(cm, crust * 0.6), hexc("#e6eef2"), coat=0.6, metal=0.0)
    s.put(lm * cm, hexc("#ffffff"))
    s.put((cm - lm).clip(0, 1) * 0.5, hexc("#b8cad6"))
    s.height = 0.45 + cm * 0.35 + crust * 0.1
    den = Shapes()
    for _ in range(80):
        cx = rng.uniform(0, WMM)
        cy = float(reach[0, min(int(cx * PX), W - 1)]) if False else rng.uniform(8, 26)
        a = math.pi / 2 + rng.uniform(-0.6, 0.6)
        def branch(x0, y0, a, l, depth):
            x1, y1 = x0 + math.cos(a) * l, y0 + math.sin(a) * l
            den.line([(x0, y0), (x1, y1)], 0.12 + depth * 0.05)
            if depth > 0:
                for k in (-1, 1):
                    branch(x0 + (x1 - x0) * 0.5, y0 + (y1 - y0) * 0.5, a + k * 1.0, l * 0.45, depth - 1)
                branch(x1, y1, a + rng.uniform(-0.3, 0.3), l * 0.6, depth - 1)
        branch(cx, cy, a, rng.uniform(2, 4), 3)
    dm = den.mask() * (1 - crust)
    s.put(dm * 0.8, hexc("#e8f8ff"), coat=0.6)


def kelp_wrap(s, rng):
    """Under the kelp: deep teal water lit by slanting rays, swaying fronds with midribs and air bladders, little fish, rising bubbles."""
    x, y = grid()
    water = mix(hexc("#2a7a7a"), hexc("#06222a"), smooth(0.0, 1.0, y / HMM))
    rays = smooth(0.6, 1.0, np.sin((x + y * 0.6) / 9.0 + fbm(20, 431) * 4) * 0.5 + 0.5) * (1 - y / HMM) * 0.35
    s.put(np.ones((H, W)), water + rays[..., None] * np.array([0.6, 0.9, 0.8]), coat=0.85)
    s.glow = rays * 0.3
    s.anim = (x / 35.0) % 1.0
    fr = Shapes()
    rib = Shapes()
    bl = Shapes()
    for k in range(18):
        x0 = rng.uniform(-20, WMM)
        y0 = HMM + 2
        L = rng.uniform(60, 120)
        sway = rng.uniform(0.6, 1.4)
        ph = rng.uniform(0, 6)
        stem = []
        for j in range(80):
            t = j / 79
            stem.append((x0 + t * L * 0.9 + math.sin(t * 4 + ph) * 6 * sway, y0 - t * HMM * 1.1 + math.sin(t * 7 + ph) * 2))
        rib.line(stem, 0.5)
        for j in range(4, 76, 5):
            px_, py_ = stem[j]
            ang = math.atan2(stem[j + 1][1] - stem[j - 1][1], stem[j + 1][0] - stem[j - 1][0])
            side = 1 if (j // 5) % 2 else -1
            la = ang + side * 0.5
            ll = rng.uniform(8, 14)
            fr.poly(leaf_pts(px_ + math.cos(la) * ll * 0.5, py_ + math.sin(la) * ll * 0.5, ll, rng.uniform(2.2, 3.2), la))
            bl.ellipse(px_ + math.cos(la) * 0.8, py_ + math.sin(la) * 0.8, 0.8, 0.8)
    fm = fr.mask()
    ripple = fbm(1.0, 433, sx=3, sy=0.6)
    kcol = mix(hexc("#5a6a1a"), hexc("#a8a83a"), ripple * 0.7 + fbm(6, 435) * 0.3)
    s.put(fm, kcol, coat=0.6)
    s.height = 0.4 + bump_of(fm, 0.4) * 0.35 + fm * ripple * 0.1
    s.put(rib.mask(), hexc("#4a4a14"), coat=0.6)
    bm = bl.mask()
    s.put(bm, hexc("#b8a840"), coat=0.9)
    s.height += bump_of(bm, 0.3) * 0.4
    fish = Shapes()
    for _ in range(14):
        cx, cy, r = rng.uniform(0, WMM), rng.uniform(4, HMM - 8), rng.uniform(1.4, 2.4)
        fish.ellipse(cx, cy, r, r * 0.45)
        fish.poly([(cx - r * 0.9, cy), (cx - r * 1.7, cy - r * 0.6), (cx - r * 1.7, cy + r * 0.6)])
    s.put(fish.mask() * 0.85, hexc("#c8d8d0"), coat=0.9)
    bub = Shapes()
    for _ in range(160):
        cx, cy, r = rng.uniform(0, WMM), rng.uniform(0, HMM), rng.uniform(0.2, 0.7)
        bub.ellipse(cx, cy, r, r)
        bub.ellipse(cx, cy, r * 0.7, r * 0.7, fill=0)
    s.put(bub.mask() * 0.8, hexc("#d8fff8"))


def abyss_lantern(s, rng):
    """The abyss: black-blue water full of marine snow; an anglerfish with its lantern, glowing jellyfish, chains of light."""
    x, y = grid()
    deep = mix(hexc("#020814"), hexc("#06183a"), fbm(30, 441) * 0.8)
    s.put(np.ones((H, W)), deep, coat=0.9)
    snow = (rng.random((H, W)) > 0.993).astype(float) * (0.3 + 0.7 * rng.random((H, W)))
    s.put(snow * 0.7, hexc("#a8c8d8"))
    glow = Shapes()
    body = Shapes()
    for k in range(int(WMM / 90) + 1):  # anglerfish: round body, huge jaw, fins, glowing rim, lure and eye
        cx, cy = 30 + k * 90 + rng.uniform(-8, 8), HMM * 0.58
        r = 11.0
        pts_ = []
        for i in range(80):
            a = i / 80 * 2 * math.pi
            rr = r * (1.0 + 0.18 * math.cos(a)) * (1.0 + 0.12 * math.sin(a * 3))
            pts_.append((cx + math.cos(a) * rr * 1.15, cy + math.sin(a) * rr * 0.85))
        body.poly(pts_)
        body.poly([(cx - r * 1.05, cy - 1), (cx - r * 1.9, cy - 6), (cx - r * 1.75, cy), (cx - r * 1.9, cy + 6), (cx - r * 1.05, cy + 1)])
        body.poly([(cx - 2, cy - r * 0.8), (cx + 1, cy - r * 1.25), (cx + 4, cy - r * 0.8)])
        glow.line(pts_ + [pts_[0]], 0.3)
        jaw = [(cx + r * 1.25, cy + 0.5), (cx + r * 0.4, cy + 4.5), (cx - r * 0.1, cy + 3.0)]
        glow.line(jaw, 0.35)
        for j in range(8):
            tx = cx + r * 1.2 - j * 1.6
            ty = cy + 0.7 + j * 0.45
            glow.poly([(tx - 0.4, ty), (tx + 0.4, ty), (tx, ty + (1.8 if j % 2 else -1.4))])
        lure = [(cx + r * 0.3, cy - r * 0.8), (cx + r * 0.7, cy - r * 1.6), (cx + r * 1.4, cy - r * 1.75), (cx + r * 1.8, cy - r * 1.3)]
        glow.line(lure, 0.35)
        glow.ellipse(lure[-1][0], lure[-1][1], 2.2, 2.2)
        glow.ellipse(cx + r * 0.65, cy - 3.0, 1.4, 1.4)
    for _ in range(9):  # jellyfish
        cx, cy, r = rng.uniform(0, WMM), rng.uniform(6, HMM * 0.5), rng.uniform(3, 5)
        bell = [(cx + math.cos(a) * r, cy - math.sin(a) * r * 0.8) for a in np.linspace(0, math.pi, 30)]
        bell += [(cx - r + j * 2 * r / 8, cy + (0.6 if j % 2 else 0.0)) for j in range(9)]
        glow.poly(bell)
        for j in range(6):
            tx = cx - r * 0.8 + j * r * 0.32
            glow.line([(tx + math.sin(t * 3 + j) * 0.8, cy + t * 2.2) for t in np.linspace(0, 6, 30)], 0.15)
    for _ in range(4):  # siphonophore chains
        x0, y0 = rng.uniform(0, WMM), rng.uniform(5, HMM - 5)
        for j in range(26):
            glow.ellipse(x0 + j * 2.2, y0 + math.sin(j * 0.5) * 2.5, 0.55, 0.55)
    bm = body.mask()
    s.put(bm, mix(hexc("#14243a"), hexc("#2a4060"), fbm(1.5, 443)), coat=0.7)
    s.height = 0.45 + bump_of(bm, 0.8) * 0.3
    gm = glow.mask()
    halo = smooth(0.02, 0.4, bump_of(gm, 1.5)) * (1 - gm)
    gcol = mix(hexc("#40e0ff"), hexc("#a0fff0"), fbm(5, 445))
    s.put(halo * 0.6, gcol * 0.4)
    s.put(gm, gcol, coat=0.9)
    s.glow = np.clip(gm + halo * 0.5, 0, 1)
    s.anim = np.clip(fbm(14, 447), 0, 1)
    plank = (rng.random((H, W)) > 0.996).astype(float)
    s.put(plank, hexc("#80ffe0"))
    s.glow = np.maximum(s.glow, plank)


def leviathans_tooth(s, rng):
    """A ghost shark the size of the blade glowing through dark water, its skin denticles over everything, a wave breaking along the spine."""
    x, y = grid()
    deep = mix(hexc("#0a1a3a"), hexc("#02060f"), smooth(0.0, 1.0, y / HMM))
    s.put(np.ones((H, W)), deep, coat=0.7, metal=0.3)
    cid, d1, d2, pts = voronoi(1.6, 451, jitter=0.6, sx=1.4)
    dent = smooth(0.0, 0.25, d2 - d1)
    s.col = s.col * (0.8 + 0.25 * dent[..., None])
    s.height = 0.45 + dent * 0.12
    # the wave along the spine
    crest = 7 + np.sin(x / 26 * 2 * math.pi) * 3 + (fbm(10, 453) - 0.5) * 3
    wave = 1 - smooth(crest - 0.5, crest + 0.5, y)
    foam = (1 - smooth(0.0, 1.6, np.abs(y - crest))) * smooth(0.4, 0.7, fbm(1.2, 455) + 0.2)
    s.put(wave, mix(hexc("#1a5aa0"), hexc("#40c0ff"), smooth(0, 8, y)), coat=0.9)
    s.put(foam, hexc("#e0ffff"))
    # ghost sharks: a filled translucent body with a glowing rim, fins, gills, eye and mouth
    g = Shapes()
    fill = Shapes()
    up = [(0.0, -0.02), (0.1, -0.05), (0.25, -0.1), (0.45, -0.14), (0.62, -0.145), (0.78, -0.12), (0.9, -0.08), (0.97, -0.04), (1.0, 0.0)]
    lo = [(0.97, 0.035), (0.88, 0.065), (0.75, 0.09), (0.6, 0.1), (0.4, 0.085), (0.2, 0.05), (0.05, 0.02), (0.0, 0.015)]
    dorsal = [(0.47, -0.138), (0.5, -0.24), (0.53, -0.31), (0.56, -0.27), (0.6, -0.2), (0.64, -0.145)]
    dorsal2 = [(0.18, -0.07), (0.2, -0.11), (0.23, -0.085)]
    pect = [(0.62, 0.095), (0.6, 0.16), (0.55, 0.24), (0.6, 0.2), (0.7, 0.09)]
    tail = [(0.02, -0.015), (-0.06, -0.12), (-0.15, -0.27), (-0.1, -0.12), (-0.05, 0.0), (-0.1, 0.1), (-0.12, 0.16), (-0.03, 0.06), (0.02, 0.02)]
    for k in range(int(WMM / 120) + 1):
        ox, oy, L = 25 + k * 120, HMM * 0.63, 82.0
        T = lambda pts: [(ox + px_ * L, oy + py_ * L) for px_, py_ in pts]
        for part in (up + lo, dorsal, dorsal2, pect, tail):
            fill.poly(T(part))
        g.line(T(up + lo + [up[0]]), 0.5)
        for part in (dorsal, dorsal2, pect, tail):
            g.line(T(part), 0.45)
        for j in range(5):
            gx = 0.8 - j * 0.018
            g.line(T([(gx, -0.04), (gx - 0.008, 0.045)]), 0.3)
        g.ellipse(ox + 0.91 * L, oy - 0.03 * L, 1.2, 1.2)
        g.line(T([(0.86, 0.055), (0.92, 0.045), (0.97, 0.03)]), 0.35)
        g.line(T([(0.3, 0.0), (0.5, 0.02), (0.75, 0.01)]), 0.2)  # lateral line
    fmask = fill.mask()
    s.put(fmask * 0.45, hexc("#2a7ac0"), coat=0.9)
    s.glow = fmask * 0.25
    gm = g.mask()
    halo = smooth(0.02, 0.5, bump_of(gm, 2.0)) * (1 - gm)
    s.put(halo * 0.5, hexc("#3aa0ff"))
    s.put(gm, hexc("#a8f4ff"), coat=0.9)
    s.glow = np.clip(np.maximum(s.glow, gm * 1.0 + halo * 0.5), 0, 1)
    s.anim = (x / 60.0) % 1.0
    vio = smooth(0.62, 0.72, fbm(12, 457)) * (1 - wave) * 0.4
    s.put(vio, hexc("#5a20c0"))


def aurora(s, rng, palette=("#3aff9a", "#a050ff", "#40c0ff")):
    """A northern night: curtains of light rising over a mountain range, pines along the edge, stars, the lights mirrored in a still lake."""
    x, y = grid()
    sky = mix(hexc("#16204a"), hexc("#04060f"), smooth(0.0, 0.7, 1 - y / HMM))
    s.put(np.ones((H, W)), sky, coat=0.9)
    stars = (rng.random((H, W)) > 0.995).astype(float) * rng.random((H, W))
    s.put(stars, hexc("#ffffff"))
    # curtains: a wavy base line, vertical rays rising off it, fading upward
    c1, c2, c3 = (hexc(c) for c in palette)
    curt = np.zeros((H, W))
    colr = np.zeros((H, W, 3))
    for i, (base, amp, per, hgt) in enumerate([(24, 5, 70, 18), (20, 4, 45, 14), (27, 3, 33, 10)]):
        by = base + np.sin(x / per * 2 * math.pi + i * 2) * amp + (fbm(30, 501 + i) - 0.5) * 8
        rise = by - y
        rays = smooth(0.25, 0.9, fbm(1.2, 505 + i, sx=0.15, sy=6.0))
        c = smooth(-0.6, 0.4, rise) * np.exp(-np.clip(rise, 0, None) / hgt) * (0.35 + 0.65 * rays) * smooth(0.3, 0.6, fbm(25, 509 + i) + 0.1)
        cc = mix(c1, c2, smooth(0, hgt, rise))
        cc = mix(cc, c3, smooth(0.6, 0.9, fbm(20, 513 + i)) * 0.5)
        colr = colr + cc * c[..., None]
        curt = np.maximum(curt, c)
    s.col = s.col + colr * 0.9
    s.glow = np.clip(curt * 0.9, 0, 1)
    s.anim = (x / 40.0 + y / 80.0) % 1.0
    # mountains + lake + pines along the edge
    ridge = 31 + (fbm(14, 517) - 0.5) * 12 + (fbm(3, 519) - 0.5) * 2.5
    mount = smooth(ridge - 0.2, ridge + 0.2, y)
    lake_y = 37.5
    snow = mount * (1 - smooth(ridge + 0.5, ridge + 2.5, y)) * smooth(0.45, 0.6, fbm(2, 521))
    s.put(mount, mix(hexc("#0a0f22"), hexc("#141c38"), fbm(4, 523)), coat=0.9)
    s.put(snow * 0.8, hexc("#8a9ac8"))
    lake = smooth(lake_y - 0.1, lake_y + 0.1, y)
    refl = warp_sample(s.col, (fbm(0.8, 525) - 0.5) * 6, -(y - lake_y) * 2 * PX)
    s.put(lake, refl * 0.55 + hexc("#04081a") * 0.45, coat=1.0)
    s.glow = s.glow * (1 - lake) + warp_sample(s.glow, 0, -(y - lake_y) * 2 * PX) * lake * 0.4
    pines = Shapes()
    xx = 0.0
    while xx < WMM:
        hgt = rng.uniform(3.5, 7.5)
        base = lake_y + 0.1
        pts_ = [(xx, base - hgt)]
        for j in range(5):
            t = (j + 1) / 5
            w = hgt * 0.32 * t
            pts_ = [(xx - w, base - hgt + t * hgt * 0.95)] + pts_ + [(xx + w, base - hgt + t * hgt * 0.95)]
        pines.poly(pts_)
        xx += rng.uniform(1.2, 4.5)
    pm = pines.mask()
    s.put(pm, hexc("#03050c"), coat=0.9)
    s.glow = s.glow * (1 - pm) * (1 - mount * (1 - lake))
    s.height = 0.5 + mount * 0.1


def magpie(s, rng):
    """A magpie's feathers: rows of black feathers with blue-green / violet sheen and white patches, and the bright things it hoards."""
    x, y = grid()
    s.put(np.ones((H, W)), hexc("#05070a"), coat=0.6)
    sheen = np.zeros((H, W))
    fea = np.zeros((H, W))
    rows = []
    for ry in np.arange(-2, HMM + 6, 4.2):
        for rx in np.arange(-4 + (ry % 8.4 > 4) * 3.0, WMM + 6, 6.0):
            rows.append((rx + rng.uniform(-0.6, 0.6), ry + rng.uniform(-0.4, 0.4)))
    order = sorted(rows, key=lambda p: p[1])
    wpatch = fbm(30, 531)
    shaft = Shapes()
    for i, (fx, fy) in enumerate(order):
        f = Shapes()
        f.poly(leaf_pts(fx + 4.4, fy, 11.0, 5.4, 0.18 + rng.uniform(-0.08, 0.08)))
        m = f.mask()
        if m.max() == 0:
            continue
        white = 1.0 if (wpatch[min(max(int(fy * PX), 0), H - 1), min(max(int(fx * PX), 0), W - 1)] > 0.64) else 0.0
        tone = rng.uniform(0, 1)
        if white:
            c = mix(hexc("#d8dce0"), hexc("#ffffff"), tone)
        else:
            c = mix(hexc("#0a1a2a"), hexc("#16303a"), tone)
        lx, ly = x - fx, y - fy
        along = np.clip(lx / 8.5, 0, 1)
        barbs = 0.5 + 0.5 * np.sin((ly * 3.0 - lx * 1.4) * 6.0)
        iri = mix(hexc("#1a7a8a"), hexc("#6a2aa8"), np.clip(along + (ly / 5.0), 0, 1))
        s.put(m, c)
        if not white:
            s.col = s.col + (iri * (0.25 + along * 0.75)[..., None] * m[..., None] * (0.5 + 0.5 * barbs[..., None])) * 1.3
        s.height = s.height * (1 - m) + m * (0.45 + 0.25 * along + 0.04 * barbs)
        shade = (1 - smooth(0.0, 1.2, inside_mm(m))) * m
        s.col = s.col * (1 - shade[..., None] * 0.5)
        shaft.line([(fx, fy), (fx + 7.5, fy + 1.5)], 0.18)
    s.put(shaft.mask() * 0.6, hexc("#3a4a50"))
    # hoard: gold rings, coins, a little key
    h = Shapes()
    gl = Shapes()
    for _ in range(18):
        cx, cy, r = rng.uniform(0, WMM), rng.uniform(4, HMM - 4), rng.uniform(1.4, 2.4)
        if rng.random() < 0.5:
            h.ellipse(cx, cy, r, r)
            h.ellipse(cx, cy, r * 0.65, r * 0.65, fill=0)
        else:
            h.ellipse(cx, cy, r, r)
            gl.ellipse(cx - r * 0.3, cy - r * 0.3, r * 0.3, r * 0.2)
    hm = h.mask()
    s.put(hm, mix(hexc("#b8892a"), hexc("#ffe080"), fbm(0.6, 533)), coat=0.0, metal=1.0)
    s.height += bump_of(hm, 0.3) * 0.4
    s.put(gl.mask(), hexc("#fff8e0"))


def worldroot(s, rng):
    """Carved heartwood: growth rings and grain, a tree of life at the guard, roots spreading along the blade filled with living gold, new leaves."""
    x, y = grid()
    grain = fbm(8, 541, sx=6, sy=0.4)
    rings = 0.5 + 0.5 * np.sin((y + (fbm(20, 543) - 0.5) * 12 + np.sin(x / 15) * 2) * 2.2)
    wood = mix(hexc("#3a2414"), hexc("#7a5030"), grain * 0.6 + rings * 0.4)
    s.put(np.ones((H, W)), wood, coat=0.55)
    s.height = 0.5 + 0.08 * rings + 0.05 * grain
    roots = Shapes()
    leaves = Shapes()
    def root(x0, y0, ang, length, width, depth):
        pts_ = [(x0, y0)]
        a = ang
        px_, py_ = x0, y0
        steps = int(length / 1.2)
        for j in range(steps):
            a += rng.uniform(-0.25, 0.25) + (0.0 - (py_ - HMM / 2) / HMM) * 0.04
            px_ += math.cos(a) * 1.2
            py_ += math.sin(a) * 1.2
            pts_.append((px_, py_))
            if depth > 0 and rng.random() < 0.08:
                root(px_, py_, a + rng.choice([-1, 1]) * rng.uniform(0.5, 1.0), length * 0.5, width * 0.6, depth - 1)
        roots.line(pts_, width)
        if width < 0.7:
            lx, ly = pts_[-1]
            leaves.poly(leaf_pts(lx + 1.4, ly - 0.8, 3.0, 1.4, a - 0.6))
            leaves.poly(leaf_pts(lx + 1.4, ly + 0.8, 3.0, 1.4, a + 0.6))
    for k in range(int(WMM / 140) + 1):
        tx, ty = 18 + k * 140, HMM / 2
        roots.ellipse(tx, ty, 2.2, 2.2)
        for a in np.linspace(-1.0, 1.0, 5):
            root(tx, ty, a * 0.7, rng.uniform(60, 110), 1.3, 3)
        for a in np.linspace(math.pi - 0.8, math.pi + 0.8, 3):
            root(tx, ty, a, rng.uniform(10, 18), 0.9, 1)
    rm = roots.mask()
    lm = leaves.mask()
    gold = mix(hexc("#c08a1a"), hexc("#ffe27a"), np.clip(inside_mm(rm) / 0.6, 0, 1))
    groove = smooth(0.0, 0.6, bump_of(rm, 0.6)) * (1 - rm)
    s.put(groove * 0.5, hexc("#1a0e06"))
    s.put(rm, gold, coat=0.2, metal=1.0)
    s.height -= rm * 0.25
    s.glow = rm * 0.35 * smooth(0.3, 0.7, fbm(12, 545) + 0.2)
    s.anim = (np.hypot(x - 18, y - HMM / 2) / 40.0) % 1.0
    s.put(lm, mix(hexc("#3a8a2a"), hexc("#9ae05a"), fbm(0.8, 547)), coat=0.6, metal=0.0)
    s.height += bump_of(lm, 0.3) * 0.3


def sky_ribbon(s, rng):
    """A storm: billowing clouds lit from inside, branching lightning, rain streaks and one bright ribbon of sky through it."""
    x, y = grid()
    c = fbm(14, 551) * 0.6 + fbm(4, 553) * 0.4
    billow = smooth(0.35, 0.7, c)
    lit = smooth(0.55, 0.8, warp_sample(c, -6, -10))
    cloud = mix(hexc("#0a0a1e"), hexc("#3a3a5a"), billow)
    cloud = mix(cloud, hexc("#9aa8d8"), (lit - billow * 0.5).clip(0, 1) * 0.8)
    s.put(np.ones((H, W)), cloud, coat=0.8)
    band = smooth(0.62, 0.8, fbm(22, 555)) * smooth(0.5, 0.8, lit + 0.3)  # a break in the clouds where the sky shows through
    s.put(band * 0.7, mix(hexc("#60c0ff"), hexc("#fff4c0"), fbm(10, 557)))
    rain = smooth(0.8, 0.95, fbm(0.4, 559, sx=0.2, sy=8.0, octaves=2)) * 0.25
    s.put(rain, hexc("#a8b8e0"))
    bolt = Shapes()
    for _ in range(9):
        px_, py_ = rng.uniform(0, WMM), -1.0
        pts_ = [(px_, py_)]
        while py_ < HMM + 2:
            px_ += rng.uniform(-2.2, 2.2)
            py_ += rng.uniform(1.0, 2.6)
            pts_.append((px_, py_))
            if rng.random() < 0.18:
                bx, by = px_, py_
                bp = [(bx, by)]
                for _b in range(rng.integers(3, 8)):
                    bx += rng.uniform(-2.0, 2.0) + rng.choice([-1, 1]) * 0.8
                    by += rng.uniform(0.8, 2.0)
                    bp.append((bx, by))
                bolt.line(bp, 0.25)
        bolt.line(pts_, 0.6)
    bm = bolt.mask()
    halo = smooth(0.02, 0.5, bump_of(bm, 1.5)) * (1 - bm)
    s.put(halo * 0.5, hexc("#c060ff"))
    s.put(bm, hexc("#f8f4ff"))
    s.glow = np.clip(bm + halo * 0.6 + band * 0.5, 0, 1)
    s.anim = np.clip(fbm(25, 561), 0, 1)
    s.height = 0.5 + billow * 0.12


def heart_of_the_wild(s, rng):
    """Night in the wild wood: a howling spirit wolf under the moon in glowing outline, vines and night flowers, fireflies."""
    aurora(s, rng, palette=("#5aff8a", "#ff70c0", "#ffe060"))
    x, y = grid()
    v = Shapes()
    fl = Shapes()
    ctr = Shapes()
    for k in range(8):
        x0 = rng.uniform(0, WMM)
        pts_ = [(x0 + t * 70 + math.sin(t * 9) * 5, HMM - 2 + math.sin(t * 5 + k) * 3 - t * 6) for t in np.linspace(0, 1, 80)]
        v.line(pts_, 0.35)
        for j in range(6, 80, 9):
            px_, py_ = pts_[j]
            if rng.random() < 0.5:
                r = rng.uniform(1.2, 2.0)
                ph = rng.uniform(0, 1)
                fp = []
                for i in range(50):
                    a = i / 50 * 2 * math.pi
                    fp.append((px_ + math.cos(a) * r * (0.5 + 0.5 * abs(math.cos(a * 2.5 + ph))), py_ - 1.5 + math.sin(a) * r * (0.5 + 0.5 * abs(math.cos(a * 2.5 + ph)))))
                fl.poly(fp)
                ctr.ellipse(px_, py_ - 1.5, r * 0.25, r * 0.25)
            else:
                v.poly(leaf_pts(px_ + 1.2, py_ - 1.0, 3.0, 1.2, -0.8))
    wolf = Shapes()
    wolf_fill = Shapes()
    moon = Shapes()
    for k in range(int(WMM / 130) + 1):
        ox, oy, sc = 40 + k * 130, 3.2, 0.92
        P = lambda pts: [(ox + px_ * sc, oy + py_ * sc) for px_, py_ in pts]
        head = [(0, 40), (1.5, 33), (3, 27), (4.2, 21), (5.6, 16), (6.8, 12.2), (7.4, 8.2), (8.6, 1.2), (10.6, 6.4), (11.8, 5.8),
                (13.6, -0.4), (15.0, 6.2), (17.2, 7.0), (20.6, 4.6), (24.6, 1.4), (27.8, -0.6), (29.4, -0.2), (28.8, 1.4), (24.8, 4.2),
                (22.6, 6.6), (26.8, 5.8), (27.6, 7.0), (23.4, 9.8), (20.6, 12.6), (19.4, 16), (18.6, 21), (17.6, 27), (17.8, 33), (18.6, 40)]
        wolf.line(P(head + [head[0]]), 0.45)
        wolf.ellipse(ox + 16.4 * sc, oy + 8.4 * sc, 0.55, 0.55)
        for j in range(6):  # fur tufts down the neck
            yy0 = 15 + j * 4.0
            wolf.line(P([(17.8 - j * 0.1, yy0), (14.6 - j * 0.2, yy0 + 1.8)]), 0.2)
            wolf.line(P([(4.6 + j * 0.0, yy0 + 1), (7.4, yy0 + 2.4)]), 0.2)
        moon.ellipse(ox + 42, oy + 5, 5.5, 5.5)
        wolf_fill.poly(P(head))
    wm = wolf.mask()
    mm_ = moon.mask()
    s.put(mm_, mix(hexc("#e8eedc"), hexc("#fffff0"), fbm(1.2, 571)), coat=0.9)
    s.glow = np.maximum(s.glow, mm_ * 0.6)
    vm = v.mask()
    s.put(vm, hexc("#1a5a2a"), coat=0.7)
    flm = fl.mask()
    s.put(flm, mix(hexc("#ff70c0"), hexc("#ffb0e0"), fbm(1, 573)), coat=0.8)
    s.put(ctr.mask(), hexc("#ffe060"))
    s.glow = np.maximum(s.glow, flm * 0.6)
    wf = wolf_fill.mask()
    s.put(wf * 0.55, hexc("#1a6a5a"), coat=0.9)
    halo = smooth(0.02, 0.5, bump_of(wm, 1.6)) * (1 - wm)
    s.put(halo * 0.5, hexc("#60ffb0"))
    s.glow = np.maximum(s.glow * (1 - wf * 0.7), wf * 0.3)
    s.put(wm, hexc("#d0fff0"))
    s.glow = np.maximum(s.glow, wm + halo * 0.5)
    ff = (rng.random((H, W)) > 0.99975).astype(float)
    ff = np.asarray(Image.fromarray((ff * 255).astype(np.uint8)).filter(ImageFilter.MaxFilter(3)), dtype=float) / 255
    s.put(ff, hexc("#e8ff80"))
    s.glow = np.maximum(s.glow, ff)
    s.anim = rng.random((H, W)) * 0.3 + s.anim * 0.7


def ticket_stub(s, rng):
    """A strip of carnival tickets: cream card, printed borders, ADMIT ONE, serial numbers, perforations between them, a red stamp."""
    x, y = grid()
    paper = mix(hexc("#e8dcc0"), hexc("#f6eedc"), fbm(0.6, 601, octaves=2) * 0.5 + fbm(10, 603) * 0.5)
    fibres = smooth(0.85, 0.95, fbm(0.4, 605, sx=4, sy=0.3, octaves=2)) * 0.08
    s.put(np.ones((H, W)), paper * (1 - fibres)[..., None], coat=0.05)
    s.height = 0.5 + 0.04 * fbm(0.5, 607)
    ink = Shapes()
    red = Shapes()
    holes = Shapes()
    tw = 62.0
    k = 0
    xx = 0.0
    while xx < WMM:
        x0 = xx
        ink.line([(x0 + 3, 3), (x0 + tw - 3, 3), (x0 + tw - 3, HMM - 3), (x0 + 3, HMM - 3), (x0 + 3, 3)], 0.35)
        ink.line([(x0 + 4.2, 4.2), (x0 + tw - 4.2, 4.2), (x0 + tw - 4.2, HMM - 4.2), (x0 + 4.2, HMM - 4.2), (x0 + 4.2, 4.2)], 0.18)
        for j in range(int((tw - 10) / 2.2)):
            ink.ellipse(x0 + 6 + j * 2.2, 6.4, 0.35, 0.35)
            ink.ellipse(x0 + 6 + j * 2.2, HMM - 6.4, 0.35, 0.35)
        ink.text(x0 + tw / 2, HMM * 0.42, "ADMIT ONE", 8.0, font="LilitaOne.ttf")
        ink.text(x0 + tw / 2, HMM * 0.68, "No. %06d" % (241000 + k * 7 + rng.integers(0, 6)), 3.4, font="Cinzel.ttf")
        for sx_ in (x0 + 9, x0 + tw - 9):
            pts_ = []
            for i in range(10):
                a = i / 10 * 2 * math.pi - math.pi / 2
                rr = 2.6 if i % 2 == 0 else 1.1
                pts_.append((sx_ + math.cos(a) * rr, HMM * 0.42 + math.sin(a) * rr))
            ink.poly(pts_)
        if rng.random() < 0.55:  # a red stamp, at a slant
            cx, cy = x0 + rng.uniform(15, tw - 15), rng.uniform(14, HMM - 14)
            red.ellipse(cx, cy, 7, 7)
            red.ellipse(cx, cy, 6.2, 6.2, fill=0)
            red.text(cx, cy, rng.choice(["LUCKY", "PRIZE", "VIP"]), 3.2, font="LilitaOne.ttf")
        for j in range(int(HMM / 1.6)):
            holes.ellipse(x0 + tw, 0.8 + j * 1.6, 0.42, 0.42)
        xx += tw
        k += 1
    im = ink.mask()
    inkc = mix(hexc("#2a1a5a"), hexc("#7a1a2a"), smooth(0.4, 0.6, fbm(40, 609)))
    s.put(im * (0.85 + 0.15 * fbm(0.3, 611)), inkc, coat=0.15)
    rm = red.mask() * smooth(0.25, 0.55, fbm(0.7, 613) + 0.15)
    s.put(rm * 0.85, hexc("#c81e2a"))
    hm = holes.mask()
    s.put(hm, hexc("#5a4a30"))
    s.height -= hm * 0.4 + im * 0.05


def confetti(s, rng):
    """Black lacquer buried in confetti: paper squares, dots, curling streamers and gold foil, each with its own little shadow and gloss."""
    x, y = grid()
    s.put(np.ones((H, W)), hexc("#07070b"), coat=1.0)
    cols = [hexc(c) for c in ["#ff4ab0", "#40e0ff", "#ffe040", "#7aff5a", "#ff7a2a", "#a070ff", "#ffffff"]]
    layer_masks = []
    for layer in range(3):
        shp = [Shapes() for _ in cols]
        foil = Shapes()
        n = 380
        for _ in range(n):
            cx, cy = rng.uniform(-2, WMM + 2), rng.uniform(-2, HMM + 2)
            ci = rng.integers(0, len(cols))
            kind = rng.random()
            if kind < 0.5:
                a = rng.uniform(0, math.pi)
                w_, h_ = rng.uniform(1.2, 2.4), rng.uniform(0.7, 1.4)
                pts_ = [(cx + math.cos(a) * w_ - math.sin(a) * h_, cy + math.sin(a) * w_ + math.cos(a) * h_),
                        (cx - math.cos(a) * w_ - math.sin(a) * h_, cy - math.sin(a) * w_ + math.cos(a) * h_),
                        (cx - math.cos(a) * w_ + math.sin(a) * h_, cy - math.sin(a) * w_ - math.cos(a) * h_),
                        (cx + math.cos(a) * w_ + math.sin(a) * h_, cy + math.sin(a) * w_ - math.cos(a) * h_)]
                (foil if rng.random() < 0.12 else shp[ci]).poly(pts_)
            elif kind < 0.78:
                r = rng.uniform(0.6, 1.2)
                shp[ci].ellipse(cx, cy, r, r)
            elif kind < 0.95:
                L = rng.uniform(8, 18)
                a0 = rng.uniform(0, 6.28)
                pts_ = [(cx + t * L * math.cos(a0) + math.sin(t * 9) * 1.4, cy + t * L * math.sin(a0) + math.cos(t * 9) * 1.4) for t in np.linspace(0, 1, 50)]
                shp[ci].line(pts_, 0.6)
        masks = [sh.mask() for sh in shp]
        fm = foil.mask()
        allm = np.clip(sum(masks) + fm, 0, 1)
        shadow = np.clip(warp_sample(bump_of(allm, 0.35), -0.4 * PX, -0.5 * PX) - allm, 0, 1)
        s.col = s.col * (1 - shadow[..., None] * 0.7)
        for m, c in zip(masks, cols):
            s.put(m, c * (0.85 + 0.25 * fbm(0.5, 615 + layer)[..., None]), coat=0.9, metal=0.0)
        s.put(fm, mix(hexc("#b8892a"), hexc("#fff0a0"), fbm(0.3, 621 + layer)), coat=0.0, metal=1.0)
        s.height = s.height * (1 - allm) + allm * (0.55 + layer * 0.1)


def neon_nights(s, rng):
    """A club wall at night: dark brick and mortar, neon tubes bent into palms, cocktail glasses, stars, moons and OPEN signs, flickering."""
    x, y = grid()
    row = np.floor(y / 4.2)
    off = (row % 2) * 4.5
    bx = (x + off) % 9.0
    by = y % 4.2
    mortar = np.maximum(1 - smooth(0.0, 0.35, bx), 1 - smooth(0.0, 0.35, by))
    brick_id = np.floor((x + off) / 9.0) + row * 137
    tone = np.random.default_rng(631).random(int(brick_id.max()) + 2)[brick_id.astype(int)]
    brick = mix(hexc("#1a0c14"), hexc("#3a1a24"), tone * 0.6 + fbm(0.6, 633) * 0.4)
    s.put(np.ones((H, W)), mix(brick, hexc("#0a0608"), mortar), coat=0.2)
    s.height = 0.5 + (1 - mortar) * 0.15 + fbm(0.4, 635) * 0.05
    tube = Shapes()
    tube2 = Shapes()
    signs = ["palm", "glass", "star", "open", "moon", "glass", "palm", "star", "club"]
    xx = 14.0
    k = 0
    while xx < WMM - 10:
        kind = signs[k % len(signs)]
        cy = HMM / 2
        T = tube if k % 2 == 0 else tube2
        if kind == "palm":
            trunk = [(xx + math.sin(t * 2) * 2, cy + 14 - t * 24) for t in np.linspace(0, 1, 30)]
            T.line(trunk, 0.55)
            tx, ty = trunk[-1]
            for a in (-2.6, -2.0, -1.2, -0.5, 0.2, 0.9):
                fr = [(tx + math.cos(a) * t * 10, ty + math.sin(a) * t * 10 + t * t * 5) for t in np.linspace(0, 1, 20)]
                T.line(fr, 0.5)
            xx += 26
        elif kind == "glass":
            T.line([(xx - 6, cy - 9), (xx + 6, cy - 9), (xx, cy - 1), (xx - 6, cy - 9)], 0.55)
            T.line([(xx, cy - 1), (xx, cy + 8), (xx - 4, cy + 10), (xx + 4, cy + 10)], 0.55)
            T.ellipse(xx + 4.5, cy - 11, 1.6, 1.6)
            T.ellipse(xx + 4.5, cy - 11, 1.0, 1.0, fill=0)
            T.line([(xx + 2, cy - 7), (xx + 7, cy - 14)], 0.4)
            xx += 22
        elif kind == "star":
            pts_ = []
            for i in range(11):
                a = i / 10 * 2 * math.pi - math.pi / 2
                rr = 9 if i % 2 == 0 else 3.8
                pts_.append((xx + math.cos(a) * rr, cy + math.sin(a) * rr))
            T.line(pts_, 0.55)
            xx += 24
        elif kind == "moon":
            arc1 = [(xx + math.cos(a) * 9, cy + math.sin(a) * 9) for a in np.linspace(0.6, 2 * math.pi - 0.6, 40)]
            arc2 = [(xx + 3.5 + math.cos(a) * 7, cy + math.sin(a) * 7) for a in np.linspace(2 * math.pi - 0.9, 0.9, 40)]
            T.line(arc1 + arc2 + [arc1[0]], 0.55)
            xx += 24
        else:
            word = "OPEN" if kind == "open" else "CLUB"
            T.text(xx + 13, cy, word, 11, font="Chewy-Regular.ttf")
            xx += 36
        k += 1
    for T, c, ph in ((tube, hexc("#ff2aa0"), 0.0), (tube2, hexc("#2af0ff"), 0.5)):
        m = T.mask()
        if T is not tube and False:
            pass
        core = np.clip(inside_mm(m) / 0.25, 0, 1)
        halo = smooth(0.01, 0.5, bump_of(m, 2.2)) * (1 - m)
        s.put(halo * 0.75, c * 0.7)
        s.put(m, mix(c, np.array([1.0, 1.0, 1.0]), core * 0.7), coat=1.0)
        s.glow = np.maximum(s.glow, np.clip(m + halo * 0.6, 0, 1))
        s.anim = np.where(m + halo > 0.05, ph + 0.1 * fbm(30, 637), s.anim)
        s.height += m * 0.3


def christmas_bells(s, rng):
    """Red velvet with a green garland swagged along the spine, gold bells hung from its bows, holly, falling snowflakes."""
    x, y = grid()
    velvet = mix(hexc("#5a0612"), hexc("#a8122a"), fbm(3, 641) * 0.5 + fbm(0.3, 643, octaves=2) * 0.5)
    s.put(np.ones((H, W)), velvet, coat=0.15)
    s.height = 0.5 + 0.06 * fbm(0.3, 645, octaves=2)
    per = 32.0
    swag = Shapes()
    gold = Shapes()
    gold_hi = Shapes()
    holly = Shapes()
    berries = Shapes()
    flakes = Shapes()
    for k in range(int(WMM / per) + 2):
        x0 = k * per
        pts_ = [(x0 + t * per, 4 + math.sin(t * math.pi) * 9) for t in np.linspace(0, 1, 40)]
        swag.line(pts_, 3.2)
        for j in range(0, 40, 2):  # needles
            px_, py_ = pts_[j]
            for a in (-0.8, 0.8, 2.3, -2.3):
                swag.line([(px_, py_), (px_ + math.cos(a) * 2.2, py_ + math.sin(a) * 2.2)], 0.25)
        bx = x0
        holly.poly(leaf_pts(bx - 3.2, 3.2, 6.5, 3.0, 2.6, spikes=4, spike_depth=0.5))
        holly.poly(leaf_pts(bx + 3.2, 3.2, 6.5, 3.0, 0.5, spikes=4, spike_depth=0.5))
        for dx, dy in ((-0.9, 3.4), (0.9, 3.4), (0.0, 2.2)):
            berries.ellipse(bx + dx, dy, 0.9, 0.9)
        # a bell hanging under the bow on a ribbon, and one at the bottom of the swag
        for (cx, top) in ((bx, 6.0), (x0 + per / 2, 13.5)):
            gold.line([(cx, top - 2), (cx, top + 2)], 0.35)
            by_ = top + 2
            r = 3.2
            bell = [(cx - r * 0.4, by_)]
            for t in np.linspace(0, 1, 20):
                bell.append((cx - r * (0.45 + 0.55 * t ** 1.6), by_ + t * r * 1.5))
            bell += [(cx + r * (0.45 + 0.55 * t ** 1.6), by_ + t * r * 1.5) for t in np.linspace(1, 0, 20)]
            gold.poly(bell)
            gold.line([(cx - r * 1.05, by_ + r * 1.5), (cx + r * 1.05, by_ + r * 1.5)], 0.55)
            gold.ellipse(cx, by_ + r * 1.75, 0.7, 0.7)
            gold_hi.poly([(cx - r * 0.25, by_ + 0.5), (cx - r * 0.15, by_ + 0.5), (cx - r * 0.6, by_ + r * 1.3), (cx - r * 0.8, by_ + r * 1.3)])
    for _ in range(140):
        cx, cy, r = rng.uniform(0, WMM), rng.uniform(16, HMM), rng.uniform(0.6, 1.6)
        for a in range(6):
            ang = a / 6 * math.pi + rng.uniform(0, 0.2)
            flakes.line([(cx - math.cos(ang) * r, cy - math.sin(ang) * r), (cx + math.cos(ang) * r, cy + math.sin(ang) * r)], 0.14)
    sm = swag.mask()
    s.put(sm, mix(hexc("#0a3a1a"), hexc("#2a7a3a"), fbm(0.5, 647)), coat=0.4)
    s.height += bump_of(sm, 0.6) * 0.3
    s.put(flakes.mask() * 0.85, hexc("#ffffff"))
    hm = holly.mask()
    s.put(hm, hexc("#14602a"), coat=0.9)
    bm = berries.mask()
    s.put(bm, hexc("#ff1a2a"), coat=1.0)
    s.height += bump_of(bm, 0.3) * 0.4
    gm = gold.mask()
    s.put(gm, mix(hexc("#b8892a"), hexc("#ffd86a"), fbm(0.6, 649)), coat=0.0, metal=1.0)
    s.height += bump_of(gm, 0.6) * 0.45
    s.put(gold_hi.mask() * gm, hexc("#fff4c0"))
    s.glow = gm * 0.35
    s.anim = (x / 16.0) % 1.0


def house_always_wins(s, rng):
    """The house's table: green baize, a fanned royal flush, stacks of chips, dice, all inside a gold filigree frame."""
    x, y = grid()
    felt = mix(hexc("#0a4a2a"), hexc("#14683a"), fbm(10, 651) * 0.6 + fbm(0.25, 653, octaves=2) * 0.4)
    s.put(np.ones((H, W)), felt, coat=0.0)
    s.height = 0.5 + 0.05 * fbm(0.25, 655, octaves=2)
    frame = Shapes()
    for yb in (2.2, HMM - 2.2):
        frame.line([(0, yb), (WMM, yb)], 0.6)
        for xx in np.arange(0, WMM, 6):
            frame.ellipse(xx, yb, 1.0, 0.6)
    fm = frame.mask()
    s.put(fm, hexc("#e0b84a"), metal=1.0)
    cards = [("A", "#c8102a"), ("K", "#c8102a"), ("Q", "#c8102a"), ("J", "#c8102a"), ("10", "#c8102a")]
    xx = 20.0
    k = 0
    while xx < WMM - 20:
        if k % 2 == 0:
            for j, (rank, c) in enumerate(cards):
                card = Shapes()
                ink = Shapes()
                suit = Shapes()
                ang = -0.5 + j * 0.25
                cx, cy = xx + j * 4.5, HMM * 0.55
                cw, ch = 9.5, 14.0
                corners = [(-cw / 2, -ch / 2), (cw / 2, -ch / 2), (cw / 2, ch / 2), (-cw / 2, ch / 2)]
                card.poly(rot([(cx + a, cy + b) for a, b in corners], ang, cx, cy))
                lx, ly = rot([(cx - cw / 2 + 1.6, cy - ch / 2 + 2.0)], ang, cx, cy)[0]
                ink.text(lx, ly, rank, 2.6, font="Cinzel.ttf")
                hx, hy = rot([(cx, cy + 0.8)], ang, cx, cy)[0]
                heart_pts = [(hx + 2.6 * (16 * math.sin(t) ** 3) / 16, hy - 2.6 * (13 * math.cos(t) - 5 * math.cos(2 * t) - 2 * math.cos(3 * t) - math.cos(4 * t)) / 16) for t in np.linspace(0, 2 * math.pi, 60)]
                suit.poly(heart_pts)
                cm = card.mask()
                sh = np.clip(warp_sample(bump_of(cm, 0.5), -0.6 * PX, -0.7 * PX) - cm, 0, 1)
                s.col = s.col * (1 - sh[..., None] * 0.6)
                s.put(cm, hexc("#f8f4ec"), coat=0.6, metal=0.0)
                edge = (1 - smooth(0.0, 0.25, inside_mm(cm))) * cm
                s.put(edge * 0.5, hexc("#b8b0a0"))
                s.put(ink.mask() * cm, hexc(c))
                s.put(suit.mask() * cm, hexc(c))
                s.height = s.height * (1 - cm) + cm * (0.62 + j * 0.02)
            xx += 52
        else:
            for j in range(3):  # chip stacks
                cx, cy = xx + j * 9, HMM * 0.6
                ccol = hexc(["#c8102a", "#1a3ab8", "#101010"][j])
                for lvl in range(rng.integers(3, 7)):
                    chip = Shapes()
                    spot = Shapes()
                    ccy = cy - lvl * 1.1
                    chip.ellipse(cx, ccy, 4.0, 2.4)
                    for a in range(8):
                        aa = a / 8 * 2 * math.pi
                        spot.ellipse(cx + math.cos(aa) * 3.2, ccy + math.sin(aa) * 1.9, 0.55, 0.35)
                    m = chip.mask()
                    s.put(m, ccol * 0.8, coat=0.7, metal=0.0)
                    s.put(spot.mask() * m, hexc("#f4f0e8"))
                    s.height = s.height * (1 - m) + m * (0.6 + lvl * 0.04)
            for j in range(2):  # dice
                d = Shapes()
                pip = Shapes()
                cx, cy, r = xx + 32 + j * 8, HMM * 0.45 + j * 6, 3.0
                ang = rng.uniform(-0.4, 0.4)
                d.poly(rot([(cx - r, cy - r), (cx + r, cy - r), (cx + r, cy + r), (cx - r, cy + r)], ang, cx, cy))
                n = rng.integers(1, 7)
                spots = {1: [(0, 0)], 2: [(-1, -1), (1, 1)], 3: [(-1, -1), (0, 0), (1, 1)], 4: [(-1, -1), (1, -1), (-1, 1), (1, 1)],
                         5: [(-1, -1), (1, -1), (0, 0), (-1, 1), (1, 1)], 6: [(-1, -1), (1, -1), (-1, 0), (1, 0), (-1, 1), (1, 1)]}[n]
                for a, b in spots:
                    px_, py_ = rot([(cx + a * 1.6, cy + b * 1.6)], ang, cx, cy)[0]
                    pip.ellipse(px_, py_, 0.5, 0.5)
                m = d.mask()
                s.put(m, hexc("#f4f0ec"), coat=0.9)
                s.put(pip.mask() * m, hexc("#1a1a1a"))
                s.height = s.height * (1 - m) + m * 0.7
            xx += 58
        k += 1


def jesters_grin(s, rng):
    """Harlequin diamonds in purple, gold and green with gold piping; grinning jester faces with belled caps; confetti."""
    x, y = grid()
    u_ = (x / 7.0 + y / 6.0)
    v_ = (x / 7.0 - y / 6.0)
    cell = (np.floor(u_) + np.floor(v_)) % 3
    cols = [hexc("#5a1a8a"), hexc("#d8a830"), hexc("#1a8a4a")]
    base = np.zeros((H, W, 3))
    for i, c in enumerate(cols):
        base = base + c * (cell == i)[..., None]
    pipe = np.maximum(1 - smooth(0.0, 0.06, np.abs(u_ - np.round(u_))), 1 - smooth(0.0, 0.06, np.abs(v_ - np.round(v_))))
    s.put(np.ones((H, W)), base * (0.85 + 0.2 * fbm(0.4, 661, octaves=2))[..., None], coat=0.8)
    s.put(pipe, hexc("#ffe080"), metal=1.0, coat=0.0)
    s.height = 0.5 + pipe * 0.2
    face = Shapes()
    feat = Shapes()
    cap = [Shapes(), Shapes()]
    bells = Shapes()
    for k in range(int(WMM / 70) + 1):
        cx, cy, r = 35 + k * 70, HMM * 0.6, 9.5
        face.ellipse(cx, cy, r * 0.9, r)
        # cap: two curled points with bells
        for side, ci in ((-1, 0), (1, 1)):
            pts_ = [(cx + side * r * 0.2, cy - r * 0.6), (cx + side * r * 0.9, cy - r * 0.7)]
            for t in np.linspace(0, 1, 14):
                pts_.append((cx + side * (r * 0.9 + t * 9), cy - r * 0.7 - math.sin(t * math.pi) * 9 + t * 6))
            for t in np.linspace(1, 0, 14):
                pts_.append((cx + side * (r * 0.9 + t * 9 - 1.6), cy - r * 0.7 - math.sin(t * math.pi) * 6.5 + t * 6 + 1.2))
            pts_.append((cx, cy - r * 0.95))
            cap[ci].poly(pts_)
            bells.ellipse(cx + side * (r * 0.9 + 9), cy - r * 0.7 + 6, 1.4, 1.4)
        # eyes, cheeks, the grin
        for side in (-1, 1):
            feat.poly([(cx + side * 3.4, cy - 3.6), (cx + side * 5.2, cy - 2.4), (cx + side * 3.4, cy - 1.4), (cx + side * 1.6, cy - 2.4)])
            feat.ellipse(cx + side * 5.6, cy + 2.0, 1.4, 1.0)
        grin = [(cx + math.cos(a) * 6.4, cy + 1.0 + math.sin(a) * 5.2) for a in np.linspace(0.15, math.pi - 0.15, 30)]
        grin += [(cx + math.cos(a) * 6.0, cy + 2.6 + math.sin(a) * 2.6) for a in np.linspace(math.pi - 0.15, 0.15, 30)]
        feat.poly(grin)
    fm = face.mask()
    s.put(fm, hexc("#f4ece4"), coat=0.9, metal=0.0)
    s.height += bump_of(fm, 1.0) * 0.4
    feat_m = feat.mask() * fm
    s.put(feat_m, hexc("#2a0a2a"))
    teeth = feat_m * smooth(0.0, 0.08, np.abs(np.sin(x * 1.4))) * 0.0
    for ci, c in ((0, hexc("#8a1aa8")), (1, hexc("#1aa860"))):
        m = cap[ci].mask()
        s.put(m, c, coat=0.9, metal=0.0)
        s.height += bump_of(m, 0.6) * 0.3
    bm = bells.mask()
    s.put(bm, hexc("#ffd860"), metal=1.0, coat=0.0)
    s.height += bump_of(bm, 0.3) * 0.4
    eyes = feat_m * smooth(-6.0, -1.0, -(y - (HMM * 0.6 - 2.4)) * 0) 
    s.glow = feat_m * 0.0
    eyeglow = Shapes()
    for k in range(int(WMM / 70) + 1):
        cx, cy = 35 + k * 70, HMM * 0.6
        for side in (-1, 1):
            eyeglow.ellipse(cx + side * 3.4, cy - 2.4, 0.7, 0.55)
    eg = eyeglow.mask()
    s.put(eg, hexc("#ff3a6a"))
    s.glow = np.maximum(s.glow, eg)
    s.anim = (x / 70.0) % 1.0
    conf = (rng.random((H, W)) > 0.997).astype(float)
    conf = np.asarray(Image.fromarray((conf * 255).astype(np.uint8)).filter(ImageFilter.MaxFilter(5)), dtype=float) / 255 * (1 - fm)
    s.put(conf, np.clip(np.stack([fbm(2, 663), fbm(2, 665), fbm(2, 667)], -1) * 1.6, 0, 1))


MELTS = {
    "prism_melt_phase_1": melt(["#1a0820", "#d01a8a", "#5a1aa8", "#ff70c0"]),
    "prism_melt_phase_2": melt(["#ff2a9a", "#a020f0", "#ff7ad0", "#ffd0f0"]),
    "prism_melt_phase_3": melt(["#0a3aa8", "#18c0d8", "#20e090", "#a0fff0"]),
    "prism_melt_phase_4": melt(["#2a40ff", "#a030ff", "#ff40b0", "#50d0ff"]),
    "prism_melt_bloodmoon": melt(["#3a0006", "#d0081a", "#ff2a2a", "#ff8a7a"]),
    "prism_melt_abyssal": melt(["#000a3a", "#0a3ad0", "#2a7aff", "#9ad0ff"]),
    "prism_melt_nightpearl": melt(["#05030a", "#2a1a4a", "#6a4a9a", "#9ad8c8"]),
    "venom_melt_phase_1": melt(["#0a2a0a", "#3ad02a", "#d0f020", "#1a6a1a"], venom=True),
    "venom_melt_phase_2": melt(["#003a2a", "#10d070", "#20f0c0", "#8aff8a"], venom=True),
    "venom_melt_phase_3": melt(["#002a3a", "#00a0a0", "#10c0ff", "#40ffd0"], venom=True),
    "venom_melt_phase_4": melt(["#0a3a10", "#00c040", "#1a60d0", "#a0ff40"], venom=True),
    "venom_melt_viper_s_eye": melt(["#002a0a", "#00c040", "#40ff70", "#c0ffd0"], venom=True),
}

FINISHES = {
    "quench": quench,
    "heat_fade": heat_fade,
    "slag": slag,
    "temper_line": temper_line,
    "anvil_king": anvil_king,
    "molten_core": molten_core,
    "sea_glass": sea_glass,
    "brine": brine,
    "kelp_wrap": kelp_wrap,
    "abyss_lantern": abyss_lantern,
    "leviathans_tooth": leviathans_tooth,
    "aurora": aurora,
    "magpie": magpie,
    "worldroot": worldroot,
    "sky_ribbon": sky_ribbon,
    "heart_of_the_wild": heart_of_the_wild,
    "ticket_stub": ticket_stub,
    "confetti": confetti,
    "neon_nights": neon_nights,
    "christmas_bells": christmas_bells,
    "house_always_wins": house_always_wins,
    "jesters_grin": jesters_grin,
    **MELTS,
    "candy_cane": candy_cane,
    "mossback": mossback,
    "quartermasters_hook": quartermasters_hook,
    "blast_furnace": blast_furnace,
}


# ================================================================== CHASE PATTERNS: their own sheets (window starts at the left end)
def _chase_tint(s, tint, keep=0.25):
    """Recolour a sheet toward one gem colour, keeping its light and dark (for gem versions of designed finishes)."""
    lum = s.col @ np.array([0.3, 0.55, 0.15])
    t = np.asarray(tint)
    s.col = s.col * keep + (lum[..., None] * t * 1.6) * (1 - keep)


def great_wave(s, rng, deep, mid, foam, engraved=False):
    """A huge curling wave across the left 180 mm (Rogue Wave)."""
    x, y = grid()
    sh = Shapes()
    fo = Shapes()
    # the wave: a long rising back, a crest that leans forward and curls over a hollow, a steep falling face
    back = [(0, HMM), (0, HMM - 6)] + [(t * 112, HMM - 6 - (t ** 1.8) * (HMM - 12)) for t in np.linspace(0, 1, 60)]
    lip = [(112 + math.sin(a) * 11, 17 - math.cos(a) * 11) for a in np.linspace(0, 2.6, 30)]  # over the top and down
    hollow = [(116 + 6 * math.cos(a), 22 + 6 * math.sin(a)) for a in np.linspace(-0.2, 2.2, 20)]
    face = [(110, 30), (112, HMM - 6), (130, HMM - 2), (140, HMM)]
    sh.poly(back + lip + hollow[::-1] + face)
    cx, cy, r = 114, 17, 10
    curl = [(cx + math.sin(a) * r * (1 - a / 9), cy - math.cos(a) * r * (1 - a / 9)) for a in np.linspace(0, 5.2, 70)]
    fo.line(curl, 1.4)
    for k in range(10):  # foam claws off the lip
        a0 = 0.3 + k * 0.24
        px_, py_ = cx + math.sin(a0) * r, cy - math.cos(a0) * r
        fo.line([(px_, py_), (px_ + math.sin(a0 + 0.9) * 3.5, py_ - math.cos(a0 + 0.9) * 3.5)], 0.8)
    for k in range(6):  # streaks along the back
        t0 = 0.15 + k * 0.13
        fo.line([(t * 112, HMM - 6 - (t ** 1.8) * (HMM - 12) + 3 + k * 0.6) for t in np.linspace(t0, min(t0 + 0.3, 0.98), 30)], 0.35)
    m = sh.mask() * (1 - smooth(165, 180, x))
    fm = fo.mask() * m
    if engraved:
        s.put(m * 0.85, deep, coat=1.0, metal=0.0)
        s.put(fm, foam, metal=1.0, coat=0.0)
        s.height -= m * 0.1
    else:
        s.put(m, mix(np.asarray(deep), np.asarray(mid), smooth(10, 40, HMM - y)), coat=0.9)
        s.put(fm, foam, coat=0.6)
        s.height += fm * 0.3
        s.glow = np.maximum(s.glow, fm * 0.35)


def heart_lava(s, rng):
    """A heart split open in the steel with molten metal in it (Heartfire), near the guard."""
    x, y = grid()
    h = Shapes()
    cx, cy, sc = 60, HMM * 0.5, 13
    pts_ = [(cx + sc * (16 * math.sin(t) ** 3) / 16, cy - sc * (13 * math.cos(t) - 5 * math.cos(2 * t) - 2 * math.cos(3 * t) - math.cos(4 * t)) / 16) for t in np.linspace(0, 2 * math.pi, 120)]
    h.poly(pts_)
    m = h.mask()
    rim = (1 - smooth(0.0, 1.0, inside_mm(m))) * m
    core = np.clip(inside_mm(m) / 6.0, 0, 1)
    lava = mix(hexc("#b81000"), hexc("#ff7a10"), smooth(0.0, 0.5, core))
    lava = mix(lava, hexc("#fff2b0"), smooth(0.6, 1.0, core))
    halo = smooth(0.02, 0.6, bump_of(m, 3.0)) * (1 - m)
    s.put(halo * 0.7, hexc("#ff4a10"))
    s.put(m, lava, coat=0.7, metal=0.0)
    crack = (1 - smooth(0.0, 0.05, np.abs(fbm(2.0, 701) - 0.5))) * m * (1 - core * 0.6)
    s.put(crack * 0.7, hexc("#3a0a04"))
    s.put(rim, hexc("#2a0804"))
    s.glow = np.maximum(s.glow, np.clip(m * (1 - crack) + halo * 0.6, 0, 1))
    s.height -= m * 0.3


def corona(s, rng, colors):
    """The aurora meets overhead: rays from every side converging on one bright point, the whole sky alight (Full Corona)."""
    x, y = grid()
    cx, cy = 90, 6
    ang = np.arctan2(y - cy, x - cx)
    dist = np.hypot(x - cx, (y - cy) * 1.5)
    rays = smooth(0.35, 0.95, fbm(1.0, 711, sx=1.0, sy=1.0) * 0.4 + 0.6 * (0.5 + 0.5 * np.sin(ang * 26 + fbm(8, 713) * 4)))
    fall = np.exp(-dist / 80.0) * smooth(0.0, 6.0, dist)
    c1, c2, c3 = (hexc(c) for c in colors)
    cc = mix(c1, c2, smooth(10, 70, dist))
    cc = mix(cc, c3, smooth(0.6, 0.9, fbm(15, 715)) * 0.5)
    a = rays * fall * (1 - smooth(150, 190, x))
    s.col = s.col * (1 - a[..., None] * 0.4) + cc * a[..., None] * 1.1
    s.glow = np.maximum(s.glow, np.clip(a * 1.1, 0, 1))
    core = np.exp(-(dist / 4.0) ** 2)
    s.put(core, hexc("#ffffff"))


def bloom(s, rng, palette, share=1.0):
    """Flowers everywhere (In Bloom): five-petal blossoms in clusters over the whole left of the sheet."""
    fl = Shapes()
    ctr = Shapes()
    for _ in range(int(380 * share)):
        cx, cy, r = rng.uniform(0, 185), rng.uniform(0, HMM), rng.uniform(1.0, 2.4)
        ph = rng.uniform(0, 1)
        pts_ = []
        for i in range(60):
            a = i / 60 * 2 * math.pi
            rr = r * (0.55 + 0.45 * abs(math.cos(a * 2.5 + ph)))
            pts_.append((cx + math.cos(a) * rr, cy + math.sin(a) * rr))
        fl.poly(pts_)
        ctr.ellipse(cx, cy, r * 0.25, r * 0.25)
    m = fl.mask()
    pal = [hexc(c) for c in palette]
    pick = np.floor(fbm(3, 721) * len(pal) * 1.999).astype(int) % len(pal)
    col = np.stack(pal)[pick]
    s.put(m, col * (0.85 + 0.25 * fbm(0.5, 723))[..., None], coat=0.6, metal=0.0)
    s.height += bump_of(m, 0.3) * 0.35
    s.put(ctr.mask(), hexc("#ffd84a"))


def seven77(s, rng, engraved=False):
    """Three golden reel windows with a red 7 in each (777), near the guard."""
    plates = Shapes()
    sev = Shapes()
    for k in range(3):
        cx, cy = 45 + k * 24, HMM * 0.5
        plates.poly([(cx - 10, cy - 14), (cx + 10, cy - 14), (cx + 10, cy + 14), (cx - 10, cy + 14)])
        sev.poly([(cx - 7, cy - 10), (cx + 7, cy - 10), (cx + 7, cy - 6.5), (cx - 0.5, cy + 11), (cx - 5, cy + 11), (cx + 2.5, cy - 6.5), (cx - 7, cy - 6.5)])
    pm = plates.mask()
    sm = sev.mask()
    x, y = grid()
    s.put(pm, mix(hexc("#b8892a"), hexc("#ffe27a"), fbm(1.0, 731)), metal=1.0, coat=0.0)
    edge = (1 - smooth(0.0, 0.8, inside_mm(pm))) * pm
    s.put(edge, hexc("#7a5a1a"))
    s.put(sm, hexc("#d8102a"), coat=1.0, metal=0.0)
    s.height += bump_of(sm, 0.5) * 0.4 - edge * 0.2
    shine = (rng.random((H, W)) > 0.996).astype(float) * pm
    s.put(shine, hexc("#ffffff"))
    s.glow = np.maximum(s.glow, sm * 0.5)


def _variant(base, extra):
    def draw(s, rng):
        base(s, rng)
        extra(s, rng)
    return draw


def quench_chase(blue_top=False):
    def draw(s, rng):
        quench(s, rng)
        x, y = grid()
        n = fbm(16, 207)
        if blue_top:
            m = 1 - smooth(16, 24, y + (n - 0.5) * 10)
        else:
            m = smooth(0.18, 0.24, n)  # almost all of it blue
        bc = mix(hexc("#123a9a"), hexc("#3c7cf0"), fbm(3, 215))
        s.put(m * (1 - smooth(165, 185, x) * (0 if blue_top else 0)), bc)
    return draw


def temper_chase(blue_top=False):
    def draw(s, rng):
        temper_line(s, rng)
        x, y = grid()
        if blue_top:
            m = (1 - smooth(14, 20, y + (fbm(8, 741) - 0.5) * 6))
        else:
            m = 1 - smooth(HMM * 0.62, HMM * 0.7, y)
        s.put(m * 0.85, mix(hexc("#1a3ab8"), hexc("#4a8af0"), fbm(5, 743)))
    return draw


def full_fade(base_fn):
    """The whole fade inside the first 175 mm: every colour of it on the blade."""
    def draw(s, rng):
        global WMM
        base_fn(s, rng)
        x, y = grid()
        squeeze = np.clip(x / 175.0, 0, 1) * WMM
        src_x = (squeeze * PX).astype(int).clip(0, W - 1)
        yy = np.arange(H)[:, None].repeat(W, 1)
        for name in ("col", "height", "glow", "metal", "coat"):
            arr = getattr(s, name)
            setattr(s, name, arr[yy, src_x] if arr.ndim == 2 else arr[yy, src_x, :])
    return draw


def recolour(base_fn, tint, keep=0.2, glow_gain=1.0):
    def draw(s, rng):
        base_fn(s, rng)
        _chase_tint(s, hexc(tint), keep)
        s.glow = np.clip(s.glow * glow_gain, 0, 1)
    return draw


def perfect_twist(s, rng):
    candy_cane(s, rng)  # then straighten the stripes: even, unbroken, glossier
    x, y = grid()
    k = (x + y * 0.9) / 14.0
    f = k - np.floor(k)
    red = smooth(0.0, 0.03, f) * (1 - smooth(0.39, 0.42, f))
    gold = smooth(0.52, 0.55, f) * (1 - smooth(0.6, 0.63, f))
    under = 1 - np.clip(s.coat * 0 + 0, 0, 1)
    keep = smooth(9.0, 11.0, y)  # keep the icing and holly at the spine
    s.put(keep * (1 - red) * (1 - gold), hexc("#fbf3e8"))
    s.put(keep * red, mix(hexc("#d0101e"), hexc("#ff4a4a"), 0.5 + 0.5 * np.cos(f * 2 * math.pi)))
    s.put(keep * gold, hexc("#e0b040"), metal=1.0)


def twelve_bells(s, rng):
    christmas_bells(s, rng)
    g = Shapes()
    for k in range(12):
        cx, top = 10 + k * 14, HMM * 0.62
        r = 3.6
        bell = [(cx - r * 0.4, top)] + [(cx - r * (0.45 + 0.55 * t ** 1.6), top + t * r * 1.5) for t in np.linspace(0, 1, 20)]
        bell += [(cx + r * (0.45 + 0.55 * t ** 1.6), top + t * r * 1.5) for t in np.linspace(1, 0, 20)]
        g.poly(bell)
        g.line([(cx, top - 6), (cx, top)], 0.4)
        g.ellipse(cx, top + r * 1.75, 0.8, 0.8)
    m = g.mask()
    s.put(m, mix(hexc("#c8992a"), hexc("#ffe27a"), fbm(0.6, 751)), metal=1.0, coat=0.0)
    s.height += bump_of(m, 0.6) * 0.45
    s.glow = np.maximum(s.glow, m * 0.6)


CHASES = {
    "quench_bluegem": quench_chase(),
    "quench_blue_top": quench_chase(True),
    "temper_line_bluegem": temper_chase(),
    "temper_line_blue_top": temper_chase(True),
    "heat_fade_full_fade": full_fade(heat_fade),
    "anvil_king_full_fade": full_fade(anvil_king),
    "brine_full_fade": full_fade(brine),
    "confetti_full_fade": _variant(confetti, lambda s, rng: bloom(s, rng, ["#ffd040", "#ff4ab0", "#40e0ff"], 0.0) or full_confetti_gold(s, rng)),
    "slag_heartfire": _variant(slag, heart_lava),
    "blast_furnace_heartfire": _variant(blast_furnace, heart_lava),
    "molten_core_heartfire": _variant(molten_core, heart_lava),
    "sea_glass_rogue_wave": _variant(sea_glass, lambda s, rng: great_wave(s, rng, hexc("#1a4a9a"), hexc("#3a8ac8"), hexc("#f0fbff"))),
    "kelp_wrap_rogue_wave": _variant(kelp_wrap, lambda s, rng: great_wave(s, rng, hexc("#06303a"), hexc("#1a7a7a"), hexc("#d8fff0"))),
    "quartermasters_hook_rogue_wave": _variant(quartermasters_hook, lambda s, rng: great_wave(s, rng, hexc("#0c2440"), hexc("#0c2440"), hexc("#e8c26a"), engraved=True)),
    "leviathans_tooth_rogue_wave": _variant(leviathans_tooth, lambda s, rng: great_wave(s, rng, hexc("#0a2a6a"), hexc("#2a8ae0"), hexc("#e0ffff"))),
    "abyss_lantern_bloodmoon": recolour(abyss_lantern, "#ff2a2a", 0.15, 1.2),
    "abyss_lantern_abyssal": recolour(abyss_lantern, "#2a6aff", 0.15, 1.2),
    "abyss_lantern_nightpearl": recolour(abyss_lantern, "#9a7ad8", 0.35, 0.9),
    "neon_nights_bloodmoon": recolour(neon_nights, "#ff2a3a", 0.12, 1.2),
    "neon_nights_abyssal": recolour(neon_nights, "#2a7aff", 0.12, 1.2),
    "neon_nights_nightpearl": recolour(neon_nights, "#b08ae8", 0.3, 1.0),
    "aurora_full_corona": _variant(aurora, lambda s, rng: corona(s, rng, ("#3aff9a", "#a050ff", "#40c0ff"))),
    "sky_ribbon_full_corona": _variant(sky_ribbon, lambda s, rng: corona(s, rng, ("#60e0ff", "#c060ff", "#fff080"))),
    "heart_of_the_wild_full_corona": _variant(heart_of_the_wild, lambda s, rng: corona(s, rng, ("#5aff8a", "#ff70c0", "#ffe060"))),
    "mossback_in_bloom": _variant(mossback, lambda s, rng: bloom(s, rng, ["#5a8cff", "#ff8ac8", "#ffffff", "#ffd040"])),
    "magpie_in_bloom": _variant(magpie, lambda s, rng: bloom(s, rng, ["#ffffff", "#e8f0ff", "#ffd8ec"], 0.7)),
    "worldroot_in_bloom": _variant(worldroot, lambda s, rng: bloom(s, rng, ["#ffc8e0", "#ffffff", "#ffd8a0"])),
    "candy_cane_perfect_twist": perfect_twist,
    "christmas_bells_twelve_bells": twelve_bells,
    "ticket_stub_777": _variant(ticket_stub, seven77),
    "house_always_wins_777": _variant(house_always_wins, seven77),
    "jesters_grin_777": _variant(jesters_grin, seven77),
}


def full_confetti_gold(s, rng):
    """Full Fade for Confetti: the confetti turns to a rainbow of foil from guard to tip within the blade."""
    x, y = grid()
    g = np.clip(x / 175.0, 0, 1)
    rain = np.stack([0.5 + 0.5 * np.cos((g + c) * 2 * math.pi) for c in (0.0, 0.33, 0.66)], -1)
    paper = (s.col.max(-1) > 0.2).astype(float) * (1 - smooth(170, 185, x))
    s.put(paper * 0.75, rain, metal=1.0, coat=0.0)


def main():
    every = {**FINISHES, **CHASES}
    ids = sys.argv[1:] or list(every)
    for fid in ids:
        base_id = next((b for b in FINISHES if fid.startswith(b + "_") and fid in CHASES), fid)
        rng = np.random.default_rng(sum(ord(c) * (i + 1) for i, c in enumerate(base_id)))  # a chase sheet starts from its finish's own drawing
        s = Sheet()
        every[fid](s, rng)
        s.save(fid)
        print("sheet", fid)


if __name__ == "__main__":
    main()
