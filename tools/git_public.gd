# Purpose: one-off: make the origin GitHub repo public (director, 2026-11-12) and log the result.
# Log: tools/git_public.log. Depends on: tools/git_cli.gd, gh logged in.
extends Node

const GitCli = preload("res://tools/git_cli.gd")
const GH_EXE := "C:/Program Files/GitHub CLI/gh.exe"

func _ready() -> void:
	var g = GitCli.new(ProjectSettings.globalize_path("res://tools/git_public.log"))
	var url_out: Array = []
	OS.execute("git", ["-C", g.root, "remote", "get-url", "origin"], url_out)
	var repo: String = str(url_out[0]).strip_edges().trim_suffix(".git").replace("https://github.com/", "")
	var code: int = g.run("gh", ["repo", "edit", repo, "--visibility", "public",
		"--accept-visibility-change-consequences"])
	g.run("gh", ["repo", "view", repo, "--json", "visibility,url"])
	g.line("RESULT " + ("OK" if code == 0 else "FAILED"))
	g.close()
	get_tree().quit()
