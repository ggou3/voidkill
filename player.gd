class_name Player
extends CharacterBody3D

const WALK_SPEED = 10.0
const CROUCH_SPEED = 3.5
const JUMP_VELOCITY = 11.0 

const GROUND_ACCEL = 14.0
const GROUND_FRICTION = 14.0
const AIR_ACCEL = 1.5
const AIR_FRICTION = 0.0

const MIN_SLIDE_SPEED = 7.0
const NORMAL_SLIDE_FRICTION = 14.0  
const BLOOD_SLIDE_FRICTION = 4.0    

var gravity = ProjectSettings.get_setting("physics/3d/default_gravity")

var is_crouched = false
var is_sliding = false
var is_on_blood = false 
var blood_pool_count: int = 0
var wall_jump_count = 0 
var current_horiz_speed: float = 0.0

signal health_changed(current: int, maximum: int)
signal died
signal speed_updated(speed: float, bhop_chain: int)
signal blood_surf_status_changed(active: bool)

# Настройки механики Wallrun и Wall-jump
@export var wallrun_min_speed: float = 5.0
@export var wallrun_speed: float = 11.0
@export var wallrun_max_speed: float = 25.0
@export var wallrun_max_duration: float = 1.2
@export var wallrun_gravity_scale: float = 0.08
@export var wallrun_jump_vertical_boost: float = 0.7
@export var wallrun_jump_horizontal_boost: float = 8.0
@export var wall_jump_cooldown: float = 0.35

# Настройки отзывчивости управления (Coyote time и Jump buffer)
@export var coyote_time: float = 0.12
@export var jump_buffer_time: float = 0.12

# Настройки фидбека приземления
@export var hard_landing_velocity_threshold: float = 12.0

# Настройки распрыжки (Bunny Hop), воздушного контроля (Air-strafing) и лимитов скорости
@export var normal_max_speed: float = 14.5
@export var blood_buffed_max_speed: float = 25.0
@export var bhop_speed_multiplier: float = 1.03
@export var bhop_blood_speed_multiplier: float = 1.08
@export var bhop_window: float = 0.12
@export var air_accel: float = 50.0
@export var air_wish_cap: float = 2.5

# Настройки навыков
@export var dash_min_interval: float = 0.5:
	set(value):
		dash_min_interval = value
		if skills:
			skills.dash_min_interval = value

var wall_jump_timer: float = 0.0
var last_wall_jump_normal: Vector3 = Vector3.ZERO
var coyote_timer: float = 0.0
var jump_buffer_timer: float = 0.0
var has_jumped: bool = false
var time_on_ground: float = 0.0
var air_time: float = 0.0
var prev_air_time: float = 0.0
var bhop_chain: int = 0
var footstep_timer: float = 0.0

var is_wallrunning: bool = false
var wallrun_side: float = 0.0 # -1.0 = стена слева, 1.0 = стена справа
var wallrun_timer: float = 0.0
var wallrun_normal: Vector3 = Vector3.ZERO
var wallrun_cooldown: float = 0.0
var last_wallrun_normal: Vector3 = Vector3.ZERO
var wallrun_exhausted: bool = false

@onready var head = $Head
@onready var collision_shape = $CollisionShape3D
@onready var weapons = $WeaponManager
@onready var skills = $SkillManager
@onready var post_process_rect: ColorRect = get_node_or_null("CanvasLayer/ColorRect")
@onready var left_wall_ray: RayCast3D = get_node_or_null("LeftWallRay")
@onready var right_wall_ray: RayCast3D = get_node_or_null("RightWallRay")
@onready var health_component: PlayerHealth = $PlayerHealth
@onready var combat: PlayerCombat = $PlayerCombat
@onready var bpm_system: BPMSystem = $BPMSystem

# Проксирующие свойства к PlayerHealth: внешний код (враги, HUD) обращается к player.health / is_dead напрямую
var max_health: int:
	get:
		return health_component.max_health if health_component else 100
	set(value):
		if health_component:
			health_component.max_health = value
var health: int:
	get:
		return health_component.health if health_component else 100
	set(value):
		if health_component:
			health_component.health = value
var is_dead: bool:
	get:
		return health_component.is_dead if health_component else false
	set(value):
		if health_component:
			health_component.is_dead = value

