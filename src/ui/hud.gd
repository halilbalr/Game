class_name Hud
extends CanvasLayer
## In-mission interface: health and stamina, objective and its marker,
## speech, prompts, the watchman's-eye meter, title cards and fades.

var player: Player
var battle: Battlefield
var _root: Control
var _bars: Control
var _objective: Label
var _objective_sub: Label
var _speaker: Label
var _speech: Label
var _prompt: Label
var _weapon: Label
var _toast: Label
var _title: Label
var _subtitle: Label
var _fade: ColorRect
var _vignette: ColorRect
var _vignette_mat: ShaderMaterial
var _overlay: Control
var _boss: Soldier
var _marker: Variant = null
var _marker_label: String = ""
var _hurt: float = 0.0
var _speech_until: float = 0.0
var _toast_until: float = 0.0
var _detection: float = 0.0
var _alarm: float = -1.0
var _alarm_total: float = 1.0
var _stealth_visible: bool = false

const VIGNETTE := "
shader_type canvas_item;
uniform float amount = 0.0;
uniform float low_health = 0.0;
void fragment() {
	vec2 p = UV - vec2(0.5);
	float d = length(p * vec2(1.0, 0.8));
	float edge = smoothstep(0.28, 0.72, d);
	float pulse = 0.85 + 0.15 * sin(TIME * 5.0);
	float a = edge * (amount + low_health * pulse * 0.55);
	COLOR = vec4(0.45, 0.01, 0.01, clamp(a, 0.0, 0.85));
}
"


func _init() -> void:
	layer = 10
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	_vignette = ColorRect.new()
	_vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vignette_mat = ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = VIGNETTE
	_vignette_mat.shader = sh
	_vignette.material = _vignette_mat
	_root.add_child(_vignette)

	_bars = Control.new()
	_bars.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bars.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bars.draw.connect(_draw_bars)
	_root.add_child(_bars)

	_objective = Ui.label("", 24, Ui.PALE)
	_objective.position = Vector2(48, 40)
	_objective.size = Vector2(900, 34)
	_root.add_child(_objective)
	_objective_sub = Ui.label("", 17, Ui.DIM, false)
	_objective_sub.position = Vector2(50, 76)
	_objective_sub.size = Vector2(900, 26)
	_root.add_child(_objective_sub)

	_speaker = Ui.label("", 22, Ui.GOLD)
	_speaker.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_speaker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_speaker.position = Vector2(-700, -238)
	_speaker.size = Vector2(1400, 30)
	_root.add_child(_speaker)
	_speech = Ui.label("", 27, Ui.PALE)
	_speech.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_speech.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_speech.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_speech.position = Vector2(-640, -204)
	_speech.size = Vector2(1280, 110)
	_root.add_child(_speech)

	_prompt = Ui.label("", 22, Ui.PALE, false)
	_prompt.set_anchors_preset(Control.PRESET_CENTER)
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.position = Vector2(-400, 70)
	_prompt.size = Vector2(800, 30)
	_root.add_child(_prompt)

	_weapon = Ui.label("", 20, Ui.DIM)
	_weapon.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_weapon.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_weapon.position = Vector2(-560, -84)
	_weapon.size = Vector2(512, 30)
	_root.add_child(_weapon)

	_toast = Ui.label("", 19, Ui.GOLD, false)
	_toast.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.position = Vector2(-500, 150)
	_toast.size = Vector2(1000, 28)
	_root.add_child(_toast)

	_fade = ColorRect.new()
	_fade.color = Color(0, 0, 0, 0)
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_fade)

	_title = Ui.label("", 68, Ui.GOLD)
	_title.set_anchors_preset(Control.PRESET_CENTER)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.position = Vector2(-900, -110)
	_title.size = Vector2(1800, 90)
	_title.modulate.a = 0.0
	_root.add_child(_title)
	_subtitle = Ui.label("", 26, Ui.PALE)
	_subtitle.set_anchors_preset(Control.PRESET_CENTER)
	_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_subtitle.position = Vector2(-620, -4)
	_subtitle.size = Vector2(1240, 220)
	_subtitle.modulate.a = 0.0
	_root.add_child(_subtitle)


## Connects the HUD to the player and the battle it reports on.
func bind(p: Player, b: Battlefield) -> void:
	player = p
	battle = b
	player.damaged.connect(func(amount: float, blocked: bool) -> void:
		_hurt = clampf(_hurt + (0.12 if blocked else 0.25 + amount / 60.0), 0.0, 1.0))
	player.weapon_changed.connect(func(_id: String) -> void: _refresh_weapon())
	_refresh_weapon()


func _refresh_weapon() -> void:
	var id := player.current_weapon()
	var w: Dictionary = Data.weapons.get(id, {})
	var text := str(w.get("name", ""))
	if id != "" and w.has("greek"):
		text += "  ·  " + str(w["greek"])
	if "spear" in player.weapons:
		text += "     spears %d" % player.spears
	_weapon.text = text


