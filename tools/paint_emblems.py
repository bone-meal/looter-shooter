# Purpose: paints the 10 painted player-card emblems (assets/ui/emblems/<name>.png, 256 px) -- our own subjects.
# Dependencies: tools/paint_lib.py, python3 with pycairo, numpy, Pillow. Usage: python3 tools/paint_emblems.py assets/ui/emblems [names...]
import sys, math, random
from paint_lib import *
from PIL import Image

OUT = sys.argv[1]


def sky(ctx, top, bottom):
    lin(ctx, 0, 0, 0, S, [(0, rgb(top)), (1, rgb(bottom))])
    ctx.paint()


def stars(ctx, n, seed, area=0.6):
    r = random.Random(seed)
    for _ in range(n):
        x, y = r.uniform(0, S), r.uniform(0, S * area)
        ctx.arc(x, y, r.uniform(0.6, 2.0), 0, math.tau)
        fill(ctx, (1, 1, 1, r.uniform(0.3, 0.9)))


def compose(*surfs):
    img = Image.new('RGBA', (S, S))
    for s in surfs:
        p = s if isinstance(s, Image.Image) else to_pil(s)
        img = Image.alpha_composite(img, p)
    return img


# 1. A crow on a skull under a blood moon, dead branches, low mist.
def crow_vigil():
    s, c = layer()
    sky(c, '#1a0608', '#4a1012')
    stars(c, 40, 1, 0.5)
    glow(c, 330, 170, 200, rgb('#ff3a2a'), 0.6)
    rad(c, 330, 170, 0, 92, [(0, rgb('#ffb08a')), (0.7, rgb('#e0402a')), (1, rgb('#a01a14'))])
    c.arc(330, 170, 92, 0, math.tau); c.fill()
    for x, y, rr in [(300, 150, 16), (355, 200, 11), (340, 130, 8)]:
        c.arc(x, y, rr, 0, math.tau); fill(c, (0.55, 0.1, 0.08, 0.35))
    # dead tree
    t, tc = layer()
    def branch(x, y, a, ln, w, d):
        if d == 0 or ln < 8:
            return
        x2, y2 = x + math.cos(a) * ln, y + math.sin(a) * ln
        tc.move_to(x, y); tc.line_to(x2, y2); stroke(tc, rgb('#0c0405'), w)
        branch(x2, y2, a - 0.45, ln * 0.72, w * 0.68, d - 1)
        branch(x2, y2, a + 0.35, ln * 0.66, w * 0.62, d - 1)
    branch(70, 520, -1.35, 150, 22, 7)
    branch(470, 520, -1.95, 110, 16, 6)
    # ground and skull
    g, gc = layer()
    smooth(gc, [(-20, 420), (120, 395), (260, 405), (400, 390), (540, 415), (540, 540), (-20, 540)])
    fill(gc, rgb('#0e0506'))
    k, kc = layer()
    sx, sy = 250, 370
    rad(kc, sx - 25, sy - 40, 5, 110, [(0, rgb('#f2e6d0')), (0.6, rgb('#b8a88c')), (1, rgb('#5a4a3a'))])
    kc.arc(sx, sy - 20, 78, math.pi * 0.95, math.pi * 2.05); kc.line_to(sx + 58, sy + 40); kc.line_to(sx + 40, sy + 72)
    kc.line_to(sx - 40, sy + 72); kc.line_to(sx - 58, sy + 40); kc.close_path(); kc.fill()
    for ex in (-30, 30):
        rad(kc, sx + ex, sy + 2, 2, 24, [(0, rgb('#000000')), (1, rgb('#1a0a08'))])
        smooth(kc, [(sx + ex - 22, sy - 6), (sx + ex, sy - 18), (sx + ex + 22, sy - 6), (sx + ex + 16, sy + 18), (sx + ex - 16, sy + 18)])
        kc.fill()
    poly(kc, [(sx, sy + 22), (sx + 11, sy + 44), (sx - 11, sy + 44)]); fill(kc, rgb('#1a0a08'))
    for i in range(5):
        x = sx - 32 + i * 16
        kc.rectangle(x, sy + 52, 12, 18); fill(kc, rgb('#e6dac2'))
        kc.rectangle(x, sy + 52, 12, 18); stroke(kc, rgb('#3a2a20'), 2)
    kc.move_to(sx + 20, sy - 80); kc.line_to(sx + 8, sy - 50); kc.line_to(sx + 22, sy - 30); stroke(kc, rgb('#4a3a2a', 0.8), 3)
    # crow
    w, wc = layer()
    cx, cy = 255, 272
    body = [(cx - 60, cy + 30), (cx - 30, cy - 10), (cx + 10, cy - 30), (cx + 40, cy - 70), (cx + 70, cy - 78), (cx + 92, cy - 70),
            (cx + 118, cy - 64), (cx + 92, cy - 54), (cx + 78, cy - 40), (cx + 70, cy - 5), (cx + 40, cy + 30), (cx - 10, cy + 45), (cx - 110, cy + 70)]
    smooth(wc, body)
    lin(wc, cx - 60, cy - 60, cx + 60, cy + 60, [(0, rgb('#2a2a3a')), (1, rgb('#050508'))]); wc.fill()
    # wing feathers
    for i in range(6):
        a = 0.2 + i * 0.12
        x0, y0 = cx + 30 - i * 12, cy - 10 + i * 4
        wc.move_to(x0, y0)
        wc.curve_to(x0 - 40, y0 + 10, x0 - 80 - i * 8, y0 + 30 + i * 6, x0 - 110 - i * 10, y0 + 40 + i * 9)
        stroke(wc, rgb('#3a3a52', 0.55), 3)
    wc.arc(cx + 80, cy - 64, 5, 0, math.tau); fill(wc, rgb('#ff5a3a'))
    wc.arc(cx + 80, cy - 64, 9, 0, math.tau); fill(wc, (1, 0.35, 0.2, 0.25))
    poly(wc, [(cx + 112, cy - 66), (cx + 132, cy - 60), (cx + 108, cy - 56)]); fill(wc, rgb('#1a1a20'))
    for fx in (cx - 5, cx + 18):
        wc.move_to(fx, cy + 40); wc.line_to(fx - 4, cy + 80); stroke(wc, rgb('#141416'), 5)
    # rim light from the moon on the crow
    wc.move_to(cx + 40, cy - 70); wc.curve_to(cx + 60, cy - 82, cx + 85, cy - 80, cx + 100, cy - 68); stroke(wc, (1, 0.4, 0.3, 0.7), 3)
    # mist
    m, mc = layer()
    for i in range(7):
        y = 400 + i * 14
        rad(mc, 80 + i * 70, y, 0, 120, [(0, (0.8, 0.5, 0.5, 0.18)), (1, (0.8, 0.5, 0.5, 0))])
        mc.arc(80 + i * 70, y, 120, 0, math.tau); mc.fill()
    return compose(s, t, g, k, w, m)


