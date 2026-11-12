class_name TroyBuilder
extends RefCounted
## Generates the fortifications and buildings of Troy VI/VIIa from
## [TroyLayout]. Output is static geometry in [member b] plus [member info],
## the list of things missions need to find (gates, torches, hearths, houses).

## Citadel wall: battered limestone below, mudbrick breastwork above.
const CITADEL_WALL := {
	"stone_h": 6.0, "out_base": 3.0, "out_top": 1.4, "inner": -2.0, "super_h": 2.4,
	"super_out": 1.25, "parapet_h": 1.05, "merlon_h": 0.75, "parapet_t": 0.6, "depth": 3.0,
	"stone": &"limestone", "upper": &"mudbrick", "step": 0.14,
}
## Lower-town wall: mudbrick on a fieldstone footing (a reconstruction; the
## excavated evidence is the ditch and traces of a palisade and gate).
const LOWER_WALL := {
	"stone_h": 1.6, "out_base": 1.75, "out_top": 1.45, "inner": -1.3, "super_h": 4.6,
	"super_out": 1.35, "parapet_h": 1.0, "merlon_h": 0.65, "parapet_t": 0.5, "depth": 2.0,
	"stone": &"rubble", "upper": &"mudbrick", "step": 0.0,
}

const PLASTER_TINTS: Array[Color] = [
	Color(1.0, 0.97, 0.90), Color(0.93, 0.86, 0.76), Color(1.05, 1.0, 0.92),
	Color(0.96, 0.84, 0.72), Color(0.88, 0.84, 0.78), Color(1.02, 0.92, 0.80),
]

var b := GeoBuilder.new()
var rng := RandomNumberGenerator.new()
## Things the rest of the game needs to locate. See [method build].
var info := {
	"torches": [],
	"gates": {},
	"houses": [],
	"hearths": [],
	"markers": {},
	"pithoi": [],
	"trees": [],
	"awnings": [],
	"columns": [],
}

var _streets: Array = []
var _footprints: Array = []
var _clearings: Array = []


func _init(seed_value: int = 1184) -> void:
	rng.seed = seed_value


## Builds every static structure into [member b]. Call [method GeoBuilder.commit] after.
func build() -> void:
	_streets = street_segments()
	_citadel_walls()
	_lower_walls()
	_summit()
	_citadel_houses()
	_lower_town()
	_streets_paving()
	_outside()


# --- frames and small helpers -------------------------------------------------

static func _v3(p: Vector2, y: float) -> Vector3:
	return Vector3(p.x, y, p.y)


## Frame at plan point [param c] whose local +Z runs along [param n].
static func frame(c: Vector2, n: Vector2, y: float) -> Transform3D:
	var z := Vector3(n.x, 0.0, n.y).normalized()
	var x := Vector3(z.z, 0.0, -z.x)
	return Transform3D(Basis(x, Vector3.UP, z), Vector3(c.x, y, c.y))


static func _yaw_frame(c: Vector2, yaw: float, y: float) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, yaw), Vector3(c.x, y, c.y))


func _alpha(col: Color, a: float) -> Color:
	return Color(col.r, col.g, col.b, a)


func _ground_range(xf: Transform3D, w: float, d: float) -> Vector2:
	var lo := INF
	var hi := -INF
	for sx: float in [-0.5, 0.0, 0.5]:
		for sz: float in [-0.5, 0.0, 0.5]:
			var p := xf * Vector3(sx * w, 0.0, sz * d)
			var h := TroyLayout.height(p.x, p.z)
			lo = minf(lo, h)
			hi = maxf(hi, h)
	return Vector2(lo, hi)


## Streets as [a, b, width] plan segments. Shared by paving, house placement
## and the AI's sense of where the roads run.
static func street_segments() -> Array:
	var pl := TroyLayout.places()
	var south: Vector2 = pl["south_gate"]
	var agora: Vector2 = pl["agora"]
	var scaean: Vector2 = pl["scaean_gate"]
	var s_in := scaean - TroyLayout.lower_normal(TroyLayout.SCAEAN_GATE_DEG) * 10.0
	var dardan: Vector2 = pl["dardanian_gate"]
	var d_in := dardan - TroyLayout.lower_normal(TroyLayout.DARDANIAN_GATE_DEG) * 10.0
	var east: Vector2 = pl["east_gate"]
	var e_out := east + TroyLayout.citadel_normal(TroyLayout.EAST_GATE_DEG) * 16.0
	var segs: Array = [
		# Citadel ramp from the South Gate up to the court.
		[Vector2(0.0, 36.0), south, 6.0, true],
		[south, agora, 7.0, true],
		# The Scaean Way.
		[agora, Vector2(-96.0, 140.0), 7.5, true],
		[Vector2(-96.0, 140.0), s_in, 7.5, true],
		[s_in, scaean, 7.5, true],
		# The Dardanian Way.
		[agora, Vector2(82.0, 172.0), 6.0, false],
		[Vector2(82.0, 172.0), d_in, 6.0, false],
		[d_in, dardan, 6.0, false],
		# South road and cross lanes.
		[agora, Vector2(0.0, 296.0), 5.0, false],
		[Vector2(-96.0, 140.0), Vector2(-70.0, 286.0), 4.5, false],
		[Vector2(82.0, 172.0), Vector2(60.0, 292.0), 4.5, false],
		[Vector2(-150.0, 110.0), Vector2(-96.0, 140.0), 4.5, false],
		[e_out, Vector2(150.0, 96.0), 5.0, false],
		[Vector2(150.0, 96.0), Vector2(82.0, 172.0), 4.5, false],
		[Vector2(-70.0, 286.0), Vector2(60.0, 292.0), 4.5, false],
		[Vector2(-160.0, 232.0), Vector2(-70.0, 286.0), 4.5, false],
	]
	# Pomerium lane round the foot of the citadel wall (south half).
	var prev := TroyLayout.citadel_point(-2.0, 1.15)
	for deg in range(8, 184, 10):
		var p := TroyLayout.citadel_point(float(deg), 1.15)
		segs.append([prev, p, 5.0, false])
		prev = p
	# Ring lane inside the lower wall.
	var span := TroyLayout.lower_wall_span()
	prev = TroyLayout.lower_point(span.y + 8.0, 0.925)
	var deg_f := span.y + 16.0
	while deg_f < span.x - 6.0:
		var p := TroyLayout.lower_point(deg_f, 0.925)
		segs.append([prev, p, 4.5, false])
		prev = p
		deg_f += 8.0
	# Citadel terrace lane.
	prev = TroyLayout.citadel_point(0.0, 0.6)
	for deg in range(12, 361, 12):
		var p := TroyLayout.citadel_point(float(deg), 0.6)
		segs.append([prev, p, 4.5, false])
		prev = p
	segs.append([east - TroyLayout.citadel_normal(TroyLayout.EAST_GATE_DEG) * 2.0,
		TroyLayout.citadel_point(TroyLayout.EAST_GATE_DEG, 0.6), 4.0, false])
	return segs


func _street_dist(p: Vector2) -> float:
	var best := INF
	for s: Array in _streets:
		var a: Vector2 = s[0]
		var ab: Vector2 = (s[1] as Vector2) - a
		var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
		var d := p.distance_to(a + ab * t) - (s[2] as float) * 0.5
		best = minf(best, d)
	return best


func _nearest_street_dir(p: Vector2) -> Vector2:
	var best := INF
	var dir := Vector2.RIGHT
	for s: Array in _streets:
		var a: Vector2 = s[0]
		var ab: Vector2 = (s[1] as Vector2) - a
		var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
		var q := a + ab * t
		var d := p.distance_to(q)
		if d < best:
			best = d
			# Face the street: the direction from the lot to the road.
			dir = (q - p).normalized() if d > 0.01 else ab.normalized().orthogonal()
	return dir


# --- fortifications -------------------------------------------------------------

func _joint(c: Vector2, n: Vector2) -> Dictionary:
	return {"c": c, "n": n, "g": TroyLayout.height(c.x, c.y)}


func _wp(j: Dictionary, off: float, y: float, st: float = 0.0) -> Vector3:
	var q: Vector2 = (j["c"] as Vector2) + (j["n"] as Vector2) * (off + st)
	return Vector3(q.x, (j["g"] as float) + y, q.y)


