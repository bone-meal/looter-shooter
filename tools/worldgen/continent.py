# Purpose: developer-time WORLD GENERATOR for Aurelind's continent (polish1 F1, diary/DESIGN_CONTINENT.md). The land
# comes out of its history instead of being drawn: (1) TECTONIC PLATES from tools/worldgen/plates.json drift; where they
# close on each other they fold up ranges (continent on continent: the highest; sea floor sliding under a continent: a
# coastal range with volcanoes and a deep trench offshore), where they part a rift valley or a gulf opens, where they
# slide past a fault valley. (2) METEOR IMPACTS leave rimmed bowls (the great old one: the Hollow Crown). (3) RAIN runs
# downhill into rivers (priority flood), fills lakes and cuts valleys. (4) CLIMATE: the north edge is near the pole, the
# south edge just past the equator; heat falls with latitude and height; winds by latitude band (polar easterlies,
# westerlies, trade winds) carry sea air inland and rain it out on rising ground, leaving rain shadows. (5) BIOMES from
# heat and rain. (6) COUNTRIES grow from their capitals across the land, slowed by mountains, rivers and sea, toward
# target sizes, so borders follow ridges and rivers and the countries differ in size and shape.
# Depends on: numpy, scipy, pillow (pip), plates.json, assets/fonts. Output: tools/worldgen/out/ (atlas pictures, grids).
# Run: python3 tools/worldgen/continent.py [seed]
import heapq
import json
import math
import os
import sys

import numpy as np
from scipy import ndimage

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
OUT = os.path.join(HERE, "out")
SEED = int(sys.argv[1]) if len(sys.argv) > 1 else 7
SPEC = json.load(open(os.path.join(HERE, "plates.json")))
W, H = SPEC.get("size", [560, 720])  # cells; north is row 0
rng = np.random.default_rng(SEED)
yy, xx = np.mgrid[0:H, 0:W].astype(float)
LAT = SPEC["latitude"]["north"] + (SPEC["latitude"]["south"] - SPEC["latitude"]["north"]) * yy / (H - 1)


def fbm(octaves=6, base=4.0, persistence=0.5, seed_off=0):
    """Smooth fractal noise, roughly -1..1."""
    out = np.zeros((H, W))
    amp, total = 1.0, 0.0
    g = np.random.default_rng(SEED * 31 + seed_off)
    for o in range(octaves):
        ny = int(base * 2 ** o) + 3
        nx = int(base * 2 ** o * W / H) + 3
        grid = g.standard_normal((ny, nx))
        z = ndimage.zoom(grid, (H / (ny - 2), W / (nx - 2)), order=3)[:H, :W]
        out += z * amp
        total += amp
        amp *= persistence
    out /= total
    return out / (np.percentile(np.abs(out), 99) + 1e-9)


def smoothstep(e0, e1, v):
    t = np.clip((v - e0) / (e1 - e0), 0, 1)
    return t * t * (3 - 2 * t)


# ---------- 1. plates ----------
P = SPEC["plates"]
NP = len(P)
cen = np.array([[p["x"] * W, p["y"] * H] for p in P])
cont = np.array([p["continental"] for p in P])
vel = np.array([p["move"] for p in P], float)
wx = fbm(5, 1.6, 0.5, 1) * 95 + fbm(4, 6, 0.5, 21) * 22
wy = fbm(5, 1.6, 0.5, 2) * 95 + fbm(4, 6, 0.5, 22) * 22
d2 = ((xx + wx)[..., None] - cen[:, 0]) ** 2 + ((yy + wy)[..., None] - cen[:, 1]) ** 2
plate = np.argmin(d2, axis=2)

# boundary pixels by kind, with the strength of the push
kinds = {k: np.zeros((H, W)) for k in ("collide", "subduct", "rift", "fault", "island_arc")}
for dy, dx in ((0, 1), (1, 0)):
    a = plate[: H - dy, : W - dx]
    b = plate[dy:, dx:]
    m = a != b
    ys, xs = np.nonzero(m)
    pa, pb = a[m], b[m]
    close = (vel[pa] - vel[pb]) @ np.array([dx, dy], float)
    ca, cb = cont[pa], cont[pb]
    for key, sel in (
        ("collide", (close > 0.15) & ca & cb),
        ("subduct", (close > 0.15) & (ca != cb)),
        ("rift", (close < -0.15) & ca & cb),
        ("fault", np.abs(close) <= 0.15),
        ("island_arc", (close > 0.3) & ~ca & ~cb),  # sea floor under sea floor: a curve of volcanic islands
    ):
        np.maximum.at(kinds[key], (ys[sel], xs[sel]), np.abs(close[sel]))


def reach(key):
    """distance (cells) to the nearest boundary of a kind, and that boundary's strength."""
    k = kinds[key]
    if not (k > 0).any():
        return np.full((H, W), 1e9), np.zeros((H, W))
    d = ndimage.distance_transform_edt(k <= 0)
    # strength blends smoothly along the boundary (the nearest pixel alone would leave cliffs where segments change)
    s = ndimage.gaussian_filter(k, 22) / (ndimage.gaussian_filter((k > 0).astype(float), 22) + 1e-6)
    return d, s


