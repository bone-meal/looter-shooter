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
# HOT POTATO: a foil-wrapped baked potato strapped on top of the grenade launcher's tube, foil peeled back at the
# front to show the split skin and a pat of butter.
# PENGUIN RESCUE: a small penguin perched on the back of the pistol's slide, facing forward; penguin = the same bird
# about the origin (the freed ones that belly-slide into enemies).
# BRAIN FREEZE: a slushie cup taped upright against the LEFT of the M60's barrel jacket near the muzzle end, a striped
# straw leaning back toward the shooter; the blue slush inside is its own node "Slush" (pivot at the cup's floor: the
# game scales it down as the cup is drunk).
# AVALANCHE CONTROL: a ski pole strapped along the LEFT of the rocket tube (rubber grip and wrist loop at the back, a
# basket and steel tip at the front). snowball = the rolling snowball its rockets start (radius 1 about the origin).
# WEATHERVANE: a little iron weathervane on top of the sniper's scope (spindle, N / E / S / W arms) with a gilt
# rooster and arrow that turn together as node "Rooster" (pivot on the spindle; the game turns it into the wind).
# KITE FLYER: a string reel bolted to the LEFT of the M60's receiver, an empty "Line" where the string leaves it;
# kite = the diamond kite with spars and a bowed tail (about the origin, nose up, facing +x).
# CHIP THIEF: a crinkled bag of chips taped to the LEFT of the double shotgun's receiver, its crimped top open a
# little with chips showing; gull = a seagull (about the origin, facing +f) with its wings as nodes "WingL" / "WingR"
# (pivots at the shoulders: the game flaps them).
# CLAM SHELL: a big ribbed clam closed round the front of the double shotgun's barrels: the lower shell fixed, the
# upper one its own node "Lid" (pivot at the hinge at the back: the game opens it to fire and snaps it shut), a pearl
# inside as node "Pearl" (the game grows it while the shot charges).
# ANGLER LIGHT: an anglerfish's lure: a thin bent stalk from the back of the pistol's slide arching out past the muzzle,
# its glowing bulb hanging from the tip as node "Lure" (pivot at the tip: the game sways it and lights it).
# FLUSH: a toilet tank's copper float ball on its brass arm and a chrome flush handle on top of the grenade launcher.
# SPAGHETTI: the sniper's barrel stretched far too long: a thin extension tube sagging on past the muzzle with two
# clamps and a second muzzle at its end.
# LIGHTHOUSE IN A BOTTLE: a corked glass bottle strapped along the LEFT of the rocket tube with a tiny striped
# lighthouse on a rock inside; the glass is node "Glass" (the game makes it see-through), the lamp node "Lamp".
# CARBON COPY: a little office photocopier strapped on top of the double shotgun's stock wrist (lid, paper tray, a sheet
# as node "Sheet" the game slides out, a green scan light "Scan"); paper_copy = the printed copy of you: a flat paper
# cut-out of a person (about 1.75 m, facing +f, standing on the origin).
# TIME CARD: a punch clock on the LEFT of the M60's stock with a time card stuck in its slot; an empty "Face" marks the
# clock face (the game writes the time and pay there).
# LOAN SHARK: a round fishbowl clamped under the pistol's barrel, its glass node "Glass" (see-through in the game),
# a little shark inside as node "Shark" (the game grows it with the debt).
# WANTED POSTER: a parchment poster pinned to the LEFT of the sniper's stock; an empty "Poster" marks its middle (the
# game writes the wanted enemy and the reward there).
# KEY RING: a steel key ring hanging from the bottom of the pistol's grip with nine keys as nodes "Key1".."Key9" (the game
# shows as many as the gun has earned).
# TREASURE MAP: a rolled parchment map tied with twine along the LEFT of the M16's handguard, a red wax seal dangling.
# GOLDEN GOOSE: a small golden goose sitting on top of the grenade launcher's tube, its head and neck as node "Head"
# (pivot at the neck's foot: the game bobs it to honk); golden_egg = the egg it lays (radius ~1 about the origin).
# SPLIT DECISION: two short barrel shrouds under the M16's handguard, red with fins (fire) beside blue with frost spikes
# (ice), and a coin on a post on top of the handguard as node "Coin" (red face up / blue face down; the game spins it).
# MESSAGE IN A BOTTLE: a corked bottle with a rolled note inside lying along the LEFT of the pistol's frame; its glass
# is node "Glass".
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
    "potatoskin": ("matte", (0.55, 0.38, 0.2), 76), "potatoflesh": ("matte", (0.95, 0.88, 0.62), 77), "butter": ("polymer", (1.0, 0.86, 0.3), 78),
    "cupwhite": ("polymer", (0.95, 0.95, 0.97), 82), "cupband": ("polymer", (0.15, 0.45, 0.9), 83),
    "slush": ("matte", (0.3, 0.72, 1.0), 84), "strawred": ("polymer", (0.9, 0.15, 0.2), 85), "snow": ("matte", (0.93, 0.96, 1.0), 86),
    "alu": ("metal", (0.6, 0.66, 0.74), 87),
    "vaneiron": ("paint", (0.12, 0.12, 0.13), 88), "gilt": ("paint", (0.85, 0.66, 0.22), 89), "comb": ("polymer", (0.85, 0.1, 0.08), 90),
    "kitered": ("fabric", (0.88, 0.16, 0.14), 91), "kiteyellow": ("fabric", (0.98, 0.82, 0.2), 92), "spar": ("wood", (0.7, 0.55, 0.35), 93),
    "bagfoil": ("polymer", (0.98, 0.78, 0.12), 94), "bagred": ("polymer", (0.85, 0.12, 0.1), 95), "chip": ("matte", (0.95, 0.78, 0.38), 96),
    "gullwhite": ("matte", (0.95, 0.95, 0.94), 97), "shell": ("matte", (0.92, 0.78, 0.66), 99),
    "shellrib": ("matte", (0.78, 0.55, 0.45), 100), "nacre": ("polymer", (0.95, 0.92, 0.96), 101), "lure": ("matte", (0.75, 0.95, 0.85), 102),
    "copper": ("paint", (0.78, 0.45, 0.25), 103), "beige": ("polymer", (0.86, 0.82, 0.72), 106),
    "paper": ("matte", (0.97, 0.97, 0.95), 107), "ink": ("matte", (0.55, 0.56, 0.6), 108), "scan": ("matte", (0.3, 1.0, 0.4), 109),
    "clockface": ("matte", (0.95, 0.94, 0.88), 110), "parchment": ("matte", (0.86, 0.76, 0.55), 111), "sharkgrey": ("polymer", (0.48, 0.53, 0.6), 112),
    "water": ("polymer", (0.3, 0.6, 0.85), 113), "keysteel": ("paint", (0.66, 0.66, 0.62), 114),
    "keybrass": ("paint", (0.82, 0.66, 0.3), 115), "goose": ("paint", (0.95, 0.75, 0.2), 116), "frost": ("polymer", (0.35, 0.65, 1.0), 117),
    "seal": ("polymer", (0.7, 0.08, 0.08), 118), "lightred": ("polymer", (0.85, 0.15, 0.12), 104), "rock": ("matte", (0.45, 0.42, 0.4), 105), "gullgrey": ("matte", (0.62, 0.65, 0.7), 98),
    "penguinback": ("polymer", (0.07, 0.08, 0.1), 79), "penguinbelly": ("polymer", (0.94, 0.94, 0.92), 80), "beak": ("polymer", (1.0, 0.55, 0.12), 81),
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


