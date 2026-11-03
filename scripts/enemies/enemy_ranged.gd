class_name EnemyRanged
extends EnemyGround

@export var projectile_scene: PackedScene = preload("res://projectile_enemy.tscn")
@export var preferred_distance_min: float = 10.0
@export var preferred_distance_max: float = 15.0
@export var projectile_speed: float = 18.0
@export var ranged_damage: int = 12
@export var ranged_attack_cooldown: float = 2.8
## Радиус обнаружения (бывшая сфера DetectionArea 30 м; турель переопределяет своим)
@export var ranged_detection_range: float = 30.0

@export var attack_damage: int = 12
@export var attack_range: float = 0.0
@export var attack_cooldown: float = 2.8

var attack_timer: float = 0.0

const EYES_BASE_COLOR = Color(0.85, 0.2, 1.0)
const EYES_TELEGRAPH_COLOR = Color(1.0, 0.85, 0.2)

var is_telegraphing_shot: bool = false
# Стрейф на позиции стрельбы: сторона (±1) и время до возможной смены
const STRAFE_SPEED_FACTOR: float = 0.45
## Упреждение выстрела (ноябрь 2026): доля полного упреждения по скорости игрока — случайная в этих пределах,
## время полёта для расчёта не больше AIM_LEAD_MAX_TIME (на дальней дистанции не стреляет далеко вперёд)
const AIM_LEAD_MIN: float = 0.3
const AIM_LEAD_MAX: float = 0.55
const AIM_LEAD_MAX_TIME: float = 0.8
var _strafe_side: float = 1.0
var _strafe_timer: float = 0.0
# Пауза проверки края после разворота: в узком проходе оба края рядом, разворот каждый тик — дрожь на месте
const STRAFE_EDGE_RECHECK: float = 0.3
var _strafe_edge_timer: float = 0.0
var antenna_material: StandardMaterial3D = null
@onready var antenna_tip: MeshInstance3D = get_node_or_null("AntennaTip")

var telegraph_tween_eyes: Tween = null
var telegraph_tween_antenna: Tween = null
var attack_flash_tween_eyes: Tween = null
var attack_flash_tween_antenna: Tween = null

## Модель (models/enemy_ranged/enemy_ranged.glb): скелет с клипами, обрез на кости gun, глаза и вспышка —
## на костях eyes и muzzle (BoneAttachment3D в сцене). У турели (наследник со своей сценой) модели нет —
## всё, что завязано на модель, молчит
@onready var model_root: Node3D = get_node_or_null("Model")
@onready var anim_player: AnimationPlayer = get_node_or_null("Model/AnimationPlayer")
@onready var muzzle_flash: MeshInstance3D = get_node_or_null("MuzzleAttach/MuzzleFlash")
const MUZZLE_FLASH_TIME: float = 0.06
## Дуло в прицельной стойке модели масштаба 1.25: x — вправо, y — вверх, z — вперёд (было (0, 0.55, 0.4) —
## точка у лица капсулы)
const MUZZLE_OFFSET: Vector3 = Vector3(0.13, 0.65, 1.29)
## Высота отладочной полоски HP над моделью (макушка ~1.28)
const MODEL_HEALTH_BAR_HEIGHT: float = 1.5
## Клипы-циклы; остальные (telegraph, fire, hit, death) играют один раз
const ANIM_LOOPED: Array[StringName] = [&"idle", &"aim", &"run", &"strafe_left", &"strafe_right", &"back"]
const ANIM_BLEND: float = 0.12
## Скорость движения, ниже которой враг стоит (клип стойки)
const ANIM_MOVE_THRESHOLD: float = 0.6
## Скорость (м/с), при которой цикл бега / шага вбок играет в своём темпе; темп ограничен, на большой
## скорости ноги проскальзывают
const ANIM_RUN_SPEED: float = 4.0
const ANIM_STEP_SPEED: float = 2.5
const HIT_ANIM_RESTART: float = 0.15
var _anim_current: StringName = &""
## Пока играет выстрел или вздрагивание от урона, клип по движению его не перебивает
var _anim_oneshot_timer: float = 0.0
var _muzzle_flash_tween: Tween = null

