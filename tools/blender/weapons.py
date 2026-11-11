# Purpose: developer-time script. Models the eight held weapons (original designs in the style of well-known firearm
# types) with tools/blender/kit.py and exports them to assets/models/weapons/<weapon id>.gltf with shared textures in
# assets/models/weapons/textures/. Same model units, origin and direction as the old code-built guns in
# game/weapon_models.gd, plus the node names the game looks for: "Slide" (pistol), "Sight" (iron-sight height), "Support" (where the left hand holds a long gun), "Barrel" / "Mag" (parts the gun-part system scales or hides), "MountMuzzle/Sight/Grip/Mag" (where part models go).
# Run: python3 tools/blender/weapons.py   (from the project folder; needs pip packages bpy, numpy, pillow)
import math
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
import kit

OUT = os.path.join(os.path.dirname(__file__), "..", "..", "assets", "models", "weapons")
SPECS = {  # name: (kind, colour, seed)
    "steel": ("metal", (0.2, 0.21, 0.23), 1), "silver": ("metal", (0.6, 0.62, 0.66), 2), "frame": ("metal", (0.3, 0.3, 0.33), 3),
    "dark": ("metal", (0.1, 0.1, 0.115), 4), "olive": ("paint", (0.25, 0.3, 0.2), 5), "warhead": ("paint", (0.8, 0.34, 0.1), 6),
    "black": ("polymer", (0.055, 0.055, 0.06), 7), "wood": ("wood", (0.34, 0.19, 0.09), 8),
}


def pins(m, mat, w, spots, r=0.006):
    for f, y in spots:
        m.cylx(mat, r, -w / 2 - 0.002, w / 2 + 0.002, f, y)


def guard(m, mat, f0, f1, y0, depth, w=0.012):
    m.strip(mat, w, 0.005, [(f0, y0), (f0 + 0.008, y0 - depth), (f1 - 0.02, y0 - depth), (f1, y0)])
    m.strip(mat, 0.007, 0.006, [((f0 + f1) / 2 - 0.005, y0), ((f0 + f1) / 2 - 0.014, y0 - depth * 0.65)])


def pistol(m, M):
    S = "Slide"
    m.prof(M["silver"], 0.042, [(0, -0.008), (0.275, -0.008), (0.287, 0.002), (0.287, 0.044), (0.272, 0.052), (0.012, 0.052), (0, 0.042)], node=S)
    for i in range(6):
        m.box(M["dark"], (0.0435, 0.034, 0.004), (0, 0.022, 0.018 + 0.011 * i), bevel=0.001, node=S)
    m.box(M["dark"], (0.004, 0.02, 0.06), (0.0205, 0.036, 0.15), bevel=0.001, node=S)
    m.cyl(M["dark"], 0.012, 0.283, 0.294, 0.022, node=S)
    m.cyl(M["black"], 0.008, 0.29, 0.2955, 0.022, bevel=0, node=S)
    m.box(M["dark"], (0.022, 0.011, 0.014), (0, 0.057, 0.014), bevel=0.002, node=S)
    m.prof(M["dark"], 0.006, [(0.25, 0.052), (0.274, 0.052), (0.268, 0.063), (0.26, 0.063)], bevel=0.001, node=S)
    m.prof(M["frame"], 0.04, [(-0.022, -0.008), (0.217, -0.008), (0.217, -0.03), (0.192, -0.048), (0.078, -0.048), (0.068, -0.032), (-0.022, -0.032)], bevel=0.004)
    m.prof(M["black"], 0.036, [(-0.022, -0.03), (0.047, -0.03), (0.022, -0.166), (-0.052, -0.16), (-0.047, -0.1)], bevel=0.008)
    m.prof(M["wood"], 0.0435, [(-0.014, -0.046), (0.032, -0.046), (0.013, -0.15), (-0.04, -0.146), (-0.036, -0.1)], bevel=0.003)
    pins(m, M["dark"], 0.0435, [(0.005, -0.06), (-0.014, -0.135)], 0.004)
    guard(m, M["frame"], 0.07, 0.158, -0.046, 0.04)
    m.box(M["dark"], (0.01, 0.018, 0.014), (0, 0.034, -0.016), tilt=-25, bevel=0.002)
    m.box(M["dark"], (0.006, 0.01, 0.03), (0.0215, -0.018, 0.12), bevel=0.001)
    m.empty("MountMuzzle", 0, 0.022, 0.294)
    m.empty("MountSight", 0, 0.052, 0.1)
    m.empty("MountMag", 0, -0.166, -0.015)


