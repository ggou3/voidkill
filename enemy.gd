class_name Enemy
extends CharacterBody3D

enum State {
	IDLE,
	CHASE,
	ATTACK,
	LUNGE,
	FLEE,
	DEAD
}

@export var max_health: int = 100
@export var move_speed: float = 11.5
@export var acceleration: float = 6.2
@export var attack_damage: int = 15
@export var attack_range: float = 2.0
@export var attack_cooldown: float = 1.0
@export var detection_range: float = 25.0
@export var rotation_speed: float = 6.0
@export var avoidance_enabled: bool = false
@export var avoidance_deadzone: float = 0.5
@export var wall_slam_threshold: float = 16.0
@export var wall_slam_damage_multiplier: float = 3.5
@export var wall_slam_max_damage: float = 55.0
@export var reaction_delay: float = 0.4
@export var lunge_min_range: float = 5.0
@export var lunge_max_range: float = 8.5
@export var lunge_speed: float = 25.0
@export var lunge_damage: int = 20
@export var lunge_telegraph_time: float = 0.38
@export var lunge_dash_time: float = 0.30
@export var lunge_cooldown: float = 4.5

var current_state: State = State.IDLE
var health: int = 100
var gravity = ProjectSettings.get_setting("physics/3d/default_gravity")
var knockback_velocity: Vector3 = Vector3.ZERO
var target_player: Node3D = null
var attack_timer: float = 0.0
var hit_reaction_timer: float = 0.0
var wall_slam_timer: float = 0.0
var pre_move_velocity: Vector3 = Vector3.ZERO
var path_update_timer: float = 0.0
const PATH_UPDATE_INTERVAL: float = 0.35
var debug_diag_timer: float = 0.0
var current_target_vel: Vector3 = Vector3.ZERO
var unreachable_timer: float = 0.0
const UNREACHABLE_TIMEOUT: float = 3.5
var repath_cooldown_timer: float = 0.0
const REPATH_COOLDOWN: float = 2.0

var is_jumping_link: bool = false
var jump_grace_timer: float = 0.0
var jump_timeout: float = 0.0

var lunge_cooldown_timer: float = 0.0
var lunge_timer: float = 0.0
var lunge_dir: Vector3 = Vector3.ZERO
var lunge_phase: int = 0
var lunge_has_hit: bool = false
var lunge_start_pos: Vector3 = Vector3.ZERO
var lunge_target_distance: float = 5.5

var fear_check_timer: float = 0.0
var flee_timer: float = 0.0

var is_inflated: bool = false
var was_killed_by_melee: bool = false
var was_killed_by_shockwave: bool = false
var last_damage_weapon: String = ""
var last_headshot_bonus_frame: int = -1
var explosion_chain_depth: int = 0
var slam_chain_depth: int = 0
var slow_factor: float = 1.0
var slow_sources: int = 0
const MAX_POISON_STACKS: int = 5
var poison_stacks: Array[Dictionary] = []
var needle_count: int = 0
var needle_timers: Array[float] = []
var inflation_tween: Tween = null
var inflation_pulse_tween: Tween = null

var blood_pool_scene = preload("res://blood_pool.tscn")
var blood_splatter_scene = preload("res://blood_splatter.tscn")

@onready var nav_agent: NavigationAgent3D = $NavigationAgent3D
@onready var collision_shape: CollisionShape3D = $CollisionShape3D
@onready var eyes: MeshInstance3D = get_node_or_null("Eyes")
@onready var detection_area: Area3D = get_node_or_null("DetectionArea")
@onready var head_hitbox: Area3D = get_node_or_null("HeadHitbox")
@onready var head_mesh: Node3D = get_node_or_null("HeadMesh")
@onready var body_mesh: MeshInstance3D = get_node_or_null("MeshInstance3D")

var eyes_material: StandardMaterial3D = null
var body_override_mat: StandardMaterial3D = null

var hp_viewport: SubViewport
var hp_bar: ProgressBar
var hp_sprite: Sprite3D
var hp_label: Label3D

func _ready():
	health = max_health
	floor_snap_length = 0.4
	floor_max_angle = deg_to_rad(60.0)
	floor_constant_speed = true
	
	if head_hitbox:
		head_hitbox.set_meta("enemy", self)
	
	if eyes:
		var mat = eyes.get_surface_override_material(0)
		if mat:
			eyes_material = mat.duplicate()
			eyes.set_surface_override_material(0, eyes_material)
			
	if detection_area:
		detection_area.body_entered.connect(_on_detection_area_body_entered)
		
	if nav_agent:
		nav_agent.avoidance_enabled = avoidance_enabled
		nav_agent.velocity_computed.connect(_on_velocity_computed)
		nav_agent.link_reached.connect(_on_link_reached)
		
	_setup_health_bar()
	lunge_cooldown_timer = randf_range(0.5, 2.5)
	fear_check_timer = randf_range(0.5, 2.5)

	# NavigationServer3D sync delay before using navigation agent
	set_physics_process(false)
	call_deferred("_setup_navigation")

func _setup_health_bar():
	# 1. SubViewport для отрисовки текстуры ProgressBar
	hp_viewport = SubViewport.new()
	hp_viewport.size = Vector2i(130, 20)
	hp_viewport.transparent_bg = true
	hp_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS

	hp_bar = ProgressBar.new()
	hp_bar.size = Vector2(130, 20)
	hp_bar.max_value = max_health
	hp_bar.value = health
	hp_bar.show_percentage = false

	var bg_box = StyleBoxFlat.new()
	bg_box.bg_color = Color(0.08, 0.08, 0.08, 0.85)
	bg_box.border_color = Color(0.35, 0.35, 0.35, 0.9)
	bg_box.set_border_width_all(2)
	bg_box.set_corner_radius_all(3)

	var fg_box = StyleBoxFlat.new()
	fg_box.bg_color = Color(0.95, 0.15, 0.15, 1.0)
	fg_box.set_corner_radius_all(2)

	hp_bar.add_theme_stylebox_override("background", bg_box)
	hp_bar.add_theme_stylebox_override("fill", fg_box)

	hp_viewport.add_child(hp_bar)
	add_child(hp_viewport)

	# 2. Sprite3D билборд полоски здоровья над головой врага
	hp_sprite = Sprite3D.new()
	hp_sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	hp_sprite.no_depth_test = true
	hp_sprite.position = Vector3(0, 1.15, 0)
	hp_sprite.texture = hp_viewport.get_texture()
	hp_sprite.pixel_size = 0.007
	add_child(hp_sprite)

	# 3. Текстовое числовое значение HP над полоской
	hp_label = Label3D.new()
	hp_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	hp_label.no_depth_test = true
	hp_label.position = Vector3(0, 1.32, 0)
	hp_label.font_size = 18
	hp_label.outline_size = 4
	hp_label.outline_modulate = Color.BLACK
	hp_label.modulate = Color(1.0, 0.9, 0.9)
	hp_label.text = "%d / %d" % [health, max_health]
	add_child(hp_label)

func _update_health_bar():
	if hp_bar:
		hp_bar.value = max(0, health)
	if hp_label:
		hp_label.text = "%d / %d" % [max(0, health), max_health]

func _setup_navigation():
	await get_tree().physics_frame
	set_physics_process(true)

func _physics_process(delta):
	if current_state == State.DEAD:
		return
		
	# Гравитация
	if not is_on_floor():
		velocity.y -= gravity * 2.0 * delta
		
	# Затухание отбрасывания
	var decay_rate = 2.5 if wall_slam_timer > 0.0 else 5.0
	knockback_velocity = knockback_velocity.lerp(Vector3.ZERO, decay_rate * delta)
	
	if attack_timer > 0.0:
		attack_timer -= delta
	if hit_reaction_timer > 0.0:
		hit_reaction_timer -= delta
	if lunge_cooldown_timer > 0.0:
		lunge_cooldown_timer -= delta
		
	# Обработка стаков яда (Poison DoT)
	if not poison_stacks.is_empty():
		var write_idx = 0
		for i in range(poison_stacks.size()):
			var stack = poison_stacks[i]
			stack["duration"] -= delta
			stack["tick_timer"] -= delta
			if stack["tick_timer"] <= 0.0:
				stack["tick_timer"] = float(stack["interval"])
				_apply_poison_tick(int(stack["damage"]))
				if current_state == State.DEAD:
					break
			if stack["duration"] > 0.0 and current_state != State.DEAD:
				poison_stacks[write_idx] = stack
				write_idx += 1
		if current_state != State.DEAD:
			poison_stacks.resize(write_idx)
			
	# Обработка застрявших игл: независимый таймер 6.0с на каждую иглу
	if not needle_timers.is_empty():
		var write_idx = 0
		var changed = false
		for i in range(needle_timers.size()):
			var t = needle_timers[i] - delta
			if t > 0.0:
				needle_timers[write_idx] = t
				write_idx += 1
			else:
				changed = true
		if changed:
			needle_timers.resize(write_idx)
			needle_count = write_idx
			_update_needle_visuals()
		
	if is_jumping_link:
		jump_grace_timer -= delta
		jump_timeout -= delta
		# Приземление: после выхода из grace-таймера при касании пола или по таймауту
		if jump_grace_timer <= 0.0 and ((is_on_floor() and velocity.y <= 0.5) or jump_timeout <= 0.0):
			is_jumping_link = false
			velocity.x = 0.0
			velocity.z = 0.0
			path_update_timer = 0.0
			unreachable_timer = 0.0
			if nav_agent:
				nav_agent.set_velocity(Vector3.ZERO)
			GameTypes.debug_log(&"enemy", "[%s] NavigationLink3D LANDED (floor: %s, vel.y: %.2f, timeout: %s)" % [
				name, is_on_floor(), velocity.y, jump_timeout <= 0.0
			])
	else:
		_process_fear_chain_check(delta)
		match current_state:
			State.IDLE:
				_process_idle(delta)
			State.CHASE:
				_process_chase(delta)
			State.ATTACK:
				_process_attack(delta)
			State.LUNGE:
				_process_lunge(delta)
			State.FLEE:
				_process_flee(delta)
			
	pre_move_velocity = velocity
	move_and_slide()
	
	_check_wall_slam(delta)

