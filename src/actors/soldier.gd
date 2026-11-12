class_name Soldier
extends CharacterBody3D
## A fighting man (or townsperson) under AI control. Seeks enemies, closes to
## the reach of his weapon, strikes with a visible wind-up, sometimes takes a
## blow on his shield, and dies where he falls. Watchmen start unaware and
## must see or hear the player first.

signal died(soldier: Soldier, killer: Node3D)
signal alerted(soldier: Soldier)

enum State { IDLE, MOVE, COMBAT, DEAD }

const GRAVITY := 19.0

var battle: Battlefield
var role_id: String = ""
var role: Dictionary = {}
var side: StringName = &"trojan"
var display_name: String = ""
var hero: bool = false
var civilian: bool = false
var max_health: float = 60.0
var health: float = 60.0
var skill: float = 0.4
var figure: Humanoid
var weapon_id: String = ""
var weapon: Dictionary = {}
var state: State = State.IDLE
var target: Node3D
## Aware soldiers hunt enemies. Unaware ones must first notice the player.
var aware: bool = true
var asleep: bool = false
## A watchman's suspicion, 0 to 1. At 1 he raises the alarm.
var detection: float = 0.0
var invulnerable: bool = false
## Holding soldiers keep their post and fight only what comes to them.
var hold: bool = false
var goal: Vector3 = Vector3.ZERO
var has_goal: bool = false
var goal_radius: float = 2.0
var leader: Node3D
var follow_offset: Vector3 = Vector3.ZERO
var patrol: Array[Vector3] = []
var idle_stance: StringName = &"guard"
var engage_range: float = 24.0
var damage_scale: float = 1.0
var throws_left: int = 0
var body_scale: float = 1.0

var _nav: NavigationAgent3D
var _think_t: float = 0.0
var _cooldown: float = 0.0
var _stun: float = 0.0
var _block_show: float = 0.0
var _attack_pending: bool = false
var _attack_timer: float = 0.0
var _attack_is_throw: bool = false
var _repath: float = 0.0
var _nav_dest: Vector3 = Vector3.INF
var _strafe: float = 1.0
var _patrol_i: int = 0
var _patrol_wait: float = 0.0
var _stuck_t: float = 0.0


## Applies role data. Call before adding to the tree.
func configure(id: String, data: Dictionary, variant: int) -> void:
	role_id = id
	role = data
	side = StringName(str(data.get("side", "trojan")))
	display_name = str(data.get("name", id))
	civilian = bool(data.get("civilian", false))
	max_health = float(data.get("health", 60.0))
	health = max_health
	skill = float(data.get("skill", 0.4))
	body_scale = float(data.get("scale", 1.0))
	hero = data.has("epithet")
	var weapons: Array = data.get("weapons", [])
	weapon_id = str(weapons[0]) if not weapons.is_empty() else ""
	weapon = Data.weapons.get(weapon_id, {})
	engage_range = float(Data.tune("ai.engage_range", 24.0))
	name = "%s_%d" % [id, variant]

	collision_layer = 4
	collision_mask = 1
	var shape := CapsuleShape3D.new()
	shape.radius = 0.32
	shape.height = 1.74
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position = Vector3(0, 0.87, 0)
	add_child(cs)
	floor_snap_length = 0.5
	floor_max_angle = deg_to_rad(50.0)

	figure = Humanoid.new()
	figure.scale = Vector3.ONE * body_scale
	add_child(figure)
	var outfit_id := str(data.get("outfit", id))
	figure.setup(outfit_id, Data.characters.get("outfits", {}).get(outfit_id, {}), variant, weapon_id)
	figure.stance = &"idle" if civilian else &"guard"
	idle_stance = figure.stance

	_nav = NavigationAgent3D.new()
	_nav.path_desired_distance = 0.8
	_nav.target_desired_distance = 0.7
	_nav.avoidance_enabled = false
	_nav.path_max_distance = 3.0
	add_child(_nav)
	_strafe = 1.0 if variant % 2 == 0 else -1.0
	if weapon_id == "spear" and not hero and variant % 3 == 0:
		throws_left = 1


