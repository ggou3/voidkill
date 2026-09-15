extends "res://enemy.gd"

## Враг "Турель" (Turret Enemy).
## Статичная огневая точка на промышленном постаменте.
## Не перемещается (NavigationAgent3D отключён, позиция зафиксирована).
## При обнаружении игрока в LOS разворачивается лицом к цели (поворот вокруг вертикальной оси Y).
## При потере LOS удерживает прицел на последней известной позиции 2.0 секунды, после чего возвращается в IDLE.
## Атака: projectile_enemy.tscn (скорость 18.0 м/с, урон 12 HP, кулдаун 2.0с).
## Fear Chain: не может убегать (State.FLEE заблокирован).
## При OVERDRIVE игрока (BPM >= 180.0) переходит в защитный локдаун: прекращает огонь,
## сворачивается / опускает ствол вниз, снижая угрозу.
## Здоровье: 90 HP.

@export var projectile_scene: PackedScene = preload("res://projectile_enemy.tscn")
@export var turret_health: int = 90
@export var turret_damage: int = 12
@export var projectile_speed: float = 18.0
@export var turret_attack_cooldown: float = 2.0
@export var turret_rotation_speed: float = 4.5
@export var los_memory_duration: float = 2.0
@export var turret_detection_range: float = 28.0

const SENSOR_BASE_COLOR: Color = Color(1.0, 0.48, 0.08)
const SENSOR_TELEGRAPH_COLOR: Color = Color(1.0, 0.95, 0.35)
const SENSOR_LOCKDOWN_COLOR: Color = Color(0.2, 0.08, 0.02)

var spawn_position: Vector3 = Vector3.ZERO
var base_fixed_basis: Basis = Basis.IDENTITY
var last_known_player_pos: Vector3 = Vector3.ZERO
var lost_los_timer: float = 0.0
var has_target_lock: bool = false
var is_telegraphing: bool = false
var is_in_lockdown: bool = false

var lockdown_tween: Tween = null
var telegraph_tween: Tween = null
var attack_flash_tween: Tween = null

@onready var base_mount: Node3D = get_node_or_null("BaseMount")
@onready var barrel_pivot: Node3D = get_node_or_null("BarrelPivot")
@onready var muzzle_point: Marker3D = get_node_or_null("BarrelPivot/MuzzlePoint")
@onready var turret_light: OmniLight3D = get_node_or_null("Eyes/TurretLight")

func _ready():
	max_health = turret_health
	health = turret_health
	super._ready()
	
	attack_damage = turret_damage
	attack_cooldown = turret_attack_cooldown
	attack_range = 0.0
	move_speed = 0.0
	acceleration = 0.0
	lunge_cooldown_timer = 999999.0
	detection_range = turret_detection_range
	spawn_position = global_position
	
	if nav_agent:
		nav_agent.avoidance_enabled = false
		
	# Случайная начальная задержка первого выстрела (0.6 - 1.4с)
	attack_timer = randf_range(0.6, 1.4)
	
	if base_mount:
		base_fixed_basis = base_mount.global_transform.basis
		
	if eyes_material:
		eyes_material.emission = SENSOR_BASE_COLOR
		eyes_material.emission_energy_multiplier = 3.2
		
	_update_health_bar()

func _can_lunge_to_player() -> bool:
	return false

func start_lunge():
	pass

func set_state(new_state: State):
	if new_state == State.FLEE:
		return # Fear Chain бегство заблокировано для стационарной турели
	if new_state == State.CHASE:
		if is_instance_valid(target_player):
			super.set_state(State.ATTACK)
		else:
			super.set_state(State.IDLE)
		return
	if new_state == State.DEAD:
		_reset_telegraph()
		if lockdown_tween and lockdown_tween.is_valid():
			lockdown_tween.kill()
		if telegraph_tween and telegraph_tween.is_valid():
			telegraph_tween.kill()
		attack_timer = 999999.0
	elif current_state == State.ATTACK and new_state != State.ATTACK:
		_reset_telegraph()
	super.set_state(new_state)

func start_chase(player: Node3D):
	if is_instance_valid(player) and not ("is_dead" in player and player.is_dead):
		target_player = player
		last_known_player_pos = player.global_position
		lost_los_timer = los_memory_duration
		set_state(State.ATTACK)

func _on_detection_area_body_entered(body: Node3D):
	if body.is_in_group("player") and current_state == State.IDLE:
		if _has_line_of_sight_to(body):
			start_chase(body)

func _apply_movement(_target_vel: Vector3, _delta: float):
	# Статичная турель никогда не перемещается
	velocity = Vector3.ZERO

