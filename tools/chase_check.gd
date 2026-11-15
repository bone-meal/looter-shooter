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
# buries the enemies in its path (freeze + push, once each); one that hits a wall does not. WEATHERVANE: damage
# follows the wind, its rooster turns into the wind, in a storm a hit calls a bolt (once per wait). KITE FLYER: the kite
# flies above, a lightning flash makes it dive onto the nearest enemy (blast), a teammate's copy tows a player who
# touches its string in the air. CHIP THIEF: gulls circle, a kill sends one pecking at the next enemy, the inspect key
# sends every idle gull (then waits); other players' copies get the kite and the flock. CLAM SHELL: opens to fire,
# the reload key bites what is in front, a grown pearl pierces enemies in a line. ANGLER LIGHT: the lure glows and
# lights, enemies in reach drift toward it. FLUSH: a grenade opens a whirlpool that swirls enemies and flushes the weak.
# SPAGHETTI: a held scope charges the next shot (x2), which stretches and pulls the enemies near its line.
# LIGHTHOUSE IN A BOTTLE: the beam sweeps, burns enemies it passes; another player's copy heals the local player.
# CARBON COPY: every shot prints a paper copy that fires once and falls over. TIME CARD: inspect clocks in, pay grows
# with time unhit, a hit docks it. LOAN SHARK: an empty magazine borrows a round for health, the shark grows, kills pay
# back. WANTED POSTER: an enemy is marked, killing it pays chips and refreshes skills. KEY RING: kills add keys, enough
# keys open something locked, the jingle draws enemies. TREASURE MAP: an X appears on the ground, inspect on it digs up
# a gun. GOLDEN GOOSE: it honks enemies over, its eggs hatch into a blast and chips. SPLIT DECISION: fire then ice on one
# enemy shatters it, the coin shows the next shot. MESSAGE IN A BOTTLE: kills reveal shanty lines, a verse buffs.
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


class WindStub extends Node:
	var blow := 0.0
	var toward := 1.0
	var storm := false

	func wind() -> float:
		return blow

	func wind_yaw() -> float:
		return toward

	func storming() -> bool:
		return storm


class GunHolder extends Node3D:
	var weapon := Gun.new()
	var explosives: Node3D
	var damage_numbers := Numbers.new()


class TowMe extends Node3D:
	var tow_point := Vector3.INF

	func is_on_floor() -> bool:
		return false


class HpHealth extends RefCounted:
	var hp := 100.0
	var max_hp := 100.0

	func is_dead() -> bool:
		return hp <= 0.0


class HpMob extends Node3D:
	var health := HpHealth.new()
	var pushed := Vector3.ZERO
	var enemy_id := "chaser"

	func head_height() -> float:
		return 1.7

	func on_hit(d: float, _p: Vector3 = Vector3.ZERO, _n: Vector3 = Vector3.UP) -> void:
		health.hp -= d

	func push(v: Vector3) -> void:
		pushed = v


class BodyMob extends StaticBody3D:
	var health := HealthStub.new()
	var got := 0.0

	func _init() -> void:
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(0.8, 2.0, 0.8)
		shape.shape = box
		shape.position.y = 1.0
		add_child(shape)
		collision_layer = 2

	func on_hit(d: float, _p: Vector3 = Vector3.ZERO, _n: Vector3 = Vector3.UP) -> void:
		got += d


class ScopeHolder extends GunHolder:
	func scope_amount() -> float:
		return 1.0


class DamHolder extends GunHolder:
	signal damaged


class AmmoGun extends RefCounted:
	var damage := 30.0
	var ammo := 5


class SharkHolder extends Node3D:
	var weapon := AmmoGun.new()
	var health := Hp.new()


class WalletStub extends RefCounted:
	var balance := 0

	func add(n: int) -> void:
		balance += n


class SessionStub extends Node:
	var purse := WalletStub.new()

	func wallet() -> WalletStub:
		return purse


class SkillsStub extends RefCounted:
	var refreshed := 0

	func reduce_all(_s: float, _now: float) -> void:
		refreshed += 1


class PosterHolder extends GunHolder:
	var skills := SkillsStub.new()


class Locked extends Node3D:
	var open := false

	func _ready() -> void:
		add_to_group("locked")

	func on_hit(_d: float, _p: Vector3 = Vector3.ZERO, _n: Vector3 = Vector3.UP) -> void:
		pass

	func unlock() -> void:
		open = true


class LureMob extends Mob:
	var chasing: Node3D

	func set_target(t: Node3D) -> void:
		chasing = t


class FieldStub extends Node:
	var spawned := 0

	func spawn(_gun: Dictionary, _at: Vector3, _shared: int = 0) -> void:
		spawned += 1


class MapSession extends SessionStub:
	var _field := FieldStub.new()


class MapHolder extends GunHolder:
	var gun_db: RefCounted


class SplitMob extends Mob:
	var burning := 0.0
	var slowed := 0.0

	func apply_burn(dps: float, _s: float) -> void:
		burning = dps

	func apply_slow(amount: float, _s: float) -> void:
		slowed = amount


class ClipFx extends RefCounted:
	var clips := 0

	func start_clip(_now: float, _s: float, _pct: float) -> void:
		clips += 1


