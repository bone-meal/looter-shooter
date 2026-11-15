# Purpose: developer-time script. Models the eight gun bodies of sea step 2 (original designs in the style of the
# firearm types they are named after: SMG, revolver, lever-action rifle, harpoon gun, flare gun, flamethrower,
# crossbow, blunderbuss) with tools/blender/kit.py and exports them to assets/models/weapons/<weapon id>.gltf,
# sharing assets/models/weapons/textures/ with tools/blender/weapons.py. Same conventions as that file: points down
# the barrel, "Sight" (iron-sight height), "Support" (left hand; none = held in one hand), "Barrel" / "Mag" (scaled /
# hidden by gun parts), "Mount<Slot>" (part models). Moving parts the game animates (game/gun_actions.gd): "Bolt",
# "Cylinder", "Hammer", "Lever", "Breech", "Spear", "StringDrawn" / "StringLoose", "Arrow", "Needle", plus the
# markers "Nozzle" and "Pilot" (where the flamethrower's flame and pilot light sit).
# Run: python3 tools/blender/weapons_sea.py   (from the project folder; needs pip packages bpy, numpy, pillow)
import math
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
import kit
from weapons import OUT, SPECS, guard, pins

MORE = {"orange": ("polymer", (0.9, 0.36, 0.06), 9), "brass": ("paint", (0.52, 0.38, 0.15), 10),
    "red": ("paint", (0.6, 0.09, 0.07), 11), "cord": ("polymer", (0.78, 0.73, 0.58), 12), "rubber": ("polymer", (0.11, 0.1, 0.1), 13)}


def smg(m, M):
    m.node("Barrel", (0, 0.012, 0.3))
    m.node("Mag", (0, -0.03, 0.11))
    m.node("Bolt", (0, 0.03, 0.18))  # the cocking handle: snaps back with every shot
    m.prof(M["black"], 0.05, [(-0.13, -0.03), (0.29, -0.03), (0.29, 0.05), (0.26, 0.062), (-0.1, 0.062), (-0.13, 0.045)], bevel=0.007)
    m.box(M["dark"], (0.024, 0.012, 0.3), (0, 0.068, 0.08), bevel=0.002)  # top rail
    for i in range(10):
        m.box(M["dark"], (0.028, 0.006, 0.012), (0, 0.077, -0.04 + 0.026 * i), bevel=0.001)
    m.cyl(M["dark"], 0.026, 0.27, 0.42, 0.012, segs=18, bevel=0.004)  # barrel shroud with cooling holes
    for i in range(5):
        m.cylx(M["black"], 0.006, -0.027, 0.027, 0.3 + 0.024 * i, 0.012, segs=8)
    m.cyl(M["steel"], 0.01, 0.3, 0.53, 0.012, node="Barrel")
    m.cyl(M["dark"], 0.014, 0.5, 0.535, 0.012, bevel=0.003, node="Barrel")
    m.cyl(M["black"], 0.007, 0.532, 0.537, 0.012, bevel=0, node="Barrel")
    m.prof(M["dark"], 0.012, [(0.4, 0.035), (0.43, 0.035), (0.425, 0.075), (0.405, 0.075)], bevel=0.002)  # front sight
    m.prof(M["dark"], 0.03, [(0.08, -0.03), (0.14, -0.03), (0.155, -0.27), (0.1, -0.272)], bevel=0.004, node="Mag")  # stick magazine
    for i in range(4):
        m.box(M["black"], (0.031, 0.004, 0.05), (0, -0.08 - 0.045 * i, 0.12), tilt=-4, bevel=0.001, node="Mag")
    m.prof(M["black"], 0.036, [(-0.09, -0.028), (-0.025, -0.028), (-0.05, -0.17), (-0.11, -0.16)], bevel=0.009)  # grip
    for i in range(5):
        m.box(M["dark"], (0.038, 0.004, 0.04), (0, -0.06 - 0.022 * i, -0.075 + 0.005 * i), tilt=-12, bevel=0.001)
    guard(m, M["dark"], -0.025, 0.07, -0.03, 0.04)
    for side in (-1, 1):  # folded wire stock
        m.strip(M["steel"], 0.007, 0.007, [(-0.13, 0.03), (-0.42, 0.02), (-0.44, -0.07)], x=0.02 * side)
    m.box(M["rubber"], (0.05, 0.11, 0.016), (0, -0.03, -0.445), bevel=0.004)
    m.box(M["steel"], (0.012, 0.014, 0.03), (-0.031, 0.04, 0.18), bevel=0.002, node="Bolt")
    m.cylx(M["dark"], 0.006, -0.05, -0.03, 0.18, 0.04, node="Bolt")
    m.box(M["black"], (0.004, 0.014, 0.08), (-0.026, 0.04, 0.14), bevel=0.001)  # the slot it runs in
    pins(m, M["dark"], 0.05, [(-0.08, 0.0), (0.2, -0.01), (0.24, 0.03)], 0.004)
    m.empty("Sight", 0, 0.085, 0)
    m.empty("Support", 0, -0.035, 0.24)
    m.empty("MountMuzzle", 0, 0.012, 0.537, parent="Barrel")
    m.empty("MountSight", 0, 0.074, 0.06)
    m.empty("MountGrip", 0, -0.03, 0.24)
    m.empty("MountMag", 0, -0.03, 0.11)


