class_name Ui
extends RefCounted
## Shared look for menus and HUD: bronze and gold on dark, inscriptional
## capitals over a book serif. Both faces ship with the game (assets/fonts).

const GOLD := Color(0.86, 0.68, 0.36)
const BRONZE := Color(0.62, 0.42, 0.22)
const PALE := Color(0.93, 0.89, 0.80)
const DIM := Color(0.70, 0.66, 0.58)
const DARK := Color(0.045, 0.038, 0.03)
const BLOOD := Color(0.60, 0.07, 0.05)

const CINZEL := "res://assets/fonts/cinzel.woff2"
const CRIMSON := "res://assets/fonts/crimson-pro.woff2"

static var _display: Font
static var _serif: Font
static var _sans: Font


static func _face(path: String, weight: int, fallback: PackedStringArray) -> Font:
	var system := SystemFont.new()
	system.font_names = fallback
	system.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
	if not ResourceLoader.exists(path):
		return system
	var fv := FontVariation.new()
	fv.base_font = load(path)
	fv.variation_opentype = {"wght": weight}
	fv.fallbacks = [system]
	return fv


## Inscriptional capitals for titles, buttons and names (Cinzel).
static func display() -> Font:
	if _display == null:
		_display = _face(CINZEL, 600, PackedStringArray(["Trajan Pro", "Palatino Linotype", "Georgia", "DejaVu Serif", "serif"]))
	return _display


## Book serif for speech and running text (Crimson Pro).
static func serif() -> Font:
	if _serif == null:
		_serif = _face(CRIMSON, 500, PackedStringArray(["Palatino Linotype", "Book Antiqua", "Palatino", "Georgia",
			"DejaVu Serif", "Times New Roman", "serif"]))
	return _serif


## The same serif a little heavier, for small interface text: it stays
## legible at sizes where a thin sans would not.
static func sans() -> Font:
	if _sans == null:
		_sans = _face(CRIMSON, 600, PackedStringArray(["Segoe UI", "Helvetica Neue", "Noto Sans", "DejaVu Sans", "Arial", "sans-serif"]))
	return _sans


## Font size for the device in hand: running text is set larger on a phone.
static func fs(size: int) -> int:
	return roundi(size * Game.text_scale()) if size < 40 else size


## A label in the house style.
static func label(text: String, size: int, color: Color = PALE, use_serif: bool = true) -> Label:
	var l := Label.new()
	l.text = text
	# Large serif text is a heading: set it in the display capitals.
	l.add_theme_font_override("font", (display() if size >= 28 else serif()) if use_serif else sans())
	l.add_theme_font_size_override("font_size", fs(size))
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("shadow_offset_x", 1)
	l.add_theme_constant_override("shadow_offset_y", 2)
	l.add_theme_constant_override("shadow_outline_size", 4)
	return l


static func _box(bg: Color, border: Color, width: int = 1) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(width)
	sb.set_content_margin_all(12)
	sb.content_margin_left = 22
	sb.content_margin_right = 22
	return sb


## A menu button in the house style.
static func button(text: String, size: int = 24) -> Button:
	var b := Button.new()
	b.text = text
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.add_theme_font_override("font", display())
	b.add_theme_font_size_override("font_size", size)
	b.add_theme_color_override("font_color", PALE)
	b.add_theme_color_override("font_hover_color", GOLD)
	b.add_theme_color_override("font_focus_color", GOLD)
	b.add_theme_color_override("font_pressed_color", Color.WHITE)
	b.add_theme_stylebox_override("normal", _box(Color(0.05, 0.04, 0.03, 0.55), Color(0.62, 0.42, 0.22, 0.35)))
	b.add_theme_stylebox_override("hover", _box(Color(0.12, 0.085, 0.05, 0.85), GOLD))
	b.add_theme_stylebox_override("focus", _box(Color(0.12, 0.085, 0.05, 0.85), GOLD))
	b.add_theme_stylebox_override("pressed", _box(Color(0.2, 0.13, 0.07, 0.95), GOLD, 2))
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	return b


## A dark translucent panel.
static func panel() -> PanelContainer:
	var p := PanelContainer.new()
	var sb := _box(Color(0.04, 0.033, 0.026, 0.9), Color(0.62, 0.42, 0.22, 0.6))
	sb.set_content_margin_all(28)
	p.add_theme_stylebox_override("panel", sb)
	return p
