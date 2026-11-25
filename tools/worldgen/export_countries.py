# Purpose: developer-time tool (polish1 F1a): cuts each country out of the grown continent (tools/worldgen/out/,
# made by continent.py) and writes its SHAPE FILE data/fantasy/countries/<id>.json: the shapes the game compiles
# into land (core/country_shape.gd): height CONTOURS (the coast is the 0 m line), RIVERS, LAKES, the crater ring,
# ZONES (outlines of each kind of land, drawn with a look from data/fantasy/world.json's regions), the BORDER WALLS
# toward the neighbours and the CROSSINGS (each names the crossing it arrives at in the next country). Everything is
# in the country's own metres (x east, z south, 0 at the middle). Hand edits belong in these files afterwards: rerun
# this only to start a country's shape over.
# Depends on: numpy, scipy, scikit-image (pip); tools/worldgen/out/continent.npz + crossings.json; plates.json.
# Run: python3 tools/worldgen/export_countries.py [country ...]
import json
import math
import os
import sys

import numpy as np
from scipy import ndimage
from skimage import measure

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
OUT_DIR = os.path.join(ROOT, "data", "fantasy", "countries")
Z = np.load(os.path.join(HERE, "out", "continent.npz"))
X = json.load(open(os.path.join(HERE, "out", "crossings.json")))
SPEC = json.load(open(os.path.join(HERE, "plates.json")))
height, owner, river, lake, biome = Z["height"], Z["owner"], Z["river"], Z["lake"], Z["biome"]
filled, acc, recv = Z["filled"], Z["acc"], Z["recv"]
BIOMES = [str(b) for b in Z["biomes"]]
IDS = [str(c) for c in Z["countries"]]
H, W = height.shape
land = height > 0
river = river & (acc > np.percentile(acc[land], 98.8))  # only the bigger rivers become rivers in a country

# country world size in km (approved by the director 2026-11-23)
SIZE_KM = {"amberfield": 3.0, "greenwald": 4.1, "brinemouth": 3.7, "sunscar": 4.5, "frostmere": 4.0, "cinderreach": 3.2, "stormcrown": 4.4, "hollow_crown": 2.8}
# which look (a region of data/fantasy/world.json: ground colours, mood, trees, gatherables) each kind of land wears
LOOK = {"farmland": "amberfield", "grassland": "amberfield", "forest": "greenwald", "taiga": "greenwald", "tundra": "frostmere", "ice": "frostmere",
    "alpine": "stormcrown", "shrubland": "sunscar", "desert": "sunscar", "salt": "sunscar", "savanna": "brinemouth", "jungle": "brinemouth",
    "swamp": "brinemouth", "volcanic": "cinderreach", "crater": "hollow_crown"}
# continent metres -> game metres: the country's relief, squeezed so mountains stay climbable at play scale
RELIEF = {"scale": 220.0, "per": 2000.0, "power": 0.8, "sea_per_m": 0.012, "sea_most": 22.0}
SPREAD_M = 220.0  # metres two crossings of one country stand apart at least
LANDING_IN = 3.0  # cells of the main land round a ferry or ship landing (no landings on spits)
CONTOURS_M = [0, 30, 70, 130, 210, 320, 460, 640, 860, 1120, 1450, 1850, 2350, 2950]
MARGIN = 0.07  # share of the world left round the country's land on each side


def game_h(h):
    h = np.asarray(h, float)
    up = RELIEF["scale"] * np.power(np.clip(h, 0, None) / RELIEF["per"], RELIEF["power"])
    down = -np.minimum(-np.clip(h, None, 0) * RELIEF["sea_per_m"], RELIEF["sea_most"])
    return np.where(h > 0, up, down)


