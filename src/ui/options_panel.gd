class_name OptionsPanel
extends VBoxContainer
## The options shared by the main menu and the pause screen.

const CONTROLS_TEXT := "Move  W A S D        Look  Mouse\nStrike  Left mouse        Shield  Right mouse (hold)\nThrow spear  G or middle mouse\nWeapons  1 2 3 or wheel        Use  E\nRun  Shift        Crouch  Ctrl or C        Jump  Space\nChronicle  Tab        Pause  Esc\nA gamepad also works."


func _init() -> void:
	add_theme_constant_override("separation", 8)
	_slider("Mouse sensitivity", "mouse_sensitivity", 0.3, 2.5, 0.05)
	_slider("Field of view", "fov", 60.0, 100.0, 1.0)
	_slider("Volume", "master_volume", 0.0, 1.0, 0.05)
	_choice("Graphics", "quality", ["Low", "Medium", "High"])
	_toggle("Blood", "blood")
	_toggle("Invert look", "invert_y")
	_toggle("Head bob", "head_bob")
	_toggle("Fullscreen", "fullscreen")


func _row(text: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	var l := Ui.label(text, 19, Ui.PALE, false)
	l.custom_minimum_size = Vector2(220, 0)
	row.add_child(l)
	add_child(row)
	return row


func _slider(text: String, key: String, lo: float, hi: float, step: float) -> void:
	var row := _row(text)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = float(Game.settings[key])
	s.custom_minimum_size = Vector2(240, 24)
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.value_changed.connect(func(v: float) -> void:
		Game.settings[key] = v
		Game.apply_settings())
	row.add_child(s)


func _toggle(text: String, key: String) -> void:
	var row := _row(text)
	var c := CheckButton.new()
	c.button_pressed = bool(Game.settings[key])
	c.toggled.connect(func(on: bool) -> void:
		Game.settings[key] = on
		Game.apply_settings())
	row.add_child(c)


func _choice(text: String, key: String, names: Array) -> void:
	var row := _row(text)
	var o := OptionButton.new()
	for n: String in names:
		o.add_item(n)
	o.selected = clampi(int(Game.settings[key]), 0, names.size() - 1)
	o.custom_minimum_size = Vector2(200, 0)
	o.item_selected.connect(func(i: int) -> void:
		Game.settings[key] = i
		Game.apply_settings())
	row.add_child(o)