def revolver(m, M):
    m.node("Barrel", (0, 0.032, 0.08))
    m.node("Cylinder", (0, 0.024, 0.045))  # turns one chamber with every shot, spins out to the left to reload
    m.node("Hammer", (0, 0.04, -0.022))
    m.prof(M["frame"], 0.03, [(-0.03, -0.012), (0.085, -0.012), (0.085, 0.002), (0.012, 0.002), (0.012, 0.046), (0.085, 0.046), (0.085, 0.056), (-0.012, 0.056), (-0.03, 0.04)], bevel=0.004)
    m.cyl(M["steel"], 0.023, 0.014, 0.078, 0.024, segs=24, bevel=0.003, node="Cylinder")
    for k in range(6):
        a = 2 * math.pi * k / 6
        m.box(M["dark"], (0.006, 0.006, 0.05), (0.023 * math.cos(a), 0.024 + 0.023 * math.sin(a), 0.046), bevel=0.001, node="Cylinder")  # flutes
        m.cyl(M["black"], 0.0045, 0.074, 0.0795, 0.024 + 0.0135 * math.sin(a + 0.52), x=0.0135 * math.cos(a + 0.52), segs=10, bevel=0, node="Cylinder")
        m.cyl(M["brass"], 0.0045, 0.009, 0.0145, 0.024 + 0.0135 * math.sin(a + 0.52), x=0.0135 * math.cos(a + 0.52), segs=10, bevel=0, node="Cylinder")  # rims
    m.cyl(M["steel"], 0.01, 0.08, 0.27, 0.034, segs=18, node="Barrel")
    m.box(M["steel"], (0.016, 0.026, 0.19), (0, 0.022, 0.175), bevel=0.003, node="Barrel")  # full underlug
    m.box(M["steel"], (0.009, 0.008, 0.19), (0, 0.046, 0.175), bevel=0.002, node="Barrel")  # vent rib
    m.cyl(M["black"], 0.0065, 0.268, 0.2725, 0.034, bevel=0, node="Barrel")
    m.prof(M["dark"], 0.005, [(0.245, 0.05), (0.265, 0.05), (0.262, 0.062), (0.25, 0.062)], bevel=0.001, node="Barrel")
    m.cyl(M["steel"], 0.003, 0.08, 0.12, 0.009, node="Barrel")  # ejector rod
    m.prof(M["dark"], 0.01, [(-0.026, 0.04), (-0.01, 0.042), (-0.014, 0.066), (-0.034, 0.072), (-0.036, 0.064), (-0.024, 0.058)], bevel=0.002, node="Hammer")
    m.box(M["dark"], (0.008, 0.012, 0.03), (0, 0.06, -0.012), bevel=0.001)  # rear sight notch
    m.prof(M["wood"], 0.036, [(-0.03, 0.0), (0.004, -0.012), (-0.012, -0.12), (-0.064, -0.124), (-0.07, -0.09), (-0.05, -0.02)], bevel=0.008)
    for side in (-1, 1):
        m.cylx(M["silver"], 0.006, side * 0.018, side * 0.019, -0.033, -0.06, segs=12)  # grip medallions
    guard(m, M["frame"], 0.005, 0.07, -0.012, 0.034, w=0.009)
    m.strip(M["dark"], 0.006, 0.006, [(0.03, -0.012), (0.024, -0.034)])  # trigger
    pins(m, M["dark"], 0.03, [(0.06, 0.05), (-0.02, 0.03)], 0.003)
    m.empty("Sight", 0, 0.064, 0)
    m.empty("MountMuzzle", 0, 0.034, 0.2725, parent="Barrel")
    m.empty("MountSight", 0, 0.056, 0.03)


