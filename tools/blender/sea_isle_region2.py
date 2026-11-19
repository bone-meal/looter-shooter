# Purpose: developer-time tool. REGION 2's islands, the Fog Banks (sea step 13 R2a, diary/DESIGN_REGION2.md; LOCKED:
# every island unique, region content baseline), built with the island kit:
#   LANTERNWICK       the region's outpost: a low mangrove island round a sheltered harbour cove opening east; a stilt
#                     village (rest hall, huts), two jetties into the cove, lantern posts along its paths
#   GREYWATER BOG     a flat peat island cut by black channels; the SUNKEN CHAPEL (mini-dungeon 1's way in)
#   THE KNOTS         a tangle of root islets with channels a sloop can thread; the PITCH WORKS on the biggest one
#                     (mini-dungeon 2's way in)
#   HERON'S REACH     a long reed island with a sandy spine and an inner lagoon; the decoy-maker's stilt hut
#   DROWNED ORCHARD   an old orchard on a mound inside a flooded rim, reached along a dyke from its jetty
#   THE HOLLOW MANGROVE  one giant mangrove on a mud ring: the main dungeon's way in (R2c)
#   10 ISLETS         lantern mounds, root knots, a stranded barge, a bell buoy, reed islets, a fog sandbank, a hermit
# Each mid island: generated paths from its landing to its places (ROUTE CHECK at build), zoned props, set pieces on
# levelled pads. -> assets/models/sea/isle_<id>.glb + data/sea/isles/isle_<id>.json (islands listed in
# data/sea/islands.json by hand from the POS printed at the end).
# Run: python3 tools/blender/sea_isle_region2.py [id ...]   (set pieces + props first: ONLY=lantern_hall,chapel_ruin,
# pitch_works,hollow_mangrove,barge,bell_buoy python3 tools/blender/sea_isle_places.py; ONLY=mangrove_a,mangrove_b,
# reed_bed,peat_mound,glowcap,lantern_post python3 tools/blender/sea_isle_props.py)
# AFTER a run: import (tools/import_assets.tscn), then RE-BAKE the island collision (tools/bake_isle_shapes.tscn,
# sea step 13g) or the changed island loads its collision the slow way.
# Dependencies: bpy, tools/blender/sea_isle_kit.py. No game code.
import math
import os
import random
import sys

sys.path.insert(0, os.path.dirname(__file__))
import bpy
import sea_isle_kit as kit


def wobble_shore(R, a3, a5, ph):
    return lambda ang: R * (1.0 + a3 * math.sin(3 * ang + ph) + a5 * math.sin(5 * ang + 2 * ph))


def mud_beyond(d, x, z):
    """Past the shore: a wide shallow mud shelf, then deeper water (d = distance / shore radius > 1)."""
    return -0.4 - 0.9 * kit.smooth(1.0, 1.25, d) - 6.0 * kit.smooth(1.35, 1.7, d) + 0.25 * kit.noise(x * 2, z * 2, 7.0)


def pad(h, x, z, pads):
    """Levelled ground for set pieces: pads [(x, z, radius, height[, blend x radius])]."""
    for p in pads:
        px, pz, r, ph = p[:4]
        out = r * (p[4] if len(p) > 4 else 2.0)
        d = math.hypot(x - px, z - pz)
        if d < out:
            h = ph + (h - ph) * kit.smooth(r, out, d)
    return h


def marsh(d, x, z, top=2.2, seed=13.0):
    """A low marsh island's ground inside its shore: about 0.4 m at the edge rising to `top`."""
    return 0.35 + top * kit.smooth(0.0, 0.45, 1.0 - d) + 0.45 * kit.noise(x * 0.8, z * 0.8, seed)


# --- LANTERNWICK ---
L_SHORE = wobble_shore(200.0, 0.06, 0.05, 0.4)
L_COVE, L_COVE_R = (178.0, 0.0), 76.0  # open to the east: ships sail in
L_PADS = [(86.0, 0.0, 30.0, 1.7, 1.8)]