# 2. A clockwork bear's head, brass and steel, gears turning behind it, glowing eyes.
def gear_path(ctx, x, y, teeth, r_out, r_in, turn=0.0):
    pts = []
    for i in range(teeth):
        a = turn + i * math.tau / teeth
        st = math.tau / teeth
        for t, rr in ((0, r_in), (0.12, r_out), (0.45, r_out), (0.57, r_in)):
            pts.append((x + math.cos(a + st * t) * rr, y + math.sin(a + st * t) * rr))
    poly(ctx, pts)


def brass_gear(ctx, x, y, teeth, r_out, r_in, turn, dark=False):
    gear_path(ctx, x, y, teeth, r_out, r_in, turn)
    top, bot = ('#8a6a2a', '#3a2a10') if dark else ('#ffe08a', '#a0701a')
    lin(ctx, x - r_out, y - r_out, x + r_out, y + r_out, [(0, rgb(top)), (1, rgb(bot))]); ctx.fill_preserve()
    stroke(ctx, rgb('#2a1a08', 0.8), 2)
    ctx.arc(x, y, r_in * 0.62, 0, math.tau); fill(ctx, rgb('#1a1208', 0.85))
    for i in range(5):
        a = turn + i * math.tau / 5
        ctx.move_to(x + math.cos(a) * r_in * 0.2, y + math.sin(a) * r_in * 0.2)
        ctx.line_to(x + math.cos(a) * r_in * 0.62, y + math.sin(a) * r_in * 0.62)
        stroke(ctx, rgb(top), max(r_in * 0.12, 3))
    ctx.arc(x, y, r_in * 0.22, 0, math.tau); fill(ctx, rgb(top))


def clockwork_heart():
    s, c = layer()
    rad(c, 256, 230, 20, 330, [(0, rgb('#4a3018')), (1, rgb('#120a06'))]); c.paint()
    g, gc = layer()
    for x, y, n, ro, ri, tr in [(110, 130, 14, 95, 80, 0.1), (400, 120, 12, 80, 66, 0.3), (420, 380, 16, 105, 90, 0.0), (90, 400, 10, 70, 57, 0.2), (256, 90, 9, 50, 40, 0.0)]:
        brass_gear(gc, x, y, n, ro, ri, tr, dark=True)
    b, bc = layer()
    hx, hy = 256, 285
    # ears
    for ex in (-110, 110):
        bc.arc(hx + ex, hy - 115, 52, 0, math.tau)
        lin(bc, hx + ex - 50, hy - 165, hx + ex + 50, hy - 65, [(0, rgb('#d8a850')), (1, rgb('#6a4a1a'))]); bc.fill()
        bc.arc(hx + ex, hy - 115, 30, 0, math.tau); fill(bc, rgb('#3a2a14'))
        brass_gear(bc, hx + ex, hy - 115, 10, 26, 20, 0.2)
    # head plates
    smooth(bc, [(hx - 150, hy - 40), (hx - 120, hy - 120), (hx, hy - 150), (hx + 120, hy - 120), (hx + 150, hy - 40), (hx + 130, hy + 70), (hx, hy + 120), (hx - 130, hy + 70)])
    lin(bc, hx - 150, hy - 150, hx + 150, hy + 120, [(0, rgb('#f0c870')), (0.5, rgb('#b07e2a')), (1, rgb('#4a3010'))]); bc.fill_preserve()
    stroke(bc, rgb('#2a1a08'), 4)
    # plate seams and rivets
    bc.move_to(hx, hy - 150); bc.line_to(hx, hy - 40); stroke(bc, rgb('#3a2610', 0.8), 3)
    bc.move_to(hx - 140, hy - 20); bc.curve_to(hx - 60, hy - 50, hx + 60, hy - 50, hx + 140, hy - 20); stroke(bc, rgb('#3a2610', 0.8), 3)
    for i in range(9):
        a = math.pi * 1.1 + i * (math.pi * 0.8 / 8)
        x, y = hx + math.cos(a) * 125, hy - 20 + math.sin(a) * 105
        bc.arc(x, y, 5, 0, math.tau); fill(bc, rgb('#ffe9a8'))
        bc.arc(x + 1.5, y + 1.5, 5, 0, math.tau); fill(bc, rgb('#3a2410', 0.5))
    # open panel on the brow showing gears
    smooth(bc, [(hx - 70, hy - 105), (hx - 10, hy - 125), (hx + 50, hy - 110), (hx + 40, hy - 70), (hx - 60, hy - 68)])
    fill(bc, rgb('#120c06'))
    brass_gear(bc, hx - 30, hy - 92, 9, 22, 17, 0.0)
    brass_gear(bc, hx + 14, hy - 95, 8, 18, 14, 0.4)
    # muzzle
    smooth(bc, [(hx - 70, hy + 20), (hx, hy - 5), (hx + 70, hy + 20), (hx + 60, hy + 85), (hx, hy + 105), (hx - 60, hy + 85)])
    lin(bc, hx, hy - 5, hx, hy + 105, [(0, rgb('#c8ccd4')), (1, rgb('#4a4e58'))]); bc.fill_preserve(); stroke(bc, rgb('#22242a'), 3)
    smooth(bc, [(hx - 26, hy + 18), (hx + 26, hy + 18), (hx + 18, hy + 42), (hx - 18, hy + 42)]); fill(bc, rgb('#141418'))
    bc.move_to(hx, hy + 42); bc.line_to(hx, hy + 66); bc.move_to(hx - 30, hy + 74); bc.curve_to(hx - 10, hy + 84, hx + 10, hy + 84, hx + 30, hy + 74)
    stroke(bc, rgb('#141418'), 4)
    # eyes
    e, ec = layer()
    for ex in (-62, 62):
        ec.arc(hx + ex, hy - 30, 26, 0, math.tau); fill(ec, rgb('#1a1008'))
        ec.arc(hx + ex, hy - 30, 26, 0, math.tau); stroke(ec, rgb('#ffe08a'), 4)
        glow(ec, hx + ex, hy - 30, 60, rgb('#ff8a2a'), 0.9)
        rad(ec, hx + ex, hy - 30, 0, 16, [(0, rgb('#fff6c0')), (0.5, rgb('#ffb030')), (1, rgb('#c04a10'))])
        ec.arc(hx + ex, hy - 30, 16, 0, math.tau); ec.fill()
    # steam wisps
    w, wc = layer()
    for x0 in (150, 360):
        wc.move_to(x0, 160)
        wc.curve_to(x0 - 20, 120, x0 + 20, 90, x0, 50)
        stroke(wc, (1, 1, 1, 0.12), 14)
    return compose(s, g, b, e, blurred(w, 6))


