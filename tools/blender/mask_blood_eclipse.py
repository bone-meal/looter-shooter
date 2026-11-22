# Blood Eclipse mask (boss mask 5, diary/DECISIONS_SKINS.md A5 + diary/MASK_PROCESS.md section 5): the base-2 smooth
# full face in deep black lacquer, sharpened: a knife-edge brow, angled slit eyes glowing faint red. Silhouette plan:
# FRONT = a raised ECLIPSE DISC on the forehead inside a glowing groove ring + the sharp brow; SIDE = the disc's
# thickness + a blade-like FIN sweeping back from each temple; BACK = the fins + the face plate's rim.
# Behaviour: glossy lacquer; the disc carries a dark moon with a red corona and its bright bead (fxBG_: glows AND is
# the moving part: the game turns it about its axis = the eclipse travelling round the forehead); groove + eyes fxR_;
# red haze from the groove (game particles).
# Run: python3 tools/blender/mask_blood_eclipse.py <out dir> [all | 34,front,side,back]   (env RES / SPP)
# Game build: python3 tools/blender/mask_bake.py blood_eclipse
# Dependencies: tools/blender/mask_kit.py.
import os
import sys
import math

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import mask_kit as K  # noqa: E402
from mask_kit import np, sd_ellipsoid, sd_capsule, smin, smax, groove  # noqa: E402
from mathutils import Vector, Matrix  # noqa: E402

GAME_FIT = {"scale": 0.13, "lift": 0.10, "back": -0.02}
SC = K.setup(53)


# ------------------------------------------------------------------ materials
def lacquer(name, base=(0.011, 0.009, 0.01), rough=0.2):
    """Deep black lacquer: a hint of orange peel in the coat, glossy."""
    m = K.bpy.data.materials.new(name)
    N, L = K.nodes(m)
    b = N["Principled BSDF"]
    b.inputs["Base Color"].default_value = (*base, 1)
    b.inputs["Roughness"].default_value = rough
    b.inputs["Coat Weight"].default_value = 1.0
    b.inputs["Coat Roughness"].default_value = 0.04
    tc = N.new("ShaderNodeTexCoord")
    peel = N.new("ShaderNodeTexNoise"); peel.inputs["Scale"].default_value = 60.0; peel.inputs["Detail"].default_value = 2
    L.new(tc.outputs["Object"], peel.inputs["Vector"])
    bump = N.new("ShaderNodeBump"); bump.inputs["Strength"].default_value = 0.08; bump.inputs["Distance"].default_value = 0.002
    L.new(peel.outputs["Fac"], bump.inputs["Height"]); L.new(bump.outputs["Normal"], b.inputs["Coat Normal"])
    return m


SHELL = lacquer("lacquer")
FIN = lacquer("fin_lacquer", (0.016, 0.006, 0.007), 0.16)  # the fins a touch redder in the black
DISC = lacquer("fxB_disc", (0.02, 0.012, 0.012), 0.14)
MOON = K.simple("fxB_moon", (0.004, 0.003, 0.003), 0.55)
CORONA = K.glow("fxBG_corona", (1.0, 0.06, 0.04), 16.0, base=(0.25, 0.0, 0.0))
RED = K.glow("fxR_red", (1.0, 0.05, 0.03), 9.0, base=(0.15, 0.0, 0.0))
HOLE = K.simple("eye_hole", (0.004, 0.003, 0.003), 0.9)

# the eclipse disc: centre on the forehead, axis out of it (sculpt space)
DISC_AT = Vector((0.0, -0.746, 0.726))
DISC_N = Vector((0.0, -0.76, 0.65)).normalized()
DISC_R = 0.2


# ------------------------------------------------------------------ the face
def ring_sd(P, c, n, R, r):
    """A torus round axis n through c (ring radius R, tube r)."""
    q = P - np.array(c)
    along = q @ np.array(n)
    rad = np.linalg.norm(q - along[..., None] * np.array(n), axis=-1)
    return np.sqrt((rad - R) ** 2 + along ** 2) - r


