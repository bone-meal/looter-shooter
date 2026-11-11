# Purpose: world pieces that belong to one look only. Flat-look pieces (the old sphere palm crowns) hide in the textured
# look; textured-look pieces (CC0 rocks, plants, iron gates) hide in the flat look. Scatter fields also thin out with
# the graphics tier ("props" in data/graphics.json). A hidden physics body also stops colliding.
# Dependencies: none. Configured by game/render_style.gd; pieces are registered by the world builders.
extends RefCounted

static var _pieces: Array = []    # [WeakRef to Node3D, textured look?]
static var _scatters: Array = []  # [WeakRef to MultiMeshInstance3D, full instance count]
static var _textured := false
static var _amount := 1.0


# `node` is visible only in the textured look (true) or only in the flat look (false).
static func add(node: Node3D, textured: bool) -> void:
	_pieces.append([weakref(node), textured])
	_show(node, textured == _textured)


# A textured-look scatter field. Fill the MultiMesh in random order first: the tier shows only the first part of it.
static func add_scatter(field: MultiMeshInstance3D) -> void:
	_scatters.append([weakref(field), field.multimesh.instance_count])
	_show_scatter(field, field.multimesh.instance_count)


static func configure(textured: bool, amount: float) -> void:
	_textured = textured
	_amount = clampf(amount, 0.0, 1.0)
	var live: Array = []
	for entry: Array in _pieces:
		var node := (entry[0] as WeakRef).get_ref() as Node3D
		if node != null:
			_show(node, bool(entry[1]) == _textured)
			live.append(entry)
	_pieces = live
	live = []
	for entry: Array in _scatters:
		var field := (entry[0] as WeakRef).get_ref() as MultiMeshInstance3D
		if field != null:
			_show_scatter(field, int(entry[1]))
			live.append(entry)
	_scatters = live


static func _show(node: Node3D, on: bool) -> void:
	node.visible = on
	if node is CollisionObject3D:
		node.process_mode = Node.PROCESS_MODE_INHERIT if on else Node.PROCESS_MODE_DISABLED


static func _show_scatter(field: MultiMeshInstance3D, full: int) -> void:
	field.visible = _textured
	field.multimesh.visible_instance_count = ceili(full * _amount)
