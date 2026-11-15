# Purpose: developer-time script. Models the gimmicks fixed onto the named chase guns (diary/DESIGN_UNIQUES.md) with
# tools/blender/kit.py into assets/models/weapons/uniques/<id>.gltf. Each is built in the GUN SPACE of the body it
# rides on (origin = the gun model's origin), so game/unique_attach.gd adds it at the gun's root with no offset.
# MIXTAPE: an MP3 player lying on the LEFT side of the M16 receiver (the side the first-person camera sees), screen
# toward the muzzle end, click wheel toward the stock, held on by two strips of silver duct tape, earbuds dangling
# from its jack. An empty "Screen" marks the middle of its screen, where the game puts the scrolling song name.
# FISH STORY: a bent fishing rod hose-clamped under the sniper's barrel (cork handle and reel at the handguard, the tip
# bowed down past the muzzle with a red-and-white bobber on its line) and a small brass tag hanging from the
# handguard's LEFT side on a split ring. An empty "Tag" marks the tag's face, where the game writes the biggest hit.
# BEACH BALL BOMBARDIER: an inflated beach ball jammed onto the grenade launcher's muzzle (six coloured gores, white
# caps, the valve on its side), and the beach ball it fires (beach_ball: radius 1 about the origin, scaled in game).
# CROAK: a small green frog sitting on the M16's ACOG, facing forward, with gold bulging eyes; its eyelids are their
# own node "Lids" (hidden; the game shows them for a blink). croak_frog = the same frog about the origin, the one that
# leaps off onto an enemy's head.
# SWAMP GAS: a jar of murky swamp water lying along the double shotgun's LEFT side at the fore-end, screw lid toward
# the muzzle, held by two leather straps round the fore-end; bubbles on the water in the jar's air gap are their own
# node "Bubbles" (the game jiggles them).
# KEEPER'S LANTERN: a small tin storm lantern hanging by its bail from a clamp under the pistol's barrel; node "Swing"
# (pivot at the hook) is swayed by the game, node "Flame" inside the cage gets the game's glow and light.
# keepers_lantern_free = the same lantern about the origin (thrown as a firebomb).
# GRILLMASTER: a little grill grate bolted flat against the LEFT of the double shotgun's barrels, a sausage on it, and
# a pair of tongs clipped under it. grilled_kebab = the food a burning kill drops (about the origin).
# VOLCANO SAUCE: a small bottle of red hot sauce (white cap, label) taped upright against the LEFT of the pistol grip
# with two strips of silver duct tape.
# Run: python3 tools/blender/unique_attach.py [ids]   (from the project folder)
import math
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
    "brass": ("metal", (0.78, 0.6, 0.28), 47), "cork": ("wood", (0.66, 0.5, 0.32), 48),
    "rodglass": ("polymer", (0.12, 0.22, 0.2), 49), "bobred": ("polymer", (0.85, 0.12, 0.1), 50),
    "line": ("polymer", (0.9, 0.92, 0.95), 51),
    "gore_red": ("polymer", (0.86, 0.14, 0.12), 52), "gore_yellow": ("polymer", (0.98, 0.82, 0.16), 53),
    "gore_blue": ("polymer", (0.14, 0.38, 0.86), 54), "gore_white": ("polymer", (0.95, 0.95, 0.94), 55),
    "gore_green": ("polymer", (0.2, 0.7, 0.3), 56), "gore_orange": ("polymer", (0.98, 0.5, 0.12), 57),
    "frogskin": ("hide", (0.3, 0.62, 0.22), 58), "frogbelly": ("polymer", (0.86, 0.84, 0.55), 59),
    "frogeye": ("polymer", (0.9, 0.72, 0.18), 60),
    "swampwater": ("matte", (0.27, 0.34, 0.11), 61), "jarglass": ("polymer", (0.72, 0.82, 0.76), 62),
    "strap": ("hide", (0.36, 0.22, 0.12), 63), "lidtin": ("paint", (0.55, 0.45, 0.22), 64),
    "lanterntin": ("paint", (0.2, 0.24, 0.2), 65), "flame": ("matte", (1.0, 0.7, 0.25), 66),
    "charsteel": ("metal", (0.16, 0.15, 0.14), 67), "sausage": ("matte", (0.55, 0.26, 0.14), 68),
    "meat": ("matte", (0.45, 0.22, 0.12), 69), "pepper": ("polymer", (0.25, 0.55, 0.18), 70),
    "onion": ("matte", (0.86, 0.8, 0.62), 71), "char": ("matte", (0.08, 0.06, 0.05), 72), "skewer": ("wood", (0.72, 0.58, 0.38), 73),
    "hotsauce": ("polymer", (0.72, 0.08, 0.05), 74), "saucelabel": ("matte", (0.95, 0.85, 0.45), 75),
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


