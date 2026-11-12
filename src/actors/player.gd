class_name Player
extends CharacterBody3D
## The hero under the player's control: first-person movement, spear, sword
## and dagger work, the shield, thrown spears, stealth and interaction.

signal died
signal damaged(amount: float, blocked: bool)
signal weapon_changed(weapon_id: String)
signal struck(target: Node3D, result: Dictionary)
signal focus_changed(item: Interactable)

const GRAVITY := 19.0

var battle: Battlefield
var role_id: String = ""
var role: Dictionary = {}
var side: StringName = &"achaean"
var display_name: String = ""
var max_health: float = 100.0
var health: float = 100.0
var max_stamina: float = 100.0
var stamina: float = 100.0
var crouching: bool = false
var blocking: bool = false
var weapons: Array[String] = []
var weapon_index: int = 0
var spears: int = 0
## When false the player cannot move, look or fight (cutscenes, menus).
var control_enabled: bool = true
## When false movement is frozen but looking is still allowed.
var move_enabled: bool = true
var combat_enabled: bool = true
var invulnerable: bool = false
var camera: Camera3D
var viewmodel: Viewmodel
## Interactable currently looked at, or null.
var focus: Interactable
## 0 to 1 progress of a hold-to-use interaction.
var hold_progress: float = 0.0
var kills: int = 0
## Harness only: holds the shield up without input.
var debug_block: bool = false
## Harness only: accepts injected input without a captured mouse.
var bot_control: bool = false

var _cfg: Dictionary = {}
var _head: Node3D
var _shape: CapsuleShape3D
var _collider: CollisionShape3D
var _pitch: float = 0.0
var _look_delta := Vector2.ZERO
var _eye: float = 1.62
var _attack_t: float = -1.0
var _attack_hit_at: float = 0.0
var _attack_end: float = 0.0
var _attack_is_throw: bool = false
var _attack_resolved: bool = false
var _regen_wait: float = 0.0
var _stamina_wait: float = 0.0
var _step_t: float = 0.0
var _dead: bool = false
var _shake: float = 0.0
var _long_spear: bool = false
var _focus_wait: int = 0
var _grace: float = 0.0
var _capture_check: float = 0.0
var _look_guard: float = 0.0


## Applies a hero role. Call before adding to the tree.
func configure(id: String, data: Dictionary) -> void:
	role_id = id
	role = data
	side = StringName(str(data.get("side", "achaean")))
	display_name = str(data.get("name", id))
	_cfg = Data.tuning.get("player", {})
	max_health = float(data.get("health", _cfg.get("max_health", 100.0)))
	health = max_health
	max_stamina = float(_cfg.get("max_stamina", 100.0))
	stamina = max_stamina
	weapons.assign(data.get("weapons", ["sword"]))
	_long_spear = id == "hector"
	spears = int(_cfg.get("spear_capacity", 2)) if "spear" in weapons else 0
	_eye = float(_cfg.get("eye_height", 1.62))
	name = "Player"
	add_to_group(&"player")

	collision_layer = 2
	collision_mask = 1 | 4
	_shape = CapsuleShape3D.new()
	_shape.radius = 0.34
	_shape.height = 1.76
	_collider = CollisionShape3D.new()
	_collider.shape = _shape
	_collider.position = Vector3(0, 0.88, 0)
	add_child(_collider)
	floor_snap_length = 0.45
	floor_max_angle = deg_to_rad(50.0)

	_head = Node3D.new()
	_head.position = Vector3(0, _eye, 0)
	add_child(_head)
	camera = Camera3D.new()
	camera.near = 0.04
	camera.far = 9000.0
	camera.fov = float(Game.settings.get("fov", 75.0))
	_head.add_child(camera)
	viewmodel = Viewmodel.new()
	camera.add_child(viewmodel)
	var outfit_id := str(data.get("outfit", id))
	var look := Humanoid.resolve_look(outfit_id, Data.characters.get("outfits", {}).get(outfit_id, {}), 0)
	viewmodel.setup(look)
	viewmodel.set_weapon(current_weapon(), _long_spear)


func _ready() -> void:
	camera.make_current()
	Game.settings_changed.connect(func() -> void: camera.fov = float(Game.settings.get("fov", 75.0)))


func is_alive() -> bool:
	return not _dead


## World position of the eyes.
func eye_position() -> Vector3:
	return _head.global_position


## Horizontal speed in m/s (what watchmen hear).
func move_speed() -> float:
	return Vector2(velocity.x, velocity.z).length()


