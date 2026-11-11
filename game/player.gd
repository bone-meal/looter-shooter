# Purpose: local player: movement, mouse look, hitscan shooting, inventory + hotbar (the held hotbar item picks the weapon), weapon animation, first/third-person view (B toggles).
# Dependencies: game/weapon_models.gd, game/character_models.gd, core/viewmodel_motion.gd, core/weapon_state.gd, core/data_store.gd,
# core/health_state.gd, core/settings_state.gd, core/item_db.gd, core/inventory_state.gd, core/armor_math.gd, core/status_state.gd, game/cigarette_model.gd. Input actions come from game/input_setup.gd.
# Movement runs in _process (every rendered frame, physics interpolation off for the player, head and body model) so the view and the
# visible body always move together with no interpolation lag. Enemies and projectiles still use the fixed tick.
extends CharacterBody3D

signal damaged
signal died  # health hit zero; the game session decides where to respawn
signal blocked  # a hit was fully blocked by armor

const WeaponState = preload("res://core/weapon_state.gd")
const WeaponModels = preload("res://game/weapon_models.gd")
const PonySkin = preload("res://game/pony_skin.gd")
const SkillState = preload("res://core/skill_state.gd")
const BodyBuilder = preload("res://game/body_builder.gd")
const RiggedBody = preload("res://game/rigged_body.gd")
const GunPartsView = preload("res://game/gun_parts_view.gd")
const AppearanceData = preload("res://game/appearance_data.gd")
const ViewmodelMotion = preload("res://core/viewmodel_motion.gd")
const DataStore = preload("res://core/data_store.gd")
const HealthState = preload("res://core/health_state.gd")
const SettingsState = preload("res://core/settings_state.gd")
const WormModel = preload("res://game/worm_model.gd")
const ArmorMath = preload("res://core/armor_math.gd")
const StatusState = preload("res://core/status_state.gd")
const CigaretteModel = preload("res://game/cigarette_model.gd")
const Explosives = preload("res://game/explosives.gd")
const DamageNumbers = preload("res://game/damage_numbers.gd")
const ItemDb = preload("res://core/item_db.gd")
const GunDb = preload("res://core/gun_db.gd")
const GunStats = preload("res://core/gun_stats.gd")
const InventoryState = preload("res://core/inventory_state.gd")
const DancePoses = preload("res://game/dance_poses.gd")
const BodyMotion = preload("res://game/body_motion.gd")
const EmoteWheel = preload("res://game/emote_wheel.gd")

const SPEED := 7.0
const JUMP_SPEED := 5.5
const SHOT_RANGE := 200.0
const HEAD_HEIGHT := 1.6
const FIRST_PERSON_CAM := Vector3(0, 0, 0)
const THIRD_PERSON_CAM := Vector3(0.9, 0.35, 2.8)   # over the right shoulder
const THIRD_PERSON_HOLD := Vector3(0.26, -0.3, -0.5)  # weapon position relative to the head in third person
const CAMERA_PADDING := 0.25
const ORBIT_CAM := Vector3(0.0, 0.3, 3.4)  # camera offset while orbiting with H held
const LOOT_HOLD := Vector3(0.28, -0.26, -0.55)  # first-person position of a held loot item
const MAX_STEP := 1.0 / 30.0  # longest movement step, so a frame hitch can't tunnel through floors
const FALL_LIMIT := -6.0
const BERSERK_MAX := 10
const BERSERK_SECONDS := 3.0
const GLASS_HEALTH := 0.65  # max health multiplier with the Glass Cannon buff
const OVERKILL_RANGE := 5.0
const VIEW_KICK_RECOVERY := 5.0  # per second: how fast the scoped view settles back after a shot

