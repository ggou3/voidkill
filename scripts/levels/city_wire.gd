@tool
class_name CityWire
extends Node3D

## Провода над улицей (ноябрь 2026, уровень city_level): пучок из нескольких проводов от узла до точки end
## (в локальных координатах), каждый провисает по параболе. Без коллизии. Геометрия создаётся в _ready и в
## редакторе (@tool) без владельца — в сцену не сохраняется.

## Второй конец пучка относительно узла
@export var end: Vector3 = Vector3(10.0, 0.0, 0.0):
	set(value):
		end = value
		_queue_rebuild()
## Провис посередине (м)
@export var sag: float = 1.2:
	set(value):
		sag = value
		_queue_rebuild()
## Сколько проводов в пучке
@export_range(1, 6) var count: int = 3:
	set(value):
		count = value
		_queue_rebuild()

const SEGMENTS: int = 14
const THICKNESS: float = 0.035
const SPREAD: float = 0.35 # м между проводами пучка

var _generated: Node3D = null
var _rebuild_queued: bool = false

func _ready() -> void:
	_rebuild()

func _queue_rebuild() -> void:
	if not is_inside_tree() or _rebuild_queued:
		return
	_rebuild_queued = true
	_rebuild.call_deferred()

func _rebuild() -> void:
	_rebuild_queued = false
	if _generated:
		_generated.queue_free()
	_generated = Node3D.new()
	_generated.name = "Generated"
	add_child(_generated)
	var m := CityMesh.new()
	var across: Vector3 = end.cross(Vector3.UP).normalized() if absf(end.normalized().y) < 0.95 else Vector3.RIGHT
	for w in range(count):
		var offset: Vector3 = across * (float(w) - float(count - 1) * 0.5) * SPREAD + Vector3.UP * (w % 2) * 0.15
		# Провисание растёт у нижних проводов пучка — пучок не выглядит одной лентой
		var wire_sag: float = sag * (1.0 + 0.12 * float(w))
		var prev: Vector3 = offset
		for s in range(1, SEGMENTS + 1):
			var t: float = float(s) / float(SEGMENTS)
			var p: Vector3 = end * t + offset + Vector3.DOWN * wire_sag * 4.0 * t * (1.0 - t)
			m.beam(&"metal_dark", prev, p, THICKNESS)
			prev = p
	_generated.add_child(m.build(false))
