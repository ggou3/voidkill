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

var max_health: int = 100
var health: int = 100
var is_dead: bool = false

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

# Настройки ближнего боя (Melee) и добивания (Execute)
@export var melee_damage: int = 45
@export var melee_range: float = 2.5
@export var melee_cooldown: float = 2.0
@export var melee_lunge_boost: float = 4.0
@export var execute_health_threshold: float = 0.25

# Настройки конусной ударной волны на максимальной скорости
@export var cone_melee_speed_threshold: float = 16.5
@export var cone_melee_range: float = 7.5
@export var cone_melee_angle: float = 100.0
@export var cone_melee_base_damage: int = 60
@export var cone_melee_base_knockback: float = 84.0
@export var cone_min_damage_ratio: float = 0.35
@export var cone_min_knockback_ratio: float = 0.40

var melee_timer: float = 0.0
var recent_peak_speed: float = 0.0
var recent_peak_timer: float = 0.0
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
@onready var speed_label = $HUD/SpeedLabel 
@onready var blood_buff_label = get_node_or_null("HUD/BloodBuffLabel")
@onready var health_bar: ProgressBar = get_node_or_null("HUD/HealthBar")
@onready var hp_text: Label = get_node_or_null("HUD/HealthBar/HPText")
@onready var health_label: Label = hp_text
@onready var crosshair = get_node_or_null("HUD/Crosshair")

var _health_bg_style: StyleBoxFlat
var _health_fill_style: StyleBoxFlat
var _health_tween: Tween = null
var _last_displayed_health: int = -1
@onready var game_over_screen = get_node_or_null("HUD/GameOverScreen")
@onready var restart_button = get_node_or_null("HUD/GameOverScreen/VBoxContainer/RestartButton")
@onready var post_process_rect: ColorRect = get_node_or_null("CanvasLayer/ColorRect")
@onready var left_wall_ray: RayCast3D = get_node_or_null("LeftWallRay")
@onready var right_wall_ray: RayCast3D = get_node_or_null("RightWallRay")
@onready var game_manager: Node = get_node_or_null("/root/GameManager")

func _get_game_manager() -> Node:
	if not game_manager and is_inside_tree():
		game_manager = get_node_or_null("/root/GameManager")
	return game_manager

func is_blood_active() -> bool:
	return is_on_blood

func has_infinite_ammo() -> bool:
	return skills != null and skills.has_method("get_bpm_tier") and skills.get_bpm_tier() == "OVERDRIVE"

func get_bpm_ratio() -> float:
	var bpm_val = skills.bpm if is_instance_valid(skills) else 50.0
	return clampf((bpm_val - 50.0) / 150.0, 0.0, 1.0)

func get_current_max_speed() -> float:
	return lerp(normal_max_speed, blood_buffed_max_speed, get_bpm_ratio())

func get_bpm_damage_reduction() -> float:
	return lerp(0.0, 0.30, get_bpm_ratio())

func _ready():
	is_dead = false
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
	health = max_health
	_setup_health_bar()
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	collision_shape.shape = collision_shape.shape.duplicate()
	floor_snap_length = 0.4 
	floor_max_angle = deg_to_rad(60.0)
	# Идеальное сохранение скорости на склонах от движка Godot:
	floor_constant_speed = true 
	
	if skills:
		skills.dash_min_interval = dash_min_interval
		
	if game_over_screen:
		game_over_screen.visible = false
	if crosshair:
		crosshair.visible = true
	if restart_button:
		restart_button.pressed.connect(restart_game)
		
	var gm = _get_game_manager()
	if gm and not gm.game_over_triggered.is_connected(_on_game_over_triggered):
		gm.game_over_triggered.connect(_on_game_over_triggered)

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
		weapons.shoot(has_infinite_ammo())
	elif event.is_action_pressed("alt_fire") or (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed):
		weapons.alt_shoot(has_infinite_ammo())
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
		perform_melee()
	if event.is_action_pressed("debug_max_bpm") or (event is InputEventKey and event.pressed and not event.is_echo() and (event.keycode == KEY_T or event.physical_keycode == KEY_T)):
		if skills and skills.has_method("force_max_bpm"):
			skills.force_max_bpm()