ROD_Y = -0.018  # under the sniper's barrel (barrel axis y 0.01, radius 0.016)
TAG_X = -0.031  # just off the handguard's left face (half width 0.026)


def fish_story_rod(m, M):
    # cork handle and reel seat at the front of the handguard, hose-clamped to the barrel
    m.cyl(M["cork"], 0.0085, 0.6, 0.7, ROD_Y, segs=14, bevel=0.002)
    m.cyl(M["chrome"], 0.0095, 0.7, 0.712, ROD_Y, segs=14, bevel=0.001)
    m.cyl(M["rodglass"], 0.0062, 0.712, 0.9, ROD_Y, segs=12, r2=0.0045, bevel=0.0)
    # the reel hanging under the seat: spool, side plates, crank and knob
    reel_f, reel_y = 0.665, ROD_Y - 0.026
    m.rod(M["chrome"], 0.003, (0.0, ROD_Y - 0.006, reel_f), (0.0, reel_y + 0.012, reel_f), segs=8)
    m.cylx(M["chrome"], 0.017, -0.009, 0.009, reel_f, reel_y, segs=22, bevel=0.0015)
    m.cylx(M["line"], 0.0135, -0.0095, 0.0095, reel_f, reel_y, segs=22, bevel=0.0)
    m.cylx(M["chrome"], 0.0045, -0.0215, -0.0095, reel_f, reel_y, segs=10)
    m.rod(M["chrome"], 0.0018, (-0.021, reel_y, reel_f), (-0.024, reel_y - 0.016, reel_f + 0.004), segs=6)
    m.ball(M["rubber"], (0.0045, 0.006, 0.0045), (-0.029, reel_y - 0.018, reel_f + 0.004))
    # two hose clamps round barrel and rod
    for f in (0.78, 0.93):
        m.cyl(M["chrome"], 0.0215, f - 0.006, f + 0.006, (0.01 + ROD_Y) / 2, segs=18, bevel=0.0008)
        m.box(M["chrome"], (0.006, 0.008, 0.01), (0.022, (0.01 + ROD_Y) / 2, f), bevel=0.001)  # the screw housing
    # the blank: straight along the barrel, then bowed down past the muzzle (it caught something once)
    pts = [(0.0, ROD_Y, 0.9), (0.0, ROD_Y - 0.002, 1.0), (0.0, ROD_Y - 0.01, 1.08), (0.0, ROD_Y - 0.03, 1.15),
        (0.0, ROD_Y - 0.062, 1.2), (0.0, ROD_Y - 0.1, 1.225)]
    radius = 0.0045
    for a, b in zip(pts, pts[1:]):
        m.rod(M["rodglass"], radius, a, b, r2=radius * 0.78, segs=8)
        radius *= 0.78
    for a in pts[1:-1]:  # line guides
        m.ball(M["chrome"], (0.0035, 0.0035, 0.0012), (a[0], a[1] - 0.005, a[2]))
    # line from the reel along the blank to the tip, then down to a bobber
    tip = pts[-1]
    m.rod(M["line"], 0.0006, (0.0, reel_y - 0.004, reel_f + 0.01), (0.0, ROD_Y - 0.006, 0.9), segs=4)
    m.rod(M["line"], 0.0006, tip, (tip[0], tip[1] - 0.07, tip[2] + 0.004), segs=4)
    bob = (tip[0], tip[1] - 0.082, tip[2] + 0.004)
    m.ball(M["bobred"], (0.0105, 0.009, 0.0105), (bob[0], bob[1] - 0.004, bob[2]))
    m.ball(M["cable"], (0.0108, 0.0085, 0.0108), (bob[0], bob[1] + 0.0045, bob[2]))
    m.rod(M["rubber"], 0.0016, (bob[0], bob[1] + 0.012, bob[2]), (bob[0], bob[1] + 0.02, bob[2]), segs=6)
    # brass tag on a split ring from the handguard's left side, hanging a little skew
    ring_f, ring_y = 0.47, -0.036
    m.cylx(M["chrome"], 0.0045, TAG_X - 0.0012, TAG_X + 0.0012, ring_f, ring_y, segs=12, bevel=0.0)
    m.rod(M["chrome"], 0.001, (TAG_X, ring_y - 0.004, ring_f), (TAG_X - 0.001, ring_y - 0.012, ring_f + 0.002), segs=4)
    tag_y, tag_f = ring_y - 0.044, ring_f + 0.004
    m.box(M["brass"], (0.0018, 0.06, 0.075), (TAG_X - 0.002, tag_y, tag_f), tilt=3.0, bevel=0.003)
    m.cylx(M["rubber"], 0.0026, TAG_X - 0.0038, TAG_X - 0.0005, tag_f, tag_y + 0.023, segs=10, bevel=0.0)  # punched hole
    m.empty("Tag", TAG_X - 0.0034, tag_y - 0.005, tag_f)


