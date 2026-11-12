extends Node
## Autoload "Game": boot arguments, settings, input map and screen flow.

signal settings_changed

const SETTINGS_PATH := "user://settings.cfg"
const MISSIONS := {
	"horse": "res://src/missions/mission_horse.gd",
	"gate": "res://src/missions/mission_gate.gd",
	"roam": "res://src/missions/mission_roam.gd",
}

## Command-line user arguments (after `--`), as key -> value.
var args: Dictionary = {}
var settings: Dictionary = {
	"mouse_sensitivity": 1.0, "fov": 75.0, "blood": true, "quality": 1,
	"master_volume": 0.8, "fullscreen": true, "invert_y": false, "head_bob": true,
	"difficulty": 1,
}
## True on phones and tablets (or with `--mobile` on a desktop, for testing):
## touch controls, lighter graphics, smaller crowds.
var mobile: bool = false
var main: Node
var screen: Node
var world: TroyWorld
var _loading: CanvasLayer


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for raw in OS.get_cmdline_user_args():
		var a := raw.trim_prefix("--")
		var eq := a.find("=")
		if eq >= 0:
			args[a.substr(0, eq)] = a.substr(eq + 1)
		else:
			args[a] = "1"
	mobile = OS.has_feature("mobile") or args.has("mobile")
	_register_inputs()
	if mobile:
		_prepare_for_touch()
	_load_settings()
	if args.has("quality"):
		settings["quality"] = int(args["quality"])
	apply_settings()


func _prepare_for_touch() -> void:
	# Touches are also reported as left clicks; a look-drag must not strike.
	for action: StringName in [&"attack", &"block", &"throw", &"weapon_next", &"weapon_prev"]:
		for ev in InputMap.action_get_events(action):
			if ev is InputEventMouseButton:
				InputMap.action_erase_event(action, ev)
	settings["quality"] = 0
	get_tree().set_quit_on_go_back(false)
	if not OS.has_feature("mobile"):
		# Desktop trial of the touch layout: let the mouse stand in for a finger.
		Input.emulate_touch_from_mouse = true


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		# Android's back gesture pauses rather than quits.
		var ev := InputEventAction.new()
		ev.action = &"pause"
		ev.pressed = true
		Input.parse_input_event(ev)


## How many soldiers a mission should field, relative to the desktop count.
func crowd_scale() -> float:
	return 0.6 if mobile else 1.0


## True when the game was started by the automated capture or test harness.
func is_harness() -> bool:
	return args.has("shot") or args.has("autoplay") or DisplayServer.get_name() == "headless"


# --- input ---------------------------------------------------------------------

func _key(code: Key) -> InputEventKey:
	var e := InputEventKey.new()
	e.physical_keycode = code
	return e


func _mouse(button: MouseButton) -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = button
	return e


func _pad(button: JoyButton) -> InputEventJoypadButton:
	var e := InputEventJoypadButton.new()
	e.button_index = button
	return e


func _axis(axis: JoyAxis, value: float) -> InputEventJoypadMotion:
	var e := InputEventJoypadMotion.new()
	e.axis = axis
	e.axis_value = value
	return e


func _action(action: StringName, events: Array) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action, 0.3)
	for e: InputEvent in events:
		InputMap.action_add_event(action, e)


func _register_inputs() -> void:
	_action(&"move_forward", [_key(KEY_W), _key(KEY_UP), _axis(JOY_AXIS_LEFT_Y, -1.0)])
	_action(&"move_back", [_key(KEY_S), _key(KEY_DOWN), _axis(JOY_AXIS_LEFT_Y, 1.0)])
	_action(&"move_left", [_key(KEY_A), _key(KEY_LEFT), _axis(JOY_AXIS_LEFT_X, -1.0)])
	_action(&"move_right", [_key(KEY_D), _key(KEY_RIGHT), _axis(JOY_AXIS_LEFT_X, 1.0)])
	_action(&"look_left", [_axis(JOY_AXIS_RIGHT_X, -1.0)])
	_action(&"look_right", [_axis(JOY_AXIS_RIGHT_X, 1.0)])
	_action(&"look_up", [_axis(JOY_AXIS_RIGHT_Y, -1.0)])
	_action(&"look_down", [_axis(JOY_AXIS_RIGHT_Y, 1.0)])
	_action(&"jump", [_key(KEY_SPACE), _pad(JOY_BUTTON_A)])
	_action(&"sprint", [_key(KEY_SHIFT), _pad(JOY_BUTTON_LEFT_STICK)])
	_action(&"crouch", [_key(KEY_CTRL), _key(KEY_C), _pad(JOY_BUTTON_B)])
	_action(&"attack", [_mouse(MOUSE_BUTTON_LEFT), _axis(JOY_AXIS_TRIGGER_RIGHT, 1.0)])
	_action(&"block", [_mouse(MOUSE_BUTTON_RIGHT), _axis(JOY_AXIS_TRIGGER_LEFT, 1.0)])
	_action(&"throw", [_key(KEY_G), _mouse(MOUSE_BUTTON_MIDDLE), _pad(JOY_BUTTON_RIGHT_SHOULDER)])
	_action(&"interact", [_key(KEY_E), _pad(JOY_BUTTON_X)])
	_action(&"weapon_1", [_key(KEY_1)])
	_action(&"weapon_2", [_key(KEY_2)])
	_action(&"weapon_3", [_key(KEY_3)])
	_action(&"weapon_next", [_mouse(MOUSE_BUTTON_WHEEL_DOWN), _key(KEY_Q), _pad(JOY_BUTTON_Y)])
	_action(&"weapon_prev", [_mouse(MOUSE_BUTTON_WHEEL_UP)])
	_action(&"pause", [_key(KEY_ESCAPE), _pad(JOY_BUTTON_START)])
	_action(&"chronicle", [_key(KEY_TAB), _pad(JOY_BUTTON_BACK)])