def ak47(m, M):
    m.node("Barrel", (0, 0.0, 0.5))  # scaled by barrel parts
    m.node("Mag", (0, -0.045, 0.08))  # hidden when a magazine part is fitted
    m.prof(M["steel"], 0.056, [(-0.2, -0.045), (0.22, -0.045), (0.22, 0.045), (-0.2, 0.045)], bevel=0.005)
    m.prof(M["frame"], 0.05, [(-0.195, 0.043), (0.2, 0.043), (0.2, 0.066), (0.17, 0.078), (-0.165, 0.078), (-0.195, 0.066)], bevel=0.012)
    m.box(M["dark"], (0.03, 0.022, 0.05), (0, 0.078, 0.215), bevel=0.003)
    m.prof(M["dark"], 0.008, [(0.19, 0.088), (0.24, 0.088), (0.24, 0.098), (0.19, 0.104)], bevel=0.001)
    m.prof(M["wood"], 0.058, [(0.222, -0.047), (0.5, -0.04), (0.5, 0.012), (0.222, 0.012)], bevel=0.013)
    m.cyl(M["wood"], 0.024, 0.235, 0.455, 0.047, bevel=0.006)
    m.cyl(M["steel"], 0.013, 0.455, 0.63, 0.047)
    m.box(M["steel"], (0.03, 0.062, 0.035), (0, 0.022, 0.635), bevel=0.004)
    m.cyl(M["steel"], 0.012, 0.22, 0.79, 0.0, node="Barrel")
    m.cyl(M["dark"], 0.017, 0.79, 0.85, 0.0, bevel=0.004, node="Barrel")
    m.prof(M["dark"], 0.03, [(0.7, 0.0), (0.74, 0.0), (0.732, 0.085), (0.708, 0.085)], bevel=0.003, node="Barrel")
    m.cyl(M["black"], 0.009, 0.845, 0.8515, 0.0, bevel=0, node="Barrel")
    m.prof(M["wood"], 0.046, [(-0.2, 0.032), (-0.2, -0.042), (-0.5, -0.115), (-0.545, -0.11), (-0.55, 0.0), (-0.52, 0.022)], bevel=0.012)
    m.box(M["steel"], (0.048, 0.125, 0.012), (0, -0.05, -0.552), tilt=4, bevel=0.003)
    m.prof(M["wood"], 0.036, [(-0.135, -0.043), (-0.07, -0.043), (-0.1, -0.175), (-0.16, -0.165)], bevel=0.01)
    guard(m, M["steel"], -0.07, 0.03, -0.045, 0.05)
    centre, radius, width = 0.525, 0.4, 0.085  # banana magazine: two arcs around a point ahead of it
    arc = [math.radians(i * 7.0) for i in range(6)]
    mag = [(centre - radius * math.cos(a), -0.045 - radius * math.sin(a)) for a in arc]
    back = [(centre - (radius + width) * math.cos(a), -0.045 - (radius + width) * math.sin(a)) for a in arc]
    m.prof(M["dark"], 0.03, mag + back[::-1], bevel=0.004, node="Mag")
    m.cylx(M["dark"], 0.007, 0.028, 0.06, 0.06, 0.03)
    m.box(M["dark"], (0.004, 0.012, 0.16), (0.03, -0.012, 0.0), tilt=-3, bevel=0.001)
    pins(m, M["dark"], 0.056, [(-0.16, 0.0), (-0.02, -0.02), (0.12, 0.01), (0.19, -0.025)])
    m.empty("Sight", 0, 0.08, 0)
    m.empty("Support", 0, -0.035, 0.36)  # where the left hand holds it
    m.empty("MountMuzzle", 0, 0.0, 0.852, parent="Barrel")
    m.empty("MountSight", 0, 0.078, 0.0)
    m.empty("MountGrip", 0, -0.047, 0.36)
    m.empty("MountMag", 0, -0.045, 0.08)