def frame(i):
    """the country's square of the continent: (x0, y0, cells across, metres a cell)."""
    mine = owner == i
    lab, n = ndimage.label(mine)
    sizes = ndimage.sum(mine, lab, range(1, n + 1))
    body = lab == (int(np.argmax(sizes)) + 1)
    near = ndimage.distance_transform_edt(~body) < 30  # the main land and the islands close by set the frame
    ys, xs = np.nonzero(mine & near)
    cx, cy = (xs.min() + xs.max()) / 2.0, (ys.min() + ys.max()) / 2.0
    span = max(xs.max() - xs.min(), ys.max() - ys.min()) + 2
    across = span / (1.0 - 2 * MARGIN)
    size_m = SIZE_KM[IDS[i]] * 1000.0
    return cx - across / 2.0, cy - across / 2.0, across, size_m / across, size_m


def to_world(fr, col, row):
    x0, y0, across, mpc, size_m = fr
    return [round((col - x0) * mpc - size_m / 2.0, 1), round((row - y0) * mpc - size_m / 2.0, 1)]


def crop(fr, grid, pad_value):
    """the frame's piece of a grid, one sample a cell (+1 so contours close at the edge)."""
    x0, y0, across, _, _ = fr
    xa, ya = int(math.floor(x0)), int(math.floor(y0))
    n = int(math.ceil(across)) + 2
    out = np.full((n, n), pad_value, dtype=float)
    sx0, sy0 = max(xa, 0), max(ya, 0)
    sx1, sy1 = min(xa + n, W), min(ya + n, H)
    out[sy0 - ya:sy1 - ya, sx0 - xa:sx1 - xa] = grid[sy0:sy1, sx0:sx1]
    return out, xa, ya


def rings(fr, mask_or_field, level, xa, ya, tol=0.6, least=4):
    """closed outlines where a field crosses a level, in world metres."""
    out = []
    padded = np.pad(mask_or_field, 1, constant_values=float(np.min(mask_or_field)))
    for c in measure.find_contours(padded, level):
        c = measure.approximate_polygon(c, tol)
        if len(c) < least:
            continue
        out.append([to_world(fr, xa + p[1] - 1, ya + p[0] - 1) for p in c])
    return out