func _ready() -> void:
	_setup_model()
	super._ready()
	detection_range = ranged_detection_range
	attack_damage = ranged_damage
	attack_cooldown = ranged_attack_cooldown
	attack_range = 0.0
	lunge_cooldown_timer = 999999.0
	attack_timer = randf_range(0.6, 1.8)
	
	if antenna_tip:
		var tip_mat = antenna_tip.get_surface_override_material(0)
		if tip_mat:
			antenna_material = tip_mat.duplicate()
			antenna_tip.set_surface_override_material(0, antenna_material)
	
	if eyes_material:
		eyes_material.emission = EYES_BASE_COLOR
	if antenna_material:
		antenna_material.emission = EYES_BASE_COLOR

## Тело и глаза модели вместо узлов по умолчанию (MeshInstance3D, Eyes) — до super._ready: там копируется
## материал глаз и собираются меши вспышки попадания. Текстуры модели — исходные, из Tripo. Копия материала
## тела ставится override-ом: иглы и раздутие копируют его через _make_body_override_mat (с текстурой)
func _setup_model() -> void:
	if not model_root:
		return
	var model_eyes := get_node_or_null("EyesAttach/Eyes") as MeshInstance3D
	if model_eyes:
		eyes = model_eyes
	var model_body := model_root.find_child("Body", true, false) as MeshInstance3D
	if model_body:
		body_mesh = model_body
		var src_mat := model_body.get_active_material(0) as StandardMaterial3D
		if src_mat:
			model_body.set_surface_override_material(0, src_mat.duplicate())
	if anim_player:
		for anim_name in ANIM_LOOPED:
			var anim: Animation = anim_player.get_animation(anim_name)
			if anim:
				anim.loop_mode = Animation.LOOP_LINEAR
		_play_anim(&"idle")

## Полоска HP над макушкой модели; без модели (турель) — как у всех
func _setup_health_bar() -> void:
	if not model_root:
		super._setup_health_bar()
		return
	_ensure_health_bar().setup(
		health,
		max_health,
		MODEL_HEALTH_BAR_HEIGHT,
		Color(0.95, 0.15, 0.15, 1.0),
		Color(1.0, 0.9, 0.9),
		health_component
	)

func _play_anim(anim_name: StringName, restart: bool = false) -> void:
	if anim_name == _anim_current and not restart:
		return
	_anim_current = anim_name
	anim_player.play(anim_name, ANIM_BLEND)
	if restart:
		anim_player.seek(0.0, true)

func _play_oneshot_anim(anim_name: StringName) -> void:
	if not anim_player or current_state == State.DEAD:
		return
	var anim: Animation = anim_player.get_animation(anim_name)
	if not anim:
		return
	anim_player.speed_scale = 1.0
	_play_anim(anim_name, true)
	_anim_oneshot_timer = anim.length

## Клип по состоянию и скорости: заряд выстрела — telegraph; в ATTACK стрейф/отход/стойка с прицелом по
## направлению скорости в осях врага (он смотрит на игрока); иначе бег или стойка с опущенным обрезом
func _update_animation(delta: float) -> void:
	if not anim_player:
		return
	if _anim_oneshot_timer > 0.0:
		_anim_oneshot_timer -= delta
		return
	var flat_vel := Vector3(velocity.x, 0.0, velocity.z)
	var speed := flat_vel.length()
	var local_vel: Vector3 = global_transform.basis.inverse() * flat_vel
	var anim_speed: float = 1.0
	var anim_name: StringName = &"idle"
	if is_telegraphing_shot:
		anim_name = &"telegraph"
	elif speed > ANIM_MOVE_THRESHOLD:
		if current_state == State.ATTACK and absf(local_vel.x) > absf(local_vel.z):
			anim_name = &"strafe_right" if local_vel.x > 0.0 else &"strafe_left"
			anim_speed = clampf(speed / ANIM_STEP_SPEED, 0.8, 2.0)
		elif current_state == State.ATTACK and local_vel.z > 0.0:
			anim_name = &"back"
			anim_speed = clampf(speed / ANIM_STEP_SPEED, 0.8, 2.0)
		else:
			anim_name = &"run"
			anim_speed = clampf(speed / ANIM_RUN_SPEED, 0.6, 2.2)
	elif current_state == State.ATTACK:
		anim_name = &"aim"
	anim_player.speed_scale = anim_speed
	_play_anim(anim_name)

func _can_lunge_to_player() -> bool:
	return false

func start_lunge() -> void:
	pass

func _physics_process(delta: float) -> void:
	if attack_timer > 0.0:
		attack_timer -= delta
	super._physics_process(delta)
	if current_state != State.DEAD:
		_update_animation(delta)