## Sets the objective line. [param marker] is a Vector3, a Node3D, or null.
func set_objective(text: String, marker: Variant = null, sub: String = "") -> void:
	if text != _objective.text and text != "":
		Sfx.play(&"objective", -8.0)
	_objective.text = ("◆  " + text) if text != "" else ""
	_objective_sub.text = sub
	_marker = marker
	_marker_label = ""


## Shows a line of speech for [param seconds].
func say(speaker: String, text: String, seconds: float) -> void:
	_speaker.text = speaker.to_upper()
	_speech.text = text
	_speech_until = Time.get_ticks_msec() * 0.001 + seconds


## Clears any speech on screen.
func hush() -> void:
	_speech_until = 0.0


## A brief notice at the top of the screen.
func toast(text: String, seconds: float = 2.5) -> void:
	_toast.text = text
	_toast_until = Time.get_ticks_msec() * 0.001 + seconds


## Shows or hides the watchman's-eye meter.
func set_stealth(visible_now: bool, detection: float = 0.0, alarm_left: float = -1.0, alarm_total: float = 1.0) -> void:
	_stealth_visible = visible_now
	_detection = detection
	_alarm = alarm_left
	_alarm_total = alarm_total


## Names a great enemy at the top of the screen (null to clear).
func set_boss(s: Soldier) -> void:
	_boss = s


## Fades the screen to black ([param alpha] 1) or back (0).
func fade(alpha: float, seconds: float) -> void:
	var tw := create_tween()
	tw.tween_property(_fade, "color:a", alpha, seconds)
	await tw.finished


## Sets the fade level at once.
func set_fade(alpha: float) -> void:
	_fade.color.a = alpha


## Shows a title and a few lines beneath it, then lets them fade.
func title_card(title: String, text: String, seconds: float) -> void:
	_title.text = title
	_subtitle.text = text
	var tw := create_tween()
	tw.tween_property(_title, "modulate:a", 1.0, 1.2)
	tw.parallel().tween_property(_subtitle, "modulate:a", 1.0, 1.8)
	tw.tween_interval(seconds)
	tw.tween_property(_title, "modulate:a", 0.0, 1.2)
	tw.parallel().tween_property(_subtitle, "modulate:a", 0.0, 1.2)
	await tw.finished


## Shows the end-of-mission panel. [param buttons] maps label -> Callable.
func show_end(title: String, text: String, buttons: Dictionary, success: bool) -> void:
	if _overlay != null:
		_overlay.queue_free()
	_overlay = Control.new()
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(_overlay)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.72)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(dim)
	var centre := CenterContainer.new()
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(centre)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 22)
	box.custom_minimum_size = Vector2(900, 0)
	centre.add_child(box)
	var t := Ui.label(title, 54, Ui.GOLD if success else Ui.BLOOD.lightened(0.25))
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(t)
	var body := Ui.label(text, 24, Ui.PALE)
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.custom_minimum_size = Vector2(900, 0)
	box.add_child(body)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 20)
	box.add_child(row)
	var first: Button = null
	for label: String in buttons:
		var btn := Ui.button(label, 24)
		btn.alignment = HORIZONTAL_ALIGNMENT_CENTER
		btn.custom_minimum_size = Vector2(260, 0)
		btn.pressed.connect(buttons[label])
		row.add_child(btn)
		if first == null:
			first = btn
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if first != null:
		first.grab_focus()


func _process(delta: float) -> void:
	var now := Time.get_ticks_msec() * 0.001
	var speaking := now < _speech_until
	_speaker.visible = speaking
	_speech.visible = speaking
	_toast.visible = now < _toast_until
	_hurt = maxf(_hurt - delta * 0.9, 0.0)
	if player != null:
		_vignette_mat.set_shader_parameter("amount", _hurt)
		var frac := player.health / maxf(player.max_health, 1.0)
		_vignette_mat.set_shader_parameter("low_health", clampf((0.4 - frac) / 0.4, 0.0, 1.0) if player.is_alive() else 1.0)
		var focus := player.focus
		if focus != null and player.control_enabled:
			var key := "E"
			_prompt.text = ("Hold [%s]  %s" if focus.hold_seconds > 0.0 else "[%s]  %s") % [key, focus.prompt]
		else:
			_prompt.text = ""
	_bars.queue_redraw()


