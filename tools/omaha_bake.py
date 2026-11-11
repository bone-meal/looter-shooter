#!/usr/bin/env python3
"""Purpose: bake raw OpenStreetMap Overpass JSON (data/omaha/raw) into game chunks (data/omaha/chunks).
Dev-time tool only, never shipped. Usage: python3 tools/omaha_bake.py <project_dir>
World: x east, z south, metres in GAME units = real metres / SCALE. Origin = Old Market, Omaha.
Map data (c) OpenStreetMap contributors, ODbL."""
import json, math, os, sys, collections

SCALE = 5.0
LAT0, LON0 = 41.2565, -95.9345
CHUNK = 192.0
REGION = 6                # chunks per region file side (files load whole, chunks stream from them)
H_COMPRESS = 0.6          # tall buildings are shortened so the squeezed city does not feel like canyons
MIN_BUILDING = 8.0        # smallest building footprint side in game metres
ROAD_W = {"motorway": 11, "trunk": 10, "primary": 9, "secondary": 8, "tertiary": 7}
ROAD_CLASS = {"motorway": 0, "motorway_link": 0, "trunk": 0, "trunk_link": 0, "primary": 1, "primary_link": 1,
              "secondary": 2, "tertiary": 3, "residential": 4, "unclassified": 4, "living_street": 4}
KEY_LANDMARKS = ["Union Pacific Center", "First National Bank Tower", "Woodmen Tower", "CHI Health Center",
                 "Charles Schwab Field", "Henry Doorly Zoo", "Desert Dome", "Joslyn Art Museum", "Holland Performing Arts Center",
                 "Kiewit Luminarium", "Omaha World Herald Building", "Qwest Center", "Creighton University", "Elmwood Tower",
                 "Nebraska Medical Center", "Durham Museum", "Union Station", "Eppley Airfield", "Rosenblatt Stadium",
                 "Bob Kerrey Pedestrian Bridge", "Ak-Sar-Ben", "Westroads Mall", "Crossroads Mall", "Boys Town"]

KX = 111320.0 * math.cos(math.radians(LAT0))
KZ = 110574.0


def proj(lat, lon):
    return ((lon - LON0) * KX / SCALE, -(lat - LAT0) * KZ / SCALE)


def pts(el):
    return [proj(g["lat"], g["lon"]) for g in el.get("geometry", []) if g]


def simplify(p, tol):
    if len(p) < 3:
        return p
    keep = [False] * len(p)
    keep[0] = keep[-1] = True
    stack = [(0, len(p) - 1)]
    while stack:
        a, b = stack.pop()
        ax, az = p[a]; bx, bz = p[b]
        dx, dz = bx - ax, bz - az
        n = math.hypot(dx, dz) or 1e-9
        best, bi = 0.0, -1
        for i in range(a + 1, b):
            d = abs((p[i][0] - ax) * dz - (p[i][1] - az) * dx) / n
            if d > best:
                best, bi = d, i
        if best > tol and bi >= 0:
            keep[bi] = True
            stack.append((a, bi)); stack.append((bi, b))
    return [q for q, k in zip(p, keep) if k]


_c = [proj(41.12, -96.30), proj(41.40, -95.85)]
BX0, BX1 = min(c[0] for c in _c), max(c[0] for c in _c)
BZ0, BZ1 = min(c[1] for c in _c), max(c[1] for c in _c)


def in_bounds(key):
    return BX0 // CHUNK - 1 <= key[0] <= BX1 // CHUNK + 1 and BZ0 // CHUNK - 1 <= key[1] <= BZ1 // CHUNK + 1


def ckey(x, z):
    return (int(math.floor(x / CHUNK)), int(math.floor(z / CHUNK)))


