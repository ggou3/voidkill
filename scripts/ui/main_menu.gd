class_name MainMenu
extends Control

## Главное меню (главная сцена scenes/main_menu.tscn): «Играть» (выбор уровня), «Настройки», «Выход».
## Интерфейс строится кодом, как HUD. Страницы — панели в центре экрана, видна одна; Esc — назад.
## Список уровней — LevelCatalog.LEVELS, запуск — GameManager.start_level.

var _main_page: Control = null
var _levels_page: Control = null
var _settings_page: Control = null
var _settings_menu: SettingsMenu = null
var _play_button: Button = null
var _first_level_button: Button = null
var _title: Label = null

func _ready() -> void:
	theme = MenuStyle.get_theme()
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_build_background()

	var center := CenterContainer.new()
	add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 36)
	center.add_child(column)
	_title = MenuStyle.make_title("VOIDKILL", 110)
	column.add_child(_title)

	_main_page = _build_main_page()
	_levels_page = _build_levels_page()
	_settings_page = _make_panel()
	_settings_menu = SettingsMenu.new()
	_settings_menu.back_requested.connect(_show_page.bind(&"main"))
	_settings_page.add_child(_settings_menu)
	for page in [_main_page, _levels_page, _settings_page]:
		page.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		column.add_child(page)
	_show_page(&"main")

func _input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel") or event.is_echo():
		return
	if _settings_page.visible:
		get_viewport().set_input_as_handled()
		_settings_menu.request_back()
	elif _levels_page.visible:
		get_viewport().set_input_as_handled()
		_show_page(&"main")

## Тёмный фон с кроваво-красным свечением из центра
func _build_background() -> void:
	var bg := ColorRect.new()
	bg.color = MenuStyle.BACKGROUND
	add_child(bg)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var gradient := Gradient.new()
	gradient.set_color(0, Color(0.35, 0.02, 0.02, 0.55))
	gradient.set_color(1, Color(0.0, 0.0, 0.0, 0.0))
	var tex := GradientTexture2D.new()
	tex.gradient = gradient
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	var glow := TextureRect.new()
	glow.texture = tex
	glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	glow.stretch_mode = TextureRect.STRETCH_SCALE
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(glow)
	glow.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

func _build_main_page() -> Control:
	var panel := _make_panel()
	var box := _make_column(panel)
	_play_button = MenuStyle.make_button("ИГРАТЬ")
	_play_button.pressed.connect(_show_page.bind(&"levels"))
	box.add_child(_play_button)
	var settings_button := MenuStyle.make_button("НАСТРОЙКИ")
	settings_button.pressed.connect(_show_page.bind(&"settings"))
	box.add_child(settings_button)
	var quit_button := MenuStyle.make_button("ВЫХОД")
	quit_button.pressed.connect(get_tree().quit)
	box.add_child(quit_button)
	return panel

func _build_levels_page() -> Control:
	var panel := _make_panel()
	var box := _make_column(panel)
	box.add_child(MenuStyle.make_title("ВЫБОР УРОВНЯ", 44))
	for entry in LevelCatalog.LEVELS:
		var button := MenuStyle.make_button(entry["title"], 420.0)
		button.tooltip_text = entry.get("description", "")
		button.pressed.connect(GameManager.start_level.bind(entry["scene"]))
		box.add_child(button)
		if _first_level_button == null:
			_first_level_button = button
		var description := Label.new()
		description.text = entry.get("description", "")
		description.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		description.add_theme_font_size_override("font_size", 15)
		description.add_theme_color_override("font_color", MenuStyle.TEXT_DIM)
		box.add_child(description)
	var back := MenuStyle.make_button("НАЗАД", 260.0)
	back.pressed.connect(_show_page.bind(&"main"))
	box.add_child(back)
	return panel

func _show_page(page: StringName) -> void:
	_main_page.visible = page == &"main"
	_levels_page.visible = page == &"levels"
	_settings_page.visible = page == &"settings"
	# Подстраницы со своим заголовком — без большого логотипа, иначе не влезают в 648 px высоты
	_title.visible = page == &"main"
	match page:
		&"main":
			_play_button.grab_focus()
		&"levels":
			if _first_level_button:
				_first_level_button.grab_focus()
		&"settings":
			_settings_menu.focus_first()

func _make_panel() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", MenuStyle.make_panel_style())
	return panel

func _make_column(parent: Control) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	parent.add_child(box)
	return box
