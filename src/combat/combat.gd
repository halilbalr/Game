class_name Combat
extends RefCounted
## Pure combat and stealth rules. No scene access, so every formula here is
## unit-tested (tests/unit/combat). Numbers come from assets/data/tuning.json.

## Fraction of a body blow each kind of armour turns aside.
const ARMOR := {
	"none": 0.0, "leather": 0.15, "linen": 0.2, "scale": 0.3, "bronze": 0.36, "bronze_gold": 0.42,
}


## Which part of a standing figure a blow at [param height] metres lands on.
## [param scale] is the figure's size relative to 1.72 m.
static func hit_zone(height: float, scale: float = 1.0, crouched: bool = false) -> StringName:
	var h := height / maxf(scale, 0.01)
	if crouched:
		h += 0.3
	if h >= 1.42:
		return &"head"
	if h < 0.72:
		return &"legs"
	return &"body"


## Protection given by an armour id (0 to 1).
static func armor_value(armor: String) -> float:
	return ARMOR.get(armor, 0.0)


## Damage dealt by one blow.
## [param roll] is a random number in 0..1; pass 0.5 for the mean.
static func damage(base: float, zone: StringName, armor: float, from_behind: bool, roll: float,
		cfg: Dictionary) -> float:
	var d := base
	match zone:
		&"head":
			d *= float(cfg.get("head_multiplier", 1.7))
		&"legs":
			d *= float(cfg.get("leg_multiplier", 0.8))
		_:
			d *= 1.0 - clampf(armor, 0.0, 0.9)
	if from_behind:
		d *= float(cfg.get("back_multiplier", 1.35))
	var spread := float(cfg.get("damage_spread", 0.12))
	d *= 1.0 + (clampf(roll, 0.0, 1.0) * 2.0 - 1.0) * spread
	return maxf(d, 0.0)


## True when a blow arriving from [param to_attacker] falls inside the arc a
## raised shield covers. Both vectors are flattened to the ground plane.
static func in_block_arc(defender_forward: Vector3, to_attacker: Vector3, arc_deg: float) -> bool:
	var f := Vector2(defender_forward.x, defender_forward.z)
	var t := Vector2(to_attacker.x, to_attacker.z)
	if f.length_squared() < 1e-6 or t.length_squared() < 1e-6:
		return true
	return rad_to_deg(absf(f.angle_to(t))) <= arc_deg * 0.5


## True when the attacker stands behind the defender.
static func is_behind(defender_forward: Vector3, to_attacker: Vector3) -> bool:
	var f := Vector2(defender_forward.x, defender_forward.z)
	var t := Vector2(to_attacker.x, to_attacker.z)
	if f.length_squared() < 1e-6 or t.length_squared() < 1e-6:
		return false
	return f.normalized().dot(t.normalized()) < -0.25


## How fast a watchman's suspicion rises, per second, for a player at
## [param distance] metres and [param angle_deg] off his line of sight.
## Returns 0 when the player is neither seen nor heard.
static func detection_gain(distance: float, angle_deg: float, crouched: bool, move_speed: float,
		line_of_sight: bool, asleep: bool, cfg: Dictionary) -> float:
	var gain := 0.0
	var rate := float(cfg.get("detect_rate", 0.85))
	var sleeper := float(cfg.get("sleeper_scale", 0.3))
	# Sight.
	if line_of_sight and not asleep:
		var view := float(cfg.get("view_range_crouched", 10.0)) if crouched else float(cfg.get("view_range", 21.0))
		var half := float(cfg.get("view_angle_deg", 100.0)) * 0.5
		if distance <= float(cfg.get("close_range", 2.0)) and angle_deg <= 120.0:
			gain = maxf(gain, rate * 3.0)
		elif distance <= view and angle_deg <= half:
			gain = maxf(gain, rate * (0.35 + 1.65 * (1.0 - distance / view)))
	# Hearing.
	var hear := float(cfg.get("hear_crouch", 1.5))
	if move_speed > 5.0:
		hear = float(cfg.get("hear_run", 13.0))
	elif move_speed > 0.6 and not crouched:
		hear = float(cfg.get("hear_walk", 6.0))
	elif move_speed <= 0.6:
		hear = 0.0
	if asleep:
		hear *= sleeper
	if hear > 0.0 and distance <= hear:
		gain = maxf(gain, rate * (0.5 + 1.2 * (1.0 - distance / hear)))
	return gain