def lanternwick(x, z):
    d = math.hypot(x, z) / L_SHORE(math.atan2(z, x))
    dc = math.hypot(x - L_COVE[0], z - L_COVE[1]) / L_COVE_R
    if d > 1.0:
        return mud_beyond(d, x, z)
    if dc < 1.0:
        return -3.6 + 2.6 * kit.smooth(0.75, 1.0, dc)  # the harbour cove
    h = marsh(d, x, z, 2.6, 21.0) * kit.smooth(1.0, 1.12, dc) + 0.2 * (1.0 - kit.smooth(1.0, 1.12, dc))
    return pad(h, x, z, L_PADS)


# --- GREYWATER BOG ---
G_SHORE = wobble_shore(240.0, 0.08, 0.05, 1.7)
G_PADS = [(-10.0, -40.0, 11.0, 1.0), (55.0, 55.0, 8.0, 0.9)]


def channel(x, z):
    """Metres-ish to the bog's meandering black channels (kept out of the middle strip the paths use)."""
    a = abs(math.sin(x * 0.028 + 1.6 * math.sin(z * 0.017)))
    b = abs(math.sin(z * 0.031 + 1.4 * math.sin(x * 0.021 + 0.7)))
    return min(a, b) * 30.0


def greywater(x, z):
    d = math.hypot(x, z) / G_SHORE(math.atan2(z, x))
    if d > 1.0:
        return mud_beyond(d, x, z)
    h = 0.55 + 0.6 * kit.smooth(0.0, 0.3, 1.0 - d) + 0.3 * kit.noise(x * 0.6, z * 0.6, 31.0)
    if abs(x - 5.0) > 22.0 and math.hypot(x + 10.0, z + 40.0) > 26.0 and math.hypot(x - 55.0, z - 55.0) > 18.0:
        c = channel(x, z)
        if c < 3.0:
            h = -0.9 + 1.4 * kit.smooth(1.2, 3.0, c)
    return pad(h, x, z, G_PADS)


# --- THE KNOTS ---
K_KNOTS = [(0.0, 0.0, 72.0), (130.0, -40.0, 38.0), (110.0, 95.0, 34.0), (-20.0, 135.0, 30.0), (-135.0, 70.0, 42.0),
           (-140.0, -60.0, 36.0), (-30.0, -140.0, 40.0), (85.0, -140.0, 28.0), (170.0, 40.0, 24.0)]
K_PADS = [(0.0, -10.0, 13.0, 1.3)]


def knots(x, z):
    best = 9.0
    for kx, kz, kr in K_KNOTS:
        ang = math.atan2(z - kz, x - kx)
        best = min(best, math.hypot(x - kx, z - kz) / (kr * (1.0 + 0.1 * math.sin(3 * ang + kx * 0.01))))
    if best > 1.0:
        return -0.6 - 2.2 * kit.smooth(1.0, 1.35, best) + 0.2 * kit.noise(x * 2, z * 2, 9.0)  # the channels between
    h = 0.35 + 2.4 * kit.smooth(0.0, 0.6, 1.0 - best) + 0.35 * kit.noise(x, z, 41.0)
    return pad(h, x, z, K_PADS)


# --- HERON'S REACH ---
H_PADS = [(60.0, 20.0, 9.0, 1.6), (-20.0, -12.0, 6.0, 4.6)]
H_LAGOON, H_LAGOON_R = (-70.0, 25.0), 45.0


def herons(x, z):
    u, v = (x * math.cos(0.35) + z * math.sin(0.35)) / 240.0, (-x * math.sin(0.35) + z * math.cos(0.35)) / 115.0
    d = math.hypot(u, v) * (1.0 + 0.05 * math.sin(5 * math.atan2(v, u)))
    dl = math.hypot(x - H_LAGOON[0], z - H_LAGOON[1]) / H_LAGOON_R
    if d > 1.0:
        return mud_beyond(d, x, z)
    if dl < 1.0:
        return -1.6 + 1.2 * kit.smooth(0.7, 1.0, dl)  # the inner lagoon
    spine = 3.6 * math.exp(-(v / 0.35) ** 2) * kit.smooth(0.0, 0.4, 1.0 - d)  # a sandy spine along the long axis
    h = 0.35 + 0.8 * kit.smooth(0.0, 0.25, 1.0 - d) + spine + 0.25 * kit.noise(x, z, 51.0)
    return pad(h, x, z, H_PADS)


