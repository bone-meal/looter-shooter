# Purpose: GHOST SHIPS (sea step 8d; director 2026-11-17: they PHASE IN AND OUT: see-through and glowing, cannon
# balls pass through her while she is faded, she turns solid to fire her broadside and can be hit then; her ghost
# crew boards like pirates; she fades away at dawn; sunk = spectral loot). A ghost ship is a foe of the fleet
# (game/sea_encounters.gd, kinds with "ghost": true) whose state carries "phase" (0 faded .. 1 solid). The HOST
# decides her phase: faded until she wants to fire, then solid for solid_s (the fade takes fade_s, she fires only
# once solid), faded again for rest_s. Every machine draws her by the phase it has (game/ghost_look.gd, eased).
# At dawn (the sea clock's daylight back over day_at) the host fades every ghost ship out and her men with her
# (also those on your deck). game/sea_cannons.gd lets a ball fly through a faded ship (passed counts them).
# Dependencies: game/ghost_look.gd, data/sea/encounters.json "ghosts"; the fleet (ships, remove_ship), the foes
# node (crews, rules, _night), the sea world (notice).
extends Node

const GhostLook = preload("res://game/ghost_look.gd")

var cfg: Dictionary  # encounters.json "ghosts"
var faded_out := 0  # dev / checks: ships faded away at dawn, solid windows opened
var windows := 0
var _fleet: Node3D
var _sea: Node3D
var _foes: Node
var _shown := {}  # ship -> the phase drawn here (eased toward her state's)
var _rng := RandomNumberGenerator.new()


func setup(fleet: Node3D, sea: Node3D, foes: Node, encounters: Dictionary) -> void:
	_fleet = fleet
	_sea = sea
	_foes = foes
	cfg = encounters["ghosts"]
	_rng.randomize()


static func is_ghost(ship: Node3D, kinds: Dictionary) -> bool:
	return bool(kinds.get(String((ship.get("state") as Dictionary).get("foe", "")), {}).get("ghost", false))


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


# Host: a ghost ship that came in starts faded.
func begin(ship: Node3D) -> void:
	var st: Dictionary = ship.get("state")
	st["phase"] = 0.0
	st["phase_to"] = 0.0
	st["rest_until"] = _now() + float(cfg["first_rest_s"])
	GhostLook.ship(ship, 0.0)


# Host: she wants to fire: true once she is solid (she starts turning solid when her rest is over).
func ready_to_fire(ship: Node3D) -> bool:
	var st: Dictionary = ship.get("state")
	var now := _now()
	if st.has("dawn_t"):
		return false  # fading out at first light
	if float(st.get("phase_to", 0.0)) < 0.5 and now >= float(st.get("rest_until", 0.0)):
		st["phase_to"] = 1.0
		st["solid_until"] = now + float(cfg["fade_s"]) + float(cfg["solid_s"])
		windows += 1
	return float(st.get("phase", 0.0)) >= 0.95


func _process(delta: float) -> void:
	if _fleet == null or not bool(_sea.call("running")):
		return
	var net: Node = _fleet.call("_net")
	var host := net == null or not bool(net.call("is_client"))
	var kinds: Dictionary = _foes.get("rules").cfg["kinds"]
	var dawn := host and not bool(_foes.call("_night"))
	for ship: Node3D in _fleet.get("ships"):
		if not is_ghost(ship, kinds):
			continue
		var st: Dictionary = ship.get("state")
		if host:
			_step(ship, st, delta, dawn)
		var want := float(st.get("phase", 0.0)) * (1.0 - float(st.get("dawn_t", 0.0)))
		var shown := move_toward(float(_shown.get(ship, 0.0)), want, delta / maxf(float(cfg["fade_s"]), 0.05))
		_shown[ship] = shown
		GhostLook.ship(ship, shown)
		ship.visible = float(st.get("dawn_t", 0.0)) < 1.0
	for gone: Variant in _shown.keys():  # (untyped: a freed ship cannot be held in a typed variable)
		if not is_instance_valid(gone):
			_shown.erase(gone)


func _step(ship: Node3D, st: Dictionary, delta: float, dawn: bool) -> void:
	var now := _now()
	if float(st.get("phase_to", 0.0)) > 0.5 and now >= float(st.get("solid_until", 0.0)):
		st["phase_to"] = 0.0
		var r: Array = cfg["rest_s"]
		st["rest_until"] = now + _rng.randf_range(float(r[0]), float(r[1]))
	st["phase"] = move_toward(float(st.get("phase", 0.0)), float(st.get("phase_to", 0.0)), delta / maxf(float(cfg["fade_s"]), 0.05))
	if dawn:  # first light: she fades out with her men and is gone
		st["phase_to"] = 0.0
		st["dawn_t"] = minf(float(st.get("dawn_t", 0.0)) + delta / float(cfg["dawn_fade_s"]), 1.0)
		if float(st["dawn_t"]) >= 1.0 and not bool(st.get("gone", false)):
			st["gone"] = true
			faded_out += 1
			(_foes.get("crews") as Node).call("vanish", "ghost_")
			_fleet.call("remove_ship", ship)
			_sea.emit_signal("notice", String(cfg["dawn_notice"]))


func status() -> String:
	var parts := PackedStringArray()
	var kinds: Dictionary = _foes.get("rules").cfg["kinds"]
	for ship: Node3D in _fleet.get("ships"):
		if is_ghost(ship, kinds):
			var st: Dictionary = ship.get("state")
			parts.append("phase %.2f%s" % [float(st.get("phase", 0.0)), " dawn %.2f" % float(st["dawn_t"]) if st.has("dawn_t") else ""])
	return "ghosts %d [%s], windows %d, faded at dawn %d, balls through %d" % [parts.size(), ", ".join(parts), windows, faded_out, int((_fleet.get("cannons") as Node).get("passed"))]