func _wall_cap(j: Dictionary, s: Dictionary, st: float, hint: Vector3) -> void:
	var k: float = (s["out_base"] - s["out_top"]) / s["stone_h"]
	var depth: float = s["depth"]
	var ob: float = s["out_top"] + k * (s["stone_h"] + depth)
	var sh: float = s["stone_h"]
	var walk: float = sh + s["super_h"]
	var top: float = walk + s["parapet_h"]
	var inner: float = s["inner"]
	var so: float = s["super_out"]
	var pin: float = so - s["parapet_t"]
	var white := Color.WHITE
	b.quad_h(s["stone"], _wp(j, inner, -depth), _wp(j, ob, -depth, st), _wp(j, s["out_top"], sh, st),
		_wp(j, inner, sh), hint, white)
	b.quad_h(s["upper"], _wp(j, inner, sh), _wp(j, so, sh, st), _wp(j, so, walk, st),
		_wp(j, inner, walk), hint, _alpha(white, 0.2), true, _alpha(white, 0.9))
	b.quad_h(s["upper"], _wp(j, pin, walk, st), _wp(j, so, walk, st), _wp(j, so, top, st),
		_wp(j, pin, top, st), hint, _alpha(white, 0.9), true, _alpha(white, 1.0))


## One straight run of curtain wall between two joints.
func _wall_span(j0: Dictionary, j1: Dictionary, s: Dictionary, merlons: bool = true) -> void:
	var st: float = s["step"]
	var k: float = (s["out_base"] - s["out_top"]) / s["stone_h"]
	var depth: float = s["depth"]
	var ob: float = s["out_top"] + k * (s["stone_h"] + depth)
	var sh: float = s["stone_h"]
	var walk: float = sh + s["super_h"]
	var top: float = walk + s["parapet_h"]
	var inner: float = s["inner"]
	var ot: float = s["out_top"]
	var so: float = s["super_out"]
	var pin: float = so - s["parapet_t"]
	var n3 := _v3(((j0["n"] as Vector2) + (j1["n"] as Vector2)).normalized(), 0.0)
	var dir := _v3(((j1["c"] as Vector2) - (j0["c"] as Vector2)).normalized(), 0.0)
	var white := Color.WHITE
	var stone: StringName = s["stone"]
	var upper: StringName = s["upper"]
	var a0 := _alpha(white, 0.0)
	var a1 := _alpha(white, 1.0)
	# Outer stone face, battered.
	b.quad_h(stone, _wp(j0, ob, -depth, st), _wp(j1, ob, -depth), _wp(j1, ot, sh), _wp(j0, ot, sh, st), n3, white)
	# Ledge where the brickwork steps back.
	b.quad_h(stone, _wp(j0, so, sh, st), _wp(j1, so, sh), _wp(j1, ot, sh), _wp(j0, ot, sh, st), Vector3.UP, white)
	# Outer brick face and breastwork.
	b.quad_h(upper, _wp(j0, so, sh, st), _wp(j1, so, sh), _wp(j1, so, top), _wp(j0, so, top, st), n3, a0, true, a1)
	b.quad_h(upper, _wp(j0, pin, top, st), _wp(j1, pin, top), _wp(j1, so, top), _wp(j0, so, top, st), Vector3.UP, a1)
	b.quad_h(upper, _wp(j0, pin, walk, st), _wp(j1, pin, walk), _wp(j1, pin, top), _wp(j0, pin, top, st), -n3,
		_alpha(white, 0.5), true, a1)
	# Wall walk.
	b.quad_h(&"roof", _wp(j0, inner, walk), _wp(j1, inner, walk), _wp(j1, pin, walk), _wp(j0, pin, walk, st),
		Vector3.UP, a1)
	# Inner faces.
	b.quad_h(upper, _wp(j0, inner, sh), _wp(j1, inner, sh), _wp(j1, inner, walk), _wp(j0, inner, walk), -n3, a0, true, a1)
	b.quad_h(stone, _wp(j0, inner, -depth), _wp(j1, inner, -depth), _wp(j1, inner, sh), _wp(j0, inner, sh), -n3, white)
	_wall_cap(j0, s, st, -dir)
	_wall_cap(j1, s, 0.0, dir)
	if merlons:
		var e0 := _wp(j0, so - s["parapet_t"] * 0.5, top, st)
		var e1 := _wp(j1, so - s["parapet_t"] * 0.5, top)
		var length := e0.distance_to(e1)
		var count := int(length / 1.9)
		var tangent := (e1 - e0).normalized()
		var basis := Basis(tangent, Vector3.UP, tangent.cross(Vector3.UP) * -1.0)
		for i in count:
			var p := e0.lerp(e1, (i + 0.5) / count)
			b.frustum(upper, Transform3D(basis, p), Vector2(1.15, s["parapet_t"]),
				Vector2(0.8, s["parapet_t"]), s["merlon_h"], a1, false)


## A rectangular tower astride the wall at plan point [param c].
## Returns the height of its fighting platform.
func _tower(c: Vector2, n: Vector2, width: float, project: float, s: Dictionary,
		extra_h: float = 2.6, label: String = "") -> float:
	var g := TroyLayout.height(c.x, c.y)
	var inner: float = (s["inner"] as float) - 0.6
	var depth_len := project - inner
	var xf := frame(c + n * ((project + inner) * 0.5), n, g - (s["depth"] as float))
	var sh: float = (s["stone_h"] as float) + 1.2
	var walk: float = (s["stone_h"] as float) + (s["super_h"] as float)
	var plat := walk + extra_h
	var batter := 0.16 * (sh + (s["depth"] as float))
	var white := Color.WHITE
	b.frustum(s["stone"], xf, Vector2(width + batter * 2.0, depth_len + batter),
		Vector2(width, depth_len), sh + (s["depth"] as float), white, true, false)
	var up := xf.translated_local(Vector3(0.0, sh + (s["depth"] as float), 0.0))
	var bh := plat - sh
	b.box(s["upper"], up.translated_local(Vector3(0.0, bh * 0.5, 0.0)),
		Vector3(width - 0.3, bh, depth_len - 0.3), _alpha(white, 0.0), true, 8 | 4, _alpha(white, 1.0))
	var top := xf.translated_local(Vector3(0.0, plat + (s["depth"] as float), 0.0))
	b.quad_h(&"roof", top * Vector3(-width * 0.5 + 0.15, 0, -depth_len * 0.5 + 0.15),
		top * Vector3(width * 0.5 - 0.15, 0, -depth_len * 0.5 + 0.15),
		top * Vector3(width * 0.5 - 0.15, 0, depth_len * 0.5 - 0.15),
		top * Vector3(-width * 0.5 + 0.15, 0, depth_len * 0.5 - 0.15), Vector3.UP, white)
	# Breastwork on three sides; the town side is left open with a low kerb.
	var t := 0.5
	var ph := 1.05
	var hw := width * 0.5 - 0.15
	var hd := depth_len * 0.5 - 0.15
	b.box(s["upper"], top.translated_local(Vector3(0.0, ph * 0.5, hd - t * 0.5)), Vector3(hw * 2.0, ph, t),
		_alpha(white, 0.8), true, 8, _alpha(white, 1.0))
	b.box(s["upper"], top.translated_local(Vector3(hw - t * 0.5, ph * 0.5, 0.0)), Vector3(t, ph, hd * 2.0),
		_alpha(white, 0.8), true, 8, _alpha(white, 1.0))
	b.box(s["upper"], top.translated_local(Vector3(-hw + t * 0.5, ph * 0.5, 0.0)), Vector3(t, ph, hd * 2.0),
		_alpha(white, 0.8), true, 8, _alpha(white, 1.0))
	b.box(s["upper"], top.translated_local(Vector3(0.0, 0.2, -hd + 0.2)), Vector3(hw * 2.0, 0.4, 0.4),
		_alpha(white, 0.9), true, 8)
	var mh: float = s["merlon_h"]
	var count := int(width / 1.9)
	for i in count:
		var x := lerpf(-hw + 0.6, hw - 0.6, (i + 0.5) / count)
		b.frustum(s["upper"], top.translated_local(Vector3(x, ph, hd - t * 0.5)), Vector2(1.15, t),
			Vector2(0.8, t), mh, _alpha(white, 1.0), false)
	count = int(depth_len / 1.9)
	for i in count:
		var z := lerpf(-hd + 0.6, hd - 0.6, (i + 0.5) / count)
		for side: float in [-1.0, 1.0]:
			b.frustum(s["upper"], top.translated_local(Vector3(side * (hw - t * 0.5), ph, z)),
				Vector2(t, 1.15), Vector2(t, 0.8), mh, _alpha(white, 1.0), false)
	# Steps from the wall walk on both flanks up to the platform.
	for side: float in [-1.0, 1.0]:
		var run := extra_h * 1.45
		var start := xf.translated_local(Vector3(side * (width * 0.5 + run), walk + (s["depth"] as float),
			-depth_len * 0.5 + 1.45))
		var sbasis := Basis(Vector3(0, 0, 1) * side, Vector3.UP, Vector3(-1, 0, 0) * side)
		b.stairs(s["upper"], Transform3D(start.basis * sbasis, start.origin), 1.5, extra_h, run, 8,
			_alpha(white, 0.9))
	if label != "":
		info["markers"][label] = top.origin + Vector3(0.0, 0.1, 0.0)
	return g + plat