def hot_potato(m, M):
    py, pf = 0.066, 0.3  # on top of the tube (radius 0.034 at y 0)
    m.ball(M["chrome"], (0.034, 0.03, 0.05), (0.0, py, pf - 0.008), u=16, v=10)  # the foil
    for dx, dy, df, s in ((0.02, 0.012, -0.03, 0.012), (-0.022, 0.01, 0.0, 0.01), (0.012, 0.024, 0.012, 0.009), (-0.01, 0.022, -0.035, 0.011)):
        m.box(M["chrome"], (s, s * 0.5, s * 1.3), (dx, py + dy, pf + df), tilt=37.0, bevel=0.002)  # crumples
    m.ball(M["potatoskin"], (0.03, 0.026, 0.02), (0.0, py + 0.002, pf + 0.036), u=14, v=8)  # the potato showing at the front
    m.ball(M["potatoflesh"], (0.02, 0.008, 0.014), (0.0, py + 0.024, pf + 0.034), u=12, v=6)  # split open
    m.box(M["butter"], (0.012, 0.006, 0.012), (0.0, py + 0.03, pf + 0.034), tilt=12.0, bevel=0.0015)
    for f in (pf - 0.03, pf + 0.012):  # two straps round potato and tube
        m.cyl(M["strap"], 0.037, f - 0.004, f + 0.004, 0.0, segs=20, bevel=0.0006)
        m.box(M["strap"], (0.07, 0.003, 0.008), (0.0, py + 0.031, f), bevel=0.0005)


def penguin_at(m, M, at, s=1.0):
    """A small penguin standing at `at` (x, y, f: between its feet), facing +f. About 6 cm tall at s = 1."""
    m.shift = at
    m.ball(M["penguinback"], (0.017 * s, 0.026 * s, 0.016 * s), (0.0, 0.026 * s, -0.002 * s), u=16, v=10)  # body
    m.ball(M["penguinbelly"], (0.013 * s, 0.021 * s, 0.009 * s), (0.0, 0.024 * s, 0.008 * s), u=14, v=10)  # white front
    m.ball(M["penguinback"], (0.011 * s, 0.011 * s, 0.011 * s), (0.0, 0.054 * s, 0.002 * s), u=14, v=10)  # head
    m.ball(M["penguinbelly"], (0.007 * s, 0.006 * s, 0.005 * s), (0.0, 0.052 * s, 0.009 * s), u=10, v=6)  # face patch
    m.rod(M["beak"], 0.0028 * s, (0.0, 0.052 * s, 0.011 * s), (0.0, 0.05 * s, 0.019 * s), r2=0.0004 * s, segs=8)
    for side in (-1.0, 1.0):
        m.ball(M["rubber"], 0.0018 * s, (side * 0.0045 * s, 0.057 * s, 0.0105 * s), u=6, v=4)  # eyes
        m.ball(M["penguinback"], (0.003 * s, 0.016 * s, 0.007 * s), (side * 0.017 * s, 0.028 * s, -0.001 * s), u=8, v=6)  # flippers
        m.ball(M["beak"], (0.004 * s, 0.0016 * s, 0.006 * s), (side * 0.006 * s, 0.0016 * s, 0.006 * s), u=8, v=4)  # feet
    m.shift = None


def penguin_slide(m, M):
    """On the back of the pistol's slide (its top at y 0.052, rear sight near f 0.014)."""
    penguin_at(m, M, (0.0, 0.052, 0.045))


def penguin(m, M):
    penguin_at(m, M, (0.0, 0.0, 0.0), s=1.0)


CUP = (-0.062, -0.034, 0.52)  # the slushie cup's foot (x, y, f) beside the M60's barrel jacket (radius 0.033)


