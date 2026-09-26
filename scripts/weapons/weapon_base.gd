class_name WeaponBase
extends Node

## Базовый класс для всех типов оружия игрока (WeaponBase).
## Предоставляет унифицированный контракт стрельбы и централизованную
## логику обработки попадания (_apply_hit) со всеми модификаторами и эффектами.

@export var data: WeaponData

## Основной огонь (ЛКМ)
func fire() -> void:
	pass

## Альтернативный огонь (ПКМ)
func alt_fire() -> void:
	pass

## Проверка готовности оружия к выстрелу
func can_fire() -> bool:
	return false

## Централизованная общая логика обработки попадания hitscan-выстрела.
## Выполняет детекцию хедшота, проверку нахождения цели в воздухе,
## расчёт урона с режимами стакинга (MULTIPLICATIVE / ADDITIVE), отброс цели,
## нанесение урона через target.take_damage и спавн трейсера через TracerPool.
func _apply_hit(collider: Node, hit_pos: Vector3, dir: Vector3, is_alt: bool = false) -> void:
	var start_pos = _get_muzzle_position()
	var tracer_style = _get_tracer_style(is_alt)
	TracerPool.spawn_tracer(start_pos, hit_pos, tracer_style)
	
	if not is_instance_valid(collider):
		return
		
	var target: Node = null
	var is_headshot: bool = false
	
	# Детекция хедшота и разрешения целевого узла
	if collider.is_in_group("enemy_head") or collider.name == "HeadHitbox":
		is_headshot = true
		if collider.has_meta("enemy"):
			target = collider.get_meta("enemy")
		elif collider.get_parent():
			target = collider.get_parent()
	else:
		target = GameTypes.resolve_damageable(collider)
		
	if not is_instance_valid(target) or not target.has_method("take_damage"):
		return
		
	# Расчёт вектора отброса с горизонтальным направлением и вертикальным подбросом
	var flat_dir = Vector3(dir.x, 0.0, dir.z)
	if flat_dir.length_squared() > 0.0001:
		flat_dir = flat_dir.normalized()
	else:
		flat_dir = Vector3.FORWARD
		
	var knockback_force = data.knockback if data else 0.0
	var upward_kick_force = data.upward_kick if data else 0.0
	var knockback_vector = flat_dir * knockback_force
	knockback_vector.y = upward_kick_force
	
	# Проверка нахождения цели в воздухе
	var target_body = GameTypes.resolve_damageable(target)
	var is_airborne: bool = not target_body.is_on_floor() if (target_body and target_body.has_method("is_on_floor")) else false
	
	# Базовый урон и множители
	var base_dmg = float(data.damage) if data else 0.0
	var hs_mult = data.headshot_multiplier if (data and is_headshot) else 1.0
	var air_mult = data.air_multiplier if (data and is_airborne) else 1.0
	var total_mult = 1.0
	
	# Режимы стакинга множителей (MULTIPLICATIVE в OVERDRIVE, ADDITIVE иначе)
	if is_headshot and is_airborne:
		if _get_bpm_tier() == GameTypes.BPMTier.OVERDRIVE:
			total_mult = hs_mult * air_mult
		else:
			total_mult = 1.0 + (hs_mult - 1.0) + (air_mult - 1.0)
	elif is_headshot:
		total_mult = hs_mult
	elif is_airborne:
		total_mult = air_mult
		
	var final_dmg = int(round(base_dmg * total_mult))
	
	# Логирование критических попаданий
	if is_headshot and is_airborne:
		var stack_mode = "MULTIPLICATIVE" if _get_bpm_tier() == GameTypes.BPMTier.OVERDRIVE else "ADDITIVE"
		GameTypes.debug_log(&"weapon", "[%s] AIRBORNE HEADSHOT! (%.1fx, %s) Damage: %d | Base: %d" % [target.name, total_mult, stack_mode, final_dmg, int(base_dmg)])
	elif is_airborne and (data and data.air_multiplier > 1.0):
		GameTypes.debug_log(&"weapon", "[%s] AIRBORNE HIT! (%.1fx) Damage: %d | Base: %d" % [target.name, total_mult, final_dmg, int(base_dmg)])
		
	# Нанесение урона цели
	var weapon_key = _get_weapon_key()
	target.take_damage(final_dmg, knockback_vector, hit_pos, false, false, false, is_headshot, -1, weapon_key)
	
	# Вакуумный след для оружия с поддержкой гравипула (Калибр-0 в OVERDRIVE)
	if data and data.has_vacuum and not is_alt and _get_bpm_tier() == GameTypes.BPMTier.OVERDRIVE:
		_apply_vacuum_wake(start_pos, hit_pos, data.vacuum_radius, data.vacuum_force, target)
		
	# Хук для специализированных эффектов наследников
	_on_hit_target(target, hit_pos, is_headshot, is_alt)

