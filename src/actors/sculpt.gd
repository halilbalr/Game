class_name Sculpt
extends RefCounted
## Smooth surfaces for figures and gear. Every surface is a grid of points
## from a function of (u, v); normals come from the neighbouring points, so
## a shape shades as one rounded form instead of a stack of facets.

## What a surface is made of travels in its vertex colour's alpha, so that
## skin, hair, cloth and leather share one material ("figure") and every
## metal another ("metal"): a figure is then a couple of draw calls a part
## instead of one for each thing it wears. See figure.gdshader, metal.gdshader.
const KIND := {&"skin": 0.95, &"hair": 0.85, &"wool": 0.75, &"hide": 0.65, &"oxhide": 0.55, &"eye": 0.45, &"ivory": 0.35,
	&"tint": 0.25, &"wool_2s": 0.75}
const METAL := {
	&"bronze": [Color(0.83, 0.56, 0.27), 0.95], &"bronze_dull": [Color(0.58, 0.41, 0.22), 0.75],
	&"gold": [Color(1.0, 0.78, 0.32), 0.55], &"silver": [Color(0.85, 0.85, 0.82), 0.35],
	&"bronze_scale": [Color(0.7, 0.48, 0.25), 0.15],
}

## When true, surfaces face toward their reference point instead of away
## from it: the inside of a hollow (a cave, a hull seen from its deck).
static var inward: bool = false

## When true, surfaces are made solid to walk on and into (cave walls).
static var collide: bool = false

## 0.5 to 1: scales how finely surfaces are divided (phones use fewer).
static var detail: float = 1.0


static func _n(count: int) -> int:
	return maxi(int(round(count * detail)), 4)


## Emits the surface pos.call(u, v) -> Vector3 for u, v in 0..1 as an
## [param nu] by [param nv] grid. [param col] is a Color or a
## Callable(u, v) -> Color. With [param wrap_u] the surface closes on itself
## in u. The surface faces away from [param inside] (a point), or from its
## own middle when that is null, which suits any closed, rounded shape.
## [codeblock]
## Sculpt.grid(gb, &"skin", 16, 8, func(u: float, v: float) -> Vector3:
##     return Vector3(cos(u * TAU), v, sin(u * TAU)) * 0.1, Color.WHITE)
## [/codeblock]
static func grid(gb: GeoBuilder, mat: StringName, nu: int, nv: int, pos: Callable, col: Variant,
		wrap_u: bool = true, inside: Variant = null, xform: Transform3D = Transform3D.IDENTITY) -> void:
	var cols := nu + 1
	var rows := nv + 1
	var p := PackedVector3Array()
	p.resize(cols * rows)
	var c := PackedColorArray()
	c.resize(cols * rows)
	var per_vertex := col is Callable
	var flat: Color = Color.WHITE if per_vertex else (col as Color)
	var alpha := 1.0
	var dye := Color.WHITE
	if KIND.has(mat):
		alpha = KIND[mat]
		mat = &"figure_2s" if mat == &"wool_2s" else &"figure"
	elif METAL.has(mat):
		dye = METAL[mat][0]
		alpha = METAL[mat][1]
		mat = &"metal"
	for j in rows:
		var v := float(j) / nv
		for i in cols:
			var u := float(i) / nu
			var k := j * cols + i
			if wrap_u and i == nu:
				p[k] = p[j * cols]
				c[k] = c[j * cols]
			else:
				p[k] = xform * (pos.call(u, v) as Vector3)
				var tone: Color = ((col as Callable).call(u, v) if per_vertex else flat) * dye
				tone.a = alpha
				c[k] = tone
	var n := PackedVector3Array()
	n.resize(cols * rows)
	var weak: Array[int] = []
	for j in rows:
		for i in cols:
			var i0 := i - 1
			var i1 := i + 1
			if wrap_u:
				i0 = posmod(i0, nu)
				i1 = posmod(i1, nu)
			else:
				i0 = maxi(i0, 0)
				i1 = mini(i1, nu)
			var du := p[j * cols + i1] - p[j * cols + i0]
			var dv := p[mini(j + 1, nv) * cols + i] - p[maxi(j - 1, 0) * cols + i]
			var nn := du.cross(dv)
			if nn.length_squared() < 1e-14:
				weak.append(j * cols + i)
			else:
				n[j * cols + i] = nn.normalized()
	# A pole (a row drawn to a point) has no slope of its own: take the
	# average of the row next to it.
	for k in weak:
		var j := k / cols
		var jn := j + 1 if j < nv else j - 1
		if j > 0 and j < nv:
			jn = j + 1 if n[(j + 1) * cols].length_squared() > 0.5 else j - 1
		var sum := Vector3.ZERO
		for i in nu:
			sum += n[jn * cols + i]
		n[k] = sum.normalized() if sum.length_squared() > 1e-10 else Vector3.UP
	var middle := Vector3.ZERO
	if inside is Vector3:
		middle = xform * (inside as Vector3)
	else:
		for q in p:
			middle += q
		middle /= p.size()
	var facing := 0.0
	for k in p.size():
		facing += n[k].dot(p[k] - middle)
	if (facing < 0.0) != inward:
		for k in n.size():
			n[k] = -n[k]
	for j in nv:
		for i in nu:
			var a := j * cols + i
			var b := a + 1
			var d := a + cols
			var e := d + 1
			_tri(gb, mat, p, n, c, a, b, e)
			_tri(gb, mat, p, n, c, a, e, d)