# 3. A golden pistol (our own shape) over hundreds of carved tally marks.
def golden_tally():
    s, c = layer()
    lin(c, 0, 0, S, S, [(0, rgb('#3a2a1e')), (1, rgb('#140e0a'))]); c.paint()
    r = random.Random(3)
    for row in range(9):
        for grp in range(6):
            x0 = 30 + grp * 80 + r.uniform(-4, 4)
            y0 = 40 + row * 52 + r.uniform(-3, 3)
            for i in range(4):
                c.move_to(x0 + i * 12, y0); c.line_to(x0 + i * 12 + r.uniform(-3, 3), y0 + 36)
                stroke(c, rgb('#0a0604', 0.9), 5)
                c.move_to(x0 + i * 12 + 2, y0); c.line_to(x0 + i * 12 + 2, y0 + 36)
                stroke(c, rgb('#c8a070', 0.55), 2)
            c.move_to(x0 - 6, y0 + 30); c.line_to(x0 + 46, y0 + 6); stroke(c, rgb('#0a0604', 0.9), 5)
            c.move_to(x0 - 5, y0 + 32); c.line_to(x0 + 47, y0 + 8); stroke(c, rgb('#c8a070', 0.55), 2)
    g, gc = layer()
    glow(gc, 256, 270, 230, rgb('#ffc040'), 0.45)
    gc.save(); gc.translate(256, 270); gc.rotate(-0.32)
    # slide
    smooth(gc, [(-150, -60), (130, -60), (150, -48), (150, -14), (-150, -14)], close=True)
    lin(gc, 0, -60, 0, -14, [(0, rgb('#fff2b0')), (0.4, rgb('#f0b830')), (1, rgb('#8a5a10'))]); gc.fill_preserve(); stroke(gc, rgb('#4a2e08'), 3)
    for i in range(7):
        gc.move_to(-130 + i * 10, -54); gc.line_to(-130 + i * 10, -20); stroke(gc, rgb('#7a4e0e', 0.8), 3)
    # frame and grip
    poly(gc, [(-150, -14), (150, -14), (150, 8), (-40, 8), (-60, 120), (-130, 120), (-125, 40), (-150, 8)])
    lin(gc, -150, -14, 0, 120, [(0, rgb('#ffd860')), (1, rgb('#7a4a0a'))]); gc.fill_preserve(); stroke(gc, rgb('#4a2e08'), 3)
    # trigger guard
    gc.arc(-20, 22, 26, 0, math.pi); stroke(gc, rgb('#c08a20'), 7)
    # grip panel with engraving
    poly(gc, [(-118, 30), (-58, 30), (-70, 108), (-120, 108)]); fill(gc, rgb('#5a2a10'))
    for i in range(6):
        gc.move_to(-115, 40 + i * 12); gc.line_to(-64, 34 + i * 12); stroke(gc, rgb('#3a1808', 0.8), 2)
    # engraved swirl on the slide
    gc.move_to(-40, -36); gc.curve_to(-10, -56, 20, -16, 50, -36); gc.curve_to(70, -50, 90, -26, 110, -36); stroke(gc, rgb('#8a5a10', 0.8), 2.5)
    # highlight
    gc.move_to(-140, -54); gc.line_to(130, -54); stroke(gc, (1, 1, 0.9, 0.7), 3)
    gc.restore()
    # sparkles
    sp, sc = layer()
    for x, y, rr in [(140, 200, 22), (360, 160, 16), (330, 330, 12)]:
        for a in (0, math.pi / 2):
            sc.move_to(x - math.cos(a) * rr, y - math.sin(a) * rr); sc.line_to(x + math.cos(a) * rr, y + math.sin(a) * rr)
            stroke(sc, (1, 0.97, 0.8, 0.9), 2.5)
        glow(sc, x, y, rr, rgb('#fff0a0'), 0.8)
    return compose(s, g, sp)


