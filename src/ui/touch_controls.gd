class_name TouchControls
extends CanvasLayer
## On-screen controls for phones and tablets: a thumb-stick that appears
## under the left thumb, drag-to-look on the right, and buttons for the
## fighting hand. Feeds the same input actions the keyboard does, so the
## player code does not know the difference.

const STICK_RADIUS := 105.0
const LOOK_SPEED := 0.0042
const BUTTONS := {
	# id: [offset from bottom-right corner, radius, label, action, kind]
	"strike": [Vector2(-180, -200), 84.0, "STRIKE", &"attack", "tap"],
	"shield": [Vector2(-385, -135), 64.0, "SHIELD", &"block", "hold"],
	"throw": [Vector2(-135, -400), 52.0, "THROW", &"throw", "tap"],
	"jump": [Vector2(-345, -325), 48.0, "JUMP", &"jump", "tap"],
	"crouch": [Vector2(-555, -95), 48.0, "CROUCH", &"crouch", "toggle"],
	"weapon": [Vector2(-560, -265), 44.0, "ARMS", &"weapon_next", "tap"],
	"use": [Vector2(-150, -575), 58.0, "USE", &"interact", "hold"],
}

var player: Player
var mission: Mission
## Shows the chronicle button (Walk the City).
var chronicle_enabled: bool = false
var _canvas: Control
var _stick_id: int = -1
var _stick_origin := Vector2.ZERO
var _stick_vec := Vector2.ZERO
var _look_ids: Dictionary = {}
var _button_ids: Dictionary = {}
var _crouched: bool = false
var _inset: float = 0.0


func _init() -> void:
	layer = 20
	_canvas = Control.new()
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.draw.connect(_draw_controls)
	add_child(_canvas)


func _ready() -> void:
	# Keep clear of a notch or rounded corner.
	var safe := DisplayServer.get_display_safe_area()
	var win := DisplayServer.window_get_size()
	if win.x > 0 and safe.size.x > 0:
		var px := maxf(float(safe.position.x), float(win.x - safe.end.x))
		_inset = px * _size().x / float(win.x)


func _size() -> Vector2:
	return _canvas.get_viewport_rect().size


func _usable() -> bool:
	return player != null and player.is_alive() and not get_tree().paused and (mission == null or not mission.ended)


func _button_centre(id: String) -> Vector2:
	var s := _size()
	return Vector2(s.x - _inset, s.y) + (BUTTONS[id][0] as Vector2)


func _small_buttons() -> Dictionary:
	# Top-right corner: pause, and the chronicle scroll when walking the city.
	var s := _size()
	var out := {"pause": Vector2(s.x - 64.0 - _inset, 62.0)}
	if chronicle_enabled:
		out["chronicle"] = Vector2(s.x - 160.0 - _inset, 62.0)
	return out


func _button_shown(id: String) -> bool:
	match id:
		"use":
			return player.focus != null
		"strike", "shield", "throw", "weapon":
			if not player.combat_enabled:
				return false
			if id == "throw":
				return player.current_weapon() == "spear" and player.spears > 0
			if id == "shield":
				return player.viewmodel.has_shield()
			return true
		"jump", "crouch":
			return player.move_enabled
	return true


func _hit_button(pos: Vector2) -> String:
	for id: String in BUTTONS:
		if _button_shown(id) and pos.distance_to(_button_centre(id)) <= (BUTTONS[id][1] as float) * 1.12:
			return id
	var small := _small_buttons()
	for id: String in small:
		if pos.distance_to(small[id]) <= 46.0:
			return id
	return ""


func _tap(action: StringName) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = true
	Input.parse_input_event(ev)
	var up := InputEventAction.new()
	up.action = action
	up.pressed = false
	Input.parse_input_event.call_deferred(up)


func _press_button(id: String, index: int) -> void:
	if id == "pause" or id == "chronicle":
		_tap(StringName(id))
		return
	var action: StringName = BUTTONS[id][3]
	match str(BUTTONS[id][4]):
		"tap":
			_tap(action)
			# A thumb resting on Strike or Throw can still turn the view.
			_look_ids[index] = true
		"hold":
			Input.action_press(action)
			_button_ids[index] = id
			if id == "shield":
				_look_ids[index] = true
		"toggle":
			_crouched = not _crouched
			if _crouched:
				Input.action_press(action)
			else:
				Input.action_release(action)


func _release_all() -> void:
	for action: StringName in [&"move_forward", &"move_back", &"move_left", &"move_right", &"sprint", &"block", &"interact"]:
		Input.action_release(action)
	if _crouched:
		Input.action_release(&"crouch")
		_crouched = false
	_stick_id = -1
	_stick_vec = Vector2.ZERO
	_look_ids.clear()
	_button_ids.clear()