def brain_freeze_cup(m, M):
    cx, cy, cf = CUP
    m.lathe(M["cupwhite"], [(0.019, 0.0), (0.0205, 0.002), (0.026, 0.072), (0.0275, 0.075), (0.0262, 0.077), (0.0245, 0.074), (0.0185, 0.004), (0.001, 0.004)], (cx, cy, cf), segs=20)
    m.lathe(M["cupband"], [(0.0236, 0.03), (0.0244, 0.032), (0.0254, 0.05), (0.0246, 0.052)], (cx, cy, cf), segs=20)  # the blue band round it
    m.node("Slush", (cx, cy + 0.004, cf))
    m.lathe(M["slush"], [(0.0183, 0.0), (0.0242, 0.069), (0.0225, 0.078), (0.016, 0.086), (0.007, 0.0895), (0.001, 0.09)], (cx, cy + 0.004, cf), node="Slush", segs=18)
    pts = [(cx + 0.004, cy + 0.04, cf), (cx + 0.006, cy + 0.12, cf - 0.012), (cx + 0.008, cy + 0.14, cf - 0.04)]  # the straw, bent back toward the shooter
    for (a, b) in zip(pts, pts[1:]):
        n = 4
        for k in range(n):
            p0 = tuple(a[i] + (b[i] - a[i]) * k / n for i in range(3))
            p1 = tuple(a[i] + (b[i] - a[i]) * (k + 1) / n for i in range(3))
            m.rod(M["strawred"] if k % 2 == 0 else M["cupwhite"], 0.0032, p0, p1, segs=8)
    for y, tilt in ((cy + 0.016, 3.0), (cy + 0.056, -4.0)):  # two strips of silver tape round cup and barrel jacket
        for side in (-1.0, 1.0):
            m.box(M["tape"], (0.1, 0.012, 0.0012), (-0.02, y, cf + side * 0.0255), tilt=tilt, bevel=0.0004)
        m.box(M["tape"], (0.0012, 0.012, 0.052), (cx - 0.0262, y, cf), tilt=tilt, bevel=0.0004)
        m.box(M["tape"], (0.0012, 0.012, 0.052), (0.0345, y, cf), tilt=tilt, bevel=0.0004)


POLE_X, POLE_Y = -0.082, 0.032  # the ski pole beside the rocket tube (radius 0.07 at y 0.02)


def ski_pole(m, M):
    m.cyl(M["alu"], 0.006, -0.36, 0.6, POLE_Y, x=POLE_X, segs=10, bevel=0.0)  # shaft
    m.cyl(M["rubber"], 0.011, -0.46, -0.34, POLE_Y, x=POLE_X, segs=12, bevel=0.003)  # grip
    m.cyl(M["rubber"], 0.014, -0.47, -0.455, POLE_Y, x=POLE_X, segs=12, bevel=0.002)  # grip cap
    loop = [(-0.45, 0.0), (-0.43, -0.05), (-0.39, -0.07), (-0.36, -0.045), (-0.355, 0.0)]  # the wrist loop hanging down
    for (f0, d0), (f1, d1) in zip(loop, loop[1:]):
        m.rod(M["strap"], 0.0025, (POLE_X - 0.004, POLE_Y + d0, f0), (POLE_X - 0.004, POLE_Y + d1, f1), segs=6)
    m.lathe(M["rubber"], [(0.0065, -0.0015), (0.032, -0.0015), (0.033, 0.0), (0.032, 0.0015), (0.0065, 0.0015)], (POLE_X, POLE_Y, 0.5), segs=18, axis="f")  # basket
    m.cyl(M["alu"], 0.006, 0.6, 0.65, POLE_Y, x=POLE_X, segs=10, bevel=0.0, r2=0.0012)  # steel tip
    for f in (-0.25, 0.32):  # two straps round pole and tube
        m.cyl(M["strap"], 0.073, f - 0.005, f + 0.005, 0.02, segs=24, bevel=0.0006)
        m.box(M["strap"], (0.016, 0.012, 0.01), (POLE_X + 0.004, POLE_Y, f), bevel=0.0008)


def snowball(m, M):
    m.ball(M["snow"], 1.0, (0.0, 0.0, 0.0), u=16, v=10)
    for x, y, f, r in ((0.6, 0.5, 0.3, 0.42), (-0.55, 0.3, -0.5, 0.45), (0.1, -0.6, 0.6, 0.4), (-0.3, 0.7, 0.4, 0.35), (0.5, -0.3, -0.6, 0.38)):
        m.ball(M["snow"], r, (x, y, f), u=10, v=6)  # lumps of packed snow


VANE = (0.0, 0.135, 0.2)  # the spindle's foot on top of the sniper's scope (radius 0.03 at y 0.105)


def weathervane(m, M):
    x, y, f = VANE
    m.box(M["vaneiron"], (0.02, 0.006, 0.026), (x, y + 0.001, f), bevel=0.001)  # saddle clamp on the scope
    m.rod(M["vaneiron"], 0.0022, (x, y, f), (x, y + 0.11, f), segs=8)  # spindle
    ay = y + 0.055
    for (dx, df) in ((1, 0), (-1, 0), (0, 1), (0, -1)):  # the four arms with little ball ends
        m.rod(M["vaneiron"], 0.0014, (x, ay, f), (x + dx * 0.03, ay, f + df * 0.03), segs=6)
        m.ball(M["gilt"], 0.003, (x + dx * 0.032, ay, f + df * 0.032), u=8, v=6)
    m.ball(M["gilt"], 0.004, (x, y + 0.112, f), u=8, v=6)
    m.node("Rooster", (x, y + 0.11, f))
    ry = y + 0.13  # the rooster stands on the arrow, facing +f (the arrow head)
    m.rod(M["vaneiron"], 0.0015, (x, y + 0.112, f - 0.04), (x, y + 0.112, f + 0.04), segs=6, node="Rooster")  # arrow shaft
    m.prof(M["gilt"], 0.002, [(f + 0.04, y + 0.104), (f + 0.052, y + 0.112), (f + 0.04, y + 0.12)], x=x, bevel=0.0, node="Rooster")  # head
    m.prof(M["gilt"], 0.002, [(f - 0.048, y + 0.1), (f - 0.032, y + 0.106), (f - 0.032, y + 0.118), (f - 0.048, y + 0.124)], x=x, bevel=0.0, node="Rooster")  # tail fin
    m.rod(M["vaneiron"], 0.0013, (x, y + 0.112, f), (x, ry - 0.008, f), segs=6, node="Rooster")
    m.ball(M["gilt"], (0.006, 0.01, 0.014), (x, ry, f), node="Rooster", u=12, v=8)  # body
    m.ball(M["gilt"], (0.005, 0.006, 0.006), (x, ry + 0.012, f + 0.011), node="Rooster", u=10, v=6)  # head
    m.prof(M["comb"], 0.003, [(f + 0.008, ry + 0.016), (f + 0.011, ry + 0.022), (f + 0.014, ry + 0.017), (f + 0.017, ry + 0.021), (f + 0.017, ry + 0.015)], x=x, bevel=0.0, node="Rooster")
    m.prof(M["comb"], 0.003, [(f + 0.012, ry + 0.007), (f + 0.016, ry + 0.003), (f + 0.014, ry + 0.009)], x=x, bevel=0.0, node="Rooster")  # wattle
    m.rod(M["butter"], 0.002, (x, ry + 0.012, f + 0.016), (x, ry + 0.011, f + 0.022), r2=0.0004, segs=6, node="Rooster")  # beak
    m.prof(M["gilt"], 0.0025, [(f - 0.01, ry + 0.002), (f - 0.026, ry + 0.022), (f - 0.03, ry + 0.012), (f - 0.022, ry - 0.004)], x=x, bevel=0.0, node="Rooster")  # tail feathers
    for side in (-1.0, 1.0):
        m.rod(M["vaneiron"], 0.001, (x + side * 0.002, ry - 0.008, f), (x + side * 0.003, ry - 0.016, f + 0.002), segs=4, node="Rooster")  # legs


