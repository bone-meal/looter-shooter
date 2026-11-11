# Purpose: one-time repo creation: git init + LFS, size report, first commit,
# private GitHub repo via gh. Stops before pushing if the LFS total is over LFS_LIMIT_MB.
# Log: tools/git_setup.log. Depends on: tools/git_cli.gd, .gitignore, .gitattributes.
extends Node

const GitCli = preload("res://tools/git_cli.gd")
const REPO_NAME := "looter-shooter"
const GH_EXE := "C:/Program Files/GitHub CLI/gh.exe"
const LFS_LIMIT_MB := 1500.0  # GitHub Free LFS = 10 GiB storage / 10 GiB bandwidth a month
const LFS_EXT := ["glb", "blend", "fbx", "png", "jpg", "jpeg", "webp", "exr", "hdr",
	"ogg", "wav", "mp3", "zip", "res", "scn", "mesh"]

func _ready() -> void:
	var g = GitCli.new(ProjectSettings.globalize_path("res://tools/git_setup.log"))
	if g.run("git", ["--version"]) != 0 or g.run("gh", ["auth", "status"]) != 0:
		g.line("RESULT STOP: install Git + GitHub CLI and run gh auth login")
		_done(g)
		return
	if not DirAccess.dir_exists_absolute(g.root + "/.git"):
		g.run("git", ["init", "-b", "main"])
	g.run("git", ["lfs", "install", "--local"])
	# Unstage anything staged before it was ignored (the source zips).
	g.run("git", ["rm", "-r", "-q", "--cached", "--ignore-unmatch", "assets/cc0/_zips"])
	g.run("git", ["add", "-A"])
	if not _size_ok(g):
		_done(g)
		return
	_ensure_identity(g)
	if g.run("git", ["rev-parse", "--verify", "HEAD"]) != 0:
		if g.run("git", ["commit", "-q", "-m", "Initial import"]) != 0:
			g.line("RESULT STOP: commit failed")
			_done(g)
			return
	var has_origin: bool = g.run("git", ["remote", "get-url", "origin"]) == 0
	if not has_origin and g.run("gh", ["repo", "view", REPO_NAME]) == 0:
		var url_out: Array = []
		OS.execute(GH_EXE, ["repo", "view", REPO_NAME, "--json", "url", "--jq", ".url"], url_out)
		has_origin = g.run("git", ["remote", "add", "origin", str(url_out[0]).strip_edges() + ".git"]) == 0
	var code: int
	if has_origin:
		code = g.run("git", ["push", "-u", "origin", "main"])
	else:
		var args := PackedStringArray(["repo", "create", REPO_NAME, "--private",
			"--source", g.root, "--remote", "origin", "--push"])
		code = g.run("gh", args)
	g.line("RESULT " + ("OK" if code == 0 else "PUSH FAILED"))
	_done(g)

# Sums staged file sizes, LFS vs plain, and lists the 15 biggest.
func _size_ok(g) -> bool:
	var out: Array = []
	# Plain lines: Godot's output reader breaks on the NUL bytes of `ls-files -z`.
	OS.execute("git", ["-C", g.root, "-c", "core.quotepath=off", "ls-files"], out)
	var files: PackedStringArray = str(out[0]).replace("\r", "").split("\n", false)
	var lfs_mb: float = 0.0
	var plain_mb: float = 0.0
	var big: Array = []
	for f in files:
		var fa := FileAccess.open(g.root + "/" + f, FileAccess.READ)
		if fa == null:
			continue
		var mb: float = fa.get_length() / 1048576.0
		if LFS_EXT.has(f.get_extension().to_lower()):
			lfs_mb += mb
		else:
			plain_mb += mb
		big.append([mb, f])
	big.sort_custom(func(a, b): return a[0] > b[0])
	g.line("files %d  plain %.1f MB  lfs %.1f MB" % [files.size(), plain_mb, lfs_mb])
	for i in mini(15, big.size()):
		g.line("  %.1f MB  %s" % [big[i][0], big[i][1]])
	if lfs_mb > LFS_LIMIT_MB:
		g.line("RESULT STOP: LFS total over %.0f MB, nothing committed" % LFS_LIMIT_MB)
		return false
	return true

# Repo-local author = the GitHub account with its private noreply address.
func _ensure_identity(g) -> void:
	if g.run("git", ["config", "user.email"]) == 0:
		return
	var out: Array = []
	OS.execute(GH_EXE, ["api", "user", "--jq", ".id,.login"], out)
	var parts: PackedStringArray = str(out[0]).strip_edges().replace("\r", "").split("\n")
	if parts.size() < 2:
		return
	g.run("git", ["config", "user.name", parts[1]])
	g.run("git", ["config", "user.email", "%s+%s@users.noreply.github.com" % [parts[0], parts[1]]])

func _done(g) -> void:
	g.close()
	get_tree().quit()