def split_line(p):
    """Split a polyline at chunk borders. Returns [(chunk_key, [x,z,x,z,...])], consecutive same-chunk runs merged."""
    res = []
    cur_key, cur = None, []
    for i in range(len(p) - 1):
        (x0, z0), (x1, z1) = p[i], p[i + 1]
        ts = [0.0, 1.0]
        for a0, a1 in ((x0, x1), (z0, z1)):
            if a0 == a1:
                continue
            lo, hi = sorted((a0, a1))
            k = math.floor(lo / CHUNK) + 1
            while k * CHUNK < hi:
                ts.append((k * CHUNK - a0) / (a1 - a0)); k += 1
        ts = sorted(set(ts))
        for ta, tb in zip(ts, ts[1:]):
            xa, za = x0 + (x1 - x0) * ta, z0 + (z1 - z0) * ta
            xb, zb = x0 + (x1 - x0) * tb, z0 + (z1 - z0) * tb
            key = ckey((xa + xb) / 2, (za + zb) / 2)
            if key == cur_key:
                cur.extend([xb, zb])
            else:
                if cur:
                    res.append((cur_key, cur))
                cur_key, cur = key, [xa, za, xb, zb]
    if cur:
        res.append((cur_key, cur))
    return res


def clip_poly(poly, x0, z0, x1, z1):
    def clip(pl, inside, inter):
        if not pl:
            return pl
        out = []
        prev = pl[-1]
        for cur in pl:
            if inside(cur):
                if not inside(prev):
                    out.append(inter(prev, cur))
                out.append(cur)
            elif inside(prev):
                out.append(inter(prev, cur))
            prev = cur
        return out
    def ix(xv):
        return lambda a, b: (xv, a[1] + (b[1] - a[1]) * (xv - a[0]) / (b[0] - a[0]))
    def iz(zv):
        return lambda a, b: (a[0] + (b[0] - a[0]) * (zv - a[1]) / (b[1] - a[1]), zv)
    p = clip(poly, lambda q: q[0] >= x0, ix(x0))
    p = clip(p, lambda q: q[0] <= x1, ix(x1))
    p = clip(p, lambda q: q[1] >= z0, iz(z0))
    p = clip(p, lambda q: q[1] <= z1, iz(z1))
    return p


def area(p):
    return 0.5 * sum(p[i][0] * p[(i + 1) % len(p)][1] - p[(i + 1) % len(p)][0] * p[i][1] for i in range(len(p)))


def oriented_rect(p):
    best = None
    n = len(p)
    for i in range(n - 1):
        dx, dz = p[i + 1][0] - p[i][0], p[i + 1][1] - p[i][1]
        L = math.hypot(dx, dz)
        if L < 1e-6:
            continue
        if best is None or L > best[0]:
            best = (L, math.atan2(dz, dx))
    ang = best[1] if best else 0.0
    c, s = math.cos(-ang), math.sin(-ang)
    rs = [(x * c - z * s, x * s + z * c) for x, z in p]
    minx, maxx = min(r[0] for r in rs), max(r[0] for r in rs)
    minz, maxz = min(r[1] for r in rs), max(r[1] for r in rs)
    cx, cz = (minx + maxx) / 2, (minz + maxz) / 2
    c2, s2 = math.cos(ang), math.sin(ang)
    return (cx * c2 - cz * s2, cx * s2 + cz * c2, maxx - minx, maxz - minz, ang)


def chain_rings(ways):
    """Join open ways end to end into longer chains (exact endpoint matches)."""
    chains = [list(w) for w in ways if len(w) > 1]
    merged = True
    while merged:
        merged = False
        for i in range(len(chains)):
            for j in range(len(chains)):
                if i == j:
                    continue
                a, b = chains[i], chains[j]
                for aa, bb in ((a, b), (a, b[::-1]), (a[::-1], b), (a[::-1], b[::-1])):
                    if abs(aa[-1][0] - bb[0][0]) < 0.01 and abs(aa[-1][1] - bb[0][1]) < 0.01:
                        chains[i] = aa + bb[1:]
                        del chains[j]
                        merged = True
                        break
                if merged:
                    break
            if merged:
                break
    return chains