GORES = ("gore_red", "gore_white", "gore_yellow", "gore_blue", "gore_green", "gore_orange")


def beach_ball_at(m, M, center, r, segs_per_gore=4, rings=10):
    """A beach ball of radius r at center (x, y, f): six gores from pole to pole along the gun (f axis), white caps,
    a valve on its side. Each gore is its own strip of quads so the colours meet on clean seams."""
    import bmesh
    from mathutils import Vector
    cx, cy, cf = center
    cap = math.radians(14.0)  # the white cap covers the poles
    for g, name in enumerate(GORES):
        bm = bmesh.new()
        rows = []
        for i in range(rings + 1):
            lat = -math.pi / 2 + cap + (math.pi - 2 * cap) * i / rings  # along f: pole to pole
            row = []
            for j in range(segs_per_gore + 1):
                lon = 2 * math.pi * (g + j / segs_per_gore) / len(GORES)
                x = cx + r * math.cos(lat) * math.cos(lon)
                y = cy + r * math.cos(lat) * math.sin(lon)
                f = cf + r * math.sin(lat)
                row.append(bm.verts.new((x, f, y)))  # Blender space: (x, f, y)
            rows.append(row)
        for i in range(rings):
            for j in range(segs_per_gore):
                bm.faces.new((rows[i][j], rows[i][j + 1], rows[i + 1][j + 1], rows[i + 1][j]))
        m._add(bm, M[name], "Body", 0)
    for sign in (1.0, -1.0):  # white caps over both poles
        m.ball(M["gore_white"], (r * 0.27, r * 0.27, r * 0.06), (cx, cy, cf + sign * r * 0.985), u=16, v=6)
    # the valve: a little stub and its folded plug on one white gore
    lon = 2 * math.pi * 1.5 / len(GORES)
    vx, vy = cx + r * math.cos(lon), cy + r * math.sin(lon)
    out = (math.cos(lon), math.sin(lon))
    m.rod(M["gore_white"], r * 0.07, (vx, vy, cf + r * 0.25), (vx + out[0] * r * 0.12, vy + out[1] * r * 0.12, cf + r * 0.25), segs=10)
    m.ball(M["gore_white"], (r * 0.06, r * 0.06, r * 0.09), (vx + out[0] * r * 0.14, vy + out[1] * r * 0.14, cf + r * 0.33))


def beach_ball_muzzle(m, M):
    """Jammed onto the grenade launcher's muzzle (tube radius 0.034, mouth at f 0.4865): the tube's end sinks into it."""
    beach_ball_at(m, M, (0.0, 0.0, 0.55), 0.085)


def beach_ball(m, M):
    """The fired ball, radius 1 about the origin (the game scales it)."""
    beach_ball_at(m, M, (0.0, 0.0, 0.0), 1.0, segs_per_gore=5, rings=12)


