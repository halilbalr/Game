extends TestCase
## Combat.detection_gain: what a watchman sees and hears.

const CFG := {
	"view_range": 21.0, "view_range_crouched": 10.0, "view_angle_deg": 100.0, "close_range": 2.0,
	"hear_run": 13.0, "hear_walk": 6.0, "hear_crouch": 1.5, "detect_rate": 0.85, "sleeper_scale": 0.3,
}
const STILL := 0.0
const WALK := 4.0
const RUN := 6.8
const SNEAK := 1.8


func test_standing_in_plain_view_is_seen() -> void:
	check(Combat.detection_gain(8.0, 10.0, false, STILL, true, false, CFG) > 0.0)


func test_standing_beyond_view_range_is_not_seen() -> void:
	eq(Combat.detection_gain(25.0, 0.0, false, STILL, true, false, CFG), 0.0)


func test_crouching_shortens_the_distance_at_which_one_is_seen() -> void:
	check(Combat.detection_gain(15.0, 0.0, false, STILL, true, false, CFG) > 0.0, "standing at 15 m")
	eq(Combat.detection_gain(15.0, 0.0, true, STILL, true, false, CFG), 0.0, "crouched at 15 m")


func test_behind_the_watchman_and_still_is_not_noticed() -> void:
	eq(Combat.detection_gain(5.0, 170.0, true, STILL, true, false, CFG), 0.0)


func test_no_line_of_sight_means_not_seen() -> void:
	eq(Combat.detection_gain(6.0, 0.0, false, STILL, false, false, CFG), 0.0)


func test_closer_is_noticed_faster() -> void:
	var far := Combat.detection_gain(18.0, 0.0, false, STILL, true, false, CFG)
	var close := Combat.detection_gain(5.0, 0.0, false, STILL, true, false, CFG)
	check(close > far)


func test_running_behind_a_watchman_is_heard() -> void:
	check(Combat.detection_gain(8.0, 170.0, false, RUN, false, false, CFG) > 0.0)


func test_walking_is_heard_only_close_by() -> void:
	check(Combat.detection_gain(4.0, 170.0, false, WALK, false, false, CFG) > 0.0, "4 m")
	eq(Combat.detection_gain(9.0, 170.0, false, WALK, false, false, CFG), 0.0, "9 m")


func test_sneaking_is_heard_only_at_arms_length() -> void:
	eq(Combat.detection_gain(3.0, 170.0, true, SNEAK, false, false, CFG), 0.0, "3 m")
	check(Combat.detection_gain(1.0, 170.0, true, SNEAK, false, false, CFG) > 0.0, "1 m")


func test_a_sleeper_sees_nothing_and_hears_little() -> void:
	eq(Combat.detection_gain(3.0, 0.0, false, STILL, true, true, CFG), 0.0, "cannot see")
	eq(Combat.detection_gain(6.0, 0.0, false, RUN, true, true, CFG), 0.0, "running at 6 m")
	check(Combat.detection_gain(2.0, 0.0, false, RUN, true, true, CFG) > 0.0, "running at 2 m")
