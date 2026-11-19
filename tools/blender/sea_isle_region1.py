# Purpose: developer-time tool. REGION 1's new islands (sea step 13b, diary/DESIGN_REGION1.md; LOCKED: every island
# unique, region content baseline), built with the island kit:
#   TURTLEBACK        a domed green island shaped like a sleeping turtle's shell (plates in its slopes); a fishing
#                     hamlet of three stilt huts and drying racks on its south beach, a jetty, a path up to the crown
#   SALTPAN KEY       a flat white key: salt pans in the middle, a low rocky rise in the north-west carrying the ruined
#                     SALT WORKS (its cellar stair = the Salt Cellars' way in, sea step 13c)
#   SMUGGLER'S HOOK   a limestone ridge curled round a hidden cove that opens to the south-east: a beached wreck on the
#                     cove's beach, a sea CAVE in the ridge's back wall (Smuggler's Grotto's way in, 13c), a jetty
#   PALM RING ATOLL   a ring of palm sand round a lagoon, one gap to the south to sail in by; a castaway's camp on its
#                     east side
#   10 ISLETS         one-tree rocks, sandbars, bird rocks, a small arch, a shoal of rocks round a sunken mast
# Each mid island: generated paths from its landing to its places (ROUTE CHECK at build), zoned props, set pieces on
# levelled pads. -> assets/models/sea/isle_<id>.glb + data/sea/isles/isle_<id>.json (islands listed in
# data/sea/islands.json by hand from the POS printed at the end).
# Run: python3 tools/blender/sea_isle_region1.py [id ...]   (set pieces first: ONLY=stilt_hut,drying_rack,salt_pans,
# salt_works python3 tools/blender/sea_isle_places.py)
# Dependencies: bpy, tools/blender/sea_isle_kit.py. No game code.
import math
import os
import random
import sys

sys.path.insert(0, os.path.dirname(__file__))
import bpy
import sea_isle_kit as kit


def dome_shore(R, a3, a5, ph):
    return lambda ang: R * (1.0 + a3 * math.sin(3 * ang + ph) + a5 * math.sin(5 * ang + 2 * ph))


def sea_beyond(d, x, z):
    """The sea floor past the shore (d = distance / shore radius > 1)."""
    return -0.5 - 1.3 * kit.smooth(1.0, 1.2, d) - 7.0 * kit.smooth(1.28, 1.55, d) + 0.25 * kit.noise(x * 2, z * 2, 3.0)


def pad(h, x, z, pads):
    """Levelled ground for set pieces: pads [(x, z, radius, height)] blended out over a second radius."""
    for p in pads:
        px, pz, r, ph = p[:4]
        out = r * (p[4] if len(p) > 4 else 2.0)  # (an optional 5th: how far out it blends, x radius)
        d = math.hypot(x - px, z - pz)
        if d < out:
            h = ph + (h - ph) * kit.smooth(r, out, d)
    return h


# --- TURTLEBACK ---
T_SHORE = dome_shore(190.0, 0.05, 0.04, 0.7)
T_PADS = [(0.0, 152.0, 20.0, 1.9, 3.4), (0.0, -10.0, 9.0, 27.0)]


def turtleback(x, z):
    ang = math.atan2(z, x)
    d = math.hypot(x, z * 1.1) / T_SHORE(ang)
    if d > 1.0:
        return sea_beyond(d, x, z)
    dome = 30.0 * max(1.0 - d * d, 0.0) ** 1.3
    plates = 1.6 * abs(math.sin(x * 0.055 + 0.3) * math.sin(z * 0.06 - 0.4)) * kit.smooth(0.1, 0.5, 1.0 - d)  # the shell's plates
    h = 0.3 + 2.0 * kit.smooth(0.0, 0.18, 1.0 - d) + dome + plates + 0.8 * kit.noise(x, z, 11.0) * kit.smooth(3.0, 8.0, dome)
    return pad(h, x, z, T_PADS)


# --- SALTPAN KEY ---
S_SHORE = dome_shore(170.0, 0.12, 0.06, 2.0)
S_PADS = [(10.0, 30.0, 17.0, 1.05), (-45.0, -58.0, 13.0, 6.2)]


