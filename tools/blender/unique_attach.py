# Purpose: developer-time script. Models the gimmicks fixed onto the named chase guns (diary/DESIGN_UNIQUES.md) with
# tools/blender/kit.py into assets/models/weapons/uniques/<id>.gltf. Each is built in the GUN SPACE of the body it
# rides on (origin = the gun model's origin), so game/unique_attach.gd adds it at the gun's root with no offset.
# MIXTAPE: an MP3 player lying on the LEFT side of the M16 receiver (the side the first-person camera sees), screen
# toward the muzzle end, click wheel toward the stock, held on by two strips of silver duct tape, earbuds dangling
# from its jack. An empty "Screen" marks the middle of its screen, where the game puts the scrolling song name.
# Run: python3 tools/blender/unique_attach.py [ids]   (from the project folder)
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
import kit
import weapons

OUT = os.path.join(weapons.OUT, "uniques")

SPECS = {  # name: (kind, colour, seed)
    "plastic": ("polymer", (0.86, 0.86, 0.88), 41), "chrome": ("metal", (0.72, 0.74, 0.78), 42),
    "wheel": ("polymer", (0.62, 0.63, 0.66), 43), "tape": ("fabric", (0.5, 0.51, 0.53), 44),
    "cable": ("polymer", (0.92, 0.92, 0.93), 45), "rubber": ("polymer", (0.08, 0.08, 0.09), 46),
}

LEFT = -0.0415  # the M16 receiver's left face (x)
MP3_T = 0.011  # thickness
MP3_X = LEFT - MP3_T / 2 - 0.0008
FACE = MP3_X - MP3_T / 2  # the MP3's front face
MP3_F = (-0.078, 0.036)  # along the gun: stock end, muzzle end
MP3_Y = (-0.03, 0.03)


def tape_strip(m, M, f, tilt, reach=0.052):
    """One strip of duct tape across the player at `f`, stuck to the receiver above and below it."""
    top, bottom = MP3_Y[1], MP3_Y[0]
    m.box(M["tape"], (0.0012, top - bottom + 0.004, 0.017), (FACE - 0.0006, 0.0, f), tilt=tilt, bevel=0.0004)
    for sign in (1.0, -1.0):
        edge = top if sign > 0 else bottom
        # over the player's edge, back down onto the receiver, then flat on the receiver
        m.box(M["tape"], (MP3_T + 0.001, 0.0012, 0.017), (MP3_X, edge + sign * 0.0006, f + sign * tilt * 0.0002), bevel=0.0004)
        m.box(M["tape"], (0.0012, reach - abs(edge), 0.017), (LEFT - 0.0007, sign * (abs(edge) + (reach - abs(edge)) / 2), f + sign * tilt * 0.0004), tilt=tilt * 0.6, bevel=0.0004)
    # a torn, slightly lifted end
    m.box(M["tape"], (0.0012, 0.008, 0.013), (LEFT - 0.0015, -(reach + 0.003), f + 0.002), tilt=tilt + 18.0, bevel=0.0003)


def mixtape_mp3(m, M):
    f0, f1 = MP3_F
    fc = (f0 + f1) / 2
    # body: white face, chrome back
    m.box(M["plastic"], (MP3_T * 0.55, MP3_Y[1] - MP3_Y[0], f1 - f0), (MP3_X - MP3_T * 0.22, 0.0, fc), bevel=0.0045)
    m.box(M["chrome"], (MP3_T * 0.5, MP3_Y[1] - MP3_Y[0] - 0.001, f1 - f0 - 0.001), (MP3_X + MP3_T * 0.24, 0.0, fc), bevel=0.0045)
    # screen: dark glass in a thin black bezel (the song name is drawn over it by the game)
    sf, sy = 0.004, 0.003
    m.box(M["rubber"], (0.0008, 0.038, 0.046), (FACE - 0.0002, sy, sf), bevel=0.001)
    m.box(M["screen"], (0.0006, 0.032, 0.040), (FACE - 0.0007, sy, sf), bevel=0.0)
    m.empty("Screen", FACE - 0.0012, sy, sf)
    # click wheel with its four marks and the centre button
    wf = -0.047
    m.cylx(M["wheel"], 0.0185, FACE - 0.0007, FACE + 0.0004, wf, 0.0, segs=28, bevel=0.0004)
    m.cylx(M["plastic"], 0.0068, FACE - 0.0012, FACE - 0.0003, wf, 0.0, segs=20, bevel=0.0004)
    for df, dy, size in ((0.0, 0.0125, (0.0006, 0.0018, 0.006)), (0.0, -0.0125, (0.0006, 0.0035, 0.0035)),
            (0.0125, 0.0, (0.0006, 0.0035, 0.0025)), (-0.0125, 0.0, (0.0006, 0.0035, 0.0025))):
        m.box(M["rubber"], size, (FACE - 0.0011, dy, wf + df), bevel=0.0)
    # hold switch and headphone jack on the top edge
    m.box(M["chrome"], (0.004, 0.002, 0.008), (MP3_X, MP3_Y[1] + 0.0008, f0 + 0.012), bevel=0.0005)
    jack_f = f1 - 0.01
    m.rod(M["rubber"], 0.0024, (MP3_X, MP3_Y[1] - 0.001, jack_f), (MP3_X, MP3_Y[1] + 0.003, jack_f), segs=10)
    # the earbud cable: up out of the jack, over the edge, down past the receiver, splitting to two earbuds
    path = [(MP3_X, MP3_Y[1] + 0.002, jack_f), (MP3_X - 0.004, MP3_Y[1] + 0.012, jack_f + 0.01),
        (MP3_X - 0.01, MP3_Y[1] + 0.004, jack_f + 0.03), (MP3_X - 0.014, -0.02, jack_f + 0.04),
        (MP3_X - 0.016, -0.075, jack_f + 0.036), (MP3_X - 0.017, -0.095, jack_f + 0.03)]
    for a, b in zip(path, path[1:]):
        m.rod(M["cable"], 0.0013, a, b, segs=6)
    split = path[-1]
    for side, (dx, dy, df) in (("l", (-0.004, -0.032, -0.012)), ("r", (0.003, -0.024, 0.014))):
        tip = (split[0] + dx, split[1] + dy, split[2] + df)
        m.rod(M["cable"], 0.0011, split, tip, segs=6)
        m.ball(M["cable"], (0.0075, 0.0075, 0.0085), (tip[0], tip[1] - 0.006, tip[2]))
        m.ball(M["wheel"], (0.0058, 0.0058, 0.0035), (tip[0] - 0.006, tip[1] - 0.006, tip[2]))
    # two strips of duct tape, not quite straight
    tape_strip(m, M, f0 + 0.009, 6.0)
    tape_strip(m, M, f1 - 0.006, -9.0, reach=0.058)


MODELS = {"mixtape_mp3": mixtape_mp3}

if __name__ == "__main__":
    import bpy
    bpy.ops.wm.read_factory_settings(use_empty=True)
    textures = os.path.join(OUT, "textures")
    M = {name: kit.material(name, kit.make_textures(textures, name, kind, color, seed)) for name, (kind, color, seed) in SPECS.items()}
    M["screen"] = kit.material("screen", None, (0.04, 0.08, 0.12))
    for model_id, build in MODELS.items():
        if len(sys.argv) > 1 and model_id not in sys.argv[1:]:
            continue
        model = kit.Model(model_id)
        build(model, M)
        print("%s: %d triangles" % (model_id, model.export(OUT)))
