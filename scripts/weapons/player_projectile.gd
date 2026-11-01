class_name PlayerProjectile
extends Node3D

## Физический снаряд игрока (дробь, иглы, шприцы). Летит с постоянной скоростью (по желанию — с гравитацией)
## и каждый физический тик проверяет пройденный отрезок лучом: ни на какой скорости не пролетает сквозь стену
## или врага. Попадание отдаётся оружию (WeaponBase.on_projectile_hit), урон считается по общим правилам
## (WeaponBase._deal_hit: хедшот, цель в воздухе, отброс, синергии). Живёт в пуле WeaponManager и не удаляется.
##
## Траектория идёт от камеры (выстрел точно в прицел), а видимая модель вылетает из дула и за
## VISUAL_CATCHUP_TIME сходится с траекторией.

const VISUAL_CATCHUP_TIME: float = 0.08
const MAX_AREA_SKIPS: int = 4 # сколько посторонних Area3D (зоны секторов, выход) луч обходит за тик
const HOMING_ARRIVE_DIST: float = 0.35 # м до цели самонаведения — «долетел» (или ближе шага за тик)

## FLY — летит по прямой; STUCK — застрял (в стене или во враге и движется с ним, stick);
## HOMING — летит к цели, поворачивая каждый тик (home_to), по прибытии — WeaponBase.on_projectile_homed
enum Mode { FLY, STUCK, HOMING }
var mode: Mode = Mode.FLY

var weapon: WeaponBase = null
var velocity: Vector3 = Vector3.ZERO
var gravity: float = 0.0
var is_alt: bool = false
var active: bool = false
var style: StringName = &""
## Произвольные данные оружия о снаряде (например, нить у игл Швейной)
var payload: Dictionary = {}

var _life: float = 0.0
var _collision_mask: int = 1
var _exclude: Array[RID] = []
var _visual_offset: Vector3 = Vector3.ZERO
var _visual_catchup_speed: float = 0.0
var _mesh_basis: Basis = Basis.IDENTITY
var _mesh: MeshInstance3D = null
## Радиус попадания по врагам (0 — только луч): кроме луча по пути, сфера этого радиуса ищет врага/голову —
## попасть немного легче. Стены сфера не задевает, поэтому снаряд не цепляется за углы
var _hit_radius: float = 0.0
var _hit_shape: SphereShape3D = null
var _host: Node3D = null
var _host_local: Transform3D = Transform3D.IDENTITY
var _homing_target: Node3D = null
var _homing_speed: float = 0.0
var _homing_offset: Vector3 = Vector3.ZERO

func _init() -> void:
	_mesh = MeshInstance3D.new()
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mesh)

func _ready() -> void:
	# Летит в физическом тике — интерполируется (урок «Интерполяция физики — только по выбору…»)
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_ON
	if not active:
		visible = false
		set_physics_process(false)

## Запуск из пула. origin — точка камеры, muzzle_pos — дуло (только для визуала), mesh_stretch — вытяжка
## модели вдоль полёта (след скорости), exclude — что луч не задевает (игрок)
func launch(p_weapon: WeaponBase, origin: Vector3, p_velocity: Vector3, muzzle_pos: Vector3, p_style: StringName,
		mesh: Mesh, material: Material, mesh_stretch: float, lifetime: float, p_is_alt: bool,
		exclude: Array[RID], collision_mask: int, p_gravity: float = 0.0, hit_radius: float = 0.0) -> void:
	weapon = p_weapon
	_hit_radius = hit_radius
	if hit_radius > 0.0:
		if not _hit_shape:
			_hit_shape = SphereShape3D.new()
		_hit_shape.radius = hit_radius
	mode = Mode.FLY
	_host = null
	_homing_target = null
	velocity = p_velocity
	gravity = p_gravity
	is_alt = p_is_alt
	style = p_style
	payload = {}
	_life = lifetime
	_exclude = exclude.duplicate()
	_collision_mask = collision_mask
	global_position = origin
	_orient()
	_visual_offset = muzzle_pos - origin
	_visual_catchup_speed = _visual_offset.length() / VISUAL_CATCHUP_TIME
	_mesh.mesh = mesh
	_mesh.material_override = material
	# Цилиндр/капсула вытянуты по Y — поворачиваем вдоль полёта (-Z) и растягиваем по длине
	_mesh_basis = Basis(Vector3.RIGHT, PI * 0.5) * Basis.from_scale(Vector3(1.0, mesh_stretch, 1.0))
	_update_mesh()
	reset_physics_interpolation()
	active = true
	visible = true
	set_physics_process(true)

