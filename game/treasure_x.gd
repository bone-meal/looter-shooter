# Purpose: TREASURE MAP's X in the world (diary/DESIGN_UNIQUES.md, Vault chase gun): a red X on the ground with a faint
# tall beam over it so the whole party can find it (no sea chart exists yet: it stands in for "on every teammate's map").
# Pure picture; game/signatures/treasure_map.gd decides when one appears and who digs it up.
# Drawn with the x_mark and dirt_mound models and a fading shaft (game/fx_kit.gd).
# Dependencies: game/fx_kit.gd.
extends Node3D

const FxKit = preload("res://game/fx_kit.gd")

const GROUP := "treasure_xs"

var owner_id := 0  # whose map put it there (0 = ours)
var slot := 0


func _ready() -> void:
	add_to_group(GROUP)
	var mark: Node3D = FxKit.shape("x_mark")  # a painted X of two rough strokes and a heap of earth by it
	if mark != null:
		FxKit.paint(mark, _paint())
		add_child(mark)
	var mound: Node3D = FxKit.shape("dirt_mound")
	if mound != null:
		mound.position = Vector3(0.9, 0.0, 0.5)
		add_child(mound)
	var beam := MeshInstance3D.new()  # a faint red shaft so the party can find it from afar
	var shaft := CylinderMesh.new()
	shaft.top_radius = 0.05
	shaft.bottom_radius = 0.25
	shaft.height = 30.0
	shaft.radial_segments = 8
	shaft.rings = 1
	shaft.cap_top = false
	shaft.cap_bottom = false
	beam.mesh = shaft
	beam.material_override = FxKit.glow(Color(0.9, 0.25, 0.15, 0.25), true, FxKit.fade_down())
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	beam.position.y = 15.0
	add_child(beam)


# The X's paint: a lit red, so it sits on the ground like paint, not like a light.
static func _paint() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.7, 0.07, 0.05)
	mat.roughness = 0.9
	return mat
