class_name Clutter
extends RefCounted
## The small things that make a town lived in and a plain alive: grass,
## scrub and stones outside the walls; baskets, benches, woodpiles, jars,
## ladders and washing against the houses; stalls and carts in the square.
## Each kind is one mesh drawn many times, so thousands cost little. None of
## it stands in the way: it is set against walls and has no collision.

const STRAW := Color(0.62, 0.56, 0.33)
const OLIVE := Color(0.36, 0.42, 0.22)
const WOOD := Color(0.4, 0.28, 0.17)
const CLAY := Color(0.62, 0.36, 0.22)


static func _gb() -> GeoBuilder:
	var gb := GeoBuilder.new()
	gb.chunk_size = 0.0
	return gb


static func _rand(a: float, b: float) -> float:
	return Sculpt.noise(a, b)


## A tuft of dry grass: a dozen blades leaning out from a point.
static func grass_mesh(col: Color, height: float) -> ArrayMesh:
	var gb := _gb()
	for i in 18:
		var a := TAU * i / 18.0 + _rand(i, 1.0)
		var lean := 0.25 + 0.5 * _rand(i, 2.0)
		var h := height * (0.6 + 0.5 * _rand(i, 3.0))
		var root := Vector3(cos(a), 0.0, sin(a)) * 0.05
		var side := Vector3(-sin(a), 0.0, cos(a)) * 0.016
		var tip := root + Vector3(cos(a) * lean * h, h, sin(a) * lean * h)
		var tone := col.darkened(0.3 * _rand(i, 4.0))
		gb.tri_smooth(&"tint_2s", root - side, root + side, tip, Vector3.UP, Vector3.UP, Vector3.UP,
			tone.darkened(0.35), tone.darkened(0.35), tone.lightened(0.15))
	return gb.build_mesh(Mats.all())


## A low thorny bush.
static func scrub_mesh() -> ArrayMesh:
	var gb := _gb()
	for i in 5:
		var at := Vector3(_rand(i, 5.0) - 0.5, 0.18 + 0.2 * _rand(i, 6.0), _rand(i, 7.0) - 0.5) * Vector3(0.7, 1.0, 0.7)
		var r := 0.22 + 0.16 * _rand(i, 8.0)
		var blob := func(u: float, v: float) -> Vector3:
			var th := PI * v
			var bumpy := 1.0 + 0.25 * sin(u * TAU * 5.0 + i) * sin(th * 4.0)
			return at + Vector3(sin(th) * cos(u * TAU), -cos(th) * 0.75, sin(th) * sin(u * TAU)) * r * bumpy
		var leaf := func(u: float, v: float) -> Color:
			return OLIVE.darkened(0.5 - 0.5 * v).lerp(STRAW, 0.25 * _rand(floorf(u * 8.0), i))
		Sculpt.grid(gb, &"tint", 8, 5, blob, leaf, true, null)
	return gb.build_mesh(Mats.all())


## A field stone.
static func stone_mesh() -> ArrayMesh:
	var gb := _gb()
	var pos := func(u: float, v: float) -> Vector3:
		var th := PI * v
		var lump := 1.0 + 0.2 * sin(u * TAU * 3.0 + 1.0) * sin(th * 2.0) + 0.12 * sin(u * TAU * 5.0)
		return Vector3(sin(th) * cos(u * TAU) * 0.3, -cos(th) * 0.16 + 0.08, sin(th) * sin(u * TAU) * 0.22) * lump
	var tone := func(_u: float, v: float) -> Color:
		return Color(0.56, 0.53, 0.47).darkened(0.35 * (1.0 - v))
	Sculpt.grid(gb, &"tint", 8, 5, pos, tone, true, null)
	return gb.build_mesh(Mats.all())