def m16(m, M):
    m.node("Barrel", (0, 0.018, 0.52))  # scaled by barrel parts
    m.node("Mag", (0, -0.1, 0.1))  # hidden when a magazine part is fitted
    m.prof(M["black"], 0.05, [(-0.2, 0.0), (0.2, 0.0), (0.2, 0.062), (-0.2, 0.062)], bevel=0.008)
    m.prof(M["black"], 0.046, [(-0.2, 0.004), (-0.2, -0.06), (0.04, -0.06), (0.05, -0.115), (0.15, -0.105), (0.155, 0.004)], bevel=0.006)
    m.strip(M["black"], 0.03, 0.012, [(-0.16, 0.062), (-0.13, 0.13), (0.1, 0.13), (0.15, 0.062)])
    m.box(M["dark"], (0.022, 0.02, 0.03), (0, 0.142, -0.1), bevel=0.003)
    m.cyl(M["black"], 0.036, 0.205, 0.52, 0.018, segs=24, bevel=0.006)
    for i in range(9):
        m.cyl(M["black"], 0.0385, 0.23 + i * 0.031, 0.243 + i * 0.031, 0.018, segs=24, bevel=0.002)
    m.cyl(M["dark"], 0.041, 0.198, 0.222, 0.018, segs=24)
    m.cyl(M["steel"], 0.011, 0.52, 0.75, 0.018, node="Barrel")
    m.cyl(M["dark"], 0.015, 0.75, 0.81, 0.018, bevel=0.003, node="Barrel")
    m.cyl(M["black"], 0.008, 0.805, 0.8115, 0.018, bevel=0, node="Barrel")
    m.prof(M["dark"], 0.014, [(0.535, 0.018), (0.61, 0.018), (0.582, 0.142), (0.57, 0.142)], bevel=0.003, node="Barrel")
    m.cyl(M["dark"], 0.013, -0.3, -0.2, 0.03)
    m.prof(M["black"], 0.046, [(-0.2, 0.055), (-0.2, -0.03), (-0.5, -0.1), (-0.525, -0.1), (-0.525, 0.055)], bevel=0.01)
    m.box(M["dark"], (0.048, 0.15, 0.012), (0, -0.022, -0.528), bevel=0.003)
    m.prof(M["black"], 0.034, [(-0.13, -0.058), (-0.07, -0.058), (-0.105, -0.185), (-0.165, -0.17)], bevel=0.009)
    guard(m, M["dark"], -0.07, 0.045, -0.06, 0.045)
    m.prof(M["frame"], 0.028, [(0.058, -0.1), (0.142, -0.1), (0.17, -0.265), (0.086, -0.27)], bevel=0.004, node="Mag")
    m.cylx(M["dark"], 0.009, 0.025, 0.045, -0.15, 0.04)
    m.box(M["dark"], (0.004, 0.03, 0.07), (0.026, 0.03, 0.07), bevel=0.001)
    pins(m, M["dark"], 0.05, [(-0.15, -0.02), (0.17, -0.01), (-0.03, -0.035)], 0.005)
    m.empty("Sight", 0, 0.14, 0)
    m.empty("Support", 0, -0.025, 0.36)  # where the left hand holds it
    m.empty("MountMuzzle", 0, 0.018, 0.812, parent="Barrel")
    m.empty("MountSight", 0, 0.136, 0.0)
    m.empty("MountGrip", 0, -0.02, 0.36)
    m.empty("MountMag", 0, -0.1, 0.1)


