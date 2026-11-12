extends TestCase
## A watchman, a floor and the player: seeing, not seeing, and the silent kill.

const SETTLE_FRAMES := 20
const WATCH_FRAMES := 240


class Stage:
	var root: Node3D
	var battle: Battlefield
	var player: Player
	var sentry: Soldier


func _stage(asleep: bool = false) -> Stage:
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
	st.battle = Battlefield.new()
	st.root.add_child(st.battle)
	st.player = Player.new()
	st.player.battle = st.battle
	st.player.configure("odysseus", Data.characters["roles"]["odysseus"])
	st.root.add_child(st.player)
	st.player.bot_control = true
	st.battle.player = st.player
	# The watchman stands at the origin looking north (-Z).
	st.sentry = st.battle.spawn("trojan_sentry", Vector3(0, 0.1, 0), 0.0,
		{"aware": false, "asleep": asleep, "stance": &"sit" if asleep else &"sentry"})
	return st


func _clear(st: Stage) -> void:
	for action: StringName in [&"crouch", &"attack", &"move_forward", &"sprint"]:
		Input.action_release(action)
	st.root.queue_free()
	await frames(2)


func test_player_standing_in_front_is_noticed() -> void:
	var st := _stage()
	st.player.global_position = Vector3(0, 0.1, -8.0)
	await frames(WATCH_FRAMES)
	check(st.sentry.aware, "watchman should have seen a man standing 8 m in front of him")
	await _clear(st)


func test_player_crouched_behind_is_not_noticed() -> void:
	var st := _stage()
	st.player.global_position = Vector3(0, 0.1, 5.0)
	Input.action_press(&"crouch")
	await frames(WATCH_FRAMES)
	check(not st.sentry.aware, "watchman should not notice a still, crouched man behind him")
	near(st.sentry.detection, 0.0, 0.05)
	await _clear(st)


func test_blow_on_an_unaware_watchman_kills_silently() -> void:
	var st := _stage()
	st.player.global_position = Vector3(0, 0.1, 1.3)
	st.player.look_toward(st.sentry.global_position + Vector3(0, 1.2, 0))
	st.player.equip("dagger")
	Input.action_press(&"crouch")
	await frames(SETTLE_FRAMES)
	Input.action_press(&"attack")
	await frames(2)
	Input.action_release(&"attack")
	await frames(40)
	check(not st.sentry.is_alive(), "one blow from behind should kill")
	eq(st.player.kills, 1)
	await _clear(st)


func test_sleeper_is_not_woken_by_a_crouched_walk_past() -> void:
	var st := _stage(true)
	st.player.global_position = Vector3(3.0, 0.1, 6.0)
	st.player.rotation.y = 0.0
	Input.action_press(&"crouch")
	Input.action_press(&"move_forward")
	await frames(WATCH_FRAMES)
	check(st.player.global_position.z < 0.0, "the player should have walked past")
	check(st.sentry.asleep, "sleeper should stay asleep")
	await _clear(st)


func test_sleeper_is_woken_by_running_feet_at_his_side() -> void:
	var st := _stage(true)
	st.player.global_position = Vector3(1.6, 0.1, 9.0)
	st.player.rotation.y = 0.0
	Input.action_press(&"move_forward")
	Input.action_press(&"sprint")
	await frames(WATCH_FRAMES)
	check(not st.sentry.asleep, "sleeper should wake to running feet 1.6 m away")
	await _clear(st)