# the crust: land plates stand high, sea floor low; soft shelves and a ragged coast
crust = ndimage.gaussian_filter(np.where(cont[plate], 1.0, -1.0), 14)
coast_noise = fbm(7, 3, 0.58, 5)
landness = crust + coast_noise * 0.75 + fbm(3, 1.5, 0.5, 6) * 0.35


def seg_dist(points):
    """distance (cells) from every cell to a polyline given in map shares, and how far along it (0..1) the nearest point is."""
    pts = [(px * W, py * H) for px, py in points]
    best = np.full((H, W), 1e9)
    along = np.zeros((H, W))
    total = sum(math.hypot(b[0] - a[0], b[1] - a[1]) for a, b in zip(pts, pts[1:])) or 1.0
    run = 0.0
    for a, b in zip(pts, pts[1:]):
        vx, vy = b[0] - a[0], b[1] - a[1]
        ln2 = vx * vx + vy * vy or 1.0
        tt = np.clip(((qx - a[0]) * vx + (qy - a[1]) * vy) / ln2, 0, 1)
        dd = np.hypot(qx - a[0] - tt * vx, qy - a[1] - tt * vy)
        closer = dd < best
        best = np.where(closer, dd, best)
        along = np.where(closer, (run + tt * math.sqrt(ln2)) / total, along)
        run += math.sqrt(ln2)
    return best, along


# PENINSULAS (plates.json): land pushed out along a line (bent by noise), narrowing to its tip, its edges ragged
rag = fbm(6, 8, 0.55, 30)
lumps = fbm(4, 5, 0.5, 35)
spine = np.zeros((H, W))  # a peninsula's backbone of hills
qx = xx + fbm(4, 4, 0.5, 33) * 22
qy = yy + fbm(4, 4, 0.5, 34) * 22
for pen in SPEC.get("peninsulas", []):
    dd, al = seg_dist(pen["points"])
    wdt = pen["width"] * (1.0 - 0.45 * al) * (1.0 + 0.4 * rag)
    wdt *= 1.0 + 0.6 * lumps  # bulges and necks along its length
    core = np.exp(-(dd / np.maximum(wdt, 1.0)) ** 2)
    landness += 2.6 * core * (1.0 + 0.9 * coast_noise)
    spine = np.maximum(spine, core * smoothstep(0.15, 0.55, al))  # hills toward the tip, not on the mainland it leaves
# ISLAND CHAINS (plates.json; hotspot trails and archipelagos): a string of rises, larger toward the start
for ch in SPEC.get("islands", []):
    pts = [(px * W, py * H) for px, py in ch["points"]]
    g = np.random.default_rng(SEED * 7 + len(ch["id"]))
    for k in range(ch["count"]):
        f = k / max(ch["count"] - 1, 1)
        seg = min(int(f * (len(pts) - 1)), len(pts) - 2)
        lf = f * (len(pts) - 1) - seg
        ix = pts[seg][0] + (pts[seg + 1][0] - pts[seg][0]) * lf + g.normal(0, ch["r"] * 0.8)
        iy = pts[seg][1] + (pts[seg + 1][1] - pts[seg][1]) * lf + g.normal(0, ch["r"] * 0.8)
        r = ch["r"] * (1.25 - 0.6 * f) * g.uniform(0.6, 1.3)
        landness += 2.4 * np.exp(-((np.hypot(xx - ix, yy - iy) * (1 + 0.3 * rag)) / r) ** 2)
# shelf islets: scattered rocks and isles on the shallow sea near the coasts
isle = fbm(5, 12, 0.5, 31)
landness += 0.9 * np.clip(isle - 0.5, 0, None) * smoothstep(-1.0, -0.4, crust) * (crust < 0.2)
ridged = np.clip(1.0 - np.abs(fbm(7, 5, 0.55, 3)), 0, 1)
ridged2 = np.clip(1.0 - np.abs(fbm(6, 9, 0.5, 13)), 0, 1)
edge = np.minimum.reduce([xx, W - 1 - xx, yy, H - 1 - yy]) / 45.0
landness -= (1.0 - smoothstep(0, 1, edge)) * 2.5
# the coast is set by the crust first (the chosen share of the map is land); ranges and rifts then raise and cut it
shore = landness - np.quantile(landness, 1.0 - SPEC["land_share"])
height = np.where(shore > 0, 15.0 + shore * 300.0, shore * 1800.0)

