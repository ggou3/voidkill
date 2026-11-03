class_name HeartMonitor
extends Control

## Индикатор BPM в левом верхнем углу HUD: анатомическое сердце (shaders/heart.gdshader) бьётся с частотой
## BPM двойным ударом «лаб-даб», справа — число BPM, под сердцем — ЭКГ (ECGTrace). Чем выше BPM, тем сильнее
## удар, а с PUMPING из сердца и аорты вылетают капли крови — тем больше, чем выше BPM. Цвет ЭКГ и числа —
## от зелёного на малом BPM к красному на большом. После смерти сердце темнеет и останавливается, на ЭКГ —
## прямая. Огибающую удара (pulse) и сглаженную долю BPM (ratio) читает HUD для виньетки и дрожи.

const HEART_SHADER: Shader = preload("res://shaders/heart.gdshader")

const HEART_SIZE: float = 128.0
const ECG_TOP: float = 132.0
const ECG_SIZE: Vector2 = Vector2(260.0, 56.0)
# Огибающая удара: первый тон — сильный, второй — DUB_STRENGTH через DUB_DELAY (не позже 40% периода)
const LUB_ATTACK: float = 0.035
const LUB_DECAY: float = 0.11
const DUB_DELAY: float = 0.2
const DUB_ATTACK: float = 0.03
const DUB_DECAY: float = 0.09
const DUB_STRENGTH: float = 0.55
# Сила удара (раздувание сердца) на 50 и на 200 BPM
const BEAT_SCALE_MIN: float = 0.05
const BEAT_SCALE_MAX: float = 0.17
# Капли крови: с какой доли BPM вылетают (0.25 — 87 BPM), сколько на удар на 200 BPM
const DROPS_FROM_RATIO: float = 0.25
const DROPS_MAX_PER_BEAT: float = 7.0
const DROP_GRAVITY: float = 900.0 # px/с²
const MAX_DROPS: int = 64
## Концы ветвей дуги аорты и центр сердца — в долях квадрата сердца (как в шейдере)
const VESSEL_TIPS: Array[Vector2] = [Vector2(0.461, 0.117), Vector2(0.551, 0.109), Vector2(0.633, 0.125)]
const HEART_CENTER: Vector2 = Vector2(0.52, 0.6)
## Скорость, с которой сглаженная доля BPM (цвет, сила удара, виньетка) догоняет настоящую, 1/с
const RATIO_RATE: float = 3.0
const COLOR_CALM: Color = Color(0.25, 1.0, 0.45)
const COLOR_MID: Color = Color(1.0, 0.85, 0.2)
const COLOR_HIGH: Color = Color(1.0, 0.12, 0.1)

var bpm_system: BPMSystem = null
var player: Player = null

## Огибающая текущего удара 0..1
var pulse: float = 0.0
## Сглаженная доля BPM 0..1 (0 — 50 BPM, 1 — 200 BPM)
var ratio: float = 0.0

var _since_beat: float = 0.0
var _period: float = 1.2
var _alive_shown: float = 1.0
var _heart: ColorRect
var _heart_material: ShaderMaterial
var _drops_layer: Control
var _ecg: ECGTrace
var _bpm_label: Label
var _unit_label: Label
var _drops: Array[Dictionary] = []

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size = Vector2(ECG_SIZE.x, ECG_TOP + ECG_SIZE.y)

	_heart = ColorRect.new()
	_heart.name = "Heart"
	_heart.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_heart.size = Vector2(HEART_SIZE, HEART_SIZE)
	_heart_material = ShaderMaterial.new()
	_heart_material.shader = HEART_SHADER
	_heart.material = _heart_material
	add_child(_heart)

	_bpm_label = _make_label(44)
	_bpm_label.position = Vector2(HEART_SIZE + 6.0, 30.0)
	_unit_label = _make_label(16)
	_unit_label.text = "BPM"
	_unit_label.position = Vector2(HEART_SIZE + 9.0, 84.0)

	_ecg = ECGTrace.new()
	_ecg.name = "ECG"
	_ecg.position = Vector2(0.0, ECG_TOP)
	_ecg.size = ECG_SIZE
	add_child(_ecg)

	# Капли — поверх сердца и ЭКГ
	_drops_layer = Control.new()
	_drops_layer.name = "Drops"
	_drops_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_drops_layer.size = size
	add_child(_drops_layer)
	_drops_layer.draw.connect(_draw_drops)

func _make_label(font_size: int) -> Label:
	var label: Label = Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.9))
	label.add_theme_constant_override("outline_size", 6)
	add_child(label)
	return label

## Цвет ЭКГ и числа по доле BPM: зелёный → жёлтый (125 BPM) → красный
static func trace_color(t: float) -> Color:
	if t < 0.5:
		return COLOR_CALM.lerp(COLOR_MID, t / 0.5)
	return COLOR_MID.lerp(COLOR_HIGH, (t - 0.5) / 0.5)