func _process(_delta):
	if is_dead:
		return
		
	var current_speed: float = Vector2(velocity.x, velocity.z).length()
	var bhop_text = ""
	if bhop_chain > 0:
		bhop_text = (" (BHOP x" + str(bhop_chain) + ")")
	speed_label.text = "SPEED: " + str(snapped(current_speed, 0.1)) + bhop_text
	if health != _last_displayed_health:
		_update_health_display(true)
	weapons.update_hud(has_infinite_ammo())
	
	if blood_buff_label:
		var blood_surf = is_sliding and is_on_blood
		blood_buff_label.visible = blood_surf
		if blood_surf:
			blood_buff_label.text = "★ BLOOD SURF (MOMENTUM +4%) ★"
	
	if post_process_rect and post_process_rect.material:
		post_process_rect.material.set_shader_parameter("player_speed", current_speed)
		var current_bpm: float = skills.bpm if is_instance_valid(skills) else 50.0
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
		
	if melee_timer > 0.0:
		melee_timer -= delta
		
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
	if h_vel_len >= recent_peak_speed:
		recent_peak_speed = h_vel_len
		recent_peak_timer = 0.35
	else:
		recent_peak_timer -= delta
		if recent_peak_timer <= 0.0:
			recent_peak_speed = h_vel_len

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
			var bpm_r = get_bpm_ratio()
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
			if skills and skills.has_method("add_combat_momentum"):
				skills.add_combat_momentum(0.04)
				
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
	var bpm_r = get_bpm_ratio()
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
					var eff_accel = air_accel * lerp(1.0, 1.3, get_bpm_ratio())
					var accel_amount = min(eff_accel * delta, add_speed)
					vel_2d += wish_dir * accel_amount
				
				# Плавный CPM поворот вектора скорости без потери набранной величины скорости
				var steer_rate = lerp(1.5, 2.4, get_bpm_ratio())
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

func _setup_health_bar():
	if not health_bar:
		return
		
	_health_bg_style = StyleBoxFlat.new()
	_health_bg_style.bg_color = Color(0.08, 0.08, 0.09, 0.85)
	_health_bg_style.border_color = Color(0.35, 0.35, 0.38, 0.9)
	_health_bg_style.set_border_width_all(2)
	_health_bg_style.set_corner_radius_all(3)
	
	_health_fill_style = StyleBoxFlat.new()
	_health_fill_style.bg_color = Color(0.2, 0.85, 0.3, 1.0)
	_health_fill_style.set_corner_radius_all(2)
	
	health_bar.add_theme_stylebox_override("background", _health_bg_style)
	health_bar.add_theme_stylebox_override("fill", _health_fill_style)
	
	health_bar.max_value = max_health
	health_bar.value = health
	_update_health_display(false)