def lever_rifle(m, M):
    m.node("Barrel", (0, 0.025, 0.14))
    m.node("Lever", (0, -0.035, 0.06))  # swings down and back with every shot and every round loaded
    m.node("Hammer", (0, 0.04, -0.1))
    m.prof(M["silver"], 0.05, [(-0.12, -0.035), (0.14, -0.035), (0.14, 0.05), (-0.06, 0.05), (-0.12, 0.02)], bevel=0.006)
    for side in (-1, 1):  # engraved side plates: a scroll of small raised panels
        for i in range(4):
            m.box(M["brass"], (0.003, 0.018, 0.04), (side * 0.026, 0.0 + (i % 2) * 0.02, -0.06 + 0.05 * i), bevel=0.001)
    m.box(M["dark"], (0.004, 0.02, 0.06), (0.026, 0.028, 0.06), bevel=0.001)  # loading gate
    m.cyl(M["dark"], 0.015, 0.14, 0.96, 0.028, segs=8, bevel=0.002, node="Barrel")  # octagonal barrel
    m.cyl(M["black"], 0.008, 0.958, 0.963, 0.028, bevel=0, node="Barrel")
    m.prof(M["brass"], 0.006, [(0.92, 0.04), (0.945, 0.04), (0.94, 0.056), (0.925, 0.056)], bevel=0.001, node="Barrel")
    m.prof(M["dark"], 0.012, [(0.3, 0.042), (0.33, 0.042), (0.33, 0.056), (0.3, 0.06)], bevel=0.001, node="Barrel")  # buckhorn rear
    m.cyl(M["steel"], 0.01, 0.14, 0.86, -0.004, segs=14)  # tube magazine
    m.cyl(M["dark"], 0.012, 0.84, 0.87, -0.004, segs=14, bevel=0.002)
    m.box(M["brass"], (0.04, 0.05, 0.02), (0, 0.012, 0.47), bevel=0.003)  # barrel band
    m.prof(M["wood"], 0.05, [(0.14, -0.035), (0.46, -0.03), (0.47, 0.012), (0.14, 0.014)], bevel=0.012)  # forend
    m.prof(M["wood"], 0.046, [(-0.12, 0.03), (-0.12, -0.035), (-0.2, -0.06), (-0.58, -0.13), (-0.62, -0.125), (-0.62, 0.0), (-0.5, 0.025)], bevel=0.014)
    m.box(M["brass"], (0.05, 0.13, 0.012), (0, -0.064, -0.623), tilt=6, bevel=0.003)  # butt plate
    m.strip(M["silver"], 0.012, 0.008, [(0.06, -0.035), (0.06, -0.06), (-0.04, -0.07), (-0.07, -0.11), (-0.13, -0.11), (-0.14, -0.08), (-0.07, -0.035)], node="Lever")
    m.strip(M["dark"], 0.006, 0.006, [(0.0, -0.035), (-0.005, -0.06)])  # trigger
    m.prof(M["dark"], 0.01, [(-0.11, 0.04), (-0.09, 0.044), (-0.1, 0.07), (-0.125, 0.074), (-0.125, 0.066), (-0.112, 0.06)], bevel=0.002, node="Hammer")
    pins(m, M["dark"], 0.05, [(-0.08, 0.0), (0.0, 0.02), (0.1, 0.01)], 0.005)
    m.empty("Sight", 0, 0.06, 0)
    m.empty("Support", 0, -0.035, 0.32)
    m.empty("MountMuzzle", 0, 0.028, 0.963, parent="Barrel")
    m.empty("MountSight", 0, 0.05, 0.02)


