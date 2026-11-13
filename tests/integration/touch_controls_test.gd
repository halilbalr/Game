extends TestCase
## Synthetic fingers on the touch layout: the stick walks, a drag turns the
## view, the buttons strike and raise the shield, and a drag never strikes.

const SETTLE := 6
const WALK_FRAMES := 60
const STICK_START := Vector2(220, 820)
const LOOK_START := Vector2(1150, 420)


class Stage:
	var root: Node3D
	var player: Player
	var touch: TouchControls


func _stage() -> Stage:
	Game.mobile = true
	Game._prepare_for_touch()
	var st := Stage.new()
	st.root = Node3D.new()
	tree.root.add_child(st.root)
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = 1
	var shape := BoxShape3D.new()
	shape.size = Vector3(80, 1, 80)
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position = Vector3(0, -0.5, 0)
	floor_body.add_child(cs)
	st.root.add_child(floor_body)
	var battle := Battlefield.new()
	st.root.add_child(battle)
	st.player = Player.new()
	st.player.battle = battle
	st.player.configure("hector", Data.characters["roles"]["hector"])
	st.root.add_child(st.player)
	battle.player = st.player
	st.player.global_position = Vector3(0, 0.1, 0)
	st.touch = TouchControls.new()
	st.touch.player = st.player
	st.root.add_child(st.touch)
	return st


func _clear(st: Stage) -> void:
	st.touch._release_all()
	st.root.queue_free()
	Game.mobile = false
	await frames(2)


## Events reach the engine in window pixels and are mapped to the canvas by
## the stretch transform. Tests think in canvas units, so map the other way.
func _to_window(canvas_pos: Vector2) -> Vector2:
	return tree.root.get_final_transform() * canvas_pos


func _touch(index: int, pos: Vector2, pressed: bool) -> void:
	var ev := InputEventScreenTouch.new()
	ev.index = index
	ev.position = _to_window(pos)
	ev.pressed = pressed
	Input.parse_input_event(ev)


func _drag(index: int, from: Vector2, to: Vector2) -> void:
	var ev := InputEventScreenDrag.new()
	ev.index = index
	ev.position = _to_window(to)
	ev.relative = _to_window(to) - _to_window(from)
	Input.parse_input_event(ev)


func test_stick_pushed_forward_walks_the_player_forward() -> void:
	var st := _stage()
	await frames(SETTLE)
	_touch(0, STICK_START, true)
	_drag(0, STICK_START, STICK_START + Vector2(0, -70))
	await frames(WALK_FRAMES)
	check(st.player.global_position.z < -1.0, "player should have walked forward, z = %f" % st.player.global_position.z)
	check(Input.is_action_pressed(&"move_forward"))
	_touch(0, STICK_START + Vector2(0, -70), false)
	await frames(SETTLE)
	check(not Input.is_action_pressed(&"move_forward"), "lifting the thumb stops the walk")
	await _clear(st)


func test_stick_pushed_to_its_rim_runs() -> void:
	var st := _stage()
	await frames(SETTLE)
	_touch(0, STICK_START, true)
	_drag(0, STICK_START, STICK_START + Vector2(0, -TouchControls.STICK_RADIUS * 1.2))
	await frames(SETTLE)
	check(Input.is_action_pressed(&"sprint"))
	_touch(0, STICK_START, false)
	await _clear(st)


func test_drag_on_the_right_turns_the_view() -> void:
	var st := _stage()
	await frames(SETTLE)
	var before := st.player.rotation.y
	_touch(1, LOOK_START, true)
	_drag(1, LOOK_START, LOOK_START + Vector2(100, 0))
	await frames(SETTLE)
	near(st.player.rotation.y, before - 100.0 * TouchControls.LOOK_SPEED, 0.01, "dragging right turns right")
	_touch(1, LOOK_START + Vector2(100, 0), false)
	await _clear(st)


func test_drag_to_look_does_not_strike() -> void:
	var st := _stage()
	await frames(SETTLE)
	_touch(1, LOOK_START, true)
	_drag(1, LOOK_START, LOOK_START + Vector2(60, 20))
	await frames(SETTLE)
	check(not st.player.viewmodel.is_busy(), "a look-drag must not start an attack")
	_touch(1, LOOK_START, false)
	await _clear(st)


func test_strike_button_starts_an_attack() -> void:
	var st := _stage()
	await frames(SETTLE)
	var pos := st.touch._button_centre("strike")
	_touch(2, pos, true)
	await frames(SETTLE)
	check(st.player.viewmodel.is_busy(), "tapping STRIKE should start an attack")
	_touch(2, pos, false)
	await _clear(st)


func test_shield_button_holds_and_releases_the_block() -> void:
	var st := _stage()
	await frames(SETTLE)
	var pos := st.touch._button_centre("shield")
	_touch(3, pos, true)
	await frames(SETTLE)
	check(st.player.blocking, "holding SHIELD raises the shield")
	_touch(3, pos, false)
	await frames(SETTLE)
	check(not st.player.blocking, "lifting the thumb lowers it")
	await _clear(st)