func deactivate() -> void:
	active = false
	visible = false
	weapon = null
	payload = {}
	mode = Mode.FLY
	_host = null
	_homing_target = null
	set_physics_process(false)

## Застрять в точке hit_pos: в стене (host = null) или во враге (двигается вместе с ним, пока тот жив).
## Через lifetime исчезает; враг умер или исчез — тоже
func stick(host: Node3D, hit_pos: Vector3, lifetime: float) -> void:
	mode = Mode.STUCK
	_life = lifetime
	global_position = hit_pos
	_visual_offset = Vector3.ZERO
	_update_mesh()
	_host = host
	if is_instance_valid(host):
		_host_local = host.global_transform.affine_inverse() * global_transform

func is_stuck() -> bool:
	return active and mode == Mode.STUCK

## Хозяин застрявшего снаряда (враг) или null (стена)
func get_host() -> Node3D:
	return _host if is_instance_valid(_host) else null

## Лететь к точке target + offset со скоростью speed, доворачивая каждый тик (возврат игл в дуло). Луч по
## пути по-прежнему отдаёт попадания оружию (вернуть true — прошить насквозь)
func home_to(target: Node3D, speed: float, lifetime: float, offset: Vector3 = Vector3.ZERO) -> void:
	mode = Mode.HOMING
	_host = null
	_homing_target = target
	_homing_offset = offset
	_homing_speed = speed
	_life = lifetime
	_visual_offset = Vector3.ZERO
	velocity = (_homing_point() - global_position).normalized() * speed
	_orient()
	_update_mesh()

func _homing_point() -> Vector3:
	return _homing_target.global_position + _homing_offset if is_instance_valid(_homing_target) else global_position

## Не задевать этот объект дальше (снаряд прошил врага насквозь)
func add_exclude(rid: RID) -> void:
	_exclude.append(rid)

func _physics_process(delta: float) -> void:
	if not active:
		return
	_life -= delta
	if _life <= 0.0:
		deactivate()
		return
	if mode == Mode.STUCK:
		_follow_host()
		return
	if mode == Mode.HOMING:
		if not is_instance_valid(_homing_target):
			deactivate()
			return
		var to_target: Vector3 = _homing_point() - global_position
		if to_target.length() <= maxf(HOMING_ARRIVE_DIST, _homing_speed * delta):
			var w: WeaponBase = weapon
			deactivate()
			if is_instance_valid(w):
				w.on_projectile_homed(self)
			return
		velocity = to_target.normalized() * _homing_speed
		_orient()
	else:
		velocity.y -= gravity * delta
	var from: Vector3 = global_position
	var to: Vector3 = from + velocity * delta
	var hit: Dictionary = _sweep(from, to)
	if not hit.is_empty():
		var keep_flying: bool = is_instance_valid(weapon) and weapon.on_projectile_hit(self, hit)
		# Оружие могло погасить снаряд или перевести его в другой режим (застрял)
		if not active or mode == Mode.STUCK:
			return
		if not keep_flying:
			global_position = hit.position
			deactivate()
			return
		# Прошил насквозь: дальше без этого объекта, с точки попадания
		add_exclude(hit.rid)
		to = hit.position + velocity.normalized() * 0.05
	global_position = to
	if gravity > 0.0:
		_orient()
	_visual_offset = _visual_offset.move_toward(Vector3.ZERO, _visual_catchup_speed * delta)
	_update_mesh()

