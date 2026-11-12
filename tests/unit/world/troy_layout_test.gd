extends TestCase
## TroyLayout: the single source of truth for where everything stands.

const EPS := 0.01


func test_citadel_points_lie_on_the_wall_ellipse() -> void:
	for deg: float in [0.0, 37.0, 90.0, 158.0, 270.0]:
		var p := TroyLayout.citadel_point(deg)
		near(TroyLayout.citadel_r(p.x, p.y), 1.0, EPS, "angle %f" % deg)


func test_south_gate_is_due_south_of_the_citadel() -> void:
	var gate := TroyLayout.citadel_point(TroyLayout.SOUTH_GATE_DEG)
	near(gate.x, 0.0, EPS)
	near(gate.y, TroyLayout.CITADEL_RZ, EPS)


func test_citadel_normal_points_outward() -> void:
	for deg: float in [0.0, 90.0, 200.0]:
		var p := TroyLayout.citadel_point(deg)
		var n := TroyLayout.citadel_normal(deg)
		check(p.dot(n) > 0.0, "angle %f" % deg)
		near(n.length(), 1.0, EPS)


func test_summit_stands_above_the_lower_town() -> void:
	near(TroyLayout.height(0.0, 0.0), TroyLayout.SUMMIT_HEIGHT, 0.6)
	check(TroyLayout.height(0.0, 0.0) > TroyLayout.height(0.0, 150.0) + 5.0)


func test_plain_lies_far_below_the_plateau() -> void:
	near(TroyLayout.height(-450.0, 80.0), TroyLayout.PLAIN_Y, 3.5)


func test_north_scarp_falls_away_behind_the_citadel() -> void:
	check(TroyLayout.height(0.0, -150.0) < TroyLayout.height(0.0, -70.0) - 10.0)


func test_height_is_deterministic() -> void:
	eq(TroyLayout.height(-123.4, 211.5), TroyLayout.height(-123.4, 211.5))


func test_in_citadel_and_in_lower_town_do_not_overlap() -> void:
	check(TroyLayout.in_citadel(10.0, 10.0))
	check(not TroyLayout.in_lower_town(10.0, 10.0))
	check(TroyLayout.in_lower_town(0.0, 200.0))
	check(not TroyLayout.in_citadel(0.0, 200.0))
	check(not TroyLayout.in_lower_town(-400.0, 200.0), "the plain")


func test_lower_wall_meets_the_citadel_on_both_sides() -> void:
	var span := TroyLayout.lower_wall_span()
	var west := TroyLayout.lower_point(span.x)
	var east := TroyLayout.lower_point(span.y)
	check(west.x < 0.0 and east.x > 0.0, "one joint each side")
	near(absf(west.x), absf(east.x), 3.0, "symmetric joints")
	check(TroyLayout.citadel_r(west.x, west.y) < 1.1 and TroyLayout.citadel_r(east.x, east.y) < 1.1, "joints touch the citadel wall")


func test_scaean_gate_faces_the_western_plain() -> void:
	var gate := TroyLayout.lower_point(TroyLayout.SCAEAN_GATE_DEG)
	var n := TroyLayout.lower_normal(TroyLayout.SCAEAN_GATE_DEG)
	check(gate.x < -150.0, "on the west side")
	check(n.x < -0.8, "opening west")


func test_ditch_is_cut_beyond_the_wall_but_not_across_the_causeway() -> void:
	var deg := 90.0
	var p := TroyLayout.lower_point(deg) + TroyLayout.lower_normal(deg) * TroyLayout.DITCH_OFFSET
	check(TroyLayout.ditch_depth(p.x, p.y) > 1.0, "ditch south of the town")
	var g := TroyLayout.lower_point(TroyLayout.SCAEAN_GATE_DEG) \
		+ TroyLayout.lower_normal(TroyLayout.SCAEAN_GATE_DEG) * TroyLayout.DITCH_OFFSET
	near(TroyLayout.ditch_depth(g.x, g.y), 0.0, 0.3, "causeway at the Scaean Gate")
	eq(TroyLayout.ditch_depth(0.0, 150.0), 0.0, "none inside the town")


func test_named_places_include_every_mission_landmark() -> void:
	var places := TroyLayout.places()
	for key: String in ["south_gate", "scaean_gate", "dardanian_gate", "horse", "temple_athena", "palace",
			"house_deiphobus", "oak", "fig_tree", "springs", "tomb_ilus"]:
		check(places.has(key), key)