class BottleHolder extends GunHolder:
	var self_fx := ClipFx.new()


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
	await _weathervane(db)
	await _kite(db)
	await _chips(db)
	await _clam(db)
	await _angler(db)
	await _flush(db)
	await _spaghetti(db)
	await _lighthouse(db)
	await _carbon(db)
	await _time_card(db)
	_loan_shark(db)
	await _wanted(db)
	_key_ring(db)
	await _treasure(db)
	await _goose(db)
	_split(db)
	_bottle(db)
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


func _weathervane(db: GunDb) -> void:
	var gun := GunGen.unique(db, "weathervane", 45)
	_say("Weathervane builds and is legal", not gun.is_empty() and GunGen.validate(db, gun) == "")
	var weather := WindStub.new()
	weather.add_to_group("island_weather")
	add_child(weather)
	var holder := GunHolder.new()
	add_child(holder)
	var model := Node3D.new()
	holder.add_child(model)
	var piece := UniqueAttach.apply(model, gun, db)
	var rooster := piece.find_child("Rooster", true, false) as Node3D if piece != null else null
	_say("its weathervane sits on the scope with a rooster", rooster != null)
	await get_tree().create_timer(1.5).timeout
	_say("the rooster turns into the wind (%.2f)" % rooster.rotation.y, absf(rooster.rotation.y) > 0.5)
	var sig: Node3D = Signatures.make("weathervane")
	holder.add_child(sig)
	sig.call("bind", holder, gun, db.uniques["weathervane"])
	weather.blow = 0.0
	var calm := float(sig.call("damage_mult"))
	weather.blow = 1.0
	_say("damage follows the wind: %.2f calm, %.2f gale" % [calm, float(sig.call("damage_mult"))], is_equal_approx(calm, 0.8) and is_equal_approx(float(sig.call("damage_mult")), 1.6))
	var mob := Mob.new()
	add_child(mob)
	sig.call("on_target_hit", mob, Vector3.ZERO, 10.0, false)
	_say("no storm: no lightning", is_zero_approx(mob.got) and int(sig.get("bolts")) == 0)
	weather.storm = true
	sig.call("on_target_hit", mob, Vector3.ZERO, 10.0, false)
	sig.call("on_target_hit", mob, Vector3.ZERO, 10.0, false)
	_say("in a storm a hit calls a bolt down on it (%.0f), the next waits" % mob.got, is_equal_approx(mob.got, 120.0) and int(sig.get("bolts")) == 1)
	weather.storm = false
	for _n in 8:
		sig.call("on_target_hit", Mob.new(), Vector3.ZERO, 10.0, true)
	var calm_mob := Mob.new()
	add_child(calm_mob)
	sig.call("on_target_hit", calm_mob, Vector3.ZERO, 10.0, false)
	sig.call("on_target_hit", calm_mob, Vector3.ZERO, 10.0, false)
	_say("no storm, but 8 kills store a bolt: the next hit calls it, once (%.0f)" % calm_mob.got, is_equal_approx(calm_mob.got, 120.0) and int(sig.get("bolts")) == 2 and not bool(sig.call("charged")))
	weather.queue_free()


func _kite(db: GunDb) -> void:
	var gun := GunGen.unique(db, "kite_flyer", 45)
	_say("Kite Flyer builds and is legal", not gun.is_empty() and GunGen.validate(db, gun) == "")
	var source := Source.new()
	add_child(source)
	var booms := FlashBooms.new()
	booms.source = source
	add_child(booms)
	var holder := GunHolder.new()
	holder.position = Vector3(9500, 0, 0)
	holder.explosives = booms
	add_child(holder)
	var model := Node3D.new()
	model.position = Vector3(0, 1.4, 0)
	holder.add_child(model)
	var piece := UniqueAttach.apply(model, gun, db)
	_say("its reel is bolted on with a string marker", piece != null and piece.find_child("Line", true, false) != null)
	var sig: Node3D = Signatures.make("kite_flyer")
	holder.add_child(sig)
	sig.call("bind", holder, gun, db.uniques["kite_flyer"])
	sig.call("start", piece)
	await get_tree().create_timer(1.0).timeout
	var kite: Node3D = sig.call("kite")
	_say("the kite flies high above the holder (%.1f m up)" % (kite.global_position.y - holder.global_position.y), kite != null and kite.global_position.y - holder.global_position.y > 4.0)
	var mob := Mob.new()
	mob.position = Vector3(9510, 0, 5)
	add_child(mob)
	source.list = [mob]
	sig.call("catch_lightning")
	await get_tree().create_timer(0.8).timeout
	var at: Vector3 = booms.blasts[0][0] if not booms.blasts.is_empty() else Vector3.INF
	_say("a lightning flash: it dives onto the enemy and the bolt goes off there (%s)" % str(booms.blasts), booms.blasts.size() == 1 and at.distance_to(mob.position) < 1.6 and is_equal_approx(float(booms.blasts[0][2]), 180.0))
	await get_tree().create_timer(2.2).timeout
	for _n in 8:
		sig.call("on_target_hit", Node.new(), Vector3.ZERO, 10.0, true)
	_say("without a storm, every 8 kills it catches a bolt too (%d caught)" % int(sig.get("caught")), int(sig.get("caught")) == 2)
	var other := Node3D.new()
	other.position = Vector3(9600, 0, 0)
	add_child(other)
	var copy_piece := UniqueAttach.apply_id(other, "kite_flyer")
	await get_tree().create_timer(1.0).timeout
	var copy_kite: Node3D = null
	for n: Node in copy_piece.get_children():
		if n.is_in_group("kites"):
			copy_kite = n
	var me := TowMe.new()
	add_child(me)
	if copy_kite != null:
		copy_kite.set("local_player", me)
		var a: Vector3 = (copy_piece.find_child("Line", true, false) as Node3D).global_position
		me.global_position = a.lerp(copy_kite.global_position, 0.5) - Vector3(0, 1.0, 0)
	await get_tree().create_timer(0.2).timeout
	_say("another player's copy flies a kite; touching its string in the air tows you (%s)" % str(me.tow_point), copy_kite != null and bool(copy_kite.call("towing")) and me.tow_point.is_finite())
	other.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	_say("his gun gone: you let go", not me.tow_point.is_finite())
	sig.call("stop")