## The lintel, threshold and records for a gate through a wall.
func _gate(name: String, c: Vector2, n: Vector2, width: float, passage_h: float, s: Dictionary) -> void:
	var g := TroyLayout.height(c.x, c.y)
	var xf := frame(c, n, g)
	var inner: float = s["inner"]
	var so: float = s["super_out"]
	var walk: float = (s["stone_h"] as float) + (s["super_h"] as float)
	var top: float = walk + (s["parapet_h"] as float)
	var white := Color.WHITE
	var span := width + 1.2
	var mid := (so + inner) * 0.5
	var thick := so - inner
	# Timber lintel beams, then brickwork up to the wall walk.
	b.box(&"wood_dark", xf.translated_local(Vector3(0.0, passage_h + 0.2, mid)), Vector3(span, 0.4, thick + 0.3),
		white, true, 0)
	b.box(s["upper"], xf.translated_local(Vector3(0.0, (passage_h + 0.4 + walk) * 0.5, mid)),
		Vector3(span, walk - passage_h - 0.4, thick), _alpha(white, 0.5), true, 8 | 4, _alpha(white, 1.0))
	b.quad_h(&"roof", xf * Vector3(-span * 0.5, walk, inner), xf * Vector3(span * 0.5, walk, inner),
		xf * Vector3(span * 0.5, walk, so), xf * Vector3(-span * 0.5, walk, so), Vector3.UP, white)
	var pt: float = s["parapet_t"]
	b.box(s["upper"], xf.translated_local(Vector3(0.0, walk + (top - walk) * 0.5, so - pt * 0.5)),
		Vector3(span, top - walk, pt), _alpha(white, 0.9), true, 8, _alpha(white, 1.0))
	var count := int(span / 1.9)
	for i in count:
		var x := lerpf(-span * 0.5 + 0.6, span * 0.5 - 0.6, (i + 0.5) / maxi(count, 1))
		b.frustum(s["upper"], xf.translated_local(Vector3(x, top, so - pt * 0.5)), Vector2(1.15, pt),
			Vector2(0.8, pt), s["merlon_h"], _alpha(white, 1.0), false)
	# Threshold and paved passage.
	b.box(&"paving", xf.translated_local(Vector3(0.0, -0.4, mid + 0.6)), Vector3(width + 0.4, 0.92, thick + 4.0),
		white, true, 8)
	info["gates"][name] = {
		"pos": Vector3(c.x, g + 0.06, c.y), "normal": Vector3(n.x, 0.0, n.y), "width": width,
		"height": passage_h, "door_offset": so - 0.55,
	}
	info["markers"][name] = Vector3(c.x, g, c.y)
	# Torches either side, within and without.
	for side: float in [-1.0, 1.0]:
		info["torches"].append(xf * Vector3(side * (width * 0.5 + 0.9), 2.6, so + 0.5))
		info["torches"].append(xf * Vector3(side * (width * 0.5 + 0.9), 2.6, inner - 0.4))


func _wall_stairs(c: Vector2, n: Vector2, s: Dictionary, dir_sign: float) -> void:
	var g := TroyLayout.height(c.x, c.y)
	var walk: float = (s["stone_h"] as float) + (s["super_h"] as float)
	var run := walk * 1.5
	var xf := frame(c, n, g)
	var origin := xf * Vector3(-dir_sign * run * 0.5, -0.3, (s["inner"] as float) - 0.85)
	var sbasis := xf.basis * Basis(Vector3(0, 0, -1) * dir_sign, Vector3.UP, Vector3(1, 0, 0) * dir_sign)
	b.stairs(s["stone"], Transform3D(sbasis, origin), 1.7, walk + 0.3, run, int(walk / 0.3), Color.WHITE)


func _citadel_walls() -> void:
	var s := CITADEL_WALL
	var gates := [[TroyLayout.SOUTH_GATE_DEG, 1.25], [TroyLayout.EAST_GATE_DEG, 1.3]]
	var breaks: Array[float] = []
	for i in 60:
		breaks.append(i * 6.0)
	for gt: Array in gates:
		breaks.append(gt[0] - gt[1])
		breaks.append(gt[0] + gt[1])
	breaks.sort()
	for i in breaks.size():
		var d0 := breaks[i]
		var d1 := breaks[(i + 1) % breaks.size()]
		if d1 < d0:
			d1 += 360.0
		if d1 - d0 < 0.05:
			continue
		var mid := (d0 + d1) * 0.5
		var in_gate := false
		for gt: Array in gates:
			if absf(wrapf(mid - (gt[0] as float), -180.0, 180.0)) < (gt[1] as float):
				in_gate = true
		if in_gate:
			continue
		_wall_span(_joint(TroyLayout.citadel_point(d0), TroyLayout.citadel_normal(d0)),
			_joint(TroyLayout.citadel_point(d1), TroyLayout.citadel_normal(d1)), s)

	# South Gate (VI T), the principal entrance, with Tower VI i on its west flank.
	var sd := TroyLayout.SOUTH_GATE_DEG
	_gate("south_gate", TroyLayout.citadel_point(sd), TroyLayout.citadel_normal(sd), 4.2, 4.6, s)
	_tower(TroyLayout.citadel_point(sd + 5.4), TroyLayout.citadel_normal(sd + 5.4), 9.5, 7.5, s, 2.6, "tower_vi_i")
	# The stelae before the tower: standing stones of a gate cult.
	var tower_c := TroyLayout.citadel_point(sd + 5.4)
	var tower_n := TroyLayout.citadel_normal(sd + 5.4)
	var txf := frame(tower_c + tower_n * 9.4, tower_n, TroyLayout.height(tower_c.x, tower_c.y + 9.0))
	for i in 4:
		var hgt := 1.5 + 0.35 * sin(i * 2.1)
		b.frustum(&"ashlar", txf.translated_local(Vector3(-3.0 + i * 2.0, -0.3, 0.0)), Vector2(0.75, 0.42),
			Vector2(0.62, 0.34), hgt + 0.3, Color(0.92, 0.9, 0.86))
	info["markers"]["stelae"] = txf.origin

	# East Gate (VI S): entered sideways behind an overlapping curtain.
	var ed := TroyLayout.EAST_GATE_DEG
	_gate("east_gate", TroyLayout.citadel_point(ed), TroyLayout.citadel_normal(ed), 3.4, 4.2, s)
	var c0 := TroyLayout.citadel_point(ed - 4.0) + TroyLayout.citadel_normal(ed - 4.0) * 7.5
	var c1 := TroyLayout.citadel_point(ed + 7.5) + TroyLayout.citadel_normal(ed + 7.5) * 7.5
	var c2 := TroyLayout.citadel_point(ed + 7.5) + TroyLayout.citadel_normal(ed + 7.5) * 2.0
	var nn := TroyLayout.citadel_normal(ed + 2.0)
	_wall_span(_joint(c0, nn), _joint(c1, nn), s)
	var side_n := (c1 - c0).normalized()
	_wall_span(_joint(c1, side_n), _joint(c2, side_n), s, false)

	# West Gate (VI U): walled up in Troy VIIa. The blocking shows as rougher work.
	var wd := TroyLayout.WEST_GATE_DEG
	var wc := TroyLayout.citadel_point(wd)
	var wn := TroyLayout.citadel_normal(wd)
	var wxf := frame(wc, wn, TroyLayout.height(wc.x, wc.y))
	for off: Array in [[2.3, 0.26], [-2.05, 0.0]]:
		var tilt := wxf.translated_local(Vector3(0.0, 2.0, off[0]))
		tilt.basis = tilt.basis * Basis(Vector3.RIGHT, off[1])
		b.box(&"rubble", tilt, Vector3(3.6, 4.2, 0.25), Color(0.86, 0.84, 0.8), false, 8)
	info["markers"]["west_gate"] = _v3(wc, TroyLayout.height(wc.x, wc.y))

	# North-East Bastion (VI g) over the cistern, and Tower VI h on the east wall.
	var nd := TroyLayout.NE_BASTION_DEG
	_tower(TroyLayout.citadel_point(nd), TroyLayout.citadel_normal(nd), 18.0, 9.0, s, 3.4, "ne_bastion")
	_tower(TroyLayout.citadel_point(-8.0), TroyLayout.citadel_normal(-8.0), 11.0, 8.0, s, 2.6, "tower_vi_h")

	# Stairs up to the wall walk.
	for sd2: Array in [[78.0, 1.0], [112.0, -1.0], [200.0, 1.0], [300.0, 1.0], [36.0, -1.0]]:
		_wall_stairs(TroyLayout.citadel_point(sd2[0]), TroyLayout.citadel_normal(sd2[0]), s, sd2[1])


