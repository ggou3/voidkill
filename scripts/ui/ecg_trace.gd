class_name ECGTrace
extends Control

## Электрокардиограмма индикатора BPM. Развёртка как у монитора: курсор идёт слева направо и перезаписывает
## след, перед курсором — зазор, старый след бледнее. Форма — комплекс PQRST; интервалы PR и QT
## укорачиваются с ростом частоты, как у настоящего сердца. Время ударов и цвет задаёт HeartMonitor.

const SWEEP_SPEED: float = 110.0 # px/с
const GAP: int = 12 # px пустого места перед курсором
const AMPLITUDE: float = 0.42 # доля высоты на зубец R
const BASELINE: float = 0.62 # линия покоя — доля высоты сверху
const GRID_STEP: float = 13.0 # px
const NOISE: float = 0.012

var _samples: PackedFloat32Array = PackedFloat32Array()
var _cursor: float = 0.0
var _color: Color = Color.GREEN

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(_reset)
	_reset()

func _reset() -> void:
	_samples.resize(maxi(int(size.x), 2))
	_samples.fill(0.0)
	_cursor = 0.0

## Сдвиг развёртки на delta: since_beat — время с последнего удара, period — период ударов, с;
## alive = false — прямая линия (остановка сердца)
func advance(delta: float, since_beat: float, period: float, alive: bool, color: Color) -> void:
	_color = color
	var n: int = _samples.size()
	var from: int = int(_cursor)
	_cursor += SWEEP_SPEED * delta
	var to: int = int(_cursor)
	from = maxi(from, to - n)
	for col in range(from + 1, to + 1):
		var v: float = 0.0
		if alive:
			# Колонка col записана (cursor − col) / SWEEP_SPEED секунд назад
			var ts: float = since_beat - (_cursor - float(col)) / SWEEP_SPEED
			while ts < 0.0:
				ts += period
			v = waveform(ts, period)
		_samples[col % n] = v + randf_range(-NOISE, NOISE)
	_cursor = fmod(_cursor, float(n))
	queue_redraw()

## Значение ЭКГ через ts секунд после зубца R при периоде period (1 — высота R)
static func waveform(ts: float, period: float) -> float:
	var qt: float = clampf(period * 0.36, 0.1, 0.3)
	var pr: float = clampf(period * 0.16, 0.07, 0.16)
	var tn: float = ts - period # до следующего R (отрицательное)
	return _qrs(ts) + _qrs(tn) + 0.26 * _gauss(ts - qt, qt * 0.22) + 0.12 * _gauss(tn + pr, 0.028)

static func _qrs(x: float) -> float:
	return -0.12 * _gauss(x + 0.028, 0.01) + _gauss(x, 0.011) - 0.28 * _gauss(x - 0.03, 0.012)

static func _gauss(x: float, w: float) -> float:
	return exp(-x * x / (2.0 * w * w))

func _draw() -> void:
	var w: float = size.x
	var h: float = size.y
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.02, 0.03, 0.03, 0.72))
	var grid: Color = Color(_color, 0.08)
	var x: float = GRID_STEP
	while x < w:
		draw_line(Vector2(x, 0.0), Vector2(x, h), grid)
		x += GRID_STEP
	var y: float = GRID_STEP
	while y < h:
		draw_line(Vector2(0.0, y), Vector2(w, y), grid)
		y += GRID_STEP
	draw_rect(Rect2(Vector2.ZERO, size), Color(_color, 0.35), false, 1.0)

	# След от самой старой колонки (сразу за зазором) к курсору; на стыке края — разрыв линии
	var n: int = _samples.size()
	var cur: int = int(_cursor)
	var pts: PackedVector2Array = PackedVector2Array()
	var cols: PackedColorArray = PackedColorArray()
	for k in range(GAP + 1, n + 1):
		var col: int = (cur + k) % n
		if col == 0 and pts.size() > 0:
			_draw_trace(pts, cols)
			pts.clear()
			cols.clear()
		pts.append(Vector2(float(col), _sample_y(col, h)))
		cols.append(Color(_color, lerpf(0.15, 1.0, float(k) / float(n))))
	_draw_trace(pts, cols)
	draw_circle(Vector2(float(cur), _sample_y(cur % n, h)), 2.5, _color.lightened(0.5))

func _sample_y(col: int, h: float) -> float:
	return clampf(h * (BASELINE - _samples[col] * AMPLITUDE), 1.0, h - 1.0)

func _draw_trace(pts: PackedVector2Array, cols: PackedColorArray) -> void:
	if pts.size() < 2:
		return
	var glow: PackedColorArray = PackedColorArray()
	for c in cols:
		glow.append(Color(c, c.a * 0.25))
	draw_polyline_colors(pts, glow, 4.0, true)
	draw_polyline_colors(pts, cols, 1.6, true)
