class_name PauseMenu
extends CanvasLayer
## Pause screen: resume, options, controls, restart and leave.

var mission: Mission
var _root: Control
var _options: Control
var _main_box: Control


func _init() -> void:
	layer = 50
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.visible = false
	add_child(_root)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.7)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)
	var centre := CenterContainer.new()
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(centre)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 40)
	centre.add_child(row)

	var panel := Ui.panel()
	row.add_child(panel)
	_main_box = VBoxContainer.new()
	_main_box.add_theme_constant_override("separation", 12)
	_main_box.custom_minimum_size = Vector2(380, 0)
	panel.add_child(_main_box)
	_main_box.add_child(Ui.label("PAUSED", 40, Ui.GOLD))
	_add_button("Resume", _resume)
	_add_button("Restart mission", func() -> void:
		get_tree().paused = false
		mission.retry())
	_add_button("Main menu", func() -> void:
		get_tree().paused = false
		Game.start_menu())
	if not Game.web:
		_add_button("Quit", Game.quit)

	var side := Ui.panel()
	row.add_child(side)
	var sbox := VBoxContainer.new()
	sbox.add_theme_constant_override("separation", 10)
	sbox.custom_minimum_size = Vector2(520, 0)
	if Game.phone:
		# Taller than a phone screen: scroll it.
		var scroll := ScrollContainer.new()
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		scroll.custom_minimum_size = Vector2(640, 500)
		side.add_child(scroll)
		sbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		scroll.add_child(sbox)
	else:
		side.add_child(sbox)
	sbox.add_child(Ui.label("OPTIONS", 26, Ui.GOLD))
	_options = OptionsPanel.new()
	sbox.add_child(_options)
	sbox.add_child(Ui.label("CONTROLS", 26, Ui.GOLD))
	var controls := Ui.label(OptionsPanel.controls_text(), 17, Ui.DIM, false)
	sbox.add_child(controls)


func _add_button(text: String, action: Callable) -> void:
	var b := Ui.button(text)
	b.pressed.connect(action)
	_main_box.add_child(b)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"pause") and mission != null and not mission.ended:
		if _root.visible:
			_resume()
		else:
			open()
		get_viewport().set_input_as_handled()


## Pauses the game and shows the menu.
func open() -> void:
	_root.visible = true
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	(_main_box.get_child(1) as Button).grab_focus()


func _resume() -> void:
	_root.visible = false
	get_tree().paused = false
	Game.save_settings()
	if not Game.mobile and not Game.free_look:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
