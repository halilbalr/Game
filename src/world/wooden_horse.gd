class_name WoodenHorse
extends Node3D
## The horse Epeius built: a hollow figure of pine planks on a wheeled sledge,
## tall enough that the Trojans broke their own gate to bring it in. Also
## builds the cramped compartment inside, which the game keeps out of sight
## below the ground and moves the player into.

## Where the player stands at the foot of the rope, in local space.
const ROPE_FOOT := Vector3(0.0, 0.2, 0.6)
## Offset of the hidden interior set from the horse's origin.
const INTERIOR_OFFSET := Vector3(0.0, -70.0, 0.0)

var interior: Node3D


func _init() -> void:
	name = "WoodenHorse"


## Builds the horse. Local -Z is the way it faces.
func build() -> void:
	var gb := GeoBuilder.new()
	gb.chunk_size = 0.0
	var pale := Color.WHITE
	var deck_y := 1.25
	# Sledge and wheels.
	gb.box(&"wood", Transform3D(Basis.IDENTITY, Vector3(0, deck_y, 0)), Vector3(3.3, 0.32, 9.2), pale, true, 0)
	for sx: float in [-1.0, 1.0]:
		gb.box(&"wood_dark", Transform3D(Basis.IDENTITY, Vector3(sx * 1.2, deck_y - 0.3, 0)), Vector3(0.3, 0.3, 9.4), pale, true, 0)
	var side_axis := Basis(Vector3(0, 0, 1), PI * 0.5)
	for sz: float in [-3.1, 3.1]:
		gb.cylinder(&"wood_dark", Vector3(-2.0, 0.92, sz), 0.13, 0.13, 4.0, 8, pale, false, true, side_axis.inverse())
		for sx: float in [-1.0, 1.0]:
			# Solid plank wheels with a bronze tyre.
			gb.cylinder(&"wood", Vector3(sx * 1.78, 0.92, sz), 0.92, 0.92, 0.22, 16, pale, true, true, side_axis if sx > 0 else side_axis.inverse())
			gb.cylinder(&"bronze_dull", Vector3(sx * 1.76, 0.92, sz), 0.95, 0.95, 0.18, 16, pale, false, false, side_axis if sx > 0 else side_axis.inverse())
	# Legs: four baulks, braced.
	var belly_y := 5.3
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-2.5, 2.3]:
			var foot := Vector3(sx * 0.95, deck_y + 0.16, sz + signf(sz) * 0.25)
			var xf := Transform3D(Basis(Vector3.RIGHT, -signf(sz) * 0.06), foot)
			gb.frustum(&"wood_pale", xf, Vector2(0.62, 0.62), Vector2(0.5, 0.5), belly_y - deck_y + 0.2, pale, true, false)
			gb.box(&"bronze_dull", Transform3D(Basis.IDENTITY, foot + Vector3(0, 0.25, 0)), Vector3(0.7, 0.2, 0.7), pale, false, 0)
	# Body: a barrel of planks, lofted through five ribs.
	var ribs: Array = [[-3.7, 0.72, 0.35], [-2.6, 1.0, 0.1], [0.0, 1.06, 0.0], [2.4, 1.0, 0.08], [3.6, 0.76, 0.3]]
	var sides := 12
	var half_w := 1.42
	var half_h := 1.55
	var centre_y := belly_y + half_h
	for i in ribs.size() - 1:
		var a: Array = ribs[i]
		var b: Array = ribs[i + 1]
		for k in sides:
			var a0 := TAU * k / sides + PI / sides
			var a1 := TAU * (k + 1) / sides + PI / sides
			var p0 := Vector3(cos(a0) * half_w * a[1], centre_y + a[2] + sin(a0) * half_h * a[1], a[0])
			var p1 := Vector3(cos(a1) * half_w * a[1], centre_y + a[2] + sin(a1) * half_h * a[1], a[0])
			var q0 := Vector3(cos(a0) * half_w * b[1], centre_y + b[2] + sin(a0) * half_h * b[1], b[0])
			var q1 := Vector3(cos(a1) * half_w * b[1], centre_y + b[2] + sin(a1) * half_h * b[1], b[0])
			var mid := (p0 + p1 + q0 + q1) * 0.25
			var out := Vector3(mid.x, mid.y - centre_y, 0.0)
			# Leave the hatch open in the belly.
			var is_hatch := i == 2 and absf(a0 + a1 - 3.0 * PI) < 0.3
			if not is_hatch:
				gb.quad_h(&"wood_pale", p0, p1, q1, q0, out, pale, true)
	# End caps of the barrel.
	for end: Array in [ribs[0], ribs[ribs.size() - 1]]:
		var ring: Array[Vector3] = []
		for k in sides:
			var a0 := TAU * k / sides + PI / sides
			ring.append(Vector3(cos(a0) * half_w * end[1], centre_y + end[2] + sin(a0) * half_h * end[1], end[0]))
		gb.poly(&"wood_pale", ring, Vector3(0, 0, signf(end[0])), pale, true)
	# Iron-hard pegs and bronze bands round the barrel.
	for z: float in [-2.6, 0.0, 2.4]:
		for k in sides:
			var a0 := TAU * (k + 0.5) / sides + PI / sides
			var p := Vector3(cos(a0) * half_w * 1.03, centre_y + sin(a0) * half_h * 1.03, z)
			var basis := Basis(Vector3(0, 0, 1), a0 - PI * 0.5)
			gb.box(&"bronze_dull", Transform3D(basis, p), Vector3(0.82, 0.06, 0.16), pale, false, 0)
	# Neck and head.
	var neck_base := Vector3(0, centre_y + 0.5, -3.3)
	var neck_basis := Basis(Vector3.RIGHT, -0.62)
	gb.frustum(&"wood_pale", Transform3D(neck_basis, neck_base), Vector2(1.5, 1.9), Vector2(0.95, 1.15), 3.6, pale, true, true)
	var head_base := neck_base + neck_basis * Vector3(0, 3.5, 0.1)
	var head_basis := Basis(Vector3.RIGHT, -2.05)
	gb.frustum(&"wood_pale", Transform3D(head_basis, head_base), Vector2(1.0, 1.25), Vector2(0.6, 0.7), 2.3, pale, true, true)
	for sx: float in [-1.0, 1.0]:
		# Ears and bronze eyes.
		gb.frustum(&"wood_pale", Transform3D(Basis(Vector3.RIGHT, -0.4), head_base + Vector3(sx * 0.32, 0.45, 0.25)), Vector2(0.22, 0.14), Vector2(0.05, 0.05), 0.7, pale, false, true)
		gb.cylinder(&"bronze", head_base + head_basis * Vector3(sx * 0.46, 0.75, 0.2), 0.13, 0.13, 0.08, 10, pale, false, true,
			Basis(Vector3(0, 0, 1), -sx * PI * 0.5))
	# Mane: a comb of upright boards.
	for i in 9:
		var t := i / 8.0
		var mp := neck_base + neck_basis * Vector3(0, 0.3 + t * 3.3, 0.95 - t * 0.38)
		gb.box(&"wood_dark", Transform3D(neck_basis, mp), Vector3(0.14, 0.34, 0.5), pale, false, 0)
	# Tail of plaited rope.
	gb.cylinder(&"cloth", Vector3(0, centre_y + 0.7, 3.65), 0.16, 0.05, 2.6, 8, Color(0.5, 0.42, 0.3), false, true, Basis(Vector3.RIGHT, 2.7))
	# The hatch door hanging open, and the rope.
	gb.box(&"wood_dark", Transform3D(Basis(Vector3(0, 0, 1), 0.15), Vector3(-0.42, belly_y - 0.55, 1.2)), Vector3(0.08, 1.1, 2.3), pale, false, 0)
	gb.cylinder(&"cloth", Vector3(0.0, 1.45, 0.6), 0.035, 0.035, belly_y - 1.3, 6, Color(0.55, 0.47, 0.34))
	gb.commit(self, Mats.all_local())
	_build_interior()