REEL = (-0.052, 0.0, -0.13)  # the reel's middle (x, y, f) beside the M60's receiver (half width 0.03)


def kite_reel(m, M):
    x, y, f = REEL
    m.box(M["vaneiron"], (0.012, 0.03, 0.03), (-0.036, y, f), bevel=0.002)  # bracket against the receiver
    for x0 in (x - 0.014, x + 0.01):  # two flanges round the wound string
        m.cylx(M["kitered"], 0.034, x0, x0 + 0.004, f, y, segs=20, bevel=0.001)
    m.cylx(M["cable"], 0.024, x - 0.01, x + 0.01, f, y, segs=20, bevel=0.0)  # the string wound on
    m.cylx(M["vaneiron"], 0.006, x - 0.022, x + 0.016, f, y, segs=10, bevel=0.0)  # axle
    m.box(M["vaneiron"], (0.004, 0.034, 0.008), (x - 0.022, y - 0.014, f), bevel=0.001)  # crank arm
    m.cylx(M["spar"], 0.005, x - 0.036, x - 0.022, f, y - 0.03, segs=8, bevel=0.001)  # crank handle
    m.empty("Line", x, y + 0.024, f)


def kite(m, M):
    m.prof(M["kitered"], 0.006, [(0.0, 0.5), (0.0, -0.5), (-0.35, 0.12)], bevel=0.0)  # two halves of the sail (in the f-y plane)
    m.prof(M["kiteyellow"], 0.006, [(0.0, 0.5), (0.35, 0.12), (0.0, -0.5)], bevel=0.0)
    m.rod(M["spar"], 0.008, (0.0, 0.5, 0.0), (0.0, -0.5, 0.0), segs=6)
    m.rod(M["spar"], 0.008, (0.0, 0.12, -0.35), (0.0, 0.12, 0.35), segs=6)
    for k in range(5):  # the tail with bows
        y0 = -0.5 - k * 0.16
        m.rod(M["cable"], 0.003, (0.0, y0, 0.0), (0.0, y0 - 0.16, 0.0), segs=4)
        bow = M["kitered"] if k % 2 == 0 else M["kiteyellow"]
        m.prof(bow, 0.005, [(-0.05, y0 - 0.1), (0.0, y0 - 0.08), (-0.05, y0 - 0.06)], bevel=0.0)
        m.prof(bow, 0.005, [(0.05, y0 - 0.1), (0.05, y0 - 0.06), (0.0, y0 - 0.08)], bevel=0.0)


BAG = (-0.048, -0.004, 0.0)  # the bag's middle beside the shotgun's receiver (half width 0.03)


def chip_bag(m, M):
    x, y, f = BAG
    m.ball(M["bagfoil"], (0.016, 0.042, 0.045), (x, y, f), u=14, v=10)  # puffed bag
    m.box(M["bagfoil"], (0.012, 0.012, 0.09), (x, y + 0.042, f), bevel=0.002)  # crimped top seam
    for k in range(9):
        m.box(M["bagfoil"], (0.013, 0.003, 0.004), (x, y + 0.049, f - 0.04 + k * 0.01), bevel=0.0)  # crimp teeth
    m.box(M["bagfoil"], (0.012, 0.01, 0.09), (x, y - 0.042, f), bevel=0.002)  # bottom seam
    m.ball(M["bagred"], (0.0162, 0.016, 0.03), (x - 0.0005, y - 0.004, f), u=14, v=8)  # the red band
    for df, dy, tilt in ((-0.015, 0.058, 20.0), (0.01, 0.06, -15.0), (0.022, 0.055, 35.0)):  # chips peeking out
        m.box(M["chip"], (0.004, 0.024, 0.02), (x + 0.002, y + dy, f + df), tilt=tilt, bevel=0.002)
    for df in (-0.028, 0.028):  # two strips of tape round bag and receiver
        m.box(M["tape"], (0.0012, 0.09, 0.012), (x - 0.0165, y, f + df), bevel=0.0004)
        m.box(M["tape"], (0.07, 0.0012, 0.012), (-0.015, y + 0.046, f + df), bevel=0.0004)
        m.box(M["tape"], (0.07, 0.0012, 0.012), (-0.015, y - 0.046, f + df), bevel=0.0004)


