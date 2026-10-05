class_name EnemySwarm
extends EnemyGround

## Враг "Рой" (Swarm Enemy).
## Многочисленные слабые враги, опасные исключительно массой и совместным окружением.
## Здоровье: 8-10 HP (погибает от любого одиночного попадания: одна игла, дробина или пуля).
## Урон атаки: 4 HP за касание (безопасен поодиночке, опасен при синхронных ударах группы).
## Скорость: 13.5 м/с — юркий и подвижный преследователь.
## Масштаб модели: 0.6x от обычного врага, сгорбленный хитиновый силуэт и паучий кластер глаз.

@export var swarm_health: int = 8
@export var swarm_attack_damage: int = 4
@export var swarm_speed: float = 13.5
@export var swarm_acceleration: float = 8.0

@export var attack_damage: int = 4
@export var attack_range: float = 1.5
@export var attack_cooldown: float = 0.8

var attack_timer: float = 0.0

const SWARM_EYES_COLOR = Color(1.0, 0.85, 0.15)

func _ready() -> void:
	super._ready()
	max_health = swarm_health
	health = swarm_health
	move_speed = swarm_speed
	acceleration = swarm_acceleration
	attack_damage = swarm_attack_damage
	attack_range = 1.5
	attack_cooldown = 0.8
	reaction_delay = 0.25
	lunge_cooldown_timer = 999999.0
	
	# Корректировка высоты HP-бара под уменьшенный силуэт роя (0.6x)
	if hp_sprite:
		hp_sprite.position = Vector3(0, 0.65, 0)
	if hp_label:
		hp_label.position = Vector3(0, 0.80, 0)
		hp_label.font_size = 14
		hp_label.text = "%d / %d" % [health, max_health]
	if hp_bar:
		hp_bar.max_value = max_health
		hp_bar.value = health
		
	# Назначение общего материала глаз всем дополнительным точкам-глазам в кластере
	if eyes_material and eyes:
		for child in eyes.get_children():
			if child is MeshInstance3D:
				child.set_surface_override_material(0, eyes_material)

func _can_lunge_to_player() -> bool:
	# Рой не совершает прыжков-выпадов LUNGE — опасность в постоянном прессинге и окружении
	return false

func start_lunge() -> void:
	pass

func _physics_process(delta: float) -> void:
	if attack_timer > 0.0:
		attack_timer -= delta
	super._physics_process(delta)

func set_state(new_state: State) -> void:
	if current_state == new_state or current_state == State.DEAD:
		return
	super.set_state(new_state)
	match current_state:
		State.ATTACK:
			attack_timer = max(attack_timer, reaction_delay)
			hit_reaction_timer = max(hit_reaction_timer, reaction_delay)
		State.DEAD:
			attack_timer = 999999.0

func _process_chase(delta: float) -> void:
	if not is_instance_valid(target_player) or ("is_dead" in target_player and target_player.is_dead):
		set_state(State.IDLE)
		return
		
	var dist_to_player = global_position.distance_to(target_player.global_position)
	if dist_to_player <= attack_range:
		set_state(State.ATTACK)
		return
		
	super._process_chase(delta)

func _process_attack(delta: float) -> void:
	if not is_instance_valid(target_player) or ("is_dead" in target_player and target_player.is_dead):
		set_state(State.IDLE)
		return
		
	var dist_to_player = global_position.distance_to(target_player.global_position)
	if dist_to_player > attack_range * 1.3:
		set_state(State.CHASE)
		return
		
	velocity.x = lerp(velocity.x, knockback_velocity.x, 10.0 * delta)
	velocity.z = lerp(velocity.z, knockback_velocity.z, 10.0 * delta)

	var to_player = target_player.global_position - global_position
	to_player.y = 0.0
	if to_player.length_squared() > 0.01:
		var target_angle = atan2(-to_player.x, -to_player.z)
		var angle_diff = abs(wrapf(target_angle - rotation.y, -PI, PI))
		if angle_diff > 0.08:
			rotation.y = lerp_angle(rotation.y, target_angle, min(1.0, rotation_speed * delta))
	
	if attack_timer <= 0.0 and hit_reaction_timer <= 0.0:
		if is_inside_tree() and current_state == State.ATTACK:
			perform_attack()
		attack_timer = attack_cooldown

func perform_attack() -> void:
	if not is_inside_tree() or current_state == State.DEAD:
		return
	if not is_instance_valid(target_player):
		return
		
	# Визуальный отклик атаки (вспышка глаз ало-красным, возврат в янтарный)
	if eyes_material:
		eyes_material.emission = Color(1.0, 0.1, 0.1)
		var tween = create_tween()
		tween.tween_property(eyes_material, "emission", SWARM_EYES_COLOR, 0.25)
		
	# Нанесение контактного урона
	if target_player.has_method("take_damage"):
		var attack_dir = (target_player.global_position - global_position).normalized()
		var attack_impulse = attack_dir * 4.0 + Vector3.UP * 1.5
		target_player.take_damage(attack_damage, attack_impulse, target_player.global_position)

func take_damage(amount: int, knockback_vector: Vector3, hit_pos: Vector3, is_melee: bool = false, is_execute: bool = false, is_shockwave: bool = false, is_headshot: bool = false, source_chain_depth: int = -1, weapon_source: String = "") -> void:
	if current_state == State.DEAD:
		return
	attack_timer = max(attack_timer, reaction_delay)
	super.take_damage(amount, knockback_vector, hit_pos, is_melee, is_execute, is_shockwave, is_headshot, source_chain_depth, weapon_source)

func die(death_info: Dictionary = {}) -> void:
	attack_timer = 999999.0
	super.die(death_info)
