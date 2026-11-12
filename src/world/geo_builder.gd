class_name GeoBuilder
extends RefCounted
## Accumulates flat-shaded triangles per material and bakes them into meshes
## plus static collision, split into square chunks so the renderer can cull.
##
## All architecture in the game is generated through this class. Faces are
## given counter-clockwise as seen from outside; the builder emits Godot's
## clockwise front-face order and the outward normal. Texturing needs no UVs:
## the shaders derive metric coordinates from world position and normal.

## Edge length of a culling chunk in metres. 0 disables chunking.
var chunk_size: float = 96.0

var _surfaces: Dictionary = {}
var _collision: Dictionary = {}


class Surf:
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var c := PackedColorArray()


func _chunk_key(p: Vector3) -> Vector2i:
	if chunk_size <= 0.0:
		return Vector2i.ZERO
	return Vector2i(floori(p.x / chunk_size), floori(p.z / chunk_size))


func _surf(chunk: Vector2i, mat: StringName) -> Surf:
	var key := [chunk, mat]
	var s: Surf = _surfaces.get(key)
	if s == null:
		s = Surf.new()
		_surfaces[key] = s
	return s


func _col(chunk: Vector2i) -> PackedVector3Array:
	if not _collision.has(chunk):
		_collision[chunk] = PackedVector3Array()
	return _collision[chunk]


## Adds one triangle (counter-clockwise from outside), flat shaded.
func tri(mat: StringName, a: Vector3, b: Vector3, c: Vector3, col: Color = Color.WHITE,
		collide: bool = true) -> void:
	var nrm := (b - a).cross(c - a)
	if nrm.length_squared() < 1e-12:
		return
	nrm = nrm.normalized()
	var chunk := _chunk_key((a + b + c) / 3.0)
	var s := _surf(chunk, mat)
	s.v.append(a); s.v.append(c); s.v.append(b)
	s.n.append(nrm); s.n.append(nrm); s.n.append(nrm)
	s.c.append(col); s.c.append(col); s.c.append(col)
	if collide:
		var faces := _col(chunk)
		faces.append(a); faces.append(c); faces.append(b)
		_collision[chunk] = faces


## Adds one triangle with explicit per-vertex normals and colours (smooth shading).
func tri_smooth(mat: StringName, a: Vector3, b: Vector3, c: Vector3, na: Vector3, nb: Vector3,
		nc: Vector3, ca: Color, cb: Color, cc: Color, collide: bool = false) -> void:
	var chunk := _chunk_key((a + b + c) / 3.0)
	var s := _surf(chunk, mat)
	s.v.append(a); s.v.append(c); s.v.append(b)
	s.n.append(na); s.n.append(nc); s.n.append(nb)
	s.c.append(ca); s.c.append(cc); s.c.append(cb)
	if collide:
		var faces := _col(chunk)
		faces.append(a); faces.append(c); faces.append(b)
		_collision[chunk] = faces


## Adds a quad a-b-c-d (counter-clockwise from outside). Colours may differ
## between the bottom edge (a, b) and the top edge (c, d).
func quad(mat: StringName, a: Vector3, b: Vector3, c: Vector3, d: Vector3,
		col: Color = Color.WHITE, collide: bool = true, col_top: Variant = null) -> void:
	var top: Color = col if col_top == null else col_top
	var nrm := (b - a).cross(d - a)
	if nrm.length_squared() < 1e-12:
		nrm = (c - b).cross(d - b)
		if nrm.length_squared() < 1e-12:
			return
	nrm = nrm.normalized()
	var chunk := _chunk_key((a + b + c + d) * 0.25)
	var s := _surf(chunk, mat)
	s.v.append(a); s.v.append(c); s.v.append(b)
	s.v.append(a); s.v.append(d); s.v.append(c)
	for i in 6:
		s.n.append(nrm)
	s.c.append(col); s.c.append(top); s.c.append(col)
	s.c.append(col); s.c.append(top); s.c.append(top)
	if collide:
		var faces := _col(chunk)
		faces.append(a); faces.append(c); faces.append(b)
		faces.append(a); faces.append(d); faces.append(c)
		_collision[chunk] = faces