def saltpan(x, z):
    ang = math.atan2(z, x)
    d = math.hypot(x, z) / S_SHORE(ang)
    if d > 1.0:
        return sea_beyond(d, x, z)
    h = 0.3 + 0.8 * kit.smooth(0.0, 0.2, 1.0 - d) + 0.15 * kit.noise(x * 0.5, z * 0.5, 5.0)
    h += 7.5 * math.exp(-(((x + 45.0) / 42.0) ** 2 + ((z + 58.0) / 34.0) ** 2)) * kit.smooth(0.05, 0.3, 1.0 - d)
    return pad(h, x, z, S_PADS)


# --- SMUGGLER'S HOOK ---
H_SHORE = dome_shore(160.0, 0.08, 0.05, 4.1)
COVE, COVE_R = (45.0, 40.0), 70.0
H_PADS = [(-12.0, -22.0, 10.0, 1.4), (45.0, -38.0, 9.0, 1.0)]


def hook(x, z):
    ang = math.atan2(z, x)
    d = math.hypot(x, z) / H_SHORE(ang)
    dc = math.hypot(x - COVE[0], z - COVE[1]) / COVE_R
    if d > 1.0:
        h = sea_beyond(d, x, z)
    elif dc < 1.0:
        h = -2.6 + 1.2 * kit.smooth(0.7, 1.0, dc)  # the cove's water
    else:
        ridge = 24.0 * kit.smooth(1.1, 1.65, dc) * max(1.0 - d, 0.0) ** 0.55
        h = 0.3 + 1.2 * kit.smooth(1.0, 1.12, dc) * kit.smooth(0.0, 0.15, 1.0 - d) + ridge + 1.4 * kit.noise(x, z, 17.0) * kit.smooth(3.0, 9.0, ridge)
    return pad(h, x, z, H_PADS)


# --- PALM RING ATOLL ---
A_SHORE = dome_shore(220.0, 0.06, 0.07, 1.1)
A_PADS = [(186.0, 0.0, 9.0, 1.5)]


def atoll(x, z):
    ang = math.atan2(z, x)
    d = math.hypot(x, z) / A_SHORE(ang)
    width = 0.11 + 0.04 * math.sin(ang * 4.0 + 0.5)
    gap = abs(math.atan2(math.sin(ang - math.pi / 2), math.cos(ang - math.pi / 2))) < 0.11  # the channel in to the south
    ring = abs(d - 0.85) / width
    if d > 1.0:
        h = sea_beyond(d, x, z)
    elif ring < 1.0 and not gap:
        h = 0.3 + 1.6 * math.sqrt(max(1.0 - ring * ring, 0.0)) + 0.2 * kit.noise(x, z, 23.0)
    elif d < 0.85:
        h = -2.6 + 1.6 * kit.smooth(0.5, 0.0, abs(d - 0.85) / width - 1.0) * 0.0 - 0.4 * kit.noise(x * 0.3, z * 0.3, 4.0)  # the lagoon
    else:
        h = -1.0 - 1.5 * kit.smooth(0.0, 1.0, (d - 0.85 - width) * 6.0)
    if gap and 0.6 < d < 1.05:
        h = min(h, -2.2)
    return pad(h, x, z, A_PADS)


