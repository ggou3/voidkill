class_name WeaponCaliber
extends WeaponBase

## Калибр-0 (Слот 1): Точный крупнокалиберный револьвер.
## ЛКМ: Одиночный точный выстрел (70 HP) с вакуумным следом на тире OVERDRIVE.
## ПКМ: Пробивной рейлган-выстрел (BPM-гейт: доступен ТОЛЬКО на тире OVERDRIVE),
## пробивающий всех врагов вдоль луча и создающий единый вакуумный вихрь.

func _init() -> void:
	if not data:
		data = preload("res://scripts/weapons/data/caliber_0.tres")

## Основной огонь (ЛКМ): одиночный точный хитскан через _apply_hit
func fire() -> void:
	if not data:
		return
		
	fire_timer = data.fire_rate
	var head = _get_head()
	if head:
		head.add_recoil(data.cam_shake, data.weapon_kick)
		head.trigger_muzzle_flash(false)
	AudioManager.play_sound("revolver_shot")
	
	var aim_dir = head.get_aim_direction() if head else Vector3.FORWARD
	var ray = head.get_aim_raycast(data.spread) if head else null
	var hit_pos = ray.to_global(ray.target_position) if ray else Vector3.ZERO
	var collider: Node = null
	
	if ray and ray.is_colliding():
		hit_pos = ray.get_collision_point()
		collider = ray.get_collider()
		
	_apply_hit(collider, hit_pos, aim_dir, false)

## Альтернативный огонь (ПКМ): пробивной рейлган-выстрел на тире OVERDRIVE
func alt_fire(_has_infinite_ammo: bool = false) -> void:
	if weapon_manager and weapon_manager.is_reloading:
		return
	if fire_timer > 0.0:
		return
		
	# BPM-гейт: ПКМ доступен ТОЛЬКО на тире OVERDRIVE
	if _get_bpm_tier() != GameTypes.BPMTier.OVERDRIVE:
		AudioManager.play_sound("dry_fire")
		return
		
	if weapon_manager:
		if weapon_manager.ammos[slot_index] <= 0:
			AudioManager.play_sound("dry_fire")
			weapon_manager.reload()
			return
		# Разряжает весь барабан
		weapon_manager.ammos[slot_index] = 0
		
	fire_timer = data.fire_rate if data else 0.45
	_fire_caliber_piercing_shot()

