class_name Humanoid
extends Node3D
## An articulated figure built and animated in code: warrior, watchman or
## townsperson. Faces local -Z. The owner sets [member speed],
## [member crouching], [member blocking] and [member stance]; attacks and
## death are played with [method attack] and [method die].

const HIP_HEIGHT := 0.92

## Joint angles for one frame.
class Pose:
	var body_y := 0.0
	var body_rot := Vector3.ZERO
	var spine := Vector3.ZERO
	var head := Vector3.ZERO
	var arm_l := Vector3(0.05, 0.0, -0.08)
	var fore_l := 0.15
	var arm_r := Vector3(0.05, 0.0, 0.08)
	var fore_r := 0.15
	var thigh_l := Vector3.ZERO
	var shin_l := 0.0
	var thigh_r := Vector3.ZERO
	var shin_r := 0.0
	var weapon_pitch := 0.0
	var weapon_yaw := 0.0
	var shield_pos := Vector3(-0.31, 0.12, -0.36)
	var shield_rot := Vector3(0.0, 0.62, 0.0)

	## Restores the neutral standing pose so one object can be reused every frame.
	func reset() -> void:
		body_y = 0.0
		body_rot = Vector3.ZERO
		spine = Vector3.ZERO
		head = Vector3.ZERO
		arm_l = Vector3(0.05, 0.0, -0.08)
		fore_l = 0.15
		arm_r = Vector3(0.05, 0.0, 0.08)
		fore_r = 0.15
		thigh_l = Vector3.ZERO
		shin_l = 0.0
		thigh_r = Vector3.ZERO
		shin_r = 0.0
		weapon_pitch = 0.0
		weapon_yaw = 0.0
		shield_pos = Vector3(-0.31, 0.12, -0.36)
		shield_rot = Vector3(0.0, 0.62, 0.0)

	func blend(to: Pose, t: float) -> void:
		body_y = lerpf(body_y, to.body_y, t)
		body_rot = body_rot.lerp(to.body_rot, t)
		spine = spine.lerp(to.spine, t)
		head = head.lerp(to.head, t)
		arm_l = arm_l.lerp(to.arm_l, t)
		fore_l = lerpf(fore_l, to.fore_l, t)
		arm_r = arm_r.lerp(to.arm_r, t)
		fore_r = lerpf(fore_r, to.fore_r, t)
		thigh_l = thigh_l.lerp(to.thigh_l, t)
		shin_l = lerpf(shin_l, to.shin_l, t)
		thigh_r = thigh_r.lerp(to.thigh_r, t)
		shin_r = lerpf(shin_r, to.shin_r, t)
		weapon_pitch = lerpf(weapon_pitch, to.weapon_pitch, t)
		weapon_yaw = lerpf(weapon_yaw, to.weapon_yaw, t)
		shield_pos = shield_pos.lerp(to.shield_pos, t)
		shield_rot = shield_rot.lerp(to.shield_rot, t)


static var _mesh_cache: Dictionary = {}
static var _frame: int = 0

## Horizontal speed in m/s, set by the owner; drives the walk cycle.
var speed: float = 0.0
var crouching: bool = false
var blocking: bool = false
## One of: guard, idle, sentry, sit, lie, hide, hold_child, cheer, pray.
var stance: StringName = &"idle"
## Resolved outfit choices for this figure.
var look: Dictionary = {}
var weapon_kind: String = ""

var _body: Node3D
var _spine: Node3D
var _head: Node3D
var _arm_l: Node3D
var _fore_l: Node3D
var _arm_r: Node3D
var _fore_r: Node3D
var _hand_r: Node3D
var _thigh_l: Node3D
var _shin_l: Node3D
var _thigh_r: Node3D
var _shin_r: Node3D
var _shield: Node3D
var _weapon: MeshInstance3D
var _head_mesh: MeshInstance3D
var _cur := Pose.new()
var _scratch := Pose.new()
var _phase: float = 0.0
var _attack_kind: StringName = &""
var _attack_t: float = -1.0
var _attack_times := Vector3(0.3, 0.12, 0.5)
var _flinch: float = 0.0
var _dying: bool = false
var _death_t: float = 0.0
var _death_forward: bool = false
var _death_seed: float = 0.0
var _lod_slot: int = 0


static func _pick(options: Variant, variant: int) -> Variant:
	if options is Array and not (options as Array).is_empty():
		var arr := options as Array
		return arr[posmod(variant, arr.size())]
	return options


static func _color(v: Variant, fallback: Color = Color.WHITE) -> Color:
	if v is Array and (v as Array).size() >= 3:
		var a := v as Array
		return Color(a[0], a[1], a[2])
	return fallback


## Resolves an outfit definition into concrete choices for [param variant].
static func resolve_look(outfit_id: String, outfit: Dictionary, variant: int) -> Dictionary:
	return {
		"id": outfit_id, "variant": variant,
		"skin": _color(_pick(outfit.get("skin", []), variant), Color(0.7, 0.5, 0.36)),
		"hair": _color(_pick(outfit.get("hair", []), variant + 1), Color(0.1, 0.07, 0.05)),
		"tunic": _color(_pick(outfit.get("tunic", []), variant), Color(0.8, 0.74, 0.6)),
		"kilt": _color(_pick(outfit.get("kilt", []), variant + 1), Color(0.5, 0.2, 0.15)),
		"armor": str(_pick(outfit.get("armor", ["none"]), variant)),
		"helmet": str(_pick(outfit.get("helmet", ["none"]), variant)),
		"crest": _color(_pick(outfit.get("crest", []), variant), Color(0.1, 0.08, 0.07)),
		"greaves": bool(_pick(outfit.get("greaves", [false]), variant)),
		"shield": str(_pick(outfit.get("shield", ["none"]), variant)),
		"shield_hide": _color(_pick(outfit.get("shield_hide", []), variant), Color(0.42, 0.28, 0.18)),
		"beard": bool(_pick(outfit.get("beard", [false]), variant)),
		"cloak": _pick(outfit.get("cloak", [null]), variant),
		"robe": bool(outfit.get("robe", false)),
	}