## Like [method quad], but the facing is taken from [param hint] rather than
## from the vertex order. [param a] and [param b] are the bottom edge,
## [param c] and [param d] the top edge (c above b, d above a).
func quad_h(mat: StringName, a: Vector3, b: Vector3, c: Vector3, d: Vector3, hint: Vector3,
		col: Color = Color.WHITE, collide: bool = true, col_top: Variant = null) -> void:
	var nrm := (b - a).cross(d - a)
	if nrm.length_squared() < 1e-12:
		nrm = (c - b).cross(d - b)
	if nrm.dot(hint) >= 0.0:
		quad(mat, a, b, c, d, col, collide, col_top)
	else:
		quad(mat, b, a, d, c, col, collide, col_top)


## A convex polygon facing [param hint], triangulated as a fan.
func poly(mat: StringName, pts: Array[Vector3], hint: Vector3, col: Color = Color.WHITE,
		collide: bool = true) -> void:
	if pts.size() < 3:
		return
	var nrm := (pts[1] - pts[0]).cross(pts[2] - pts[0])
	var flip := nrm.dot(hint) < 0.0
	for i in range(1, pts.size() - 1):
		if flip:
			tri(mat, pts[0], pts[i + 1], pts[i], col, collide)
		else:
			tri(mat, pts[0], pts[i], pts[i + 1], col, collide)



## Adds a box. [param xform] places the box centre; [param size] is full extents.
## [param skip] is a bit mask of faces to omit: 1 +X, 2 -X, 4 +Y, 8 -Y, 16 +Z, 32 -Z.
func box(mat: StringName, xform: Transform3D, size: Vector3, col: Color = Color.WHITE,
		collide: bool = true, skip: int = 8, col_top: Variant = null) -> void:
	var h := size * 0.5
	var p: Array[Vector3] = [
		xform * Vector3(-h.x, -h.y, -h.z), xform * Vector3(h.x, -h.y, -h.z),
		xform * Vector3(h.x, -h.y, h.z), xform * Vector3(-h.x, -h.y, h.z),
		xform * Vector3(-h.x, h.y, -h.z), xform * Vector3(h.x, h.y, -h.z),
		xform * Vector3(h.x, h.y, h.z), xform * Vector3(-h.x, h.y, h.z),
	]
	var top: Color = col if col_top == null else col_top
	if skip & 1 == 0:
		quad(mat, p[2], p[1], p[5], p[6], col, collide, top)
	if skip & 2 == 0:
		quad(mat, p[0], p[3], p[7], p[4], col, collide, top)
	if skip & 4 == 0:
		quad(mat, p[7], p[6], p[5], p[4], top, collide, top)
	if skip & 8 == 0:
		quad(mat, p[0], p[1], p[2], p[3], col, collide, col)
	if skip & 16 == 0:
		quad(mat, p[3], p[2], p[6], p[7], col, collide, top)
	if skip & 32 == 0:
		quad(mat, p[1], p[0], p[4], p[5], col, collide, top)


## Axis-aligned box given by its minimum corner and size, optionally rotated
## about the vertical axis through [param pivot].
func block(mat: StringName, min_corner: Vector3, size: Vector3, col: Color = Color.WHITE,
		yaw: float = 0.0, pivot: Vector3 = Vector3.ZERO, collide: bool = true, skip: int = 8,
		col_top: Variant = null) -> void:
	var center := min_corner + size * 0.5
	var xf := Transform3D(Basis.IDENTITY, center)
	if yaw != 0.0:
		var rot := Basis(Vector3.UP, yaw)
		xf = Transform3D(rot, pivot + rot * (center - pivot))
	box(mat, xf, size, col, collide, skip, col_top)


## A box whose top rectangle differs from its base: battered walls, plinths.
## Sizes are full widths on local X and Z.
func frustum(mat: StringName, xform: Transform3D, base: Vector2, top: Vector2, h: float,
		col: Color = Color.WHITE, collide: bool = true, cap_top: bool = true,
		col_top: Variant = null) -> void:
	var b := base * 0.5
	var t := top * 0.5
	var ct: Color = col if col_top == null else col_top
	var p: Array[Vector3] = [
		xform * Vector3(-b.x, 0, -b.y), xform * Vector3(b.x, 0, -b.y),
		xform * Vector3(b.x, 0, b.y), xform * Vector3(-b.x, 0, b.y),
		xform * Vector3(-t.x, h, -t.y), xform * Vector3(t.x, h, -t.y),
		xform * Vector3(t.x, h, t.y), xform * Vector3(-t.x, h, t.y),
	]
	quad(mat, p[2], p[1], p[5], p[6], col, collide, ct)
	quad(mat, p[0], p[3], p[7], p[4], col, collide, ct)
	quad(mat, p[3], p[2], p[6], p[7], col, collide, ct)
	quad(mat, p[1], p[0], p[4], p[5], col, collide, ct)
	if cap_top:
		quad(mat, p[7], p[6], p[5], p[4], ct, collide, ct)