## A woven basket, some with a lid of fruit or grain showing.
static func basket_mesh(full: bool) -> ArrayMesh:
	var gb := _gb()
	var weave := func(u: float, v: float) -> Color:
		var over := (int(floorf(u * 24.0)) + int(floorf(v * 9.0))) % 2 == 0
		return STRAW.darkened(0.12 if over else 0.4)
	Sculpt.lathe(gb, &"tint", Transform3D.IDENTITY, PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.16, 0.0), Vector2(0.22, 0.14),
		Vector2(0.24, 0.3), Vector2(0.22, 0.34)]), 12, weave, 1.0, 3)
	if full:
		var heap := func(u: float, _v: float) -> Color:
			return Color(0.5, 0.42, 0.16).darkened(0.3 * _rand(floorf(u * 12.0), 9.0))
		Sculpt.lathe(gb, &"tint", Transform3D.IDENTITY, PackedVector2Array([Vector2(0.215, 0.3), Vector2(0.14, 0.37), Vector2(0.0, 0.4)]), 10, heap)
	return gb.build_mesh(Mats.all())


## Two-handled jars, a group of three.
static func amphorae_mesh() -> ArrayMesh:
	var gb := _gb()
	var jar := PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.05, 0.01), Vector2(0.15, 0.2), Vector2(0.17, 0.36), Vector2(0.11, 0.5),
		Vector2(0.055, 0.56), Vector2(0.06, 0.66), Vector2(0.075, 0.68)])
	for i in 3:
		var at := Vector3([0.0, 0.34, 0.15][i], 0.0, [0.0, 0.04, 0.3][i])
		var lean := Basis(Vector3(1, 0, 0.3).normalized(), [0.0, 0.06, -0.3][i])
		var paint := func(_u: float, v: float) -> Color:
			return Color(0.2, 0.1, 0.07) if absf(v - 0.55) < 0.03 or absf(v - 0.75) < 0.02 else CLAY.lightened(0.1 * i)
		Sculpt.lathe(gb, &"tint", Transform3D(lean, at), jar, 10, paint, 1.0, 2)
	return gb.build_mesh(Mats.all())


## A plank on two stones.
static func bench_mesh() -> ArrayMesh:
	var gb := _gb()
	gb.box(&"wood", Transform3D(Basis.IDENTITY, Vector3(0, 0.4, 0)), Vector3(1.5, 0.07, 0.36), Color.WHITE, false, 0)
	for sx: float in [-0.55, 0.55]:
		gb.box(&"rubble", Transform3D(Basis.IDENTITY, Vector3(sx, 0.18, 0)), Vector3(0.3, 0.36, 0.32), Color.WHITE, false, 0)
	return gb.build_mesh(Mats.all())


## Split logs stacked against a wall.
static func woodpile_mesh() -> ArrayMesh:
	var gb := _gb()
	var along := Basis(Vector3(0, 0, 1), PI * 0.5)
	for row in 4:
		for i in 6 - row:
			var r := 0.075 + 0.02 * _rand(row, i)
			var at := Vector3(-0.55, 0.08 + row * 0.15, (i - (5 - row) * 0.5) * 0.17)
			var bark := func(u: float, _v: float) -> Color:
				return WOOD.darkened(0.2 + 0.3 * _rand(floorf(u * 6.0), i + row * 7.0))
			Sculpt.lathe(gb, &"tint", Transform3D(along, at + Vector3(1.1, 0, 0)), PackedVector2Array([Vector2(0.0, 0.0), Vector2(r, 0.0),
				Vector2(r, 1.1), Vector2(0.0, 1.1)]), 6, bark, 1.0, 1)
			var cut := func(u: float, v: float) -> Vector3:
				return at + Vector3(0.0, sin(u * TAU) * r * v, cos(u * TAU) * r * v)
			Sculpt.grid(gb, &"tint", 6, 1, cut, Color(0.72, 0.58, 0.38), true, at + Vector3(1, 0, 0))
	return gb.build_mesh(Mats.all())


## A ladder leaning on a wall behind it (-Z).
static func ladder_mesh() -> ArrayMesh:
	var gb := _gb()
	var lean := Basis(Vector3.RIGHT, 0.24)
	for sx: float in [-0.24, 0.24]:
		gb.box(&"wood", Transform3D(lean, lean * Vector3(sx, 1.6, 0)), Vector3(0.055, 3.2, 0.055), Color.WHITE, false, 0)
	for i in 8:
		gb.box(&"wood", Transform3D(lean, lean * Vector3(0, 0.35 + i * 0.36, 0)), Vector3(0.5, 0.04, 0.04), Color.WHITE, false, 0)
	return gb.build_mesh(Mats.all())


