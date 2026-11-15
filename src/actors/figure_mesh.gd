class_name FigureMesh
extends RefCounted
## Sculpts the parts of a figure: head and face, trunk, limbs, armour and
## dress. Everything is smooth geometry from [Sculpt]; colour is painted per
## vertex and the materials add grain, weave and hammer marks.
##
## Each part is built in its joint's own space (see [Humanoid.setup]) from a
## resolved look (see [method Humanoid.resolve_look]). Front is -Z.

const HEAD_C := Vector3(0.0, 0.125, -0.004)
const HEAD_R := Vector3(0.084, 0.116, 0.097)
## Share of the way from chin to crown at seven even steps up the grid: the
## middle rows crowd into the face.
static var _face_rows := PackedVector2Array([Vector2(0, 0.0), Vector2(0, 0.25), Vector2(0, 0.36), Vector2(0, 0.45),
	Vector2(0, 0.54), Vector2(0, 0.63), Vector2(0, 1.0)])
const LEATHER := Color(0.30, 0.19, 0.11)
const LEATHER_DARK := Color(0.17, 0.11, 0.07)
const LINEN := Color(0.86, 0.82, 0.72)


static func _gb() -> GeoBuilder:
	var gb := GeoBuilder.new()
	gb.chunk_size = 0.0
	return gb


static func _dir(x: float, y: float, z: float) -> Vector3:
	return Vector3(x, y, z).normalized()


## Traits of one face, steady for a given look: 1 is average.
static func face(look: Dictionary) -> Dictionary:
	var v := float(int(look.get("face", 0)) * 7 + str(look.get("id", "")).hash() % 97)
	var female: bool = look.get("female", false)
	return {
		"nose": (0.82 if female else 1.0) * (0.86 + 0.3 * Sculpt.noise(v, 1.0)),
		"jaw": (0.8 if female else 1.0) * (0.9 + 0.22 * Sculpt.noise(v, 2.0)),
		"brow": (0.45 if female else 1.0) * (0.8 + 0.4 * Sculpt.noise(v, 3.0)),
		"cheek": 0.8 + 0.5 * Sculpt.noise(v, 4.0),
		"chin": (0.7 if female else 1.0) * (0.85 + 0.35 * Sculpt.noise(v, 5.0)),
		"lips": 1.3 if female else 0.9,
		"female": female,
		"cyclops": bool(look.get("cyclops", false)),
	}


## The surface of the bare head in direction [param d] (a unit vector from
## the middle of the skull).
static func head_point(d: Vector3, f: Dictionary) -> Vector3:
	var base := d * HEAD_R
	var low := clampf(-d.y, 0.0, 1.0)
	# The jaw narrows toward the chin and the back of the neck tucks in.
	base.x *= 1.0 - 0.2 * smoothstep(0.3, 1.0, low) / float(f["jaw"])
	if d.z > 0.0:
		base.z *= 1.0 - 0.3 * smoothstep(0.2, 1.0, low)
	var front := smoothstep(0.0, 0.5, -d.z)
	var s := 1.0
	s += 0.07 * float(f["chin"]) * Sculpt.bump(d, _dir(0.0, -0.78, -0.62), 0.42)
	# The corners of the jaw.
	s += 0.07 * float(f["jaw"]) * (Sculpt.bump(d, _dir(0.74, -0.56, -0.3), 0.3) + Sculpt.bump(d, _dir(-0.74, -0.56, -0.3), 0.3))
	s += 0.06 * Sculpt.bump(d, _dir(0.0, 0.25, 0.97), 0.6)
	s += 0.05 * float(f["brow"]) * (Sculpt.bump(d, _dir(0.27, 0.27, -0.92), 0.2) + Sculpt.bump(d, _dir(-0.27, 0.27, -0.92), 0.2))
	if f.get("cyclops", false):
		# One great eye in the middle of the brow (Odyssey 9).
		s -= 0.13 * Sculpt.bump(d, _dir(0.0, 0.2, -0.98), 0.2)
	else:
		s -= 0.085 * (Sculpt.bump(d, _dir(0.35, 0.13, -0.93), 0.15) + Sculpt.bump(d, _dir(-0.35, 0.13, -0.93), 0.15))
	s += 0.045 * float(f["cheek"]) * (Sculpt.bump(d, _dir(0.62, -0.08, -0.78), 0.24) + Sculpt.bump(d, _dir(-0.62, -0.08, -0.78), 0.24))
	# A slight swell where the nose and mouth sit; they are sculpted apart
	# (see _nose and _lips), finer than this surface could hold them.
	s += 0.03 * exp(-pow(d.x / 0.22, 2.0)) * exp(-pow((d.y + 0.2) / 0.3, 2.0)) * front
	return HEAD_C + base * s


## Unit direction for grid coordinates: v runs chin to crown, u round the
## head with the face (u = 0) given more of the grid than the back.
## With [param even] the rows are spread evenly instead (for hair).
static func head_dir(u: float, v: float, even: bool = false) -> Vector3:
	var phi := TAU * u - 0.55 * sin(TAU * u)
	# More rows through the face (brow to chin) than over the crown or under the jaw.
	var theta := PI * (v if even else clampf(Sculpt.spline2(_face_rows, v).y, 0.0, 1.0))
	return Vector3(sin(theta) * sin(phi), -cos(theta), -sin(theta) * cos(phi))


static func _skin_tone(d: Vector3, skin: Color, f: Dictionary) -> Color:
	var c := skin
	# Blood near the surface in the cheeks. Shadow in the sockets.
	var flush := Sculpt.bump(d, _dir(0.55, -0.12, -0.8), 0.3) + Sculpt.bump(d, _dir(-0.55, -0.12, -0.8), 0.3)
	c = c.lerp(skin * Color(1.05, 0.86, 0.82), clampf(flush, 0.0, 1.0) * 0.3)
	var socket := Sculpt.bump(d, _dir(0.35, 0.13, -0.93), 0.13) + Sculpt.bump(d, _dir(-0.35, 0.13, -0.93), 0.13)
	c = c.lerp(skin * Color(0.62, 0.52, 0.5), clampf(socket, 0.0, 1.0) * 0.55)
	# The mouth's shadow, behind the lips.
	var mouth := exp(-pow((d.y + 0.37) / 0.05, 2.0)) * exp(-pow(d.x / 0.17, 2.0)) * (1.0 if d.z < 0.0 else 0.0)
	c = c.lerp(skin * Color(0.4, 0.24, 0.22), mouth * 0.85)
	# Under the jaw sits in its own shade.
	c = c.darkened(0.22 * smoothstep(0.7, 1.0, -d.y))
	return c