func test_crouch_button_toggles() -> void:
	var st := _stage()
	await frames(SETTLE)
	var pos := st.touch._button_centre("crouch")
	_touch(4, pos, true)
	_touch(4, pos, false)
	await frames(SETTLE)
	check(st.player.crouching, "first tap crouches")
	_touch(4, pos, true)
	_touch(4, pos, false)
	await frames(SETTLE)
	check(not st.player.crouching, "second tap stands")
	await _clear(st)


func test_buttons_all_sit_inside_a_phone_screen() -> void:
	var st := _stage()
	await frames(SETTLE)
	var size := st.touch._size()
	for id: String in TouchControls.BUTTONS:
		var c := st.touch._button_centre(id)
		var r: float = TouchControls.BUTTONS[id][1]
		check(c.x - r >= 0.0 and c.x + r <= size.x and c.y - r >= 0.0 and c.y + r <= size.y, "%s is off screen" % id)
	# No two buttons may overlap.
	var ids := TouchControls.BUTTONS.keys()
	for i in ids.size():
		for j in range(i + 1, ids.size()):
			var gap := st.touch._button_centre(ids[i]).distance_to(st.touch._button_centre(ids[j]))
			check(gap > (TouchControls.BUTTONS[ids[i]][1] as float) + (TouchControls.BUTTONS[ids[j]][1] as float),
				"%s overlaps %s" % [ids[i], ids[j]])
	await _clear(st)


## An iPhone held sideways: 956 x 440 points, drawn at the phone interface
## scale of 1.7 over a 1080-unit-high design.
const PHONE_SCREEN := Vector2(1380.0, 635.0)


func test_phone_buttons_fit_a_phone_held_sideways_without_touching() -> void:
	# Arrange: every button of the phone layout as a circle on that screen.
	var circles := {}
	for id: String in TouchControls.PHONE_OFFSETS:
		circles[id] = [PHONE_SCREEN + (TouchControls.PHONE_OFFSETS[id][0] as Vector2), TouchControls.PHONE_OFFSETS[id][1] as float]
	check(circles.size() == TouchControls.BUTTONS.size(), "every button has a phone position")
	# Fixed furniture they must stay clear of: the resting stick, Pause, Skip.
	var stick := [Vector2(170.0, PHONE_SCREEN.y - 160.0), TouchControls.STICK_RADIUS]
	var pause := [Vector2(PHONE_SCREEN.x - 64.0, 62.0), 34.0]
	var skip := Rect2(PHONE_SCREEN.x - 276.0, 30.0, 160.0, 64.0)
	# Assert.
	var ids := circles.keys()
	for i in ids.size():
		var c: Vector2 = circles[ids[i]][0]
		var r: float = circles[ids[i]][1]
		check(c.x - r >= 0.0 and c.x + r <= PHONE_SCREEN.x and c.y - r >= 0.0 and c.y + r <= PHONE_SCREEN.y, "%s is off screen" % ids[i])
		# 45 units is 5.2 mm on a 6.9-inch phone: a button at least 10 mm across.
		check(r >= 45.0, "%s is too small to hit" % ids[i])
		check(c.distance_to(stick[0]) > r + (stick[1] as float), "%s sits on the stick" % ids[i])
		check(c.distance_to(pause[0]) > r + (pause[1] as float), "%s sits on Pause" % ids[i])
		check(not skip.grow(r).has_point(c), "%s sits on Skip" % ids[i])
		for j in range(i + 1, ids.size()):
			check(c.distance_to(circles[ids[j]][0]) > r + (circles[ids[j]][1] as float), "%s overlaps %s" % [ids[i], ids[j]])


func test_look_drag_with_two_thumbs_down_turns_by_the_distance_moved() -> void:
	# Arrange: one thumb on the stick, one looking. In a browser the engine
	# measures a drag from whichever finger came first in the previous touch
	# event, so with two thumbs down the relative it reports can be hundreds
	# of pixels off. The position it reports is always right.
	var st := _stage()
	await frames(SETTLE)
	_touch(0, STICK_START, true)
	_touch(1, LOOK_START, true)
	await frames(2)
	var yaw_before := st.player.rotation.y
	var moved_to := LOOK_START + Vector2(10, 0)
	# Act: the looking thumb moves 10 units right; the event claims it came
	# from where the stick thumb is.
	var ev := InputEventScreenDrag.new()
	ev.index = 1
	ev.position = _to_window(moved_to)
	ev.relative = _to_window(moved_to) - _to_window(STICK_START)
	Input.parse_input_event(ev)
	await frames(2)
	# Assert
	var expected := -10.0 * TouchControls.LOOK_SPEED * float(Game.settings.get("mouse_sensitivity", 1.0))
	var turned := st.player.rotation.y - yaw_before
	check(absf(turned - expected) < 0.002, "turned %.4f rad, expected %.4f" % [turned, expected])
	_touch(1, moved_to, false)
	_touch(0, STICK_START, false)
	await _clear(st)