## Id of the weapon in hand ("" when unarmed).
func current_weapon() -> String:
	if weapons.is_empty():
		return ""
	return weapons[clampi(weapon_index, 0, weapons.size() - 1)]


## Turns the player to face a world point.
func look_toward(point: Vector3) -> void:
	var to := point - eye_position()
	rotation.y = atan2(-to.x, -to.z)
	_pitch = clampf(atan2(to.y, Vector2(to.x, to.z).length()), -1.4, 1.4)
	_head.rotation.x = _pitch


## Turns the view by the given angles in radians (touch look).
func add_look(yaw: float, pitch: float) -> void:
	if not _dead and control_enabled:
		_turn(yaw, pitch)


## Sets the up/down angle of the view in radians.
func set_pitch(pitch: float) -> void:
	_pitch = clampf(pitch, -1.45, 1.45)
	_head.rotation.x = _pitch


## Selects a weapon by id if the hero carries it.
func equip(id: String) -> void:
	var i := weapons.find(id)
	if i < 0 or (id == "spear" and spears <= 0):
		return
	weapon_index = i
	viewmodel.set_weapon(id, _long_spear)
	weapon_changed.emit(id)


func _cycle_weapon(step: int) -> void:
	if weapons.size() < 2:
		return
	for i in weapons.size():
		weapon_index = posmod(weapon_index + step, weapons.size())
		if current_weapon() != "spear" or spears > 0:
			break
	viewmodel.set_weapon(current_weapon(), _long_spear)
	weapon_changed.emit(current_weapon())


## Adds a spear to those carried. Returns false when the hero can hold no more.
func add_spear() -> bool:
	if not "spear" in weapons:
		weapons.append("spear")
	if spears >= int(_cfg.get("spear_capacity", 2)):
		return false
	spears += 1
	Sfx.play(&"pickup")
	if spears == 1 and current_weapon() != "spear" and _attack_t < 0.0:
		equip("spear")
	else:
		weapon_changed.emit(current_weapon())
	return true


func _unhandled_input(event: InputEvent) -> void:
	if _dead or not control_enabled:
		return
	if Game.web and not Game.mobile and not Game.free_look and event is InputEventMouseButton \
			and (event as InputEventMouseButton).pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		# A browser hands over the pointer only on a click. If it refuses,
		# _physics_process falls back to turning with the free cursor.
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		_capture_check = 0.7
		_look_guard = 0.3
		return
	if event is InputEventMouseMotion and (Input.mouse_mode == Input.MOUSE_MODE_CAPTURED or Game.free_look):
		# Some browsers report one huge movement at the moment the pointer is captured.
		if _look_guard > 0.0:
			return
		var sens := 0.0022 * float(Game.settings.get("mouse_sensitivity", 1.0))
		var rel: Vector2 = (event as InputEventMouseMotion).relative.limit_length(160.0)
		_turn(-rel.x * sens, -rel.y * sens * (-1.0 if Game.settings.get("invert_y", false) else 1.0))
	elif event.is_action_pressed(&"weapon_1"):
		_select_slot(0)
	elif event.is_action_pressed(&"weapon_2"):
		_select_slot(1)
	elif event.is_action_pressed(&"weapon_3"):
		_select_slot(2)
	elif event.is_action_pressed(&"weapon_next"):
		_cycle_weapon(1)
	elif event.is_action_pressed(&"weapon_prev"):
		_cycle_weapon(-1)


func _select_slot(i: int) -> void:
	if i < weapons.size() and _attack_t < 0.0:
		equip(weapons[i])


func _turn(yaw: float, pitch: float) -> void:
	rotation.y += yaw
	_pitch = clampf(_pitch + pitch, -1.45, 1.45)
	_head.rotation.x = _pitch
	_look_delta += Vector2(yaw, pitch)


func _start_attack(throw: bool) -> void:
	var id := current_weapon()
	if id == "":
		return
	var w: Dictionary = Data.weapons.get(id, {})
	if throw and (id != "spear" or spears <= 0):
		return
	var cost := float(w.get("stamina", 10.0)) * (1.3 if throw else 1.0)
	if stamina < cost * 0.5:
		return
	stamina = maxf(stamina - cost, 0.0)
	_stamina_wait = float(_cfg.get("stamina_regen_delay", 0.9))
	var windup := float(w.get("windup", 0.25)) * (1.5 if throw else 1.0)
	var strike := float(w.get("strike", 0.12))
	var recover := float(w.get("recover", 0.4))
	_attack_t = 0.0
	_attack_hit_at = windup + strike * 0.55
	_attack_end = windup + strike + recover
	_attack_is_throw = throw
	_attack_resolved = false
	viewmodel.attack(&"throw" if throw else StringName(str(w.get("kind", "thrust"))), windup, strike, recover)
	if not bool(w.get("silent", false)):
		Sfx.play(&"whoosh", -6.0)


