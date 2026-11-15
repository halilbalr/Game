extends TestCase
## The ship's oars and the men at them: every manned oar runs from its
## oarlock through the rower's two hands, at every point of the stroke.

const GRIP_TOLERANCE := 0.06


func _ship() -> Ship:
	var ship := Ship.new()
	tree.root.add_child(ship)
	return ship


## Lets the figures pose and the ship lay its oars: drawing frames, not physics ones.
func _settle(count: int) -> void:
	for i in count:
		await tree.process_frame


## Distance from the midpoint of a rower's hands to the line of his oar.
func _grip_error(ship: Ship, station: int) -> float:
	var hull: Node3D = ship.get("_hull")
	var rower: Humanoid = (ship.get("_manned") as Dictionary)[station]
	var g := rower.grip_points()
	var grip := hull.to_local((g[0] + g[1]) * 0.5)
	var xf := ship.oar_transform(station)
	var axis := xf.basis.x.normalized()
	var rel := grip - xf.origin
	return (rel - axis * rel.dot(axis)).length()


func test_every_manned_oar_passes_through_the_rowers_hands() -> void:
	var ship := _ship()
	var manned: Dictionary = ship.get("_manned")
	check(manned.size() >= 8, "the benches are manned (%d)" % manned.size())
	for phase: float in [0.0, 1.3, 2.6, 4.4]:
		for r in ship.rowers:
			r.row_phase = phase
		await _settle(3)
		for station: int in manned:
			var err := _grip_error(ship, station)
			check(err < GRIP_TOLERANCE, "station %d at phase %.1f: hands %.3f m off the oar" % [station, phase, err])
	ship.queue_free()


func test_an_oar_reaches_inboard_to_its_rowers_hands() -> void:
	var ship := _ship()
	await _settle(3)
	var hull: Node3D = ship.get("_hull")
	for station: int in ship.get("_manned"):
		var rower: Humanoid = (ship.get("_manned") as Dictionary)[station]
		var g := rower.grip_points()
		var reach := hull.to_local((g[0] + g[1]) * 0.5).distance_to(ship.oar_transform(station).origin)
		# The oar's handle reaches 1.3 m inboard of the oarlock.
		check(reach < 1.3, "station %d: hands %.2f m from the oarlock" % [station, reach])
	ship.queue_free()


func test_lost_rowers_let_their_oars_trail() -> void:
	var ship := _ship()
	await frames(2)
	var before := ship.rowers.size()
	ship.lose_rowers(2)
	await frames(2)
	eq(ship.rowers.size(), before - 2, "two men taken from the benches")
	var lost: Dictionary = ship.get("_lost")
	eq(lost.size(), 2, "their two oars trail")
	ship.queue_free()


func test_lens_water_never_holds_more_than_its_drops() -> void:
	var lens := LensWater.new()
	tree.root.add_child(lens)
	for i in 5:
		lens.splash(1.0)
	var drops: Array = lens.get("_drops")
	check(drops.size() <= LensWater.MAX_DROPS, "drops %d" % drops.size())
	check(drops.size() > 0, "a splash leaves drops")
	lens.queue_free()