d, s = reach("collide")  # the great fold ranges
height += 3000.0 * np.clip(s, 0, 1.2) * np.exp(-(d / 38.0) ** 2) * (0.35 + 0.65 * ridged ** 2.2) * smoothstep(-0.6, 0.2, landness)
d, s = reach("subduct")  # coastal range on the land side, volcanoes, trench offshore
landside = crust > 0
arc = np.exp(-((d - 16.0) / 11.0) ** 2) * landside
height += 1900.0 * np.clip(s, 0, 1.2) * arc * (0.4 + 0.6 * ridged2 ** 2)
peaks = np.clip(fbm(4, 18, 0.45, 12), 0, None) ** 2.5
volcanic = arc * np.clip(s, 0, 1.2) * smoothstep(0.05, 0.4, peaks + arc * 0.15)
height += 2200.0 * volcanic * peaks
height -= 1600.0 * np.exp(-(d / 7.0) ** 2) * ~landside
d, s = reach("rift")  # rift valley / gulf with raised shoulders
height += -900.0 * np.clip(s, 0, 1.2) * np.exp(-(d / 11.0) ** 2) + 320.0 * np.clip(s, 0, 1.2) * np.exp(-((d - 20.0) / 8.0) ** 2)
height += spine ** 2 * 650.0 * (0.3 + 0.7 * ridged ** 2)  # hills down the peninsulas
d, s = reach("island_arc")  # volcanic islands rise from the sea floor along the arc
height += np.clip(s, 0, 1.2) * np.exp(-((d - 6.0) / 6.0) ** 2) * peaks * 9000.0 * (crust < 0)
d, s = reach("fault")
height -= 70.0 * np.exp(-(d / 6.0) ** 2) * (crust > 0)

# ---------- 2. meteor impacts ----------
CR = SPEC["craters"]
for c in CR:
    cx, cy, r = c["x"] * W, c["y"] * H, float(c["r"])
    wob = 1.0 + 0.25 * fbm(4, 10, 0.5, 40 + len(c["id"]))
    rr = np.hypot(xx - cx, yy - cy) / r * wob
    fresh = 1.0 - 0.55 * c["age"]
    rim = np.exp(-((rr - 1.0) / 0.17) ** 2) * c["rim_m"] * (0.55 + 0.45 * ridged)
    ejecta = np.exp(-((rr - 1.0) / 0.9) ** 2) * (rr > 1) * c["rim_m"] * 0.15
    bowl = np.clip(1.0 - rr, 0, 1) ** 0.6 * c["floor_m"]
    # the floor sits below the plain around it but the land under it keeps its old height in the middle
    height += (rim + ejecta) * fresh + bowl * fresh
    c["cx"], c["cy"] = cx, cy

height += fbm(8, 6, 0.55, 4) * 150.0 * smoothstep(-0.05, 0.25, shore)
land = height > 0
lab, n = ndimage.label(land)
sizes = ndimage.sum(land, lab, range(1, n + 1))
keep = np.zeros(n + 1, bool)
keep[1:] = sizes > 10
land = keep[lab]
height = np.where(land, np.maximum(height, 1.0), np.minimum(height, -1.0))

# ---------- 3. climate: heat, winds, rain ----------
temp = 27.0 - 0.5 * np.abs(LAT) - 0.0065 * np.clip(height, 0, None)
east_blow = smoothstep(31, 36, LAT) * (1 - smoothstep(60, 65, LAT))  # westerlies blow east; trades and polar winds west


def rain_pass(cols):
    m = np.ones(H)
    prev = np.zeros(H)
    out = np.zeros((H, W))
    for c in cols:
        h = height[:, c]
        sea = h <= 0
        rise = np.clip(h - prev, 0, None)
        rain = np.minimum(m * (0.0035 + rise * 0.0028), m * 0.5) * ~sea
        out[:, c] = (m * 0.7 + rain * 25.0) * ~sea
        m = np.where(sea, np.minimum(1.0, m + 0.08), m - rain)
        prev = np.where(sea, 0.0, h)
    return out


wet = east_blow * rain_pass(range(W)) + (1 - east_blow) * rain_pass(range(W - 1, -1, -1))
wet = ndimage.gaussian_filter(wet, (9, 4))
# the planet's belts: rainy equator, dry horse latitudes, rainy westerlies, dry pole
belt = 1.0 + 0.9 * np.exp(-((LAT - 2.0) / 9.0) ** 2) - 0.85 * np.exp(-((LAT - 17.0) / 8.0) ** 2) + 0.2 * np.exp(-((LAT - 50.0) / 9.0) ** 2) - 0.45 * smoothstep(60, 70, LAT)
rain = np.zeros((H, W))
v = (wet * belt)[land]
rain[land] = np.argsort(np.argsort(v)) / max(len(v) - 1, 1)  # 0 driest land .. 1 wettest

# ---------- 4. water: priority flood from the sea, rivers, lakes ----------
filled = height.copy()
recv = np.full(H * W, -1, np.int64)
seen = ~land.copy()
order = []
heap = []
coastal_sea = ~land & ndimage.binary_dilation(land)
for i in np.flatnonzero(coastal_sea):
    heap.append((0.0, int(i)))
heapq.heapify(heap)
fl = filled.ravel()
jitter = rng.uniform(0, 0.8, H * W)
sn = seen.ravel()
NB = ((-1, -1), (-1, 0), (-1, 1), (0, -1), (0, 1), (1, -1), (1, 0), (1, 1))
while heap:
    h0, i = heapq.heappop(heap)
    y, x = divmod(i, W)
    for dy, dx in NB:
        y2, x2 = y + dy, x + dx
        if 0 <= y2 < H and 0 <= x2 < W:
            j = y2 * W + x2
            if not sn[j]:
                sn[j] = True
                if fl[j] < h0 + 0.01:
                    fl[j] = h0 + 0.01 + jitter[j]  # a whisper of slope so water meanders over flats
                recv[j] = i
                order.append(j)
                heapq.heappush(heap, (fl[j], j))