func _apply_stick() -> void:
	var v := _stick_vec
	var dead := 0.14
	for pair: Array in [[&"move_right", v.x], [&"move_left", -v.x], [&"move_back", v.y], [&"move_forward", -v.y]]:
		var strength: float = pair[1]
		if strength > dead:
			Input.action_press(pair[0], clampf(strength, 0.0, 1.0))
		else:
			Input.action_release(pair[0])
	# Pushing the stick to its rim is a run.
	if v.length() > 0.93 and v.y < -0.5:
		Input.action_press(&"sprint")
	else:
		Input.action_release(&"sprint")


func _input(event: InputEvent) -> void:
	if not (event is InputEventScreenTouch or event is InputEventScreenDrag):
		return
	if not _usable():
		if _stick_id != -1 or not _button_ids.is_empty():
			_release_all()
		return
	var s := _size()
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed:
			var id := _hit_button(touch.position)
			if id != "":
				_press_button(id, touch.index)
			elif touch.position.x < s.x * 0.42 and touch.position.y > s.y * 0.2 and _stick_id == -1:
				_stick_id = touch.index
				_stick_origin = touch.position
				_stick_vec = Vector2.ZERO
			else:
				_look_ids[touch.index] = true
		else:
			if touch.index == _stick_id:
				_stick_id = -1
				_stick_vec = Vector2.ZERO
				_apply_stick()
			if _button_ids.has(touch.index):
				Input.action_release(BUTTONS[_button_ids[touch.index]][3])
				_button_ids.erase(touch.index)
			_look_ids.erase(touch.index)
	else:
		var drag := event as InputEventScreenDrag
		if drag.index == _stick_id:
			_stick_vec = ((drag.position - _stick_origin) / STICK_RADIUS).limit_length(1.0)
			_apply_stick()
		elif _look_ids.has(drag.index) and player.control_enabled:
			var sens := LOOK_SPEED * float(Game.settings.get("mouse_sensitivity", 1.0))
			var invert := -1.0 if Game.settings.get("invert_y", false) else 1.0
			player.add_look(-drag.relative.x * sens, -drag.relative.y * sens * invert)


func _process(_delta: float) -> void:
	var show := _usable()
	if _canvas.visible != show:
		_canvas.visible = show
		if not show:
			_release_all()
	if show:
		_canvas.queue_redraw()


func _ring(centre: Vector2, radius: float, fill: Color, edge: Color, label: String, size: int = 15) -> void:
	_canvas.draw_circle(centre, radius, fill)
	_canvas.draw_arc(centre, radius, 0.0, TAU, 40, edge, 2.5, true)
	if label != "":
		_canvas.draw_string(Ui.sans(), centre + Vector2(-radius, size * 0.38), label, HORIZONTAL_ALIGNMENT_CENTER,
			radius * 2.0, size, Color(1, 1, 1, 0.9))


func _draw_controls() -> void:
	if player == null:
		return
	var s := _size()
	var fill := Color(0.05, 0.04, 0.03, 0.34)
	var edge := Color(0.86, 0.68, 0.36, 0.7)
	# Thumb-stick.
	if player.move_enabled:
		var origin := _stick_origin if _stick_id != -1 else Vector2(190.0 + _inset, s.y - 190.0)
		_canvas.draw_circle(origin, STICK_RADIUS, Color(0.05, 0.04, 0.03, 0.22 if _stick_id == -1 else 0.34))
		_canvas.draw_arc(origin, STICK_RADIUS, 0.0, TAU, 48, Color(0.86, 0.68, 0.36, 0.35 if _stick_id == -1 else 0.7), 2.5, true)
		_canvas.draw_circle(origin + _stick_vec * STICK_RADIUS, 44.0, Color(0.86, 0.68, 0.36, 0.3 if _stick_id == -1 else 0.6))
	for id: String in BUTTONS:
		if not _button_shown(id):
			continue
		var held := id in _button_ids.values() or (id == "crouch" and _crouched)
		var f := Color(0.86, 0.68, 0.36, 0.45) if held else fill
		var e := edge
		if id == "use":
			# The one button that only appears when it matters: make it loud.
			f = Color(0.86, 0.68, 0.36, 0.55)
			e = Color(1.0, 0.9, 0.6, 0.95)
			if player.hold_progress > 0.0:
				_canvas.draw_arc(_button_centre(id), (BUTTONS[id][1] as float) + 9.0, -PI * 0.5,
					-PI * 0.5 + TAU * player.hold_progress, 40, Color(1, 1, 1, 0.9), 5.0, true)
		_ring(_button_centre(id), BUTTONS[id][1], f, e, BUTTONS[id][2], 17 if id == "strike" else 14)
	var small := _small_buttons()
	_ring(small["pause"], 34.0, fill, edge, "II", 20)
	if small.has("chronicle"):
		_ring(small["chronicle"], 34.0, fill, edge, "READ", 12)