## Виртуальный метод для переопределения в специализированных классах оружия
## (например, наложение яда Инъектором, добавление иглы Швейной машиной, бонус урона от игл у Наковальни)
func _on_hit_target(_target: Node, _hit_pos: Vector3, _is_headshot: bool, _is_alt: bool) -> void:
	pass

## Определение текущего BPM-тира игрока
func _get_bpm_tier() -> GameTypes.BPMTier:
	var skill_mgr = get_node_or_null("../SkillManager")
	if not skill_mgr:
		var player = get_tree().get_first_node_in_group("player") if is_inside_tree() else null
		if is_instance_valid(player) and "skills" in player:
			skill_mgr = player.skills
	if skill_mgr is SkillManager:
		return skill_mgr.get_bpm_tier()
	return GameTypes.BPMTier.CALM

## Получение стартовой точки вылета снаряда / трейсера (дуло оружия)
func _get_muzzle_position() -> Vector3:
	var head = get_node_or_null("../Head")
	if not head:
		var player = get_tree().get_first_node_in_group("player") if is_inside_tree() else null
		if is_instance_valid(player) and "head" in player:
			head = player.head
	if is_instance_valid(head) and head.has_method("get_muzzle_position"):
		return head.get_muzzle_position()
	return Vector3.ZERO

## Определение визуального стиля трейсера по конфигурации оружия
func _get_tracer_style(_is_alt: bool = false) -> StringName:
	if not data:
		return &"bullet"
	if data.has_vacuum:
		return &"bullet"
	match data.weapon_id:
		&"anvil":
			return &"pellet"
		&"injector":
			return &"syringe"
		&"sewing_machine":
			return &"needle"
		_:
			return &"bullet"

## Строковый ключ источника урона для статистики убийств в SkillManager
func _get_weapon_key() -> String:
	if not data:
		return ""
	match data.weapon_id:
		&"caliber_0":
			return "caliber0"
		&"sewing_machine":
			return "sewing"
		_:
			return String(data.weapon_id)

## Создание вакуумного следа вдоль линии выстрела, затягивающего ближайших врагов
func _apply_vacuum_wake(start_pos: Vector3, end_pos: Vector3, radius: float, force: float, excluded_target: Node = null) -> void:
	var line_vec = end_pos - start_pos
	var line_len_sq = line_vec.length_squared()
	if line_len_sq < 0.01:
		return
		
	var all_enemies = get_tree().get_nodes_in_group("enemy") if is_inside_tree() else []
	for enemy in all_enemies:
		if not is_instance_valid(enemy) or enemy == excluded_target:
			continue
		if ("current_state" in enemy and enemy.current_state == enemy.State.DEAD) or ("health" in enemy and enemy.health <= 0):
			continue
			
		var enemy_pos = enemy.global_position + Vector3(0.0, 0.9, 0.0)
		var to_enemy = enemy_pos - start_pos
		var t = clamp(to_enemy.dot(line_vec) / line_len_sq, 0.0, 1.0)
		var closest_point = start_pos + line_vec * t
		
		var to_line = closest_point - enemy_pos
		var dist = to_line.length()
		
		if dist <= radius:
			var falloff = 1.0 - (dist / radius)
			var pull_dir = to_line.normalized() if dist > 0.05 else -enemy.global_transform.basis.z
			pull_dir.y = max(pull_dir.y, 0.15)
			pull_dir = pull_dir.normalized()
			
			var pull_impulse = pull_dir * (force * falloff)
			if enemy.has_method("apply_vacuum_pull"):
				enemy.apply_vacuum_pull(pull_impulse)
			elif "velocity" in enemy:
				enemy.velocity += pull_impulse