func set_state(new_state: State):
	if current_state == new_state or current_state == State.DEAD:
		return
		
	GameTypes.debug_log(&"enemy", "[%s] State: %s -> %s" % [name, State.keys()[current_state], State.keys()[new_state]])
	var prev_state = current_state
	current_state = new_state
	
	if prev_state == State.LUNGE and new_state != State.LUNGE:
		_reset_lunge_visuals()
		lunge_phase = 0
	
	match current_state:
		State.IDLE:
			target_player = null
			is_jumping_link = false
		State.CHASE:
			path_update_timer = 0.0
		State.ATTACK:
			velocity.x = 0.0
			velocity.z = 0.0
			is_jumping_link = false
			# На первый контакт (вход в зону атаки) обязательная задержка перед ударом
			attack_timer = max(attack_timer, reaction_delay)
			hit_reaction_timer = max(hit_reaction_timer, reaction_delay)
		State.LUNGE:
			is_jumping_link = false
		State.FLEE:
			is_jumping_link = false
			path_update_timer = 0.0
			attack_timer = 1.0
		State.DEAD:
			is_jumping_link = false
			die()

func _process_idle(delta):
	velocity.x = knockback_velocity.x
	velocity.z = knockback_velocity.z
	
	if repath_cooldown_timer > 0.0:
		repath_cooldown_timer -= delta
		return
		
	# Поиск игрока в радиусе детекции
	var player = get_tree().get_first_node_in_group("player")
	if is_instance_valid(player):
		if "is_dead" in player and player.is_dead:
			return
		var dist = global_position.distance_to(player.global_position)
		if dist <= detection_range:
			start_chase(player)

func _process_chase(delta):
	if not is_instance_valid(target_player) or ("is_dead" in target_player and target_player.is_dead):
		set_state(State.IDLE)
		return
		
	var dist_to_player = global_position.distance_to(target_player.global_position)
	
	# Если игрок в радиусе атаки — переходим в ATTACK
	if dist_to_player <= attack_range:
		set_state(State.ATTACK)
		return
		
	# Проверка атаки-выпада (LUNGE):
	# дистанция 5-7м, кулдаун готов, стоим на земле, не прыгаем link, не отброшены от стены
	if lunge_cooldown_timer <= 0.0 and dist_to_player >= lunge_min_range and dist_to_player <= lunge_max_range:
		if is_on_floor() and not is_jumping_link and wall_slam_timer <= 0.0 and _can_lunge_to_player():
			start_lunge()
			return
		
	# Обновляем целевую позицию для NavigationAgent3D с фиксированным интервалом
	path_update_timer -= delta
	if path_update_timer <= 0.0:
		path_update_timer = PATH_UPDATE_INTERVAL
		nav_agent.target_position = target_player.global_position
		
	# Проверка достижимости цели (защита от бесконечного застревания в недостижимой точке)
	var is_reachable = nav_agent.is_target_reachable()
	if not is_reachable:
		unreachable_timer += delta
		if unreachable_timer >= UNREACHABLE_TIMEOUT:
			GameTypes.debug_log(&"enemy", "[%s] Target unreachable for %.1fs, returning to IDLE with repath cooldown" % [name, unreachable_timer])
			unreachable_timer = 0.0
			repath_cooldown_timer = REPATH_COOLDOWN
			set_state(State.IDLE)
			return
	else:
		unreachable_timer = max(0.0, unreachable_timer - delta * 2.0)
		
	var next_path_pos = nav_agent.get_next_path_position()
	var move_dir = next_path_pos - global_position
	move_dir.y = 0.0
	
	# Фолбэк: если nav_agent вернул текущую позицию (нет пути или точка на краю navmesh),
	# используем прямое направление на игрока ТОЛЬКО если путь в целом достижим или в упор (dist <= 6м)
	if move_dir.length_squared() <= 0.01 and dist_to_player > attack_range:
		if is_reachable or dist_to_player <= 6.0:
			var direct = target_player.global_position - global_position
			direct.y = 0.0
			if direct.length_squared() > 0.01:
				move_dir = direct
			
	# Диагностический лог в CHASE (раз в 0.5с)
	debug_diag_timer -= delta
	if debug_diag_timer <= 0.0:
		debug_diag_timer = 0.5
		GameTypes.debug_log(&"enemy", "[%s CHASE] dist: %.2f | next_pos: %s | my_pos: %s | move_dir: %s | vel: (%.1f, %.1f) | reachable: %s | unreach_t: %.1f" % [
			name,
			dist_to_player,
			next_path_pos,
			global_position,
			move_dir,
			velocity.x,
			velocity.z,
			is_reachable,
			unreachable_timer
		])
	
	if move_dir.length_squared() > 0.05:
		move_dir = move_dir.normalized()
		current_target_vel = move_dir * (move_speed * slow_factor)
		if nav_agent.avoidance_enabled:
			nav_agent.set_velocity(current_target_vel)
		else:
			_apply_movement(current_target_vel, delta)
	else:
		current_target_vel = Vector3.ZERO
		if nav_agent.avoidance_enabled:
			nav_agent.set_velocity(Vector3.ZERO)
		else:
			_apply_movement(Vector3.ZERO, delta)

func _on_velocity_computed(safe_velocity: Vector3):
	if is_jumping_link or current_state == State.LUNGE:
		return
	var final_target = safe_velocity
	# Мёртвая зона avoidance: если вектор уклонения незначительно отличается от прямого пути
	# (< avoidance_deadzone), игнорируем микро-поправку avoidance.
	# Это предотвращает взаимный "пинг-понг" и поперечные автоколебания между соседними агентами.
	if current_target_vel.length_squared() > 0.1:
		var diff = safe_velocity - current_target_vel
		diff.y = 0.0
		if diff.length() < avoidance_deadzone:
			final_target = current_target_vel
	_apply_movement(final_target, get_physics_process_delta_time())

func _apply_movement(target_vel: Vector3, delta: float):
	if wall_slam_timer > 0.0:
		# Во время отброса от мощного melee враг летит по инерции и не может бежать навстречу
		target_vel = Vector3.ZERO
		# Сбалансированное сопротивление (в воздухе 2.0, на земле 4.0) для полета в ~3 раза дальше
		var flight_drag = 4.0 if is_on_floor() else 2.0
		velocity.x = lerp(velocity.x, 0.0, flight_drag * delta)
		velocity.z = lerp(velocity.z, 0.0, flight_drag * delta)
	else:
		# Усиленное сглаживание скорости через lerp с умеренным acceleration
		velocity.x = lerp(velocity.x, target_vel.x + knockback_velocity.x, min(1.0, acceleration * delta))
		velocity.z = lerp(velocity.z, target_vel.z + knockback_velocity.z, min(1.0, acceleration * delta))
	
	# Сглаживание поворота строго ПОСЛЕ финального сглаженного вектора скорости через lerp_angle
	var horiz_vel = Vector2(velocity.x, velocity.z)
	if horiz_vel.length_squared() > 0.2:
		var target_angle = atan2(-horiz_vel.x, -horiz_vel.y)
		var angle_diff = abs(wrapf(target_angle - rotation.y, -PI, PI))
		if angle_diff > 0.08: # Мёртвая зона ~4.5 градуса против микро-рысканья
			rotation.y = lerp_angle(rotation.y, target_angle, min(1.0, rotation_speed * delta))

func _process_attack(delta):
	if not is_instance_valid(target_player) or ("is_dead" in target_player and target_player.is_dead):
		set_state(State.IDLE)
		return
		
	var dist_to_player = global_position.distance_to(target_player.global_position)
	
	# Если игрок отошел из радиуса атаки — возвращаемся в CHASE
	if dist_to_player > attack_range * 1.3:
		set_state(State.CHASE)
		return
		
	# Замедляемся во время атаки
	velocity.x = lerp(velocity.x, knockback_velocity.x, 10.0 * delta)
	velocity.z = lerp(velocity.z, knockback_velocity.z, 10.0 * delta)

	# Плавный поворот к игроку во время атаки
	var to_player = target_player.global_position - global_position
	to_player.y = 0.0
	if to_player.length_squared() > 0.01:
		var target_angle = atan2(-to_player.x, -to_player.z)
		var angle_diff = abs(wrapf(target_angle - rotation.y, -PI, PI))
		if angle_diff > 0.08:
			rotation.y = lerp_angle(rotation.y, target_angle, min(1.0, rotation_speed * delta))
	
	# Атакуем по кулдауну с учетом задержки реакции после получения урона
	if attack_timer <= 0.0 and hit_reaction_timer <= 0.0:
		if is_inside_tree() and current_state == State.ATTACK:
			perform_attack()
		attack_timer = attack_cooldown

func perform_attack():
	if not is_inside_tree() or current_state == State.DEAD:
		return
	if not is_instance_valid(target_player):
		return
		
	# Визуальный отклик атаки (вспышка глаз)
	if eyes_material:
		eyes_material.emission = Color(1.0, 0.1, 0.1)
		var tween = create_tween()
		tween.tween_property(eyes_material, "emission", Color(1.0, 1.0, 1.0), 0.25)
		
	# Нанесение урона в ближнем бою через has_method("take_damage")
	if target_player.has_method("take_damage"):
		var attack_dir = (target_player.global_position - global_position).normalized()
		var attack_impulse = attack_dir * 8.0 + Vector3.UP * 2.0
		target_player.take_damage(attack_damage, attack_impulse, target_player.global_position)

