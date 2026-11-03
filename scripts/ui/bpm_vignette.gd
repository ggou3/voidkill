class_name BPMVignette
extends ColorRect

## Полупрозрачная красная виньетка с капиллярами на высоком BPM (shaders/bpm_vignette.gdshader).
## Проявляется с начала SURGING и полностью — на 200 BPM, пульсирует под удары сердца индикатора BPM.
## Создаёт HUD под всеми панелями; на малом BPM узел скрыт и не рисуется.

const SHADER: Shader = preload("res://shaders/bpm_vignette.gdshader")
## Доля BPM, с которой виньетка начинает проявляться: 0.6 — 140 BPM, начало SURGING
const FROM_RATIO: float = 0.6

var _material: ShaderMaterial

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_material = ShaderMaterial.new()
	_material.shader = SHADER
	material = _material
	visible = false

## ratio — сглаженная доля BPM 0..1, pulse — огибающая удара сердца 0..1
func set_state(ratio: float, pulse: float) -> void:
	var k: float = smoothstep(FROM_RATIO, 1.0, ratio)
	visible = k > 0.001
	if not visible:
		return
	_material.set_shader_parameter("intensity", k)
	_material.set_shader_parameter("pulse", pulse)
