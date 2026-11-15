# Purpose: developer check of the chase guns' red-text behaviours (game/signatures/) on stand-ins, and that the host
# accepts what they remember on the gun and refuses forged copies. FISH STORY: kills told bigger with a line, the
# biggest real hit kept on the gun ("record") and on its tag, the boast after a new record. BEACH BALL BOMBARDIER:
# balls bounce off heads (each bounce hits), a shot pops one, a kick sends it where the kicker looks and makes its pop
# bigger, they pop on the ground in the end. CROAK: an air jump while the frog is on the gun, every 5th kill it leaps
# onto the nearest enemy's head and marks it, then hops back when that enemy dies. SWAMP GAS: shots leave clouds; fire
# near one sets it off and its blast sets off the next (a chain); a burning enemy in a cloud sets it off too. Log
# tools/chase_check.log. KEEPER'S LANTERN: its light makes near enemies glow and thins the fog near the camera, the
# inspect key throws it as a firebomb (blast, burning oil that counts as fire), it is lit again after its wait.
# GRILLMASTER: a burning enemy killed by it drops food (a plain kill does not), so does one it hit that burns to death
# later; walking over it heals (offline here). VOLCANO SAUCE: hits add heat to a target, the 5th within the cool-off
# erupts a geyser (blast, burning, fire for Swamp Gas), heat cools off after a pause. HOT POTATO: shots heat the gun
# (it glows), the reload key throws it only at full heat (a big blast where it lands), it is gone and cannot fire
# until it comes back; another player's copy shows the glow and the gun gone. PENGUIN RESCUE: a kill frees a penguin
# that slides into the nearest other enemy and pops there. BRAIN FREEZE: each shot drinks the cup down, the 30th gives
# brain freeze (frosted gun and screen edges, every hit freezes) until a reload refills it; another player's copy shows
# the level and the frost. AVALANCHE CONTROL: a rocket that hits the ground starts a snowball that rolls on, grows and
# buries the enemies in its path (freeze + push, once each); one that hits a wall does not.
# (CHASE_CHECK_DONE problems=n).
# Dependencies: core/gun_db.gd, core/gun_gen.gd, game/signatures/index.gd, game/unique_attach.gd.
extends Node

const GunGen = preload("res://core/gun_gen.gd")
const GunDb = preload("res://core/gun_db.gd")
const Signatures = preload("res://game/signatures/index.gd")
const UniqueAttach = preload("res://game/unique_attach.gd")
const BeachBalls = preload("res://game/beach_balls.gd")
const SwampGas = preload("res://game/swamp_gas.gd")
const LanternGlow = preload("res://game/lantern_glow.gd")


class Numbers extends Node:
	var said: Array[String] = []

	func say(_at: Vector3, words: String, _c: Color) -> void:
		said.append(words)


class Holder extends Node3D:
	var damage_numbers := Numbers.new()


class Mob extends Node3D:
	var health := HealthStub.new()
	var got := 0.0

	func head_height() -> float:
		return 1.7

	func on_hit(d: float, _p: Vector3 = Vector3.ZERO, _n: Vector3 = Vector3.UP) -> void:
		got += d


class HealthStub extends RefCounted:
	var dead := false

	func is_dead() -> bool:
		return dead


class MarkMob extends Mob:
	var vuln := 1.0

	func apply_vulnerable(m: float, _s: float) -> void:
		vuln = m


class FrogHolder extends Node3D:
	var damage_numbers := Numbers.new()
	var explosives: Node3D


class Booms extends Node3D:
	var source: Node = null
	var numbers: Node = null
	var score: RefCounted = null
	var sounds: Node = null
	var blasts: Array = []

	func blast(at: Vector3, radius: float, damage: float, _flash: bool = true) -> void:
		blasts.append([at, radius, damage])


class FireSpot extends Node3D:  # a stand-in fire pit for the gas
	var on := false

	func fire_near(point: Vector3, reach: float) -> bool:
		return on and point.distance_to(global_position) <= 1.0 + reach


class FlashBooms extends Booms:  # blasts that also burn for a moment, like game/explosives.gd's flash
	var flashes: Array = []

	func blast(at: Vector3, radius: float, damage: float, _flash: bool = true) -> void:
		blasts.append([at, radius, damage])
		flashes.append([at, radius, Time.get_ticks_msec() / 1000.0])

	func fire_near(point: Vector3, reach: float) -> bool:
		for f: Array in flashes:
			if Time.get_ticks_msec() / 1000.0 - float(f[2]) < 0.35 and point.distance_to(f[0]) <= float(f[1]) + reach:
				return true
		return false


