class_name Mats
extends RefCounted
## The game's material library. Everything is procedural: shaders in
## assets/shaders plus a few standard materials for metal, skin and fire.

const _SHADER_DIR := "res://assets/shaders/"

static var _lib: Dictionary = {}
static var _local: Dictionary = {}
static var _sooty: Array[ShaderMaterial] = []


static func _shader(file: String, params: Dictionary = {}) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load(_SHADER_DIR + file)
	for k: String in params:
		m.set_shader_parameter(k, params[k])
	return m


static func _std(albedo: Color, metallic: float, roughness: float, vertex_color: bool = false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = albedo
	m.metallic = metallic
	m.roughness = roughness
	m.vertex_color_use_as_albedo = vertex_color
	m.vertex_color_is_srgb = true
	return m


static func _build() -> void:
	_lib.clear()
	_local.clear()
	_sooty.clear()
	# Citadel ashlar: large pale limestone blocks.
	_lib[&"limestone"] = _shader("stone_wall.gdshader")
	# Finer dressed stone for the great houses, palace and temple.
	_lib[&"ashlar"] = _shader("stone_wall.gdshader", {
		"block_size": Vector2(0.62, 0.31), "base_color": Color(0.80, 0.75, 0.63),
		"variation": 0.10, "weathering": 0.3, "bevel": 0.02})
	_lib[&"mudbrick"] = _shader("plaster.gdshader", {
		"plaster_color": Color(0.70, 0.58, 0.42), "reveal": 0.75})
	_lib[&"plaster"] = _shader("plaster.gdshader")
	_lib[&"plaster_fine"] = _shader("plaster.gdshader", {
		"plaster_color": Color(0.90, 0.86, 0.76), "reveal": 0.0, "bump": 0.5})
	_lib[&"roof"] = _shader("plaster.gdshader", {
		"plaster_color": Color(0.60, 0.50, 0.37), "reveal": 0.0, "bump": 1.4})
	_lib[&"rubble"] = _shader("rubble.gdshader", {"stone_scale": 4.0, "joint_width": 0.03})
	_lib[&"paving"] = _shader("rubble.gdshader", {
		"base_color": Color(0.60, 0.56, 0.48), "stone_scale": 2.3, "joint_width": 0.022,
		"variation": 0.16, "polish": 0.5, "bump": 0.7})
	_lib[&"wood"] = _shader("wood.gdshader")
	_lib[&"wood_dark"] = _shader("wood.gdshader", {
		"base_color": Color(0.20, 0.13, 0.08), "weathered": 0.15})
	_lib[&"wood_pale"] = _shader("wood.gdshader", {
		"base_color": Color(0.55, 0.40, 0.24), "weathered": 0.05, "plank_width": 0.3})
	_lib[&"wood_red"] = _shader("wood.gdshader", {
		"base_color": Color(0.52, 0.12, 0.08), "weathered": 0.1, "grain_vertical": true})
	_lib[&"wood_door"] = _shader("wood.gdshader", {
		"base_color": Color(0.30, 0.19, 0.11), "grain_vertical": true, "plank_width": 0.28})
	_lib[&"cloth"] = _shader("cloth.gdshader")
	_lib[&"cloth_stripe"] = _shader("cloth.gdshader", {"stripe": 1.6})
	_lib[&"cloth_sway"] = _shader("cloth.gdshader", {"sway": 1.0})
	_lib[&"ground"] = _shader("ground.gdshader")
	_lib[&"water"] = _shader("water.gdshader")

	var bronze := _std(Color(0.83, 0.56, 0.27), 1.0, 0.32)
	_lib[&"bronze"] = bronze
	_lib[&"bronze_dull"] = _std(Color(0.55, 0.40, 0.22), 1.0, 0.55)
	_lib[&"gold"] = _std(Color(1.0, 0.78, 0.32), 1.0, 0.25)
	_lib[&"silver"] = _std(Color(0.85, 0.85, 0.82), 1.0, 0.3)
	_lib[&"ivory"] = _std(Color(0.90, 0.85, 0.72), 0.0, 0.45)
	_lib[&"dark"] = _std(Color(0.015, 0.012, 0.01), 0.0, 1.0)
	# Skin, cloth and leather on figures are tinted per vertex.
	var tint := _std(Color.WHITE, 0.0, 0.8, true)
	_lib[&"tint"] = tint
	var hide := _std(Color.WHITE, 0.0, 0.6, true)
	_lib[&"hide"] = hide
	var tint2 := _std(Color.WHITE, 0.0, 0.85, true)
	tint2.cull_mode = BaseMaterial3D.CULL_DISABLED
	_lib[&"tint_2s"] = tint2
	var ember := _std(Color(1.0, 0.45, 0.1), 0.0, 1.0)
	ember.emission_enabled = true
	ember.emission = Color(1.0, 0.42, 0.08)
	ember.emission_energy_multiplier = 6.0
	_lib[&"ember"] = ember

	for key: StringName in _lib:
		var sm := _lib[key] as ShaderMaterial
		if sm != null and sm.shader != null and "soot" in sm.shader.code:
			_sooty.append(sm)


## Returns the shared material named [param id].
static func get_mat(id: StringName) -> Material:
	if _lib.is_empty():
		_build()
	return _lib.get(id)


## Returns the whole library, for [method GeoBuilder.commit].
static func all() -> Dictionary:
	if _lib.is_empty():
		_build()
	return _lib


## Library variant whose shaders texture in object space, for anything that
## moves (doors, the horse, carried shields) so the grain does not swim.
static func all_local() -> Dictionary:
	if _lib.is_empty():
		_build()
	if _local.is_empty():
		for key: StringName in _lib:
			var sm := _lib[key] as ShaderMaterial
			if sm != null:
				var copy := sm.duplicate() as ShaderMaterial
				copy.set_shader_parameter("local_space", true)
				_local[key] = copy
			else:
				_local[key] = _lib[key]
	return _local


## Blackens stone, plaster and timber as the city burns (0 clean, 1 charred).
static func set_soot(amount: float) -> void:
	if _lib.is_empty():
		_build()
	for sm in _sooty:
		sm.set_shader_parameter("soot", amount)


## Drops cached materials so a new session starts clean.
static func reset() -> void:
	_lib.clear()
	_local.clear()
	_sooty.clear()
