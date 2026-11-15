class_name Gear
extends RefCounted
## Mesh builders for Late Bronze Age arms: spears, swords, daggers and shields.
## Weapons lie along local -Z with the grip at the origin; shields face -Z.
## [param mats] maps material names to materials so the same shapes serve
## both world figures and the first-person view model.

const WOOD := Color(0.42, 0.29, 0.16)
const GRIP := Color(0.16, 0.10, 0.07)

static var _cache: Dictionary = {}


static func _new_builder() -> GeoBuilder:
	var gb := GeoBuilder.new()
	gb.chunk_size = 0.0
	return gb


## Basis whose local +Y points along world -Z: turns an upright lathe into a
## forward-pointing one.
static func _forward_basis() -> Basis:
	return Basis(Vector3.RIGHT, -PI * 0.5)


## A weapon mesh by id ("spear", "spear_long", "sword", "dagger").
static func weapon_mesh(kind: String, mats: Dictionary, cache_key: String = "world") -> ArrayMesh:
	var key := "w:%s:%s" % [kind, cache_key]
	if _cache.has(key):
		return _cache[key]
	var gb := _new_builder()
	var fwd := _forward_basis()
	match kind:
		"spear", "spear_long":
			var length := 2.9 if kind == "spear_long" else 2.3
			var butt := 0.85
			var tip_z := butt - length
			# Ash shaft, a little thicker at the grip, with the grain running along it.
			var grain := func(u: float, v: float) -> Color:
				return WOOD.darkened(0.25 * Sculpt.noise(floorf(u * 9.0), floorf(v * 5.0)))
			Sculpt.lathe(gb, &"hide", Transform3D(fwd, Vector3(0, 0, butt)), PackedVector2Array([Vector2(0.0135, 0.0), Vector2(0.016, length * 0.3),
				Vector2(0.0155, length * 0.6), Vector2(0.0135, length)]), 8, grain, 1.0, 4)
			# Leaf-shaped bronze head with a midrib, on a socket.
			Sculpt.lathe_hard(gb, &"bronze", Transform3D(fwd, Vector3(0, 0, tip_z + 0.07)), PackedVector2Array([Vector2(0.0205, 0.0),
				Vector2(0.0185, 0.012), Vector2(0.015, 0.11)]), 8)
			var leaf := PackedVector2Array([Vector2(0.011, 0.0), Vector2(0.036, 0.075), Vector2(0.031, 0.16), Vector2(0.013, 0.27), Vector2(0.0, 0.315)])
			Sculpt.lathe(gb, &"bronze", Transform3D(fwd, Vector3(0, 0, tip_z - 0.02)), leaf, 10, Color.WHITE, 0.16)
			Sculpt.lathe(gb, &"bronze", Transform3D(fwd, Vector3(0, 0, tip_z - 0.02)), PackedVector2Array([Vector2(0.011, 0.0),
				Vector2(0.008, 0.15), Vector2(0.0, 0.3)]), 6, Color.WHITE, 1.0, 1)
			# Butt spike, the sauroter.
			Sculpt.lathe(gb, &"bronze", Transform3D(fwd, Vector3(0, 0, butt)), PackedVector2Array([Vector2(0.0, -0.14), Vector2(0.012, -0.04),
				Vector2(0.017, 0.0), Vector2(0.015, 0.03)]), 8, Color.WHITE, 1.0, 2)
			if kind == "spear_long":
				# The ring of gold that held Hector's spearhead (Iliad 6.320).
				Sculpt.lathe_hard(gb, &"gold", Transform3D(fwd, Vector3(0, 0, tip_z + 0.1)), PackedVector2Array([Vector2(0.019, 0.0),
					Vector2(0.023, 0.012), Vector2(0.023, 0.03), Vector2(0.019, 0.04)]), 8)
		"sword", "dagger":
			var blade := 0.62 if kind == "sword" else 0.27
			var width := 0.03 if kind == "sword" else 0.022
			# Naue II: parallel-edged blade swelling slightly toward the
			# point. Rolled a quarter turn so the edge, not the flat, faces down.
			var edge := Basis(Vector3(0, 0, 1), PI * 0.5) * fwd
			var prof := PackedVector2Array([Vector2(width * 0.85, 0.0), Vector2(width * 0.8, blade * 0.45), Vector2(width, blade * 0.74),
				Vector2(width * 0.6, blade * 0.92), Vector2(0.0, blade)])
			Sculpt.lathe(gb, &"bronze", Transform3D(edge, Vector3(0, 0, -0.05)), prof, 10, Color.WHITE, 0.13)
			Sculpt.lathe(gb, &"bronze", Transform3D(edge, Vector3(0, 0, -0.05)), PackedVector2Array([Vector2(0.007, 0.0),
				Vector2(0.006, blade * 0.6), Vector2(0.0, blade * 0.9)]), 6, Color.WHITE, 1.0, 1)
			# Flanged hilt with grip plates and silver studs: Homer's "silver-studded sword".
			Sculpt.lathe(gb, &"bronze", Transform3D(Basis(Vector3(0, 0, 1), PI * 0.5), Vector3(0, 0, -0.045)), PackedVector2Array([Vector2(0.0, -0.046),
				Vector2(0.011, -0.04), Vector2(0.013, 0.0), Vector2(0.011, 0.04), Vector2(0.0, 0.046)]), 8, Color.WHITE, 0.9, 2)
			Sculpt.lathe(gb, &"hide", Transform3D(fwd, Vector3(0, 0, 0.07)), PackedVector2Array([Vector2(0.013, 0.0), Vector2(0.0165, 0.03),
				Vector2(0.0155, 0.075), Vector2(0.013, 0.115)]), 8, GRIP, 0.8, 2)
			for z: float in [-0.015, 0.02]:
				for sx: float in [-1.0, 1.0]:
					Sculpt.lathe(gb, &"silver", Transform3D(Basis(Vector3(0, 0, 1), -sx * PI * 0.5), Vector3(sx * 0.0125, 0, z)),
						PackedVector2Array([Vector2(0.006, 0.0), Vector2(0.004, 0.003), Vector2(0.0, 0.004)]), 6, Color.WHITE, 1.0, 1)
			Sculpt.lathe(gb, &"ivory", Transform3D(fwd, Vector3(0, 0, 0.078)), PackedVector2Array([Vector2(0.0, -0.024), Vector2(0.021, -0.012),
				Vector2(0.025, 0.004), Vector2(0.0, 0.02)]), 10, Color.WHITE)
	var mesh := Sculpt.mesh_with_lods(gb, mats)
	_cache[key] = mesh
	return mesh