## How much hair grows in direction [param d]: 0 none, 1 full.
static func _scalp(d: Vector3, long_hair: bool) -> float:
	var s := sqrt(maxf(1.0 - d.y * d.y, 1e-6))
	var back := (d.z / s + 1.0) * 0.5
	var line := lerpf(0.5, -0.92 if long_hair else -0.5, smoothstep(0.22, 0.78, back))
	# Clear of the ears' front edge, and a temple's recess.
	line += 0.1 * Sculpt.bump(d, _dir(0.75, 0.3, -0.6), 0.2) + 0.1 * Sculpt.bump(d, _dir(-0.75, 0.3, -0.6), 0.2)
	return smoothstep(line, line + 0.14, d.y)


static func _beard(d: Vector3) -> float:
	if d.z > 0.35:
		return 0.0
	var jaw := smoothstep(-0.12, -0.34, d.y) * smoothstep(0.35, 0.1, d.z)
	var moustache := exp(-pow((d.y + 0.27) / 0.05, 2.0)) * exp(-pow(d.x / 0.3, 2.0))
	var mouth := exp(-pow((d.y + 0.36) / 0.04, 2.0)) * exp(-pow(d.x / 0.15, 2.0))
	# Bare cheeks high on the face.
	var cheek := smoothstep(-0.2, -0.45, d.y) + smoothstep(0.45, 0.8, absf(d.x))
	return clampf(maxf(jaw * clampf(cheek, 0.0, 1.0), moustache) - mouth * 0.9, 0.0, 1.0)


static func _streak(col: Color, a: float, b: float, amount: float = 0.3) -> Color:
	return col.darkened(amount * Sculpt.noise(floorf(a), floorf(b))).lightened(0.08 * Sculpt.noise(floorf(a) + 9.0, b))


## The helmet's inner form at angle [param phi] (0 at the face) and height.
static func _helm(phi: float, y: float, grow: float = 0.0) -> Vector3:
	var r := 0.094 + grow
	if y < 0.155:
		r -= (0.155 - y) * 0.1
	return Vector3(sin(phi) * r, y, -cos(phi) * r * 1.2)


static func _cheek_piece(gb: GeoBuilder, mat: StringName, col: Color, sx: float, drop: float = 0.15) -> void:
	var pos := func(u: float, v: float) -> Vector3:
		var narrow := 1.0 - 0.55 * v * v
		return _helm(sx * (1.3 + (u - 0.5) * 0.9 * narrow), 0.162 - v * drop, 0.004)
	Sculpt.grid(gb, mat, 4, 4, pos, col, false, HEAD_C)


## A horsehair crest: a fan standing along [param path] (z, y points from
## brow to tail), [param height] tall at its fullest.
static func _crest(gb: GeoBuilder, path: PackedVector2Array, height: float, col: Color) -> void:
	var pos := func(u: float, v: float) -> Vector3:
		var p := Sculpt.spline2(path, v)
		var q := Sculpt.spline2(path, minf(v + 0.02, 1.0)) - Sculpt.spline2(path, maxf(v - 0.02, 0.0))
		var out := Vector2(-q.y, q.x).normalized()
		var h := height * (0.35 + 0.65 * sin(PI * clampf(v * 1.15, 0.0, 1.0))) * (0.6 + 0.4 * Sculpt.noise(floorf(v * 40.0), 3.0))
		var lift := 0.5 * (1.0 - cos(u * TAU))
		var side := sin(u * TAU) * 0.013 * (1.0 - 0.6 * lift)
		return Vector3(side, p.y + out.y * h * lift, p.x + out.x * h * lift)
	var tone := func(u: float, v: float) -> Color:
		return _streak(col, v * 46.0, 1.0, 0.35).darkened(0.25 * (1.0 - 0.5 * (1.0 - cos(u * TAU))))
	Sculpt.grid(gb, &"hair", 6, Sculpt._n(18), pos, tone, true, null)


## The nose: a ridge from between the brows that swells to the tip and
## nostrils, then tucks back under.
static func _nose(gb: GeoBuilder, skin: Color, f: Dictionary) -> void:
	var size := float(f["nose"])
	var pos := func(u: float, v: float) -> Vector3:
		var root := head_point(_dir(0.0, lerpf(0.2, -0.17, minf(v, 0.86) / 0.86), -1.0), f)
		var t := minf(v / 0.86, 1.0)
		var under := smoothstep(0.86, 1.0, v)
		var w := lerpf(0.0075, 0.0185, pow(t, 1.6)) * size
		var h := lerpf(0.004, 0.027, pow(t, 1.35)) * size * (1.0 - under)
		var a := PI * u
		# Nostril wings: the sides flare out near the base.
		var wing := 0.004 * size * pow(t, 5.0) * pow(sin(a), 0.5)
		return root + Vector3(-cos(a) * (w + wing), -0.006 * under, -sin(a) * h + 0.002)
	var tone := func(u: float, v: float) -> Color:
		var c := skin.lerp(skin * Color(1.05, 0.84, 0.8), 0.35 * v)
		return c.darkened(0.5) if v > 0.9 and absf(u - 0.5) > 0.12 and absf(u - 0.5) < 0.4 else c
	Sculpt.grid(gb, &"skin", 8, 9, pos, tone, false, HEAD_C)


