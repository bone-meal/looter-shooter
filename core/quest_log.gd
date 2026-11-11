# Purpose: pure quest state of the fantasy world: which quests are open, on which step, which are finished, and what
# finishing them gives. The game reports events (a kill, a cast, arriving somewhere, talking) and bag/skill state; this
# decides what advances. One log is shared by the whole party and kept by the host. No nodes.
# Dependencies: none. Data: data/fantasy/quests.json.
extends RefCounted

var active := {}  # quest id -> {"step": index, "n": progress of that step}
var done: Array[String] = []

var _quests := {}  # id -> quest
var _order: Array[String] = []


func _init(quest_data: Dictionary) -> void:
	for quest: Dictionary in quest_data["quests"]:
		_quests[String(quest["id"])] = quest
		_order.append(String(quest["id"]))


func ids() -> Array[String]:
	return _order


func quest(id: String) -> Dictionary:
	return _quests.get(id, {})


func is_done(id: String) -> bool:
	return done.has(id)


func can_start(id: String) -> bool:
	if not _quests.has(id) or active.has(id) or done.has(id):
		return false
	for needed: String in _quests[id]["requires"]:
		if not done.has(needed):
			return false
	return true


# Quests an NPC can hand out right now.
func offers(npc: String) -> Array[String]:
	var out: Array[String] = []
	for id in _order:
		if String(_quests[id]["giver"]) == npc and can_start(id):
			out.append(id)
	return out


func start(id: String) -> bool:
	if not can_start(id):
		return false
	active[id] = {"step": 0, "n": 0}
	return true


# The step an open quest is on ({} when it is not open).
func step(id: String) -> Dictionary:
	if not active.has(id):
		return {}
	var steps: Array = _quests[id]["steps"]
	return steps[int(active[id]["step"])]


func step_text(id: String) -> String:
	var s := step(id)
	if s.is_empty():
		return ""
	var goal := int(s.get("count", 1))
	return String(s["text"]) if goal <= 1 or String(s["type"]) in ["have", "skill"] else "%s (%d/%d)" % [s["text"], int(active[id]["n"]), goal]


# Reports something that happened. event = {"type": "kill", "enemy": id} | {"type": "cast", "sequence", "substance",
# "secret"} | {"type": "reach", "place": id} | {"type": "talk", "npc": id} | {"type": "fire"}. Returns the changes:
# [{"quest": id, "finished": bool, "rewards": {...} when finished}].
func note(event: Dictionary) -> Array:
	var changes: Array = []
	for id: String in active.keys():
		var s := step(id)
		if String(s["type"]) != String(event.get("type", "")) or not _matches(s, event):
			continue
		active[id]["n"] = int(active[id]["n"]) + 1
		if int(active[id]["n"]) >= int(s.get("count", 1)):
			changes.append(_advance(id))
		else:
			changes.append({"quest": id, "finished": false})
	return changes


func _matches(s: Dictionary, event: Dictionary) -> bool:
	match String(s["type"]):
		"kill":
			return String(s["enemy"]) == String(event.get("enemy", ""))
		"reach":
			return String(s["place"]) == String(event.get("place", ""))
		"talk":
			return String(s["npc"]) == String(event.get("npc", ""))
		"fire":
			return true
		"cast":
			if s.has("secret"):
				return String(s["secret"]) == String(event.get("secret", ""))
			if s.has("sequence"):
				return String(s["sequence"]) == String(event.get("sequence", ""))
			return String(s["substance"]) == String(event.get("substance", "")) and String(event.get("secret", "")) == ""
	return false


# Checks the steps that depend on what a player carries or has learned ("have", "skill"). bag = {item: count},
# levels = {skill: level}. Returns changes like note(); a finished "have" step with take lists it under "take".
func check(bag: Dictionary, levels: Dictionary) -> Array:
	var changes: Array = []
	var moved := true
	while moved:  # one quest may pass several such steps in a row
		moved = false
		for id: String in active.keys():
			var s := step(id)
			var ok := false
			var take := {}
			if String(s["type"]) == "have":
				ok = int(bag.get(String(s["item"]), 0)) >= int(s["count"])
				if ok and bool(s.get("take", false)):
					take[String(s["item"])] = int(s["count"])
					bag[String(s["item"])] = int(bag[String(s["item"])]) - int(s["count"])
			elif String(s["type"]) == "skill":
				ok = int(levels.get(String(s["skill"]), 1)) >= int(s["level"])
			if ok:
				var change := _advance(id)
				change["take"] = take
				changes.append(change)
				moved = true
	return changes


