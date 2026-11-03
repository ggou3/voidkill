class_name WeaponCard
extends Control

## Карточка оружия в руке (правый нижний угол HUD): силуэт ствола, название, патроны и индикатор готовности
## ПКМ. Остальные стволы не показываются. Силуэты нарисованы векторно в коде (полигоны в долях рамки
## SILHOUETTE_RECT), отдельно для каждого класса оружия. При смене оружия карточка вздрагивает и вспыхивает.
## Готовность ПКМ — WeaponBase.get_alt_charge() / is_alt_available().
## Данные читает сама из WeaponManager и BPMSystem каждый кадр.

const CARD_SIZE: Vector2 = Vector2(290.0, 96.0)
const SILHOUETTE_RECT: Rect2 = Rect2(14.0, 12.0, 112.0, 56.0)
const TEXT_X: float = 136.0
const ALT_BAR: Rect2 = Rect2(46.0, 81.0, 150.0, 5.0)
const RELOAD_BAR: Rect2 = Rect2(TEXT_X, 66.0, 140.0, 3.0)
const COLOR_ACCENT: Color = Color(0.95, 0.72, 0.2)
const COLOR_ALT: Color = Color(0.25, 0.8, 1.0)
const COLOR_INF: Color = Color(1.0, 0.2, 0.2)
const COLOR_DIM: Color = Color(0.55, 0.57, 0.6)
const SWITCH_TIME: float = 0.25

var weapon_manager: WeaponManager = null
var bpm_system: BPMSystem = null

var _name_label: Label
var _ammo_label: Label
var _alt_caption: Label
var _alt_status: Label
var _panel_style: StyleBoxFlat
var _weapon: WeaponBase = null
var _alt_charge: float = 1.0
var _alt_available: bool = true
var _reload_progress: float = -1.0
var _infinite: bool = false
var _switch_t: float = 0.0
var _last_index: int = -1

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size = CARD_SIZE
	_panel_style = StyleBoxFlat.new()
	_panel_style.bg_color = Color(0.06, 0.07, 0.09, 0.78)
	_panel_style.border_color = Color(COLOR_ACCENT, 0.9)
	_panel_style.set_border_width_all(1)
	_panel_style.border_width_left = 4
	_panel_style.set_corner_radius_all(4)
	_name_label = _make_label(14, Vector2(TEXT_X, 8.0))
	_name_label.add_theme_color_override("font_color", Color(1.0, 0.88, 0.35))
	_ammo_label = _make_label(30, Vector2(TEXT_X, 24.0))
	_alt_caption = _make_label(12, Vector2(14.0, 75.0))
	_alt_caption.text = "ПКМ"
	_alt_status = _make_label(12, Vector2(ALT_BAR.end.x + 8.0, 75.0))

func _make_label(font_size: int, pos: Vector2) -> Label:
	var label: Label = Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.position = pos
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.8))
	label.add_theme_constant_override("outline_size", 4)
	add_child(label)
	return label

func _process(delta: float) -> void:
	if not is_instance_valid(weapon_manager) or weapon_manager.weapons.is_empty():
		visible = false
		return
	var index: int = clampi(weapon_manager.current_weapon_index, 0, weapon_manager.weapons.size() - 1)
	var w: WeaponBase = weapon_manager.weapons[index]
	if not w or not w.data:
		visible = false
		return
	visible = true
	if index != _last_index:
		if _last_index >= 0:
			_switch_t = SWITCH_TIME
		_last_index = index
	_switch_t = maxf(_switch_t - delta, 0.0)
	_weapon = w
	_infinite = bpm_system.has_infinite_ammo() if is_instance_valid(bpm_system) else false
	_update_ammo(w, index)
	_update_alt(w)
	# Смена оружия: карточка вздрагивает (растёт от правого нижнего угла) и вспыхивает
	var k: float = _switch_t / SWITCH_TIME
	pivot_offset = size
	scale = Vector2.ONE * (1.0 + k * k * 0.08)
	modulate = Color(1.0 + k * 0.6, 1.0 + k * 0.4, 1.0 + k * 0.2, 1.0 - k * 0.4)
	queue_redraw()

