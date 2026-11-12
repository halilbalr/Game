extends TestCase
## Combat.damage, hit zones and the shield arc.

const CFG := {"head_multiplier": 1.7, "leg_multiplier": 0.8, "back_multiplier": 1.35, "damage_spread": 0.12}
const BASE := 40.0
const MEAN_ROLL := 0.5


func test_hit_zone_by_height_returns_head_body_legs() -> void:
	eq(Combat.hit_zone(1.6), &"head", "eye level")
	eq(Combat.hit_zone(1.1), &"body", "chest")
	eq(Combat.hit_zone(0.4), &"legs", "shin")


func test_hit_zone_on_a_taller_man_scales_with_him() -> void:
	# 1.45 m is head height on a man of ordinary size but only shoulder height on Ajax.
	eq(Combat.hit_zone(1.45, 1.0), &"head")
	eq(Combat.hit_zone(1.45, 1.15), &"body")


func test_hit_zone_crouched_brings_the_head_lower() -> void:
	eq(Combat.hit_zone(1.2, 1.0, true), &"head")


func test_damage_to_unarmoured_body_at_mean_roll_equals_base() -> void:
	near(Combat.damage(BASE, &"body", 0.0, false, MEAN_ROLL, CFG), BASE, 0.001)


func test_damage_to_head_applies_multiplier_and_ignores_armour() -> void:
	near(Combat.damage(BASE, &"head", 0.36, false, MEAN_ROLL, CFG), BASE * 1.7, 0.001)


func test_damage_to_armoured_body_is_reduced_by_armour() -> void:
	near(Combat.damage(BASE, &"body", 0.36, false, MEAN_ROLL, CFG), BASE * 0.64, 0.001)


func test_damage_to_legs_applies_leg_multiplier() -> void:
	near(Combat.damage(BASE, &"legs", 0.36, false, MEAN_ROLL, CFG), BASE * 0.8, 0.001)


func test_damage_from_behind_is_increased() -> void:
	near(Combat.damage(BASE, &"body", 0.0, true, MEAN_ROLL, CFG), BASE * 1.35, 0.001)


func test_damage_roll_stays_within_the_spread() -> void:
	near(Combat.damage(BASE, &"body", 0.0, false, 0.0, CFG), BASE * 0.88, 0.001, "lowest roll")
	near(Combat.damage(BASE, &"body", 0.0, false, 1.0, CFG), BASE * 1.12, 0.001, "highest roll")


func test_damage_is_never_negative() -> void:
	check(Combat.damage(BASE, &"body", 5.0, false, 0.0, CFG) >= 0.0)


func test_armor_value_ranks_bronze_above_linen_above_none() -> void:
	check(Combat.armor_value("bronze") > Combat.armor_value("linen"))
	check(Combat.armor_value("linen") > Combat.armor_value("none"))
	eq(Combat.armor_value("no such armour"), 0.0)


func test_block_arc_covers_the_front_and_not_the_back() -> void:
	var forward := Vector3(0, 0, -1)
	check(Combat.in_block_arc(forward, Vector3(0, 0, -3), 115.0), "dead ahead")
	check(Combat.in_block_arc(forward, Vector3(2, 0, -2), 115.0), "45 degrees off")
	check(not Combat.in_block_arc(forward, Vector3(3, 0, 0.5), 115.0), "from the flank")
	check(not Combat.in_block_arc(forward, Vector3(0, 0, 3), 115.0), "from behind")


func test_is_behind_only_for_attackers_at_the_back() -> void:
	var forward := Vector3(0, 0, -1)
	check(Combat.is_behind(forward, Vector3(0, 0, 2)))
	check(not Combat.is_behind(forward, Vector3(0, 0, -2)))
	check(not Combat.is_behind(forward, Vector3(2, 0, 0)), "the flank is not the back")
