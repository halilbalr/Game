class_name Viewmodel
extends Node3D
## What the player sees of himself: the weapon arm and the shield arm,
## animated in camera space, or, while he is doing something (see [method
## act]), both hands at it: on the tiller, bound at his sides, holding the
## stake in the fire, raising the wine bowl.

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
## 0 to 1: how far the weapon arm is drawn back for a heavy blow.
var charge: float = 0.0
var _charge_k: float = 0.0
var _bash: float = 0.0

## What the hands are doing (see [method act]); empty for the weapon and shield.
var action: StringName = &""
## 0 to 1: how far along a held action is (the hold to use).
var progress: float = 0.0
## The strength of the action: -1 to 1 on the tiller (the turn), 0 to 1
## against the ropes (the strain).
var drive: float = 0.0
var _anchor: Node3D
var _act_root: Node3D
var _hand_l: MeshInstance3D
var _hand_r: MeshInstance3D
var _props: Dictionary = {}
var _act_t: float = 0.0
var _act_k: float = 0.0


## The view-model material set, keyed like [Mats]: the figure materials,
## each with its depth pulled toward the camera so a long spear never pokes
## through a wall or a man standing close.
static func materials() -> Dictionary:
	if _mats.is_empty():
		for key: StringName in Mats.FIGURE:
			var spec: Array = Mats.FIGURE[key]
			var src := load("res://assets/shaders/" + str(spec[0])) as Shader
			var sh := Shader.new()
			var pull := "\tPOSITION = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0);\n\tPOSITION.z = mix(POSITION.z, POSITION.w, 0.86);\n"
			sh.code = src.code.replace("shader_type spatial;", "shader_type spatial;\nrender_mode cull_disabled;") \
				.replace("\tlp = VERTEX;\n", "\tlp = VERTEX;\n" + pull)
			var m := ShaderMaterial.new()
			m.shader = sh
			for k: String in spec[1]:
				m.set_shader_parameter(k, (spec[1] as Dictionary)[k])
			_mats[key] = m
		_mats[&"tint_2s"] = _mats[&"tint"]
		_mats[&"figure_2s"] = _mats[&"figure"]
		_mats[&"wool_2s"] = _mats[&"wool"]
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
	_act_root = Node3D.new()
	_act_root.visible = false
	add_child(_act_root)
	_hand_l = _forearm(look, mats)
	_hand_r = _forearm(look, mats)
	_act_root.add_child(_hand_l)
	_act_root.add_child(_hand_r)


## Puts the hands to [param kind] ("" to take up weapon and shield again):
## &"helm" (on the tiller at [param anchor], a node with children "GripL"
## and "GripR"), &"bound", &"wax", &"chop", &"fire", &"bowl", &"stake", &"cling".
func act(kind: StringName, anchor: Node3D = null) -> void:
	if kind == action and anchor == _anchor:
		return
	if kind != action:
		_act_t = 0.0
	action = kind
	_anchor = anchor
	for k: StringName in _props:
		(_props[k] as Node3D).visible = false
	if kind in [&"fire", &"stake"]:
		_prop(&"stake").visible = true
	elif kind in [&"bowl", &"wax", &"bound", &"cling"]:
		_prop(kind).visible = true


