# Purpose: developer-time script. For every surface in data/surfaces.json marked "grain" it writes a grey copy of the
# texture set's colour map, assets/cc0/textures/<set>/<set>_grain_1k.jpg, brightened or darkened so that its average
# (in linear light) is exactly one half. The game multiplies it by two and by the model's own colour
# (game/surface_library.gd), so a part keeps the colour its model gave it and the texture only adds the grain.
# Run: python3 tools/make_grain.py   (from the project folder; needs pip packages numpy, pillow)
import json
import os

import numpy as np
from PIL import Image

ROOT = os.path.join(os.path.dirname(__file__), "..")


def main():
    surfaces = json.load(open(os.path.join(ROOT, "data", "surfaces.json")))["surfaces"]
    for set_id in sorted({s["set"] for s in surfaces if s.get("grain")}):
        folder = os.path.join(ROOT, "assets", "cc0", "textures", set_id)
        srgb = np.asarray(Image.open(os.path.join(folder, set_id + "_diff_1k.jpg")).convert("RGB")).astype(np.float64) / 255.0
        lin = np.where(srgb <= 0.04045, srgb / 12.92, ((srgb + 0.055) / 1.055) ** 2.4)
        lum = lin @ np.array([0.2126, 0.7152, 0.0722])
        lum = np.clip(lum * (0.5 / lum.mean()), 0.0, 1.0)
        lum = np.clip(lum * (0.5 / lum.mean()), 0.0, 1.0)  # once more: clipping the brightest spots lowered the average
        out = np.where(lum <= 0.0031308, lum * 12.92, 1.055 * lum ** (1 / 2.4) - 0.055)
        Image.fromarray((out * 255.0 + 0.5).astype(np.uint8), "L").save(os.path.join(folder, set_id + "_grain_1k.jpg"), quality=90)
        print(set_id, "average", round(float(lum.mean()), 3))


if __name__ == "__main__":
    main()