func _lower_walls() -> void:
	var s := LOWER_WALL
	var span := TroyLayout.lower_wall_span()
	var east := span.y
	var west := span.x
	var gates := [[TroyLayout.SCAEAN_GATE_DEG, 0.95], [TroyLayout.DARDANIAN_GATE_DEG, 0.8]]
	var breaks: Array[float] = [east, west]
	var d := ceilf(east / 3.0) * 3.0
	while d < west:
		if d > east + 0.5 and d < west - 0.5:
			breaks.append(d)
		d += 3.0
	for gt: Array in gates:
		breaks.append(gt[0] - gt[1])
		breaks.append(gt[0] + gt[1])
	breaks.sort()
	for i in breaks.size() - 1:
		var d0 := breaks[i]
		var d1 := breaks[i + 1]
		if d1 - d0 < 0.05:
			continue
		var mid := (d0 + d1) * 0.5
		var in_gate := false
		for gt: Array in gates:
			if absf(mid - (gt[0] as float)) < (gt[1] as float):
				in_gate = true
		if in_gate:
			continue
		_wall_span(_joint(TroyLayout.lower_point(d0), TroyLayout.lower_normal(d0)),
			_joint(TroyLayout.lower_point(d1), TroyLayout.lower_normal(d1)), s)

	# The Scaean Gate, facing the plain, between two towers. The northern one
	# is the "great tower of Ilios" from which the elders watched the war.
	var sg := TroyLayout.SCAEAN_GATE_DEG
	_gate("scaean_gate", TroyLayout.lower_point(sg), TroyLayout.lower_normal(sg), 5.0, 5.0, s)
	_tower(TroyLayout.lower_point(sg + 3.1), TroyLayout.lower_normal(sg + 3.1), 9.0, 6.5, s, 3.2, "great_tower")
	_tower(TroyLayout.lower_point(sg - 3.1), TroyLayout.lower_normal(sg - 3.1), 8.0, 6.0, s, 2.4, "scaean_south_tower")
	_wall_stairs(TroyLayout.lower_point(sg + 7.0), TroyLayout.lower_normal(sg + 7.0), s, -1.0)
	_wall_stairs(TroyLayout.lower_point(sg - 7.0), TroyLayout.lower_normal(sg - 7.0), s, 1.0)

	var dg := TroyLayout.DARDANIAN_GATE_DEG
	_gate("dardanian_gate", TroyLayout.lower_point(dg), TroyLayout.lower_normal(dg), 4.2, 4.6, s)
	_tower(TroyLayout.lower_point(dg + 2.6), TroyLayout.lower_normal(dg + 2.6), 7.0, 5.0, s, 2.4)
	_tower(TroyLayout.lower_point(dg - 2.6), TroyLayout.lower_normal(dg - 2.6), 7.0, 5.0, s, 2.4)
	_wall_stairs(TroyLayout.lower_point(dg + 6.5), TroyLayout.lower_normal(dg + 6.5), s, -1.0)

	# Interval towers.
	for deg: float in [-30.0, 0.0, 70.0, 100.0, 130.0, 196.0, 222.0]:
		_tower(TroyLayout.lower_point(deg), TroyLayout.lower_normal(deg), 6.5, 4.5, s, 2.2)


# --- buildings ---------------------------------------------------------------------

func _column(base: Vector3, height: float, radius: float = 0.24) -> void:
	# Aegean column: timber shaft tapering downward, on a stone base.
	b.cylinder(&"ashlar", base, radius * 1.7, radius * 1.6, 0.18, 12, Color.WHITE, false)
	b.cylinder(&"wood_red", base + Vector3(0, 0.18, 0), radius * 0.82, radius, height - 0.62, 12, Color.WHITE, false, false)
	var profile := PackedVector2Array([Vector2(radius, 0.0), Vector2(radius * 1.5, 0.1),
		Vector2(radius * 1.62, 0.2), Vector2(radius * 1.2, 0.3)])
	b.lathe(&"wood_dark", Transform3D(Basis.IDENTITY, base + Vector3(0, height - 0.44, 0)), profile, 12)
	b.box(&"wood_dark", Transform3D(Basis.IDENTITY, base + Vector3(0, height - 0.07, 0)),
		Vector3(radius * 3.4, 0.14, radius * 3.4), Color.WHITE, false, 0)
	info["columns"].append({"pos": base, "h": height, "r": radius * 1.3})


func _beam_ends(xf: Transform3D, length: float, y: float, z: float, spacing: float = 0.72) -> void:
	var count := int(length / spacing)
	for i in count:
		var x := lerpf(-length * 0.5 + 0.3, length * 0.5 - 0.3, (i + 0.5) / maxi(count, 1))
		var out := 0.14 * signf(z)
		b.box(&"wood_dark", xf.translated_local(Vector3(x, y, z + out)), Vector3(0.15, 0.15, 0.3),
			Color.WHITE, false, 0)


func _window(xf: Transform3D, pos: Vector3, facing: Vector3, size: float = 0.46) -> void:
	# A small high opening: dark inset, timber lintel and sill.
	var right := facing.cross(Vector3.UP).normalized()
	var o := pos + facing * 0.012
	var hs := size * 0.5
	b.quad_h(&"dark", xf * (o - right * hs - Vector3(0, hs, 0)), xf * (o + right * hs - Vector3(0, hs, 0)),
		xf * (o + right * hs + Vector3(0, hs, 0)), xf * (o - right * hs + Vector3(0, hs, 0)),
		xf.basis * facing, Color.WHITE, false)
	var lintel := Transform3D(Basis(right, Vector3.UP, facing), pos + Vector3(0, hs + 0.05, 0))
	b.box(&"wood_dark", xf * lintel, Vector3(size + 0.24, 0.1, 0.1), Color.WHITE, false, 0)


## A wall panel on the local +Z face with one doorway recessed into it.
func _front_with_door(xf: Transform3D, w: float, h: float, z: float, door_x: float, door_w: float,
		door_h: float, tint: Color, wall_mat: StringName, recess: float = 0.3) -> void:
	var fwd := xf.basis * Vector3(0, 0, 1)
	var x0 := -w * 0.5
	var x1 := w * 0.5
	var dl := door_x - door_w * 0.5
	var dr := door_x + door_w * 0.5
	var a0 := _alpha(tint, 0.0)
	var ah := _alpha(tint, 1.0)
	var ad := _alpha(tint, door_h / h)
	b.quad_h(wall_mat, xf * Vector3(x0, 0, z), xf * Vector3(dl, 0, z), xf * Vector3(dl, h, z), xf * Vector3(x0, h, z), fwd, a0, true, ah)
	b.quad_h(wall_mat, xf * Vector3(dr, 0, z), xf * Vector3(x1, 0, z), xf * Vector3(x1, h, z), xf * Vector3(dr, h, z), fwd, a0, true, ah)
	b.quad_h(wall_mat, xf * Vector3(dl, door_h, z), xf * Vector3(dr, door_h, z), xf * Vector3(dr, h, z), xf * Vector3(dl, h, z), fwd, ad, true, ah)
	var zr := z - recess
	var right := xf.basis * Vector3(1, 0, 0)
	b.quad_h(wall_mat, xf * Vector3(dl, 0, zr), xf * Vector3(dl, 0, z), xf * Vector3(dl, door_h, z), xf * Vector3(dl, door_h, zr), right, a0, false, ad)
	b.quad_h(wall_mat, xf * Vector3(dr, 0, zr), xf * Vector3(dr, 0, z), xf * Vector3(dr, door_h, z), xf * Vector3(dr, door_h, zr), -right, a0, false, ad)
	b.box(&"wood_dark", xf.translated_local(Vector3(door_x, door_h + 0.09, z - recess * 0.5 + 0.03)),
		Vector3(door_w + 0.5, 0.18, recess + 0.1), Color.WHITE, false, 0)
	b.quad_h(&"wood_door", xf * Vector3(dl, 0, zr), xf * Vector3(dr, 0, zr), xf * Vector3(dr, door_h, zr), xf * Vector3(dl, door_h, zr), fwd, Color.WHITE, true)
	b.box(&"ashlar", xf.translated_local(Vector3(door_x, 0.06, z - recess * 0.5 + 0.1)),
		Vector3(door_w + 0.2, 0.12, recess + 0.3), Color(0.9, 0.88, 0.84), false, 8)


