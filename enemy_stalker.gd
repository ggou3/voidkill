extends "res://enemy.gd"

## Враг "Соглядатай" (Stalker Enemy).
## Скрытный преследователь с оптическим искажением пространства (heat haze) вместо полной невидимости.
## По умолчанию в STEALTH: медленно подкрадывается и кружит по флангам NavMesh, невидим для обычной детекции.
## При сближении на 3-4м: 0.4с телеграф (материализация силуэта, вспышка фиолетовых глаз, звуковой шелест).
## Атака из засады: 25 HP урона, после чего 2.0с окно уязвимости (полная видимость).
## При получении урона: маскировка срывается, таймер видимости продлевается до 3.0с отступления.
## Растворение обратно в STEALTH: плавный переход за 1.5 секунды.

enum StalkerState {
	STEALTH_IDLE,    # Ожидание игрока вне зоны детекции (> 15м)
	STEALTH_STALK,   # Скрытное сближение и кружение по флангам (дистанция 3.8-15м)
	TELEGRAPH,       # Телеграф атаки (0.4с) — материализация, вспышка глаз
	VULNERABLE,      # Окно уязвимости после атаки (2.0с) или после получения урона (3.0с)
	DISSOLVING       # Плавное растворение обратно в STEALTH (1.5с)
}

@export var stalker_health: int = 80
@export var stalker_attack_damage: int = 25
@export var stalker_detect_range: float = 15.0
@export var ambush_trigger_dist: float = 3.8
@export var stalk_speed: float = 7.0
@export var vulnerable_speed: float = 6.0
@export var telegraph_duration: float = 0.4
@export var base_vulnerability_duration: float = 2.0
@export var damage_vulnerability_duration: float = 3.0
@export var dissolve_duration: float = 1.5

var stalker_state: StalkerState = StalkerState.STEALTH_IDLE
var current_visibility: float = 0.0
var telegraph_timer: float = 0.0
var vulnerability_timer: float = 0.0
var dissolve_timer: float = 0.0
var stalk_flank_sign: float = 1.0 # 1.0 = обход справа, -1.0 = обход слева
var stalk_update_timer: float = 0.0
const STALK_UPDATE_INTERVAL: float = 0.25

var stalker_shader_mat: ShaderMaterial = null
var hit_flash_tween: Tween = null

const STALKER_EYES_COLOR = Color(0.85, 0.25, 1.0)
const STALKER_BODY_COLOR = Color(0.12, 0.05, 0.18)

func _ready():
	super._ready()
	max_health = stalker_health
	health = stalker_health
	attack_damage = stalker_attack_damage
	detection_range = stalker_detect_range
	move_speed = stalk_speed
	acceleration = 7.5
	attack_range = 2.2
	lunge_cooldown_timer = 999999.0
	
	# Случайный выбор стороны первичного фланкирования
	stalk_flank_sign = 1.0 if randf() > 0.5 else -1.0
	
	# Создаем уникальный экземпляр ShaderMaterial для независимого управления прозрачностью каждого Соглядатая
	if body_mesh:
		var b_mat = body_mesh.get_surface_override_material(0)
		if b_mat is ShaderMaterial:
			stalker_shader_mat = b_mat.duplicate()
			body_mesh.set_surface_override_material(0, stalker_shader_mat)
	if head_mesh and stalker_shader_mat:
		head_mesh.material = stalker_shader_mat
		
	if eyes_material:
		eyes_material.emission = STALKER_EYES_COLOR
		eyes_material.emission_energy_multiplier = 4.5
		
	# Инициализация состояния: полная маскировка со старта
	set_visibility(0.0)
	if eyes:
		eyes.visible = false
	if hp_sprite:
		hp_sprite.visible = false
	if hp_label:
		hp_label.visible = false

func _can_lunge_to_player() -> bool:
	return false

func start_lunge():
	pass

