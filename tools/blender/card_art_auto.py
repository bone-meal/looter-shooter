# Purpose: developer-time scene recipes for every card of "You got me Lobster?" that has no hand-made entry in
# data/tcg/art.json: which of our models stands in it (or which CC0 character and clip), its stage, light, pose,
# effects and camera, derived from the card's faction, type, tribe, name and effects. Hand-made entries in art.json
# always win; this only fills the rest. Used by tools/blender/card_art.py.
# Dependencies: data/tcg/cards.json, data/tcg/leaders.json (read by the caller).
import hashlib

STAGE = {"tide": "beach", "waste": "waste", "crypt": "crypt", "aurelind": "field", "club": "club", "neutral": "arena"}
TIMES = {"tide": ["sunset", "dusk", "storm", "day"], "waste": ["dust", "sunset", "fire"], "crypt": ["night", "dusk", "cave"],
         "aurelind": ["sunset", "day", "storm", "dusk"], "club": ["club"], "neutral": ["day", "sunset", "dusk"]}
EARS = (0.95, 0.92, 0.95)
STAFF_TINTS = {"violet": (0.6, 0.35, 1.0), "mint": (0.4, 1.0, 0.8), "goldie": (1.0, 0.8, 0.3), "lottie": (1.0, 0.75, 0.35),
               "cherry": (1.0, 0.45, 0.65), "bartender_juniper": (0.35, 0.85, 1.0), "cocktail_waitress": (1.0, 0.5, 0.75),
               "chip_runner": (1.0, 0.55, 0.55), "dice_shaker": (0.8, 0.5, 1.0), "pachinko_queen": (1.0, 0.4, 0.8)}