# --- DROWNED ORCHARD ---
O_SHORE = wobble_shore(230.0, 0.05, 0.04, 2.4)
O_PADS = [(22.0, -15.0, 9.0, 6.5)]


def orchard(x, z):
    d = math.hypot(x, z) / O_SHORE(math.atan2(z, x))
    if d > 1.0:
        return mud_beyond(d, x, z)
    mound = 8.0 * max(1.0 - (math.hypot(x, z) / 135.0) ** 2, 0.0) ** 0.8
    h = -0.35 + 0.5 * kit.noise(x * 0.5, z * 0.5, 61.0) * 0.4 + mound  # the flooded rim round the mound
    if abs(x) < 4.5 and 95.0 < z < 228.0:  # the dyke from the jetty to the mound
        h = max(h, 1.0)
    return pad(h, x, z, O_PADS)


# --- THE HOLLOW MANGROVE ---
M_SHORE = wobble_shore(120.0, 0.07, 0.05, 0.9)
M_PADS = [(0.0, 0.0, 22.0, 0.6, 1.5)]


def hollow(x, z):
    d = math.hypot(x, z) / M_SHORE(math.atan2(z, x))
    if d > 1.0:
        return mud_beyond(d, x, z)
    return pad(marsh(d, x, z, 0.8, 71.0), x, z, M_PADS)


def edge(land, ang, start=40.0, step=1.0):
    """The island-local point where the shore crosses sea level along a bearing (angle from +x toward +z)."""
    r = start
    while land(r * math.cos(ang), r * math.sin(ang)) > 0.1 and r < 400.0:
        r += step
    return r


