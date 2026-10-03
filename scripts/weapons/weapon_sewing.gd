class_name WeaponSewing
extends WeaponBase

## Швейная машина (Слот 4): Скорострельный игольник.
## ЛКМ: Автоматическая стрельба иглами (6 HP, 10 выстр/с), иглы застревают во враге (add_needle).
## ПКМ: Заградительный веерный залп: 12 игл веером (конус 35-40°), урон 4 HP за иглу,
## расход 10 игл из общего магазина, независимый кулдаун 1.5с.
## Параметры ПКМ — в группе «Альт-огонь» ресурса sewing_machine.tres.

func _init() -> void:
	if not data:
		data = preload("res://scripts/weapons/data/sewing_machine.tres")

## Основной огонь (ЛКМ): непрерывная стрельба иглами
func fire() -> void:
	if not data:
		return
		
	fire_timer = data.fire_rate
	var head = _get_head()
	if head:
		head.add_recoil(data.cam_shake, data.weapon_kick)
		head.trigger_muzzle_flash(false)
	AudioManager.play_sound("needle_shot")
	
	var aim_dir = head.get_aim_direction() if head else Vector3.FORWARD
	var ray = head.get_aim_raycast(data.spread) if head else null
	var hit_pos = ray.to_global(ray.target_position) if ray else Vector3.ZERO
	var collider: Node = null
	if ray and ray.is_colliding():
		hit_pos = ray.get_collision_point()
		collider = ray.get_collider()
	_apply_hit(collider, hit_pos, aim_dir, false)

## Застревание иглы во враге
func _on_hit_target(target: Node, _hit_pos: Vector3, _is_headshot: bool, _is_alt: bool) -> void:
	if target.has_method("add_needle"):
		target.add_needle()

## Альтернативный огонь (ПКМ): заградительный веерный залп
func alt_fire(has_infinite_ammo: bool = false) -> void:
	if alt_timer > 0.0:
		return
		
	# Тратит 10 игл из общего магазина ЛКМ; если меньше 10 — недоступен (dry_fire)
	if weapon_manager and weapon_manager.ammos[slot_index] < data.alt_ammo_cost:
		AudioManager.play_sound("dry_fire")
		return

	if not has_infinite_ammo and weapon_manager:
		weapon_manager.ammos[slot_index] -= data.alt_ammo_cost

	alt_timer = data.alt_cooldown
	_fire_sewing_barrage()

func _fire_sewing_barrage() -> void:
	var head = _get_head()
	if not head or not head.raycast:
		return
		
	head.add_recoil(0.06, 0.22)
	head.trigger_muzzle_flash(false)
	AudioManager.play_sound("needle_shot")
	
	var aim_dir = head.get_aim_direction()
	var start_pos = _get_muzzle_position()
	
	# Веерный разброс 12 игл широким сектором (конус разброса 35-40 градусов)
	var needle_count = data.alt_projectile_count
	for i in range(needle_count):
		var h_frac = (float(i) / float(needle_count - 1)) * 2.0 - 1.0 # от -1.0 до +1.0
		var spread_x = (h_frac * 0.34) + randf_range(-0.03, 0.03) # дуга ~38 градусов
		var spread_y = randf_range(-0.16, 0.16) # вертикальный разброс ~18 градусов
		
		head.raycast.target_position = Vector3(spread_x * 100.0, spread_y * 100.0, -100.0)
		head.raycast.force_raycast_update()
		var ray = head.raycast
		
		var hit_pos = ray.to_global(ray.target_position)
		if ray.is_colliding():
			hit_pos = ray.get_collision_point()
			var hit = ray.get_collider()
			if hit != null:
				var target: Node = null
				var is_headshot: bool = false
				
				if hit.is_in_group("enemy_head") or hit.name == "HeadHitbox":
					is_headshot = true
					if hit.has_meta("enemy"):
						target = hit.get_meta("enemy")
					elif hit.get_parent():
						target = hit.get_parent()
				else:
					target = GameTypes.resolve_damageable(hit)
					
				if target != null and target.has_method("take_damage"):
					var flat_dir = Vector3(aim_dir.x, 0.0, aim_dir.z).normalized()
					var knockback_vector = flat_dir * 1.5 + Vector3.UP * 0.5
					var final_dmg = data.alt_damage
					if is_headshot:
						final_dmg = int(round(float(data.alt_damage) * data.headshot_multiplier))
						
					if target.has_method("add_needle"):
						target.add_needle()
						
					target.take_damage(final_dmg, knockback_vector, hit_pos, false, false, false, is_headshot, -1, "sewing")
					
		TracerPool.spawn_tracer(start_pos, hit_pos, &"needle")
		
	head.raycast.target_position = Vector3(0, 0, -100)
	var remaining_ammo = weapon_manager.ammos[slot_index] if weapon_manager else 0
	GameTypes.debug_log(&"weapon", "[SEWING MACHINE] Barrage fired! Needles: %d | Ammos remaining: %d" % [needle_count, remaining_ammo])

func get_alt_hud_suffix(_has_infinite_ammo: bool = false) -> String:
	if alt_timer > 0.0:
		return " (RMB %.1fs)" % alt_timer
	return ""