func _process(delta: float) -> void:
	var alive: bool = is_instance_valid(bpm_system) and not (is_instance_valid(player) and player.is_dead)
	var bpm: float = bpm_system.bpm if alive else 0.0
	var target_ratio: float = bpm_system.get_bpm_ratio() if alive else 0.0
	ratio = lerpf(ratio, target_ratio, 1.0 - exp(-RATIO_RATE * delta))

	if alive:
		_period = 60.0 / maxf(bpm, 1.0)
		_since_beat += delta
		if _since_beat >= _period:
			_since_beat = fmod(_since_beat, _period)
			_spawn_drops()
		pulse = _envelope(_since_beat)
	else:
		pulse = move_toward(pulse, 0.0, delta * 4.0)
	_alive_shown = move_toward(_alive_shown, 1.0 if alive else 0.0, delta * 2.0)

	_heart_material.set_shader_parameter("beat", pulse)
	_heart_material.set_shader_parameter("beat_scale", lerpf(BEAT_SCALE_MIN, BEAT_SCALE_MAX, ratio))
	_heart_material.set_shader_parameter("intensity", ratio)
	_heart_material.set_shader_parameter("alive", _alive_shown)

	var color: Color = trace_color(ratio) if alive else COLOR_HIGH
	_ecg.advance(delta, _since_beat, _period, alive, color)
	_bpm_label.text = str(int(round(bpm))) if alive else "--"
	_bpm_label.add_theme_color_override("font_color", color)
	_unit_label.add_theme_color_override("font_color", Color(color, 0.75))

	_update_drops(delta)

## Огибающая «лаб-даб» через ts секунд после удара
func _envelope(ts: float) -> float:
	var dub_at: float = minf(DUB_DELAY, _period * 0.4)
	var lub: float = _bump(ts, LUB_ATTACK, LUB_DECAY)
	var dub: float = _bump(ts - dub_at, DUB_ATTACK, DUB_DECAY) * DUB_STRENGTH
	return maxf(lub, dub)

## Быстрый рост за attack и экспоненциальный спад с постоянной decay
static func _bump(x: float, attack: float, decay: float) -> float:
	if x < 0.0:
		return 0.0
	if x < attack:
		return smoothstep(0.0, 1.0, x / attack)
	return exp(-(x - attack) / decay)

# --- Капли крови ---

func _spawn_drops() -> void:
	if ratio < DROPS_FROM_RATIO:
		return
	var k: float = (ratio - DROPS_FROM_RATIO) / (1.0 - DROPS_FROM_RATIO)
	var count: int = int(round(lerpf(1.0, DROPS_MAX_PER_BEAT, k) * randf_range(0.6, 1.2)))
	for i in range(count):
		if _drops.size() >= MAX_DROPS:
			_drops.pop_front()
		var pos: Vector2
		var dir: Vector2
		if randf() < 0.5:
			# Брызги из ветвей аорты — вверх веером
			pos = VESSEL_TIPS[randi() % VESSEL_TIPS.size()] * HEART_SIZE
			dir = Vector2.UP.rotated(randf_range(-0.6, 0.6))
		else:
			# С поверхности сердца — вверх и в стороны, вниз реже
			dir = Vector2.RIGHT.rotated(randf_range(-PI * 0.95, PI * 0.15))
			pos = HEART_CENTER * HEART_SIZE + dir * HEART_SIZE * 0.3
		var speed: float = randf_range(90.0, 200.0) * (0.7 + 0.6 * k)
		_drops.append({
			"pos": pos,
			"vel": dir * speed,
			"life": 0.0,
			"max_life": randf_range(0.45, 0.85),
			"radius": randf_range(1.4, 3.0),
		})

func _update_drops(delta: float) -> void:
	if _drops.is_empty():
		return
	for i in range(_drops.size() - 1, -1, -1):
		var drop: Dictionary = _drops[i]
		drop.life += delta
		if drop.life >= drop.max_life:
			_drops.remove_at(i)
			continue
		drop.vel += Vector2(0.0, DROP_GRAVITY * delta)
		drop.pos += drop.vel * delta
	_drops_layer.queue_redraw()

func _draw_drops() -> void:
	for drop in _drops:
		var alpha: float = 1.0 - pow(drop.life / drop.max_life, 2.0)
		var pos: Vector2 = drop.pos
		var r: float = drop.radius
		# Хвост вдоль скорости — капля вытягивается в полёте
		_drops_layer.draw_line(pos - drop.vel * 0.02, pos, Color(0.4, 0.0, 0.02, alpha * 0.8), r * 1.3, true)
		_drops_layer.draw_circle(pos, r, Color(0.58, 0.02, 0.04, alpha))
		_drops_layer.draw_circle(pos + Vector2(-0.35, -0.35) * r, r * 0.35, Color(1.0, 0.6, 0.6, alpha * 0.6))