def m60(m, M):
    m.node("Barrel", (0, 0.0, 0.6))  # scaled by barrel parts
    m.node("Mag", (0, -0.06, 0.08))  # hidden when a magazine part is fitted
    m.prof(M["steel"], 0.06, [(-0.25, -0.05), (0.25, -0.05), (0.25, 0.05), (-0.25, 0.05)], bevel=0.006)
    m.prof(M["frame"], 0.064, [(-0.2, 0.048), (0.16, 0.048), (0.15, 0.082), (-0.19, 0.082)], bevel=0.006)  # feed cover
    m.cyl(M["dark"], 0.02, 0.25, 0.86, 0.0, node="Barrel")
    m.cyl(M["frame"], 0.033, 0.25, 0.6, 0.0, segs=24, bevel=0.004)
    for i in range(6):
        m.box(M["black"], (0.07, 0.012, 0.03), (0, 0.0, 0.29 + i * 0.05), bevel=0.002)  # cooling slots
    m.cyl(M["dark"], 0.026, 0.86, 0.93, 0.0, bevel=0.004, node="Barrel")
    m.cyl(M["steel"], 0.012, 0.25, 0.62, -0.042)
    m.prof(M["dark"], 0.012, [(0.6, 0.02), (0.66, 0.02), (0.64, 0.12), (0.625, 0.12)], bevel=0.002, node="Barrel")
    m.box(M["dark"], (0.02, 0.04, 0.02), (0, 0.1, -0.12), bevel=0.003)
    m.strip(M["dark"], 0.03, 0.01, [(0.3, 0.035), (0.33, 0.1), (0.47, 0.1), (0.5, 0.035)])  # carry handle
    m.prof(M["wood"], 0.062, [(0.26, -0.035), (0.56, -0.035), (0.56, -0.085), (0.26, -0.075)], bevel=0.012)
    m.prof(M["black"], 0.056, [(-0.25, 0.045), (-0.25, -0.05), (-0.52, -0.1), (-0.56, -0.09), (-0.56, 0.05), (-0.5, 0.06)], bevel=0.014)
    m.prof(M["black"], 0.036, [(-0.13, -0.048), (-0.065, -0.048), (-0.095, -0.175), (-0.155, -0.16)], bevel=0.009)
    guard(m, M["steel"], -0.065, 0.04, -0.05, 0.045)
    m.box(M["olive"], (0.1, 0.11, 0.15), (-0.075, -0.06, 0.08), bevel=0.008, node="Mag")  # ammo box on the left
    m.box(M["silver"], (0.04, 0.012, 0.09), (-0.035, 0.04, 0.08), bevel=0.003, node="Mag")  # belt
    for leg in (-1, 1):
        m.strip(M["dark"], 0.008, 0.008, [(0.78, -0.02), (0.72, -0.2)], x=0.03 * leg)  # folded bipod
    pins(m, M["dark"], 0.06, [(-0.2, 0.0), (0.0, -0.02), (0.2, 0.01)])
    m.empty("Sight", 0, 0.12, 0)
    m.empty("Support", 0, -0.075, 0.42)  # where the left hand holds it
    m.empty("MountMuzzle", 0, 0.0, 0.93, parent="Barrel")
    m.empty("MountSight", 0, 0.082, -0.02)
    m.empty("MountGrip", 0, -0.085, 0.42)
    m.empty("MountMag", 0, -0.05, 0.08)


def shotgun(m, M):
    m.node("Barrel", (0, 0.01, 0.1))  # scaled by barrel parts
    for side in (-1, 1):
        m.cyl(M["steel"], 0.017, 0.075, 0.725, 0.01, x=0.019 * side, node="Barrel")
        m.cyl(M["black"], 0.0135, 0.72, 0.7265, 0.01, x=0.019 * side, bevel=0, node="Barrel")
    m.box(M["steel"], (0.012, 0.006, 0.6), (0, 0.03, 0.4), bevel=0.002, node="Barrel")  # sighting rib
    m.cyl(M["silver"], 0.004, 0.705, 0.713, 0.04, bevel=0.001, node="Barrel")  # bead
    m.prof(M["frame"], 0.06, [(-0.09, -0.04), (0.09, -0.045), (0.09, 0.032), (-0.02, 0.036), (-0.09, 0.02)], bevel=0.008)
    m.prof(M["wood"], 0.056, [(0.1, -0.045), (0.36, -0.028), (0.36, 0.0), (0.1, 0.0)], bevel=0.012)
    m.prof(M["wood"], 0.048, [(-0.085, 0.022), (-0.085, -0.04), (-0.16, -0.075), (-0.4, -0.13), (-0.44, -0.12), (-0.44, -0.01), (-0.2, 0.012)], bevel=0.013)
    m.box(M["black"], (0.05, 0.115, 0.012), (0, -0.065, -0.443), tilt=6, bevel=0.004)
    guard(m, M["frame"], -0.07, 0.03, -0.042, 0.04)
    m.box(M["dark"], (0.008, 0.016, 0.03), (0, 0.04, -0.04), tilt=-20, bevel=0.002)  # top lever
    pins(m, M["dark"], 0.06, [(0.06, 0.0), (-0.05, -0.01)], 0.005)
    m.empty("Sight", 0, 0.045, 0)
    m.empty("Support", 0, -0.03, 0.23)  # where the left hand holds it
    m.empty("MountMuzzle", 0, 0.01, 0.727, parent="Barrel")
    m.empty("MountGrip", 0, -0.036, 0.23)


