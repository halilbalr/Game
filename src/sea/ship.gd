class_name Ship
extends Node3D
## Odysseus's black ship: a long open hull with a high curved stern, a red
## painted bow, a mast with a square sail, oars and the men at them. It
## rides the swell of the [Sea] it is given and is steered from the stern,
## by the player (see [member controlled]) or by its own helmsman toward
## [member autopilot_to]. Front is -Z.
##
## [codeblock]
## var ship := Ship.new()
## ship.sea = sea_world.sea
## ship.ground = sea_world.ground_height
## add_child(ship)
## ship.controlled = true
## [/codeblock]

signal struck_rock(strength: float)

const LENGTH := 22.0
const BEAM := 3.6
const OARS_A_SIDE := 10

## The water it floats on.
var sea: Sea
## Callable(x, z) -> float: the height of the ground (islands, rocks) there.
var ground: Callable
## When true the movement controls steer and row.
var controlled: bool = false
## When set (and not controlled) the ship makes for this point by itself.
var autopilot_to: Variant = null
var max_speed: float = 5.0
## Metres a second, forward.
var speed: float = 0.0
## Pushed by currents, waves and the whirlpool: metres a second.
var drift := Vector3.ZERO
## The water's own flow here (a whirlpool's draw): the drift settles toward it.
var current := Vector3.ZERO
## Drawn up on a beach: it rides the swell but goes nowhere.
var moored: bool = false
## Seconds it has been pinned against rock (the script decides what that costs).
var damage: float = 0.0
## Where the player stands to steer, and the mast he can be bound to.
var helm: Node3D
var mast_spot: Node3D
var rowers: Array[Humanoid] = []
var _yaw: float = 0.0
var _hull: Node3D
var _oars: MultiMesh
var _sail: MeshInstance3D
var _stroke: float = 0.0
var _throttle: float = 0.0
var _steer: float = 0.0
var _bump_cool: float = 0.0


func _init() -> void:
	name = "Ship"
	# After the man at its helm, so his eye is drawn smoothly between steps
	# (see Player._process).
	process_physics_priority = 10


func _ready() -> void:
	_yaw = rotation.y
	_hull = Node3D.new()
	add_child(_hull)
	var mi := MeshInstance3D.new()
	mi.mesh = hull_mesh()
	_hull.add_child(mi)
	_sail = MeshInstance3D.new()
	_sail.mesh = sail_mesh()
	_sail.position = Vector3(0, 0, -1.0)
	_hull.add_child(_sail)
	_oars = MultiMesh.new()
	_oars.transform_format = MultiMesh.TRANSFORM_3D
	_oars.mesh = oar_mesh()
	_oars.instance_count = OARS_A_SIDE * 2
	var mm := MultiMeshInstance3D.new()
	mm.multimesh = _oars
	mm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_hull.add_child(mm)
	helm = Node3D.new()
	helm.name = "Helm"
	helm.position = Vector3(0.0, 0.3, LENGTH * 0.5 - 3.4)
	_hull.add_child(helm)
	mast_spot = Node3D.new()
	mast_spot.name = "Mast"
	mast_spot.position = Vector3(0.0, 0.3, 0.1)
	_hull.add_child(mast_spot)
	var outfits: Dictionary = Data.characters.get("outfits", {})
	for i in 8:
		var side := -1.0 if i % 2 == 0 else 1.0
		var h := Humanoid.new()
		_hull.add_child(h)
		h.setup("oarsman", outfits.get("oarsman", {}), i * 5 + 1, "")
		h.stance = &"row"
		# Facing the stern, as rowers do.
		h.rotation.y = PI
		h.position = Vector3(side * 0.85, 0.42, -6.0 + int(i / 2) * 2.4)
		rowers.append(h)
	_place_oars()


## Takes [param n] men from the benches (Scylla). Returns their positions.
func lose_rowers(n: int) -> Array[Vector3]:
	var out: Array[Vector3] = []
	for i in mini(n, rowers.size()):
		var h: Humanoid = rowers.pop_back()
		out.append(h.global_position)
		h.queue_free()
	return out


## Shows or hides the sail (it is furled when rowing hard or in the strait).
func set_sail(up: bool) -> void:
	_sail.visible = up


## World point ahead of the bow, [param ahead] metres.
func bow(ahead: float = 0.0) -> Vector3:
	return global_position + global_transform.basis * Vector3(0, 0, -LENGTH * 0.5 - ahead)


