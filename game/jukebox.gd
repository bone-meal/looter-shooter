# Purpose: the club's jukebox: a rounded cabinet with a glowing arch and a speaker grille. Draws only; the session
# opens game/music_menu.gd when a player interacts with it.
# Dependencies: none.
extends StaticBody3D

const REACH := 2.4


func _ready() -> void:
	var cabinet := StandardMaterial3D.new()
	cabinet.albedo_color = Color(0.35, 0.12, 0.08)
	cabinet.roughness = 0.4
	cabinet.emission_enabled = true  # a faint self-glow so the cabinet reads in the dark club (no extra light)
	cabinet.emission = Color(0.5, 0.15, 0.08)
	cabinet.emission_energy_multiplier = 0.6
	var glow := StandardMaterial3D.new()
	glow.albedo_color = Color(1.0, 0.55, 0.15)
	glow.emission_enabled = true
	glow.emission = Color(1.0, 0.45, 0.1)
	glow.emission_energy_multiplier = 2.0
	var grille := StandardMaterial3D.new()
	grille.albedo_color = Color(0.1, 0.08, 0.07)
	_box(Vector3(1.0, 1.4, 0.6), Vector3(0, 0.7, 0), cabinet)
	var arch := MeshInstance3D.new()
	var arch_mesh := CylinderMesh.new()
	arch_mesh.top_radius = 0.5
	arch_mesh.bottom_radius = 0.5
	arch_mesh.height = 0.6
	arch.mesh = arch_mesh
	arch.material_override = cabinet
	arch.rotation.x = PI * 0.5
	arch.position = Vector3(0, 1.4, 0)
	add_child(arch)
	_box(Vector3(0.9, 0.08, 0.05), Vector3(0, 1.38, -0.31), glow)
	_box(Vector3(0.08, 1.2, 0.05), Vector3(-0.42, 0.75, -0.31), glow)
	_box(Vector3(0.08, 1.2, 0.05), Vector3(0.42, 0.75, -0.31), glow)
	_box(Vector3(0.6, 0.5, 0.04), Vector3(0, 0.45, -0.31), grille)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.0, 1.9, 0.6)
	shape.shape = box
	shape.position = Vector3(0, 0.95, 0)
	add_child(shape)


func _box(size: Vector3, at: Vector3, material: Material) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	var piece := MeshInstance3D.new()
	piece.mesh = mesh
	piece.material_override = material
	piece.position = at
	add_child(piece)