# 4. A lighthouse on a rock in a storm: beam, rain, lightning, breaking waves.
def storm_light():
    s, c = layer()
    sky(c, '#0a1218', '#24384a')
    for i in range(14):
        r = random.Random(i)
        x, y = r.uniform(-50, 560), r.uniform(20, 240)
        rad(c, x, y, 0, r.uniform(60, 130), [(0, (0.18, 0.25, 0.32, 0.8)), (1, (0.1, 0.15, 0.2, 0))])
        c.arc(x, y, 130, 0, math.tau); c.fill()
    # lightning
    lt, lc = layer()
    pts = [(420, 0), (400, 60), (425, 70), (385, 150), (405, 158), (370, 230)]
    poly(lc, pts, close=False); stroke(lc, (0.85, 0.95, 1, 0.9), 4)
    poly(lc, pts, close=False); stroke(lc, (0.6, 0.8, 1, 0.3), 14)
    # beam
    bm, bc = layer()
    lx, ly = 210, 175
    poly(bc, [(lx, ly), (-40, ly - 120), (-40, ly + 30)])
    lin(bc, lx, ly, -40, ly, [(0, (1, 0.95, 0.7, 0.75)), (1, (1, 0.95, 0.7, 0))]); bc.fill()
    poly(bc, [(lx, ly), (560, ly - 60), (560, ly + 40)])
    lin(bc, lx, ly, 560, ly, [(0, (1, 0.95, 0.7, 0.5)), (1, (1, 0.95, 0.7, 0))]); bc.fill()
    # rock and lighthouse
    t, tc = layer()
    smooth(tc, [(60, 420), (120, 340), (220, 320), (320, 350), (360, 420), (360, 540), (60, 540)])
    lin(tc, 0, 320, 0, 540, [(0, rgb('#3a4048')), (1, rgb('#0e1014'))]); tc.fill()
    poly(tc, [(175, 335), (245, 335), (232, 200), (188, 200)])
    lin(tc, 175, 0, 245, 0, [(0, rgb('#e8e4dc')), (0.6, rgb('#b8b2a8')), (1, rgb('#5a5650'))]); tc.fill()
    for i, y in enumerate((300, 255)):
        top = 335 - (335 - 200) * ((335 - y + 22) / 135)
        poly(tc, [(176 + (y - 200) * 0 - 0, y), (244, y), (241, y - 22), (179, y - 22)]); fill(tc, rgb('#c03030'))
    tc.rectangle(180, 186, 60, 14); fill(tc, rgb('#2a2a2e'))
    tc.rectangle(188, 156, 44, 30); fill(tc, rgb('#fff2b0'))
    glow(tc, lx, ly, 70, rgb('#fff0a0'), 1.0)
    poly(tc, [(182, 156), (238, 156), (210, 128)]); fill(tc, rgb('#2a2a2e'))
    tc.rectangle(203, 230, 14, 22); fill(tc, rgb('#3a3020'))
    # waves
    wv, wc = layer()
    for k in range(4):
        y0 = 400 + k * 30
        pts = [(-20, y0 + 30)]
        for i in range(12):
            x = -20 + i * 50
            pts.append((x, y0 + math.sin(i * 1.3 + k) * 14))
        pts += [(560, y0 + 30), (560, 540), (-20, 540)]
        smooth(wc, pts)
        lin(wc, 0, y0 - 20, 0, y0 + 80, [(0, rgb(['#3a6a80', '#2a5468', '#1c3e50', '#102a38'][k])), (1, rgb('#081820'))]); wc.fill()
        for i in range(12):
            x = -20 + i * 50
            wc.arc(x + 10, y0 + math.sin(i * 1.3 + k) * 14 - 2, 12, math.pi, math.tau)
            stroke(wc, (0.85, 0.95, 1, 0.5), 3)
    # spray at the rock
    sp, sc = layer()
    for i in range(30):
        r = random.Random(100 + i)
        sc.arc(r.uniform(60, 360), r.uniform(330, 420), r.uniform(4, 16), 0, math.tau); fill(sc, (0.9, 0.97, 1, r.uniform(0.15, 0.4)))
    # rain
    rn, rc = layer()
    r = random.Random(9)
    for _ in range(170):
        x, y = r.uniform(-40, S), r.uniform(-20, S)
        rc.move_to(x, y); rc.line_to(x + 10, y + 34); stroke(rc, (0.75, 0.85, 0.95, 0.28), 1.5)
    return compose(s, blurred(lt, 1), bm, t, wv, blurred(sp, 3), rn)


# 5. A sunken bell held by kraken tentacles, light from far above, bubbles.
def tentacle(ctx, pts, w0, w1, col_top, col_bot, suckers=True):
    n = len(pts)
    left, right = [], []
    for i, p in enumerate(pts):
        q = pts[min(i + 1, n - 1)]; o = pts[max(i - 1, 0)]
        dx, dy = q[0] - o[0], q[1] - o[1]
        ln = math.hypot(dx, dy) or 1
        nx, ny = -dy / ln, dx / ln
        w = w0 + (w1 - w0) * i / (n - 1)
        left.append((p[0] + nx * w, p[1] + ny * w)); right.append((p[0] - nx * w, p[1] - ny * w))
    smooth(ctx, left + right[::-1])
    lin(ctx, pts[0][0], pts[0][1], pts[-1][0], pts[-1][1], [(0, rgb(col_top)), (1, rgb(col_bot))]); ctx.fill_preserve()
    stroke(ctx, rgb('#1a0612', 0.7), 2)
    if suckers:
        for i in range(1, n - 1):
            p = right[i]; w = w0 + (w1 - w0) * i / (n - 1)
            ctx.arc((p[0] * 2 + pts[i][0]) / 3, (p[1] * 2 + pts[i][1]) / 3, max(w * 0.32, 2), 0, math.tau)
            fill(ctx, rgb('#f0b0c0', 0.8))


