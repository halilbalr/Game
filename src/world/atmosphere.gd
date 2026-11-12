class_name Atmosphere
extends Node3D
## Sky, sun or moon, fog and post-processing for one hour of the siege.
##
## Presets are art direction rather than gameplay tuning, so they live here.
## Quality level (0 low, 1 medium, 2 high) trims the expensive effects.

const PRESETS := {
	# Clear morning over the Troad: used for walking the city.
	"day": {
		"sun_dir": Vector3(-0.45, 0.72, 0.52), "sun_color": Color(1.0, 0.96, 0.88), "sun_energy": 1.9,
		"zenith": Color(0.13, 0.31, 0.62), "horizon": Color(0.66, 0.78, 0.90), "ground": Color(0.36, 0.32, 0.25),
		"ambient": 0.9, "stars": 0.0, "clouds": 0.42, "sun_glow": 0.5, "moon": false,
		"fog_color": Color(0.70, 0.78, 0.88), "fog_density": 0.0006, "vol_density": 0.004,
		"exposure": 1.0, "disk": 14.0, "sky_exposure": 1.0,
	},
	# The long gold light of late afternoon: Hector at the Scaean Gate.
	"evening": {
		"sun_dir": Vector3(-0.80, 0.33, 0.30), "sun_color": Color(1.0, 0.82, 0.60), "sun_energy": 2.2,
		"zenith": Color(0.17, 0.30, 0.56), "horizon": Color(0.93, 0.74, 0.52), "ground": Color(0.30, 0.26, 0.21),
		"ambient": 0.85, "stars": 0.0, "clouds": 0.45, "sun_glow": 0.9, "moon": false,
		"fog_color": Color(0.80, 0.72, 0.62), "fog_density": 0.0008, "vol_density": 0.005,
		"exposure": 1.0, "disk": 16.0, "sky_exposure": 1.0,
	},
	# Moonlit night of the horse.
	"night": {
		"sun_dir": Vector3(0.42, 0.62, -0.50), "sun_color": Color(0.58, 0.70, 1.0), "sun_energy": 0.62,
		"ambient_color": Color(0.10, 0.135, 0.21),
		"zenith": Color(0.006, 0.010, 0.028), "horizon": Color(0.030, 0.045, 0.085), "ground": Color(0.012, 0.014, 0.02),
		"ambient": 1.0, "stars": 1.4, "clouds": 0.22, "sun_glow": 0.25, "moon": true,
		"fog_color": Color(0.05, 0.07, 0.12), "fog_density": 0.0016, "vol_density": 0.012,
		"exposure": 1.25, "disk": 2.2, "sky_exposure": 1.0,
	},
}

var sun: DirectionalLight3D
var env: Environment
var sky_material: ShaderMaterial
var _world_env: WorldEnvironment
var _preset: Dictionary = {}
var _fire: float = 0.0
var _mobile: bool = false
var _sky_frozen: bool = false
var _compat: bool = false


func _init() -> void:
	name = "Atmosphere"
	sky_material = ShaderMaterial.new()
	sky_material.shader = load("res://assets/shaders/sky.gdshader")
	var sky := Sky.new()
	sky.sky_material = sky_material
	sky.radiance_size = Sky.RADIANCE_SIZE_128
	sky.process_mode = Sky.PROCESS_MODE_INCREMENTAL
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_white = 6.0
	_world_env = WorldEnvironment.new()
	_world_env.environment = env
	add_child(_world_env)
	sun = DirectionalLight3D.new()
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_max_distance = 260.0
	sun.directional_shadow_blend_splits = true
	sun.shadow_bias = 0.04
	sun.shadow_normal_bias = 1.6
	sun.light_angular_distance = 0.6
	add_child(sun)


