# Purpose: developer-time tool. CORALBACK REEF (sea step 9c-3, LOCKED: a new reef island ~300 m in region 1 with a
# ruined sea temple and the Tidewater Temple's gate, built with the island kit, a few things to find round it):
# assets/models/sea/isle_reef.glb + data/sea/isles/isle_reef.json (props, set pieces, the paths for the walk check).
# The design, island-local metres (x east, z south): a low island ~300 m across on a wide reef flat (coral, reef
# rocks in the shallows); white beaches all round, a jungle-grown rocky SPINE along the north rising to ~18 m; on its
# shoulder the ruined SEA TEMPLE on a levelled terrace (its court opens south over the island, the gate at its back);
# a broken LOOKOUT tower on the north-east knoll; a beached WRECK on the west beach; TIDE POOLS on the east rocks; a
# JETTY on the south beach where ships land; a sea arch and stacks off the north. Paths are generated (kit.route) from
# the jetty to every place and checked here (ROUTE CHECK) like the start island's.
# Run: python3 tools/blender/sea_isle_reef.py   (bpy as a module; the set pieces first: tools/blender/sea_isle_places.py)
# Dependencies: bpy, tools/blender/sea_isle_kit.py. The gate's sea position (data/sea/dungeons.json tidewater_temple
# entrance) and the island's (data/sea/islands.json "reef") follow GATE / TEMPLE_YAW below.
import math
import os
import random
import sys

sys.path.insert(0, os.path.dirname(__file__))
import bpy
import sea_isle_kit as kit

NAME = "isle_reef"
R = 150.0  # shore radius (m)
REACH = R * 1.5
GATE = (-10.0, -52.0)  # the dungeon gate (island-local), facing south (+z); the ruin's court opens south from it
TERRACE = (GATE[0], GATE[1] + 10.0, 25.0, 12.0)  # x, z, radius, height of the levelled terrace the temple stands on
LOOKOUT = (78.0, -70.0)
WRECK_ANG = math.pi + 0.15
POOLS_ANG = 0.35
JETTY_X = 18.0
WALK_INTO = {}
AVOID = []


def shore(ang):
    return R * (1.0 + 0.12 * math.sin(3 * ang + 0.7) + 0.07 * math.sin(5 * ang + 2.1))


def polar(ang, r):
    return (math.cos(ang) * r, math.sin(ang) * r)


def gauss(x, z, cx, cz, sx, sz):
    return math.exp(-(((x - cx) / sx) ** 2 + ((z - cz) / sz) ** 2))


def natural(x, z):
    ang = math.atan2(z, x)
    d = math.hypot(x, z) / shore(ang)
    if d > 1.0:  # the reef flat a metre or two under, then the drop to deep water
        return -0.5 - 1.3 * kit.smooth(1.0, 1.2, d) - 7.0 * kit.smooth(1.28, 1.5, d) + 0.3 * kit.noise(x * 2, z * 2, 3.0)
    beach = 0.25 + 2.3 * kit.smooth(0.0, 0.22, 1.0 - d)
    spine = 15.0 * gauss(x, z, 0.0, -55.0, 95.0, 36.0) * kit.smooth(0.02, 0.3, 1.0 - d)
    knoll = 6.0 * gauss(x, z, LOOKOUT[0], LOOKOUT[1], 22.0, 22.0)
    rough = 2.2 * kit.noise(x, z, 7.0) * kit.smooth(4.0, 9.0, spine + knoll)
    return beach + spine + knoll + rough


def land(x, z):
    h = natural(x, z)
    tx, tz, tr, th = TERRACE
    d = math.hypot(x - tx, z - tz)
    if d < tr + 14.0:  # the temple's terrace, blended into the hill over 14 m
        h = th + (h - th) * kit.smooth(tr, tr + 14.0, d)
    d = math.hypot(x - LOOKOUT[0], z - LOOKOUT[1])
    if d < 12.0:
        flat = natural(LOOKOUT[0], LOOKOUT[1])
        h = flat + (h - flat) * kit.smooth(5.0, 12.0, d)
    return h


def jetty_spot():
    """The jetty's land end: on the south beach where the ground is about 1.2 m high."""
    z = 60.0
    while land(JETTY_X, z) > 1.25:
        z += 0.5
    return JETTY_X, z


def places_list():
    jx, jz = jetty_spot()
    wx, wz = polar(WRECK_ANG, shore(WRECK_ANG) - 9.0)
    px, pz = polar(POOLS_ANG, shore(POOLS_ANG) - 14.0)
    return {
        "landing": (jx, jz - 4.0), "temple": (GATE[0], GATE[1] + 30.0), "lookout": (LOOKOUT[0], LOOKOUT[1] + 7.0),
        "wreck": (wx + 14.0, wz), "tide_pools": (px - 8.0, pz),
    }


START = "landing"
_PATHS = []
_INDEX = []


def paths():
    if not _PATHS:
        pois = places_list()
        found = kit.route(land, REACH, pois[START], {k: v for k, v in pois.items() if k != START},
            avoid=lambda x, z: any(math.hypot(x - ax, z - az) < ar for ax, az, ar in AVOID))
        for k in pois:
            if k != START and k not in found:
                print("ROUTE PROBLEM", k, "no way found")
        _PATHS.extend(kit.smooth_path(line) for line in found.values())
        _INDEX.append(kit.PathIndex(_PATHS))
    return _PATHS