## Lips: two soft rolls over the mouth's shadow.
static func _lips(gb: GeoBuilder, skin: Color, f: Dictionary) -> void:
	var full := float(f["lips"])
	var red := skin * (Color(0.9, 0.56, 0.52) if f["female"] else Color(0.84, 0.66, 0.6))
	for upper: bool in [true, false]:
		var pos := func(u: float, v: float) -> Vector3:
			var x := lerpf(-0.23, 0.23, u)
			var edge := sin(PI * u)
			var mid := -0.37 + (0.012 if upper else -0.012) * edge
			var y := mid + (v - 0.5) * 0.042 * full * edge * (1.0 if upper else 1.25)
			# The upper lip dips in the middle; the corners turn down a touch.
			if upper:
				y -= 0.008 * exp(-pow((u - 0.5) / 0.08, 2.0)) * v
			var d := _dir(x, y - 0.012 * (1.0 - edge), -0.93)
			return head_point(d, f) + d * (0.0005 + 0.0038 * full * sin(PI * v) * edge)
		Sculpt.grid(gb, &"skin", 8, 3, pos, red, false, HEAD_C)


static func _eye(gb: GeoBuilder, look: Dictionary, f: Dictionary, sx: float) -> void:
	var skin: Color = look["skin"]
	var hair: Color = look["hair"]
	var cyclops := sx == 0.0
	var socket := head_point(_dir(0.0, 0.2, -0.98) if cyclops else _dir(sx * 0.35, 0.13, -0.93), f)
	var eye := socket + Vector3(-sx * 0.001, -0.001, 0.0075)
	var big := 1.9 if cyclops else 1.0
	if look.get("blind", false):
		big = 0.0
	var iris := Color(0.16, 0.10, 0.06) if int(look.get("face", 0)) != 3 else Color(0.24, 0.26, 0.2)
	var ball := func(u: float, v: float) -> Vector3:
		var th := PI * v
		return eye + Vector3(sin(th) * cos(u * TAU), sin(th) * sin(u * TAU), -cos(th)) * 0.0125 * big
	var ball_col := func(_u: float, v: float) -> Color:
		if v < 0.1:
			return Color(0.02, 0.02, 0.02)
		return iris if v < 0.24 else Color(0.9, 0.87, 0.82)
	if big > 0.0:
		Sculpt.grid(gb, &"eye", 10, 8, ball, ball_col, true, null)
	else:
		# Put out: a raw, dark wound.
		var wound := func(u: float, v: float) -> Vector3:
			var th := PI * v
			return eye + Vector3(sin(th) * cos(u * TAU), sin(th) * sin(u * TAU), -cos(th) * 0.4) * 0.02
		Sculpt.grid(gb, &"skin", 8, 6, wound, Color(0.35, 0.05, 0.04), true, null)
	var lid := func(u: float, v: float) -> Vector3:
		var a := lerpf(0.15, PI - 0.15, u)
		var e := lerpf(0.3, 1.32, v)
		return eye + Vector3(cos(a) * sin(e), cos(e), -sin(a) * sin(e)).normalized() * 0.0138
	Sculpt.grid(gb, &"skin", 6, 3, lid, skin.darkened(0.1), false, HEAD_C)
	var lower := func(u: float, v: float) -> Vector3:
		var a := lerpf(0.15, PI - 0.15, u)
		var e := lerpf(PI - 0.35, PI - 1.0, v)
		return eye + Vector3(cos(a) * sin(e), cos(e), -sin(a) * sin(e)).normalized() * 0.0136
	Sculpt.grid(gb, &"skin", 6, 2, lower, skin.darkened(0.05), false, HEAD_C)
	var brow := func(u: float, v: float) -> Vector3:
		var y := 0.245 + 0.03 * sin(PI * u) - 0.02 * u + (v - 0.5) * 0.045
		var d := _dir((lerpf(-0.36, 0.36, u) if cyclops else sx * lerpf(0.13, 0.5, u)), y + (0.06 if cyclops else 0.0), -0.93)
		return head_point(d, f) + d * (0.0015 + 0.0025 * sin(PI * v))
	Sculpt.grid(gb, &"hair", 5, 2, brow, hair.darkened(0.25), false, HEAD_C)
	if cyclops:
		return
	var at := head_point(_dir(sx * 0.99, 0.02, 0.12), f) + Vector3(sx * 0.004, 0.0, 0.0)
	var ear := func(u: float, v: float) -> Vector3:
		var th := PI * v
		return at + Vector3(sin(th) * cos(u * TAU) * 0.008, -cos(th) * 0.027, sin(th) * sin(u * TAU) * 0.015)
	Sculpt.grid(gb, &"skin", 6, 4, ear, skin * Color(1.0, 0.86, 0.82), true, null)


static func _ring(gb: GeoBuilder, mat: StringName, r: float, y: float, h: float, col: Color = Color.WHITE, squash: float = 1.2, segs: int = 20) -> void:
	Sculpt.lathe_hard(gb, mat, Transform3D.IDENTITY, PackedVector2Array([Vector2(r, y), Vector2(r + h * 0.35, y + h * 0.5),
		Vector2(r, y + h)]), segs, col, squash)