class BurnMob extends Mob:
	signal died(enemy: Node)

	var burning := false
	var burned := 0.0

	func is_burning() -> bool:
		return burning

	func apply_burn(dps: float, _s: float) -> void:
		burned = dps


class GlowMob extends BurnMob:
	var glowing := false

	func set_glow(on: bool) -> void:
		glowing = on


class Weather extends Node:
	var left := 1.0

	func set_clear(v: float) -> void:
		left = v


class Gun extends RefCounted:
	var damage := 30.0


class LanternHolder extends Node3D:
	var explosives: Node3D
	var weapon := Gun.new()


class Hp extends RefCounted:
	var hp := 40.0
	var max_hp := 100.0

	func heal(n: float) -> void:
		hp = minf(hp + n, max_hp)


class Eater extends Node3D:
	var health := Hp.new()
	var damage_numbers := Numbers.new()


class Source extends Node:
	var list: Array = []

	func enemy_list() -> Array:
		return list


class ReloadGun extends RefCounted:
	var reloading := false

	func is_reloading() -> bool:
		return reloading


class FreezeHolder extends Node3D:
	var weapon := ReloadGun.new()
	var explosives: Node3D


class FreezeMob extends Mob:
	var frozen := 0.0
	var pushed := Vector3.ZERO

	func apply_freeze(seconds: float) -> void:
		frozen = seconds

	func push(v: Vector3) -> void:
		pushed = v


class Kicker extends Node3D:
	func aim_flat() -> Vector3:
		return Vector3(1, 0, 0)


var _lines: Array[String] = []
var _problems := 0


func _ready() -> void:
	var db := GunDb.new(_json("gun_loot"), _json("gun_parts"), _json("manufacturers"), _json("weapons"), _json("skills"), _json("gun_uniques"))
	_fish_story(db)
	await _beach_balls(db)
	await _croak(db)
	await _swamp_gas(db)
	await _lantern(db)
	await _grill(db)
	await _sauce(db)
	await _potato(db)
	await _penguin(db)
	await _brain_freeze(db)
	await _avalanche(db)
	_finish()


func _fish_story(db: GunDb) -> void:
	var gun := GunGen.unique(db, "fish_story", 12)
	_say("Fish Story builds and is legal", not gun.is_empty() and GunGen.validate(db, gun) == "")
	var holder := Holder.new()
	add_child(holder)
	var sig: Node3D = Signatures.make("fish_story")
	holder.add_child(sig)
	var model := Node3D.new()
	add_child(model)
	var piece := UniqueAttach.apply(model, gun, db)
	_say("its rod and tag model loads with a Tag marker", piece != null and piece.find_child("Tag", true, false) != null)
	sig.call("bind", holder, gun, db.uniques["fish_story"])
	sig.call("start", piece)
	var shown := float(sig.call("on_hit_total", Vector3.ZERO, 120.0, false))
	_say("a hit that is no kill shows its true number (120 -> %d) and becomes the record (%d)" % [roundi(shown), int(gun.get("record", 0))], is_equal_approx(shown, 120.0) and int(gun.get("record", 0)) == 120)
	_say("a new record boasts: damage x%.2f" % float(sig.call("damage_mult")), bool(sig.call("boasting")) and float(sig.call("damage_mult")) > 1.0)
	var label := piece.find_child("Record", true, false) as Label3D if piece != null else null
	_say("the tag reads the record (%s)" % (label.text.replace("\n", " ") if label != null else "no label"), label != null and label.text.contains("120"))
	var said_before := holder.damage_numbers.said.size()
	shown = float(sig.call("on_hit_total", Vector3.ZERO, 80.0, true))
	_say("a smaller kill is told bigger (80 -> %d) with a line (%s), record stays 120" % [roundi(shown), str(holder.damage_numbers.said.slice(said_before))], shown >= 80.0 * 1.5 - 0.01 and shown <= 80.0 * 3.0 + 0.01 and holder.damage_numbers.said.size() == said_before + 1 and int(gun["record"]) == 120)
	_say("the host accepts it with its record", GunGen.validate(db, gun) == "")
	var forged := gun.duplicate(true)
	forged["record"] = -5
	_say("a negative record is refused (%s)" % GunGen.validate(db, forged), GunGen.validate(db, forged) != "")
	var other := GunGen.unique(db, "mixtape", 12)
	other["record"] = 50
	_say("a record on any other gun is refused (%s)" % GunGen.validate(db, other), GunGen.validate(db, other) != "")
	sig.call("stop")
	_say("putting it away ends the boast", float(sig.call("damage_mult")) == 1.0)


