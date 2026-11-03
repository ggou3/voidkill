class_name SettingsMenu
extends VBoxContainer

## Экран настроек — общий для главного меню и паузы. Значения меняются сразу (Settings.set_value),
## в файл пишутся при выходе с экрана (request_back: кнопка «Назад» или Esc у владельца).

signal back_requested

var _back_button: Button = null

func _ready() -> void:
	add_theme_constant_override("separation", 18)
	add_child(MenuStyle.make_title("НАСТРОЙКИ", 44))

	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 20)
	grid.add_theme_constant_override("v_separation", 14)
	add_child(grid)

	_add_volume_row(grid, "Общая громкость", &"master_volume")
	_add_volume_row(grid, "Музыка", &"music_volume")
	_add_volume_row(grid, "Эффекты", &"sfx_volume")
	_add_slider_row(grid, "Чувствительность мыши", &"mouse_sensitivity",
		Settings.MOUSE_SENSITIVITY_MIN, Settings.MOUSE_SENSITIVITY_MAX, 0.05, 1.0, "×%.2f")
	_add_toggle_row(grid, "Полный экран", &"fullscreen")
	_add_toggle_row(grid, "Вертикальная синхронизация", &"vsync")

	_back_button = MenuStyle.make_button("НАЗАД", 260.0)
	_back_button.pressed.connect(request_back)
	add_child(_back_button)

## Первый элемент для фокуса клавиатурой
func focus_first() -> void:
	var grid: GridContainer = get_child(1)
	for child in grid.get_children():
		if child is Range or child is BaseButton:
			child.grab_focus()
			return

func request_back() -> void:
	Settings.save()
	back_requested.emit()

func _add_volume_row(grid: GridContainer, title: String, key: StringName) -> void:
	_add_slider_row(grid, title, key, 0.0, 100.0, 1.0, 100.0, "%d%%")

## Ползунок: в интерфейсе значение настройки × ui_scale (громкость 0..1 показывается как 0..100%)
func _add_slider_row(grid: GridContainer, title: String, key: StringName, min_value: float, max_value: float,
		step: float, ui_scale: float, value_format: String) -> void:
	var is_integer: bool = value_format.contains("%d")
	grid.add_child(_make_row_label(title))
	var slider := HSlider.new()
	slider.min_value = min_value
	slider.max_value = max_value
	slider.step = step
	slider.custom_minimum_size = Vector2(300, 28)
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.value = float(Settings.get(key)) * ui_scale
	grid.add_child(slider)
	var value_label := Label.new()
	value_label.custom_minimum_size = Vector2(70, 0)
	value_label.add_theme_color_override("font_color", MenuStyle.TEXT_DIM)
	grid.add_child(value_label)
	var update := func(v: float) -> void:
		if is_integer:
			value_label.text = value_format % int(round(v))
		else:
			value_label.text = value_format % v
	update.call(slider.value)
	slider.value_changed.connect(func(v: float) -> void:
		update.call(v)
		Settings.set_value(key, v / ui_scale)
	)

func _add_toggle_row(grid: GridContainer, title: String, key: StringName) -> void:
	grid.add_child(_make_row_label(title))
	var toggle := CheckButton.new()
	toggle.button_pressed = bool(Settings.get(key))
	toggle.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	toggle.toggled.connect(func(on: bool) -> void: Settings.set_value(key, on))
	grid.add_child(toggle)
	grid.add_child(Control.new())

func _make_row_label(title: String) -> Label:
	var label := Label.new()
	label.text = title
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return label
