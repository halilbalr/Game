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
## The bow has driven into a wave and thrown spray back over the ship (0..1).
signal sprayed(strength: float)

const LENGTH := 22.0
const BEAM := 3.6
const OARS_A_SIDE := 10
## The tiller's set at rest, its end where the helmsman holds it.
const TILLER_YAW := -0.1

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
## The tiller of the steering oar, with "GripL" and "GripR" where the
## helmsman's hands go. It swings with the steering.
var tiller: Node3D
var _bonds: Array[MeshInstance3D] = []
var rowers: Array[Humanoid] = []
## Oar station (0..OARS_A_SIDE * 2 - 1, port first) -> the man at it. A
## station not in it has no man: its oar is not rigged, or (taken by
## Scylla) trails alongside.
var _manned: Dictionary = {}
var _lost: Dictionary = {}
var _yaw: float = 0.0
var _hull: Node3D
var _oars: MultiMesh
var _sail: MeshInstance3D
var _stroke: float = 0.0
var _throttle: float = 0.0
var _steer: float = 0.0
var _bump_cool: float = 0.0
var _spray: CPUParticles3D
var _oar_xf: Array[Transform3D] = []
var _spray_cool: float = 0.0


func _init() -> void:
	name = "Ship"
	# After the man at its helm, so his eye is drawn smoothly between steps
	# (see Player._process).
	process_physics_priority = 10
	# And after the rowers have moved, so the oars are laid through their hands.
	process_priority = 10


func _ready() -> void:
	_yaw = rotation.y
	if sea != null:
		sea.hull = self
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
	# Bound "upright against the mast-step", his back to the mast, facing the bow.
	mast_spot = Node3D.new()
	mast_spot.name = "Mast"
	mast_spot.position = Vector3(0.0, 0.14, -1.36)
	_hull.add_child(mast_spot)
	tiller = Node3D.new()
	tiller.name = "Tiller"
	tiller.position = Vector3(BEAM * 0.5 + 0.12, 1.55, LENGTH * 0.5 - 4.39)
	# Swung aft, its end within the helmsman's reach.
	tiller.rotation.y = TILLER_YAW
	_hull.add_child(tiller)
	var bar := MeshInstance3D.new()
	bar.mesh = tiller_mesh()
	tiller.add_child(bar)
	for g: Array in [["GripL", Vector3(-1.42, -0.09, 0.06)], ["GripR", Vector3(-1.12, -0.08, 0.06)]]:
		var grip := Node3D.new()
		grip.name = g[0]
		grip.position = g[1]
		tiller.add_child(grip)
	var outfits: Dictionary = Data.characters.get("outfits", {})
	# The middle benches are manned; fewer on phones.
	var benches: Array = [3, 4, 5, 6] if Game.lite else [2, 3, 4, 5, 6, 7]
	var n := 0
	for k: int in benches:
		for side_i in 2:
			var side := -1.0 if side_i == 0 else 1.0
			var h := Humanoid.new()
			_hull.add_child(h)
			h.setup("oarsman", outfits.get("oarsman", {}), n * 5 + 1, "")
			n += 1
			h.stance = &"row"
			# Facing the stern, as rowers do, on the bench just forward of his oar.
			h.rotation.y = PI
			h.position = Vector3(side * 0.8, 0.42, station_z(k) - 0.55)
			rowers.append(h)
			_manned[side_i * OARS_A_SIDE + k] = h
	_spray = _bow_spray()
	_hull.add_child(_spray)
	_spray.position = Vector3(0.0, 0.7, -LENGTH * 0.5 + 0.8)
	_place_oars()


## Fore-and-aft position of oar station [param k] (0 at the bow end).
static func station_z(k: int) -> float:
	return -7.0 + k * 1.45


## Takes [param n] men from the benches (Scylla). Returns their positions.
func lose_rowers(n: int) -> Array[Vector3]:
	var out: Array[Vector3] = []
	for i in mini(n, rowers.size()):
		var h: Humanoid = rowers.pop_back()
		out.append(h.global_position)
		for st: int in _manned.keys():
			if _manned[st] == h:
				_manned.erase(st)
				_lost[st] = true
		h.queue_free()
	return out


## Shows the first [param n] turns of rope binding a man to the mast (0 for none).
func show_bonds(n: int) -> void:
	if _bonds.is_empty():
		for i in 5:
			var mi := MeshInstance3D.new()
			mi.mesh = bond_mesh(i)
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			_hull.add_child(mi)
			_bonds.append(mi)
	for i in _bonds.size():
		_bonds[i].visible = i < n