## Пробивной рейлган-выстрел Калибр-0
func _fire_caliber_piercing_shot() -> void:
	var head = _get_head()
	if head:
		head.add_recoil(0.20, 0.60)
		head.trigger_muzzle_flash(true)
	AudioManager.play_sound("rail_shot")
	
	var aim_dir = head.get_aim_direction().normalized() if head else Vector3.FORWARD
	var from_pos = head.camera.global_position if (head and head.camera) else Vector3.ZERO
	var start_pos = _get_muzzle_position()
	var space_state = head.camera.get_world_3d().direct_space_state if (head and head.camera) else null
	var player_node = _get_player()
	
	if not space_state:
		if weapon_manager:
			weapon_manager.reload()
		return
		
	const MAX_BEAM_DIST: float = 120.0
	var current_from = from_pos
	var remaining_dist = MAX_BEAM_DIST
	var beam_end = from_pos + aim_dir * MAX_BEAM_DIST
	var exclude_list: Array[RID] = []
	if is_instance_valid(player_node):
		exclude_list.append(player_node.get_rid())
		
	while remaining_dist > 0.1:
		var ray_query = PhysicsRayQueryParameters3D.create(current_from, current_from + aim_dir * remaining_dist)
		ray_query.exclude = exclude_list
		ray_query.collide_with_areas = true
		ray_query.collide_with_bodies = true
		var hit_res = space_state.intersect_ray(ray_query)
		if hit_res.is_empty():
			break
		var col = hit_res.collider
		var is_enemy_or_part = false
		if col:
			if col.is_in_group("enemy") or col.is_in_group("enemy_head") or col.name == "HeadHitbox":
				is_enemy_or_part = true
			elif GameTypes.resolve_damageable(col) != null:
				is_enemy_or_part = true
				
		if is_enemy_or_part:
			if "get_rid" in col:
				exclude_list.append(col.get_rid())
			current_from = hit_res.position + aim_dir * 0.05
			remaining_dist = MAX_BEAM_DIST - from_pos.distance_to(current_from)
		else:
			beam_end = hit_res.position
			break
			
	var beam_vec = beam_end - from_pos
	var beam_len = beam_vec.length()
	if beam_len < 0.1:
		if weapon_manager:
			weapon_manager.reload()
		return
	var beam_dir = beam_vec / beam_len
	
	var all_enemies = get_tree().get_nodes_in_group("enemy") if is_inside_tree() else []
	var hit_enemies: Array = []
	const BEAM_TOLERANCE: float = 0.38
	
	for e in all_enemies:
		if not is_instance_valid(e):
			continue
		if ("current_state" in e and e.current_state == e.State.DEAD) or ("health" in e and e.health <= 0):
			continue
			
		var e_pos = e.global_position
		var head_pos = e_pos + Vector3(0.0, 0.55, 0.0)
		var t_head = clamp((head_pos - from_pos).dot(beam_dir), 0.0, beam_len)
		var beam_pt_head = from_pos + beam_dir * t_head
		var dist_to_head = beam_pt_head.distance_to(head_pos)
		
		var t_body = clamp((e_pos - from_pos).dot(beam_dir), 0.0, beam_len)
		var beam_pt_body = from_pos + beam_dir * t_body
		var clamped_body_y = clamp(beam_pt_body.y, e_pos.y - 0.95, e_pos.y + 0.35)
		var body_axis_pt = Vector3(e_pos.x, clamped_body_y, e_pos.z)
		var dist_to_body = beam_pt_body.distance_to(body_axis_pt)
		
		var hit_head = dist_to_head <= (0.34 + BEAM_TOLERANCE)
		var hit_body = dist_to_body <= (0.36 + BEAM_TOLERANCE)
		
		if not hit_head and not hit_body:
			continue
			
		if t_head <= 0.05 and t_body <= 0.05:
			continue
			
		var is_headshot = false
		var hit_pos = beam_pt_body
		var target_dist = t_body
		
		if hit_head and (not hit_body or dist_to_head < dist_to_body or beam_pt_head.y >= e_pos.y + 0.35):
			is_headshot = true
			hit_pos = beam_pt_head
			target_dist = t_head
			
		var los_query = PhysicsRayQueryParameters3D.create(from_pos, hit_pos)
		los_query.collide_with_areas = false
		los_query.collide_with_bodies = true
		if is_instance_valid(player_node):
			los_query.exclude = [player_node]
		var los_res = space_state.intersect_ray(los_query)
		if not los_res.is_empty():
			var blocker = los_res.collider
			if blocker != e and not blocker.is_in_group("enemy") and not blocker.is_in_group("enemy_head"):
				continue
				
		hit_enemies.append({
			"enemy": e,
			"hit_pos": hit_pos,
			"dist": target_dist,
			"is_headshot": is_headshot
		})
		
	hit_enemies.sort_custom(func(a, b): return a["dist"] < b["dist"])
	
	var base_dmg = float(data.damage) if data else 70.0
	var hs_mult = data.headshot_multiplier if data else 1.7
	var air_mult = data.air_multiplier if data else 2.0
	var flat_dir = Vector3(aim_dir.x, 0.0, aim_dir.z).normalized()
	var knockback_force = data.knockback if data else 12.0
	var upward_force = data.upward_kick if data else 4.0
	var knockback_vector = flat_dir * knockback_force
	knockback_vector.y = upward_force
	
	for item in hit_enemies:
		var target = item["enemy"]
		if not is_instance_valid(target) or ("current_state" in target and target.current_state == target.State.DEAD):
			continue
			
		var is_headshot = item["is_headshot"]
		var target_body = GameTypes.resolve_damageable(target)
		var is_airborne: bool = not target_body.is_on_floor() if (target_body and target_body.has_method("is_on_floor")) else false
			
		var total_mult = 1.0
		if is_headshot and is_airborne:
			total_mult = hs_mult * air_mult
		elif is_headshot:
			total_mult = hs_mult
		elif is_airborne:
			total_mult = air_mult
			
		var final_dmg = int(round(base_dmg * total_mult))
		
		if is_headshot and is_airborne:
			GameTypes.debug_log(&"weapon", "[RAIL SHOT] AIRBORNE HEADSHOT on %s! (%.1fx MULTIPLICATIVE) Damage: %d | Base: %d" % [target.name, total_mult, final_dmg, int(base_dmg)])
		elif is_headshot:
			GameTypes.debug_log(&"weapon", "[RAIL SHOT] HEADSHOT on %s! (%.1fx) Damage: %d | Base: %d" % [target.name, total_mult, final_dmg, int(base_dmg)])
		elif is_airborne:
			GameTypes.debug_log(&"weapon", "[RAIL SHOT] AIRBORNE HIT on %s! (%.1fx) Damage: %d | Base: %d" % [target.name, total_mult, final_dmg, int(base_dmg)])
		else:
			GameTypes.debug_log(&"weapon", "[RAIL SHOT] PIERCING HIT on %s! Damage: %d | Base: %d" % [target.name, final_dmg, int(base_dmg)])
			
		target.take_damage(final_dmg, knockback_vector, item["hit_pos"], false, false, false, is_headshot, -1, "caliber0")
		
	TracerPool.spawn_tracer(start_pos, beam_end, &"piercing")
	# Вакуумный след создается РОВНО ОДИН РАЗ на весь луч выстрела
	_apply_vacuum_wake(start_pos, beam_end, 2.5, 25.6, null)
	
	if weapon_manager:
		weapon_manager.reload()

func get_alt_hud_suffix(has_infinite_ammo: bool = false) -> String:
	if has_infinite_ammo and weapon_manager:
		return " [RMB: %d]" % weapon_manager.ammos[slot_index]
	return ""