# --- mesh construction -----------------------------------------------------------

static func _limb(gb: GeoBuilder, mat: StringName, col: Color, r_top: float, r_bot: float, length: float,
		squash: float = 1.0, bulge: float = 0.0) -> void:
	var prof := PackedVector2Array()
	prof.append(Vector2(0.0, -length - r_bot * 0.7))
	prof.append(Vector2(r_bot * 0.78, -length - r_bot * 0.3))
	prof.append(Vector2(r_bot, -length))
	if bulge > 0.0:
		prof.append(Vector2(r_bot + bulge * 0.4, -length * 0.62))
		prof.append(Vector2(r_top + bulge, -length * 0.28))
	prof.append(Vector2(r_top, 0.0))
	prof.append(Vector2(r_top * 0.78, r_top * 0.4))
	prof.append(Vector2(0.0, r_top * 0.7))
	gb.lathe(mat, Transform3D.IDENTITY, prof, 10, col, false, squash)


static func _ring(gb: GeoBuilder, mat: StringName, col: Color, y: float, r: float, h: float, squash: float) -> void:
	var prof := PackedVector2Array([Vector2(r - 0.004, y), Vector2(r, y + h * 0.3), Vector2(r, y + h * 0.7), Vector2(r - 0.004, y + h)])
	gb.lathe(mat, Transform3D.IDENTITY, prof, 12, col, false, squash)


static func _build_torso(look: Dictionary) -> ArrayMesh:
	var gb := GeoBuilder.new()
	gb.chunk_size = 0.0
	var tunic: Color = look["tunic"]
	var skin: Color = look["skin"]
	var squash := 0.64
	var body := PackedVector2Array([Vector2(0.0, -0.03), Vector2(0.135, 0.0), Vector2(0.15, 0.12), Vector2(0.176, 0.28),
		Vector2(0.186, 0.4), Vector2(0.13, 0.48), Vector2(0.062, 0.515), Vector2(0.0, 0.52)])
	gb.lathe(&"tint", Transform3D.IDENTITY, body, 12, tunic, false, squash)
	var neck := PackedVector2Array([Vector2(0.056, 0.49), Vector2(0.05, 0.6)])
	gb.lathe(&"tint", Transform3D.IDENTITY, neck, 8, skin, false, 0.95)
	var armor: String = look["armor"]
	var shell := PackedVector2Array([Vector2(0.146, -0.01), Vector2(0.162, 0.12), Vector2(0.188, 0.28),
		Vector2(0.198, 0.4), Vector2(0.14, 0.485), Vector2(0.075, 0.5)])
	match armor:
		"bronze", "bronze_gold":
			gb.lathe(&"bronze", Transform3D.IDENTITY, shell, 12, Color.WHITE, false, squash + 0.03)
			for sx: float in [-1.0, 1.0]:
				var cap := PackedVector2Array([Vector2(0.0, -0.05), Vector2(0.075, -0.03), Vector2(0.085, 0.02), Vector2(0.05, 0.055), Vector2(0.0, 0.065)])
				gb.lathe(&"bronze", Transform3D(Basis.IDENTITY, Vector3(sx * 0.205, 0.43, 0.0)), cap, 8, Color.WHITE, false, 0.9)
			var trim: StringName = &"gold" if armor == "bronze_gold" else &"bronze_dull"
			_ring(gb, trim, Color.WHITE, -0.01, 0.152, 0.035, squash + 0.03)
			_ring(gb, trim, Color.WHITE, 0.26, 0.192, 0.02, squash + 0.03)
			if armor == "bronze_gold":
				# The stars on the breastplate of Achilles (Iliad 16.134).
				for i in 5:
					var a := -0.9 + i * 0.45
					gb.box(&"gold", Transform3D(Basis.IDENTITY, Vector3(sin(a) * 0.15, 0.34 - absf(a) * 0.06, -0.127 * cos(a) - 0.004)),
						Vector3(0.022, 0.022, 0.012), Color.WHITE, false, 0)
		"linen":
			gb.lathe(&"tint", Transform3D.IDENTITY, shell, 12, Color(0.86, 0.82, 0.72), false, squash + 0.02)
			for y: float in [0.06, 0.16, 0.26]:
				_ring(gb, &"tint", Color(0.5, 0.42, 0.32), y, 0.2 if y > 0.2 else 0.178, 0.012, squash + 0.02)
		"leather":
			gb.lathe(&"hide", Transform3D.IDENTITY, shell, 12, Color(0.34, 0.22, 0.14), false, squash + 0.02)
			for i in 6:
				var a := TAU * i / 6.0 + 0.5
				gb.box(&"bronze", Transform3D(Basis(Vector3.UP, -a), Vector3(sin(a) * 0.178, 0.3, cos(a) * 0.178 * (squash + 0.02))),
					Vector3(0.035, 0.035, 0.012), Color.WHITE, false, 0)
			_ring(gb, &"hide", Color(0.2, 0.13, 0.08), 0.0, 0.156, 0.04, squash + 0.03)
		"scale":
			gb.lathe(&"bronze_dull", Transform3D.IDENTITY, shell, 12, Color.WHITE, false, squash + 0.02)
			for i in 6:
				_ring(gb, &"bronze", Color.WHITE, 0.02 + i * 0.07, lerpf(0.154, 0.2, i / 5.0), 0.014, squash + 0.03)
		_:
			# A belt over the plain tunic.
			_ring(gb, &"hide", Color(0.25, 0.16, 0.1), 0.0, 0.14, 0.035, squash + 0.02)
	var cloak: Variant = look["cloak"]
	if cloak is Array:
		var cc := _color(cloak)
		var top_l := Vector3(-0.19, 0.47, 0.085)
		var top_r := Vector3(0.19, 0.47, 0.085)
		var mid_l := Vector3(-0.24, 0.1, 0.16)
		var mid_r := Vector3(0.24, 0.1, 0.16)
		var bot_l := Vector3(-0.27, -0.42, 0.2)
		var bot_r := Vector3(0.27, -0.42, 0.2)
		gb.quad_h(&"tint_2s", mid_l, mid_r, top_r, top_l, Vector3(0, 0, 1), cc.darkened(0.08), false, cc)
		gb.quad_h(&"tint_2s", bot_l, bot_r, mid_r, mid_l, Vector3(0, 0, 1), cc.darkened(0.2), false, cc.darkened(0.08))
		# Folded over the shoulders and pinned at the breast.
		for sx: float in [-1.0, 1.0]:
			gb.quad_h(&"tint_2s", Vector3(sx * 0.19, 0.47, 0.085), Vector3(sx * 0.2, 0.47, -0.06), Vector3(sx * 0.08, 0.5, -0.09),
				Vector3(sx * 0.07, 0.5, 0.08), Vector3(0, 1, 0), cc, false)
		gb.box(&"gold", Transform3D(Basis.IDENTITY, Vector3(0.0, 0.47, -0.1)), Vector3(0.035, 0.035, 0.015), Color.WHITE, false, 0)
	return gb.build_mesh(Mats.all())


