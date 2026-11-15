extends TestCase
## The sea levels: the water surface, the islands' ground and the cave.


func test_sea_height_stays_within_the_summed_amplitudes() -> void:
	var sea := Sea.new()
	var most := 0.0
	for w: Array in Sea.WAVES:
		most += float(w[3])
	for i in 40:
		sea.time = i * 0.37
		var h := sea.height(i * 13.1 - 200.0, i * 7.3 + 50.0)
		check(absf(h) <= most + 1e-4, "height %f at step %d" % [h, i])
	sea.free()


func test_sea_height_is_flat_without_swell() -> void:
	var sea := Sea.new()
	sea.swell = 0.0
	sea.time = 12.5
	near(sea.height(31.0, -77.0), 0.0, 1e-6)
	sea.free()


func test_whirlpool_sinks_the_water_deepest_at_its_eye() -> void:
	var sea := Sea.new()
	sea.swell = 0.0
	sea.vortex = Vector4(-50.0, -950.0, 60.0, 9.0)
	near(sea.height(-50.0, -950.0), -9.0, 1e-4, "eye")
	var mid := sea.height(-20.0, -950.0)
	var edge := sea.height(70.0, -950.0)
	check(mid < edge and mid > -9.0, "funnel deepens toward the eye (%f, %f)" % [mid, edge])
	near(sea.height(800.0, -950.0), 0.0, 0.05, "far off")
	sea.free()


func test_island_flats_hold_their_height() -> void:
	var isle := Island.new(Vector2.ZERO, Vector2(250.0, 195.0), 58.0, 11)
	isle.flats.append([Vector2(40.0, 108.0), 22.0, 14.0])
	near(isle.height(40.0, 108.0), 14.0, 1e-4, "middle of the flat")
	near(isle.height(55.0, 115.0), 14.0, 1e-4, "inside its radius")


func test_island_sinks_below_the_sea_past_its_coast() -> void:
	var isle := Island.new(Vector2(-420.0, 640.0), Vector2(120.0, 90.0), 20.0, 3)
	check(isle.height(-420.0, 640.0) > 0.0, "the middle is dry land")
	check(isle.height(-420.0 + 200.0, 640.0) < 0.0, "out past the coast is sea")
	eq(isle.height(-400.0, 610.0), isle.height(-400.0, 610.0), "deterministic")


func test_cave_doorway_is_wide_enough_to_walk_through() -> void:
	# The shell's two sides at the doorway, at a man's height.
	var gap := asin(Cave.DOOR_W * 0.5 / Cave.R)
	var left := Cave.shell(-gap, 1.0, 0.0)
	var right := Cave.shell(gap, 1.0, 0.0)
	check(left.distance_to(right) > 5.0, "door width %f" % left.distance_to(right))
	check(Cave.DOOR_H > 2.5, "door height")


func test_sea_floor_falls_away_below_the_strand() -> void:
	# Arrange: an island and a bearing from its middle out to sea.
	var isle := Island.new(Vector2.ZERO, Vector2(120.0, 90.0), 20.0, 3)
	var under := 0
	# Act / assert: once under water, the bottom is never a shallow bar near the surface.
	for i in 120:
		var h := isle.height(i * 1.5, 0.0)
		if h < 0.0:
			under += 1
			check(h < -0.6, "at %.0f m the bottom is %.2f m, a bar the troughs would show" % [i * 1.5, h])
	check(under > 10, "the bearing reaches open water")
