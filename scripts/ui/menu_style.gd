class_name MenuStyle
extends RefCounted

## Общий вид меню (главное, пауза, настройки): тёмные панели, кроваво-красный акцент как в HUD
## (красный GAME OVER — Color(0.95, 0.15, 0.15)), чёрная обводка текста.

const ACCENT: Color = Color(0.95, 0.15, 0.15)
const ACCENT_DIM: Color = Color(0.45, 0.04, 0.04)
const BACKGROUND: Color = Color(0.03, 0.01, 0.01)
const PANEL: Color = Color(0.07, 0.02, 0.02, 0.92)
const TEXT: Color = Color(0.92, 0.88, 0.86)
const TEXT_DIM: Color = Color(0.6, 0.55, 0.53)

## Тема для корня меню: кнопки, ползунки, переключатели, подписи. Новая на каждый вызов — без static var
## (статический ресурс в классе держится до выхода и даёт утечки, см. lessons.md)
static func get_theme() -> Theme:
	var t := Theme.new()
	t.default_font_size = 22

	t.set_stylebox("normal", "Button", _box(Color(0.09, 0.03, 0.03, 0.95), ACCENT_DIM, 2))
	t.set_stylebox("hover", "Button", _box(Color(0.3, 0.03, 0.03, 0.95), ACCENT, 2))
	t.set_stylebox("pressed", "Button", _box(Color(0.5, 0.05, 0.05, 0.95), ACCENT, 2))
	t.set_stylebox("focus", "Button", _box(Color(0, 0, 0, 0), ACCENT, 2))
	t.set_stylebox("disabled", "Button", _box(Color(0.05, 0.03, 0.03, 0.8), Color(0.2, 0.08, 0.08), 2))
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_pressed_color", "Button", Color.WHITE)
	t.set_color("font_focus_color", "Button", Color.WHITE)
	t.set_color("font_outline_color", "Button", Color.BLACK)
	t.set_constant("outline_size", "Button", 3)

	t.set_color("font_color", "Label", TEXT)
	t.set_color("font_outline_color", "Label", Color.BLACK)
	t.set_constant("outline_size", "Label", 3)

	var track := _box(Color(0.12, 0.04, 0.04), ACCENT_DIM, 1)
	track.content_margin_top = 4.0
	track.content_margin_bottom = 4.0
	t.set_stylebox("slider", "HSlider", track)
	var fill := _box(ACCENT_DIM, ACCENT_DIM, 0)
	fill.content_margin_top = 4.0
	fill.content_margin_bottom = 4.0
	t.set_stylebox("grabber_area", "HSlider", fill)
	var fill_hl := _box(ACCENT, ACCENT, 0)
	fill_hl.content_margin_top = 4.0
	fill_hl.content_margin_bottom = 4.0
	t.set_stylebox("grabber_area_highlight", "HSlider", fill_hl)

	t.set_color("font_color", "CheckButton", TEXT)
	t.set_color("font_hover_color", "CheckButton", Color.WHITE)
	t.set_color("font_pressed_color", "CheckButton", TEXT)
	t.set_color("font_hover_pressed_color", "CheckButton", Color.WHITE)
	t.set_color("font_focus_color", "CheckButton", Color.WHITE)
	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		t.set_stylebox(state, "CheckButton", StyleBoxEmpty.new())
	t.set_stylebox("focus", "CheckButton", _box(Color(0, 0, 0, 0), ACCENT, 1))

	return t

## Кнопка меню: фиксированная ширина, по центру колонки
static func make_button(text: String, width: float = 320.0) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(width, 52)
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	return b

## Заголовок экрана меню
static func make_title(text: String, font_size: int = 56) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", ACCENT)
	l.add_theme_constant_override("outline_size", 6)
	return l

## Тёмная подложка панели меню с красной рамкой
static func make_panel_style() -> StyleBoxFlat:
	var s := _box(PANEL, ACCENT_DIM, 2)
	s.content_margin_left = 36.0
	s.content_margin_right = 36.0
	s.content_margin_top = 28.0
	s.content_margin_bottom = 28.0
	return s

static func _box(bg: Color, border: Color, border_width: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(border_width)
	s.content_margin_left = 16.0
	s.content_margin_right = 16.0
	s.content_margin_top = 8.0
	s.content_margin_bottom = 8.0
	return s
