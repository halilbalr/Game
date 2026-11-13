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
## Bumped when a default changes meaning, so an old saved value is not kept.
const SETTINGS_VERSION := 2
## The graphics option on phones, tablets and browsers, low to high. `scale`
## is the share of the screen's own pixels the 3D view is drawn at (the
## interface is always drawn at full sharpness); `detail` 1 turns on the bump
## pass and full noise in the procedural shaders; `shadow` is how far the sun
## casts, in metres; `lamps` how far a torch stays lit; `crowd` the share of
## the desktop head-count.
const LITE_TIERS := [
	{"scale": 0.5, "detail": 0.0, "shadow": 70.0, "splits": 2, "glow": false, "lamps": 60.0, "crowd": 0.6},
	{"scale": 0.67, "detail": 1.0, "shadow": 120.0, "splits": 2, "glow": true, "lamps": 80.0, "crowd": 0.75},
	{"scale": 0.85, "detail": 1.0, "shadow": 180.0, "splits": 4, "glow": true, "lamps": 110.0, "crowd": 0.9},
]
## True on phones and tablets (or with `--mobile` on a desktop, for testing):
## touch controls, lighter graphics, smaller crowds.
var mobile: bool = false
## True when running in a browser (or with `--web` on a desktop, for testing).
var web: bool = false
## True wherever the reduced graphics tier applies: phones, tablets, browsers.
var lite: bool = false
## True on a phone-sized screen (or with `--phone`): the interface is drawn
## larger still and the touch controls closer together.
var phone: bool = false
## Browser only: the page could not capture the pointer, so the view turns
## with the free cursor and at the screen edges instead.
var free_look: bool = false
var main: Node
var screen: Node
var world: TroyWorld
var _loading: CanvasLayer
## Share of the chosen 3D resolution in use: lowered when frames run slow.
var _res_scale: float = 1.0
var _fps_time: float = 0.0
var _fps_frames: int = 0
var _settle: float = 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for raw in OS.get_cmdline_user_args():
		var a := raw.trim_prefix("--")
		var eq := a.find("=")
		if eq >= 0:
			args[a.substr(0, eq)] = a.substr(eq + 1)
		else:
			args[a] = "1"
	web = OS.has_feature("web") or args.has("web")
	mobile = OS.has_feature("mobile") or args.has("mobile")
	if web and (OS.has_feature("web_android") or OS.has_feature("web_ios") \
			or (OS.has_feature("web_macos") and DisplayServer.is_touchscreen_available())):
		# A phone or tablet browser: an iPad reports itself as a Mac with a touch screen.
		mobile = true
	lite = mobile or web
	phone = args.has("phone") or (OS.has_feature("mobile") and _short_side_inches() < 3.7)
	_register_inputs()
	if web:
		_prepare_for_browser()
	if mobile:
		_prepare_for_touch()
	_load_settings()
	# Stock controls (drop-downs, switches) take their face and size from here.
	var theme := Theme.new()
	theme.default_font = Ui.sans()
	theme.default_font_size = Ui.fs(18)
	get_tree().root.theme = theme
	if args.has("quality"):
		settings["quality"] = int(args["quality"])
	apply_settings()


func _prepare_for_browser() -> void:
	# Ctrl+W closes a browser tab, so Ctrl must not be a game key: crouch is C.
	for ev in InputMap.action_get_events(&"crouch"):
		if ev is InputEventKey and (ev as InputEventKey).physical_keycode == KEY_CTRL:
			InputMap.action_erase_event(&"crouch", ev)
	# Tab can carry focus out of the page: R also opens the chronicle.
	InputMap.action_add_event(&"chronicle", _key(KEY_R))


func _prepare_for_touch() -> void:
	# Touches are also reported as left clicks; a look-drag must not strike.
	for action: StringName in [&"attack", &"block", &"throw", &"weapon_next", &"weapon_prev"]:
		for ev in InputMap.action_get_events(action):
			if ev is InputEventMouseButton:
				InputMap.action_erase_event(action, ev)
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


func _short_side_inches() -> float:
	var size := DisplayServer.screen_get_size()
	return minf(size.x, size.y) / maxf(float(DisplayServer.screen_get_dpi()), 1.0)


## The row of [constant LITE_TIERS] the graphics option selects.
func lite_tier() -> Dictionary:
	return LITE_TIERS[clampi(int(settings["quality"]), 0, 2)]