def frog_at(m, M, at):
    """A small frog sitting at `at` (x, y, f: the middle under its belly), facing +f. About 5 cm long."""
    m.shift = at
    m.ball(M["frogskin"], (0.019, 0.012, 0.024), (0.0, 0.012, -0.002), pitch=-12.0, u=16, v=10)  # body, rump low
    m.ball(M["frogbelly"], (0.016, 0.008, 0.02), (0.0, 0.008, 0.0), u=14, v=8)
    m.ball(M["frogskin"], (0.016, 0.01, 0.014), (0.0, 0.019, 0.017), u=16, v=10)  # head
    m.ball(M["frogbelly"], (0.013, 0.006, 0.011), (0.0, 0.014, 0.02), u=12, v=8)  # throat
    m.box(M["rubber"], (0.02, 0.0012, 0.0012), (0.0, 0.0165, 0.0305), bevel=0.0)  # the mouth line
    for side in (-1.0, 1.0):
        x = side * 0.0085
        m.ball(M["frogskin"], 0.0062, (x, 0.0265, 0.017), u=12, v=8)  # eye bulge
        m.ball(M["frogeye"], 0.0052, (x + side * 0.0012, 0.0275, 0.0185), u=12, v=8)
        m.ball(M["rubber"], (0.0018, 0.0034, 0.0024), (x + side * 0.0055, 0.0278, 0.0195), u=8, v=6)  # pupil
        m.ball(M["frogskin"], (0.0058, 0.0035, 0.0058), (x + side * 0.0012, 0.0302, 0.0185), node="Lids", u=12, v=6)  # eyelid
        # folded back legs and little front legs with splayed toes
        m.ball(M["frogskin"], (0.007, 0.0065, 0.016), (side * 0.017, 0.007, -0.012), yaw=side * 18.0, u=10, v=8)
        m.ball(M["frogskin"], (0.0045, 0.003, 0.012), (side * 0.02, 0.002, 0.0), yaw=-side * 12.0, u=8, v=6)
        m.rod(M["frogskin"], 0.0024, (side * 0.011, 0.01, 0.016), (side * 0.014, 0.002, 0.024), segs=6)
        for toe in (-1.0, 0.0, 1.0):
            m.ball(M["frogbelly"], (0.0016, 0.0009, 0.0026), (side * 0.0145 + toe * 0.002, 0.0012, 0.0265 + abs(toe) * -0.0008), u=6, v=4)
    m.shift = None
    m.node("Lids", (at[0], at[1] + 0.03, at[2] + 0.018))


def croak_scope(m, M):
    """The frog on the M16's ACOG (sight mount y 0.136; the ACOG's top about 0.06-0.07 above it)."""
    frog_at(m, M, (0.0, 0.198, -0.02))


def croak_frog(m, M):
    frog_at(m, M, (0.0, 0.0, 0.0))


JAR_X, JAR_Y, JAR_R = -0.058, -0.008, 0.024  # the jar's axis (along f) beside the fore-end (half width 0.028)
JAR_F = (0.15, 0.25)


def swamp_jar(m, M):
    f0, f1 = JAR_F
    m.cyl(M["swampwater"], JAR_R, f0 + 0.004, f1 - 0.012, JAR_Y, x=JAR_X, segs=20, bevel=0.0)
    for f in (f0, f1 - 0.016):  # thick glass rims at both ends, and the glass bottom
        m.cyl(M["jarglass"], JAR_R + 0.0018, f, f + 0.006, JAR_Y, x=JAR_X, segs=20, bevel=0.001)
    m.box(M["jarglass"], (0.012, 0.004, f1 - f0 - 0.02), (JAR_X, JAR_Y + JAR_R - 0.001, (f0 + f1) / 2 - 0.004), bevel=0.0015)  # the air gap
    # screw lid toward the muzzle with ridges
    m.cyl(M["lidtin"], JAR_R + 0.0012, f1 - 0.012, f1, JAR_Y, x=JAR_X, segs=24, bevel=0.0015)
    for k in range(12):
        a = 2 * math.pi * k / 12
        m.box(M["lidtin"], (0.002, 0.002, 0.01), (JAR_X + math.cos(a) * (JAR_R + 0.0018), JAR_Y + math.sin(a) * (JAR_R + 0.0018), f1 - 0.006), bevel=0.0)
    # bubbles on the water in the air gap
    m.node("Bubbles", (JAR_X, JAR_Y + JAR_R, (f0 + f1) / 2))
    for dx, df, r in ((-0.003, -0.02, 0.0028), (0.002, -0.004, 0.0022), (-0.001, 0.012, 0.0032), (0.003, 0.026, 0.0018)):
        m.ball(M["jarglass"], r, (JAR_X + dx, JAR_Y + JAR_R + 0.0012, (f0 + f1) / 2 + df), node="Bubbles", u=8, v=6)
    # two leather straps round jar and fore-end, buckles on the outside
    for f in (f0 + 0.022, f1 - 0.03):
        m.cyl(M["strap"], JAR_R + 0.003, f - 0.006, f + 0.006, JAR_Y, x=JAR_X, segs=20, bevel=0.0008)
        m.box(M["strap"], (0.06, 0.003, 0.012), (JAR_X + 0.03, JAR_Y + JAR_R + 0.0015, f), bevel=0.0008)  # over the top
        m.box(M["strap"], (0.06, 0.003, 0.012), (JAR_X + 0.03, -0.047, f), bevel=0.0008)  # under the fore-end
        m.box(M["strap"], (0.003, 0.05, 0.012), (0.03, -0.02, f), bevel=0.0008)  # up the far side
        m.box(M["chrome"], (0.004, 0.012, 0.014), (JAR_X - JAR_R - 0.004, JAR_Y, f), bevel=0.001)  # buckle