## Head, face, hair and whatever is worn on it.
static func head(look: Dictionary, mats: Dictionary) -> ArrayMesh:
	var gb := _gb()
	var skin: Color = look["skin"]
	var hair: Color = look["hair"]
	var crest: Color = look["crest"]
	var f := face(look)
	var helmet: String = look["helmet"]
	var covered := helmet in ["boar_tusk", "bronze_crest", "bronze_crest_tall", "bronze_gold", "anatolian", "leather"]
	var long_hair: bool = look.get("long_hair", true)

	var face_pos := func(u: float, v: float) -> Vector3:
		return head_point(head_dir(u, v), f)
	var face_col := func(u: float, v: float) -> Color:
		return _skin_tone(head_dir(u, v), skin, f)
	Sculpt.grid(gb, &"skin", Sculpt._n(34), Sculpt._n(28), face_pos, face_col, true, null)
	if f.get("cyclops", false):
		_eye(gb, look, f, 0.0)
	else:
		for sx: float in [-1.0, 1.0]:
			_eye(gb, look, f, sx)
	_nose(gb, skin, f)
	_lips(gb, skin, f)

	# Hair: a shell over the scalp that sinks into the head where none grows.
	var hair_pos := func(u: float, v: float) -> Vector3:
		var d := head_dir(u, v, true)
		var m := _scalp(d, long_hair)
		var thick := 0.011 + 0.008 * Sculpt.noise(floorf(u * 40.0), floorf(v * 9.0))
		if long_hair and d.y < 0.0:
			thick += 0.02 * smoothstep(0.0, -0.6, d.y)
		if covered and d.y > -0.2:
			thick = minf(thick, 0.008)
		return head_point(d, f) + d * lerpf(-0.02, thick, smoothstep(0.0, 0.3, m))
	var hair_col := func(u: float, _v: float) -> Color:
		return _streak(hair, u * 60.0, 2.0)
	Sculpt.grid(gb, &"hair", Sculpt._n(24), Sculpt._n(16), hair_pos, hair_col, true, null)
	if look["beard"]:
		var beard_pos := func(u: float, v: float) -> Vector3:
			# Only the lower face: above the nostrils a coarse shell would
			# cut across the hollows of the eyes.
			var d := head_dir(u * 0.56 - 0.28, 0.02 + v * 0.48)
			var m := _beard(d) * smoothstep(-0.16, -0.24, d.y)
			var q := head_point(d, f) + d * lerpf(-0.02, 0.008 + 0.012 * smoothstep(-0.4, -0.9, d.y), smoothstep(0.0, 0.3, m))
			q.y -= 0.03 * m * smoothstep(-0.55, -0.95, d.y)
			return q
		var beard_col := func(u: float, _v: float) -> Color:
			return _streak(hair.darkened(0.08), u * 44.0, 5.0)
		Sculpt.grid(gb, &"hair", Sculpt._n(18), Sculpt._n(10), beard_pos, beard_col, false, HEAD_C)

	var dome := PackedVector2Array([Vector2(0.097, 0.15), Vector2(0.1, 0.185), Vector2(0.09, 0.225), Vector2(0.055, 0.262), Vector2(0.0, 0.278)])
	match helmet:
		"boar_tusk":
			# Rows of split boar tusks sewn to a leather cap, each row
			# curving the other way from the last (Iliad 10.261-265).
			var tusk_pos := func(u: float, v: float) -> Vector3:
				var q := Sculpt.spline2(dome, v)
				var row := floorf(v * 4.0)
				var swell := 0.0035 * sin(PI * fposmod(v * 4.0, 1.0)) * (1.0 if v < 0.98 else 0.0)
				var r := q.x + swell + 0.0012 * sin(u * TAU * 24.0 + row * PI)
				return Vector3(cos(u * TAU) * r, q.y, sin(u * TAU) * r * 1.2)
			var tusk_col := func(u: float, v: float) -> Color:
				var row := floorf(v * 4.0)
				if absf(fposmod(v * 4.0, 1.0) - 0.5) > 0.4:
					return Color(0.3, 0.22, 0.14)
				return Color.WHITE.darkened(0.16 * Sculpt.noise(floorf(u * 24.0 + row * 0.5), row))
			Sculpt.grid(gb, &"ivory", Sculpt._n(24), 12, tusk_pos, tusk_col, true, null)
			for sx: float in [-1.0, 1.0]:
				_cheek_piece(gb, &"ivory", Color(0.92, 0.9, 0.84), sx)
			Sculpt.lathe(gb, &"ivory", Transform3D(Basis.IDENTITY, Vector3(0, 0.272, 0)), PackedVector2Array([Vector2(0.02, 0.0),
				Vector2(0.014, 0.012), Vector2(0.024, 0.03), Vector2(0.0, 0.04)]), 8, Color.WHITE)
		"bronze_crest", "bronze_crest_tall", "bronze_gold":
			Sculpt.lathe(gb, &"bronze", Transform3D.IDENTITY, dome, 20, Color.WHITE, 1.2)
			_ring(gb, &"gold" if helmet == "bronze_gold" else &"bronze_dull", 0.099, 0.147, 0.015)
			for sx: float in [-1.0, 1.0]:
				_cheek_piece(gb, &"bronze", Color.WHITE, sx)
			var nasal := func(u: float, v: float) -> Vector3:
				return _helm((u - 0.5) * 0.16, 0.158 - v * 0.075, 0.006)
			Sculpt.grid(gb, &"bronze", 2, 3, nasal, Color.WHITE, false, HEAD_C)
			var nape := func(u: float, v: float) -> Vector3:
				return _helm(PI + (u - 0.5) * 2.6, 0.155 - v * 0.12, 0.004 + v * 0.014)
			Sculpt.grid(gb, &"bronze", 8, 2, nape, Color.WHITE, false, HEAD_C)
			var tall := helmet != "bronze_crest"
			var lift := 0.06 if tall else 0.0
			if tall:
				Sculpt.lathe_hard(gb, &"gold" if helmet == "bronze_gold" else &"bronze", Transform3D(Basis.IDENTITY, Vector3(0, 0.27, 0.0)),
					PackedVector2Array([Vector2(0.016, 0.0), Vector2(0.011, 0.02), Vector2(0.011, lift), Vector2(0.02, lift + 0.012)]), 8)
			_crest(gb, PackedVector2Array([Vector2(-0.1, 0.235 + lift), Vector2(-0.04, 0.28 + lift), Vector2(0.05, 0.278 + lift),
				Vector2(0.125, 0.2 + lift * 0.6), Vector2(0.15, 0.04), Vector2(0.165, -0.12)]), 0.1 if tall else 0.075, crest)
			if helmet == "bronze_gold":
				_ring(gb, &"gold", 0.093, 0.215, 0.014)
		"anatolian":
			# Tall pointed helmet with a plume down the back, as on the
			# warrior of the King's Gate at Hattusa.
			var cone := PackedVector2Array([Vector2(0.097, 0.15), Vector2(0.098, 0.19), Vector2(0.068, 0.265), Vector2(0.03, 0.34), Vector2(0.0, 0.362)])
			Sculpt.lathe(gb, &"bronze_dull", Transform3D.IDENTITY, cone, 20, Color.WHITE, 1.2)
			_ring(gb, &"bronze", 0.099, 0.147, 0.02)
			for sx: float in [-1.0, 1.0]:
				_cheek_piece(gb, &"hide", LEATHER, sx, 0.15)
			var plume := PackedVector2Array([Vector2(0.0, 0.36), Vector2(0.07, 0.34), Vector2(0.125, 0.21), Vector2(0.14, 0.03)])
			var plume_pos := func(u: float, v: float) -> Vector3:
				var q := Sculpt.spline2(plume, v)
				var r := 0.014 * (0.5 + 0.9 * sin(PI * clampf(v * 0.9 + 0.1, 0.0, 1.0)))
				return Vector3(cos(u * TAU) * r, q.y + sin(u * TAU) * r, q.x)
			var plume_col := func(_u: float, v: float) -> Color:
				return _streak(crest, v * 30.0, 6.0)
			Sculpt.grid(gb, &"hair", 6, 10, plume_pos, plume_col, true, null)
		"leather":
			var cap_col := func(u: float, _v: float) -> Color:
				return LEATHER.darkened(0.5) if fposmod(u * 6.0, 1.0) < 0.05 else LEATHER
			Sculpt.lathe(gb, &"hide", Transform3D.IDENTITY, dome, 20, cap_col, 1.2)
			_ring(gb, &"bronze_dull", 0.099, 0.147, 0.02)
			Sculpt.lathe(gb, &"bronze_dull", Transform3D(Basis.IDENTITY, Vector3(0, 0.27, 0)), PackedVector2Array([Vector2(0.03, 0.0),
				Vector2(0.02, 0.014), Vector2(0.0, 0.022)]), 8, Color.WHITE)
			for sx: float in [-1.0, 1.0]:
				_cheek_piece(gb, &"hide", LEATHER, sx, 0.13)
		"veil":
			# A veil over the hair, falling to the shoulders behind.
			var veil_pos := func(u: float, v: float) -> Vector3:
				var phi := PI + (u - 0.5) * lerpf(4.3, 3.3, v)
				var y := lerpf(0.272, -0.3, v * v * 0.6 + v * 0.4)
				var r := 0.0
				if y > 0.15:
					r = Sculpt.spline2(dome, clampf((y - 0.15) / 0.128, 0.0, 1.0)).x + 0.006
				else:
					r = 0.103 + (0.15 - y) * 0.18 + 0.006 * sin(phi * 9.0) * (0.15 - y) * 3.0
				return Vector3(sin(phi) * r, y, -cos(phi) * r * 1.2)
			var veil_col := func(u: float, _v: float) -> Color:
				return crest.darkened(0.12 * absf(sin(u * 30.0)))
			Sculpt.grid(gb, &"wool_2s", Sculpt._n(16), 10, veil_pos, veil_col, false, HEAD_C)
		"diadem":
			_ring(gb, &"gold", 0.086, 0.176, 0.024)
		_:
			_ring(gb, &"wool", 0.088, 0.172, 0.016, Color(0.5, 0.2, 0.14), 1.2, 16)
	return Sculpt.mesh_with_lods(gb, mats)