func take_damage(amount: int, knockback_vector: Vector3, hit_pos: Vector3, is_melee: bool = false, is_execute: bool = false, is_shockwave: bool = false, is_headshot: bool = false, source_chain_depth: int = -1, weapon_source: String = ""):
	# Тяжёлая стационарная огневая точка защищена от физического отбрасывания
	super.take_damage(amount, Vector3.ZERO, hit_pos, is_melee, is_execute, is_shockwave, is_headshot, source_chain_depth, weapon_source)

func die():
	_reset_telegraph()
	if lockdown_tween and lockdown_tween.is_valid():
		lockdown_tween.kill()
	if telegraph_tween and telegraph_tween.is_valid():
		telegraph_tween.kill()
	if attack_flash_tween and attack_flash_tween.is_valid():
		attack_flash_tween.kill()
	attack_timer = 999999.0
	super.die()

func _process_fear_chain_check(_delta: float):
	if current_state == State.DEAD:
		return
		
	var player = target_player if is_instance_valid(target_player) else get_tree().get_first_node_in_group("player")
	var is_overdrive = false
	if is_instance_valid(player) and not ("is_dead" in player and player.is_dead):
		var player_bpm: float = 0.0
		if "skills" in player and is_instance_valid(player.skills) and "bpm" in player.skills:
			player_bpm = player.skills.bpm
		if player_bpm >= 180.0:
			is_overdrive = true
			
	if is_overdrive:
		if not is_in_lockdown:
			_enter_lockdown()
	else:
		if is_in_lockdown:
			_exit_lockdown()

func _enter_lockdown():
	is_in_lockdown = true
	_reset_telegraph()
	
	if lockdown_tween and lockdown_tween.is_valid():
		lockdown_tween.kill()
	lockdown_tween = create_tween().set_parallel(true)
	
	if barrel_pivot:
		lockdown_tween.tween_property(barrel_pivot, "rotation:x", deg_to_rad(45.0), 0.35).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		lockdown_tween.tween_property(barrel_pivot, "position:y", 0.24, 0.35).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	if eyes_material:
		lockdown_tween.tween_property(eyes_material, "emission", SENSOR_LOCKDOWN_COLOR, 0.35)
		lockdown_tween.tween_property(eyes_material, "emission_energy_multiplier", 0.3, 0.35)
	if turret_light:
		lockdown_tween.tween_property(turret_light, "light_energy", 0.1, 0.35)
		
	print("[%s] TURRET LOCKDOWN: Player in OVERDRIVE! Ceased fire, tucked barrel." % name)

func _exit_lockdown():
	is_in_lockdown = false
	
	if lockdown_tween and lockdown_tween.is_valid():
		lockdown_tween.kill()
	lockdown_tween = create_tween().set_parallel(true)
	
	if barrel_pivot:
		lockdown_tween.tween_property(barrel_pivot, "rotation:x", 0.0, 0.35).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		lockdown_tween.tween_property(barrel_pivot, "position:y", 0.35, 0.35).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	if eyes_material:
		lockdown_tween.tween_property(eyes_material, "emission", SENSOR_BASE_COLOR, 0.3)
		lockdown_tween.tween_property(eyes_material, "emission_energy_multiplier", 3.2, 0.3)
	if turret_light:
		lockdown_tween.tween_property(turret_light, "light_energy", 1.2, 0.3)
		
	attack_timer = max(attack_timer, 0.6)
	print("[%s] TURRET RESTORE: Player exited OVERDRIVE. Resumed targeting." % name)

func _process_idle(delta: float):
	velocity = Vector3.ZERO
	knockback_velocity = Vector3.ZERO
	
	var player = get_tree().get_first_node_in_group("player")
	if is_instance_valid(player) and not ("is_dead" in player and player.is_dead):
		var dist = global_position.distance_to(player.global_position)
		if dist <= detection_range and _has_line_of_sight_to(player):
			start_chase(player)

func _process_chase(_delta: float):
	# Турель никогда не выполняет физическое преследование
	if is_instance_valid(target_player) and not ("is_dead" in target_player and target_player.is_dead):
		set_state(State.ATTACK)
	else:
		set_state(State.IDLE)