var third_person := false
var emote := ""  # id of the dance playing, "" = none
var weapon: WeaponState  # currently held weapon
var gun_db: GunDb  # tiers, parts and makers for rolled guns
var health: HealthState
var settings: SettingsState  # set by game/game_session.gd before add_child
var inventory: InventoryState
var items: ItemDb
var status: StatusState  # burning / poisoned / chilled timers
var armor := {}  # totals from core/armor_math.gd, refreshed by refresh_equipment()
var carried := false  # true while the crow carries the player (movement is driven from outside)
var controls_enabled := true  # false while the inventory screen is open
var damage_numbers: DamageNumbers  # optional; game/damage_numbers.gd
var explosives: Explosives  # rocket/grenade pool, set by game/game_session.gd
var skill_fx: Node3D  # world effects of gun skills (game/skill_effects.gd), set by game/game_session.gd
var skills := SkillState.new()  # cooldowns of the Q/E gun skills

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _head := Node3D.new()
var _wheel := EmoteWheel.new()
var _wheel_open := false
var _wheel_mouse := Vector2.ZERO
var _orbit_yaw := 0.0
var _orbit_pitch := 0.0
var _emote_t := 0.0
var _view_before_emote := false
var _camera := Camera3D.new()
var appearance := {}  # how the body looks (see core/appearance_db.gd); set with set_appearance
var _visual: Node3D  # third-person holder (top level, follows the player)
var _body: Node3D  # the body model inside _visual (rigged, or code-built when the character packs are missing)
var _third_person_hold := THIRD_PERSON_HOLD  # rigged bodies move it to the hands of their weapon pose
var _spawn_position: Vector3
var _yaw := 0.0
var _walk_phase := 0.0
var _weapons: Array[WeaponState] = []
var _models: Array[Node3D] = []
var _slot := 0  # index of the weapon being held (or last held)
var _hotbar := 0  # selected hotbar slot
var _holding := false  # true when the selected hotbar slot holds a weapon
var _loot_models := {}  # loot item ID -> hand model (only the worm for now)
var _held_loot: Node3D  # loot model currently in the hand, or null
var _weapon_stats: Dictionary  # data/weapons.json entries
var _base_views: Array[Dictionary] = []
var _held_gun := {}  # the rolled gun in the selected hotbar slot, or {}
var _held_stats := {}  # GunStats.final_stats of _held_gun
var _gun_hash := {}  # slot index -> hash of the gun its WeaponState was built from
var _weapon_index := {}  # weapon item ID -> index into _weapons/_models/_views
var _motion := ViewmodelMotion.new()
var _views: Array[Dictionary] = []  # per-slot "view" tuning from data/weapons.json
var _hip_positions: Array[Vector3] = []
var _ads_positions: Array[Vector3] = []
var _base_ads: Array[Vector3] = []  # aim positions of the plain guns (parts with an optic change _ads_positions)
var _slides: Array[Node3D] = []  # pistol slide (null for weapons without one)
var _camera_query := PhysicsRayQueryParameters3D.new()
var _sprint_multiplier := 1.6
var _cigarette: Node3D
var _dot_accum := 0.0
var _base_max_hp := 100.0
var _berserk_stacks := 0
var _berserk_until := 0.0
var _rally_until := 0.0  # Rally Cry: extra damage and healing until this engine time
var _rally_dmg := 0.0
var _rally_regen := 0.0
var _last_crit := false
var bonus_damage_pct := 0.0  # from stats and traits (core/progress_state.gd), set by the session
var bonus_speed_pct := 0.0
var bonus_hp_pct := 0.0
var _view_kick := Vector2.ZERO  # degrees (pitch up, yaw) the camera is kicked by scoped shots; fades on its own
var cheat_god := false  # admin commands (game/admin_commands.gd): no damage
var cheat_fly := false  # free flight: move where the camera looks, no gravity
var cheat_speed := 1.0  # movement speed multiplier
var _shove := Vector3.ZERO  # see shove()
var guns_locked := false  # fantasy world (game/fantasy_world.gd): guns stay holstered until its story is finished
var channelling := false  # a staff spell is being built (game/staff_caster.gd): the element keys are not gun keys now
var _world_hp := 0.0  # extra max health from the fantasy world's Magic level and robe
var _world_damage := 1.0  # share of incoming damage that gets through the robe


func _ready() -> void:
	add_to_group("player")
	add_child(_wheel)
	collision_mask = 3  # world (1) and enemies (2)
	_spawn_position = position
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	var player_data := DataStore.load_json("res://data/player.json")
	health = HealthState.new(float(player_data["max_hp"]))
	_base_max_hp = health.max_hp
	items = ItemDb.new(DataStore.load_json("res://data/items.json"))
	inventory = InventoryState.new(items)
	gun_db = GunDb.new(DataStore.load_json("res://data/gun_loot.json"), DataStore.load_json("res://data/gun_parts.json"), DataStore.load_json("res://data/manufacturers.json"), DataStore.load_json("res://data/weapons.json"), DataStore.load_json("res://data/skills.json"), DataStore.load_json("res://data/gun_uniques.json"))
	inventory.set_gun_db(gun_db)
	status = StatusState.new(player_data["status"])
	for id in items.ids_of_kind("loot"):
		var held := WormModel.build()
		held.visible = false
		_head.add_child(held)
		_loot_models[id] = held
	for entry in player_data["starting_items"]:
		inventory.add(String(entry[0]), int(entry[1]))
	_sprint_multiplier = float(player_data["sprint_multiplier"])
	_camera_query.exclude = [get_rid()]
	_camera_query.collision_mask = 1

	var shape := CollisionShape3D.new()
	var capsule_shape := CapsuleShape3D.new()
	capsule_shape.height = 1.8
	capsule_shape.radius = 0.4
	shape.shape = capsule_shape
	shape.position.y = 0.9
	add_child(shape)

	set_appearance(AppearanceData.db().default_for("female"))

	_head.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_head.position.y = HEAD_HEIGHT
	add_child(_head)
	_head.add_child(_camera)
	_camera.current = true

	var stats := DataStore.load_json("res://data/weapons.json")
	_weapon_stats = stats["weapons"]
	for id in items.weapon_ids():
		_weapon_index[id] = _weapons.size()
		_weapons.append(WeaponState.new(id, stats["weapons"][id]))
		var model := WeaponModels.build(id)
		model.visible = false
		_head.add_child(model)
		_models.append(model)
		var view: Dictionary = stats["weapons"][id].get("view", {})
		var ads: Array = view.get("ads_position", [0.0, -0.07, -0.4])
		_views.append(view)
		_base_views.append(view)
		_hip_positions.append(model.position)
		var sight := model.get_node_or_null("Sight")  # models with a Sight marker line their sights up with the crosshair automatically
		if sight != null:
			_ads_positions.append(Vector3(-sight.position.x * model.scale.x, -sight.position.y * model.scale.y, ads[2]))
		else:
			_ads_positions.append(Vector3(ads[0], ads[1], ads[2]))
		_base_ads.append(_ads_positions[_ads_positions.size() - 1])
		_slides.append(model.get_node_or_null("Slide"))
	_select_slot(0)
	refresh_held()
	refresh_equipment()
	_apply_view()
	apply_settings()