func _beach_balls(db: GunDb) -> void:
	var gun := GunGen.unique(db, "beach_ball_bombardier", 12)
	_say("Beach Ball Bombardier builds and is legal", not gun.is_empty() and GunGen.validate(db, gun) == "")
	var model := Node3D.new()
	add_child(model)
	_say("its beach ball sits on the muzzle", UniqueAttach.apply(model, gun, db) != null)
	var cfg: Dictionary = db.uniques["beach_ball_bombardier"]["cfg"]
	var floor_body := StaticBody3D.new()  # a floor to bounce on, far from everything else
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(200, 1, 200)
	shape.shape = box
	floor_body.add_child(shape)
	floor_body.position = Vector3(1000, -0.5, 0)
	add_child(floor_body)
	var mob := Mob.new()
	mob.position = Vector3(1000, 0, 0)
	add_child(mob)
	var source := Source.new()
	source.list = [mob]
	add_child(source)
	var booms := Booms.new()
	booms.source = source
	add_child(booms)
	var balls := BeachBalls.new()
	balls.explosives = booms
	add_child(balls)
	await get_tree().physics_frame
	_say("the ball model loads (%d balls in the pool)" % balls.get_child_count(), balls.get_child_count() == BeachBalls.POOL_SIZE and ResourceLoader.exists(BeachBalls.MODEL))
	balls.launch(Vector3(1000, 3.0, 0), Vector3.DOWN, cfg, 100.0, 4.0)  # dropped onto the enemy's head
	for _i in 30:
		await get_tree().physics_frame
	_say("a ball dropped on a head hits it (%.0f damage) and springs back up" % mob.got, mob.got >= 49.0 and balls._vel[0].y > 0.0 or balls._bounces[0] >= 1)
	booms.blasts.clear()
	var popped := balls.shot_through(Vector3(990, balls._balls[0].position.y, 0), Vector3(1, 0, 0), 50.0)
	_say("shooting the ball pops it (%s, blast %s)" % [str(popped), str(booms.blasts)], popped and booms.blasts.size() == 1 and is_equal_approx(float(booms.blasts[0][2]), 120.0))
	var kicker := Kicker.new()
	kicker.position = Vector3(1010, 0, 0)
	add_child(kicker)
	balls.kicker = kicker
	balls.launch(Vector3(1010, 1.1, 0.0), Vector3(0, 0.01, 0).normalized(), cfg.merged({"speed": 0.0}, true), 100.0, 4.0)
	for _i in 30:
		await get_tree().physics_frame
	var i := 0
	for k in BeachBalls.POOL_SIZE:
		if balls._life[k] > 0.0:
			i = k
	_say("walking into a ball kicks it where you look (volleys %d, moving x %.1f m/s)" % [balls._volleys[i], balls._vel[i].x], balls._volleys[i] >= 1 and balls._vel[i].x > 3.0)
	booms.blasts.clear()
	for _i in 600:
		await get_tree().physics_frame
		if not booms.blasts.is_empty():
			break
	var expect := 120.0 * (1.0 + float(cfg["volley_bonus"]) * float(balls._volleys[i]))
	_say("a kicked ball pops in the end, bigger for its volleys (%s, expected %.0f)" % [str(booms.blasts), expect], booms.blasts.size() == 1 and is_equal_approx(float(booms.blasts[0][2]), expect))
	_say("no ball left flying", balls.active_count() == 0)


func _croak(db: GunDb) -> void:
	var gun := GunGen.unique(db, "croak", 20)
	_say("Croak builds and is legal", not gun.is_empty() and GunGen.validate(db, gun) == "")
	var model := Node3D.new()
	add_child(model)
	var piece := UniqueAttach.apply(model, gun, db)
	_say("its frog sits on the scope with eyelids that blink", piece != null and piece.find_child("Lids", true, false) != null and ResourceLoader.exists("res://assets/models/weapons/uniques/croak_frog.gltf"))
	var holder := FrogHolder.new()
	holder.position = Vector3(2000, 0, 0)
	add_child(holder)
	var booms := Booms.new()
	var source := Source.new()
	add_child(source)
	booms.source = source
	holder.explosives = booms
	add_child(booms)
	var near_mob := MarkMob.new()
	near_mob.position = Vector3(2004, 0, 0)
	var far_mob := MarkMob.new()
	far_mob.position = Vector3(2030, 0, 0)
	add_child(near_mob)
	add_child(far_mob)
	source.list = [far_mob, near_mob]
	var sig: Node3D = Signatures.make("croak")
	holder.add_child(sig)
	sig.call("bind", holder, gun, db.uniques["croak"])
	sig.call("start", piece)
	_say("while the frog rides on the gun: one air jump", int(sig.call("extra_jumps")) == 1)
	for n in 4:
		sig.call("on_hit_total", Vector3(2003, 1, 0), 50.0, true)
	_say("four kills: it stays on the gun", int(sig.call("frog_state")) == 0)
	sig.call("on_hit_total", Vector3(2003, 1, 0), 50.0, true)
	for _i in 40:  # by time, not frames: his PC draws hundreds of frames a second
		await get_tree().create_timer(0.05).timeout
		if int(sig.call("frog_state")) == 2:
			break
	await get_tree().create_timer(0.1).timeout
	_say("the 5th kill: it leaps onto the NEAREST enemy's head and marks it (x%.2f), no air jump while away" % near_mob.vuln, sig.call("marked") == near_mob and is_equal_approx(near_mob.vuln, 1.3) and is_equal_approx(far_mob.vuln, 1.0) and int(sig.call("extra_jumps")) == 0 and piece.visible == false)
	near_mob.health.dead = true
	await get_tree().create_timer(1.2).timeout
	_say("its enemy dies: the frog hops back on the gun and the air jump returns", int(sig.call("frog_state")) == 0 and int(sig.call("extra_jumps")) == 1 and piece.visible)
	sig.call("stop")