## Rings of the trunk for [method Sculpt.loft], grown outward by [param grow].
static func _trunk(grow: float, female: bool) -> Array:
	var waist := 0.9 if female else 1.0
	var chest := 1.08 if female else 1.0
	return [
		[-0.03, 0.03, 0.03, 0.03, 0.0, 0.0, 2.0],
		[0.0, 0.135 * waist + grow, 0.09 + grow, 0.085 + grow, 0.0, 0.0, 2.3],
		[0.12, 0.146 * waist + grow, 0.098 + grow, 0.09 + grow, 0.0, 0.0, 2.3],
		[0.26, 0.17 + grow, 0.116 * chest + grow, 0.1 + grow, 0.0, 0.0, 2.4],
		[0.38, 0.188 + grow, 0.124 * chest + grow, 0.106 + grow, 0.0, 0.0, 2.5],
		[0.455, 0.18 + grow, 0.1 + grow, 0.1 + grow, 0.0, 0.006, 2.5],
		[0.5, 0.105 + grow, 0.072 + grow, 0.084 + grow, 0.0, 0.01, 2.2],
		[0.53, 0.056 + grow * 0.4, 0.052 + grow * 0.4, 0.056 + grow * 0.4, 0.0, 0.006, 2.0],
		[0.61, 0.05, 0.05, 0.052, 0.0, 0.0, 2.0],
	]


static func _band(gb: GeoBuilder, mat: StringName, y: float, w: float, df: float, db: float, col: Color = Color.WHITE) -> void:
	Sculpt.loft(gb, mat, Transform3D.IDENTITY, [[y - 0.016, w - 0.003, df - 0.003, db - 0.003, 0, 0, 2.3], [y, w, df, db, 0, 0, 2.3],
		[y + 0.016, w - 0.003, df - 0.003, db - 0.003, 0, 0, 2.3]], 22, col, 1)


static func _stud(gb: GeoBuilder, mat: StringName, at: Vector3, out: Vector3, r: float) -> void:
	var up := Vector3.UP if absf(out.y) < 0.9 else Vector3.RIGHT
	var x := up.cross(out).normalized()
	var basis := Basis(x, out, x.cross(out))
	Sculpt.lathe(gb, mat, Transform3D(basis, at), PackedVector2Array([Vector2(r, 0.0), Vector2(r * 0.7, r * 0.45), Vector2(0.0, r * 0.6)]),
		6, Color.WHITE, 1.0, 1)