def harpoon_gun(m, M):
    m.node("Spear", (0, 0.0, 0.0))  # gone once fired, slid back in by the reload
    m.cyl(M["olive"], 0.032, -0.12, 0.56, 0.0, segs=22, bevel=0.005)  # launch tube
    m.cyl(M["dark"], 0.036, 0.52, 0.58, 0.0, segs=22, bevel=0.004)
    m.cyl(M["black"], 0.024, 0.578, 0.583, 0.0, segs=22, bevel=0)
    m.cyl(M["steel"], 0.022, 0.0, 0.42, -0.058, segs=18, bevel=0.004)  # air tank under it
    m.cyl(M["dark"], 0.023, 0.38, 0.43, -0.058, segs=18, bevel=0.003)
    m.cylx(M["brass"], 0.008, -0.03, 0.03, 0.42, -0.058)  # valve
    for f in (0.1, 0.3, 0.48):
        m.cyl(M["dark"], 0.035, f, f + 0.018, 0.0, segs=22, bevel=0.002)  # tube clamps
    m.cylx(M["dark"], 0.045, -0.085, -0.045, 0.24, 0.0, segs=20)  # line reel on the left
    m.cylx(M["orange"], 0.038, -0.083, -0.047, 0.24, 0.0, segs=20, bevel=0.0)
    m.cylx(M["silver"], 0.006, -0.1, -0.03, 0.24, 0.0, segs=8)
    m.box(M["dark"], (0.006, 0.006, 0.03), (-0.105, -0.02, 0.24), bevel=0.001)  # crank
    m.strip(M["orange"], 0.004, 0.003, [(0.24, 0.04), (0.6, 0.02), (0.9, 0.006)], x=-0.03)  # the line running to the spear
    m.cyl(M["steel"], 0.009, -0.05, 0.9, 0.0, segs=10, node="Spear")
    m.cyl(M["silver"], 0.022, 0.9, 1.0, 0.0, segs=12, r2=0.0, bevel=0, node="Spear")
    for side in (-1, 1):
        m.box(M["silver"], (0.004, 0.012, 0.05), (0, side * 0.018, 0.88), tilt=side * 25, bevel=0.001, node="Spear")  # barbs
        m.box(M["silver"], (0.012, 0.004, 0.05), (side * 0.018, 0.0, 0.88), bevel=0.001, node="Spear")
    m.prof(M["black"], 0.036, [(-0.06, -0.03), (0.0, -0.03), (-0.02, -0.17), (-0.08, -0.16)], bevel=0.009)
    guard(m, M["dark"], 0.0, 0.09, -0.032, 0.04)
    m.prof(M["black"], 0.03, [(0.3, -0.08), (0.35, -0.08), (0.345, -0.2), (0.305, -0.2)], bevel=0.009)  # front grip
    for side in (-1, 1):  # open skeleton stock
        m.strip(M["dark"], 0.008, 0.01, [(-0.12, 0.02), (-0.4, -0.02), (-0.42, -0.1), (-0.12, -0.03)], x=0.018 * side)
    m.box(M["rubber"], (0.05, 0.12, 0.018), (0, -0.06, -0.425), bevel=0.004)
    m.empty("Sight", 0, 0.062, 0)
    m.empty("Support", 0, -0.1, 0.325)
    m.empty("MountSight", 0, 0.032, 0.05)
    m.empty("MountGrip", 0, -0.08, 0.325)


