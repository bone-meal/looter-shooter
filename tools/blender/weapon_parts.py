# Purpose: developer-time script. Models the attachable gun parts (6 muzzle devices, 6 sights, 6 fore-grips, 6 magazines)
# with tools/blender/kit.py into assets/models/weapons/parts/<model id>.gltf. Each is built around its mount point
# (origin), pointing forward, in the same model units as the guns. Surfaces named "maker" are painted in the part
# manufacturer's colour by game/gun_parts_view.gd; "dot" is the red reticle glow. Barrel parts have no model: they scale
# the gun's own Barrel. Run: python3 tools/blender/weapon_parts.py [part ids]   (from the project folder)
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
import kit
import weapons

OUT = os.path.join(weapons.OUT, "parts")


def muzzle_silencer(m, M):
    m.cyl(M["black"], 0.024, 0.0, 0.22, bevel=0.004, segs=20)
    for f in (0.0, 0.198):
        m.cyl(M["dark"], 0.0262, f, f + 0.022, bevel=0.002, segs=20)
    m.cyl(M["maker"], 0.0252, 0.06, 0.078, bevel=0, segs=20)
    m.cyl(M["black"], 0.009, 0.218, 0.2215, bevel=0)


def muzzle_comp(m, M):
    m.cyl(M["steel"], 0.021, 0.0, 0.085, bevel=0.003, segs=16)
    for f in (0.022, 0.042, 0.062):
        m.box(M["black"], (0.014, 0.014, 0.012), (0, 0.016, f), bevel=0.001)
        m.cylx(M["black"], 0.0055, -0.022, 0.022, f, 0.0, bevel=0)
    m.cyl(M["maker"], 0.0222, 0.002, 0.012, bevel=0, segs=16)
    m.cyl(M["black"], 0.009, 0.083, 0.0865, bevel=0)


def muzzle_flash_hider(m, M):
    m.cyl(M["dark"], 0.017, 0.0, 0.03, bevel=0.002, segs=16)
    for x, y in ((0.011, 0.0), (-0.011, 0.0), (0.0, 0.011), (0.0, -0.011)):
        m.rod(M["dark"], 0.0045, (x, y, 0.03), (x * 1.15, y * 1.15, 0.09), r2=0.003, segs=6)
    m.cyl(M["maker"], 0.0182, 0.004, 0.012, bevel=0, segs=16)


def sight_red_dot(m, M):
    m.box(M["dark"], (0.03, 0.012, 0.06), (0, 0.006, 0), bevel=0.003)
    m.cyl(M["black"], 0.024, -0.036, 0.036, 0.04, bevel=0.004, segs=20)
    m.cyl(M["dot"], 0.0185, 0.0355, 0.0375, 0.04, bevel=0, segs=20)
    m.cyl(M["lens"], 0.0185, -0.0375, -0.0355, 0.04, bevel=0, segs=20)
    m.cylx(M["dark"], 0.008, 0.02, 0.034, 0.0, 0.04)
    m.cyl(M["maker"], 0.0252, -0.006, 0.006, 0.04, bevel=0, segs=20)


def sight_acog(m, M):
    m.prof(M["black"], 0.036, [(-0.07, 0.012), (0.07, 0.012), (0.085, 0.03), (0.085, 0.062), (0.03, 0.07), (-0.07, 0.058)], bevel=0.006)
    m.box(M["dark"], (0.03, 0.012, 0.09), (0, 0.006, 0), bevel=0.003)
    m.cyl(M["black"], 0.026, 0.06, 0.105, 0.042, bevel=0.003, segs=20)
    m.cyl(M["black"], 0.02, -0.105, -0.06, 0.04, bevel=0.003, segs=20)
    m.cyl(M["lens"], 0.022, 0.1045, 0.1065, 0.042, bevel=0, segs=20)
    m.cyl(M["lens"], 0.016, -0.1065, -0.1045, 0.04, bevel=0, segs=20)
    m.box(M["dot"], (0.006, 0.004, 0.07), (0, 0.073, 0.0), bevel=0.001)
    m.box(M["maker"], (0.0375, 0.012, 0.03), (0, 0.035, -0.03), bevel=0.001)