## The ship's heading as a flat unit vector.
func forward() -> Vector3:
	return Vector3(-sin(_yaw), 0.0, -cos(_yaw))


## Puts the ship at [param pos] facing [param yaw] at once.
func place(pos: Vector3, yaw: float) -> void:
	_yaw = yaw
	speed = 0.0
	drift = Vector3.ZERO
	global_position = Vector3(pos.x, 0.0, pos.z)
	rotation = Vector3(0.0, yaw, 0.0)


func _physics_process(delta: float) -> void:
	var throttle := 0.0
	var steer := 0.0
	if moored:
		speed = 0.0
		drift = Vector3.ZERO
	elif controlled:
		var v := Input.get_vector(&"move_left", &"move_right", &"move_forward", &"move_back")
		throttle = clampf(-v.y, -0.4, 1.0)
		steer = -v.x
		if Input.is_action_pressed(&"sprint"):
			throttle = minf(throttle * 1.25, 1.25)
	elif autopilot_to is Vector3:
		var to: Vector3 = (autopilot_to as Vector3) - global_position
		to.y = 0.0
		if to.length() > 6.0:
			throttle = 0.8
			steer = clampf(forward().signed_angle_to(to, Vector3.UP) * 2.0, -1.0, 1.0)
	_throttle = move_toward(_throttle, throttle, delta * 0.6)
	_steer = move_toward(_steer, steer, delta * 2.0)
	speed = move_toward(speed, _throttle * max_speed, delta * (0.9 if absf(_throttle * max_speed) > absf(speed) else 0.6))
	# The steering oar bites harder the faster she goes.
	_yaw += _steer * 0.32 * clampf(absf(speed) / 2.5, 0.25, 1.0) * delta * signf(speed + 0.01)
	var move := forward() * speed + drift
	var next := global_position + move * delta
	# Rock and shore: look ahead of the bow (or the stern going astern).
	_bump_cool -= delta
	if ground.is_valid() and not moored:
		var probe := next + forward() * (LENGTH * 0.45 if speed >= 0.0 else -LENGTH * 0.45)
		if float(ground.call(probe.x, probe.z)) > -0.8:
			var hit := absf(speed) + drift.length()
			speed = -speed * 0.25
			drift = -drift * 0.3
			next = global_position
			damage += delta
			if _bump_cool <= 0.0:
				_bump_cool = 1.2
				struck_rock.emit(hit)
	global_position = next
	drift = drift.move_toward(current, delta * 1.5)
	# Ride the swell: height from the middle, pitch and roll from the ends and sides.
	if sea != null:
		var f := forward()
		var side := Vector3(-f.z, 0.0, f.x)
		var p := global_position
		var hb := sea.height(p.x + f.x * 8.0, p.z + f.z * 8.0)
		var hs := sea.height(p.x - f.x * 8.0, p.z - f.z * 8.0)
		var hl := sea.height(p.x - side.x * 1.6, p.z - side.z * 1.6)
		var hr := sea.height(p.x + side.x * 1.6, p.z + side.z * 1.6)
		global_position.y = lerpf(global_position.y, (hb + hs + hl + hr) * 0.25 - 0.1, minf(1.0, delta * 4.0))
		var pitch := atan2(hb - hs, 16.0)
		var roll := atan2(hl - hr, 3.2) * 0.8 - _steer * speed * 0.012
		rotation = Vector3(lerp_angle(rotation.x, pitch, minf(1.0, delta * 3.0)), _yaw, lerp_angle(rotation.z, roll, minf(1.0, delta * 3.0)))
	else:
		rotation.y = _yaw
	# The oars keep stroke with the speed asked of them.
	_stroke += delta * (1.2 + 2.6 * clampf(absf(_throttle), 0.0, 1.25))
	if absf(_throttle) < 0.05 and absf(speed) < 0.3:
		_stroke = lerpf(_stroke, snappedf(_stroke, TAU), delta)
	_place_oars()
	for r in rowers:
		r.row_phase = _stroke


