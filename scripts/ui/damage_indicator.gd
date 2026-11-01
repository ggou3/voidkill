class_name DamageIndicator
extends Control

## Индикатор направления урона: дуга вокруг прицела в сторону источника и треугольник-указатель снаружи
## дуги (различим формой и положением, а не только цветом). Направление хранится в мировых координатах,
## поэтому дуга поворачивается вместе с игроком: источник за спиной — дуга внизу экрана.
## Удары с близких направлений (MERGE_ANGLE) сливаются в одну дугу, сила — по максимальному урону.

const MAX_MARKERS: int = 8
const SHOW_TIME: float = 0.8
const FADE_TIME: float = 0.4 # последние 0.4 с показа — затухание
const RADIUS: float = 96.0 # пикселей от центра экрана
const MERGE_ANGLE: float = 0.35 # рад (~20°)
const COLOR_HIT: Color = Color(1.0, 0.12, 0.08)

var player: Node3D = null
var _dirs: Array[Vector3] = []
var _times: Array[float] = []
var _strengths: Array[float] = []

func _ready() -> void:
	# Именно «и отступы»: set_anchors_preset сохраняет текущий прямоугольник узла (у нового — 0×0 в углу),
	# и центр дуг оказывался в левом верхнем углу экрана
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

## Урон amount с горизонтального направления from_dir (мировые координаты, на источник)
func add_hit(from_dir: Vector3, amount: int) -> void:
	if from_dir == Vector3.ZERO:
		return
	# 10 HP (удар роя) — слабая дуга, 30+ HP (выпад, взрыв) — полная
	var strength: float = clampf(float(amount) / 30.0, 0.35, 1.0)
	for i in range(_dirs.size()):
		if _dirs[i].angle_to(from_dir) < MERGE_ANGLE:
			_dirs[i] = from_dir
			_times[i] = SHOW_TIME
			_strengths[i] = maxf(_strengths[i], strength)
			queue_redraw()
			return
	if _dirs.size() >= MAX_MARKERS:
		var oldest: int = 0
		for i in range(1, _times.size()):
			if _times[i] < _times[oldest]:
				oldest = i
		_remove_marker(oldest)
	_dirs.append(from_dir)
	_times.append(SHOW_TIME)
	_strengths.append(strength)
	queue_redraw()

func clear() -> void:
	_dirs.clear()
	_times.clear()
	_strengths.clear()
	queue_redraw()

func _remove_marker(i: int) -> void:
	_dirs.remove_at(i)
	_times.remove_at(i)
	_strengths.remove_at(i)

func _process(delta: float) -> void:
	if _dirs.is_empty():
		return
	for i in range(_times.size() - 1, -1, -1):
		_times[i] -= delta
		if _times[i] <= 0.0:
			_remove_marker(i)
	queue_redraw()

func _draw() -> void:
	if _dirs.is_empty() or not is_instance_valid(player):
		return
	var center: Vector2 = size * 0.5
	var fwd: Vector3 = -player.global_transform.basis.z
	var right: Vector3 = player.global_transform.basis.x
	for i in range(_dirs.size()):
		var d: Vector3 = _dirs[i]
		# Угол источника относительно взгляда: 0 — впереди (верх экрана), ±PI — сзади (низ экрана)
		var rel: float = atan2(d.dot(right), d.dot(fwd))
		var ang: float = -PI * 0.5 + rel
		var alpha: float = clampf(_times[i] / FADE_TIME, 0.0, 1.0)
		var s: float = _strengths[i]
		var half: float = lerpf(0.3, 0.55, s)
		var width: float = lerpf(5.0, 10.0, s)
		var col := Color(COLOR_HIT.r, COLOR_HIT.g, COLOR_HIT.b, 0.85 * alpha)
		var outline := Color(0.0, 0.0, 0.0, 0.5 * alpha)
		draw_arc(center, RADIUS, ang - half, ang + half, 24, outline, width + 4.0, true)
		draw_arc(center, RADIUS, ang - half, ang + half, 24, col, width, true)
		var dir2 := Vector2(cos(ang), sin(ang))
		var perp := Vector2(-dir2.y, dir2.x) * (8.0 + 6.0 * s)
		var base_c: Vector2 = center + dir2 * (RADIUS + width * 0.5 + 4.0)
		var tip: Vector2 = center + dir2 * (RADIUS + width * 0.5 + 18.0 + 8.0 * s)
		draw_colored_polygon(PackedVector2Array([tip, base_c + perp, base_c - perp]), col)