def drowned_bell():
    s, c = layer()
    sky(c, '#1a6a80', '#020c18')
    rays, rc = layer()
    for x0, w in [(150, 40), (240, 60), (330, 30), (400, 50)]:
        poly(rc, [(x0, -10), (x0 + w, -10), (x0 + w * 2.5 + 40, 540), (x0 - 40, 540)])
        lin(rc, 0, 0, 0, 540, [(0, (0.7, 1, 1, 0.22)), (1, (0.7, 1, 1, 0))]); rc.fill()
    # sea floor
    f, fc = layer()
    smooth(fc, [(-20, 450), (100, 430), (250, 445), (400, 425), (540, 450), (540, 540), (-20, 540)])
    fill(fc, rgb('#0a1a20'))
    # bell
    b, bc = layer()
    bx, by = 256, 300
    bc.save(); bc.translate(bx, by); bc.rotate(0.18)
    smooth(bc, [(-28, -150), (28, -150), (70, -110), (85, -10), (100, 70), (140, 105), (-140, 105), (-100, 70), (-85, -10), (-70, -110)])
    lin(bc, -140, 0, 140, 0, [(0, rgb('#2a4a3a')), (0.35, rgb('#7aa070')), (0.55, rgb('#c8b060')), (1, rgb('#1a3028'))]); bc.fill_preserve()
    stroke(bc, rgb('#0a1810'), 3)
    for y in (-60, 60):
        bc.move_to(-92, y); bc.curve_to(-30, y + 12, 30, y + 12, 92, y); stroke(bc, rgb('#3a5a40', 0.9), 5)
    bc.arc(0, -158, 22, math.pi, math.tau); stroke(bc, rgb('#5a7a50'), 10)
    bc.arc(0, 112, 20, 0, math.tau); fill(bc, rgb('#2a3a28'))
    # barnacles and weed
    r = random.Random(5)
    for _ in range(18):
        bc.arc(r.uniform(-90, 90), r.uniform(-120, 95), r.uniform(3, 7), 0, math.tau); fill(bc, rgb('#c8d0b0', 0.7))
    bc.restore()
    # tentacles wrapping it
    t, tc = layer()
    tentacle(tc, [(60, 470), (90, 380), (150, 330), (230, 340), (310, 300), (360, 250), (340, 200)], 40, 7, '#5a0e2a', '#e05a7a')
    tentacle(tc, [(470, 480), (430, 400), (360, 380), (290, 400), (210, 380), (160, 330), (175, 270)], 36, 6, '#4a0a22', '#d04a6a')
    tentacle(tc, [(-10, 300), (60, 260), (120, 200), (180, 190), (215, 160)], 28, 5, '#3a0818', '#b03a5a')
    tentacle(tc, [(520, 230), (460, 220), (420, 170), (380, 160), (350, 130)], 26, 5, '#3a0818', '#b03a5a')
    # a great eye in the dark
    e, ec = layer()
    glow(ec, 430, 470, 60, rgb('#ffd040'), 0.6)
    smooth(ec, [(395, 470), (430, 452), (465, 470), (430, 488)]); fill(ec, rgb('#ffcc30'))
    ec.rectangle(426, 456, 8, 28); fill(ec, rgb('#140404'))
    # bubbles
    bb, bbc = layer()
    r = random.Random(7)
    for _ in range(40):
        x, y, rr = r.uniform(80, 440), r.uniform(20, 420), r.uniform(2, 9)
        bbc.arc(x, y, rr, 0, math.tau); stroke(bbc, (0.85, 1, 1, 0.55), 1.5)
        bbc.arc(x - rr * 0.3, y - rr * 0.3, rr * 0.25, 0, math.tau); fill(bbc, (1, 1, 1, 0.6))
    return compose(s, blurred(rays, 4), f, b, t, e, bb)


# 6. A glowing jukebox with notes rising out of it.
def jukebox():
    s, c = layer()
    rad(c, 256, 260, 10, 320, [(0, rgb('#3a1a4a')), (1, rgb('#08040e'))]); c.paint()
    fl, flc = layer()
    rad(flc, 256, 470, 0, 220, [(0, (1, 0.4, 0.8, 0.35)), (1, (1, 0.4, 0.8, 0))]); flc.paint()
    j, jc = layer()
    x0, x1, top, bot = 150, 362, 110, 470
    glow(jc, 256, 270, 250, rgb('#ff6ab0'), 0.5)
    jc.move_to(x0, bot); jc.line_to(x0, 220); jc.arc(256, 220, 106, math.pi, math.tau); jc.line_to(x1, bot); jc.close_path()
    lin(jc, x0, 0, x1, 0, [(0, rgb('#5a2a10')), (0.5, rgb('#b06a2a')), (1, rgb('#4a200c'))]); jc.fill()
    # neon arches
    for i, col in enumerate(['#ff4aa0', '#ffd040', '#40e0ff']):
        rr = 96 - i * 16
        jc.arc(256, 222, rr, math.pi, math.tau); jc.line_to(256 + rr, 300); jc.move_to(256 - rr, 300); jc.line_to(256 - rr, 222)
        stroke(jc, rgb(col, 0.3), 16);
        jc.arc(256, 222, rr, math.pi, math.tau); jc.line_to(256 + rr, 300); jc.move_to(256 - rr, 300); jc.line_to(256 - rr, 222)
        stroke(jc, rgb(col), 5)
    # record window
    jc.arc(256, 220, 46, math.pi, math.tau); jc.line_to(302, 270); jc.line_to(210, 270); jc.close_path(); fill(jc, rgb('#120814'))
    jc.arc(256, 252, 34, math.pi, math.tau); fill(jc, rgb('#0a0a0a'))
    for rr in (12, 20, 28):
        jc.arc(256, 252, rr, math.pi, math.tau); stroke(jc, rgb('#3a3a3a'), 1.5)
    jc.arc(256, 252, 8, math.pi, math.tau); fill(jc, rgb('#e04040'))
    # selector panel and grille
    jc.rectangle(180, 310, 152, 44); fill(jc, rgb('#fff2d0'))
    for i in range(4):
        jc.move_to(186, 320 + i * 9); jc.line_to(326, 320 + i * 9); stroke(jc, rgb('#a08060', 0.7), 1.5)
    jc.rectangle(180, 368, 152, 86); fill(jc, rgb('#1a0c06'))
    for i in range(9):
        x = 190 + i * 16
        jc.move_to(x, 374); jc.line_to(x, 448); stroke(jc, rgb('#d8a050'), 4)
    jc.rectangle(x0, bot - 12, x1 - x0, 12); fill(jc, rgb('#2a1408'))
    # bubble tubes on the sides
    for sx in (x0 + 12, x1 - 12):
        jc.move_to(sx, bot - 20); jc.line_to(sx, 230); stroke(jc, rgb('#ff8ad0', 0.8), 9)
        for k in range(6):
            jc.arc(sx, 250 + k * 34, 3, 0, math.tau); fill(jc, (1, 1, 1, 0.8))
    # notes
    n, nc = layer()
    for x, y, sc, col, tw in [(100, 150, 1.0, '#ffd040', False), (410, 120, 1.2, '#40e0ff', True), (80, 300, 0.8, '#ff4aa0', True), (430, 290, 0.9, '#ffd040', False), (330, 60, 0.7, '#ff4aa0', False), (190, 60, 0.8, '#40e0ff', False)]:
        nc.save(); nc.translate(x, y); nc.scale(sc, sc); nc.rotate(-0.2)
        glow(nc, 0, 0, 50, rgb(col), 0.5)
        nc.save(); nc.scale(1.3, 1.0); nc.arc(0, 20, 12, 0, math.tau); nc.restore(); fill(nc, rgb(col))
        nc.move_to(14, 20); nc.line_to(14, -30); stroke(nc, rgb(col), 4)
        if tw:
            nc.save(); nc.scale(1.3, 1.0); nc.arc(40, 10, 12, 0, math.tau); nc.restore(); fill(nc, rgb(col))
            nc.move_to(66, 10); nc.line_to(66, -40); stroke(nc, rgb(col), 4)
            poly(nc, [(14, -30), (66, -40), (66, -28), (14, -18)]); fill(nc, rgb(col))
        else:
            nc.move_to(14, -30); nc.curve_to(30, -20, 34, -6, 26, 4); stroke(nc, rgb(col), 4)
        nc.restore()
    return compose(s, fl, j, n)