def gull(m, M):
    m.ball(M["gullwhite"], (0.06, 0.06, 0.16), (0.0, 0.0, 0.0), u=14, v=10)  # body
    m.ball(M["gullwhite"], (0.045, 0.045, 0.05), (0.0, 0.04, 0.15), u=12, v=8)  # head
    m.rod(M["butter"], 0.012, (0.0, 0.035, 0.19), (0.0, 0.03, 0.25), r2=0.003, segs=8)  # beak
    m.ball(M["bagred"], 0.004, (0.0, 0.026, 0.228), u=6, v=4)  # the red spot on the beak
    for side in (-1.0, 1.0):
        m.ball(M["rubber"], 0.006, (side * 0.03, 0.055, 0.17), u=6, v=4)  # eyes
    m.prof(M["gullgrey"], 0.012, [(-0.12, 0.0), (-0.24, 0.03), (-0.24, -0.03)], bevel=0.0)  # tail
    for side, name in ((-1.0, "WingL"), (1.0, "WingR")):
        m.node(name, (side * 0.05, 0.02, 0.02))
        m.box(M["gullgrey"], (0.26, 0.01, 0.12), (side * 0.18, 0.02, 0.02), node=name, bevel=0.003)
        m.box(M["rubber"], (0.08, 0.011, 0.08), (side * 0.32, 0.02, 0.0), node=name, bevel=0.003)  # black wing tips


def clam_shell(m, M):
    hinge_f = 0.4
    m.ball(M["shell"], (0.052, 0.022, 0.17), (0.0, -0.006, 0.56), u=20, v=10)  # lower shell
    m.node("Lid", (0.0, 0.02, hinge_f))
    m.ball(M["shell"], (0.054, 0.026, 0.172), (0.0, 0.03, 0.56), node="Lid", u=20, v=10)  # upper shell
    for k in range(-3, 4):  # ribs fanning from the hinge over the lid
        a = k * 0.14
        m.rod(M["shellrib"], 0.0035, (math.sin(a) * 0.01, 0.05, hinge_f + 0.01), (math.sin(a) * 0.05, 0.05 - abs(math.sin(a)) * 0.012, 0.72), node="Lid", segs=6)
        m.rod(M["shellrib"], 0.003, (math.sin(a) * 0.01, -0.024, hinge_f + 0.01), (math.sin(a) * 0.05, -0.022, 0.72), segs=6)
    m.box(M["shellrib"], (0.03, 0.012, 0.02), (0.0, 0.016, hinge_f), bevel=0.003)  # hinge
    m.node("Pearl", (0.0, 0.03, 0.66))
    m.ball(M["nacre"], 0.012, (0.0, 0.03, 0.66), node="Pearl", u=12, v=8)


def angler_lure(m, M):
    pts = [(0.0, 0.058, 0.03), (0.0, 0.1, 0.07), (0.0, 0.135, 0.15), (0.0, 0.14, 0.23), (0.0, 0.125, 0.3)]  # the stalk, arching forward
    for a, b in zip(pts, pts[1:]):
        m.rod(M["rubber"], 0.0025, a, b, r2=0.002, segs=6)
    m.box(M["rubber"], (0.012, 0.008, 0.02), (0.0, 0.055, 0.03), bevel=0.002)  # its clamp on the slide
    tip = pts[-1]
    m.node("Lure", tip)
    m.rod(M["cable"], 0.0008, tip, (0.0, tip[1] - 0.03, tip[2]), segs=4, node="Lure")
    m.ball(M["lure"], 0.009, (0.0, tip[1] - 0.039, tip[2]), node="Lure", u=12, v=8)  # the glowing bulb
    m.ball(M["lure"], (0.004, 0.006, 0.004), (0.0, tip[1] - 0.05, tip[2]), node="Lure", u=8, v=6)


def float_ball(m, M):
    m.box(M["chrome"], (0.018, 0.016, 0.03), (0.0, 0.045, 0.16), bevel=0.003)  # valve block on the tube
    m.rod(M["brass"], 0.003, (0.0, 0.05, 0.17), (0.0, 0.07, 0.34), segs=8)  # float arm
    m.ball(M["copper"], 0.03, (0.0, 0.075, 0.37), u=16, v=10)  # the float
    m.lathe(M["copper"], [(0.006, -0.002), (0.006, 0.004)], (0.0, 0.105, 0.37), segs=10)  # its seam knob
    m.box(M["chrome"], (0.01, 0.01, 0.012), (-0.033, 0.03, 0.12), bevel=0.002)  # the flush handle on the side
    m.box(M["chrome"], (0.006, 0.006, 0.045), (-0.04, 0.03, 0.145), bevel=0.002)


def long_barrel(m, M):
    y = 0.01
    pts = [(0.0, y, 1.04), (0.0, y - 0.004, 1.35), (0.0, y - 0.016, 1.65), (0.0, y - 0.03, 1.9)]  # sagging
    for a, b in zip(pts, pts[1:]):
        m.rod(M["chrome"], 0.012, a, b, segs=12)
    for f, yy in ((1.3, y - 0.003), (1.6, y - 0.014)):  # clamps
        m.cyl(M["vaneiron"], 0.016, f - 0.01, f + 0.01, yy, segs=12, bevel=0.002)
    m.cyl(M["vaneiron"], 0.018, 1.88, 1.94, y - 0.03, segs=12, bevel=0.003)  # the far muzzle
    m.cyl(M["rubber"], 0.009, 1.94, 1.945, y - 0.03, segs=12, bevel=0.0)


BOTTLE = (-0.112, 0.03, 0.0)  # the lying bottle's axis (x, y) and its back end f, beside the rocket tube (radius 0.07)


