class_name BPMHint
extends Label

## Подсказка у прицела: за что растёт и за что падает BPM. События одной серии (пауза между ними меньше
## MERGE_WINDOW, один знак) объединяются в одну строку: «+38 BPM» и ниже «KILL ×7 · HEADSHOT · MOMENTUM ×1.4».
## Рой даёт десятки убийств подряд — строка одна, а не стопка. Потеря от урона — отдельной красной строкой.

const MERGE_WINDOW: float = 0.7 # с между событиями одной серии
const HOLD_TIME: float = 1.2 # с показа после последнего события
const FADE_TIME: float = 0.4
const OFFSET_Y: float = 64.0 # пикселей ниже центра экрана (под прицелом, не на нём)
const COLOR_GAIN: Color = Color(1.0, 0.82, 0.2)
const COLOR_LOSS: Color = Color(1.0, 0.25, 0.2)
const REASON_TEXT: Dictionary = {
	&"kill": "KILL",
	&"shockwave": "SHOCKWAVE",
	&"headshot": "HEADSHOT",
	&"variety": "VARIETY",
	&"hit": "HIT",
}
# Порядок причин в строке
const REASON_ORDER: Array[StringName] = [&"kill", &"shockwave", &"headshot", &"variety", &"hit"]

var _total: float = 0.0
var _counts: Dictionary = {} # причина -> число событий в серии
var _max_momentum: float = 1.0
var _since_last: float = 999.0

func _ready() -> void:
	# Якоря в центре экрана, прямоугольник 520×60 под прицелом
	set_anchors_preset(Control.PRESET_CENTER)
	offset_left = -260.0
	offset_right = 260.0
	offset_top = OFFSET_Y
	offset_bottom = OFFSET_Y + 60.0
	horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vertical_alignment = VERTICAL_ALIGNMENT_TOP
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_font_size_override("font_size", 20)
	add_theme_constant_override("outline_size", 6)
	add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.9))
	visible = false

func on_bpm_event(amount: float, reason: StringName, momentum: float) -> void:
	if amount == 0.0:
		return
	var same_series: bool = _since_last < MERGE_WINDOW and signf(amount) == signf(_total)
	if not same_series:
		_total = 0.0
		_counts.clear()
		_max_momentum = 1.0
	_total += amount
	_counts[reason] = int(_counts.get(reason, 0)) + 1
	_max_momentum = maxf(_max_momentum, momentum)
	_since_last = 0.0
	_refresh_text()
	modulate.a = 1.0
	visible = true

func clear() -> void:
	_total = 0.0
	_counts.clear()
	_since_last = 999.0
	visible = false

func _refresh_text() -> void:
	var parts := PackedStringArray()
	for r in REASON_ORDER:
		if not _counts.has(r):
			continue
		var n: int = _counts[r]
		parts.append(REASON_TEXT[r] if n == 1 else "%s ×%d" % [REASON_TEXT[r], n])
	if _total > 0.0 and _max_momentum > 1.01:
		parts.append("MOMENTUM ×%.1f" % _max_momentum)
	var sign_text: String = "+" if _total > 0.0 else "−"
	text = "%s%d BPM\n%s" % [sign_text, int(round(absf(_total))), " · ".join(parts)]
	add_theme_color_override("font_color", COLOR_GAIN if _total > 0.0 else COLOR_LOSS)

func _process(delta: float) -> void:
	if not visible:
		return
	_since_last += delta
	if _since_last >= HOLD_TIME + FADE_TIME:
		visible = false
	elif _since_last > HOLD_TIME:
		modulate.a = 1.0 - (_since_last - HOLD_TIME) / FADE_TIME