def lantern_at(m, M, hook, node="Swing"):
    """A storm lantern hanging from `hook` (x, y, f): bail, cap, four posts round the flame, fuel tank. ~9 cm tall."""
    hx, hy, hf = hook
    top = hy - 0.028  # the cap's top
    r = 0.018
    m.node(node, (hx, hy, hf))
    # the wire bail from the hook down to both sides of the cap
    for side in (-1.0, 1.0):
        m.rod(M["chrome"], 0.0011, (hx, hy - 0.002, hf), (hx + side * 0.016, top - 0.004, hf), segs=5, node=node)
    m.cylx(M["chrome"], 0.0035, hx - 0.0015, hx + 0.0015, hf, hy - 0.002, segs=10, bevel=0.0, node=node)  # the bail's eye on the hook
    # cap: a little cone with a vent ring
    m.lathe(M["lanterntin"], [(r + 0.004, 0.0), (r + 0.003, 0.002), (0.006, 0.012), (0.004, 0.018)], (hx, top - 0.018, hf), node=node, segs=16)
    m.cyl(M["lanterntin"], 0.0055, hf - 0.003, hf + 0.003, top + 0.002, x=hx, segs=10, bevel=0.0, node=node)
    # four posts round the flame, a guard ring halfway
    for k in range(4):
        a = math.pi / 4 + math.pi / 2 * k
        x, f = hx + math.cos(a) * r, hf + math.sin(a) * r
        m.rod(M["lanterntin"], 0.0012, (x, top - 0.018, f), (x, top - 0.06, f), segs=5, node=node)
    m.lathe(M["lanterntin"], [(r + 0.0005, 0.0), (r + 0.0012, 0.0015)], (hx, top - 0.04, hf), node=node, segs=16)
    # fuel tank and base
    m.lathe(M["lanterntin"], [(0.0, 0.0), (r + 0.004, 0.0), (r + 0.005, 0.006), (r + 0.002, 0.014), (0.007, 0.016)], (hx, top - 0.076, hf), node=node, segs=16)
    m.rod(M["chrome"], 0.0012, (hx, top - 0.06, hf), (hx, top - 0.054, hf), segs=5, node=node)  # wick tube
    # the flame (the game gives it its glow and light)
    m.node("Flame", (hx, top - 0.046, hf), parent=node)
    m.ball(M["flame"], (0.0035, 0.008, 0.0035), (hx, top - 0.046, hf), node="Flame", u=10, v=8)


def keepers_lantern(m, M):
    """Under the pistol's barrel (barrel axis y 0.022, the muzzle at f 0.294): a clamp ring with a hook at f 0.25."""
    m.cyl(M["chrome"], 0.0145, 0.244, 0.256, 0.022, segs=16, bevel=0.0008)
    m.rod(M["chrome"], 0.0016, (0.0, 0.008, 0.25), (0.0, -0.004, 0.25), segs=6)
    lantern_at(m, M, (0.0, -0.004, 0.25))


def keepers_lantern_free(m, M):
    lantern_at(m, M, (0.0, 0.05, 0.0))


GRILL_X = -0.048  # left of the barrels (they sit at x +-0.019, radius 0.017)
GRILL_F = (0.38, 0.54)