def flare_gun(m, M):
    m.node("Breech", (0, 0.012, 0.03))  # break action: tips down to load a cartridge
    m.node("Hammer", (0, 0.035, -0.035))
    m.prof(M["orange"], 0.036, [(-0.04, 0.0), (0.04, 0.0), (0.04, 0.03), (-0.025, 0.04), (-0.04, 0.03)], bevel=0.005)  # frame
    m.prof(M["orange"], 0.038, [(-0.04, 0.005), (0.0, 0.0), (-0.012, -0.11), (-0.06, -0.112), (-0.07, -0.08), (-0.055, -0.01)], bevel=0.01)  # grip
    for i in range(4):
        m.box(M["black"], (0.04, 0.005, 0.03), (0, -0.03 - 0.022 * i, -0.035 + 0.004 * i), tilt=-10, bevel=0.001)
    m.cyl(M["orange"], 0.024, 0.03, 0.2, 0.032, segs=22, bevel=0.004, node="Breech")  # fat barrel
    m.cyl(M["black"], 0.017, 0.198, 0.203, 0.032, segs=22, bevel=0, node="Breech")
    m.cyl(M["dark"], 0.026, 0.19, 0.205, 0.032, segs=22, bevel=0.003, node="Breech")
    m.cyl(M["red"], 0.018, 0.024, 0.034, 0.032, segs=20, bevel=0.0, node="Breech")  # cartridge base
    m.cyl(M["brass"], 0.02, 0.02, 0.025, 0.032, segs=20, bevel=0.0, node="Breech")
    m.box(M["dark"], (0.012, 0.012, 0.02), (0, 0.06, 0.18), bevel=0.002, node="Breech")  # front blade
    m.cylx(M["dark"], 0.008, -0.022, 0.022, 0.03, 0.012)  # hinge pin
    m.prof(M["dark"], 0.012, [(-0.04, 0.03), (-0.025, 0.034), (-0.03, 0.058), (-0.05, 0.062), (-0.052, 0.054), (-0.04, 0.05)], bevel=0.002, node="Hammer")
    guard(m, M["orange"], -0.005, 0.045, 0.0, 0.035, w=0.01)
    m.empty("Sight", 0, 0.068, 0)
    m.empty("MountSight", 0, 0.056, 0.1, parent="Breech")


def flamethrower(m, M):
    m.node("Needle", (0.066, -0.06, 0.0))  # the fuel gauge's needle (turns with the fuel left)
    m.cyl(M["dark"], 0.022, -0.06, 0.76, 0.0, segs=16, bevel=0.003)  # wand
    m.cyl(M["steel"], 0.034, 0.3, 0.7, 0.0, segs=20, bevel=0.003)  # heat shield
    for i in range(7):
        for k in range(3):
            a = -0.6 + 0.6 * k
            m.cylx(M["black"], 0.006, -0.036, 0.036, 0.33 + 0.05 * i, 0.03 * math.sin(a), segs=8)
    m.cyl(M["dark"], 0.026, 0.76, 0.83, 0.0, segs=18, r2=0.031, bevel=0.003)  # nozzle
    m.cyl(M["black"], 0.022, 0.828, 0.832, 0.0, segs=18, bevel=0)
    m.box(M["dark"], (0.022, 0.02, 0.06), (0, -0.034, 0.79), bevel=0.003)  # pilot light housing
    m.cyl(M["brass"], 0.005, 0.8, 0.825, -0.038, segs=10)
    m.cyl(M["red"], 0.06, -0.16, 0.24, -0.11, segs=24, bevel=0.008)  # fuel tank
    m.cyl(M["dark"], 0.062, 0.2, 0.22, -0.11, segs=24, bevel=0.002)
    m.cyl(M["dark"], 0.062, -0.14, -0.12, -0.11, segs=24, bevel=0.002)
    m.cyl(M["brass"], 0.016, 0.24, 0.27, -0.11, segs=14)
    m.strip(M["rubber"], 0.016, 0.016, [(0.27, -0.11), (0.32, -0.06), (0.36, -0.02)])  # hose up into the wand
    m.cylx(M["dark"], 0.024, 0.04, 0.062, 0.0, -0.06, segs=18)  # fuel gauge on the right
    m.cylx(M["cord"], 0.02, 0.062, 0.064, 0.0, -0.06, segs=18, bevel=0.0)
    m.box(M["red"], (0.002, 0.016, 0.003), (0.067, -0.052, 0.0), bevel=0.0, node="Needle")
    m.prof(M["black"], 0.036, [(-0.04, -0.022), (0.02, -0.022), (0.0, -0.16), (-0.06, -0.15)], bevel=0.009)
    guard(m, M["dark"], 0.02, 0.1, -0.022, 0.035)
    m.prof(M["black"], 0.032, [(0.42, -0.022), (0.47, -0.022), (0.465, -0.15), (0.425, -0.15)], bevel=0.009)  # front grip
    m.box(M["dark"], (0.03, 0.06, 0.3), (0, -0.02, -0.2), bevel=0.008)  # short stock
    m.box(M["rubber"], (0.05, 0.1, 0.016), (0, -0.03, -0.355), bevel=0.004)
    m.empty("Sight", 0, 0.065, 0)
    m.empty("Support", 0, -0.085, 0.445)
    m.empty("MountGrip", 0, -0.022, 0.6)
    m.empty("Nozzle", 0, 0.0, 0.84)
    m.empty("Pilot", 0, -0.038, 0.83)