func _update_ammo(w: WeaponBase, index: int) -> void:
	_name_label.text = w.data.name
	var ammo: int = weapon_manager.ammos[index] if index < weapon_manager.ammos.size() else 0
	_reload_progress = -1.0
	if weapon_manager.is_reloading:
		_reload_progress = clampf((w.data.reload_time - weapon_manager.active_reload_timer) / maxf(0.001, w.data.reload_time), 0.0, 1.0)
		_ammo_label.text = "RELOAD %d%%" % int(_reload_progress * 100.0)
		_ammo_label.add_theme_color_override("font_color", Color(1.0, 0.6, 0.1))
	elif weapon_manager.is_bursting:
		_ammo_label.text = "%d / %d" % [ammo, w.data.max_ammo]
		_ammo_label.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3))
	elif _infinite:
		_ammo_label.text = "∞"
		_ammo_label.add_theme_color_override("font_color", COLOR_INF)
	else:
		_ammo_label.text = "%d / %d" % [ammo, w.data.max_ammo]
		_ammo_label.add_theme_color_override("font_color", Color.WHITE if ammo > 0 else COLOR_INF)

func _update_alt(w: WeaponBase) -> void:
	_alt_available = w.is_alt_available()
	_alt_charge = w.get_alt_charge() if _alt_available else 0.0
	if not _alt_available:
		_alt_status.text = "OVERDRIVE"
		_alt_status.add_theme_color_override("font_color", COLOR_DIM)
	elif _alt_charge < 1.0:
		_alt_status.text = "%d%%" % int(_alt_charge * 100.0)
		_alt_status.add_theme_color_override("font_color", Color(COLOR_ALT, 0.8))
	else:
		# Готов; у Швейной — сколько игл вернёт «Стежок» (суффикс «(STITCH N)»)
		var suffix: String = w.get_alt_hud_suffix(_infinite).strip_edges()
		_alt_status.text = suffix.trim_prefix("(").trim_suffix(")") if suffix.begins_with("(") else "ГОТОВ"
		_alt_status.add_theme_color_override("font_color", COLOR_ALT)
	_alt_caption.add_theme_color_override("font_color", COLOR_ALT if _alt_available else COLOR_DIM)

func _draw() -> void:
	draw_style_box(_panel_style, Rect2(Vector2.ZERO, size))
	if _weapon:
		_draw_silhouette(_weapon)
	# ПКМ: полоска готовности
	draw_rect(ALT_BAR, Color(0.1, 0.12, 0.14, 0.9))
	if _alt_available and _alt_charge > 0.0:
		var bar: Rect2 = Rect2(ALT_BAR.position, Vector2(ALT_BAR.size.x * _alt_charge, ALT_BAR.size.y))
		draw_rect(bar, COLOR_ALT if _alt_charge >= 1.0 else Color(COLOR_ALT, 0.6))
	# Перезарядка основного огня
	if _reload_progress >= 0.0:
		draw_rect(RELOAD_BAR, Color(0.1, 0.12, 0.14, 0.9))
		draw_rect(Rect2(RELOAD_BAR.position, Vector2(RELOAD_BAR.size.x * _reload_progress, RELOAD_BAR.size.y)), Color(0.95, 0.65, 0.15))

# --- Силуэты ---

## Точка силуэта: координаты в долях ширины рамки (x 0..1, y 0..0.5)
func _sp(x: float, y: float) -> Vector2:
	return SILHOUETTE_RECT.position + Vector2(x, y) * SILHOUETTE_RECT.size.x

func _poly(points: Array) -> void:
	var pts: PackedVector2Array = PackedVector2Array()
	for p in points:
		pts.append(_sp(p.x, p.y))
	draw_colored_polygon(pts, _fill_color())
	pts.append(pts[0])
	draw_polyline(pts, _outline_color(), 1.4, true)

func _rect(x0: float, y0: float, x1: float, y1: float) -> void:
	_poly([Vector2(x0, y0), Vector2(x1, y0), Vector2(x1, y1), Vector2(x0, y1)])

func _circle(cx: float, cy: float, r: float, filled: bool = true) -> void:
	var c: Vector2 = _sp(cx, cy)
	var rr: float = r * SILHOUETTE_RECT.size.x
	if filled:
		draw_circle(c, rr, _fill_color())
	draw_arc(c, rr, 0.0, TAU, 24, _outline_color(), 1.4, true)

func _line(x0: float, y0: float, x1: float, y1: float, width: float = 1.4) -> void:
	draw_line(_sp(x0, y0), _sp(x1, y1), _outline_color(), width, true)

func _fill_color() -> Color:
	return Color(0.13, 0.13, 0.15, 0.95)

func _outline_color() -> Color:
	return COLOR_INF.lerp(Color.WHITE, 0.35) if _infinite else Color(0.88, 0.88, 0.9, 0.95)