## An ordinary townhouse: mudbrick on a fieldstone footing under a flat mud roof.
func _house(c: Vector2, yaw: float, w: float, d: float, floors: int, tint: Color, rich: bool = false) -> void:
	var xf0 := _yaw_frame(c, yaw, 0.0)
	var gr := _ground_range(xf0, w, d)
	var g := gr.y + 0.12
	var xf := _yaw_frame(c, yaw, g)
	var h := 2.9 * floors + rng.randf_range(0.0, 0.5)
	var wall: StringName = &"plaster_fine" if rich else &"plaster"
	# Footing.
	var foot_h := 0.55
	b.box(&"rubble", xf.translated_local(Vector3(0, (foot_h - (g - gr.x) - 0.8) * 0.5, 0)),
		Vector3(w + 0.18, foot_h + (g - gr.x) + 0.8, d + 0.18), Color.WHITE, true, 8)
	# Walls: three sides as a box, the front built round its door.
	var a0 := _alpha(tint, 0.0)
	var a1 := _alpha(tint, 1.0)
	b.box(wall, xf.translated_local(Vector3(0, foot_h + (h - foot_h) * 0.5, 0)), Vector3(w, h - foot_h, d), a0, true,
		8 | 4 | 16, a1)
	var front := xf.translated_local(Vector3(0, foot_h, 0))
	var door_x := rng.randf_range(-w * 0.28, w * 0.28)
	_front_with_door(front, w, h - foot_h, d * 0.5, door_x, 1.05, 1.95, tint, wall)
	# Roof slab and parapet.
	b.quad_h(&"roof", xf * Vector3(-w * 0.5, h, -d * 0.5), xf * Vector3(w * 0.5, h, -d * 0.5),
		xf * Vector3(w * 0.5, h, d * 0.5), xf * Vector3(-w * 0.5, h, d * 0.5), Vector3.UP, Color.WHITE)
	var pt := 0.28
	var ph := 0.36
	for sgn: float in [-1.0, 1.0]:
		b.box(wall, xf.translated_local(Vector3(0, h + ph * 0.5, sgn * (d * 0.5 - pt * 0.5))), Vector3(w, ph, pt), a1, false, 8)
		b.box(wall, xf.translated_local(Vector3(sgn * (w * 0.5 - pt * 0.5), h + ph * 0.5, 0)), Vector3(pt, ph, d - pt * 2.0), a1, false, 8)
	_beam_ends(xf, w, h - 0.32, d * 0.5)
	_beam_ends(xf, w, h - 0.32, -d * 0.5)
	if floors > 1:
		_beam_ends(xf, w, 2.95, d * 0.5)
		_beam_ends(xf, w, 2.95, -d * 0.5)
	# Windows.
	for fl in floors:
		var wy := 2.05 + fl * 2.9
		for i in rng.randi_range(1, 2):
			var wx := rng.randf_range(-w * 0.4, w * 0.4)
			if fl == 0 and absf(wx - door_x) < 1.1:
				continue
			_window(xf, Vector3(wx, wy, d * 0.5), Vector3(0, 0, 1), 0.42 if fl == 0 else 0.6)
		if rng.randf() < 0.6:
			_window(xf, Vector3(w * 0.5, wy, rng.randf_range(-d * 0.3, d * 0.3)), Vector3(1, 0, 0))
		if rng.randf() < 0.6:
			_window(xf, Vector3(-w * 0.5, wy, rng.randf_range(-d * 0.3, d * 0.3)), Vector3(-1, 0, 0))
	# Street furniture.
	var roll := rng.randf()
	if roll < 0.22:
		info["awnings"].append({"xf": xf.translated_local(Vector3(door_x, 0, d * 0.5)), "w": rng.randf_range(2.4, 3.6),
			"hue": rng.randf()})
	elif roll < 0.5:
		var side := 1.0 if door_x < 0.0 else -1.0
		info["pithoi"].append(xf * Vector3(door_x + side * 1.3, 0.0, d * 0.5 + 0.55))
	elif roll < 0.62:
		# Mud bench against the wall.
		b.box(wall, xf.translated_local(Vector3(clampf(door_x + 2.2, -w * 0.5 + 1.0, w * 0.5 - 1.0), 0.22, d * 0.5 + 0.28)),
			Vector3(1.8, 0.44, 0.5), a0, true, 8)
	info["houses"].append({"pos": xf.origin, "yaw": yaw, "w": w, "d": d, "h": h})