def main(root):
    raw = os.path.join(root, "data/omaha/raw")
    out = os.path.join(root, "data/omaha/chunks")
    os.makedirs(out, exist_ok=True)
    for f in os.listdir(out):
        os.remove(os.path.join(out, f))
    chunks = collections.defaultdict(lambda: {"r": [], "w": [], "p": [], "g": [], "b": []})

    def load(name):
        path = os.path.join(raw, name + ".json")
        return json.load(open(path))["elements"] if os.path.exists(path) else []

    def r1(v):
        return [round(c, 1) for c in v]

    # roads
    nroad = 0
    for name, tol in (("roads_major", 0.8), ("roads_minor", 1.2)):
        for el in load(name):
            cls = ROAD_CLASS.get(el["tags"].get("highway", ""), 4)
            p = simplify(pts(el), tol)
            if len(p) < 2:
                continue
            for key, seg in split_line(p):
                chunks[key]["r"].append([cls] + r1(seg)); nroad += 1
    # rail
    for el in load("rail"):
        p = simplify(pts(el), 1.0)
        if len(p) < 2:
            continue
        for key, seg in split_line(p):
            chunks[key]["r"].append([5] + r1(seg))
    # water lines (named streams/rivers/canals only for streams)
    for el in load("water"):
        t = el["tags"]
        ww = t.get("waterway")
        p = pts(el)
        if ww in ("river", "canal", "stream"):
            if ww == "stream" and not t.get("name"):
                continue
            w = {"river": 6, "canal": 4, "stream": 2.5}[ww]
            p = simplify(p, 1.0)
            if len(p) < 2:
                continue
            for key, seg in split_line(p):
                chunks[key]["w"].append([w] + r1(seg))
        elif t.get("natural") == "water" and len(p) > 3:
            polys = [simplify(p[:-1], 0.7)]
            for poly in polys:
                if len(poly) >= 3 and abs(area(poly)) > 12:
                    add_poly(chunks, "p", poly)
    # river relations (outer members, chained and closed along the bbox)
    for el in load("river_rel"):
        outer = [pts({"geometry": m["geometry"]}) for m in el.get("members", []) if m.get("role") == "outer" and m.get("geometry")]
        chains = chain_rings(outer)
        closed = [c for c in chains if math.hypot(c[0][0] - c[-1][0], c[0][1] - c[-1][1]) < 0.01]
        opened = sorted([c for c in chains if c not in closed], key=lambda c: -len(c))
        for c in closed:
            if abs(area(c[:-1])) > 12:
                add_poly(chunks, "p", simplify(c[:-1], 0.7))
        if len(opened) >= 2:
            a, b = opened[0], opened[1]
            if math.hypot(a[-1][0] - b[0][0], a[-1][1] - b[0][1]) > math.hypot(a[-1][0] - b[-1][0], a[-1][1] - b[-1][1]):
                b = b[::-1]
            ring = simplify(a, 0.8) + simplify(b, 0.8)
            if abs(area(ring)) > 12:
                add_poly(chunks, "p", ring)
        print("river relation", el.get("id"), "outer", len(outer), "chains", len(chains), "closed", len(closed), "open", len(opened))
    # parks (kind 1) and golf (kind 2); pitches skipped (too small at this scale)
    for el in load("parks"):
        lt = el["tags"].get("leisure")
        if lt in ("pitch",):
            continue
        p = simplify(pts(el)[:-1], 1.0)
        if len(p) >= 3 and abs(area(p)) > 40:
            add_poly(chunks, "g", p)
    # buildings: landmarks (named) + towers
    seen = set()
    nb = 0
    landmarks = []
    for name in ("towers", "landmarks"):
        for el in load(name):
            if el["id"] in seen:
                continue
            seen.add(el["id"])
            t = el["tags"]
            p = pts(el)[:-1]
            if len(p) < 3:
                continue
            cx, cz, w, d, ang = oriented_rect(p)
            real_area = w * d * SCALE * SCALE
            levels = float(t.get("building:levels", "0") or 0) if str(t.get("building:levels", "0")).replace(".", "").isdigit() else 0
            try:
                height = float(str(t.get("height", "0")).split()[0])
            except ValueError:
                height = 0
            tall = name == "towers"
            if not tall and real_area < 700 and levels < 3:
                continue
            real_h = height or (levels * 3.4 if levels else (7 if real_area > 3000 else 5))
            hg = max(4.5, real_h * H_COMPRESS)
            w, d = max(w, MIN_BUILDING), max(d, MIN_BUILDING)
            nm = t.get("name", "")
            kind = t.get("building", "yes")
            if t.get("amenity") in ("hospital", "university"):
                kind = t["amenity"]
            rec = [round(cx, 1), round(cz, 1), round(w, 1), round(d, 1), round(ang, 3), round(hg, 1), kind, nm]
            chunks[ckey(cx, cz)]["b"].append(rec); nb += 1
            if nm and (tall or any(k.lower() in nm.lower() for k in KEY_LANDMARKS) or kind in ("hospital", "university")):
                landmarks.append({"name": nm, "x": rec[0], "z": rec[1], "h": rec[5], "kind": kind})
    spawn = find_spawn(chunks)
    keys = []
    regions = collections.defaultdict(dict)
    for (cx, cz), c in chunks.items():
        if not any(c.values()) or not in_bounds((cx, cz)):
            continue
        regions[(cx // REGION, cz // REGION)]["%d_%d" % (cx, cz)] = c
        keys.append([cx, cz])
    for (rx, rz), d in regions.items():
        json.dump(d, open(os.path.join(out, "r_%d_%d.json" % (rx, rz)), "w"), separators=(",", ":"))
    minx = min(k[0] for k in keys); maxx = max(k[0] for k in keys)
    minz = min(k[1] for k in keys); maxz = max(k[1] for k in keys)
    manifest = {"version": 1, "scale": SCALE, "origin_lat": LAT0, "origin_lon": LON0, "chunk": CHUNK, "region": REGION,
                "bounds": [minx, minz, maxx, maxz], "chunks": keys, "landmarks": landmarks,
                "spawn": [round(spawn[0], 1), round(spawn[1], 1)], "credit": "Map data (c) OpenStreetMap contributors, ODbL"}
    json.dump(manifest, open(os.path.join(root, "data/omaha/map.json"), "w"), separators=(",", ":"))
    print("chunks", len(keys), "roads", nroad, "buildings", nb, "landmarks", len(landmarks), "bounds", manifest["bounds"])


def find_spawn(chunks):
    """Nearest secondary/tertiary/residential road vertex to the origin that is clear of buildings and water."""
    cands = []
    for (cx, cz), c in chunks.items():
        if abs(cx) > 2 or abs(cz) > 2:
            continue
        for r in c["r"]:
            if r[0] in (2, 3, 4):
                for i in range(1, len(r) - 1, 2):
                    cands.append((math.hypot(r[i], r[i + 1]), r[i], r[i + 1]))
    cands.sort()
    for d, x, z in cands:
        cx, cz = ckey(x, z)
        near = [b for k in [(cx + a, cz + e) for a in (-1, 0, 1) for e in (-1, 0, 1)] for b in chunks.get(k, {"b": []})["b"]]
        if all(math.hypot(b[0] - x, b[1] - z) > max(b[2], b[3]) * 0.75 + 8 for b in near):
            return (x, z)
    return (0.0, 0.0)


def add_poly(chunks, layer, poly):
    if area(poly) < 0:
        poly = poly[::-1]
    xs = [q[0] for q in poly]; zs = [q[1] for q in poly]
    for cx in range(max(int(math.floor(min(xs) / CHUNK)), int(BX0 // CHUNK) - 1), min(int(math.floor(max(xs) / CHUNK)), int(BX1 // CHUNK) + 1) + 1):
        for cz in range(max(int(math.floor(min(zs) / CHUNK)), int(BZ0 // CHUNK) - 1), min(int(math.floor(max(zs) / CHUNK)), int(BZ1 // CHUNK) + 1) + 1):
            c = clip_poly(poly, cx * CHUNK, cz * CHUNK, (cx + 1) * CHUNK, (cz + 1) * CHUNK)
            if len(c) >= 3 and abs(area(c)) > 4:
                chunks[(cx, cz)][layer].append([v for q in c for v in (round(q[0], 1), round(q[1], 1))])


if __name__ == "__main__":
    main(sys.argv[1])
