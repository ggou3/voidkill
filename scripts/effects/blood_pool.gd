class_name BloodPool
extends Area3D

var _expand_tween: Tween = null
var _base_scale: Vector3 = Vector3.ZERO

## Отравленная лужа (дротик Инъектора упал в неё, ноябрь 2026): темнеет и раз в POISON_TICK_INTERVAL
## накладывает стак яда Инъектора на врагов в луже. Игрока не травит — свои приёмы игрока не ранят.
## Для игрока лужа остаётся кровью: сёрф по ней работает как обычно.
const POOL_RADIUS: float = 1.75 # радиус меша 3.5×3.5 / 2; форма-цилиндр 1.7
const POISON_TICK_INTERVAL: float = 1.0
const POISON_COLOR: Color = Color(0.12, 0.32, 0.04)
var poison_timer: float = 0.0
var _poison_tick_timer: float = 0.0
var _mesh: MeshInstance3D = null
var _blood_material: Material = null
var _poison_material: StandardMaterial3D = null

func _ready():
	set_physics_process(false)
	_mesh = get_node_or_null("MeshInstance3D")
	add_to_group("blood_pool")
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
	if _mesh:
		if not _poison_material:
			_blood_material = _mesh.get_surface_override_material(0)
			_poison_material = StandardMaterial3D.new()
			_poison_material.albedo_color = POISON_COLOR
			_poison_material.emission_enabled = true
			_poison_material.emission = POISON_COLOR
			_poison_material.emission_energy_multiplier = 0.6
		_mesh.set_surface_override_material(0, _poison_material)

func _physics_process(delta: float) -> void:
	if poison_timer <= 0.0:
		return
	poison_timer -= delta
	if poison_timer <= 0.0:
		set_physics_process(false)
		if _mesh and _blood_material:
			_mesh.set_surface_override_material(0, _blood_material)
		return
	_poison_tick_timer -= delta
	if _poison_tick_timer > 0.0:
		return
	_poison_tick_timer = POISON_TICK_INTERVAL
	for body in get_overlapping_bodies():
		if body.is_in_group("enemy") and body.has_method("apply_poison_dot"):
			body.apply_poison_dot(3.0, 3, 0.5)

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