## A megaron: the hall-and-porch house of Aegean and north-west Anatolian
## chiefs. Enterable. Local +Z is the porch front.
func _megaron(c: Vector2, yaw: float, w: float, d: float, h: float, label: String = "",
		opts: Dictionary = {}) -> Transform3D:
	var xf0 := _yaw_frame(c, yaw, 0.0)
	var gr := _ground_range(xf0, w + 2.0, d + 2.0)
	var floor_y: float = opts.get("floor_y", gr.y + 0.35)
	var xf := _yaw_frame(c, yaw, floor_y)
	var t := 0.9
	var porch := minf(4.2, d * 0.24)
	var stone_h := 2.3
	var white := Color.WHITE
	var tint: Color = opts.get("tint", Color(1.0, 0.98, 0.94))
	# Terrace podium: tall on the downhill side, as at House VI M.
	var pod_h := floor_y - gr.x + 1.0
	b.frustum(&"limestone", xf.translated_local(Vector3(0, -pod_h, 0)),
		Vector2(w + 1.6 + pod_h * 0.3, d + 1.6 + pod_h * 0.3), Vector2(w + 1.2, d + 1.2), pod_h, white, true, false)
	b.quad_h(&"paving", xf * Vector3(-w * 0.5 - 0.6, 0, -d * 0.5 - 0.6), xf * Vector3(w * 0.5 + 0.6, 0, -d * 0.5 - 0.6),
		xf * Vector3(w * 0.5 + 0.6, 0, d * 0.5 + 0.6), xf * Vector3(-w * 0.5 - 0.6, 0, d * 0.5 + 0.6), Vector3.UP, white)
	# Steps at the front when the floor stands proud of the street.
	var front_ground := TroyLayout.height((xf * Vector3(0, 0, d * 0.5 + 3.0)).x, (xf * Vector3(0, 0, d * 0.5 + 3.0)).z)
	var rise := floor_y - front_ground
	if rise > 0.15:
		var run := maxf(rise * 1.7, 1.2)
		var sb := xf.basis * Basis(Vector3(-1, 0, 0), Vector3.UP, Vector3(0, 0, -1))
		b.stairs(&"ashlar", Transform3D(sb, xf * Vector3(0, -rise, d * 0.5 + 0.6 + run)), minf(w - 2.0, 6.0),
			rise, run, maxi(int(rise / 0.2), 1), white)
	# Walls: dressed stone below, plastered brick above.
	var walls: Array = [
		[Vector3(-w * 0.5 + t * 0.5, 0, 0), Vector3(t, 0, d)],
		[Vector3(w * 0.5 - t * 0.5, 0, 0), Vector3(t, 0, d)],
		[Vector3(0, 0, -d * 0.5 + t * 0.5), Vector3(w - t * 2.0, 0, t)],
	]
	var door_w: float = opts.get("door_w", 2.0)
	var door_h := 3.0
	var cross_z := d * 0.5 - porch
	var seg_w := (w - t * 2.0 - door_w) * 0.5
	walls.append([Vector3(-(door_w * 0.5 + seg_w * 0.5), 0, cross_z), Vector3(seg_w, 0, t)])
	walls.append([Vector3(door_w * 0.5 + seg_w * 0.5, 0, cross_z), Vector3(seg_w, 0, t)])
	for wl: Array in walls:
		var p: Vector3 = wl[0]
		var sz: Vector3 = wl[1]
		b.box(&"ashlar", xf.translated_local(p + Vector3(0, stone_h * 0.5, 0)), Vector3(sz.x, stone_h, sz.z), white, true, 8 | 4)
		b.box(&"plaster_fine", xf.translated_local(p + Vector3(0, stone_h + (h - stone_h) * 0.5, 0)),
			Vector3(sz.x, h - stone_h, sz.z), _alpha(tint, 0.3), true, 8 | 4, _alpha(tint, 1.0))
	# Painted dado band along the porch walls.
	b.box(&"plaster_fine", xf.translated_local(Vector3(0, door_h + (h - door_h) * 0.5 + 0.1, cross_z)),
		Vector3(door_w, h - door_h - 0.2, t), _alpha(tint, 0.6), true, 4, _alpha(tint, 1.0))
	b.box(&"wood_dark", xf.translated_local(Vector3(0, door_h + 0.02, cross_z)), Vector3(door_w + 0.7, 0.24, t + 0.12), white, false, 0)
	# Door jamb posts.
	for sgn: float in [-1.0, 1.0]:
		b.box(&"wood_dark", xf.translated_local(Vector3(sgn * (door_w * 0.5 - 0.06), door_h * 0.5, cross_z)),
			Vector3(0.14, door_h, t + 0.1), white, false, 8 | 4)
	# Roof: timber deck under packed earth, with a parapet.
	var roof_t := 0.45
	b.box(&"wood", xf.translated_local(Vector3(0, h + 0.06, 0)), Vector3(w, 0.12, d), white, false, 4)
	b.box(&"plaster", xf.translated_local(Vector3(0, h + 0.12 + roof_t * 0.5, 0)), Vector3(w + 0.5, roof_t, d + 0.5),
		_alpha(white, 0.8), true, 8 | 4, _alpha(white, 1.0))
	var ry := h + 0.12 + roof_t
	b.quad_h(&"roof", xf * Vector3(-w * 0.5 - 0.25, ry, -d * 0.5 - 0.25), xf * Vector3(w * 0.5 + 0.25, ry, -d * 0.5 - 0.25),
		xf * Vector3(w * 0.5 + 0.25, ry, d * 0.5 + 0.25), xf * Vector3(-w * 0.5 - 0.25, ry, d * 0.5 + 0.25), Vector3.UP, white)
	for sgn: float in [-1.0, 1.0]:
		b.box(&"plaster", xf.translated_local(Vector3(0, ry + 0.2, sgn * (d * 0.5 + 0.1))), Vector3(w + 0.5, 0.4, 0.3),
			_alpha(white, 1.0), false, 8)
		b.box(&"plaster", xf.translated_local(Vector3(sgn * (w * 0.5 + 0.1), ry + 0.2, 0)), Vector3(0.3, 0.4, d), _alpha(white, 1.0), false, 8)
	_beam_ends(xf, w, h - 0.1, d * 0.5, 0.6)
	# Porch columns in antis, hall columns round the hearth.
	var col_x := w * 0.5 - t - (w - 2.0 * t) * 0.3
	for sgn: float in [-1.0, 1.0]:
		_column(xf * Vector3(sgn * col_x, 0, d * 0.5 - 0.7), h)
	var hall_len := d - porch - t
	var hall_c := -d * 0.5 + t + (hall_len - t) * 0.5
	if w > 8.5:
		for sx: float in [-1.0, 1.0]:
			for sz: float in [-1.0, 1.0]:
				_column(xf * Vector3(sx * minf(2.4, w * 0.2), 0, hall_c + sz * minf(2.6, hall_len * 0.18)), h)
	# Hearth.
	var hearth := xf * Vector3(0, 0, hall_c)
	b.cylinder(&"plaster_fine", hearth, minf(1.5, w * 0.12), minf(1.4, w * 0.11), 0.22, 20, Color(0.95, 0.9, 0.82), true)
	info["hearths"].append({"pos": hearth + Vector3(0, 0.25, 0), "label": label})
	# High windows down the long walls.
	for sgn: float in [-1.0, 1.0]:
		var count := int(hall_len / 4.5)
		for i in count:
			var z := lerpf(-d * 0.5 + 2.0, cross_z - 2.0, (i + 0.5) / maxi(count, 1))
			_window(xf, Vector3(sgn * w * 0.5, h - 1.0, z), Vector3(sgn, 0, 0), 0.6)
	if label != "":
		info["markers"][label] = xf * Vector3(0, 0, d * 0.5 + 3.0)
		info["markers"][label + "_hall"] = hearth
	info["torches"].append(xf * Vector3(-w * 0.5 + t + 0.2, 2.6, d * 0.5 - 0.4))
	info["torches"].append(xf * Vector3(w * 0.5 - t - 0.2, 2.6, d * 0.5 - 0.4))
	return xf


## A long two-storey wing of chambers opening on a colonnade: Priam's
## "fifty chambers of polished stone" for his sons and their wives.
func _chamber_wing(c: Vector2, yaw: float, length: float, depth: float, floor_y: float) -> void:
	var xf := _yaw_frame(c, yaw, floor_y)
	var h := 6.2
	var white := Color.WHITE
	var gr := _ground_range(xf, length + 2.0, depth + 6.0)
	var pod_h := floor_y - gr.x + 1.0
	b.frustum(&"limestone", xf.translated_local(Vector3(0, -pod_h, 1.6)),
		Vector2(length + 1.4, depth + 4.6), Vector2(length + 1.0, depth + 4.2), pod_h, white, true, false)
	b.quad_h(&"paving", xf * Vector3(-length * 0.5 - 0.5, 0, -depth * 0.5 - 0.5), xf * Vector3(length * 0.5 + 0.5, 0, -depth * 0.5 - 0.5),
		xf * Vector3(length * 0.5 + 0.5, 0, depth * 0.5 + 3.7), xf * Vector3(-length * 0.5 - 0.5, 0, depth * 0.5 + 3.7), Vector3.UP, white)
	b.box(&"ashlar", xf.translated_local(Vector3(0, 1.1, 0)), Vector3(length, 2.2, depth), white, true, 8 | 4 | 16)
	b.box(&"plaster_fine", xf.translated_local(Vector3(0, 2.2 + (h - 2.2) * 0.5, 0)), Vector3(length, h - 2.2, depth),
		_alpha(white, 0.35), true, 8 | 4 | 16, _alpha(white, 1.0))
	# Front wall with a row of doors.
	var doors := int(length / 4.2)
	var bay := length / doors
	for i in doors:
		var bx := -length * 0.5 + bay * (i + 0.5)
		var bay_xf := xf.translated_local(Vector3(bx, 0, 0))
		_front_with_door(bay_xf, bay, h, depth * 0.5, 0.0, 1.15, 2.2, Color(1.0, 0.98, 0.94), &"plaster_fine", 0.35)
		_window(bay_xf, Vector3(0, 4.3, depth * 0.5), Vector3(0, 0, 1), 0.7)
		_column(xf * Vector3(bx + bay * 0.5 - 0.01, 0, depth * 0.5 + 3.0), 3.3, 0.2)
	_column(xf * Vector3(-length * 0.5 + 0.2, 0, depth * 0.5 + 3.0), 3.3, 0.2)
	# Colonnade roof.
	b.box(&"wood", xf.translated_local(Vector3(0, 3.36, depth * 0.5 + 1.65)), Vector3(length + 0.4, 0.12, 3.5), white, false, 0)
	b.box(&"plaster", xf.translated_local(Vector3(0, 3.57, depth * 0.5 + 1.65)), Vector3(length + 0.5, 0.3, 3.6),
		_alpha(white, 1.0), true, 8)
	b.quad_h(&"roof", xf * Vector3(-length * 0.5, h, -depth * 0.5), xf * Vector3(length * 0.5, h, -depth * 0.5),
		xf * Vector3(length * 0.5, h, depth * 0.5), xf * Vector3(-length * 0.5, h, depth * 0.5), Vector3.UP, white)
	for sgn: float in [-1.0, 1.0]:
		b.box(&"plaster_fine", xf.translated_local(Vector3(0, h + 0.2, sgn * (depth * 0.5 - 0.15))), Vector3(length, 0.4, 0.3),
			_alpha(white, 1.0), false, 8)
	_beam_ends(xf, length, h - 0.3, depth * 0.5, 0.7)