def sniper(m, M):
    m.node("Barrel", (0, 0.01, 0.3))  # scaled by barrel parts
    m.node("Mag", (0, -0.04, 0.09))  # hidden when a magazine part is fitted
    m.prof(M["olive"], 0.05, [(-0.2, -0.04), (0.3, -0.04), (0.3, 0.04), (-0.2, 0.04)], bevel=0.008)
    m.cyl(M["steel"], 0.016, 0.295, 1.045, 0.01, node="Barrel")
    m.cyl(M["dark"], 0.022, 0.98, 1.06, 0.01, bevel=0.004, node="Barrel")
    m.cyl(M["black"], 0.011, 1.055, 1.0615, 0.01, bevel=0, node="Barrel")
    m.prof(M["olive"], 0.052, [(0.3, -0.04), (0.62, -0.02), (0.62, 0.005), (0.3, 0.005)], bevel=0.012)
    m.prof(M["olive"], 0.046, [(-0.2, 0.035), (-0.2, -0.04), (-0.27, -0.1), (-0.5, -0.12), (-0.52, -0.1), (-0.52, 0.03), (-0.44, 0.045)], bevel=0.012)
    m.box(M["black"], (0.04, 0.03, 0.16), (0, 0.055, -0.38), bevel=0.008)  # cheek rest
    m.box(M["black"], (0.048, 0.14, 0.014), (0, -0.04, -0.524), bevel=0.004)
    m.prof(M["olive"], 0.036, [(-0.14, -0.038), (-0.08, -0.038), (-0.105, -0.15), (-0.165, -0.14)], bevel=0.009)
    guard(m, M["dark"], -0.08, 0.02, -0.04, 0.04)
    m.prof(M["dark"], 0.03, [(0.04, -0.04), (0.14, -0.04), (0.145, -0.12), (0.045, -0.12)], bevel=0.004, node="Mag")
    for f in (-0.08, 0.12):
        m.box(M["dark"], (0.022, 0.05, 0.03), (0, 0.062, f), bevel=0.003)
        m.cyl(M["dark"], 0.031, f - 0.012, f + 0.012, 0.105, segs=24)
    m.cyl(M["black"], 0.025, -0.2, 0.3, 0.105, segs=24)
    m.cyl(M["black"], 0.036, 0.3, 0.4, 0.105, segs=24, r2=0.038)
    m.cyl(M["black"], 0.03, -0.27, -0.2, 0.105, segs=24)
    m.cyl(M["lens"], 0.033, 0.398, 0.401, 0.105, segs=24, bevel=0)
    m.cyl(M["lens"], 0.026, -0.2715, -0.269, 0.105, segs=24, bevel=0)
    m.cylx(M["dark"], 0.012, -0.012, 0.012, 0.03, 0.142, bevel=0.003)  # elevation knob (turned up below)
    m.cylx(M["dark"], 0.012, 0.022, 0.045, 0.03, 0.105, bevel=0.003)
    m.cylx(M["steel"], 0.006, 0.025, 0.075, -0.05, 0.02)  # bolt handle
    m.cylx(M["dark"], 0.013, 0.07, 0.095, -0.05, 0.02, bevel=0.005)
    for leg in (-1, 1):
        m.strip(M["dark"], 0.008, 0.008, [(0.58, -0.02), (0.5, -0.2)], x=0.028 * leg)
    m.empty("Support", 0, -0.03, 0.46)  # where the left hand holds it
    m.empty("MountMuzzle", 0, 0.01, 1.062, parent="Barrel")
    m.empty("MountSight", 0, 0.142, 0.05)
    m.empty("MountGrip", 0, -0.02, 0.46)
    m.empty("MountMag", 0, -0.04, 0.09)