func _resolve_attack() -> void:
	var id := current_weapon()
	var w: Dictionary = Data.weapons.get(id, {})
	var origin := camera.global_position
	var aim := -camera.global_transform.basis.z
	if _attack_is_throw:
		viewmodel.release_weapon()
		var speed := float(w.get("throw_speed", 25.0))
		battle.throw_spear(self, side, origin + aim * 0.6 + camera.global_transform.basis.x * 0.2,
			aim * speed + Vector3(0, 1.4, 0) + velocity * 0.5, float(w.get("throw_damage", 80.0)))
		spears -= 1
		if spears <= 0:
			_cycle_weapon(1)
		else:
			weapon_changed.emit(current_weapon())
		return
	var reach := float(w.get("reach", 1.8))
	var half_arc := deg_to_rad(float(w.get("arc_deg", 40.0))) * 0.5
	var best: Node3D = null
	var best_score := INF
	var best_height := 1.2
	for e in battle.enemies_of(side):
		var feet: Vector3 = e.global_position
		var body_top := feet + Vector3(0, 1.75, 0)
		# Closest point on the man's body to the line of the blow.
		var pts := Geometry3D.get_closest_points_between_segments(origin, origin + aim * (reach + 0.4),
			feet + Vector3(0, 0.1, 0), body_top)
		var on_body: Vector3 = pts[1]
		var to := on_body - origin
		var dist := to.length()
		if dist > reach + 0.45:
			continue
		var ang := aim.angle_to(to) if dist > 0.3 else 0.0
		if ang > half_arc + 0.16:
			continue
		var q := PhysicsRayQueryParameters3D.create(origin, on_body, 1)
		if not get_world_3d().direct_space_state.intersect_ray(q).is_empty():
			continue
		var score := ang * 2.0 + dist * 0.2
		if score < best_score:
			best_score = score
			best = e
			best_height = on_body.y - feet.y
	if best == null:
		# Bronze on stone.
		var q := PhysicsRayQueryParameters3D.create(origin, origin + aim * (reach * 0.8), 1)
		var hit := get_world_3d().direct_space_state.intersect_ray(q)
		if not hit.is_empty():
			Sfx.play_at(&"clang", hit["position"], -4.0)
		return
	var result: Dictionary = best.receive_hit(self, float(w.get("damage", 30.0)), best_height, aim, id)
	if result.is_empty():
		return
	if result.get("blocked", false):
		Sfx.play_at(&"block", best.global_position)
		_shake = 0.25
	else:
		Sfx.play_at(&"stab" if result.get("stealth", false) else &"hit", best.global_position)
		_shake = 0.18
	if result.get("killed", false):
		kills += 1
	struck.emit(best, result)


## Takes a blow. Returns {"blocked", "killed", "damage"}.
func receive_hit(attacker: Node3D, base_damage: float, height: float, dir: Vector3, _weapon: String = "") -> Dictionary:
	if _dead or invulnerable:
		return {}
	var cfg: Dictionary = Data.tuning.get("combat", {})
	# Two men striking in the same instant count as one blow.
	if _grace > 0.0:
		return {}
	_grace = float(cfg.get("player_hit_grace", 0.7))
	var to_att := attacker.global_position - global_position if attacker != null else -dir
	var fwd := -global_transform.basis.z
	var can_block := blocking and viewmodel.has_shield() \
		and Combat.in_block_arc(fwd, to_att, float(_cfg.get("block_arc_deg", 115.0)))
	if can_block:
		stamina = maxf(stamina - float(_cfg.get("block_hit_cost", 16.0)), 0.0)
		_stamina_wait = float(_cfg.get("stamina_regen_delay", 0.9))
		var leak := base_damage * float(_cfg.get("block_damage_leak", 0.08))
		# A blow that lands on an exhausted arm drives through.
		if stamina <= 0.0:
			leak = base_damage * 0.5
		_apply_damage(leak * float(cfg.get("player_damage_taken_scale", 0.4)) * Game.damage_taken_scale(), true)
		viewmodel.flinch()
		_shake = 0.3
		return {"blocked": true, "killed": _dead, "damage": leak}
	var zone := Combat.hit_zone(height, 1.0, crouching)
	var outfit: Dictionary = Data.characters.get("outfits", {}).get(str(role.get("outfit", role_id)), {})
	var armor_id := str((outfit.get("armor", ["none"]) as Array)[0])
	var dmg := Combat.damage(base_damage, zone, Combat.armor_value(armor_id), Combat.is_behind(fwd, to_att), randf(), cfg)
	dmg *= float(cfg.get("player_damage_taken_scale", 0.4)) * Game.damage_taken_scale()
	_apply_damage(dmg, false)
	viewmodel.flinch()
	_shake = 0.5
	return {"blocked": false, "killed": _dead, "damage": dmg, "zone": zone}