MID = {
    "lanternwick": {"land": lanternwick, "reach": 290.0, "cells": 200, "seed": 81, "pos": (-3900.0, 6200.0),
                    "landing": (99.0, 14.0), "pois": {"hall": (94.0, -4.0), "village": (74.0, -36.0), "marsh": (-90.0, 30.0)},
                    "places": [["lantern_hall", 82.0, 1.7, 0.0, -90.0, 1.0], ["stilt_hut", 96.0, 1.7, -38.0, -60.0, 1.0], ["stilt_hut", 96.0, 1.7, 38.0, -120.0, 1.0],
                               ["stilt_hut", 70.0, 1.7, -54.0, -30.0, 1.0], ["stilt_hut", 70.0, 1.7, 54.0, -150.0, 1.0],
                               ["jetty", 103.0, 0.0, 14.0, -90.0, 1.0], ["jetty", 103.0, 0.0, -14.0, -90.0, 1.0], ["drying_rack", 62.0, 1.7, -30.0, 70.0, 1.0]],
                    "keep": [(86.0, 0.0, 30.0)], "avoid": [(82.0, 0.0, 7.0), (96.0, -38.0, 4.0), (96.0, 38.0, 4.0), (70.0, -54.0, 4.0), (70.0, 54.0, 4.0), (62.0, -30.0, 2.6)],
                    "zone": "swamp", "lanterns": 24.0},
    "greywater_bog": {"land": greywater, "reach": 330.0, "cells": 210, "seed": 83, "pos": (-5300.0, 4300.0),
                      "landing": None, "landing_ang": 90.0, "pois": {"chapel": (-10.0, -30.0), "cuttings": (55.0, 46.0)},
                      "places": [["chapel_ruin", -10.0, 0.95, -40.0, -90.0, 1.0]],
                      "keep": [(-10.0, -40.0, 9.0)], "avoid": [(-10.0, -40.0, 7.0)], "zone": "swamp", "lanterns": 40.0},
    "the_knots": {"land": knots, "reach": 230.0, "cells": 200, "seed": 85, "pos": (-6300.0, 6900.0),
                  "landing": None, "landing_ang": 90.0, "pois": {"works": (-3.0, 4.0), "tapper": (-26.0, -22.0)},
                  "places": [["pitch_works", 0.0, 1.3, -10.0, 180.0, 1.0]],
                  "keep": [(0.0, -10.0, 10.0)], "avoid": [(0.0, -10.0, 7.0)], "zone": "swamp", "lanterns": 0.0},
    "herons_reach": {"land": herons, "reach": 300.0, "cells": 210, "seed": 87, "pos": (-4900.0, 8100.0),
                     "landing": None, "landing_ang": 100.0, "pois": {"hut": (60.0, 27.0), "spine": (-20.0, -12.0)},
                     "places": [["stilt_hut", 60.0, 1.6, 20.0, 180.0, 1.0]],
                     "keep": [(60.0, 20.0, 7.0)], "avoid": [(60.0, 20.0, 4.0)], "zone": "swamp", "lanterns": 0.0},
    "drowned_orchard": {"land": orchard, "reach": 300.0, "cells": 210, "seed": 89, "pos": (-7600.0, 4600.0),
                        "landing": (0.0, 226.0), "jetty_f": 228.0, "pois": {"orchard": (0.0, 0.0), "farm": (22.0, -5.0)},
                        "places": [],
                        "keep": [(22.0, -15.0, 8.0)], "avoid": [(22.0, -15.0, 6.0)], "zone": "orchard", "lanterns": 0.0, "orchard": True},
    "hollow_mangrove": {"land": hollow, "reach": 190.0, "cells": 170, "seed": 91, "pos": (-7900.0, 7900.0),
                        "landing": None, "landing_ang": 90.0, "pois": {"door": (0.0, 15.0)},
                        "places": [["hollow_mangrove", 0.0, 0.5, 0.0, 180.0, 1.0]],
                        "keep": [(0.0, 0.0, 24.0)], "avoid": [], "zone": "swamp", "lanterns": 0.0, "giant": True},
}