def export(i):
    cid = IDS[i]
    fr = frame(i)
    mpc = fr[3]
    hgrid, xa, ya = crop(fr, height, -2000.0)
    ogrid, _, _ = crop(fr, owner.astype(float), -1.0)
    shape = {"relief": RELIEF, "metres_a_cell": round(mpc, 2), "contours": []}
    smooth = ndimage.gaussian_filter(hgrid, 0.7)
    for lv in CONTOURS_M:
        gl = float(game_h(lv + 0.01)) if lv > 0 else 0.0
        polys = rings(fr, smooth, lv, xa, ya, tol=0.5 if lv == 0 else 0.8, least=4 if lv == 0 else 6)
        if polys:
            shape["contours"].append({"height": round(gl, 2), "from_m": lv, "rings": polys})
    # rivers: from each river head down the flow to the sea or a lake, inside the frame
    x0, y0, across = fr[0], fr[1], fr[2]
    inside = lambda r, c: x0 <= c < x0 + across and y0 <= r < y0 + across
    seen = np.zeros((H, W), bool)
    heads = []
    up_count = np.zeros(H * W, np.int32)
    rv = river.ravel()
    for k in np.flatnonzero(rv):
        j = recv.ravel()[k]
        if j >= 0 and rv[j]:
            up_count[j] += 1
    for k in np.flatnonzero(rv):
        r, c = divmod(int(k), W)
        if up_count[k] == 0 and inside(r, c):
            heads.append(int(k))
    heads.sort(key=lambda k: -acc.ravel()[k])
    rivers = []
    for k in heads:
        pts, widths = [], []
        while k >= 0:
            r, c = divmod(k, W)
            if not inside(r, c):
                break
            pts.append(to_world(fr, c + 0.5, r + 0.5))
            widths.append(round(float(np.clip(1.5 + np.log1p(acc.ravel()[k]) * 1.1, 2.0, 14.0)), 1))
            if seen[r, c] or not land[r, c] or lake[r, c]:
                break
            seen[r, c] = True
            k = int(recv.ravel()[k])
        if len(pts) >= 10 or (len(pts) >= 4 and widths[-1] >= 9.0):
            keep = [0] + list(range(2, len(pts) - 1, 2)) + [len(pts) - 1]
            rivers.append({"points": [pts[q] for q in keep], "width": [widths[q] for q in keep]})
    shape["rivers"] = rivers
    # lakes: outlines with their water level
    lgrid, _, _ = crop(fr, lake.astype(float), 0.0)
    fgrid, _, _ = crop(fr, filled, 0.0)
    lab, n = ndimage.label(lgrid > 0.5)
    lakes = []
    for k in range(1, n + 1):
        m = lab == k
        if m.sum() < 6:
            continue
        level = float(game_h(float(np.median(fgrid[m]))))
        for ring in rings(fr, ndimage.gaussian_filter(m.astype(float), 0.6), 0.5, xa, ya, tol=0.5):
            lakes.append({"id": "%s_lake_%d" % (cid, len(lakes) + 1), "level": round(level, 2), "ring": ring})
    shape["lakes"] = lakes
    # craters whose middle lies in the frame
    craters = []
    for c in X["craters"]:
        if inside(c["cy"], c["cx"]):
            craters.append({"id": c["id"], "pos": to_world(fr, c["cx"], c["cy"]), "radius": round(c["r"] * mpc, 1),
                "rim": round(float(game_h(c["rim_m"])) * 0.6, 1), "floor": round(float(game_h(-c["floor_m"])) * -0.25, 1)})
    shape["craters"] = craters
    # zones: outlines of each look over this country's land (and the neighbours' land seen past the walls)
    bgrid, _, _ = crop(fr, biome.astype(float), -1.0)
    zones = []
    looks = {}
    for b in np.unique(bgrid[bgrid >= 0]).astype(int):
        looks.setdefault(LOOK.get(BIOMES[b], "amberfield"), []).append(b)
    for look, bs in sorted(looks.items()):
        m = np.isin(bgrid, bs).astype(float)
        polys = rings(fr, ndimage.gaussian_filter(m, 0.8), 0.5, xa, ya, tol=0.8, least=5)
        if polys:
            zones.append({"look": look, "kinds": [BIOMES[b] for b in bs], "rings": polys})
    shape["zones"] = zones
    # border walls: this country's outline wherever another country's land lies beyond it
    mine = (ogrid == i).astype(float)
    others = (ogrid >= 0) & (ogrid != i)
    near_other = ndimage.binary_dilation(others, iterations=2)
    walls = []
    for c in measure.find_contours(np.pad(ndimage.gaussian_filter(mine, 0.6), 1), 0.5):
        run = []
        for p in c:
            r_, c_ = int(round(p[0] - 1)), int(round(p[1] - 1))
            on = 0 <= r_ < near_other.shape[0] and 0 <= c_ < near_other.shape[1] and near_other[r_, c_]
            if on:
                run.append(p)
            elif len(run) >= 3:
                walls.append(run)
                run = []
            else:
                run = []
        if len(run) >= 3:
            walls.append(run)
    shape["walls"] = [[to_world(fr, xa + p[1] - 1, ya + p[0] - 1) for p in measure.approximate_polygon(np.array(w_), 0.6)] for w_ in walls]
    # crossings: this country's end of every crossing it takes part in
    crossings = []
    picked = []
    lab_, n_lab = ndimage.label(owner == i)
    body = lab_ == (int(np.argmax(ndimage.sum(owner == i, lab_, range(1, n_lab + 1)))) + 1)  # the country's main land
    for n_, c in enumerate(X["crossings"]):
        if cid not in (c["from"], c["to"]):
            continue
        other = c["to"] if c["from"] == cid else c["from"]
        oi = IDS.index(other)
        if c["kind"] in ("ferry", "voyage"):
            ends = [c["route"][0], c["route"][-1]]
            mine_end = min(ends, key=lambda e: np.hypot(*(np.argwhere(owner == i) - [e[1], e[0]]).T).min())
            ex, ey = mine_end
        else:
            ex, ey = c["x"], c["y"]
        # stand on this country's own MAIN land (an islet is out of reach on foot), a few cells in from the border / shore
        own = np.argwhere(body)
        dist_in = ndimage.distance_transform_edt(body)
        dd = np.hypot(own[:, 0] - ey, own[:, 1] - ex) - np.minimum(dist_in[own[:, 0], own[:, 1]], 3.0) * 1.5
        if c["kind"] in ("ferry", "voyage"):  # a landing stands on solid ground, its pier reaches the water
            dd = dd + np.where(dist_in[own[:, 0], own[:, 1]] < LANDING_IN, 1e5, 0.0)
        for pr, pc in picked:  # two crossings never share a spot: each stands at least SPREAD_M from the others
            dd = dd + np.where(np.hypot(own[:, 0] - pr, own[:, 1] - pc) * fr[3] < SPREAD_M, 1e6, 0.0)
        r, col = own[int(np.argmin(dd))]
        picked.append((r, col))
        crossings.append({"id": "%s_%s_%d" % (c["from"], c["to"], n_), "to": other, "kind": c["kind"], "pos": to_world(fr, col + 0.5, r + 0.5),
            "hard": c.get("rough", 0.0) >= X.get("rough_cut", 1e9)})
    # the spawn: low, dry, gentle ground nearest the country's heart
    gy_, gx_ = np.gradient(height)
    calm = (owner == i) & land & ~lake & ~river & (height < 400) & (np.hypot(gx_, gy_) < 40)
    cy_, cx_ = np.nonzero(calm)
    hx, hy = Z["caps"][i]
    k_ = int(np.argmin((cx_ - hx) ** 2 + (cy_ - hy) ** 2)) if len(cx_) else 0
    cap = (int(cx_[k_]), int(cy_[k_])) if len(cx_) else (int(hx), int(hy))
    # snow lies above the height where the year averages -2 C at the country's latitude
    lat_n, lat_s = SPEC["latitude"]["north"], SPEC["latitude"]["south"]
    lat = float(np.mean(lat_n + (lat_s - lat_n) * np.nonzero(owner == i)[0] / (H - 1)))
    snow_m = max((29.0 - 0.5 * abs(lat)) / 0.0065, 0.0)
    country = {
        "version": 1,
        "_about": "Polish1 F1a country shape, cut from the grown continent by tools/worldgen/export_countries.py. The game compiles shape into land (core/country_shape.gd). Edit freely.",
        "id": cid, "name": cid.replace("_", " ").title(), "levels": next(c["levels"] for c in SPEC["countries"] if c["id"] == cid),
        "size": round(fr[4]), "seed": 1000 + i * 17, "sea_level": 0.0, "chunk": 50,
        "spawn": to_world(fr, cap[0] + 0.5, cap[1] + 0.5),
        "latitude": round(lat, 1), "snowline": round(max(float(game_h(snow_m)), 3.0), 1),
        "crossings": crossings, "shape": shape,
    }
    os.makedirs(OUT_DIR, exist_ok=True)
    path = os.path.join(OUT_DIR, cid + ".json")
    with open(path, "w") as f:
        f.write(compact(country))
    return path, os.path.getsize(path), len(shape["contours"]), sum(len(cn["rings"]) for cn in shape["contours"]), len(rivers), len(lakes), len(zones), len(shape["walls"]), len(crossings)