func _unhandled_input(event: InputEvent) -> void:
	if not controls_enabled:
		return
	if _handle_emote_input(event):
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var sens := settings.mouse_sens * (_camera.fov / settings.fov)  # slower look while zoomed
		_yaw -= event.relative.x * sens
		_head.rotation.y = _yaw
		_head.rotation.x = clampf(_head.rotation.x - event.relative.y * sens, -1.5, 1.5)
	elif channelling:
		return
	elif event.is_action_pressed("toggle_view"):
		third_person = not third_person
		_apply_view()
	elif event.is_action_pressed("reload"):
		if _holding:
			weapon.start_reload(_now())
	elif event.is_action_pressed("skill_1"):
		use_skill(0)
	elif event.is_action_pressed("skill_2"):
		use_skill(1)
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP:
		select_hotbar((_hotbar + InventoryState.HOTBAR - 1) % InventoryState.HOTBAR)
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		select_hotbar((_hotbar + 1) % InventoryState.HOTBAR)
	else:
		for i in InventoryState.HOTBAR:
			if event.is_action_pressed("weapon_%d" % (i + 1)):
				select_hotbar(i)


# Hold H: wheel opens. Digits 1-8 or scroll pick; first-person mouse points at a slot; third-person mouse orbits the camera. Release H plays the pick.
func _handle_emote_input(event: InputEvent) -> bool:
	if event is InputEventKey and event.keycode == KEY_H and not event.echo:
		if event.pressed:
			_wheel_open = true
			_wheel_mouse = Vector2.ZERO
			_wheel.show_wheel()
		elif _wheel_open:
			_close_wheel(true)
		return true
	if not _wheel_open:
		return false
	if event is InputEventKey and event.pressed:
		for i in DancePoses.DANCES.size():
			if event.keycode == KEY_1 + i:
				_wheel.select(i)
				_close_wheel(true)
				return true
	elif event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		var step := -1 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1
		_wheel.select(posmod(_wheel.selected + step, DancePoses.DANCES.size()))
		return true
	elif event is InputEventMouseMotion:
		var sens := settings.mouse_sens
		if third_person:
			_orbit_yaw -= event.relative.x * sens
			_orbit_pitch = clampf(_orbit_pitch - event.relative.y * sens, -1.0, 1.0)
		else:
			_wheel_mouse += event.relative
			_wheel.select_by_direction(_wheel_mouse)
		return true
	return false


func _close_wheel(play: bool) -> void:
	_wheel_open = false
	_wheel.hide_wheel()
	_orbit_yaw = 0.0
	_orbit_pitch = 0.0
	if play and _wheel.selected >= 0:
		start_emote(DancePoses.id_at(_wheel.selected))


func start_emote(id: String) -> void:
	if not DancePoses.has(id):
		return
	if emote.is_empty():
		_view_before_emote = third_person
	emote = id
	_emote_t = 0.0
	third_person = true
	_apply_view()


func stop_emote() -> void:
	if emote.is_empty():
		return
	emote = ""
	DancePoses.reset(_body)
	third_person = _view_before_emote
	_apply_view()


func emote_id() -> String:
	return emote


