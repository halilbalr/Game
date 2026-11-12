class_name Ui
extends RefCounted
## Shared look for menus and HUD: bronze and gold on dark, serif capitals.

const GOLD := Color(0.86, 0.68, 0.36)
const BRONZE := Color(0.62, 0.42, 0.22)
const PALE := Color(0.93, 0.89, 0.80)
const DIM := Color(0.70, 0.66, 0.58)
const DARK := Color(0.045, 0.038, 0.03)
const BLOOD := Color(0.60, 0.07, 0.05)

static var _serif: SystemFont
static var _sans: SystemFont


## Display serif for titles and speech.
static func serif() -> Font:
	if _serif == null:
		_serif = SystemFont.new()
		_serif.font_names = PackedStringArray(["Cinzel", "Trajan Pro", "Palatino Linotype", "Book Antiqua",
			"Palatino", "Georgia", "DejaVu Serif", "Times New Roman", "serif"])
		_serif.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
	return _serif


## Plain face for small interface text.
static func sans() -> Font:
	if _sans == null:
		_sans = SystemFont.new()
		_sans.font_names = PackedStringArray(["Segoe UI", "Helvetica Neue", "Noto Sans", "DejaVu Sans", "Arial", "sans-serif"])
	return _sans


## A label in the house style.
static func label(text: String, size: int, color: Color = PALE, use_serif: bool = true) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", serif() if use_serif else sans())
	l.add_theme_font_size_override("font_size", size)
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
	b.add_theme_font_override("font", serif())
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