filled = fl.reshape(H, W)
acc = (rain.ravel() + 0.02).copy()
for j in reversed(order):
    if recv[j] >= 0:
        acc[recv[j]] += acc[j]
acc = acc.reshape(H, W)
hollow = land & (filled - height > 18.0)
lake = hollow & (rain > 0.45)
crown_r = np.hypot(xx - CR[0]["cx"], yy - CR[0]["cy"]) / CR[0]["r"]
lake &= ~((crown_r > 0.3) & (crown_r < 1.3))  # the crown's floor drains through its breach; only a small tarn at the centre
lab, n = ndimage.label(lake)
sizes = ndimage.sum(lake, lab, range(1, n + 1))
keep = np.zeros(n + 1, bool)
keep[1:] = sizes > 25
lake = keep[lab]
depth = filled - height
lab, n = ndimage.label(lake)
for k in range(1, n + 1):  # a big flooded basin keeps water only in its deeper half (it has had time to drain)
    m = lab == k
    if m.sum() > 1200:
        lake &= ~(m & (depth < depth[m].max() * 0.55))
river = land & ~lake & (acc > np.percentile(acc[land], 97.2))
pooled = filled - height > 1.5  # water standing on a filled flat, not running in a channel
height = np.where(river, height - np.clip(np.log1p(acc) * 6.0, 0, 60), height)
height = np.where(land, np.maximum(height, 0.5), height)

# ---------- 5. biomes ----------
BIOMES = [  # id, colour, plain-words
    ("ice", (236, 241, 247), "ice and snowfields"), ("tundra", (174, 176, 152), "tundra"), ("taiga", (74, 102, 82), "pine taiga"),
    ("alpine", (150, 144, 136), "bare high rock"), ("forest", (76, 124, 66), "broadleaf forest"), ("grassland", (172, 184, 100), "grassland"),
    ("farmland", (214, 196, 112), "wheat country"), ("shrubland", (168, 156, 104), "dry scrub"), ("desert", (230, 200, 142), "sand desert"),
    ("savanna", (196, 180, 92), "savanna"), ("jungle", (36, 104, 50), "jungle"), ("swamp", (84, 108, 78), "swamp and mangrove"),
    ("volcanic", (86, 66, 62), "ash and lava"), ("crater", (140, 132, 150), "crater floor"), ("salt", (236, 228, 214), "salt pans"),
]
BI = {b[0]: i for i, b in enumerate(BIOMES)}
T, R, Hm = temp, rain, height
biome = np.full((H, W), BI["grassland"], np.int16)


def put(mask, name):
    biome[mask & land] = BI[name]


put(R > 0.62, "forest")
put((R < 0.35), "shrubland")
put((T < 5) & (R > 0.3), "taiga")
put((T < 5) & (R <= 0.3), "tundra")
put(T < -1, "tundra")
put(T < -6, "ice")
put((T > 17) & (R < 0.32), "desert")
put((T > 19) & (R >= 0.32) & (R < 0.7), "savanna")
put((T > 21) & (R >= 0.7), "jungle")
put((T >= 8) & (T <= 19) & (R >= 0.3) & (R <= 0.82) & (Hm < 450), "farmland")
put((Hm > 1400) & (T > -6), "alpine")
put((Hm > 1400) & (T < -3), "ice")
put((Hm < 25) & (R > 0.8) & (T > 8), "swamp")
put((volcanic > 0.1) & (Hm > 150), "volcanic")
hc = CR[0]
in_crown = np.hypot(xx - hc["cx"], yy - hc["cy"]) < hc["r"] * 0.78
put(in_crown, "crater")
put(hollow & ~lake & (rain <= 0.45) & ~in_crown & (T > 12), "salt")  # cold dry hollows stay tundra / scrub

# ---------- 6. countries ----------
COUNTRIES = [(c["id"], c["levels"], c["x"] * W, c["y"] * H, c["share"], tuple(c["colour"])) for c in SPEC["countries"]]
NC = len(COUNTRIES)
caps = []  # each heart snaps to the nearest dry land, off the water
dry = land & ~lake & ~river
dry_idx = ndimage.distance_transform_edt(~dry, return_distances=False, return_indices=True)
for c in COUNTRIES:
    x, y = int(min(max(c[2], 0), W - 1)), int(min(max(c[3], 0), H - 1))
    caps.append((int(dry_idx[1][y, x]), int(dry_idx[0][y, x])))

gy, gx = np.gradient(height / 25.0)
slope = np.hypot(gx, gy)
step_cost = (1.0 + slope * 6.0 + np.clip(height, 0, None) / 700.0 + river * 8.0 + lake * 30.0).ravel()
landf = land.ravel()


def grow(weights):
    owner = np.full(H * W, -1, np.int16)
    best = np.full(H * W, np.inf)
    heap = []
    for i, (x, y) in enumerate(caps):
        k = y * W + x
        best[k] = 0.0
        heap.append((0.0, i, k))
    heapq.heapify(heap)
    while heap:
        dd, i, k = heapq.heappop(heap)
        if owner[k] != -1:
            continue
        owner[k] = i
        y, x = divmod(k, W)
        for y2, x2 in ((y - 1, x), (y + 1, x), (y, x - 1), (y, x + 1)):
            if 0 <= y2 < H and 0 <= x2 < W:
                j = y2 * W + x2
                if landf[j] and owner[j] == -1:
                    nd = dd + step_cost[j] / weights[i]
                    if nd < best[j]:
                        best[j] = nd
                        heapq.heappush(heap, (nd, i, j))
    return owner.reshape(H, W)