static func _build_pelvis(look: Dictionary) -> ArrayMesh:
	var gb := GeoBuilder.new()
	gb.chunk_size = 0.0
	var kilt: Color = look["kilt"]
	if look["robe"]:
		var robe := PackedVector2Array([Vector2(0.0, -0.78), Vector2(0.235, -0.86), Vector2(0.21, -0.45), Vector2(0.17, -0.1),
			Vector2(0.15, 0.05), Vector2(0.0, 0.06)])
		gb.lathe(&"tint", Transform3D.IDENTITY, robe, 12, kilt, false, 0.82)
		_ring(gb, &"tint", kilt.lightened(0.35), -0.85, 0.24, 0.05, 0.82)
		_ring(gb, &"tint", kilt.lightened(0.35), -0.5, 0.217, 0.03, 0.82)
	else:
		var skirt := PackedVector2Array([Vector2(0.0, -0.26), Vector2(0.2, -0.36), Vector2(0.185, -0.16), Vector2(0.152, 0.04),
			Vector2(0.0, 0.06)])
		gb.lathe(&"tint", Transform3D.IDENTITY, skirt, 12, kilt, false, 0.82)
		# Fringed hem, as on the Warrior Vase.
		_ring(gb, &"tint", kilt.lightened(0.4), -0.365, 0.204, 0.035, 0.82)
	return gb.build_mesh(Mats.all())