func set_visibility(val: float):
	current_visibility = clampf(val, 0.0, 1.0)
	if stalker_shader_mat:
		stalker_shader_mat.set_shader_parameter("visibility", current_visibility)
	if eyes_material and eyes:
		eyes_material.emission_energy_multiplier = lerp(0.0, 4.5, current_visibility)
		eyes.visible = current_visibility > 0.2
	if hp_sprite and hp_label:
		var show_bars = current_visibility > 0.65
		hp_sprite.visible = show_bars
		hp_label.visible = show_bars

func _physics_process(delta: float):
	if current_state == State.DEAD:
		return
		
	# Если враг в состоянии паники Fear Chain (OVERDRIVE) — раскрываем маскировку и уступаем логике бегства
	if current_state == State.FLEE:
		set_visibility(1.0)
		if eyes:
			eyes.visible = true
		super._physics_process(delta)
		return
		
	# Базовая гравитация
	if not is_on_floor():
		velocity.y -= gravity * 2.0 * delta
		
	# Затухание кинетического отброса
	var decay_rate = 2.5 if wall_slam_timer > 0.0 else 5.0
	knockback_velocity = knockback_velocity.lerp(Vector3.ZERO, decay_rate * delta)
	
	if hit_reaction_timer > 0.0:
		hit_reaction_timer -= delta
		
	# Обработка стаков яда Инъектора
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
			
	# Обработка таймеров игл Швейной машины
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
			
	# Проверка Fear Chain на тире OVERDRIVE игрока
	_process_fear_chain_check(delta)
	if current_state == State.FLEE:
		set_visibility(1.0)
		return
		
	# Логика состояний Соглядатая
	var player = target_player if is_instance_valid(target_player) else get_tree().get_first_node_in_group("player")
	if not is_instance_valid(player) or ("is_dead" in player and player.is_dead):
		_process_no_player(delta)
	else:
		target_player = player
		match stalker_state:
			StalkerState.STEALTH_IDLE:
				_process_stealth_idle(player, delta)
			StalkerState.STEALTH_STALK:
				_process_stealth_stalk(player, delta)
			StalkerState.TELEGRAPH:
				_process_telegraph(player, delta)
			StalkerState.VULNERABLE:
				_process_vulnerable(player, delta)
			StalkerState.DISSOLVING:
				_process_dissolving(player, delta)
				
	pre_move_velocity = velocity
	move_and_slide()
	_check_wall_slam(delta)

func _process_no_player(delta: float):
	velocity.x = lerp(velocity.x, knockback_velocity.x, 8.0 * delta)
	velocity.z = lerp(velocity.z, knockback_velocity.z, 8.0 * delta)
	if stalker_state != StalkerState.STEALTH_IDLE:
		stalker_state = StalkerState.STEALTH_IDLE
		set_visibility(0.0)

func _process_stealth_idle(player: Node3D, delta: float):
	set_visibility(0.0)
	velocity.x = lerp(velocity.x, knockback_velocity.x, 6.0 * delta)
	velocity.z = lerp(velocity.z, knockback_velocity.z, 6.0 * delta)
	
	var dist = global_position.distance_to(player.global_position)
	if dist <= stalker_detect_range:
		stalker_state = StalkerState.STEALTH_STALK
		stalk_update_timer = 0.0

func _process_stealth_stalk(player: Node3D, delta: float):
	set_visibility(0.0)
	var dist = global_position.distance_to(player.global_position)
	
	# Если игрок вышел за пределы дальности детекции
	if dist > stalker_detect_range * 1.25:
		stalker_state = StalkerState.STEALTH_IDLE
		return
		
	# Триггер атаки из засады при сближении на 3-4 метра при наличии прямой видимости
	if dist <= ambush_trigger_dist and _has_line_of_sight_to(player):
		_start_telegraph()
		return
		
	# Навигация по спирали/флангам вокруг игрока
	stalk_update_timer -= delta
	if stalk_update_timer <= 0.0:
		stalk_update_timer = STALK_UPDATE_INTERVAL
		var from_player = (global_position - player.global_position)
		from_player.y = 0.0
		if from_player.length_squared() > 0.05:
			var base_dir = from_player.normalized()
			# Фланговый угол ~48° для органичного полукруглого захода
			var flank_angle = stalk_flank_sign * deg_to_rad(48.0)
			var flank_dir = base_dir.rotated(Vector3.UP, flank_angle)
			var target_radius = clampf(dist - 2.0, 3.2, 14.0)
			nav_agent.target_position = player.global_position + flank_dir * target_radius
		else:
			nav_agent.target_position = player.global_position
			
	_follow_nav_path(stalk_speed, delta)

