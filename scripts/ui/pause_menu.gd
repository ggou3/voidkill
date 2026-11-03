class_name PauseMenu
extends CanvasLayer

## Меню паузы (Esc): «Продолжить», «Настройки», «Перезапуск уровня», «Главное меню». Создаёт HUD.
## Открывается только во время игры (GameManager.State.PLAYING) — не на экранах смерти и конца уровня.
## Пауза — GameManager.set_paused: дерево на паузе, курсор свободен; само меню работает с PROCESS_MODE_ALWAYS.
## Потеря фокуса окна (Alt+Tab) во время игры тоже открывает паузу.

const LAYER: int = 50 # поверх HUD и его экранов

var _root: Control = null
var _main_page: Control = null
var _settings_page: Control = null
var _settings_menu: SettingsMenu = null
var _resume_button: Button = null

func _ready() -> void:
	layer = LAYER
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root = Control.new()
	_root.name = "PauseRoot"
	_root.theme = MenuStyle.get_theme()
	add_child(_root)
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.65)
	_root.add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var center := CenterContainer.new()
	_root.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var column := VBoxContainer.new()
	center.add_child(column)

	_main_page = _make_panel()
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	_main_page.add_child(box)
	box.add_child(MenuStyle.make_title("ПАУЗА", 56))
	_resume_button = _add_button(box, "ПРОДОЛЖИТЬ", resume)
	_add_button(box, "НАСТРОЙКИ", _show_settings.bind(true))
	_add_button(box, "ПЕРЕЗАПУСК УРОВНЯ", GameManager.restart_level)
	_add_button(box, "ГЛАВНОЕ МЕНЮ", GameManager.go_to_main_menu)
	column.add_child(_main_page)

	_settings_page = _make_panel()
	_settings_menu = SettingsMenu.new()
	_settings_menu.back_requested.connect(_show_settings.bind(false))
	_settings_page.add_child(_settings_menu)
	column.add_child(_settings_page)

	_root.visible = false
	GameManager.pause_changed.connect(_on_pause_changed)

func _input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel") or event.is_echo():
		return
	if _root.visible:
		get_viewport().set_input_as_handled()
		if _settings_page.visible:
			_settings_menu.request_back()
		else:
			resume()
	elif GameManager.current_state == GameManager.State.PLAYING:
		get_viewport().set_input_as_handled()
		open()

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and is_inside_tree() and not _root.visible \
			and GameManager.current_state == GameManager.State.PLAYING:
		open()

func open() -> void:
	GameManager.set_paused(true)

func resume() -> void:
	GameManager.set_paused(false)

## Показ меню — по сигналу GameManager: пауза снимается и при перезапуске/выходе в меню
func _on_pause_changed(is_paused: bool) -> void:
	_root.visible = is_paused
	if is_paused:
		_show_settings(false)

func _show_settings(show_settings: bool) -> void:
	_main_page.visible = not show_settings
	_settings_page.visible = show_settings
	if show_settings:
		_settings_menu.focus_first()
	else:
		_resume_button.grab_focus()

func _add_button(parent: Control, text: String, action: Callable) -> Button:
	var b := MenuStyle.make_button(text)
	b.pressed.connect(action)
	parent.add_child(b)
	return b

func _make_panel() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", MenuStyle.make_panel_style())
	return panel
