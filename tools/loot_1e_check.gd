# Purpose: developer check of sea step 1e (diary/DECISIONS_SEA.md): pony families and their pony-only traits
# (data/pony_families.json, data/gun_traits.json), sea affixes (data/sea_affixes.json) in core/gun_gen.gd /
# core/gun_stats.gd, the host refusing edited ones, and what the 12 pony-only traits do (game/gun_traits.gd on
# stand-ins). Log tools/loot_1e_check.log (LOOT_1E_CHECK_DONE problems=n).
# Dependencies: core/gun_gen.gd, core/gun_stats.gd, core/gun_db.gd, game/gun_traits.gd, core/health_state.gd.
extends Node

const GunGen = preload("res://core/gun_gen.gd")
const GunStats = preload("res://core/gun_stats.gd")
const GunDb = preload("res://core/gun_db.gd")
const GunTraits = preload("res://game/gun_traits.gd")
const HealthState = preload("res://core/health_state.gd")


class Mob extends Node3D:
	var health := HealthState.new(1000.0)
	var got := 0.0
	var burn := 0.0
	var pushed := Vector3.ZERO
	var slowed := 0.0
	var vuln := 1.0
	var burning := false

	func on_hit(d: float, _p: Vector3 = Vector3.ZERO, _n: Vector3 = Vector3.UP) -> void:
		got += d
		health.take_damage(d)

	func apply_burn(dps: float, _s: float) -> void:
		burn = dps

	func push(v: Vector3) -> void:
		pushed = v

	func apply_slow(a: float, _s: float) -> void:
		slowed = a

	func apply_vulnerable(m: float, _s: float) -> void:
		vuln = m

	func is_burning() -> bool:
		return burning


class Crowd extends RefCounted:
	var list: Array = []

	func enemy_list() -> Array:
		return list


class Blasts extends Node:
	var source: RefCounted
	var blasts := 0
	var flashes := 0

	func blast(_p: Vector3, _r: float, _d: float, _flash: bool = true) -> void:
		blasts += 1

	func show_flash(_p: Vector3, _r: float) -> void:
		flashes += 1


class Holder extends Node3D:
	var explosives: Node
	var health := HealthState.new(100.0)
	var allies_close := 0


var _lines := PackedStringArray()
var _problems := 0


func _ready() -> void:
	var db := GunDb.new(_json("gun_loot"), _json("gun_parts"), _json("manufacturers"), _json("weapons"), _json("skills"), _json("gun_uniques"))
	var rng := RandomNumberGenerator.new()
	rng.seed = 21
	_data(db)
	_ponies(db, rng)
	_sea(db, rng)
	_effects()
	_finish()


func _data(db: GunDb) -> void:
	var pony_traits := 0
	var formats := true
	for t: Dictionary in db.traits:
		formats = formats and not (String(t["desc"]) % "5").is_empty()
		if String(t.get("family", "")) != "":
			pony_traits += 1
			formats = formats and not db.family_def(String(t["family"])).is_empty()
	var listed := true
	for f: String in db.families:
		for id: String in db.family_def(f)["traits"]:
			listed = listed and String(db.trait_def(id).get("family", "")) == f
	_say("6 families, 12 pony-only traits, each listed by its own family, every text formats", db.families.size() == 6 and pony_traits == 12 and formats and listed)
	var buffs_known := true
	for id: String in db.sea["affixes"]:
		for b: String in (db.sea_def(id).get("buffs", {}) as Dictionary):
			buffs_known = buffs_known and not db.buff_def(b).is_empty()
	_say("10 sea affixes, their buffs all known", (db.sea["affixes"] as Dictionary).size() == 10 and buffs_known)