## Applies spawn options (see [method Battlefield.spawn]).
func apply_options(opts: Dictionary) -> void:
	if opts.has("name"):
		display_name = opts["name"]
	if opts.has("stance"):
		idle_stance = opts["stance"]
		figure.stance = idle_stance
	aware = opts.get("aware", true)
	asleep = opts.get("asleep", false)
	hold = opts.get("hold", false)
	invulnerable = opts.get("invulnerable", false)
	if opts.has("health"):
		max_health = opts["health"]
		health = max_health
	if opts.has("patrol"):
		patrol.assign(opts["patrol"])
	if opts.has("goal"):
		set_goal(opts["goal"], opts.get("goal_radius", 2.0))
	if opts.has("leader"):
		leader = opts["leader"]
		follow_offset = opts.get("follow_offset", Vector3(randf_range(-2.5, 2.5), 0, randf_range(1.5, 4.0)))
	if opts.has("damage_scale"):
		damage_scale = opts["damage_scale"]
	if opts.has("engage_range"):
		engage_range = opts["engage_range"]
	if opts.has("throws"):
		throws_left = opts["throws"]


func is_alive() -> bool:
	return state != State.DEAD


## Sends the soldier to a point; he fights what he meets on the way.
func set_goal(point: Vector3, radius: float = 2.0) -> void:
	goal = point
	goal_radius = radius
	has_goal = true


func clear_goal() -> void:
	has_goal = false


## Height of the eyes above the feet (for line-of-sight checks).
func eye_position() -> Vector3:
	return global_position + Vector3(0, 1.55 * body_scale, 0)


func _valid(t: Node3D) -> bool:
	return t != null and is_instance_valid(t) and t.has_method("is_alive") and t.is_alive()


func _forward() -> Vector3:
	return -global_transform.basis.z


func _face(dir: Vector3, delta: float, rate: float = 10.0) -> void:
	if dir.length_squared() < 1e-6:
		return
	rotation.y = lerp_angle(rotation.y, atan2(-dir.x, -dir.z), 1.0 - exp(-rate * delta))


func _path_dir(dest: Vector3, delta: float) -> Vector3:
	var direct := dest - global_position
	direct.y = 0.0
	if battle != null and battle.nav_ready and direct.length() > 2.5:
		_repath -= delta
		if _repath <= 0.0 or _nav_dest.distance_squared_to(dest) > 9.0:
			_nav.target_position = dest
			_nav_dest = dest
			_repath = float(Data.tune("ai.repath_seconds", 0.45)) + randf() * 0.2
		var next := _nav.get_next_path_position()
		var d := next - global_position
		d.y = 0.0
		if d.length() > 0.08:
			return d.normalized()
	return direct.normalized() if direct.length() > 0.05 else Vector3.ZERO


func _think(dt: float) -> void:
	if asleep or not aware:
		_perceive(dt)
		if not aware:
			return
	if civilian:
		return
	# Keep a live target; otherwise look for the nearest enemy.
	var keep := _valid(target) and global_position.distance_to(target.global_position) < engage_range * 1.4
	if not keep:
		target = battle.nearest_enemy(global_position, side, engage_range)
	else:
		# Switch to something much closer if it turns up.
		var near := battle.nearest_enemy(global_position, side, 4.0)
		if near != null and near != target and global_position.distance_to(target.global_position) > 5.0:
			target = near
	if target != null:
		state = State.COMBAT
		figure.stance = &"guard"
		_maybe_throw()
	elif has_goal or leader != null or not patrol.is_empty():
		state = State.MOVE
	else:
		state = State.IDLE
		figure.stance = idle_stance


