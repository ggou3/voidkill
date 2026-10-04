class_name SkillManager
extends Node

const MAX_DASH = 3
@export var dash_cd: float = 3.5 # Заметно увеличенное время восполнения заряда (было 1.5 сек)
@export var dash_min_interval: float = 0.5 # Минимальный интервал между последовательными дэшами
@export var dash_target_speed: float = 16.0 # Базовая целевая скорость рывка (от 10 м/с бега до 16 м/с)
@export var dash_boost: float = 5.0 # Добавочный импульс к скорости движения
const DASH_DUR = 0.15

const SLAM_SPEED = 60.0
const SLAM_AOE = 6.0
const SLAM_DMG = 10
const SLAM_CD = 4.0
# Слэм — контроль толпы: горизонтальный разброс волной, без подброса.
# Максимум строго ниже порога wall slam врагов (16 м/с), чтобы разброс не превращался в урон о стены.
const SLAM_KNOCKBACK_CENTER = 14.0
const SLAM_KNOCKBACK_EDGE = 6.0
# Расталкивание врагов под игроком во время падения (без урона)
const SLAM_DESCENT_PUSH_RADIUS = 1.6
const SLAM_DESCENT_PUSH_SPEED = 8.0
# Проход сквозь врагов во время падения: снимок врагов в этом горизонтальном радиусе на старте слэма
const SLAM_PASSTHROUGH_RADIUS = 3.0
const SLAM_PASSTHROUGH_TIMEOUT = 0.5

var dashes = MAX_DASH
var dash_timer_cd = 0.0
var dash_interval_timer = 0.0
var is_dashing = false
var dash_timer = 0.0
var dash_dir = Vector3.ZERO
var dash_current_speed: float = 16.0

var is_slamming = false
var slam_timer = 0.0
# Враги, с которыми на время слэма отключены столкновения (в обе стороны)
var slam_passthrough_bodies: Array[Node3D] = []
var slam_passthrough_timer: float = 0.0

signal dash_charges_changed(count: int)
signal hud_popup_requested(text: String)

@onready var player = $".."
@onready var head = $"../Head"
var blood_splatter_scene = preload("res://blood_splatter.tscn")

func _ready():
	dashes = MAX_DASH
	dash_timer_cd = 0.0
	dash_interval_timer = 0.0
	dash_current_speed = dash_target_speed

func _process(delta):
	# Восстановление зарядов дэша
	if dashes < MAX_DASH:
		dash_timer_cd -= delta
		if dash_timer_cd <= 0.0:
			dashes += 1
			dash_timer_cd = dash_cd if dashes < MAX_DASH else 0.0
			dash_charges_changed.emit(dashes)

	# Таймер минимального интервала между дэшами
	if dash_interval_timer > 0.0:
		dash_interval_timer -= delta
			
	if slam_timer > 0: slam_timer -= delta

func show_hud_popup(text: String):
	hud_popup_requested.emit(text)

func add_dash_charge():
	if dashes < MAX_DASH:
		dashes += 1
		if dashes == MAX_DASH:
			dash_timer_cd = 0.0
		dash_charges_changed.emit(dashes)