## Trunk, neck and body armour.
static func torso(look: Dictionary, mats: Dictionary) -> ArrayMesh:
	var gb := _gb()
	var tunic: Color = look["tunic"]
	var skin: Color = look["skin"]
	var female: bool = look.get("female", false)
	var rings := _trunk(0.0, female)
	var trim: Color = look["kilt"]
	var cloth := func(u: float, v: float) -> Color:
		var y := Sculpt.loft_point(rings, u, v).y
		if y > 0.49:
			return trim
		return tunic.darkened(0.07 * absf(sin(u * TAU * 9.0)) * smoothstep(0.3, 0.0, y))
	Sculpt.loft(gb, &"wool", Transform3D.IDENTITY, rings.slice(0, 8), 22, cloth)
	Sculpt.loft(gb, &"skin", Transform3D.IDENTITY, [[0.5, 0.062, 0.058, 0.062, 0.0, 0.008, 2.0], [0.535, 0.058, 0.054, 0.058, 0.0, 0.006, 2.0],
		[0.61, 0.051, 0.051, 0.053, 0.0, 0.0, 2.0]], 12, skin.darkened(0.05), 2)
	var armor: String = look["armor"]
	var shell := _trunk(0.011, female).slice(1, 7)
	match armor:
		"bronze", "bronze_gold":
			# A bronze corslet of front and back plates, with wide shoulder
			# pieces and a collar, after the panoply found at Dendra.
			Sculpt.loft(gb, &"bronze", Transform3D.IDENTITY, shell, 22, Color.WHITE)
			var edge: StringName = &"gold" if armor == "bronze_gold" else &"bronze_dull"
			_band(gb, edge, 0.004, 0.153, 0.109, 0.103)
			_band(gb, edge, 0.257, 0.187, 0.133, 0.116)
			Sculpt.lathe_hard(gb, &"bronze", Transform3D(Basis.IDENTITY, Vector3(0, 0, 0.008)), PackedVector2Array([Vector2(0.066, 0.515),
				Vector2(0.074, 0.55), Vector2(0.08, 0.575)]), 14, Color.WHITE, 1.05)
			for sx: float in [-1.0, 1.0]:
				var tilt := Transform3D(Basis(Vector3(0, 0, 1), -sx * 0.42), Vector3(sx * 0.2, 0.445, 0.004))
				Sculpt.lathe(gb, &"bronze", tilt, PackedVector2Array([Vector2(0.098, -0.07), Vector2(0.094, -0.01), Vector2(0.066, 0.04),
					Vector2(0.0, 0.056)]), 12, Color.WHITE, 1.05)
				Sculpt.lathe_hard(gb, edge, tilt, PackedVector2Array([Vector2(0.097, -0.078), Vector2(0.101, -0.07), Vector2(0.097, -0.062)]),
					12, Color.WHITE, 1.05)
			if armor == "bronze_gold":
				# The stars on the breastplate of Achilles (Iliad 16.134).
				for i in 5:
					var at := Sculpt.loft_point(shell, 0.75 + (i - 2) * 0.045, 0.62 - absf(i - 2.0) * 0.05)
					_stud(gb, &"gold", at, Vector3(at.x * 0.6, 0.0, -1.0).normalized(), 0.015)
		"linen":
			# A quilted linen corslet, edged in the colour of the kilt.
			var quilt := func(u: float, v: float) -> Color:
				if v < 0.05 or v > 0.93:
					return trim
				var line := absf(fposmod(u * 26.0, 1.0) - 0.5) > 0.42 or absf(fposmod(v * 7.0, 1.0) - 0.5) > 0.44
				return LINEN.darkened(0.3) if line else LINEN
			Sculpt.loft(gb, &"wool", Transform3D.IDENTITY, shell, 26, quilt)
		"leather":
			var hide := func(u: float, v: float) -> Color:
				if v < 0.06 or v > 0.93 or absf(fposmod(v * 4.0, 1.0) - 0.5) > 0.46:
					return LEATHER_DARK
				return LEATHER.darkened(0.15 * Sculpt.noise(floorf(u * 8.0), floorf(v * 4.0)))
			Sculpt.loft(gb, &"hide", Transform3D.IDENTITY, shell, 22, hide)
			for i in 8:
				var at := Sculpt.loft_point(shell, (i + 0.5) / 8.0, 0.5)
				_stud(gb, &"bronze", at, Vector3(at.x, 0.0, at.z).normalized(), 0.016)
		"scale":
			Sculpt.loft(gb, &"bronze_scale", Transform3D.IDENTITY, shell, 22, Color.WHITE)
			_band(gb, &"hide", 0.004, 0.152, 0.108, 0.102, LEATHER_DARK)
		_:
			# A belt over the plain tunic.
			_band(gb, &"hide", 0.004, 0.143, 0.099, 0.093, LEATHER)
			_stud(gb, &"bronze_dull", Vector3(0.0, 0.004, -0.099), Vector3(0, 0, -1), 0.016)
	var cloak: Variant = look["cloak"]
	if cloak is Array:
		var cc := Humanoid._color(cloak)
		# Hung from the shoulders, pinned at the breast, falling in folds.
		var fall := func(u: float, v: float) -> Vector3:
			var a := (u - 0.5) * lerpf(2.5, 2.9, v)
			var r := lerpf(0.19, 0.3, v) + 0.014 * sin(a * 11.0) * v
			return Vector3(sin(a) * r, lerpf(0.5, -0.46, v) - 0.03 * cos(a) * (1.0 - v), 0.03 + cos(a) * r * lerpf(0.5, 0.75, v))
		var fold := func(u: float, v: float) -> Color:
			return cc.darkened(0.1 + 0.16 * v + 0.1 * absf(sin((u - 0.5) * 16.0)))
		Sculpt.grid(gb, &"wool_2s", Sculpt._n(14), 10, fall, fold, false, Vector3(0, 0.1, 0))
		var over := _trunk(0.02, female)
		for sx: float in [-1.0, 1.0]:
			var yoke := func(u: float, v: float) -> Vector3:
				return Sculpt.loft_point(over, 0.25 + sx * (0.25 - v * 0.47), lerpf(0.66, 0.73, u))
			Sculpt.grid(gb, &"wool_2s", 3, 4, yoke, cc, false, Vector3(0, 0.3, 0))
		_stud(gb, &"gold", Vector3(0.0, 0.47, -0.105), Vector3(0, 0.3, -1).normalized(), 0.02)
	return Sculpt.mesh_with_lods(gb, mats)