## Washing on a line between two poles.
static func washing_mesh() -> ArrayMesh:
	var gb := _gb()
	for sx: float in [-1.4, 1.4]:
		gb.box(&"wood", Transform3D(Basis.IDENTITY, Vector3(sx, 1.0, 0)), Vector3(0.07, 2.0, 0.07), Color.WHITE, false, 0)
	gb.box(&"tint", Transform3D(Basis.IDENTITY, Vector3(0, 1.9, 0)), Vector3(2.8, 0.015, 0.015), Color(0.3, 0.25, 0.18), false, 0)
	var dyes: Array[Color] = [Color(0.85, 0.82, 0.74), Color(0.55, 0.16, 0.12), Color(0.2, 0.3, 0.5), Color(0.8, 0.62, 0.2)]
	for i in 4:
		var x0 := -1.15 + i * 0.6
		var w := 0.42 + 0.1 * _rand(i, 11.0)
		var drop := 0.7 + 0.5 * _rand(i, 12.0)
		var dye := dyes[i]
		var hang := func(u: float, v: float) -> Vector3:
			return Vector3(x0 + u * w, 1.9 - v * drop, 0.03 * sin(u * 9.0 + i) * v)
		var shade := func(u: float, v: float) -> Color:
			return dye.darkened(0.12 * absf(sin(u * 9.0 + i)) + 0.1 * v)
		Sculpt.grid(gb, &"figure_2s", 4, 3, hang, shade, false, Vector3(0, 1.5, -3))
	return gb.build_mesh(Mats.all())


## A market stall: a trestle under an awning, with jars and baskets on it.
static func stall_mesh(dye: Color) -> ArrayMesh:
	var gb := _gb()
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-0.6, 0.6]:
			gb.box(&"wood", Transform3D(Basis.IDENTITY, Vector3(sx, 1.1, sz)), Vector3(0.07, 2.2, 0.07), Color.WHITE, false, 0)
	gb.box(&"wood", Transform3D(Basis.IDENTITY, Vector3(0, 0.78, 0)), Vector3(2.1, 0.06, 1.0), Color.WHITE, false, 0)
	var roof := func(u: float, v: float) -> Vector3:
		return Vector3(lerpf(-1.25, 1.25, u), 2.2 - 0.3 * v - 0.06 * sin(PI * u), lerpf(-0.75, 0.95, v))
	var stripe := func(u: float, _v: float) -> Color:
		return dye if int(floorf(u * 8.0)) % 2 == 0 else Color(0.84, 0.8, 0.7)
	Sculpt.grid(gb, &"figure_2s", 8, 3, roof, stripe, false, Vector3(0, -5, 0))
	var jar := PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.07, 0.0), Vector2(0.12, 0.12), Vector2(0.1, 0.24), Vector2(0.06, 0.28), Vector2(0.075, 0.31)])
	for i in 5:
		Sculpt.lathe(gb, &"tint", Transform3D(Basis.IDENTITY, Vector3(-0.8 + i * 0.4, 0.81, 0.15 * sin(i * 2.0))), jar, 8,
			CLAY.lerp(Color(0.8, 0.7, 0.5), _rand(i, 13.0)), 1.0, 2)
	var heap := func(u: float, _v: float) -> Color:
		return Color(0.6, 0.3, 0.12).lerp(Color(0.5, 0.5, 0.2), _rand(floorf(u * 10.0), 14.0))
	Sculpt.lathe(gb, &"tint", Transform3D(Basis.IDENTITY, Vector3(0.0, 0.81, -0.28)), PackedVector2Array([Vector2(0.3, 0.0), Vector2(0.2, 0.1),
		Vector2(0.0, 0.14)]), 10, heap)
	return gb.build_mesh(Mats.all())


