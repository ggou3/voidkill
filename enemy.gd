extends CharacterBody3D

enum State {
	IDLE,
	CHASE,
	ATTACK,
	DEAD
}

@export var max_health: int = 100
@export var move_speed: float = 5.5
@export var acceleration: float = 4.0
@export var attack_damage: int = 15
@export var attack_range: float = 2.0
@export var attack_cooldown: float = 1.0
@export var detection_range: float = 25.0
@export var rotation_speed: float = 6.0
@export var avoidance_enabled: bool = false
@export var avoidance_deadzone: float = 0.5
@export var wall_slam_threshold: float = 16.0
@export var wall_slam_damage_multiplier: float = 3.5
@export var reaction_delay: float = 0.4

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

var blood_pool_scene = preload("res://blood_pool.tscn")
var blood_splatter_scene = preload("res://blood_splatter.tscn")

@onready var nav_agent: NavigationAgent3D = $NavigationAgent3D
@onready var collision_shape: CollisionShape3D = $CollisionShape3D
@onready var eyes: MeshInstance3D = get_node_or_null("Eyes")
@onready var detection_area: Area3D = get_node_or_null("DetectionArea")
@onready var head_hitbox: Area3D = get_node_or_null("HeadHitbox")
@onready var head_mesh: Node3D = get_node_or_null("HeadMesh")

var eyes_material: StandardMaterial3D = null

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
		
	# NavigationServer3D sync delay before using navigation agent
	set_physics_process(false)
	call_deferred("_setup_navigation")

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
		
	match current_state:
		State.IDLE:
			_process_idle(delta)
		State.CHASE:
			_process_chase(delta)
		State.ATTACK:
			_process_attack(delta)
			
	pre_move_velocity = velocity
	move_and_slide()
	
	_check_wall_slam(delta)

func set_state(new_state: State):
	if current_state == new_state or current_state == State.DEAD:
		return
		
	print("[%s] State: %s -> %s" % [name, State.keys()[current_state], State.keys()[new_state]])
	current_state = new_state
	
	match current_state:
		State.IDLE:
			target_player = null
		State.CHASE:
			path_update_timer = 0.0
		State.ATTACK:
			velocity.x = 0.0
			velocity.z = 0.0
			# На первый контакт (вход в зону атаки) обязательная задержка перед ударом
			attack_timer = max(attack_timer, reaction_delay)
			hit_reaction_timer = max(hit_reaction_timer, reaction_delay)
		State.DEAD:
			die()

func _process_idle(_delta):
	velocity.x = knockback_velocity.x
	velocity.z = knockback_velocity.z
	
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
		
	# Обновляем целевую позицию для NavigationAgent3D с фиксированным интервалом
	path_update_timer -= delta
	if path_update_timer <= 0.0:
		path_update_timer = PATH_UPDATE_INTERVAL
		nav_agent.target_position = target_player.global_position
		
	var next_path_pos = nav_agent.get_next_path_position()
	var move_dir = next_path_pos - global_position
	move_dir.y = 0.0
	
	# Фолбэк: если nav_agent вернул текущую позицию (нет пути или точка на краю navmesh),
	# используем прямое направление на игрока
	if move_dir.length_squared() <= 0.01 and dist_to_player > attack_range:
		var direct = target_player.global_position - global_position
		direct.y = 0.0
		if direct.length_squared() > 0.01:
			move_dir = direct
			
	# Диагностический лог в CHASE (раз в 0.5с)
	debug_diag_timer -= delta
	if debug_diag_timer <= 0.0:
		debug_diag_timer = 0.5
		print("[%s CHASE] dist: %.2f | next_pos: %s | my_pos: %s | move_dir: %s | vel: (%.1f, %.1f) | reachable: %s" % [
			name,
			dist_to_player,
			next_path_pos,
			global_position,
			move_dir,
			velocity.x,
			velocity.z,
			nav_agent.is_target_reachable()
		])
	
	if move_dir.length_squared() > 0.05:
		move_dir = move_dir.normalized()
		current_target_vel = move_dir * move_speed
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
		perform_attack()
		attack_timer = attack_cooldown

func perform_attack():
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

func start_chase(player: Node3D):
	target_player = player
	set_state(State.CHASE)
	if is_instance_valid(nav_agent):
		nav_agent.target_position = target_player.global_position

func _on_detection_area_body_entered(body: Node3D):
	if body.is_in_group("player") and current_state == State.IDLE:
		if "is_dead" in body and body.is_dead:
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

func take_damage(amount: int, knockback_vector: Vector3, hit_pos: Vector3, is_melee: bool = false, is_execute: bool = false, is_shockwave: bool = false, is_headshot: bool = false):
	if current_state == State.DEAD:
		return
		
	health -= amount
	AudioManager.play_sound("enemy_hit")
	
	if is_headshot:
		print("[%s] HEADSHOT! Damage: %d | Remaining HP: %d" % [name, amount, max(0, health)])
	
	# Задержка реакции перед контратакой после получения любого урона (telegraph window)
	hit_reaction_timer = reaction_delay
	attack_timer = max(attack_timer, reaction_delay)
	
	# Разделяем входящий импульс
	knockback_velocity = Vector3(knockback_vector.x, 0, knockback_vector.z)
	
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
	
	# Если оружие подкидывает, задаем вертикальную скорость
	if knockback_vector.y > 0.0:
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
		# Стены имеют нормаль, перпендикулярную полу (|n.y| < 0.4)
		if abs(n.y) < 0.4:
			var impact_speed = -pre_move_velocity.dot(n)
			if impact_speed >= wall_slam_threshold:
				trigger_wall_slam(impact_speed, col)
				break

func trigger_wall_slam(impact_speed: float, col: KinematicCollision3D):
	wall_slam_timer = 0.0 # Предотвращаем повторное срабатывание в течение одного отброса
	var wall_damage = int(round(impact_speed * wall_slam_damage_multiplier))
	print("[%s] Wall slam! Impact speed: %.1f, damage: %d" % [name, impact_speed, wall_damage])
	
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
	if health <= 0:
		var player = get_tree().get_first_node_in_group("player")
		if is_instance_valid(player) and "skills" in player and player.skills:
			player.skills.add_dash_charge()
			player.skills.activate_blood_buff()
		set_state(State.DEAD)


func die():
	current_state = State.DEAD
	set_physics_process(false)
	AudioManager.play_sound("enemy_death")
	
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
