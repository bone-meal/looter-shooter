# Purpose: developer check of the eight sea step 2 gun bodies (data/weapons.json, data/gun_parts.json, data/items.json,
# core/weapon_state.gd, game/shot_bolts.gd, game/gun_actions.gd, the models of tools/blender/weapons_sea.py): every
# body rolls into legal guns with a name; the lever-action loads one round at a time and a shot breaks in; the
# revolver fans faster on fresh presses; the flamethrower overheats, locks and cools; the harpoon pins and reels in
# a small enemy (not a big one); a flare sets fire round where it lands, burns there as a light and counts as fire;
# a crossbow bolt lies where it landed and goes back into the pool when walked over; the models carry their moving
# parts and the parts move. Log tools/sea_guns_check.log (SEA_GUNS_CHECK_DONE problems=n).
# Dependencies: the files above, core/gun_db.gd, core/gun_gen.gd, core/gun_stats.gd, game/weapon_models.gd.
extends Node3D

const WeaponState = preload("res://core/weapon_state.gd")
const GunDb = preload("res://core/gun_db.gd")
const GunGen = preload("res://core/gun_gen.gd")
const GunStats = preload("res://core/gun_stats.gd")
const ShotBolts = preload("res://game/shot_bolts.gd")
const WeaponModels = preload("res://game/weapon_models.gd")
const GunActions = preload("res://game/gun_actions.gd")

const BODIES := ["smg", "revolver", "lever_rifle", "harpoon_gun", "flare_gun", "flamethrower", "crossbow", "blunderbuss"]
const PARTS := {"smg": ["Bolt", "Barrel", "Mag", "Support"], "revolver": ["Cylinder", "Hammer", "Barrel"], "lever_rifle": ["Lever", "Hammer", "Barrel", "Support"],
	"harpoon_gun": ["Spear", "Support"], "flare_gun": ["Breech", "Hammer"], "flamethrower": ["Needle", "Nozzle", "Pilot", "Support"],
	"crossbow": ["Arrow", "StringDrawn", "StringLoose", "Support"], "blunderbuss": ["Hammer", "Barrel", "Support"]}

var _lines := PackedStringArray()
var _problems := 0


class Dummy extends StaticBody3D:  # stands in for game/enemy.gd
	var enemy_id := "chaser"
	var health := Health.new()
	var hits := 0.0
	var slowed := 0.0
	var pushed := Vector3.ZERO
	var burning := 0.0

	func on_hit(damage: float, _at: Vector3 = Vector3.ZERO, _normal: Vector3 = Vector3.UP) -> void:
		hits += damage

	func apply_slow(amount: float, _seconds: float) -> void:
		slowed = amount

	func push(v: Vector3) -> void:
		pushed = v

	func apply_burn(dps: float, _seconds: float) -> void:
		burning = dps

	func head_height() -> float:
		return 1.8


class Health:
	var max_hp := 100.0

	func is_dead() -> bool:
		return false


class Source:
	var list: Array = []

	func enemy_list() -> Array:
		return list


class Shooter extends Node3D:  # stands in for game/player.gd
	var landed := 0
	var picked := 0

	func projectile_hit(collider: Object, _at: Vector3, _normal: Vector3, _stats: Dictionary) -> void:
		landed += 1
		collider.call("on_hit", 10.0)

	func bolt_picked() -> bool:
		picked += 1
		return true


