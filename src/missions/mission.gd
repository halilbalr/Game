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
var _pause: PauseMenu
var _started_ms: int = 0
var _started_frame: int = 0


func _ready() -> void:
	autoplay = Game.args.has("autoplay")
	data = Data.mission(id)
	Sfx.music(&"")
	Sfx.ambience(&"")
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
	_pause = PauseMenu.new()
	_pause.mission = self
	add_child(_pause)
	player.died.connect(_on_player_died)
	for gate_id: String in world.info["gates"]:
		var doors := GateDoors.new()
		add_child(doors)
		doors.setup(world.gate(gate_id), true, false)
		gates[gate_id] = doors
	if not Game.is_harness():
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


## Text from the mission data file.
func text(key: String, fallback: String = "") -> String:
	return str((data.get("text", {}) as Dictionary).get(key, fallback))


## Puts the player at a point, facing [param yaw] radians.
func place_player(pos: Vector3, yaw: float) -> void:
	player.global_position = pos
	player.rotation.y = yaw
	player.velocity = Vector3.ZERO


## Waits [param seconds] of game time.
func wait(seconds: float) -> void:
	if ended:
		await _never
	if autoplay:
		seconds = minf(seconds, 0.05)
	var t := Timer.new()
	t.one_shot = true
	t.wait_time = maxf(seconds, 0.02)
	add_child(t)
	t.start()
	await t.timeout
	t.queue_free()
	if ended:
		await _never


## Shows a line of speech and waits while it is read.
func say(speaker: String, line: String, seconds: float = 0.0) -> void:
	if ended:
		await _never
	if seconds <= 0.0:
		seconds = maxf(2.4, 1.3 + line.split(" ").size() * 0.34)
	hud.say(speaker, line, seconds)
	await wait(seconds + 0.25)


## Speaks a line from the mission data: "lines": {"key": ["Speaker", "Text"]}.
func speak(key: String) -> void:
	var lines: Dictionary = data.get("lines", {})
	if not lines.has(key):
		push_warning("Mission %s: no line '%s'" % [id, key])
		return
	var entry: Array = lines[key]
	await say(str(entry[0]), str(entry[1]))


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
	fail(text("death_title", "You have fallen"), text("death_text", ""))


## Ends the mission in defeat.
func fail(title: String, body: String) -> void:
	if ended:
		return
	ended = true
	player.control_enabled = false
	_report("MISSION FAILED (%s)" % title)
	hud.show_end(title, body, {"Try again": retry, "Main menu": Game.start_menu}, false)
	if autoplay or Game.args.has("bot"):
		get_tree().quit(1)


## Ends the mission in victory.
func complete(title: String, body: String) -> void:
	if ended:
		return
	ended = true
	player.control_enabled = false
	player.invulnerable = true
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
