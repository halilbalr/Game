class_name Battlefield
extends Node3D
## Everyone fighting in a mission: spawning, target queries, the limit on how
## many enemies may press the player at once, corpses and dropped spears.

signal soldier_died(soldier: Soldier, killer: Node3D)
signal sentry_alerted(soldier: Soldier)

var player: Player
var soldiers: Array[Soldier] = []
## Set once a navigation mesh covers the play area.
var nav_ready: bool = false
var _corpses: Array[Soldier] = []
var _player_slots: Array[Soldier] = []
var _variant: int = 0
var _enemy_cache: Dictionary = {}
var _cache_frame: int = -1


func _init() -> void:
	name = "Battlefield"


## Spawns a soldier of the given role. Options: variant, stance, aware,
## asleep, hold, patrol, goal, leader, name, invulnerable, health.
func spawn(role_id: String, pos: Vector3, yaw: float = 0.0, opts: Dictionary = {}) -> Soldier:
	var roles: Dictionary = Data.characters.get("roles", {})
	if not roles.has(role_id):
		push_error("Battlefield: unknown role '%s'" % role_id)
		return null
	_variant += 1
	var s := Soldier.new()
	s.battle = self
	s.configure(role_id, roles[role_id], opts.get("variant", _variant))
	add_child(s)
	s.global_position = pos
	s.rotation.y = yaw
	s.apply_options(opts)
	soldiers.append(s)
	s.died.connect(_on_died)
	s.alerted.connect(func(who: Soldier) -> void: sentry_alerted.emit(who))
	return s


func _on_died(s: Soldier, killer: Node3D) -> void:
	soldiers.erase(s)
	_player_slots.erase(s)
	_corpses.append(s)
	var limit := int(Data.tune("combat.corpse_limit", 70))
	while _corpses.size() > limit:
		var old: Soldier = _corpses.pop_front()
		if is_instance_valid(old):
			old.queue_free()
	soldier_died.emit(s, killer)


## Living soldiers of one side.
func living(side: StringName) -> Array[Soldier]:
	var out: Array[Soldier] = []
	for s in soldiers:
		if s.side == side and s.is_alive():
			out.append(s)
	return out


## Everything hostile to [param side] that can be struck: soldiers and the
## player. The list is built once per physics tick and shared: do not modify it.
func enemies_of(side: StringName) -> Array[Node3D]:
	var frame := Engine.get_physics_frames()
	if frame != _cache_frame:
		_cache_frame = frame
		_enemy_cache.clear()
	if _enemy_cache.has(side):
		return _enemy_cache[side]
	var out: Array[Node3D] = []
	for s in soldiers:
		if s.side != side and s.is_alive() and not s.civilian:
			out.append(s)
	if player != null and player.side != side and player.is_alive():
		out.append(player)
	_enemy_cache[side] = out
	return out


## Nearest living enemy of [param side] within [param max_range] of [param from].
func nearest_enemy(from: Vector3, side: StringName, max_range: float) -> Node3D:
	var best: Node3D = null
	var best_d := max_range * max_range
	for e in enemies_of(side):
		var d := from.distance_squared_to(e.global_position)
		# The player draws a little less attention so allies get their share.
		if e is Player:
			d *= 1.25
		if d < best_d:
			best_d = d
			best = e
	return best


## Grants or refuses one of the few places from which the player may be attacked.
func take_player_slot(s: Soldier) -> bool:
	var live: Array[Soldier] = []
	for o in _player_slots:
		if is_instance_valid(o) and o.is_alive() and o.target == player:
			live.append(o)
	_player_slots = live
	if s in _player_slots:
		return true
	if _player_slots.size() < int(Data.tune("combat.max_attackers_on_player", 3)):
		_player_slots.append(s)
		return true
	return false


## Push needed to keep [param s] from standing inside its neighbours.
func separation(s: Soldier, radius: float) -> Vector3:
	var push := Vector3.ZERO
	var pos := s.global_position
	for o in soldiers:
		if o == s or not o.is_alive():
			continue
		var d := pos - o.global_position
		d.y = 0.0
		var len := d.length()
		if len < radius and len > 0.001:
			push += d / len * (radius - len) * 3.0
	if player != null and player.is_alive():
		var d := pos - player.global_position
		d.y = 0.0
		var len := d.length()
		if len < radius * 0.9 and len > 0.001:
			push += d / len * (radius * 0.9 - len) * 4.0
	return push


## Number of living soldiers of [param side] within [param radius] of a point.
func count_near(side: StringName, pos: Vector3, radius: float) -> int:
	var n := 0
	for s in soldiers:
		if s.side == side and s.is_alive() and s.global_position.distance_to(pos) <= radius:
			n += 1
	return n


## Throws a spear from [param from] with the given velocity.
func throw_spear(thrower: Node3D, side: StringName, from: Vector3, velocity: Vector3, damage: float) -> void:
	var p := SpearProjectile.new()
	p.thrower = thrower
	p.side = side
	p.velocity = velocity
	p.damage = damage
	p.battle = self
	add_child(p)
	p.global_position = from
	Sfx.play_at(&"whoosh_throw", from)


## Leaves a spear lying on the ground for the player to take.
func drop_spear(pos: Vector3) -> void:
	var node := Node3D.new()
	add_child(node)
	var y := TroyLayout.height(pos.x, pos.z)
	if absf(y - pos.y) > 1.0:
		y = pos.y
	node.global_position = Vector3(pos.x, y + 0.04, pos.z)
	node.rotation = Vector3(0.0, randf() * TAU, 0.0)
	var mi := MeshInstance3D.new()
	mi.mesh = Gear.weapon_mesh("spear", Mats.all())
	node.add_child(mi)
	_attach_pickup(node, 0.2)


## Turns a spear that has stuck in the ground into a pickup.
func make_spear_pickup(spear: Node3D) -> void:
	_attach_pickup(spear, 0.3)


func _attach_pickup(node: Node3D, focus: float) -> void:
	var it := Interactable.new()
	it.prompt = "Take spear"
	it.radius = 2.3
	it.focus_height = focus
	node.add_child(it)
	it.used.connect(func(p: Node3D) -> void:
		if p is Player and (p as Player).add_spear():
			node.queue_free())
	get_tree().create_timer(120.0).timeout.connect(func() -> void:
		if is_instance_valid(node):
			node.queue_free())
