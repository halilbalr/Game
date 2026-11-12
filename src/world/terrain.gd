class_name Terrain
extends RefCounted
## Builds the ground of the Troad from [TroyLayout.height]: a fine walkable
## grid around the city, a coarse apron to the horizon, the sea and the river.

## Extent of the fine, collidable grid (min x, min z, max x, max z).
const FINE := Rect2(-660.0, -264.0, 1080.0, 792.0)
const CELL := 3.0
const FAR_EXTENT := 5200.0
const FAR_CELL := 80.0


## Ground blend weights at a point: R packed earth, G grass, B rock.
static func blend_at(x: float, z: float) -> Color:
	var in_town := TroyLayout.lower_r(x, z) < 1.03 or TroyLayout.citadel_r(x, z) < 1.12
	if in_town:
		return Color(1.0, 0.0, 0.0, 1.0)
	var dirt := 0.0
	# Trampled apron outside the walls and the roads leaving each gate.
	var apron := 1.0 - TroyLayout._smooth(1.03, 1.14, TroyLayout.lower_r(x, z))
	dirt = maxf(dirt, apron * 0.8)
	var p := Vector2(x, z)
	for road: Array in _roads():
		var d := _seg_dist(p, road[0], road[1])
		dirt = maxf(dirt, 1.0 - TroyLayout._smooth(road[2] * 0.5, road[2] * 0.5 + 5.0, d))
	# The battlefield before the Scaean Gate is worn bare in patches.
	if _oak == Vector2.ZERO:
		_oak = TroyLayout.places()["oak"]
	var field := 1.0 - TroyLayout._smooth(40.0, 150.0, p.distance_to(_oak))
	dirt = maxf(dirt, field * (0.25 + 0.5 * TroyLayout.noise(x * 0.05, z * 0.05)))
	return Color(dirt, 1.0 - dirt, 0.0, 1.0)


static var _road_cache: Array = []
static var _oak := Vector2.ZERO


static func _roads() -> Array:
	if _road_cache.is_empty():
		var pl := TroyLayout.places()
		var scaean: Vector2 = pl["scaean_gate"]
		var sn := TroyLayout.lower_normal(TroyLayout.SCAEAN_GATE_DEG)
		var dardan: Vector2 = pl["dardanian_gate"]
		var dn := TroyLayout.lower_normal(TroyLayout.DARDANIAN_GATE_DEG)
		var springs: Vector2 = pl["springs"]
		var out := scaean + sn * 120.0
		_road_cache = [
			[scaean, out, 9.0],
			[out, springs, 6.0],
			[springs, Vector2(-520.0, -40.0), 6.0],
			[out, Vector2(-470.0, 240.0), 5.0],
			[dardan, dardan + dn * 220.0, 7.0],
		]
	return _road_cache