func set_state(new_state: State) -> void:
	if new_state == State.DEAD:
		_reset_ranged_telegraph()
		attack_timer = 999999.0
	elif current_state == State.ATTACK and new_state != State.ATTACK:
		_reset_ranged_telegraph()
	super.set_state(new_state)

func take_damage(amount: int, knockback_vector: Vector3, hit_pos: Vector3, is_melee: bool = false, is_execute: bool = false, is_shockwave: bool = false, is_headshot: bool = false, source_chain_depth: int = -1, weapon_source: String = "") -> void:
	if current_state == State.DEAD:
		return
	attack_timer = max(attack_timer, reaction_delay)
	super.take_damage(amount, knockback_vector, hit_pos, is_melee, is_execute, is_shockwave, is_headshot, source_chain_depth, weapon_source)
	# Вздрагивание; дробь бьёт несколькими попаданиями в кадр — клип не перезапускается чаще раза в HIT_ANIM_RESTART
	if anim_player and (_anim_current != &"hit" or anim_player.current_animation_position >= HIT_ANIM_RESTART):
		_play_oneshot_anim(&"hit")

func die(death_info: Dictionary = {}) -> void:
	_reset_ranged_telegraph()
	if attack_flash_tween_eyes and attack_flash_tween_eyes.is_valid():
		attack_flash_tween_eyes.kill()
	if attack_flash_tween_antenna and attack_flash_tween_antenna.is_valid():
		attack_flash_tween_antenna.kill()
	if _muzzle_flash_tween and _muzzle_flash_tween.is_valid():
		_muzzle_flash_tween.kill()
	attack_timer = 999999.0
	super.die(death_info)

func _process_chase(delta: float) -> void:
	if not is_instance_valid(target_player) or ("is_dead" in target_player and target_player.is_dead):
		set_state(State.IDLE)
		return
		
	var dist_to_player = global_position.distance_to(target_player.global_position)
	
	# Переход в режим дальней атаки (ATTACK), если игрок в радиусе 10-15м И есть прямая видимость
	if dist_to_player <= preferred_distance_max and _has_line_of_sight_to(target_player):
		set_state(State.ATTACK)
		return
		
	# Иначе продолжаем обычное сближение и навигацию по NavMesh
	super._process_chase(delta)

func _process_attack(delta: float) -> void:
	if not is_inside_tree() or current_state == State.DEAD:
		return
	if not is_instance_valid(target_player) or ("is_dead" in target_player and target_player.is_dead):
		set_state(State.IDLE)
		return
		
	var dist_to_player = global_position.distance_to(target_player.global_position)
	
	# Если игрок ушел слишком далеко или скрылся за стеной/препятствием — возвращаемся в CHASE
	if dist_to_player > (preferred_distance_max + 1.5) or not _has_line_of_sight_to(target_player):
		_reset_ranged_telegraph()
		set_state(State.CHASE)
		return
		
	# Плавный поворот к игроку при прицеливании
	var to_player = target_player.global_position - global_position
	to_player.y = 0.0
	if to_player.length_squared() > 0.01:
		var target_angle = atan2(-to_player.x, -to_player.z)
		var angle_diff = abs(wrapf(target_angle - rotation.y, -PI, PI))
		if angle_diff > 0.08:
			rotation.y = lerp_angle(rotation.y, target_angle, min(1.0, rotation_speed * delta))
			
	# Удержание дистанции (10-15 метров):
	# Если игрок сближается ближе 10м — плавно отступаем назад, сохраняя прямую видимость и прицел
	if dist_to_player < preferred_distance_min and wall_slam_timer <= 0.0:
		var away_dir = (global_position - target_player.global_position)
		away_dir.y = 0.0
		if away_dir.length_squared() > 0.01:
			var retreat_vel = away_dir.normalized() * (move_speed * 0.6 * slow_factor)
			# Скорость напрямую, как в стрейфе: _apply_movement разворачивал врага по движению, а поворот выше —
			# к игроку; два разворота боролись, и дальник убегал боком
			velocity.x = lerp(velocity.x, retreat_vel.x + knockback_velocity.x, min(1.0, acceleration * delta))
			velocity.z = lerp(velocity.z, retreat_vel.z + knockback_velocity.z, min(1.0, acceleration * delta))
	elif is_telegraphing_shot or wall_slam_timer > 0.0:
		# Заряд выстрела — стоит на месте, чтобы выстрел читался
		velocity.x = lerp(velocity.x, knockback_velocity.x, 10.0 * delta)
		velocity.z = lerp(velocity.z, knockback_velocity.z, 10.0 * delta)
	else:
		# На дистанции 10-15м — стрейф вбок (раньше стоял столбом): сторона меняется раз в 1.5–3 с
		# и на краю навмеша, скорость — STRAFE_SPEED_FACTOR от скорости бега. Скорость задаётся напрямую, без
		# _apply_movement: тот разворачивает врага по движению, а дальник должен смотреть на игрока
		var strafe_vel: Vector3 = _get_strafe_velocity(delta)
		velocity.x = lerp(velocity.x, strafe_vel.x + knockback_velocity.x, min(1.0, acceleration * delta))
		velocity.z = lerp(velocity.z, strafe_vel.z + knockback_velocity.z, min(1.0, acceleration * delta))
		
	# Визуальный телеграф перед выстрелом (за 0.35с до конца кулдауна глаза загораются золотым цветом)
	if attack_timer <= 0.35 and hit_reaction_timer <= 0.0 and not is_telegraphing_shot:
		if is_inside_tree() and current_state == State.ATTACK:
			# Токен атаки на телеграф + выстрел; пул занят — выстрел откладывается
			if GameManager.request_attack_token(&"ranged", 0.7):
				_start_ranged_telegraph()
			else:
				attack_timer = 0.35 + randf_range(0.3, 0.7)
	elif attack_timer > 0.35 and is_telegraphing_shot:
		_reset_ranged_telegraph()

	# Выстрел по завершении кулдауна (2.5-3.0с) — только после телеграфа: если телеграф не начался
	# (реакция на урон, нет токена), сначала полный телеграф
	if attack_timer <= 0.0 and hit_reaction_timer <= 0.0:
		if is_inside_tree() and current_state == State.ATTACK:
			if not is_telegraphing_shot:
				attack_timer = 0.36
				return
			perform_attack()
		attack_timer = attack_cooldown