def path_off(x, z):
    best = 99.0
    for a, b in _INDEX[0].near(x, z):
        best = min(best, kit.seg_dist(x, z, a, b)[0])
    return best


def trodden(x, z):
    off = path_off(x, z)
    return 0.0 if off >= 3.5 else 0.7 * (1.0 - off / 3.5)


def route_check():
    """Every place lies at the end of a path from the landing, every step of every path above the sea and at most
    0.75 up per metre on the ground as built."""
    problems = []
    for line in paths():
        for a, b in zip(line, line[1:]):
            ha, hb = land(*a), land(*b)
            run = max(math.hypot(b[0] - a[0], b[1] - a[1]), 0.5)
            if abs(hb - ha) / run > 0.75:
                problems.append("steep at (%.0f, %.0f): %.2f" % (a[0], a[1], abs(hb - ha) / run))
            if min(ha, hb) < 0.1:
                problems.append("under the sea at (%.0f, %.0f)" % (a[0], a[1]))
    ends = [line[-1] for line in paths()]
    for k, v in places_list().items():
        if k != START and not any(math.hypot(e[0] - v[0], e[1] - v[1]) < 1.0 for e in ends):
            problems.append("%s has no path" % k)
    return problems


def zone(x, z, h):
    if h < 2.4:
        return "beach"
    if h > 10.0 or kit.slope(land, x, z) > 0.55:
        return "rocky"
    if z < 10.0:
        return "jungle"
    return "meadow"


def place():
    tx, tz, tr, _th = TERRACE
    def clear(x, z):
        return path_off(x, z) < 3.5 or math.hypot(x - tx, z - tz) < tr + 2.0 or math.hypot(x - LOOKOUT[0], z - LOOKOUT[1]) < 7.0
    props = kit.scatter_zones(land, REACH, 31, zone, clear, density=0.55)
    rnd = random.Random(32)
    for ang in (-1.3, -1.7, -2.05, -0.95):  # sea stacks off the north
        x, z = polar(ang, shore(ang) + rnd.uniform(35, 60))
        props.append(["sea_stack", round(x, 2), 0.0, round(z, 2), round(rnd.uniform(0, 360), 1), round(rnd.uniform(0.8, 1.3), 2)])
    for k in range(10):  # tumbled temple blocks on the slope below the terrace
        kit.put(props, rnd, land, "ruin_wall", tx + rnd.uniform(-40, 40), tz + rnd.uniform(28, 45), rnd.uniform(0.7, 1.1), 0.2)
    def blocks(p):
        r = kit.SOLID.get(p[0])
        return r is not None and path_off(p[1], p[3]) < (r if r > 0 else 2.0) * p[5] + 0.6
    props = [p for p in props if not blocks(p)]
    places = []
    def put_place(model, x, z, yaw, y=None, scale=1.0):
        places.append([model, round(x, 2), round(land(x, z) if y is None else y, 2), round(z, 2), yaw, scale])
    put_place("sea_temple", GATE[0], GATE[1], 180.0, TERRACE[3])
    put_place("sea_lookout", LOOKOUT[0], LOOKOUT[1], 180.0)
    wx, wz = polar(WRECK_ANG, shore(WRECK_ANG) - 9.0)
    put_place("wreck", wx, wz, 70.0)
    for k in range(2):
        a = POOLS_ANG + (k - 0.5) * 0.06
        x, z = polar(a, shore(a) - 6.0)
        put_place("tide_pool", x, z, round(rnd.uniform(0, 360), 1), round(max(land(x, z), 0.15), 2))
    jx, jz = jetty_spot()
    put_place("jetty", jx, jz, 180.0, 0.0)
    WALK_INTO["temple"] = (GATE[0], GATE[1] + 16.0)  # (into the court, short of its basin)
    ax, az = polar(-0.55, shore(-0.55) + 55.0)
    put_place("sea_arch", ax, az, 120.0, 0.0, 0.7)
    return props, places


def main():
    AVOID.extend([(GATE[0], GATE[1] + 6.0, 11.0), (LOOKOUT[0], LOOKOUT[1], 4.0)])
    bpy.ops.wm.read_factory_settings(use_empty=True)
    paths()
    obj = kit.ground(NAME, land, REACH, 170, trodden, lambda x, z: 1.0 if zone(x, z, land(x, z)) == "jungle" else 0.0)
    props, places = place()
    problems = route_check()
    for line in problems:
        print("ROUTE PROBLEM", line)
    print("ROUTE CHECK", "problems=%d" % len(problems))
    pois = places_list()
    routes = {"start": START, "pois": {k: [round(v[0], 2), round(v[1], 2)] for k, v in pois.items()},
        "walk_into": {k: [round(v[0], 2), round(v[1], 2)] for k, v in WALK_INTO.items()}, "paths": [[[round(a, 2), round(b, 2)] for a, b in line] for line in paths()]}
    kit.save(NAME, obj, props, "tools/blender/sea_isle_reef.py", places, None, routes)
    print("gate", GATE, "terrace height", TERRACE[3], "jetty", jetty_spot())


if __name__ == "__main__":
    main()
