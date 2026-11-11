# Purpose: commit everything and push to GitHub at the end of a work round.
# Message comes from tools/git_message.txt (first line = subject). Log: tools/git_push.log.
# Depends on: tools/git_cli.gd, an existing repo with remote "origin" (see git_setup).
extends Node

const GitCli = preload("res://tools/git_cli.gd")

func _ready() -> void:
	var g = GitCli.new(ProjectSettings.globalize_path("res://tools/git_push.log"))
	var msg: String = "Work round"
	if FileAccess.file_exists("res://tools/git_message.txt"):
		msg = FileAccess.get_file_as_string("res://tools/git_message.txt").strip_edges()
	g.run("git", ["add", "-A"])
	g.run("git", ["commit", "-m", msg])  # exit 1 = nothing to commit, fine
	var code: int = g.run("git", ["push", "origin", "HEAD"])
	g.line("RESULT " + ("OK" if code == 0 else "PUSH FAILED"))
	g.close()
	get_tree().quit()