func _has_floor_at_destination(target_pos: Vector3) -> bool:
	var space_state = get_world_3d().direct_space_state
	if not space_state:
		return true
	# Луч вниз от новой (потенциально более высокой) расчетной точки приземления
	var ray_start_y = target_pos.y + 0.5
	var ray_end_y = min(global_position.y, target_pos.y) - 3.0
	var ray_start = Vector3(target_pos.x, ray_start_y, target_pos.z)
	var ray_end = Vector3(target_pos.x, ray_end_y, target_pos.z)
	var query = PhysicsRayQueryParameters3D.create(ray_start, ray_end)
	
	# Исключаем себя, игрока и других врагов, чтобы проверять именно статическую геометрию/пол
	var exclude_list: Array[RID] = [get_rid()]
	if is_instance_valid(target_player) and target_player is CollisionObject3D:
		exclude_list.append(target_player.get_rid())
	for e in get_tree().get_nodes_in_group("enemy"):
		if e is CollisionObject3D:
			exclude_list.append(e.get_rid())
	query.exclude = exclude_list
	query.collide_with_areas = false
	query.collide_with_bodies = true
	
	var result = space_state.intersect_ray(query)
	if result.is_empty():
		return false # Нет пола в пределах допустимой глубины — пропасть/обрыв
		
	var normal = result.get("normal", Vector3.UP)
	# Проверяем, что коллизия — это проходимый пол или наклонная поверхность (не отвесная стена)
	if normal.y < 0.5:
		return false
		
	return true

func _calculate_lunge_vector_and_distance() -> Dictionary:
	if not is_instance_valid(target_player):
		return {
			"dir": -transform.basis.z.normalized(),
			"dist": 8.0
		}
	var diff = target_player.global_position - global_position
	var horiz = Vector2(diff.x, diff.z)
	var horiz_dist = horiz.length()
	var dy = diff.y
	
	var dir_3d = Vector3.ZERO
	if horiz_dist > 0.01:
		var horiz_norm = horiz.normalized()
		# Вертикальное наведение: если цель выше врага (в прыжке или на платформе),
		# добавляем вертикальную составляющую вверх с лимитом 35-40° (38° ≈ 0.663 рад)
		var pitch = 0.0
		if dy > 0.0:
			var raw_pitch = atan2(dy, horiz_dist)
			pitch = min(raw_pitch, deg_to_rad(38.0))
		var cos_p = cos(pitch)
		var sin_p = sin(pitch)
		dir_3d = Vector3(horiz_norm.x * cos_p, sin_p, horiz_norm.y * cos_p).normalized()
	else:
		dir_3d = Vector3.UP if dy > 0.0 else -transform.basis.z.normalized()
		
	# Дистанция рывка 6.5 - 7.5 метров с пролётом дальше текущей позиции цели
	var total_dist = diff.length()
	var target_dist = clamp(total_dist + 1.5, 6.5, 7.5)
	
	return {
		"dir": dir_3d,
		"dist": target_dist
	}

func _has_line_of_sight_to(target: Node3D) -> bool:
	if not is_instance_valid(target):
		return false
	var space_state = get_world_3d().direct_space_state
	if not space_state:
		return true
	var from_pos = global_position + Vector3(0.0, 0.6, 0.0)
	var to_pos = target.global_position + Vector3(0.0, 0.6, 0.0)
	var query = PhysicsRayQueryParameters3D.create(from_pos, to_pos)
	query.exclude = [get_rid()]
	var result = space_state.intersect_ray(query)
	if result.is_empty():
		return true
	var col_obj = result.get("collider")
	return is_instance_valid(col_obj) and (col_obj == target or col_obj.is_in_group("player"))

func _can_lunge_to_player() -> bool:
	if not is_instance_valid(target_player):
		return false
		
	# Лимит перепада высоты: цель не выше 4.0м и не ниже 2.5м
	var height_diff = target_player.global_position.y - global_position.y
	if height_diff > 4.0 or height_diff < -2.5:
		return false
		
	# 1. Проверка прямой видимости (Line of Sight)
	if not _has_line_of_sight_to(target_player):
		return false # Препятствие между врагом и игроком (стена, колонна)
			
	# 2. Предварительная проверка наличия пола в направлении рывка с учётом 3D-вектора
	var lunge_data = _calculate_lunge_vector_and_distance()
	var test_landing = global_position + lunge_data["dir"] * lunge_data["dist"]
	if not _has_floor_at_destination(test_landing):
		return false # Направление ведёт в пропасть — не начинаем телеграф
			
	return true

func start_lunge():
	if not is_instance_valid(target_player):
		return
	set_state(State.LUNGE)
	lunge_phase = 1 # Фаза 1: Телеграф
	lunge_timer = lunge_telegraph_time
	lunge_has_hit = false
	lunge_cooldown_timer = lunge_cooldown
	
	# Полная остановка горизонтального движения при начале телеграфа
	velocity.x = 0.0
	velocity.z = 0.0
	if nav_agent and nav_agent.avoidance_enabled:
		nav_agent.set_velocity(Vector3.ZERO)
		
	# Направление на игрока в начале телеграфа (для поворота лицом)
	var to_player = target_player.global_position - global_position
	to_player.y = 0.0
	if to_player.length_squared() > 0.01:
		lunge_dir = to_player.normalized()
		rotation.y = atan2(-lunge_dir.x, -lunge_dir.z)
	else:
		lunge_dir = -transform.basis.z.normalized()
		
	# Визуальный телеграф (0.35-0.4с):
	# 1. Глаза загораются ярким янтарно-оранжевым цветом
	if eyes_material:
		eyes_material.emission_enabled = true
		eyes_material.emission = Color(1.0, 0.6, 0.0)
		eyes_material.emission_energy_multiplier = 4.5
		
	# 2. Моделька приседает / сжимается по вертикали (crouch & squash)
	if not is_inflated:
		if body_mesh:
			body_mesh.scale = Vector3(1.2, 0.75, 1.2)
		if head_mesh:
			head_mesh.position = Vector3(0.0, 0.38, 0.0)
		if eyes:
			eyes.position = Vector3(0.0, 0.38, -0.28)
		if head_hitbox:
			head_hitbox.position = Vector3(0.0, 0.38, 0.0)
			
	GameTypes.debug_log(&"enemy", "[%s] LUNGE started: Telegraph (%.2fs) towards %s" % [name, lunge_telegraph_time, lunge_dir])

func _process_lunge(delta: float):
	lunge_timer -= delta
	
	if lunge_phase == 1:
		# Фаза 1: Телеграф (0.38с)
		# Враг замирает на месте
		velocity.x = lerp(velocity.x, knockback_velocity.x, 15.0 * delta)
		velocity.z = lerp(velocity.z, knockback_velocity.z, 15.0 * delta)
		
		# Плавная доводка взгляда на игрока во время телеграфа
		if is_instance_valid(target_player):
			var to_player = target_player.global_position - global_position
			to_player.y = 0.0
			if to_player.length_squared() > 0.01:
				var target_angle = atan2(-to_player.x, -to_player.z)
				rotation.y = lerp_angle(rotation.y, target_angle, min(1.0, 10.0 * delta))
				
		if lunge_timer <= 0.0:
			# МОМЕНТ ЗАВЕРШЕНИЯ ТЕЛЕГРАФА:
			# Фиксируем 3D-направление (с вертикальным наведением до 38°) и полную дистанцию рывка (6.5-7.5м)
			var lunge_data = _calculate_lunge_vector_and_distance()
			lunge_dir = lunge_data["dir"]
			lunge_target_distance = lunge_data["dist"]
				
			rotation.y = atan2(-lunge_dir.x, -lunge_dir.z)
			
			# Защита от рывка в пропасть / с края платформы:
			# Проверяем raycast вниз от новой (3D) конечной точки рывка (позиция + вектор × дистанция)
			var landing_pos = global_position + lunge_dir * lunge_target_distance
			if not _has_floor_at_destination(landing_pos):
				GameTypes.debug_log(&"enemy", "[%s] LUNGE cancelled: Destination %s has no floor (chasm)! Resuming chase." % [name, landing_pos])
				lunge_cooldown_timer = 2.0
				end_lunge()
				return
				
			# Переход в Фазу 2: Рывок по зафиксированному вектору
			lunge_phase = 2
			lunge_has_hit = false
			lunge_start_pos = global_position
			# Защитный таймаут на основе дистанции и скорости (с запасом 0.08с)
			lunge_timer = (lunge_target_distance / lunge_speed) + 0.08
			
			# Применяем импульс рывка (24-26 м/с) строго по зафиксированному 3D-направлению
			velocity = lunge_dir * lunge_speed
			
			# Визуал фазы рывка: вытягивание вперёд, алые глаза
			if eyes_material:
				eyes_material.emission_enabled = true
				eyes_material.emission = Color(1.0, 0.15, 0.1)
				eyes_material.emission_energy_multiplier = 4.0
			if not is_inflated:
				if body_mesh:
					body_mesh.scale = Vector3(0.85, 1.0, 1.25)
				if head_mesh:
					head_mesh.position = Vector3(0.0, 0.55, 0.0)
				if eyes:
					eyes.position = Vector3(0.0, 0.55, -0.28)
				if head_hitbox:
					head_hitbox.position = Vector3(0.0, 0.55, 0.0)
					
			AudioManager.play_sound("dash")
			GameTypes.debug_log(&"enemy", "[%s] LUNGE DASH START! dir: %s, target_dist: %.2fm, speed: %.1f" % [
				name, lunge_dir, lunge_target_distance, lunge_speed
			])
			
	elif lunge_phase == 2:
		# Фаза 2: Прямолинейный рывок по зафиксированному 3D-вектору (НЕ наводится и НЕ тормозит)
		velocity = lunge_dir * lunge_speed
		
		# Проверка нанесения урона при пересечении с игроком в любой момент рывка
		if not lunge_has_hit:
			# 1. Проверка через физические slide collisions
			for i in range(get_slide_collision_count()):
				var col = get_slide_collision(i)
				var collider = col.get_collider()
				if is_instance_valid(collider) and collider.is_in_group("player"):
					_on_lunge_hit_player(collider)
					break
					
			# 2. Дополнительная проверка расстояния (защита от туннелирования на высокой скорости)
			if not lunge_has_hit and is_instance_valid(target_player):
				var dist = global_position.distance_to(target_player.global_position)
				if dist <= 1.6:
					_on_lunge_hit_player(target_player)
					
		# Расчёт фактически пройденного 3D-расстояния от точки старта рывка
		var covered_dist = global_position.distance_to(lunge_start_pos)
		
		# Завершение активного импульса рывка строго по прохождению полной дистанции или по истечению таймаута
		if covered_dist >= lunge_target_distance or lunge_timer <= 0.0:
			GameTypes.debug_log(&"enemy", "[%s] LUNGE DASH DISTANCE REACHED: traveled %.2fm / %.2fm (hit_player: %s, on_floor: %s). Handing over to ballistic inertia." % [
				name, covered_dist, lunge_target_distance, lunge_has_hit, is_on_floor()
			])
			_reset_lunge_visuals()
			if not is_on_floor():
				# В воздухе: переходим в фазу 3 (свободное падение по баллистической траектории с сохранением инерции)
				lunge_phase = 3
				lunge_timer = 2.5 # Защитный таймаут падения
			else:
				# Уже на земле: сохраняем скорость и передаем управление CHASE
				end_lunge()
				
	elif lunge_phase == 3:
		# Фаза 3: Свободное падение по баллистической траектории с сохранением инерции
		# В воздухе действует сопротивление воздуха на горизонтальную скорость
		var air_drag = 4.0
		velocity.x = lerp(velocity.x, 0.0, air_drag * delta)
		velocity.z = lerp(velocity.z, 0.0, air_drag * delta)
		# Вертикальная скорость velocity.y падает под действием гравитации в _physics_process()
		
		# Проверка нанесения урона при столкновении с игроком в падении
		if not lunge_has_hit:
			for i in range(get_slide_collision_count()):
				var col = get_slide_collision(i)
				var collider = col.get_collider()
				if is_instance_valid(collider) and collider.is_in_group("player"):
					_on_lunge_hit_player(collider)
					break
			if not lunge_has_hit and is_instance_valid(target_player):
				var dist = global_position.distance_to(target_player.global_position)
				if dist <= 1.6:
					_on_lunge_hit_player(target_player)
					
		# Приземление: возврат управления NavigationAgent3D только после касания земли (или по таймауту)
		if is_on_floor() or lunge_timer <= 0.0:
			GameTypes.debug_log(&"enemy", "[%s] LUNGE LANDED on floor! (is_on_floor: %s, vel: (%.1f, %.1f, %.1f)). Resuming chase." % [
				name, is_on_floor(), velocity.x, velocity.y, velocity.z
			])
			end_lunge()