MID = {
    "turtleback": {"land": turtleback, "reach": 300.0, "cells": 210, "seed": 51, "pos": (1500.0, 5600.0),
                   "landing": (0.0, 165.0), "pois": {"hamlet": (0.0, 124.0), "crown": (0.0, -2.0)},
                   "places": [["stilt_hut", -15.0, 1.9, 156.0, 180.0, 1.0], ["stilt_hut", 0.0, 1.9, 160.0, 175.0, 1.0], ["stilt_hut", 15.0, 1.9, 154.0, 190.0, 1.0],
                              ["drying_rack", -7.0, 1.9, 140.0, 10.0, 1.0], ["drying_rack", 8.0, 1.9, 141.0, -12.0, 1.0], ["jetty", 0.0, 0.0, 170.0, 180.0, 1.0]],
                   "keep": [(0.0, 150.0, 22.0)], "avoid": [(-15.0, 156.0, 4.0), (0.0, 160.0, 5.0), (15.0, 154.0, 4.0), (-7.0, 140.0, 2.6), (8.0, 141.0, 2.6)], "jungle_above": 7.0},
    "saltpan": {"land": saltpan, "reach": 270.0, "cells": 190, "seed": 53, "pos": (-2100.0, 4400.0),
                "landing": (0.0, 160.0), "pois": {"pans": (10.0, 48.0), "works": (-36.0, -50.0)},
                "places": [["salt_pans", 10.0, 1.05, 30.0, 0.0, 1.0], ["salt_works", -45.0, 6.2, -58.0, 90.0, 1.0], ["jetty", 0.0, 0.0, 158.0, 180.0, 1.0]],
                "keep": [(10.0, 30.0, 14.0), (-45.0, -58.0, 10.0)], "avoid": [(10.0, 30.0, 12.0), (-45.0, -58.0, 8.5)], "jungle_above": 99.0, "dunes": True},
    "smugglers_hook": {"land": hook, "reach": 250.0, "cells": 190, "seed": 57, "pos": (-2350.0, 7600.0),
                       "landing": (-31.0, 40.0), "pois": {"cave": (-3.0, -12.0), "wreck": (30.0, -34.0)},
                       "places": [["cave", -12.0, 1.4, -22.0, 225.0, 1.0], ["wreck", 45.0, 0.6, -38.0, 80.0, 1.0], ["jetty", -27.0, 0.0, 40.0, -90.0, 1.0]],
                       "keep": [(-12.0, -22.0, 9.0), (45.0, -38.0, 8.0)], "avoid": [(-12.0, -22.0, 7.0), (45.0, -38.0, 6.0)], "jungle_above": 10.0},
    "palm_ring": {"land": atoll, "reach": 320.0, "cells": 230, "seed": 59, "pos": (500.0, 3900.0),
                  "landing": (200.0, 14.0), "pois": {"camp": (180.0, -8.0)},
                  "places": [["camp", 186.0, 1.5, 0.0, 90.0, 1.0]],
                  "keep": [(186.0, 0.0, 8.0)], "avoid": [(186.0, 0.0, 5.0)], "jungle_above": 99.0, "dunes": True},
}


def build_mid(iid):
    s = MID[iid]
    land, reach = s["land"], s["reach"]
    name = "isle_" + iid
    bpy.ops.wm.read_factory_settings(use_empty=True)

    def keep_out(x, z):
        return any(math.hypot(x - kx, z - kz) < kr for kx, kz, kr in s["keep"])

    def footprint(x, z):  # paths keep clear of the set pieces themselves (props of the whole keep area)
        return any(math.hypot(x - ax, z - az) < ar for ax, az, ar in s["avoid"])

    found = kit.route(land, reach, s["landing"], s["pois"], avoid=footprint)
    paths = [kit.smooth_path(line) for line in found.values()]
    index = kit.PathIndex(paths)

    def path_off(x, z):
        best = 99.0
        for a, b in index.near(x, z):
            best = min(best, kit.seg_dist(x, z, a, b)[0])
        return best

    def zone(x, z, h):
        if h < 2.4:
            return "dune" if s.get("dunes") and h > 0.9 else "beach"
        if kit.slope(land, x, z) > 0.6:
            return "rocky"
        return "jungle" if h > s["jungle_above"] else "meadow"

    def trodden(x, z):
        off = path_off(x, z)
        return 0.0 if off >= 3.5 else 0.7 * (1.0 - off / 3.5)

    obj = kit.ground(name, land, reach, s["cells"], trodden, lambda x, z: 1.0 if zone(x, z, land(x, z)) == "jungle" else 0.0)
    props = kit.scatter_zones(land, reach, s["seed"], zone, lambda x, z: path_off(x, z) < 3.5 or keep_out(x, z), density=0.6)
    props = [p for p in props if not (kit.SOLID.get(p[0]) is not None and path_off(p[1], p[3]) < (kit.SOLID[p[0]] or 2.0) * p[5] + 0.6)]
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
    print("ROUTE CHECK", iid, "problems=%d" % len(problems))
    routes = {"start": "landing", "pois": {k: [round(v[0], 2), round(v[1], 2)] for k, v in dict(s["pois"], landing=s["landing"]).items()},
              "walk_into": {}, "paths": [[[round(a, 2), round(b, 2)] for a, b in line] for line in paths]}
    kit.save(name, obj, props, "tools/blender/sea_isle_region1.py", s["places"], None, routes)
    print("POS", iid, s["pos"], "radius", round(reach * 0.62))