def crossbow(m, M):
    m.node("StringDrawn", (0, 0.045, 0.0))  # drawn back to the latch while loaded ...
    m.node("StringLoose", (0, 0.045, 0.38))  # ... straight between the limb tips once fired
    m.node("Arrow", (0, 0.05, 0.0))  # the loaded bolt
    m.prof(M["wood"], 0.05, [(-0.5, -0.06), (-0.45, 0.025), (0.46, 0.025), (0.46, -0.025), (0.1, -0.035), (-0.1, -0.03), (-0.25, -0.1), (-0.5, -0.12)], bevel=0.012)
    m.box(M["dark"], (0.03, 0.012, 0.46), (0, 0.032, 0.22), bevel=0.002)  # rail
    m.box(M["steel"], (0.036, 0.022, 0.05), (0, 0.04, 0.0), bevel=0.003)  # latch
    for side in (-1, 1):  # recurve limbs
        pts = [(0.0, 0.04, 0.46), (side * 0.12, 0.04, 0.44), (side * 0.24, 0.04, 0.4), (side * 0.3, 0.04, 0.39), (side * 0.32, 0.04, 0.4)]
        for a, b, r in zip(pts, pts[1:], (0.016, 0.013, 0.01, 0.008)):
            m.rod(M["black"], r, a, b, r2=r * 0.85, segs=10)
        m.rod(M["cord"], 0.003, (side * 0.315, 0.045, 0.395), (0.0, 0.045, 0.0), node="StringDrawn", segs=6)
    m.rod(M["cord"], 0.003, (-0.315, 0.045, 0.395), (0.315, 0.045, 0.395), node="StringLoose", segs=6)
    m.rod(M["steel"], 0.012, (-0.05, 0.0, 0.47), (0.05, 0.0, 0.47), segs=10)  # riser
    for side in (-1, 1):  # foot stirrup
        m.strip(M["steel"], 0.008, 0.008, [(0.46, 0.0), (0.55, -0.02), (0.58, 0.02)], x=side * 0.035)
    m.box(M["steel"], (0.08, 0.008, 0.012), (0, 0.025, 0.585), bevel=0.002)
    m.cyl(M["wood"], 0.006, 0.0, 0.4, 0.052, segs=10, node="Arrow")
    m.cyl(M["steel"], 0.009, 0.4, 0.44, 0.052, segs=10, r2=0.0, bevel=0, node="Arrow")
    m.box(M["red"], (0.002, 0.024, 0.05), (0, 0.065, 0.04), bevel=0.0, node="Arrow")
    m.box(M["red"], (0.024, 0.002, 0.05), (0, 0.052, 0.04), bevel=0.0, node="Arrow")
    m.strip(M["dark"], 0.006, 0.006, [(-0.06, -0.035), (-0.08, -0.07)])  # trigger lever
    guard(m, M["dark"], -0.12, -0.02, -0.035, 0.035)
    m.empty("Sight", 0, 0.08, 0)
    m.empty("Support", 0, -0.035, 0.26)
    m.empty("MountSight", 0, 0.04, -0.12)
    m.empty("MountGrip", 0, -0.03, 0.28)


