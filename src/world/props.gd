class_name Props
extends RefCounted
## Dressing for the city: trees, storage jars, awnings, torches and hearth
## fires. Repeated objects are drawn with MultiMesh.

const TREE_KINDS := {
	# trunk height, trunk radius, crown radius, crown height offset, leaf colour, blobs
	"olive": {"trunk": 2.0, "radius": 0.28, "crown": 2.3, "leaf": Color(0.36, 0.42, 0.30), "blobs": 6, "leaf_size": 1.1, "squash": 0.75},
	"oak": {"trunk": 3.4, "radius": 0.5, "crown": 4.6, "leaf": Color(0.17, 0.27, 0.10), "blobs": 9, "leaf_size": 1.7, "squash": 0.8},
	"fig": {"trunk": 1.3, "radius": 0.2, "crown": 2.1, "leaf": Color(0.24, 0.38, 0.14), "blobs": 5, "leaf_size": 1.3, "squash": 0.7},
	"tamarisk": {"trunk": 1.0, "radius": 0.12, "crown": 1.6, "leaf": Color(0.38, 0.45, 0.36), "blobs": 5, "leaf_size": 0.9, "squash": 1.1},
}

static var _leaf_material: StandardMaterial3D


static func _leaf_texture() -> ImageTexture:
	var size := 128
	var img := Image.create(size, size, true, Image.FORMAT_RGBA8)
	img.fill(Color(1, 1, 1, 0))
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	for i in 46:
		var c := Vector2(rng.randf_range(10, size - 10), rng.randf_range(10, size - 10))
		var ang := rng.randf() * TAU
		var len := rng.randf_range(9.0, 15.0)
		var wid := len * rng.randf_range(0.3, 0.45)
		var shade := rng.randf_range(0.62, 1.0)
		var dir := Vector2(cos(ang), sin(ang))
		var perp := dir.orthogonal()
		for y in range(int(c.y - len), int(c.y + len) + 1):
			for x in range(int(c.x - len), int(c.x + len) + 1):
				if x < 0 or y < 0 or x >= size or y >= size:
					continue
				var p := Vector2(x, y) - c
				var u := p.dot(dir) / len
				var v := p.dot(perp) / wid
				if u * u + v * v < 1.0:
					var rib := 1.0 - 0.25 * absf(v)
					img.set_pixel(x, y, Color(shade * rib, shade * rib, shade * rib, 1.0))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


static func leaf_material() -> StandardMaterial3D:
	if _leaf_material == null:
		var m := StandardMaterial3D.new()
		m.albedo_texture = _leaf_texture()
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		m.alpha_scissor_threshold = 0.4
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.vertex_color_use_as_albedo = true
		m.roughness = 0.75
		m.backlight_enabled = true
		m.backlight = Color(0.35, 0.42, 0.15)
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		_leaf_material = m
	return _leaf_material


