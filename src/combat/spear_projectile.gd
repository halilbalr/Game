class_name SpearProjectile
extends Node3D
## A thrown spear in flight. Strikes the first enemy or wall it meets; a spear
## that lands in the ground can be picked up again.

var velocity := Vector3.ZERO
var thrower: Node3D
var side: StringName
var damage: float = 70.0
var battle: Battlefield
var _stuck: bool = false
var _age: float = 0.0


func _ready() -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = Gear.weapon_mesh("spear", Mats.all())
	# Carry the mesh so its balance point is the node origin.
	mi.position = Vector3(0, 0, -0.3)
	add_child(mi)
	_aim()


func _aim() -> void:
	if velocity.length() > 0.1:
		var up := Vector3.UP if absf(velocity.normalized().y) < 0.98 else Vector3.RIGHT
		look_at(global_position + velocity, up)


func _physics_process(delta: float) -> void:
	if _stuck:
		return
	_age += delta
	if _age > 8.0:
		queue_free()
		return
	velocity.y -= 9.8 * delta
	var from := global_position
	var to := from + velocity * delta
	# Bodies first.
	var best: Node3D = null
	var best_t := 2.0
	var best_height := 1.2
	for c in battle.enemies_of(side):
		var feet: Vector3 = c.global_position
		if feet.distance_squared_to(from) > 36.0:
			continue
		var pts := Geometry3D.get_closest_points_between_segments(from, to, feet + Vector3(0, 0.15, 0), feet + Vector3(0, 1.75, 0))
		if pts[0].distance_to(pts[1]) < 0.4:
			var t := from.distance_to(pts[0]) / maxf(from.distance_to(to), 0.001)
			if t < best_t:
				best_t = t
				best = c
				best_height = pts[1].y - feet.y
	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(from, to, 1)
	var hit := space.intersect_ray(query)
	if best != null and (hit.is_empty() or from.distance_to(hit["position"]) > from.distance_to(to) * best_t):
		var result: Dictionary = best.receive_hit(thrower, damage, best_height, velocity.normalized(), "spear")
		Sfx.play_at(&"block" if result.get("blocked", false) else &"hit", best.global_position)
		if result.get("blocked", false) or randf() < 0.6:
			battle.drop_spear(best.global_position + Vector3(randf_range(-0.6, 0.6), 0, randf_range(-0.6, 0.6)))
		queue_free()
		return
	if not hit.is_empty():
		global_position = (hit["position"] as Vector3) - velocity.normalized() * 0.25
		_aim()
		_stuck = true
		Sfx.play_at(&"thud", global_position)
		battle.make_spear_pickup(self)
		return
	global_position = to
	_aim()