func _chips(db: GunDb) -> void:
	var gun := GunGen.unique(db, "chip_thief", 45)
	_say("Chip Thief builds and is legal", not gun.is_empty() and GunGen.validate(db, gun) == "")
	var source := Source.new()
	add_child(source)
	var booms := FlashBooms.new()
	booms.source = source
	add_child(booms)
	var holder := GunHolder.new()
	holder.position = Vector3(9800, 0, 0)
	holder.explosives = booms
	add_child(holder)
	var model := Node3D.new()
	model.position = Vector3(0, 1.4, 0)
	holder.add_child(model)
	var piece := UniqueAttach.apply(model, gun, db)
	_say("its chip bag is taped on, the gull model loads", piece != null and ResourceLoader.exists("res://assets/models/weapons/uniques/gull.gltf"))
	var sig: Node3D = Signatures.make("chip_thief")
	holder.add_child(sig)
	sig.call("bind", holder, gun, db.uniques["chip_thief"])
	sig.call("start", piece)
	await get_tree().process_frame
	var flock: Node3D = sig.call("flock")
	_say("four gulls circle the holder", flock != null and int(flock.call("idle_count")) == 4)
	var dead := Mob.new()
	dead.position = Vector3(9805, 0, 0)
	add_child(dead)
	dead.health.dead = true
	var next := Mob.new()
	next.position = Vector3(9808, 0, 4)
	add_child(next)
	var third := Mob.new()
	third.position = Vector3(9795, 0, -3)
	add_child(third)
	source.list = [dead, next, third]
	sig.call("on_target_hit", dead, dead.position, 50.0, true)
	_say("a kill sends a gull at the next enemy", int(sig.get("sent")) == 1 and int(flock.call("idle_count")) == 3)
	await get_tree().create_timer(2.6).timeout
	_say("it pecks 4 times (%.0f)" % next.got, is_equal_approx(next.got, 60.0))
	sig.call("on_inspect")
	var after_bag := int(sig.get("sent"))
	sig.call("on_inspect")
	_say("the inspect key opens the bag: the idle gulls dive at the enemies (%d), then it waits" % after_bag, after_bag == 3 and int(sig.get("sent")) == 3)
	var copy := Node3D.new()
	add_child(copy)
	var copy_piece := UniqueAttach.apply_id(copy, "chip_thief")
	var copy_flock := false
	for n: Node in copy_piece.get_children():
		copy_flock = copy_flock or n.is_in_group("gull_flocks")
	_say("another player's copy has its own circling flock", copy_flock)
	sig.call("stop")


func _clam(db: GunDb) -> void:
	var gun := GunGen.unique(db, "clam_shell", 50)
	_say("Clam Shell builds and is legal", not gun.is_empty() and GunGen.validate(db, gun) == "")
	var source := Source.new()
	add_child(source)
	var booms := FlashBooms.new()
	booms.source = source
	add_child(booms)
	var holder := GunHolder.new()
	holder.position = Vector3(10000, 0, 0)
	holder.explosives = booms
	add_child(holder)
	var camera := Camera3D.new()
	camera.position = Vector3(0, 1.2, 0)
	holder.add_child(camera)
	camera.current = true
	var model := Node3D.new()
	model.position = Vector3(0, 1.4, 0)
	holder.add_child(model)
	var piece := UniqueAttach.apply(model, gun, db)
	var lid := piece.find_child("Lid", true, false) as Node3D if piece != null else null
	_say("the clam closes round the barrels (lid + pearl)", lid != null and piece.find_child("Pearl", true, false) != null)
	var sig: Node3D = Signatures.make("clam_shell")
	holder.add_child(sig)
	sig.call("bind", holder, gun, db.uniques["clam_shell"])
	sig.call("start", piece)
	await get_tree().process_frame
	sig.call("on_fired")
	var widest := 0.0
	for _f in 5:
		await get_tree().process_frame
		widest = minf(widest, lid.rotation.x)
	_say("a shot opens the clam (%.2f)" % widest, widest < -0.3)
	var near := BodyMob.new()
	near.position = Vector3(10000, 0, -1.6)
	add_child(near)
	var far := BodyMob.new()
	far.position = Vector3(10000, 0, -6)
	add_child(far)
	var far2 := BodyMob.new()
	far2.position = Vector3(10000.2, 0, -9)
	add_child(far2)
	source.list = [near, far, far2]
	_say("the reload key snaps it shut and bites what is in front (%.0f), the far one is spared" % near.got, not bool(sig.call("on_reload")) and is_equal_approx(near.got, 240.0) and is_zero_approx(far.got))
	near.position.x += 3.0
	await get_tree().physics_frame
	await get_tree().physics_frame
	sig.call("release_pearl", 1.0)
	_say("a full pearl goes through the enemies in its line (%.0f, %.0f)" % [far.got, far2.got], is_equal_approx(far.got, 300.0) and is_equal_approx(far2.got, 300.0))
	var copy := Node3D.new()
	add_child(copy)
	var copy_piece := UniqueAttach.apply_id(copy, "clam_shell")
	UniqueAttach.show_extra(copy_piece, "clam_shell", "p4")
	var shown := (copy_piece.find_child("Pearl", true, false) as Node3D).visible
	UniqueAttach.show_extra(copy_piece, "clam_shell", "")
	_say("another player's copy shows the pearl growing, gone after", shown and not (copy_piece.find_child("Pearl", true, false) as Node3D).visible)
	camera.queue_free()
	sig.call("stop")