func _ready() -> void:
	var weapons: Dictionary = _json("weapons")["weapons"]
	var db := GunDb.new(_json("gun_loot"), _json("gun_parts"), _json("manufacturers"), _json("weapons"), _json("skills"), _json("gun_uniques"))
	var items: Dictionary = _json("items")["items"]
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	for body: String in BODIES:
		var ok := weapons.has(body) and db.bodies.has(body) and items.has(body) and String(items[body]["kind"]) == "weapon"
		var legal := true
		var sample := ""
		for tier: String in ["grey", "purple", "pony"]:
			var gun := GunGen.generate(db, rng, 0.0, body, tier, "", 20)
			legal = legal and GunGen.validate(db, gun) == ""
			sample = GunStats.display_name(db, gun)
		_say("%s: in the data, rolls legal guns (%s)" % [body, sample], ok and legal)
	# --- lever-action: one round at a time, a shot breaks in
	var lever := WeaponState.new("lever_rifle", weapons["lever_rifle"])
	lever.ammo = 2
	lever.start_reload(0.0)
	lever.update(0.51)
	var after_one := lever.ammo
	lever.update(1.02)
	var after_two := lever.ammo
	var fired := lever.try_fire(1.1)
	_say("lever-action: +1 round per 0.5 s (%d, %d), a shot breaks into the reload (%s)" % [after_one, after_two, str(fired)], after_one == 3 and after_two == 4 and fired and not lever.is_reloading())
	# --- revolver: held 2.2 / s, fresh presses up to 7 / s
	var rev := WeaponState.new("revolver", weapons["revolver"])
	var held := 0
	var tapped := 0
	for i in 20:  # one second, every 0.05 s
		if rev.try_fire(0.05 * i, false):
			held += 1
	rev = WeaponState.new("revolver", weapons["revolver"])
	for i in 7:  # one press every 1/7 s
		if rev.try_fire(10.0 + float(i) / 7.0 + 0.001, true):
			tapped += 1
	_say("revolver: held fires %d in a second, fanning %d of 7 presses (wider: %s)" % [held, tapped, str(rev.fanned_shot)], held <= 3 and tapped >= 6 and rev.fanned_shot)
	# --- flamethrower: overheats, locks, cools
	var flame := WeaponState.new("flamethrower", weapons["flamethrower"])
	var shots := 0
	var t := 0.0
	while not flame.overheated and t < 20.0:
		if flame.try_fire(t):
			shots += 1
		t += 1.0 / 15.0
		if flame.ammo <= 0:
			flame.ammo = flame.mag_size
	var locked := not flame.try_fire(t + 0.1)
	flame.update(t + 4.0)
	_say("flamethrower: overheats after %d puffs (%.1f s), then will not fire; cool again after 4 s (heat %.2f)" % [shots, t, flame.heat], shots > 40 and locked and not flame.overheated and flame.try_fire(t + 4.0))
	# --- projectiles
	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(80, 1, 80)
	shape.shape = box
	floor_body.add_child(shape)
	floor_body.position = Vector3(0, -0.5, 0)
	add_child(floor_body)
	var small := _dummy(Vector3(0, 1, -8), 100.0)
	var big := _dummy(Vector3(3, 1, -8), 2000.0)
	var source := Source.new()
	source.list = [small, big]
	var bolts := ShotBolts.new()
	bolts.source = source
	add_child(bolts)
	var shooter := Shooter.new()
	add_child(shooter)
	await get_tree().physics_frame
	await get_tree().physics_frame
	bolts.fire(Vector3(0, 1, 0), Vector3(0, 0, -1), weapons["harpoon_gun"]["projectile"], shooter)
	bolts.fire(Vector3(3, 1, 0), Vector3(0, 0, -1), weapons["harpoon_gun"]["projectile"], shooter)
	await _wait(0.6)
	_say("harpoon: both hit (%d), pinned (slow %.1f), the small one reeled in (%.1f m/s) but not the big one (%.1f)" % [shooter.landed, small.slowed, small.pushed.length(), big.pushed.length()],
		shooter.landed == 2 and small.slowed >= 0.8 and small.pushed.z > 5.0 and big.pushed.length() == 0.0)
	small.position = Vector3(0, 1, -40)  # out of the way
	big.position = Vector3(3, 1, -40)
	var near := _dummy(Vector3(-4, 1, -6), 100.0)
	source.list = [near]
	bolts.fire(Vector3(-4, 1.5, 0), Vector3(0, -0.25, -1).normalized(), weapons["flare_gun"]["projectile"], shooter)
	await _wait(1.2)
	var lit := bolts.flare_count()
	_say("flare: lands and burns on (%d), sets the enemy near it burning (%.0f dps), counts as fire" % [lit, near.burning], lit == 1 and near.burning > 0.0 and bolts.fire_near(Vector3(-4, 0, -5.5), 1.5))
	shooter.position = Vector3(8, 0, 0)
	bolts.fire(Vector3(8, 1.2, 0), Vector3(0, -0.4, -1).normalized(), weapons["crossbow"]["projectile"], shooter)
	await _wait(0.6)
	var lying := bolts.lying_count()
	var where := Vector3(8, 0, -3)
	for found: Node in bolts.get_children():
		if found is Node3D and (found as Node3D).position.z < -1.0 and absf((found as Node3D).position.x - 8.0) < 0.5 and (found as Node3D).position.y < 1.0:
			where = (found as Node3D).position
	var before := shooter.picked
	shooter.position = where
	await _wait(0.2)
	_say("bolt: lies where it landed (%d lying at %.1f m) and is picked back up when walked over" % [lying, where.z], lying >= 1 and shooter.picked > before)
	# --- models and moving parts
	for body: String in BODIES:
		var model := WeaponModels.build(body)
		add_child(model)
		var missing := PackedStringArray()
		for part: String in PARTS[body]:
			if model.find_child(part, true, false) == null:
				missing.append(part)
		var gun := WeaponState.new(body, weapons[body])
		var moved := true
		match body:
			"revolver":
				gun.try_fire(1.0)
				GunActions.pose(model, gun, 1.4)
				moved = absf((model.get_node("Cylinder") as Node3D).rotation.z - TAU / 6.0) < 0.05
			"lever_rifle":
				gun.try_fire(1.0)
				GunActions.pose(model, gun, 1.33)
				moved = (model.get_node("Lever") as Node3D).rotation.x > 0.5
			"crossbow":
				gun.try_fire(1.0)
				GunActions.pose(model, gun, 1.1)
				moved = not (model.get_node("Arrow") as Node3D).visible and (model.get_node("StringLoose") as Node3D).visible
			"harpoon_gun":
				gun.try_fire(1.0)
				GunActions.pose(model, gun, 1.1)
				moved = not (model.get_node("Spear") as Node3D).visible
			"flamethrower":
				gun.try_fire(1.0)
				GunActions.pose(model, gun, 1.05)
				var stream := model.find_child("Stream", true, false) as CPUParticles3D
				moved = stream != null and stream.emitting
			"flare_gun":
				gun.try_fire(1.0)
				gun.start_reload(1.5)
				GunActions.pose(model, gun, 1.5 + float(weapons[body]["reload_time"]) * 0.5)
				moved = (model.get_node("Breech") as Node3D).rotation.x < -0.5
		_say("%s model: moving parts there%s, %s" % [body, "" if missing.is_empty() else " MISSING " + ", ".join(missing), "they move" if moved else "DID NOT MOVE"], missing.is_empty() and moved)
		model.queue_free()
	_finish()


func _dummy(at: Vector3, hp: float) -> Dummy:
	var d := Dummy.new()
	d.health.max_hp = hp
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.4
	capsule.height = 1.8
	shape.shape = capsule
	d.add_child(shape)
	d.collision_layer = 2
	d.position = at
	add_child(d)
	return d


func _wait(seconds: float) -> void:
	var until := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < until:
		await get_tree().physics_frame


func _json(file: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://data/%s.json" % file))


func _say(text: String, ok: bool) -> void:
	_lines.append(("ok   " if ok else "FAIL ") + text)
	if not ok:
		_problems += 1


func _finish() -> void:
	_lines.append("SEA_GUNS_CHECK_DONE problems=%d" % _problems)
	var f := FileAccess.open("res://tools/sea_guns_check.log", FileAccess.WRITE)
	f.store_string("\n".join(_lines) + "\n")
	f.close()
	print("\n".join(_lines))
	get_tree().quit()