# card id -> subject: ("m", model path, scale, tint) for our models, ("h", body, clip, extra dict) for CC0 characters
M = lambda path, scale=1.0, tint=None: ("m", path, scale, tint)
Hm = lambda body, clip, **x: ("h", body, clip, x)
SUBJECTS = {
    # tide
    "drowned_spawn": M("fantasy/creatures/drowned_sailor", 0.7), "drowned_deckhand": M("fantasy/creatures/drowned_sailor"),
    "brine_runner": M("fantasy/creatures/drowned_sailor", 1.0, (0.8, 1.1, 1.0)), "drowned_sailor": M("fantasy/creatures/drowned_sailor"),
    "tide_caller": M("fantasy/creatures/drowned_sailor", 1.05, (0.7, 1.0, 1.2)), "undertow_lurker": M("fantasy/creatures/drowned_sailor", 1.0, (0.6, 0.8, 0.9)),
    "drowned_boatswain": M("fantasy/creatures/drowned_sailor", 1.15, (1.0, 0.9, 0.8)), "drowned_captain": M("fantasy/creatures/tidewarden", 0.9),
    "kraken_bitten_bosun": M("fantasy/creatures/drowned_sailor", 1.3, (0.8, 0.7, 0.9)), "barnacled_brute": M("fantasy/creatures/tidewarden", 1.1, (0.9, 1.0, 0.8)),
    "bell_keeper": M("fantasy/creatures/tidewarden", 1.3, (1.1, 1.0, 0.8)), "undertow_leviathan": M("fantasy/creatures/tidewarden", 2.6, (0.5, 0.8, 1.0)),
    "harbor_gull": M("creatures/crow", 0.12, (2.5, 2.5, 2.5)), "gull_chick": M("creatures/crow", 0.07, (2.5, 2.5, 2.3)),
    "gull_matriarch": M("creatures/crow", 0.16, (2.4, 2.4, 2.4)), "stormgull": M("creatures/crow", 0.16, (1.6, 1.8, 2.4)),
    "reef_crab": M("fantasy/creatures/reef_crab", 1.3), "sea_crawler": M("fantasy/creatures/reef_crab", 0.9, (1.2, 0.9, 0.7)),
    "hermit_crab": M("fantasy/creatures/reef_crab", 0.9, (1.1, 1.1, 0.6)), "bulwark_crab": M("fantasy/creatures/reef_crab", 1.5, (0.8, 0.9, 1.2)),
    "old_shellback": M("fantasy/creatures/reef_crab", 2.6, (0.7, 0.8, 0.7)), "crawler_mother": M("fantasy/creatures/reef_crab", 2.0, (1.2, 0.7, 0.6)),
    "tide_brute": M("fantasy/creatures/tidewarden", 1.2), "crab_queen": M("fantasy/creatures/reef_crab", 2.4, (1.6, 1.2, 0.5)),
    # waste
    "raider_scrapper": M("creatures/raider"), "wasteland_feral": M("creatures/feral"), "scav_gunner": M("creatures/scav_gunner"),
    "raider_marksman": M("creatures/marksman"), "raider_brute": M("creatures/brute"), "sandbag_guard": M("creatures/brute", 1.0, (0.9, 0.85, 0.7)),
    "scav_lookout": M("creatures/marksman", 1.0, (0.9, 1.0, 0.9)), "raider_bomber": M("creatures/raider", 1.0, (1.1, 0.9, 0.8)),
    "raider_warchief": M("creatures/boss_warlord"), "scrap_mortar": M("creatures/scav_gunner", 1.0, (1.0, 0.9, 0.8)),
    "blood_drinker": M("creatures/feral", 1.0, (1.4, 0.6, 0.6)), "scav_squad": M("creatures/raider"), "dune_sniper": M("creatures/marksman", 1.0, (1.1, 1.0, 0.8)),
    "feral_alpha": M("creatures/feral", 1.15, (0.9, 0.9, 1.1)), "raider_flamethrower": M("creatures/raider", 1.0, (1.2, 0.8, 0.6)),
    "old_man_brawn": M("creatures/brute", 1.2, (1.0, 0.9, 1.1)), "mira_kestrel": Hm("Female_Ranger", "Pistol_Shoot", hold="pistol", tint=(0.9, 1.0, 1.1)),
    "warlord": M("creatures/boss_warlord", 1.1), "butcher": M("creatures/boss_butcher", 1.1),
    # crypt
    "restless_bones": M("creatures/skeleton_sword"), "bone_rattler": M("creatures/skeleton_sword", 0.8), "skeleton_archer": M("creatures/skeleton_bow"),
    "skeleton_swordsman": M("creatures/skeleton_sword"), "fire_skeleton": M("creatures/skeleton_sword", 1.0, (1.4, 0.7, 0.5)),
    "frostbone_guard": M("creatures/skeleton_sword", 1.05, (0.7, 0.9, 1.4)), "toxic_skeleton": M("creatures/skeleton_sword", 1.0, (0.7, 1.3, 0.6)),
    "bone_knight": M("fantasy/creatures/pale_knight"), "crypt_keeper": M("fantasy/creatures/pallid_king"), "mother_of_bones": M("fantasy/creatures/pallid_king", 1.4, (1.1, 1.0, 0.9)),
    "bonewall_colossus": M("fantasy/creatures/rime_colossus", 1.0, (1.2, 1.15, 0.95)), "lich_clockmaker": M("fantasy/creatures/hollow_shade", 1.2, (1.2, 1.0, 0.7)),
    "brass_beetle": M("creatures/clockwork_bear", 0.35, (1.3, 1.0, 0.5)), "clockwork_sentry": M("creatures/clockwork_bear", 0.8),
    "cog_spider": M("creatures/clockwork_bear", 0.45, (0.9, 0.9, 1.0)), "mainspring_golem": M("creatures/clockwork_bear", 1.2, (1.1, 1.0, 0.8)),
    "brass_owl": M("creatures/crow", 0.1, (1.8, 1.4, 0.6)), "clockwork_repairman": M("creatures/clockwork_bear", 0.9, (0.9, 1.0, 1.1)),
    "cog_hound": M("creatures/clockwork_bear", 0.6, (1.2, 0.8, 0.6)), "grand_orrery": M("creatures/clockwork_bear", 1.6, (1.4, 1.1, 0.5)),
    "clockwork_bear": M("creatures/clockwork_bear", 1.1), "skeleton_king": M("fantasy/creatures/pallid_king", 1.2, (1.2, 1.1, 0.8)),
    # aurelind
    "strawling": M("fantasy/creatures/strawling"), "scarecrow_sentinel": M("fantasy/creatures/strawling", 1.3, (0.9, 0.8, 0.7)),
    "field_slime": M("fantasy/creatures/field_slime"), "slimelet": M("fantasy/creatures/field_slime", 0.6), "great_slime": M("fantasy/creatures/field_slime", 2.2),
    "moss_goblin": M("fantasy/creatures/mossgoblin"), "forest_wolf": M("fantasy/creatures/forest_wolf"), "frost_wolf": M("fantasy/creatures/frost_wolf"),
    "barkhide": M("fantasy/creatures/barkhide"), "storm_harpy": M("fantasy/creatures/storm_harpy"), "magma_imp": M("fantasy/creatures/magma_imp"),
    "ice_golem": M("fantasy/creatures/ice_golem"), "gale_spirit": M("fantasy/creatures/gale_spirit"), "harvest_king": M("fantasy/creatures/harvest_king"),
    "ash_drake": M("fantasy/creatures/ash_drake"), "cinderwyrm": M("fantasy/creatures/cinderwyrm"), "tempest_roc": M("fantasy/creatures/tempest_roc"),
    "apprentice_mage": Hm("Female_Peasant", "Spell_Simple_Shoot", hold="staff"), "mirren": Hm("Female_Ranger", "Spell_Simple_Shoot", hold="staff", tint=(0.8, 0.9, 1.2)),
    "slime_king": M("fantasy/creatures/field_slime", 2.6, (1.3, 1.2, 0.5)),
    # club
    "party_goer": Hm("Male_Peasant", "Dance_Loop", tint=(1.1, 0.8, 1.2)), "dance_floor_regular": Hm("Female_Peasant", "Dance_Loop", tint=(0.8, 1.0, 1.3)),
    "glow_stick_raver": Hm("Male_Ranger", "Dance_Loop", tint=(0.6, 1.3, 0.8)), "stage_diver": Hm("Male_Peasant", "Jump_Loop", tint=(1.2, 0.9, 0.7)),
    "club_bouncer": Hm("Male_Ranger", "Punch_Cross", tint=(0.5, 0.5, 0.6)), "pit_boss": Hm("Male_Ranger", "Idle_Talking_Loop", tint=(0.6, 0.5, 0.4)),
    "high_roller": Hm("Male_Peasant", "Interact", tint=(1.3, 1.1, 0.6)), "dj": Hm("Male_Ranger", "Dance_Loop", tint=(0.4, 0.4, 0.5)),
    # neutral
    "island_fisher": Hm("Male_Peasant", "PickUp_Table"), "lifeguard_trainee": Hm("Female_Ranger", "Jog_Fwd_Loop", tint=(1.3, 0.6, 0.5)),
    "chalk_artist": Hm("Male_Peasant", "Interact", tint=(1.0, 1.0, 1.2)), "shipwright": Hm("Male_Ranger", "Fixing_Kneeling", tint=(1.1, 0.9, 0.7)),
    "debris_hauler": Hm("Male_Peasant", "Push_Loop", tint=(0.9, 0.9, 0.8)), "hop_runner": Hm("Male_Ranger", "Jump_Loop", tint=(0.9, 1.1, 1.3)),
    "marina": Hm("Female_Ranger", "Sprint_Loop", tint=(1.3, 0.55, 0.5)), "arena_gladiator": M("fantasy/creatures/red_warrior"),
    "colosseum_bruiser": M("fantasy/creatures/blue_warrior", 1.15), "driftwood_golem": M("fantasy/creatures/barkhide", 1.4, (1.1, 1.0, 0.8)),
    "box_seagull": M("creatures/crow", 0.14, (2.5, 2.5, 2.5)), "giant_crow": M("creatures/crow", 0.45), "dome_beast": M("creatures/boss_dome_beast", 1.3),
    "the_tyrant": M("creatures/boss_tyrant", 1.3), "the_overseer": M("creatures/boss_overseer", 1.2),
}
for staff in STAFF_TINTS:
    SUBJECTS.setdefault(staff, Hm("Female_Ranger", "Idle_Talking_Loop"))