func is_blood_active() -> bool:
	return is_on_blood

func get_current_max_speed() -> float:
	return lerp(normal_max_speed, blood_buffed_max_speed, bpm_system.get_bpm_ratio())

func _ready():
	is_wallrunning = false
	wallrun_side = 0.0
	wallrun_timer = 0.0
	wallrun_cooldown = 0.0
	last_wallrun_normal = Vector3.ZERO
	wallrun_exhausted = false
	coyote_timer = 0.0
	jump_buffer_timer = 0.0
	has_jumped = false
	time_on_ground = 0.0
	air_time = 0.0
	prev_air_time = 0.0
	bhop_chain = 0
	health_component.health_changed.connect(health_changed.emit)
	health_component.died.connect(_on_health_died)
	health_component.setup(self)
	combat.setup(self)
	bpm_system.setup(self)
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	collision_shape.shape = collision_shape.shape.duplicate()
	floor_snap_length = 0.4 
	floor_max_angle = deg_to_rad(60.0)
	# Идеальное сохранение скорости на склонах от движка Godot:
	floor_constant_speed = true 
	
	if skills:
		skills.dash_min_interval = dash_min_interval

func _input(event):
	if is_dead:
		return
		
	if event.is_action_pressed("ui_cancel"):
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_1: weapons.switch_weapon(0) 
		elif event.keycode == KEY_2: weapons.switch_weapon(1) 
		elif event.keycode == KEY_3: weapons.switch_weapon(2)
		elif event.keycode == KEY_4: weapons.switch_weapon(3)
			
	if event.is_action_pressed("shoot"):
		weapons.shoot(bpm_system.has_infinite_ammo())
	elif event.is_action_pressed("alt_fire") or (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed):
		weapons.alt_shoot(bpm_system.has_infinite_ammo())
	if event.is_action_pressed("reload"):
		weapons.reload()
		
	if event.is_action_pressed("jump") and not event.is_echo() and not skills.is_slamming:
		jump_buffer_timer = jump_buffer_time
		
	if event.is_action_pressed("dash"):
		if skills.trigger_dash(Input.get_vector("move_left", "move_right", "move_forward", "move_backward"), transform.basis):
			coyote_timer = 0.0
	if event.is_action_pressed("slam"):
		coyote_timer = 0.0
		jump_buffer_timer = 0.0
		skills.trigger_slam()
	if event.is_action_pressed("melee") and not event.is_echo():
		combat.perform_melee()
	if event.is_action_pressed("debug_max_bpm") or (event is InputEventKey and event.pressed and not event.is_echo() and (event.keycode == KEY_T or event.physical_keycode == KEY_T)):
		if bpm_system is BPMSystem:
			bpm_system.force_max_bpm()

func _process(_delta):
	if is_dead:
		return
		
	var current_speed: float = Vector2(velocity.x, velocity.z).length()
	speed_updated.emit(current_speed, bhop_chain)
	var blood_surf = is_sliding and is_on_blood
	blood_surf_status_changed.emit(blood_surf)
	
	if post_process_rect and post_process_rect.material:
		post_process_rect.material.set_shader_parameter("player_speed", current_speed)
		var current_bpm: float = bpm_system.bpm if is_instance_valid(bpm_system) else 50.0
		# Интерполяция внутри тира OVERDRIVE: нелинейный рост (pow 0.6) для усиления контраста на подходе к пику
		var overdrive_factor: float = pow(clampf((current_bpm - 180.0) / 20.0, 0.0, 1.0), 0.6)
		post_process_rect.material.set_shader_parameter("overdrive_factor", overdrive_factor)

