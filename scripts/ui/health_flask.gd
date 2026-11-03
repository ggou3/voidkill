class_name HealthFlask
extends Control

## Резервуар HP (левый нижний угол HUD): стеклянная колба с кровью в металлической обойме
## (shaders/health_flask.gdshader), справа — число HP. Уровень крови — доля HP, плавно догоняет её.
## Кровь плещется по инерции: поверхность наклоняется от ускорения вбок (стрейф, рывок, подкат) и поворота
## камеры, волны поднимают прыжки, приземления и резкие разгоны вперёд. Попадание бьёт по стеклу —
## трещина в случайной точке (до 4, новые вытесняют старые), вспышка и всплеск; трещины гаснут при лечении.
## На критическом HP (порог Player.low_health_threshold) кровь кипит и мигает аварийный диод.

const SHADER: Shader = preload("res://shaders/health_flask.gdshader")

const TANK_SIZE: Vector2 = Vector2(54.0, 120.0)
const PANEL_SIZE: Vector2 = Vector2(150.0, 120.0)
const FILL_RATE: float = 6.0 # 1/с — уровень догоняет HP
# Наклон поверхности — пружина: сила от ускорения вбок и рыскания камеры
const TILT_ACCEL: float = 0.018 # наклон на м/с² ускорения вбок
const TILT_LOOK: float = 0.06 # наклон на рад/с поворота камеры
const TILT_STIFFNESS: float = 60.0
const TILT_DAMPING: float = 5.0
const TILT_MAX: float = 0.6
const ACCEL_MAX: float = 120.0 # м/с² — отсечка выбросов (рывок за кадр)
# Волны: энергия от вертикальных и продольных ускорений, затухание
const WAVE_ACCEL: float = 0.025 # px амплитуды на м/с² за секунду
const WAVE_DECAY: float = 2.5 # 1/с
const WAVE_MAX: float = 3.5 # px
const WAVE_HIT: float = 0.05 # px на HP урона
const CRACK_SLOTS: int = 4
const DIODE_HZ: float = 2.5

var player: Player = null

var _material: ShaderMaterial
var _tank: ColorRect
var _hp_label: Label
var _unit_label: Label
var _fill_target: float = 1.0
var _fill_shown: float = 1.0
var _ratio: float = 1.0
var _tilt: float = 0.0
var _tilt_vel: float = 0.0
var _wave: float = 0.0
var _flash: float = 0.0
var _boil: float = 0.0
var _time: float = 0.0
var _prev_vel: Vector3 = Vector3.ZERO
var _prev_yaw: float = 0.0
var _has_prev: bool = false
var _cracks: PackedVector4Array = PackedVector4Array()
var _next_crack: int = 0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size = PANEL_SIZE
	_tank = ColorRect.new()
	_tank.name = "Tank"
	_tank.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tank.size = TANK_SIZE
	_material = ShaderMaterial.new()
	_material.shader = SHADER
	_material.set_shader_parameter("rect_size", TANK_SIZE)
	_tank.material = _material
	add_child(_tank)
	_hp_label = _make_label(34, Vector2(TANK_SIZE.x + 10.0, 40.0))
	_unit_label = _make_label(14, Vector2(TANK_SIZE.x + 12.0, 80.0))
	_unit_label.text = "HP"
	_unit_label.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85, 0.75))
	clear_cracks()

func _make_label(font_size: int, pos: Vector2) -> Label:
	var label: Label = Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.position = pos
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.85))
	label.add_theme_constant_override("outline_size", 6)
	add_child(label)
	return label

## Новое значение HP; animate = false — уровень сразу на месте (старт, смерть)
func set_health(current: int, max_hp: int, animate: bool = true) -> void:
	var shown: int = maxi(0, current)
	_ratio = float(shown) / float(max_hp) if max_hp > 0 else 0.0
	_fill_target = _ratio
	if not animate:
		_fill_shown = _ratio
	_hp_label.text = str(shown)
	# Цвет числа — по прежним порогам полосы HP: > 50% белый, 25–50% жёлтый, < 25% красный
	var c: Color = Color.WHITE
	if _ratio < 0.25:
		c = Color(0.95, 0.2, 0.2)
	elif _ratio <= 0.5:
		c = Color(0.95, 0.8, 0.15)
	_hp_label.add_theme_color_override("font_color", c)