static func _seg_dist(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
	return p.distance_to(a + ab * t)


## Builds terrain, sea and river under [param parent].
static func build(parent: Node3D) -> void:
	_build_fine(parent)
	_build_far(parent)
	_build_water(parent)


static func _build_fine(parent: Node3D) -> void:
	var nx := int(FINE.size.x / CELL) + 1
	var nz := int(FINE.size.y / CELL) + 1
	# Heights are sampled once on a grid one cell wider than the mesh, so the
	# normals come from neighbours instead of four more height() calls each.
	var gx := nx + 2
	var gz := nz + 2
	var heights := PackedFloat32Array()
	heights.resize(gx * gz)
	for j in gz:
		var z := FINE.position.y + (j - 1) * CELL
		for i in gx:
			heights[j * gx + i] = TroyLayout.height(FINE.position.x + (i - 1) * CELL, z)
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	verts.resize(nx * nz)
	norms.resize(nx * nz)
	cols.resize(nx * nz)
	for j in nz:
		var z := FINE.position.y + j * CELL
		for i in nx:
			var x := FINE.position.x + i * CELL
			var k := j * nx + i
			var hk := (j + 1) * gx + (i + 1)
			verts[k] = Vector3(x, heights[hk], z)
			norms[k] = Vector3(heights[hk - 1] - heights[hk + 1], 2.0 * CELL,
				heights[hk - gx] - heights[hk + gx]).normalized()
			cols[k] = blend_at(x, z)
	var idx := PackedInt32Array()
	idx.resize((nx - 1) * (nz - 1) * 6)
	var faces := PackedVector3Array()
	faces.resize((nx - 1) * (nz - 1) * 6)
	var w := 0
	for j in nz - 1:
		for i in nx - 1:
			var a := j * nx + i
			var b := a + 1
			var c := a + nx
			var d := c + 1
			# Clockwise seen from above (+Y), Godot's front face.
			idx[w] = a; idx[w + 1] = b; idx[w + 2] = c
			idx[w + 3] = b; idx[w + 4] = d; idx[w + 5] = c
			faces[w] = verts[a]; faces[w + 1] = verts[b]; faces[w + 2] = verts[c]
			faces[w + 3] = verts[b]; faces[w + 4] = verts[d]; faces[w + 5] = verts[c]
			w += 6
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, Mats.get_mat(&"ground"))
	var mi := MeshInstance3D.new()
	mi.name = "TerrainFine"
	mi.mesh = mesh
	mi.gi_mode = GeometryInstance3D.GI_MODE_STATIC
	parent.add_child(mi)

	var body := StaticBody3D.new()
	body.name = "TerrainBody"
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := ConcavePolygonShape3D.new()
	shape.backface_collision = true
	shape.set_faces(faces)
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)
	parent.add_child(body)


static func _build_far(parent: Node3D) -> void:
	var n := int(FAR_EXTENT * 2.0 / FAR_CELL) + 1
	var heights := PackedFloat32Array()
	heights.resize(n * n)
	var skirt := FINE.grow(FAR_CELL)
	for j in n:
		var z := -FAR_EXTENT + j * FAR_CELL
		for i in n:
			var x := -FAR_EXTENT + i * FAR_CELL
			var y := TroyLayout.height(x, z)
			# Sink the coarse skirt slightly so it never pokes through the fine grid.
			if skirt.has_point(Vector2(x, z)):
				y -= 0.6
			heights[j * n + i] = y
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	verts.resize(n * n)
	norms.resize(n * n)
	cols.resize(n * n)
	for j in n:
		for i in n:
			var k := j * n + i
			verts[k] = Vector3(-FAR_EXTENT + i * FAR_CELL, heights[k], -FAR_EXTENT + j * FAR_CELL)
			var l := heights[k - 1] if i > 0 else heights[k]
			var r := heights[k + 1] if i < n - 1 else heights[k]
			var u := heights[k - n] if j > 0 else heights[k]
			var d := heights[k + n] if j < n - 1 else heights[k]
			norms[k] = Vector3(l - r, 2.0 * FAR_CELL, u - d).normalized()
			cols[k] = Color(0.1, 0.9, 0.0, 1.0)
	var idx := PackedInt32Array()
	var inner := FINE.grow(-FAR_CELL)
	for j in n - 1:
		for i in n - 1:
			var x0 := -FAR_EXTENT + i * FAR_CELL
			var z0 := -FAR_EXTENT + j * FAR_CELL
			# Skip cells wholly under the fine grid.
			if inner.has_point(Vector2(x0, z0)) and inner.has_point(Vector2(x0 + FAR_CELL, z0 + FAR_CELL)):
				continue
			var a := j * n + i
			idx.append(a); idx.append(a + 1); idx.append(a + n)
			idx.append(a + 1); idx.append(a + n + 1); idx.append(a + n)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, Mats.get_mat(&"ground"))
	var mi := MeshInstance3D.new()
	mi.name = "TerrainFar"
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)


static func _build_water(parent: Node3D) -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(FAR_EXTENT * 2.4, FAR_EXTENT * 2.4)
	plane.subdivide_width = 1
	plane.subdivide_depth = 1
	var sea := MeshInstance3D.new()
	sea.name = "Sea"
	sea.mesh = plane
	sea.material_override = Mats.get_mat(&"water")
	sea.position = Vector3(0.0, TroyLayout.SEA_Y, 0.0)
	sea.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(sea)