# Online: a party member says their own bag or skills pass the step this quest is on. Only "have" and "skill" steps
# can be passed this way (kills and bosses are decided by the host). Returns changes like note().
func claim(id: String, step_index: int) -> Array:
	if not active.has(id) or int(active[id]["step"]) != step_index:
		return []
	if not (String(step(id)["type"]) in ["have", "skill"]):
		return []
	return [_advance(id)]


func _advance(id: String) -> Dictionary:
	var steps: Array = _quests[id]["steps"]
	active[id] = {"step": int(active[id]["step"]) + 1, "n": 0}
	if int(active[id]["step"]) < steps.size():
		return {"quest": id, "finished": false}
	active.erase(id)
	done.append(id)
	return {"quest": id, "finished": true, "rewards": _quests[id]["rewards"]}


# Admin command: finishes a quest outright (its requirements are finished too). Returns the rewards of each, in order.
func force_finish(id: String) -> Array:
	var given: Array = []
	if not _quests.has(id) or done.has(id):
		return given
	for needed: String in _quests[id]["requires"]:
		given.append_array(force_finish(needed))
	active.erase(id)
	done.append(id)
	given.append({"quest": id, "finished": true, "rewards": _quests[id]["rewards"]})
	return given


func reset() -> void:
	active = {}
	done = []


# How many element slots the story has added (one per finished quest that returns a pigment).
func pigments() -> int:
	var n := 0
	for id in done:
		if bool((_quests[id]["rewards"] as Dictionary).get("pigment", false)):
			n += 1
	return n


# Ids of the long spells the party has been taught.
func secrets() -> Array[String]:
	var out: Array[String] = []
	for id in done:
		var secret := String((_quests[id]["rewards"] as Dictionary).get("secret", ""))
		if secret != "":
			out.append(secret)
	return out


func guns_unlocked() -> bool:
	for id in done:
		if bool((_quests[id]["rewards"] as Dictionary).get("unlock_guns", false)):
			return true
	return false


# The main-line chapter the party is in (1-8; 9 = finished).
func chapter() -> int:
	var at := 1
	for id in _order:
		var q: Dictionary = _quests[id]
		if int(q["chapter"]) > 0 and not done.has(id):
			return int(q["chapter"])
		at = maxi(at, int(q["chapter"]) + 1)
	return at


func to_dict() -> Dictionary:
	return {"v": 1, "active": active.duplicate(true), "done": done.duplicate()}


# Loads a save, keeping only what the quest data allows (known ids, steps in range, requirements met).
func from_dict(saved: Variant) -> void:
	reset()
	if not saved is Dictionary:
		return
	var src: Dictionary = saved
	if src.get("done") is Array:
		for id: Variant in src["done"]:
			if _quests.has(String(id)) and not done.has(String(id)):
				done.append(String(id))
	var kept: Array[String] = []
	for id in _order:  # a finished quest whose requirements are not finished was edited in: drop it
		if done.has(id):
			var ok := true
			for needed: String in _quests[id]["requires"]:
				ok = ok and kept.has(needed)
			if ok:
				kept.append(id)
	done = kept
	if src.get("active") is Dictionary:
		for id: Variant in src["active"]:
			var key := String(id)
			var entry: Variant = src["active"][id]
			if can_start(key) and entry is Dictionary:
				var steps: Array = _quests[key]["steps"]
				var at := clampi(int((entry as Dictionary).get("step", 0)), 0, steps.size() - 1)
				active[key] = {"step": at, "n": clampi(int((entry as Dictionary).get("n", 0)), 0, int((steps[at] as Dictionary).get("count", 1)))}