static func _build_head(look: Dictionary) -> ArrayMesh:
	var gb := GeoBuilder.new()
	gb.chunk_size = 0.0
	var skin: Color = look["skin"]
	var hair: Color = look["hair"]
	var crest: Color = look["crest"]
	var skull := PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.058, 0.012), Vector2(0.084, 0.06), Vector2(0.094, 0.125),
		Vector2(0.09, 0.18), Vector2(0.06, 0.225), Vector2(0.0, 0.24)])
	gb.lathe(&"tint", Transform3D.IDENTITY, skull, 12, skin, false, 1.12)
	var dark := Color(0.06, 0.04, 0.03)
	gb.frustum(&"tint", Transform3D(Basis.IDENTITY, Vector3(0, 0.092, -0.108)), Vector2(0.03, 0.03), Vector2(0.018, 0.02), 0.055, skin.darkened(0.08), false)
	for sx: float in [-1.0, 1.0]:
		gb.box(&"tint", Transform3D(Basis.IDENTITY, Vector3(sx * 0.036, 0.142, -0.097)), Vector3(0.024, 0.012, 0.012), dark, false, 0)
		gb.box(&"tint", Transform3D(Basis.IDENTITY, Vector3(sx * 0.037, 0.158, -0.098)), Vector3(0.036, 0.008, 0.014), hair.darkened(0.2), false, 0)
	gb.box(&"tint", Transform3D(Basis.IDENTITY, Vector3(0, 0.064, -0.094)), Vector3(0.04, 0.007, 0.012), skin.darkened(0.45), false, 0)
	if look["beard"]:
		var beard := PackedVector2Array([Vector2(0.0, -0.045), Vector2(0.05, -0.03), Vector2(0.088, 0.03), Vector2(0.097, 0.085)])
		gb.lathe(&"tint", Transform3D(Basis.IDENTITY, Vector3(0, 0.0, -0.012)), beard, 10, hair, false, 1.05)
	var helmet: String = look["helmet"]
	var covered := helmet in ["boar_tusk", "bronze_crest", "bronze_crest_tall", "bronze_gold", "anatolian", "leather"]
	if not covered:
		var cap := PackedVector2Array([Vector2(0.099, 0.165), Vector2(0.096, 0.19), Vector2(0.066, 0.232), Vector2(0.0, 0.25)])
		gb.lathe(&"tint", Transform3D.IDENTITY, cap, 12, hair, false, 1.12)
	# Long hair down the neck: the "long-haired Achaeans".
	gb.box(&"tint", Transform3D(Basis.IDENTITY, Vector3(0, 0.08, 0.078)), Vector3(0.16, 0.2, 0.06), hair, false, 0)
	var dome := PackedVector2Array([Vector2(0.104, 0.105), Vector2(0.108, 0.15), Vector2(0.096, 0.205), Vector2(0.058, 0.25), Vector2(0.0, 0.266)])
	match helmet:
		"boar_tusk":
			# Rows of split boar tusks sewn to a leather cap (Iliad 10.261-265).
			gb.lathe(&"ivory", Transform3D.IDENTITY, dome, 12, Color.WHITE, false, 1.12)
			for y: float in [0.135, 0.172, 0.208]:
				_ring(gb, &"tint", Color(0.2, 0.13, 0.08), y, 0.112 - (y - 0.135) * 0.2, 0.008, 1.12)
			for sx: float in [-1.0, 1.0]:
				gb.box(&"ivory", Transform3D(Basis.IDENTITY, Vector3(sx * 0.098, 0.05, -0.02)), Vector3(0.016, 0.12, 0.075), Color.WHITE, false, 0)
			gb.cylinder(&"ivory", Vector3(0, 0.262, 0), 0.02, 0.028, 0.035, 8)
		"bronze_crest", "bronze_crest_tall", "bronze_gold":
			gb.lathe(&"bronze", Transform3D.IDENTITY, dome, 12, Color.WHITE, false, 1.12)
			for sx: float in [-1.0, 1.0]:
				gb.box(&"bronze", Transform3D(Basis.IDENTITY, Vector3(sx * 0.098, 0.05, -0.025)), Vector3(0.014, 0.125, 0.08), Color.WHITE, false, 0)
			gb.box(&"bronze", Transform3D(Basis.IDENTITY, Vector3(0, 0.12, -0.112)), Vector3(0.02, 0.075, 0.012), Color.WHITE, false, 0)
			var tall := helmet != "bronze_crest"
			var lift := 0.07 if tall else 0.0
			if tall:
				gb.cylinder(&"gold" if helmet == "bronze_gold" else &"bronze", Vector3(0, 0.26, 0), 0.014, 0.014, lift + 0.01, 6)
			# Horsehair crest, front to back, with the tail hanging behind.
			var steps := 7
			for i in steps:
				var a := lerpf(-0.9, 1.5, float(i) / (steps - 1))
				var p := Vector3(0, 0.15 + lift + cos(a) * 0.125, sin(a) * 0.125)
				var basis := Basis(Vector3.RIGHT, a)
				gb.box(&"tint", Transform3D(basis, p + basis * Vector3(0, 0.04, 0)), Vector3(0.028, 0.09 if not tall else 0.12, 0.07),
					crest if i % 2 == 0 else crest.darkened(0.15), false, 0)
			gb.box(&"tint", Transform3D(Basis(Vector3.RIGHT, 0.25), Vector3(0, 0.02 + lift * 0.5, 0.17)), Vector3(0.03, 0.3 + lift, 0.05), crest, false, 0)
			if helmet == "bronze_gold":
				_ring(gb, &"gold", Color.WHITE, 0.112, 0.111, 0.016, 1.12)
				_ring(gb, &"gold", Color.WHITE, 0.2, 0.1, 0.012, 1.12)
		"anatolian":
			# Tall pointed helmet with a plume down the back, as on the
			# warrior of the King's Gate at Hattusa.
			var cone := PackedVector2Array([Vector2(0.104, 0.105), Vector2(0.104, 0.16), Vector2(0.07, 0.25), Vector2(0.03, 0.33), Vector2(0.0, 0.35)])
			gb.lathe(&"bronze_dull", Transform3D.IDENTITY, cone, 12, Color.WHITE, false, 1.12)
			_ring(gb, &"bronze", Color.WHITE, 0.105, 0.108, 0.02, 1.12)
			for sx: float in [-1.0, 1.0]:
				gb.box(&"hide", Transform3D(Basis.IDENTITY, Vector3(sx * 0.098, 0.045, -0.015)), Vector3(0.014, 0.13, 0.085), Color(0.3, 0.2, 0.12), false, 0)
			gb.box(&"tint", Transform3D(Basis(Vector3.RIGHT, 0.5), Vector3(0, 0.26, 0.07)), Vector3(0.025, 0.2, 0.03), crest, false, 0)
			gb.box(&"tint", Transform3D(Basis(Vector3.RIGHT, 0.12), Vector3(0, 0.06, 0.14)), Vector3(0.028, 0.26, 0.035), crest, false, 0)
		"leather":
			gb.lathe(&"hide", Transform3D.IDENTITY, dome, 12, Color(0.32, 0.21, 0.13), false, 1.12)
			_ring(gb, &"bronze_dull", Color.WHITE, 0.105, 0.108, 0.02, 1.12)
			gb.cylinder(&"bronze_dull", Vector3(0, 0.258, 0), 0.03, 0.012, 0.025, 8)
		"veil":
			var hood := PackedVector2Array([Vector2(0.104, 0.15), Vector2(0.1, 0.2), Vector2(0.066, 0.24), Vector2(0.0, 0.256)])
			gb.lathe(&"tint", Transform3D.IDENTITY, hood, 12, crest, false, 1.14)
			gb.quad_h(&"tint_2s", Vector3(-0.15, -0.3, 0.13), Vector3(0.15, -0.3, 0.13), Vector3(0.1, 0.2, 0.1), Vector3(-0.1, 0.2, 0.1),
				Vector3(0, 0, 1), crest.darkened(0.1), false, crest)
			for sx: float in [-1.0, 1.0]:
				gb.quad_h(&"tint_2s", Vector3(sx * 0.15, -0.3, 0.13), Vector3(sx * 0.14, -0.12, -0.02), Vector3(sx * 0.105, 0.17, 0.0),
					Vector3(sx * 0.1, 0.2, 0.1), Vector3(sx, 0, 0), crest.darkened(0.06), false, crest)
		"diadem":
			_ring(gb, &"gold", Color.WHITE, 0.175, 0.101, 0.022, 1.12)
		_:
			_ring(gb, &"tint", Color(0.5, 0.2, 0.14), 0.168, 0.1, 0.014, 1.12)
	return gb.build_mesh(Mats.all())