func _perceive(dt: float) -> void:
	var p := battle.player
	if p == null or not p.is_alive() or p.side == side:
		return
	var eye := eye_position()
	var to := p.eye_position() - eye
	var dist := to.length()
	var cfg: Dictionary = Data.tuning.get("stealth", {})
	var gain := 0.0
	if dist < 30.0:
		var flat := Vector3(to.x, 0, to.z)
		var angle := rad_to_deg(_forward().angle_to(flat)) if flat.length() > 0.01 else 0.0
		var los := false
		if dist < float(cfg.get("view_range", 21.0)) + 1.0 and not asleep:
			var q := PhysicsRayQueryParameters3D.create(eye, p.eye_position(), 1)
			los = get_world_3d().direct_space_state.intersect_ray(q).is_empty()
		gain = Combat.detection_gain(dist, angle, p.crouching, p.move_speed(), los, asleep, cfg)
	if gain > 0.0:
		detection += gain * dt
	else:
		detection -= float(cfg.get("forget_rate", 0.3)) * dt
	detection = clampf(detection, 0.0, 1.0)
	if detection >= 1.0:
		alert(p)
	elif detection > 0.45 and not asleep:
		# Suspicious: turn toward the sound.
		_face(Vector3(to.x, 0, to.z), dt, 2.0)


## Makes a watchman aware of [param source] and raises the cry.
func alert(source: Node3D) -> void:
	if state == State.DEAD or (aware and not asleep):
		return
	aware = true
	asleep = false
	detection = 1.0
	hold = false
	figure.stance = &"guard"
	if civilian:
		return
	target = source
	_stun = 0.5
	Sfx.play_at(&"shout", global_position)
	alerted.emit(self)


func _maybe_throw() -> void:
	if throws_left <= 0 or _attack_pending or _cooldown > 0.0 or not _valid(target):
		return
	var dist := global_position.distance_to(target.global_position)
	if dist < 8.0 or dist > 19.0 or randf() > 0.22:
		return
	var q := PhysicsRayQueryParameters3D.create(eye_position(), target.global_position + Vector3(0, 1.2, 0), 1)
	if not get_world_3d().direct_space_state.intersect_ray(q).is_empty():
		return
	throws_left -= 1
	figure.attack(&"throw", 0.5, 0.12, 0.5)
	_attack_pending = true
	_attack_is_throw = true
	_attack_timer = 0.56
	_cooldown = 2.4


func _begin_attack() -> void:
	var slow := 1.0 + (1.0 - skill) * 0.4
	var windup := float(weapon.get("windup", 0.3)) * slow + 0.14
	var strike := float(weapon.get("strike", 0.12))
	var recover := float(weapon.get("recover", 0.5))
	figure.attack(StringName(str(weapon.get("kind", "thrust"))), windup, strike, recover)
	_attack_pending = true
	_attack_is_throw = false
	_attack_timer = windup + strike * 0.6
	var lo := float(Data.tune("ai.attack_cooldown_min", 0.9))
	var hi := float(Data.tune("ai.attack_cooldown_max", 2.0))
	_cooldown = windup + strike + recover + randf_range(lo, hi) * (1.3 - skill * 0.7)
	Sfx.play_at(&"whoosh", global_position, -8.0)


func _resolve_attack() -> void:
	if not _valid(target) or _stun > 0.0:
		return
	if _attack_is_throw:
		var from := eye_position() + _forward() * 0.5
		var aim := target.global_position + Vector3(0, 1.15, 0)
		if "velocity" in target:
			aim += (target.velocity as Vector3) * 0.35
		var dvec := aim - from
		var speed := float(Data.weapons.get("spear", {}).get("throw_speed", 25.0))
		var t := dvec.length() / speed
		var vel := dvec / maxf(t, 0.05) + Vector3(0, 4.9 * t, 0)
		vel += Vector3(randf_range(-1, 1), randf_range(-0.6, 0.6), randf_range(-1, 1)) * (1.4 - skill)
		battle.throw_spear(self, side, from, vel, float(Data.weapons.get("spear", {}).get("throw_damage", 80.0)) * 0.55 * damage_scale)
		return
	var to := target.global_position - global_position
	to.y = 0.0
	var dist := to.length()
	var reach := float(weapon.get("reach", 1.7))
	if dist > reach + 0.5:
		return
	var arc := deg_to_rad(float(weapon.get("arc_deg", 40.0))) * 0.5 + 0.35
	if dist > 0.4 and _forward().angle_to(to) > arc:
		return
	# Where the blow lands: mostly the body.
	var roll := randf()
	var height := 1.15
	if roll < 0.12 + skill * 0.08:
		height = 1.58
	elif roll > 0.86:
		height = 0.5
	var base := float(weapon.get("damage", 30.0)) * (0.7 + 0.5 * skill) * damage_scale
	var result: Dictionary = target.receive_hit(self, base, height, to.normalized(), weapon_id)
	if result.get("blocked", false):
		Sfx.play_at(&"block", target.global_position)
		_stun = 0.25
	elif not result.is_empty():
		Sfx.play_at(&"hit", target.global_position)


