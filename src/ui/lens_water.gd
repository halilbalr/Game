class_name LensWater
extends CanvasLayer
## Sea water on the eye: drops that land on the view when spray comes over
## the bow, a boulder lands close or the whirlpool churns, each bending the
## picture behind it like a lens, sliding down and drying off. A heavy
## splash runs a sheet of water across the whole view first.
##
## [codeblock]
## lens.splash(0.4)   # a few drops
## lens.splash(1.0)   # drenched
## [/codeblock]

const MAX_DROPS := 24

var _rect: ColorRect
var _mat: ShaderMaterial
var _drops: Array[Dictionary] = []
var _sheet: float = 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	# Under the HUD and its text, over the world.
	layer = 5
	_rect = ColorRect.new()
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mat = ShaderMaterial.new()
	_mat.shader = load("res://assets/shaders/lens_water.gdshader")
	_rect.material = _mat
	_rect.visible = false
	add_child(_rect)
	_rng.randomize()


## Throws water on the lens: [param strength] 0..1, from a few drops to a
## sheet of it.
func splash(strength: float) -> void:
	strength = clampf(strength, 0.0, 1.0)
	var count := int(round(2.0 + strength * 16.0))
	for i in count:
		if _drops.size() >= MAX_DROPS:
			_drops.pop_front()
		_drops.append({
			"pos": Vector2(_rng.randf_range(0.04, 0.96), _rng.randf_range(0.05, 0.9)),
			"r": _rng.randf_range(0.012, 0.03) * (1.0 + strength * 0.8),
			"life": _rng.randf_range(0.8, 1.0),
			"dry": _rng.randf_range(0.25, 0.5),
			"slide": _rng.randf_range(0.0, 0.05) * (1.0 if _rng.randf() < 0.5 else 0.2),
		})
	if strength > 0.6:
		_sheet = maxf(_sheet, strength)


func _process(delta: float) -> void:
	_sheet = maxf(_sheet - delta * 1.6, 0.0)
	var packed := PackedVector4Array()
	var i := 0
	while i < _drops.size():
		var d: Dictionary = _drops[i]
		d["life"] = float(d["life"]) - delta * float(d["dry"])
		# The heavier drops run down the lens.
		d["pos"] = (d["pos"] as Vector2) + Vector2(0.0, float(d["slide"]) * delta)
		if float(d["life"]) <= 0.0:
			_drops.remove_at(i)
			continue
		var p: Vector2 = d["pos"]
		packed.append(Vector4(p.x, p.y, float(d["r"]), float(d["life"])))
		i += 1
	_rect.visible = not packed.is_empty() or _sheet > 0.0
	if not _rect.visible:
		return
	while packed.size() < MAX_DROPS:
		packed.append(Vector4.ZERO)
	_mat.set_shader_parameter("drops", packed)
	_mat.set_shader_parameter("sheet", _sheet)
	var size := _rect.get_viewport_rect().size
	_mat.set_shader_parameter("aspect", size.x / maxf(size.y, 1.0))