## Builds one tree mesh: bent trunk, a few limbs, and a crown of leaf cards
## whose normals point away from the crown centre so it shades as a volume.
static func tree_mesh(kind: String, seed_value: int) -> ArrayMesh:
	var k: Dictionary = TREE_KINDS[kind]
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var gb := GeoBuilder.new()
	gb.chunk_size = 0.0
	var bark := Color(0.9, 0.85, 0.78) if kind == "olive" else Color.WHITE
	var trunk_h: float = k["trunk"]
	var r: float = k["radius"]
	var crown: float = k["crown"]
	# Trunk in three leaning sections.
	var p := Vector3.ZERO
	var lean := Vector3(rng.randf_range(-0.2, 0.2), 1.0, rng.randf_range(-0.2, 0.2)).normalized()
	var limbs: Array[Vector3] = []
	for i in 3:
		var seg_h := trunk_h / 3.0
		var up := lean
		var side := up.cross(Vector3.RIGHT).normalized()
		var basis := Basis(side.cross(up).normalized(), up, side)
		gb.cylinder(&"wood", p, r * (1.0 - i * 0.2), r * (1.0 - (i + 1) * 0.2), seg_h * 1.04, 8, bark, false, false, basis)
		p += up * seg_h
		lean = (lean + Vector3(rng.randf_range(-0.25, 0.25), 0.3, rng.randf_range(-0.25, 0.25))).normalized()
	var top := p
	# Limbs reaching into the crown.
	for i in 4:
		var ang := TAU * i / 4.0 + rng.randf_range(-0.4, 0.4)
		var dir := Vector3(cos(ang), rng.randf_range(0.5, 0.9), sin(ang)).normalized()
		var side := dir.cross(Vector3.UP).normalized()
		var basis := Basis(side.cross(dir).normalized(), dir, side)
		var length := crown * rng.randf_range(0.6, 0.9)
		gb.cylinder(&"wood", top - dir * 0.2, r * 0.42, r * 0.12, length, 6, bark, false, false, basis)
		limbs.append(top + dir * length)
	# Crown.
	var leaf: Color = k["leaf"]
	var centre := top + Vector3(0, crown * 0.45, 0)
	var squash: float = k["squash"]
	var blobs: int = k["blobs"]
	var leaf_size: float = k["leaf_size"]
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	var cols := PackedColorArray()
	for bi in blobs:
		var bc := centre
		if bi < limbs.size():
			bc = limbs[bi]
		else:
			bc = centre + Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.4, 0.8) * squash, rng.randf_range(-1, 1)) * crown * 0.55
		var br := crown * rng.randf_range(0.42, 0.62)
		for qi in 13:
			var d := Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1) * squash, rng.randf_range(-1, 1))
			if d.length() < 0.05:
				continue
			d = d.normalized() * br * rng.randf_range(0.45, 1.0)
			var qc := bc + d
			var nrm := (qc - centre).normalized()
			var ax := Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)).normalized()
			var u := ax.cross(nrm)
			if u.length() < 0.1:
				u = Vector3.RIGHT
			u = u.normalized()
			var v := u.cross(ax.lerp(nrm, 0.5).normalized()).normalized()
			var s := leaf_size * rng.randf_range(0.75, 1.25)
			var shade := rng.randf_range(0.75, 1.15) * (0.8 + 0.3 * clampf((qc.y - centre.y) / crown + 0.5, 0.0, 1.0))
			var col := Color(leaf.r * shade, leaf.g * shade, leaf.b * shade)
			var corners: Array[Vector3] = [qc - u * s - v * s, qc + u * s - v * s, qc + u * s + v * s, qc - u * s + v * s]
			var cuv: Array[Vector2] = [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)]
			for idx: int in [0, 1, 2, 0, 2, 3]:
				verts.append(corners[idx])
				norms.append(nrm)
				uvs.append(cuv[idx])
				cols.append(col)
	var mesh := gb.build_mesh(Mats.all_local())
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_COLOR] = cols
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(mesh.get_surface_count() - 1, leaf_material())
	return mesh


## A pithos: the shoulder-high storage jar found sunk into Troy VIIa floors.
static func pithos_mesh() -> ArrayMesh:
	var gb := GeoBuilder.new()
	gb.chunk_size = 0.0
	var profile := PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.16, 0.0), Vector2(0.30, 0.22),
		Vector2(0.40, 0.55), Vector2(0.42, 0.80), Vector2(0.36, 1.02), Vector2(0.25, 1.14),
		Vector2(0.24, 1.22), Vector2(0.30, 1.27), Vector2(0.27, 1.29), Vector2(0.20, 1.24)])
	gb.lathe(&"tint", Transform3D.IDENTITY, profile, 14, Color(0.62, 0.36, 0.22))
	# Rope-pattern bands.
	for y: float in [0.5, 0.86]:
		gb.cylinder(&"tint", Vector3(0, y, 0), 0.425, 0.425, 0.035, 14, Color(0.52, 0.30, 0.18), false, false)
	return gb.build_mesh(Mats.all())


static func _multimesh(parent: Node3D, mesh: Mesh, xforms: Array[Transform3D], node_name: String,
		range_end: float = 0.0) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = node_name
	mmi.multimesh = mm
	if range_end > 0.0:
		mmi.visibility_range_end = range_end
	parent.add_child(mmi)
	return mmi