func _summit() -> void:
	var pl := TroyLayout.places()
	var floor_y := TroyLayout.SUMMIT_HEIGHT + 0.35
	# Palace of Priam: the great megaron facing south across the court.
	var palace: Vector2 = pl["palace"]
	_megaron(palace, 0.0, 14.0, 28.0, 7.4, "palace", {"floor_y": floor_y + 0.5, "door_w": 2.6})
	_chamber_wing(Vector2(31.0, -31.0), 0.0, 34.0, 7.0, floor_y + 0.2)
	_chamber_wing(Vector2(-23.0, -31.0), 0.0, 34.0, 7.0, floor_y + 0.2)
	# Temple of Athena, entered from the east, with its altar before the door.
	var temple: Vector2 = pl["temple_athena"]
	_megaron(temple, PI * 0.5, 9.5, 18.0, 6.4, "temple_athena", {"floor_y": floor_y + 0.9, "door_w": 2.2})
	var altar := temple + Vector2(15.5, 0.0)
	var ag := TroyLayout.height(altar.x, altar.y)
	b.frustum(&"ashlar", Transform3D(Basis.IDENTITY, Vector3(altar.x, ag - 0.2, altar.y)), Vector2(3.4, 2.4), Vector2(3.0, 2.0), 0.6, Color.WHITE)
	b.frustum(&"ashlar", Transform3D(Basis.IDENTITY, Vector3(altar.x, ag + 0.4, altar.y)), Vector2(2.2, 1.4), Vector2(2.0, 1.2), 0.9, Color(0.95, 0.93, 0.9))
	info["markers"]["altar"] = Vector3(altar.x, ag, altar.y)
	info["hearths"].append({"pos": Vector3(altar.x, ag + 1.35, altar.y), "label": "altar"})
	# Houses of Hector and of Paris, close by Priam's as Homer has them.
	_megaron(pl["house_hector"], -PI * 0.5, 10.5, 18.0, 6.0, "house_hector", {"floor_y": floor_y + 0.1})
	_megaron(pl["house_paris"], -PI * 0.5, 10.0, 17.0, 6.0, "house_paris", {"floor_y": floor_y, "tint": Color(1.0, 0.94, 0.86)})
	info["markers"]["horse"] = TroyLayout.ground(pl["horse"].x, pl["horse"].y)
	info["markers"]["court"] = TroyLayout.ground(0.0, 12.0)


func _citadel_houses() -> void:
	# The ring of great terrace houses (VI A, B, M, E, F, C, G, the Pillar House).
	var ring: Array = [
		[112.0, 11.0, 20.0, "house_vi_m"], [136.0, 10.0, 18.0, ""], [176.0, 11.0, 19.0, "house_vi_a"],
		[204.0, 10.0, 18.0, "house_vi_b"], [232.0, 10.5, 17.0, ""], [262.0, 11.0, 18.0, ""],
		[290.0, 10.0, 17.0, ""], [334.0, 10.5, 18.0, "house_vi_e"], [4.0, 11.0, 19.0, "house_vi_f"],
		[66.0, 11.0, 22.0, "pillar_house"],
	]
	for item: Array in ring:
		var deg: float = item[0]
		var c := TroyLayout.citadel_point(deg, 0.795)
		var inward := -TroyLayout.citadel_normal(deg)
		var yaw := atan2(inward.x, inward.y)
		_megaron(c, yaw, item[1], item[2], 5.8, item[3])
	# House of Deiphobus on the eastern terrace.
	var dp: Vector2 = TroyLayout.places()["house_deiphobus"]
	var inward := (Vector2.ZERO - dp).normalized()
	_megaron(dp, atan2(inward.x, inward.y), 11.5, 20.0, 6.2, "house_deiphobus", {"tint": Color(1.0, 0.95, 0.88)})

	# Troy VIIa: small houses packed against the inside of the wall, their
	# floors sunk with storage jars. The crowding of a city under threat.
	var deg := 4.0
	while deg < 360.0:
		var skip := false
		for g: float in [TroyLayout.SOUTH_GATE_DEG, TroyLayout.EAST_GATE_DEG, 78.0, 112.0, 200.0, 300.0, 36.0,
				TroyLayout.NE_BASTION_DEG + 360.0, 352.0]:
			if absf(wrapf(deg - g, -180.0, 180.0)) < 7.5:
				skip = true
		if not skip:
			var c := TroyLayout.citadel_point(deg, 0.925)
			var inward2 := -TroyLayout.citadel_normal(deg)
			var w := rng.randf_range(5.5, 7.5)
			_house(c, atan2(inward2.x, inward2.y), w, 4.6, 1, PLASTER_TINTS[rng.randi() % PLASTER_TINTS.size()])
			for i in 2:
				info["pithoi"].append(_v3(c + inward2 * 3.4 + inward2.orthogonal() * (i * 1.1 - 0.5),
					TroyLayout.height(c.x, c.y)))
		deg += rng.randf_range(5.6, 7.4)


## Separating-axis test for two plan rectangles (centre, half extents, yaw).
static func obb_overlap(c1: Vector2, h1: Vector2, yaw1: float, c2: Vector2, h2: Vector2, yaw2: float) -> bool:
	var axes: Array[Vector2] = [Vector2(cos(yaw1), -sin(yaw1)), Vector2(sin(yaw1), cos(yaw1)),
		Vector2(cos(yaw2), -sin(yaw2)), Vector2(sin(yaw2), cos(yaw2))]
	var delta := c2 - c1
	for axis in axes:
		var r1 := h1.x * absf(axes[0].dot(axis)) + h1.y * absf(axes[1].dot(axis))
		var r2 := h2.x * absf(axes[2].dot(axis)) + h2.y * absf(axes[3].dot(axis))
		if absf(delta.dot(axis)) > r1 + r2:
			return false
	return true


func _fits(c: Vector2, w: float, d: float, yaw: float, margin: float) -> bool:
	var half := Vector2(w, d) * 0.5 + Vector2(margin, margin)
	var rad := half.length()
	for f: Array in _footprints:
		if c.distance_to(f[0]) > rad + (f[3] as float):
			continue
		if obb_overlap(c, half, yaw, f[0], f[1], f[2]):
			return false
	return true


func _lot_ok(c: Vector2, w: float, d: float, yaw: float) -> bool:
	var ax := Vector2(cos(yaw), -sin(yaw))
	var az := Vector2(sin(yaw), cos(yaw))
	for sx: float in [-0.5, 0.0, 0.5]:
		for sz: float in [-0.5, 0.0, 0.5]:
			var p := c + ax * (sx * w) + az * (sz * d)
			if TroyLayout.lower_r(p.x, p.y) > 0.962 or TroyLayout.citadel_r(p.x, p.y) < 1.215 or p.y < 2.0:
				return false
			for clear: Array in _clearings:
				if p.distance_to(clear[0]) < (clear[1] as float):
					return false
			if _street_dist(p) < 0.12:
				return false
	return true


func _place_house(c: Vector2, yaw: float, w: float, d: float, floors: int) -> void:
	_footprints.append([c, Vector2(w, d) * 0.5, yaw, Vector2(w, d).length() * 0.5])
	_house(c, yaw, w, d, floors, PLASTER_TINTS[rng.randi() % PLASTER_TINTS.size()])


func _rows_along(seg: Array, sides: Array) -> void:
	var a: Vector2 = seg[0]
	var bb: Vector2 = seg[1]
	var width: float = seg[2]
	var dir := (bb - a).normalized()
	var length := a.distance_to(bb)
	for side: float in sides:
		var nrm := dir.orthogonal() * side
		var facing := -nrm
		var yaw := atan2(facing.x, facing.y)
		var s := 1.0
		while s < length - 5.0:
			var w := rng.randf_range(6.0, 10.5)
			var d := rng.randf_range(6.0, 9.0)
			var c := a + dir * (s + w * 0.5) + nrm * (width * 0.5 + d * 0.5 + 0.4)
			if _lot_ok(c, w, d, yaw) and _fits(c, w, d, yaw, -0.04):
				_place_house(c, yaw, w, d, 2 if rng.randf() < 0.36 else 1)
				s += w + (2.9 if rng.randf() < 0.2 else 0.0)
			else:
				s += 1.5


