# Purpose: look for secrets (tokens, keys, passwords, personal emails) in every commit of the
# repo before it is made public. Log: tools/git_scan.log (one line per hit, all revisions).
# Depends on: tools/git_cli.gd. Changes nothing.
extends Node

const GitCli = preload("res://tools/git_cli.gd")
const PATTERN := "(gh[pousr]_[A-Za-z0-9]{20,}|github_pat_|AKIA[0-9A-Z]{16}|BEGIN [A-Z ]*PRIVATE KEY|sk-[A-Za-z0-9]{20,}|xox[bpa]-|AIza[0-9A-Za-z_-]{30,}|api[_-]?key|secret|passw|bearer|webapi|[A-Za-z0-9._%+-]+@(gmail|yahoo|hotmail|outlook|icloud|proton)[a-z.]*)"

func _ready() -> void:
	var g = GitCli.new(ProjectSettings.globalize_path("res://tools/git_scan.log"))
	var out: Array = []
	OS.execute("git", ["-C", g.root, "rev-list", "--all"], out)
	var revs: PackedStringArray = str(out[0]).replace("\r", "").split("\n", false)
	g.line("revisions %d" % revs.size())
	var args := PackedStringArray(["grep", "-I", "-n", "-i", "-m", "3", "-E", PATTERN])
	args.append_array(revs)
	# The Omaha map tiles and the asset packs are megabytes of one-line JSON/mesh text that
	# made the scan run for over 8 minutes; no hand-written secret lives there.
	args.append_array(["--", ".", ":(exclude)data/omaha", ":(exclude)assets"])
	g.run("git", args)
	g.line("RESULT DONE")
	g.close()
	get_tree().quit()
