extends TestCase
## TroyBuilder: the generated city is complete, repeatable and walkable.

static var _built: TroyBuilder


func _city() -> TroyBuilder:
	if _built == null:
		_built = TroyBuilder.new()
		_built.build()
	return _built


func test_obb_overlap_detects_touching_and_separate_rectangles() -> void:
	var half := Vector2(2.0, 1.0)
	check(TroyBuilder.obb_overlap(Vector2.ZERO, half, 0.0, Vector2(3.0, 0.0), half, 0.0), "overlapping")
	check(not TroyBuilder.obb_overlap(Vector2.ZERO, half, 0.0, Vector2(5.0, 0.0), half, 0.0), "apart")
	check(not TroyBuilder.obb_overlap(Vector2.ZERO, half, 0.0, Vector2(0.0, 3.5), half, PI * 0.5), "turned, apart")
	check(TroyBuilder.obb_overlap(Vector2.ZERO, half, 0.0, Vector2(0.0, 2.5), half, PI * 0.5), "turned, overlapping")


func test_city_records_all_four_gates() -> void:
	var gates: Dictionary = _city().info["gates"]
	for key: String in ["south_gate", "east_gate", "scaean_gate", "dardanian_gate"]:
		check(gates.has(key), key)


func test_city_has_markers_the_missions_ask_for() -> void:
	var markers: Dictionary = _city().info["markers"]
	for key: String in ["horse", "court", "palace", "temple_athena", "house_deiphobus", "house_hector", "agora",
			"oak", "south_gate", "scaean_gate", "great_tower", "springs", "tomb_ilus"]:
		check(markers.has(key), key)


func test_city_has_a_dense_lower_town() -> void:
	check((_city().info["houses"] as Array).size() > 350, "house count %d" % (_city().info["houses"] as Array).size())


func test_no_house_stands_in_a_main_street() -> void:
	var streets := TroyBuilder.street_segments()
	for h: Dictionary in _city().info["houses"]:
		var p := Vector2((h["pos"] as Vector3).x, (h["pos"] as Vector3).z)
		if TroyLayout.in_citadel(p.x, p.y):
			continue
		for s: Array in streets:
			if not (s[3] as bool):
				continue
			var a: Vector2 = s[0]
			var ab: Vector2 = (s[1] as Vector2) - a
			var t := clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
			check(p.distance_to(a + ab * t) > (s[2] as float) * 0.5, "house at %s in a paved street" % str(p))


func test_city_generation_is_repeatable() -> void:
	var again := TroyBuilder.new()
	again.build()
	eq(again.b.triangle_count(), _city().b.triangle_count())
	eq((again.info["houses"] as Array).size(), (_city().info["houses"] as Array).size())


func test_gate_records_carry_what_the_doors_need() -> void:
	for rec: Dictionary in (_city().info["gates"] as Dictionary).values():
		for key: String in ["pos", "normal", "width", "height", "door_offset"]:
			check(rec.has(key), key)
		near((rec["normal"] as Vector3).length(), 1.0, 0.01)