func _move_and_shoot(delta: float) -> void:
	if carried:
		velocity = Vector3.ZERO
		return
	if cheat_fly:
		velocity.y = 0.0
	elif not is_on_floor():
		velocity.y -= _gravity * delta
	elif controls_enabled and Input.is_action_just_pressed("jump"):
		velocity.y = JUMP_SPEED

	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back") if controls_enabled else Vector2.ZERO
	var dir := (Basis(Vector3.UP, _yaw) * Vector3(input.x, 0, input.y)).normalized()
	var sprinting := Input.is_action_pressed("sprint") and input.y < 0.0 and not Input.is_action_pressed("aim")
	var speed := SPEED * (_sprint_multiplier if sprinting else 1.0) * status.speed_multiplier() * (1.0 + bonus_speed_pct / 100.0) * cheat_speed
	velocity.x = dir.x * speed + _shove.x
	velocity.z = dir.z * speed + _shove.z
	_shove = _shove.move_toward(Vector3.ZERO, 30.0 * delta)
	if cheat_fly:  # the whole movement follows the view, up and down included
		velocity = (_head.global_transform.basis * Vector3(input.x, 0, input.y)).normalized() * speed * 2.0
	if not emote.is_empty() and (input != Vector2.ZERO or Input.is_action_just_pressed("jump") or Input.is_action_pressed("shoot")):
		stop_emote()
	move_and_slide()
	if position.y < FALL_LIMIT:
		position = _spawn_position
		velocity = Vector3.ZERO

	if _holding and controls_enabled and Input.is_action_pressed("shoot") and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		if weapon.ammo <= 0 and armor["abilities"].has("auto_reload"):
			weapon.start_reload(_now())  # the equipped cigarette reloads for you
		if weapon.try_fire(_now()):
			_shoot()
			_motion.fire()
	else:
		weapon.update(_now())


# Runs every rendered frame: places the camera, body model and weapon, and plays the animations.
func _process(delta: float) -> void:
	_move_and_shoot(minf(delta, MAX_STEP))
	var origin := global_position
	_head.global_position = origin + Vector3(0, HEAD_HEIGHT, 0)
	_visual.global_position = origin
	_visual.rotation.y = _yaw
	if third_person:
		if emote.is_empty():
			_animate_walk(delta)
		else:
			_emote_t += delta
			DancePoses.apply(_body, emote, _emote_t)
		_place_third_person_camera()
	_animate_weapon(delta)
	_update_view_kick(delta)
	if _now() < _rally_until:
		health.heal(health.max_hp * _rally_regen / 100.0 * delta)
	_dot_accum += status.tick(delta)
	if _dot_accum >= 1.0:
		var chunk := floorf(_dot_accum)
		_dot_accum -= chunk
		_hurt(chunk)
	if third_person and _cigarette.visible:
		CigaretteModel.animate(_cigarette, _now())


func apply_settings() -> void:
	_camera.fov = settings.fov


# `element` is "physical", "fire", "ice" or "toxic". Armor can block, reduce and resist; elements also start a status effect.
# Something drags or blows the player along the ground at `v` m/s (a boss's undertow or gale); it fades on its own.
func shove(v: Vector3) -> void:
	_shove = Vector3(v.x, 0.0, v.z)


func take_damage(amount: float, element: String = "physical") -> void:
	if cheat_god:
		return
	var taken := ArmorMath.incoming(amount * _world_damage, element, armor, randf())
	if taken <= 0.0:
		blocked.emit()
		return
	if element != "physical":
		status.apply(element, float(armor["resist"].get(element, 0.0)))
	_hurt(taken)


func _hurt(amount: float) -> void:
	health.take_damage(amount)
	damaged.emit()
	if health.is_dead():
		position = _spawn_position
		velocity = Vector3.ZERO
		health.reset()
		status.clear()
		died.emit()


# Re-reads worn items (call after the inventory screen changes anything).
func refresh_equipment() -> void:
	armor = ArmorMath.totals(inventory, items)
	_cigarette.visible = armor["abilities"].has("auto_reload")


# Moves the player to a new spawn point (island -> arena) and makes it the respawn point.
# Current look direction (radians), used by online position sync.
func look_yaw() -> float:
	return _yaw


func teleport(to: Vector3, yaw: float) -> void:
	position = to
	velocity = Vector3.ZERO
	_spawn_position = to
	_yaw = yaw
	_head.rotation = Vector3(0.0, yaw, 0.0)


# Turns the view towards a world point (used when you sit down at a casino machine).
func look_at_point(point: Vector3) -> void:
	var d := point - global_position
	_yaw = atan2(-d.x, -d.z)
	_head.rotation = Vector3(atan2(d.y - 1.6, Vector2(d.x, d.z).length()), _yaw, 0.0)


# The weapon in the selected hotbar slot, or null when that slot holds something else.
func held_weapon() -> WeaponState:
	return weapon if _holding else null


# Item ID in the selected hotbar slot (online: shown in other players' hands; a rolled gun shows its body's model).
func held_id() -> String:
	var id := inventory.item_id(_hotbar)
	return String(_held_gun["body"]) if id == "gun" and not _held_gun.is_empty() else id


# The rolled gun in the selected hotbar slot ({} for a plain weapon or something else).
func held_gun() -> Dictionary:
	return _held_gun if _holding else {}


# True while a lit cigarette is worn (online: shown on other players).
func smoking() -> bool:
	return _cigarette.visible


func hotbar_index() -> int:
	return _hotbar


