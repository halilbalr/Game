class_name TroyLayout
extends RefCounted
## Pure geometry of Late Bronze Age Troy (Hisarlik, Troy VI/VIIa).
##
## Every builder, mission and AI waypoint reads its positions from here, so the
## city has exactly one source of truth. Axes: +X east, +Z south, +Y up. Units
## are metres. The citadel is close to true scale (about 200 m by 160 m); the
## lower town and the plain are compressed for play. See design/game-brief.md.

## Half-widths of the citadel ellipse (east-west, north-south).
const CITADEL_RX := 100.0
const CITADEL_RZ := 80.0
## Height of the citadel summit above the lower-town plateau.
const SUMMIT_HEIGHT := 8.0
## Normalised radius inside which the summit is flat.
const SUMMIT_FLAT := 0.5

## Lower-town wall ellipse.
const LOWER_CENTER := Vector2(0.0, 150.0)
const LOWER_RX := 210.0
const LOWER_RZ := 170.0

## Level of the Scamander plain relative to the plateau.
const PLAIN_Y := -17.2
const SEA_Y := -19.6

## Angles are measured from +X (east) turning towards +Z (south), in degrees.
const SOUTH_GATE_DEG := 90.0
const EAST_GATE_DEG := 22.0
const WEST_GATE_DEG := 158.0
const NE_BASTION_DEG := -48.0
const SCAEAN_GATE_DEG := 165.0
const DARDANIAN_GATE_DEG := 38.0

## Distance from the lower wall to the rock-cut ditch found by Korfmann's team.
const DITCH_OFFSET := 46.0

const _TAU_DEG := PI / 180.0


## Point on the citadel wall centre line at [param deg].
static func citadel_point(deg: float, scale: float = 1.0) -> Vector2:
	var a := deg * _TAU_DEG
	return Vector2(cos(a) * CITADEL_RX * scale, sin(a) * CITADEL_RZ * scale)


## Outward unit normal of the citadel ellipse at [param deg].
static func citadel_normal(deg: float) -> Vector2:
	var a := deg * _TAU_DEG
	return Vector2(cos(a) / CITADEL_RX, sin(a) / CITADEL_RZ).normalized()


## Normalised radius inside the citadel: 0 at the centre, 1 on the wall line.
static func citadel_r(x: float, z: float) -> float:
	return sqrt((x / CITADEL_RX) * (x / CITADEL_RX) + (z / CITADEL_RZ) * (z / CITADEL_RZ))


## Point on the lower-town wall centre line at [param deg].
static func lower_point(deg: float, scale: float = 1.0) -> Vector2:
	var a := deg * _TAU_DEG
	return LOWER_CENTER + Vector2(cos(a) * LOWER_RX * scale, sin(a) * LOWER_RZ * scale)


## Outward unit normal of the lower-town ellipse at [param deg].
static func lower_normal(deg: float) -> Vector2:
	var a := deg * _TAU_DEG
	return Vector2(cos(a) / LOWER_RX, sin(a) / LOWER_RZ).normalized()


## Normalised radius inside the lower-town ellipse.
static func lower_r(x: float, z: float) -> float:
	var dx := (x - LOWER_CENTER.x) / LOWER_RX
	var dz := (z - LOWER_CENTER.y) / LOWER_RZ
	return sqrt(dx * dx + dz * dz)


## True when the point lies inside the citadel wall line.
static func in_citadel(x: float, z: float) -> bool:
	return citadel_r(x, z) < 1.0


## True when the point lies in the lower town (inside its wall, outside the citadel).
static func in_lower_town(x: float, z: float) -> bool:
	return lower_r(x, z) < 1.0 and citadel_r(x, z) > 1.0 and z > -10.0


## Angles (degrees) at which the lower wall meets the citadel wall, [west, east].
## The lower wall runs clockwise-on-the-map from the east joint, round the
## south, to the west joint.
static func lower_wall_span() -> Vector2:
	# Solved once numerically: the two ellipses cross near z = 0.
	var east := -90.0
	var west := 270.0
	var step := 0.25
	var deg := -90.0
	var found_east := false
	while deg < 270.0:
		var p := lower_point(deg)
		var outside := citadel_r(p.x, p.y) > 1.02
		if outside and not found_east:
			east = deg
			found_east = true
		if found_east and not outside:
			west = deg - step
			break
		deg += step
	return Vector2(west, east)


