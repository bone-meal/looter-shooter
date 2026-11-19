# Purpose: developer-time tool. Region 1's three PUZZLE ISLANDS (sea step 9d, LOCKED: a mix of one outdoor puzzle and
# small vaults; 3 islands, a chest each and a chart piece; Grapple Hook + no-tool puzzles), built with the island kit:
#   STACKWATER ROCKS  a rocky islet among sea stacks; the OUTDOOR puzzle court (data/sea/dungeons.json
#                     stackwater_court: walls, a sluice channel, stacks to hook onto) stands on a levelled shelf whose
#                     ground is dug out under the court's water cells
#   BELLROCK          a round grassy island with a bell-shaped crag; a small shrine (sea_shrine) round the Bellrock
#                     Vault's gate
#   GULLHOOK CAY      a hooked sandy cay with a rocky head; a small shrine round the Gullhook Vault's gate
# Each: generated paths from its jetty to its puzzle (ROUTE CHECK at build), zoned props, a few rocks / stacks.
# -> assets/models/sea/isle_<id>.glb + data/sea/isles/isle_<id>.json. Islands in data/sea/islands.json; the court's
# and gates' sea positions in data/sea/dungeons.json follow ISLANDS below (printed at the end).
# Run: python3 tools/blender/sea_isle_puzzles.py [id ...]   (set pieces first: tools/blender/sea_isle_places.py)
# AFTER a run: import (tools/import_assets.tscn), then RE-BAKE the island collision (tools/bake_isle_shapes.tscn,
# sea step 13g) or the changed island loads its collision the slow way.
# Dependencies: bpy, tools/blender/sea_isle_kit.py, data/sea/dungeons.json (the court's map). No game code.
import json
import math
import os
import random
import sys

sys.path.insert(0, os.path.dirname(__file__))
import bpy
import sea_isle_kit as kit

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
TILE = 3.0
# id: sea position, shore radius, wobble (a3, a5, phase), hills [(x, z, sx, sz, height)], puzzle
ISLANDS = {
    "stackwater": {"pos": (-1500.0, 8200.0), "r": 72.0, "wobble": (0.16, 0.09, 1.3), "hills": [(30.0, -40.0, 30.0, 22.0, 9.0), (-38.0, -30.0, 22.0, 18.0, 7.0)],
                   "court": {"id": "stackwater_court", "c0": (-21.0, -24.0), "y": 4.0}, "jetty_x": 8.0, "seed": 41, "stacks": 9},
    "bellrock": {"pos": (700.0, 8500.0), "r": 85.0, "wobble": (0.08, 0.05, 0.4), "hills": [(-30.0, -35.0, 26.0, 26.0, 22.0), (25.0, -15.0, 40.0, 30.0, 6.0)],
                 "shrine": {"gate": (0.0, -20.0), "h": 5.0}, "jetty_x": 10.0, "seed": 43, "stacks": 2},
    "gullhook": {"pos": (2400.0, 4300.0), "r": 70.0, "wobble": (0.22, 0.1, 2.2), "hills": [(-25.0, -30.0, 22.0, 20.0, 14.0)],
                 "shrine": {"gate": (0.0, -15.0), "h": 4.0}, "jetty_x": -6.0, "seed": 47, "stacks": 4},
}


def court_map(cid):
    d = json.load(open(os.path.join(ROOT, "data", "sea", "dungeons.json")))
    return d["dungeons"][cid]["map"]