## Extrudes a plan polygon between two heights. [param pts] holds (x, z)
## pairs in either winding; the builder corrects the facing itself.
func prism(mat: StringName, pts: PackedVector2Array, y0: float, y1: float,
		col: Color = Color.WHITE, collide: bool = true, cap_top: bool = true,
		cap_mat: StringName = &"", col_top: Variant = null) -> void:
	var n := pts.size()
	if n < 3:
		return
	var area := 0.0
	for i in n:
		var p := pts[i]
		var q := pts[(i + 1) % n]
		area += p.x * q.y - q.x * p.y
	# In plan (x, z) a positive shoelace area means clockwise seen from above.
	var ordered := pts.duplicate()
	if area < 0.0:
		ordered.reverse()
	var ct: Color = col if col_top == null else col_top
	for i in n:
		var p := ordered[i]
		var q := ordered[(i + 1) % n]
		quad(mat, Vector3(q.x, y0, q.y), Vector3(p.x, y0, p.y), Vector3(p.x, y1, p.y),
			Vector3(q.x, y1, q.y), col, collide, ct)
	if cap_top:
		var m := mat if cap_mat == &"" else cap_mat
		var idx := Geometry2D.triangulate_polygon(ordered)
		for i in range(0, idx.size(), 3):
			var a := ordered[idx[i]]
			var b := ordered[idx[i + 1]]
			var c := ordered[idx[i + 2]]
			var va := Vector3(a.x, y1, a.y)
			var vb := Vector3(b.x, y1, b.y)
			var vc := Vector3(c.x, y1, c.y)
			if (vb - va).cross(vc - va).y > 0.0:
				tri(m, va, vb, vc, ct, collide)
			else:
				tri(m, va, vc, vb, ct, collide)


## A tapered cylinder standing on [param base]. Smooth sides, flat caps.
func cylinder(mat: StringName, base: Vector3, r0: float, r1: float, h: float, segs: int = 12,
		col: Color = Color.WHITE, collide: bool = false, cap_top: bool = true,
		axis: Basis = Basis.IDENTITY) -> void:
	var slope := (r0 - r1) / maxf(h, 0.001)
	for i in segs:
		var a0 := TAU * float(i) / segs
		var a1 := TAU * float(i + 1) / segs
		var d0 := Vector3(cos(a0), 0, sin(a0))
		var d1 := Vector3(cos(a1), 0, sin(a1))
		var p0 := base + axis * (d0 * r0)
		var p1 := base + axis * (d1 * r0)
		var p2 := base + axis * (d1 * r1 + Vector3(0, h, 0))
		var p3 := base + axis * (d0 * r1 + Vector3(0, h, 0))
		var n0 := (axis * (d0 + Vector3(0, slope, 0))).normalized()
		var n1 := (axis * (d1 + Vector3(0, slope, 0))).normalized()
		# Seen from outside with +Y up, increasing angle runs to the left.
		tri_smooth(mat, p1, p0, p3, n1, n0, n0, col, col, col, collide)
		tri_smooth(mat, p1, p3, p2, n1, n0, n1, col, col, col, collide)
		if cap_top and r1 > 0.001:
			var top := base + axis * Vector3(0, h, 0)
			tri(mat, top, p2, p3, col, collide)


## Surface of revolution about the local Y axis. [param profile] holds
## (radius, height) pairs from bottom to top.
func lathe(mat: StringName, xform: Transform3D, profile: PackedVector2Array, segs: int = 12,
		col: Color = Color.WHITE, collide: bool = false, squash: float = 1.0) -> void:
	for j in profile.size() - 1:
		var a := profile[j]
		var b := profile[j + 1]
		var dr := a.x - b.x
		var dy := b.y - a.y
		for i in segs:
			var a0 := TAU * float(i) / segs
			var a1 := TAU * float(i + 1) / segs
			var d0 := Vector3(cos(a0), 0, sin(a0) * squash)
			var d1 := Vector3(cos(a1), 0, sin(a1) * squash)
			var p0 := xform * (d0 * a.x + Vector3(0, a.y, 0))
			var p1 := xform * (d1 * a.x + Vector3(0, a.y, 0))
			var p2 := xform * (d1 * b.x + Vector3(0, b.y, 0))
			var p3 := xform * (d0 * b.x + Vector3(0, b.y, 0))
			var n0 := (xform.basis * Vector3(cos(a0) * dy, dr, sin(a0) * dy / squash)).normalized()
			var n1 := (xform.basis * Vector3(cos(a1) * dy, dr, sin(a1) * dy / squash)).normalized()
			if a.x > 0.0005:
				tri_smooth(mat, p1, p0, p3, n1, n0, n0, col, col, col, collide)
			if b.x > 0.0005:
				tri_smooth(mat, p1, p3, p2, n1, n0, n1, col, col, col, collide)