func _start_telegraph():
	stalker_state = StalkerState.TELEGRAPH
	telegraph_timer = telegraph_duration
	velocity.x = 0.0
	velocity.z = 0.0
	AudioManager.play_sound("stalker_reveal")
	if eyes:
		eyes.visible = true

func _process_telegraph(player: Node3D, delta: float):
	telegraph_timer -= delta
	var progress = clampf(1.0 - (telegraph_timer / telegraph_duration), 0.0, 1.0)
	set_visibility(progress)
	
	# Торможение и плавный поворот к игроку
	velocity.x = lerp(velocity.x, knockback_velocity.x, 10.0 * delta)
	velocity.z = lerp(velocity.z, knockback_velocity.z, 10.0 * delta)
	
	var to_player = player.global_position - global_position
	to_player.y = 0.0
	if to_player.length_squared() > 0.05:
		var target_angle = atan2(-to_player.x, -to_player.z)
		rotation.y = lerp_angle(rotation.y, target_angle, 14.0 * delta)
		
	if telegraph_timer <= 0.0:
		_execute_ambush_attack(player)

func _execute_ambush_attack(player: Node3D):
	# Удар из засады (25 HP урона)
	if player.has_method("take_damage"):
		var to_player = (player.global_position - global_position)
		to_player.y = 0.0
		var attack_dir = to_player.normalized() if to_player.length_squared() > 0.01 else -transform.basis.z.normalized()
		var attack_impulse = attack_dir * 12.0 + Vector3.UP * 2.5
		player.take_damage(stalker_attack_damage, attack_impulse, player.global_position)
		
	# Переход в окно уязвимости (2.0 секунды полной видимости)
	stalker_state = StalkerState.VULNERABLE
	vulnerability_timer = base_vulnerability_duration
	set_visibility(1.0)
	
	# Меняем сторону фланкирования для следующей атаки
	stalk_flank_sign = -stalk_flank_sign

func _process_vulnerable(player: Node3D, delta: float):
	vulnerability_timer -= delta
	set_visibility(1.0)
	
	# Во время окна уязвимости Соглядатай пятится назад и маневрирует по NavMesh
	stalk_update_timer -= delta
	if stalk_update_timer <= 0.0:
		stalk_update_timer = STALK_UPDATE_INTERVAL
		var away_from_player = (global_position - player.global_position)
		away_from_player.y = 0.0
		var retreat_dir = away_from_player.normalized() if away_from_player.length_squared() > 0.01 else transform.basis.z.normalized()
		var flank_retreat = retreat_dir.rotated(Vector3.UP, stalk_flank_sign * deg_to_rad(35.0))
		nav_agent.target_position = global_position + flank_retreat * 7.0
		
	_follow_nav_path(vulnerable_speed, delta)
	
	if vulnerability_timer <= 0.0:
		# Переход к плавному растворению в STEALTH
		stalker_state = StalkerState.DISSOLVING
		dissolve_timer = dissolve_duration