def sight_holo(m, M):
    m.box(M["black"], (0.036, 0.016, 0.075), (0, 0.008, 0), bevel=0.004)
    for x in (-0.018, 0.018):
        m.box(M["black"], (0.005, 0.044, 0.03), (x, 0.038, 0.012), bevel=0.002)
    m.box(M["black"], (0.041, 0.005, 0.03), (0, 0.061, 0.012), bevel=0.002)
    m.box(M["lens"], (0.031, 0.04, 0.002), (0, 0.038, 0.012), bevel=0)
    m.ball(M["dot"], 0.003, (0, 0.038, 0.011), u=6, v=4)
    m.box(M["dark"], (0.03, 0.02, 0.025), (0, 0.026, -0.024), bevel=0.003)
    m.box(M["maker"], (0.0375, 0.006, 0.05), (0, 0.011, 0), bevel=0.001)


def grip_vertical(m, M):
    m.box(M["dark"], (0.034, 0.012, 0.05), (0, -0.006, 0), bevel=0.003)
    m.prof(M["black"], 0.03, [(-0.018, -0.01), (0.018, -0.01), (0.015, -0.125), (-0.015, -0.125)], bevel=0.008)
    m.box(M["maker"], (0.0315, 0.01, 0.035), (0, -0.03, 0), bevel=0.001)


def grip_angled(m, M):
    m.prof(M["black"], 0.034, [(-0.055, 0.0), (0.055, 0.0), (0.055, -0.02), (-0.02, -0.078), (-0.055, -0.06)], bevel=0.008)
    m.box(M["maker"], (0.0355, 0.008, 0.03), (0, -0.012, 0.03), bevel=0.001)


def grip_stubby(m, M):
    m.box(M["dark"], (0.034, 0.012, 0.045), (0, -0.006, 0), bevel=0.003)
    m.prof(M["black"], 0.032, [(-0.02, -0.01), (0.02, -0.01), (0.018, -0.06), (-0.018, -0.06)], bevel=0.008)
    m.ball(M["black"], (0.019, 0.012, 0.021), (0, -0.064, 0), u=10, v=6)
    m.box(M["maker"], (0.0335, 0.008, 0.03), (0, -0.026, 0), bevel=0.001)


def mag_extended(m, M):
    m.prof(M["dark"], 0.03, [(-0.04, 0.0), (0.045, 0.0), (0.072, -0.33), (-0.013, -0.34)], bevel=0.004)
    m.box(M["black"], (0.034, 0.014, 0.095), (0, -0.338, 0.03), tilt=-5, bevel=0.003)
    m.box(M["maker"], (0.0315, 0.02, 0.09), (0, -0.17, 0.016), tilt=-5, bevel=0.001)


def mag_drum(m, M):
    m.prof(M["dark"], 0.03, [(-0.04, 0.0), (0.045, 0.0), (0.045, -0.075), (-0.04, -0.075)], bevel=0.004)
    m.cylx(M["dark"], 0.09, -0.032, 0.032, 0.005, -0.14, segs=24, bevel=0.006)
    m.cylx(M["steel"], 0.022, -0.036, 0.036, 0.005, -0.14, segs=12, bevel=0.003)
    m.cylx(M["maker"], 0.062, -0.0335, 0.0335, 0.005, -0.14, segs=24, bevel=0)
    for k in range(6):
        import math
        a = math.pi * k / 3.0
        m.cylx(M["black"], 0.007, -0.0345, 0.0345, 0.005 + 0.075 * math.cos(a), -0.14 + 0.075 * math.sin(a), segs=6, bevel=0)


def mag_fast(m, M):
    m.prof(M["dark"], 0.03, [(-0.04, 0.0), (0.045, 0.0), (0.056, -0.17), (-0.029, -0.176)], bevel=0.004)
    m.strip(M["maker"], 0.02, 0.006, [(-0.02, -0.172), (-0.008, -0.215), (0.036, -0.213), (0.046, -0.168)])
    m.box(M["maker"], (0.0315, 0.012, 0.085), (0, -0.05, 0.004), bevel=0.001)


def muzzle_brake(m, M):
    m.cyl(M["steel"], 0.022, 0.0, 0.075, bevel=0.003, segs=16)
    for f in (0.02, 0.04, 0.058):  # side ports
        m.box(M["black"], (0.048, 0.012, 0.01), (0, 0.0, f), bevel=0.001)
    m.cyl(M["maker"], 0.0232, 0.002, 0.012, bevel=0, segs=16)
    m.cyl(M["black"], 0.009, 0.073, 0.0765, bevel=0)