func select_hotbar(index: int) -> void:
	_hotbar = index
	refresh_held()


# Re-reads the selected hotbar slot (call after the inventory changes).
func refresh_held() -> void:
	_models[_slot].visible = false
	if _held_loot != null:
		_held_loot.visible = false
	var id := inventory.item_id(_hotbar)
	_held_loot = _loot_models.get(id)
	if _held_loot != null:
		_held_loot.visible = true
	_held_gun = {}
	_held_stats = {}
	if guns_locked and (id == "gun" or _weapon_index.has(id)):
		_holding = false
		_apply_health_cap()
		return
	if id == "gun":
		_held_gun = inventory.gun_at(_hotbar)
		var body := String(_held_gun["body"])
		_holding = _weapon_index.has(body)
		if _holding:
			_build_gun_slot(_weapon_index[body], body)
			_select_slot(_weapon_index[body])
		_apply_health_cap()
		return
	_holding = _weapon_index.has(id)
	if _holding:
		_reset_slot(_weapon_index[id], id)
		_select_slot(_weapon_index[id])
	_apply_health_cap()


# Gives the weapon slot of a gun's body the gun's final stats (only rebuilt when the gun changed, so ammo survives refreshes).
func _build_gun_slot(index: int, body: String) -> void:
	_held_stats = GunStats.final_stats(gun_db, _held_gun)
	var h := _held_gun.hash()
	if int(_gun_hash.get(index, 0)) == h:
		return
	_gun_hash[index] = h
	var eye := GunPartsView.apply(_models[index], _held_gun, gun_db)  # an optic raises the line the eye aims along
	_ads_positions[index] = _base_ads[index] if eye <= 0.0 else Vector3(_base_ads[index].x, -eye * _models[index].scale.y, _base_ads[index].z)
	PonySkin.apply(_models[index], String(gun_db.tier(String(_held_gun["tier"])).get("skin", "")) == "pony")
	_weapons[index] = WeaponState.new(body, _held_stats)
	var view: Dictionary = _base_views[index].duplicate()
	view["ads_fov"] = float(view.get("ads_fov", 60.0)) * float(_held_stats["ads_fov"])
	view["recoil_back"] = float(view.get("recoil_back", 0.05)) * float(_held_stats["recoil"])
	view["recoil_pitch"] = float(view.get("recoil_pitch", 6.0)) * float(_held_stats["recoil"])
	_views[index] = view


# A plain weapon item goes back to the stock stats if a rolled gun used its slot before.
func _reset_slot(index: int, id: String) -> void:
	if not _gun_hash.has(index):
		return
	_gun_hash.erase(index)
	GunPartsView.clear(_models[index])
	_ads_positions[index] = _base_ads[index]
	PonySkin.apply(_models[index], false)
	_weapons[index] = WeaponState.new(id, _weapon_stats[id])
	_views[index] = _base_views[index]


# 0..1 how far the scope view is up (only weapons with "scope": true, first person only).
func scope_amount() -> float:
	return _motion.ads_eased() if _holding and bool(_views[_slot].get("scope", false)) else 0.0


func _select_slot(index: int) -> void:
	_models[_slot].visible = false
	_slot = index
	weapon = _weapons[index]
	_models[index].visible = true
	_motion.reset()
	_motion.ads_speed = float(_views[index].get("ads_speed", 9.0))


# (Re)builds the visible body from an appearance dictionary; anything invalid is replaced by defaults.
func set_appearance(look: Dictionary) -> void:
	appearance = AppearanceData.db().sanitize(look)
	var was_smoking := _cigarette != null and _cigarette.visible
	if _visual != null:
		_visual.queue_free()
	_visual = Node3D.new()
	_body = RiggedBody.build(appearance)  # rigged character when the packs are installed
	if _body == null:
		_body = BodyBuilder.build(appearance)
	_third_person_hold = (_body.call("third_person_hold") as Vector3) if _body.has_method("third_person_hold") else THIRD_PERSON_HOLD
	_visual.add_child(_body)
	_visual.top_level = true
	_visual.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(_visual)
	_visual.global_position = global_position
	_visual.rotation.y = _yaw
	_visual.visible = third_person
	_cigarette = CigaretteModel.build()
	_cigarette.position = Vector3(0.035, 0.05, -0.098)  # on the lips of the rounded head
	_cigarette.rotation_degrees.x = 10.0
	_cigarette.visible = was_smoking
	if _body.has_method("head_anchor"):
		(_body.call("head_anchor") as Node3D).add_child(_cigarette)
	else:
		_body.get_node("Torso/Head").add_child(_cigarette)


# Forces first/third person (used while riding the crow).
func set_third_person(on: bool) -> void:
	third_person = on
	_apply_view()


func _apply_view() -> void:
	_visual.visible = third_person
	if not third_person:
		_camera.position = FIRST_PERSON_CAM
	_motion.reset()


