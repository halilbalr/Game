class_name Cave
extends Node3D
## The Cyclops's cave (Odyssey 9.181-192, 9.218-223): a high hollow in the
## rock near the sea, with folds for lambs and kids, racks of cheeses, pails
## of whey, a hearth, his great club of green olive wood, and a doorway that
## a stone no twenty-two wagons could shift is set across at night.
## Its floor is at local y 0; the doorway faces +Z.

const R := 13.0
const H := 10.5
const DOOR_W := 7.5
const DOOR_H := 8.0

## The stone across the doorway.
var stone: Node3D
## Where the hearth burns, the club lies, the giant sits and the rams wait.
var hearth: Vector3
var club: Node3D
var seat: Vector3
var bed: Vector3
var rams_spot: Vector3
var _stone_shut := Vector3.ZERO


static func _noise(a: float, b: float) -> float:
	return Sculpt.noise(floorf(a), floorf(b)) * 0.6 + Sculpt.noise(floorf(a * 2.3), floorf(b * 2.3) + 7.0) * 0.4


## The shell's surface at angle [param a] (0 = the doorway), height [param y].
static func shell(a: float, y: float, grow: float) -> Vector3:
	var k := clampf(y / H, 0.0, 0.999)
	var r := R * sqrt(1.0 - k * k) * (0.92 + 0.16 * _noise(a * 3.0 + 9.0, y * 0.6)) + grow
	r = maxf(r, 0.6)
	return Vector3(sin(a) * r, y, cos(a) * r)