def grill_plate(m, M):
    f0, f1 = GRILL_F
    y0, y1 = -0.02, 0.04
    # frame and bars of the grate, standing on edge against the barrels
    for y in (y0, y1):
        m.box(M["charsteel"], (0.004, 0.004, f1 - f0), (GRILL_X, y, (f0 + f1) / 2), bevel=0.0008)
    for f in (f0, f1):
        m.box(M["charsteel"], (0.004, y1 - y0, 0.004), (GRILL_X, (y0 + y1) / 2, f), bevel=0.0008)
    for k in range(1, 8):
        f = f0 + (f1 - f0) * k / 8
        m.box(M["charsteel"], (0.0025, y1 - y0, 0.0022), (GRILL_X, (y0 + y1) / 2, f), bevel=0.0)
    # two bolts and spacers to the barrel
    for f in (f0 + 0.02, f1 - 0.02):
        m.rod(M["chrome"], 0.0028, (GRILL_X + 0.002, 0.01, f), (-0.034, 0.01, f), segs=8)
        m.cylx(M["chrome"], 0.0045, GRILL_X - 0.004, GRILL_X - 0.002, f, 0.01, segs=6, bevel=0.0)
    # a sausage cooking on it, with grill marks
    m.ball(M["sausage"], (0.007, 0.007, 0.03), (GRILL_X - 0.008, 0.012, (f0 + f1) / 2), u=12, v=8)
    for df in (-0.015, -0.005, 0.005, 0.015):
        m.box(M["char"], (0.0015, 0.012, 0.0022), (GRILL_X - 0.0148, 0.012, (f0 + f1) / 2 + df), tilt=20.0, bevel=0.0)
    # tongs clipped along the barrel underneath
    for side in (-1.0, 1.0):
        m.box(M["chrome"], (0.003, 0.0015, 0.13), (GRILL_X + 0.006 + side * 0.003, -0.03, 0.47), bevel=0.0005)
        m.box(M["chrome"], (0.006, 0.004, 0.014), (GRILL_X + 0.006 + side * 0.003, -0.03, 0.535), bevel=0.0008)
    m.cyl(M["rubber"], 0.004, 0.395, 0.425, -0.03, x=GRILL_X + 0.006, segs=8, bevel=0.001)


def grilled_kebab(m, M):
    """A skewer of grilled meat, pepper and onion, ~22 cm, lying along f about the origin."""
    m.rod(M["skewer"], 0.003, (0.0, 0.0, -0.11), (0.0, 0.0, 0.12), segs=6)
    pieces = [("meat", 0.022), ("pepper", 0.018), ("meat", 0.024), ("onion", 0.019), ("meat", 0.022)]
    f = -0.07
    for name, r in pieces:
        if name == "onion":
            m.cyl(M["onion"], r, f - 0.007, f + 0.007, 0.0, segs=12, bevel=0.002)
        elif name == "pepper":
            m.box(M["pepper"], (r * 1.6, r * 1.4, 0.014), (0.0, 0.0, f), tilt=12.0, bevel=0.004)
        else:
            m.box(M["meat"], (r * 1.5, r * 1.3, 0.024), (0.0, 0.0, f), tilt=-8.0, bevel=0.006)
            for dy in (-0.006, 0.004):
                m.box(M["char"], (r * 1.55, 0.0025, 0.026), (0.0, dy, f), tilt=-8.0, bevel=0.0)
        f += 0.034


def sauce_bottle(m, M):
    bx, by, bf = -0.036, -0.142, -0.006  # the bottle's foot, beside the grip (wood panels: half width 0.022)
    m.lathe(M["hotsauce"], [(0.0105, 0.0), (0.012, 0.004), (0.012, 0.046), (0.0085, 0.053), (0.0042, 0.059), (0.0042, 0.066)], (bx, by, bf), segs=18)
    m.lathe(M["saucelabel"], [(0.01245, 0.014), (0.01245, 0.038)], (bx, by, bf), segs=18)
    m.lathe(M["hotsauce"], [(0.0127, 0.022), (0.0127, 0.03)], (bx, by, bf), segs=18)  # a red band across the label
    m.lathe(M["cable"], [(0.0048, 0.066), (0.0048, 0.075), (0.003, 0.077)], (bx, by, bf), segs=14)  # cap
    for y, tilt in ((-0.125, 5.0), (-0.092, -7.0)):  # two strips of tape round bottle and grip
        m.box(M["tape"], (0.0012, 0.014, 0.03), (bx - 0.0125, y, bf), tilt=tilt, bevel=0.0004)
        for side in (-1.0, 1.0):
            m.box(M["tape"], (0.06, 0.014, 0.0012), (-0.006, y, bf + side * 0.0128), tilt=tilt, bevel=0.0004)
        m.box(M["tape"], (0.0012, 0.014, 0.024), (0.0235, y, bf), tilt=tilt, bevel=0.0004)


MODELS = {"mixtape_mp3": mixtape_mp3, "sauce_bottle": sauce_bottle, "grill_plate": grill_plate, "grilled_kebab": grilled_kebab, "keepers_lantern": keepers_lantern, "keepers_lantern_free": keepers_lantern_free, "swamp_jar": swamp_jar, "croak_scope": croak_scope, "croak_frog": croak_frog, "fish_story_rod": fish_story_rod, "beach_ball_muzzle": beach_ball_muzzle,
    "beach_ball": beach_ball}

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