func _ponies(db: GunDb, rng: RandomNumberGenerator) -> void:
	var ok := true
	var seen_families := {}
	var seen_traits := {}
	for i in 300:
		var gun := GunGen.generate(db, rng, 0.0, "", "pony", "", 12)
		if gun.has("unique"):
			continue
		var family := String(gun.get("family", ""))
		seen_families[family] = true
		var own := 0
		for t: Dictionary in gun["traits"]:
			var of := String(db.trait_def(String(t["id"])).get("family", ""))
			if of != "":
				seen_traits[String(t["id"])] = true
				own += 1 if of == family else 100
		ok = ok and family != "" and own == 1 and GunGen.validate(db, gun) == ""
	_say("pony guns: a family, exactly one of its own traits, legal (all 6 families and %d of 12 pony traits seen)" % seen_traits.size(), ok and seen_families.size() == 6 and seen_traits.size() == 12)
	var clean := true
	for i in 200:
		var gun := GunGen.generate(db, rng, 0.0, "", "orange", "", 12)
		for t: Dictionary in gun["traits"]:
			clean = clean and String(db.trait_def(String(t["id"])).get("family", "")) == ""
		clean = clean and not gun.has("family")
	_say("orange guns never get a family or a pony-only trait", clean)
	var pony := GunGen.generate(db, rng, 0.0, "m16", "pony", "", 12)
	while pony.has("unique"):
		pony = GunGen.generate(db, rng, 0.0, "m16", "pony", "", 12)
	_say("the pony's name carries its family", GunStats.display_name(db, pony).contains(String(db.family_def(String(pony["family"]))["name"])))
	var other_family := ""
	for f: String in db.families:
		if f != String(pony["family"]):
			other_family = f
	var edited := pony.duplicate(true)
	((edited["traits"] as Array)[0] as Dictionary)["id"] = String(db.family_def(other_family)["traits"][0])
	_say("another family's trait is refused", GunGen.validate(db, edited) != "")
	edited = pony.duplicate(true)
	edited.erase("family")
	_say("a pony without a family is refused", GunGen.validate(db, edited) != "")
	edited = pony.duplicate(true)
	edited["family"] = "unicorn_dreams"
	_say("an unknown family is refused", GunGen.validate(db, edited) != "")
	var orange := GunGen.generate(db, rng, 0.0, "m16", "orange", "", 12)
	edited = orange.duplicate(true)
	edited["family"] = String(pony["family"])
	_say("a family on an orange gun is refused", GunGen.validate(db, edited) != "")
	edited = orange.duplicate(true)
	((edited["traits"] as Array)[0] as Dictionary)["id"] = "storm_hoof"
	_say("a pony-only trait on an orange gun is refused", GunGen.validate(db, edited) != "")
	var u := GunGen.unique(db, "stampede", 10)
	_say("a unique stays legal", GunGen.validate(db, u) == "")
	u["v"] = 3
	_say("a unique saved as version 3 stays legal", GunGen.validate(db, u) == "")


func _sea(db: GunDb, rng: RandomNumberGenerator) -> void:
	var low := 0
	for i in 300:
		if GunGen.generate(db, rng, 0.0, "", "blue", "", 30).has("sea"):
			low += 1
	var high := 0
	var legal := true
	for i in 300:
		var gun := GunGen.generate(db, rng, 0.0, "", "blue", "", 70)
		if gun.has("sea"):
			high += 1
		legal = legal and GunGen.validate(db, gun) == ""
	_say("no sea affix below level 31 (%d); about 75 %% at level 70 (%d of 300), all legal" % [low, high], low == 0 and high > 180 and high < 270 and legal)
	var gun := GunGen.generate(db, rng, 0.0, "ak47", "purple", "", 60)
	gun["sea"] = {"id": "brined", "q": float((gun["rolls"] as Dictionary).values()[0])}
	var plain := gun.duplicate(true)
	plain.erase("sea")
	var with_sea := GunStats.final_stats(db, gun)
	var without := GunStats.final_stats(db, plain)
	_say("Brined adds damage and the slow buff", float(with_sea["damage"]) > float(without["damage"]) and float((with_sea["buffs"] as Dictionary).get("slow_on_hit", 0.0)) > float((without["buffs"] as Dictionary).get("slow_on_hit", 0.0)))
	_say("the name carries the affix's word and the card text reads", GunStats.display_name(db, gun).contains("Brined") and GunStats.sea_text(db, gun).begins_with("Brined: "))
	_say("that gun is legal", GunGen.validate(db, gun) == "")
	var edited := gun.duplicate(true)
	edited["lvl"] = 20
	_say("a sea affix on a level-20 gun is refused", GunGen.validate(db, edited) != "")
	edited = gun.duplicate(true)
	edited["sea"] = {"id": "lava_lamp", "q": 0.9}
	_say("an unknown affix is refused", GunGen.validate(db, edited) != "")
	edited = gun.duplicate(true)
	edited["sea"] = {"id": "brined", "q": 0.01}
	_say("an affix below the tier's quality is refused", GunGen.validate(db, edited) != "")
	edited = gun.duplicate(true)
	edited["v"] = 3
	_say("a version-3 gun with a sea affix is refused", GunGen.validate(db, edited) != "")