func build(rock_material: Material) -> void:
	name = "Cave"
	var gb := GeoBuilder.new()
	gb.chunk_size = 0.0
	var gap := asin(DOOR_W * 0.5 / R)
	var rock := func(_u: float, v: float) -> Color:
		return Color(0.62, 0.58, 0.52).darkened(0.25 * (1.0 - v))
	Sculpt.collide = true
	for side: Array in [[0.0, true], [0.9, false]]:
		var grow: float = side[0]
		Sculpt.inward = side[1]
		var walls := func(u: float, v: float) -> Vector3:
			return shell(lerpf(gap, TAU - gap, u), v * H, grow)
		var over := func(u: float, v: float) -> Vector3:
			return shell(lerpf(-gap, gap, u), lerpf(DOOR_H, H, v), grow)
		# The inner face looks in toward the middle, the outer face out.
		Sculpt.grid(gb, &"island", 40, 14, walls, rock, false, Vector3(0, 3, 0))
		Sculpt.grid(gb, &"island", 6, 4, over, rock, false, Vector3(0, 3, 0))
	Sculpt.inward = false
	Sculpt.collide = false
	# Jambs: the doorway's sides, so it has thickness.
	for sgn: float in [-1.0, 1.0]:
		var jamb := func(u: float, v: float) -> Vector3:
			return shell(sgn * gap, v * DOOR_H, u * 0.9)
		Sculpt.grid(gb, &"island", 2, 6, jamb, Color(0.55, 0.52, 0.47), false, Vector3(0, 4, 0))
	# Folds of wattle for the lambs and kids, along the back wall.
	for i in 3:
		var a := PI + (i - 1) * 0.75
		var c := Vector3(sin(a), 0, cos(a)) * (R * 0.62)
		var tangent := Vector3(cos(a), 0, -sin(a))
		for k in 6:
			var p := c + tangent * (k - 2.5) * 0.9
			gb.box(&"hide", Transform3D(Basis.IDENTITY, p + Vector3(0, 0.55, 0)), Vector3(0.09, 1.1, 0.09), Color(0.35, 0.26, 0.16), true, 0)
		gb.box(&"hide", Transform3D(Basis(Vector3.UP, a + PI * 0.5), c + Vector3(0, 0.75, 0)), Vector3(5.0, 0.5, 0.06), Color(0.42, 0.32, 0.2), true, 0)
	# Racks of cheeses and pails of whey by the west wall.
	for i in 4:
		var a := -1.3 - i * 0.22
		var p := Vector3(sin(a), 0, cos(a)) * (R * 0.78)
		gb.box(&"hide", Transform3D(Basis(Vector3.UP, a), p + Vector3(0, 0.9, 0)), Vector3(1.6, 0.06, 0.6), Color(0.4, 0.3, 0.2), false, 0)
		for k in 3:
			var cheese := func(u: float, v: float) -> Vector3:
				return p + Vector3(cos(u * TAU) * 0.22, 0.96 + v * 0.14, sin(u * TAU) * 0.22) + Vector3(sin(a + PI * 0.5), 0, cos(a + PI * 0.5)) * (k - 1) * 0.5
			Sculpt.grid(gb, &"tint", 10, 1, cheese, Color(0.86, 0.8, 0.6), true, null)
	# The hearth: a ring of stones.
	hearth = Vector3(1.5, 0, 1.0)
	for i in 9:
		var a := TAU * i / 9.0
		var stone_ := func(u: float, v: float) -> Vector3:
			var th := PI * v
			return hearth + Vector3(cos(a) * 1.0, 0.12, sin(a) * 1.0) + Vector3(sin(th) * cos(u * TAU) * 0.22, -cos(th) * 0.14, sin(th) * sin(u * TAU) * 0.2)
		Sculpt.grid(gb, &"tint", 6, 4, stone_, Color(0.4, 0.37, 0.33), true, null)
	gb.commit(self, {&"island": rock_material, &"hide": Mats.get_mat(&"figure"), &"tint": Mats.get_mat(&"figure")})
	seat = Vector3(0.0, 0.0, R * 0.62)
	bed = Vector3(-4.0, 0.0, -2.0)
	rams_spot = Vector3(-2.2, 0.0, R * 0.55)
	# The club: a whole trunk of green olive, "as long and as thick as the
	# mast of a twenty-oared ship".
	club = MeshInstance3D.new()
	var cgb := GeoBuilder.new()
	cgb.chunk_size = 0.0
	var bark := func(u: float, v: float) -> Color:
		return Color(0.38, 0.33, 0.22).darkened(0.25 * Sculpt.noise(floorf(u * 8.0), floorf(v * 20.0)))
	Sculpt.lathe(cgb, &"hide", Transform3D(Basis(Vector3(0, 0, 1), PI * 0.5), Vector3.ZERO), PackedVector2Array([Vector2(0.0, -4.5),
		Vector2(0.3, -4.4), Vector2(0.24, 0.0), Vector2(0.2, 4.4), Vector2(0.0, 4.5)]), 10, bark, 1.0, 3)
	(club as MeshInstance3D).mesh = cgb.build_mesh(Mats.all())
	club.position = Vector3(5.5, 0.3, -5.0)
	club.rotation.y = 0.6
	add_child(club)
	# The door stone.
	stone = MeshInstance3D.new()
	var sgb := GeoBuilder.new()
	sgb.chunk_size = 0.0
	var boulder := func(u: float, v: float) -> Vector3:
		var th := PI * v
		var lump := 1.0 + 0.12 * sin(u * TAU * 3.0 + 1.0) * sin(th * 2.0) + 0.08 * sin(u * TAU * 7.0)
		return Vector3(sin(th) * cos(u * TAU) * 4.4, -cos(th) * 4.6 + 4.4, sin(th) * sin(u * TAU) * 1.6) * lump
	Sculpt.collide = true
	Sculpt.grid(sgb, &"island", 16, 10, boulder, Color.WHITE, true, null)
	Sculpt.collide = false
	stone.free()
	# Committed with its collision, so no one walks through it while it is shut.
	stone = AnimatableBody3D.new()
	var holder := stone
	var tmp := Node3D.new()
	sgb.commit(tmp, {&"island": rock_material})
	for c in tmp.get_children():
		if c is StaticBody3D:
			for shape in c.get_children():
				shape.reparent(holder, false)
			c.queue_free()
		else:
			c.reparent(holder, false)
	tmp.queue_free()
	_stone_shut = Vector3(0.0, -0.2, R - 0.5)
	holder.position = _stone_shut
	add_child(holder)


## Rolls the stone across the doorway (true) or aside (false) over [param seconds].
func set_door(shut: bool, seconds: float = 2.5) -> void:
	var to := _stone_shut if shut else _stone_shut + Vector3(DOOR_W * 0.5 + 5.6, 0.0, 1.6)
	if seconds <= 0.0:
		stone.position = to
		return
	var tw := create_tween()
	tw.tween_property(stone, "position", to, seconds).set_trans(Tween.TRANS_SINE)
	tw.parallel().tween_property(stone, "rotation:z", -1.2 if not shut else 0.0, seconds)
