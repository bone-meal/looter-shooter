# Purpose: MESSAGE IN A BOTTLE's red-text behaviour (diary/DESIGN_UNIQUES.md, rare world chase gun): a corked bottle with
# a rolled note rides on the pistol. Every kill reveals the next line of a sea shanty (data/uniques/writing/shanty.txt,
# his to edit), shown over the kill; every finished VERSE (verse_lines lines) is sent to the party chat and gives everyone
# a short buff (damage +buff_pct % for buff_seconds: each machine gives its own player the buff on game/net_chase.gd
# "verse"). After the last line the song starts again.
# Numbers in data/gun_uniques.json message_bottle "cfg".
# Dependencies: data/uniques/writing/shanty.txt; the holder's self_fx (start_clip), damage numbers; the session's net
# chat (net_session `chat`) for the verse.
extends Node3D

const SONG := "res://data/uniques/writing/shanty.txt"

var _player: Node3D
var _cfg: Dictionary = {}
var _lines: PackedStringArray = []
var next_line := 0
var verses := 0


func bind(player: Node3D, _gun: Dictionary, def: Dictionary) -> void:
	_player = player
	_cfg = def.get("cfg", {})
	_lines = song_lines()


func start(_gimmick: Node3D) -> void:
	pass


func stop() -> void:
	pass


func on_inspect() -> void:
	pass


static func song_lines() -> PackedStringArray:
	var out := PackedStringArray()
	for line in FileAccess.get_file_as_string(SONG).split("\n"):
		var clean := line.strip_edges()
		if clean != "" and not clean.begins_with("#"):
			out.append(clean)
	return out


func on_target_hit(_target: Node, at: Vector3, _amount: float, killed: bool) -> void:
	if not killed or _lines.is_empty():
		return
	var line := _lines[next_line % _lines.size()]
	next_line += 1
	var numbers: Variant = _player.get("damage_numbers")
	if numbers != null and (numbers as Object).has_method("say"):
		numbers.call("say", at + Vector3(0, 0.6, 0), line, Color(0.85, 0.95, 1.0))
	var per := int(_cfg.get("verse_lines", 4))
	if next_line % per != 0:
		return
	verses += 1
	var start_at := next_line - per
	var verse := PackedStringArray()
	for k in per:
		verse.append(_lines[(start_at + k) % _lines.size()])
	var link: Node = get_tree().get_first_node_in_group("net_chase") if is_inside_tree() else null
	var net: Variant = link.get("net") if link != null else null
	if net != null and net.get("chat") != null:
		net.get("chat").call("say", "~ " + " / ".join(verse) + " ~")
	buff(_player, _cfg)
	if link != null:
		link.call("send", "verse", -1, at, 0, at)


# The verse's buff on this machine's player.
static func buff(player: Node3D, cfg: Dictionary) -> void:
	var fx: Variant = player.get("self_fx") if player != null else null
	if fx != null:
		fx.call("start_clip", Time.get_ticks_msec() / 1000.0, float(cfg.get("buff_seconds", 10.0)), float(cfg.get("buff_pct", 20.0)))