weights = np.ones(NC)
target = np.array([c[4] for c in COUNTRIES])
target /= target.sum()
for it in range(7):
    owner = grow(weights)
    got = np.array([(owner == i).sum() for i in range(NC)], float)
    got /= max(got.sum(), 1)
    weights *= np.clip((target / np.maximum(got, 1e-4)) ** 0.5, 0.6, 1.7)
far = land & (owner < 0)  # islands no road reaches: each whole island goes to the country nearest to it
if far.any():
    idx = ndimage.distance_transform_edt(owner < 0, return_distances=False, return_indices=True)
    near = owner[idx[0], idx[1]]
    lab_f, n_f = ndimage.label(far)
    for k in range(1, n_f + 1):
        m = lab_f == k
        owner[m] = np.bincount(near[m]).argmax()
owner = np.where(land, owner, -1)

# ---------- 7. crossings ----------
crossings = []
for i in range(NC):
    for j in range(i + 1, NC):
        a, b = owner == i, owner == j
        border = (a & ndimage.binary_dilation(b)) | (b & ndimage.binary_dilation(a))
        if border.sum() < 6:
            continue
        hi, lo = (i, j) if i > j else (j, i)  # the later country is the hard side
        score = np.where(border, slope * 25.0 + np.clip(height, 0, None) / 400.0 + river * 3.0, np.inf)
        picks = []
        for _ in range(1 + int(border.sum() > 160)):
            k = int(np.argmin(score))
            if not np.isfinite(score.ravel()[k]):
                break
            y, x = divmod(k, W)
            picks.append((x, y))
            score[np.hypot(xx - x, yy - y) < 60] = np.inf
        for x, y in picks:
            ring = (np.hypot(xx - x, yy - y) < 18) & (owner == hi)
            rough = float(slope[ring].mean() if ring.any() else 0) * 10 + float(height[ring].mean() if ring.any() else 0) / 500
            kind = "pass" if height[y, x] > 700 else ("ford" if (river & (np.hypot(xx - x, yy - y) < 4)).any() else "road")
            crossings.append({"from": COUNTRIES[lo][0], "to": COUNTRIES[hi][0], "x": x, "y": y, "kind": kind, "rough": round(rough, 2), "height_m": int(height[y, x])})

# sea crossings: neighbours across a strait with no land border take a ferry; voyages in plates.json sail further
from collections import deque


def sea_route(i, j):
    """shortest way over water from country i's shore to country j's shore: a list of (x, y) cells."""
    sea_ok = ~land
    start = (owner == i) & ndimage.binary_dilation(sea_ok)
    goal = (owner == j) & ndimage.binary_dilation(sea_ok)
    prev = np.full(H * W, -2, np.int64)
    q = deque()
    for k in np.flatnonzero(start):
        prev[k] = -1
        q.append(int(k))
    gf = goal.ravel()
    sf = sea_ok.ravel()
    while q:
        k = q.popleft()
        if gf[k]:
            path = []
            while k >= 0:
                y, x = divmod(k, W)
                path.append((int(x), int(y)))
                k = int(prev[k])
            path = path[::-1]
            pulled = [path[0]]  # pull the grid path straight wherever the water allows
            a_ = 0
            while a_ < len(path) - 1:
                b_ = len(path) - 1
                while b_ > a_ + 1:
                    (x1, y1), (x2, y2) = path[a_], path[b_]
                    n_ = max(abs(x2 - x1), abs(y2 - y1))
                    ok = all(sf[int(round(y1 + (y2 - y1) * s_ / n_)) * W + int(round(x1 + (x2 - x1) * s_ / n_))] or gf[int(round(y1 + (y2 - y1) * s_ / n_)) * W + int(round(x1 + (x2 - x1) * s_ / n_))] for s_ in range(1, n_))
                    if ok:
                        break
                    b_ -= 1
                pulled.append(path[b_])
                a_ = b_
            return pulled
        y, x = divmod(k, W)
        for y2, x2 in ((y - 1, x), (y + 1, x), (y, x - 1), (y, x + 1)):
            if 0 <= y2 < H and 0 <= x2 < W:
                n2 = y2 * W + x2
                if prev[n2] == -2 and (sf[n2] or gf[n2]):
                    prev[n2] = k
                    q.append(n2)
    return []


linked = {(c["from"], c["to"]) for c in crossings} | {(c["to"], c["from"]) for c in crossings}
ids = [c[0] for c in COUNTRIES]
wanted = [(ids.index(v["from"]), ids.index(v["to"]), "voyage") for v in SPEC.get("voyages", []) if (v["from"], v["to"]) not in linked]
for i in range(NC):
    for j in range(i + 1, NC):
        if (ids[i], ids[j]) not in linked:
            wanted.append((i, j, "ferry"))