func _prop(kind: StringName) -> Node3D:
	if _props.has(kind):
		return _props[kind]
	var mats := materials()
	var gb := GeoBuilder.new()
	gb.chunk_size = 0.0
	var node := Node3D.new()
	match kind:
		&"stake":
			# A fathom of green olive wood, sharpened and charred.
			var along := Basis(Vector3.RIGHT, -PI * 0.5)
			var char_ := func(_u: float, v: float) -> Color:
				return Color(0.42, 0.34, 0.2).lerp(Color(0.08, 0.06, 0.05), smoothstep(0.7, 0.9, v))
			Sculpt.lathe(gb, &"hide", Transform3D(along, Vector3.ZERO), PackedVector2Array([Vector2(0.0, -0.36),
				Vector2(0.045, -0.34), Vector2(0.05, 0.6), Vector2(0.04, 1.1), Vector2(0.0, 1.32)]), 9, char_, 1.0, 3)
			var tip := MeshInstance3D.new()
			var tgb := GeoBuilder.new()
			tgb.chunk_size = 0.0
			Sculpt.lathe(tgb, &"ember", Transform3D(along, Vector3.ZERO), PackedVector2Array([Vector2(0.03, 1.2),
				Vector2(0.012, 1.3), Vector2(0.0, 1.33)]), 8, Color.WHITE, 1.0, 2)
			tip.mesh = tgb.build_mesh({&"ember": Mats.get_mat(&"ember")})
			tip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			node.add_child(tip)
		&"bowl":
			# The ivy-wood bowl, brimming with dark wine.
			Sculpt.lathe_hard(gb, &"hide", Transform3D.IDENTITY, PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.06, 0.0),
				Vector2(0.11, 0.035), Vector2(0.135, 0.08), Vector2(0.128, 0.082), Vector2(0.1, 0.04), Vector2(0.0, 0.03)]), 18,
				Color(0.46, 0.33, 0.18))
			Sculpt.lathe_hard(gb, &"tint", Transform3D.IDENTITY, PackedVector2Array([Vector2(0.0, 0.07), Vector2(0.124, 0.07)]), 18,
				Color(0.18, 0.02, 0.04))
		&"wax":
			# A cake of honey-sweet wax, softened in the hands.
			var cake := func(u: float, v: float) -> Vector3:
				var th := PI * v
				var lump := 1.0 + 0.15 * sin(u * TAU * 3.0) * sin(th * 2.0)
				return Vector3(sin(th) * cos(u * TAU) * 0.05, -cos(th) * 0.035, sin(th) * sin(u * TAU) * 0.045) * lump
			Sculpt.grid(gb, &"tint", 10, 6, cake, Color(0.86, 0.72, 0.38), true)
		&"bound":
			# Turns of rope about each wrist.
			for side: float in [-1.0, 1.0]:
				for t in 3:
					var c := Vector3(side * 0.31, -0.375 + t * 0.028, -0.4)
					var turn := func(u: float, v: float) -> Vector3:
						var ring := Vector3(cos(u * TAU) * 0.055, 0.0, sin(u * TAU) * 0.055)
						var tube := Vector3(cos(u * TAU), 0.0, sin(u * TAU)) * cos(v * TAU) * 0.01 + Vector3(0, sin(v * TAU) * 0.01, 0)
						return c + ring + tube
					Sculpt.grid(gb, &"hide", 10, 5, turn, Color(0.62, 0.52, 0.34), true, c)
		&"cling":
			# The ram's fleece close overhead.
			var belly := func(u: float, v: float) -> Vector3:
				var x := lerpf(-0.9, 0.9, u)
				var z := lerpf(0.2, -1.2, v)
				return Vector3(x, 0.34 + 0.08 * Sculpt.noise(floorf(u * 9.0), floorf(v * 5.0)) - 0.12 * (1.0 - absf(x)), z)
			var fleece := func(u: float, v: float) -> Color:
				return Color(0.78, 0.74, 0.64).darkened(0.2 * Sculpt.noise(floorf(u * 14.0), floorf(v * 7.0)))
			Sculpt.grid(gb, &"wool", 18, 8, belly, fleece, false, Vector3(0, 1, 0))
	var mi := MeshInstance3D.new()
	mi.mesh = gb.build_mesh(mats)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.add_child(mi)
	node.visible = false
	_act_root.add_child(node)
	_props[kind] = node
	return node


## Lays a forearm from [param hand] (the grip) back toward [param elbow], in camera space.
func _aim(arm: Node3D, hand: Vector3, elbow: Vector3, roll: float = 0.0) -> void:
	var y := (elbow - hand).normalized()
	var x := Vector3.RIGHT.slide(y).normalized()
	var b := Basis(x, y, x.cross(y)) * Basis(Vector3.UP, roll)
	arm.transform = Transform3D(b, hand + b * Vector3(0, 0.3, 0.01))