func _angler(db: GunDb) -> void:
	var gun := GunGen.unique(db, "angler_light", 50)
	_say("Angler Light builds and is legal", not gun.is_empty() and GunGen.validate(db, gun) == "")
	var source := Source.new()
	add_child(source)
	var booms := FlashBooms.new()
	booms.source = source
	add_child(booms)
	var holder := GunHolder.new()
	holder.position = Vector3(10200, 0, 0)
	holder.explosives = booms
	add_child(holder)
	var model := Node3D.new()
	model.position = Vector3(0, 1.4, 0)
	holder.add_child(model)
	var piece := UniqueAttach.apply(model, gun, db)
	var lure := piece.find_child("Lure", true, false) if piece != null else null
	_say("its lure hangs from the pistol, glowing with a light", lure != null and not lure.find_children("*", "OmniLight3D", true, false).is_empty())
	var sig: Node3D = Signatures.make("angler_light")
	holder.add_child(sig)
	sig.call("bind", holder, gun, db.uniques["angler_light"])
	sig.call("start", piece)
	var near := HpMob.new()
	near.position = Vector3(10208, 0, 0)
	add_child(near)
	var far := HpMob.new()
	far.position = Vector3(10230, 0, 0)
	add_child(far)
	source.list = [near, far]
	await get_tree().process_frame
	sig.call("drift")
	_say("an enemy in reach drifts toward the light %s, one far off does not" % str(near.pushed), near.pushed.x < -2.0 and far.pushed == Vector3.ZERO)


func _flush(db: GunDb) -> void:
	var gun := GunGen.unique(db, "flush", 50)
	_say("Flush builds and is legal", not gun.is_empty() and GunGen.validate(db, gun) == "")
	var source := Source.new()
	add_child(source)
	var booms: Node3D = (load("res://game/explosives.gd") as GDScript).new()
	booms.set("source", source)
	add_child(booms)
	var holder := GunHolder.new()
	holder.position = Vector3(10400, 0, 0)
	holder.explosives = booms
	add_child(holder)
	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(100, 1, 100)
	shape.shape = box
	floor_body.add_child(shape)
	floor_body.position = Vector3(10400, -0.5, 0)
	add_child(floor_body)
	var model := Node3D.new()
	holder.add_child(model)
	_say("its float ball and handle sit on the tube", UniqueAttach.apply(model, gun, db) != null)
	var weak := HpMob.new()
	weak.health.hp = 10.0
	weak.position = Vector3(10401, 0, 9)
	add_child(weak)
	var strong := HpMob.new()
	strong.position = Vector3(10398, 0, 11)
	add_child(strong)
	source.list = [weak, strong]
	var sig: Node3D = Signatures.make("flush")
	holder.add_child(sig)
	sig.call("bind", holder, gun, db.uniques["flush"])
	sig.call("fire_projectile", Vector3(10400, 3, 0), Vector3(0, -0.3, 1).normalized(), {"kind": "grenade", "speed": 30.0, "gravity": 0.0, "splash_radius": 1.0, "splash_damage": 1.0})
	for _i in 40:
		await get_tree().create_timer(0.05).timeout
		if weak.health.is_dead():
			break
	_say("the grenade opens a whirlpool (%d)" % int(sig.get("opened")), int(sig.get("opened")) == 1 and get_tree().get_nodes_in_group("whirlpools").size() == 1)
	await get_tree().create_timer(0.3).timeout
	_say("a weak enemy is flushed, a strong one swirls (%s)" % str(strong.pushed), weak.health.is_dead() and strong.pushed.length() > 3.0 and not strong.health.is_dead())
	await get_tree().create_timer(4.0).timeout
	_say("the whirlpool closes after its time", get_tree().get_nodes_in_group("whirlpools").is_empty())