static func _build_arm(look: Dictionary, upper: bool) -> ArrayMesh:
	var gb := GeoBuilder.new()
	gb.chunk_size = 0.0
	var skin: Color = look["skin"]
	if upper:
		_limb(gb, &"tint", skin, 0.055, 0.046, 0.28)
		var sleeve := PackedVector2Array([Vector2(0.052, -0.13 if not look["robe"] else -0.24), Vector2(0.06, -0.04), Vector2(0.058, 0.02), Vector2(0.0, 0.05)])
		gb.lathe(&"tint", Transform3D.IDENTITY, sleeve, 10, look["tunic"])
	else:
		_limb(gb, &"tint", skin, 0.045, 0.035, 0.25)
		gb.box(&"tint", Transform3D(Basis.IDENTITY, Vector3(0, -0.295, -0.005)), Vector3(0.07, 0.09, 0.045), skin, false, 0)
		if look["armor"] in ["bronze", "bronze_gold"]:
			var guard := PackedVector2Array([Vector2(0.037, -0.22), Vector2(0.044, -0.06), Vector2(0.042, -0.04)])
			gb.lathe(&"bronze", Transform3D.IDENTITY, guard, 10)
	return gb.build_mesh(Mats.all())


static func _build_leg(look: Dictionary, upper: bool) -> ArrayMesh:
	var gb := GeoBuilder.new()
	gb.chunk_size = 0.0
	var skin: Color = look["skin"]
	if upper:
		_limb(gb, &"tint", skin, 0.086, 0.062, 0.44)
	else:
		_limb(gb, &"tint", skin, 0.056, 0.04, 0.42, 1.0, 0.014)
		var sole := Color(0.22, 0.14, 0.09)
		gb.box(&"tint", Transform3D(Basis.IDENTITY, Vector3(0, -0.455, -0.055)), Vector3(0.085, 0.05, 0.235), skin.darkened(0.05), false, 0)
		gb.box(&"tint", Transform3D(Basis.IDENTITY, Vector3(0, -0.482, -0.055)), Vector3(0.095, 0.02, 0.25), sole, false, 0)
		if look["greaves"]:
			# Bronze greaves: the "well-greaved Achaeans".
			var greave := PackedVector2Array([Vector2(0.044, -0.41), Vector2(0.058, -0.3), Vector2(0.07, -0.13), Vector2(0.062, -0.02), Vector2(0.05, 0.0)])
			gb.lathe(&"bronze", Transform3D.IDENTITY, greave, 10)
		else:
			for y: float in [-0.4, -0.33]:
				_ring(gb, &"tint", sole, y, 0.046, 0.012, 1.0)
	return gb.build_mesh(Mats.all())


static func _cached(look: Dictionary, part: String, builder: Callable) -> ArrayMesh:
	var key := "%s:%d:%s:%s" % [look["id"], look["variant"], part, look["helmet"]]
	if not _mesh_cache.has(key):
		_mesh_cache[key] = builder.call()
	return _mesh_cache[key]