SUBJECTS["chip_runner"] = Hm("Female_Ranger", "Sprint_Loop")
SUBJECTS["dice_shaker"] = Hm("Female_Peasant", "Interact")
SUBJECTS["violet"] = Hm("Female_Ranger", "Spell_Simple_Shoot")
SUBJECTS["cherry"] = Hm("Female_Peasant", "Interact")
SUBJECTS["pachinko_queen"] = Hm("Female_Ranger", "Dance_Loop")
SUBJECTS["lottie"] = Hm("Female_Peasant", "Idle_Talking_Loop")
STAGE_BY_ID = {"frost_wolf": "ice", "ice_golem": "ice", "frostbone_guard": "ice", "magma_imp": "volcano", "ash_drake": "volcano",
               "cinderwyrm": "volcano", "fire_skeleton": "volcano", "harbor_gull": "beach", "box_seagull": "beach", "giant_crow": "beach",
               "marina": "beach", "lifeguard_trainee": "beach", "island_fisher": "beach", "shipwright": "beach", "debris_hauler": "beach",
               "chalk_artist": "beach", "hop_runner": "beach", "pink_earthworm": "field", "driftwood_golem": "beach"}
BIPED_POSES = [  # ArmL, ArmR, LegL, LegR in degrees (+x raises forward)
    {"ArmR": [150, 0, 20], "ArmL": [40, 0, -20], "LegL": [25, 0, 0], "LegR": [-20, 0, 0]},
    {"ArmR": [100, 0, 40], "ArmL": [90, 0, -40], "LegL": [-25, 0, 0], "LegR": [30, 0, 0]},
    {"ArmR": [60, 0, 80], "ArmL": [60, 0, -80], "LegL": [15, 0, 0], "LegR": [-15, 0, 0]},
    {"ArmR": [170, 0, 0], "ArmL": [-30, 0, -20], "LegL": [35, 0, 0], "LegR": [-10, 0, 0]},
]