func _update_health_display(animate: bool = true):
	_last_displayed_health = health
	var current_hp = max(0, health)
	
	if hp_text:
		hp_text.text = "%d / %d" % [current_hp, max_health]
		
	if not health_bar:
		return
		
	health_bar.max_value = max_health
	
	# Пороги здоровья:
	# > 50%: Зеленый / нейтральный
	# 25% - 50%: Желтый
	# < 25%: Красный критический
	var ratio = float(current_hp) / float(max_health) if max_health > 0 else 0.0
	var target_color: Color
	if ratio > 0.5:
		target_color = Color(0.2, 0.85, 0.3, 1.0)
	elif ratio >= 0.25:
		target_color = Color(0.95, 0.8, 0.15, 1.0)
	else:
		target_color = Color(0.95, 0.2, 0.2, 1.0)
		
	if animate and is_inside_tree():
		if _health_tween and _health_tween.is_valid():
			_health_tween.kill()
		_health_tween = create_tween().set_parallel(true)
		_health_tween.tween_property(health_bar, "value", float(current_hp), 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		if _health_fill_style:
			_health_tween.tween_property(_health_fill_style, "bg_color", target_color, 0.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	else:
		if _health_tween and _health_tween.is_valid():
			_health_tween.kill()
		health_bar.value = float(current_hp)
		if _health_fill_style:
			_health_fill_style.bg_color = target_color

func take_damage(amount: int, knockback_vector: Vector3 = Vector3.ZERO, _hit_pos: Vector3 = Vector3.ZERO):
	if is_dead or amount <= 0:
		return
	var reduction = get_bpm_damage_reduction()
	var final_damage = max(1, int(round(float(amount) * (1.0 - reduction))))
	health = max(0, health - final_damage)
	_update_health_display(true)
	if skills and skills.has_method("drop_bpm_on_damage"):
		skills.drop_bpm_on_damage()
	if head:
		head.add_recoil(0.25, 0.0)
	if knockback_vector != Vector3.ZERO:
		velocity += knockback_vector
	if health <= 0:
		die()

func heal(amount: int, is_melee_bonus: bool = false):
	if is_dead or amount <= 0:
		return
	var old_health = health
	health = min(max_health, health + amount)
	var _gained = health - old_health
	_update_health_display(true)
	AudioManager.play_sound("player_heal")
	_spawn_heal_feedback(amount, is_melee_bonus)

func _spawn_heal_feedback(heal_amount: int, is_melee_bonus: bool = false):
	var label = Label3D.new()
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.outline_size = 6
	label.outline_modulate = Color.BLACK
	
	if is_melee_bonus:
		label.text = "+%d HP (MELEE SIPHON!)" % heal_amount
		label.modulate = Color(0.2, 1.0, 0.4, 1.0)
		label.font_size = 32
	else:
		label.text = "+%d HP" % heal_amount
		label.modulate = Color(0.3, 0.95, 0.5, 1.0)
		label.font_size = 26
		
	var scene_root = get_tree().current_scene if get_tree().current_scene else get_parent()
	if not scene_root:
		return
	scene_root.add_child(label)
	
	var start_p = global_position + Vector3(randf_range(-0.2, 0.2), 1.2, randf_range(-0.2, 0.2))
	label.global_position = start_p
	
	var target_p = start_p + Vector3(0.0, 0.85, 0.0)
	var tween = create_tween().set_parallel(true)
	tween.tween_property(label, "global_position", target_p, 0.7).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "modulate:a", 0.0, 0.7).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(label.queue_free)

func die():
	if is_dead:
		return
	is_dead = true
	health = 0
	_update_health_display(false)
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
	
	var gm = _get_game_manager()
	if gm:
		gm.trigger_game_over()

func _on_game_over_triggered():
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	if game_over_screen:
		game_over_screen.visible = true
	if crosshair:
		crosshair.visible = false

func restart_game():
	var gm = _get_game_manager()
	if gm:
		gm.restart_game()
	else:
		get_tree().reload_current_scene()

func spawn_cone_shockwave_vfx(from_pos: Vector3, aim_dir: Vector3, range_val: float, angle_deg: float):
	var mesh_inst = MeshInstance3D.new()
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	
	var apex = Vector3.ZERO
	var half_rad = deg_to_rad(angle_deg * 0.5)
	var half_v_rad = deg_to_rad(min(32.0, angle_deg * 0.28))
	var L = range_val
	var rx = L * tan(half_rad)
	var ry = L * tan(half_v_rad)
	
	# 1. Внешний 3D-конус (радиальная мантия и передний фронт)
	var segments = 20
	var rim_pts: Array[Vector3] = []
	for i in range(segments):
		var phi = (float(i) / float(segments)) * (PI * 2.0)
		rim_pts.append(Vector3(rx * cos(phi), ry * sin(phi), -L))
		
	var front_center = Vector3(0, 0, -L)
	for i in range(segments):
		var p1 = rim_pts[i]
		var p2 = rim_pts[(i + 1) % segments]
		
		# Боковые грани конуса от вершины
		st.add_vertex(apex)
		st.add_vertex(p2)
		st.add_vertex(p1)
		
		# Передний фронт ударной волны
		st.add_vertex(front_center)
		st.add_vertex(p1)
		st.add_vertex(p2)
		
	# 2. Внутренний яркий горизонтальный веер-сектор
	var fan_segs = 14
	var fan_pts: Array[Vector3] = []
	for j in range(fan_segs + 1):
		var u = float(j) / float(fan_segs)
		var h_ang = lerp(-half_rad, half_rad, u)
		fan_pts.append(Vector3(L * sin(h_ang), 0.0, -L * cos(h_ang)))
		
	for j in range(fan_segs):
		st.add_vertex(apex)
		st.add_vertex(fan_pts[j + 1])
		st.add_vertex(fan_pts[j])
		
	var mesh = st.commit()
	mesh_inst.mesh = mesh
	
	var mat = StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = Color(1.0, 0.22, 0.08, 0.45)
	mesh_inst.material_override = mat
	
	var scene_root = get_tree().current_scene if get_tree().current_scene else get_parent()
	if not scene_root:
		return
	scene_root.add_child(mesh_inst)
	
	# Смещаем точку спавна чуть вперед от камеры, чтобы отсечь клиппинг камеры
	var spawn_pos = from_pos + aim_dir * 0.35
	mesh_inst.global_position = spawn_pos
	var up_vec = Vector3.UP if abs(aim_dir.y) < 0.99 else Vector3.FORWARD
	mesh_inst.look_at(spawn_pos + aim_dir, up_vec)
	mesh_inst.scale = Vector3(0.15, 0.15, 0.15)
	
	var tween = create_tween()
	# 1. Быстрое расширение конуса вперед до полного размера за 0.18 сек
	tween.tween_property(mesh_inst, "scale", Vector3(1.0, 1.0, 1.0), 0.18).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	
	# 2. Медленное рассеивание и видимость в течение 2.0 секунд
	var fade_tween = create_tween()
	fade_tween.set_parallel(true)
	fade_tween.tween_property(mesh_inst, "scale", Vector3(1.08, 1.08, 1.08), 2.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	fade_tween.tween_property(mat, "albedo_color:a", 0.0, 2.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	fade_tween.chain().tween_callback(mesh_inst.queue_free)

func perform_melee():
	if melee_timer > 0.0 or is_dead or skills.is_slamming:
		return
		
	melee_timer = melee_cooldown
	
	var cur_speed = Vector2(velocity.x, velocity.z).length()
	var effective_speed = max(cur_speed, recent_peak_speed)
	var cap = get_current_max_speed()
	var aim_dir = head.get_aim_direction()
	
	# Строгий порог: конусная ударная волна активируется ТОЛЬКО при скорости >= 16.5 м/с
	var is_cone_shockwave = effective_speed >= cone_melee_speed_threshold
	
	# Инерция и импульс: выпад вперёд в направлении взгляда при ударе в движении, дэше или слайде
	var is_moving = cur_speed > 0.5 or recent_peak_speed > 1.0 or skills.is_dashing or is_sliding
	if is_moving:
		var lunge_dir = Vector3(aim_dir.x, 0.0, aim_dir.z).normalized()
		if lunge_dir != Vector3.ZERO:
			var boost = melee_lunge_boost
			if skills.is_dashing or is_sliding or is_cone_shockwave:
				boost *= 1.3 # Усиленный кинетический выпад при выходе из дэша, слайда или на максимальной скорости
			velocity.x += lunge_dir.x * boost
			velocity.z += lunge_dir.z * boost
			
			# Удерживаем скорость в пределах действующего потолка скорости
			var new_horiz_speed = Vector2(velocity.x, velocity.z).length()
			if new_horiz_speed > cap:
				var clamped_vel = Vector2(velocity.x, velocity.z).normalized() * cap
				velocity.x = clamped_vel.x
				velocity.z = clamped_vel.y
				
	# Визуальная анимация удара левой рукой
	head.play_melee_animation()
	
	# Базовый толчок оружия/камеры при взмахе (усилен при конусной ударной волне)
	head.add_recoil(0.06 if is_cone_shockwave else 0.03, 0.35 if is_cone_shockwave else 0.2)
	
	var space_state = get_world_3d().direct_space_state
	var from_pos = head.camera.global_position
	
	if is_cone_shockwave:
		# Визуальный эффект конуса ударной волны
		spawn_cone_shockwave_vfx(from_pos, aim_dir, cone_melee_range, cone_melee_angle)
		AudioManager.play_sound("melee_heavy_hit")
		
		# РЕЖИМ 1: Конусная ударная волна (AOE) на высокой скорости
		var all_enemies = get_tree().get_nodes_in_group("enemy")
		var half_angle_rad = deg_to_rad(cone_melee_angle * 0.5)
		var min_cos = cos(half_angle_rad)
		var targets_to_hit: Dictionary = {} # Node -> { "dist": float, "dir": Vector3, "hit_pos": Vector3 }
		
		# 1. Сначала проверяем прямую цель под прицелом (RayCast + SphereCast), чтобы прямой фокус НИКОГДА не терялся
		var to_pos = from_pos + aim_dir * cone_melee_range
		var direct_ray = PhysicsRayQueryParameters3D.create(from_pos, to_pos)
		direct_ray.exclude = [self]
		var direct_res = space_state.intersect_ray(direct_ray)
		if not direct_res.is_empty():
			var col = direct_res.collider
			if col and col.is_in_group("enemy") and not ("current_state" in col and col.current_state == col.State.DEAD):
				var e_center = col.global_position + Vector3(0, 0.9, 0)
				targets_to_hit[col] = {
					"dist": from_pos.distance_to(e_center),
					"dir": (e_center - from_pos).normalized(),
					"hit_pos": direct_res.position,
					"is_primary": true
				}
				
		var sphere = SphereShape3D.new()
		sphere.radius = 0.85
		var shape_query = PhysicsShapeQueryParameters3D.new()
		shape_query.shape = sphere
		shape_query.transform = Transform3D(Basis(), from_pos + aim_dir * 1.8)
		shape_query.exclude = [self]
		var close_results = space_state.intersect_shape(shape_query, 8)
		for r in close_results:
			var col = r.collider
			if col and col != self and col.is_in_group("enemy") and not ("current_state" in col and col.current_state == col.State.DEAD):
				if not targets_to_hit.has(col):
					var e_center = col.global_position + Vector3(0, 0.9, 0)
					targets_to_hit[col] = {
						"dist": from_pos.distance_to(e_center),
						"dir": (e_center - from_pos).normalized(),
						"hit_pos": e_center,
						"is_primary": true
					}

		# 2. Сканируем всех врагов в конусе перед игроком
		var flat_aim = Vector2(aim_dir.x, aim_dir.z).normalized()
		for e in all_enemies:
			if not is_instance_valid(e) or targets_to_hit.has(e):
				continue
			if ("current_state" in e and e.current_state == e.State.DEAD) or ("health" in e and e.health <= 0):
				continue
				
			var e_center = e.global_position + Vector3(0, 0.9, 0)
			var to_e = e_center - from_pos
			var dist = to_e.length()
			if dist > cone_melee_range:
				continue
				
			# Проверка по высоте (до 3.5м по высоте)
			if abs(to_e.y) > 3.5:
				continue
				
			# 2D горизонтальный угол конуса для надежного обнаружения
			var flat_to_e = Vector2(to_e.x, to_e.z).normalized()
			var flat_dot = flat_aim.dot(flat_to_e)
			var dir_to_e = to_e / max(0.001, dist)
			var dot_3d = aim_dir.dot(dir_to_e)
			
			# В упор (до 2.0м) захватываем широкий сектор, на дистанции — cone_melee_angle
			if dist <= 2.0:
				if flat_dot < -0.25:
					continue
			else:
				if flat_dot < min_cos and dot_3d < min_cos:
					continue
					
			# Проверка видимости цели (не через сплошные стены)
			var occ_query = PhysicsRayQueryParameters3D.create(from_pos, e_center)
			occ_query.exclude = [self]
			var occ_res = space_state.intersect_ray(occ_query)
			if not occ_res.is_empty():
				var occ_col = occ_res.collider
				# Игнорируем других врагов в траектории конуса — только геометрия стен блокирует удар
				if occ_col != e and not occ_col.is_in_group("enemy"):
					continue
					
			targets_to_hit[e] = {
				"dist": dist,
				"dir": dir_to_e,
				"hit_pos": e_center,
				"is_primary": false
			}
			
		var hit_count = 0
		var killed_any = false
		var executed_any = false
		
		# Если ни одна цель не была под прицелом напрямую, ближайшая цель считается основной
		var has_primary = false
		for d in targets_to_hit.values():
			if d.get("is_primary", false):
				has_primary = true
				break
		if not has_primary and not targets_to_hit.is_empty():
			var min_dist = 999.0
			var primary_e = null
			for e in targets_to_hit.keys():
				if targets_to_hit[e]["dist"] < min_dist:
					min_dist = targets_to_hit[e]["dist"]
					primary_e = e
			if primary_e:
				targets_to_hit[primary_e]["is_primary"] = true
		
		# Нелинейный расчет базового урона конуса:
		# Начинается строго с порога 16.5 м/с и резко возрастает к максимуму (60) на скорости 20.0 м/с
		var high_t = clamp((effective_speed - cone_melee_speed_threshold) / (20.0 - cone_melee_speed_threshold), 0.0, 1.0)
		var speed_base_dmg = lerp(32.0, float(cone_melee_base_damage), pow(high_t, 2.0))
		
		for e in targets_to_hit.keys():
			if not is_instance_valid(e):
				continue
			var data = targets_to_hit[e]
			var dist: float = data["dist"]
			var dir_to_e: Vector3 = data["dir"]
			var hit_pos: Vector3 = data["hit_pos"]
			var is_prim: bool = data.get("is_primary", false)
			
			# Линейное падение урона и силы отталкивания с расстоянием
			var t = clamp(dist / cone_melee_range, 0.0, 1.0)
			var dmg_factor = lerp(1.0, cone_min_damage_ratio, t)
			var knock_factor = lerp(1.0, cone_min_knockback_ratio, t)
			
			# Основная цель melee-удара получает увеличенный урон (direct-hit ударной волны)
			var raw_eff_dmg: int
			if is_prim:
				raw_eff_dmg = int(round(speed_base_dmg * 1.45))
			else:
				raw_eff_dmg = int(round(speed_base_dmg * dmg_factor))
				
			var needle_count: int = 0
			if "needle_count" in e:
				needle_count = e.needle_count
			elif e.get_parent() and "needle_count" in e.get_parent():
				needle_count = e.get_parent().needle_count
			
			var final_multiplier: float = 1.0 + min(needle_count, 15) * 0.04
			var eff_dmg: int = int(round(float(raw_eff_dmg) * final_multiplier))
			
			if needle_count > 0:
				print("[%s] CONE MELEE HIT: BaseEffDmg: %d | Needles: %d | Mult: %.2f | FinalDmg: %d" % [
					e.name, raw_eff_dmg, needle_count, final_multiplier, eff_dmg
				])
				
			var eff_knock_speed = cone_melee_base_knockback * knock_factor
			
			var enemy_cur_hp = e.health if "health" in e else 100
			var enemy_max_hp = e.max_health if "max_health" in e else 100
			var is_exec = (float(enemy_cur_hp) <= float(enemy_max_hp) * execute_health_threshold)
			var final_dmg = max(eff_dmg, enemy_cur_hp) if is_exec else eff_dmg
			var will_kill = is_exec or (enemy_cur_hp <= final_dmg)
			
			var flat_dir = Vector3(dir_to_e.x, 0.0, dir_to_e.z).normalized()
			if flat_dir == Vector3.ZERO:
				flat_dir = Vector3(aim_dir.x, 0.0, aim_dir.z).normalized()
			var knock_vec = flat_dir * eff_knock_speed + Vector3.UP * 7.5
			
			e.take_damage(final_dmg, knock_vec, hit_pos, true, is_exec, true, false, -1, "melee")
			hit_count += 1
			if will_kill:
				killed_any = true
			if is_exec:
				executed_any = true
				
		print("[MELEE] Speed: %.2f (Live: %.2f, Peak: %.2f) | Thresh: %.2f | BaseDmg: %.1f | SHOCKWAVE: true | Hits: %d" % [
			effective_speed, cur_speed, recent_peak_speed, cone_melee_speed_threshold, speed_base_dmg, hit_count
		])
		
		if hit_count > 0:
			head.trigger_melee_impact(executed_any)
			if killed_any and skills:
				skills.add_dash_charge()
	else:
		# РЕЖИМ 2: Одиночный прямой слабый удар ближнего боя (RayCast + SphereCast)
		var to_pos = from_pos + aim_dir * melee_range
		var hit_collider: Node = null
		var hit_pos: Vector3 = to_pos
		
		# 1. Прямой луч
		var ray_query = PhysicsRayQueryParameters3D.create(from_pos, to_pos)
		ray_query.exclude = [self]
		var ray_res = space_state.intersect_ray(ray_query)
		
		if not ray_res.is_empty():
			hit_collider = ray_res.collider
			hit_pos = ray_res.position
		else:
			# 2. SphereCast в направлении удара (сфера радиусом 0.55м) для надежного хитбокса в упор
			var sphere = SphereShape3D.new()
			sphere.radius = 0.55
			var shape_query = PhysicsShapeQueryParameters3D.new()
			shape_query.shape = sphere
			shape_query.transform = Transform3D(Basis(), from_pos + aim_dir * (melee_range * 0.6))
			shape_query.exclude = [self]
			var results = space_state.intersect_shape(shape_query, 8)
			for r in results:
				var col = r.collider
				if col and col != self and (col.is_in_group("enemy") or col.has_method("take_damage")):
					hit_collider = col
					hit_pos = col.global_position + Vector3(0, 0.8, 0)
					break
					
		var hit_anything = false
		if hit_collider and hit_collider.has_method("take_damage"):
			hit_anything = true
			AudioManager.play_sound("melee_hit")
			var enemy_cur_hp: int = hit_collider.health if "health" in hit_collider else 100
			var enemy_max_hp: int = hit_collider.max_health if "max_health" in hit_collider else 100
			
			var needle_count: int = 0
			if "needle_count" in hit_collider:
				needle_count = hit_collider.needle_count
			elif hit_collider.get_parent() and "needle_count" in hit_collider.get_parent():
				needle_count = hit_collider.get_parent().needle_count
				
			var final_multiplier: float = 1.0 + min(needle_count, 15) * 0.04
			var is_execute: bool = (float(enemy_cur_hp) <= float(enemy_max_hp) * execute_health_threshold)
			var eff_melee_damage: int = int(round(float(melee_damage) * final_multiplier))
			var dmg: int = max(eff_melee_damage, enemy_cur_hp) if is_execute else eff_melee_damage
			var will_kill: bool = is_execute or (enemy_cur_hp <= dmg)
			
			if needle_count > 0:
				print("[%s] REGULAR MELEE HIT: BaseDmg: %d | Needles: %d | Mult: %.2f | FinalDmg: %d" % [
					hit_collider.name, melee_damage, needle_count, final_multiplier, dmg
				])
			
			var knock_dir = Vector3(aim_dir.x, 0.0, aim_dir.z).normalized()
			var knock_speed = 21.0 if is_execute else 8.0
			var knockback_vector = knock_dir * knock_speed
			knockback_vector.y = 3.0 if is_execute else 1.5
			
			hit_collider.take_damage(dmg, knockback_vector, hit_pos, true, is_execute, false, false, -1, "melee")
			head.trigger_melee_impact(is_execute)
			
			if will_kill and skills:
				skills.add_dash_charge()
				
		print("[MELEE] Speed: %.2f (Live: %.2f, Peak: %.2f) | Thresh: %.2f | SHOCKWAVE: false | Dmg: %d | Hit: %s" % [
			effective_speed, cur_speed, recent_peak_speed, cone_melee_speed_threshold, melee_damage, str(hit_anything)
		])