def bottle_lighthouse(m, M):
    x, y, f = BOTTLE
    m.node("Glass", (x, y, f + 0.15))
    m.lathe(M["jarglass"], [(0.03, 0.0), (0.036, 0.006), (0.036, 0.24), (0.026, 0.27), (0.012, 0.29), (0.012, 0.33)], (x, y, f), node="Glass", segs=20, axis="f")
    m.lathe(M["cork"], [(0.0115, 0.32), (0.0125, 0.345), (0.011, 0.35)], (x, y, f), segs=12, axis="f")
    m.ball(M["rock"], (0.026, 0.012, 0.05), (x, y - 0.026, f + 0.13), u=12, v=6)  # the rock inside
    by = y - 0.018
    for k in range(5):  # striped tower, red and white bands
        r0 = 0.0085 - k * 0.0006
        m.lathe(M["lightred"] if k % 2 == 0 else M["cupwhite"], [(r0, by + k * 0.008), (r0 - 0.0006, by + (k + 1) * 0.008)], (x, 0.0, f + 0.13), segs=12)
    m.node("Lamp", (x, by + 0.046, f + 0.13))
    m.lathe(M["flame"], [(0.0055, by + 0.04), (0.0055, by + 0.05)], (x, 0.0, f + 0.13), node="Lamp", segs=10)
    m.lathe(M["vaneiron"], [(0.0068, by + 0.05), (0.0068, by + 0.052), (0.001, by + 0.058)], (x, 0.0, f + 0.13), segs=10)  # cap
    for ff in (f + 0.05, f + 0.21):  # two straps round bottle and tube
        m.cyl(M["strap"], 0.073, ff - 0.005, ff + 0.005, 0.02, segs=24, bevel=0.0006)
        m.box(M["strap"], (0.03, 0.01, 0.01), (x + 0.02, y + 0.034, ff), bevel=0.0008)


def photocopier(m, M):
    x, y, f = -0.045, 0.012, -0.19  # middle of the copier on the stock wrist's left
    m.box(M["beige"], (0.04, 0.05, 0.13), (x, y, f), bevel=0.004)  # body
    m.box(M["ink"], (0.042, 0.008, 0.132), (x, y + 0.028, f), bevel=0.002)  # lid
    m.box(M["ink"], (0.03, 0.004, 0.05), (x, y - 0.012, f + 0.075), bevel=0.001)  # paper tray out the front
    m.node("Sheet", (x, y - 0.008, f + 0.06))
    m.box(M["paper"], (0.026, 0.002, 0.045), (x, y - 0.008, f + 0.075), node="Sheet", bevel=0.0)
    m.node("Scan", (x - 0.021, y + 0.01, f))
    m.box(M["scan"], (0.002, 0.006, 0.1), (x - 0.021, y + 0.01, f), node="Scan", bevel=0.0)  # the green light down its side
    for b in range(3):  # little buttons
        m.box(M["ink"], (0.006, 0.004, 0.008), (x - 0.008 + b * 0.008, y + 0.033, f - 0.05), bevel=0.001)
    for ff in (f - 0.04, f + 0.04):  # two straps round copier and stock
        m.box(M["strap"], (0.075, 0.004, 0.01), (-0.03, y + 0.034, ff), bevel=0.0008)
        m.box(M["strap"], (0.075, 0.004, 0.01), (-0.03, -0.045, ff), bevel=0.0008)


def paper_copy(m, M):
    body = [(0.0, 0.75), (0.05, 0.0), (0.18, 0.0), (0.15, 0.85), (0.16, 1.0), (0.3, 0.95), (0.34, 1.0), (0.24, 1.42), (0.1, 1.47), (0.06, 1.5),
            (-0.06, 1.5), (-0.1, 1.47), (-0.24, 1.42), (-0.34, 1.0), (-0.3, 0.95), (-0.16, 1.0), (-0.15, 0.85), (-0.18, 0.0), (-0.05, 0.0)]
    head = [(0.11 * math.cos(2 * math.pi * k / 10), 1.63 + 0.12 * math.sin(2 * math.pi * k / 10)) for k in range(10)]
    m.prof(M["paper"], 0.004, body, x=0.0, bevel=0.0, across="f")
    m.prof(M["paper"], 0.004, head, x=0.0, bevel=0.0, across="f")
    ink = [(px * 0.86, 0.06 + py * 0.92) for px, py in body]
    m.prof(M["ink"], 0.001, ink, x=0.0025, bevel=0.0, across="f")  # the grey print on its face
    m.prof(M["ink"], 0.001, [(px * 0.85, 1.63 + (py - 1.63) * 0.85) for px, py in head], x=0.0025, bevel=0.0, across="f")


def punch_clock(m, M):
    x, y, f = -0.05, -0.01, -0.38
    m.box(M["beige"], (0.03, 0.08, 0.07), (x, y, f), bevel=0.004)  # the clock box
    m.cylx(M["clockface"], 0.026, x - 0.017, x - 0.015, f, y + 0.012, segs=24, bevel=0.0)  # face
    m.cylx(M["vaneiron"], 0.028, x - 0.0155, x - 0.0145, f, y + 0.012, segs=24, bevel=0.0)  # rim
    m.empty("Face", x - 0.018, y + 0.012, f)
    m.box(M["ink"], (0.026, 0.006, 0.04), (x, y + 0.043, f), bevel=0.001)  # card slot
    m.box(M["parchment"], (0.002, 0.04, 0.03), (x, y + 0.06, f), bevel=0.0)  # the time card stuck in it
    for k in range(4):
        m.box(M["ink"], (0.0022, 0.002, 0.024), (x, y + 0.05 + k * 0.007, f), bevel=0.0)  # its printed rows
    for ff in (f - 0.025, f + 0.025):
        m.box(M["strap"], (0.08, 0.004, 0.008), (-0.03, y + 0.042, ff), bevel=0.0008)
        m.box(M["strap"], (0.08, 0.004, 0.008), (-0.03, y - 0.042, ff), bevel=0.0008)


BOWL = (0.0, -0.1, 0.235)  # the fishbowl's middle under the pistol's barrel (frame bottom y -0.048)