# --- ISLETS ---
ISLETS = [
    # id, sea position, shore radius, kind, seed
    ("islet_lone_rock", (2600.0, 6400.0), 16.0, "rock", 61),
    ("islet_bird_rock", (2200.0, 8600.0), 14.0, "bird", 62),
    ("islet_one_palm", (-2600.0, 5800.0), 10.0, "tree", 63),
    ("islet_sandbar_west", (-700.0, 4300.0), 26.0, "sand", 64),
    ("islet_one_tree", (1100.0, 7000.0), 9.0, "tree", 65),
    ("islet_little_arch", (-2700.0, 3400.0), 12.0, "arch", 66),
    ("islet_cormorant", (2700.0, 3300.0), 18.0, "rock", 67),
    ("islet_sandbar_north", (-200.0, 8000.0), 22.0, "sand", 68),
    ("islet_gannet_stack", (2700.0, 5100.0), 12.0, "bird", 69),
    ("islet_mast_shoal", (-1700.0, 3200.0), 20.0, "shoal", 70),
]


def islet_land(R, kind, seed):
    shore = dome_shore(R, 0.15, 0.1, seed * 0.37)
    top = {"rock": 6.0, "bird": 14.0, "tree": 2.6, "sand": 0.55, "arch": 4.0, "shoal": -0.7}[kind]

    def land(x, z):
        ang = math.atan2(z, x)
        d = math.hypot(x, z) / shore(ang)
        if d > 1.0:
            return -0.5 - 1.3 * kit.smooth(1.0, 1.3, d) - 6.0 * kit.smooth(1.4, 2.2, d) + 0.2 * kit.noise(x * 2, z * 2, seed)
        prof = (1.0 - d * d) ** (0.5 if kind in ("rock", "bird") else 1.4)
        return (0.25 if kind != "shoal" else -1.6) + top * prof + 0.6 * kit.noise(x * 1.5, z * 1.5, seed) * (1.0 if kind in ("rock", "bird", "arch") else 0.2)
    return land


def build_islet(entry):
    iid, pos, R, kind, seed = entry
    name = "isle_" + iid
    bpy.ops.wm.read_factory_settings(use_empty=True)
    land = islet_land(R, kind, seed)
    reach = R * 2.4
    obj = kit.ground(name, land, reach, 60)
    rnd = random.Random(seed)
    props = []

    def zone(x, z, h):
        if kind in ("rock", "bird", "arch") and h > 1.5:
            return "rocky"
        return "beach"
    if kind != "shoal":
        props = kit.scatter_zones(land, reach, seed, zone, None, density=0.5)
    if kind == "tree":
        props = [p for p in props if p[0] not in ("palm_a", "palm_b", "broadleaf_a", "broadleaf_b")]
        props.append(["palm_a" if seed % 2 else "broadleaf_a", 0.0, round(land(0.0, 0.0) - 0.1, 2), 0.0, rnd.uniform(0, 360), 1.15])
    places = []
    if kind == "arch":
        places.append(["sea_arch", 0.0, 0.0, -R * 1.6, 30.0, 0.45])
    if kind == "shoal":  # rocks breaking the surface round a mast standing out of the sea
        for k in range(7):
            a = 2 * math.pi * k / 7 + rnd.uniform(-0.3, 0.3)
            props.append(["boulder_b", round(math.cos(a) * R * 0.8, 2), -0.6, round(math.sin(a) * R * 0.8, 2), rnd.uniform(0, 360), rnd.uniform(0.7, 1.2)])
        places.append(["wreck", 0.0, -3.2, 0.0, 40.0, 0.8])
    if kind == "bird":
        for k in range(rnd.randint(1, 3)):
            a = rnd.uniform(0, 2 * math.pi)
            props.append(["sea_stack", round(math.cos(a) * R * 1.9, 2), 0.0, round(math.sin(a) * R * 1.9, 2), rnd.uniform(0, 360), rnd.uniform(0.4, 0.7)])
    kit.save(name, obj, props, "tools/blender/sea_isle_region1.py", places)
    print("POS", iid, pos, "radius", round(R * 1.6))


if __name__ == "__main__":
    want = sys.argv[1:]
    for iid in MID:
        if not want or iid in want:
            build_mid(iid)
    for e in ISLETS:
        if not want or e[0] in want or "islets" in want:
            build_islet(e)
