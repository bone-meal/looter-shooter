# Purpose: which script plays each chase gun's red-text behaviour (data/gun_uniques.json "signature" -> a node made
# here). A behaviour node lives under the player while its gun is in hand: start(gimmick), stop(), on_inspect().
# Dependencies: the scripts in game/signatures/.
extends RefCounted

const SCRIPTS := {
	"mixtape": preload("res://game/signatures/mixtape.gd"),
}


static func make(id: String) -> Node3D:
	return (SCRIPTS[id] as GDScript).new() if SCRIPTS.has(id) else null