func trigger_dash(input_dir: Vector2, p_basis: Basis) -> bool:
	if dashes > 0 and not is_dashing and not is_slamming and dash_interval_timer <= 0.0:
		is_dashing = true
		dash_timer = DASH_DUR
		dash_interval_timer = dash_min_interval
		dashes -= 1
		dash_charges_changed.emit(dashes)
		if dash_timer_cd <= 0.0:
			dash_timer_cd = dash_cd
		
		if input_dir != Vector2.ZERO:
			dash_dir = (p_basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
		else:
			dash_dir = -p_basis.z
			
		# Вычисляем скорость рывка: всегда даёт заметное ускорение и никогда не замедляет
		var cur_h_vel = Vector2(player.velocity.x, player.velocity.z)
		var dash_dir_2d = Vector2(dash_dir.x, dash_dir.z).normalized()
		var forward_speed = cur_h_vel.dot(dash_dir_2d)
		var cur_speed = cur_h_vel.length()
		
		# Комбинация гарантированного минимума и добавочного импульса к текущей скорости
		var target_vel = max(dash_target_speed, max(forward_speed + dash_boost, cur_speed + 2.0))
		var max_cap = player.blood_buffed_max_speed if "blood_buffed_max_speed" in player else 20.0
		dash_current_speed = min(target_vel, max_cap)
		AudioManager.play_sound("dash")
		return true
	return false

func process_dash(delta, vel: Vector3) -> Vector3:
	if is_dashing:
		dash_timer -= delta
		if dash_timer <= 0: is_dashing = false
		var out_y = vel.y if vel.y > 0.0 else 0.0
		return Vector3(dash_dir.x * dash_current_speed, out_y, dash_dir.z * dash_current_speed)
	return vel

func trigger_slam():
	if not player.is_on_floor() and not is_slamming and slam_timer <= 0:
		is_slamming = true
		_begin_slam_passthrough()

## Прерывание слэма (смерть игрока): сброс состояния и немедленное снятие исключений столкновений
func cancel_slam() -> void:
	is_slamming = false
	_release_slam_passthrough(true)

func process_slam(delta, vel: Vector3) -> Vector3:
	_update_slam_passthrough(delta)
	if not is_slamming: return vel

	# Слэм всегда долетает до земли (сквозь врагов) и по пути расталкивает врагов под игроком
	_push_enemies_below()

	if player.is_on_floor():
		is_slamming = false
		vel.y = 0
		slam_timer = SLAM_CD
		slam_passthrough_timer = SLAM_PASSTHROUGH_TIMEOUT
		
		# Проверка наличия лужи крови в радиусе обычного слэма + 2 метра (8.0м) или нахождения на крови
		var search_radius: float = SLAM_AOE + 2.0
		var nearby_blood_pools = _find_nearby_blood_pools(player.global_position, search_radius)
		var has_blood_slam: bool = (nearby_blood_pools.size() > 0) or player.is_on_blood
		
		var effective_aoe: float = SLAM_AOE
		
		if has_blood_slam:
			effective_aoe = SLAM_AOE * 1.5 # 9.0 метров
			head.add_recoil(0.35, 0.0)
			AudioManager.play_sound("slam_impact")
			AudioManager.play_sound("flask_splash")
			
			# Временное расширение луж крови (масштаб x1.4 на 4.0 секунды)
			for pool in nearby_blood_pools:
				if pool is BloodPool:
					pool.expand_temporarily(1.4, 4.0)
					
			# Попап кровавого слэма (BPM не начисляется: слэм — контроль толпы)
			show_hud_popup("★ BLOOD SLAM ★")
			
			# Визуальный эффект расширяющейся волны крови
			_spawn_blood_slam_vfx(player.global_position, effective_aoe)
			GameTypes.debug_log(&"bpm", "[BLOOD SLAM] Enhanced shockwave! AOE: %.1fm, expanded %d blood pool(s)" % [
				effective_aoe, nearby_blood_pools.size()
			])
		else:
			head.add_recoil(0.25, 0.0)
			AudioManager.play_sound("slam_impact")
		
		# Волна: небольшой урон + горизонтальный разброс от центра (сильнее в центре, слабее на краю)
		var enemies = player.get_tree().get_nodes_in_group("enemy")
		for e in enemies:
			if is_instance_valid(e):
				var dist = player.global_position.distance_to(e.global_position)
				if dist <= effective_aoe:
					var t = clampf(dist / effective_aoe, 0.0, 1.0)
					var knock_speed = lerp(SLAM_KNOCKBACK_CENTER, SLAM_KNOCKBACK_EDGE, t)
					var knock_vec = _flat_dir_from_player(e) * knock_speed
					e.take_damage(SLAM_DMG, knock_vec, e.global_position, false, false, true, false, -1, "slam")

	if is_slamming:
		vel.y = -SLAM_SPEED
		vel.x = 0
		vel.z = 0
		
	return vel

## Горизонтальное направление от оси падения игрока к врагу
func _flat_dir_from_player(e: Node3D) -> Vector3:
	var flat = Vector3(e.global_position.x - player.global_position.x, 0.0, e.global_position.z - player.global_position.z)
	if flat.length_squared() > 0.0025:
		return flat.normalized()
	# Враг точно на оси падения — толкаем по направлению взгляда игрока
	var fwd = -player.transform.basis.z
	return Vector3(fwd.x, 0.0, fwd.z).normalized()

## Во время падения враги под игроком отъезжают в сторону от оси падения (без урона, без подброса).
## Скорость отброса доводится до SLAM_DESCENT_PUSH_SPEED, а не накапливается покадрово.
func _push_enemies_below() -> void:
	for e in player.get_tree().get_nodes_in_group("enemy"):
		if not is_instance_valid(e) or not (e is EnemyBase):
			continue
		if e.global_position.y > player.global_position.y + 0.5:
			continue
		var flat = Vector2(e.global_position.x - player.global_position.x, e.global_position.z - player.global_position.z)
		if flat.length() > SLAM_DESCENT_PUSH_RADIUS:
			continue
		var dir = _flat_dir_from_player(e)
		var outward = e.knockback_velocity.dot(dir)
		if outward < SLAM_DESCENT_PUSH_SPEED:
			e.apply_vacuum_pull(dir * (SLAM_DESCENT_PUSH_SPEED - outward))

## Снимок врагов в радиусе падения: на время слэма столкновения с ними отключены в обе стороны,
## чтобы игрок не вставал на голову врага и всегда долетал до земли.
func _begin_slam_passthrough() -> void:
	_release_slam_passthrough(true)
	for e in player.get_tree().get_nodes_in_group("enemy"):
		if not is_instance_valid(e) or not (e is PhysicsBody3D):
			continue
		var flat = Vector2(e.global_position.x - player.global_position.x, e.global_position.z - player.global_position.z)
		if flat.length() <= SLAM_PASSTHROUGH_RADIUS:
			player.add_collision_exception_with(e)
			e.add_collision_exception_with(player)
			slam_passthrough_bodies.append(e)

## После приземления: исключение снимается с врага, как только он вышел из капсулы игрока
## по горизонтали; по истечении SLAM_PASSTHROUGH_TIMEOUT — со всех оставшихся.
func _update_slam_passthrough(delta: float) -> void:
	if slam_passthrough_bodies.is_empty() or is_slamming:
		return
	slam_passthrough_timer -= delta
	_release_slam_passthrough(slam_passthrough_timer <= 0.0)

func _release_slam_passthrough(release_all: bool) -> void:
	var remaining: Array[Node3D] = []
	for e in slam_passthrough_bodies:
		if not is_instance_valid(e):
			continue
		if release_all or _is_outside_player_capsule(e):
			if is_instance_valid(player):
				player.remove_collision_exception_with(e)
				e.remove_collision_exception_with(player)
		else:
			remaining.append(e)
	slam_passthrough_bodies = remaining

func _is_outside_player_capsule(e: Node3D) -> bool:
	var flat = Vector2(e.global_position.x - player.global_position.x, e.global_position.z - player.global_position.z)
	return flat.length() > _body_radius(player) + _body_radius(e)

## Горизонтальный радиус тела по его CollisionShape3D (с учётом масштаба узла)
func _body_radius(body: Node3D) -> float:
	var cs = body.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if cs and cs.shape and "radius" in cs.shape:
		return cs.shape.radius * absf(cs.global_transform.basis.get_scale().x)
	return 0.5

func _find_nearby_blood_pools(impact_pos: Vector3, search_radius: float) -> Array[Node]:
	var blood_pools = player.get_tree().get_nodes_in_group("blood_pool")
	var found: Array[Node] = []
	for pool in blood_pools:
		if not is_instance_valid(pool) or not (pool is Node3D):
			continue
		var pool_pos = pool.global_position
		# Проверяем перепад высоты (допустимый перепад до 3.0м)
		if abs(impact_pos.y - pool_pos.y) <= 3.0:
			var horiz_dist = Vector2(impact_pos.x - pool_pos.x, impact_pos.z - pool_pos.z).length()
			# Радиус цилиндра лужи ~1.7м, учитываем его при проверке дистанции
			if horiz_dist <= (search_radius + 1.7):
				found.append(pool)
	return found

func _spawn_blood_slam_vfx(impact_pos: Vector3, radius: float):
	var scene_root = player.get_tree().current_scene if player.get_tree().current_scene else player.get_parent()
	if not scene_root:
		return
		
	var ground_y = impact_pos.y - 0.95
	var space_state = player.get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(impact_pos, impact_pos + Vector3.DOWN * 2.5)
	var result = space_state.intersect_ray(query)
	if result:
		ground_y = result.position.y + 0.05
		
	var center_pos = Vector3(impact_pos.x, ground_y, impact_pos.z)
	
	# 1. Радиальный разлёт брызг крови
	if blood_splatter_scene:
		var splatter = blood_splatter_scene.instantiate()
		splatter.amount = 85
		var pmat = splatter.process_material.duplicate()
		pmat.direction = Vector3.UP
		pmat.spread = 85.0
		pmat.initial_velocity_min = 10.0
		pmat.initial_velocity_max = 22.0
		pmat.scale_min = 0.35
		pmat.scale_max = 0.8
		splatter.process_material = pmat
		scene_root.add_child(splatter)
		splatter.global_position = center_pos + Vector3(0, 0.1, 0)
		
	# 2. Расширяющаяся тороидальная волна крови по полу
	var ring = MeshInstance3D.new()
	var tmesh = TorusMesh.new()
	tmesh.inner_radius = 0.88
	tmesh.outer_radius = 1.0
	tmesh.rings = 36
	tmesh.ring_segments = 12
	ring.mesh = tmesh
	
	var mat = StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = Color(0.9, 0.06, 0.06, 0.85)
	ring.material_override = mat
	
	scene_root.add_child(ring)
	ring.global_position = center_pos + Vector3(0, 0.04, 0)
	ring.scale = Vector3(0.5, 0.2, 0.5)
	
	var tween = ring.create_tween().set_parallel(true)
	tween.tween_property(ring, "scale", Vector3(radius, 0.2, radius), 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(mat, "albedo_color:a", 0.0, 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(ring.queue_free)
	
	# 3. Кратковременная алая вспышка освещения
	var light = OmniLight3D.new()
	light.light_color = Color(1.0, 0.1, 0.05)
	light.light_energy = 4.0
	light.omni_range = radius
	scene_root.add_child(light)
	light.global_position = center_pos + Vector3(0, 0.5, 0)
	var ltween = light.create_tween()
	ltween.tween_property(light, "light_energy", 0.0, 0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	ltween.tween_callback(light.queue_free)