def fishbowl(m, M):
    x, y, f = BOWL
    m.box(M["vaneiron"], (0.014, 0.03, 0.012), (x, -0.058, f), bevel=0.002)  # clamp on the frame's front
    m.node("Glass", (x, y, f))
    m.lathe(M["jarglass"], [(0.012, -0.036), (0.03, -0.028), (0.038, -0.008), (0.036, 0.016), (0.024, 0.032), (0.022, 0.036)], (x, y, f), node="Glass", segs=20)
    m.lathe(M["water"], [(0.01, -0.035), (0.028, -0.029)], (x, y, f), segs=16)  # water: only the bottom and the line show
    m.lathe(M["water"], [(0.0345, 0.011), (0.0348, 0.013)], (x, y, f), segs=20)
    m.node("Shark", (x, y, f))
    m.ball(M["sharkgrey"], (0.006, 0.006, 0.016), (x, y, f), node="Shark", u=12, v=8)
    m.prof(M["sharkgrey"], 0.002, [(f - 0.004, y + 0.004), (f + 0.004, y + 0.004), (f - 0.004, y + 0.013)], x=x, bevel=0.0, node="Shark")  # fin
    m.prof(M["sharkgrey"], 0.002, [(f - 0.014, y), (f - 0.022, y + 0.008), (f - 0.02, y), (f - 0.022, y - 0.006)], x=x, bevel=0.0, node="Shark")  # tail
    m.ball(M["paper"], (0.0045, 0.002, 0.008), (x, y - 0.004, f + 0.004), node="Shark", u=8, v=4)  # pale belly


def wanted_poster(m, M):
    x, y, f = -0.026, -0.02, -0.35
    m.box(M["parchment"], (0.002, 0.1, 0.13), (x, y, f), bevel=0.0)
    m.box(M["ink"], (0.0022, 0.012, 0.11), (x, y + 0.037, f), bevel=0.0)  # the header band
    m.box(M["ink"], (0.0022, 0.004, 0.08), (x, y - 0.035, f), bevel=0.0)  # the reward line
    for dy, df in ((0.045, 0.058), (0.045, -0.058), (-0.045, 0.058), (-0.045, -0.058)):
        m.ball(M["lightred"], 0.0035, (x - 0.002, y + dy, f + df), u=8, v=6)  # pins
    m.empty("Poster", x - 0.0015, y, f)


def key_ring(m, M):
    cx, cy, cf = 0.0, -0.19, -0.02  # the ring's middle, hanging under the grip's base (y -0.166)
    m.box(M["keysteel"], (0.006, 0.012, 0.006), (cx, -0.17, cf), bevel=0.001)  # lanyard loop
    for k in range(16):  # the ring (a loop of short rods in the y-f plane)
        a0 = 2 * math.pi * k / 16
        a1 = 2 * math.pi * (k + 1) / 16
        m.rod(M["keysteel"], 0.0015, (cx, cy + 0.012 * math.cos(a0), cf + 0.012 * math.sin(a0)), (cx, cy + 0.012 * math.cos(a1), cf + 0.012 * math.sin(a1)), segs=5)
    for k in range(9):  # nine keys fanned round the bottom of the ring
        a = math.radians(-70 + k * 17.5)
        top = (cx + (k % 3 - 1) * 0.002, cy - 0.012 * math.cos(a), cf + 0.012 * math.sin(a))
        down = (math.sin(a) * 0.5, -math.cos(a))
        name = "Key%d" % (k + 1)
        m.node(name, top)
        mat = M["keybrass"] if k % 2 == 0 else M["keysteel"]
        bow = (top[0], top[1] + down[1] * 0.008, top[2] + down[0] * 0.008)
        m.ball(mat, (0.002, 0.007, 0.007), bow, node=name, u=10, v=6)  # the bow
        tip = (top[0], top[1] + down[1] * 0.04, top[2] + down[0] * 0.04)
        m.rod(mat, 0.0016, bow, tip, segs=5, node=name)  # the blade
        for t in (0.6, 0.8):
            tooth = (top[0], top[1] + down[1] * 0.04 * t, top[2] + down[0] * 0.04 * t)
            m.box(mat, (0.0015, 0.004, 0.004), (tooth[0], tooth[1], tooth[2] + 0.003), bevel=0.0, node=name)


def treasure_map(m, M):
    x, y, f0, f1 = -0.054, 0.0, 0.29, 0.46
    m.cyl(M["parchment"], 0.016, f0, f1, y, x=x, segs=16, bevel=0.002)
    m.cyl(M["parchment"], 0.0175, f1 - 0.004, f1, y, x=x, segs=16, bevel=0.0)  # the rolled edge
    for f in (f0 + 0.035, f1 - 0.035):  # twine round map and handguard
        m.cyl(M["strap"], 0.0175, f - 0.003, f + 0.003, y, x=x, segs=16, bevel=0.0)
        m.box(M["strap"], (0.045, 0.003, 0.006), (-0.032, y + 0.035, f), bevel=0.0)
        m.box(M["strap"], (0.045, 0.003, 0.006), (-0.032, y - 0.03, f), bevel=0.0)
    m.rod(M["strap"], 0.0012, (x, y - 0.016, f1 - 0.035), (x, y - 0.04, f1 - 0.03), segs=4)
    m.ball(M["seal"], (0.003, 0.009, 0.009), (x, y - 0.047, f1 - 0.03), u=12, v=6)  # wax seal


def goose_at(m, M, at, s=1.0, node_head="Head"):
    x, y, f = at
    m.ball(M["goose"], (0.022 * s, 0.018 * s, 0.035 * s), (x, y + 0.016 * s, f), u=14, v=10)  # body
    for side in (-1.0, 1.0):
        m.ball(M["goose"], (0.006 * s, 0.012 * s, 0.026 * s), (x + side * 0.019 * s, y + 0.02 * s, f - 0.004 * s), u=10, v=6)  # folded wings
    m.prof(M["goose"], 0.004 * s, [(f - 0.03 * s, y + 0.02 * s), (f - 0.05 * s, y + 0.032 * s), (f - 0.034 * s, y + 0.012 * s)], x=x, bevel=0.0)  # tail
    m.node(node_head, (x, y + 0.026 * s, f + 0.026 * s))
    m.rod(M["goose"], 0.006 * s, (x, y + 0.026 * s, f + 0.026 * s), (x, y + 0.05 * s, f + 0.034 * s), segs=8, node=node_head)  # neck
    m.ball(M["goose"], (0.008 * s, 0.008 * s, 0.011 * s), (x, y + 0.056 * s, f + 0.038 * s), node=node_head, u=10, v=8)  # head
    m.rod(M["butter"], 0.003 * s, (x, y + 0.055 * s, f + 0.047 * s), (x, y + 0.053 * s, f + 0.058 * s), r2=0.0012 * s, segs=6, node=node_head)  # beak
    for side in (-1.0, 1.0):
        m.ball(M["rubber"], 0.0015 * s, (x + side * 0.0055 * s, y + 0.059 * s, f + 0.043 * s), u=6, v=4, node=node_head)


