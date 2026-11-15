class_name Mats
extends RefCounted
## The game's material library. Everything is procedural: shaders in
## assets/shaders plus a few standard materials for metal, skin and fire.

const _SHADER_DIR := "res://assets/shaders/"

## Materials of figures and their gear: name -> [shader file, parameters].
## Shared with the first-person view (see [Viewmodel.materials]).
const FIGURE := {
	&"figure": ["figure.gdshader", {}],
	&"metal": ["metal.gdshader", {"base_color": Color.WHITE}],
	&"skin": ["figure.gdshader", {"rough": 0.58, "grain": 0.07, "grain_size": 90.0, "sheen": 0.22}],
	&"hair": ["figure.gdshader", {"rough": 0.5, "grain": 0.1, "strands": 0.5, "sheen": 0.12}],
	&"eye": ["figure.gdshader", {"rough": 0.12, "grain": 0.0}],
	&"wool": ["figure.gdshader", {"rough": 0.92, "grain": 0.1, "grain_size": 25.0, "weave": 900.0}],
	&"tint": ["figure.gdshader", {"rough": 0.8, "grain": 0.08}],
	&"hide": ["figure.gdshader", {"rough": 0.62, "grain": 0.2, "grain_size": 40.0}],
	&"oxhide": ["figure.gdshader", {"rough": 0.7, "grain": 0.14, "grain_size": 30.0, "dapple": 1.0}],
	&"ivory": ["figure.gdshader", {"rough": 0.4, "grain": 0.08, "grain_size": 50.0}],
	&"bronze": ["metal.gdshader", {}],
	&"bronze_dull": ["metal.gdshader", {"base_color": Color(0.58, 0.41, 0.22), "rough": 0.5, "tarnish": 0.55}],
	&"bronze_scale": ["metal.gdshader", {"base_color": Color(0.7, 0.48, 0.25), "rough": 0.38, "scales": 34.0, "hammer": 0.4}],
	&"gold": ["metal.gdshader", {"base_color": Color(1.0, 0.78, 0.32), "rough": 0.24, "tarnish": 0.05, "hammer": 0.6}],
	&"silver": ["metal.gdshader", {"base_color": Color(0.85, 0.85, 0.82), "rough": 0.3, "tarnish": 0.35, "hammer": 0.5}],
}

static var _lib: Dictionary = {}
static var _local: Dictionary = {}
static var _sooty: Array[ShaderMaterial] = []
static var _detail: float = 1.0


static func _shader(file: String, params: Dictionary = {}) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load(_SHADER_DIR + file)
	for k: String in params:
		m.set_shader_parameter(k, params[k])
	return m


## The same material drawn from both sides: cloaks, veils, awning cloth.
static func _two_sided(m: ShaderMaterial) -> ShaderMaterial:
	var copy := m.duplicate() as ShaderMaterial
	var sh := Shader.new()
	sh.code = m.shader.code.replace("shader_type spatial;", "shader_type spatial;\nrender_mode cull_disabled;") \
		.replace("\tRIM_TINT = 0.6;", "\tRIM_TINT = 0.6;\n\tif (!FRONT_FACING) {\n\t\tNORMAL = -NORMAL;\n\t}")
	copy.shader = sh
	return copy


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

	for key: StringName in FIGURE:
		var spec: Array = FIGURE[key]
		_lib[key] = _shader(spec[0], spec[1])
	_lib[&"wool_2s"] = _two_sided(_lib[&"wool"])
	_lib[&"figure_2s"] = _two_sided(_lib[&"figure"])
	_lib[&"tint_2s"] = _two_sided(_lib[&"tint"])
	_lib[&"dark"] = _std(Color(0.015, 0.012, 0.01), 0.0, 1.0)
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
				copy.set_shader_parameter("detail_scale", _detail)
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


## Sets shader detail for every procedural material: 1 full, 0 the phone
## tier (no bump pass, fewer noise octaves).
static func set_detail(scale: float) -> void:
	_detail = scale
	if _lib.is_empty():
		_build()
	for table: Dictionary in [_lib, _local]:
		for key: StringName in table:
			var sm := table[key] as ShaderMaterial
			if sm != null:
				sm.set_shader_parameter("detail_scale", scale)


## Drops cached materials so a new session starts clean.
static func reset() -> void:
	_lib.clear()
	_local.clear()
	_sooty.clear()