def compact(o, ind=0):
    """JSON with one ring / point list per line (readable, not one number a line)."""
    pad = " " * ind
    if isinstance(o, dict):
        items = [pad + " " + json.dumps(k) + ": " + compact(v, ind + 1).lstrip() for k, v in o.items()]
        return pad + "{\n" + ",\n".join(items) + "\n" + pad + "}"
    if isinstance(o, list) and o and all(isinstance(e, (list, int, float)) for e in o) and any(isinstance(e, list) for e in o):
        return pad + json.dumps(o, separators=(",", ":"))
    if isinstance(o, list) and o and any(isinstance(e, dict) for e in o):
        return pad + "[\n" + ",\n".join(compact(e, ind + 1) for e in o) + "\n" + pad + "]"
    return pad + json.dumps(o)


def pictures():
    """the atlas (assets/ui/atlas.jpg + data/fantasy/atlas.json: where each country's name goes) and each country's
    painted map for its crossing card (assets/ui/countries/<id>.png)."""
    from PIL import Image, ImageDraw
    land_img = Image.open(os.path.join(HERE, "out", "atlas_land.png")).convert("RGB")
    s = land_img.width / W
    arr = np.array(land_img)
    big_owner = np.kron(owner, np.ones((int(s), int(s)), np.int8)) if s == int(s) else owner
    edge = np.zeros(big_owner.shape, bool)
    for dy, dx in ((0, 1), (1, 0)):
        a_, b_ = big_owner[: big_owner.shape[0] - dy, : big_owner.shape[1] - dx], big_owner[dy:, dx:]
        edge[: edge.shape[0] - dy, : edge.shape[1] - dx] |= (a_ != b_) & (a_ >= 0) & (b_ >= 0)
    arr[edge] = (96, 30, 22)
    with_borders = Image.fromarray(arr)
    ui = os.path.join(ROOT, "assets", "ui")
    os.makedirs(os.path.join(ui, "countries"), exist_ok=True)
    with_borders.resize((1024, int(1024 * H / W)), Image.LANCZOS).save(os.path.join(ui, "atlas.jpg"), quality=88)
    names = {}
    for i, cid in enumerate(IDS):
        core = ndimage.distance_transform_edt(owner == i)
        y, x = np.unravel_index(np.argmax(core), core.shape)
        names[cid] = {"x": round(float(x) / W, 4), "y": round(float(y) / H, 4), "levels": next(c["levels"] for c in SPEC["countries"] if c["id"] == cid)}
        x0, y0, across, _, _ = frame(i)
        box = (int(x0 * s), int(y0 * s), int((x0 + across) * s), int((y0 + across) * s))
        pic = Image.new("RGB", (box[2] - box[0], box[3] - box[1]), (40, 70, 110))
        pic.paste(with_borders.crop((max(box[0], 0), max(box[1], 0), min(box[2], with_borders.width), min(box[3], with_borders.height))), (max(-box[0], 0), max(-box[1], 0)))
        dim = np.array(pic).astype(float)
        mine = np.kron((owner == i).astype(np.uint8), np.ones((int(s), int(s)), np.uint8))
        sub = np.zeros(dim.shape[:2], bool)
        ys0, xs0 = max(box[1], 0), max(box[0], 0)
        piece = mine[ys0:min(box[3], mine.shape[0]), xs0:min(box[2], mine.shape[1])]
        sub[ys0 - box[1]:ys0 - box[1] + piece.shape[0], xs0 - box[0]:xs0 - box[0] + piece.shape[1]] = piece > 0
        dim[~sub] = dim[~sub] * 0.55 + np.array([20, 24, 34]) * 0.45  # the neighbours fade, the country stands out
        Image.fromarray(dim.astype(np.uint8)).resize((512, 512), Image.LANCZOS).save(os.path.join(ui, "countries", cid + ".png"))
    with open(os.path.join(ROOT, "data", "fantasy", "atlas.json"), "w") as f:
        json.dump({"_about": "Polish1 F1a: where each country's name sits on assets/ui/atlas.jpg (shares of its width / height). Made by tools/worldgen/export_countries.py.", "countries": names}, f, indent=1)


if __name__ == "__main__":
    # matching crossing ids: both ends of a crossing share its id; rough cut = the atlas's red mark
    land_rough = [c.get("rough", 0.0) for c in X["crossings"] if c["kind"] not in ("ferry", "voyage")]
    X["rough_cut"] = float(np.percentile(land_rough, 60)) if land_rough else 1e9
    want = sys.argv[1:] or IDS
    for cid in want:
        print(cid, export(IDS.index(cid)))
    pictures()