# Swing the legs while moving (third person only).
func _animate_walk(delta: float) -> void:
	var speed := Vector2(velocity.x, velocity.z).length()
	_walk_phase += speed * delta * 1.6
	BodyMotion.animate(_body, clampf(speed / SPEED, 0.0, 1.0), _walk_phase, _now(), _holding)


# Keeps the shoulder camera from clipping through walls: pulls it in front of whatever blocks the view.
func _place_third_person_camera() -> void:
	var desired := _head.global_transform * THIRD_PERSON_CAM
	if _wheel_open:
		var orbit := Basis(Vector3.UP, _yaw + _orbit_yaw) * Basis(Vector3.RIGHT, _orbit_pitch)
		desired = _head.global_position + orbit * ORBIT_CAM
	_camera_query.from = _head.global_position
	_camera_query.to = desired
	var hit := get_world_3d().direct_space_state.intersect_ray(_camera_query)
	_camera.global_position = desired if hit.is_empty() else hit.position + hit.normal * CAMERA_PADDING
	if _wheel_open:
		_camera.look_at(_head.global_position, Vector3.UP)
	else:
		_camera.rotation = Vector3.ZERO


# Recoil, pistol slide, reload dip, aim down sights (first person) and zoom.
func _animate_weapon(delta: float) -> void:
	if not _holding:
		_motion.update(delta, false, 0.0)
		_camera.fov = settings.fov
		if _held_loot != null:
			_held_loot.position = _third_person_hold if third_person else LOOT_HOLD
			_held_loot.rotation_degrees = Vector3(0, -25, 0)
			WormModel.pose(_held_loot, _now(), 1.0)
		return
	var wants_ads := not third_person and Input.is_action_pressed("aim") and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	_motion.update(delta, wants_ads, weapon.reload_fraction(_now()))
	var view := _views[_slot]
	var aim := _motion.ads_eased()
	var curve := _motion.reload_curve()
	var kick := _motion.kick
	var back := float(view.get("recoil_back", 0.05))
	var model := _models[_slot]
	if _body != null and _body.has_method("support"):  # long guns: the body's left hand reaches the fore-end
		_body.call("support", model.get_node_or_null("Support") if third_person else null)
	var base := _third_person_hold if third_person else _hip_positions[_slot]
	model.position = base.lerp(_ads_positions[_slot], aim) + Vector3(0.0, -0.16, 0.04) * curve + Vector3(0.0, back * 0.25, back) * kick
	model.rotation_degrees = Vector3(float(view.get("recoil_pitch", 6.0)) * kick + 20.0 * curve, 0.0, 35.0 * curve)
	var slide := _slides[_slot]
	if slide != null:
		slide.position.z = 0.05 * kick
	_camera.fov = lerpf(settings.fov, float(view.get("ads_fov", settings.fov)), aim)
	model.visible = not (bool(view.get("scope", false)) and aim > 0.85)


# Scoped shots kick the camera itself (the gun model is hidden in the scope): the weapon's "scope_kick" degrees up with a little sideways drift, scaled by the gun's recoil stat.
func _kick_view() -> void:
	var scope_kick: float = float(_views[_slot].get("scope_kick", 0.0))
	if scope_kick <= 0.0 or scope_amount() < 0.5:
		return
	var amount := scope_kick * float(_held_stats.get("recoil", 1.0))
	_view_kick += Vector2(amount, randf_range(-0.25, 0.25) * amount)


func _update_view_kick(delta: float) -> void:
	_view_kick *= exp(-VIEW_KICK_RECOVERY * delta)
	if third_person or _view_kick.length() < 0.001:
		_view_kick = Vector2.ZERO
		if not third_person:
			_camera.rotation = Vector3.ZERO
		return
	_camera.rotation_degrees = Vector3(_view_kick.x, _view_kick.y, 0.0)


func _shoot() -> void:
	var origin := _camera.global_position
	var forward := -_camera.global_transform.basis.z
	var right := _camera.global_transform.basis.x
	var up := _camera.global_transform.basis.y
	var spread := weapon.spread * lerpf(1.0, float(_views[_slot].get("ads_spread_mult", 1.0)), _motion.ads_eased())
	_kick_view()  # applies after this shot's direction is taken (the camera vectors above were read first)

	var buffs: Dictionary = _held_stats.get("buffs", {})
	if buffs.has("free_shot") and randf() * 100.0 < float(buffs["free_shot"]):
		weapon.ammo = mini(weapon.ammo + 1, weapon.mag_size)
	if not weapon.projectile.is_empty():
		var aim := (forward + right * randf_range(-spread, spread) + up * randf_range(-spread, spread)).normalized()
		explosives.fire(_head.global_position + aim * 0.6, aim, weapon.projectile)
		return

	var totals := {}  # collider -> damage dealt this shot (one number per target, even for shotgun pellets)
	var spots := {}
	for pellet in weapon.pellets:
		var dir := (forward + right * randf_range(-spread, spread) + up * randf_range(-spread, spread)).normalized()
		var query := PhysicsRayQueryParameters3D.create(origin, origin + dir * SHOT_RANGE)
		query.exclude = [get_rid()]
		var hit := get_world_3d().direct_space_state.intersect_ray(query)
		if not hit.is_empty() and hit.collider.has_method("on_hit"):
			var dealt := _gun_damage()
			var hp_before := _hp_of(hit.collider)
			hit.collider.on_hit(dealt, hit.position, hit.normal)
			totals[hit.collider] = float(totals.get(hit.collider, 0.0)) + dealt
			spots[hit.collider] = hit.position
			if not _held_gun.is_empty():
				_gun_hit_effects(hit.collider, hit.position, dealt, hp_before)
	if damage_numbers != null:
		for collider in totals:
			damage_numbers.spawn(spots[collider], totals[collider])