static func _smooth(e0: float, e1: float, x: float) -> float:
	var t := clampf((x - e0) / (e1 - e0), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


static func _hash(x: float, z: float) -> float:
	var h := sin(x * 127.1 + z * 311.7) * 43758.5453
	return h - floorf(h)


static func _vnoise(x: float, z: float) -> float:
	var xi := floorf(x)
	var zi := floorf(z)
	var xf := x - xi
	var zf := z - zi
	var u := xf * xf * (3.0 - 2.0 * xf)
	var v := zf * zf * (3.0 - 2.0 * zf)
	var a := _hash(xi, zi)
	var b := _hash(xi + 1.0, zi)
	var c := _hash(xi, zi + 1.0)
	var d := _hash(xi + 1.0, zi + 1.0)
	return lerpf(lerpf(a, b, u), lerpf(c, d, u), v)


## Smooth value noise in 0..1, three octaves. Deterministic.
static func noise(x: float, z: float) -> float:
	return _vnoise(x, z) * 0.57 + _vnoise(x * 2.1 + 5.2, z * 2.1 + 1.3) * 0.29 \
		+ _vnoise(x * 4.3 + 9.1, z * 4.3 + 7.7) * 0.14


## How much of the plateau (1) versus the plain (0) lies under a point.
static func plateau_mask(x: float, z: float) -> float:
	var qx := (x - 40.0) / 330.0
	var qz := (z - 150.0) / 300.0
	var q := sqrt(qx * qx + qz * qz)
	var mask_a := 1.0 - _smooth(0.92, 1.5, q)
	# The north scarp is steep: the citadel stands on the lip of the ridge.
	var north := _smooth(-132.0, -92.0, z)
	var ridge := _smooth(120.0, 260.0, x) * (1.0 - _smooth(430.0, 580.0, z))
	return maxf(mask_a, ridge) * north


## Depth of the lower-town ditch at a point (0 when outside the ditch).
static func ditch_depth(x: float, z: float) -> float:
	if z < 40.0:
		return 0.0
	# Distance outside the lower wall ellipse, in metres (approximate).
	var r := lower_r(x, z)
	if r < 1.05 or r > 1.6:
		return 0.0
	var dir := Vector2(x - LOWER_CENTER.x, z - LOWER_CENTER.y)
	var len := dir.length()
	var dist := len - len / r
	var d := absf(dist - DITCH_OFFSET)
	if d > 4.5:
		return 0.0
	# Causeways left uncut in front of the two gates.
	var deg := rad_to_deg(atan2(dir.y / LOWER_RZ, dir.x / LOWER_RX))
	for gate_deg: float in [SCAEAN_GATE_DEG, DARDANIAN_GATE_DEG]:
		var diff := absf(wrapf(deg - gate_deg, -180.0, 180.0))
		if diff < 4.0:
			return 0.0
		if diff < 6.0:
			return 2.4 * (1.0 - _smooth(0.0, 4.5, d)) * _smooth(4.0, 6.0, diff)
	return 2.4 * (1.0 - _smooth(0.0, 4.5, d))


## Ground height at a world position. The single source of terrain truth.
static func height(x: float, z: float) -> float:
	var mask := plateau_mask(x, z)
	# The plateau dips gently to the south and west, as the real ridge does.
	var plateau := -0.008 * maxf(z, 0.0) - 0.006 * maxf(-x, 0.0)
	var rough := (noise(x * 0.02, z * 0.02) - 0.5) * 2.0
	var plain := PLAIN_Y + rough * 0.8 + (noise(x * 0.006 + 3.0, z * 0.006) - 0.5) * 2.0
	var town_calm := 1.0 - 0.85 * mask
	var h := lerpf(plain, plateau + rough * 0.5 * town_calm, mask)

	# Citadel mound.
	var r := citadel_r(x, z)
	if r < 1.25:
		var rise := 1.0 - _smooth(SUMMIT_FLAT, 1.0, r)
		var mound := SUMMIT_HEIGHT * rise
		if r > 1.0:
			# Outside the wall the mound fades into the plateau or the scarp.
			mound = 0.0
		var base := lerpf(h, maxf(h, plateau), 1.0 - _smooth(1.0, 1.25, r))
		h = base + mound

	h -= ditch_depth(x, z)

	# Scamander: a shallow braided channel across the western plain.
	var river_x := -520.0 + sin(z * 0.006) * 70.0 + sin(z * 0.019 + 1.0) * 18.0
	var river := 1.0 - _smooth(0.0, 26.0, absf(x - river_x))
	h -= river * 2.6 * (1.0 - mask)

	# The shore: land falls below sea level to the far north-west.
	var shore := _smooth(1150.0, 1500.0, -x * 0.75 - z * 0.66)
	h = lerpf(h, SEA_Y - 6.0, shore)

	# Distant high ground: the foothills of Ida to the south-east.
	var ida := _smooth(900.0, 3600.0, x * 0.55 + z * 0.83)
	h += ida * ida * 560.0 * (0.75 + 0.5 * noise(x * 0.0012, z * 0.0012))
	return h


## Ground height as a Vector3 at the given plan position.
static func ground(x: float, z: float, lift: float = 0.0) -> Vector3:
	return Vector3(x, height(x, z) + lift, z)


## Key places, as plan positions. Missions and the builder share these.
static func places() -> Dictionary:
	var south := citadel_point(SOUTH_GATE_DEG)
	var scaean := lower_point(SCAEAN_GATE_DEG)
	var dardan := lower_point(DARDANIAN_GATE_DEG)
	return {
		"citadel_center": Vector2.ZERO,
		"south_gate": south,
		"east_gate": citadel_point(EAST_GATE_DEG),
		"west_gate": citadel_point(WEST_GATE_DEG),
		"ne_bastion": citadel_point(NE_BASTION_DEG),
		"scaean_gate": scaean,
		"dardanian_gate": dardan,
		"horse": Vector2(-6.0, 14.0),
		"temple_athena": Vector2(-34.0, 6.0),
		"palace": Vector2(4.0, -22.0),
		"house_hector": Vector2(38.0, -4.0),
		"house_paris": Vector2(36.0, 18.0),
		"house_deiphobus": Vector2(58.0, 36.0),
		"agora": south + Vector2(0.0, 26.0),
		"oak": scaean + lower_normal(SCAEAN_GATE_DEG) * 62.0 + Vector2(10.0, 24.0),
		"fig_tree": lower_point(128.0) + lower_normal(128.0) * 22.0,
		"springs": scaean + lower_normal(SCAEAN_GATE_DEG) * 120.0 + Vector2(-20.0, -70.0),
		"tomb_ilus": Vector2(-470.0, 150.0),
		"greek_camp": Vector2(-980.0, -640.0),
	}