func _on_lunge_hit_player(player: Node3D):
	if lunge_has_hit:
		return
	lunge_has_hit = true
	if player.has_method("take_damage"):
		var attack_impulse = lunge_dir * 12.0 + Vector3.UP * 3.0
		player.take_damage(lunge_damage, attack_impulse, global_position)
	GameTypes.debug_log(&"enemy", "[%s] LUNGE HIT player for %d damage! (Continuing full dash)" % [name, lunge_damage])
	# НЕ вызываем end_lunge() — враг завершает полный рывок по инерции!

func end_lunge():
	_reset_lunge_visuals()
	lunge_phase = 0
	# Сохраняем текущую скорость по инерции, НЕ гасим velocity резко!
	# Управление передается обратно NavigationAgent3D / _apply_movement,
	# которая плавно сглаживает скорость через acceleration
	set_state(State.CHASE)

func _reset_lunge_visuals():
	if eyes_material:
		eyes_material.emission_enabled = true
		eyes_material.emission = Color(1.0, 1.0, 1.0)
		eyes_material.emission_energy_multiplier = 2.0
	if head_mesh and not is_inflated:
		head_mesh.position = Vector3(0.0, 0.55, 0.0)
	if eyes:
		eyes.position = Vector3(0.0, 0.55, -0.28)
	if head_hitbox:
		head_hitbox.position = Vector3(0.0, 0.55, 0.0)
	if not is_inflated:
		if needle_count > 0:
			_update_needle_visuals()
		elif body_mesh:
			body_mesh.scale = Vector3.ONE
			if head_mesh:
				head_mesh.scale = Vector3.ONE
# --- FEAR CHAIN (Паника на тире OVERDRIVE) ---

func _process_fear_chain_check(delta: float):
	if current_state != State.IDLE and current_state != State.CHASE:
		return
	if is_jumping_link:
		return
		
	fear_check_timer -= delta
	if fear_check_timer > 0.0:
		return
	fear_check_timer = 3.0 # Проверка каждые 3 секунды
	
	var player = target_player
	if not is_instance_valid(player):
		player = get_tree().get_first_node_in_group("player")
	if not is_instance_valid(player) or ("is_dead" in player and player.is_dead):
		return
		
	# Проверяем тир OVERDRIVE игрока (BPM >= 180.0)
	var player_bpm: float = 0.0
	var is_overdrive: bool = false
	if "skills" in player and is_instance_valid(player.skills):
		if "bpm" in player.skills:
			player_bpm = player.skills.bpm
		if player.skills.has_method("get_bpm_tier"):
			is_overdrive = (player.skills.get_bpm_tier() == GameTypes.BPMTier.OVERDRIVE)
		else:
			is_overdrive = (player_bpm >= 180.0)
	if not is_overdrive:
		return
		
	# Проверяем нахождение в зоне видимости / детекции и прямую видимость (LOS)
	var dist = global_position.distance_to(player.global_position)
	if dist > detection_range:
		return
	if not _has_line_of_sight_to(player):
		return
		
	# 40% шанс паники
	if randf() <= 0.40:
		target_player = player
		flee_timer = randf_range(4.0, 5.0)
		GameTypes.debug_log(&"enemy", "[%s] FEAR CHAIN: Overdrive panic triggered (BPM: %.1f)! FLEE for %.2fs" % [name, player_bpm, flee_timer])
		set_state(State.FLEE)

func _process_flee(delta: float):
	if not is_instance_valid(target_player) or ("is_dead" in target_player and target_player.is_dead):
		set_state(State.IDLE)
		return
		
	# Прерывание FLEE при падении BPM ниже 180 (игрок вышел из OVERDRIVE)
	var player_bpm: float = 0.0
	var is_overdrive: bool = false
	if "skills" in target_player and is_instance_valid(target_player.skills):
		if "bpm" in target_player.skills:
			player_bpm = target_player.skills.bpm
		if target_player.skills.has_method("get_bpm_tier"):
			is_overdrive = (target_player.skills.get_bpm_tier() == GameTypes.BPMTier.OVERDRIVE)
		else:
			is_overdrive = (player_bpm >= 180.0)
	if not is_overdrive:
		GameTypes.debug_log(&"enemy", "[%s] FLEE interrupted: Player left OVERDRIVE (BPM: %.1f). Resuming normal behavior." % [name, player_bpm])
		_resume_from_flee()
		return
		
	# Отсчет таймера паники (4-5 сек)
	flee_timer -= delta
	if flee_timer <= 0.0:
		GameTypes.debug_log(&"enemy", "[%s] FLEE expired. Resuming normal behavior." % name)
		_resume_from_flee()
		return
		
	# Обновление целевой точки бегства прочь от игрока
	path_update_timer -= delta
	if path_update_timer <= 0.0:
		path_update_timer = PATH_UPDATE_INTERVAL
		var base_away = (global_position - target_player.global_position)
		base_away.y = 0.0
		if base_away.length_squared() > 0.01:
			base_away = base_away.normalized()
		else:
			base_away = -transform.basis.z.normalized()
			
		var best_flee_target = global_position + base_away * 12.0
		var nav_map = nav_agent.get_navigation_map()
		if nav_map.is_valid():
			var max_player_dist = -1.0
			var candidate_angles = [0.0, 0.785, -0.785, 1.57, -1.57]
			for angle_offset in candidate_angles:
				var candidate_dir = base_away.rotated(Vector3.UP, angle_offset)
				var candidate_pos = global_position + candidate_dir * 12.0
				var nav_pt = NavigationServer3D.map_get_closest_point(nav_map, candidate_pos)
				var d_player = nav_pt.distance_squared_to(target_player.global_position)
				if d_player > max_player_dist:
					max_player_dist = d_player
					best_flee_target = nav_pt
			nav_agent.target_position = best_flee_target
		else:
			nav_agent.target_position = best_flee_target
			
	var next_path_pos = nav_agent.get_next_path_position()
	var move_dir = next_path_pos - global_position
	move_dir.y = 0.0
	
	# Фолбэк: если nav_agent вернул текущую позицию, жмёмся прямо прочь от игрока
	if move_dir.length_squared() <= 0.01:
		var direct_away = global_position - target_player.global_position
		direct_away.y = 0.0
		if direct_away.length_squared() > 0.01:
			move_dir = direct_away
			
	if move_dir.length_squared() > 0.05:
		move_dir = move_dir.normalized()
		current_target_vel = move_dir * (move_speed * slow_factor)
		if nav_agent.avoidance_enabled:
			nav_agent.set_velocity(current_target_vel)
		else:
			_apply_movement(current_target_vel, delta)
	else:
		current_target_vel = Vector3.ZERO
		if nav_agent.avoidance_enabled:
			nav_agent.set_velocity(Vector3.ZERO)
		else:
			_apply_movement(Vector3.ZERO, delta)

