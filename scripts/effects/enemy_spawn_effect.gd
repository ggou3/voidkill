class_name EnemySpawnEffect
extends Node3D

## Эффект появления врага: на точке спавна растекается кровь, из неё поднимается кровавый столб;
## к концу подъёма (rise_time) столб лопается брызгами — в этот момент сектор создаёт врага.
## Чисто визуальный: коллизий и урона нет, лужа не даёт кровавого сёрфа. Удаляет себя сам.
## Стартует из play() после add_child() и выставления global_position.

const BLOOD_SPLATTER_SCENE = preload("res://blood_splatter.tscn")
const BLOOD_COLOR = Color(0.55, 0.0, 0.02, 1.0)

const POOL_RADIUS: float = 0.9
const POOL_GROW_TIME: float = 0.25
const COLUMN_RADIUS: float = 0.42
const COLUMN_HEIGHT: float = 2.0
const POP_TIME: float = 0.22
const FADE_TIME: float = 0.6
# Поиск пола под точкой спавна: точка врага обычно ~1 м над полом; летуна над полом нет
const FLOOR_PROBE_DEPTH: float = 3.0
const NO_FLOOR_OFFSET: float = -0.5

var _material: StandardMaterial3D
var _pool: Node3D
var _column: Node3D

func play(rise_time: float) -> void:
	var floor_offset = _find_floor_offset()
	_build(floor_offset)
	_spawn_splatter(Vector3(0.0, floor_offset + 0.1, 0.0), 24, 35.0, 3.0, 7.0)

	var grow = create_tween().set_parallel(true)
	grow.tween_property(_pool, "scale", Vector3.ONE, POOL_GROW_TIME).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	grow.tween_property(_column, "scale:y", 1.0, rise_time).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

	var pop = create_tween()
	pop.tween_interval(rise_time)
	pop.tween_callback(_spawn_splatter.bind(Vector3(0.0, floor_offset + COLUMN_HEIGHT * 0.5, 0.0), 70, 180.0, 5.0, 11.0))
	pop.tween_property(_column, "scale", Vector3(1.6, 0.02, 1.6), POP_TIME).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	pop.parallel().tween_property(_material, "albedo_color:a", 0.0, FADE_TIME)
	pop.tween_callback(queue_free)

func _find_floor_offset() -> float:
	var space_state = get_world_3d().direct_space_state
	if not space_state:
		return NO_FLOOR_OFFSET
	var from = global_position + Vector3.UP * 0.5
	var query = PhysicsRayQueryParameters3D.create(from, global_position + Vector3.DOWN * FLOOR_PROBE_DEPTH)
	query.collide_with_areas = false
	var hit = space_state.intersect_ray(query)
	if hit.is_empty():
		return NO_FLOOR_OFFSET
	return hit.position.y - global_position.y

func _build(floor_offset: float) -> void:
	_material = StandardMaterial3D.new()
	_material.albedo_color = BLOOD_COLOR
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.emission_enabled = true
	_material.emission = Color(0.6, 0.0, 0.02)
	_material.emission_energy_multiplier = 0.6
	_material.roughness = 0.25

	_pool = Node3D.new()
	_pool.position.y = floor_offset + 0.02
	_pool.scale = Vector3(0.05, 1.0, 0.05)
	add_child(_pool)
	var pool_mesh = CylinderMesh.new()
	pool_mesh.top_radius = POOL_RADIUS
	pool_mesh.bottom_radius = POOL_RADIUS
	pool_mesh.height = 0.03
	_pool.add_child(_make_mesh(pool_mesh))

	# Опорная точка столба — у пола, чтобы он рос вверх
	_column = Node3D.new()
	_column.position.y = floor_offset
	_column.scale = Vector3(1.0, 0.02, 1.0)
	add_child(_column)
	var column_mesh = CylinderMesh.new()
	column_mesh.top_radius = COLUMN_RADIUS * 0.55
	column_mesh.bottom_radius = COLUMN_RADIUS
	column_mesh.height = COLUMN_HEIGHT
	var column_inst = _make_mesh(column_mesh)
	column_inst.position.y = COLUMN_HEIGHT * 0.5
	_column.add_child(column_inst)

func _make_mesh(mesh: Mesh) -> MeshInstance3D:
	var inst = MeshInstance3D.new()
	inst.mesh = mesh
	inst.material_override = _material
	inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return inst

func _spawn_splatter(local_pos: Vector3, amount: int, spread: float, vel_min: float, vel_max: float) -> void:
	var splatter = BLOOD_SPLATTER_SCENE.instantiate()
	splatter.amount = amount
	var pmat = splatter.process_material.duplicate()
	pmat.spread = spread
	pmat.initial_velocity_min = vel_min
	pmat.initial_velocity_max = vel_max
	splatter.process_material = pmat
	# Брызги живут дольше эффекта — кладём их рядом, а не внутрь
	var root = get_parent() if get_parent() else self
	root.add_child(splatter)
	splatter.global_position = to_global(local_pos)
	# Направление частиц — локальная +Z: разворачиваем вверх
	splatter.global_rotation = Vector3(-PI * 0.5, 0.0, 0.0)