func _spaghetti(db: GunDb) -> void:
	var gun := GunGen.unique(db, "spaghetti", 50)
	_say("Spaghetti builds and is legal", not gun.is_empty() and GunGen.validate(db, gun) == "")
	var source := Source.new()
	add_child(source)
	var booms := FlashBooms.new()
	booms.source = source
	add_child(booms)
	var holder := ScopeHolder.new()
	holder.position = Vector3(10600, 0, 0)
	holder.explosives = booms
	add_child(holder)
	var model := Node3D.new()
	holder.add_child(model)
	var piece := UniqueAttach.apply(model, gun, db)
	_say("its stretched barrel is on", piece != null)
	var def: Dictionary = (db.uniques["spaghetti"] as Dictionary).duplicate(true)
	(def["cfg"] as Dictionary)["charge_seconds"] = 0.3
	var sig: Node3D = Signatures.make("spaghetti")
	holder.add_child(sig)
	sig.call("bind", holder, gun, def)
	sig.call("start", piece)
	_say("not charged at first (x%.1f)" % float(sig.call("damage_mult")), is_equal_approx(float(sig.call("damage_mult")), 1.0))
	await get_tree().create_timer(0.5).timeout
	var overlay: Variant = (model.find_children("*", "GeometryInstance3D", true, false)[0] as GeometryInstance3D).material_overlay
	_say("held scope: the next shot is charged (x%.1f), the gun glows, others see \"c\"" % float(sig.call("damage_mult")), is_equal_approx(float(sig.call("damage_mult")), 2.0) and overlay != null and String(sig.call("held_suffix")) == "c")
	var on_line := HpMob.new()
	on_line.position = Vector3(10600.8, -1.0, -20)
	add_child(on_line)
	var off_line := HpMob.new()
	off_line.position = Vector3(10606, -1.0, -20)
	add_child(off_line)
	source.list = [on_line, off_line]
	sig.call("after_shot", Vector3(10600, 0, 0), Vector3(0, 0, -1))
	_say("the charged shot stretches and pulls the enemy near its line %s, not one off it; charge spent" % str(on_line.pushed), on_line.pushed.x < -3.0 and off_line.pushed == Vector3.ZERO and not bool(sig.call("charged")) and int(sig.get("noodled")) == 1)
	sig.call("stop")


func _lighthouse(db: GunDb) -> void:
	var gun := GunGen.unique(db, "lighthouse", 50)
	_say("Lighthouse in a Bottle builds and is legal", not gun.is_empty() and GunGen.validate(db, gun) == "")
	var source := Source.new()
	add_child(source)
	var booms := FlashBooms.new()
	booms.source = source
	add_child(booms)
	var holder := GunHolder.new()
	holder.position = Vector3(10800, 0, 0)
	holder.explosives = booms
	add_child(holder)
	var model := Node3D.new()
	model.position = Vector3(0, 1.4, 0)
	holder.add_child(model)
	var piece := UniqueAttach.apply(model, gun, db)
	var glass := piece.find_child("Glass", true, false) if piece != null else null
	var see_through := false
	var glass_meshes: Array = glass.find_children("*", "MeshInstance3D", true, false) if glass != null else []
	if glass is MeshInstance3D:
		glass_meshes.append(glass)
	for mesh in glass_meshes:
		see_through = see_through or ((mesh as MeshInstance3D).material_override as StandardMaterial3D).transparency != BaseMaterial3D.TRANSPARENCY_DISABLED
	_say("its bottle is strapped on, the glass see-through", see_through)
	var sig: Node3D = Signatures.make("lighthouse")
	holder.add_child(sig)
	sig.call("bind", holder, gun, db.uniques["lighthouse"])
	sig.call("start", piece)
	var mob := BurnMob.new()
	mob.position = Vector3(10806, 0, 3)
	add_child(mob)
	source.list = [mob]
	await get_tree().create_timer(3.5).timeout
	_say("the beam sweeps round and sets the enemy it passes burning (%.0f a second)" % mob.burned, mob.burned > 0.0)
	var other := Node3D.new()
	other.position = Vector3(11000, 1.4, 0)
	add_child(other)
	var copy_piece := UniqueAttach.apply_id(other, "lighthouse")
	var me := Eater.new()
	me.position = Vector3(11005, 0, 2)
	add_child(me)
	var copy_beam: Node3D = null
	for n: Node in copy_piece.get_children():
		if n.is_in_group("lighthouse_beams"):
			copy_beam = n
	if copy_beam != null:
		copy_beam.set("local_player", me)
	await get_tree().create_timer(3.5).timeout
	_say("another player's beam heals the local player when it passes (%.0f)" % me.health.hp, copy_beam != null and me.health.hp > 40.0)
	sig.call("stop")


func _carbon(db: GunDb) -> void:
	var gun := GunGen.unique(db, "carbon_copy", 60)
	_say("Carbon Copy builds and is legal", not gun.is_empty() and GunGen.validate(db, gun) == "")
	var holder := GunHolder.new()
	holder.position = Vector3(11200, 0, 0)
	add_child(holder)
	var camera := Camera3D.new()
	camera.position = Vector3(0, 1.3, 0)
	holder.add_child(camera)
	camera.current = true
	var model := Node3D.new()
	holder.add_child(model)
	var piece := UniqueAttach.apply(model, gun, db)
	_say("its photocopier rides on the stock, the copy model loads", piece != null and piece.find_child("Sheet", true, false) != null and ResourceLoader.exists("res://assets/models/weapons/uniques/paper_copy.gltf"))
	var target := BodyMob.new()
	target.position = Vector3(11200.75, 0, -15)
	add_child(target)
	var sig: Node3D = Signatures.make("carbon_copy")
	holder.add_child(sig)
	sig.call("bind", holder, gun, db.uniques["carbon_copy"])
	sig.call("start", piece)
	await get_tree().physics_frame
	sig.call("on_fired")
	var copies: Node3D = get_tree().get_first_node_in_group("paper_copies")
	_say("a shot prints a paper copy beside the shooter", copies != null and int(copies.call("count")) == 1)
	await get_tree().create_timer(1.0).timeout
	var sheet: Node3D = copies.get_child(0) as Node3D if copies.get_child_count() > 0 else null
	_say("it fires once at the aim (%.0f) and falls over flat" % target.got, is_equal_approx(target.got, 90.0) and sheet != null and sheet.rotation.x < -1.2)
	camera.queue_free()