## Hips: the kilt or robe, and the skirt of the armour over it.
static func pelvis(look: Dictionary, mats: Dictionary) -> ArrayMesh:
	var gb := _gb()
	var kilt: Color = look["kilt"]
	var robe: bool = look["robe"]
	var hem := -0.86 if robe else -0.37
	var flare := 0.235 if robe else 0.2
	var skirt := func(u: float, v: float) -> Vector3:
		if v < 0.08:
			return Vector3(cos(u * TAU) * 0.05, 0.07, sin(u * TAU) * 0.04)
		var t := (v - 0.08) / 0.92
		var r := lerpf(0.15, flare, pow(t, 0.5 if robe else 0.8)) * (1.0 + 0.045 * sin(u * TAU * 14.0) * t)
		# A robe hangs full enough to walk in.
		return Vector3(cos(u * TAU) * r, lerpf(0.05, hem, t), sin(u * TAU) * r * (1.0 if robe else 0.82))
	var skirt_col := func(_u: float, v: float) -> Color:
		if v > 0.93:
			return kilt.lightened(0.45)
		return kilt.darkened(0.35) if v > 0.84 and v < 0.88 else kilt
	Sculpt.grid(gb, &"wool", Sculpt._n(28), 10, skirt, skirt_col, true, null)
	# Shade inside the skirt, so the hem does not look hollow from below.
	var under := func(u: float, v: float) -> Vector3:
		return Vector3(cos(u * TAU) * flare * 0.96 * v, hem + 0.05, sin(u * TAU) * flare * 0.8 * v)
	Sculpt.grid(gb, &"dark", 10, 1, under, Color.WHITE, true, Vector3(0, hem + 1.0, 0))
	match str(look["armor"]):
		"bronze", "bronze_gold":
			# Hoops of bronze hung from the corslet.
			for i in 3:
				var y := 0.02 - i * 0.075
				var r := 0.162 + i * 0.016
				Sculpt.lathe_hard(gb, &"bronze", Transform3D.IDENTITY, PackedVector2Array([Vector2(r + 0.012, y - 0.092), Vector2(r + 0.014, y - 0.085),
					Vector2(r, y), Vector2(r - 0.004, y + 0.004)]), 22, Color.WHITE, 0.84)
		"linen", "leather", "scale":
			# Strips of stiffened linen or leather.
			var leather := str(look["armor"]) != "linen"
			var base := LEATHER if leather else LINEN
			var strips := func(u: float, v: float) -> Vector3:
				var r := 0.158 + v * 0.03
				var notch := 0.0 if absf(fposmod(u * 14.0, 1.0) - 0.5) < 0.4 else 0.6
				return Vector3(cos(u * TAU) * r, 0.03 - v * 0.2 * (1.0 - notch * v), sin(u * TAU) * r * 0.83)
			var strips_col := func(u: float, _v: float) -> Color:
				if absf(fposmod(u * 14.0, 1.0) - 0.5) > 0.4:
					return base.darkened(0.45)
				return base.darkened(0.1 * (int(floorf(u * 14.0)) % 2))
			Sculpt.grid(gb, &"hide" if leather else &"wool", Sculpt._n(28), 3, strips, strips_col, true, null)
	return Sculpt.mesh_with_lods(gb, mats)


## Upper arm (with its sleeve) or forearm (with hand and bracer).
static func arm(look: Dictionary, upper: bool, mats: Dictionary) -> ArrayMesh:
	var gb := _gb()
	var skin: Color = look["skin"]
	if upper:
		Sculpt.loft(gb, &"skin", Transform3D.IDENTITY, [[-0.31, 0.02, 0.02, 0.02, 0, 0, 2], [-0.28, 0.044, 0.044, 0.046, 0, 0, 2],
			[-0.21, 0.048, 0.049, 0.05, 0, 0, 2], [-0.12, 0.055, 0.06, 0.055, 0, -0.004, 2], [-0.04, 0.062, 0.062, 0.06, 0, 0, 2],
			[0.03, 0.056, 0.058, 0.058, 0, 0, 2], [0.062, 0.02, 0.02, 0.02, 0, 0, 2]], 10, skin, 2)
		var cuff := -0.25 if look["robe"] else -0.13
		var edge: Color = look["kilt"]
		var cloth: Color = look["tunic"]
		var sleeve := func(_u: float, v: float) -> Color:
			return edge if v < 0.12 else cloth
		Sculpt.loft(gb, &"wool", Transform3D.IDENTITY, [[cuff, 0.066, 0.068, 0.066, 0, 0, 2], [cuff + 0.02, 0.063, 0.066, 0.064, 0, 0, 2],
			[-0.03, 0.069, 0.069, 0.067, 0, 0, 2], [0.04, 0.062, 0.064, 0.064, 0, 0, 2], [0.07, 0.022, 0.022, 0.022, 0, 0, 2]], 10, sleeve, 2)
	else:
		forearm(gb, look)
	return Sculpt.mesh_with_lods(gb, mats)


## A forearm with its hand and bracer, hanging down -Y from the elbow. Also
## used for the first-person arms.
static func forearm(gb: GeoBuilder, look: Dictionary) -> void:
	var skin: Color = look.get("skin", Color(0.7, 0.5, 0.36))
	Sculpt.loft(gb, &"skin", Transform3D.IDENTITY, [[-0.272, 0.012, 0.012, 0.012, 0, 0, 2], [-0.25, 0.03, 0.026, 0.028, 0, 0, 2],
		[-0.18, 0.037, 0.035, 0.037, 0, 0, 2], [-0.07, 0.049, 0.047, 0.05, 0, 0, 2], [0.0, 0.046, 0.046, 0.047, 0, 0, 2],
		[0.03, 0.02, 0.02, 0.02, 0, 0, 2]], 10, skin, 2)
	hand(gb, skin, Vector3(0.0, -0.3, -0.008))
	if look.get("armor", "none") in ["bronze", "bronze_gold"]:
		Sculpt.loft(gb, &"bronze", Transform3D.IDENTITY, [[-0.235, 0.036, 0.034, 0.036, 0, 0, 2], [-0.225, 0.04, 0.038, 0.04, 0, 0, 2],
			[-0.15, 0.047, 0.045, 0.047, 0, 0, 2], [-0.07, 0.055, 0.053, 0.056, 0, 0, 2], [-0.06, 0.052, 0.05, 0.053, 0, 0, 2]], 10, Color.WHITE, 1)
	else:
		Sculpt.loft(gb, &"hide", Transform3D.IDENTITY, [[-0.235, 0.033, 0.031, 0.033, 0, 0, 2], [-0.225, 0.037, 0.035, 0.037, 0, 0, 2],
			[-0.16, 0.044, 0.042, 0.044, 0, 0, 2], [-0.15, 0.041, 0.039, 0.041, 0, 0, 2]], 10, LEATHER_DARK, 1)


