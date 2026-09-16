extends "res://enemy.gd"

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

const SWARM_EYES_COLOR = Color(1.0, 0.85, 0.15)

func _ready():
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

func start_lunge():
	pass

func perform_attack():
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