func _get_strafe_velocity(delta: float) -> Vector3:
	_strafe_timer -= delta
	if _strafe_timer <= 0.0:
		_strafe_timer = randf_range(1.5, 3.0)
		_strafe_side = -_strafe_side if randf() < 0.7 else _strafe_side
	var to_player: Vector3 = target_player.global_position - global_position
	to_player.y = 0.0
	if to_player.length_squared() < 0.01:
		return Vector3.ZERO
	var strafe_dir: Vector3 = to_player.normalized().cross(Vector3.UP) * _strafe_side
	# Край навмеша (уступ, стена) впереди по стрейфу — разворот. Сравнение по горизонтали: центр тела
	# выше навмеша на ~1 м, и полная 3D-дистанция до ближайшей точки была больше порога всегда
	_strafe_edge_timer -= delta
	if nav_agent and _strafe_edge_timer <= 0.0:
		var map: RID = nav_agent.get_navigation_map()
		if NavigationServer3D.map_get_iteration_id(map) > 0:
			var ahead: Vector3 = global_position + strafe_dir * 1.5
			var ahead_on_mesh: Vector3 = NavigationServer3D.map_get_closest_point(map, ahead)
			var off_mesh: Vector3 = ahead_on_mesh - ahead
			off_mesh.y = 0.0
			# Перепад до точки впереди — уступ (ближайшей оказалась точка другого яруса); пандусы до ~33° проходят
			var drop: float = absf(ahead_on_mesh.y - NavigationServer3D.map_get_closest_point(map, global_position).y)
			if off_mesh.length() > 0.6 or drop > 1.0:
				_strafe_side = -_strafe_side
				strafe_dir = -strafe_dir
				_strafe_edge_timer = STRAFE_EDGE_RECHECK
	return strafe_dir * (move_speed * STRAFE_SPEED_FACTOR * slow_factor)

## Дуло обреза в прицельной стойке (клипы aim/telegraph): вправо, вверх и вперёд от центра врага.
## Константа, а не позиция кости: точка выстрела не зависит от того, в какой фазе смешивания клипы
func _get_projectile_spawn_position() -> Vector3:
	return global_position + Vector3(0.0, MUZZLE_OFFSET.y, 0.0) + transform.basis.x * MUZZLE_OFFSET.x - transform.basis.z * MUZZLE_OFFSET.z

