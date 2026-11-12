extends TestCase
## GeoBuilder: winding, facing and counts of generated geometry.

const UNIT := Vector3(2.0, 2.0, 2.0)


func _builder() -> GeoBuilder:
	var gb := GeoBuilder.new()
	gb.chunk_size = 0.0
	return gb


func _outward(mesh: ArrayMesh, centre: Vector3) -> bool:
	# Every normal should point away from the centre of a convex solid.
	var arrays := mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var norms: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	for i in verts.size():
		if (verts[i] - centre).dot(norms[i]) <= 0.0:
			return false
	return true


func test_box_without_its_base_has_ten_triangles() -> void:
	var gb := _builder()
	gb.box(&"m", Transform3D.IDENTITY, UNIT)
	eq(gb.triangle_count(), 10)


func test_box_with_all_faces_has_twelve_triangles() -> void:
	var gb := _builder()
	gb.box(&"m", Transform3D.IDENTITY, UNIT, Color.WHITE, true, 0)
	eq(gb.triangle_count(), 12)


func test_box_normals_point_outward() -> void:
	var gb := _builder()
	gb.box(&"m", Transform3D.IDENTITY, UNIT, Color.WHITE, true, 0)
	check(_outward(gb.build_mesh({}), Vector3.ZERO))


func test_box_front_faces_are_clockwise_for_godot() -> void:
	var gb := _builder()
	gb.box(&"m", Transform3D.IDENTITY, UNIT, Color.WHITE, true, 0)
	var arrays := gb.build_mesh({}).surface_get_arrays(0)
	var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var n: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	for i in range(0, v.size(), 3):
		# Clockwise seen from outside means (c - a) x (b - a) points along the normal.
		var winding := (v[i + 2] - v[i]).cross(v[i + 1] - v[i])
		check(winding.dot(n[i]) > 0.0, "triangle %d" % (i / 3))


func test_prism_faces_outward_whichever_way_its_outline_is_wound() -> void:
	var square := PackedVector2Array([Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)])
	var reversed := square.duplicate()
	reversed.reverse()
	for outline: PackedVector2Array in [square, reversed]:
		var gb := _builder()
		gb.prism(&"m", outline, 0.0, 2.0)
		check(_outward(gb.build_mesh({}), Vector3(0, 1, 0)))
		eq(gb.triangle_count(), 10, "four sides and a cap")


func test_quad_h_faces_the_hint() -> void:
	var a := Vector3(0, 0, 0)
	var b := Vector3(1, 0, 0)
	var c := Vector3(1, 1, 0)
	var d := Vector3(0, 1, 0)
	for hint: Vector3 in [Vector3(0, 0, 1), Vector3(0, 0, -1)]:
		var gb := _builder()
		gb.quad_h(&"m", a, b, c, d, hint)
		var n: PackedVector3Array = gb.build_mesh({}).surface_get_arrays(0)[Mesh.ARRAY_NORMAL]
		check(n[0].dot(hint) > 0.99, "hint %s" % str(hint))


func test_degenerate_triangle_is_dropped() -> void:
	var gb := _builder()
	gb.tri(&"m", Vector3.ZERO, Vector3.ZERO, Vector3(1, 0, 0))
	eq(gb.triangle_count(), 0)


func test_surfaces_are_split_by_material() -> void:
	var gb := _builder()
	gb.box(&"stone", Transform3D.IDENTITY, UNIT)
	gb.box(&"wood", Transform3D(Basis.IDENTITY, Vector3(5, 0, 0)), UNIT)
	eq(gb.build_mesh({}).get_surface_count(), 2)


func test_commit_makes_one_mesh_and_one_body_per_chunk() -> void:
	var gb := GeoBuilder.new()
	gb.chunk_size = 10.0
	gb.box(&"m", Transform3D(Basis.IDENTITY, Vector3(2, 0, 2)), UNIT)
	gb.box(&"m", Transform3D(Basis.IDENTITY, Vector3(42, 0, 2)), UNIT)
	var parent := Node3D.new()
	gb.commit(parent, {})
	var meshes := 0
	var bodies := 0
	for child in parent.get_children():
		if child is MeshInstance3D:
			meshes += 1
		elif child is StaticBody3D:
			bodies += 1
	eq(meshes, 2)
	eq(bodies, 2)
	parent.free()
