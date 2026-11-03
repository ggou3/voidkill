class_name BPMVignette
extends ColorRect

## Полупрозрачная красная виньетка с капиллярами на высоком BPM (shaders/bpm_vignette.gdshader).
## Сосуды — настоящие ветвящиеся деревья, как разряд молнии: при создании их один раз рисует в текстуру
## SubViewport (от краёв экрана к центру, с ветвлением и сужением; R — яркая сердцевина, G — свечение).
## Шейдер показывает их у краёв, на каждом ударе сердца — ярче и глубже к центру.
## Проявляется с начала SURGING и полностью — на 200 BPM. Создаёт HUD под всеми панелями; на малом BPM узел
## скрыт и не рисуется.

const SHADER: Shader = preload("res://shaders/bpm_vignette.gdshader")
## Доля BPM, с которой виньетка начинает проявляться: 0.6 — 140 BPM, начало SURGING
const FROM_RATIO: float = 0.6

const TEX_SIZE: Vector2i = Vector2i(1280, 720)
const ROOTS: int = 38 # стволов по периметру
const STEP: float = 7.0 # px шага роста
const TURN: float = 0.42 # рад случайного поворота на шаг — изломанность «молнии»
const BRANCH_CHANCE: float = 0.075 # на шаг
const MAX_DEPTH: int = 4
const ROOT_WIDTH: float = 2.6 # px
const ROOT_LENGTH: Vector2 = Vector2(220.0, 420.0) # px, случайно в диапазоне

var _material: ShaderMaterial
var _veins_viewport: SubViewport

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_material = ShaderMaterial.new()
	_material.shader = SHADER
	material = _material
	visible = false
	_bake_veins()

## ratio — сглаженная доля BPM 0..1, pulse — огибающая удара сердца 0..1
func set_state(ratio: float, pulse: float) -> void:
	var k: float = smoothstep(FROM_RATIO, 1.0, ratio)
	visible = k > 0.001
	if not visible:
		return
	_material.set_shader_parameter("intensity", k)
	_material.set_shader_parameter("pulse", pulse)

## Текстура сосудов: SubViewport рендерится один раз, рисунок — в draw холста с аддитивным смешиванием
func _bake_veins() -> void:
	_veins_viewport = SubViewport.new()
	_veins_viewport.name = "VeinsViewport"
	_veins_viewport.size = TEX_SIZE
	_veins_viewport.transparent_bg = true
	_veins_viewport.disable_3d = true
	_veins_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(_veins_viewport)
	var painter: Control = Control.new()
	painter.size = Vector2(TEX_SIZE)
	var add_material: CanvasItemMaterial = CanvasItemMaterial.new()
	add_material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	painter.material = add_material
	painter.draw.connect(_draw_veins.bind(painter))
	_veins_viewport.add_child(painter)
	_material.set_shader_parameter("veins_tex", _veins_viewport.get_texture())

func _draw_veins(canvas: Control) -> void:
	var size_f: Vector2 = Vector2(TEX_SIZE)
	var center: Vector2 = size_f * 0.5
	var perimeter: float = 2.0 * (size_f.x + size_f.y)
	# Ветви растут стеком: [позиция, направление, ширина, длина, глубина]
	var stack: Array = []
	for i in range(ROOTS):
		var along: float = (float(i) + randf_range(0.1, 0.9)) / float(ROOTS) * perimeter
		var start: Vector2 = _perimeter_point(along, size_f)
		var dir: Vector2 = (center - start).normalized().rotated(randf_range(-0.6, 0.6))
		stack.append([start, dir, ROOT_WIDTH * randf_range(0.7, 1.2), randf_range(ROOT_LENGTH.x, ROOT_LENGTH.y), 0])
	while not stack.is_empty():
		var b: Array = stack.pop_back()
		var pos: Vector2 = b[0]
		var dir: Vector2 = b[1]
		var width: float = b[2]
		var length: float = b[3]
		var depth: int = b[4]
		var steps: int = maxi(int(length / STEP), 2)
		var to_center: Vector2 = (center - pos).normalized()
		for s in range(steps):
			dir = dir.rotated(randf_range(-TURN, TURN)).lerp(to_center, 0.04).normalized()
			var next: Vector2 = pos + dir * STEP * randf_range(0.6, 1.4)
			var w: float = maxf(width * (1.0 - 0.75 * float(s) / float(steps)), 0.6)
			canvas.draw_line(pos, next, Color(0.0, 0.16, 0.0), w * 5.0 + 2.0, true)
			canvas.draw_line(pos, next, Color(1.0, 0.0, 0.0), w, true)
			pos = next
			if depth < MAX_DEPTH and randf() < BRANCH_CHANCE:
				var side: float = 1.0 if randf() < 0.5 else -1.0
				stack.append([pos, dir.rotated(side * randf_range(0.45, 1.1)), w * 0.7, (length - float(s) * STEP) * randf_range(0.45, 0.8), depth + 1])

## Точка периметра на расстоянии along по часовой стрелке от левого верхнего угла (чуть за краем)
func _perimeter_point(along: float, size_f: Vector2) -> Vector2:
	var pad: float = 6.0
	if along < size_f.x:
		return Vector2(along, -pad)
	along -= size_f.x
	if along < size_f.y:
		return Vector2(size_f.x + pad, along)
	along -= size_f.y
	if along < size_f.x:
		return Vector2(size_f.x - along, size_f.y + pad)
	along -= size_f.x
	return Vector2(-pad, size_f.y - along)