func _resume_from_flee():
	flee_timer = 0.0
	if is_instance_valid(target_player) and not ("is_dead" in target_player and target_player.is_dead):
		var dist = global_position.distance_to(target_player.global_position)
		if dist <= detection_range:
			repath_cooldown_timer = 0.0
			start_chase(target_player)
			return
	set_state(State.IDLE)

func start_chase(player: Node3D):
	if repath_cooldown_timer > 0.0:
		return
	target_player = player
	unreachable_timer = 0.0
	set_state(State.CHASE)
	if is_instance_valid(nav_agent):
		nav_agent.target_position = target_player.global_position

func _on_link_reached(details: Dictionary):
	if is_jumping_link or current_state == State.DEAD or current_state == State.LUNGE:
		return
		
	var exit_pos: Vector3 = details.get("link_exit_position", Vector3.ZERO)
	
	# Фолбэк на owner (NavigationLink3D), если exit_pos не передан напрямую
	if exit_pos == Vector3.ZERO:
		var link_node = details.get("owner") as NavigationLink3D
		if link_node:
			var p_start = link_node.global_transform * link_node.start_position
			var p_end = link_node.global_transform * link_node.end_position
			if global_position.distance_squared_to(p_start) < global_position.distance_squared_to(p_end):
				exit_pos = p_end
			else:
				exit_pos = p_start
				
	if exit_pos == Vector3.ZERO:
		return
		
	_start_link_jump(exit_pos)

func _start_link_jump(target_pos: Vector3):
	var delta_pos = target_pos - global_position
	var delta_h = Vector3(delta_pos.x, 0.0, delta_pos.z)
	var dist_h = delta_h.length()
	var delta_y = delta_pos.y
	
	# Эффективная гравитация врага: gravity * 2.0 (как в _physics_process)
	var eff_gravity: float = gravity * 2.0
	if eff_gravity <= 0.1:
		eff_gravity = 19.6
		
	# Расчёт высоты апекса траектории над текущей точкой
	var h_apex: float
	if delta_y >= 0.0:
		# Прыжок вверх: апекс выше целевой площадки на 1.5м (минимум 2.5м над стартом)
		h_apex = max(delta_y + 1.5, 2.5)
	else:
		# Прыжок вниз: мягкий перескок вверх на 1.2м над стартовой точкой
		h_apex = 1.2
		
	var v_y: float = sqrt(2.0 * eff_gravity * h_apex)
	var t_up: float = v_y / eff_gravity
	var fall_height: float = max(0.01, h_apex - delta_y)
	var t_down: float = sqrt(2.0 * fall_height / eff_gravity)
	var t_total: float = t_up + t_down
	
	var horiz_vel: Vector3 = Vector3.ZERO
	if t_total > 0.01:
		horiz_vel = delta_h / t_total
	elif dist_h > 0.01:
		horiz_vel = delta_h.normalized() * move_speed
		
	velocity = Vector3(horiz_vel.x, v_y, horiz_vel.z)
	is_jumping_link = true
	jump_grace_timer = 0.25
	jump_timeout = t_total + 1.2
	unreachable_timer = 0.0
	
	# Поворачиваемся в сторону прыжка
	if dist_h > 0.01:
		rotation.y = atan2(-delta_h.x, -delta_h.z)
		
	GameTypes.debug_log(&"enemy", "[%s] NavigationLink3D JUMP -> target %s, dy=%.2f, dh=%.2f, v=(%.1f, %.1f, %.1f), t_flight=%.2fs" % [
		name, target_pos, delta_y, dist_h, velocity.x, velocity.y, velocity.z, t_total
	])

func _on_detection_area_body_entered(body: Node3D):
	if body.is_in_group("player") and current_state == State.IDLE:
		if "is_dead" in body and body.is_dead:
			return
		if repath_cooldown_timer > 0.0:
			return
		start_chase(body)

func apply_vacuum_pull(pull_impulse: Vector3):
	if current_state == State.DEAD:
		return
	# Добавляем импульс притягивания к текущей скорости и knockback_velocity
	knockback_velocity += Vector3(pull_impulse.x, 0.0, pull_impulse.z)
	velocity.x += pull_impulse.x
	velocity.z += pull_impulse.z
	if pull_impulse.y > 0.0:
		velocity.y = max(velocity.y, pull_impulse.y)
	elif pull_impulse.y < 0.0:
		velocity.y += pull_impulse.y
		
	# Отключаем сопротивление навигации на время притягивания (0.25с)
	wall_slam_timer = max(wall_slam_timer, 0.25)
	hit_reaction_timer = max(hit_reaction_timer, 0.2)

func add_slow(factor: float = 0.5):
	slow_sources += 1
	slow_factor = factor

func remove_slow():
	slow_sources = max(0, slow_sources - 1)
	if slow_sources == 0:
		slow_factor = 1.0

func apply_poison_dot(duration: float = 3.0, damage_per_tick: int = 3, interval: float = 0.5, chain_depth: int = 0):
	if current_state == State.DEAD:
		return
	last_damage_weapon = "injector"
	if poison_stacks.size() < MAX_POISON_STACKS:
		poison_stacks.append({
			"duration": duration,
			"tick_timer": interval,
			"damage": damage_per_tick,
			"interval": interval,
			"chain_depth": chain_depth
		})
	else:
		# При максимуме 5 стаков обновляем стак с наименьшим оставшимся временем
		var min_idx = 0
		var min_dur = float(poison_stacks[0]["duration"])
		for i in range(1, poison_stacks.size()):
			if float(poison_stacks[i]["duration"]) < min_dur:
				min_dur = float(poison_stacks[i]["duration"])
				min_idx = i
		poison_stacks[min_idx]["duration"] = max(float(poison_stacks[min_idx]["duration"]), duration)
		poison_stacks[min_idx]["chain_depth"] = min(int(poison_stacks[min_idx]["chain_depth"]), chain_depth)

func _apply_poison_tick(damage: int):
	if current_state == State.DEAD:
		return
	last_damage_weapon = "injector"
	health -= damage
	_update_health_bar()
	var hit_pos = global_position + Vector3(randf_range(-0.15, 0.15), 0.85 + randf_range(-0.1, 0.1), randf_range(-0.15, 0.15))
	_spawn_damage_number(damage, hit_pos, false, true)
	if current_state == State.IDLE:
		var player = get_tree().get_first_node_in_group("player")
		if is_instance_valid(player):
			start_chase(player)
	if health <= 0:
		explosion_chain_depth = 0
		set_state(State.DEAD)

func add_needle():
	if current_state == State.DEAD:
		return
	last_damage_weapon = "sewing"
	needle_timers.append(6.0)
	needle_count = needle_timers.size()
	_update_needle_visuals()
	GameTypes.debug_log(&"enemy", "[%s] Needle stuck! Total needles: %d" % [name, needle_count])

func _update_needle_visuals():
	if current_state == State.DEAD:
		return
	if is_inflated:
		return # Визуал раздутия Инъектора имеет приоритет
		
	if needle_count > 0:
		# Мягкое увеличение размера пропорционально количеству игл (до +18% при 30 иглах)
		var n_factor = clamp(float(needle_count) / 30.0, 0.0, 1.0)
		var target_scale = Vector3.ONE * (1.0 + n_factor * 0.18)
		if body_mesh:
			body_mesh.scale = target_scale
			if not body_override_mat:
				var orig_mat = body_mesh.get_surface_override_material(0)
				body_override_mat = orig_mat.duplicate() if orig_mat else StandardMaterial3D.new()
				body_mesh.set_surface_override_material(0, body_override_mat)
			body_override_mat.emission_enabled = true
			body_override_mat.emission = Color(0.75, 0.88, 1.0) # Металлический отблеск игл
			body_override_mat.emission_energy_multiplier = 0.4 + n_factor * 1.6
		if head_mesh:
			head_mesh.scale = target_scale
	else:
		if body_mesh:
			body_mesh.scale = Vector3.ONE
			if body_override_mat:
				body_override_mat.emission_enabled = false
		if head_mesh:
			head_mesh.scale = Vector3.ONE

