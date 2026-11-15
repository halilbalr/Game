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


func test_assist_picks_the_man_nearest_the_crosshair_within_range_and_cone() -> void:
	var eye := Vector3.ZERO
	var fwd := Vector3(0, 0, -1)
	var men: Array[Vector3] = [Vector3(1.5, 0, -4), Vector3(0.2, 0, -5), Vector3(0, 0, 4), Vector3(0, 0, -20)]
	check(Combat.assist_pick(eye, fwd, men, 7.0, 26.0) == 1, "the man straight ahead, not the one off to the side")
	var off: Array[Vector3] = [Vector3(3, 0, -3)]
	check(Combat.assist_pick(eye, fwd, off, 7.0, 26.0) == -1, "45 degrees off is outside a 26 degree cone")
	var far: Array[Vector3] = [Vector3(0, 0, -9)]
	check(Combat.assist_pick(eye, fwd, far, 7.0, 26.0) == -1, "beyond range")
	var behind: Array[Vector3] = [Vector3(0, 0, 3)]
	check(Combat.assist_pick(eye, fwd, behind, 7.0, 26.0) == -1, "never someone behind")
	var low: Array[Vector3] = [Vector3(0.2, -0.45, -1.4)]
	check(Combat.assist_pick(eye, fwd, low, 7.0, 26.0) == 0, "a man close by and below the eye line still counts")


func test_assist_turn_moves_toward_the_target_capped_and_never_past_it() -> void:
	var t := Combat.assist_turn(Vector2(0.2, -0.1), 2.0, 1.0, 1.0 / 60.0)
	check(t.x > 0.0 and t.y < 0.0, "toward the error")
	check(is_equal_approx(t.x, 0.2 * 2.0 / 60.0), "a share of the error each step")
	var capped := Combat.assist_turn(Vector2(0.5, 0.0), 30.0, 1.0, 1.0 / 60.0)
	check(capped.length() <= 1.0 / 60.0 + 1e-6, "no faster than max_turn")
	var whole := Combat.assist_turn(Vector2(0.01, 0.0), 1000.0, 100.0, 1.0)
	check(is_equal_approx(whole.x, 0.01), "never overshoots")


const MOVES := {"heavy_hold": 0.32, "heavy_damage": 1.7, "heavy_windup": 1.45, "heavy_stamina": 1.8,
	"combo_damage": [1.0, 1.12, 1.4], "combo_windup": [1.0, 0.85, 0.78], "parry_window": 0.24, "riposte_damage": 1.5}


func test_strike_held_past_the_threshold_is_heavy() -> void:
	check(not Combat.is_heavy(0.1, MOVES), "a tap is light")
	check(Combat.is_heavy(0.32, MOVES), "held to the threshold is heavy")
	check(Combat.is_heavy(0.8, MOVES), "held long is heavy")


func test_combo_climbs_on_hits_inside_the_window_and_stops_at_three() -> void:
	check(Combat.combo_step(0, 0.5, false) == 1, "second blow")
	check(Combat.combo_step(1, 0.5, false) == 2, "third blow")
	check(Combat.combo_step(2, 0.5, false) == 2, "stays at the third")
	check(Combat.combo_step(1, 0.0, false) == 0, "window closed")
	check(Combat.combo_step(1, 0.5, true) == 0, "a heavy blow starts again")


func test_later_blows_of_a_chain_hit_harder_and_come_faster() -> void:
	var first := Combat.blow(0, false, false, MOVES)
	var third := Combat.blow(2, false, false, MOVES)
	check(float(third["damage"]) > float(first["damage"]), "third hits harder")
	check(float(third["windup"]) < float(first["windup"]), "third comes faster")


func test_heavy_blow_is_slower_harder_and_costlier() -> void:
	var light := Combat.blow(0, false, false, MOVES)
	var heavy := Combat.blow(0, true, false, MOVES)
	check(is_equal_approx(float(heavy["damage"]), 1.7), "damage x1.7")
	check(float(heavy["windup"]) > float(light["windup"]), "slower")
	check(float(heavy["stamina"]) > float(light["stamina"]), "costlier")


func test_riposte_multiplies_whatever_blow_it_is() -> void:
	check(is_equal_approx(float(Combat.blow(0, false, true, MOVES)["damage"]), 1.5), "light riposte")
	check(is_equal_approx(float(Combat.blow(0, true, true, MOVES)["damage"]), 1.7 * 1.5), "heavy riposte")


func test_guard_parries_when_fresh_breaks_under_a_heavy_blow_else_blocks() -> void:
	check(Combat.guard(0.1, false, MOVES) == &"parry", "fresh guard parries")
	check(Combat.guard(0.1, true, MOVES) == &"parry", "a fresh guard parries even a heavy blow")
	check(Combat.guard(1.0, false, MOVES) == &"block", "a held guard blocks")
	check(Combat.guard(1.0, true, MOVES) == &"broken", "a heavy blow breaks a held guard")