func _effects() -> void:
	var crowd := Crowd.new()
	var blasts := Blasts.new()
	blasts.source = crowd
	add_child(blasts)
	var holder := Holder.new()
	holder.explosives = blasts
	add_child(holder)
	var mobs: Array[Mob] = []
	for i in 3:
		var m := Mob.new()
		m.position = Vector3(float(i) * 2.0, 0.0, -10.0)
		add_child(m)
		mobs.append(m)
		crowd.list.append(m)
	var fx := GunTraits.new()
	fx.player = holder
	var t := Time.get_ticks_msec() / 1000.0
	# Storm Hoof: the 4th hit adds a strike
	for n in 4:
		fx.on_hit({"storm_hoof": 100.0}, mobs[0], mobs[0].position, 10.0)
	_say("Storm Hoof: the 4th hit calls lightning (+10 on a 10 hit)", is_equal_approx(mobs[0].got, 10.0) and blasts.flashes == 1)
	fx.on_hit({"cinder_trail": 30.0}, mobs[0], mobs[0].position, 10.0)
	_say("Cinder Trail burns for 30 % of the hit a second", is_equal_approx(mobs[0].burn, 3.0))
	fx.on_hit({"undertow": 25.0}, mobs[1], mobs[1].position, 10.0)
	_say("Undertow drags toward the shooter and slows", mobs[1].pushed.z > 0.0 and is_equal_approx(mobs[1].slowed, 0.25))
	fx.on_hit({"gravity_mane": 6.0}, mobs[1], mobs[1].position, 10.0)
	_say("Gravity Mane pulls the others toward the target", mobs[0].pushed.x > 0.0 and mobs[2].pushed.x < 0.0)
	fx.on_kill({"static_mane": 20.0}, mobs[1].position, 10.0, t, mobs[1])
	_say("Static Mane charges enemies within 6 m", is_equal_approx(mobs[0].vuln, 1.2) and is_equal_approx(mobs[2].vuln, 1.2))
	var before := blasts.blasts
	mobs[2].burning = true
	fx.on_kill({"firestorm_mane": 100.0}, mobs[2].position, 10.0, t, mobs[2])
	mobs[0].burning = false
	fx.on_kill({"firestorm_mane": 100.0}, mobs[0].position, 10.0, t, mobs[0])
	_say("Firestorm Mane bursts only from a burning kill", blasts.blasts == before + 1)
	var got := mobs[1].got
	fx.on_kill({"comet_tail": 100.0}, mobs[0].position, 10.0, t, mobs[0])
	_say("Comet Tail drops a star on the nearest other enemy", mobs[1].got > got)
	var ec := {"eclipse": 50.0}
	fx.on_kill(ec, mobs[0].position, 10.0, t, mobs[0])
	fx.on_kill(ec, mobs[0].position, 10.0, t, mobs[0])
	fx.on_shot(ec, t)
	var charged := fx.damage_mult(ec, mobs[0])
	fx.after_shot(true)
	fx.on_shot(ec, t)
	_say("Eclipse: two kills make the next shot x2.0, then it is spent (%.2f, %.2f)" % [charged, fx.damage_mult(ec, mobs[0])], is_equal_approx(charged, 2.0) and is_equal_approx(fx.damage_mult(ec, mobs[0]), 1.0))
	fx.after_shot(true)
	var far := fx.damage_mult({"moonlit": 40.0}, mobs[0])
	mobs[0].position = Vector3(0, 0, -5)
	_say("Moonlit: nothing at 10 m", is_equal_approx(far, 1.0) and true)
	mobs[0].position = Vector3(0, 0, -30)
	_say("Moonlit: +40 % at 30 m", is_equal_approx(fx.damage_mult({"moonlit": 40.0}, mobs[0]), 1.4))
	var pr := {"prism_mane": 10.0}
	for m in mobs:
		fx.on_hit(pr, m, m.position, 1.0)
	_say("Prism Mane: three different enemies hit = +30 %", is_equal_approx(fx.damage_mult(pr, mobs[0]), 1.3))
	before = blasts.blasts
	var tide := {"tidal_surge": 100.0}
	for n in 8:
		fx.on_shot(tide, t)
		fx.on_hit(tide, mobs[0], mobs[0].position, 10.0)
		fx.on_hit(tide, mobs[1], mobs[1].position, 10.0)  # a second pellet: still one wave
		fx.after_shot(true)
	_say("Tidal Surge: one wave on the 8th shot", blasts.blasts == before + 1)


func _json(name: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://data/%s.json" % name))


func _say(text: String, ok: bool) -> void:
	_lines.append(("ok   " if ok else "FAIL ") + text)
	if not ok:
		_problems += 1


func _finish() -> void:
	_lines.append("LOOT_1E_CHECK_DONE problems=%d" % _problems)
	var f := FileAccess.open("res://tools/loot_1e_check.log", FileAccess.WRITE)
	f.store_string("\n".join(_lines) + "\n")
	f.close()
	print("\n".join(_lines))
	get_tree().quit()
