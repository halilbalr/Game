class_name Sea
extends Node3D
## The open sea round a voyage: a field of long waves that follows the eye,
## a flat sea to the horizon beyond it, and the same waves computed here so
## that ships and thrown rocks meet the water where it is drawn.
##
## [codeblock]
## var sea := Sea.new()
## add_child(sea)
## var y := sea.height(ship.global_position.x, ship.global_position.z)
## [/codeblock]

## Keep in step with W0..W3 in assets/shaders/sea.gdshader: direction x, z,
## wavelength (m), amplitude (m).
const WAVES := [
	[1.0, 0.25, 46.0, 0.34], [0.55, 0.85, 23.0, 0.18], [-0.4, 0.92, 11.0, 0.08], [0.9, -0.45, 6.5, 0.04],
]
const NEAR := 360.0
const STEP := 3.0

## Wave height: 1 a fair day, up to 3 in a storm.
var swell: float = 1.0:
	set(v):
		swell = v
		_mat.set_shader_parameter("swell", v)
## Seconds of sea time; drives every wave.
var time: float = 0.0
## Whirlpool: centre (x, z), funnel radius, depth at the eye. Zero radius for none.
var vortex := Vector4.ZERO:
	set(v):
		vortex = v
		_mat.set_shader_parameter("vortex", v)
## A ship whose hull the water is kept out of (see Ship).
var hull: Node3D
var _mat: ShaderMaterial
var _calm: ShaderMaterial
var _near: MeshInstance3D
var _waves: Array = []


func _init() -> void:
	name = "Sea"
	_mat = ShaderMaterial.new()
	_mat.shader = load("res://assets/shaders/sea.gdshader")
	_mat.set_shader_parameter("vortex_spin", 1.0)
	for w: Array in WAVES:
		var d := Vector2(w[0], w[1]).normalized()
		var k := TAU / float(w[2])
		_waves.append([d, k, sqrt(9.8 / k), float(w[3])])
	# A dense grid near the eye, carried along with it.
	var cells := int(NEAR * 2.0 / STEP)
	if Game.lite:
		cells = int(cells * 0.6)
	var plane := PlaneMesh.new()
	plane.size = Vector2(NEAR * 2.0, NEAR * 2.0)
	plane.subdivide_width = cells
	plane.subdivide_depth = cells
	_near = MeshInstance3D.new()
	_near.mesh = plane
	_near.material_override = _mat
	_near.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_near.extra_cull_margin = 8.0
	add_child(_near)
	# Beyond it, a ring of flat sea out to the horizon, just under the near grid's edge.
	var far := MeshInstance3D.new()
	var big := PlaneMesh.new()
	big.size = Vector2(16000.0, 16000.0)
	far.mesh = big
	_calm = _mat.duplicate() as ShaderMaterial
	_calm.set_shader_parameter("swell", 0.0)
	far.material_override = _calm
	far.position.y = -0.35
	far.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(far)


func _process(delta: float) -> void:
	time += delta
	_mat.set_shader_parameter("sea_time", time)
	_mat.set_shader_parameter("detail_scale", Game.detail())
	if hull != null and hull.is_inside_tree():
		var yaw := hull.global_rotation.y
		var xf := Vector4(hull.global_position.x, hull.global_position.z, sin(yaw), cos(yaw))
		# Both the near swell and the flat sea under it, or the one shows where the other is cut away.
		for m: ShaderMaterial in [_mat, _calm]:
			m.set_shader_parameter("hull_xf", xf)
			m.set_shader_parameter("hull_size", Vector2(Ship.BEAM * 0.5, Ship.LENGTH * 0.5))
	var cam := get_viewport().get_camera_3d()
	if cam != null:
		# Snapped to whole cells, so the grid does not swim under the waves.
		var c := cam.global_position
		var span := NEAR * 2.0 / float((_near.mesh as PlaneMesh).subdivide_width + 1)
		_near.global_position = Vector3(snappedf(c.x, span), 0.0, snappedf(c.z, span))


## Tells the water how deep it is: [param tex] holds the sea floor's height
## over [param rect] (x, z of its corner, then width and depth in metres),
## as (height + 12) / 16, so the shallows show turquoise over the sand and
## the surf breaks at the waterline.
func set_floor(tex: Texture2D, rect: Vector4) -> void:
	_mat.set_shader_parameter("ground_tex", tex)
	_mat.set_shader_parameter("ground_rect", rect)


## Height of the water surface at (x, z) now, metres above sea level.
func height(x: float, z: float) -> float:
	var h := 0.0
	var p := Vector2(x, z)
	for w: Array in _waves:
		h += float(w[3]) * swell * sin(float(w[1]) * ((w[0] as Vector2).dot(p) - float(w[2]) * time))
	if vortex.z > 0.0:
		var r := p.distance_to(Vector2(vortex.x, vortex.y)) / vortex.z
		h -= vortex.w / (1.0 + 9.0 * r * r)
	return h