# --- settings -------------------------------------------------------------------

func _load_settings() -> void:
	var cf := ConfigFile.new()
	if cf.load(SETTINGS_PATH) != OK:
		return
	for key: String in settings:
		settings[key] = cf.get_value("settings", key, settings[key])


## Writes the current settings to user://.
func save_settings() -> void:
	var cf := ConfigFile.new()
	for key: String in settings:
		cf.set_value("settings", key, settings[key])
	cf.save(SETTINGS_PATH)


## Applies settings to the window, audio and renderer, and notifies listeners.
func apply_settings() -> void:
	AudioServer.set_bus_volume_db(0, linear_to_db(clampf(float(settings["master_volume"]), 0.0001, 1.0)))
	if not is_harness() and not mobile:
		var mode := DisplayServer.WINDOW_MODE_FULLSCREEN if settings["fullscreen"] else DisplayServer.WINDOW_MODE_WINDOWED
		if DisplayServer.window_get_mode() != mode:
			DisplayServer.window_set_mode(mode)
	var q := clampi(int(settings["quality"]), 0, 2)
	var vp := get_viewport()
	if vp != null:
		if mobile:
			# On a phone the option trades sharpness for frame rate.
			vp.msaa_3d = Viewport.MSAA_DISABLED
			vp.scaling_3d_scale = [0.6, 0.75, 0.9][q]
			# Text sized for a desk is too small in the hand.
			get_tree().root.content_scale_factor = 1.3
		else:
			vp.msaa_3d = Viewport.MSAA_DISABLED if q == 0 else Viewport.MSAA_2X
			vp.scaling_3d_scale = 0.8 if q == 0 else 1.0
	if world != null and world.atmosphere != null:
		world.atmosphere.apply(world.preset, q, mobile)
	settings_changed.emit()


## Multiplier on damage the player takes, from the difficulty option.
func damage_taken_scale() -> float:
	return [0.55, 1.0, 1.5][clampi(int(settings.get("difficulty", 1)), 0, 2)]


# --- screens ---------------------------------------------------------------------

func _show_loading(text: String) -> void:
	if _loading == null:
		_loading = CanvasLayer.new()
		_loading.layer = 100
		var bg := ColorRect.new()
		bg.color = Color(0.03, 0.025, 0.02)
		bg.set_anchors_preset(Control.PRESET_FULL_RECT)
		_loading.add_child(bg)
		var label := Label.new()
		label.name = "Label"
		label.set_anchors_preset(Control.PRESET_FULL_RECT)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.add_theme_font_override("font", Ui.serif())
		label.add_theme_font_size_override("font_size", 30)
		label.add_theme_color_override("font_color", Ui.GOLD)
		_loading.add_child(label)
		add_child(_loading)
	(_loading.get_node("Label") as Label).text = text
	_loading.visible = true


func _hide_loading() -> void:
	if _loading != null:
		_loading.visible = false


## Returns the shared city, building it on first use, lit for [param preset].
func acquire_world(preset: String) -> TroyWorld:
	if world == null:
		world = TroyWorld.new()
		world.build(preset, int(settings["quality"]))
	else:
		if world.get_parent() != null:
			world.get_parent().remove_child(world)
		world.set_preset(preset, int(settings["quality"]))
	return world


func _swap(next: Node) -> void:
	get_tree().paused = false
	if world != null and world.get_parent() != null:
		world.get_parent().remove_child(world)
	if screen != null:
		screen.queue_free()
	screen = next
	main.add_child(next)


## Shows the main menu.
func start_menu() -> void:
	_show_loading("Sing, O goddess...")
	await get_tree().process_frame
	await get_tree().process_frame
	_swap((load("res://src/ui/main_menu.gd") as GDScript).new())
	_hide_loading()


## Starts a mission by id: "horse", "gate" or "roam".
func start_mission(id: String) -> void:
	if not MISSIONS.has(id):
		push_error("Game: unknown mission '%s'" % id)
		return
	_show_loading(str(Data.mission(id).get("loading", "Raising the walls of Ilios...")))
	await get_tree().process_frame
	await get_tree().process_frame
	var m: Node = (load(MISSIONS[id]) as GDScript).new()
	_swap(m)
	_hide_loading()


## Leaves the game.
func quit() -> void:
	save_settings()
	get_tree().quit()
