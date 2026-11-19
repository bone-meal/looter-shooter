# Purpose: pure rules of the sea quests (sea step 13e; LOCKED: progress is the HOST'S WORLD, shared by the party; each
# quest ends with its person taking over a building of the home port). The quests and their steps (data/sea/
# quests.json), which step each stands at, whether a step may be finished now, who runs which building once done,
# where to go (for the chart), and the writing files' words (data/sea/writing/quests_r1.txt + quests_r2.txt). No nodes.
# Dependencies: the config and the writing text given to _init.
extends RefCounted

var cfg: Dictionary
var state := {}  # quest id -> the step it stands at (steps.size() = done; missing = 0)
var words := {}  # quest id -> {key: text}


func _init(config: Dictionary, writing: String) -> void:
	cfg = config
	var section := ""
	for raw: String in writing.split("\n"):
		var line := raw.strip_edges()
		if line == "" or line.begins_with("#"):
			continue
		if line.begins_with("[quest ") and line.ends_with("]"):
			section = line.trim_prefix("[quest ").trim_suffix("]").strip_edges()
			words[section] = {}
			continue
		var at := line.find(":")
		if at > 0 and section != "":
			words[section][line.substr(0, at).strip_edges()] = line.substr(at + 1).strip_edges()


func quests() -> Array:
	return cfg["quests"]


func quest(id: String) -> Dictionary:
	for q: Dictionary in cfg["quests"]:
		if String(q["id"]) == id:
			return q
	return {}


func step_of(id: String) -> int:
	return int(state.get(id, 0))


func done(id: String) -> bool:
	return step_of(id) >= (quest(id).get("steps", []) as Array).size()


# The step the quest stands at ({} = done).
func current(id: String) -> Dictionary:
	var steps: Array = quest(id).get("steps", [])
	var k := step_of(id)
	return steps[k] if k < steps.size() else {}


# May step `k` of quest `id` be finished now (it is the step it stands at)?
func can_finish(id: String, k: int) -> bool:
	return not quest(id).is_empty() and step_of(id) == k and not done(id)


func finish(id: String, k: int) -> bool:
	if not can_finish(id, k):
		return false
	state[id] = k + 1
	return true


# The quest whose person runs town plot `plot` now ("" = its own resident still).
func runner_of(plot: String) -> String:
	for q: Dictionary in cfg["quests"]:
		if String(q.get("takes_over", "")) == plot and done(String(q["id"])):
			return String(q["id"])
	return ""


# Where the quest's current step happens (sea x, z): the step's own "at", else the person.
func where(id: String) -> Vector2:
	var q := quest(id)
	var st := current(id)
	var a: Array = st.get("at", q.get("at", [0.0, 0.0]))
	return Vector2(float(a[0]), float(a[1]))


func word(id: String, key: String) -> String:
	return String((words.get(id, {}) as Dictionary).get(key, ""))


func goal(id: String) -> String:
	return word(id, "goal%d" % step_of(id)) if not done(id) else "Done: %s runs the %s at the home port" % [word(id, "person"), word(id, "trade").to_lower()]


func to_dict() -> Dictionary:
	return state.duplicate()


func from_dict(saved: Variant) -> void:
	state.clear()
	if not saved is Dictionary:
		return
	for id: Variant in saved:
		var q := quest(String(id))
		if not q.is_empty():
			state[String(id)] = clampi(int(saved[id]), 0, (q["steps"] as Array).size())
