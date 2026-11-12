# Purpose: developer-time script. Turns the white gun shapes of tools/chalk_shot.tscn (tools/shots/chalk_<body>.png)
# into chalk outlines on one sheet, assets/ui/chalk_guns.png (white chalk with a rough, broken line and a faint smear
# inside), and writes data/chalk_guns.json (which cell is which gun). The wall buys draw a cell on their board.
# Run: python3 tools/make_chalk_guns.py   (from the project folder, after the chalk_shot scene; needs numpy + Pillow)
import json
import os

import numpy as np
from PIL import Image, ImageFilter

HERE = os.path.dirname(__file__)
CELL = (512, 256)
COLUMNS = 2
LINE = 4  # half the width of the chalk line in pixels
MARGIN = 26  # pixels kept free round every outline


def outline(shape, rng):
    solid = shape.point(lambda v: 255 if v > 96 else 0)
    grown = solid.filter(ImageFilter.MaxFilter(2 * LINE + 1))
    shrunk = solid.filter(ImageFilter.MinFilter(2 * LINE + 1))
    ring = np.asarray(grown, dtype=np.float32) - np.asarray(shrunk, dtype=np.float32)
    ring = np.asarray(Image.fromarray(ring.astype(np.uint8)).filter(ImageFilter.GaussianBlur(1.2)), dtype=np.float32) / 255.0
    inside = np.asarray(shrunk, dtype=np.float32) / 255.0
    h, w = ring.shape
    grain = rng.random((h, w)).astype(np.float32)  # chalk skips over the board's grain
    coarse = np.asarray(Image.fromarray((rng.random((h // 8, w // 8)) * 255).astype(np.uint8)).resize((w, h), Image.BILINEAR), dtype=np.float32) / 255.0
    line = ring * (0.55 + 0.45 * coarse) * np.where(grain > 0.18, 1.0, 0.35)
    smear = inside * 0.07 * (0.4 + 0.6 * coarse)
    return np.clip(line + smear, 0.0, 1.0)


def main():
    rng = np.random.default_rng(7)
    bodies = list(json.load(open(os.path.join(HERE, "..", "data", "weapons.json")))["weapons"].keys())
    rows = (len(bodies) + COLUMNS - 1) // COLUMNS
    sheet = np.zeros((rows * CELL[1], COLUMNS * CELL[0], 4), dtype=np.uint8)
    sheet[..., 0] = 246
    sheet[..., 1] = 243
    sheet[..., 2] = 232
    cells = {}
    for i, body in enumerate(bodies):
        shot = Image.open(os.path.join(HERE, "shots", "chalk_%s.png" % body)).convert("L")
        shot = shot.crop(shot.point(lambda v: 255 if v > 96 else 0).getbbox())  # just the gun ...
        fit = min((CELL[0] - 2 * MARGIN) / shot.width, (CELL[1] - 2 * MARGIN) / shot.height)
        shot = shot.resize((max(int(shot.width * fit), 1), max(int(shot.height * fit), 1)), Image.LANCZOS)
        shape = Image.new("L", CELL, 0)  # ... as large as its cell allows, in the middle of it
        shape.paste(shot, ((CELL[0] - shot.width) // 2, (CELL[1] - shot.height) // 2))
        x = (i % COLUMNS) * CELL[0]
        y = (i // COLUMNS) * CELL[1]
        sheet[y:y + CELL[1], x:x + CELL[0], 3] = (outline(shape, rng) * 255).astype(np.uint8)
        cells[body] = i
    Image.fromarray(sheet, "RGBA").save(os.path.join(HERE, "..", "assets", "ui", "chalk_guns.png"))
    json.dump({"version": 1, "_about": "The chalk outlines of the wall buys (assets/ui/chalk_guns.png, made by tools/make_chalk_guns.py from tools/chalk_shot.tscn): cell = size of one outline in pixels, columns = outlines per row, cells = gun body -> which cell (counted along the rows from 0).",
               "cell": list(CELL), "columns": COLUMNS, "rows": rows, "cells": cells}, open(os.path.join(HERE, "..", "data", "chalk_guns.json"), "w"), indent=1)
    print("chalk_guns.png", sheet.shape, cells)


main()
