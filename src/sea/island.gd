class_name Island
extends RefCounted
## An island raised from a height function: a ridge of hills round a centre,
## a ragged coast, and places flattened for a beach or a cave floor. Built as
## one walkable, solid mesh; [method height] answers for any point.
##
## [codeblock]
## var isle := Island.new(Vector2(0, -300), Vector2(180, 140), 42.0, 7)
## isle.flats.append([Vector2(20, -170), 14.0, 1.2])  # a beach at 1.2 m
## isle.build(world)
## [/codeblock]

var center: Vector2
var radii: Vector2
var peak: float
var seed_value: int
## Areas levelled to a height: [centre Vector2, radius, height]. Blended at the edges.
var flats: Array = []
## Extra hills: [centre Vector2, radius, height].
var hills: Array = []
## 1 for a flowering meadow (the Sirens).
var meadow: float = 0.0
## Cliffs: sides steepened toward the sea.
var cliffs: float = 0.0
## True for ground the player climbs: it keeps its full detail on phones,
## where a coarser grid can leave a step too steep to walk up.
var walked: bool = false


func _init(c: Vector2, r: Vector2, top: float, s: int) -> void:
	center = c
	radii = r
	peak = top
	seed_value = s


static func _noise(p: Vector2, s: float) -> float:
	var i := p.floor()
	var f := p - i
	var u := f * f * (Vector2(3, 3) - 2.0 * f)
	var a := Sculpt.noise(i.x + s, i.y)
	var b := Sculpt.noise(i.x + 1.0 + s, i.y)
	var c := Sculpt.noise(i.x + s, i.y + 1.0)
	var d := Sculpt.noise(i.x + 1.0 + s, i.y + 1.0)
	return lerpf(lerpf(a, b, u.x), lerpf(c, d, u.x), u.y)


static func _fbm(p: Vector2, s: float) -> float:
	return _noise(p, s) * 0.55 + _noise(p * 2.1, s + 5.0) * 0.28 + _noise(p * 4.3, s + 9.0) * 0.17


## Ground height at (x, z), metres above sea level (negative under water).
func height(x: float, z: float) -> float:
	var p := Vector2(x, z) - center
	var ang := atan2(p.y, p.x)
	# A ragged coast: the island's edge wanders in and out.
	var edge := 1.0 + 0.22 * (_fbm(Vector2(cos(ang), sin(ang)) * 2.2, seed_value) - 0.5) * 2.0
	var r := Vector2(p.x / radii.x, p.y / radii.y).length() / edge
	var land := clampf(1.0 - r * r, 0.0, 1.0)
	var h := peak * pow(land, 1.0 + cliffs * -0.6) * (0.7 + 0.6 * _fbm(Vector2(x, z) * 0.012, seed_value + 2.0))
	h += 6.0 * (_fbm(Vector2(x, z) * 0.04, seed_value + 4.0) - 0.5) * land
	h -= 6.0 * smoothstep(0.82, 1.15, r) + 2.0
	for hill: Array in hills:
		var d := Vector2(x, z).distance_to(hill[0]) / float(hill[1])
		h += float(hill[2]) * clampf(1.0 - d * d, 0.0, 1.0) ** 1.5
	for flat: Array in flats:
		var d := Vector2(x, z).distance_to(flat[0])
		var k := smoothstep(float(flat[1]) * 1.6, float(flat[1]), d)
		h = lerpf(h, float(flat[2]), k)
	return h


## Builds the mesh and its collision under [param parent].
func build(parent: Node3D) -> void:
	var step := 4.0 if Game.lite and not walked else 2.5
	var half := Vector2(radii.x, radii.y) * 1.3
	var nx := int(half.x * 2.0 / step)
	var nz := int(half.y * 2.0 / step)
	var hs := PackedFloat32Array()
	hs.resize((nx + 1) * (nz + 1))
	for j in nz + 1:
		for i in nx + 1:
			hs[j * (nx + 1) + i] = height(center.x - half.x + i * step, center.y - half.y + j * step)
	var gb := GeoBuilder.new()
	gb.chunk_size = 64.0
	var mat := ShaderMaterial.new()
	mat.shader = load("res://assets/shaders/island.gdshader")
	mat.set_shader_parameter("meadow", meadow)
	mat.set_shader_parameter("detail_scale", Game.detail())
	for j in nz:
		for i in nx:
			var x0 := center.x - half.x + i * step
			var z0 := center.y - half.y + j * step
			var a := Vector3(x0, hs[j * (nx + 1) + i], z0)
			var b := Vector3(x0 + step, hs[j * (nx + 1) + i + 1], z0)
			var c := Vector3(x0 + step, hs[(j + 1) * (nx + 1) + i + 1], z0 + step)
			var d := Vector3(x0, hs[(j + 1) * (nx + 1) + i], z0 + step)
			if maxf(maxf(a.y, b.y), maxf(c.y, d.y)) < -3.0:
				continue
			var na := _normal(hs, nx, nz, i, j, step)
			var nb := _normal(hs, nx, nz, i + 1, j, step)
			var nc := _normal(hs, nx, nz, i + 1, j + 1, step)
			var nd := _normal(hs, nx, nz, i, j + 1, step)
			gb.tri_smooth(&"island", a, c, b, na, nc, nb, Color.WHITE, Color.WHITE, Color.WHITE, true)
			gb.tri_smooth(&"island", a, d, c, na, nd, nc, Color.WHITE, Color.WHITE, Color.WHITE, true)
	gb.commit(parent, {&"island": mat})


static func _normal(hs: PackedFloat32Array, nx: int, nz: int, i: int, j: int, step: float) -> Vector3:
	var l := hs[j * (nx + 1) + maxi(i - 1, 0)]
	var r := hs[j * (nx + 1) + mini(i + 1, nx)]
	var u := hs[maxi(j - 1, 0) * (nx + 1) + i]
	var dn := hs[mini(j + 1, nz) * (nx + 1) + i]
	return Vector3(l - r, 2.0 * step, u - dn).normalized()
