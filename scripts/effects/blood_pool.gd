class_name BloodPool
extends Area3D

var _expand_tween: Tween = null
var _base_scale: Vector3 = Vector3.ZERO

## Отравленная лужа (дротик Инъектора упал в неё, ноябрь 2026): темнеет и раз в POISON_TICK_INTERVAL
## накладывает стак яда Инъектора на врагов в луже. Игрока не травит — свои приёмы игрока не ранят.
## Для игрока лужа остаётся кровью: сёрф по ней работает как обычно.
const POOL_RADIUS: float = 1.75 # радиус меша 3.5×3.5 / 2; форма-цилиндр 1.7
const POISON_TICK_INTERVAL: float = 1.0
## Визуал — shaders/blood_pool.gdshader (ноябрь 2026): форма от seed, растекание spread, отравление poison
## (параметры экземпляра меша). Лужа появляется маленькой и растекается за SPREAD_TIME
const SPREAD_START: float = 0.2
const SPREAD_TIME: float = 0.6
const POISON_FADE_TIME: float = 0.3
## Поиск пола под точкой смерти: длина луча и сколько тел (враги, игрок) он может пропустить
const FLOOR_RAY_LENGTH: float = 50.0
const FLOOR_RAY_MAX_SKIPS: int = 8
const FLOOR_MIN_NORMAL_Y: float = 0.7 # круче — лужа ложится ровно
var poison_timer: float = 0.0
var _poison_tick_timer: float = 0.0
var _mesh: MeshInstance3D = null
var _poison_tween: Tween = null

## Лужа на полу под from: луч вниз только до геометрии мира. Враги и игрок на пути пропускаются (раньше
## лужа ложилась на голову врага снизу), пола нет — лужа не создаётся (раньше висела в воздухе на месте
## смерти). Лужа ложится по нормали пола. exclude — что луч не задевает с самого начала (умерший)
static func spawn_on_floor(scene: PackedScene, parent: Node, from: Vector3, exclude: Array[RID] = []) -> BloodPool:
	if not parent.is_inside_tree():
		return null
	var space: PhysicsDirectSpaceState3D = parent.get_viewport().world_3d.direct_space_state
	var query := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * FLOOR_RAY_LENGTH, 1)
	var skip: Array[RID] = exclude.duplicate()
	for i in range(FLOOR_RAY_MAX_SKIPS):
		query.exclude = skip
		var hit: Dictionary = space.intersect_ray(query)
		if hit.is_empty():
			return null
		var collider: Object = hit.collider
		if collider is CharacterBody3D or (collider is Node and (collider.is_in_group("enemy") or collider.is_in_group("player"))):
			skip.append(hit.rid)
			continue
		var pool: BloodPool = scene.instantiate()
		parent.add_child(pool)
		# Наклон пола — по нормали; крутая нормаль (луч попал в ребро ступеньки) — лужа ровно, а не боком
		var up: Vector3 = hit.normal.normalized()
		if up.y < FLOOR_MIN_NORMAL_Y:
			up = Vector3.UP
		var pool_basis: Basis = Basis(Quaternion(Vector3.UP, up)) if up.y < 0.999 else Basis.IDENTITY
		pool.global_transform = Transform3D(pool_basis, hit.position + up * 0.01)
		return pool
	return null

func _ready():
	set_physics_process(false)
	_mesh = get_node_or_null("MeshInstance3D")
	add_to_group("blood_pool")
	if _mesh:
		_mesh.set_instance_shader_parameter("seed", randf() * 100.0)
		_mesh.set_instance_shader_parameter("spread", SPREAD_START)
		_mesh.set_instance_shader_parameter("poison", 0.0)
		create_tween().tween_method(_set_spread, SPREAD_START, 1.0, SPREAD_TIME) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	# Подключаем сигналы касания кодом
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

func _on_body_entered(body):
	# Если в лужу наступает Игрок, включаем флаг скольжения
	if body.name == "Player" or body.is_in_group("player"):
		if "blood_pool_count" in body:
			body.blood_pool_count += 1
			body.is_on_blood = true
		else:
			body.is_on_blood = true

func _on_body_exited(body):
	# Когда Игрок покидает лужу
	if body.name == "Player" or body.is_in_group("player"):
		if "blood_pool_count" in body:
			body.blood_pool_count = max(0, body.blood_pool_count - 1)
			body.is_on_blood = (body.blood_pool_count > 0)
		else:
			body.is_on_blood = false

## Точка лежит в луже (по горизонтали в радиусе, по высоте ±1 м); масштаб лужи учитывается
func contains_point(world_pos: Vector3) -> bool:
	var local: Vector3 = to_local(world_pos)
	return Vector2(local.x, local.z).length() <= POOL_RADIUS and absf(local.y) <= 1.0

## Отравить лужу на duration секунд (повторно — продлевает)
func poison(duration: float) -> void:
	var was_poisoned: bool = poison_timer > 0.0
	poison_timer = maxf(poison_timer, duration)
	if was_poisoned:
		return
	_poison_tick_timer = 0.0
	set_physics_process(true)
	_fade_poison(1.0)

func _physics_process(delta: float) -> void:
	if poison_timer <= 0.0:
		return
	poison_timer -= delta
	if poison_timer <= 0.0:
		set_physics_process(false)
		_fade_poison(0.0)
		return
	_poison_tick_timer -= delta
	if _poison_tick_timer > 0.0:
		return
	_poison_tick_timer = POISON_TICK_INTERVAL
	for body in get_overlapping_bodies():
		if body.is_in_group("enemy") and body.has_method("apply_poison_dot"):
			body.apply_poison_dot(3.0, 3, 0.5)

func _set_spread(value: float) -> void:
	if _mesh:
		_mesh.set_instance_shader_parameter("spread", value)

func _set_poison(value: float) -> void:
	if _mesh:
		_mesh.set_instance_shader_parameter("poison", value)

## Плавный переход цвета лужи к яду (1) или обратно к крови (0)
func _fade_poison(target: float) -> void:
	if not _mesh:
		return
	if _poison_tween and _poison_tween.is_valid():
		_poison_tween.kill()
	var current: float = float(_mesh.get_instance_shader_parameter("poison"))
	_poison_tween = create_tween()
	_poison_tween.tween_method(_set_poison, current, target, POISON_FADE_TIME)

func expand_temporarily(multiplier: float = 1.4, duration: float = 4.0):
	if _base_scale == Vector3.ZERO:
		_base_scale = scale
		
	if _expand_tween and _expand_tween.is_valid():
		_expand_tween.kill()
		
	var target_scale = _base_scale * multiplier
	
	_expand_tween = create_tween()
	# Быстрое расплёскивание лужи наружу (0.22с)
	_expand_tween.tween_property(self, "scale", target_scale, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	# Удержание увеличенного размера в течение 4 секунд
	_expand_tween.tween_interval(duration)
	# Плавное возвращение к исходному размеру (0.8с)
	_expand_tween.tween_property(self, "scale", _base_scale, 0.8).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