class Island:
    def __init__(self, iid, spec):
        self.id, self.s = iid, spec
        self.R = spec["r"]
        self.reach = self.R * 1.55
        self.rows = court_map(spec["court"]["id"]) if "court" in spec else None

    def shore(self, ang):
        a3, a5, ph = self.s["wobble"]
        return self.R * (1.0 + a3 * math.sin(3 * ang + ph) + a5 * math.sin(5 * ang + 2 * ph))

    def natural(self, x, z):
        ang = math.atan2(z, x)
        d = math.hypot(x, z) / self.shore(ang)
        if d > 1.0:
            return -0.5 - 1.3 * kit.smooth(1.0, 1.2, d) - 7.0 * kit.smooth(1.28, 1.55, d) + 0.25 * kit.noise(x * 2, z * 2, 3.0)
        h = 0.25 + 2.3 * kit.smooth(0.0, 0.25, 1.0 - d)
        for hx, hz, sx, sz, hh in self.s["hills"]:
            h += hh * math.exp(-(((x - hx) / sx) ** 2 + ((z - hz) / sz) ** 2)) * kit.smooth(0.02, 0.3, 1.0 - d)
        return h + 1.8 * kit.noise(x, z, self.s["seed"]) * kit.smooth(3.0, 8.0, h)

    # --- the puzzle's ground ---
    def court_cell(self, x, z):
        c0 = self.s["court"]["c0"]
        return int(round((x - c0[0]) / TILE)), int(round((z - c0[1]) / TILE))

    def court_char(self, i, j):
        if 0 <= j < len(self.rows) and 0 <= i < len(self.rows[0]):
            return self.rows[j][i]
        return " "

    def land(self, x, z):
        h = self.natural(x, z)
        if "court" in self.s:
            c0, y = self.s["court"]["c0"], self.s["court"]["y"]
            w, dpt = len(self.rows[0]) * TILE, len(self.rows) * TILE
            dx = max(c0[0] - 1.5 - x, 0.0, x - (c0[0] - 1.5 + w))
            dz = max(c0[1] - 1.5 - z, 0.0, z - (c0[1] - 1.5 + dpt))
            out = math.hypot(dx, dz)
            if out < 12.0:  # the shelf: just under the court's paving, blended into the island over 12 m
                h = (y - 0.15) + (h - (y - 0.15)) * kit.smooth(1.0, 12.0, out)
            i, j = self.court_cell(x, z)
            if self.court_char(i, j) in "=_":  # dug out under the court's water (the pits' floor is 3 m down)
                h = y - 3.4
        if "shrine" in self.s:
            gx, gz = self.s["shrine"]["gate"]
            d = math.hypot(x - gx, (z - gz - 5.0) * 0.85)
            if d < 22.0:
                hh = self.s["shrine"]["h"]
                h = hh + (h - hh) * kit.smooth(11.0, 22.0, d)
        return h

    def jetty(self):
        x, z = self.s["jetty_x"], self.R * 0.5
        while self.land(x, z) > 1.25 and z < self.reach:
            z += 0.5
        return x, z

    def pois(self):
        jx, jz = self.jetty()
        if "court" in self.s:
            c0 = self.s["court"]["c0"]
            entry = (c0[0] + 7 * TILE, c0[1] + (len(self.rows) - 1) * TILE + 6.0)
            return {"landing": (jx, jz - 4.0), "court": entry}
        gx, gz = self.s["shrine"]["gate"]
        return {"landing": (jx, jz - 4.0), "shrine": (gx, gz + 15.0)}

    def avoid(self, x, z):
        if "court" in self.s:
            c0 = self.s["court"]["c0"]
            return c0[0] - 2.0 < x < c0[0] + len(self.rows[0]) * TILE - 1.0 and c0[1] - 2.0 < z < c0[1] + (len(self.rows) - 2) * TILE
        gx, gz = self.s["shrine"]["gate"]
        return math.hypot(x - gx, z - gz - 4.0) < 9.0

    def zone(self, x, z, h):
        if h < 2.4:
            return "beach"
        if h > 9.0 or kit.slope(self.land, x, z) > 0.55:
            return "rocky"
        return "jungle" if (self.id == "bellrock" and z < 0) else "meadow"