func _swamp_gas(db: GunDb) -> void:
	var gun := GunGen.unique(db, "swamp_gas", 20)
	_say("Swamp Gas builds and is legal", not gun.is_empty() and GunGen.validate(db, gun) == "")
	var model := Node3D.new()
	add_child(model)
	var piece := UniqueAttach.apply(model, gun, db)
	_say("its jar sits on the shotgun with bubbles", piece != null and piece.find_child("Bubbles", true, false) != null)
	var cfg: Dictionary = db.uniques["swamp_gas"]["cfg"]
	var source := Source.new()
	add_child(source)
	var booms := FlashBooms.new()
	booms.source = source
	add_child(booms)
	booms.add_to_group("fire_sources")
	var gas := SwampGas.new()
	gas.explosives = booms
	add_child(gas)
	await get_tree().process_frame
	gas.puff(Vector3(3000, 1, 0), cfg, 40.0)
	gas.puff(Vector3(3003, 1, 0), cfg, 40.0)
	gas.puff(Vector3(3030, 1, 0), cfg, 40.0)
	await get_tree().create_timer(0.3).timeout
	_say("three clouds hang there, nothing goes off without fire", gas.active_count() == 3 and booms.blasts.is_empty())
	var pit := FireSpot.new()
	pit.position = Vector3(2999, 0, 0)
	add_child(pit)
	pit.add_to_group("fire_sources")
	pit.on = true
	await get_tree().create_timer(0.8).timeout
	pit.on = false
	_say("fire beside the first cloud sets it off, its blast sets off the second (%d blasts of %.0f), the far one waits" % [booms.blasts.size(), float(booms.blasts[0][2]) if not booms.blasts.is_empty() else 0.0], booms.blasts.size() == 2 and gas.active_count() == 1 and is_equal_approx(float(booms.blasts[0][2]), 100.0))
	var mob := BurnMob.new()
	mob.position = Vector3(3030, 0.5, 0)
	add_child(mob)
	source.list = [mob]
	mob.burning = true
	await get_tree().create_timer(0.5).timeout
	_say("a burning enemy in the last cloud sets it off, and the blast sets it burning (%.0f a second)" % mob.burned, booms.blasts.size() == 3 and gas.active_count() == 0 and mob.burned > 0.0)
	pit.remove_from_group("fire_sources")
	booms.remove_from_group("fire_sources")


