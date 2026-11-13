class_name Mission
extends Node3D
## Base for every playable episode. Owns the city, the battle, the player and
## the HUD, and gives mission scripts small awaitable steps: speak, wait,
## reach a place, clear a group of enemies.
##
## Subclasses set [member id], [member hero] and [member preset] in _init,
## place things in [method prepare] and tell the story in [method run].

## Never emitted: a finished mission parks its script on this.
signal _never
## Emitted when a wait may have ended: its timer ran out, or the player skipped.
signal _wake

var id: String = ""
var hero: String = "odysseus"
var preset: String = "day"
var data: Dictionary = {}
var world: TroyWorld
var battle: Battlefield
var player: Player
var hud: Hud
## Gate id -> [GateDoors].
var gates: Dictionary = {}
var ended: bool = false
## True when a script drives the mission instead of a person (test harness).
var autoplay: bool = false
## On-screen controls; null on a desktop.
var touch: TouchControls
## True while a title card fills the screen: the HUD and the touch controls
## stand down.
var cinematic: bool = false
## Music and ambience this mission will ask for, loaded behind the loading
## screen (see [method Sfx.preload_loops]).
var music: Array[StringName] = []
var ambience: Array[StringName] = []
var _scene: bool = false
var _skipping: bool = false
var _pause: PauseMenu
var _started_ms: int = 0
var _started_frame: int = 0


func _ready() -> void:
	autoplay = Game.args.has("autoplay")
	data = Data.mission(id)
	Sfx.music(&"")
	Sfx.ambience(&"")
	Sfx.preload_loops(music, ambience)
	world = Game.acquire_world(preset)
	add_child(world)
	world.ensure_navigation()
	battle = Battlefield.new()
	add_child(battle)
	battle.nav_ready = true
	var roles: Dictionary = Data.characters.get("roles", {})
	player = Player.new()
	player.battle = battle
	player.configure(hero, roles.get(hero, {}))
	add_child(player)
	battle.player = player
	hud = Hud.new()
	add_child(hud)
	hud.bind(player, battle)
	hud.mission = self
	if Game.mobile:
		touch = TouchControls.new()
		touch.player = player
		touch.mission = self
		add_child(touch)
	_pause = PauseMenu.new()
	_pause.mission = self
	add_child(_pause)
	player.died.connect(_on_player_died)
	for gate_id: String in world.info["gates"]:
		var doors := GateDoors.new()
		add_child(doors)
		doors.setup(world.gate(gate_id), true, false)
		gates[gate_id] = doors
	if not Game.is_harness() and not Game.mobile and not Game.web:
		# (A browser grants the pointer only on a click: see Player._unhandled_input.)
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	prepare()
	_apply_debug_args()
	_started_ms = Time.get_ticks_msec()
	_started_frame = Engine.get_physics_frames()
	_begin.call_deferred()


func _apply_debug_args() -> void:
	# Harness only: --at=x,y,z,yaw,pitch places the player; --pose=block|sword|dagger sets a stance.
	if Game.args.has("at"):
		var c: PackedStringArray = (Game.args["at"] as String).split(",")
		place_player(Vector3(float(c[0]), float(c[1]), float(c[2])), float(c[3]))
		player.set_pitch(float(c[4]))
	if Game.args.has("pause"):
		_pause.open.call_deferred()
	if Game.args.has("bot"):
		var bot: Node = (load("res://src/debug/bot.gd") as GDScript).new()
		bot.set("mission", self)
		add_child(bot)
	if Game.args.has("god"):
		player.invulnerable = true
	match str(Game.args.get("pose", "")):
		"block":
			player.debug_block = true
		"sword":
			player.equip("sword")
		"dagger":
			player.equip("dagger")


func _begin() -> void:
	await get_tree().process_frame
	await run()


## Override: place actors and props before the first frame.
func prepare() -> void:
	pass


## Override: the mission script.
func run() -> void:
	pass


# --- helpers for scripts -----------------------------------------------------------

## Names a point in the script. The harness can stop auto-play here with
## `--stop=<label>` so a screenshot shows the mission as it stands.
func mark(label: String) -> void:
	if autoplay and str(Game.args.get("stop", "")) == label:
		autoplay = false
		Game.args["stopped"] = "1"
		print("Mission %s: stopped at '%s'" % [id, label])


## Harness only (`--verbose`): logs each step of the script as it starts.
func _trace(what: String) -> void:
	if Game.args.has("verbose"):
		print("Mission %s @%.0fs: %s" % [id, (Engine.get_physics_frames() - _started_frame) / 60.0, what])


