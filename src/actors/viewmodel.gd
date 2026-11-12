class_name Viewmodel
extends Node3D
## What the player sees of himself: the weapon arm and the shield arm,
## animated in camera space.

const REST := {
	"spear": [Vector3(0.27, -0.25, -0.34), Vector3(0.05, 0.07, 0.0)],
	"sword": [Vector3(0.30, -0.33, -0.46), Vector3(0.95, 0.12, -0.12)],
	"dagger": [Vector3(0.26, -0.30, -0.42), Vector3(0.55, 0.1, -0.1)],
}

static var _mats: Dictionary = {}

var weapon_id: String = ""
var blocking: bool = false
## When true the weapon hangs low, out of the way (talk, not war).
var lowered: bool = false
var _right: Node3D
var _left: Node3D
var _weapon: MeshInstance3D
var _arm_r: MeshInstance3D
var _shield: MeshInstance3D
var _attack_kind: StringName = &""
var _attack_t: float = -1.0
var _attack_times := Vector3(0.3, 0.12, 0.5)
var _bob: float = 0.0
var _sway := Vector2.ZERO
var _block_k: float = 0.0
var _has_shield: bool = false
var _hide_weapon_until_recover: bool = false
var _flinch: float = 0.0
var _shield_radius: float = 0.44
var _lower_k: float = 0.0


static func _mat(tint: Color, metal: float, rough: float, vertex_color: bool) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://assets/shaders/viewmodel.gdshader")
	m.set_shader_parameter("tint", tint)
	m.set_shader_parameter("metal", metal)
	m.set_shader_parameter("rough", rough)
	m.set_shader_parameter("use_vertex_color", vertex_color)
	return m


## The view-model material set, keyed like [Mats].
static func materials() -> Dictionary:
	if _mats.is_empty():
		_mats = {
			&"tint": _mat(Color.WHITE, 0.0, 0.8, true),
			&"tint_2s": _mat(Color.WHITE, 0.0, 0.85, true),
			&"hide": _mat(Color.WHITE, 0.0, 0.6, true),
			&"bronze": _mat(Color(0.83, 0.56, 0.27), 1.0, 0.32, false),
			&"bronze_dull": _mat(Color(0.55, 0.40, 0.22), 1.0, 0.55, false),
			&"gold": _mat(Color(1.0, 0.78, 0.32), 1.0, 0.25, false),
			&"silver": _mat(Color(0.85, 0.85, 0.82), 1.0, 0.3, false),
			&"ivory": _mat(Color(0.90, 0.85, 0.72), 0.0, 0.45, false),
		}
	return _mats


## Builds the arms for a hero's outfit.
func setup(look: Dictionary) -> void:
	var mats := materials()
	_right = Node3D.new()
	add_child(_right)
	_weapon = MeshInstance3D.new()
	_weapon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_right.add_child(_weapon)
	_arm_r = _forearm(look, mats)
	_right.add_child(_arm_r)
	_arm_r.rotation = Vector3(PI * 0.5 - 0.42, 0.0, -0.25)
	_arm_r.position = _arm_r.basis * Vector3(0, 0.3, 0.01)
	_left = Node3D.new()
	add_child(_left)
	var shield_kind: String = look.get("shield", "none")
	_has_shield = shield_kind != "none"
	_shield_radius = {"round_great": 0.58, "tower": 0.6, "crescent": 0.37}.get(shield_kind, 0.44)
	if _has_shield:
		_shield = MeshInstance3D.new()
		_shield.mesh = Gear.shield_mesh(shield_kind, look.get("shield_hide", Color(0.4, 0.28, 0.18)), mats, "view")
		_shield.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_left.add_child(_shield)
		var arm_l := _forearm(look, mats)
		_left.add_child(arm_l)
		arm_l.rotation = Vector3(PI * 0.5 - 0.5, 0.0, 0.5)
		arm_l.position = Vector3(0.02, 0.0, 0.07) + arm_l.basis * Vector3(0, 0.3, 0.0)


func _forearm(look: Dictionary, mats: Dictionary) -> MeshInstance3D:
	var gb := GeoBuilder.new()
	gb.chunk_size = 0.0
	var skin: Color = look.get("skin", Color(0.7, 0.5, 0.36))
	var prof := PackedVector2Array([Vector2(0.0, -0.34), Vector2(0.03, -0.32), Vector2(0.036, -0.25), Vector2(0.05, -0.08),
		Vector2(0.056, 0.2), Vector2(0.058, 0.5)])
	gb.lathe(&"tint", Transform3D.IDENTITY, prof, 10, skin)
	gb.box(&"tint", Transform3D(Basis.IDENTITY, Vector3(0, -0.3, -0.012)), Vector3(0.078, 0.085, 0.07), skin, false, 0)
	if look.get("armor", "none") in ["bronze", "bronze_gold"]:
		var guard := PackedVector2Array([Vector2(0.04, -0.23), Vector2(0.056, -0.06), Vector2(0.054, -0.03)])
		gb.lathe(&"bronze", Transform3D.IDENTITY, guard, 10)
	else:
		var wrap := PackedVector2Array([Vector2(0.04, -0.22), Vector2(0.046, -0.15), Vector2(0.044, -0.13)])
		gb.lathe(&"hide", Transform3D.IDENTITY, wrap, 10, Color(0.25, 0.16, 0.1))
	var mi := MeshInstance3D.new()
	mi.mesh = gb.build_mesh(mats)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