func _draw_silhouette(w: WeaponBase) -> void:
	if w is WeaponCaliber:
		_draw_caliber()
	elif w is WeaponAnvil:
		_draw_anvil()
	elif w is WeaponInjector:
		_draw_injector()
	elif w is WeaponSewing:
		_draw_sewing()

## Калибр-0 — тяжёлый револьвер с направляющей рейлгана над стволом
func _draw_caliber() -> void:
	_poly([Vector2(0.26, 0.26), Vector2(0.37, 0.27), Vector2(0.31, 0.48), Vector2(0.18, 0.48), Vector2(0.16, 0.43)])
	_poly([Vector2(0.21, 0.08), Vector2(0.27, 0.05), Vector2(0.31, 0.11), Vector2(0.26, 0.13)])
	_rect(0.44, 0.13, 0.98, 0.22)
	_rect(0.47, 0.085, 0.95, 0.13)
	_poly([Vector2(0.27, 0.09), Vector2(0.47, 0.09), Vector2(0.47, 0.27), Vector2(0.41, 0.3), Vector2(0.27, 0.3)])
	_circle(0.37, 0.19, 0.075)
	for i in range(3):
		var y: float = 0.15 + 0.04 * float(i)
		_line(0.32, y, 0.42, y, 1.0)
	draw_arc(_sp(0.39, 0.32), 0.045 * SILHOUETTE_RECT.size.x, 0.0, PI, 12, _outline_color(), 1.4, true)
	for i in range(6):
		var x: float = 0.52 + 0.075 * float(i)
		_line(x, 0.085, x, 0.13, 1.0)

## Кровавая Наковальня — поршневой дробовик с головкой-наковальней
func _draw_anvil() -> void:
	_poly([Vector2(0.0, 0.12), Vector2(0.14, 0.13), Vector2(0.14, 0.22), Vector2(0.03, 0.31)])
	_rect(0.11, 0.15, 0.24, 0.19)
	_poly([Vector2(0.3, 0.22), Vector2(0.4, 0.22), Vector2(0.36, 0.45), Vector2(0.26, 0.45)])
	_rect(0.22, 0.11, 0.57, 0.23)
	_line(0.3, 0.11, 0.3, 0.23, 1.0)
	_line(0.4, 0.11, 0.4, 0.23, 1.0)
	_poly([Vector2(0.62, 0.25), Vector2(0.7, 0.25), Vector2(0.68, 0.4), Vector2(0.62, 0.4)])
	_poly([Vector2(0.5, 0.06), Vector2(0.83, 0.06), Vector2(1.0, 0.095), Vector2(0.83, 0.15), Vector2(0.8, 0.26), Vector2(0.58, 0.26), Vector2(0.56, 0.15), Vector2(0.5, 0.13)])
	_line(0.58, 0.2, 0.8, 0.2, 1.0)

## Инъектор — шприц-пистолет: колба с кровью, игла, поршень
func _draw_injector() -> void:
	_poly([Vector2(0.36, 0.24), Vector2(0.46, 0.24), Vector2(0.42, 0.46), Vector2(0.32, 0.46)])
	_rect(0.1, 0.14, 0.3, 0.18)
	_rect(0.07, 0.05, 0.11, 0.27)
	_rect(0.27, 0.03, 0.31, 0.29)
	_rect(0.31, 0.07, 0.72, 0.25)
	draw_rect(Rect2(_sp(0.43, 0.1), _sp(0.7, 0.22) - _sp(0.43, 0.1)), Color(0.75, 0.05, 0.08, 0.85))
	for i in range(6):
		var x: float = 0.36 + 0.06 * float(i)
		_line(x, 0.07, x, 0.11 if i % 2 == 0 else 0.095, 1.0)
	_rect(0.72, 0.11, 0.78, 0.21)
	_line(0.78, 0.16, 1.0, 0.16, 1.6)

## Швейная машина — рукав, головка с иглой, маховик и станина
func _draw_sewing() -> void:
	_poly([Vector2(0.4, 0.38), Vector2(0.5, 0.38), Vector2(0.46, 0.48), Vector2(0.36, 0.48)])
	_rect(0.06, 0.3, 0.94, 0.38)
	_rect(0.12, 0.06, 0.26, 0.3)
	_rect(0.12, 0.04, 0.84, 0.14)
	_rect(0.74, 0.03, 0.89, 0.22)
	_line(0.8, 0.22, 0.8, 0.31, 1.6)
	_circle(0.08, 0.12, 0.075)
	for i in range(3):
		var a: float = TAU * float(i) / 3.0
		_line(0.08, 0.12, 0.08 + cos(a) * 0.065, 0.12 + sin(a) * 0.065, 1.0)
