# Purpose: pure rules for what the skills open on the way to level 50 (data/fantasy/skilling.json "unlocks": ten steps
# per skill at levels 5, 10 ... 50, each either new content or a perk). Adds up a skill's perks at a level, lists the
# extra finds, and tells which steps a level-up has just reached. No nodes.
# Dependencies: none. Data: data/fantasy/skilling.json unlocks (names and lines from writing/skills.txt via core/fantasy_data.gd).
extends RefCounted

const KEYS := ["speed", "double", "keep", "save", "regrow", "bonus", "heal", "potency", "fire_time", "fire_regen", "fire_radius",
	"mana", "regen", "power", "ship_speed", "repair", "cannon_reload", "snare_speed", "finer", "run_speed", "sure_foot"]


# The sum of one perk key over every step of `skill` reached at `level` (0 when none).
static func total(unlocks: Dictionary, skill: String, level: int, key: String) -> float:
	var sum := 0.0
	for step: Dictionary in unlocks.get(skill, []):
		if String(step["kind"]) == "perk" and int(step["level"]) <= level:
			sum += float((step["perk"] as Dictionary).get(key, 0.0)) if key != "bonus" else 0.0
	return sum


# The extra finds of `skill` at `level`: [{"item", "chance"}].
static func bonus_finds(unlocks: Dictionary, skill: String, level: int) -> Array:
	var out: Array = []
	for step: Dictionary in unlocks.get(skill, []):
		if String(step["kind"]) == "perk" and int(step["level"]) <= level and (step["perk"] as Dictionary).has("bonus"):
			out.append(step["perk"]["bonus"])
	return out


# The steps passed when a skill goes from level `before` to `after`.
static func reached(unlocks: Dictionary, skill: String, before: int, after: int) -> Array:
	var out: Array = []
	for step: Dictionary in unlocks.get(skill, []):
		if int(step["level"]) > before and int(step["level"]) <= after:
			out.append(step)
	return out


# What is wrong with an unlocks table ([] = nothing). `known` = ids that content may open (nodes, recipes, logs,
# "slot"); content ids starting with "later:" belong to systems still to come.
static func problems(unlocks: Dictionary, skills: Dictionary, known: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	for skill: String in skills:
		var steps: Array = unlocks.get(skill, [])
		if steps.is_empty():
			continue
		if steps.size() != 10:
			out.append("%s has %d steps, not 10" % [skill, steps.size()])
		for i in steps.size():
			var step: Dictionary = steps[i]
			if int(step.get("level", 0)) != (i + 1) * 5:
				out.append("%s step %d is at level %s, not %d" % [skill, i + 1, str(step.get("level")), (i + 1) * 5])
			match String(step.get("kind", "")):
				"content":
					for id: String in step.get("ids", []):
						if id.begins_with("later:"):
							continue
						if not known.has(id):
							out.append("%s %d opens unknown %s" % [skill, int(step["level"]), id])
						elif int(known[id]) != int(step["level"]) and id != "slot":
							out.append("%s %d opens %s, which needs level %d" % [skill, int(step["level"]), id, int(known[id])])
				"perk":
					for key: String in step.get("perk", {}):
						if not KEYS.has(key):
							out.append("%s %d has unknown perk %s" % [skill, int(step["level"]), key])
				_:
					out.append("%s step %d has no kind" % [skill, i + 1])
			if String(step.get("name", "x")) == "":
				out.append("%s %d has no name" % [skill, int(step["level"])])
	return out