func _lantern(db: GunDb) -> void:
	var gun := GunGen.unique(db, "keepers_lantern", 20)
	_say("Keeper's Lantern builds and is legal", not gun.is_empty() and GunGen.validate(db, gun) == "")
	var holder := LanternHolder.new()
	holder.position = Vector3(4000, 0, 0)
	add_child(holder)
	var model := Node3D.new()
	holder.add_child(model)
	model.position = Vector3(0, 1.4, 0)
	var piece := UniqueAttach.apply(model, gun, db)
	var flame := piece.find_child("Flame", true, false) if piece != null else null
	_say("its lantern hangs under the barrel with a lit flame and a small light", piece != null and piece.find_child("Swing", true, false) != null and flame != null and not flame.find_children("*", "OmniLight3D", true, false).is_empty() and piece.is_in_group("lanterns"))
	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(100, 1, 100)
	shape.shape = box
	floor_body.add_child(shape)
	floor_body.position = Vector3(4000, -0.5, 0)
	add_child(floor_body)
	var source := Source.new()
	add_child(source)
	var booms := FlashBooms.new()
	booms.source = source
	add_child(booms)
	booms.add_to_group("fire_sources")
	holder.explosives = booms
	var near_mob := GlowMob.new()
	near_mob.position = Vector3(4003, 0, 0)
	var far_mob := GlowMob.new()
	far_mob.position = Vector3(4040, 0, 0)
	add_child(near_mob)
	add_child(far_mob)
	source.list = [near_mob, far_mob]
	var weather := Weather.new()
	add_child(weather)
	weather.add_to_group("island_weather")
	var def: Dictionary = (db.uniques["keepers_lantern"] as Dictionary).duplicate(true)
	(def["cfg"] as Dictionary)["relight_seconds"] = 1.0
	var sig: Node3D = Signatures.make("keepers_lantern")
	holder.add_child(sig)
	sig.call("bind", holder, gun, def)
	sig.call("start", piece)
	await get_tree().create_timer(0.5).timeout
	_say("lit: the near enemy glows (%s), the far one not (%s)" % [str(near_mob.glowing), str(far_mob.glowing)], near_mob.glowing and not far_mob.glowing)
	booms.blasts.clear()
	holder.rotation.y = PI * 0.5  # throws toward -x... any way: the floor catches it
	sig.call("on_inspect")
	_say("the inspect key throws it: the lantern is gone from the gun, others see \"out\"", String(sig.call("held_suffix")) == "out" and not (piece.find_child("Swing", true, false) as Node3D).visible)
	var bomb: Node = null
	for _i in 60:
		await get_tree().create_timer(0.05).timeout
		for n: Node in get_tree().get_nodes_in_group("fire_sources"):
			if n.get_script() != null and String(n.get_script().resource_path).ends_with("firebomb.gd") and float(n.get("_burning")) > 0.0:
				bomb = n
		if bomb != null:
			break
	_say("it smashes in a blast (%s) and leaves burning oil that counts as fire" % str(booms.blasts), bomb != null and booms.blasts.size() >= 1 and bool(bomb.call("fire_near", (bomb as Node3D).global_position, 0.5)))
	await get_tree().create_timer(1.3).timeout
	_say("a new lantern is lit after its wait", String(sig.call("held_suffix")) == "" and (piece.find_child("Swing", true, false) as Node3D).visible)
	booms.remove_from_group("fire_sources")
	weather.remove_from_group("island_weather")


func _grill(db: GunDb) -> void:
	var gun := GunGen.unique(db, "grillmaster", 30)
	_say("Grillmaster builds and is legal", not gun.is_empty() and GunGen.validate(db, gun) == "")
	var model := Node3D.new()
	add_child(model)
	_say("its grill plate is on the shotgun, the kebab model loads", UniqueAttach.apply(model, gun, db) != null and ResourceLoader.exists("res://assets/models/weapons/uniques/grilled_kebab.gltf"))
	var eater := Eater.new()
	eater.position = Vector3(5000, 0, 0)
	add_child(eater)
	var sig: Node3D = Signatures.make("grillmaster")
	eater.add_child(sig)
	sig.call("bind", eater, gun, db.uniques["grillmaster"])
	sig.call("start", null)
	var plain := BurnMob.new()
	plain.position = Vector3(5010, 0, 0)
	add_child(plain)
	plain.health.dead = true
	sig.call("on_target_hit", plain, plain.position, 80.0, true)
	var food: Node = get_tree().get_first_node_in_group("grill_food")
	_say("a plain kill drops nothing", food != null and int(food.call("active_count")) == 0)
	var burnt := BurnMob.new()
	burnt.position = Vector3(5010, 0, 0)
	burnt.burning = true
	add_child(burnt)
	burnt.health.dead = true
	sig.call("on_target_hit", burnt, burnt.position, 80.0, true)
	await get_tree().process_frame
	_say("a burning kill drops grilled food", int(food.call("active_count")) == 1)
	eater.position = Vector3(5010.5, 0, 0)
	for _i in 10:
		await get_tree().process_frame
	_say("walking over it eats it: health %.0f -> %.0f (a quarter of max)" % [40.0, eater.health.hp], int(food.call("active_count")) == 0 and is_equal_approx(eater.health.hp, 65.0))
	var later := BurnMob.new()
	later.position = Vector3(5020, 0, 0)
	later.burning = true
	add_child(later)
	sig.call("on_target_hit", later, later.position, 20.0, false)
	await get_tree().process_frame
	var before := int(food.call("active_count"))
	later.health.dead = true
	later.died.emit(later)  # it burns to death after the shot
	await get_tree().process_frame
	_say("an enemy it hit that burns to death later drops food too (%d -> %d)" % [before, int(food.call("active_count"))], before == 0 and int(food.call("active_count")) == 1)