func inflate():
	if is_inflated or current_state == State.DEAD:
		return
	last_damage_weapon = "injector"
	is_inflated = true
	
	if inflation_tween:
		inflation_tween.kill()
	inflation_tween = create_tween().set_parallel(true)
	
	if body_mesh:
		var orig_mat = body_mesh.get_surface_override_material(0)
		if orig_mat:
			body_override_mat = orig_mat.duplicate()
		else:
			body_override_mat = StandardMaterial3D.new()
			body_override_mat.albedo_color = Color(0.015, 0.015, 0.015, 1)
		body_override_mat.emission_enabled = true
		body_override_mat.emission = Color(1.0, 0.12, 0.12)
		body_override_mat.emission_energy_multiplier = 1.6
		body_mesh.set_surface_override_material(0, body_override_mat)
		inflation_tween.tween_property(body_mesh, "scale", Vector3(1.26, 1.26, 1.26), 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		
	if head_mesh:
		inflation_tween.tween_property(head_mesh, "scale", Vector3(1.26, 1.26, 1.26), 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		
	if eyes_material:
		eyes_material.emission = Color(1.0, 0.1, 0.1)
		eyes_material.emission_energy_multiplier = 3.5
		
	if inflation_pulse_tween:
		inflation_pulse_tween.kill()
	inflation_pulse_tween = create_tween().set_loops()
	if body_override_mat:
		inflation_pulse_tween.tween_property(body_override_mat, "emission_energy_multiplier", 3.2, 0.45).set_trans(Tween.TRANS_SINE)
		inflation_pulse_tween.tween_property(body_override_mat, "emission_energy_multiplier", 1.2, 0.45).set_trans(Tween.TRANS_SINE)
		
	if current_state == State.IDLE:
		var player = get_tree().get_first_node_in_group("player")
		if is_instance_valid(player):
			start_chase(player)

	GameTypes.debug_log(&"enemy", "[%s] INFLATED with blood!" % name)

func take_damage(amount: int, knockback_vector: Vector3, hit_pos: Vector3, is_melee: bool = false, is_execute: bool = false, is_shockwave: bool = false, is_headshot: bool = false, source_chain_depth: int = -1, weapon_source: String = ""):
	if current_state == State.DEAD:
		return
		
	if source_chain_depth >= 0:
		explosion_chain_depth = source_chain_depth + 1
		# Жёсткий предел: если смертельный урон получен от взрыва с глубиной >= 3 — цепная детонация блокируется
		if source_chain_depth >= 3 and (health - amount <= 0):
			is_inflated = false
	else:
		explosion_chain_depth = 0
		
	if is_shockwave:
		slam_chain_depth = max(0, source_chain_depth)
		was_killed_by_shockwave = true
	elif amount > 0:
		was_killed_by_shockwave = false
		
	was_killed_by_melee = is_melee or is_shockwave or is_execute
	if is_melee or is_shockwave or is_execute:
		last_damage_weapon = "melee"
	elif weapon_source != "":
		last_damage_weapon = weapon_source
		
	health -= amount
	_update_health_bar()
	_spawn_damage_number(amount, hit_pos, is_headshot)
	AudioManager.play_sound("enemy_hit")
	
	if is_headshot:
		GameTypes.debug_log(&"enemy", "[%s] HEADSHOT! Damage: %d | Remaining HP: %d" % [name, amount, max(0, health)])
		var cur_frame = Engine.get_process_frames()
		if cur_frame != last_headshot_bonus_frame:
			last_headshot_bonus_frame = cur_frame
			var player_node = get_tree().get_first_node_in_group("player")
			if is_instance_valid(player_node) and "skills" in player_node and is_instance_valid(player_node.skills):
				player_node.skills.add_bpm(1.5)
				GameTypes.debug_log(&"enemy", "[HEADSHOT BPM BONUS] +1.5 BPM granted for precision headshot! (Current BPM: %.1f)" % player_node.skills.bpm)
	
	# Задержка реакции перед контратакой после получения любого урона (telegraph window)
	hit_reaction_timer = reaction_delay
	attack_timer = max(attack_timer, reaction_delay)
	
	# Разделяем входящий импульс
	knockback_velocity = Vector3(knockback_vector.x, 0, knockback_vector.z)
	if is_shockwave or is_execute or is_melee or knockback_vector.length_squared() > 10.0:
		is_jumping_link = false
	if current_state == State.LUNGE and (is_shockwave or is_execute or is_melee or amount >= 20 or knockback_vector.length_squared() > 10.0):
		GameTypes.debug_log(&"enemy", "[%s] Lunge interrupted by damage/melee!" % [name])
		end_lunge()
	
	# При melee-ударе активируем окно отслеживания удара об стену только для мощной ударной волны или добивания
	if is_shockwave or is_execute:
		wall_slam_timer = 0.8 if is_shockwave else 0.4
		velocity.x = knockback_vector.x
		velocity.z = knockback_vector.z
	elif is_melee:
		# Обычный direct-hit: короткий отброс с плавным скольжением
		wall_slam_timer = 0.25
		velocity.x = knockback_vector.x
		velocity.z = knockback_vector.z
	
	# Если оружие задает вертикальную скорость (вверх или вниз)
	if knockback_vector.y != 0.0:
		velocity.y = knockback_vector.y
		
	# Агримся на игрока при получении урона
	if current_state == State.IDLE:
		var player = get_tree().get_first_node_in_group("player")
		if is_instance_valid(player):
			start_chase(player)
	
	if blood_splatter_scene:
		var splatter = blood_splatter_scene.instantiate()
		var pmat = splatter.process_material.duplicate()
		
		if is_execute:
			# Максимальный gore-эффект при добивании (execute)
			splatter.amount = 160
			splatter.scale = Vector3(2.4, 2.4, 2.4)
			pmat.spread = 180.0
			pmat.initial_velocity_min = 8.0
			pmat.initial_velocity_max = 20.0
			pmat.scale_min = 0.35
			pmat.scale_max = 0.65
		elif is_headshot:
			# Сочный, мощный разрыв головы при хедшоте (высокая скорость разлёта во все стороны)
			splatter.amount = 145
			splatter.scale = Vector3(2.2, 2.2, 2.2)
			pmat.spread = 160.0
			pmat.initial_velocity_min = 7.5
			pmat.initial_velocity_max = 18.0
			pmat.scale_min = 0.26
			pmat.scale_max = 0.55
		elif is_shockwave or amount >= 80 or knockback_vector.length() >= 25.0:
			# Массивный, сочный разлёт крови от конусной ударной волны / высокой скорости / мощного удара
			splatter.amount = 110
			splatter.scale = Vector3(1.9, 1.9, 1.9)
			pmat.spread = 100.0
			pmat.initial_velocity_min = 6.0
			pmat.initial_velocity_max = 16.0
			pmat.scale_min = 0.22
			pmat.scale_max = 0.50
		elif is_melee:
			# Скромный, компактный всплеск крови при обычном слабом тычке стоя на месте (~35 урона)
			splatter.amount = 20
			splatter.scale = Vector3(0.8, 0.8, 0.8)
			pmat.spread = 35.0
			pmat.initial_velocity_min = 3.0
			pmat.initial_velocity_max = 6.0
			pmat.scale_min = 0.08
			pmat.scale_max = 0.18
		else:
			# Стандартные попадания из огнестрельного оружия
			splatter.amount = 28
			splatter.scale = Vector3(1.0, 1.0, 1.0)
			pmat.spread = 40.0
			pmat.initial_velocity_min = 4.0
			pmat.initial_velocity_max = 8.0
			pmat.scale_min = 0.10
			pmat.scale_max = 0.25
			
		splatter.process_material = pmat
		
		var scene_root = get_tree().current_scene if get_tree().current_scene else get_parent()
		if scene_root:
			scene_root.add_child(splatter)
			splatter.global_position = hit_pos
			
			# Чтобы кровь не выдавала ошибку при выстреле ровно сверху вниз
			var flat_knockback = Vector3(knockback_vector.x, 0, knockback_vector.z)
			if flat_knockback != Vector3.ZERO and hit_pos != hit_pos + flat_knockback:
				splatter.look_at(hit_pos + flat_knockback, Vector3.UP)
	
	if health <= 0:
		if is_headshot:
			if eyes:
				eyes.visible = false
			if head_mesh:
				head_mesh.visible = false
		set_state(State.DEAD)

func _check_wall_slam(delta: float):
	if wall_slam_timer <= 0.0 or current_state == State.DEAD:
		return
		
	wall_slam_timer -= delta
	
	for i in range(get_slide_collision_count()):
		var col = get_slide_collision(i)
		var n = col.get_normal()
		# Стены или пол/препятствия при сильном соударении (impact_speed >= threshold)
		var impact_speed = -pre_move_velocity.dot(n)
		if impact_speed >= wall_slam_threshold:
			trigger_wall_slam(impact_speed, col)
			break

func trigger_wall_slam(impact_speed: float, col: KinematicCollision3D):
	wall_slam_timer = 0.0 # Предотвращаем повторное срабатывание в течение одного отброса
	var raw_wall_damage = impact_speed * wall_slam_damage_multiplier
	# Формула с насыщением: урон продолжает расти со скоростью столкновения,
	# но асимптотически приближается к потолку wall_slam_max_damage (55 HP) и никогда не превышает его.
	var saturated_damage = wall_slam_max_damage * (1.0 - exp(-raw_wall_damage / wall_slam_max_damage))
	var base_wall_damage = mini(int(round(saturated_damage)), int(wall_slam_max_damage))
	
	# Затухание урона от столкновений по цепочке (100% -> 60% -> 35% -> 20%)
	var my_mult: float = 1.0
	if slam_chain_depth == 0:
		my_mult = 1.0
	elif slam_chain_depth == 1:
		my_mult = 0.60
	elif slam_chain_depth == 2:
		my_mult = 0.35
	else:
		my_mult = 0.20
		
	var wall_damage = int(round(base_wall_damage * my_mult))
	GameTypes.debug_log(&"enemy", "[%s] Wall slam! Speed: %.1f, chain_depth: %d, damage: %d (base: %d)" % [
		name, impact_speed, slam_chain_depth, wall_damage, base_wall_damage
	])
	
	# Если столкновение произошло с другим врагом — наносим collateral_slam со следующим уровнем глубины цепи
	var other = col.get_collider()
	if is_instance_valid(other) and other != self:
		var target: Node = null
		if other.is_in_group("enemy_head") or other.name == "HeadHitbox":
			target = other.get_meta("enemy") if other.has_meta("enemy") else other.get_parent()
		else:
			target = GameTypes.resolve_damageable(other)
		if target and target != self and target.has_method("take_damage"):
			var next_depth = slam_chain_depth + 1
			var next_mult: float = 1.0
			if next_depth == 1:
				next_mult = 0.60
			elif next_depth == 2:
				next_mult = 0.35
			else:
				next_mult = 0.20
			var collateral_damage = int(round(base_wall_damage * next_mult))
			GameTypes.debug_log(&"enemy", "[%s] Collateral hit %s! Depth: %d, damage: %d" % [name, target.name, next_depth, collateral_damage])
			# Импульс отброса сохраняется, урон ослаблен по цепи:
			target.take_damage(collateral_damage, -col.get_normal() * 12.0 + Vector3.UP * 4.0, col.get_position(), false, false, true, false, next_depth)
	
	# Сочный разлёт крови на стену в точке удара
	if blood_splatter_scene:
		var splatter = blood_splatter_scene.instantiate()
		splatter.amount = 60
		var pmat = splatter.process_material.duplicate()
		pmat.spread = 75.0
		pmat.initial_velocity_min = 4.0
		pmat.initial_velocity_max = 10.0
		splatter.process_material = pmat
		splatter.scale = Vector3(1.5, 1.5, 1.5)
		var scene_root = get_tree().current_scene if get_tree().current_scene else get_parent()
		if scene_root:
			scene_root.add_child(splatter)
			splatter.global_position = col.get_position()
			if col.get_normal() != Vector3.ZERO:
				splatter.look_at(col.get_position() + col.get_normal(), Vector3.UP)
				
	# Гасим отброс после удара о стену
	knockback_velocity = Vector3.ZERO
	velocity = velocity.slide(col.get_normal()) * 0.2
	
	health -= wall_damage
	_update_health_bar()
	_spawn_damage_number(wall_damage, col.get_position(), false)
	if health <= 0:
		explosion_chain_depth = 0
		var player = get_tree().get_first_node_in_group("player")
		if is_instance_valid(player) and "skills" in player and player.skills:
			player.skills.add_dash_charge()
		set_state(State.DEAD)


func _spawn_damage_number(dmg_amount: int, spawn_pos: Vector3, is_crit: bool = false, is_poison: bool = false):
	if dmg_amount <= 0:
		return
	var label = Label3D.new()
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.outline_size = 6
	label.outline_modulate = Color(0, 0, 0, 1)
	
	if is_poison:
		label.text = "-%d" % dmg_amount
		label.modulate = Color(0.25, 0.95, 0.35, 1.0) # Токсичный ядовито-зеленый цвет
		label.font_size = 20
	elif is_crit:
		label.text = "-%d CRIT!" % dmg_amount
		label.modulate = Color(1.0, 0.2, 0.1, 1.0)
		label.font_size = 32
	elif dmg_amount >= 140:
		label.text = "-%d AIR!" % dmg_amount
		label.modulate = Color(0.2, 0.85, 1.0, 1.0)
		label.font_size = 28
	else:
		label.text = "-%d" % dmg_amount
		label.modulate = Color(1.0, 0.92, 0.25, 1.0)
		label.font_size = 24
		
	var scene_root = get_tree().current_scene if get_tree().current_scene else get_parent()
	if not scene_root:
		return
	scene_root.add_child(label)
	
	var base_p = spawn_pos if spawn_pos.length_squared() > 0.01 else global_position + Vector3(0, 0.8, 0)
	var offset = Vector3(randf_range(-0.15, 0.15), randf_range(0.05, 0.2), randf_range(-0.15, 0.15))
	var start_p = base_p + offset
	label.global_position = start_p
	
	var target_p = start_p + Vector3(0.0, 0.75, 0.0)
	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "global_position", target_p, 0.65).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "modulate:a", 0.0, 0.65).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(label.queue_free)