## A hand closed round a shaft that runs along Z through [param at].
static func hand(gb: GeoBuilder, skin: Color, at: Vector3) -> void:
	var fist := func(u: float, v: float) -> Vector3:
		var th := PI * v
		return at + Vector3(sin(th) * cos(u * TAU) * 0.035, sin(th) * sin(u * TAU) * 0.04, -cos(th) * 0.047)
	# The fingers lie side by side along the shaft: mark the gaps between
	# them on the outer half of the fist.
	var fingers := func(u: float, v: float) -> Color:
		var z := -cos(PI * v) * 0.047
		var outer := cos(u * TAU) < 0.2 and sin(u * TAU) < 0.6
		var gap := absf(fposmod(z / 0.0225 + 0.5, 1.0) - 0.5) < 0.1 and absf(z) < 0.04
		return skin.darkened(0.4) if outer and gap else skin
	Sculpt.grid(gb, &"skin", 10, 8, fist, fingers, true, null)
	var thumb := func(u: float, v: float) -> Vector3:
		var th := PI * v
		return at + Vector3(-0.012, 0.03, -0.022) + Vector3(sin(th) * cos(u * TAU) * 0.012, sin(th) * sin(u * TAU) * 0.011, -cos(th) * 0.03)
	Sculpt.grid(gb, &"skin", 6, 4, thumb, skin, true, null)


## Thigh, or shin with foot, sandal and greave.
static func leg(look: Dictionary, upper: bool, mats: Dictionary) -> ArrayMesh:
	var gb := _gb()
	var skin: Color = look["skin"]
	if upper:
		Sculpt.loft(gb, &"skin", Transform3D.IDENTITY, [[-0.465, 0.03, 0.03, 0.03, 0, 0, 2], [-0.43, 0.055, 0.058, 0.055, 0, 0, 2],
			[-0.3, 0.066, 0.072, 0.068, 0, 0, 2], [-0.13, 0.083, 0.092, 0.085, 0, 0, 2], [0.0, 0.085, 0.088, 0.088, 0, 0, 2],
			[0.05, 0.03, 0.03, 0.03, 0, 0, 2]], 12, skin, 2)
		return Sculpt.mesh_with_lods(gb, mats)
	Sculpt.loft(gb, &"skin", Transform3D.IDENTITY, [[-0.44, 0.03, 0.032, 0.032, 0, 0, 2], [-0.39, 0.034, 0.036, 0.036, 0, 0, 2],
		[-0.25, 0.042, 0.041, 0.052, 0, 0, 2], [-0.11, 0.055, 0.05, 0.07, 0, 0, 2], [0.0, 0.054, 0.056, 0.054, 0, 0, 2],
		[0.035, 0.022, 0.022, 0.022, 0, 0, 2]], 10, skin, 2)
	var fwd := Basis(Vector3.RIGHT, -PI * 0.5)
	var foot := PackedVector2Array([Vector2(0.0, -0.072), Vector2(0.034, -0.06), Vector2(0.04, 0.0), Vector2(0.047, 0.1),
		Vector2(0.038, 0.16), Vector2(0.0, 0.178)])
	var toes := func(_u: float, v: float) -> Color:
		return skin.darkened(0.25) if v > 0.86 and fposmod(v * 40.0, 1.0) < 0.3 else skin
	Sculpt.lathe(gb, &"skin", Transform3D(fwd, Vector3(0, -0.452, 0.005)), foot, 10, toes, 0.62, 2)
	var sole := PackedVector2Array([Vector2(0.0, -0.08), Vector2(0.04, -0.066), Vector2(0.046, 0.0), Vector2(0.054, 0.1),
		Vector2(0.044, 0.17), Vector2(0.0, 0.19)])
	Sculpt.lathe(gb, &"hide", Transform3D(fwd, Vector3(0, -0.484, 0.005)), sole, 10, LEATHER_DARK, 0.2, 2)
	# Sandal straps: over the instep and round the ankle.
	Sculpt.lathe_hard(gb, &"hide", Transform3D(fwd, Vector3(0, -0.452, 0.005)), PackedVector2Array([Vector2(0.049, 0.06), Vector2(0.05, 0.072),
		Vector2(0.049, 0.084)]), 10, LEATHER, 0.66)
	_ring(gb, &"hide", 0.037, -0.405, 0.02, LEATHER, 1.0, 10)
	if look["greaves"]:
		# Bronze greaves: the "well-greaved Achaeans".
		Sculpt.loft(gb, &"bronze", Transform3D.IDENTITY, [[-0.385, 0.04, 0.043, 0.042, 0, 0, 2], [-0.37, 0.042, 0.045, 0.044, 0, 0, 2],
			[-0.25, 0.049, 0.05, 0.059, 0, 0, 2], [-0.11, 0.062, 0.059, 0.077, 0, 0, 2], [-0.02, 0.06, 0.066, 0.06, 0, -0.004, 2],
			[0.02, 0.05, 0.062, 0.04, 0, -0.008, 2]], 10, Color.WHITE, 2)
	else:
		_ring(gb, &"hide", 0.041, -0.34, 0.02, LEATHER, 1.0, 10)
	return Sculpt.mesh_with_lods(gb, mats)