func _play_attack_flash() -> void:
	_play_oneshot_anim(&"fire")
	if muzzle_flash:
		muzzle_flash.visible = true
		if _muzzle_flash_tween and _muzzle_flash_tween.is_valid():
			_muzzle_flash_tween.kill()
		_muzzle_flash_tween = create_tween()
		_muzzle_flash_tween.tween_interval(MUZZLE_FLASH_TIME)
		_muzzle_flash_tween.tween_callback(muzzle_flash.hide)
	if eyes_material:
		if attack_flash_tween_eyes and attack_flash_tween_eyes.is_valid():
			attack_flash_tween_eyes.kill()
		eyes_material.emission = Color(1.0, 0.4, 0.1)
		attack_flash_tween_eyes = create_tween()
		attack_flash_tween_eyes.tween_property(eyes_material, "emission", EYES_BASE_COLOR, 0.3)
	if antenna_material:
		if attack_flash_tween_antenna and attack_flash_tween_antenna.is_valid():
			attack_flash_tween_antenna.kill()
		antenna_material.emission = Color(1.0, 0.4, 0.1)
		attack_flash_tween_antenna = create_tween()
		attack_flash_tween_antenna.tween_property(antenna_material, "emission", EYES_BASE_COLOR, 0.3)

func perform_attack() -> void:
	if not is_inside_tree() or current_state == State.DEAD:
		return
	_reset_ranged_telegraph()
	if not is_instance_valid(target_player):
		return
		
	_play_attack_flash()
		
	if not projectile_scene:
		return
		
	var scene_root = get_tree().current_scene if (get_tree() and get_tree().current_scene) else get_parent()
	if not scene_root:
		return
		
	var spawn_pos = _get_projectile_spawn_position()
	
	# Точка прицеливания: корпус игрока плюс частичное упреждение по его горизонтальной скорости (прямая
	# траектория, без самонаведения). Доля упреждения случайная и меньше полной — стоящего игрока бьёт точно,
	# бегущего «почти»: смена направления и рывок по-прежнему уводят из-под выстрела
	var target_pos = target_player.global_position + Vector3(0.0, 0.2, 0.0)
	if "velocity" in target_player and projectile_speed > 0.0:
		var flight_time: float = minf(spawn_pos.distance_to(target_pos) / projectile_speed, AIM_LEAD_MAX_TIME)
		var target_vel: Vector3 = target_player.velocity
		target_pos += Vector3(target_vel.x, 0.0, target_vel.z) * flight_time * randf_range(AIM_LEAD_MIN, AIM_LEAD_MAX)
	var fly_dir = (target_pos - spawn_pos).normalized()
	
	var proj = projectile_scene.instantiate()
	proj.direction = fly_dir
	proj.speed = projectile_speed
	proj.damage = attack_damage
	proj.shooter = self
	
	scene_root.add_child(proj)
	proj.global_position = spawn_pos
		
	AudioManager.play_sound_at("ranged_shot", spawn_pos)
	GameTypes.debug_log(&"enemy", "[%s] RANGED ATTACK: fired projectile at %s (dir: %s, speed: %.1f, dmg: %d)" % [
		name, target_player.name, fly_dir, projectile_speed, attack_damage
	])

func _start_ranged_telegraph() -> void:
	if not is_inside_tree() or current_state == State.DEAD:
		return
	is_telegraphing_shot = true
	AudioManager.play_sound_at("ranged_windup", global_position)
	if eyes_material:
		if telegraph_tween_eyes and telegraph_tween_eyes.is_valid():
			telegraph_tween_eyes.kill()
		telegraph_tween_eyes = create_tween()
		telegraph_tween_eyes.tween_property(eyes_material, "emission", EYES_TELEGRAPH_COLOR, 0.18)
	if antenna_material:
		if telegraph_tween_antenna and telegraph_tween_antenna.is_valid():
			telegraph_tween_antenna.kill()
		telegraph_tween_antenna = create_tween()
		telegraph_tween_antenna.tween_property(antenna_material, "emission", EYES_TELEGRAPH_COLOR, 0.18)

func _reset_ranged_telegraph() -> void:
	if telegraph_tween_eyes and telegraph_tween_eyes.is_valid():
		telegraph_tween_eyes.kill()
	if telegraph_tween_antenna and telegraph_tween_antenna.is_valid():
		telegraph_tween_antenna.kill()
	if not is_telegraphing_shot:
		return
	is_telegraphing_shot = false
	if eyes_material:
		eyes_material.emission = EYES_BASE_COLOR
	if antenna_material:
		antenna_material.emission = EYES_BASE_COLOR