func die():
	current_state = State.DEAD
	attack_timer = 999999.0
	set_physics_process(false)
	AudioManager.play_sound("enemy_death")
	
	# Начисление BPM игроку (+8.0 за убийство ударной волной, +5.5 за обычное убийство, +2.0 за смену оружия)
	var player = get_tree().get_first_node_in_group("player")
	if is_instance_valid(player) and "skills" in player and is_instance_valid(player.skills):
		var weapon_used = last_damage_weapon
		if was_killed_by_shockwave or was_killed_by_melee:
			weapon_used = "melee"
		elif weapon_used == "":
			# Фолбэк на текущее активное оружие игрока
			var weapons_mgr = player.get_node_or_null("Weapons")
			if is_instance_valid(weapons_mgr) and "current_weapon_index" in weapons_mgr:
				match weapons_mgr.current_weapon_index:
					0: weapon_used = "caliber0"
					1: weapon_used = "anvil"
					2: weapon_used = "injector"
					3: weapon_used = "sewing"
					_: weapon_used = "unknown"
			else:
				weapon_used = "unknown"
				
		if player.skills.has_method("record_kill_bpm"):
			player.skills.record_kill_bpm(weapon_used, was_killed_by_shockwave)
		else:
			var mult: float = player.skills.combat_momentum if "combat_momentum" in player.skills else 1.0
			player.skills.add_bpm((8.0 if was_killed_by_shockwave else 5.5) * mult)
	
	if hp_sprite:
		hp_sprite.visible = false
	if hp_label:
		hp_label.visible = false
		
	if collision_shape:
		collision_shape.set_deferred("disabled", true)
		
	if head_hitbox:
		var head_col = head_hitbox.get_node_or_null("CollisionShape3D")
		if head_col:
			head_col.set_deferred("disabled", true)
			
	if detection_area:
		var det_col = detection_area.get_node_or_null("CollisionShape3D")
		if det_col:
			det_col.set_deferred("disabled", true)
			
	# Разлёт застрявших игл при смерти (Швейная машина)
	var was_inflated = is_inflated
	var chain_depth = explosion_chain_depth
	if needle_count > 0:
		_trigger_needle_burst(was_inflated, chain_depth)

	# Заражение при смерти: если враг отравлен, выпускает облако яда (радиус 2.5м, максимум 3 поколения цепи)
	if not poison_stacks.is_empty():
		var min_depth = 999
		for stack in poison_stacks:
			var d = int(stack.get("chain_depth", 0))
			if d < min_depth:
				min_depth = d
		if min_depth < 3:
			_trigger_poison_contagion(min_depth)

	# Если враг был раздут шприцем — инициируем кровавую детонацию с учётом глубины цепи
	if is_inflated:
		if explosion_chain_depth > 3:
			is_inflated = false
		else:
			_trigger_inflation_explosion(explosion_chain_depth)
		
	if blood_pool_scene:
		var space_state = get_world_3d().direct_space_state
		var query = PhysicsRayQueryParameters3D.create(global_position, global_position + Vector3.DOWN * 50.0)
		var result = space_state.intersect_ray(query)
		
		var pool = blood_pool_scene.instantiate()
		var scene_root = get_tree().current_scene if get_tree().current_scene else get_parent()
		if scene_root:
			scene_root.add_child(pool)
			
			if result:
				pool.global_position = result.position + Vector3(0, 0.01, 0)
			else:
				pool.global_position = global_position
			
	queue_free()

func _trigger_inflation_explosion(depth: int = 0):
	is_inflated = false
	if inflation_pulse_tween:
		inflation_pulse_tween.kill()
		
	var explosion_pos = global_position + Vector3(0, 0.9, 0)
	
	# Расчёт затухания силы взрыва в зависимости от глубины цепи (chain_depth)
	# глубина 0 = 100%, глубина 1 = 70%, глубина 2 = 49%, глубина 3+ = 20%
	var mult: float = 1.0
	if depth >= 3:
		mult = 0.20
	else:
		mult = pow(0.7, depth)
		
	var base_radius: float = 5.2
	var base_damage: int = 85
	var explosion_radius: float = base_radius * mult
	var explosion_damage: int = max(1, int(round(float(base_damage) * mult)))
	
	var base_heal: int = 35 if was_killed_by_melee else 15
	var heal_amount: int = max(1, int(round(float(base_heal) * mult)))
	
	GameTypes.debug_log(&"enemy", "[%s] DETONATION! chain_depth: %d | mult: %.2f | dmg: %d | radius: %.2fm | heal: %d%s" % [
		name, depth, mult, explosion_damage, explosion_radius, heal_amount,
		" (CHAIN LIMIT: NO FURTHER CHAIN DETONATIONS)" if depth >= 3 else ""
	])
	
	AudioManager.play_sound("explosion")
	
	var scene_root = get_tree().current_scene if get_tree().current_scene else get_parent()
	if scene_root:
		# Сочный разлёт крови во все стороны (360 градусов), масштабируемый от силы взрыва
		if blood_splatter_scene:
			var splatter = blood_splatter_scene.instantiate()
			splatter.amount = max(20, int(round(135.0 * mult)))
			splatter.scale = Vector3(2.4, 2.4, 2.4) * max(0.5, mult)
			var pmat = splatter.process_material.duplicate()
			pmat.spread = 180.0
			pmat.initial_velocity_min = 7.0 * max(0.5, mult)
			pmat.initial_velocity_max = 20.0 * max(0.5, mult)
			pmat.scale_min = 0.28 * max(0.6, mult)
			pmat.scale_max = 0.65 * max(0.6, mult)
			splatter.process_material = pmat
			scene_root.add_child(splatter)
			splatter.global_position = explosion_pos
			
		_spawn_explosion_shockwave(scene_root, explosion_pos, explosion_radius)
		
	# 1. АОЕ урон по соседним врагам (запускает цепную реакцию для других раздутых врагов)
	var all_enemies = get_tree().get_nodes_in_group("enemy")
	for enemy in all_enemies:
		if not is_instance_valid(enemy) or enemy == self:
			continue
		if ("current_state" in enemy and enemy.current_state == enemy.State.DEAD) or ("health" in enemy and enemy.health <= 0):
			continue
			
		var enemy_center = enemy.global_position + Vector3(0, 0.9, 0)
		var dist = explosion_pos.distance_to(enemy_center)
		if dist <= explosion_radius:
			var falloff = 1.0 - (dist / explosion_radius) * 0.35
			var dmg = max(1, int(round(float(explosion_damage) * falloff)))
			var knock_dir = (enemy_center - explosion_pos).normalized()
			if knock_dir.length_squared() < 0.01:
				knock_dir = Vector3.UP
			var knock_vec = knock_dir * (14.0 * mult) + Vector3.UP * (4.5 * mult)
			
			GameTypes.debug_log(&"enemy", "[%s] DETONATION AOE HIT (chain %d -> %d) -> %s for %d dmg!" % [name, depth, depth + 1, enemy.name, dmg])
			enemy.take_damage(dmg, knock_vec, enemy_center, false, false, false, false, depth, "injector")
			
	# 2. Лечение игрока, если он в радиусе взрыва
	var player = get_tree().get_first_node_in_group("player")
	if is_instance_valid(player) and not ("is_dead" in player and player.is_dead):
		var player_center = player.global_position + Vector3(0, 0.9, 0)
		var dist_to_player = explosion_pos.distance_to(player_center)
		var heal_radius = (5.2 + 1.8) * mult
		if dist_to_player <= heal_radius:
			if player.has_method("heal"):
				player.heal(heal_amount, was_killed_by_melee)