def _h(card_id, n):
    return int(hashlib.md5(card_id.encode()).hexdigest()[:8], 16) % n


def spell_scene(cid, c):
    """Spells: the faction's place with the effect as the subject (fire, a bolt, a wave, chips ...) and, for summons and
    buffs, the creatures it makes or helps."""
    effects = c.get("effects", [])
    does = [e.get("do") for e in effects]
    f = c["faction"]
    subjects, fx = [], []
    victim = {"tide": "raider_scrapper", "waste": "drowned_deckhand", "crypt": "forest_wolf", "aurelind": "skeleton_swordsman",
              "club": "raider_brute", "neutral": "moss_goblin"}[f]
    friend = {"tide": "drowned_sailor", "waste": "raider_scrapper", "crypt": "skeleton_swordsman", "aurelind": "forest_wolf",
              "club": "cocktail_waitress", "neutral": "arena_gladiator"}[f]
    if "summon" in does:
        token = next(e["card"] for e in effects if e.get("do") == "summon")
        n = max(e.get("count", 1) for e in effects if e.get("do") == "summon")
        for i in range(min(n, 3)):
            subjects.append({"card": token, "at": [(i - (min(n, 3) - 1) / 2) * 1.3, i % 2 * 0.8, 0]})
    elif any(d in does for d in ("damage", "destroy", "bounce")):
        subjects.append({"card": victim, "at": [0, 1.0, 0]})  # the one it hits
    elif any(d in does for d in ("buff", "give", "heal", "draw")):
        subjects.append({"card": friend, "at": [0, 0.6, 0]})  # the one it helps
    colors = {"tide": (0.4, 0.8, 1.0), "waste": (1.0, 0.6, 0.2), "crypt": (0.5, 1.0, 0.7), "aurelind": (1.0, 0.5, 0.15), "club": (1.0, 0.3, 0.8), "neutral": (1.0, 0.9, 0.6)}
    col = list(colors[f])
    name = c.get("name", cid).lower()
    if "water" in name or "tidal" in name or "spray" in name or "wave" in name or "mend" in name:
        col = [0.4, 0.8, 1.0]
    if "stone" in name or "earth" in name:
        col = [0.8, 0.6, 0.35]
    if "gust" in name or "air" in name:
        col = [0.85, 0.95, 1.0]
    if "gravity" in name:
        col = [0.6, 0.4, 1.0]
    if "damage" in does:
        if f == "waste":
            fx += [{"kind": "sparks", "at": [0, 0.5, 0.8], "size": 1.4, "count": 140}, {"kind": "smoke", "at": [0.4, 1.5, 0], "size": 1.4}, {"kind": "glow", "at": [0, 0.3, 0.9], "size": 2, "color": [1, 0.6, 0.2]}]
        elif f == "tide":
            fx += [{"kind": "spray", "at": [0, 0.6, 0.0], "size": 1.4, "count": 260}]
        elif "random_enemy" in str(effects) or f == "club":
            fx += [{"kind": "bolt", "at": [0.3, 1.5, 0], "color": col}, {"kind": "sparks", "at": [0.3, 1.5, 0.2], "size": 1.0, "color": col}]
        elif col == [1.0, 0.5, 0.15]:
            fx += [{"kind": "fire", "at": [0, 1.0, 0], "size": 1.2}, {"kind": "embers", "at": [0, 1.0, 0.6], "size": 1.5, "count": 120}]
        else:
            fx += [{"kind": "magic", "at": [0, 1.0, 0.3], "size": 1.4, "color": col}, {"kind": "sparks", "at": [0, 1.0, 0.8], "size": 1.0, "color": col}]
    if any(d in does for d in ("buff", "give", "heal", "crystal", "mana")):
        fx += [{"kind": "beam", "at": [0, 1.0, 0], "size": 1.2, "color": col}, {"kind": "magic", "at": [0, 1.0, 0.2], "size": 1.0, "color": col}]
    if "destroy" in does:
        fx += [{"kind": "bones", "at": [0, 1.0, 0.4], "size": 1.4}, {"kind": "smoke", "at": [0, 1.6, 0], "size": 1.6, "color": [0.08, 0.06, 0.1]}, {"kind": "glow", "at": [0, 1, 1], "size": 2, "color": [0.6, 0.2, 1.0]}]
    if "bounce" in does:
        fx += [{"kind": "streaks", "at": [0, 0.5, 0.2], "size": 1.4, "color": col}, {"kind": "spray", "at": [0, 1.0, 0], "size": 1.0, "count": 150}]
    if "draw" in does or "add" in does:
        fx += [{"kind": "magic", "at": [0, 0.8, 0.4], "size": 1.0, "color": [1.0, 0.85, 0.4]}, {"kind": "beam", "at": [0, 1.0, 0], "size": 0.8, "color": [1.0, 0.85, 0.5]}]
    if "roll" in does or "flip" in does or c["type"] == "trap" or f == "club":
        fx += [{"kind": "chips", "at": [0, 0.6, 0.5], "size": 1.2, "count": 40}, {"kind": "confetti", "at": [0, 0.8, 0.8], "size": 1.0, "count": 60}]
    if not fx:
        fx = [{"kind": "magic", "at": [0, 1.0, 0.3], "size": 1.2, "color": col}]
    return subjects, fx


