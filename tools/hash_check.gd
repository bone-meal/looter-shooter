# Purpose: one-off check of Dictionary.hash() on appearance dictionaries differing only in float sliders; writes tools/hash_check.log.
extends Node

const AppearanceData = preload("res://game/appearance_data.gd")


func _ready() -> void:
	var db := AppearanceData.db()
	var a := db.default_for("female")
	var out := PackedStringArray()
	for key in ["height", "weight", "bust", "glutes"]:
		var b := a.duplicate()
		var r := db.range_of(key)
		b[key] = float(r[1])
		var s := db.sanitize(b)
		out.append("%s: a=%s b=%s sanitized=%s hash_eq=%s sanitized_eq=%s" % [key, a[key], b[key], s[key], a.hash() == b.hash(), a.hash() == s.hash()])
	var f := FileAccess.open("res://tools/hash_check.log", FileAccess.WRITE)
	f.store_string("\n".join(out))
	f.close()
	get_tree().quit()
