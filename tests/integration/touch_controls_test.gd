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
