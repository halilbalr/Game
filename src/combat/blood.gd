class_name Blood
extends RefCounted
## Blood effects: a spray where a blow lands and a pool where a man falls.
## Respects the "blood" option.

static var _spray_mesh: QuadMesh
static var _pool_material: StandardMaterial3D
static var _pool_mesh: PlaneMesh


static func _ensure() -> void:
	if _spray_mesh != null:
		return
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	m.albedo_color = Color(0.32, 0.01, 0.01)
	m.roughness = 0.35
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.billboard_keep_scale = true
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	g.add_point(0.6, Color(1, 1, 1, 0.9))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(0.5, 0.0)
	t.width = 32
	t.height = 32
	m.albedo_texture = t
	_spray_mesh = QuadMesh.new()
	_spray_mesh.size = Vector2(0.07, 0.07)
	_spray_mesh.material = m

	_pool_material = StandardMaterial3D.new()
	_pool_material.albedo_color = Color(0.22, 0.008, 0.008, 0.92)
	_pool_material.roughness = 0.18
	_pool_material.metallic_specular = 0.7
	_pool_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_pool_material.albedo_texture = t
	_pool_mesh = PlaneMesh.new()
	_pool_mesh.size = Vector2(1.0, 1.0)
	_pool_mesh.material = _pool_material


## A burst of blood at [param pos], thrown along [param dir].
static func spray(parent: Node, pos: Vector3, dir: Vector3, amount: float = 1.0) -> void:
	if not Game.settings.get("blood", true):
		return
	_ensure()
	var p := GPUParticles3D.new()
	var pm := ParticleProcessMaterial.new()
	pm.direction = dir.normalized() if dir.length() > 0.01 else Vector3.UP
	pm.spread = 38.0
	pm.initial_velocity_min = 1.6
	pm.initial_velocity_max = 4.6
	pm.gravity = Vector3(0, -9.8, 0)
	pm.scale_min = 0.5
	pm.scale_max = 1.5
	pm.color = Color(0.9, 0.9, 0.9, 1.0)
	p.process_material = pm
	p.draw_pass_1 = _spray_mesh
	p.amount = int(18 * amount)
	p.lifetime = 0.7
	p.one_shot = true
	p.explosiveness = 0.92
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(p)
	p.global_position = pos
	p.emitting = true
	p.get_tree().create_timer(1.6).timeout.connect(p.queue_free)


## A pool that spreads on the ground under a body.
static func pool(parent: Node, pos: Vector3, size: float = 1.3) -> void:
	if not Game.settings.get("blood", true):
		return
	_ensure()
	var mi := MeshInstance3D.new()
	mi.mesh = _pool_mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	var y := pos.y
	# Lie on the terrain when over open ground; otherwise keep the given height.
	var ground := TroyLayout.height(pos.x, pos.z)
	if absf(ground - pos.y) < 0.6:
		y = ground
	mi.global_position = Vector3(pos.x, y + 0.045, pos.z)
	mi.rotation.y = randf() * TAU
	mi.scale = Vector3(0.15, 1.0, 0.15)
	var tw := mi.create_tween()
	tw.tween_property(mi, "scale", Vector3(size * randf_range(0.8, 1.2), 1.0, size * randf_range(0.7, 1.1)), 5.0) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	mi.add_to_group(&"blood_pools")
	var pools := parent.get_tree().get_nodes_in_group(&"blood_pools")
	if pools.size() > 60:
		pools[0].queue_free()