## Text from the mission data file. On a touch screen a "<key>_touch"
## entry, when present, replaces the one that names keys.
func text(key: String, fallback: String = "") -> String:
	var table: Dictionary = data.get("text", {})
	if Game.mobile and table.has(key + "_touch"):
		return str(table[key + "_touch"])
	return str(table.get(key, fallback))


## Puts the player at a point, facing [param yaw] radians.
func place_player(pos: Vector3, yaw: float) -> void:
	player.global_position = pos
	player.rotation.y = yaw
	player.velocity = Vector3.ZERO


## Waits [param seconds] of game time. Inside a scene the wait ends at once
## if the player skips.
func wait(seconds: float) -> void:
	if ended:
		await _never
	if autoplay:
		seconds = minf(seconds, 0.05)
	if _skipping:
		seconds = 0.02
	var state := {"done": false}
	var t := Timer.new()
	t.one_shot = true
	t.wait_time = maxf(seconds, 0.02)
	add_child(t)
	t.timeout.connect(func() -> void:
		state["done"] = true
		_wake.emit())
	t.start()
	while not state["done"] and not _skipping:
		await _wake
	t.queue_free()
	if ended:
		await _never


## Opens a stretch of story the player may skip whole: until
## [method scene_end], one press of Skip ends every line, wait and card.
## Keep anything the player must do outside it.
## [codeblock]
## scene_begin()
## await speak("helen_1")
## await speak("helen_2")
## scene_end()
## [/codeblock]
func scene_begin() -> void:
	_scene = true
	_skipping = false


## Closes the scene opened by [method scene_begin].
func scene_end() -> void:
	_scene = false
	_skipping = false


## True while a press of Skip would do something.
func can_skip() -> bool:
	return _scene and not ended and not autoplay and not _skipping


## Skips to the end of the scene in progress.
func skip() -> void:
	if not can_skip():
		return
	_skipping = true
	Sfx.hush_voice()
	hud.hush()
	_wake.emit()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"skip") and can_skip() and not get_tree().paused:
		skip()
		get_viewport().set_input_as_handled()


## Shows the mission's title and introduction, read aloud, for at least
## [param seconds]; then clears it. Call inside a scene to make it skippable.
func card(seconds: float) -> void:
	if autoplay:
		return
	cinematic = true
	var spoken: float = Sfx.speak(id, "text_intro") if not _skipping else 0.0
	hud.show_card(text("title"), text("intro"))
	await wait(maxf(seconds, spoken + 1.2))
	await hud.hide_card(0.3 if _skipping else 1.2)
	cinematic = false


## Shows a line of speech and waits while it is read. [param voice] names
## the recording to play with it (see [method Sfx.speak]).
func say(speaker: String, line: String, seconds: float = 0.0, voice: String = "") -> void:
	if ended:
		await _never
	if _skipping:
		return
	var spoken: float = Sfx.speak(id, voice) if voice != "" and not autoplay else 0.0
	if spoken > 0.0:
		seconds = spoken + 0.4
	elif seconds <= 0.0:
		seconds = maxf(2.4, 1.3 + line.split(" ").size() * 0.34)
	hud.say(speaker, line, seconds)
	await wait(seconds + 0.25)


## Speaks a line from the mission data: "lines": {"key": ["Speaker", "Text"]}.
## The voice is assets/audio/voice/<mission>/<key>.ogg when it exists.
func speak(key: String) -> void:
	var lines: Dictionary = data.get("lines", {})
	if not lines.has(key):
		push_warning("Mission %s: no line '%s'" % [id, key])
		return
	var entry: Array = lines[key]
	_trace("speak " + key)
	await say(str(entry[0]), str(entry[1]), 0.0, key)


## Sets the objective from the mission data: "objectives": {"key": "Text"}.
func objective(key: String, marker: Variant = null) -> void:
	var objectives: Dictionary = data.get("objectives", {})
	hud.set_objective(str(objectives.get(key, key)), marker, str(objectives.get(key + "_sub", "")))


## Waits until [param condition] returns true.
func until(condition: Callable, poll: float = 0.15) -> void:
	while not condition.call():
		if ended:
			await _never
		var t := Timer.new()
		t.one_shot = true
		t.wait_time = poll
		add_child(t)
		t.start()
		await t.timeout
		t.queue_free()
	if ended:
		await _never


