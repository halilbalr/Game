class_name Fire
extends Node3D
## A flame with its light: torch, brazier, hearth or burning house.
## [member size] is the flame's rough radius in metres.

static var _flame_mesh: QuadMesh
static var _smoke_mesh: QuadMesh
static var _noise_phase := 0.0

var size: float = 0.25
var light: OmniLight3D
var _flames: GPUParticles3D
var _smoke: GPUParticles3D
var _base_energy: float = 1.0
var _phase: float = 0.0
var _lit: bool = true


static func _soft_texture() -> GradientTexture2D:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	g.add_point(0.35, Color(1, 1, 1, 0.6))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(0.5, 0.0)
	t.width = 64
	t.height = 64
	return t


static func _ensure_meshes() -> void:
	if _flame_mesh != null:
		return
	var tex := _soft_texture()
	var fm := StandardMaterial3D.new()
	fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	fm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fm.vertex_color_use_as_albedo = true
	fm.albedo_texture = tex
	fm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	fm.billboard_keep_scale = true
	fm.disable_fog = true
	_flame_mesh = QuadMesh.new()
	_flame_mesh.material = fm
	var sm := StandardMaterial3D.new()
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm.vertex_color_use_as_albedo = true
	sm.albedo_texture = tex
	sm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	sm.billboard_keep_scale = true
	_smoke_mesh = QuadMesh.new()
	_smoke_mesh.material = sm


func _init(flame_size: float = 0.25, with_smoke: bool = false, shadows: bool = false) -> void:
	size = flame_size
	_ensure_meshes()
	_noise_phase += 1.7
	_phase = _noise_phase

	_flames = GPUParticles3D.new()
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = size * 0.45
	pm.direction = Vector3.UP
	pm.spread = 14.0
	pm.initial_velocity_min = 1.2 * sqrt(size * 4.0)
	pm.initial_velocity_max = 2.2 * sqrt(size * 4.0)
	pm.gravity = Vector3(0.0, 2.2, 0.0)
	pm.scale_min = size * 1.5
	pm.scale_max = size * 2.6
	var sc := Curve.new()
	sc.add_point(Vector2(0.0, 0.55))
	sc.add_point(Vector2(0.25, 1.0))
	sc.add_point(Vector2(1.0, 0.1))
	var sct := CurveTexture.new()
	sct.curve = sc
	pm.scale_curve = sct
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1.0, 0.9, 0.55, 0.0))
	ramp.set_color(1, Color(0.5, 0.06, 0.0, 0.0))
	ramp.add_point(0.12, Color(1.0, 0.78, 0.32, 0.9))
	ramp.add_point(0.5, Color(1.0, 0.38, 0.06, 0.65))
	ramp.add_point(0.8, Color(0.75, 0.14, 0.02, 0.3))
	var rt := GradientTexture1D.new()
	rt.gradient = ramp
	pm.color_ramp = rt
	pm.turbulence_enabled = size > 0.6
	pm.turbulence_noise_strength = 0.6
	_flames.process_material = pm
	_flames.draw_pass_1 = _flame_mesh
	_flames.amount = clampi(int(10 + size * 26.0), 10, 90)
	_flames.lifetime = 0.55 + size * 0.5
	_flames.preprocess = 1.0
	_flames.randomness = 0.4
	_flames.visibility_aabb = AABB(Vector3(-size * 3.0, -size, -size * 3.0), Vector3(size * 6.0, size * 10.0 + 3.0, size * 6.0))
	_flames.visibility_range_end = 60.0 + size * 160.0
	_flames.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_flames)

	if with_smoke:
		_smoke = GPUParticles3D.new()
		var sp := ParticleProcessMaterial.new()
		sp.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
		sp.emission_sphere_radius = size * 0.6
		sp.direction = Vector3(0.25, 1.0, 0.1)
		sp.spread = 12.0
		sp.initial_velocity_min = 1.6
		sp.initial_velocity_max = 3.2
		sp.gravity = Vector3(0.5, 0.6, 0.2)
		sp.scale_min = size * 2.0
		sp.scale_max = size * 4.0
		var ssc := Curve.new()
		ssc.add_point(Vector2(0.0, 0.3))
		ssc.add_point(Vector2(1.0, 1.6))
		var ssct := CurveTexture.new()
		ssct.curve = ssc
		sp.scale_curve = ssct
		var sramp := Gradient.new()
		sramp.set_color(0, Color(0.25, 0.14, 0.08, 0.0))
		sramp.set_color(1, Color(0.05, 0.05, 0.05, 0.0))
		sramp.add_point(0.15, Color(0.16, 0.11, 0.08, 0.5))
		sramp.add_point(0.6, Color(0.07, 0.065, 0.06, 0.32))
		var srt := GradientTexture1D.new()
		srt.gradient = sramp
		sp.color_ramp = srt
		_smoke.process_material = sp
		_smoke.draw_pass_1 = _smoke_mesh
		_smoke.amount = clampi(int(16 + size * 8.0), 16, 60)
		_smoke.lifetime = 5.0 + size
		_smoke.preprocess = 3.0
		_smoke.position = Vector3(0.0, size * 1.6, 0.0)
		_smoke.visibility_aabb = AABB(Vector3(-size * 8.0, -size, -size * 8.0), Vector3(size * 16.0 + 8.0, size * 14.0 + 22.0, size * 16.0 + 8.0))
		_smoke.visibility_range_end = 450.0
		_smoke.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_smoke)

	light = OmniLight3D.new()
	light.light_color = Color(1.0, 0.60, 0.26)
	_base_energy = 1.4 + size * 4.5
	light.light_energy = _base_energy
	light.omni_range = 7.0 + size * 22.0
	light.omni_attenuation = 1.3
	light.position = Vector3(0.0, size * 1.2 + 0.1, 0.0)
	light.shadow_enabled = shadows
	light.shadow_bias = 0.08
	light.distance_fade_enabled = true
	light.distance_fade_begin = 70.0 + size * 120.0
	light.distance_fade_length = 30.0
	light.light_volumetric_fog_energy = 1.4
	add_child(light)
	if Game.lite:
		# Fewer sparks, and lamps that fade out sooner.
		_flames.amount = maxi(6, _flames.amount / 2)
		_flames.visibility_range_end = minf(_flames.visibility_range_end, 55.0 + size * 60.0)
		light.shadow_enabled = false
		light.distance_fade_begin = 42.0 + size * 30.0
		light.distance_fade_length = 12.0
		if _smoke != null:
			_smoke.amount = maxi(8, _smoke.amount / 2)


func _process(_delta: float) -> void:
	if not _lit:
		return
	var t := Time.get_ticks_msec() * 0.001 + _phase
	var f := 0.82 + 0.12 * sin(t * 11.0) + 0.08 * sin(t * 23.7 + 1.3) + 0.06 * sin(t * 5.3 + 2.1)
	light.light_energy = _base_energy * f


## Lights or douses the flame.
func set_lit(on: bool) -> void:
	_lit = on
	_flames.emitting = on
	if _smoke != null:
		_smoke.emitting = on
	light.visible = on