func _sauce(db: GunDb) -> void:
	var gun := GunGen.unique(db, "volcano_sauce", 30)
	_say("Volcano Sauce builds and is legal", not gun.is_empty() and GunGen.validate(db, gun) == "")
	var model := Node3D.new()
	add_child(model)
	_say("its sauce bottle is taped to the grip", UniqueAttach.apply(model, gun, db) != null)
	var source := Source.new()
	add_child(source)
	var booms := FlashBooms.new()
	booms.source = source
	add_child(booms)
	var holder := LanternHolder.new()  # (has explosives, weapon damage 30)
	holder.position = Vector3(6000, 0, 0)
	holder.explosives = booms
	add_child(holder)
	var mob := BurnMob.new()
	mob.position = Vector3(6005, 0, 0)
	add_child(mob)
	source.list = [mob]
	var sig: Node3D = Signatures.make("volcano_sauce")
	holder.add_child(sig)
	sig.call("bind", holder, gun, db.uniques["volcano_sauce"])
	for n in 4:
		sig.call("on_target_hit", mob, mob.position, 20.0, false)
	_say("four hits: heat 4, no eruption", int(mob.get_meta("sauce_heat")) == 4 and booms.blasts.is_empty())
	sig.call("on_target_hit", mob, mob.position, 20.0, false)
	await get_tree().process_frame
	var geyser: Node = null
	for n: Node in get_tree().get_nodes_in_group("fire_sources"):
		if n.get_script() != null and String(n.get_script().resource_path).ends_with("fire_geyser.gd"):
			geyser = n
	_say("the 5th erupts: blast %s, the enemy burns, the geyser is fire" % str(booms.blasts), booms.blasts.size() == 1 and is_equal_approx(float(booms.blasts[0][2]), 180.0) and mob.burned > 0.0 and geyser != null and bool(geyser.call("fire_near", mob.position, 0.5)) and int(mob.get_meta("sauce_heat")) == 0)
	sig.call("on_target_hit", mob, mob.position, 20.0, false)
	mob.set_meta("sauce_at", Time.get_ticks_msec() / 1000.0 - 10.0)  # a long pause
	sig.call("on_target_hit", mob, mob.position, 20.0, false)
	_say("after a pause the heat has cooled (back to 1)", int(mob.get_meta("sauce_heat")) == 1)


func _potato(db: GunDb) -> void:
	var gun := GunGen.unique(db, "hot_potato", 30)
	_say("Hot Potato builds and is legal", not gun.is_empty() and GunGen.validate(db, gun) == "")
	var source := Source.new()
	add_child(source)
	var booms := FlashBooms.new()
	booms.source = source
	add_child(booms)
	var holder := LanternHolder.new()
	holder.position = Vector3(7000, 0, 0)
	holder.explosives = booms
	add_child(holder)
	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(100, 1, 100)
	shape.shape = box
	floor_body.add_child(shape)
	floor_body.position = Vector3(7000, -0.5, 0)
	add_child(floor_body)
	var model := Node3D.new()
	model.position = Vector3(0, 1.4, 0)
	holder.add_child(model)
	var piece := UniqueAttach.apply(model, gun, db)
	_say("its foil potato is strapped on", piece != null)
	var def: Dictionary = (db.uniques["hot_potato"] as Dictionary).duplicate(true)
	(def["cfg"] as Dictionary)["back_seconds"] = 0.8
	var sig: Node3D = Signatures.make("hot_potato")
	holder.add_child(sig)
	sig.call("bind", holder, gun, def)
	sig.call("start", piece)
	for _n in 4:
		sig.call("on_fired")
	_say("half hot after 4 shots: the reload key reloads as usual", not bool(sig.call("on_reload")) and is_equal_approx(float(sig.call("heat")), 0.5))
	for _n in 4:
		sig.call("on_fired")
	await get_tree().process_frame
	var glow: Variant = (model.find_children("*", "GeometryInstance3D", true, false)[0] as GeometryInstance3D).material_overlay
	_say("full heat after 8 shots: the gun glows (%s)" % String(sig.call("held_suffix")), glow != null and String(sig.call("held_suffix")) == "h9")
	booms.blasts.clear()
	_say("at full heat the reload key throws it: gone from the hands, cannot fire, others see \"out\"", bool(sig.call("on_reload")) and bool(sig.call("blocks_fire")) and String(sig.call("held_suffix")) == "out")
	await get_tree().process_frame
	_say("the gun model is hidden while it is away", not model.visible)
	for _i in 40:
		await get_tree().create_timer(0.05).timeout
		if not booms.blasts.is_empty():
			break
	_say("it lands in a big blast %s" % str(booms.blasts), booms.blasts.size() == 1 and is_equal_approx(float(booms.blasts[0][1]), 6.0) and is_equal_approx(float(booms.blasts[0][2]), 240.0))
	await get_tree().create_timer(0.8).timeout
	_say("back in the hands, cooled", model.visible and not bool(sig.call("blocks_fire")) and String(sig.call("held_suffix")) == "h0")
	var copy := Node3D.new()
	add_child(copy)
	var copy_piece := UniqueAttach.apply_id(copy, "hot_potato")
	UniqueAttach.show_extra(copy_piece, "hot_potato", "h9")
	var copy_glow: Variant = (copy.find_children("*", "GeometryInstance3D", true, false)[0] as GeometryInstance3D).material_overlay
	UniqueAttach.show_extra(copy_piece, "hot_potato", "out")
	_say("another player's copy: glows at h9, hidden at out", copy_glow != null and not copy.visible)
	sig.call("stop")