## Poses the hands and props for the current action.
func _act_pose(delta: float) -> void:
	_act_t += delta
	var t := _act_t
	var hl := Vector3(-0.12, -0.3, -0.42)
	var hr := Vector3(0.12, -0.3, -0.42)
	var el := Vector3(-0.3, -0.62, 0.05)
	var er := Vector3(0.3, -0.62, 0.05)
	var roll_l := 0.0
	var roll_r := 0.0
	var shown := true
	match action:
		&"helm":
			# Both hands on the tiller bar, wherever it is in view.
			shown = _anchor != null and _anchor.is_inside_tree()
			if shown:
				hl = to_local((_anchor.get_node("GripL") as Node3D).global_position)
				hr = to_local((_anchor.get_node("GripR") as Node3D).global_position)
				shown = hl.z < -0.05 and hl.length() < 1.5 and hr.length() < 1.5
			roll_l = 1.2
			roll_r = -1.2
		&"bound":
			# Lashed at his sides; against the song he strains at the ropes.
			var pull := drive * (0.06 + 0.03 * sin(t * 23.0))
			hl = Vector3(-0.31, -0.35 + pull, -0.4 - pull * 0.5)
			hr = Vector3(0.31, -0.35 + pull * 0.9, -0.4 - pull * 0.4)
			el = Vector3(-0.36, -0.62, 0.05)
			er = Vector3(0.36, -0.62, 0.05)
			(_props[&"bound"] as Node3D).position = Vector3(0, pull, -pull * 0.45)
		&"wax":
			# Kneading the wax warm in the sun.
			var k := sin(t * 5.0) * 0.025
			hl = Vector3(-0.07 + k, -0.3, -0.38)
			hr = Vector3(0.07 + k, -0.3 - k, -0.38)
			var wax: Node3D = _props[&"wax"]
			wax.position = Vector3(k, -0.31, -0.39)
			wax.rotation = Vector3(0.3, t * 1.4, 0.2 * sin(t * 5.0))
			roll_l = 1.4
			roll_r = -1.4
		&"fire":
			# The point held down in the embers, turned and turned.
			var stake: Node3D = _props[&"stake"]
			stake.position = Vector3(0.17, -0.33, -0.6)
			stake.rotation = Vector3(-0.3, -0.04, t * 2.2)
			hl = stake.position + stake.basis * Vector3(0, 0, -0.02)
			hr = stake.position + stake.basis * Vector3(0, 0, 0.26)
		&"stake":
			# Driven in with the whole weight, and twisted like a shipwright's drill.
			var stake: Node3D = _props[&"stake"]
			var push := sin(minf(progress, 1.0) * PI * 0.5) * 0.28
			stake.position = Vector3(0.17, -0.24, -0.62 - push)
			stake.rotation = Vector3(0.04, -0.04, t * 6.0)
			hl = stake.position + stake.basis * Vector3(0, 0, 0.0)
			hr = stake.position + stake.basis * Vector3(0, 0, 0.27)
		&"bowl":
			# The bowl lifted up to the giant's mouth.
			var lift := minf(t / 0.8, 1.0)
			var bowl: Node3D = _props[&"bowl"]
			bowl.position = Vector3(0.0, -0.3 + 0.32 * lift, -0.5 - 0.1 * lift)
			bowl.rotation = Vector3(0.25 * lift, 0.0, 0.0)
			hl = bowl.position + Vector3(-0.12, 0.0, 0.01)
			hr = bowl.position + Vector3(0.12, 0.0, 0.01)
			el = Vector3(-0.28, -0.5 + 0.2 * lift, -0.1)
			er = Vector3(0.28, -0.5 + 0.2 * lift, -0.1)
			roll_l = 0.8
			roll_r = -0.8
		&"cling":
			# Fists in the fleece of the ram's belly.
			var sway := sin(t * 3.0) * 0.02
			hl = Vector3(-0.17, 0.3 + sway, -0.45)
			hr = Vector3(0.17, 0.3 - sway, -0.5)
			el = Vector3(-0.3, -0.05, 0.05)
			er = Vector3(0.3, -0.05, 0.05)
	_hand_l.visible = shown
	_hand_r.visible = shown
	_aim(_hand_l, hl, el, roll_l)
	_aim(_hand_r, hr, er, roll_r)