## Takes a blow. Returns {"blocked", "killed", "damage", "zone", "stealth"}.
func receive_hit(attacker: Node3D, base_damage: float, height: float, dir: Vector3, _weapon: String = "") -> Dictionary:
	if state == State.DEAD or invulnerable:
		return {}
	var to_att := attacker.global_position - global_position if attacker != null else -dir
	var behind := Combat.is_behind(_forward(), to_att)
	var by_player := attacker is Player
	# An unaware or sleeping man dies without a sound.
	if by_player and (not aware or asleep):
		health = 0.0
		Blood.spray(battle, global_position + Vector3(0, 1.3, 0), dir + Vector3(0, 0.4, 0), 1.2)
		_die(attacker, dir, true)
		return {"blocked": false, "killed": true, "damage": max_health, "zone": &"body", "stealth": true}
	var cfg: Dictionary = Data.tuning.get("combat", {})
	if figure.has_shield() and not behind and _stun <= 0.0 and not civilian:
		var chance := 0.08 + 0.42 * skill
		if _attack_pending:
			chance *= 0.35
		if randf() < chance:
			_block_show = 0.5
			_face(to_att, 1.0, 100.0)
			return {"blocked": true, "killed": false, "damage": 0.0, "zone": &"body"}
	var zone := Combat.hit_zone(height, body_scale, figure.crouching)
	var dmg := Combat.damage(base_damage, zone, Combat.armor_value(str(figure.look.get("armor", "none"))), behind, randf(), cfg)
	health -= dmg
	Blood.spray(battle, global_position + Vector3(0, clampf(height, 0.3, 1.65), 0), -dir + Vector3(0, 0.5, 0),
		1.4 if zone == &"head" else 1.0)
	figure.flinch(1.0)
	_stun = float(cfg.get("hit_stun", 0.38)) * (0.5 if hero else 1.0)
	if _attack_pending and not hero:
		_attack_pending = false
	if not aware or asleep:
		alert(attacker)
	if _valid(attacker) and not civilian:
		target = attacker
	if health <= 0.0:
		_die(attacker, dir, false)
		return {"blocked": false, "killed": true, "damage": dmg, "zone": zone}
	Sfx.play_at(&"grunt", global_position, -4.0)
	return {"blocked": false, "killed": false, "damage": dmg, "zone": zone}


func _die(killer: Node3D, dir: Vector3, quiet: bool) -> void:
	state = State.DEAD
	health = 0.0
	collision_layer = 0
	collision_mask = 0
	velocity = Vector3.ZERO
	# Struck from the front a man goes over backward; from behind, on his face.
	var fall_forward := _forward().dot(dir) > 0.0
	figure.die(fall_forward)
	if not quiet:
		Sfx.play_at(&"death", global_position)
	else:
		Sfx.play_at(&"thud", global_position, -6.0)
	var pos := global_position
	var tree := get_tree()
	if tree != null:
		tree.create_timer(0.9).timeout.connect(func() -> void:
			if is_instance_valid(battle):
				Blood.pool(battle, pos))
	if weapon_id == "spear" and battle != null and randf() < 0.45:
		battle.drop_spear(pos + Vector3(randf_range(-0.8, 0.8), 0, randf_range(-0.8, 0.8)))
	died.emit(self, killer)
	set_physics_process(false)


## Kills the soldier outright (used by missions for scripted deaths).
func kill(dir: Vector3 = Vector3.FORWARD) -> void:
	if state != State.DEAD:
		_die(null, dir, false)


