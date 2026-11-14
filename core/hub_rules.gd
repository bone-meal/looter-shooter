# Purpose: the safe hub's rules (locked: diary/DECISIONS_HUB.md). Everyone in the hub sees a countdown (60 s); when
# it runs out everyone goes to the island. Anyone may press the red button: the countdown stops for good, and from
# then on only "everyone ready" sends the group. A player is ready after holding F for 5 s ON THE STAGE; pressing F
# again or stepping off the stage un-readies. Every player in the hub counts (card players and AFK players hold the
# group). Pure rules, no nodes: the host (or a player alone) feeds it who is where and who holds F.
# Dependencies: none. Data: data/hub.json, passed to the constructor.
extends RefCounted

var cfg: Dictionary
var left := 60.0  # seconds of countdown left (stops for good once the button is pressed)
var button := false
var launched := false
var players := {}  # peer -> {"stage": bool, "ready": bool, "hold": float, "was_held": bool, "need_release": bool}


func _init(config: Dictionary) -> void:
	cfg = config
	left = float(cfg.get("countdown", 60.0))


func join(peer: int) -> void:
	if not players.has(peer):
		players[peer] = {"stage": false, "ready": false, "hold": 0.0, "was_held": false, "need_release": false}


# Gone from the hub (to the island, into the Aurelind painting, or out of the game): no longer counted.
func leave(peer: int) -> void:
	players.erase(peer)


func press_button() -> void:
	button = true


# Where everyone stands: peer -> on the stage or not. Stepping off un-readies.
func set_stage(peer: int, on: bool) -> void:
	if not players.has(peer):
		return
	var p: Dictionary = players[peer]
	p["stage"] = on
	if not on:
		p["ready"] = false
		p["hold"] = 0.0


# One step of time. held = peer -> F held now. Returns true the moment the group goes (countdown out, or all ready).
func tick(dt: float, held: Dictionary) -> bool:
	if launched:
		return false
	for peer: int in players:
		var p: Dictionary = players[peer]
		var down := bool(held.get(peer, false))
		if down and not bool(p["was_held"]) and bool(p["ready"]):  # F again: not ready any more
			p["ready"] = false
			p["need_release"] = true
		if not down:
			p["hold"] = 0.0
			p["need_release"] = false
		elif bool(p["stage"]) and not bool(p["ready"]) and not bool(p["need_release"]):
			p["hold"] = float(p["hold"]) + dt
			if float(p["hold"]) >= float(cfg.get("hold", 5.0)):
				p["ready"] = true
				p["hold"] = 0.0
				p["need_release"] = true
		p["was_held"] = down
	if everyone_ready():
		launched = true
		return true
	if not button and not players.is_empty():
		left = maxf(left - dt, 0.0)
		if left <= 0.0:
			launched = true
			return true
	return false


func everyone_ready() -> bool:
	if players.is_empty():
		return false
	for peer: int in players:
		if not bool(players[peer]["ready"]):
			return false
	return true


func ready_count() -> int:
	var n := 0
	for peer: int in players:
		if bool(players[peer]["ready"]):
			n += 1
	return n


# Is a hub-local point on the stage? (x / z in metres from the hub's middle)
func on_stage(x: float, z: float) -> bool:
	var r: Array = cfg.get("stage", [0, 0, 0, 0])
	return x >= float(r[0]) and x <= float(r[2]) and z >= float(r[1]) and z <= float(r[3])


# Is a hub-local point inside the hub (the hall or the trophy room)?
func inside(x: float, z: float) -> bool:
	var s: Array = cfg.get("size", [50, 30])
	if absf(x) <= float(s[0]) * 0.5 and absf(z) <= float(s[1]) * 0.5:
		return true
	var t: Array = cfg.get("trophy_room", [0, 0, 0, 0])
	return x >= float(t[0]) and x <= float(t[2]) and z >= float(t[1]) and z <= float(t[3])


# What the HUD shows: {"left", "button", "ready", "total", "players": {peer: {"ready", "hold" (0..1), "stage"}}}.
func view() -> Dictionary:
	var out := {}
	for peer: int in players:
		var p: Dictionary = players[peer]
		out[peer] = {"ready": bool(p["ready"]), "hold": clampf(float(p["hold"]) / float(cfg.get("hold", 5.0)), 0.0, 1.0), "stage": bool(p["stage"])}
	return {"left": left, "button": button, "ready": ready_count(), "total": players.size(), "players": out}
