extends Node

## Настройки игрока (Autoload singleton): громкость шин, чувствительность мыши, режим окна, VSync.
## Хранятся в user://settings.cfg (ConfigFile), загружаются и применяются при старте игры.
## Меню настроек меняет поля через set_value() — значение применяется сразу; save() — при выходе из меню.

signal changed(key: StringName)

const PATH: String = "user://settings.cfg"
const SECTION_AUDIO: String = "audio"
const SECTION_CONTROLS: String = "controls"
const SECTION_VIDEO: String = "video"

## Громкость шин 0..1 (переводится в дБ через linear_to_db)
var master_volume: float = 1.0
var music_volume: float = 0.7
var sfx_volume: float = 1.0
## Множитель к Head.MOUSE_SENSITIVITY (1.0 — прежняя чувствительность)
var mouse_sensitivity: float = 1.0
const MOUSE_SENSITIVITY_MIN: float = 0.1
const MOUSE_SENSITIVITY_MAX: float = 3.0
var fullscreen: bool = false
var vsync: bool = true

# Поле → секция файла
const _KEYS: Dictionary = {
	&"master_volume": SECTION_AUDIO,
	&"music_volume": SECTION_AUDIO,
	&"sfx_volume": SECTION_AUDIO,
	&"mouse_sensitivity": SECTION_CONTROLS,
	&"fullscreen": SECTION_VIDEO,
	&"vsync": SECTION_VIDEO,
}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	load_settings()
	apply_all()

func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	for key in _KEYS:
		var value = cfg.get_value(_KEYS[key], String(key), get(key))
		# Чужой тип в файле (правка руками) — оставляем значение по умолчанию
		if typeof(value) == typeof(get(key)) or (typeof(value) == TYPE_INT and typeof(get(key)) == TYPE_FLOAT):
			set(key, value)
	master_volume = clampf(master_volume, 0.0, 1.0)
	music_volume = clampf(music_volume, 0.0, 1.0)
	sfx_volume = clampf(sfx_volume, 0.0, 1.0)
	mouse_sensitivity = clampf(mouse_sensitivity, MOUSE_SENSITIVITY_MIN, MOUSE_SENSITIVITY_MAX)

func save() -> void:
	var cfg := ConfigFile.new()
	for key in _KEYS:
		cfg.set_value(_KEYS[key], String(key), get(key))
	var err: Error = cfg.save(PATH)
	if err != OK:
		push_warning("[Settings] Failed to save %s: %s" % [PATH, error_string(err)])

## Изменить настройку и сразу применить её
func set_value(key: StringName, value) -> void:
	if not _KEYS.has(key):
		push_warning("[Settings] Unknown setting '%s'" % key)
		return
	set(key, value)
	_apply(key)
	changed.emit(key)

func apply_all() -> void:
	for key in _KEYS:
		_apply(key)

func _apply(key: StringName) -> void:
	match key:
		&"master_volume":
			_set_bus_volume(&"Master", master_volume)
		&"music_volume":
			_set_bus_volume(&"Music", music_volume)
		&"sfx_volume":
			_set_bus_volume(&"SFX", sfx_volume)
		&"fullscreen":
			var mode: DisplayServer.WindowMode = DisplayServer.window_get_mode()
			var is_full: bool = mode == DisplayServer.WINDOW_MODE_FULLSCREEN or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN
			if fullscreen and not is_full:
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
			elif not fullscreen and is_full:
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		&"vsync":
			DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED)

func _set_bus_volume(bus_name: StringName, linear: float) -> void:
	var idx: int = AudioServer.get_bus_index(bus_name)
	if idx < 0:
		push_warning("[Settings] Audio bus '%s' not found (default_bus_layout.tres)" % bus_name)
		return
	AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(linear, 0.0001)))
	AudioServer.set_bus_mute(idx, linear <= 0.0)