func _spawn_explosion_shockwave(scene_root: Node, pos: Vector3, radius: float):
	var sphere = MeshInstance3D.new()
	var smesh = SphereMesh.new()
	smesh.radius = 0.4
	smesh.height = 0.8
	smesh.radial_segments = 16
	smesh.rings = 8
	sphere.mesh = smesh
	
	var mat = StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = Color(1.0, 0.15, 0.1, 0.8)
	sphere.material_override = mat
	
	scene_root.add_child(sphere)
	sphere.global_position = pos
	
	var tween = create_tween().set_parallel(true)
	tween.tween_property(sphere, "scale", Vector3(radius * 1.6, radius * 1.6, radius * 1.6), 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(mat, "albedo_color:a", 0.0, 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(sphere.queue_free)

func _trigger_poison_contagion(depth: int = 0):
	const CONTAGION_RADIUS: float = 2.5
	var cloud_pos = global_position + Vector3(0, 0.8, 0)
	
	GameTypes.debug_log(&"enemy", "[%s] POISON CONTAGION! depth: %d, radius: %.1fm" % [name, depth, CONTAGION_RADIUS])
	AudioManager.play_sound("flask_splash")
	
	var scene_root = get_tree().current_scene if get_tree().current_scene else get_parent()
	if scene_root:
		_spawn_poison_cloud_visual(scene_root, cloud_pos, CONTAGION_RADIUS)
		
	var space_state = get_world_3d().direct_space_state
	var all_enemies = get_tree().get_nodes_in_group("enemy")
	for enemy in all_enemies:
		if not is_instance_valid(enemy) or enemy == self:
			continue
		if ("current_state" in enemy and enemy.current_state == enemy.State.DEAD) or ("health" in enemy and enemy.health <= 0):
			continue
			
		var enemy_center = enemy.global_position + Vector3(0, 0.8, 0)
		var dist = cloud_pos.distance_to(enemy_center)
		if dist <= CONTAGION_RADIUS:
			if space_state:
				var ray_query = PhysicsRayQueryParameters3D.create(cloud_pos, enemy_center)
				ray_query.exclude = [self, enemy]
				ray_query.collide_with_areas = false
				ray_query.collide_with_bodies = true
				var hit_res = space_state.intersect_ray(ray_query)
				if not hit_res.is_empty():
					var col = hit_res.collider
					if col and not (col.is_in_group("enemy") or col.is_in_group("enemy_head")):
						continue
						
			if enemy.has_method("apply_poison_dot"):
				enemy.apply_poison_dot(3.0, 3, 0.5, depth + 1)
				GameTypes.debug_log(&"enemy", "[%s] CONTAGION INFECTED %s! Stack applied at depth %d" % [name, enemy.name, depth + 1])

func _spawn_poison_cloud_visual(scene_root: Node, cloud_pos: Vector3, cloud_radius: float):
	var mesh_inst = MeshInstance3D.new()
	var smesh = SphereMesh.new()
	smesh.radius = 0.4
	smesh.height = 0.8
	smesh.radial_segments = 16
	smesh.rings = 8
	mesh_inst.mesh = smesh
	
	var mat = StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = Color(0.25, 0.95, 0.35, 0.6) # Токсично-зеленый цвет яда
	mesh_inst.material_override = mat
	
	scene_root.add_child(mesh_inst)
	mesh_inst.global_position = cloud_pos
	
	var target_scale = Vector3.ONE * (cloud_radius / 0.4)
	var tween = mesh_inst.create_tween().set_parallel(true)
	tween.tween_property(mesh_inst, "scale", target_scale, 0.38).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(mat, "albedo_color:a", 0.0, 0.38).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(mesh_inst.queue_free)

func _trigger_needle_burst(was_inflated: bool, depth: int):
	var burst_radius: float = 6.0 if was_inflated else 4.0
	var count = needle_count
	needle_count = 0
	needle_timers.clear()
	
	# Расчет урона за иглу с учетом раздутия и цепного затухания Инъектора
	var base_needle_dmg = 8.0 if was_inflated else 3.0
	var mult: float = 1.0
	if was_inflated:
		if depth >= 3:
			mult = 0.20
		else:
			mult = pow(0.7, depth)
	var damage_per_needle = max(1, int(round(base_needle_dmg * mult)))
	
	var burst_pos = global_position + Vector3(0.0, 0.85, 0.0)
	var space_state = get_world_3d().direct_space_state
	
	var all_enemies = get_tree().get_nodes_in_group("enemy")
	var nearby_enemies: Array = []
	for e in all_enemies:
		if not is_instance_valid(e) or e == self:
			continue
		if ("current_state" in e and e.current_state == e.State.DEAD) or ("health" in e and e.health <= 0):
			continue
		var e_pos = e.global_position + Vector3(0.0, 0.85, 0.0)
		var dist = burst_pos.distance_to(e_pos)
		if dist <= burst_radius:
			nearby_enemies.append({"enemy": e, "pos": e_pos, "dist": dist})
			
	nearby_enemies.sort_custom(func(a, b): return a["dist"] < b["dist"])
	
	GameTypes.debug_log(&"enemy", "[%s] NEEDLE BURST! Count: %d | Inflated: %s | Radius: %.1f | DmgPerNeedle: %d | Depth: %d | EnemiesNearby: %d" % [
		name, count, str(was_inflated), burst_radius, damage_per_needle, depth, nearby_enemies.size()
	])
	
	AudioManager.play_sound("needle_shot")
	
	const NEEDLE_TOLERANCE: float = 0.40
	
	for i in range(count):
		var needle_dir: Vector3 = Vector3.FORWARD
		if nearby_enemies.size() > 0:
			var target_entry = nearby_enemies[i % nearby_enemies.size()]
			var to_target = target_entry["pos"] - burst_pos
			var base_dir = to_target.normalized() if to_target.length_squared() > 0.01 else Vector3.FORWARD
			var jitter = Vector3(randf_range(-0.12, 0.12), randf_range(-0.12, 0.12), randf_range(-0.12, 0.12))
			needle_dir = (base_dir + jitter).normalized()
		else:
			var angle = (float(i) / float(count)) * TAU + randf_range(-0.1, 0.1)
			needle_dir = Vector3(cos(angle), randf_range(-0.2, 0.3), sin(angle)).normalized()
			
		var max_dist = burst_radius
		var wall_query = PhysicsRayQueryParameters3D.create(burst_pos, burst_pos + needle_dir * max_dist)
		wall_query.exclude = [self]
		wall_query.collide_with_areas = false
		wall_query.collide_with_bodies = true
		var wall_res = space_state.intersect_ray(wall_query)
		var needle_end = burst_pos + needle_dir * max_dist
		if not wall_res.is_empty():
			var col = wall_res.collider
			if col and not (col.is_in_group("enemy") or col.is_in_group("enemy_head")):
				needle_end = wall_res.position
				max_dist = burst_pos.distance_to(needle_end)
				
		var line_vec = needle_end - burst_pos
		var line_len = line_vec.length()
		if line_len < 0.05:
			continue
		var line_dir = line_vec / line_len
		
		var hit_on_path: Array = []
		for cand in nearby_enemies:
			var e = cand["enemy"]
			if not is_instance_valid(e):
				continue
			var e_pos = cand["pos"]
			var t = clamp((e_pos - burst_pos).dot(line_dir), 0.0, line_len)
			if t < 0.05:
				continue
			var pt = burst_pos + line_dir * t
			var d = pt.distance_to(e_pos)
			if d <= (0.36 + NEEDLE_TOLERANCE):
				hit_on_path.append({"enemy": e, "hit_pos": pt, "dist": t})
				
		hit_on_path.sort_custom(func(a, b): return a["dist"] < b["dist"])
		
		if not was_inflated:
			# Обычный разлёт: игла поражает только ближайшего врага на траектории (не пробивает)
			if not hit_on_path.is_empty():
				var first_hit = hit_on_path[0]
				var target = first_hit["enemy"]
				if is_instance_valid(target) and ("health" in target and target.health > 0):
					var knock = needle_dir * 1.5 + Vector3.UP * 0.5
					target.take_damage(damage_per_needle, knock, first_hit["hit_pos"], false, false, false, false, -1, "sewing")
				needle_end = first_hit["hit_pos"]
		else:
			# Раздутый враг: иглы пробивают навылет всех врагов на своей траектории с наследованием chain_depth
			for hit_info in hit_on_path:
				var target = hit_info["enemy"]
				if is_instance_valid(target) and ("health" in target and target.health > 0):
					var knock = needle_dir * 2.5 + Vector3.UP * 0.8
					target.take_damage(damage_per_needle, knock, hit_info["hit_pos"], false, false, false, false, depth, "sewing")
					
		TracerPool.spawn_tracer(burst_pos, needle_end, &"shrapnel", was_inflated)