# 7. The colosseum against a setting sun, crossed swords planted in the sand.
def sunset_arena():
    s, c = layer()
    sky(c, '#3a1050', '#ff8a30')
    glow(c, 256, 300, 260, rgb('#ffb040'), 0.7)
    rad(c, 256, 300, 0, 110, [(0, rgb('#fff6c0')), (0.6, rgb('#ffc040')), (1, rgb('#ff7020'))])
    c.arc(256, 300, 110, 0, math.tau); c.fill()
    for i, y in enumerate((260, 285, 312, 338)):
        c.rectangle(0, y, S, 4 + i); fill(c, rgb('#ff8a40', 0.5))
    cl, clc = layer()
    for x, y, w in [(110, 140, 160), (380, 110, 140), (300, 190, 120)]:
        smooth(clc, [(x - w / 2, y), (x - w / 4, y - 18), (x, y - 10), (x + w / 4, y - 22), (x + w / 2, y), (x + w / 3, y + 10), (x - w / 3, y + 10)])
        fill(clc, rgb('#8a3a6a', 0.75))
        clc.move_to(x - w / 2.4, y + 6); clc.line_to(x + w / 2.4, y + 6); stroke(clc, rgb('#ffb070', 0.6), 3)
    a, ac = layer()
    # arena: three tiers of arches
    base_y = 390
    ac.move_to(40, base_y)
    ac.line_to(40, 250); ac.curve_to(150, 230, 362, 230, 472, 250); ac.line_to(472, base_y); ac.close_path()
    fill(ac, rgb('#2a0e1a'))
    for tier, (yt, yb, n) in enumerate([(262, 300, 9), (304, 344, 9), (348, 388, 9)]):
        for i in range(n):
            x = 56 + i * 46
            ac.move_to(x, yb); ac.line_to(x, yt + 12); ac.arc(x + 15, yt + 12, 15, math.pi, math.tau); ac.line_to(x + 30, yb); ac.close_path()
            fill(ac, rgb('#ffb050', 0.85 - tier * 0.15))
    # broken top edge
    poly(ac, [(40, 250), (60, 236), (90, 244), (120, 226), (170, 238), (472, 250), (472, 262), (40, 262)]); fill(ac, rgb('#2a0e1a'))
    # sand
    sd, sdc = layer()
    smooth(sdc, [(-20, 400), (150, 385), (360, 392), (540, 380), (540, 540), (-20, 540)])
    lin(sdc, 0, 380, 0, 540, [(0, rgb('#c87a3a')), (1, rgb('#4a2010'))]); sdc.fill()
    # swords crossed in front
    w, wc = layer()
    for side in (-1, 1):
        wc.save(); wc.translate(256, 330); wc.rotate(side * 0.55); wc.translate(0, 60)
        poly(wc, [(-9, 30), (-9, -230), (0, -258), (9, -230), (9, 30)])
        lin(wc, -9, 0, 9, 0, [(0, rgb('#e8ecf4')), (0.5, rgb('#ffffff')), (1, rgb('#7a808c'))]); wc.fill()
        wc.move_to(0, -240); wc.line_to(0, 20); stroke(wc, rgb('#9aa0ac', 0.8), 2)
        wc.rectangle(-42, 26, 84, 14); fill(wc, rgb('#c89030'))
        wc.rectangle(-7, 40, 14, 56); fill(wc, rgb('#4a2a14'))
        wc.arc(0, 102, 11, 0, math.tau); fill(wc, rgb('#e0b040'))
        wc.move_to(-8, -220); wc.line_to(-8, 10); stroke(wc, (1, 0.8, 0.5, 0.6), 2)
        wc.restore()
    # dust
    d, dc = layer()
    rr = random.Random(11)
    for _ in range(50):
        dc.arc(rr.uniform(0, S), rr.uniform(330, 470), rr.uniform(1, 3), 0, math.tau); fill(dc, (1, 0.85, 0.6, rr.uniform(0.2, 0.6)))
    return compose(s, cl, a, sd, w, d)


