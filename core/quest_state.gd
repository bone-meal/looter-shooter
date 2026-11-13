# Purpose: pure rules of the islands' main quest: which step the party is on, how far that step has got, and which
# event finishes it. No nodes. The texts are checked here too (every step needs its lines in the writers' file).
# Dependencies: none. Data: data/zombies/quest.json (the steps) and the parsed data/zombies/writing/quest.txt
# (core/text_book.gd), passed to setup().
extends RefCounted

const LINES := ["what", "where", "done"]  # every step's lines the game cannot do without

var cfg: Dictionary = {}
var texts: Dictionary = {}  # kind -> id -> {key: text or list}
var step := 0  # the step to do (steps.size() = all done)
var count := 0  # kills of a kills step so far
var shot: Array[bool] = []  # lamps of a shoot step put out
var boss_out := false  # the boss step's enemy has been sent


func setup(config: Dictionary, writing: Dictionary) -> void:
	cfg = config
	texts = writing
	reset()


func steps() -> Array:
	return cfg.get("steps", [])


func done() -> bool:
	return step >= steps().size()


# The step to do now ({} when the quest is done).
func current() -> Dictionary:
	return {} if done() else steps()[step]


func kind() -> String:
	return String(current().get("kind", ""))


# A step's line from the writers' file ("" when missing); "says" gives the list.
func line(step_id: String, key: String) -> String:
	var value: Variant = (texts.get("step", {}) as Dictionary).get(step_id, {}).get(key, "")
	return String(value[0]) if value is Array else String(value)


func says(step_id: String) -> PackedStringArray:
	var value: Variant = (texts.get("step", {}) as Dictionary).get(step_id, {}).get("says", [])
	return PackedStringArray(value if value is Array else ([value] if String(value) != "" else []))


func quest_line(key: String) -> String:
	return String((texts.get("quest", {}) as Dictionary).get("main", {}).get(key, ""))


# What is missing in the writers' file, one line each (empty = all there).
func text_problems() -> PackedStringArray:
	var found := PackedStringArray()
	if quest_line("name") == "":
		found.append("quest.txt: [quest main] has no name line")
	for entry: Dictionary in steps():
		var id := String(entry["id"])
		if not (texts.get("step", {}) as Dictionary).has(id):
			found.append("quest.txt: there is no [step %s] section" % id)
			continue
		for key: String in LINES:
			if line(id, key) == "":
				found.append("quest.txt: step %s has no %s line" % [id, key])
	return found


# --- events: each returns true when it finished the step it belongs to (the caller then calls advance) ---

func used(step_id: String) -> bool:
	return kind() == "use" and String(current()["id"]) == step_id


func power_is_on(on: bool) -> bool:
	return kind() == "power" and on


func built(thing: String) -> bool:
	return kind() == "build" and String(current()["thing"]) == thing


# A kill near the kills step's spot (the caller measured the distance). True once the count is reached.
func killed_near() -> bool:
	if kind() != "kills":
		return false
	count += 1
	return count >= int(current()["count"])


# Lamp `index` of the shoot step is put out. True once every lamp is out.
func lamp_out(index: int) -> bool:
	if kind() != "shoot" or index < 0 or index >= shot.size() or shot[index]:
		return false
	shot[index] = true
	return not shot.has(false)


func boss_killed() -> bool:
	return kind() == "boss" and boss_out


# On to the next step, its progress cleared.
func advance() -> void:
	step = mini(step + 1, steps().size())
	count = 0
	boss_out = false
	shot.clear()
	if kind() == "shoot":
		shot.resize((current()["spots"] as Array).size())
		shot.fill(false)


# Game over: from the first step again.
func reset() -> void:
	step = -1
	advance()


# The whole state as one dictionary of plain numbers (sent online).
func to_dict() -> Dictionary:
	var lamps := 0
	for i in shot.size():
		lamps |= (1 << i) if shot[i] else 0
	return {"step": step, "count": count, "lamps": lamps, "boss": boss_out}


func from_dict(d: Dictionary) -> void:
	step = clampi(int(d.get("step", 0)), 0, steps().size())
	count = 0
	boss_out = false
	shot.clear()
	if kind() == "shoot":
		shot.resize((current()["spots"] as Array).size())
		for i in shot.size():
			shot[i] = (int(d.get("lamps", 0)) >> i) & 1 == 1
	count = int(d.get("count", 0))
	boss_out = bool(d.get("boss", false))