## Applies the named preset and the given quality level. [param mobile]
## selects the phone tier: no screen-space or volumetric effects, a short
## two-split sun shadow and a sky that is drawn once instead of every frame.
func apply(preset_name: String, quality: int = 1, mobile: bool = false) -> void:
	_mobile = mobile
	if mobile and not _sky_frozen:
		_sky_frozen = true
		var frozen := Shader.new()
		frozen.code = sky_material.shader.code.replace("TIME", "frozen_time") \
			.replace("shader_type sky;", "shader_type sky;\nuniform float frozen_time = 0.0;")
		sky_material.shader = frozen
		env.sky.radiance_size = Sky.RADIANCE_SIZE_64
		env.sky.process_mode = Sky.PROCESS_MODE_QUALITY
	_preset = PRESETS.get(preset_name, PRESETS["day"])
	var p := _preset
	var dir: Vector3 = (p["sun_dir"] as Vector3).normalized()
	sun.look_at_from_position(dir * 100.0, Vector3.ZERO, Vector3.UP)
	sun.light_color = p["sun_color"]
	sun.light_energy = p["sun_energy"]
	sky_material.set_shader_parameter("zenith_color", p["zenith"])
	sky_material.set_shader_parameter("horizon_color", p["horizon"])
	sky_material.set_shader_parameter("ground_color", p["ground"])
	sky_material.set_shader_parameter("sun_color", p["sun_color"])
	sky_material.set_shader_parameter("star_intensity", p["stars"])
	sky_material.set_shader_parameter("cloud_cover", p["clouds"])
	sky_material.set_shader_parameter("sun_glow", p["sun_glow"])
	sky_material.set_shader_parameter("moon", p["moon"])
	sky_material.set_shader_parameter("sun_disk_energy", p["disk"])
	sky_material.set_shader_parameter("sun_size", 0.03 if p["moon"] else 0.022)
	sky_material.set_shader_parameter("exposure", p["sky_exposure"])
	var night: bool = p["moon"]
	sky_material.set_shader_parameter("cloud_color", Color(0.16, 0.19, 0.27) if night else Color(1.0, 0.97, 0.93))
	sky_material.set_shader_parameter("cloud_shadow", Color(0.03, 0.04, 0.07) if night else Color(0.52, 0.57, 0.68))
	if p.has("ambient_color"):
		# Moonless shadow would be black; a flat cool fill keeps the night readable.
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_color = p["ambient_color"]
	else:
		env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_sky_contribution = 1.0
	env.ambient_light_energy = p["ambient"]
	# The OpenGL renderer used in browsers shows the same scene brighter and
	# hazier than the Vulkan ones: pull exposure and fog back to match.
	_compat = RenderingServer.get_current_rendering_method() == "gl_compatibility"
	# It also has no AgX curve; Filmic is the nearest it offers.
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC if _compat else Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = (p["exposure"] as float) * (0.8 if _compat else 1.0)
	env.fog_enabled = true
	env.fog_light_color = p["fog_color"]
	env.fog_density = (p["fog_density"] as float) * (0.55 if _compat else 1.0)
	env.fog_sun_scatter = 0.25
	env.fog_aerial_perspective = 0.6
	env.fog_sky_affect = 0.0
	env.fog_height = TroyLayout.PLAIN_Y
	env.fog_height_density = 0.02
	_apply_quality(quality)
	set_fire(_fire)


func _apply_quality(quality: int) -> void:
	var p := _preset
	env.ssao_enabled = quality >= 1 and not _mobile
	env.ssao_radius = 1.6
	env.ssao_intensity = 2.2
	env.ssao_power = 1.6
	env.ssil_enabled = quality >= 2 and not _mobile
	env.sdfgi_enabled = quality >= 2 and not _mobile
	env.sdfgi_cascades = 4
	env.sdfgi_max_distance = 320.0
	env.sdfgi_use_occlusion = true
	env.glow_enabled = true
	env.glow_intensity = 0.55
	env.glow_bloom = 0.04
	env.glow_hdr_threshold = 1.1
	env.volumetric_fog_enabled = quality >= 1 and not _mobile
	env.volumetric_fog_density = p.get("vol_density", 0.005)
	env.volumetric_fog_albedo = Color(0.9, 0.88, 0.84)
	env.volumetric_fog_length = 140.0
	env.volumetric_fog_anisotropy = 0.55
	env.volumetric_fog_ambient_inject = 0.4
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.06
	env.adjustment_saturation = 1.05
	sun.directional_shadow_max_distance = [120.0, 220.0, 320.0][clampi(quality, 0, 2)]
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS if quality == 0 \
		else DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	if _mobile:
		env.ssao_enabled = false
		env.ssil_enabled = false
		env.sdfgi_enabled = false
		env.volumetric_fog_enabled = false
		env.glow_enabled = false
		env.adjustment_enabled = false
		sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
		sun.directional_shadow_max_distance = 70.0
		sun.directional_shadow_blend_splits = false


## Sets how far the city is alight (0 none, 1 the whole town burning). Tints
## the sky, fog and ambient light.
func set_fire(amount: float) -> void:
	_fire = clampf(amount, 0.0, 1.0)
	if _preset.is_empty():
		return
	sky_material.set_shader_parameter("fire_glow", _fire * 1.4)
	var base_fog: Color = _preset["fog_color"]
	env.fog_light_color = base_fog.lerp(Color(0.55, 0.20, 0.07), _fire * 0.8)
	env.fog_density = lerpf(_preset["fog_density"], 0.006, _fire)
	env.volumetric_fog_density = lerpf(_preset.get("vol_density", 0.005), 0.03, _fire)
	if _mobile:
		# No volumetric smoke on a phone: thicken the plain fog a little instead.
		env.fog_density = lerpf(_preset["fog_density"], 0.011, _fire)
	env.volumetric_fog_albedo = Color(0.9, 0.88, 0.84).lerp(Color(0.75, 0.55, 0.45), _fire)
	env.ambient_light_energy = lerpf(_preset["ambient"], _preset["ambient"] * 1.8, _fire)