# 8. A crowned pale skull in a ghostly purple light.
def pallid_crown():
    s, c = layer()
    rad(c, 256, 240, 10, 330, [(0, rgb('#3a2a5a')), (1, rgb('#06040c'))]); c.paint()
    wisp, wc = layer()
    for i in range(9):
        r = random.Random(20 + i)
        x = r.uniform(60, 450)
        wc.move_to(x, 520); wc.curve_to(x + r.uniform(-80, 80), 380, x + r.uniform(-60, 60), 260, x + r.uniform(-40, 40), r.uniform(90, 200))
        stroke(wc, (0.7, 0.6, 1, 0.22), r.uniform(8, 20))
    k, kc = layer()
    sx, sy = 256, 300
    glow(kc, sx, sy, 230, rgb('#b8a0ff'), 0.55)
    rad(kc, sx - 30, sy - 60, 10, 170, [(0, rgb('#ffffff')), (0.5, rgb('#d0cce0')), (1, rgb('#6a6480'))])
    kc.arc(sx, sy - 30, 108, math.pi * 0.92, math.pi * 2.08)
    kc.line_to(sx + 84, sy + 50); kc.curve_to(sx + 70, sy + 90, sx + 50, sy + 108, sx + 46, sy + 120)
    kc.line_to(sx - 46, sy + 120); kc.curve_to(sx - 50, sy + 108, sx - 70, sy + 90, sx - 84, sy + 50); kc.close_path(); kc.fill()
    for ex in (-42, 42):
        rad(kc, sx + ex, sy, 0, 34, [(0, rgb('#2a1a5a')), (0.5, rgb('#0a0614')), (1, rgb('#141020'))])
        smooth(kc, [(sx + ex - 32, sy - 10), (sx + ex, sy - 28), (sx + ex + 32, sy - 10), (sx + ex + 24, sy + 26), (sx + ex - 24, sy + 26)]); kc.fill()
        glow(kc, sx + ex, sy, 22, rgb('#c0a0ff'), 1.0)
        kc.arc(sx + ex, sy, 5, 0, math.tau); fill(kc, rgb('#ffffff'))
    poly(kc, [(sx, sy + 34), (sx + 15, sy + 64), (sx - 15, sy + 64)]); fill(kc, rgb('#141020'))
    for i in range(6):
        x = sx - 42 + i * 14.5
        kc.rectangle(x, sy + 84, 12, 26); fill(kc, rgb('#ece8f4'))
        kc.rectangle(x, sy + 84, 12, 26); stroke(kc, rgb('#4a4460'), 2)
    kc.move_to(sx - 60, sy - 110); kc.line_to(sx - 40, sy - 70); kc.line_to(sx - 56, sy - 46); stroke(kc, rgb('#6a6480', 0.8), 3)
    # crown
    cr, cc = layer()
    cy = sy - 120
    pts = [(sx - 100, cy + 40), (sx - 110, cy - 50), (sx - 66, cy - 6), (sx - 34, cy - 80), (sx, cy - 20), (sx + 34, cy - 80), (sx + 66, cy - 6), (sx + 110, cy - 50), (sx + 100, cy + 40)]
    poly(cc, pts)
    lin(cc, sx - 110, cy - 80, sx + 110, cy + 40, [(0, rgb('#e8e0ff')), (0.5, rgb('#a898d0')), (1, rgb('#4a4070'))]); cc.fill_preserve()
    stroke(cc, rgb('#201a34'), 3)
    cc.rectangle(sx - 102, cy + 18, 204, 24); fill(cc, rgb('#7a6aa8'))
    for x, col in [(sx - 60, '#7a3aff'), (sx, '#c0a0ff'), (sx + 60, '#7a3aff')]:
        glow(cc, x, cy + 30, 20, rgb(col), 0.8)
        poly(cc, [(x, cy + 18), (x + 10, cy + 30), (x, cy + 42), (x - 10, cy + 30)]); fill(cc, rgb(col))
    for x, y in [(sx - 110, cy - 50), (sx - 34, cy - 80), (sx + 34, cy - 80), (sx + 110, cy - 50)]:
        cc.arc(x, y, 8, 0, math.tau); fill(cc, rgb('#f0eaff'))
    return compose(s, blurred(wisp, 5), k, cr)


# 9. A staff's orb with the five element sigils circling it.
def five_sigils():
    s, c = layer()
    rad(c, 256, 230, 10, 330, [(0, rgb('#20284a')), (1, rgb('#04060e'))]); c.paint()
    stars(c, 70, 4, 1.0)
    st, stc = layer()
    # staff
    poly(stc, [(244, 330), (268, 330), (276, 540), (236, 540)])
    lin(stc, 236, 0, 276, 0, [(0, rgb('#3a2010')), (0.5, rgb('#8a5a30')), (1, rgb('#2a1408'))]); stc.fill()
    for y in (360, 420):
        stc.rectangle(238, y, 36, 10); fill(stc, rgb('#c8a050'))
    # claws holding the orb
    for side in (-1, 1):
        stc.move_to(256 + side * 10, 335); stc.curve_to(256 + side * 70, 320, 256 + side * 85, 250, 256 + side * 50, 200)
        stroke(stc, rgb('#c8a050'), 10)
    o, oc = layer()
    glow(oc, 256, 245, 200, rgb('#9fd8ff'), 0.6)
    rad(oc, 236, 220, 5, 82, [(0, rgb('#ffffff')), (0.25, rgb('#c8f0ff')), (0.7, rgb('#4a7ae0')), (1, rgb('#1a2a6a'))])
    oc.arc(256, 245, 76, 0, math.tau); oc.fill()
    oc.arc(232, 218, 18, 0, math.tau); fill(oc, (1, 1, 1, 0.75))
    # swirl inside
    oc.move_to(210, 260); oc.curve_to(240, 220, 280, 290, 300, 240); stroke(oc, (1, 1, 1, 0.35), 4)
    # orbit ring
    ring, rcx = layer()
    rcx.save(); rcx.translate(256, 245); rcx.scale(1.0, 0.38)
    rcx.arc(0, 0, 170, 0, math.tau); rcx.restore(); stroke(rcx, (1, 1, 1, 0.35), 3)
    # sigils: water, fire, earth, air, gravity
    sg, sgc = layer()
    cols = ['#40a0ff', '#ff6a1e', '#a07040', '#d8f2ff', '#a866ff']
    for i in range(5):
        a = -math.pi / 2 + i * math.tau / 5
        x, y = 256 + math.cos(a) * 190, 245 + math.sin(a) * 165
        col = rgb(cols[i])
        glow(sgc, x, y, 52, col, 0.8)
        sgc.arc(x, y, 34, 0, math.tau); fill(sgc, rgb('#0a0c18', 0.85))
        sgc.arc(x, y, 34, 0, math.tau); stroke(sgc, col, 4)
        sgc.save(); sgc.translate(x, y)
        if i == 0:  # water drop
            sgc.move_to(0, -20); sgc.curve_to(16, 0, 14, 18, 0, 18); sgc.curve_to(-14, 18, -16, 0, 0, -20); fill(sgc, col)
        elif i == 1:  # flame
            sgc.move_to(0, -22); sgc.curve_to(18, -4, 14, 18, 0, 18); sgc.curve_to(-14, 18, -18, 0, -4, -8); sgc.curve_to(-2, 0, 4, -6, 0, -22); fill(sgc, col)
        elif i == 2:  # earth: mountain over a line
            poly(sgc, [(-20, 14), (-6, -14), (2, -2), (8, -12), (20, 14)]); fill(sgc, col)
            sgc.move_to(-20, 18); sgc.line_to(20, 18); stroke(sgc, col, 3)
        elif i == 3:  # air: three swirls
            for k in range(3):
                sgc.move_to(-18, -10 + k * 10); sgc.curve_to(0, -16 + k * 10, 10, -4 + k * 10, 18 - k * 4, -10 + k * 10); stroke(sgc, col, 3)
        else:  # gravity: rings falling to a dot
            for rr in (18, 12):
                sgc.arc(0, 0, rr, 0, math.tau); stroke(sgc, col, 2.5)
            sgc.arc(0, 0, 5, 0, math.tau); fill(sgc, col)
        sgc.restore()
        # thread of light to the orb
        sgc.move_to(x, y); sgc.line_to(256 + math.cos(a) * 80, 245 + math.sin(a) * 80)
        stroke(sgc, (col[0], col[1], col[2], 0.35), 3)
    return compose(s, st, ring, o, sg)