func _penguin(db: GunDb) -> void:
	var gun := GunGen.unique(db, "penguin_rescue", 35)
	_say("Penguin Rescue builds and is legal", not gun.is_empty() and GunGen.validate(db, gun) == "")
	var model := Node3D.new()
	add_child(model)
	_say("its penguin rides on the slide, the freed penguin model loads", UniqueAttach.apply(model, gun, db) != null and ResourceLoader.exists("res://assets/models/weapons/uniques/penguin.gltf"))
	var source := Source.new()
	add_child(source)
	var booms := FlashBooms.new()
	booms.source = source
	add_child(booms)
	var holder := LanternHolder.new()
	holder.position = Vector3(8000, 0, 0)
	holder.explosives = booms
	add_child(holder)
	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(100, 1, 100)
	shape.shape = box
	floor_body.add_child(shape)
	floor_body.position = Vector3(8000, -0.5, 0)
	add_child(floor_body)
	var dead := BurnMob.new()
	dead.position = Vector3(8008, 0, 0)
	add_child(dead)
	dead.health.dead = true
	var next := BurnMob.new()
	next.position = Vector3(8008, 0, 8)
	add_child(next)
	source.list = [dead, next]
	var sig: Node3D = Signatures.make("penguin_rescue")
	holder.add_child(sig)
	sig.call("bind", holder, gun, db.uniques["penguin_rescue"])
	sig.call("on_target_hit", dead, dead.position, 50.0, true)
	for _i in 60:
		await get_tree().create_timer(0.05).timeout
		if not booms.blasts.is_empty():
			break
	var at: Vector3 = booms.blasts[0][0] if not booms.blasts.is_empty() else Vector3.INF
	_say("the kill frees a penguin that slides into the next enemy and pops there (%s)" % str(booms.blasts), booms.blasts.size() == 1 and at.distance_to(next.position) < 1.6 and is_equal_approx(float(booms.blasts[0][2]), 90.0))


func _brain_freeze(db: GunDb) -> void:
	var gun := GunGen.unique(db, "brain_freeze", 40)
	_say("Brain Freeze builds and is legal", not gun.is_empty() and GunGen.validate(db, gun) == "")
	var holder := FreezeHolder.new()
	add_child(holder)
	var model := Node3D.new()
	holder.add_child(model)
	var piece := UniqueAttach.apply(model, gun, db)
	var slush := piece.find_child("Slush", true, false) as Node3D if piece != null else null
	_say("its slushie cup is taped on, slush inside", slush != null)
	var sig: Node3D = Signatures.make("brain_freeze")
	holder.add_child(sig)
	sig.call("bind", holder, gun, db.uniques["brain_freeze"])
	sig.call("start", piece)
	var mob := FreezeMob.new()
	add_child(mob)
	for _n in 29:
		sig.call("on_fired")
	sig.call("on_target_hit", mob, Vector3.ZERO, 10.0, false)
	_say("29 sips: the cup is nearly empty (%s), no brain freeze, hits do not freeze" % String(sig.call("held_suffix")), String(sig.call("held_suffix")) == "c1" and slush.scale.y < 0.1 and is_zero_approx(mob.frozen))
	sig.call("on_fired")
	await get_tree().process_frame
	var overlay: Variant = (model.find_children("*", "GeometryInstance3D", true, false)[0] as GeometryInstance3D).material_overlay
	var frost_layer := sig.find_children("*", "CanvasLayer", true, false)
	_say("the 30th: brain freeze, cup empty, gun frosted, screen frost made, others see \"bf\"", bool(sig.call("frozen")) and not slush.visible and overlay != null and frost_layer.size() == 1 and String(sig.call("held_suffix")) == "bf")
	sig.call("on_target_hit", mob, Vector3.ZERO, 10.0, false)
	_say("now every hit freezes for 3 s (%.1f)" % mob.frozen, is_equal_approx(mob.frozen, 3.0))
	holder.weapon.reloading = true
	await get_tree().process_frame
	holder.weapon.reloading = false
	var overlay2: Variant = (model.find_children("*", "GeometryInstance3D", true, false)[0] as GeometryInstance3D).material_overlay
	_say("a reload refills the cup and thaws the gun (%s)" % String(sig.call("held_suffix")), not bool(sig.call("frozen")) and String(sig.call("held_suffix")) == "c9" and slush.visible and is_equal_approx(slush.scale.y, 1.0) and overlay2 == null)
	var copy := Node3D.new()
	add_child(copy)
	var copy_piece := UniqueAttach.apply_id(copy, "brain_freeze")
	UniqueAttach.show_extra(copy_piece, "brain_freeze", "c4")
	var half := (copy_piece.find_child("Slush", true, false) as Node3D).scale.y
	UniqueAttach.show_extra(copy_piece, "brain_freeze", "bf")
	var copy_frost: Variant = (copy.find_children("*", "GeometryInstance3D", true, false)[0] as GeometryInstance3D).material_overlay
	_say("another player's copy: half a cup at c4 (%.2f), empty and frosted at bf" % half, absf(half - 4.0 / 9.0) < 0.01 and not (copy_piece.find_child("Slush", true, false) as Node3D).visible and copy_frost != null)
	sig.call("stop")


