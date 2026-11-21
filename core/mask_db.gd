# Purpose: the masks (polish1 D5c, diary/DECISIONS_SKINS.md + diary/MASK_PROCESS.md): the list from data/masks.json,
# one mask's data, drop rolls (any mask of a source at the data's chance), the graphics-tier detail (mesh / texture size / effects share) and the Morse code of a message as
# on / off units (the eyes of the Plague Doctor flash it). A data check for tools/mask_check.gd. Pure rules.
# Dependencies: none (data/masks.json passed in).
extends RefCounted

const MORSE := {"A": ".-", "B": "-...", "C": "-.-.", "D": "-..", "E": ".", "F": "..-.", "G": "--.", "H": "....",
	"I": "..", "J": ".---", "K": "-.-", "L": ".-..", "M": "--", "N": "-.", "O": "---", "P": ".--.", "Q": "--.-",
	"R": ".-.", "S": "...", "T": "-", "U": "..-", "V": "...-", "W": ".--", "X": "-..-", "Y": "-.--", "Z": "--..",
	"0": "-----", "1": ".----", "2": "..---", "3": "...--", "4": "....-", "5": ".....", "6": "-....", "7": "--...",
	"8": "---..", "9": "----."}
const SOURCES := ["boss", "elite", "loot", "playtime", "achievement"]

var cfg: Dictionary


func _init(config: Dictionary) -> void:
	cfg = config


func ids() -> Array:
	return (cfg.get("masks", {}) as Dictionary).keys()


func has(id: String) -> bool:
	return (cfg.get("masks", {}) as Dictionary).has(id)


func mask(id: String) -> Dictionary:
	return (cfg.get("masks", {}) as Dictionary).get(id, {})


func name_of(id: String) -> String:
	return String(mask(id).get("name", id))


func tradable(id: String) -> bool:
	return bool(mask(id).get("trade", false))


# Every mask that comes from `source` (boss / elite / loot / playtime / achievement).
func of_source(source: String) -> Array:
	var out: Array = []
	for id: String in ids():
		if String(mask(id).get("source", "")) == source:
			out.append(id)
	return out


# A drop roll: "" or the id of one mask of `source`, at the data's chance `drop_key` (boss / elite / chest).
func roll_drop(drop_key: String, source: String, rng: RandomNumberGenerator) -> String:
	var pool := of_source(source)
	if pool.is_empty() or rng.randf() >= float((cfg.get("drops", {}) as Dictionary).get(drop_key, 0.0)):
		return ""
	return String(pool[rng.randi() % pool.size()])


# The detail row of graphics tier `tier` (0 potato .. 4 ultimate).
func detail(tier: int) -> Dictionary:
	var rows: Array = cfg.get("detail", [])
	if rows.is_empty():
		return {"mesh": "hi", "tex": "full", "fx": 1.0}
	return rows[clampi(tier, 0, rows.size() - 1)]


# `text` in Morse as units: true = lit, false = dark (dot 1, dash 3, gap in a letter 1, between letters 3, between
# words 7, and 7 more after the message before it loops).
static func morse_units(text: String) -> Array:
	var out: Array = []
	for word: String in text.to_upper().split(" ", false):
		for ch in word:
			var code := String(MORSE.get(ch, ""))
			for s in code:
				for k in (3 if s == "-" else 1):
					out.append(true)
				out.append(false)
			if code != "":
				out.append_array([false, false])  # letter gap = 3 (one already there)
		out.append_array([false, false, false, false])  # word gap = 7
	out.append_array([false, false, false, false, false, false, false])
	return out


# Every message of a mask back to back, as units.
func morse_loop(id: String) -> Array:
	var out: Array = []
	for line: String in (mask(id).get("fx", {}) as Dictionary).get("morse", []):
		out.append_array(morse_units(line))
	return out


# Problems in the data ("" each line = fine), for tools/mask_check.gd.
func problems() -> Array:
	var out: Array = []
	for id: String in ids():
		var m := mask(id)
		for key in ["name", "source", "base", "covers"]:
			if not m.has(key):
				out.append("%s: no %s" % [id, key])
		if not String(m.get("source", "")) in SOURCES:
			out.append("%s: source %s" % [id, m.get("source")])
		for line: String in (m.get("fx", {}) as Dictionary).get("morse", []):
			for ch in line.to_upper():
				if ch != " " and not MORSE.has(ch):
					out.append("%s: morse has no %s" % [id, ch])
	return out