# 10. A phoenix rising out of flames, wings spread.
def phoenix():
    s, c = layer()
    rad(c, 256, 300, 10, 340, [(0, rgb('#5a1a08')), (1, rgb('#0a0204'))]); c.paint()
    f, fc = layer()
    r = random.Random(12)
    for k in range(26):
        x = r.uniform(40, 470); h = r.uniform(80, 200)
        fc.move_to(x - 30, 540); fc.curve_to(x - 30, 540 - h * 0.5, x + r.uniform(-20, 20), 540 - h * 0.7, x + r.uniform(-10, 10), 540 - h)
        fc.curve_to(x + 10, 540 - h * 0.6, x + 34, 540 - h * 0.4, x + 30, 540); fc.close_path()
        lin(fc, 0, 540 - h, 0, 540, [(0, rgb('#ffe060', 0.0)), (0.3, rgb('#ffb030', 0.8)), (1, rgb('#d02a08', 0.9))]); fc.fill()
    p, pc = layer()
    glow(pc, 256, 250, 240, rgb('#ff8a20'), 0.7)
    def wing(side):
        pc.save(); pc.translate(256, 240); pc.scale(side, 1)
        for i in range(9):
            a = -0.95 + i * 0.16
            ln = 220 - abs(i - 3) * 14
            x1, y1 = math.cos(a) * ln, math.sin(a) * ln
            pc.move_to(10, 10)
            pc.curve_to(x1 * 0.4, y1 * 0.4 - 30, x1 * 0.8, y1 * 0.8 - 10, x1, y1)
            pc.curve_to(x1 * 0.85 + 14, y1 * 0.85 + 26, x1 * 0.4 + 10, y1 * 0.4 + 30, 10, 30)
            pc.close_path()
            lin(pc, 0, 0, x1, y1, [(0, rgb('#fff2a0')), (0.4, rgb('#ffb030')), (0.8, rgb('#ff4a10')), (1, rgb('#a01806'))]); pc.fill_preserve()
            stroke(pc, rgb('#6a1004', 0.5), 1.5)
        pc.restore()
    wing(1); wing(-1)
    # body and tail
    smooth(pc, [(256, 160), (282, 200), (284, 260), (270, 320), (256, 360), (242, 320), (228, 260), (230, 200)])
    lin(pc, 256, 160, 256, 360, [(0, rgb('#fff6c0')), (0.5, rgb('#ffc040')), (1, rgb('#ff5a10'))]); pc.fill()
    for i, (dx, ln) in enumerate([(-50, 150), (0, 180), (50, 150), (-25, 165), (25, 165)]):
        pc.move_to(256, 340); pc.curve_to(256 + dx * 0.5, 400, 256 + dx * 1.2, 440, 256 + dx * 1.5, 340 + ln)
        stroke(pc, rgb(['#ff6a10', '#ffd040', '#ff6a10', '#ff9a20', '#ff9a20'][i]), 10 - i)
        pc.arc(256 + dx * 1.5, 340 + ln, 10, 0, math.tau); fill(pc, rgb('#ffe060'))
    # head and crest
    pc.arc(256, 150, 26, 0, math.tau)
    rad(pc, 250, 142, 2, 28, [(0, rgb('#ffffff')), (0.5, rgb('#ffe080')), (1, rgb('#ff9a20'))]); pc.fill()
    for k in range(5):
        a = -math.pi / 2 + (k - 2) * 0.32
        pc.move_to(256, 130); pc.curve_to(256 + math.cos(a) * 20, 130 + math.sin(a) * 30, 256 + math.cos(a) * 34, 120 + math.sin(a) * 50, 256 + math.cos(a) * 40, 112 + math.sin(a) * 58)
        stroke(pc, rgb('#ffd040'), 4)
        pc.arc(256 + math.cos(a) * 40, 112 + math.sin(a) * 58, 5, 0, math.tau); fill(pc, rgb('#fff6c0'))
    poly(pc, [(256, 158), (272, 166), (256, 176)]); fill(pc, rgb('#a05010'))
    pc.arc(248, 148, 4, 0, math.tau); fill(pc, rgb('#3a0a04'))
    # embers
    e, ec = layer()
    for _ in range(60):
        x, y = r.uniform(20, 490), r.uniform(40, 500)
        ec.arc(x, y, r.uniform(1.5, 4), 0, math.tau); fill(ec, (1, r.uniform(0.6, 0.95), 0.3, r.uniform(0.4, 0.95)))
    return compose(s, blurred(f, 2), p, e)


ALL = [("crow_vigil", crow_vigil), ("clockwork_heart", clockwork_heart), ("golden_tally", golden_tally), ("storm_light", storm_light),
       ("drowned_bell", drowned_bell), ("jukebox", jukebox), ("sunset_arena", sunset_arena), ("pallid_crown", pallid_crown),
       ("five_sigils", five_sigils), ("phoenix", phoenix)]

if __name__ == "__main__":
    for i, (name, fn) in enumerate(ALL):
        if len(sys.argv) > 2 and name not in sys.argv[2:]:
            continue
        finish(fn(), name, OUT, seed=i + 1)
        print("painted", name)