func _combat_velocity(delta: float) -> Vector3:
	if not _valid(target):
		target = null
		state = State.IDLE
		return Vector3.ZERO
	var to := target.global_position - global_position
	to.y = 0.0
	var dist := to.length()
	var dir := to / maxf(dist, 0.001)
	_face(dir, delta)
	var reach := float(weapon.get("reach", 1.7))
	var want := reach * 0.8
	var run := float(Data.tune("ai.run_speed", 4.4)) * (0.92 + 0.16 * skill)
	var slot := true
	if target is Player:
		slot = battle.take_player_slot(self)
		if not slot:
			want = 4.2
	var move := Vector3.ZERO
	if hold and dist > reach * 2.4:
		move = Vector3.ZERO
	elif dist > want + 0.2:
		move = _path_dir(target.global_position, delta) * (run if dist > want + 1.2 else run * 0.5)
	elif dist < want * 0.55:
		move = -dir * 1.3
	else:
		move = dir.cross(Vector3.UP) * _strafe * 0.6
	if slot and dist <= reach * 0.97 and _cooldown <= 0.0 and _stun <= 0.0 and not _attack_pending \
			and not civilian and not weapon.is_empty():
		_begin_attack()
	return move


func _travel_velocity(delta: float) -> Vector3:
	var walk := float(Data.tune("ai.walk_speed", 1.5))
	var run := float(Data.tune("ai.run_speed", 4.4))
	var dest := Vector3.ZERO
	var speed := run
	var stop_at := goal_radius
	if has_goal:
		dest = goal
	elif leader != null and is_instance_valid(leader):
		dest = leader.global_position + leader.global_transform.basis * follow_offset
		stop_at = 1.6
		var gap := global_position.distance_to(dest)
		speed = run if gap > 6.0 else walk * 1.8
	elif not patrol.is_empty():
		if _patrol_wait > 0.0:
			_patrol_wait -= delta
			figure.stance = &"sentry"
			return Vector3.ZERO
		dest = patrol[_patrol_i]
		speed = walk
		stop_at = 0.7
	else:
		return Vector3.ZERO
	var to := dest - global_position
	to.y = 0.0
	if to.length() <= stop_at:
		if has_goal:
			# Arrived: hold here and face the way we came in.
			pass
		elif not patrol.is_empty():
			_patrol_i = (_patrol_i + 1) % patrol.size()
			_patrol_wait = randf_range(2.0, 5.0)
		figure.stance = idle_stance
		return Vector3.ZERO
	figure.stance = &"guard" if not civilian else &"idle"
	var dir := _path_dir(dest, delta)
	_face(dir, delta, 6.0)
	return dir * speed


func _physics_process(delta: float) -> void:
	if state == State.DEAD:
		return
	_cooldown -= delta
	_stun -= delta
	_block_show -= delta
	_think_t -= delta
	if _think_t <= 0.0:
		_think_t = 0.2 + randf() * 0.08
		_think(0.24)
	var desired := Vector3.ZERO
	if not asleep and aware:
		match state:
			State.COMBAT:
				desired = _combat_velocity(delta)
			State.MOVE:
				desired = _travel_velocity(delta)
			_:
				pass
	elif not asleep and not patrol.is_empty():
		desired = _travel_velocity(delta)
	if _stun > 0.0:
		desired = Vector3.ZERO
	if not asleep:
		desired += battle.separation(self, float(Data.tune("ai.separation", 0.95)))
	velocity.x = move_toward(velocity.x, desired.x, 22.0 * delta)
	velocity.z = move_toward(velocity.z, desired.z, 22.0 * delta)
	if is_on_floor():
		velocity.y = -1.0
	else:
		velocity.y -= GRAVITY * delta
	move_and_slide()
	var flat := Vector2(velocity.x, velocity.z).length()
	figure.speed = flat
	figure.blocking = _block_show > 0.0
	# Unstick: if we want to move but are not, sidestep.
	if desired.length() > 1.0 and get_real_velocity().length() < 0.2:
		_stuck_t += delta
		if _stuck_t > 0.8:
			_strafe = -_strafe
			_repath = 0.0
			velocity += global_transform.basis.x * _strafe * 2.5
			_stuck_t = 0.0
	else:
		_stuck_t = 0.0
	if _attack_pending:
		_attack_timer -= delta
		if _attack_timer <= 0.0:
			_attack_pending = false
			_resolve_attack()
