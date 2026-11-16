# Purpose: developer-time tool. The SHOWCASE start island of region 1 (director: an island kit + one hand-designed start
# island as the art target; ground = textured blend + plenty of props). Builds assets/models/sea/isle_start.glb and
# data/sea/isles/isle_start.json through the island kit (tools/blender/sea_isle_kit.py: ground painting, prop rules);
# this file is only the island's shape and its hand-placed bits (sea stacks, headland boulders, ruined walls, the path
# and the shipyard's clear ground). The design, island-local metres (x east, z south):
#   north   sheer cliffs 20-30 m dropping into deep water, sea stacks off them
#   centre  a ridge rising to a 40 m peak in the north-west, a lower hill in the south
#   east    a sheltered cove (the slipway's beach, data/sea/ships.json shipyard) opening to the east
#   south   a long sandy beach with a dune line and palms
#   west    a rocky headland reaching out with tide-washed boulders
#   between a high meadow above the cove where new arrivals land (data/sea/islands.json spawn), a path down to the slipway
# Run: python3 tools/blender/sea_isle_start.py   (bpy as a module)
# Dependencies: bpy, tools/blender/sea_isle_kit.py. No game code.
import math
import os
import random
import sys

sys.path.insert(0, os.path.dirname(__file__))
import bpy
from sea_isle_kit import noise, smooth
import sea_isle_kit as kit

NAME = "isle_start"
REACH = 150.0  # metres from the centre the ground mesh covers (the sea floor beyond the shore included)
CELLS = 220
COVE = (78.0, 6.0, 30.0)  # x, z, radius of the cove's water


def shore_radius(ang):
    r = 92.0 * (1.0 + 0.1 * math.sin(3 * ang + 1.0) + 0.06 * math.sin(5 * ang + 2.2) + 0.035 * math.sin(9 * ang + 0.4))
    west = math.exp(-((math.atan2(math.sin(ang - math.pi), math.cos(ang - math.pi))) / 0.22) ** 2)
    r += 34.0 * west  # the headland
    return r


def northness(ang):
    return max(0.0, -math.sin(ang)) ** 1.5  # z < 0 is north


def land(x, z):
    """Ground height (m above sea level) at island-local x, z; and how much of it is cliff (0..1)."""
    ang = math.atan2(z, x)
    north = northness(ang)
    r = math.hypot(x, z) + north * 5.0 * noise(x * 0.9, z * 0.9, 4.0)  # a ragged cliff line with small inlets
    R = shore_radius(ang)
    t = (R - r) / R  # 0 at the shoreline, 1 at the centre, negative at sea
    ridge = 40.0 * math.exp(-(((x + 22) / 34.0) ** 2 + ((z + 28) / 30.0) ** 2))
    hill = 16.0 * math.exp(-(((x - 18) / 24.0) ** 2 + ((z - 34) / 20.0) ** 2))
    meadow = 9.0 * math.exp(-(((x - 22) / 20.0) ** 2 + ((z + 4) / 16.0) ** 2))
    inland = 5.0 + max(ridge, hill, meadow) + 0.6 * ridge * 0.3 + 2.2 * noise(x, z, 3.0)
    cliff = 0.0
    if t < 0.0:  # the shelf under the sea, steeper under the cliffs
        east = max(0.0, math.cos(ang))  # deep water off the cove so launched ships float
        h = -0.4 + t * R * (0.18 + 0.6 * north + 0.3 * east)
        h = max(h, -14.0 - 4.0 * north)
    else:
        beach_w = 0.24 * (1.0 - north) + 0.012
        u = min(t / beach_w, 1.0)
        beach = 0.15 + 1.9 * u * u
        rise = smooth(beach_w, beach_w + 0.18 * (1.0 - north) + 0.03, t)
        h = beach * (1.0 - rise) + inland * rise
        if north > 0.25:  # cliffs: a high plateau 20-30 m up runs right to the edge
            sheer = smooth(0.25, 0.6, north)
            top = max(inland, (22.0 + 6.0 * noise(x, z, 9.0)) * (1.0 - smooth(0.18, 0.5, t)))
            plateau = top * smooth(0.0, 0.04, t)
            cliff = sheer * (1.0 - smooth(0.0, 0.22, t))
            h = h * (1.0 - sheer) + plateau * sheer
        west = math.exp(-((math.atan2(math.sin(ang - math.pi), math.cos(ang - math.pi))) / 0.3) ** 2)
        h += west * 2.5 * noise(x * 2.0, z * 2.0, 7.0)  # a rough rocky headland
    cx, cz, cr = COVE
    dc = math.hypot(x - cx, z - cz) if x < cx else abs(z - cz)  # east of its centre the cove runs out to sea as a channel
    if dc < cr * 1.55:
        water = -5.5 * (1.0 - smooth(cr * 0.5, cr, dc)) - 0.12 * max(0.0, x - cx)
        bank = 0.25 + 1.7 * smooth(cr * 0.85, cr * 1.4, dc)
        shore = smooth(cr * 0.85, cr * 1.55, dc)
        if dc < cr * 0.85:
            h = min(h, water)
        else:
            h = min(h, bank * (1.0 - shore) + h * shore)
    # the shipyard's flat yard and the slipway's bed (the ramp runs island-local x 44 -> 66 at z 6, top 0.6 m, foot -2 m)
    w = (1.0 - smooth(7.0, 13.0, abs(z - 6.0))) * smooth(28.0, 36.0, x)
    if w > 0.0:
        bed = 0.35 if x < 45.0 else 0.35 - (x - 45.0) * 0.13
        h = min(h, h * (1.0 - w) + bed * w)
    return h, cliff