def blunderbuss(m, M):
    m.node("Barrel", (0, 0.025, 0.12))
    m.node("Hammer", (0.034, 0.03, -0.04))  # the flintlock's cock: snaps forward with each shot, cocked back by the reload
    m.cyl(M["brass"], 0.024, 0.1, 0.62, 0.028, segs=20, r2=0.028, bevel=0.003, node="Barrel")
    m.cyl(M["brass"], 0.028, 0.62, 0.8, 0.028, segs=22, r2=0.068, bevel=0.003, node="Barrel")  # the bell
    m.cyl(M["black"], 0.058, 0.798, 0.803, 0.028, segs=22, bevel=0, node="Barrel")
    m.cyl(M["brass"], 0.071, 0.79, 0.81, 0.028, segs=22, bevel=0.004, node="Barrel")
    for f in (0.2, 0.42):
        m.cyl(M["brass"], 0.03, f, f + 0.02, 0.028, segs=20, bevel=0.002, node="Barrel")  # barrel bands
    m.prof(M["wood"], 0.05, [(-0.06, -0.03), (0.56, -0.012), (0.56, 0.018), (-0.06, 0.024)], bevel=0.012)  # full stock
    m.prof(M["wood"], 0.046, [(-0.06, 0.024), (-0.06, -0.03), (-0.16, -0.07), (-0.5, -0.15), (-0.55, -0.14), (-0.55, -0.03), (-0.3, 0.012)], bevel=0.016)
    m.box(M["brass"], (0.05, 0.13, 0.014), (0, -0.088, -0.552), tilt=12, bevel=0.003)
    m.cyl(M["wood"], 0.005, 0.06, 0.55, -0.02, segs=8)  # ramrod
    m.cyl(M["brass"], 0.007, 0.54, 0.56, -0.02, segs=8)
    m.box(M["steel"], (0.006, 0.04, 0.12), (0.028, 0.012, -0.03), bevel=0.003)  # lock plate
    m.box(M["steel"], (0.016, 0.006, 0.026), (0.032, 0.035, 0.015), bevel=0.001)  # pan
    m.prof(M["steel"], 0.008, [(0.01, 0.035), (0.03, 0.035), (0.034, 0.07), (0.022, 0.072)], x=0.034, bevel=0.001)  # frizzen
    m.prof(M["steel"], 0.007, [(-0.05, 0.028), (-0.035, 0.03), (-0.02, 0.055), (-0.01, 0.07), (-0.022, 0.074), (-0.04, 0.06), (-0.06, 0.04)], x=0.034, bevel=0.001, node="Hammer")
    m.box(M["black"], (0.008, 0.006, 0.014), (0.034, 0.072, -0.016), bevel=0.0, node="Hammer")  # the flint
    guard(m, M["brass"], -0.12, -0.02, -0.03, 0.04, w=0.011)
    m.strip(M["steel"], 0.006, 0.006, [(-0.07, -0.03), (-0.075, -0.06)])
    pins(m, M["brass"], 0.05, [(0.1, 0.0), (0.3, 0.0), (-0.03, 0.0)], 0.004)
    m.empty("Sight", 0, 0.065, 0)
    m.empty("Support", 0, -0.035, 0.3)
    m.empty("MountMuzzle", 0, 0.028, 0.81, parent="Barrel")
    m.empty("MountGrip", 0, -0.03, 0.3)


GUNS = {"smg": smg, "revolver": revolver, "lever_rifle": lever_rifle, "harpoon_gun": harpoon_gun, "flare_gun": flare_gun,
    "flamethrower": flamethrower, "crossbow": crossbow, "blunderbuss": blunderbuss}

if __name__ == "__main__":
    import bpy
    bpy.ops.wm.read_factory_settings(use_empty=True)
    textures = os.path.join(OUT, "textures")
    specs = dict(SPECS)
    specs.update(MORE)
    M = {name: kit.material(name, kit.make_textures(textures, name, kind, color, seed)) for name, (kind, color, seed) in specs.items()}
    M["lens"] = kit.material("lens", None, (0.1, 0.28, 0.6))
    only = sys.argv[1:]
    for gun_id, build in GUNS.items():
        if only and gun_id not in only:
            continue
        model = kit.Model(gun_id)
        build(model, M)
        print("%s: %d triangles" % (gun_id, model.export(OUT)))