def rocket_launcher(m, M):
    m.cyl(M["olive"], 0.07, -0.4, 0.6, 0.02, segs=28, bevel=0.006)
    m.cyl(M["dark"], 0.078, 0.56, 0.62, 0.02, segs=28, bevel=0.004)
    m.cyl(M["dark"], 0.085, -0.46, -0.38, 0.02, segs=28, r2=0.07, bevel=0.004)
    m.cyl(M["black"], 0.062, 0.615, 0.6215, 0.02, segs=28, bevel=0)
    for f in (-0.2, 0.05, 0.3):
        m.cyl(M["dark"], 0.074, f, f + 0.02, 0.02, segs=28, bevel=0.002)
    m.cyl(M["warhead"], 0.05, 0.6, 0.72, 0.02, segs=24, r2=0.075, bevel=0.003)
    m.cyl(M["warhead"], 0.075, 0.72, 0.78, 0.02, segs=24, bevel=0.003)
    m.cyl(M["warhead"], 0.075, 0.78, 0.9, 0.02, segs=24, r2=0.012, bevel=0.002)
    m.prof(M["black"], 0.036, [(0.02, -0.05), (0.085, -0.05), (0.06, -0.19), (0.0, -0.18)], bevel=0.009)
    m.prof(M["black"], 0.036, [(0.26, -0.05), (0.32, -0.05), (0.305, -0.17), (0.25, -0.165)], bevel=0.009)
    guard(m, M["dark"], 0.085, 0.19, -0.05, 0.045)
    m.box(M["wood"], (0.05, 0.03, 0.2), (0, 0.1, -0.12), bevel=0.01)  # shoulder/cheek pad
    m.prof(M["dark"], 0.012, [(0.14, 0.09), (0.2, 0.09), (0.19, 0.15), (0.15, 0.15)], bevel=0.002)
    m.box(M["dark"], (0.03, 0.03, 0.012), (0, 0.155, 0.17), bevel=0.002)
    m.strip(M["black"], 0.02, 0.004, [(-0.3, -0.05), (-0.1, -0.11), (0.0, -0.06)])  # sling
    m.empty("Sight", 0, 0.14, 0)
    m.empty("Support", 0, -0.11, 0.285)  # where the left hand holds it
    m.empty("MountSight", 0, 0.165, 0.17)
    m.empty("MountGrip", 0, -0.05, 0.42)


def grenade_launcher(m, M):
    m.cyl(M["dark"], 0.034, 0.12, 0.48, 0.0, segs=24, bevel=0.005)
    m.cyl(M["steel"], 0.038, 0.44, 0.485, 0.0, segs=24, bevel=0.003)
    m.cyl(M["black"], 0.028, 0.48, 0.4865, 0.0, segs=24, bevel=0)
    m.prof(M["frame"], 0.06, [(-0.1, -0.045), (0.13, -0.045), (0.13, 0.042), (-0.04, 0.042), (-0.1, 0.02)], bevel=0.008)
    m.prof(M["wood"], 0.058, [(0.14, -0.052), (0.36, -0.045), (0.36, -0.02), (0.14, -0.02)], bevel=0.011)
    m.prof(M["wood"], 0.05, [(-0.095, 0.02), (-0.095, -0.04), (-0.17, -0.075), (-0.36, -0.12), (-0.385, -0.11), (-0.385, 0.0), (-0.2, 0.02)], bevel=0.013)
    m.box(M["black"], (0.052, 0.115, 0.016), (0, -0.057, -0.39), tilt=5, bevel=0.005)
    guard(m, M["frame"], -0.075, 0.03, -0.047, 0.04)
    m.strip(M["dark"], 0.012, 0.004, [(0.2, 0.034), (0.2, 0.092)])  # ladder sight
    m.box(M["dark"], (0.03, 0.006, 0.006), (0, 0.092, 0.2), bevel=0.001)
    m.prof(M["dark"], 0.008, [(0.45, 0.036), (0.475, 0.036), (0.468, 0.07), (0.458, 0.07)], bevel=0.001)
    m.box(M["dark"], (0.008, 0.016, 0.03), (0, 0.048, -0.05), tilt=-20, bevel=0.002)
    pins(m, M["dark"], 0.06, [(0.09, 0.0), (-0.06, -0.01)], 0.006)
    m.empty("Sight", 0, 0.09, 0)
    m.empty("Support", 0, -0.045, 0.25)  # where the left hand holds it
    m.empty("MountSight", 0, 0.045, 0.02)
    m.empty("MountGrip", 0, -0.052, 0.25)


GUNS = {"pistol_basic": pistol, "ak47": ak47, "m16": m16, "m60": m60, "shotgun_double": shotgun, "sniper_basic": sniper,
    "rocket_launcher": rocket_launcher, "grenade_launcher": grenade_launcher}

if __name__ == "__main__":
    import bpy
    bpy.ops.wm.read_factory_settings(use_empty=True)
    textures = os.path.join(OUT, "textures")
    M = {name: kit.material(name, kit.make_textures(textures, name, kind, color, seed)) for name, (kind, color, seed) in SPECS.items()}
    M["lens"] = kit.material("lens", None, (0.1, 0.28, 0.6))
    for gun_id, build in GUNS.items():
        model = kit.Model(gun_id)
        build(model, M)
        print("%s: %d triangles" % (gun_id, model.export(OUT)))
