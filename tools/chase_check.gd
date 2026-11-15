# Purpose: developer check of the chase guns' red-text behaviours (game/signatures/) on stand-ins, and that the host
# accepts what they remember on the gun and refuses forged copies. FISH STORY: kills told bigger with a line, the
# biggest real hit kept on the gun ("record") and on its tag, the boast after a new record. BEACH BALL BOMBARDIER:
# balls bounce off heads (each bounce hits), a shot pops one, a kick sends it where the kicker looks and makes its pop
# bigger, they pop on the ground in the end. Log tools/chase_check.log
# (CHASE_CHECK_DONE problems=n).
# Dependencies: core/gun_db.gd, core/gun_gen.gd, game/signatures/index.gd, game/unique_attach.gd.
extends Node

const GunGen = preload("res://core/gun_gen.gd")
const GunDb = preload("res://core/gun_db.gd")
const Signatures = preload("res://game/signatures/index.gd")
const UniqueAttach = preload("res://game/unique_attach.gd")
const BeachBalls = preload("res://game/beach_balls.gd")


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
	func is_dead() -> bool:
		return false


class Booms extends Node3D:
	var source: Node = null
	var numbers: Node = null
	var score: RefCounted = null
	var sounds: Node = null
	var blasts: Array = []

	func blast(at: Vector3, radius: float, damage: float, _flash: bool = true) -> void:
		blasts.append([at, radius, damage])


class Source extends Node:
	var list: Array = []

	func enemy_list() -> Array:
		return list


class Kicker extends Node3D:
	func aim_flat() -> Vector3:
		return Vector3(1, 0, 0)


var _lines: Array[String] = []
var _problems := 0


func _ready() -> void:
	var db := GunDb.new(_json("gun_loot"), _json("gun_parts"), _json("manufacturers"), _json("weapons"), _json("skills"), _json("gun_uniques"))
	_fish_story(db)
	await _beach_balls(db)
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
