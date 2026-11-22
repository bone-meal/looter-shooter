# Purpose: log `git status --porcelain` (what is changed but not pushed) without committing.
# Log: tools/git_status.log. Depends on: tools/git_cli.gd.
extends Node

const GitCli = preload("res://tools/git_cli.gd")

func _ready() -> void:
	var g = GitCli.new(ProjectSettings.globalize_path("res://tools/git_status.log"))
	g.run("git", PackedStringArray(["status", "--porcelain"]))
	g.close()
	get_tree().quit()
