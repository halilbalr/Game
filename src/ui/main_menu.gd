extends Node3D
## Title screen: the city at evening behind the choice of side.

var _cam: Camera3D
var _t: float = 0.0
var _options: Control


func _ready() -> void:
	var world := Game.acquire_world("evening")
	add_child(world)
	_cam = Camera3D.new()
	_cam.far = 9000.0
	_cam.fov = 52.0
	add_child(_cam)
	_cam.make_current()
	_place_camera()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Sfx.preload_loops([&"theme"], [])
	Sfx.music(&"theme")
	Sfx.ambience(&"")

	var layer := CanvasLayer.new()
	add_child(layer)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(root)
	# Shade the left third so the text reads against the sky.
	var shade := ColorRect.new()
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	var sm := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = "shader_type canvas_item;\nvoid fragment() {\n\tfloat a = smoothstep(0.62, 0.0, UV.x) * 0.82 + smoothstep(0.7, 1.0, UV.y) * 0.5;\n\tCOLOR = vec4(0.02, 0.016, 0.012, clamp(a, 0.0, 0.9));\n}\n"
	sm.shader = sh
	shade.material = sm
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(shade)

	var col := VBoxContainer.new()
	col.position = Vector2(110, 60 if Game.mobile else 110)
	col.custom_minimum_size = Vector2(640, 0)
	col.add_theme_constant_override("separation", 10)
	if Game.phone:
		# A phone held sideways is a short screen: draw the menu tighter.
		col.position = Vector2(64, 14)
		col.add_theme_constant_override("separation", 3)
	root.add_child(col)
	var title := Ui.label("THE ODYSSEY", 72 if Game.phone else 92, Ui.GOLD)
	col.add_child(title)
	var sub := Ui.label("THE FALL OF TROY", 30, Ui.PALE)
	col.add_child(sub)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, (4 if Game.phone else 14) if Game.mobile else 34)
	col.add_child(gap)

	var first := _entry(col, "THE WOODEN HORSE", "Attacker  ·  Odysseus  ·  the last night of Troy", func() -> void: Game.start_mission("horse"))
	_entry(col, "THE SCAEAN GATE", "Defender  ·  Hector  ·  the day Patroclus came to the wall", func() -> void: Game.start_mission("gate"))
	_entry(col, "WALK THE CITY", "Troy by daylight, with a chronicle of what is known", func() -> void: Game.start_mission("roam"))
	_entry(col, "OPTIONS", "", func() -> void: _options.visible = not _options.visible)
	if not Game.web:
		_entry(col, "QUIT", "", Game.quit)
	first.grab_focus()

	var quote := Ui.label("\"Tell me, O Muse, of that ingenious hero who travelled far and wide\nafter he had sacked the famous town of Troy.\"\nHomer, Odyssey 1.1, tr. Samuel Butler", 20, Ui.DIM)
	if Game.mobile:
		# A phone screen is too short for the quotation under the menu: set it bottom right.
		quote.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
		quote.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		quote.position = Vector2(-760, -130)
		quote.size = Vector2(700, 100)
		if Game.phone:
			quote.text = "\"Tell me, O Muse, of that ingenious hero\nwho travelled far and wide after he had\nsacked the famous town of Troy.\"\nHomer, Odyssey 1.1, tr. Samuel Butler"
			quote.position = Vector2(-600, -150)
			quote.size = Vector2(560, 130)
	else:
		quote.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
		quote.position = Vector2(112, -150)
	root.add_child(quote)

	var panel := Ui.panel()
	var pbox := VBoxContainer.new()
	pbox.add_theme_constant_override("separation", 10)
	var done := Ui.button("Done", 20)
	done.pressed.connect(func() -> void:
		panel.visible = false
		Game.save_settings())
	if Game.mobile:
		# Taller than a phone screen: the panel fills the right side and scrolls.
		panel.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
		panel.offset_left = -720.0
		panel.offset_right = -24.0
		panel.offset_top = 16.0
		panel.offset_bottom = -16.0
		var scroll := ScrollContainer.new()
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		panel.add_child(scroll)
		pbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		scroll.add_child(pbox)
		pbox.add_child(done)
	else:
		panel.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
		panel.position = Vector2(-700, -330)
		panel.custom_minimum_size = Vector2(600, 0)
		panel.add_child(pbox)
	root.add_child(panel)
	pbox.add_child(Ui.label("OPTIONS", 28, Ui.GOLD))
	pbox.add_child(OptionsPanel.new())
	pbox.add_child(Ui.label("CONTROLS", 28, Ui.GOLD))
	pbox.add_child(Ui.label(OptionsPanel.controls_text(), 17, Ui.DIM, false))
	if not Game.mobile:
		pbox.add_child(done)
	panel.visible = false
	_options = panel


func _entry(parent: Control, text: String, note: String, action: Callable) -> Button:
	var b := Ui.button(text, 30)
	b.pressed.connect(action)
	parent.add_child(b)
	if note != "":
		var n := Ui.label("      " + note, 18, Ui.DIM, false)
		parent.add_child(n)
	return b


func _place_camera() -> void:
	var a := 2.35 + _t * 0.012
	var centre := Vector3(-30.0, 10.0, 70.0)
	_cam.position = centre + Vector3(cos(a) * 230.0, 34.0 + sin(_t * 0.05) * 5.0, sin(a) * 230.0)
	_cam.look_at(centre + Vector3(30.0, -2.0, -40.0), Vector3.UP)


func _process(delta: float) -> void:
	_t += delta
	_place_camera()