# Damage of one pellet: the weapon's damage, doubled (plus the crit_damage buff) on a critical hit of a rolled gun, times the damage multiplier (berserker, glass cannon, rally).
func _gun_damage() -> float:
	var mult := _damage_mult()
	_last_crit = false
	if _held_gun.is_empty() or randf() >= float(_held_stats["crit_chance"]):
		return weapon.damage * mult
	_last_crit = true
	var buffs: Dictionary = _held_stats["buffs"]
	return weapon.damage * (2.0 + float(buffs.get("crit_damage", 0.0)) / 100.0) * mult


# Damage multiplier from Berserker Chain stacks, Glass Cannon and Rally Cry.
func _damage_mult() -> float:
	var now := _now()
	var mult := 1.0
	var buffs: Dictionary = _held_stats.get("buffs", {})
	if buffs.has("berserker_chain"):
		if now > _berserk_until:
			_berserk_stacks = 0
		mult *= 1.0 + float(_berserk_stacks) * float(buffs["berserker_chain"]) / 100.0
	if buffs.has("glass_cannon"):
		mult *= 1.0 + float(buffs["glass_cannon"]) / 100.0
	if now < _rally_until:
		mult *= 1.0 + _rally_dmg / 100.0
	return mult * (1.0 + bonus_damage_pct / 100.0)


# Applies the progression bonuses (percent). A higher max health also heals by the difference.
func set_progress_bonuses(damage_pct: float, speed_pct: float, hp_pct: float) -> void:
	bonus_damage_pct = damage_pct
	bonus_speed_pct = speed_pct
	bonus_hp_pct = hp_pct
	var before := health.max_hp
	_apply_health_cap()
	if health.max_hp > before:
		health.hp += health.max_hp - before


# Glass Cannon lowers max health while the gun is held (current health is never raised by swapping).
func _apply_health_cap() -> void:
	var buffs: Dictionary = _held_stats.get("buffs", {})
	health.max_hp = (_base_max_hp + _world_hp) * (1.0 + bonus_hp_pct / 100.0) * (GLASS_HEALTH if buffs.has("glass_cannon") else 1.0)
	health.hp = minf(health.hp, health.max_hp)


# Fantasy world: extra max health and the share of damage that still gets through (1 = all of it).
func set_world_bonus(extra_hp: float, damage_share: float) -> void:
	var before := health.max_hp
	_world_hp = extra_hp
	_world_damage = damage_share
	_apply_health_cap()
	if health.max_hp > before:
		health.hp += health.max_hp - before


# True while a gun is in the hands (the staff is out whenever this is false in the fantasy world).
func holding_gun() -> bool:
	return _holding


# Where the eyes are and where they look (spells start here).
func view_origin() -> Vector3:
	return _camera.global_position


func view_forward() -> Vector3:
	return -_camera.global_transform.basis.z


# The node things held in the hand hang from, and where on it the hand is right now.
func hand_parent() -> Node3D:
	return _head


func hand_position() -> Vector3:
	return _third_person_hold if third_person else LOOT_HOLD


func _hp_of(target: Node) -> float:
	return float(target.health.hp) if target.get("health") != null else 0.0