func _place_oars() -> void:
	if _oars == null:
		return
	var k := sin(_stroke)
	var lift := maxf(0.0, cos(_stroke))
	for i in OARS_A_SIDE * 2:
		var side := -1.0 if i < OARS_A_SIDE else 1.0
		var z := -7.0 + (i % OARS_A_SIDE) * 1.45
		# The oar mesh reaches out along +X: turn the port oars about to reach the other way.
		var b := Basis(Vector3.UP, (PI if side < 0.0 else 0.0) + side * 0.45 * k) * Basis(Vector3(0, 0, 1), -(0.22 - 0.16 * lift))
		_oars.set_instance_transform(i, Transform3D(b, Vector3(side * (BEAM * 0.5 - 0.1), 0.85, z)))


# --- shapes -------------------------------------------------------------------------

static func _half_beam(v: float) -> float:
	return BEAM * 0.5 * pow(sin(PI * clampf(v, 0.0, 1.0)), 0.55)


static func _sheer(v: float) -> float:
	# The gunwale rises to the bow and climbs high at the stern.
	return 1.05 + 0.9 * pow(smoothstep(0.18, 0.0, v), 2.0) + 2.4 * pow(smoothstep(0.78, 1.0, v), 2.0)


static func _hull_point(u: float, v: float, inset: float) -> Vector3:
	var th := (u - 0.5) * PI
	var b := maxf(_half_beam(v) - inset, 0.02)
	var g := _sheer(v)
	var d := 1.0 - inset
	return Vector3(b * sin(th), g - (g + d) * pow(cos(th), 1.4), lerpf(-LENGTH * 0.5, LENGTH * 0.5, v))


## The hull, deck, benches, mast, stern post, steering oar and rigging.
static func hull_mesh() -> ArrayMesh:
	var gb := GeoBuilder.new()
	gb.chunk_size = 0.0
	var pitch := Color(0.07, 0.06, 0.05)
	var red := Color(0.55, 0.12, 0.08)
	var outer := func(u: float, v: float) -> Vector3:
		return _hull_point(u, v, 0.0)
	# Black with pitch, the bows painted red ("red-cheeked ships"), with an eye.
	var paint := func(u: float, v: float) -> Color:
		var plank := absf(fposmod(u * 14.0, 1.0) - 0.5) > 0.44
		var c := red if v < 0.12 and absf(u - 0.5) > 0.12 else pitch
		if v > 0.05 and v < 0.09 and absf(absf(u - 0.5) - 0.38) < 0.04:
			c = Color(0.9, 0.86, 0.75)
		return c.lightened(0.06) if plank else c
	Sculpt.grid(gb, &"hide", 14, 40, outer, paint, false)
	var inner := func(u: float, v: float) -> Vector3:
		return _hull_point(u, v, 0.09)
	var wood := func(u: float, _v: float) -> Color:
		return Color(0.42, 0.29, 0.17).darkened(0.18 * float(int(u * 14.0) % 2))
	Sculpt.grid(gb, &"hide", 14, 40, inner, wood, false, Vector3(0, -30, 0))
	# Gunwale cap.
	for side: float in [0.0, 1.0]:
		var cap := func(u: float, v: float) -> Vector3:
			var a := _hull_point(side, v, 0.0)
			var b := _hull_point(side, v, 0.09)
			return a.lerp(b, u) + Vector3(0, 0.03, 0)
		Sculpt.grid(gb, &"hide", 1, 40, cap, Color(0.3, 0.2, 0.12), false, Vector3(0, -30, 0))
	# Deck planks, benches.
	gb.box(&"wood", Transform3D(Basis.IDENTITY, Vector3(0, 0.12, 0)), Vector3(BEAM * 0.6, 0.05, LENGTH * 0.72), Color.WHITE, false, 0)
	for i in 6:
		var z := -6.6 + i * 2.4
		gb.box(&"wood", Transform3D(Basis.IDENTITY, Vector3(0, 0.45, z)), Vector3(_half_beam(z / LENGTH + 0.5) * 2.0 - 0.15, 0.07, 0.3), Color.WHITE, false, 0)
	# Stern deck where the helmsman stands, bow deck.
	gb.box(&"wood", Transform3D(Basis.IDENTITY, Vector3(0, 0.3, LENGTH * 0.5 - 3.2)), Vector3(2.2, 0.06, 2.6), Color.WHITE, false, 0)
	gb.box(&"wood", Transform3D(Basis.IDENTITY, Vector3(0, 0.55, -LENGTH * 0.5 + 2.6)), Vector3(1.6, 0.06, 2.4), Color.WHITE, false, 0)
	# The stern post curling up and forward.
	var post := func(u: float, v: float) -> Vector3:
		var a := lerpf(0.0, 2.4, v)
		var r := 0.12 * (1.0 - v * 0.6)
		var c := Vector3(0.0, _sheer(1.0) - 0.4 + sin(a) * 1.4, LENGTH * 0.5 - 0.3 - (1.0 - cos(a)) * 1.0 + v * 0.4)
		return c + Vector3(cos(u * TAU) * r, sin(u * TAU) * r * 0.5, 0.0)
	Sculpt.grid(gb, &"hide", 8, 12, post, pitch, true)
	# Mast, yard and stays.
	Sculpt.lathe(gb, &"hide", Transform3D(Basis.IDENTITY, Vector3(0, 0.1, -1.0)), PackedVector2Array([Vector2(0.13, 0.0), Vector2(0.11, 4.0),
		Vector2(0.08, 9.0), Vector2(0.0, 9.2)]), 8, Color(0.45, 0.32, 0.19), 1.0, 2)
	gb.box(&"hide", Transform3D(Basis(Vector3(0, 0, 1), PI * 0.5), Vector3(0, 8.4, -1.0)), Vector3(0.12, 7.6, 0.12), Color(0.4, 0.28, 0.16), false, 0)
	for end: Vector3 in [Vector3(0, 1.4, -LENGTH * 0.5 + 0.4), Vector3(0, 2.2, LENGTH * 0.5 - 2.0)]:
		var top := Vector3(0, 8.9, -1.0)
		var mid := (top + end) * 0.5
		gb.box(&"hide", Transform3D(Basis.looking_at((top - end).normalized(), Vector3.RIGHT), mid),
			Vector3(0.03, 0.03, top.distance_to(end)), Color(0.5, 0.42, 0.3), false, 0)
	# Steering oar on the starboard quarter.
	gb.box(&"hide", Transform3D(Basis(Vector3.RIGHT, 0.55), Vector3(BEAM * 0.5 + 0.12, 0.2, LENGTH * 0.5 - 2.6)), Vector3(0.1, 0.1, 4.2),
		Color(0.4, 0.28, 0.16), false, 0)
	gb.box(&"hide", Transform3D(Basis(Vector3.RIGHT, 0.55), Vector3(BEAM * 0.5 + 0.12, -0.85, LENGTH * 0.5 - 1.0)), Vector3(0.05, 0.6, 1.1),
		Color(0.35, 0.24, 0.14), false, 0)
	return Sculpt.mesh_with_lods(gb, Mats.all())