## A two-wheeled ox cart, its pole resting on the ground.
static func cart_mesh() -> ArrayMesh:
	var gb := _gb()
	gb.box(&"wood", Transform3D(Basis.IDENTITY, Vector3(0, 0.75, 0)), Vector3(1.2, 0.08, 2.0), Color.WHITE, false, 0)
	for sx: float in [-0.6, 0.6]:
		gb.box(&"wood", Transform3D(Basis.IDENTITY, Vector3(sx, 1.0, 0)), Vector3(0.05, 0.45, 2.0), Color.WHITE, false, 0)
		# Solid plank wheels, as on Bronze Age carts.
		Sculpt.lathe_hard(gb, &"hide", Transform3D(Basis(Vector3(0, 0, 1), PI * 0.5), Vector3(sx * 1.2 + 0.04, 0.55, 0.1)),
			PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.55, 0.0), Vector2(0.55, 0.08), Vector2(0.0, 0.08)]), 14, WOOD.darkened(0.2))
	gb.box(&"wood", Transform3D(Basis(Vector3.RIGHT, 0.26), Vector3(0, 0.42, -2.1)), Vector3(0.09, 0.09, 2.6), Color.WHITE, false, 0)
	return gb.build_mesh(Mats.all())


static func _spot(x: float, z: float, yaw: float, scale: float = 1.0) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * scale), TroyLayout.ground(x, z))


## Scatters everything over the world built from [param info].
## [param density] is 1 on a desktop; phones ask for less.
static func place(world: Node3D, info: Dictionary, density: float) -> void:
	var grass: Array[Transform3D] = []
	var green: Array[Transform3D] = []
	var scrub: Array[Transform3D] = []
	var stones: Array[Transform3D] = []
	# The plain: a belt of rough ground round the town, thinning with distance.
	var count := int(20000 * density)
	for i in count:
		var a := _rand(i, 21.0) * TAU
		var out := 1.03 + pow(_rand(i, 22.0), 2.2) * 0.75
		var x := TroyLayout.LOWER_CENTER.x + cos(a) * TroyLayout.LOWER_RX * out + (_rand(i, 23.0) - 0.5) * 30.0
		var z := TroyLayout.LOWER_CENTER.y + sin(a) * TroyLayout.LOWER_RZ * out + (_rand(i, 24.0) - 0.5) * 30.0
		if TroyLayout.in_lower_town(x, z) or TroyLayout.in_citadel(x, z) or _on_road(x, z):
			continue
		var pick := _rand(i, 25.0)
		var xf := _spot(x, z, a * 7.0, 0.7 + 0.8 * _rand(i, 26.0))
		if pick < 0.6:
			grass.append(xf)
		elif pick < 0.88:
			green.append(xf)
		elif pick < 0.96:
			scrub.append(xf)
		else:
			stones.append(xf)
	_scatter(world, grass_mesh(STRAW, 0.45), grass, "GrassDry", 110.0, false)
	_scatter(world, grass_mesh(OLIVE.lerp(STRAW, 0.3), 0.32), green, "GrassGreen", 110.0, false)
	_scatter(world, scrub_mesh(), scrub, "Scrub", 260.0, true)
	_scatter(world, stone_mesh(), stones, "Stones", 160.0, false)

	# Before the houses: a thing or two against each street front, clear of
	# the door; washing hung out on the flat roofs.
	var kinds := {"basket": [], "basket_full": [], "amphorae": [], "bench": [], "woodpile": [], "ladder": [], "washing": [], "weeds": []}
	var houses: Array = info["houses"]
	for i in houses.size():
		var h: Dictionary = houses[i]
		var pos: Vector3 = h["pos"]
		var yaw: float = h["yaw"]
		var basis := Basis(Vector3.UP, yaw)
		var w := float(h["w"])
		var front := float(h["d"]) * 0.5
		var door := float(h.get("door", 0.0))
		for k in 2:
			if _rand(i, 30.0 + k) > 0.75 * density:
				continue
			var kind: String = ["basket", "basket_full", "amphorae", "bench", "woodpile", "ladder", "basket", "amphorae"][int(_rand(i, 36.0 + k) * 8.0) % 8]
			var x := lerpf(-w * 0.42, w * 0.42, _rand(i, 34.0 + k))
			if absf(x - door) < 1.3:
				x = door + signf(x - door + 0.01) * 1.4
				if absf(x) > w * 0.45:
					continue
			# Flat against the wall: what lies along it faces along it.
			var gap := {"bench": 0.25, "woodpile": 0.1, "ladder": 0.55}.get(kind, 0.32) as float
			var at := pos + basis * Vector3(x, 0.0, front + gap)
			var turn := PI * 0.5 if kind in ["bench", "woodpile"] else 0.0
			(kinds[kind] as Array).append(_spot(at.x, at.z, yaw + turn))
		if _rand(i, 38.0) < 0.22 * density:
			var roof := pos + basis * Vector3(0.0, float(h["h"]), 0.0)
			kinds["washing"].append(Transform3D(Basis(Vector3.UP, yaw + _rand(i, 39.0)), roof))
		# Weeds in the angle of wall and street.
		for k in 3:
			var at := pos + basis * Vector3(lerpf(-w * 0.48, w * 0.48, _rand(i, 40.0 + k)), 0.0, front + 0.12)
			if _rand(i, 44.0 + k) < 0.55 * density:
				(kinds["weeds"] as Array).append(_spot(at.x, at.z, _rand(i, k) * TAU, 0.6 + 0.5 * _rand(i, 46.0 + k)))
	var meshes := {"basket": basket_mesh(false), "basket_full": basket_mesh(true), "amphorae": amphorae_mesh(), "bench": bench_mesh(),
		"woodpile": woodpile_mesh(), "ladder": ladder_mesh(), "washing": washing_mesh(), "weeds": grass_mesh(OLIVE, 0.3)}
	for kind: String in kinds:
		var xfs: Array[Transform3D] = []
		xfs.assign(kinds[kind])
		_scatter(world, meshes[kind], xfs, "Clutter_" + kind, 70.0 if kind == "weeds" else 140.0, kind in ["washing", "ladder"])

	# The square before the citadel: a ring of stalls, and carts drawn up.
	var agora: Vector3 = (info["markers"] as Dictionary).get("agora", Vector3.ZERO)
	var dyes: Array[Color] = [Color(0.6, 0.16, 0.12), Color(0.2, 0.3, 0.5), Color(0.75, 0.56, 0.16)]
	for d in dyes.size():
		var stalls: Array[Transform3D] = []
		for i in 3:
			var a := (d * 3 + i) * TAU / 9.0 + 0.35
			# The Scaean Way and the road to the South Gate cross the square: leave them open.
			var x := agora.x + cos(a) * 15.0
			var z := agora.z + sin(a) * 13.0
			if not _on_road(x, z):
				stalls.append(_spot(x, z, -a + PI * 0.5))
		Props._multimesh(world, stall_mesh(dyes[d]), stalls, "Stalls_%d" % d, 200.0)
	var carts: Array[Transform3D] = []
	for i in 3:
		var a := 1.1 + i * 2.1
		var x := agora.x + cos(a) * 20.0
		var z := agora.z + sin(a) * 18.0
		if not _on_road(x, z):
			carts.append(_spot(x, z, a * 2.0))
	Props._multimesh(world, cart_mesh(), carts, "Carts", 200.0)