func _follow_host() -> void:
	if _host == null:
		return
	var host_alive: bool = is_instance_valid(_host) and _host.is_inside_tree() \
			and not ("health" in _host and _host.health <= 0)
	if not host_alive:
		deactivate()
		return
	global_transform = _host.global_transform * _host_local

## Луч по отрезку пути: тела и хитбоксы голов; прочие Area3D (зоны секторов, выход уровня) пропускаются
func _sweep(from: Vector3, to: Vector3) -> Dictionary:
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	if not space:
		return {}
	var query := PhysicsRayQueryParameters3D.create(from, to, _collision_mask)
	query.collide_with_areas = true
	query.collide_with_bodies = true
	var exclude: Array[RID] = _exclude.duplicate()
	query.exclude = exclude
	for i in range(MAX_AREA_SKIPS + 1):
		var hit: Dictionary = space.intersect_ray(query)
		if hit.is_empty():
			return {}
		var collider: Object = hit.collider
		if collider is Area3D and not _is_enemy_collider(collider):
			exclude.append(hit.rid)
			query.exclude = exclude
			continue
		return _with_radius(space, from, to, hit)
	return _with_radius(space, from, to, {})

func _is_enemy_collider(collider: Object) -> bool:
	if collider is Area3D:
		return collider.is_in_group("enemy_head") or collider.name == "HeadHitbox"
	return collider is Node and GameTypes.resolve_enemy(collider) != null

## Луч не попал во врага (мимо или в стену) — сфера _hit_radius ищет врага на пути до точки луча
func _with_radius(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3, ray_hit: Dictionary) -> Dictionary:
	if _hit_radius <= 0.0 or (not ray_hit.is_empty() and _is_enemy_collider(ray_hit.collider)):
		return ray_hit
	var max_dist: float = from.distance_to(ray_hit.position) if not ray_hit.is_empty() else from.distance_to(to)
	var motion: Vector3 = to - from
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = _hit_shape
	params.collision_mask = _collision_mask
	params.collide_with_areas = true
	params.collide_with_bodies = true
	var exclude: Array[RID] = _exclude.duplicate()
	for i in range(MAX_AREA_SKIPS + 1):
		params.exclude = exclude
		params.transform = Transform3D(Basis.IDENTITY, from)
		params.motion = motion
		var fractions: PackedFloat32Array = space.cast_motion(params)
		if fractions.size() < 2 or fractions[1] >= 1.0:
			return ray_hit
		var contact_pos: Vector3 = from + motion * fractions[1]
		if from.distance_to(contact_pos) > max_dist:
			return ray_hit
		params.transform = Transform3D(Basis.IDENTITY, contact_pos)
		params.motion = Vector3.ZERO
		var info: Dictionary = space.get_rest_info(params)
		if info.is_empty():
			return ray_hit
		var collider: Object = instance_from_id(info.collider_id)
		if collider and _is_enemy_collider(collider):
			return {"collider": collider, "position": info.point, "rid": info.rid, "normal": info.normal}
		# Стена или посторонняя область — не цель сферы, ищем дальше без неё
		exclude.append(info.rid)
	return ray_hit

func _orient() -> void:
	if velocity.length_squared() < 0.0001:
		return
	var dir: Vector3 = velocity.normalized()
	var up: Vector3 = Vector3.UP if absf(dir.y) < 0.99 else Vector3.FORWARD
	look_at(global_position + dir, up)

func _update_mesh() -> void:
	# Смещение визуала к дулу — в мировых координатах, переводим в локальные снаряда
	_mesh.transform = Transform3D(_mesh_basis, global_transform.basis.inverse() * _visual_offset)