# Gun buffs that trigger on a hit: leech, burn, slow, shock, explosive, ammo on kill, slayer's mark, overkill splash.
func _gun_hit_effects(target: Node, point: Vector3, dealt: float, hp_before: float) -> void:
	var buffs: Dictionary = _held_stats["buffs"]
	if buffs.has("lifesteal"):
		health.heal(dealt * float(buffs["lifesteal"]) / 100.0)
	if buffs.has("slow_on_hit") and target.has_method("apply_slow"):
		target.apply_slow(float(buffs["slow_on_hit"]) / 100.0, 2.0)
	if buffs.has("burn_chance") and target.has_method("apply_burn") and randf() * 100.0 < float(buffs["burn_chance"]):
		target.apply_burn(weapon.damage * 0.4, 3.0)
	if buffs.has("slayer_mark") and _last_crit and target.has_method("apply_vulnerable"):
		target.apply_vulnerable(1.0 + float(buffs["slayer_mark"]) / 100.0, 6.0)
	if explosives != null:
		if buffs.has("explosive_chance") and randf() * 100.0 < float(buffs["explosive_chance"]):
			explosives.blast(point, 3.0, weapon.damage * 1.5)
		if buffs.has("shock_chance") and randf() * 100.0 < float(buffs["shock_chance"]):
			explosives.blast(point, 5.0, weapon.damage * 0.5, false)
	var killed: bool = target.get("health") != null and target.health.is_dead()
	if buffs.has("reload_on_kill") and killed:
		weapon.ammo = mini(weapon.ammo + roundi(float(weapon.mag_size) * float(buffs["reload_on_kill"]) / 100.0), weapon.mag_size)
	if buffs.has("overkill_splash") and killed and dealt > hp_before:
		_spill(target, point, (dealt - hp_before) * float(buffs["overkill_splash"]) / 100.0)


# Overkill Splash: damage that was more than enough to kill goes to the nearest other enemy within range.
func _spill(from: Node, point: Vector3, amount: float) -> void:
	if explosives == null or explosives.source == null:
		return
	var best = null
	var best_d := OVERKILL_RANGE
	for e in explosives.source.enemy_list():
		if e == from or not is_instance_valid(e) or e.health.is_dead():
			continue
		var d: float = e.global_position.distance_to(point)
		if d <= best_d:
			best_d = d
			best = e
	if best != null:
		best.on_hit(amount, best.global_position + Vector3(0, best.head_height() * 0.5, 0), Vector3.UP)
		if damage_numbers != null:
			damage_numbers.spawn(best.global_position + Vector3(0, best.head_height() * 0.5, 0), amount)


# The Q / E gun skills: skill `index` of the held rolled gun (0 = Q, 1 = E). Cooldowns belong to the gun, so swapping guns does not reset them.
func use_skill(index: int) -> void:
	if not _holding or _held_gun.is_empty() or skill_fx == null:
		return
	var list: Array = _held_gun.get("skills", [])
	if index >= list.size():
		return
	var entry: Dictionary = list[index]
	var key := "%d:%d" % [_held_gun.hash(), index]
	var now := _now()
	if not skills.is_ready(key, now):
		return
	var cd := SkillState.cooldown(gun_db, entry, String(_held_gun["tier"]))
	var buffs: Dictionary = _held_stats.get("buffs", {})
	if buffs.has("skill_echo") and randf() * 100.0 < float(buffs["skill_echo"]):
		cd = 0.0  # Skill Echo: the cooldown is refunded
	skills.start(key, now, cd)
	var eye := _camera.global_position
	var forward := -_camera.global_transform.basis.z
	var aim := eye + forward * 14.0
	var query := PhysicsRayQueryParameters3D.create(eye, eye + forward * 30.0)
	query.exclude = [get_rid()]
	query.collision_mask = 1
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		aim = hit.position
	if String(entry["id"]) == "rally_cry":
		_rally_until = now + SkillState.value(gun_db, entry, "seconds")
		_rally_dmg = SkillState.value(gun_db, entry, "damage")
		_rally_regen = SkillState.value(gun_db, entry, "regen")
	skill_fx.cast(gun_db, entry, weapon.damage, global_position, eye, forward, aim)


# How many skills the held gun has (HUD).
func skill_count() -> int:
	return (_held_gun.get("skills", []) as Array).size() if _holding and not _held_gun.is_empty() else 0


func skill_name(index: int) -> String:
	var entry: Dictionary = (_held_gun["skills"] as Array)[index]
	return String(gun_db.skill_def(String(entry["id"]))["name"])


# Seconds left on the cooldown of the held gun's skill `index` (0 = ready).
func skill_cooldown_left(index: int) -> float:
	return skills.remaining("%d:%d" % [_held_gun.hash(), index], _now())


func skill_cooldown_total(index: int) -> float:
	var entry: Dictionary = (_held_gun["skills"] as Array)[index]
	return SkillState.cooldown(gun_db, entry, String(_held_gun["tier"]))


# A kill happened in the arena (game/game_session.gd forwards the director's signal): Berserker Chain stacks, Cooldown Siphon.
func on_enemy_killed(elite: String, enemy_id: String) -> void:
	var buffs: Dictionary = _held_stats.get("buffs", {})
	var now := _now()
	if buffs.has("berserker_chain"):
		_berserk_stacks = mini(_berserk_stacks + 1, BERSERK_MAX)
		_berserk_until = now + BERSERK_SECONDS
	if buffs.has("cooldown_siphon"):
		var secs := float(buffs["cooldown_siphon"])
		if enemy_id == "boss":
			secs = maxf(secs, 5.0)
		elif elite != "":
			secs = maxf(secs, 3.0)
		skills.reduce_all(secs, now)


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0