for i, j, kind in wanted:
    path = sea_route(i, j)
    if not path:
        continue
    length = sum(math.hypot(b_[0] - a_[0], b_[1] - a_[1]) for a_, b_ in zip(path, path[1:]))
    if kind == "ferry" and length > 120:
        continue
    x, y = path[len(path) // 2] if len(path) > 2 else ((path[0][0] + path[-1][0]) // 2, (path[0][1] + path[-1][1]) // 2)
    hi, lo = (i, j) if i > j else (j, i)
    crossings.append({"from": ids[lo], "to": ids[hi], "x": int(x), "y": int(y), "kind": kind, "rough": 0.0, "height_m": 0, "route": [list(p_) for p_ in path]})

# ---------- 8. pictures ----------
from PIL import Image, ImageDraw, ImageFont

os.makedirs(OUT, exist_ok=True)
FD = os.path.join(ROOT, "assets", "fonts")
F_BIG = ImageFont.truetype(os.path.join(FD, "Cinzel.ttf"), 22)
F_MED = ImageFont.truetype(os.path.join(FD, "Alegreya.ttf"), 17)
F_SM = ImageFont.truetype(os.path.join(FD, "Alegreya-Italic.ttf"), 14)
S = 2  # atlas scale

lgy, lgx = np.gradient(np.where(land, height, 0) / 25.0)
shade = np.clip(0.82 + (-lgx * 0.6 - lgy * 0.75) * 0.9, 0.45, 1.3)
depth = np.clip(-height / 2500.0, 0, 1)
sea_rgb = np.stack([70 - depth * 40, 118 - depth * 60, 158 - depth * 50], -1)
sea_rgb[(height > -180) & ~land] = (104, 156, 182)
bio_rgb = np.array([b[1] for b in BIOMES], float)[biome]
base_rgb = np.where(land[..., None], bio_rgb * shade[..., None], sea_rgb)
water = (river | lake) & land
base_rgb[lake] = (78, 128, 176)


def img(a):
    return Image.fromarray(np.clip(a, 0, 255).astype(np.uint8))


def border_mask(o):
    bm = np.zeros((H, W), bool)
    for dy, dx in ((0, 1), (1, 0)):
        diff = (o[: H - dy, : W - dx] != o[dy:, dx:]) & (o[: H - dy, : W - dx] >= 0) & (o[dy:, dx:] >= 0)
        bm[: H - dy, : W - dx] |= diff
    return bm


def draw_rivers(d, scale):
    rr = np.flatnonzero((river & ~pooled).ravel())  # not across flooded flats
    for k in rr:
        j = recv[k]
        if j < 0:
            continue
        y, x = divmod(k, W)
        y2, x2 = divmod(j, W)
        wdt = 1 + int(np.log1p(acc.ravel()[k]) > 6.2) + int(np.log1p(acc.ravel()[k]) > 7.4)
        d.line([(x * scale + scale / 2, y * scale + scale / 2), (x2 * scale + scale / 2, y2 * scale + scale / 2)], fill=(66, 112, 168), width=wdt)


rough_cut = np.percentile([c["rough"] for c in crossings if c["kind"] not in ("ferry", "voyage")], 60) if crossings else 0
marks = []
for lm in SPEC.get("landmarks", []):  # snap to the owning country's shore
    ci = [c[0] for c in COUNTRIES].index(lm["country"])
    shore_m = (owner == ci) & ndimage.binary_dilation(~land, iterations=2)
    sy, sx = np.nonzero(shore_m)
    k = int(np.argmin((sx - lm["x"] * W) ** 2 + (sy - lm["y"] * H) ** 2))
    marks.append((lm["name"], int(sx[k]), int(sy[k])))


def political():
    # drawn at atlas scale: smooth heights for the shading, soft edges between lands and countries
    hs = ndimage.zoom(ndimage.gaussian_filter(height, 1.3), S, order=3)
    ls = ndimage.zoom(land.astype(float), S, order=1) > 0.5
    gy_, gx_ = np.gradient(np.where(ls, hs, 0) / (25.0 / S))
    sh = np.clip(0.84 + (-gx_ * 0.55 - gy_ * 0.7) * 0.75, 0.5, 1.28)
    bio = ndimage.zoom(np.array([b[1] for b in BIOMES], float)[biome], (S, S, 1), order=0)
    bio = ndimage.gaussian_filter(bio, (1.6, 1.6, 0))
    tint = np.zeros((H, W, 3))
    for i, c in enumerate(COUNTRIES):
        tint[owner == i] = c[5]
    tint = ndimage.gaussian_filter(ndimage.zoom(tint, (S, S, 1), order=0), (1.2, 1.2, 0))
    sea_s = ndimage.zoom(sea_rgb, (S, S, 1), order=1)
    rgb = np.where(ls[..., None], (bio * 0.74 + tint * 0.26) * sh[..., None], sea_s)
    lk = ndimage.zoom(lake.astype(float), S, order=1) > 0.5
    rgb[lk & ls] = (78, 128, 176)
    # a pale shore line
    shore_s = ls & ~ndimage.binary_erosion(ls, iterations=1)
    rgb[shore_s] = rgb[shore_s] * 0.6 + np.array([250, 240, 210]) * 0.4
    im = img(rgb)
    d = ImageDraw.Draw(im)
    draw_rivers(d, S)
    bm = border_mask(owner)
    ys, xs = np.nonzero(bm)
    for y, x in zip(ys, xs):
        if (x + y) % 5 < 3:
            d.rectangle((x * S, y * S, x * S + 1, y * S + 1), fill=(92, 28, 22))
    for k in range(6):
        latv = 60 - k * 15
        yr = (SPEC["latitude"]["north"] - latv) / (SPEC["latitude"]["north"] - SPEC["latitude"]["south"]) * (H - 1) * S
        d.line([(0, yr), (W * S, yr)], fill=(220, 230, 240), width=1)
        d.text((6, yr + 3), "%d°%s" % (abs(latv), "N" if latv > 0 else ("S" if latv < 0 else "")), font=F_SM, fill=(230, 238, 245))
    for c in crossings:
        X, Y = c["x"] * S, c["y"] * S
        if c["kind"] in ("ferry", "voyage"):
            pts = [(px_ * S, py_ * S) for px_, py_ in c["route"]]
            for _ in range(3):  # round the corners of the grid path
                pts = [pts[0]] + [q for a_, b_ in zip(pts, pts[1:]) for q in ((0.75 * a_[0] + 0.25 * b_[0], 0.75 * a_[1] + 0.25 * b_[1]), (0.25 * a_[0] + 0.75 * b_[0], 0.25 * a_[1] + 0.75 * b_[1]))] + [pts[-1]]
            dense = []  # even dashes: resample the line every 4 px
            for a_, b_ in zip(pts, pts[1:]):
                n_ = max(int(math.hypot(b_[0] - a_[0], b_[1] - a_[1]) / 4), 1)
                dense += [(a_[0] + (b_[0] - a_[0]) * k_ / n_, a_[1] + (b_[1] - a_[1]) * k_ / n_) for k_ in range(n_)]
            dense.append(pts[-1])
            for q_ in range(0, len(dense) - 2, 4):
                d.line([dense[q_], dense[q_ + 2]], fill=(250, 246, 230), width=2)
            mx_, my_ = dense[len(dense) // 2]
            X, Y = mx_, my_
            d.ellipse((X - 7, Y - 7, X + 7, Y + 7), fill=(250, 246, 230), outline=(30, 16, 10), width=2)
            continue
        col = (196, 40, 28) if c["rough"] >= rough_cut else (240, 200, 60)
        d.polygon([(X, Y - 9), (X + 8, Y), (X, Y + 9), (X - 8, Y)], fill=col, outline=(30, 16, 10))
    for name, mx, my in marks:
        X, Y = mx * S, my * S
        d.regular_polygon((X, Y, 9), 5, fill=(255, 120, 200), outline=(40, 10, 30))
        d.text((X - 12, Y + 4), name, font=F_SM, fill=(60, 10, 40), anchor="ra", stroke_width=2, stroke_fill=(255, 236, 246))
    land_total = land.sum()
    for i, c in enumerate(COUNTRIES):
        m = owner == i
        if not m.any():
            continue
        core = ndimage.distance_transform_edt(m)
        y, x = np.unravel_index(np.argmax(core), core.shape)
        name = c[0].replace("_", " ").title()
        d.text((x * S, y * S - 12), name, font=F_BIG, fill=(36, 20, 12), anchor="mm", stroke_width=3, stroke_fill=(248, 238, 214))
        d.text((x * S, y * S + 13), "levels %s · %d%% of the land" % (c[1], round(100 * m.sum() / land_total)), font=F_SM, fill=(36, 20, 12), anchor="mm", stroke_width=2, stroke_fill=(248, 238, 214))
    return im


def geology():
    pal = np.array([[96, 120, 150] if not cont[i] else [160 + 40 * (i % 3), 140 + 25 * (i % 2), 110] for i in range(NP)], float)
    g = pal[plate]
    g = g * 0.55 + np.where(land[..., None], base_rgb, sea_rgb) * 0.45
    for key, col in (("collide", (214, 80, 50)), ("subduct", (236, 50, 40)), ("rift", (70, 180, 220)), ("fault", (240, 240, 240))):
        g[ndimage.binary_dilation(kinds[key] > 0, iterations=2)] = col
    g[volcanic > 0.25] = (250, 120, 40)
    im = img(g)
    d = ImageDraw.Draw(im)
    for i in range(NP):
        x, y = cen[i]
        x, y = min(max(x, 12), W - 12), min(max(y, 12), H - 12)
        vx, vy = vel[i] * 40
        d.line([(x, y), (x + vx, y + vy)], fill=(255, 255, 255), width=3)
        ang = math.atan2(vy, vx)
        d.polygon([(x + vx, y + vy), (x + vx - 9 * math.cos(ang - 0.5), y + vy - 9 * math.sin(ang - 0.5)), (x + vx - 9 * math.cos(ang + 0.5), y + vy - 9 * math.sin(ang + 0.5))], fill=(255, 255, 255))
    for c in CR:
        d.ellipse((c["cx"] - c["r"], c["cy"] - c["r"], c["cx"] + c["r"], c["cy"] + c["r"]), outline=(255, 240, 120), width=2)
    return im


def climate():
    tn = np.clip((temp + 12) / 40, 0, 1)
    c = np.stack([60 + tn * 190, 60 + (1 - np.abs(tn - 0.5) * 2) * 120, 60 + (1 - tn) * 190], -1)
    rn = np.clip(rain, 0, 1.2) / 1.2
    c2 = np.stack([200 - rn * 170, 170 - rn * 40, 120 + rn * 100], -1)
    return img(np.where(land[..., None], c, (24, 28, 40))), img(np.where(land[..., None], c2, (24, 28, 40)))


pol = political()
pol.save(os.path.join(OUT, "atlas_political.png"))
img(base_rgb).resize((W * S, H * S), Image.LANCZOS).save(os.path.join(OUT, "atlas_land.png"))
geo = geology()
geo.save(os.path.join(OUT, "geology.png"))
tmp_i, rain_i = climate()

# the review sheet: atlas, plus geology, heat, rain and the biome key
sheet = Image.new("RGB", (W * S + 600, H * S), (30, 30, 36))
sheet.paste(pol, (0, 0))
d = ImageDraw.Draw(sheet)
X0 = W * S + 20
small = (270, int(270 * H / W))
d.text((X0, 8), "Plates & impacts", font=F_MED, fill=(240, 236, 226))
sheet.paste(geo.resize(small, Image.LANCZOS), (X0, 32))
d.text((X0 + 290, 8), "Heat (blue cold, red hot)", font=F_MED, fill=(240, 236, 226))
sheet.paste(tmp_i.resize(small, Image.LANCZOS), (X0 + 290, 32))
y2 = 32 + small[1] + 14
d.text((X0, y2), "Rain (tan dry, blue wet)", font=F_MED, fill=(240, 236, 226))
sheet.paste(rain_i.resize(small, Image.LANCZOS), (X0, y2 + 24))
ky = y2 + 24
d.text((X0 + 290, ky - 24), "Lands", font=F_MED, fill=(240, 236, 226))
present = [b for b in BIOMES if (biome[land] == BI[b[0]]).any()]
for b in present:
    d.rectangle((X0 + 290, ky + 2, X0 + 306, ky + 16), fill=b[1], outline=(0, 0, 0))
    d.text((X0 + 314, ky), b[2], font=F_SM, fill=(236, 232, 220))
    ky += 21
ky += 8
for lab_, col in (("fold range (plates collide)", (214, 80, 50)), ("sea floor dives under land", (236, 50, 40)), ("rift (plates part)", (70, 180, 220)), ("fault (plates slide)", (240, 240, 240)), ("volcanoes", (250, 120, 40)), ("meteor impact", (255, 240, 120))):
    d.rectangle((X0 + 290, ky + 2, X0 + 306, ky + 16), fill=col, outline=(0, 0, 0))
    d.text((X0 + 314, ky), lab_, font=F_SM, fill=(236, 232, 220))
    ky += 21
ky += 8
d.polygon([(X0 + 298, ky), (X0 + 306, ky + 9), (X0 + 298, ky + 18), (X0 + 290, ky + 9)], fill=(240, 200, 60))
d.text((X0 + 314, ky), "border crossing", font=F_SM, fill=(236, 232, 220))
ky += 22
d.polygon([(X0 + 298, ky), (X0 + 306, ky + 9), (X0 + 298, ky + 18), (X0 + 290, ky + 9)], fill=(196, 40, 28))
d.text((X0 + 314, ky), "crossing into rough country", font=F_SM, fill=(236, 232, 220))
ky += 22
d.ellipse((X0 + 291, ky + 2, X0 + 305, ky + 16), fill=(250, 246, 230), outline=(30, 16, 10), width=2)
d.text((X0 + 314, ky), "ferry or voyage by sea", font=F_SM, fill=(236, 232, 220))
sheet.save(os.path.join(OUT, "review_sheet.jpg"), quality=90)

land_total = land.sum()
report = {}
for i, c in enumerate(COUNTRIES):
    m = owner == i
    bs, counts = np.unique(biome[m], return_counts=True)
    report[c[0]] = {"share": round(float(m.sum() / land_total), 3), "highest_m": int(height[m].max()) if m.any() else 0,
        "lands": {BIOMES[b][0]: round(float(k / max(m.sum(), 1)), 2) for b, k in zip(bs, counts) if k / max(m.sum(), 1) > 0.05}}
print(json.dumps(report))
print("crossings", len(crossings), "land share", round(float(land.mean()), 3))
np.savez_compressed(os.path.join(OUT, "continent.npz"), height=height.astype(np.float32), owner=owner.astype(np.int8), river=river, lake=lake, biome=biome.astype(np.int8), rain=rain.astype(np.float16), temp=temp.astype(np.float16), filled=filled.astype(np.float32), acc=acc.astype(np.float32), recv=recv.reshape(H, W).astype(np.int32), caps=np.array(caps), biomes=np.array([b[0] for b in BIOMES]), countries=np.array([c[0] for c in COUNTRIES]))
json.dump({"crossings": crossings, "craters": CR, "capitals": caps, "landmarks": marks}, open(os.path.join(OUT, "crossings.json"), "w"), indent=1)
