# Purpose: TREASURE MAP's X in the world (diary/DESIGN_UNIQUES.md, Vault chase gun): a red X on the ground with a faint
# tall beam over it so the whole party can find it (no sea chart exists yet: it stands in for "on every teammate's map").
# Pure picture; game/signatures/treasure_map.gd decides when one appears and who digs it up.
# Dependencies: none.
extends Node3D

const GROUP := "treasure_xs"

var owner_id := 0  # whose map put it there (0 = ours)
var slot := 0


func _ready() -> void:
	add_to_group(GROUP)
	var red := StandardMaterial3D.new()
	red.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	red.albedo_color = Color(0.85, 0.1, 0.08)
	for turn in [PI * 0.25, -PI * 0.25]:
		var bar := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.25, 0.03, 1.6)
		bar.mesh = box
		bar.material_override = red
		bar.rotation.y = turn
		bar.position.y = 0.03
		add_child(bar)
	var beam := MeshInstance3D.new()
	var tall := BoxMesh.new()
	tall.size = Vector3(0.12, 30.0, 0.12)
	beam.mesh = tall
	var glow := StandardMaterial3D.new()
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	glow.albedo_color = Color(0.5, 0.12, 0.08)
	beam.material_override = glow
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	beam.position.y = 15.0
	add_child(beam)