def face(P):
    x, y, z = P[..., 0], P[..., 1], P[..., 2]
    d = sd_ellipsoid(P, (0, 0.02, 0.2), (0.8, 0.94, 0.84))  # cranium
    d = smax(d, y - 0.86, 0.2)  # a flatter back
    d = smin(d, sd_ellipsoid(P, (0, -0.36, -0.28), (0.6, 0.64, 0.52)), 0.25)  # lower face and jaw
    d = smin(d, sd_ellipsoid(P, (0, -0.8, -0.5), (0.22, 0.17, 0.16)), 0.14)  # chin
    d = smax(d, -y - 1.0, 0.16)  # the soft front plane
    for s in (-1, 1):
        # the brow: a knife edge, low at the middle (scowl), raked back at the temples
        d = smin(d, sd_capsule(P, (s * 0.04, -0.975, 0.36), (s * 0.4, -0.85, 0.46), 0.04), 0.09)
        d = smax(d, -sd_capsule(P, (s * 0.04, -1.03, 0.3), (s * 0.4, -0.9, 0.4), 0.045), 0.03)  # undercut: crisp edge
        d = smin(d, sd_ellipsoid(P, (s * 0.45, -0.76, 0.06), (0.21, 0.16, 0.12)), 0.1)  # cheekbone
        d = smax(d, -sd_ellipsoid(P, (s * 0.72, -0.42, 0.36), (0.12, 0.2, 0.16)), 0.12)  # temple
        # the slit eye: a long thin cut tilted down toward the nose
        q = P - np.array([s * 0.29, -0.97, 0.265])
        rot = np.stack([q[..., 0] * math.cos(0.28) - s * q[..., 2] * math.sin(0.28), q[..., 1],
                        s * q[..., 0] * math.sin(0.28) + q[..., 2] * math.cos(0.28)], axis=-1)
        d = smax(d, -sd_ellipsoid(rot, (0, 0, 0), (0.13, 0.3, 0.026)), 0.012)
        d = smin(d, sd_ellipsoid(P, (s * 0.07, -1.05, 0.02), (0.045, 0.045, 0.035)), 0.03)  # nostril wing
    d = smin(d, sd_capsule(P, (0, -0.98, 0.33), (0, -1.11, 0.07), 0.045), 0.05)  # nose: narrow, straight
    d = smin(d, sd_ellipsoid(P, (0, -1.1, 0.04), (0.075, 0.065, 0.055)), 0.04)
    d = smin(d, sd_ellipsoid(P, (0, -0.9, -0.2), (0.28, 0.13, 0.17)), 0.12)  # muzzle
    d = smin(d, sd_ellipsoid(P, (0, -1.01, -0.17), (0.15, 0.04, 0.028)), 0.025)  # thin hard lips
    d = smin(d, sd_ellipsoid(P, (0, -0.99, -0.245), (0.13, 0.04, 0.032)), 0.025)
    mouth = np.where((np.abs(x) < 0.17) & (y < -0.85), z + 0.205 + 0.03 * (x / 0.16) ** 2, 9.0)
    d = groove(d, mouth, 0.012, 0.007, 0.0)
    d = smin(d, sd_capsule(P, (0, 0.1, -0.5), (0, 0.12, -0.95), 0.5), 0.2)  # neck down to the collar
    d = smax(d, -(z + 0.97), 0.03)
    # the face plate's rim: a step from the temples past the ears to the jaw
    edge = np.where(y < 0.2, y - (-0.42 + 0.22 * np.clip((0.55 - z) / 1.3, 0.0, 1.0)), 9.0)
    d = groove(d, edge, 0.014, 0.014, -0.022)
    w = np.clip(y / 0.35, 0.0, 1.0)  # back panels: two seams from behind the temples down to the nape, the middle plate raised
    for s in (-1, 1):
        pd = s * x - (0.34 - 0.1 * z)
        d = d + 0.01 * w * np.exp(-(pd / 0.012) ** 2) - 0.012 * w * 0.5 * (1.0 - np.tanh(pd / 0.005))
    # the disc's seat: a raised boss with the glowing groove ring round the disc
    d = smin(d, ring_sd(P, DISC_AT - DISC_N * 0.03, DISC_N, DISC_R + 0.02, 0.045), 0.05)
    d = smax(d, -ring_sd(P, DISC_AT, DISC_N, DISC_R + 0.028, 0.017), 0.006)
    return d


head = K.sdf_mesh("face", face, (-0.95, -1.25, -1.0), (0.95, 1.1, 1.2), 0.012, SHELL)
K.tube("groove_glow", [DISC_AT - DISC_N * 0.012 + (Matrix.Rotation(a, 3, DISC_N) @ Vector((DISC_R + 0.028, 0, 0)))
                       for a in np.linspace(0, 2 * math.pi, 49)], 0.011, RED, res=3)