func _time_card(db: GunDb) -> void:
	var gun := GunGen.unique(db, "time_card", 60)
	_say("Time Card builds and is legal", not gun.is_empty() and GunGen.validate(db, gun) == "")
	var holder := DamHolder.new()
	add_child(holder)
	var model := Node3D.new()
	holder.add_child(model)
	var piece := UniqueAttach.apply(model, gun, db)
	_say("its punch clock is on the stock with a face", piece != null and piece.find_child("Face", true, false) != null)
	var def: Dictionary = (db.uniques["time_card"] as Dictionary).duplicate(true)
	(def["cfg"] as Dictionary)["pay"] = [{"after": 0.0, "mult": 1.0}, {"after": 0.2, "mult": 1.5}, {"after": 0.4, "mult": 2.0}]
	var sig: Node3D = Signatures.make("time_card")
	holder.add_child(sig)
	sig.call("bind", holder, gun, def)
	sig.call("start", piece)
	_say("clocked out at first: no extra pay, others see \"o\"", is_equal_approx(float(sig.call("damage_mult")), 1.0) and String(sig.call("held_suffix")) == "o")
	sig.call("on_inspect")
	await get_tree().create_timer(0.55).timeout
	_say("clocked in and unhit: double pay (x%.1f, %s)" % [float(sig.call("damage_mult")), String(sig.call("held_suffix"))], is_equal_approx(float(sig.call("damage_mult")), 2.0) and String(sig.call("held_suffix")) == "t2")
	holder.damaged.emit()
	var words := piece.find_child("Words", true, false) as Label3D
	_say("a hit docks the pay (x%.1f, \"%s\")" % [float(sig.call("damage_mult")), words.text if words != null else "-"], is_equal_approx(float(sig.call("damage_mult")), 1.0) and int(sig.get("docks")) == 1 and words != null and words.text == "DOCKED")
	var copy := Node3D.new()
	add_child(copy)
	var copy_piece := UniqueAttach.apply_id(copy, "time_card")
	UniqueAttach.show_extra(copy_piece, "time_card", "t2")
	var copy_words := copy_piece.find_child("Words", true, false) as Label3D
	_say("another player's clock shows his rate (%s)" % (copy_words.text.replace("\n", " ") if copy_words != null else "-"), copy_words != null and copy_words.text.contains("x2"))
	sig.call("stop")


func _loan_shark(db: GunDb) -> void:
	var gun := GunGen.unique(db, "loan_shark", 60)
	_say("Loan Shark builds and is legal", not gun.is_empty() and GunGen.validate(db, gun) == "")
	var holder := SharkHolder.new()
	add_child(holder)
	var model := Node3D.new()
	holder.add_child(model)
	var piece := UniqueAttach.apply(model, gun, db)
	var shark := piece.find_child("Shark", true, false) as Node3D if piece != null else null
	_say("its fishbowl hangs under the barrel with a shark", shark != null)
	var sig: Node3D = Signatures.make("loan_shark")
	holder.add_child(sig)
	sig.call("bind", holder, gun, db.uniques["loan_shark"])
	sig.call("start", piece)
	holder.weapon.ammo = 3
	sig.call("on_fired")
	_say("rounds left in the magazine: nothing borrowed", int(sig.get("debt")) == 0 and holder.weapon.ammo == 3)
	holder.health.hp = 100.0
	holder.weapon.ammo = 0
	sig.call("on_fired")
	_say("an empty magazine borrows a round for health (%d left, hp %.2f)" % [holder.weapon.ammo, holder.health.hp], holder.weapon.ammo == 1 and int(sig.get("debt")) == 1 and absf(holder.health.hp - 98.96) < 0.01)
	for _n in 59:
		holder.weapon.ammo = 0
		sig.call("on_fired")
	_say("the shark grows with the debt (x%.2f, %s)" % [shark.scale.x, String(sig.call("held_suffix"))], shark.scale.x > 2.3 and String(sig.call("held_suffix")) == "s9")
	_say("it never takes the last point of health (%.1f)" % holder.health.hp, holder.health.hp >= 1.0)
	sig.call("on_target_hit", Node.new(), Vector3.ZERO, 10.0, true)
	_say("a kill pays back 5 rounds (debt %d)" % int(sig.get("debt")), int(sig.get("debt")) == 55)