## A shield mesh by id ("round", "round_great", "tower", "crescent").
static func shield_mesh(kind: String, hide: Color, mats: Dictionary, cache_key: String = "world") -> ArrayMesh:
	var key := "s:%s:%s:%s" % [kind, hide.to_html(false), cache_key]
	if _cache.has(key):
		return _cache[key]
	var gb := _new_builder()
	var fwd := _forward_basis()
	var xf := Transform3D(fwd, Vector3.ZERO)
	match kind:
		"round", "round_great", "crescent":
			var r := 0.44
			if kind == "round_great":
				r = 0.58
			elif kind == "crescent":
				r = 0.37
			# Layers of ox-hide with the hair left on, gently domed, stitched in rings.
			var dome := PackedVector2Array([Vector2(r, 0.0), Vector2(r * 0.72, r * 0.075), Vector2(r * 0.36, r * 0.135), Vector2(0.0, r * 0.155)])
			var stitched := func(_u: float, v: float) -> Color:
				return hide.darkened(0.35) if absf(fposmod(v * 3.0 + 0.5, 1.0) - 0.5) < 0.035 and v < 0.8 else hide
			# A flat dome has no clear "middle" to face away from: say where behind is.
			var behind := Vector3(0, -1, 0)
			Sculpt.lathe(gb, &"oxhide", xf, dome, 30, stitched, 1.0, 4, behind)
			Sculpt.lathe_hard(gb, &"bronze", xf, PackedVector2Array([Vector2(r * 0.945, 0.024), Vector2(r + 0.006, 0.014), Vector2(r + 0.016, 0.0),
				Vector2(r + 0.006, -0.014), Vector2(r * 0.95, -0.016)]), 30)
			Sculpt.lathe(gb, &"bronze", xf, PackedVector2Array([Vector2(r * 0.27, r * 0.125), Vector2(r * 0.22, r * 0.15), Vector2(r * 0.2, r * 0.2),
				Vector2(r * 0.1, r * 0.262), Vector2(0.0, r * 0.285)]), 16, Color.WHITE)
			# Rivets holding the rim.
			for i in 12:
				var a := TAU * i / 12.0
				Sculpt.lathe(gb, &"bronze_dull", Transform3D(fwd, Vector3(cos(a) * r * 0.975, sin(a) * r * 0.975, -0.016)),
					PackedVector2Array([Vector2(0.011, 0.0), Vector2(0.008, 0.005), Vector2(0.0, 0.007)]), 6, Color.WHITE, 1.0, 1)
			if kind == "round_great":
				for ring: float in [0.48, 0.78]:
					var y := r * (0.15 - ring * ring * 0.11)
					Sculpt.lathe_hard(gb, &"bronze", xf, PackedVector2Array([Vector2(r * ring - 0.022, y - 0.002), Vector2(r * ring, y + 0.009),
						Vector2(r * ring + 0.022, y - 0.01)]), 30)
			# Back: bare hide, an arm band and a hand grip.
			Sculpt.lathe_hard(gb, &"hide", Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3.ZERO), PackedVector2Array([Vector2(r * 0.96, -0.004),
				Vector2(0.001, -0.02)]), 20, hide.darkened(0.5), 1.0, Vector3(0, -1, 0))
			gb.box(&"hide", Transform3D(Basis.IDENTITY, Vector3(0.0, 0, 0.03)), Vector3(0.05, 0.3, 0.03), GRIP, false, 0)
		"tower":
			# The sakos: a tall body shield of hide on a curved frame, its top arched.
			var h := 1.28
			var w := 0.66
			var rad := w * 0.5 / sin(0.75)
			var face := func(u: float, v: float) -> Vector3:
				var a := lerpf(-0.75, 0.75, u)
				var arch := 0.1 * cos(a * 2.0) * smoothstep(0.75, 1.0, v)
				return Vector3(sin(a) * rad, (v - 0.5) * h + arch, -cos(a) * rad + rad * cos(0.75))
			var seams := func(u: float, v: float) -> Color:
				var seam := absf(fposmod(u * 3.0 + 0.5, 1.0) - 0.5) < 0.03 or absf(v - 0.5) < 0.012
				return hide.darkened(0.4) if seam else hide
			Sculpt.grid(gb, &"oxhide", 14, 14, face, seams, false, Vector3(0, 0, 1.0))
			Sculpt.grid(gb, &"hide", 8, 4, face, hide.darkened(0.5), false, Vector3(0, 0, -3.0))
			for edge: float in [0.0, 1.0]:
				var band := func(u: float, v: float) -> Vector3:
					var q: Vector3 = face.call(u, lerpf(edge, 1.0 - edge, v * 0.035) if edge < 0.5 else 1.0 - v * 0.035)
					return q + Vector3(0, 0, -0.008)
				Sculpt.grid(gb, &"bronze", 14, 1, band, Color.WHITE, false, Vector3(0, 0, 1.0))
			for side: float in [0.0, 1.0]:
				var strip := func(u: float, v: float) -> Vector3:
					var q: Vector3 = face.call(lerpf(side, 1.0 - side, u * 0.04) if side < 0.5 else 1.0 - u * 0.04, v)
					return q + Vector3(0, 0, -0.008)
				Sculpt.grid(gb, &"bronze", 1, 14, strip, Color.WHITE, false, Vector3(0, 0, 1.0))
			Sculpt.lathe(gb, &"bronze", Transform3D(fwd, Vector3(0, 0.12, -0.115)), PackedVector2Array([Vector2(0.1, 0.0), Vector2(0.08, 0.03),
				Vector2(0.04, 0.062), Vector2(0.0, 0.07)]), 14, Color.WHITE)
	var mesh := Sculpt.mesh_with_lods(gb, mats)
	_cache[key] = mesh
	return mesh


## Drops cached meshes (their materials belong to a finished session).
static func reset() -> void:
	_cache.clear()