def build(iid):
    isl = Island(iid, ISLANDS[iid])
    name = "isle_" + iid
    bpy.ops.wm.read_factory_settings(use_empty=True)
    pois = isl.pois()
    found = kit.route(isl.land, isl.reach, pois["landing"], {k: v for k, v in pois.items() if k != "landing"}, avoid=isl.avoid)
    paths = [kit.smooth_path(line) for line in found.values()]
    index = kit.PathIndex(paths)
    def path_off(x, z):
        best = 99.0
        for a, b in index.near(x, z):
            best = min(best, kit.seg_dist(x, z, a, b)[0])
        return best
    def trodden(x, z):
        off = path_off(x, z)
        return 0.0 if off >= 3.5 else 0.7 * (1.0 - off / 3.5)
    obj = kit.ground(name, isl.land, isl.reach, 150, trodden, lambda x, z: 1.0 if isl.zone(x, z, isl.land(x, z)) == "jungle" else 0.0)
    def clear(x, z):
        return path_off(x, z) < 3.5 or isl.avoid(x, z) or ("court" in isl.s and isl.court_char(*isl.court_cell(x, z)) != " ")
    props = kit.scatter_zones(isl.land, isl.reach, isl.s["seed"], isl.zone, clear, density=0.55)
    rnd = random.Random(isl.s["seed"] + 1)
    for k in range(isl.s["stacks"]):  # sea stacks round it (Stackwater: many)
        ang = rnd.uniform(0, 2 * math.pi)
        x, z = math.cos(ang) * (isl.shore(ang) + rnd.uniform(18, 45)), math.sin(ang) * (isl.shore(ang) + rnd.uniform(18, 45))
        props.append(["sea_stack", round(x, 2), 0.0, round(z, 2), round(rnd.uniform(0, 360), 1), round(rnd.uniform(0.6, 1.2), 2)])
    props = [p for p in props if not (kit.SOLID.get(p[0]) is not None and path_off(p[1], p[3]) < (kit.SOLID[p[0]] or 2.0) * p[5] + 0.6)]
    places = []
    jx, jz = isl.jetty()
    places.append(["jetty", round(jx, 2), 0.0, round(jz, 2), 180.0, 1.0])
    if "shrine" in isl.s:
        gx, gz = isl.s["shrine"]["gate"]
        places.append(["sea_shrine", gx, isl.s["shrine"]["h"], gz, 180.0, 1.0])
    problems = ["%s: no way found" % k for k in pois if k != "landing" and k not in found]
    for line in paths:
        for a, b in zip(line, line[1:]):
            ha, hb = isl.land(*a), isl.land(*b)
            run = max(math.hypot(b[0] - a[0], b[1] - a[1]), 0.5)
            if abs(hb - ha) / run > 0.75:
                problems.append("steep at (%.0f, %.0f): %.2f" % (a[0], a[1], abs(hb - ha) / run))
            if min(ha, hb) < 0.1:
                problems.append("under the sea at (%.0f, %.0f)" % (a[0], a[1]))
    for line in problems:
        print("ROUTE PROBLEM", iid, line)
    print("ROUTE CHECK", iid, "problems=%d" % len(problems))
    walk_into = {}
    if "shrine" in isl.s:
        gx, gz = isl.s["shrine"]["gate"]
        walk_into["shrine"] = [gx, gz + 4.5]
    else:
        e = pois["court"]
        walk_into["court"] = [e[0], e[1] - 7.0]
    routes = {"start": "landing", "pois": {k: [round(v[0], 2), round(v[1], 2)] for k, v in pois.items()}, "walk_into": walk_into,
        "paths": [[[round(a, 2), round(b, 2)] for a, b in line] for line in paths]}
    kit.save(name, obj, props, "tools/blender/sea_isle_puzzles.py", places, None, routes)
    px, pz = isl.s["pos"]
    if "court" in isl.s:
        c0 = isl.s["court"]["c0"]
        print("COURT", isl.s["court"]["id"], "at", (px + c0[0], pz + c0[1]), "y", isl.s["court"]["y"])
    else:
        gx, gz = isl.s["shrine"]["gate"]
        print("GATE", iid, "at", (px + gx, pz + gz), "ground", isl.s["shrine"]["h"])


if __name__ == "__main__":
    for iid in (sys.argv[1:] or list(ISLANDS)):
        build(iid)