def golden_goose(m, M):
    goose_at(m, M, (0.0, 0.034, 0.3), s=1.2)
    m.box(M["strap"], (0.07, 0.003, 0.008), (0.0, 0.034, 0.3), bevel=0.0005)  # a little saddle strap
    m.cyl(M["strap"], 0.037, 0.296, 0.304, 0.0, segs=20, bevel=0.0005)


def golden_egg(m, M):
    m.lathe(M["goose"], [(0.001, -1.0), (0.45, -0.9), (0.7, -0.5), (0.75, 0.0), (0.65, 0.5), (0.4, 0.85), (0.001, 1.0)], (0.0, 0.0, 0.0), segs=16)


def split_barrels(m, M):
    y = -0.034
    m.cyl(M["lightred"], 0.012, 0.24, 0.5, y, x=-0.016, segs=14, bevel=0.002)
    m.cyl(M["frost"], 0.012, 0.24, 0.5, y, x=0.016, segs=14, bevel=0.002)
    for k in range(4):  # fire fins on the red, frost spikes on the blue
        f = 0.28 + k * 0.06
        m.prof(M["flame"], 0.003, [(f, y - 0.008), (f + 0.03, y - 0.008), (f + 0.004, y - 0.026)], x=-0.03, bevel=0.0)
        m.rod(M["cable"], 0.003, (0.026, y - 0.004, f), (0.036, y - 0.016, f + 0.006), r2=0.0005, segs=5)
    m.cyl(M["vaneiron"], 0.0145, 0.235, 0.25, y, x=-0.016, segs=14, bevel=0.0)
    m.cyl(M["vaneiron"], 0.0145, 0.235, 0.25, y, x=0.016, segs=14, bevel=0.0)
    m.box(M["vaneiron"], (0.06, 0.01, 0.02), (0.0, y + 0.012, 0.3), bevel=0.002)  # bracket to the handguard
    m.rod(M["vaneiron"], 0.002, (0.0, 0.054, 0.15), (0.0, 0.07, 0.15), segs=6)  # the coin's post
    m.node("Coin", (0.0, 0.084, 0.15))
    m.lathe(M["lightred"], [(0.001, 0.0), (0.014, 0.0), (0.014, 0.0015)], (0.0, 0.084, 0.15), node="Coin", segs=20, axis="f")
    m.lathe(M["frost"], [(0.014, -0.0015), (0.001, -0.0015)], (0.0, 0.084, 0.15), node="Coin", segs=20, axis="f")
    m.lathe(M["gilt"], [(0.0145, -0.0016), (0.0145, 0.0016)], (0.0, 0.084, 0.15), node="Coin", segs=20, axis="f")  # gold rim


def message_bottle(m, M):
    x, y, f = -0.034, -0.022, 0.05
    m.node("Glass", (x, y, f + 0.1))
    m.lathe(M["jarglass"], [(0.01, 0.0), (0.013, 0.004), (0.013, 0.12), (0.008, 0.14), (0.005, 0.15), (0.005, 0.17)], (x, y, f), node="Glass", segs=16, axis="f")
    m.lathe(M["cork"], [(0.0048, 0.165), (0.0052, 0.18), (0.0045, 0.184)], (x, y, f), segs=10, axis="f")
    m.cyl(M["parchment"], 0.006, f + 0.02, f + 0.1, y - 0.004, x=x, segs=10, bevel=0.001)  # the rolled note inside
    m.cyl(M["strap"], 0.0062, f + 0.055, f + 0.06, y - 0.004, x=x, segs=10, bevel=0.0)  # its ribbon
    for ff in (f + 0.03, f + 0.1):  # tape round bottle and frame
        m.box(M["tape"], (0.05, 0.0012, 0.012), (-0.012, y + 0.014, ff), bevel=0.0004)
        m.box(M["tape"], (0.05, 0.0012, 0.012), (-0.012, y - 0.014, ff), bevel=0.0004)


MODELS = {"key_ring": key_ring, "treasure_map": treasure_map, "golden_goose": golden_goose, "golden_egg": golden_egg, "split_barrels": split_barrels, "message_bottle": message_bottle, "photocopier": photocopier, "paper_copy": paper_copy, "punch_clock": punch_clock, "fishbowl": fishbowl, "wanted_poster": wanted_poster, "clam_shell": clam_shell, "angler_lure": angler_lure, "float_ball": float_ball, "long_barrel": long_barrel, "bottle_lighthouse": bottle_lighthouse, "weathervane": weathervane, "kite_reel": kite_reel, "kite": kite, "chip_bag": chip_bag, "gull": gull, "brain_freeze_cup": brain_freeze_cup, "ski_pole": ski_pole, "snowball": snowball, "mixtape_mp3": mixtape_mp3, "penguin_slide": penguin_slide, "penguin": penguin, "hot_potato": hot_potato, "sauce_bottle": sauce_bottle, "grill_plate": grill_plate, "grilled_kebab": grilled_kebab, "keepers_lantern": keepers_lantern, "keepers_lantern_free": keepers_lantern_free, "swamp_jar": swamp_jar, "croak_scope": croak_scope, "croak_frog": croak_frog, "fish_story_rod": fish_story_rod, "beach_ball_muzzle": beach_ball_muzzle,
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