func _draw_bars() -> void:
	if player == null:
		return
	var vp := _bars.size
	var hidden := not player.control_enabled and not player.is_alive()
	if not hidden:
		# Health and stamina, bottom left.
		var x := 48.0
		var y := vp.y - 78.0
		var w := 300.0
		_bars.draw_rect(Rect2(x - 2, y - 2, w + 4, 16), Color(0, 0, 0, 0.55))
		_bars.draw_rect(Rect2(x, y, w * clampf(player.health / player.max_health, 0.0, 1.0), 12), Color(0.62, 0.10, 0.07))
		_bars.draw_rect(Rect2(x - 2, y - 2, w + 4, 16), Ui.BRONZE, false, 1.5)
		_bars.draw_rect(Rect2(x - 2, y + 20, w * 0.8 + 4, 9), Color(0, 0, 0, 0.5))
		_bars.draw_rect(Rect2(x, y + 22, w * 0.8 * clampf(player.stamina / player.max_stamina, 0.0, 1.0), 5), Ui.GOLD)
		# Aim point.
		var c := vp * 0.5
		_bars.draw_circle(c, 2.6, Color(0, 0, 0, 0.5))
		_bars.draw_circle(c, 1.6, Color(1, 1, 1, 0.85))
		# Hold-to-use ring.
		if player.hold_progress > 0.0:
			_bars.draw_arc(c, 22.0, -PI * 0.5, -PI * 0.5 + TAU * player.hold_progress, 40, Ui.GOLD, 4.0, true)
	# Objective marker.
	var target := Vector3.INF
	if _marker is Vector3:
		target = _marker
	elif _marker is Node3D and is_instance_valid(_marker):
		target = (_marker as Node3D).global_position + Vector3(0, 2.2, 0)
	if target != Vector3.INF and player.camera != null and player.is_alive():
		var cam := player.camera
		var dist := cam.global_position.distance_to(target)
		var behind := cam.is_position_behind(target)
		var sp := cam.unproject_position(target)
		var margin := 60.0
		if behind:
			sp = vp - sp
			sp.y = vp.y - margin
		sp.x = clampf(sp.x, margin, vp.x - margin)
		sp.y = clampf(sp.y, margin + 60.0, vp.y - margin)
		var pts := PackedVector2Array([sp + Vector2(0, -9), sp + Vector2(8, 0), sp + Vector2(0, 9), sp + Vector2(-8, 0)])
		_bars.draw_colored_polygon(pts, Color(0.86, 0.68, 0.36, 0.9))
		_bars.draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2], pts[3], pts[0]]), Color(0, 0, 0, 0.7), 1.5)
		_bars.draw_string(Ui.sans(), sp + Vector2(-40, 30), "%d m" % int(dist), HORIZONTAL_ALIGNMENT_CENTER, 80, 16,
			Color(0.93, 0.89, 0.80, 0.9))
	# Watchman's eye.
	if _stealth_visible and player.is_alive():
		var c := Vector2(vp.x * 0.5, 64.0)
		var open := clampf(_detection, 0.0, 1.0)
		var col := Ui.PALE.lerp(Ui.BLOOD.lightened(0.3), open)
		var pts := PackedVector2Array()
		for i in 25:
			var t := i / 24.0
			pts.append(c + Vector2(lerpf(-34.0, 34.0, t), -sin(t * PI) * (4.0 + 12.0 * open)))
		for i in 25:
			var t := 1.0 - i / 24.0
			pts.append(c + Vector2(lerpf(-34.0, 34.0, t), sin(t * PI) * (4.0 + 12.0 * open)))
		_bars.draw_polyline(pts, col, 2.0, true)
		_bars.draw_circle(c, 2.0 + 5.0 * open, col)
		var word := "UNSEEN"
		if _alarm >= 0.0:
			word = "SILENCE HIM"
		elif open > 0.45:
			word = "SUSPECTED"
		_bars.draw_string(Ui.serif(), c + Vector2(-100, 42), word, HORIZONTAL_ALIGNMENT_CENTER, 200, 16, col)
		if _alarm >= 0.0:
			var bw := 220.0
			_bars.draw_rect(Rect2(c.x - bw * 0.5, c.y + 52, bw, 6), Color(0, 0, 0, 0.6))
			_bars.draw_rect(Rect2(c.x - bw * 0.5, c.y + 52, bw * clampf(_alarm / _alarm_total, 0.0, 1.0), 6), Ui.BLOOD.lightened(0.2))
	# A great enemy's name and strength.
	if _boss != null and is_instance_valid(_boss) and _boss.is_alive():
		var bw := 520.0
		var bx := vp.x * 0.5 - bw * 0.5
		var by := 112.0 if _stealth_visible else 54.0
		_bars.draw_string(Ui.serif(), Vector2(bx, by - 8), _boss.display_name.to_upper(), HORIZONTAL_ALIGNMENT_CENTER, bw, 22, Ui.GOLD)
		_bars.draw_rect(Rect2(bx - 2, by, bw + 4, 12), Color(0, 0, 0, 0.6))
		_bars.draw_rect(Rect2(bx, by + 2, bw * clampf(_boss.health / _boss.max_health, 0.0, 1.0), 8), Color(0.62, 0.10, 0.07))
		_bars.draw_rect(Rect2(bx - 2, by, bw + 4, 12), Ui.BRONZE, false, 1.5)