## How many soldiers a mission should field, relative to the desktop count.
func crowd_scale() -> float:
	return float(lite_tier()["crowd"]) if lite else 1.0


## Shader detail for the procedural materials (see [method Mats.set_detail]).
func detail() -> float:
	return float(lite_tier()["detail"]) if lite else 1.0


## How much larger than on a desk the whole interface is drawn.
func ui_scale() -> float:
	if phone:
		return 1.7
	return 1.3 if mobile else 1.0


## Extra enlargement of running text, on top of [method ui_scale].
func text_scale() -> float:
	return 1.25 if phone else 1.0


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
	# P as well as Esc: in a browser Esc belongs to the page (it frees the pointer).
	_action(&"pause", [_key(KEY_ESCAPE), _key(KEY_P), _pad(JOY_BUTTON_START)])
	_action(&"chronicle", [_key(KEY_TAB), _pad(JOY_BUTTON_BACK)])
	_action(&"skip", [_key(KEY_ENTER), _key(KEY_KP_ENTER), _pad(JOY_BUTTON_RIGHT_STICK)])


# --- settings -------------------------------------------------------------------

func _load_settings() -> void:
	var cf := ConfigFile.new()
	if cf.load(SETTINGS_PATH) != OK:
		return
	var current := int(cf.get_value("settings", "version", 1)) >= SETTINGS_VERSION
	for key: String in settings:
		if key == "quality" and lite and not current:
			# Saved when "Low" was the only tier a phone or browser was given.
			continue
		settings[key] = cf.get_value("settings", key, settings[key])


## Writes the current settings to user://.
func save_settings() -> void:
	var cf := ConfigFile.new()
	cf.set_value("settings", "version", SETTINGS_VERSION)
	for key: String in settings:
		cf.set_value("settings", key, settings[key])
	cf.save(SETTINGS_PATH)


## Applies settings to the window, audio and renderer, and notifies listeners.
func apply_settings() -> void:
	AudioServer.set_bus_volume_db(0, linear_to_db(clampf(float(settings["master_volume"]), 0.0001, 1.0)))
	if not is_harness() and not mobile and not web:
		var mode := DisplayServer.WINDOW_MODE_FULLSCREEN if settings["fullscreen"] else DisplayServer.WINDOW_MODE_WINDOWED
		if DisplayServer.window_get_mode() != mode:
			DisplayServer.window_set_mode(mode)
	var q := clampi(int(settings["quality"]), 0, 2)
	var vp := get_viewport()
	if vp != null:
		if lite:
			# On a phone or in a browser the option trades sharpness for frame rate.
			vp.msaa_3d = Viewport.MSAA_DISABLED
			vp.scaling_3d_scale = [0.6, 0.75, 0.9][q]
			if mobile:
				# Text sized for a desk is too small in the hand.
				get_tree().root.content_scale_factor = 1.3
		else:
			vp.msaa_3d = Viewport.MSAA_DISABLED if q == 0 else Viewport.MSAA_2X
			vp.scaling_3d_scale = 0.8 if q == 0 else 1.0
	if world != null and world.atmosphere != null:
		world.atmosphere.apply(world.preset, q, lite, lite_tier() if lite else {})
	settings_changed.emit()


func _process(delta: float) -> void:
	# Nobody can know in advance how fast a given phone or browser draws
	# this: watch the frame rate and trade 3D sharpness for it when needed.
	if not lite or is_harness() or args.has("noadapt") or get_tree().paused or delta > 0.25:
		return
	if _loading != null and _loading.visible:
		_settle = 3.0
	if _settle > 0.0:
		_settle -= delta
		_fps_time = 0.0
		_fps_frames = 0
		return
	_fps_time += delta
	_fps_frames += 1
	if _fps_time < 1.5:
		return
	var fps := _fps_frames / _fps_time
	_fps_time = 0.0
	_fps_frames = 0
	var next := _res_scale
	if fps < 26.0:
		next = maxf(_res_scale * 0.86, 0.5)
	elif fps > 52.0:
		next = minf(_res_scale * 1.08, 1.0)
	if not is_equal_approx(next, _res_scale):
		_res_scale = next
		get_viewport().scaling_3d_scale = float(lite_tier()["scale"]) * _res_scale


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
		label.add_theme_font_override("font", Ui.display())
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
	Sfx.hush_voice()
	_settle = 3.0
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


## Leaves the game. A browser page cannot close itself, so there it returns to the menu.
func quit() -> void:
	save_settings()
	if web:
		start_menu()
	else:
		get_tree().quit()
