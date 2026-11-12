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
			# Ash shaft.
			gb.cylinder(&"tint", Vector3(0, 0, butt), 0.0155, 0.014, length, 8, WOOD, false, false, fwd)
			# Leaf-shaped bronze head on a socket.
			var tip_z := butt - length
			gb.cylinder(&"bronze", Vector3(0, 0, tip_z + 0.06), 0.02, 0.016, 0.1, 8, Color.WHITE, false, false, fwd)
			var head := PackedVector2Array([Vector2(0.012, 0.0), Vector2(0.036, 0.07), Vector2(0.03, 0.16),
				Vector2(0.012, 0.27), Vector2(0.0, 0.31)])
			gb.lathe(&"bronze", Transform3D(fwd, Vector3(0, 0, tip_z - 0.02)), head, 8, Color.WHITE, false, 0.22)
			# Butt spike, the sauroter.
			var spike := PackedVector2Array([Vector2(0.0, -0.13), Vector2(0.014, -0.02), Vector2(0.017, 0.0)])
			gb.lathe(&"bronze", Transform3D(fwd, Vector3(0, 0, butt)), spike, 6)
			if kind == "spear_long":
				# The ring of gold that held Hector's spearhead (Iliad 6.320).
				gb.cylinder(&"gold", Vector3(0, 0, tip_z + 0.11), 0.022, 0.022, 0.035, 8, Color.WHITE, false, false, fwd)
		"sword", "dagger":
			var blade := 0.62 if kind == "sword" else 0.27
			var width := 0.03 if kind == "sword" else 0.022
			# Naue II: parallel-edged blade swelling slightly toward the point.
			var prof := PackedVector2Array([Vector2(width * 0.85, 0.0), Vector2(width * 0.8, blade * 0.5),
				Vector2(width, blade * 0.74), Vector2(width * 0.55, blade * 0.92), Vector2(0.0, blade)])
			# Rolled a quarter turn so the edge, not the flat, faces down.
			var edge := Basis(Vector3(0, 0, 1), PI * 0.5) * fwd
			gb.lathe(&"bronze", Transform3D(edge, Vector3(0, 0, -0.05)), prof, 6, Color.WHITE, false, 0.16)
			gb.box(&"bronze", Transform3D(Basis.IDENTITY, Vector3(0, 0, -0.045)), Vector3(0.085, 0.022, 0.02), Color.WHITE, false, 0)
			gb.cylinder(&"tint", Vector3(0, 0, 0.065), 0.016, 0.015, 0.11, 8, GRIP, false, false, fwd)
			# Silver studs on the hilt: Homer's "silver-studded sword".
			for z: float in [-0.02, 0.025]:
				gb.box(&"silver", Transform3D(Basis.IDENTITY, Vector3(0, 0, z)), Vector3(0.037, 0.012, 0.012), Color.WHITE, false, 0)
			var pommel := PackedVector2Array([Vector2(0.0, -0.022), Vector2(0.022, -0.01), Vector2(0.024, 0.006), Vector2(0.0, 0.02)])
			gb.lathe(&"ivory", Transform3D(fwd, Vector3(0, 0, 0.075)), pommel, 8)
	var mesh := gb.build_mesh(mats)
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
			# Layered ox-hide, gently domed.
			var dome := PackedVector2Array([Vector2(r, 0.0), Vector2(r * 0.72, r * 0.07), Vector2(r * 0.36, r * 0.13),
				Vector2(0.0, r * 0.15)])
			gb.lathe(&"hide", xf, dome, 18, hide)
			var rim := PackedVector2Array([Vector2(r * 0.94, -0.012), Vector2(r + 0.014, -0.004), Vector2(r + 0.014, 0.012),
				Vector2(r * 0.93, 0.03)])
			gb.lathe(&"bronze", xf, rim, 18)
			# Bronze boss.
			var boss := PackedVector2Array([Vector2(r * 0.24, r * 0.135), Vector2(r * 0.2, r * 0.2), Vector2(r * 0.1, r * 0.255),
				Vector2(0.0, r * 0.27)])
			gb.lathe(&"bronze", xf, boss, 12)
			if kind == "round_great":
				for ring: float in [0.48, 0.78]:
					var band := PackedVector2Array([Vector2(r * ring - 0.02, r * (0.14 - ring * 0.09)),
						Vector2(r * ring, r * (0.155 - ring * 0.09)), Vector2(r * ring + 0.02, r * (0.14 - ring * 0.09) - 0.004)])
					gb.lathe(&"bronze", xf, band, 18)
			# Back face and arm strap.
			var back: Array[Vector3] = []
			for i in 14:
				var a := TAU * i / 14.0
				back.append(Vector3(cos(a) * r * 0.97, sin(a) * r * 0.97, 0.005))
			gb.poly(&"hide", back, Vector3(0, 0, 1), hide.darkened(0.45), false)
			gb.box(&"hide", Transform3D(Basis.IDENTITY, Vector3(0, 0, 0.03)), Vector3(0.05, 0.3, 0.03), GRIP, false, 0)
		"tower":
			# The sakos: a tall body shield of hide on a curved frame.
			var h := 1.28
			var w := 0.66
			var strips := 6
			for i in strips:
				var a0 := lerpf(-0.75, 0.75, float(i) / strips)
				var a1 := lerpf(-0.75, 0.75, float(i + 1) / strips)
				var rad := w * 0.5 / sin(0.75)
				var p0 := Vector3(sin(a0) * rad, 0, -cos(a0) * rad + rad * cos(0.75))
				var p1 := Vector3(sin(a1) * rad, 0, -cos(a1) * rad + rad * cos(0.75))
				var up := Vector3(0, h * 0.5, 0)
				var shade := hide if i % 2 == 0 else hide.darkened(0.12)
				gb.quad_h(&"hide", p0 - up, p1 - up, p1 + up, p0 + up, Vector3(0, 0, -1), shade, false)
				gb.quad_h(&"hide", p0 - up, p1 - up, p1 + up, p0 + up, Vector3(0, 0, 1), hide.darkened(0.45), false)
				gb.box(&"bronze", Transform3D(Basis.IDENTITY, (p0 + p1) * 0.5 + up), Vector3(p0.distance_to(p1) + 0.01, 0.035, 0.03),
					Color.WHITE, false, 0)
				gb.box(&"bronze", Transform3D(Basis.IDENTITY, (p0 + p1) * 0.5 - up), Vector3(p0.distance_to(p1) + 0.01, 0.035, 0.03),
					Color.WHITE, false, 0)
			var boss2 := PackedVector2Array([Vector2(0.09, 0.0), Vector2(0.07, 0.04), Vector2(0.0, 0.06)])
			gb.lathe(&"bronze", Transform3D(fwd, Vector3(0, 0.12, -0.115)), boss2, 10)
	var mesh := gb.build_mesh(mats)
	_cache[key] = mesh
	return mesh


## Drops cached meshes (their materials belong to a finished session).
static func reset() -> void:
	_cache.clear()