def muzzle_choke(m, M):
    m.cyl(M["dark"], 0.02, 0.0, 0.065, bevel=0.002, segs=16, r2=0.014)
    for f in (0.02, 0.035, 0.05):
        m.cyl(M["black"], 0.0175 - f * 0.08, f, f + 0.004, bevel=0, segs=16)
    m.cyl(M["maker"], 0.021, 0.002, 0.012, bevel=0, segs=16)


def muzzle_bayonet(m, M):
    m.cyl(M["dark"], 0.019, 0.0, 0.03, bevel=0.002, segs=16)
    m.box(M["dark"], (0.012, 0.02, 0.03), (0, -0.022, 0.015), bevel=0.002)
    m.prof(M["steel"], 0.004, [(0.0, -0.028), (0.17, -0.03), (0.21, -0.038), (0.16, -0.046), (0.0, -0.044)], bevel=0.001)
    m.cyl(M["maker"], 0.0198, 0.018, 0.026, bevel=0, segs=16)


def sight_peep(m, M):
    m.box(M["dark"], (0.026, 0.01, 0.03), (0, 0.005, 0), bevel=0.002)
    m.box(M["black"], (0.006, 0.026, 0.01), (0, 0.022, -0.008), bevel=0.001)
    m.cyl(M["black"], 0.008, -0.012, -0.004, 0.03, bevel=0, segs=12)
    m.cyl(M["lens"], 0.003, -0.0125, -0.0035, 0.03, bevel=0, segs=8)
    m.box(M["maker"], (0.027, 0.004, 0.02), (0, 0.011, 0.005), bevel=0.0005)


def sight_long_scope(m, M):
    for f in (-0.06, 0.06):
        m.box(M["dark"], (0.03, 0.03, 0.02), (0, 0.015, f), bevel=0.002)
    m.cyl(M["black"], 0.017, -0.12, 0.12, 0.046, bevel=0.002, segs=20)
    m.cyl(M["black"], 0.026, 0.12, 0.17, 0.046, bevel=0.003, segs=20, r2=0.03)
    m.cyl(M["black"], 0.022, -0.16, -0.12, 0.046, bevel=0.003, segs=20)
    m.cyl(M["lens"], 0.027, 0.169, 0.171, 0.046, bevel=0, segs=20)
    m.cyl(M["lens"], 0.019, -0.161, -0.159, 0.046, bevel=0, segs=20)
    m.box(M["dark"], (0.016, 0.022, 0.016), (0, 0.07, 0.0), bevel=0.002)  # turret
    m.box(M["dark"], (0.022, 0.016, 0.016), (0.022, 0.046, 0.0), bevel=0.002)
    m.cyl(M["maker"], 0.0182, -0.03, -0.015, 0.046, bevel=0, segs=20)


def sight_thermal(m, M):
    m.box(M["dark"], (0.03, 0.012, 0.07), (0, 0.006, 0), bevel=0.003)
    m.box(M["black"], (0.046, 0.044, 0.09), (0, 0.044, 0), bevel=0.006)
    m.cyl(M["lens"], 0.019, 0.045, 0.048, 0.044, bevel=0, segs=20)
    m.cyl(M["dot"], 0.012, -0.0475, -0.045, 0.044, bevel=0, segs=16)
    m.box(M["dark"], (0.016, 0.022, 0.04), (0.03, 0.04, -0.01), bevel=0.003)  # battery
    m.box(M["maker"], (0.047, 0.008, 0.06), (0, 0.068, 0), bevel=0.001)


def grip_folding(m, M):
    m.box(M["dark"], (0.03, 0.012, 0.04), (0, -0.006, 0), bevel=0.003)
    m.cylx(M["steel"], 0.006, -0.017, 0.017, 0.01, -0.016, bevel=0)  # hinge
    m.prof(M["black"], 0.024, [(-0.006, -0.014), (0.022, -0.014), (0.048, -0.1), (0.028, -0.104)], bevel=0.005)
    m.box(M["maker"], (0.0255, 0.008, 0.026), (0, -0.026, 0.012), bevel=0.001)