func _build_interior() -> void:
	interior = Node3D.new()
	interior.name = "Interior"
	interior.position = INTERIOR_OFFSET
	add_child(interior)
	var gb := GeoBuilder.new()
	gb.chunk_size = 0.0
	var w := 2.3
	var h := 1.95
	var l := 6.2
	var dark := Color(0.75, 0.7, 0.66)
	# A box of planks seen from within: floor, roof, two sides, two ends.
	gb.quad_h(&"wood_pale", Vector3(-w * 0.5, 0, -l * 0.5), Vector3(w * 0.5, 0, -l * 0.5), Vector3(w * 0.5, 0, l * 0.5), Vector3(-w * 0.5, 0, l * 0.5), Vector3.UP, dark, true)
	gb.quad_h(&"wood_pale", Vector3(-w * 0.5, h, -l * 0.5), Vector3(w * 0.5, h, -l * 0.5), Vector3(w * 0.5, h, l * 0.5), Vector3(-w * 0.5, h, l * 0.5), Vector3.DOWN, dark, true)
	for sx: float in [-1.0, 1.0]:
		gb.quad_h(&"wood_pale", Vector3(sx * w * 0.5, 0, -l * 0.5), Vector3(sx * w * 0.5, 0, l * 0.5), Vector3(sx * w * 0.5, h, l * 0.5), Vector3(sx * w * 0.5, h, -l * 0.5), Vector3(-sx, 0, 0), dark, true)
		# Ribs.
		for i in 5:
			var z := lerpf(-l * 0.5 + 0.5, l * 0.5 - 0.5, i / 4.0)
			gb.box(&"wood_dark", Transform3D(Basis.IDENTITY, Vector3(sx * (w * 0.5 - 0.07), h * 0.5, z)), Vector3(0.14, h, 0.16), Color.WHITE, false, 0)
	for sz: float in [-1.0, 1.0]:
		gb.quad_h(&"wood_pale", Vector3(-w * 0.5, 0, sz * l * 0.5), Vector3(w * 0.5, 0, sz * l * 0.5), Vector3(w * 0.5, h, sz * l * 0.5), Vector3(-w * 0.5, h, sz * l * 0.5), Vector3(0, 0, -sz), dark, true)
	# The hatch outlined in the floor.
	gb.box(&"wood_dark", Transform3D(Basis.IDENTITY, Vector3(0, 0.02, 1.2)), Vector3(1.0, 0.04, 1.6), Color.WHITE, false, 8)
	gb.box(&"bronze_dull", Transform3D(Basis.IDENTITY, Vector3(0.3, 0.06, 1.2)), Vector3(0.1, 0.05, 0.3), Color.WHITE, false, 8)
	gb.commit(interior, Mats.all_local(), false)
	# Chinks between the planks, where the firelight of the feast leaks in.
	var seam := StandardMaterial3D.new()
	seam.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	seam.albedo_color = Color(1.0, 0.55, 0.22)
	for i in 7:
		var mi := MeshInstance3D.new()
		var q := QuadMesh.new()
		q.size = Vector2(randf_range(0.5, 1.6), 0.012)
		mi.mesh = q
		mi.material_override = seam
		var sx := 1.0 if i % 2 == 0 else -1.0
		mi.position = Vector3(sx * (w * 0.5 - 0.004), randf_range(0.5, 1.6), randf_range(-2.4, 2.4))
		mi.rotation.y = -sx * PI * 0.5
		interior.add_child(mi)
	var glow := OmniLight3D.new()
	glow.light_color = Color(1.0, 0.55, 0.25)
	glow.light_energy = 0.16
	glow.omni_range = 6.0
	glow.position = Vector3(0, 1.5, 0)
	glow.shadow_enabled = false
	interior.add_child(glow)


## World position of the player's seat inside the compartment.
func seat() -> Vector3:
	return interior.global_transform * Vector3(0.0, 0.05, -0.4)


## World transforms for the companions sitting along the walls.
func bench(index: int) -> Transform3D:
	var spots: Array = [Vector3(-0.72, 0.0, -1.6), Vector3(0.72, 0.0, -2.2), Vector3(-0.72, 0.0, 0.4),
		Vector3(0.72, 0.0, -0.9), Vector3(0.72, 0.0, 2.2)]
	var p: Vector3 = spots[index % spots.size()]
	var yaw := -PI * 0.5 if p.x < 0.0 else PI * 0.5
	return interior.global_transform * Transform3D(Basis(Vector3.UP, yaw), p)


## World position of the hatch inside.
func hatch() -> Vector3:
	return interior.global_transform * Vector3(0.0, 0.1, 1.2)


## World position at the foot of the rope outside.
func rope_foot() -> Vector3:
	return global_transform * ROPE_FOOT
