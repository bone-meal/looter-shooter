# Purpose: paints the card pack and the 50-pack box of "You got me Lobster?" for the card machine and pack opening:
# a crimson foil wrapper with crimped gold ends, a holographic sheen, the logo and the name (assets/tcg/pack.png,
# 360 x 600) and a gold-trimmed box with the logo (assets/tcg/box.png, 520 x 420). Developer-time (Pillow).
# Usage: python3 tools/paint_pack.py
# Dependencies: Pillow, numpy; assets/tcg/logo.png, assets/fonts/Cinzel.ttf.
import os

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
TCG = os.path.join(ROOT, "assets", "tcg")


def holo(w, h, base, strength=0.35):
    y, x = np.mgrid[0:h, 0:w].astype(np.float32)
    band = (x * 0.8 + y * 0.6) / 90.0
    r = 0.5 + 0.5 * np.sin(band * 2.0)
    g = 0.5 + 0.5 * np.sin(band * 2.0 + 2.1)
    b = 0.5 + 0.5 * np.sin(band * 2.0 + 4.2)
    shine = np.clip(1.0 - np.abs(((x + y * 0.7) / (w + h) * 3.0) % 1.0 - 0.5) * 4.0, 0, 1) ** 2
    img = np.zeros((h, w, 3), np.float32)
    for i, c in enumerate(base):
        img[..., i] = c
    img[..., 0] += (r * strength + shine * 0.35) * 255 * 0.5
    img[..., 1] += (g * strength + shine * 0.35) * 255 * 0.5
    img[..., 2] += (b * strength + shine * 0.35) * 255 * 0.5
    return Image.fromarray(np.clip(img, 0, 255).astype(np.uint8)).convert("RGBA")


def pack():
    W, H = 360, 600
    body = holo(W, H, (120, 10, 40))
    d = ImageDraw.Draw(body)
    for y0 in (0, H - 46):  # crimped gold ends
        d.rectangle([0, y0, W, y0 + 46], fill=(214, 165, 70))
        for x in range(0, W, 12):
            d.line([x, y0, x, y0 + 46], fill=(150, 105, 35), width=3)
    d.rectangle([14, 60, W - 14, H - 60], outline=(240, 200, 110), width=4)
    logo = Image.open(os.path.join(TCG, "logo.png")).convert("RGBA").resize((300, 300), Image.LANCZOS)
    body.alpha_composite(logo, ((W - 300) // 2, 120))
    f = ImageFont.truetype(os.path.join(ROOT, "assets", "fonts", "Cinzel.ttf"), 34)
    for i, line in enumerate(["You got me", "Lobster?"]):
        tw = d.textlength(line, font=f)
        d.text(((W - tw) / 2, 430 + i * 44), line, font=f, fill=(255, 230, 150), stroke_width=3, stroke_fill=(60, 10, 20))
    mask = Image.new("L", (W, H), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, W - 1, H - 1], 18, fill=255)
    out = Image.new("RGBA", (W + 30, H + 30), (0, 0, 0, 0))
    shadow = Image.new("RGBA", (W + 30, H + 30), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle([12, 16, W + 12, H + 16], 18, fill=(0, 0, 0, 140))
    out.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(8)))
    body.putalpha(mask)
    out.alpha_composite(body, (6, 4))
    out.save(os.path.join(TCG, "pack.png"))


def box():
    W, H = 520, 420
    out = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(out)
    d.rounded_rectangle([20, 34, W - 14, H - 6], 14, fill=(0, 0, 0, 120))
    d.polygon([(10, 80), (60, 20), (W - 20, 20), (W - 60, 80)], fill=(170, 20, 60))  # lid top
    front = holo(W - 70, H - 90, (110, 8, 36), 0.25)
    out.alpha_composite(front, (10, 80))
    d = ImageDraw.Draw(out)
    d.polygon([(W - 60, 80), (W - 20, 20), (W - 20, H - 70), (W - 60, H - 10)], fill=(80, 5, 25))  # side
    d.rectangle([10, 80, W - 60, H - 10], outline=(240, 200, 110), width=6)
    d.line([(10, 80), (60, 20), (W - 20, 20), (W - 60, 80)], fill=(240, 200, 110), width=5)
    logo = Image.open(os.path.join(TCG, "logo.png")).convert("RGBA").resize((230, 230), Image.LANCZOS)
    out.alpha_composite(logo, ((W - 70 - 230) // 2 + 10, 95))
    f = ImageFont.truetype(os.path.join(ROOT, "assets", "fonts", "Cinzel.ttf"), 30)
    t = "50 PACKS"
    tw = d.textlength(t, font=f)
    d.text(((W - 70 - tw) / 2 + 10, H - 70), t, font=f, fill=(255, 230, 150), stroke_width=3, stroke_fill=(60, 10, 20))
    out.save(os.path.join(TCG, "box.png"))


if __name__ == "__main__":
    pack()
    box()
    print("PACK done")