def grip_bipod(m, M):
    m.box(M["dark"], (0.036, 0.016, 0.05), (0, -0.008, 0), bevel=0.003)
    for side in (-1, 1):
        m.rod(M["black"], 0.0055, (side * 0.012, -0.016, 0.0), (side * 0.05, -0.14, 0.02), segs=8)
        m.rod(M["steel"], 0.0042, (side * 0.05, -0.14, 0.02), (side * 0.058, -0.17, 0.024), segs=8)
        m.ball(M["black"], 0.008, (side * 0.058, -0.172, 0.024), u=8, v=5)
    m.box(M["maker"], (0.037, 0.008, 0.03), (0, -0.012, 0.0), bevel=0.001)


def grip_skeleton(m, M):
    m.box(M["dark"], (0.03, 0.01, 0.045), (0, -0.005, 0), bevel=0.002)
    for f in (-0.014, 0.014):
        m.rod(M["black"], 0.005, (0, -0.01, f), (0, -0.11, f * 0.8), segs=8)
    for y in (-0.04, -0.075, -0.11):
        m.rod(M["black"], 0.004, (0, y, -0.013), (0, y, 0.013), segs=6)
    m.box(M["maker"], (0.031, 0.006, 0.03), (0, -0.02, 0), bevel=0.0005)


def mag_twin(m, M):
    for side in (-0.017, 0.017):
        m.prof(M["dark"], 0.026, [(-0.04, 0.0), (0.045, 0.0), (0.06, -0.21), (-0.025, -0.216)], x=side, bevel=0.003)
    m.box(M["maker"], (0.066, 0.03, 0.09), (0, -0.11, 0.01), tilt=-4, bevel=0.002)  # the tape round both


def mag_box(m, M):
    m.prof(M["dark"], 0.036, [(-0.045, 0.0), (0.05, 0.0), (0.06, -0.17), (-0.06, -0.17), (-0.06, -0.06)], bevel=0.005)
    for y in (-0.06, -0.1, -0.14):
        m.box(M["black"], (0.038, 0.006, 0.11), (0, y, -0.002), bevel=0.001)
    m.box(M["maker"], (0.037, 0.024, 0.08), (0, -0.03, 0.0), bevel=0.001)


def mag_slim(m, M):
    m.prof(M["dark"], 0.022, [(-0.035, 0.0), (0.035, 0.0), (0.042, -0.15), (-0.024, -0.154)], bevel=0.003)
    m.box(M["maker"], (0.0235, 0.012, 0.06), (0, -0.06, 0.004), bevel=0.001)


PARTS = {"muzzle_silencer": muzzle_silencer, "muzzle_comp": muzzle_comp, "muzzle_flash_hider": muzzle_flash_hider,
    "sight_red_dot": sight_red_dot, "sight_acog": sight_acog, "sight_holo": sight_holo, "grip_vertical": grip_vertical,
    "grip_angled": grip_angled, "grip_stubby": grip_stubby, "mag_extended": mag_extended, "mag_drum": mag_drum, "mag_fast": mag_fast,
    "muzzle_brake": muzzle_brake, "muzzle_choke": muzzle_choke, "muzzle_bayonet": muzzle_bayonet, "sight_peep": sight_peep,
    "sight_long_scope": sight_long_scope, "sight_thermal": sight_thermal, "grip_folding": grip_folding, "grip_bipod": grip_bipod,
    "grip_skeleton": grip_skeleton, "mag_twin": mag_twin, "mag_box": mag_box, "mag_slim": mag_slim}

if __name__ == "__main__":
    import bpy
    bpy.ops.wm.read_factory_settings(use_empty=True)
    textures = os.path.join(weapons.OUT, "textures")
    M = {name: kit.material(name, [os.path.join(textures, "%s_%s.png" % (name, part)) for part in ("albedo", "orm", "normal")]) for name in ("steel", "dark", "black")}
    M["lens"] = kit.material("lens", None, (0.1, 0.28, 0.6))
    M["maker"] = kit.material("maker", None, (0.9, 0.9, 0.9))
    M["dot"] = kit.material("dot", None, (1.0, 0.08, 0.05))
    for part_id, build in PARTS.items():
        if len(sys.argv) > 1 and part_id not in sys.argv[1:]:  # names given: only those
            continue
        model = kit.Model(part_id)
        build(model, M)
        print("%s: %d triangles" % (part_id, model.export(OUT)))
