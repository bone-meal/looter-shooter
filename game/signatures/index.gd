# Purpose: which script plays each chase gun's red-text behaviour (data/gun_uniques.json "signature" -> a node made
# here). A behaviour node lives under the player while its gun is in hand: start(gimmick), stop(), on_inspect(); optional bind(player, gun, def) first, on_hit_total(at, amount, killed) -> shown number, damage_mult(), fire_projectile(origin, dir, stats) instead of a grenade / rocket, extra_jumps(), after_shot(origin, dir) after a hitscan shot, held_suffix() for what others see after "#".
# Dependencies: the scripts in game/signatures/.
extends RefCounted

const SCRIPTS := {
	"mixtape": preload("res://game/signatures/mixtape.gd"),
	"fish_story": preload("res://game/signatures/fish_story.gd"),
	"beach_ball": preload("res://game/signatures/beach_ball.gd"),
	"croak": preload("res://game/signatures/croak.gd"),
	"swamp_gas": preload("res://game/signatures/swamp_gas.gd"),
	"keepers_lantern": preload("res://game/signatures/keepers_lantern.gd"),
}


static func make(id: String) -> Node3D:
	return (SCRIPTS[id] as GDScript).new() if SCRIPTS.has(id) else null