## A deckhand standing on the ship at [param pos] (hull space), facing [param yaw].
func add_hand(pos: Vector3, yaw: float, variant: int) -> Humanoid:
	var h := Humanoid.new()
	_hull.add_child(h)
	h.setup("oarsman", Data.characters.get("outfits", {}).get("oarsman", {}), variant, "")
	h.position = pos
	h.rotation.y = yaw
	return h


## Seats [param h] at oar station [param station] (port 0..9, starboard 10..19) and sets him rowing.
func man_station(h: Humanoid, station: int) -> void:
	var side := -1.0 if station < OARS_A_SIDE else 1.0
	h.stance = &"row"
	h.rotation = Vector3(0.0, PI, 0.0)
	h.position = Vector3(side * 0.8, 0.42, station_z(station % OARS_A_SIDE) - 0.55)
	rowers.append(h)
	_manned[station] = h
	_lost.erase(station)


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
		# The bow driving into the face of a wave throws up spray: more the
		# faster she goes and the higher the water stands at the stem.
		_spray_cool -= delta
		var dig := hb - global_position.y
		_spray.emitting = speed > 2.0
		if _spray_cool <= 0.0 and speed > 2.2 and dig > 0.12:
			_spray_cool = 2.0
			var strength := clampf(dig * speed / 3.0, 0.15, 1.0)
			_spray.restart()
			sprayed.emit(strength)
	else:
		rotation.y = _yaw
	# The oars keep stroke with the speed asked of them.
	_stroke += delta * (1.2 + 2.6 * clampf(absf(_throttle), 0.0, 1.25))
	if absf(_throttle) < 0.05 and absf(speed) < 0.3:
		_stroke = lerpf(_stroke, snappedf(_stroke, TAU), delta)
	for r in rowers:
		r.row_phase = _stroke


func _process(_delta: float) -> void:
	_place_oars()
	# The tiller swings opposite to the turn it makes.
	tiller.rotation.y = TILLER_YAW - _steer * 0.32


## Lays each manned oar from its oarlock through the rower's two hands, so
## the man is holding it wherever his stroke has brought them.
func _place_oars() -> void:
	if _oars == null:
		return
	for i in OARS_A_SIDE * 2:
		var side := -1.0 if i < OARS_A_SIDE else 1.0
		var lock := Vector3(side * (BEAM * 0.5 - 0.1), 0.85, station_z(i % OARS_A_SIDE))
		var out := Vector3(side, 0.0, 0.0)
		if _manned.has(i) and is_instance_valid(_manned[i]):
			var g := (_manned[i] as Humanoid).grip_points()
			var grip := _hull.to_local((g[0] + g[1]) * 0.5)
			out = lock - grip
		elif _lost.has(i):
			# Let go: the oar swings back along the hull and trails in the water.
			out = Vector3(side * 0.35, -0.22, 1.0)
		else:
			# No man at it: the oar is not shipped. Drawn at no size.
			_set_oar(i, Transform3D(Basis().scaled(Vector3.ZERO), lock))
			continue
		var x := out.normalized()
		var z := x.cross(Vector3.UP).normalized()
		var y := z.cross(x)
		_set_oar(i, Transform3D(Basis(x, y, z), lock))


func _set_oar(i: int, xf: Transform3D) -> void:
	if _oar_xf.size() < OARS_A_SIDE * 2:
		_oar_xf.resize(OARS_A_SIDE * 2)
	_oar_xf[i] = xf
	_oars.set_instance_transform(i, xf)


## Oar [param station]'s transform in the hull's space: the oarlock, and +X
## out along the loom to the blade.
func oar_transform(station: int) -> Transform3D:
	return _oar_xf[station] if station < _oar_xf.size() else Transform3D()


# --- shapes -------------------------------------------------------------------------

## Half the beam at [param v] (0 the stem, 1 the stern). The sea keeps out of
## this plan: keep sea.gdshader's hull mask in step.
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
			# Crowned, but meeting the planking on both edges: no gap to see the sea through.
			return a.lerp(b, u) + Vector3(0, 0.035 * sin(PI * u), 0)
		Sculpt.grid(gb, &"hide", 3, 40, cap, Color(0.3, 0.2, 0.12), false, Vector3(0, -30, 0))
	# Deck planks, benches.
	gb.box(&"wood", Transform3D(Basis.IDENTITY, Vector3(0, 0.12, 0)), Vector3(BEAM * 0.6, 0.05, LENGTH * 0.72), Color.WHITE, false, 0)
	# A thwart for each pair of oars, just forward of the oarlocks.
	for k in range(1, OARS_A_SIDE - 1):
		var z := station_z(k) - 0.55
		gb.box(&"wood", Transform3D(Basis.IDENTITY, Vector3(0, 0.45, z)), Vector3(_half_beam(z / LENGTH + 0.5) * 2.0 - 0.15, 0.07, 0.3), Color.WHITE, false, 0)
	# Oarlocks: a thole pin and its leather loop at each station.
	for k in OARS_A_SIDE:
		for side: float in [-1.0, 1.0]:
			gb.box(&"hide", Transform3D(Basis.IDENTITY, Vector3(side * (BEAM * 0.5 - 0.1), 0.95, station_z(k) - 0.06)), Vector3(0.05, 0.22, 0.05),
				Color(0.3, 0.2, 0.12), false, 0)
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