func _avalanche(db: GunDb) -> void:
	var gun := GunGen.unique(db, "avalanche_control", 40)
	_say("Avalanche Control builds and is legal", not gun.is_empty() and GunGen.validate(db, gun) == "")
	var model := Node3D.new()
	add_child(model)
	_say("its ski pole is strapped on, the snowball model loads", UniqueAttach.apply(model, gun, db) != null and ResourceLoader.exists("res://assets/models/weapons/uniques/snowball.gltf"))
	var source := Source.new()
	add_child(source)
	var booms: Node3D = (load("res://game/explosives.gd") as GDScript).new()
	booms.set("source", source)
	add_child(booms)
	var holder := FreezeHolder.new()
	holder.position = Vector3(9000, 0, 0)
	holder.explosives = booms
	add_child(holder)
	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(100, 1, 100)
	shape.shape = box
	floor_body.add_child(shape)
	floor_body.position = Vector3(9000, -0.5, 0)
	add_child(floor_body)
	var wall := StaticBody3D.new()
	var wall_shape := CollisionShape3D.new()
	var wall_box := BoxShape3D.new()
	wall_box.size = Vector3(1, 10, 10)
	wall_shape.shape = wall_box
	wall.add_child(wall_shape)
	wall.position = Vector3(9010, 5, -20)
	add_child(wall)
	var near := FreezeMob.new()
	near.position = Vector3(9000, 0, 11)
	add_child(near)
	var far := FreezeMob.new()
	far.position = Vector3(9006, 0, 14)
	add_child(far)
	source.list = [near, far]
	var sig: Node3D = Signatures.make("avalanche_control")
	holder.add_child(sig)
	sig.call("bind", holder, gun, db.uniques["avalanche_control"])
	var stats := {"kind": "rocket", "speed": 40.0, "gravity": 0.0, "splash_radius": 2.0, "splash_damage": 200.0}
	sig.call("fire_projectile", Vector3(9000, 3, 0), Vector3(0, -0.5, 1).normalized(), stats)
	for _i in 60:
		await get_tree().create_timer(0.05).timeout
		if near.frozen > 0.0:
			break
	_say("the rocket hits the ground: a snowball starts (%d) and rolls on" % int(sig.get("started")), int(sig.get("started")) == 1 and get_tree().get_nodes_in_group("snowballs").size() == 1)
	_say("it buries the enemy in its path: hit, frozen 2 s, pushed along its way (%s, %.0f)" % [str(near.pushed), near.got], is_equal_approx(near.frozen, 2.0) and near.pushed.z > 7.0 and is_equal_approx(near.got, 50.0))
	_say("not the one off its path", is_zero_approx(far.frozen))
	sig.call("fire_projectile", Vector3(9005, 3, -10), Vector3(1, 0, -2).normalized(), stats)
	await get_tree().create_timer(0.8).timeout
	_say("a rocket into a wall starts no snowball", int(sig.get("started")) == 1)
	await get_tree().create_timer(4.0).timeout
	_say("the snowball breaks up when its time is out", get_tree().get_nodes_in_group("snowballs").is_empty())


func _json(name: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://data/%s.json" % name))


func _say(text: String, ok: bool) -> void:
	_lines.append(("ok   " if ok else "FAIL ") + text)
	if not ok:
		_problems += 1


func _finish() -> void:
	_lines.append("CHASE_CHECK_DONE problems=%d" % _problems)
	var f := FileAccess.open("res://tools/chase_check.log", FileAccess.WRITE)
	f.store_string("\n".join(_lines) + "\n")
	f.close()
	print("\n".join(_lines))
	get_tree().quit()
