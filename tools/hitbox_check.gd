# Purpose: developer check of the enemies' hit volumes (bug update): every reworked enemy (game/enemy.gd on a folded
# model) standing and mid-stride is shot from the front at its head and its chest; reports whether the shot lands, on
# the head or not, where the head sits against the old movement box (head share, outside the box) and the cost of a
# test. Prints HITBOX lines; run headless: --script res://tools/hitbox_check.gd
# Dependencies: game/enemy.gd, game/rigid_skin.gd, data/island_rounds.json, data/enemies.json.
extends SceneTree

const Enemy = preload("res://game/enemy.gd")


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var lists := {}
	var isl: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/island_rounds.json"))["enemies"]
	var col: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/enemies.json"))["enemies"]
	for id: String in isl:
		lists[id] = isl[id]
	for id: String in col:
		if String((col[id] as Dictionary).get("model", "")).begins_with("en_"):
			lists[id] = col[id]
	var problems := 0
	var x := 0.0
	for id: String in lists:
		var stats: Dictionary = (lists[id] as Dictionary).duplicate(true)
		var e: CharacterBody3D = Enemy.new()
		e.configure(id, stats, null, null, null)
		root.add_child(e)
		e.position = Vector3(x, 0, 0)
		x += 8.0
		await process_frame
		e.set_physics_process(false)
		e.set_process(false)
		var rig: Variant = e.get("_rig")
		var skin: Skeleton3D = e.get("_skin")
		if skin == null or rig == null:
			print("HITBOX skip %s (not reworked)" % id)
			continue
		for state in ["stand", "stride"]:
			for k in 12:
				rig.call("pose", 0.05, 0.0 if state == "stand" else float(stats.get("speed", 3.0)), float(k) * 0.5, 0.0, 0.0, 0.0, 0.0, false)
			var head := _centre(e, skin, true)
			var chest := _centre(e, skin, false)
			var top := _top(e, skin)
			var size: Vector3 = e.get("_size")
			var share := (head.y - e.global_position.y) / size.y
			var tall := (top - e.global_position.y) / size.y
			var outside := absf(head.x - e.global_position.x) > size.x * 0.5 or absf(head.z - e.global_position.z) > size.z * 0.5
			var t0 := Time.get_ticks_usec()
			var hh: Dictionary = e.call("ray_parts", head + Vector3(0, 0, 6), head - Vector3(0, 0, 6))
			var hh2: Dictionary = e.call("ray_parts", head - Vector3(0, 0, 6), head + Vector3(0, 0, 6))
			var us := float(Time.get_ticks_usec() - t0) * 0.5
			var ch: Dictionary = e.call("ray_parts", chest + Vector3(0, 0, 6), chest - Vector3(0, 0, 6))
			var ch2: Dictionary = e.call("ray_parts", chest - Vector3(0, 0, 6), chest + Vector3(0, 0, 6))
			if head == Vector3.INF:
				hh = {"head": true}
			var head_ok := (not hh.is_empty() and bool(hh["head"])) or (not hh2.is_empty() and bool(hh2["head"]))
			var chest_ok := (not ch.is_empty() and not bool(ch["head"])) or (not ch2.is_empty() and not bool(ch2["head"]))
			for axis: Vector3 in [Vector3.RIGHT, Vector3.UP]:  # (a glider hangs face down: across or from below)
				var c3: Dictionary = e.call("ray_parts", chest + axis * 6.0, chest - axis * 6.0)
				chest_ok = chest_ok or (not c3.is_empty() and not bool(c3["head"]))
			var old_head := share >= 1.0 - 0.17
			var ok := head_ok and chest_ok
			if not ok:
				problems += 1
			print("HITBOX %s %-15s %-6s model top %.2f of box, head at %.2f (old head zone %s), head outside box %s, head shot %s, chest shot %s, %.0f us a test" % ["ok  " if ok else "FAIL", id, state, tall, share, "yes" if old_head else "NO", str(outside), str(head_ok), str(chest_ok), us])
	print("HITBOX_DONE problems=%d" % problems)
	quit()


# Middle of the shown head pieces (head) or of the body pieces between the hips and the head (not head), world space.
func _centre(e: Node3D, skin: Skeleton3D, head: bool) -> Vector3:
	var boxes: Array = e.get("_boxes")
	var heads: PackedByteArray = e.get("_heads")
	var sum := Vector3.ZERO
	var n := 0.0
	var lo := INF
	var hi := -INF
	var hb := skin.find_bone("Head")
	if head and hb >= 0 and (boxes[hb] as AABB).size != Vector3.ZERO:  # the head piece itself
		return skin.global_transform * skin.get_bone_global_pose(hb) * (boxes[hb] as AABB).get_center()
	for i in boxes.size():
		var box: AABB = boxes[i]
		var xf := skin.global_transform * skin.get_bone_global_pose(i)
		if box.size == Vector3.ZERO or xf.basis.x.length_squared() < 1e-6:
			continue
		var c := xf * box.get_center()
		if (heads[i] == 1) == head:
			if head:
				var w := box.get_volume() + 1e-6
				sum += c * w
				n += w
			else:
				lo = minf(lo, c.y)
				hi = maxf(hi, c.y)
	if head:
		return sum / n if n > 0.0 else Vector3.INF
	var mid := (lo + hi) * 0.5
	var best := Vector3.INF  # the body piece centre nearest the body's mid height
	for i in boxes.size():
		var box: AABB = boxes[i]
		var xf := skin.global_transform * skin.get_bone_global_pose(i)
		if box.size == Vector3.ZERO or xf.basis.x.length_squared() < 1e-6 or heads[i] == 1 or box.get_volume() < 0.002:
			continue
		var c := xf * box.get_center()
		if best == Vector3.INF or absf(c.y - mid) + Vector2(c.x - e.global_position.x, c.z - e.global_position.z).length() < absf(best.y - mid) + Vector2(best.x - e.global_position.x, best.z - e.global_position.z).length():
			best = c
	return best


func _top(e: Node3D, skin: Skeleton3D) -> float:
	var boxes: Array = e.get("_boxes")
	var top := -INF
	for i in boxes.size():
		var box: AABB = boxes[i]
		var xf := skin.global_transform * skin.get_bone_global_pose(i)
		if box.size == Vector3.ZERO or xf.basis.x.length_squared() < 1e-6:
			continue
		for c in 8:
			top = maxf(top, (xf * box.get_endpoint(c)).y)
	return top