def build_mid(iid):
    s = MID[iid]
    land, reach = s["land"], s["reach"]
    name = "isle_" + iid
    bpy.ops.wm.read_factory_settings(use_empty=True)
    places = [list(p) for p in s["places"]]
    landing = s["landing"]
    if landing is None:  # a jetty out from the shore along the landing bearing
        ang = math.radians(s["landing_ang"])
        r = edge(land, ang)
        landing = (round((r - 5.0) * math.cos(ang), 1), round((r - 5.0) * math.sin(ang), 1))
        places.append(["jetty", round((r - 1.0) * math.cos(ang), 1), 0.0, round((r - 1.0) * math.sin(ang), 1), round(-90.0 - math.degrees(ang), 1), 1.0])
    elif "jetty_f" in s:
        places.append(["jetty", 0.0, 0.0, s["jetty_f"], 180.0, 1.0])

    def keep_out(x, z):
        return any(math.hypot(x - kx, z - kz) < kr for kx, kz, kr in s["keep"])

    def footprint(x, z):  # paths keep clear of the set pieces themselves
        if s.get("giant") and math.hypot(x, z) < 18.0 and not (abs(x) < 2.6 and z > 4.0):
            return True  # the giant's root cage, but for the doorway corridor
        return any(math.hypot(x - ax, z - az) < ar for ax, az, ar in s["avoid"])

    found = kit.route(land, reach, landing, s["pois"], avoid=footprint)
    paths = [kit.smooth_path(line) for line in found.values()]
    index = kit.PathIndex(paths)

    def path_off(x, z):
        best = 99.0
        for a, b in index.near(x, z):
            best = min(best, kit.seg_dist(x, z, a, b)[0])
        return best

    def zone(x, z, h):
        if h < 0.9:
            return "mudflat"
        if kit.slope(land, x, z) > 0.6:
            return "rocky"
        if s["zone"] == "orchard" and h < 2.0:
            return "mudflat"
        return s["zone"]

    def trodden(x, z):
        off = path_off(x, z)
        return 0.0 if off >= 3.5 else 0.7 * (1.0 - off / 3.5)

    obj = kit.ground(name, land, reach, s["cells"], trodden, lambda x, z: 1.0 if zone(x, z, land(x, z)) == "swamp" and land(x, z) > 1.2 else 0.0)
    props = kit.scatter_zones(land, reach, s["seed"], zone, lambda x, z: path_off(x, z) < 3.5 or keep_out(x, z) or footprint(x, z), density=0.6)
    props = [p for p in props if not (kit.SOLID.get(p[0]) is not None and path_off(p[1], p[3]) < (kit.SOLID[p[0]] or 2.0) * p[5] + 0.6)]
    rnd = random.Random(s["seed"] + 1)
    if s.get("orchard"):  # the old orchard: rows of fruit trees on the mound, a ruined farmhouse
        for i in range(-6, 7):
            for j in range(-6, 7):
                x, z = i * 11.0 + rnd.uniform(-1.2, 1.2), j * 11.0 + rnd.uniform(-1.2, 1.2)
                if land(x, z) > 2.2 and path_off(x, z) > 3.0 and not keep_out(x, z) and rnd.random() < 0.85:
                    kit.put(props, rnd, land, "broadleaf_a", x, z, rnd.uniform(0.5, 0.65), 0.2)
        for k, (wx, wz, wy) in enumerate(((22.0, -21.0, 0.0), (22.0, -9.0, 180.0), (16.0, -15.0, 90.0), (28.0, -15.0, 270.0))):
            if k != 1:
                props.append(["ruin_wall", wx, round(land(wx, wz) - 0.1, 2), wz, wy, 1.0])
    if s["lanterns"] > 0.0:  # lantern posts along the paths, 2 m to one side, every `lanterns` metres
        for line in paths:
            run = 0.0
            for a, b in zip(line, line[1:]):
                seg = math.hypot(b[0] - a[0], b[1] - a[1])
                run += seg
                if run >= s["lanterns"] and seg > 0.1:
                    run = 0.0
                    nx, nz = -(b[1] - a[1]) / seg, (b[0] - a[0]) / seg
                    x, z = b[0] + nx * 2.2, b[1] + nz * 2.2
                    if land(x, z) > 0.3 and not footprint(x, z):
                        props.append(["lantern_post", round(x, 2), round(land(x, z) - 0.05, 2), round(z, 2), round(math.degrees(math.atan2(nx, nz)), 1), 1.0])
    problems = ["%s: no way found" % k for k in s["pois"] if k not in found]
    for line in paths:
        for a, b in zip(line, line[1:]):
            ha, hb = land(*a), land(*b)
            run = max(math.hypot(b[0] - a[0], b[1] - a[1]), 0.5)
            if abs(hb - ha) / run > 0.75:
                problems.append("steep at (%.0f, %.0f): %.2f" % (a[0], a[1], abs(hb - ha) / run))
            if min(ha, hb) < 0.1:
                problems.append("under the sea at (%.0f, %.0f)" % (a[0], a[1]))
    for line in problems:
        print("ROUTE PROBLEM", iid, line)
    print("ROUTE CHECK", iid, "problems=%d" % len(problems), "landing", landing)
    routes = {"start": "landing", "pois": {k: [round(v[0], 2), round(v[1], 2)] for k, v in dict(s["pois"], landing=landing).items()},
              "walk_into": {}, "paths": [[[round(a, 2), round(b, 2)] for a, b in line] for line in paths]}
    kit.save(name, obj, props, "tools/blender/sea_isle_region2.py", places, None, routes)
    print("POS", iid, s["pos"], "radius", round(reach * 0.66))