func _apply_damage(amount: float, blocked: bool) -> void:
	health -= amount
	_regen_wait = float(_cfg.get("regen_delay", 6.0))
	damaged.emit(amount, blocked)
	if not blocked:
		Sfx.play(&"hurt")
	if health <= 0.0 and not _dead:
		_dead = true
		health = 0.0
		control_enabled = false
		Sfx.play(&"death")
		# Fall: the camera drops and rolls.
		var tw := create_tween()
		tw.tween_property(_head, "position:y", 0.3, 0.9).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.parallel().tween_property(_head, "rotation:z", 0.9, 0.9)
		died.emit()


## Restores health (used between mission phases).
func heal(amount: float) -> void:
	if not _dead:
		health = minf(health + amount, max_health)


func _update_focus() -> void:
	# A tree query: run it a few times a second, not every tick.
	_focus_wait -= 1
	if _focus_wait > 0:
		return
	_focus_wait = 6
	var best: Interactable = null
	var best_score := INF
	var origin := camera.global_position
	var aim := -camera.global_transform.basis.z
	for node in get_tree().get_nodes_in_group(&"interactables"):
		var it := node as Interactable
		if it == null or not it.enabled or not it.is_inside_tree():
			continue
		var to := it.focus_point() - origin
		var dist := to.length()
		if dist > it.radius:
			continue
		var ang := aim.angle_to(to) if dist > 0.4 else 0.0
		if ang <= it.aim_cone and ang < best_score:
			best_score = ang
			best = it
	if best != focus:
		focus = best
		hold_progress = 0.0
		focus_changed.emit(focus)