func _physics_process(delta):
	if is_dead:
		if not is_on_floor():
			velocity.y -= gravity * 2.5 * delta
			move_and_slide()
		return
		
	var input_dir = Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
	current_horiz_speed = Vector2(velocity.x, velocity.z).length()
	
	# Обновление таймеров отзывчивости управления (Coyote time и Jump buffer)
	if jump_buffer_timer > 0.0:
		jump_buffer_timer -= delta
		
	combat.tick_cooldown(delta)

	if wall_jump_timer > 0.0:
		wall_jump_timer -= delta
		
	if is_on_floor():
		if not has_jumped:
			coyote_timer = coyote_time
		if air_time > 0.0:
			prev_air_time = air_time
		air_time = 0.0
		time_on_ground += delta
		if time_on_ground > 0.2:
			bhop_chain = 0
	else:
		air_time += delta
		time_on_ground = 0.0
		coyote_timer -= delta
	
	if wallrun_cooldown > 0.0:
		wallrun_cooldown -= delta

	# Воспроизведение звуков шагов при беге/ходьбе по земле или wallrun
	var is_walking_on_floor = is_on_floor() and not is_sliding and not skills.is_dashing and not skills.is_slamming and current_horiz_speed > 1.5
	var is_stepping = is_walking_on_floor or (is_wallrunning and current_horiz_speed > 3.0)
	if is_stepping:
		footstep_timer -= delta
		if footstep_timer <= 0.0:
			AudioManager.play_sound("footstep")
			var step_interval = clamp(3.2 / max(2.0, current_horiz_speed), 0.22, 0.48)
			footstep_timer = step_interval
	else:
		footstep_timer = min(footstep_timer, 0.15)

	# Проверка условий входа в wallrun
	if not is_on_floor() and not is_wallrunning and not skills.is_dashing and not skills.is_slamming and wallrun_cooldown <= 0.0:
		if current_horiz_speed >= wallrun_min_speed:
			var wall_info = check_wallrun_wall()
			if wall_info.found:
				var is_same_wall = wallrun_exhausted and (wall_info.normal.dot(last_wallrun_normal) > 0.7)
				if not is_same_wall:
					var vel_h = Vector3(velocity.x, 0, velocity.z).normalized()
					# Игрок движется в сторону стены или вдоль неё (не от неё)
					if vel_h.dot(wall_info.normal) < 0.2:
						start_wallrun(wall_info.normal, wall_info.side)

	# Если во время wallrun активирован дэш или слэм — выходим из wallrun
	if is_wallrunning and (skills.is_dashing or skills.is_slamming):
		end_wallrun()
	
	head.update_visuals(delta, current_horiz_speed, is_on_floor(), is_sliding, skills.is_dashing, input_dir, weapons.is_reloading, wallrun_side if is_wallrunning else 0.0)

	var wants_crouch = Input.is_action_pressed("slide")

	if wants_crouch and not is_crouched and not skills.is_slamming and not is_wallrunning:
		is_crouched = true
		collision_shape.shape.height = 1.0
		collision_shape.position.y = -0.5
		head.trigger_slide_animation(true)
	elif not wants_crouch and is_crouched:
		is_crouched = false
		is_sliding = false
		collision_shape.shape.height = 2.0
		collision_shape.position.y = 0.0
		head.trigger_slide_animation(false)

	if is_crouched and is_on_floor() and current_horiz_speed >= MIN_SLIDE_SPEED:
		is_sliding = true
	if is_sliding and current_horiz_speed < CROUCH_SPEED + 0.8:
		is_sliding = false

	# Гравитация в воздухе (при wallrun гравитация своя, существенно сниженная)
	if not is_on_floor() and not skills.is_dashing and not skills.is_slamming and not is_wallrunning:
		velocity.y -= gravity * 2.5 * delta

	if Input.is_action_just_pressed("jump") and not skills.is_slamming:
		jump_buffer_timer = jump_buffer_time

	if jump_buffer_timer > 0.0 and not skills.is_slamming:
		handle_jump()

	velocity = skills.process_dash(delta, velocity)
	velocity = skills.process_slam(delta, velocity)

	var direction = (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	var vel_2d = Vector2(velocity.x, velocity.z)

	if not skills.is_slamming and not skills.is_dashing:
		if is_wallrunning:
			process_wallrun_physics(delta, input_dir)
		elif is_sliding and not has_jumped:
			vel_2d = handle_slide_physics(vel_2d, direction, delta)
			velocity.x = vel_2d.x
			velocity.z = vel_2d.y
		else:
			vel_2d = handle_walk_physics(vel_2d, direction, current_horiz_speed, delta)
			velocity.x = vel_2d.x
			velocity.z = vel_2d.y

	# Глобальное ограничение максимальной скорости по горизонтали с учетом баффа крови
	var current_cap = get_current_max_speed()
	var cur_vel_2d = Vector2(velocity.x, velocity.z)
	if cur_vel_2d.length() > current_cap:
		cur_vel_2d = cur_vel_2d.normalized() * current_cap
		velocity.x = cur_vel_2d.x
		velocity.z = cur_vel_2d.y

	# Отслеживаем недавнюю пиковую скорость (до возможного гашения скорости столкновениями)
	var h_vel_len = Vector2(velocity.x, velocity.z).length()
	if skills and skills.is_dashing:
		h_vel_len = max(h_vel_len, skills.dash_current_speed)
	combat.track_peak_speed(h_vel_len, delta)

	var was_in_air = not is_on_floor()
	var fall_speed = velocity.y 
	
	# Запоминаем полную скорость до удара о геометрию
	var pre_speed = velocity.length()
	
	move_and_slide()
	
	# При приземлении на пол сбрасываем wallrun и счетчик обычных прыжков от стены
	if is_on_floor():
		wall_jump_count = 0
		wall_jump_timer = 0.0
		last_wall_jump_normal = Vector3.ZERO
		if is_wallrunning:
			end_wallrun()
		wallrun_exhausted = false
		last_wallrun_normal = Vector3.ZERO
		if velocity.y <= 0.0:
			has_jumped = false
	
	# Принудительно восстанавливаем скорость, если мы скользим на рампе
	if is_sliding and is_on_floor():
		var fn = get_floor_normal()
		if fn.y < 0.99:
			var current_speed = velocity.length()
			if current_speed < pre_speed - 0.5:
				var slide_dir = velocity.normalized()
				if slide_dir != Vector3.ZERO:
					velocity = slide_dir * pre_speed
	
	if was_in_air and is_on_floor() and not skills.is_slamming:
		var abs_fall = abs(fall_speed)
		if abs_fall >= hard_landing_velocity_threshold:
			head.trigger_hard_landing(abs_fall, hard_landing_velocity_threshold)
		elif fall_speed < -4.0: 
			head.add_recoil(clamp(abs_fall * 0.0015, 0.01, 0.04), 0.0)

	# Управление процедурным зацикленным звуком скольжения (slide)
	var is_slide_active = is_sliding and is_on_floor() and not is_dead
	AudioManager.set_slide_active(is_slide_active)

func _exit_tree():
	AudioManager.set_slide_active(false)

func handle_jump() -> bool:
	var cap = get_current_max_speed()
	if is_on_floor() or coyote_timer > 0.0:
		velocity.y = JUMP_VELOCITY
		var speed_2d = Vector2(velocity.x, velocity.z).length()
		
		if is_on_floor():
			var floor_normal = get_floor_normal()
			if floor_normal.y < 0.99 and is_sliding: 
				velocity.y += speed_2d * 0.4
			
		var was_sliding = is_sliding
		if is_sliding:
			var boost_limit = cap
			if speed_2d < boost_limit:
				var boosted = min(speed_2d * 1.15, boost_limit)
				var dir = Vector2(velocity.x, velocity.z).normalized()
				if dir == Vector2.ZERO: dir = Vector2(-transform.basis.z.x, -transform.basis.z.z).normalized()
				velocity.x = dir.x * boosted
				velocity.z = dir.y * boosted
			is_sliding = false

		# Проверка условий успешного Bunny Hop (независимо от того, был ли слайд):
		# 1. Игрок только что приземлился из воздуха (был в воздухе хотя бы 0.08с)
		# 2. Прыжок совершен сразу при приземлении: через буфер прыжка или время на земле <= bhop_window
		# 3. Имеется начальная скорость движения (не прыжок с места)
		var is_clean_bhop = (prev_air_time >= 0.08 or air_time >= 0.08 or coyote_timer > 0.0) \
			and (jump_buffer_timer > 0.0 or time_on_ground <= bhop_window) \
			and speed_2d >= (WALK_SPEED * 0.7)
			
		if is_clean_bhop:
			var bpm_r = bpm_system.get_bpm_ratio()
			if not was_sliding:
				var mult = lerp(bhop_speed_multiplier, bhop_blood_speed_multiplier, bpm_r)
				var boosted = clamp(speed_2d * mult, speed_2d, cap)
				var dir = Vector2(velocity.x, velocity.z).normalized()
				if dir == Vector2.ZERO:
					var input_dir = Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
					if input_dir != Vector2.ZERO:
						var wish = (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
						dir = Vector2(wish.x, wish.z).normalized()
					else:
						dir = Vector2(-transform.basis.z.x, -transform.basis.z.z).normalized()
				velocity.x = dir.x * boosted
				velocity.z = dir.y * boosted
			bhop_chain += 1
			head.add_recoil(lerp(0.035, 0.045, bpm_r), 0.0)
			time_on_ground = 0.0
			prev_air_time = 0.0
			if bpm_system is BPMSystem:
				bpm_system.add_combat_momentum(0.04)
				
		coyote_timer = 0.0
		jump_buffer_timer = 0.0
		has_jumped = true
		AudioManager.play_sound("jump")
		return true
				
	elif is_wallrunning:
		# Пологий прыжок из состояния wallrun:
		# Умеренный вертикальный импульс + сохранение набранного импульса вперед + отталкивание от стены
		var forward = -transform.basis.z
		forward.y = 0.0
		var wall_tangent = (forward - wallrun_normal * forward.dot(wallrun_normal)).normalized()
		var cur_speed = Vector2(velocity.x, velocity.z).length()
		
		velocity.y = JUMP_VELOCITY * wallrun_jump_vertical_boost
		var jump_horiz = (wallrun_normal * wallrun_jump_horizontal_boost) + (wall_tangent * max(cur_speed, wallrun_speed) * 1.05)
		var jump_h_len = jump_horiz.length()
		if jump_h_len > cap:
			jump_horiz = jump_horiz.normalized() * cap
		velocity.x = jump_horiz.x
		velocity.z = jump_horiz.z
		
		head.add_recoil(0.08, 0.0)
		wallrun_cooldown = 0.25
		end_wallrun()
		wall_jump_count = 1
		wall_jump_timer = wall_jump_cooldown
		last_wall_jump_normal = wallrun_normal
		coyote_timer = 0.0
		jump_buffer_timer = 0.0
		has_jumped = true
		time_on_ground = 0.0
		air_time = 0.1
		prev_air_time = 0.1
		AudioManager.play_sound("jump")
		return true
		
	elif is_on_wall():
		# Обычный wall-jump
		var wall_normal = get_wall_normal()
		
		# Защита от эксплойта зависания на стене: кулдаун между прыжками от одной и той же стены
		if wall_jump_timer > 0.0:
			var is_same_side = (last_wall_jump_normal != Vector3.ZERO and wall_normal.dot(last_wall_jump_normal) > 0.4)
			if is_same_side:
				return false
				
		var push_multiplier = max(0.1, 1.0 - (wall_jump_count * 0.3))
		
		velocity.y = JUMP_VELOCITY * 0.85 * push_multiplier
		var wall_speed = min(12.0 * push_multiplier, cap)
		velocity.x = wall_normal.x * wall_speed
		velocity.z = wall_normal.z * wall_speed
		head.add_recoil(0.08 * push_multiplier, 0.0)
		wall_jump_count += 1
		wall_jump_timer = wall_jump_cooldown
		last_wall_jump_normal = wall_normal
		coyote_timer = 0.0
		jump_buffer_timer = 0.0
		has_jumped = true
		time_on_ground = 0.0
		air_time = 0.1
		prev_air_time = 0.1
		AudioManager.play_sound("jump")
		return true
		
	return false

func check_wallrun_wall() -> Dictionary:
	var result = { "found": false, "normal": Vector3.ZERO, "side": 0.0 }
	
	if left_wall_ray:
		left_wall_ray.force_raycast_update()
		if left_wall_ray.is_colliding():
			var n = left_wall_ray.get_collision_normal()
			if abs(n.y) < 0.25:
				result.found = true
				result.normal = n
				result.side = -1.0
				return result
				
	if right_wall_ray:
		right_wall_ray.force_raycast_update()
		if right_wall_ray.is_colliding():
			var n = right_wall_ray.get_collision_normal()
			if abs(n.y) < 0.25:
				result.found = true
				result.normal = n
				result.side = 1.0
				return result
				
	if is_on_wall():
		var n = get_wall_normal()
		if abs(n.y) < 0.25:
			var side_dot = (-n).dot(transform.basis.x)
			var side = 1.0 if side_dot > 0.0 else -1.0
			result.found = true
			result.normal = n
			result.side = side
			return result
			
	return result

func start_wallrun(normal: Vector3, side: float):
	is_wallrunning = true
	wallrun_side = side
	wallrun_normal = normal
	wallrun_timer = 0.0
	wall_jump_count = 0
	wallrun_exhausted = false
	coyote_timer = 0.0
	
	# Срезаем падение вниз при входе в wallrun
	if velocity.y < 0.0:
		velocity.y = 0.0
	elif velocity.y > 2.5:
		velocity.y = 2.5

func end_wallrun():
	if not is_wallrunning:
		return
	last_wallrun_normal = wallrun_normal
	wallrun_exhausted = true
	is_wallrunning = false
	wallrun_side = 0.0
	wallrun_timer = 0.0
	wallrun_cooldown = 0.2

func process_wallrun_physics(delta: float, input_dir: Vector2):
	wallrun_timer += delta
	
	# Если игрок жмет "назад" (S), прекращаем wallrun
	if input_dir.y > 0.5:
		end_wallrun()
		return
		
	# Проверяем, что стена всё ещё рядом или истекло максимальное время
	var wall_info = check_wallrun_wall()
	if not wall_info.found or wallrun_timer >= wallrun_max_duration:
		end_wallrun()
		return
		
	wallrun_normal = wall_info.normal
	wallrun_side = wall_info.side
	
	# Направление взгляда игрока в горизонтальной плоскости
	var forward = -transform.basis.z
	forward.y = 0.0
	if forward.length_squared() > 0.001:
		forward = forward.normalized()
	else:
		forward = -Vector3.FORWARD
		
	# Касательная к стене
	var wall_tangent = (forward - wallrun_normal * forward.dot(wallrun_normal)).normalized()
	
	# Если игрок отвернулся от стены слишком сильно (> 75 градусов)
	if wall_tangent.dot(forward) < 0.25:
		end_wallrun()
		return
		
	# Поддерживаем и разгоняем скорость вдоль стены вплоть до общего потолка скорости (14.5..25.0 м/с)
	var cur_horiz = Vector2(velocity.x, velocity.z).length()
	var max_cap = get_current_max_speed()
	var run_speed = clamp(max(cur_horiz, wallrun_speed) + delta * 2.0, wallrun_speed, max_cap)
		
	var move_vel = wall_tangent * run_speed
	
	# Небольшой прижим к стене (0.8 м/с), предотвращающий случайный отрыв
	velocity.x = move_vel.x - wallrun_normal.x * 0.8
	velocity.z = move_vel.z - wallrun_normal.z * 0.8
	
	# Постепенное медленное снижение по вертикали во время wallrun,
	# усиливающееся ближе к истечению времени (ощущение ослабевающего зацепа)
	var t_ratio = clamp(wallrun_timer / wallrun_max_duration, 0.0, 1.0)
	var slip_accel = lerp(gravity * 0.12, gravity * 1.5, t_ratio * t_ratio)
	velocity.y -= slip_accel * delta

func handle_slide_physics(vel_2d: Vector2, direction: Vector3, delta: float) -> Vector2:
	var bpm_r = bpm_system.get_bpm_ratio()
	if direction:
		var current_slide_speed = vel_2d.length()
		if current_slide_speed > 0.1:
			var turn_speed = lerp(1.5, 3.0, bpm_r)
			var target_dir = Vector2(direction.x, direction.z)
			vel_2d = vel_2d.normalized().lerp(target_dir, turn_speed * delta).normalized() * current_slide_speed
	
	var active_friction = lerp(NORMAL_SLIDE_FRICTION, BLOOD_SLIDE_FRICTION, bpm_r)
	vel_2d = vel_2d.move_toward(Vector2.ZERO, active_friction * delta)
	
	var cap = get_current_max_speed()
	if is_on_floor():
		var floor_normal = get_floor_normal()
		if floor_normal.y < 0.99: 
			var slope_down = Vector3.DOWN.slide(floor_normal).normalized()
			var max_slope = cap
			if vel_2d.length() < max_slope:
				vel_2d += Vector2(slope_down.x, slope_down.z) * 32.0 * delta 
				
	if vel_2d.length() > cap:
		vel_2d = vel_2d.normalized() * cap
		
	return vel_2d

func handle_walk_physics(vel_2d: Vector2, direction: Vector3, _current_speed: float, delta: float) -> Vector2:
	var is_airborne = not is_on_floor() or has_jumped
	var cap = get_current_max_speed()
	
	if is_airborne:
		if direction:
			var wish_dir = Vector2(direction.x, direction.z).normalized()
			var speed_2d = vel_2d.length()
			if speed_2d < WALK_SPEED:
				vel_2d = vel_2d.lerp(wish_dir * WALK_SPEED, 4.0 * delta)
			else:
				# Quake / Source air-strafe physics:
				# Проекция текущей скорости на вектор желаемого направления движения
				var cur_wish_speed = vel_2d.dot(wish_dir)
				var add_speed = air_wish_cap - cur_wish_speed
				if add_speed > 0.0:
					var eff_accel = air_accel * lerp(1.0, 1.3, bpm_system.get_bpm_ratio())
					var accel_amount = min(eff_accel * delta, add_speed)
					vel_2d += wish_dir * accel_amount
				
				# Плавный CPM поворот вектора скорости без потери набранной величины скорости
				var steer_rate = lerp(1.5, 2.4, bpm_system.get_bpm_ratio())
				if vel_2d.length_squared() > 0.001:
					vel_2d = vel_2d.normalized().lerp(wish_dir, steer_rate * delta).normalized() * vel_2d.length()
		else:
			# В воздухе без нажатых клавиш движения трение отсутствует
			if AIR_FRICTION > 0.0:
				vel_2d = vel_2d.move_toward(Vector2.ZERO, AIR_FRICTION * delta)
	else:
		# На земле (Ground physics)
		var target_speed = CROUCH_SPEED if is_crouched else WALK_SPEED
		if direction:
			var wish_dir = Vector2(direction.x, direction.z).normalized()
			var speed_2d = vel_2d.length()
			
			if speed_2d > target_speed + 0.8 and time_on_ground <= bhop_window:
				# Кратковременное переходное окно (0.12 сек) после приземления на высокой скорости:
				# Сохраняем набранный импульс для следующего прыжка (bhop) или слайда,
				# при этом давая полное и отзывчивое управление направлением (GROUND_ACCEL)
				vel_2d = vel_2d.lerp(wish_dir * speed_2d, GROUND_ACCEL * delta)
				var preserved_speed = move_toward(speed_2d, target_speed, GROUND_FRICTION * 0.5 * delta)
				if vel_2d.length_squared() > 0.001:
					vel_2d = vel_2d.normalized() * preserved_speed
			else:
				# Обычная ходьба/бег по земле: отличный отклик, высокое сцепление, без "ледяного" скольжения
				vel_2d = vel_2d.lerp(wish_dir * target_speed, GROUND_ACCEL * delta)
		else:
			# Мгновенная отзывчивая остановка при отпускании клавиш движения (нормальное трение)
			vel_2d = vel_2d.move_toward(Vector2.ZERO, GROUND_FRICTION * 16.0 * delta)
			
	# Ограничение текущим потолком максимальной скорости (с учетом баффа крови)
	if vel_2d.length() > cap:
		vel_2d = vel_2d.normalized() * cap

	return vel_2d

# --- Делегирование в PlayerHealth (внешние вызовы: враги, снаряды, статус-эффекты, HUD) ---

func take_damage(amount: int, knockback_vector: Vector3 = Vector3.ZERO, hit_pos: Vector3 = Vector3.ZERO):
	health_component.take_damage(amount, knockback_vector, hit_pos)

func heal(amount: int, is_melee_bonus: bool = false):
	health_component.heal(amount, is_melee_bonus)

func restart_game():
	health_component.restart_game()

## Ретрансляция смерти подписчикам Player и сброс состояния движения
func _on_health_died():
	died.emit()
	end_wallrun()
	coyote_timer = 0.0
	jump_buffer_timer = 0.0
	has_jumped = false
	time_on_ground = 0.0
	air_time = 0.0
	prev_air_time = 0.0
	bhop_chain = 0
	velocity.x = 0.0
	velocity.z = 0.0
	is_crouched = false
	is_sliding = false
	AudioManager.set_slide_active(false)
	collision_shape.shape.height = 2.0
	collision_shape.position.y = 0.0