## The square sail of linen on its yard, bellied by the wind.
static func sail_mesh() -> ArrayMesh:
	var gb := GeoBuilder.new()
	gb.chunk_size = 0.0
	var cloth := func(u: float, v: float) -> Vector3:
		var x := lerpf(-3.6, 3.6, u)
		var y := lerpf(8.3, 2.6, v)
		return Vector3(x, y, -0.9 * sin(PI * u) * sin(PI * clampf(v * 0.9 + 0.1, 0.0, 1.0)))
	var weave := func(u: float, v: float) -> Color:
		var seam := absf(fposmod(u * 8.0, 1.0) - 0.5) > 0.46 or absf(fposmod(v * 6.0, 1.0) - 0.5) > 0.47
		return Color(0.78, 0.72, 0.6).darkened(0.18 if seam else 0.05 * v)
	Sculpt.grid(gb, &"wool_2s", 12, 10, cloth, weave, false, Vector3(0, 5, 3))
	return gb.build_mesh(Mats.all())


## One oar, pivoting at the gunwale, its blade out over the water (+X).
static func oar_mesh() -> ArrayMesh:
	var gb := GeoBuilder.new()
	gb.chunk_size = 0.0
	gb.box(&"hide", Transform3D(Basis.IDENTITY, Vector3(1.6, 0.0, 0.0)), Vector3(4.6, 0.06, 0.06), Color(0.5, 0.36, 0.22), false, 0)
	gb.box(&"hide", Transform3D(Basis.IDENTITY, Vector3(3.6, 0.0, 0.0)), Vector3(0.9, 0.03, 0.2), Color(0.45, 0.32, 0.2), false, 0)
	var m := gb.build_mesh(Mats.all())
	return m