static func _tri(gb: GeoBuilder, mat: StringName, p: PackedVector3Array, n: PackedVector3Array, c: PackedColorArray,
		a: int, b: int, d: int) -> void:
	var g := (p[b] - p[a]).cross(p[d] - p[a])
	if g.length_squared() < 1e-16:
		return
	if g.dot(n[a] + n[b] + n[d]) > 0.0:
		gb.tri_smooth(mat, p[a], p[b], p[d], n[a], n[b], n[d], c[a], c[b], c[d], collide)
	else:
		gb.tri_smooth(mat, p[a], p[d], p[b], n[a], n[d], n[b], c[a], c[d], c[b], collide)


## Catmull-Rom through [param pts] at t in 0..1.
static func spline2(pts: PackedVector2Array, t: float) -> Vector2:
	var last := pts.size() - 1
	var f := clampf(t, 0.0, 1.0) * last
	var i := mini(int(f), last - 1)
	var k := f - i
	var p0 := pts[maxi(i - 1, 0)]
	var p1 := pts[i]
	var p2 := pts[i + 1]
	var p3 := pts[mini(i + 2, last)]
	return 0.5 * ((2.0 * p1) + (-p0 + p2) * k + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * k * k
		+ (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * k * k * k)


## A rounded solid of revolution about +Y: [param profile] is (radius, y)
## from bottom to top, smoothed through its points. [param squash] flattens
## it front to back. [param col] as for [method grid].
static func lathe(gb: GeoBuilder, mat: StringName, xform: Transform3D, profile: PackedVector2Array, segs: int,
		col: Variant, squash: float = 1.0, rings_per_point: int = 3, inside: Variant = null) -> void:
	var nv := maxi((profile.size() - 1) * rings_per_point, 2)
	var pos := func(u: float, v: float) -> Vector3:
		var q := spline2(profile, v)
		var r := maxf(q.x, 0.0)
		return Vector3(cos(u * TAU) * r, q.y, sin(u * TAU) * r * squash)
	grid(gb, mat, _n(segs), nv, pos, col, true, inside, xform)


## Like [method lathe] but with straight sides between the profile points:
## for rims, bands and anything with a made edge.
static func lathe_hard(gb: GeoBuilder, mat: StringName, xform: Transform3D, profile: PackedVector2Array, segs: int,
		col: Color = Color.WHITE, squash: float = 1.0, inside: Variant = null) -> void:
	for j in profile.size() - 1:
		var a := profile[j]
		var b := profile[j + 1]
		var pos := func(u: float, v: float) -> Vector3:
			var q := a.lerp(b, v)
			return Vector3(cos(u * TAU) * q.x, q.y, sin(u * TAU) * q.x * squash)
		grid(gb, mat, _n(segs), 1, pos, col, true, inside, xform)


## A limb or trunk: cross-sections strung along +Y and smoothed between.
## Each ring is [y, half_width, depth_front, depth_back, centre_x, centre_z,
## squareness]; squareness 2 is an ellipse, higher is boxier. Front is -Z.
static func loft(gb: GeoBuilder, mat: StringName, xform: Transform3D, rings: Array, segs: int, col: Variant,
		rings_per_point: int = 3) -> void:
	var last := rings.size() - 1
	var nv := last * rings_per_point
	var pos := func(u: float, v: float) -> Vector3:
		return loft_point(rings, u, v)
	grid(gb, mat, _n(segs), nv, pos, col, true, null, xform)


## The point of a [method loft] surface at (u, v); u = 0.25 is the front.
static func loft_point(rings: Array, u: float, v: float) -> Vector3:
	var last := rings.size() - 1
	var f := clampf(v, 0.0, 1.0) * last
	var i := mini(int(f), last - 1)
	var k := f - i
	var r0: Array = rings[maxi(i - 1, 0)]
	var r1: Array = rings[i]
	var r2: Array = rings[i + 1]
	var r3: Array = rings[mini(i + 2, last)]
	var q: Array[float] = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
	for m in 7:
		var a: float = r0[m]
		var b: float = r1[m]
		var c: float = r2[m]
		var d: float = r3[m]
		q[m] = 0.5 * ((2.0 * b) + (-a + c) * k + (2.0 * a - 5.0 * b + 4.0 * c - d) * k * k
			+ (-a + 3.0 * b - 3.0 * c + d) * k * k * k)
	var cs := cos(u * TAU)
	var sn := sin(u * TAU)
	var e := 2.0 / maxf(q[6], 1.0)
	var x := signf(cs) * pow(absf(cs), e) * maxf(q[1], 0.0)
	# sin > 0 is the back (+Z), sin < 0 the front.
	var z := signf(sn) * pow(absf(sn), e) * maxf(q[3] if sn > 0.0 else q[2], 0.0)
	return Vector3(q[4] + x, q[0], q[5] + z)


## A falling-off bump: 1 where unit vector [param d] meets [param toward],
## fading over [param width] (about the sine of the half-angle).
static func bump(d: Vector3, toward: Vector3, width: float) -> float:
	return exp(-(1.0 - d.dot(toward)) / (width * width))


## Cheap repeatable noise in 0..1 for breaking up hair and cloth.
static func noise(a: float, b: float) -> float:
	var s := sin(a * 127.1 + b * 311.7) * 43758.5453
	return s - floorf(s)


## Turns a builder's triangles into a mesh that carries simpler versions of
## itself, which the renderer swaps in as the figure gets small on screen: a
## man across the field costs a fraction of one at arm's length.
static func mesh_with_lods(gb: GeoBuilder, mats: Dictionary) -> ArrayMesh:
	var plain := gb.build_mesh(mats)
	var importer := ImporterMesh.new()
	for i in plain.get_surface_count():
		var st := SurfaceTool.new()
		st.create_from(plain, i)
		st.index()
		importer.add_surface(Mesh.PRIMITIVE_TRIANGLES, st.commit_to_arrays(), [], {}, plain.surface_get_material(i))
	importer.generate_lods(30.0, 60.0, [])
	return importer.get_mesh()
