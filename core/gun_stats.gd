# Purpose: pure final stats of a gun: base weapon stats x part modifiers (boosted by the part's manufacturer) x part combos (core/gun_combos.gd) x rolled stat bonuses, plus buff values and a display name. No nodes.
# Dependencies: core/gun_db.gd. Output of final_stats is shaped like a data/weapons.json entry so core/weapon_state.gd can use it, with extra keys: crit_chance, recoil (multiplier), ads_fov (multiplier), buffs {id: value}, combos, and unique (its data entry) for hand-made guns.
extends RefCounted

const GunCombos = preload("res://core/gun_combos.gd")

const MIN_RELOAD := 0.2
const MIN_SPREAD := 0.001


static func final_stats(db: RefCounted, gun: Dictionary) -> Dictionary:
	var base: Dictionary = db.weapons[String(gun["body"])]
	var out: Dictionary = base.duplicate(true)
	# 1. multiplier sums per stat from parts
	var bonus := {"damage": 0.0, "fire_rate": 0.0, "mag_size": 0.0, "reload_time": 0.0, "spread": 0.0, "recoil": 0.0, "ads_fov": 0.0}
	var crit: float = db.base_crit_chance
	var gun_parts: Dictionary = gun["parts"]
	for slot: String in gun_parts:
		var pd: Dictionary = gun_parts[slot]
		var mods: Dictionary = db.parts[slot][String(pd["kind"])]["mods"]
		var boost: Dictionary = db.makers[String(pd["maker"])]["part_boost"]
		for stat: String in mods:
			var v: float = float(mods[stat])
			# a manufacturer boost makes its focus stat's bonus stronger (and its penalty weaker for stats where lower is better)
			if boost.has(stat):
				var b: float = float(boost[stat])
				var lower_better := stat in ["reload_time", "spread", "recoil", "ads_fov"]
				v = v * b if (v < 0.0) == lower_better else v / b
			if stat == "crit_chance":
				crit += v
			else:
				bonus[stat] = float(bonus[stat]) + v
	# 1b. what the parts do together: combos and the factory-matched bonus
	var combo_list: Array = GunCombos.active(db, gun)
	for combo: Dictionary in combo_list:
		var extra: Dictionary = combo.get("mods", {})
		for stat: String in extra:
			if stat == "crit_chance":
				crit += float(extra[stat])
			else:
				bonus[stat] = float(bonus[stat]) + float(extra[stat])
	# 2. rolled stat bonuses
	var rolls: Dictionary = gun["rolls"]
	for stat: String in rolls:
		var def: Dictionary = db.stats[stat]
		var amount: float = float(def["max"]) * float(rolls[stat])
		if String(def["mode"]) == "add":
			crit += amount
		else:
			bonus[stat] = float(bonus[stat]) + amount
	# 2b. hand-made uniques: every stat gets the shared unique bonus on top
	if gun.has("unique") and db.uniques.has(String(gun["unique"])):
		for stat: String in db.unique_bonus:
			if stat == "crit_chance":
				crit += float(db.unique_bonus[stat])
			else:
				bonus[stat] = float(bonus[stat]) + float(db.unique_bonus[stat])
		out["unique"] = db.uniques[String(gun["unique"])]
	# 3. apply
	out["damage"] = float(base["damage"]) * maxf(0.1, 1.0 + float(bonus["damage"]))
	out["fire_rate"] = float(base["fire_rate"]) * maxf(0.1, 1.0 + float(bonus["fire_rate"]))
	out["mag_size"] = maxi(1, roundi(float(base["mag_size"]) * maxf(0.1, 1.0 + float(bonus["mag_size"]))))
	out["reload_time"] = maxf(MIN_RELOAD, float(base["reload_time"]) * (1.0 + float(bonus["reload_time"])))
	out["spread"] = maxf(MIN_SPREAD, float(base["spread"]) * maxf(0.05, 1.0 + float(bonus["spread"])))
	out["recoil"] = maxf(0.1, 1.0 + float(bonus["recoil"]))
	out["ads_fov"] = maxf(0.2, 1.0 + float(bonus["ads_fov"]))
	out["crit_chance"] = clampf(crit, 0.0, 0.75)
	if out.has("projectile"):  # launchers: damage is the splash damage
		var proj: Dictionary = out["projectile"]
		proj["splash_damage"] = float(proj["splash_damage"]) * float(out["damage"]) / maxf(float(base["damage"]), 0.001)
	var buff_values: Dictionary = {}
	for b: Dictionary in gun["buffs"]:
		var def: Dictionary = db.buff_def(String(b["id"]))
		buff_values[String(b["id"])] = lerpf(float(def["min"]), float(def["max"]), float(b["q"]))
	for combo: Dictionary in combo_list:  # combo effects add to a rolled buff of the same kind
		var given: Dictionary = combo.get("buffs", {})
		for id: String in given:
			buff_values[id] = float(buff_values.get(id, 0.0)) + float(given[id])
	out["buffs"] = buff_values
	out["combos"] = combo_list
	return out


static func display_name(db: RefCounted, gun: Dictionary) -> String:
	var maker: String = String(db.makers[String(gun["maker"])]["name"])
	var body: String = String(db.bodies[String(gun["body"])]["name"])
	var tier_def: Dictionary = db.tier(String(gun["tier"]))
	var tier: String = String(tier_def.get("tag", tier_def["name"]))
	if gun.has("unique") and db.uniques.has(String(gun["unique"])):
		return "%s %s" % [tier, db.uniques[String(gun["unique"])]["name"]]
	for combo: Dictionary in GunCombos.active(db, gun):  # the strongest named combo goes into the name
		if String(combo.get("name", "")) != "":
			return "%s %s %s %s" % [tier, maker, combo["name"], body]
	return "%s %s %s" % [tier, maker, body]
