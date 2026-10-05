class_name BloodBarrier
extends Node3D

## Кровавая перегородка между секторами: полупрозрачная стена стекающей крови, пульсирующая
## в такт сердцу игрока (частота — текущий BPM). Блокирует проход игроку и врагам.
## Когда привязанный сектор зачищен — стена обрушивается (анимация + звук), оставляет лужи
## крови на пороге (blood_pool.tscn) и становится чекпоинтом.
##
## Ориентация: локальная -Z смотрит в следующий сектор, +Z — в зачищаемый сектор.
## Стена стоит основанием на y = 0 узла. Точка возрождения — дочерний Marker3D "Checkpoint",
## если он есть, иначе 2.5 м перед стеной со стороны зачищенного сектора, лицом к следующему.

signal collapsed

const BLOOD_POOL_SCENE = preload("res://blood_pool.tscn")
const BARRIER_SHADER = preload("res://shaders/blood_barrier.gdshader")

## Сектор, зачистка которого обрушивает стену
@export var sector: Sector
## Ширина, высота, толщина стены (м)
@export var size: Vector3 = Vector3(12.0, 8.0, 0.6)
## Луж в ряду и число рядов (ряды уходят в следующий сектор)
@export var pools_per_row: int = 3
@export var pool_rows: int = 2
@export var pool_row_spacing: float = 3.5
@export var collapse_duration: float = 0.9

var is_collapsed: bool = false

var _wall: Node3D
var _body: StaticBody3D
var _material: ShaderMaterial
var _beat_phase: float = 0.0

func _ready() -> void:
	_build()
	if sector:
		sector.cleared.connect(collapse)

func _build() -> void:
	_wall = Node3D.new()
	_wall.name = "Wall"
	add_child(_wall)
	var mesh_inst = MeshInstance3D.new()
	var quad = QuadMesh.new()
	quad.size = Vector2(size.x, size.y)
	mesh_inst.mesh = quad
	mesh_inst.position.y = size.y * 0.5
	mesh_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_material = ShaderMaterial.new()
	_material.shader = BARRIER_SHADER
	_material.set_shader_parameter("wall_width", size.x)
	mesh_inst.material_override = _material
	_wall.add_child(mesh_inst)

	_body = StaticBody3D.new()
	_body.name = "Body"
	add_child(_body)
	var shape = CollisionShape3D.new()
	var box = BoxShape3D.new()
	box.size = size
	shape.shape = box
	shape.position.y = size.y * 0.5
	_body.add_child(shape)

func _process(delta: float) -> void:
	if is_collapsed:
		return
	var bpm: float = 50.0
	var player = get_tree().get_first_node_in_group("player")
	if is_instance_valid(player) and "bpm_system" in player and is_instance_valid(player.bpm_system):
		bpm = player.bpm_system.bpm
	_beat_phase += delta * bpm / 60.0
	_material.set_shader_parameter("beat_phase", _beat_phase)

func collapse() -> void:
	if is_collapsed:
		return
	is_collapsed = true
	for child in _body.get_children():
		if child is CollisionShape3D:
			child.set_deferred("disabled", true)
	AudioManager.play_sound("slam_impact")
	AudioManager.play_sound("flask_splash")
	_spawn_pools()

	var tween = create_tween().set_parallel(true)
	tween.tween_property(_material, "shader_parameter/collapse", 1.0, collapse_duration)
	tween.tween_property(_wall, "scale:y", 0.05, collapse_duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(_wall.hide)
	GameTypes.debug_log(&"enemy", "[BARRIER %s] Collapsed" % name)
	collapsed.emit()

## Лужи крови на пороге: ряды поперёк прохода, уходящие в следующий сектор, — по ним можно сёрфить
func _spawn_pools() -> void:
	var scene_root = get_tree().current_scene if get_tree().current_scene else get_parent()
	if not scene_root:
		return
	var space_state = get_world_3d().direct_space_state
	for row in range(pool_rows):
		for i in range(pools_per_row):
			var across = ((float(i) + 0.5) / float(pools_per_row) - 0.5) * size.x * 0.8
			var from = to_global(Vector3(across, 1.0, -1.5 - row * pool_row_spacing))
			var pool_pos = from + Vector3.DOWN * 1.0
			if space_state:
				var query = PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 4.0)
				query.exclude = [_body.get_rid()]
				var hit = space_state.intersect_ray(query)
				if not hit.is_empty():
					pool_pos = hit.position
			var pool = BLOOD_POOL_SCENE.instantiate()
			scene_root.add_child(pool)
			pool.global_position = pool_pos + Vector3(0.0, 0.01, 0.0)

func get_checkpoint_transform() -> Transform3D:
	var marker = get_node_or_null("Checkpoint")
	if marker is Node3D:
		return marker.global_transform
	return global_transform.translated_local(Vector3(0.0, 1.2, 2.5))