## Попадание: трещина в случайной точке стекла, вспышка, всплеск
func on_damage(amount: int) -> void:
	var strength: float = clampf(float(amount) / 30.0, 0.35, 1.0)
	var pos: Vector2 = Vector2(randf_range(12.0, 42.0), randf_range(20.0, TANK_SIZE.y - 20.0))
	_cracks[_next_crack] = Vector4(pos.x, pos.y, strength, randf())
	_next_crack = (_next_crack + 1) % CRACK_SLOTS
	_flash = 1.0
	_wave = minf(_wave + float(amount) * WAVE_HIT, WAVE_MAX)
	_tilt_vel += randf_range(-1.0, 1.0) * strength * 2.0
	_material.set_shader_parameter("cracks", _cracks)

func clear_cracks() -> void:
	_cracks.clear()
	for i in range(CRACK_SLOTS):
		_cracks.append(Vector4.ZERO)
	_next_crack = 0
	_material.set_shader_parameter("cracks", _cracks)

func _process(delta: float) -> void:
	if delta <= 0.0:
		return
	_time += delta
	_fill_shown = lerpf(_fill_shown, _fill_target, 1.0 - exp(-FILL_RATE * delta))
	_simulate_slosh(delta)
	_flash = move_toward(_flash, 0.0, delta * 4.0)

	var critical: bool = is_instance_valid(player) and not player.is_dead and _ratio <= player.low_health_threshold and _ratio > 0.0
	_boil = move_toward(_boil, 1.0 if critical else 0.0, delta * 2.0)
	var diode: float = 0.0
	if critical:
		diode = 0.15 + 0.85 * smoothstep(-0.2, 0.2, sin(_time * TAU * DIODE_HZ))

	_material.set_shader_parameter("fill", _fill_shown)
	_material.set_shader_parameter("tilt", _tilt)
	_material.set_shader_parameter("wave", _wave + _boil * 0.6)
	_material.set_shader_parameter("boil", _boil)
	_material.set_shader_parameter("diode", diode)
	_material.set_shader_parameter("flash", _flash)
	# Трещины видны, пока HP не близко к полному: лечение «затягивает» стекло
	_material.set_shader_parameter("crack_visibility", clampf((1.0 - _ratio) / 0.15, 0.0, 1.0))

## Инерция крови: ускорение игрока в его осях (x — вбок, y — вверх, z — вперёд) и рыскание камеры
func _simulate_slosh(delta: float) -> void:
	var force: float = 0.0
	if is_instance_valid(player) and not player.is_dead:
		var vel: Vector3 = player.global_basis.inverse() * player.velocity
		var yaw: float = player.head.global_rotation.y if player.head else 0.0
		if _has_prev:
			var accel: Vector3 = ((vel - _prev_vel) / delta).limit_length(ACCEL_MAX)
			var yaw_rate: float = angle_difference(_prev_yaw, yaw) / delta
			# Разгон вправо — кровь отстаёт и поднимается у левой стенки (поверхность наклоняется вниз вправо)
			force = accel.x * TILT_ACCEL + yaw_rate * TILT_LOOK
			_wave = minf(_wave + (absf(accel.y) + absf(accel.z) * 0.4) * WAVE_ACCEL * delta, WAVE_MAX)
		_prev_vel = vel
		_prev_yaw = yaw
		_has_prev = true
	else:
		_has_prev = false
	var acc: float = force * TILT_STIFFNESS - _tilt * TILT_STIFFNESS - _tilt_vel * TILT_DAMPING
	_tilt_vel += acc * delta
	_tilt = clampf(_tilt + _tilt_vel * delta, -TILT_MAX, TILT_MAX)
	_wave *= exp(-WAVE_DECAY * delta)