func _process_attack(delta: float):
	if not is_inside_tree() or current_state == State.DEAD:
		return
	if not is_instance_valid(target_player) or ("is_dead" in target_player and target_player.is_dead):
		target_player = null
		set_state(State.IDLE)
		return
		
	var dist_to_player = global_position.distance_to(target_player.global_position)
	var has_los = (dist_to_player <= (detection_range + 2.0)) and _has_line_of_sight_to(target_player)
	
	if has_los:
		last_known_player_pos = target_player.global_position
		lost_los_timer = los_memory_duration
	else:
		# Потеря LOS: удержание прицела на последней известной позиции 2.0 секунды
		_reset_telegraph()
		lost_los_timer -= delta
		if lost_los_timer <= 0.0:
			target_player = null
			set_state(State.IDLE)
			return
			
	# Поворот турели вокруг вертикальной оси Y к последней известной позиции цели
	if not is_in_lockdown:
		var to_target = last_known_player_pos - global_position
		to_target.y = 0.0
		if to_target.length_squared() > 0.01:
			var target_angle = atan2(-to_target.x, -to_target.z)
			var angle_diff = abs(wrapf(target_angle - rotation.y, -PI, PI))
			if angle_diff > 0.02:
				rotation.y = lerp_angle(rotation.y, target_angle, min(1.0, turret_rotation_speed * delta))
				
	# Логика атаки и телеграфа
	if is_in_lockdown:
		_reset_telegraph()
		attack_timer = max(attack_timer, 0.6)
	elif has_los:
		# Визуальный телеграф перед выстрелом (за 0.35с)
		if attack_timer <= 0.35 and hit_reaction_timer <= 0.0 and not is_telegraphing:
			_start_telegraph()
		elif attack_timer > 0.35 and is_telegraphing:
			_reset_telegraph()
			
		# Выстрел по завершении кулдауна (2.0с)
		if attack_timer <= 0.0 and hit_reaction_timer <= 0.0:
			perform_attack()
			attack_timer = attack_cooldown
	else:
		_reset_telegraph()

func perform_attack():
	if not is_inside_tree() or current_state == State.DEAD or is_in_lockdown:
		return
	_reset_telegraph()
	if not is_instance_valid(target_player):
		return
		
	var scene_root = get_tree().current_scene if (get_tree() and get_tree().current_scene) else get_parent()
	if not scene_root or not projectile_scene:
		return
		
	var spawn_pos = muzzle_point.global_position if muzzle_point else (global_position + Vector3(0.0, 0.45, 0.0) - transform.basis.z * 0.72)
	var target_pos = target_player.global_position + Vector3(0.0, 0.25, 0.0)
	var fly_dir = (target_pos - spawn_pos).normalized()
	
	var proj = projectile_scene.instantiate()
	proj.direction = fly_dir
	proj.speed = projectile_speed
	proj.damage = attack_damage
	proj.shooter = self
	
	scene_root.add_child(proj)
	proj.global_position = spawn_pos
	
	# Вспышка сенсора и ствола при выстреле
	if eyes_material:
		if attack_flash_tween and attack_flash_tween.is_valid():
			attack_flash_tween.kill()
		eyes_material.emission = Color(1.0, 0.95, 0.7)
		attack_flash_tween = create_tween()
		attack_flash_tween.tween_property(eyes_material, "emission", SENSOR_BASE_COLOR, 0.22)
		
	AudioManager.play_sound("flask_throw")
	print("[%s] TURRET ATTACK: fired projectile at %s (dir: %s, speed: %.1f, dmg: %d)" % [
		name, target_player.name, fly_dir, projectile_speed, attack_damage
	])

func _start_telegraph():
	if not is_inside_tree() or current_state == State.DEAD or is_in_lockdown:
		return
	is_telegraphing = true
	if eyes_material:
		if telegraph_tween and telegraph_tween.is_valid():
			telegraph_tween.kill()
		telegraph_tween = create_tween().set_parallel(true)
		telegraph_tween.tween_property(eyes_material, "emission", SENSOR_TELEGRAPH_COLOR, 0.18)
		telegraph_tween.tween_property(eyes_material, "emission_energy_multiplier", 5.0, 0.18)
	if turret_light:
		telegraph_tween.tween_property(turret_light, "light_energy", 2.2, 0.18)
		telegraph_tween.tween_property(turret_light, "light_color", SENSOR_TELEGRAPH_COLOR, 0.18)

func _reset_telegraph():
	if telegraph_tween and telegraph_tween.is_valid():
		telegraph_tween.kill()
	if not is_telegraphing:
		return
	is_telegraphing = false
	if eyes_material and not is_in_lockdown:
		eyes_material.emission = SENSOR_BASE_COLOR
		eyes_material.emission_energy_multiplier = 3.2
	if turret_light and not is_in_lockdown:
		turret_light.light_energy = 1.2
		turret_light.light_color = SENSOR_BASE_COLOR

func _physics_process(delta: float):
	if current_state == State.DEAD:
		super._physics_process(delta)
		return
		
	# Зафиксированная стационарная установка: координаты спавна и вращение постамента не меняются
	global_position = spawn_position
	velocity = Vector3.ZERO
	knockback_velocity = Vector3.ZERO
	
	if base_mount:
		base_mount.global_transform.basis = base_fixed_basis
		
	super._physics_process(delta)
