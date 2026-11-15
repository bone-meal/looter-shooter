# Purpose: developer check of the chase guns' red-text behaviours (game/signatures/) on stand-ins, and that the host
# accepts what they remember on the gun and refuses forged copies. FISH STORY: kills told bigger with a line, the
# biggest real hit kept on the gun ("record") and on its tag, the boast after a new record. Log tools/chase_check.log
# (CHASE_CHECK_DONE problems=n).
# Dependencies: core/gun_db.gd, core/gun_gen.gd, game/signatures/index.gd, game/unique_attach.gd.
extends Node

const GunGen = preload("res://core/gun_gen.gd")
const GunDb = preload("res://core/gun_db.gd")
const Signatures = preload("res://game/signatures/index.gd")
const UniqueAttach = preload("res://game/unique_attach.gd")


class Numbers extends Node:
	var said: Array[String] = []

	func say(_at: Vector3, words: String, _c: Color) -> void:
		said.append(words)


class Holder extends Node3D:
	var damage_numbers := Numbers.new()


var _lines: Array[String] = []
var _problems := 0


func _ready() -> void:
	var db := GunDb.new(_json("gun_loot"), _json("gun_parts"), _json("manufacturers"), _json("weapons"), _json("skills"), _json("gun_uniques"))
	_fish_story(db)
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