func _physics_process(delta: float) -> void:
	if _dead:
		velocity.x = move_toward(velocity.x, 0.0, 20.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, 20.0 * delta)
		velocity.y -= GRAVITY * delta
		move_and_slide()
		return
	_look_guard -= delta
	if _capture_check > 0.0:
		_capture_check -= delta
		if _capture_check <= 0.0 and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Game.free_look = true
	var active := control_enabled and (Input.mouse_mode == Input.MOUSE_MODE_CAPTURED or bot_control or Game.mobile or Game.free_look)
	if active and Game.free_look and not get_tree().paused:
		# No captured pointer: the view also turns while the cursor rests near a side edge.
		var vp := get_viewport()
		var fx := vp.get_mouse_position().x / maxf(vp.get_visible_rect().size.x, 1.0)
		if fx < 0.14:
			_turn(2.2 * delta * (0.14 - fx) / 0.14, 0.0)
		elif fx > 0.86:
			_turn(-2.2 * delta * (fx - 0.86) / 0.14, 0.0)
	var can_move := active and move_enabled

	# Gamepad look.
	if active:
		var look := Input.get_vector(&"look_left", &"look_right", &"look_up", &"look_down")
		if look.length() > 0.05:
			_turn(-look.x * 2.6 * delta, -look.y * 1.8 * delta)

	# Crouch.
	var want_crouch := can_move and Input.is_action_pressed(&"crouch")
	if want_crouch != crouching:
		if want_crouch or _can_stand():
			crouching = want_crouch
			_shape.height = 1.2 if crouching else 1.76
			_collider.position.y = _shape.height * 0.5
	var eye_target := float(_cfg.get("crouch_eye_height", 1.02)) if crouching else _eye
	_head.position.y = lerpf(_head.position.y, eye_target, 1.0 - exp(-12.0 * delta))

	# Shield.
	blocking = active and combat_enabled and Input.is_action_pressed(&"block") and viewmodel.has_shield() and _attack_t < 0.0
	if debug_block:
		blocking = true
	viewmodel.blocking = blocking
	if blocking:
		stamina = maxf(stamina - float(_cfg.get("block_hold_cost", 2.0)) * delta, 0.0)

	# Movement.
	var input := Input.get_vector(&"move_left", &"move_right", &"move_forward", &"move_back") if can_move else Vector2.ZERO
	var wish := (global_transform.basis * Vector3(input.x, 0, input.y))
	wish.y = 0.0
	if wish.length() > 1.0:
		wish = wish.normalized()
	var sprinting := can_move and Input.is_action_pressed(&"sprint") and input.y < -0.2 and not crouching \
		and not blocking and stamina > 1.0
	var speed := float(_cfg.get("walk_speed", 4.2))
	if crouching:
		speed = float(_cfg.get("crouch_speed", 2.0))
	elif sprinting:
		speed = float(_cfg.get("sprint_speed", 6.8))
		stamina = maxf(stamina - float(_cfg.get("sprint_cost", 10.0)) * delta, 0.0)
		_stamina_wait = 0.4
	if blocking:
		speed *= 0.6
	var accel := float(_cfg.get("acceleration", 26.0))
	if not is_on_floor():
		accel *= float(_cfg.get("air_control", 0.3))
	velocity.x = move_toward(velocity.x, wish.x * speed, accel * delta)
	velocity.z = move_toward(velocity.z, wish.z * speed, accel * delta)
	if is_on_floor():
		velocity.y = -1.0
		if can_move and Input.is_action_just_pressed(&"jump") and not crouching and stamina >= 4.0:
			velocity.y = float(_cfg.get("jump_velocity", 4.6))
			stamina = maxf(stamina - float(_cfg.get("jump_cost", 8.0)), 0.0)
			_stamina_wait = 0.5
	else:
		velocity.y -= GRAVITY * delta
	move_and_slide()

	# Footsteps.
	var flat := move_speed()
	if is_on_floor() and flat > 0.8:
		_step_t -= delta * flat
		if _step_t <= 0.0:
			_step_t = 2.3
			Sfx.play(&"step", -22.0 if crouching else (-9.0 if sprinting else -14.0))

	# Attacks.
	if active and combat_enabled and _attack_t < 0.0:
		if Input.is_action_just_pressed(&"attack"):
			_start_attack(false)
		elif Input.is_action_just_pressed(&"throw"):
			_start_attack(true)
	if _attack_t >= 0.0:
		_attack_t += delta
		if not _attack_resolved and _attack_t >= _attack_hit_at:
			_attack_resolved = true
			_resolve_attack()
		if _attack_t >= _attack_end:
			_attack_t = -1.0

	# Interaction.
	_update_focus()
	if focus != null and active:
		if focus.hold_seconds <= 0.0:
			if Input.is_action_just_pressed(&"interact"):
				focus.interact(self)
		elif Input.is_action_pressed(&"interact"):
			hold_progress += delta / focus.hold_seconds
			if hold_progress >= 1.0:
				hold_progress = 0.0
				focus.interact(self)
		else:
			hold_progress = maxf(hold_progress - delta * 2.0, 0.0)

	# Recovery.
	_grace -= delta
	_stamina_wait -= delta
	if _stamina_wait <= 0.0 and not sprinting and not blocking:
		stamina = minf(stamina + float(_cfg.get("stamina_regen", 24.0)) * delta, max_stamina)
	_regen_wait -= delta
	if _regen_wait <= 0.0 and health < max_health:
		health = minf(health + float(_cfg.get("regen_rate", 5.0)) * delta, max_health)


func _process(delta: float) -> void:
	viewmodel.lowered = not combat_enabled
	viewmodel.update(delta, move_speed() if is_on_floor() else 0.0, _look_delta, crouching)
	_look_delta = Vector2.ZERO
	# Camera shake from blows given and taken.
	_shake = maxf(_shake - delta * 2.4, 0.0)
	var t := Time.get_ticks_msec() * 0.001
	camera.rotation.z = sin(t * 47.0) * 0.012 * _shake
	camera.rotation.x = sin(t * 61.0) * 0.01 * _shake
	if Game.settings.get("head_bob", true) and is_on_floor() and not _dead:
		var s := clampf(move_speed() / 6.0, 0.0, 1.0)
		camera.position.y = sin(t * (6.0 + move_speed())) * 0.018 * s


func _can_stand() -> bool:
	var q := PhysicsRayQueryParameters3D.create(global_position + Vector3(0, 1.0, 0), global_position + Vector3(0, 1.85, 0), 1)
	return get_world_3d().direct_space_state.intersect_ray(q).is_empty()