func _wanted(db: GunDb) -> void:
	var gun := GunGen.unique(db, "wanted_poster", 60)
	_say("Wanted Poster builds and is legal", not gun.is_empty() and GunGen.validate(db, gun) == "")
	var session := SessionStub.new()
	session.add_to_group("game_session")
	add_child(session)
	var source := Source.new()
	add_child(source)
	var booms := FlashBooms.new()
	booms.source = source
	add_child(booms)
	var holder := PosterHolder.new()
	holder.position = Vector3(11400, 0, 0)
	holder.explosives = booms
	add_child(holder)
	var model := Node3D.new()
	holder.add_child(model)
	var piece := UniqueAttach.apply(model, gun, db)
	_say("its poster is pinned to the stock", piece != null and piece.find_child("Poster", true, false) != null)
	var a := HpMob.new()
	a.position = Vector3(11410, 0, 0)
	add_child(a)
	var b := HpMob.new()
	b.position = Vector3(11420, 0, 0)
	add_child(b)
	source.list = [a, b]
	var sig: Node3D = Signatures.make("wanted_poster")
	holder.add_child(sig)
	sig.call("bind", holder, gun, db.uniques["wanted_poster"])
	sig.call("start", piece)
	sig.call("pick")
	var face: Node3D = sig.call("wanted")
	_say("an enemy is wanted and marked over its head", face != null and face.has_node("wanted_mark"))
	var other := a if face == b else b
	sig.call("on_target_hit", other, other.position, 100.0, true)
	_say("killing someone else pays nothing", session.purse.balance == 0)
	sig.call("on_target_hit", face, face.position, 100.0, true)
	await get_tree().process_frame
	_say("killing the wanted one pays %d chips, refreshes the skills, takes the mark down" % session.purse.balance, session.purse.balance == 50 and holder.skills.refreshed == 1 and not face.has_node("wanted_mark"))
	session.queue_free()
	sig.call("stop")


func _key_ring(db: GunDb) -> void:
	var gun := GunGen.unique(db, "key_ring", 65)
	_say("Key Ring builds and is legal", not gun.is_empty() and GunGen.validate(db, gun) == "")
	var source := Source.new()
	add_child(source)
	var booms := FlashBooms.new()
	booms.source = source
	add_child(booms)
	var holder := GunHolder.new()
	holder.explosives = booms
	add_child(holder)
	var model := Node3D.new()
	holder.add_child(model)
	var piece := UniqueAttach.apply(model, gun, db)
	_say("its key ring hangs from the grip, nine keys on it", piece != null and piece.find_child("Key9", true, false) != null)
	var sig: Node3D = Signatures.make("key_ring")
	holder.add_child(sig)
	sig.call("bind", holder, gun, db.uniques["key_ring"])
	sig.call("start", piece)
	_say("no keys at first: none shown", not (piece.find_child("Key1", true, false) as Node3D).visible)
	for _n in 6:
		sig.call("on_target_hit", Node.new(), Vector3.ZERO, 10.0, true)
	_say("six kills: six keys (%s), the sixth shown, the seventh not" % String(sig.call("held_suffix")), int(sig.get("keys")) == 6 and (piece.find_child("Key6", true, false) as Node3D).visible and not (piece.find_child("Key7", true, false) as Node3D).visible)
	var door := Locked.new()
	add_child(door)
	sig.call("on_target_hit", door, Vector3.ZERO, 10.0, false)
	_say("shooting something locked opens it for 5 keys (%d left)" % int(sig.get("keys")), door.open and int(sig.get("keys")) == 1)
	var mob := LureMob.new()
	mob.position = Vector3(8, 0, 0)
	add_child(mob)
	source.list = [mob]
	sig.call("jingle")
	_say("the jingle draws an enemy in earshot to the holder", mob.chasing == holder)


func _treasure(db: GunDb) -> void:
	var gun := GunGen.unique(db, "treasure_map", 65)
	_say("Treasure Map builds and is legal", not gun.is_empty() and GunGen.validate(db, gun) == "")
	var session := MapSession.new()
	session.add_to_group("game_session")
	add_child(session)
	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(200, 1, 200)
	shape.shape = box
	floor_body.add_child(shape)
	floor_body.position = Vector3(12000, -0.5, 0)
	add_child(floor_body)
	var holder := MapHolder.new()
	holder.gun_db = db
	holder.position = Vector3(12000, 0, 0)
	add_child(holder)
	var model := Node3D.new()
	holder.add_child(model)
	_say("its rolled map is tied to the barrel", UniqueAttach.apply(model, gun, db) != null)
	var sig: Node3D = Signatures.make("treasure_map")
	holder.add_child(sig)
	sig.call("bind", holder, gun, db.uniques["treasure_map"])
	await get_tree().physics_frame
	var x: Node3D = sig.call("mark_new")
	var far_off := x.global_position.distance_to(holder.global_position) if x != null else 0.0
	_say("an X appears on the ground %.0f m away" % far_off, x != null and far_off >= 14.0 and far_off <= 41.0 and absf(x.global_position.y) < 0.1)
	_say("away from it the stock digs nothing", not bool(sig.call("dig")))
	holder.global_position = x.global_position + Vector3(1, 0, 0)
	_say("on it the inspect key digs up a gun, the X is gone", bool(sig.call("dig")) and session._field.spawned == 1)
	await get_tree().process_frame
	_say("(no X left)", get_tree().get_nodes_in_group("treasure_xs").is_empty())
	session.queue_free()