static func _part(parent: Node3D, mesh: Mesh, pos: Vector3, shadow: bool = true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadow \
		else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if not shadow and Game.mobile:
		# Forearms and shins are not worth a draw call across the field.
		mi.visibility_range_end = 60.0
	parent.add_child(mi)
	return mi


static func _joint(parent: Node3D, pos: Vector3) -> Node3D:
	var n := Node3D.new()
	n.position = pos
	parent.add_child(n)
	return n


## Builds the figure for an outfit. [param weapon] is a weapon id or "".
func setup(outfit_id: String, outfit: Dictionary, variant: int, weapon: String = "") -> void:
	look = resolve_look(outfit_id, outfit, variant)
	_lod_slot = variant
	_body = _joint(self, Vector3(0, HIP_HEIGHT, 0))
	_part(_body, _cached(look, "pelvis", _build_pelvis.bind(look)), Vector3.ZERO)
	_spine = _joint(_body, Vector3(0, 0.02, 0))
	_part(_spine, _cached(look, "torso", _build_torso.bind(look)), Vector3.ZERO)
	_head = _joint(_spine, Vector3(0, 0.575, 0))
	_head_mesh = _part(_head, _cached(look, "head", _build_head.bind(look)), Vector3.ZERO)
	_head_mesh.scale = Vector3.ONE * 1.1
	var arm_u := _cached(look, "arm_u", _build_arm.bind(look, true))
	var arm_f := _cached(look, "arm_f", _build_arm.bind(look, false))
	_arm_l = _joint(_spine, Vector3(-0.205, 0.43, 0))
	_part(_arm_l, arm_u, Vector3.ZERO, false)
	_fore_l = _joint(_arm_l, Vector3(0, -0.28, 0))
	_part(_fore_l, arm_f, Vector3.ZERO, false)
	_arm_r = _joint(_spine, Vector3(0.205, 0.43, 0))
	_part(_arm_r, arm_u, Vector3.ZERO, false)
	_fore_r = _joint(_arm_r, Vector3(0, -0.28, 0))
	_part(_fore_r, arm_f, Vector3.ZERO, false)
	_hand_r = _joint(_fore_r, Vector3(0, -0.3, -0.01))
	var leg_u := _cached(look, "leg_u", _build_leg.bind(look, true))
	var leg_l := _cached(look, "leg_l", _build_leg.bind(look, false))
	_thigh_l = _joint(_body, Vector3(-0.088, -0.02, 0))
	_part(_thigh_l, leg_u, Vector3.ZERO)
	_shin_l = _joint(_thigh_l, Vector3(0, -0.44, 0))
	_part(_shin_l, leg_l, Vector3.ZERO, false)
	_thigh_r = _joint(_body, Vector3(0.088, -0.02, 0))
	_part(_thigh_r, leg_u, Vector3.ZERO)
	_shin_r = _joint(_thigh_r, Vector3(0, -0.44, 0))
	_part(_shin_r, leg_l, Vector3.ZERO, false)
	_shield = _joint(_spine, _cur.shield_pos)
	var shield_kind: String = look["shield"]
	if shield_kind != "none":
		_part(_shield, Gear.shield_mesh(shield_kind, look["shield_hide"], Mats.all()), Vector3.ZERO)
	_weapon = MeshInstance3D.new()
	_weapon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_hand_r.add_child(_weapon)
	set_weapon(weapon)
	_phase = variant * 1.37
	_apply(_cur)


## Bares the head (a helmet struck off or laid aside).
func remove_helmet() -> void:
	look["helmet"] = "none"
	_head_mesh.mesh = _cached(look, "head", _build_head.bind(look))


## True when this figure carries a shield.
func has_shield() -> bool:
	return look.get("shield", "none") != "none"


## Changes the weapon in the right hand ("" for empty-handed).
func set_weapon(kind: String) -> void:
	weapon_kind = kind
	if kind == "":
		_weapon.mesh = null
	else:
		var id := kind
		if kind == "spear" and look.get("id", "") == "hector":
			id = "spear_long"
		_weapon.mesh = Gear.weapon_mesh(id, Mats.all())


## World transform of the weapon hand, for spawning thrown spears.
func hand_transform() -> Transform3D:
	return _hand_r.global_transform


## World position of the head centre.
func head_position() -> Vector3:
	return _head.global_position + Vector3(0, 0.12, 0)


# --- animation ---------------------------------------------------------------------

func _stance_pose() -> Pose:
	var p := _scratch
	p.reset()
	match stance:
		&"guard":
			p.arm_r = Vector3(-0.3, 0.0, 0.14)
			p.fore_r = 0.8
			p.arm_l = Vector3(0.2, 0.0, -0.3)
			p.fore_l = 1.25
			if weapon_kind == "sword" or weapon_kind == "dagger":
				p.arm_r = Vector3(0.25, 0.0, 0.2)
				p.fore_r = 1.1
				p.weapon_pitch = 0.9
		&"sentry":
			p.arm_r = Vector3(0.3, 0.0, 0.22)
			p.fore_r = 0.75
			p.weapon_pitch = PI * 0.5 - 0.04
			p.shield_pos = Vector3(-0.3, 0.1, -0.04)
			p.shield_rot = Vector3(0.0, 1.1, 0.0)
			p.arm_l = Vector3(0.1, 0.0, -0.2)
			p.fore_l = 0.5
		&"sit":
			p.body_y = -0.78
			p.thigh_l = Vector3(1.42, 0.0, -0.12)
			p.thigh_r = Vector3(1.3, 0.0, 0.14)
			p.shin_l = -0.3
			p.shin_r = -0.55
			p.spine = Vector3(0.1, 0.0, 0.06)
			p.head = Vector3(-0.5, 0.0, 0.1)
			p.arm_l = Vector3(0.4, 0.0, -0.1)
			p.fore_l = 0.5
			p.arm_r = Vector3(0.35, 0.0, 0.3)
			p.fore_r = 0.6
			p.weapon_pitch = 1.2
			p.shield_pos = Vector3(-0.36, -0.05, 0.0)
			p.shield_rot = Vector3(0.3, 1.3, 0.0)
		&"lie":
			p.body_y = -0.8
			p.body_rot = Vector3(PI * 0.5 - 0.06, 0.0, 0.0)
			p.arm_l = Vector3(0.2, 0.0, -0.7)
			p.arm_r = Vector3(0.4, 0.0, 0.5)
			p.fore_r = 0.9
			p.thigh_l = Vector3(0.15, 0.0, -0.1)
			p.shin_l = -0.3
			p.weapon_pitch = 0.2
			p.shield_pos = Vector3(-0.5, -0.1, -0.1)
			p.shield_rot = Vector3(-1.3, 0.3, 0.0)
		&"hide":
			p.body_y = -0.42
			p.thigh_l = Vector3(1.5, 0.0, -0.1)
			p.thigh_r = Vector3(1.5, 0.0, 0.1)
			p.shin_l = -2.3
			p.shin_r = -2.3
			p.spine = Vector3(-0.3, 0.0, 0.0)
			p.head = Vector3(0.2, 0.0, 0.0)
			p.arm_l = Vector3(0.7, 0.0, 0.1)
			p.fore_l = 1.3
			p.arm_r = Vector3(0.7, 0.0, -0.1)
			p.fore_r = 1.3
			p.weapon_pitch = 0.3
		&"hold_child":
			p.arm_l = Vector3(0.75, 0.0, 0.2)
			p.fore_l = 1.5
			p.arm_r = Vector3(0.6, 0.0, -0.3)
			p.fore_r = 1.35
			p.head = Vector3(-0.2, 0.25, 0.0)
		&"cheer":
			p.arm_r = Vector3(2.7, 0.0, 0.3)
			p.fore_r = 0.3
			p.weapon_pitch = 1.3
			p.arm_l = Vector3(0.5, 0.0, -0.22)
			p.fore_l = 1.2
		&"pray":
			p.arm_l = Vector3(2.3, 0.0, -0.4)
			p.arm_r = Vector3(2.3, 0.0, 0.4)
			p.fore_l = 0.4
			p.fore_r = 0.4
			p.head = Vector3(0.35, 0.0, 0.0)
		_:
			pass
	if blocking:
		p.shield_pos = Vector3(-0.1, 0.3, -0.5)
		p.shield_rot = Vector3(-0.08, 0.1, 0.0)
		p.arm_l = Vector3(0.7, 0.0, -0.05)
		p.fore_l = 1.2
		p.body_y -= 0.06
		p.spine.x -= 0.1
	return p


func _apply_locomotion(p: Pose, delta: float) -> void:
	var static_pose := stance == &"sit" or stance == &"lie" or stance == &"hide"
	if static_pose:
		return
	var amp := clampf(speed / 4.6, 0.0, 1.0)
	if speed > 0.15:
		_phase += delta * (3.0 + speed * 1.45)
	var crouch := 1.0 if crouching else 0.0
	if crouch > 0.0:
		p.body_y -= 0.26
		p.thigh_l.x += 0.9
		p.thigh_r.x += 0.9
		p.shin_l -= 1.5
		p.shin_r -= 1.5
		p.spine.x -= 0.38
		p.head.x += 0.32
		amp = clampf(speed / 2.4, 0.0, 1.0) * 0.5
	var s := sin(_phase)
	var c := cos(_phase)
	var swing := 0.2 + 0.62 * amp
	if speed <= 0.15:
		swing = 0.0
	p.thigh_l.x += s * swing
	p.thigh_r.x -= s * swing
	p.shin_l -= (0.12 + 1.0 * maxf(0.0, c)) * swing
	p.shin_r -= (0.12 + 1.0 * maxf(0.0, -c)) * swing
	p.body_y -= 0.035 * swing * absf(s)
	p.spine.y += 0.1 * swing * s
	p.spine.x -= 0.12 * amp
	if stance == &"idle" or stance == &"cheer":
		p.arm_l.x -= s * swing * 0.7
		p.arm_r.x += s * swing * 0.7
		p.fore_l += 0.3 * amp
		p.fore_r += 0.3 * amp
	# A little breathing so a still figure is not a statue.
	var breath := sin(Time.get_ticks_msec() * 0.0016 + _phase)
	p.spine.x += 0.012 * breath
	p.arm_r.z += 0.01 * breath


func _ease(t: float) -> float:
	t = clampf(t, 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


func _apply_attack(p: Pose, delta: float) -> void:
	_attack_t += delta
	var tw := _attack_times.x
	var ts := _attack_times.y
	var tr := _attack_times.z
	if _attack_t >= tw + ts + tr:
		_attack_t = -1.0
		return
	# Wind-up and strike poses for the weapon arm and trunk.
	var wind_arm := Vector3(-0.95, 0.0, 0.2)
	var wind_fore := 1.35
	var wind_pitch := 0.05
	var hit_arm := Vector3(1.2, 0.0, 0.05)
	var hit_fore := 0.1
	var hit_pitch := 0.0
	match _attack_kind:
		&"slash":
			wind_arm = Vector3(2.5, 0.0, 0.4)
			wind_fore = 0.8
			wind_pitch = 1.9
			hit_arm = Vector3(0.75, 0.0, -0.25)
			hit_fore = 0.25
			hit_pitch = -0.4
		&"stab":
			wind_arm = Vector3(-0.5, 0.0, 0.25)
			wind_fore = 1.5
			hit_arm = Vector3(1.0, 0.0, 0.0)
			hit_fore = 0.2
		&"throw":
			wind_arm = Vector3(2.9, 0.0, 0.35)
			wind_fore = 1.3
			wind_pitch = 0.2
			hit_arm = Vector3(1.5, 0.0, 0.1)
			hit_fore = 0.15
			hit_pitch = 0.05
	var arm := p.arm_r
	var fore := p.fore_r
	var pitch := p.weapon_pitch
	var twist := 0.0
	var lean := 0.0
	if _attack_t < tw:
		var k := _ease(_attack_t / tw)
		arm = p.arm_r.lerp(wind_arm, k)
		fore = lerpf(p.fore_r, wind_fore, k)
		pitch = lerpf(p.weapon_pitch, wind_pitch, k)
		twist = -0.42 * k
		lean = 0.06 * k
	elif _attack_t < tw + ts:
		var k := (_attack_t - tw) / ts
		arm = wind_arm.lerp(hit_arm, k)
		fore = lerpf(wind_fore, hit_fore, k)
		pitch = lerpf(wind_pitch, hit_pitch, k)
		twist = lerpf(-0.42, 0.38, k)
		lean = lerpf(0.06, -0.26, k)
	else:
		var k := _ease((_attack_t - tw - ts) / tr)
		arm = hit_arm.lerp(p.arm_r, k)
		fore = lerpf(hit_fore, p.fore_r, k)
		pitch = lerpf(hit_pitch, p.weapon_pitch, k)
		twist = 0.38 * (1.0 - k)
		lean = -0.26 * (1.0 - k)
	p.arm_r = arm
	p.fore_r = fore
	p.weapon_pitch = pitch
	p.spine.y += twist
	p.spine.x += lean
	# The weapon arm is driven exactly; only the rest of the body is smoothed.
	_cur.arm_r = arm
	_cur.fore_r = fore
	_cur.weapon_pitch = pitch


func _death_pose(p: Pose, delta: float) -> void:
	_death_t = minf(_death_t + delta / 0.95, 1.0)
	var k := _death_t * _death_t
	var bounce := sin(clampf((_death_t - 0.82) / 0.18, 0.0, 1.0) * PI) * 0.03
	var sgn := -1.0 if _death_forward else 1.0
	p.body_rot = Vector3(sgn * (PI * 0.5 - 0.05) * k, sin(_death_seed) * 0.5 * k, cos(_death_seed * 1.7) * 0.25 * k)
	p.body_y = -0.8 * k + bounce
	p.spine = Vector3(-0.15 * sgn * (1.0 - k), sin(_death_seed * 2.3) * 0.3 * k, 0.0)
	p.head = Vector3(0.2 * sgn * k, sin(_death_seed * 3.1) * 0.6 * k, 0.0)
	p.arm_l = Vector3(0.3 + sin(_death_seed * 1.3) * 0.8 * k, 0.0, -0.9 * k)
	p.arm_r = Vector3(0.3 + cos(_death_seed * 2.1) * 0.8 * k, 0.0, 1.0 * k)
	p.fore_l = 0.4 + 0.5 * k
	p.fore_r = 0.4
	var buckle := sin(minf(_death_t * 1.6, 1.0) * PI)
	p.thigh_l = Vector3(0.5 * buckle + 0.2 * k * sin(_death_seed), 0.0, -0.1 * k)
	p.thigh_r = Vector3(0.7 * buckle + 0.35 * k * cos(_death_seed), 0.0, 0.16 * k)
	p.shin_l = -0.9 * buckle - 0.25 * k
	p.shin_r = -1.1 * buckle - 0.5 * k * absf(sin(_death_seed))
	p.weapon_pitch = 0.3
	p.shield_pos = Vector3(-0.42, 0.05, -0.1)
	p.shield_rot = Vector3(-1.0 * sgn * k, 0.6, 0.0)


func _process(delta: float) -> void:
	# Distant figures animate on alternate frames.
	_frame += 1
	var cam := get_viewport().get_camera_3d()
	if cam != null and not _dying:
		var d2 := cam.global_position.distance_squared_to(global_position)
		var far := 28.0 if Game.mobile else 70.0
		if d2 > far * far and (_frame + _lod_slot) % 3 != 0:
			return
	var target := _stance_pose()
	if _dying:
		_death_pose(target, delta)
		_cur.blend(target, 1.0 - exp(-22.0 * delta))
		_apply(_cur)
		if _death_t >= 1.0:
			_cur.blend(target, 1.0)
			_apply(_cur)
			set_process(false)
		return
	_apply_locomotion(target, delta)
	if _flinch > 0.0:
		_flinch = maxf(_flinch - delta * 3.2, 0.0)
		target.spine.x += 0.35 * _flinch
		target.head.x += 0.25 * _flinch
		target.body_y -= 0.04 * _flinch
	var rate := 22.0 if blocking else 13.0
	_cur.blend(target, 1.0 - exp(-rate * delta))
	if _attack_t >= 0.0:
		_apply_attack(target, delta)
	_apply(_cur)


func _apply(p: Pose) -> void:
	_body.position.y = HIP_HEIGHT + p.body_y
	_body.rotation = p.body_rot
	_spine.rotation = p.spine
	_head.rotation = p.head
	_arm_l.rotation = p.arm_l
	_fore_l.rotation.x = p.fore_l
	_arm_r.rotation = p.arm_r
	_fore_r.rotation.x = p.fore_r
	_hand_r.rotation = Vector3(p.weapon_pitch - p.arm_r.x - p.fore_r - p.spine.x, p.weapon_yaw, 0.0)
	_thigh_l.rotation = p.thigh_l
	_shin_l.rotation.x = p.shin_l
	_thigh_r.rotation = p.thigh_r
	_shin_r.rotation.x = p.shin_r
	_shield.position = p.shield_pos
	_shield.rotation = p.shield_rot


## Plays an attack: "thrust", "slash", "stab" or "throw". Times are the
## wind-up, strike and recovery in seconds.
func attack(kind: StringName, windup: float, strike: float, recover: float) -> void:
	_attack_kind = kind
	_attack_times = Vector3(windup, strike, recover)
	_attack_t = 0.0


## True while an attack animation is running.
func is_attacking() -> bool:
	return _attack_t >= 0.0


## Jerks the figure back as a blow lands.
func flinch(strength: float = 1.0) -> void:
	_flinch = clampf(strength, 0.0, 1.5)


## Collapses the figure. [param forward] falls face down.
func die(forward: bool) -> void:
	if _dying:
		return
	_dying = true
	_death_forward = forward
	_death_seed = randf() * TAU
	_attack_t = -1.0
	blocking = false
	stance = &"idle"
	set_process(true)


## Puts the figure straight into its final death pose (for bodies placed by a mission).
func lie_dead(forward: bool) -> void:
	_dying = true
	_death_forward = forward
	_death_seed = randf() * TAU
	_death_t = 0.999
	set_process(true)


## Drops cached figure meshes.
static func reset() -> void:
	_mesh_cache.clear()