def recipe(cid, c):
    f = c.get("faction", "neutral")
    r = {"stage": STAGE_BY_ID.get(cid, STAGE[f]), "time": TIMES[f][_h(cid, len(TIMES[f]))], "sun_yaw": [-30, -10, 10, 25][_h(cid + "s", 4)],
         "mist": [4, 40], "camera": "auto", "subjects": [], "fx": []}
    if r["stage"] in ("ice",):
        r["time"] = ["day", "dusk", "night"][_h(cid, 3)]
    if r["stage"] == "volcano":
        r["time"] = "fire"
    if c.get("type") in ("spell", "trap"):
        subs, r["fx"] = spell_scene(cid, c)
        for s in subs:
            sub = subject(s["card"], s["at"])
            if sub:
                r["subjects"].append(sub)
        return r
    sub = subject(cid, [0, 0, 0])
    if sub:
        r["subjects"].append(sub)
    kws = c.get("keywords", [])
    if cid in ("scav_squad", "feral_alpha", "mother_of_bones", "harvest_king", "crawler_mother", "bell_keeper", "conga_line"):
        extra = {"scav_squad": "raider_scrapper", "feral_alpha": "wasteland_feral", "mother_of_bones": "bone_rattler", "harvest_king": "strawling",
                 "crawler_mother": "sea_crawler", "bell_keeper": "drowned_spawn"}.get(cid)
        if extra:
            for i, x in enumerate((-1.4, 1.4)):
                s2 = subject(extra, [x, 0.9 + i * 0.3, 0])
                if s2:
                    r["subjects"].append(s2)
    text = str(c.get("effects", []))
    if "charge" in kws or "rush" in kws:
        r["fx"].append({"kind": "streaks", "at": [0, 0.2, 0.0], "size": 1.2})
        r["fx"].append({"kind": "dust", "at": [0, 0.5, 0], "size": 0.9})
    if "fire" in cid or "flame" in cid or "magma" in cid or "ash" in cid or "cinder" in cid or "bomber" in cid:
        r["fx"] += [{"kind": "fire", "at": [0.8, 0.6, 0], "size": 0.7}, {"kind": "embers", "at": [0, 0.2, 0.8], "size": 1.6, "count": 120}]
    if "frost" in cid or "ice" in cid:
        r["fx"].append({"kind": "magic", "at": [0, 0.2, 0.4], "size": 1.4, "color": [0.7, 0.9, 1.0]})
    if "toxic" in cid or "venom" in kws or "slime" in cid:
        r["fx"].append({"kind": "magic", "at": [0, 0.2, 0.3], "size": 1.2, "color": [0.5, 1.0, 0.3]})
    if "guard" in kws:
        r["fx"].append({"kind": "glow", "at": [-1.0, -1.0, 1.2], "size": 1.0, "color": [0.8, 0.9, 1.0]})
    if "damage" in text and not r["fx"]:
        r["fx"].append({"kind": "sparks", "at": [0.6, -0.4, 1.2], "size": 0.9})
    if f == "club":
        r["fx"] += [{"kind": "confetti", "at": [0, 0.5, 1.2], "size": 1.0}, {"kind": "glow", "at": [1.5, -1, 2], "size": 1.0, "color": [1, 0.2, 0.7]}]
    if f == "tide" and r["stage"] == "beach":
        r["fx"].append({"kind": "spray", "at": [0.3, 1.5, 0.0], "size": 0.8, "count": 180})
    if c.get("rarity") == "legendary" or c.get("leader"):
        r["fx"].append({"kind": "beam", "at": [0, 0.6, 0], "size": 1.5, "color": [1.0, 0.85, 0.5]})
        # grander: a slow ring of golden motes and a warm rim light behind
        r["fx"].append({"kind": "magic", "at": [0, 0.5, 0.2], "size": 2.0, "color": [1.0, 0.82, 0.4], "count": 90})
        r["fx"].append({"kind": "glow", "at": [0, 2.5, 2.2], "size": 2.0, "color": [1.0, 0.75, 0.4]})
        r["light"] = 2.2 if r["time"] in ("club", "night", "cave") else 1.25
        r["time"] = {"club": "club", "crypt": "night"}.get(f, "sunset")
    return r


def subject(cid, at):
    s = SUBJECTS.get(cid)
    if s is None:
        return None
    if s[0] == "m":
        out = {"model": s[1], "at": at, "yaw": 180 + [-25, -10, 10, 25][_h(cid + "y", 4)], "scale": s[2], "pose": BIPED_POSES[_h(cid, len(BIPED_POSES))]}
        if s[3]:
            out["tint"] = list(s[3])
        return out
    x = dict(s[3])
    out = {"human": s[1], "clip": s[2], "phase": [0.3, 0.45, 0.6][_h(cid, 3)], "at": at, "yaw": [-20, -5, 10, 20][_h(cid + "y", 4)]}
    if cid in STAFF_TINTS:
        out["ears"] = list(EARS)
        out["tint"] = list(STAFF_TINTS[cid])
    if "tint" in x:
        out["tint"] = list(x["tint"])
    if "hold" in x:
        out["hold"] = x["hold"]
    return out