## Spray thrown off the stem: white drops flung up and aft, falling back.
static func _bow_spray() -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = 60
	p.lifetime = 1.3
	p.local_coords = false
	p.emitting = false
	p.direction = Vector3(0.0, 1.0, 0.5)
	p.spread = 55.0
	p.initial_velocity_min = 3.0
	p.initial_velocity_max = 7.5
	p.gravity = Vector3(0, -9.8, 0)
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(0.9, 0.2, 0.4)
	p.scale_amount_min = 0.25
	p.scale_amount_max = 0.9
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 0.85))
	fade.set_color(1, Color(1, 1, 1, 0.0))
	p.color_ramp = fade
	var quad := QuadMesh.new()
	quad.size = Vector2(0.6, 0.6)
	var m := StandardMaterial3D.new()
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.albedo_color = Color(0.92, 0.96, 0.97)
	var dot := GradientTexture2D.new()
	dot.fill = GradientTexture2D.FILL_RADIAL
	dot.fill_from = Vector2(0.5, 0.5)
	dot.fill_to = Vector2(1.0, 0.5)
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	dot.gradient = g
	m.albedo_texture = dot
	quad.material = m
	p.mesh = quad
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return p


## The tiller: a bar from the head of the steering oar in toward the helmsman (-X).
static func tiller_mesh() -> ArrayMesh:
	var gb := GeoBuilder.new()
	gb.chunk_size = 0.0
	var wood := Color(0.42, 0.29, 0.17)
	gb.box(&"hide", Transform3D(Basis(Vector3(0, 0, 1), 0.04), Vector3(-0.72, -0.03, 0.06)), Vector3(1.5, 0.06, 0.07), wood, false, 0)
	# The head of the loom, with a lashing where the tiller is socketed.
	gb.box(&"hide", Transform3D(Basis.IDENTITY, Vector3(0.0, -0.1, 0.0)), Vector3(0.14, 0.34, 0.14), wood.darkened(0.2), false, 0)
	gb.box(&"hide", Transform3D(Basis.IDENTITY, Vector3(-0.08, -0.02, 0.03)), Vector3(0.12, 0.08, 0.1), Color(0.6, 0.5, 0.32), false, 0)
	return gb.build_mesh(Mats.all())


## Turn [param i] of the rope binding a man to the mast: a loop round the
## mast and his body, from the shins up to the chest.
static func bond_mesh(i: int) -> ArrayMesh:
	var gb := GeoBuilder.new()
	gb.chunk_size = 0.0
	var y: float = [1.35, 1.15, 0.95, 0.72, 0.45][i]
	var centre := Vector3(0.0, y, -1.18)
	var loop := func(u: float, v: float) -> Vector3:
		var a := u * TAU
		var ring := Vector3(cos(a) * 0.3, sin(a * 2.0 + float(i)) * 0.02, sin(a) * 0.36)
		var out := Vector3(cos(a), 0.0, sin(a) * 1.2).normalized()
		return centre + ring + out * cos(v * TAU) * 0.016 + Vector3(0, sin(v * TAU) * 0.016, 0)
	Sculpt.grid(gb, &"hide", 24, 4, loop, Color(0.6, 0.5, 0.33), true, centre)
	return gb.build_mesh(Mats.all())


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


## One oar, pivoting at the gunwale, its blade out over the water (+X) and
## its handle reaching 1.3 m inboard (-X), with a grip worn dark by hands.
static func oar_mesh() -> ArrayMesh:
	var gb := GeoBuilder.new()
	gb.chunk_size = 0.0
	gb.box(&"hide", Transform3D(Basis.IDENTITY, Vector3(1.3, 0.0, 0.0)), Vector3(5.2, 0.06, 0.06), Color(0.5, 0.36, 0.22), false, 0)
	gb.box(&"hide", Transform3D(Basis.IDENTITY, Vector3(-0.95, 0.0, 0.0)), Vector3(0.7, 0.07, 0.07), Color(0.32, 0.22, 0.14), false, 0)
	gb.box(&"hide", Transform3D(Basis.IDENTITY, Vector3(3.6, 0.0, 0.0)), Vector3(0.9, 0.03, 0.2), Color(0.45, 0.32, 0.2), false, 0)
	var m := gb.build_mesh(Mats.all())
	return m
