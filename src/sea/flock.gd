class_name Flock
extends RefCounted
## The Cyclops's sheep and rams: thick-fleeced, dark-faced, the rams heavy
## and curl-horned (Odyssey 9.425-436). One mesh each, shared.

static var _cache: Dictionary = {}


## A sheep facing -Z, standing on y 0. [param ram] adds horns and bulk.
static func sheep_mesh(ram: bool) -> ArrayMesh:
	var key := "ram" if ram else "ewe"
	if _cache.has(key):
		return _cache[key]
	var gb := GeoBuilder.new()
	gb.chunk_size = 0.0
	var size := 1.25 if ram else 1.0
	var wool := Color(0.82, 0.78, 0.68) if not ram else Color(0.62, 0.55, 0.45)
	var fleece := func(u: float, v: float) -> Vector3:
		var th := PI * v
		var lumpy := 1.0 + 0.07 * sin(u * TAU * 9.0) * sin(th * 7.0)
		return Vector3(sin(th) * cos(u * TAU) * 0.36, 0.72 + sin(th) * sin(u * TAU) * 0.34, -cos(th) * 0.62) * lumpy * size
	var curl := func(u: float, v: float) -> Color:
		return wool.darkened(0.15 * Sculpt.noise(floorf(u * 18.0), floorf(v * 12.0)))
	Sculpt.grid(gb, &"wool", 14, 10, fleece, curl, true, null)
	var dark := Color(0.16, 0.13, 0.11)
	var face := func(u: float, v: float) -> Vector3:
		var th := PI * v
		return Vector3(0.0, 0.92, -0.72) * size + Vector3(sin(th) * cos(u * TAU) * 0.12, sin(th) * sin(u * TAU) * 0.14, -cos(th) * 0.24) * size
	Sculpt.grid(gb, &"skin", 10, 6, face, dark, true, null)
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			var leg := Vector3(sx * 0.18, 0.0, sz * 0.36) * size
			Sculpt.lathe(gb, &"skin", Transform3D(Basis.IDENTITY, leg), PackedVector2Array([Vector2(0.035, 0.0), Vector2(0.03, 0.25),
				Vector2(0.045, 0.5), Vector2(0.0, 0.56)]), 6, dark, 1.0, 1)
		var ear := Vector3(sx * 0.12, 0.98, -0.62) * size
		Sculpt.lathe(gb, &"skin", Transform3D(Basis(Vector3(0, 0, 1), sx * 1.2), ear), PackedVector2Array([Vector2(0.03, 0.0), Vector2(0.03, 0.1),
			Vector2(0.0, 0.13)]), 5, dark, 0.4, 1)
		if ram:
			# A horn curling back and round beside the face.
			var horn := func(u: float, v: float) -> Vector3:
				var a := v * 4.4
				var r := 0.11 * (1.0 - v * 0.55)
				var c := Vector3(sx * (0.13 + 0.03 * v), 1.06 + sin(a) * 0.12 * (1.0 - v * 0.3), -0.66 + (1.0 - cos(a)) * 0.1) * size
				return c + Vector3(sx * cos(u * TAU) * r * 0.35, sin(u * TAU) * r * 0.35, 0.0)
			Sculpt.grid(gb, &"ivory", 6, 10, horn, Color(0.7, 0.62, 0.48), true, null)
	var mesh := gb.build_mesh(Mats.all())
	_cache[key] = mesh
	return mesh


## Puts a sheep at [param at] facing [param yaw]; returns its node.
static func place(parent: Node3D, at: Vector3, yaw: float, ram: bool) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = sheep_mesh(ram)
	parent.add_child(mi)
	mi.global_position = at
	mi.rotation.y = yaw
	return mi