func _forearm(look: Dictionary, mats: Dictionary) -> MeshInstance3D:
	var gb := GeoBuilder.new()
	gb.chunk_size = 0.0
	FigureMesh.forearm(gb, look)
	# The arm runs on up out of sight.
	var skin: Color = look.get("skin", Color(0.7, 0.5, 0.36))
	Sculpt.loft(gb, &"skin", Transform3D.IDENTITY, [[0.0, 0.046, 0.046, 0.047, 0, 0, 2], [0.2, 0.056, 0.056, 0.056, 0, 0, 2],
		[0.5, 0.058, 0.058, 0.058, 0, 0, 2]], 10, skin, 1)
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


## Punches the shield forward.
func bash() -> void:
	_bash = 1.0


## Kicks the view model back when the player is struck.
func flinch() -> void:
	_flinch = 1.0


func _ease(t: float) -> float:
	t = clampf(t, 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


## Advances the animation. [param move_speed] in m/s, [param look_delta] in radians this frame.
func update(delta: float, move_speed: float, look_delta: Vector2, crouched: bool) -> void:
	# Doing something with both hands: the weapon and shield are put by.
	var acting := action != &"" and action != &"chop"
	_act_root.visible = acting
	_right.visible = not acting
	if _has_shield:
		_left.visible = action == &""
	if acting:
		_act_pose(delta)
		return
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
	_charge_k = lerpf(_charge_k, charge, 1.0 - exp(-14.0 * delta))
	pos += Vector3(0.06, 0.05, 0.2) * _charge_k
	rot += Vector3(0.12, 0.0, -0.12) * _charge_k
	_bash = maxf(_bash - delta * 3.5, 0.0)
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
	if action == &"chop":
		# Hacking a fathom's length from the club: the blade raised and brought down, again and again.
		_act_t += delta
		var k := 0.5 - 0.5 * cos(_act_t * 7.0)
		pos = Vector3(0.22, -0.12, -0.5).lerp(Vector3(0.12, -0.42, -0.62), k)
		rot = Vector3(1.6, 0.2, -0.3).lerp(Vector3(-0.4, 0.3, -0.1), k)
	_right.position = pos + bob + Vector3(_sway.x, _sway.y - _flinch * 0.05, _flinch * 0.06)
	_right.rotation = rot + Vector3(_sway.y * 0.6, _sway.x * 0.8, 0.0)

	_block_k = lerpf(_block_k, 1.0 if blocking else 0.0, 1.0 - exp(-16.0 * delta))
	if _has_shield:
		# At rest only the rim shows at the lower left; raised, the player looks over its top edge.
		var r := _shield_radius
		var lp := Vector3(-0.22 - r * 0.8, -0.2 - r * 0.98, -0.52).lerp(Vector3(-0.2, -0.13 - r, -0.56), _block_k)
		var lr := Vector3(0.1, -0.5, 0.2).lerp(Vector3(0.06, -0.1, 0.04), _block_k)
		var punch := sin(_bash * PI) * 0.34
		_left.position = lp + bob * 0.8 + Vector3(_sway.x + punch * 0.25, _sway.y + _flinch * 0.03 + punch * 0.3,
			_flinch * 0.08 * _block_k - punch)
		_left.rotation = lr


## True when the hero carries a shield.
func has_shield() -> bool:
	return _has_shield


## True while an attack animation is playing.
func is_busy() -> bool:
	return _attack_t >= 0.0