## Adds awnings and stalls to the static builder (call before commit).
static func build_awnings(b: GeoBuilder, info: Dictionary) -> void:
	var dyes: Array[Color] = [Color(0.62, 0.16, 0.10), Color(0.80, 0.70, 0.50), Color(0.72, 0.52, 0.16),
		Color(0.20, 0.28, 0.42), Color(0.84, 0.80, 0.70)]
	for a: Dictionary in info["awnings"]:
		var xf: Transform3D = a["xf"]
		var w: float = a["w"]
		var col := dyes[int((a["hue"] as float) * dyes.size()) % dyes.size()]
		var depth := 2.2
		var back_y := 2.7
		var front_y := 2.15
		var stall: bool = a.get("stall", false)
		if stall:
			back_y = 2.6
			for sx: float in [-1.0, 1.0]:
				b.cylinder(&"wood", xf * Vector3(sx * w * 0.5, 0, 0), 0.05, 0.045, back_y, 6)
		for sx: float in [-1.0, 1.0]:
			b.cylinder(&"wood", xf * Vector3(sx * w * 0.5, 0, depth), 0.05, 0.045, front_y, 6)
		var c0 := Color(col.r, col.g, col.b, 0.0)
		var c1 := Color(col.r, col.g, col.b, 1.0)
		# Two strips so the cloth sags in the middle.
		var mid_y := (back_y + front_y) * 0.5 - 0.14
		b.quad_h(&"cloth_sway", xf * Vector3(-w * 0.5, back_y, 0.02), xf * Vector3(w * 0.5, back_y, 0.02),
			xf * Vector3(w * 0.5, mid_y, depth * 0.5), xf * Vector3(-w * 0.5, mid_y, depth * 0.5), Vector3.UP, c0, false, c1)
		b.quad_h(&"cloth_sway", xf * Vector3(-w * 0.5, mid_y, depth * 0.5), xf * Vector3(w * 0.5, mid_y, depth * 0.5),
			xf * Vector3(w * 0.5, front_y, depth), xf * Vector3(-w * 0.5, front_y, depth), Vector3.UP, c1, false, c0)
		if stall:
			b.box(&"wood", xf.translated_local(Vector3(0, 0.82, depth * 0.5)), Vector3(w * 0.9, 0.08, 1.1), Color.WHITE, true, 0)
			for sx: float in [-1.0, 1.0]:
				b.box(&"wood", xf.translated_local(Vector3(sx * w * 0.4, 0.4, depth * 0.5)), Vector3(0.1, 0.8, 1.0), Color.WHITE, false, 8)
			info["pithoi"].append(xf * Vector3(w * 0.5 + 0.6, 0.0, depth * 0.4))


## Adds the wooden torch posts along the streets (call before commit).
static func build_torch_posts(b: GeoBuilder, info: Dictionary) -> void:
	for p: Vector3 in info.get("torch_posts", []):
		b.cylinder(&"wood_dark", p - Vector3(0, 0.3, 0), 0.07, 0.055, 2.5, 6)
		b.cylinder(&"bronze_dull", p + Vector3(0, 2.12, 0), 0.09, 0.15, 0.2, 8)


## Places instanced props and, at night, the fires. Returns the list of fires.
static func place(world: Node3D, info: Dictionary, night: bool, quality: int) -> Array[Fire]:
	var by_kind: Dictionary = {}
	for t: Dictionary in info["trees"]:
		var kind: String = t["kind"]
		var variant := "%s_%d" % [kind, absi(int((t["pos"] as Vector3).x * 7.0)) % 3]
		if not by_kind.has(variant):
			by_kind[variant] = []
		var s: float = t["scale"]
		var basis := Basis(Vector3.UP, (t["pos"] as Vector3).x * 1.7).scaled(Vector3(s, s, s))
		by_kind[variant].append(Transform3D(basis, (t["pos"] as Vector3) - Vector3(0, 0.15, 0)))
	for variant: String in by_kind:
		var kind := variant.get_slice("_", 0)
		var xfs: Array[Transform3D] = []
		xfs.assign(by_kind[variant])
		_multimesh(world, tree_mesh(kind, variant.hash()), xfs, "Trees_" + variant)

	var jars: Array[Transform3D] = []
	for i in (info["pithoi"] as Array).size():
		var p: Vector3 = info["pithoi"][i]
		var s := 0.8 + 0.35 * absf(sin(i * 12.9898))
		var y := TroyLayout.height(p.x, p.z) - 0.04
		jars.append(Transform3D(Basis(Vector3.UP, i * 2.4).scaled(Vector3(s, s, s)), Vector3(p.x, maxf(y, p.y - 0.3), p.z)))
	_multimesh(world, pithos_mesh(), jars, "Pithoi", 140.0)

	var fires: Array[Fire] = []
	if night:
		for p: Vector3 in info["torches"]:
			var f := Fire.new(0.16)
			f.position = p
			world.add_child(f)
			fires.append(f)
		for h: Dictionary in info["hearths"]:
			var f := Fire.new(0.42, false, quality >= 2)
			f.position = h["pos"]
			world.add_child(f)
			fires.append(f)
	return fires