## Waits until the player stands within [param radius] of [param pos].
func reach(pos: Vector3, radius: float = 3.0) -> void:
	_trace("reach %s within %.0f m" % [str(pos.round()), radius])
	if autoplay:
		await wait(0.1)
		place_player(pos + Vector3(0, 0.3, 0), player.rotation.y)
		await wait(0.1)
		return
	await until(func() -> bool:
		var d := player.global_position - pos
		return Vector2(d.x, d.z).length() <= radius and absf(d.y) < 4.0)


## Waits until every soldier in [param group] is dead.
func all_dead(group: Array) -> void:
	_trace("all_dead (%d)" % group.size())
	if autoplay:
		for s: Soldier in group:
			if is_instance_valid(s) and s.is_alive():
				s.kill()
				await wait(0.02)
	await until(func() -> bool:
		for s: Soldier in group:
			if is_instance_valid(s) and s.is_alive():
				return false
		return true)


## Waits until the player uses [param item].
func used(item: Interactable) -> void:
	if autoplay:
		await wait(0.1)
		item.interact(player)
		return
	await item.used
	if ended:
		await _never


## Adds something the player can use at a world position.
func add_interactable(pos: Vector3, prompt: String, hold: float = 0.0, radius: float = 2.6, focus_height: float = 0.0) -> Interactable:
	var it := Interactable.new()
	it.prompt = prompt
	it.hold_seconds = hold
	it.radius = radius
	it.focus_height = focus_height
	add_child(it)
	it.global_position = pos
	return it


## Spawns a soldier (see [method Battlefield.spawn]).
func spawn(role_id: String, pos: Vector3, yaw: float = 0.0, opts: Dictionary = {}) -> Soldier:
	return battle.spawn(role_id, pos, yaw, opts)


## Spawns [param count] soldiers scattered round a point. Roles are picked in turn.
func spawn_group(roles: Array, count: int, centre: Vector3, spread: float, yaw: float, opts: Dictionary = {}) -> Array[Soldier]:
	var out: Array[Soldier] = []
	if count > 3:
		count = maxi(3, roundi(count * Game.crowd_scale()))
	for i in count:
		var a := TAU * i / maxf(count, 1.0) + randf() * 0.8
		var r := spread * sqrt((i + 1.0) / count)
		var p := centre + Vector3(cos(a) * r, 0.0, sin(a) * r)
		p.y = TroyLayout.height(p.x, p.z) + 0.1 if absf(TroyLayout.height(p.x, p.z) - centre.y) < 3.0 else centre.y
		var s := spawn(str(roles[i % roles.size()]), p, yaw + randf_range(-0.3, 0.3), opts)
		if s != null:
			out.append(s)
	return out


## Yaw (radians) that faces from one point toward another.
static func yaw_to(from: Vector3, to: Vector3) -> float:
	return atan2(-(to.x - from.x), -(to.z - from.z))


# --- endings ----------------------------------------------------------------------

func _on_player_died() -> void:
	if ended:
		return
	await get_tree().create_timer(1.6).timeout
	fail(text("death_title", "You have fallen"), text("death_text", ""), "text_death_text")


## Ends the mission in defeat. [param voice] names the narration to read.
func fail(title: String, body: String, voice: String = "") -> void:
	if ended:
		return
	ended = true
	_wake.emit()
	player.control_enabled = false
	Sfx.music(&"lament")
	if voice != "" and not autoplay:
		Sfx.speak(id, voice)
	_report("MISSION FAILED (%s)" % title)
	hud.show_end(title, body, {"Try again": retry, "Main menu": Game.start_menu}, false)
	if autoplay or Game.args.has("bot"):
		get_tree().quit(1)


## Ends the mission in victory.
func complete(title: String, body: String) -> void:
	if ended:
		return
	ended = true
	_wake.emit()
	player.control_enabled = false
	player.invulnerable = true
	Sfx.music(&"lament")
	if not autoplay:
		Sfx.speak(id, "text_end_text")
	_report("MISSION COMPLETE")
	hud.show_end(title, body, {"Continue": Game.start_menu, "Play again": retry}, true)
	if autoplay or Game.args.has("bot"):
		get_tree().quit(0)


func _report(what: String) -> void:
	print("%s: %s after %.1f s wall, %.0f s game time, kills %d, health %.0f" % [what, id,
		(Time.get_ticks_msec() - _started_ms) * 0.001, (Engine.get_physics_frames() - _started_frame) / 60.0,
		player.kills, player.health])


## Restarts this mission.
func retry() -> void:
	Game.start_mission(id)
