extends "res://enemy.gd"

@export var projectile_scene: PackedScene = preload("res://projectile_enemy.tscn")
@export var preferred_distance_min: float = 10.0
@export var preferred_distance_max: float = 15.0
@export var projectile_speed: float = 18.0
@export var ranged_damage: int = 12
@export var ranged_attack_cooldown: float = 2.8

const EYES_BASE_COLOR = Color(0.85, 0.2, 1.0)
const EYES_TELEGRAPH_COLOR = Color(1.0, 0.85, 0.2)

var is_telegraphing_shot: bool = false
var antenna_material: StandardMaterial3D = null
@onready var antenna_tip: MeshInstance3D = get_node_or_null("AntennaTip")

var telegraph_tween_eyes: Tween = null
var telegraph_tween_antenna: Tween = null
var attack_flash_tween_eyes: Tween = null
var attack_flash_tween_antenna: Tween = null

func _ready():
	super._ready()
	attack_damage = ranged_damage
	attack_cooldown = ranged_attack_cooldown
	# Обнуляем базовый attack_range, чтобы базовый enemy.gd не переходил в State.ATTACK на 2.0м сам
	attack_range = 0.0
	lunge_cooldown_timer = 999999.0
	# Случайная задержка первого выстрела при спавне (0.6 - 1.8с)
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

func _can_lunge_to_player() -> bool:
	# Дальник не использует атаку-выпад LUNGE ближнего боя
	return false

func start_lunge():
	# Блокировка выпада LUNGE
	pass

func set_state(new_state: State):
	if new_state == State.DEAD:
		_reset_ranged_telegraph()
		attack_timer = 999999.0
	elif current_state == State.ATTACK and new_state != State.ATTACK:
		_reset_ranged_telegraph()
	super.set_state(new_state)

func die():
	_reset_ranged_telegraph()
	if attack_flash_tween_eyes and attack_flash_tween_eyes.is_valid():
		attack_flash_tween_eyes.kill()
	if attack_flash_tween_antenna and attack_flash_tween_antenna.is_valid():
		attack_flash_tween_antenna.kill()
	attack_timer = 999999.0
	super.die()

func _process_chase(delta: float):
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

func _process_attack(delta: float):
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
			_apply_movement(retreat_vel, delta)
	else:
		# На дистанции 10-15м останавливаемся на месте
		velocity.x = lerp(velocity.x, knockback_velocity.x, 10.0 * delta)
		velocity.z = lerp(velocity.z, knockback_velocity.z, 10.0 * delta)
		
	# Визуальный телеграф перед выстрелом (за 0.35с до конца кулдауна глаза загораются золотым цветом)
	if attack_timer <= 0.35 and hit_reaction_timer <= 0.0 and not is_telegraphing_shot:
		_start_ranged_telegraph()
	elif attack_timer > 0.35 and is_telegraphing_shot:
		_reset_ranged_telegraph()
		
	# Выстрел по завершении кулдауна (2.5-3.0с)
	if attack_timer <= 0.0 and hit_reaction_timer <= 0.0:
		perform_attack()
		attack_timer = attack_cooldown

func perform_attack():
	if not is_inside_tree() or current_state == State.DEAD:
		return
	_reset_ranged_telegraph()
	if not is_instance_valid(target_player):
		return
		
	# Вспышка глаз и маячка антенны при выстреле
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
		
	if not projectile_scene:
		return
		
	var scene_root = get_tree().current_scene if (get_tree() and get_tree().current_scene) else get_parent()
	if not scene_root:
		return
		
	var spawn_pos = global_position + Vector3(0.0, 0.55, 0.0) - transform.basis.z * 0.4
	
	# Точка прицеливания: корпус игрока на момент выстрела (прямая траектория, без самонаведения)
	var target_pos = target_player.global_position + Vector3(0.0, 0.2, 0.0)
	var fly_dir = (target_pos - spawn_pos).normalized()
	
	var proj = projectile_scene.instantiate()
	proj.direction = fly_dir
	proj.speed = projectile_speed
	proj.damage = attack_damage
	proj.shooter = self
	
	scene_root.add_child(proj)
	proj.global_position = spawn_pos
		
	AudioManager.play_sound("flask_throw")
	print("[%s] RANGED ATTACK: fired projectile at %s (dir: %s, speed: %.1f, dmg: %d)" % [
		name, target_player.name, fly_dir, projectile_speed, attack_damage
	])

func _start_ranged_telegraph():
	if not is_inside_tree() or current_state == State.DEAD:
		return
	is_telegraphing_shot = true
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

func _reset_ranged_telegraph():
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

func _process_fear_chain_check(delta: float):
	if current_state == State.ATTACK:
		fear_check_timer -= delta
		if fear_check_timer <= 0.0:
			fear_check_timer = 3.0
			var player = target_player if is_instance_valid(target_player) else get_tree().get_first_node_in_group("player")
			if is_instance_valid(player) and not ("is_dead" in player and player.is_dead):
				var player_bpm: float = 0.0
				if "skills" in player and is_instance_valid(player.skills) and "bpm" in player.skills:
					player_bpm = player.skills.bpm
				if player_bpm >= 180.0 and global_position.distance_to(player.global_position) <= detection_range and _has_line_of_sight_to(player):
					if randf() <= 0.40:
						target_player = player
						flee_timer = randf_range(4.0, 5.0)
						print("[%s] FEAR CHAIN: Ranged enemy panicked! FLEE for %.2fs" % [name, flee_timer])
						set_state(State.FLEE)
						return
	super._process_fear_chain_check(delta)