func _goose(db: GunDb) -> void:
	var gun := GunGen.unique(db, "golden_goose", 65)
	_say("Golden Goose builds and is legal", not gun.is_empty() and GunGen.validate(db, gun) == "")
	var session := SessionStub.new()
	session.add_to_group("game_session")
	add_child(session)
	var source := Source.new()
	add_child(source)
	var booms := FlashBooms.new()
	booms.source = source
	add_child(booms)
	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(100, 1, 100)
	shape.shape = box
	floor_body.add_child(shape)
	floor_body.position = Vector3(12500, -0.5, 0)
	add_child(floor_body)
	var holder := GunHolder.new()
	holder.position = Vector3(12500, 0, 0)
	holder.explosives = booms
	add_child(holder)
	var model := Node3D.new()
	model.position = Vector3(0, 1.4, 0)
	holder.add_child(model)
	var piece := UniqueAttach.apply(model, gun, db)
	var head := piece.find_child("Head", true, false) as Node3D if piece != null else null
	_say("its golden goose sits on the tube, the egg model loads", head != null and ResourceLoader.exists("res://assets/models/weapons/uniques/golden_egg.gltf"))
	var sig: Node3D = Signatures.make("golden_goose")
	holder.add_child(sig)
	sig.call("bind", holder, gun, db.uniques["golden_goose"])
	sig.call("start", piece)
	var mob := LureMob.new()
	mob.position = Vector3(12512, 0, 0)
	add_child(mob)
	source.list = [mob]
	await get_tree().process_frame
	sig.call("honk")
	var lowest := 0.0
	for _f in 6:
		await get_tree().process_frame
		lowest = minf(lowest, head.rotation.x)
	_say("it honks: its head bobs (%.2f), an enemy near comes for it (%s)" % [lowest, str(mob.chasing == holder)], lowest < -0.05 and mob.chasing == holder)
	sig.call("fire_projectile", Vector3(12500, 1.5, 0), Vector3(0, 0.2, 1).normalized(), {"speed": 12.0, "splash_damage": 150.0, "splash_radius": 4.0})
	await get_tree().create_timer(1.0).timeout
	_say("an egg flies and sits there, not hatched yet", get_tree().get_nodes_in_group("golden_eggs").size() == 1 and booms.blasts.is_empty())
	await get_tree().create_timer(2.5).timeout
	_say("it hatches: a blast (%s) and chips (%d)" % [str(booms.blasts), session.purse.balance], booms.blasts.size() == 1 and is_equal_approx(float(booms.blasts[0][2]), 150.0) and session.purse.balance == 5)
	session.queue_free()


func _split(db: GunDb) -> void:
	var gun := GunGen.unique(db, "split_decision", 65)
	_say("Split Decision builds and is legal", not gun.is_empty() and GunGen.validate(db, gun) == "")
	var holder := GunHolder.new()
	add_child(holder)
	var model := Node3D.new()
	holder.add_child(model)
	var piece := UniqueAttach.apply(model, gun, db)
	_say("its two barrels and the coin are on", piece != null and piece.find_child("Coin", true, false) != null)
	var sig: Node3D = Signatures.make("split_decision")
	holder.add_child(sig)
	sig.call("bind", holder, gun, db.uniques["split_decision"])
	sig.call("start", piece)
	var mob := SplitMob.new()
	add_child(mob)
	sig.set("fire", true)
	sig.call("on_target_hit", mob, Vector3.ZERO, 10.0, false)
	_say("a fire shot burns (%.0f a second), no shatter yet; others see \"f\"" % mob.burning, mob.burning > 0.0 and int(sig.get("shatters")) == 0 and String(sig.call("held_suffix")) == "f")
	sig.set("fire", false)
	sig.call("on_target_hit", mob, Vector3.ZERO, 10.0, false)
	_say("then an ice shot slows it and it shatters (%.0f)" % mob.got, mob.slowed > 0.0 and int(sig.get("shatters")) == 1 and is_equal_approx(mob.got, 300.0))
	var copy := Node3D.new()
	add_child(copy)
	var copy_piece := UniqueAttach.apply_id(copy, "split_decision")
	UniqueAttach.show_extra(copy_piece, "split_decision", "f")
	_say("another player's coin shows his next shot", is_equal_approx((copy_piece.find_child("Coin", true, false) as Node3D).rotation.x, PI))


func _bottle(db: GunDb) -> void:
	var gun := GunGen.unique(db, "message_bottle", 65)
	_say("Message in a Bottle builds and is legal", not gun.is_empty() and GunGen.validate(db, gun) == "")
	var holder := BottleHolder.new()
	add_child(holder)
	var model := Node3D.new()
	holder.add_child(model)
	_say("its bottle is taped to the frame, the shanty has 12 lines", UniqueAttach.apply(model, gun, db) != null and (load("res://game/signatures/message_bottle.gd") as GDScript).call("song_lines").size() == 12)
	var sig: Node3D = Signatures.make("message_bottle")
	holder.add_child(sig)
	sig.call("bind", holder, gun, db.uniques["message_bottle"])
	for _n in 3:
		sig.call("on_target_hit", Node.new(), Vector3.ZERO, 10.0, true)
	_say("three kills: three lines told, no verse yet (%s)" % ", ".join(holder.damage_numbers.said.slice(-3)), int(sig.get("next_line")) == 3 and int(sig.get("verses")) == 0)
	sig.call("on_target_hit", Node.new(), Vector3.ZERO, 10.0, true)
	_say("the fourth finishes the verse: the buff", int(sig.get("verses")) == 1 and holder.self_fx.clips == 1)


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