func _lower_town() -> void:
	var agora: Vector2 = TroyLayout.places()["agora"]
	_clearings = [[agora, 21.0], [TroyLayout.places()["scaean_gate"], 22.0],
		[TroyLayout.places()["dardanian_gate"], 20.0]]
	# Wall stairs must stay reachable.
	for deg: float in [TroyLayout.SCAEAN_GATE_DEG + 7.0, TroyLayout.SCAEAN_GATE_DEG - 7.0,
			TroyLayout.DARDANIAN_GATE_DEG + 6.5]:
		_clearings.append([TroyLayout.lower_point(deg, 0.97), 11.0])
	# Only streets outside the citadel shape the lower town.
	var all_streets := _streets
	var town: Array = []
	for s: Array in all_streets:
		var a: Vector2 = s[0]
		var bb: Vector2 = s[1]
		if TroyLayout.citadel_r(a.x, a.y) > 1.0 and TroyLayout.citadel_r(bb.x, bb.y) > 1.0:
			town.append(s)
	_streets = town
	# Street frontages first: attached rows with the odd alley between.
	for s: Array in town:
		var a: Vector2 = s[0]
		var mid := (a + (s[1] as Vector2)) * 0.5
		var cr := TroyLayout.citadel_r(mid.x, mid.y)
		if cr < 1.2:
			# Pomerium lane: houses only on the side away from the citadel wall.
			var outward := (mid - Vector2.ZERO).normalized()
			var dir := ((s[1] as Vector2) - a).normalized()
			_rows_along(s, [1.0 if dir.orthogonal().dot(outward) > 0.0 else -1.0])
		else:
			_rows_along(s, [-1.0, 1.0])
	# Then fill the blocks behind them.
	var spacing := 12.5
	var z := 4.0
	while z < 330.0:
		var x := -215.0
		while x < 215.0:
			var p := Vector2(x + rng.randf_range(-1.4, 1.4), z + rng.randf_range(-1.4, 1.4))
			x += spacing
			if TroyLayout.lower_r(p.x, p.y) > 0.95 or TroyLayout.citadel_r(p.x, p.y) < 1.2:
				continue
			var w := rng.randf_range(6.5, 9.5)
			var d := rng.randf_range(6.0, 8.2)
			var facing := _nearest_street_dir(p)
			var yaw := atan2(facing.x, facing.y)
			if not _lot_ok(p, w, d, yaw) or not _fits(p, w, d, yaw, 1.15):
				continue
			if rng.randf() < 0.13:
				_footprints.append([p, Vector2(2.0, 2.0), 0.0, 2.9])
				info["trees"].append({"pos": TroyLayout.ground(p.x, p.y), "kind": "olive" if rng.randf() < 0.6 else "fig",
					"scale": rng.randf_range(0.8, 1.15)})
				continue
			_place_house(p, yaw, w, d, 2 if rng.randf() < 0.25 else 1)
		z += spacing
	_streets = all_streets
	# Agora well and market awnings.
	var well := agora + Vector2(8.0, 6.0)
	var wy := TroyLayout.height(well.x, well.y)
	b.cylinder(&"rubble", Vector3(well.x, wy - 0.2, well.y), 1.25, 1.15, 1.0, 16, Color.WHITE, true, false)
	b.cylinder(&"dark", Vector3(well.x, wy + 0.5, well.y), 0.9, 0.9, 0.02, 16, Color.WHITE, false)
	info["markers"]["agora"] = TroyLayout.ground(agora.x, agora.y)
	for i in 5:
		var ang := 0.7 + i * 1.1
		var sp := agora + Vector2(cos(ang), sin(ang)) * 15.0
		info["awnings"].append({"xf": _yaw_frame(sp, ang + PI * 0.5, TroyLayout.height(sp.x, sp.y)), "w": 3.4,
			"hue": rng.randf(), "stall": true})
	# Torches along the Scaean Way.
	for s: Array in _streets:
		if not (s[3] as bool):
			continue
		var a: Vector2 = s[0]
		var bb: Vector2 = s[1]
		var length := a.distance_to(bb)
		var count := int(length / 26.0)
		for i in count:
			var p := a.lerp(bb, (i + 0.5) / maxi(count, 1))
			var side := (bb - a).normalized().orthogonal() * ((s[2] as float) * 0.5 + 0.4) * (1.0 if i % 2 == 0 else -1.0)
			var q := p + side
			info["torches"].append(Vector3(q.x, TroyLayout.height(q.x, q.y) + 2.3, q.y))
			info["torch_posts"] = info.get("torch_posts", [])
			info["torch_posts"].append(Vector3(q.x, TroyLayout.height(q.x, q.y), q.y))


func _streets_paving() -> void:
	for s: Array in _streets:
		if not (s[3] as bool):
			continue
		var a: Vector2 = s[0]
		var bb: Vector2 = s[1]
		var w: float = s[2]
		var length := a.distance_to(bb)
		var steps := maxi(int(length / 1.5), 1)
		var side := (bb - a).normalized().orthogonal() * w * 0.5
		var prev_l := Vector3.ZERO
		var prev_r := Vector3.ZERO
		for i in steps + 1:
			var p := a.lerp(bb, float(i) / steps)
			var l := p + side
			var r := p - side
			var y := maxf(maxf(TroyLayout.height(l.x, l.y), TroyLayout.height(r.x, r.y)), TroyLayout.height(p.x, p.y)) + 0.07
			var vl := Vector3(l.x, y, l.y)
			var vr := Vector3(r.x, y, r.y)
			if i > 0:
				b.quad_h(&"paving", prev_l, prev_r, vr, vl, Vector3.UP, Color.WHITE, false)
			prev_l = vl
			prev_r = vr
	# The court before Priam's doors and the agora are paved.
	for disc: Array in [[Vector2(0.0, 12.0), 26.0, 20.0], [TroyLayout.places()["agora"], 17.0, 17.0]]:
		var c: Vector2 = disc[0]
		var segs := 28
		for i in segs:
			var a0 := TAU * i / segs
			var a1 := TAU * (i + 1) / segs
			var p0 := c + Vector2(cos(a0) * disc[1], sin(a0) * disc[2])
			var p1 := c + Vector2(cos(a1) * disc[1], sin(a1) * disc[2])
			var yc := TroyLayout.height(c.x, c.y) + 0.07
			b.poly(&"paving", [Vector3(c.x, yc, c.y), Vector3(p0.x, TroyLayout.height(p0.x, p0.y) + 0.07, p0.y),
				Vector3(p1.x, TroyLayout.height(p1.x, p1.y) + 0.07, p1.y)] as Array[Vector3], Vector3.UP, Color.WHITE, false)


func _outside() -> void:
	var pl := TroyLayout.places()
	# The oak of Zeus before the Scaean Gate, and the wild fig by the wall.
	var oak: Vector2 = pl["oak"]
	info["trees"].append({"pos": TroyLayout.ground(oak.x, oak.y), "kind": "oak", "scale": 1.5})
	info["markers"]["oak"] = TroyLayout.ground(oak.x, oak.y)
	var fig: Vector2 = pl["fig_tree"]
	info["trees"].append({"pos": TroyLayout.ground(fig.x, fig.y), "kind": "fig", "scale": 1.3})
	info["markers"]["fig_tree"] = TroyLayout.ground(fig.x, fig.y)
	# The washing troughs by the springs of Scamander.
	var sp: Vector2 = pl["springs"]
	var sy := TroyLayout.height(sp.x, sp.y)
	for i in 3:
		var bx := Transform3D(Basis(Vector3.UP, 0.4), Vector3(sp.x + i * 3.2, sy, sp.y + i * 1.1))
		b.box(&"ashlar", bx.translated_local(Vector3(0, 0.25, 0)), Vector3(2.6, 0.5, 1.3), Color.WHITE, true, 8)
		b.box(&"dark", bx.translated_local(Vector3(0, 0.46, 0)), Vector3(2.2, 0.1, 0.9), Color(0.2, 0.3, 0.35), false, 8)
	info["markers"]["springs"] = Vector3(sp.x, sy, sp.y)
	# The barrow of Ilus out on the plain.
	var tomb: Vector2 = pl["tomb_ilus"]
	var ty := TroyLayout.height(tomb.x, tomb.y)
	var profile := PackedVector2Array()
	for i in 9:
		var t := i / 8.0
		profile.append(Vector2(16.0 * cos(t * PI * 0.5), 7.0 * sin(t * PI * 0.5) - 0.5))
	b.lathe(&"ground", Transform3D(Basis.IDENTITY, Vector3(tomb.x, ty, tomb.y)), profile, 24, Color(0.1, 0.9, 0.0, 1.0), true)
	b.frustum(&"ashlar", Transform3D(Basis.IDENTITY, Vector3(tomb.x, ty + 6.3, tomb.y)), Vector2(0.9, 0.5), Vector2(0.7, 0.4), 2.4, Color.WHITE)
	info["markers"]["tomb_ilus"] = Vector3(tomb.x, ty, tomb.y)
	# Scattered trees on the plain and the ridge.
	for i in 170:
		var p := Vector2(rng.randf_range(-640.0, 400.0), rng.randf_range(-250.0, 510.0))
		if TroyLayout.lower_r(p.x, p.y) < 1.22 or TroyLayout.citadel_r(p.x, p.y) < 1.5:
			continue
		if p.distance_to(oak) < 70.0 and p.distance_to(oak) > 3.0:
			continue
		var h := TroyLayout.height(p.x, p.y)
		if h < TroyLayout.SEA_Y + 0.6:
			continue
		var near_river := absf(p.x - (-520.0 + sin(p.y * 0.006) * 70.0)) < 60.0
		var kind := "tamarisk" if near_river else (["oak", "olive", "olive", "fig"][rng.randi() % 4] as String)
		info["trees"].append({"pos": Vector3(p.x, h, p.y), "kind": kind, "scale": rng.randf_range(0.8, 1.4)})