## A flight of steps rising along local +Z from the transform origin.
func stairs(mat: StringName, xform: Transform3D, width: float, rise: float, run: float,
		steps: int, col: Color = Color.WHITE) -> void:
	var step_h := rise / steps
	var step_d := run / steps
	for i in steps:
		var hgt := step_h * (i + 1)
		box(mat, xform * Transform3D(Basis.IDENTITY, Vector3(0, hgt * 0.5, step_d * (i + 0.5))),
			Vector3(width, hgt, step_d), col, false, 8)
	# One smooth ramp carries the collision so bodies do not snag on each tread.
	var a := xform * Vector3(-width * 0.5, 0, 0)
	var b := xform * Vector3(width * 0.5, 0, 0)
	var c := xform * Vector3(width * 0.5, rise, run)
	var d := xform * Vector3(-width * 0.5, rise, run)
	var faces := _col(_chunk_key((a + c) * 0.5))
	faces.append(a); faces.append(b); faces.append(c)
	faces.append(a); faces.append(c); faces.append(d)
	_collision[_chunk_key((a + c) * 0.5)] = faces


## Total triangle count currently held (for diagnostics and tests).
func triangle_count() -> int:
	var total := 0
	for s: Surf in _surfaces.values():
		total += s.v.size() / 3
	return total


## Bakes one ArrayMesh from everything added so far (ignores chunking).
## Used for props and characters that are instanced many times.
func build_mesh(materials: Dictionary) -> ArrayMesh:
	var merged: Dictionary = {}
	for key: Array in _surfaces:
		var mat: StringName = key[1]
		var src: Surf = _surfaces[key]
		var dst: Surf = merged.get(mat)
		if dst == null:
			merged[mat] = src
		else:
			dst.v.append_array(src.v)
			dst.n.append_array(src.n)
			dst.c.append_array(src.c)
	var mesh := ArrayMesh.new()
	for mat: StringName in merged:
		_add_surface(mesh, merged[mat], materials.get(mat))
	return mesh


static func _add_surface(mesh: ArrayMesh, s: Surf, material: Material) -> void:
	if s.v.is_empty():
		return
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = s.v
	arrays[Mesh.ARRAY_NORMAL] = s.n
	arrays[Mesh.ARRAY_COLOR] = s.c
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	if material != null:
		mesh.surface_set_material(mesh.get_surface_count() - 1, material)


## Bakes chunk meshes and static collision under [param parent].
func commit(parent: Node3D, materials: Dictionary, cast_shadows: bool = true,
		collision_layer: int = 1) -> void:
	var by_chunk: Dictionary = {}
	for key: Array in _surfaces:
		var chunk: Vector2i = key[0]
		if not by_chunk.has(chunk):
			by_chunk[chunk] = []
		by_chunk[chunk].append(key)
	for chunk: Vector2i in by_chunk:
		var mesh := ArrayMesh.new()
		for key: Array in by_chunk[chunk]:
			_add_surface(mesh, _surfaces[key], materials.get(key[1]))
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.name = "chunk_%d_%d" % [chunk.x, chunk.y]
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if cast_shadows \
			else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.gi_mode = GeometryInstance3D.GI_MODE_STATIC
		parent.add_child(mi)
	for chunk: Vector2i in _collision:
		var faces: PackedVector3Array = _collision[chunk]
		if faces.is_empty():
			continue
		var body := StaticBody3D.new()
		body.name = "col_%d_%d" % [chunk.x, chunk.y]
		body.collision_layer = collision_layer
		body.collision_mask = 0
		var shape := ConcavePolygonShape3D.new()
		shape.backface_collision = true
		shape.set_faces(faces)
		var cs := CollisionShape3D.new()
		cs.shape = shape
		body.add_child(cs)
		parent.add_child(body)
	_surfaces.clear()
	_collision.clear()
