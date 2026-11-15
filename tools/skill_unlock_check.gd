# Purpose: developer check of sea step 3's skill milestones (data/fantasy/skilling.json "unlocks"): fifteen skills,
# ten steps each at levels 5 ... 50, content steps open things that exist at exactly that level, perk keys are known,
# every step has its name and line in writing/skills.txt, and what each perk adds up to at a few levels. Things to
# gather or make that no milestone names are listed (not counted as problems: old recipes waiting for their skill).
# Writes tools/skill_unlock_check.log ("SKILL_UNLOCKS problems=n"). Run scene tools/skill_unlock_check.tscn.
# Dependencies: core/fantasy_data.gd, core/skill_perks.gd.
extends Node

const FantasyData = preload("res://core/fantasy_data.gd")
const SkillPerks = preload("res://core/skill_perks.gd")

var _lines := PackedStringArray()
var _problems := 0


func _ready() -> void:
	var all := FantasyData.load_all()
	var skilling: Dictionary = all["skilling"]
	var unlocks: Dictionary = skilling.get("unlocks", {})
	_check((skilling["skills"] as Dictionary).size() == 15, "15 skills (%d)" % (skilling["skills"] as Dictionary).size())
	var known := {"slot": 0}
	for id: String in skilling["nodes"]:
		known[id] = int(skilling["nodes"][id]["level"])
	for recipe: Dictionary in skilling["recipes"]:
		known[String(recipe["id"])] = int(recipe["level"])
	for log_id: String in skilling["fire"]["level"]:
		known[log_id] = int(skilling["fire"]["level"][log_id])
	for animal: String in all["enemies"]["enemies"]:  # wild animals (Hunting) a step may open
		if all["enemies"]["enemies"][animal].has("skill"):
			known[animal] = int(all["enemies"]["enemies"][animal]["level"])
	for problem in SkillPerks.problems(unlocks, skilling["skills"], known):
		_check(false, problem)
	for text_problem: String in all["problems"]:
		if text_problem.contains("[unlock ") or text_problem.contains("[skill "):
			_check(false, text_problem)
	var listed := {}
	for skill: String in unlocks:
		for step: Dictionary in unlocks[skill]:
			for id: String in step.get("ids", []):
				listed[id] = skill
	for id: String in known:
		if int(known[id]) > 1 and not listed.has(id):
			_lines.append("  not on a milestone (level %d): %s" % [int(known[id]), id])
	for skill: String in skilling["skills"]:
		var steps: Array = unlocks.get(skill, [])
		_lines.append("%s: %d steps%s" % [skill, steps.size(), "" if steps.is_empty() else ", e.g. 25 = %s (%s)" % [String(steps[4]["name"]), String(steps[4]["about"])]])
	var level50 := SkillPerks.total(unlocks, "woodcutting", 50, "double")
	_check(is_equal_approx(level50, 0.25), "woodcutting double at 50 = 0.25 (%.2f)" % level50)
	_check(is_equal_approx(SkillPerks.total(unlocks, "woodcutting", 19, "double"), 0.0), "woodcutting double at 19 = 0")
	_check(SkillPerks.bonus_finds(unlocks, "mining", 40).size() == 2, "mining has 2 extra finds at 40")
	_check(SkillPerks.reached(unlocks, "farming", 44, 45).size() == 1, "farming 44 -> 45 reaches one milestone")
	_lines.append("SKILL_UNLOCKS problems=%d" % _problems)
	var f := FileAccess.open("res://tools/skill_unlock_check.log", FileAccess.WRITE)
	f.store_string("\n".join(_lines) + "\n")
	f.close()
	get_tree().quit()


func _check(ok: bool, what: String) -> void:
	_lines.append(("ok   " if ok else "FAIL ") + what)
	if not ok:
		_problems += 1