PATH = ((22.0, -4.0), (34.0, 2.0), (44.0, 6.0))  # meadow -> slipway top, island-local


def path_off(x, z):
    best = 99.0
    for (ax, az), (bx, bz) in zip(PATH, PATH[1:]):
        dx, dz = bx - ax, bz - az
        t = max(0.0, min(1.0, ((x - ax) * dx + (z - az) * dz) / (dx * dx + dz * dz)))
        best = min(best, math.hypot(x - ax - dx * t, z - az - dz * t))
    return best


def height(x, z):
    return land(x, z)[0]


def trodden(x, z):  # the trodden path from the meadow down to the slipway
    off = path_off(x, z)
    return 0.7 * (1.0 - off / 2.2) if off < 2.2 else 0.0


def clear(x, z):  # the shipyard's ground (data/sea/ships.json shipyard sits at island-local (52, 6)), the path, the landing
    return (36.0 < x < 72.0 and abs(z - 6.0) < 9.0) or path_off(x, z) < 1.6 or math.hypot(x - 22.0, z + 4.0) < 5.0


def place():
    """The kit's rule-scattered props plus this island's hand-placed ones."""
    out = kit.scatter(height, REACH, 7, clear)
    rnd = random.Random(8)
    for ang in (-1.25, -1.6, -1.9, -2.25):  # sea stacks off the north cliffs
        r = shore_radius(ang) + rnd.uniform(14, 26)
        x, z = r * math.cos(ang), r * math.sin(ang)
        out.append(["sea_stack", round(x, 2), 0.0, round(z, 2), round(rnd.uniform(0, 360), 1), round(rnd.uniform(0.8, 1.2), 2)])
    for k in range(9):  # the headland's tide-washed boulders
        ang = math.pi + rnd.uniform(-0.25, 0.25)
        r = shore_radius(ang) + rnd.uniform(-12, 8)
        kit.put(out, rnd, height, "boulder_b", r * math.cos(ang), r * math.sin(ang), rnd.uniform(1.0, 2.2), 0.6)
    kit.put(out, rnd, height, "ruin_wall", 14.0, -12.0, 1.0, 0.1)  # a ruined wall on the meadow above the cove
    kit.put(out, rnd, height, "ruin_wall", 18.0, -8.0, 0.9, 0.2)
    return out


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    obj = kit.ground(NAME, height, REACH, CELLS, trodden)
    kit.save(NAME, obj, place(), "tools/blender/sea_isle_start.py")


main()