## Draws [param xforms] as one batch per 64 m tile, each dropped beyond
## [param range_end]: one batch over the whole plain would be "near" from
## anywhere on it and never culled.
static func _scatter(world: Node3D, mesh: Mesh, xforms: Array[Transform3D], node_name: String, range_end: float,
		shadow: bool) -> void:
	var tiles: Dictionary = {}
	for xf in xforms:
		var key := Vector2i(floori(xf.origin.x / 64.0), floori(xf.origin.z / 64.0))
		if not tiles.has(key):
			tiles[key] = [] as Array[Transform3D]
		(tiles[key] as Array[Transform3D]).append(xf)
	for key: Vector2i in tiles:
		var mmi := Props._multimesh(world, mesh, tiles[key], "%s_%d_%d" % [node_name, key.x, key.y], range_end)
		mmi.visibility_range_end_margin = 10.0
		mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


static var _roads: Array = []


## True within a street's width of its centre line.
static func _on_road(x: float, z: float) -> bool:
	if _roads.is_empty():
		_roads = TroyBuilder.street_segments()
	var q := Vector2(x, z)
	for seg: Array in _roads:
		var a: Vector2 = seg[0]
		var ab: Vector2 = (seg[1] as Vector2) - a
		var t := clampf((q - a).dot(ab) / maxf(ab.length_squared(), 0.001), 0.0, 1.0)
		if q.distance_to(a + ab * t) < float(seg[2]) * 0.5 + 0.6:
			return true
	return false