func _process_dissolving(player: Node3D, delta: float):
	dissolve_timer -= delta
	var progress = clampf(dissolve_timer / dissolve_duration, 0.0, 1.0)
	set_visibility(progress)
	
	# Продолжает отход при растворении
	stalk_update_timer -= delta
	if stalk_update_timer <= 0.0:
		stalk_update_timer = STALK_UPDATE_INTERVAL
		var away_from_player = (global_position - player.global_position)
		away_from_player.y = 0.0
		var retreat_dir = away_from_player.normalized() if away_from_player.length_squared() > 0.01 else transform.basis.z.normalized()
		nav_agent.target_position = global_position + retreat_dir * 6.0
		
	_follow_nav_path(stalk_speed, delta)
	
	if dissolve_timer <= 0.0:
		set_visibility(0.0)
		stalker_state = StalkerState.STEALTH_STALK

func _follow_nav_path(speed: float, delta: float):
	var next_pos = nav_agent.get_next_path_position()
	var move_dir = next_pos - global_position
	move_dir.y = 0.0
	
	if move_dir.length_squared() > 0.05:
		move_dir = move_dir.normalized()
		velocity.x = lerp(velocity.x, move_dir.x * speed + knockback_velocity.x, min(1.0, acceleration * delta))
		velocity.z = lerp(velocity.z, move_dir.z * speed + knockback_velocity.z, min(1.0, acceleration * delta))
		
		var target_angle = atan2(-move_dir.x, -move_dir.z)
		rotation.y = lerp_angle(rotation.y, target_angle, min(1.0, rotation_speed * delta))
	else:
		velocity.x = lerp(velocity.x, knockback_velocity.x, 8.0 * delta)
		velocity.z = lerp(velocity.z, knockback_velocity.z, 8.0 * delta)

func take_damage(amount: int, knockback_vector: Vector3, hit_pos: Vector3, is_melee: bool = false, is_execute: bool = false, is_shockwave: bool = false, is_headshot: bool = false, source_chain_depth: int = -1, weapon_source: String = ""):
	super.take_damage(amount, knockback_vector, hit_pos, is_melee, is_execute, is_shockwave, is_headshot, source_chain_depth, weapon_source)
	if current_state == State.DEAD:
		return
		
	# Получение урона срывает маскировку и продлевает окно видимости до 3.0 секунд
	stalker_state = StalkerState.VULNERABLE
	vulnerability_timer = max(vulnerability_timer, damage_vulnerability_duration)
	set_visibility(1.0)
	
	# Визуальная вспышка повреждения в шейдере
	if stalker_shader_mat:
		stalker_shader_mat.set_shader_parameter("hit_flash", 1.0)
		if hit_flash_tween:
			hit_flash_tween.kill()
		hit_flash_tween = create_tween()
		hit_flash_tween.tween_method(func(v): stalker_shader_mat.set_shader_parameter("hit_flash", v), 1.0, 0.0, 0.18)

func _update_needle_visuals():
	if current_state == State.DEAD:
		return
	if is_inflated:
		return
		
	if needle_count > 0:
		var n_factor = clampf(float(needle_count) / 20.0, 0.0, 1.0)
		if stalker_shader_mat:
			stalker_shader_mat.set_shader_parameter("needle_glow", n_factor)
		# Иглы, застрявшие в невидимом Соглядатае, создают демаскирующий контур
		if stalker_state == StalkerState.STEALTH_IDLE or stalker_state == StalkerState.STEALTH_STALK:
			set_visibility(max(current_visibility, min(0.45, needle_count * 0.09)))
		if body_mesh:
			body_mesh.scale = Vector3.ONE * (1.0 + n_factor * 0.15)
		if head_mesh:
			head_mesh.scale = Vector3.ONE * (1.0 + n_factor * 0.15)
	else:
		if stalker_shader_mat:
			stalker_shader_mat.set_shader_parameter("needle_glow", 0.0)
		if body_mesh:
			body_mesh.scale = Vector3.ONE
		if head_mesh:
			head_mesh.scale = Vector3.ONE

func inflate():
	if is_inflated or current_state == State.DEAD:
		return
	super.inflate()
	# Раздутие кровью полностью срывает маскировку Соглядатая
	stalker_state = StalkerState.VULNERABLE
	vulnerability_timer = max(vulnerability_timer, 6.0)
	set_visibility(1.0)