## Shows the given weapon in the right hand ("" for an empty hand).
func set_weapon(id: String, long_spear: bool = false) -> void:
	weapon_id = id
	_hide_weapon_until_recover = false
	if id == "":
		_weapon.mesh = null
	else:
		var mesh_id := "spear_long" if (id == "spear" and long_spear) else id
		_weapon.mesh = Gear.weapon_mesh(mesh_id, materials(), "view")
	_weapon.visible = true


## Plays an attack. Kinds: thrust, slash, stab, throw.
func attack(kind: StringName, windup: float, strike: float, recover: float) -> void:
	_attack_kind = kind
	_attack_times = Vector3(windup, strike, recover)
	_attack_t = 0.0
	_hide_weapon_until_recover = false


## Hides the weapon as it leaves the hand in a throw.
func release_weapon() -> void:
	_weapon.visible = false
	_hide_weapon_until_recover = true


## Kicks the view model back when the player is struck.
func flinch() -> void:
	_flinch = 1.0


func _ease(t: float) -> float:
	t = clampf(t, 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


## Advances the animation. [param move_speed] in m/s, [param look_delta] in radians this frame.
func update(delta: float, move_speed: float, look_delta: Vector2, crouched: bool) -> void:
	_bob += delta * (2.0 + move_speed * 1.7)
	var bob_amt := clampf(move_speed / 6.0, 0.0, 1.0)
	var bob := Vector3(sin(_bob) * 0.012, absf(cos(_bob)) * 0.014, 0.0) * bob_amt
	_sway = _sway.lerp(Vector2(clampf(-look_delta.x * 1.4, -0.06, 0.06), clampf(look_delta.y * 1.4, -0.05, 0.05)),
		1.0 - exp(-9.0 * delta))
	_flinch = maxf(_flinch - delta * 4.0, 0.0)
	var rest: Array = REST.get(weapon_id, REST["sword"])
	var pos: Vector3 = rest[0]
	var rot: Vector3 = rest[1]
	if crouched:
		pos += Vector3(-0.02, 0.03, 0.02)
	_lower_k = lerpf(_lower_k, 1.0 if lowered else 0.0, 1.0 - exp(-5.0 * delta))
	pos += Vector3(0.08, -0.22, 0.12) * _lower_k
	rot += Vector3(-0.45, -0.1, 0.0) * _lower_k
	if _attack_t >= 0.0:
		_attack_t += delta
		var tw := _attack_times.x
		var ts := _attack_times.y
		var tr := _attack_times.z
		var wind_pos := pos + Vector3(0.05, 0.0, 0.3)
		var wind_rot := rot
		var hit_pos := pos + Vector3(-0.1, 0.07, -0.72)
		var hit_rot := rot + Vector3(0.0, 0.03, 0.0)
		match _attack_kind:
			&"slash":
				wind_pos = pos + Vector3(0.12, 0.3, 0.06)
				wind_rot = Vector3(1.9, 0.0, -0.5)
				hit_pos = pos + Vector3(-0.36, -0.05, -0.2)
				hit_rot = Vector3(-0.25, 0.75, 0.5)
			&"stab":
				wind_pos = pos + Vector3(0.04, 0.02, 0.2)
				wind_rot = Vector3(0.2, 0.05, 0.0)
				hit_pos = pos + Vector3(-0.12, 0.08, -0.5)
				hit_rot = Vector3(0.05, 0.1, 0.0)
			&"throw":
				wind_pos = pos + Vector3(0.1, 0.36, 0.3)
				wind_rot = Vector3(0.16, 0.0, 0.0)
				hit_pos = pos + Vector3(0.0, 0.3, -0.6)
				hit_rot = Vector3(-0.1, 0.0, 0.0)
		if _attack_t < tw:
			var k := _ease(_attack_t / tw)
			pos = pos.lerp(wind_pos, k)
			rot = rot.lerp(wind_rot, k)
		elif _attack_t < tw + ts:
			var k := (_attack_t - tw) / ts
			pos = wind_pos.lerp(hit_pos, k)
			rot = wind_rot.lerp(hit_rot, k)
		elif _attack_t < tw + ts + tr:
			var k := _ease((_attack_t - tw - ts) / tr)
			pos = hit_pos.lerp(pos, k)
			rot = hit_rot.lerp(rot, k)
			if _hide_weapon_until_recover and k > 0.85:
				_weapon.visible = weapon_id != ""
				_hide_weapon_until_recover = false
		else:
			_attack_t = -1.0
			if _hide_weapon_until_recover:
				_weapon.visible = weapon_id != ""
				_hide_weapon_until_recover = false
	_right.position = pos + bob + Vector3(_sway.x, _sway.y - _flinch * 0.05, _flinch * 0.06)
	_right.rotation = rot + Vector3(_sway.y * 0.6, _sway.x * 0.8, 0.0)

	_block_k = lerpf(_block_k, 1.0 if blocking else 0.0, 1.0 - exp(-16.0 * delta))
	if _has_shield:
		# At rest only the rim shows at the lower left; raised, the player looks over its top edge.
		var r := _shield_radius
		var lp := Vector3(-0.22 - r * 0.8, -0.2 - r * 0.98, -0.52).lerp(Vector3(-0.2, -0.13 - r, -0.56), _block_k)
		var lr := Vector3(0.1, -0.5, 0.2).lerp(Vector3(0.06, -0.1, 0.04), _block_k)
		_left.position = lp + bob * 0.8 + Vector3(_sway.x, _sway.y + _flinch * 0.03, _flinch * 0.08 * _block_k)
		_left.rotation = lr


## True when the hero carries a shield.
func has_shield() -> bool:
	return _has_shield


## True while an attack animation is playing.
func is_busy() -> bool:
	return _attack_t >= 0.0