for s in (-1, 1):  # red light deep in the slits
    K.ball("eye_dark", 0.1, (s * 0.29, -0.83, 0.265), HOLE, (1.15, 1.0, 0.3), 16)
    K.ball("eye_glow", 0.07, (s * 0.29, -0.9, 0.262), RED, (1.5, 0.5, 0.25), 16)


# ------------------------------------------------------------------ the eclipse disc (built at the origin, axis +z, then set on the forehead)
def disc_sd(P):
    rad = np.linalg.norm(P[..., :2], axis=-1)
    d = smax(rad - DISC_R, np.abs(P[..., 2]) - 0.03, 0.015)  # a thick coin with rounded edges
    return d


disc = K.sdf_mesh("eclipse_disc", disc_sd, (-0.24, -0.24, -0.05), (0.24, 0.24, 0.05), 0.006, DISC)
# the red sun on the disc's face, the black moon over it a little off centre: a crescent of red light
sun = K.sdf_mesh("eclipse_sun", lambda P: smax(np.linalg.norm(P[..., :2], axis=-1) - 0.15, np.abs(P[..., 2] - 0.031) - 0.003, 0.002),
                 (-0.17, -0.17, 0.02), (0.17, 0.17, 0.042), 0.004, CORONA)
moon = K.sdf_mesh("eclipse_moon", lambda P: smax(np.linalg.norm(P[..., :2] - np.array([0.035, -0.022]), axis=-1) - 0.135,
                                                  np.abs(P[..., 2] - 0.036) - 0.006, 0.004),
                  (-0.16, -0.16, 0.02), (0.2, 0.2, 0.05), 0.004, MOON)
# the corona: a thin ring round the moon, thicker and brighter on one side (the bead of the diamond ring)
K.ball("corona_bead", 0.026, (0.152 * math.cos(2.55), 0.152 * math.sin(2.55), 0.034), CORONA, (1.0, 1.0, 0.35), 16)  # the bright bead where the crescent is thinnest
place = Matrix.Translation(DISC_AT) @ Vector((0, 0, 1)).rotation_difference(DISC_N).to_matrix().to_4x4()
for o in list(K.bpy.data.objects):
    if o.name.startswith(("eclipse_disc", "eclipse_moon", "eclipse_sun", "corona")):
        o.matrix_world = place @ o.matrix_world


# ------------------------------------------------------------------ fins: blades sweeping back from the temples
for s in (-1, 1):
    a0 = Vector((s * 0.7, -0.5, 0.42)); a1 = Vector((s * 0.9, 0.4, 0.66)); a2 = Vector((s * 0.82, 1.4, 1.18))

    def path(t, a0=a0, a1=a1, a2=a2):
        return a0 * (1 - t) ** 2 + a1 * 2 * t * (1 - t) + a2 * t * t
    K.loft("fin", path, lambda t: 0.04 + 0.23 * math.sin(math.pi * min(t * 1.25, 1.0)) * (1 - t) ** 0.6 + 0.004,
           60, 12, profile=lambda th, t: (0.16, 1.0), mat=FIN)
    # a red line along the fin's root, glowing
    K.tube("fin_line", [path(t) + Vector((s * 0.012, 0, -0.01)) for t in np.linspace(0.05, 0.7, 14)], 0.006, RED, res=2,
           taper=lambda t: 1.0 - 0.7 * t)

# a dorsal fin down the middle of the back: from the crown over the back of the skull to the nape
def dorsal(t):
    a = 0.25 + 2.0 * t  # an arc round the skull, crown to nape
    return Vector((0.0, 0.02 + 0.98 * math.sin(a), 0.2 + 0.88 * math.cos(a)))


def dorsal_h(t):
    return 0.025 + 0.22 * math.sin(math.pi * t ** 0.6) * (1 - 0.75 * t)


K.loft("dorsal_fin", lambda t: dorsal(t) + (dorsal(t) - Vector((0, 0.02, 0.2))).normalized() * dorsal_h(t) * 0.55, dorsal_h,
       60, 12, profile=lambda th, t: (0.14, 1.0), mat=FIN)
K.tube("dorsal_line", [dorsal(t) + Vector((0.025, 0, 0)) for t in np.linspace(0.08, 0.9, 20)], 0.006, RED, res=2)
K.tube("dorsal_line", [dorsal(t) + Vector((-0.025, 0, 0)) for t in np.linspace(0.08, 0.9, 20)], 0.006, RED, res=2)

if K.GAME:
    raise SystemExit(0)  # tools/blender/mask_bake.py takes it from here

K.stage(head=False)
K.shoot_views("blood_eclipse")
print("ok")
