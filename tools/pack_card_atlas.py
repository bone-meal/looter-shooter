# Purpose: packs the card art (assets/tcg/art/<id>.jpg, 640 x 480) into atlas pages for the low-end machines
# (locked: art in atlases sized for the HD 620): 2048 x 2048 pages, 12 pictures each with 16 px of padding (no colour
# bleeds into a neighbour at small mipmaps), written as assets/tcg/atlas/page_<n>.jpg, and the map
# data/tcg/atlas.json {id: [page, x, y, w, h]}. Pages import VRAM-compressed with mipmaps (their .import files).
# Run again after the art changes: python3 tools/pack_card_atlas.py
# Dependencies: Pillow.
import json, os
from PIL import Image
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ART = os.path.join(ROOT, "assets/tcg/art")
OUT = os.path.join(ROOT, "assets/tcg/atlas")
PAGE, PAD, COLS, ROWS = 2048, 16, 3, 4
IMPORT = """[remap]

importer="texture"
type="CompressedTexture2D"

[deps]

source_file="res://assets/tcg/atlas/{name}"

[params]

compress/mode=2
compress/high_quality=false
compress/lossy_quality=0.7
mipmaps/generate=true
mipmaps/limit=-1
process/fix_alpha_border=false
detect_3d/compress_to=0
"""
ids = sorted(f[:-4] for f in os.listdir(ART) if f.endswith(".jpg"))
os.makedirs(OUT, exist_ok=True)
for old in os.listdir(OUT):
    if old.startswith("page_") and old.endswith(".jpg"):
        os.remove(os.path.join(OUT, old))
mapping, page, n = {}, None, 0
per = COLS * ROWS
for i, cid in enumerate(ids):
    if i % per == 0:
        if page is not None:
            page.save(os.path.join(OUT, "page_%d.jpg" % n), quality=92)
            n += 1
        page = Image.new("RGB", (PAGE, PAGE), (20, 20, 24))
    im = Image.open(os.path.join(ART, cid + ".jpg")).convert("RGB")
    w, h = im.size
    cell = (i % per)
    x = PAD + (cell % COLS) * (w + 2 * PAD)
    y = PAD + (cell // COLS) * (h + 2 * PAD)
    # padding = the picture's own edge colours stretched outward, so mipmaps never pick up a neighbour
    big = im.resize((w + 2 * PAD, h + 2 * PAD))
    page.paste(big, (x - PAD, y - PAD))
    page.paste(im, (x, y))
    mapping[cid] = [n, x, y, w, h]
page.save(os.path.join(OUT, "page_%d.jpg" % n), quality=92)
for k in range(n + 1):
    name = "page_%d.jpg" % k
    imp = os.path.join(OUT, name + ".import")
    if not os.path.exists(imp):
        open(imp, "w").write(IMPORT.format(name=name))
about = "The card art atlas (made by tools/pack_card_atlas.py from assets/tcg/art): card id -> [page, x, y, w, h] in assets/tcg/atlas/page_<page>.jpg. game/tcg/card_art.gd reads it."
lines = ["{", ' "version": 1,', ' "_about": %s,' % json.dumps(about), ' "pages": %d,' % (n + 1), ' "art": {']
items = list(mapping.items())
for j, (k, v) in enumerate(items):
    lines.append('  %s: %s%s' % (json.dumps(k), json.dumps(v), "," if j < len(items) - 1 else ""))
lines += [" }", "}"]
open(os.path.join(ROOT, "data/tcg/atlas.json"), "w").write("\n".join(lines) + "\n")
print(len(mapping), "pictures on", n + 1, "pages")