# --- ISLETS ---
ISLETS = [
    # id, sea position, shore radius, kind, seed
    ("islet_lantern_east", (-3400.0, 4300.0), 14.0, "lantern", 101),
    ("islet_root_knot_a", (-4500.0, 5200.0), 18.0, "knot", 102),
    ("islet_barge", (-6100.0, 5400.0), 22.0, "barge", 103),
    ("islet_bell", (-5600.0, 7400.0), 10.0, "bell", 104),
    ("islet_reeds_a", (-7000.0, 3500.0), 26.0, "reeds", 105),
    ("islet_root_knot_b", (-8600.0, 6200.0), 20.0, "knot", 106),
    ("islet_fog_sand", (-6800.0, 8600.0), 30.0, "sand", 107),
    ("islet_lantern_west", (-8400.0, 3500.0), 14.0, "lantern", 108),
    ("islet_reeds_b", (-4100.0, 7300.0), 24.0, "reeds", 109),
    ("islet_hermit", (-3500.0, 8700.0), 18.0, "hermit", 110),
]


def islet_land(R, kind, seed):
    shore = wobble_shore(R, 0.15, 0.1, seed * 0.37)
    top = {"lantern": 1.4, "knot": 1.6, "barge": 0.6, "bell": -0.8, "reeds": 0.7, "sand": 0.45, "hermit": 1.5}[kind]

    def land(x, z):
        d = math.hypot(x, z) / shore(math.atan2(z, x))
        if d > 1.0:
            return -0.4 - 1.0 * kit.smooth(1.0, 1.3, d) - 5.0 * kit.smooth(1.4, 2.2, d) + 0.2 * kit.noise(x * 2, z * 2, seed)
        return (0.25 if kind != "bell" else -1.5) + top * (1.0 - d * d) ** 1.2 + 0.2 * kit.noise(x * 1.5, z * 1.5, seed)
    return land


def build_islet(entry):
    iid, pos, R, kind, seed = entry
    name = "isle_" + iid
    bpy.ops.wm.read_factory_settings(use_empty=True)
    land = islet_land(R, kind, seed)
    reach = R * 2.4
    obj = kit.ground(name, land, reach, 60)
    rnd = random.Random(seed)
    props, places = [], []

    def zone(x, z, h):
        return "mudflat" if h < 0.9 or kind in ("sand", "reeds", "barge") else "swamp"
    if kind not in ("bell",):
        props = kit.scatter_zones(land, reach, seed, zone, None, density=0.5 if kind != "sand" else 0.15)
    if kind in ("knot", "hermit"):
        props = [p for p in props if p[0] not in ("mangrove_a", "mangrove_b")]
        props.append(["mangrove_b", 0.0, round(land(0.0, 0.0) - 0.2, 2), 0.0, rnd.uniform(0, 360), 1.3])
    if kind == "lantern":
        for k in range(3):
            a = 2 * math.pi * k / 3 + rnd.uniform(-0.3, 0.3)
            x, z = R * 0.45 * math.cos(a), R * 0.45 * math.sin(a)
            props.append(["lantern_post", round(x, 2), round(land(x, z) - 0.05, 2), round(z, 2), round(rnd.uniform(0, 360), 1), 1.0])
    if kind == "barge":
        places.append(["barge", 2.0, round(land(2.0, 0.0) - 0.2, 2), 0.0, 25.0, 1.0])
    if kind == "bell":
        places.append(["bell_buoy", 0.0, 0.0, 0.0, 0.0, 1.0])
    if kind == "hermit":
        places.append(["camp", R * 0.35, round(land(R * 0.35, 0.0), 2), 0.0, 90.0, 0.8])
    kit.save(name, obj, props, "tools/blender/sea_isle_region2.py", places)
    print("POS", iid, pos, "radius", round(R * 1.6))


if __name__ == "__main__":
    want = sys.argv[1:]
    for iid in MID:
        if not want or iid in want:
            build_mid(iid)
    for e in ISLETS:
        if not want or e[0] in want or "islets" in want:
            build_islet(e)
