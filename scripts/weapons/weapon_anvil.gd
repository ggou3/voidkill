class_name WeaponAnvil
extends WeaponBase

## Кровавая наковальня (Слот 2): Мощный двуствольный дробовик.
## ЛКМ: Выстрел дробью (8 дробин по 12 урона) с синергией застрявших игл (+4% за иглу до +60%).
## ПКМ: Пневмопоршень (sphere-cast AoE, 0 прямого урона): подброс в ноги (21 м/с) или 3D-толчок (42 м/с)
## для вызова wall_slam / collateral_slam; направленный self-launch игрока от поверхностей.

var self_launch_chain: int = 0
const ALT_COOLDOWN: float = 1.2

func _init() -> void:
	if not data:
		data = preload("res://scripts/weapons/data/anvil.tres")

func _process(delta: float) -> void:
	super._process(delta)
	var player = _get_player()
	if is_instance_valid(player) and player.is_on_floor() and player.velocity.y <= 0.0:
		self_launch_chain = 0

## Основной огонь (ЛКМ): 8 дробин через базовый _apply_hit
func fire() -> void:
	if not data:
		return
		
	fire_timer = data.fire_rate
	var head = _get_head()
	if head:
		head.add_recoil(data.cam_shake, data.weapon_kick)
		head.trigger_muzzle_flash(true)
	AudioManager.play_sound("shotgun_shot")
	
	var aim_dir = head.get_aim_direction() if head else Vector3.FORWARD
	for i in range(data.pellets):
		var ray = head.get_aim_raycast(data.spread) if head else null
		var hit_pos = ray.to_global(ray.target_position) if ray else Vector3.ZERO
		var collider: Node = null
		if ray and ray.is_colliding():
			hit_pos = ray.get_collision_point()
			collider = ray.get_collider()
		_apply_hit(collider, hit_pos, aim_dir, false)

## Синергия со Швейной машиной: +4% к урону за каждую застрявшую иглу (до 15 игл / +60%)
func _get_damage_multiplier(target: Node, _is_headshot: bool, _is_airborne: bool, _is_alt: bool) -> float:
	var enemy_node = GameTypes.resolve_enemy(target)
	var needle_count: int = 0
	if enemy_node and "needle_count" in enemy_node:
		needle_count = enemy_node.needle_count
	elif "needle_count" in target:
		needle_count = target.needle_count
		
	if needle_count > 0:
		var mult = 1.0 + min(needle_count, 15) * 0.04
		var base_dmg = float(data.damage) if data else 0.0
		GameTypes.debug_log(&"weapon", "[%s] SHOTGUN PELLET HIT: BaseDmg: %d | Needles: %d | Mult: %.2f" % [
			target.name, int(base_dmg), needle_count, mult
		])
		return mult
	return 1.0

## Альтернативный огонь (ПКМ): пневмопоршень
func alt_fire(_has_infinite_ammo: bool = false) -> void:
	if alt_timer > 0.0:
		return
	_fire_anvil_piston()

## Пневмопоршень Кровавой наковальни
func _fire_anvil_piston() -> void:
	var head = _get_head()
	if not head or not head.camera:
		return
		
	var aim_dir = head.get_aim_direction().normalized()
	var from_pos = head.camera.global_position
	var start_pos = _get_muzzle_position()
	var space_state = head.camera.get_world_3d().direct_space_state
	var player_node = _get_player()
	
	const PISTON_RANGE: float = 5.0 # Дальность действия ПКМ (5.0 метров)
	const SPHERE_TOLERANCE: float = 0.40 # Радиус допуска sphere-cast (0.4 метра вокруг центральной линии прицела)
	const ENEMY_COL_RADIUS: float = 0.38 # Радиус коллизии врага
	
	# 1. Поиск врагов с помощью Sphere-Cast детекции с радиусом допуска вдоль линии прицела
	var enemies_in_cone: Array = []
	var detected_enemies_set: Dictionary = {}
	var all_enemies = get_tree().get_nodes_in_group("enemy") if is_inside_tree() else []
	
	# А. Проверка прямого тонкого луча (для максимально точной фиксации точки коллизии при прямом прицеливании)
	var direct_ray = PhysicsRayQueryParameters3D.create(from_pos, from_pos + aim_dir * PISTON_RANGE)
	if is_instance_valid(player_node):
		direct_ray.exclude = [player_node]
	direct_ray.collide_with_areas = true
	direct_ray.collide_with_bodies = true
	var direct_res = space_state.intersect_ray(direct_ray)
	var direct_target: Node = null
	var direct_hit_pos: Vector3 = from_pos + aim_dir * PISTON_RANGE
	
	if not direct_res.is_empty():
		direct_hit_pos = direct_res.position
		var col = direct_res.collider
		if col:
			if col.is_in_group("enemy_head") or col.name == "HeadHitbox":
				direct_target = col.get_meta("enemy") if col.has_meta("enemy") else col.get_parent()
			else:
				direct_target = GameTypes.resolve_damageable(col)
				
	if direct_target and is_instance_valid(direct_target) and not ("current_state" in direct_target and direct_target.current_state == direct_target.State.DEAD):
		enemies_in_cone.append({
			"enemy": direct_target,
			"hit_pos": direct_hit_pos,
			"dist": from_pos.distance_to(direct_hit_pos)
		})
		detected_enemies_set[direct_target] = true
		
	# Б. Sphere-Cast сканирование врагов с радиусом допуска (0.4м на дистанции, до 0.55м в упор)
	var ray_dir_h = Vector2(aim_dir.x, aim_dir.z)
	var ray_dir_h_len_sq = ray_dir_h.length_squared()
	
	for e in all_enemies:
		if not is_instance_valid(e) or detected_enemies_set.has(e):
			continue
		if ("current_state" in e and e.current_state == e.State.DEAD) or ("health" in e and e.health <= 0):
			continue
			
		var e_pos = e.global_position
		var y_min = e_pos.y - 0.95
		var y_max = e_pos.y + 0.85
		
		# Проекция на линию луча прицела
		var t: float = 0.0
		if ray_dir_h_len_sq > 0.0001:
			var to_e_h = Vector2(e_pos.x - from_pos.x, e_pos.z - from_pos.z)
			var t_h = to_e_h.dot(ray_dir_h) / ray_dir_h_len_sq
			if t_h < -0.2:
				continue # Враг находится позади взгляда игрока
			t = clamp(t_h, 0.0, PISTON_RANGE)
		else:
			t = clamp(from_pos.y - e_pos.y, 0.0, PISTON_RANGE)
			
		var ray_pt = from_pos + aim_dir * t
		
		# Горизонтальное расстояние от точки луча до вертикальной оси врага
		var h_dist = Vector2(ray_pt.x - e_pos.x, ray_pt.z - e_pos.z).length()
		# Ближайшая точка по высоте на теле врага к точке луча
		var contact_y = clamp(ray_pt.y, y_min, y_max)
		var v_dist = abs(ray_pt.y - contact_y)
		
		var dist_to_axis = sqrt(h_dist * h_dist + v_dist * v_dist)
		var dist_to_surface = max(0.0, dist_to_axis - ENEMY_COL_RADIUS)
		
		# Радиус допуска: 0.40м на дистанции, до 0.55м в упор (до 2.0м)
		var allowed_tolerance = 0.55 if t <= 2.0 else SPHERE_TOLERANCE
		if dist_to_surface > allowed_tolerance:
			continue
			
		var hit_pos = Vector3(e_pos.x, contact_y, e_pos.z)
		if h_dist > 0.01:
			var h_norm = Vector3(ray_pt.x - e_pos.x, 0.0, ray_pt.z - e_pos.z).normalized()
			hit_pos += h_norm * ENEMY_COL_RADIUS
			
		var dist_from_player = from_pos.distance_to(hit_pos)
		if dist_from_player > PISTON_RANGE:
			continue
			
		# Проверка видимости цели через геометрию стен (Line of Sight)
		var occ_ray = PhysicsRayQueryParameters3D.create(from_pos, hit_pos)
		if is_instance_valid(player_node):
			occ_ray.exclude = [player_node]
		occ_ray.collide_with_areas = false
		occ_ray.collide_with_bodies = true
		var occ_res = space_state.intersect_ray(occ_ray)
		if not occ_res.is_empty():
			var occ_col = occ_res.collider
			if occ_col != e and GameTypes.resolve_enemy(occ_col) == null:
				continue # Перекрыто сплошной стеной
				
		enemies_in_cone.append({
			"enemy": e,
			"hit_pos": hit_pos,
			"dist": dist_from_player
		})
		detected_enemies_set[e] = true
		
	# Если обнаружен хотя бы один враг в конусе — бьем врагов (self-launch не срабатывает)
	if enemies_in_cone.size() > 0:
		alt_timer = ALT_COOLDOWN
		head.add_recoil(0.12, 0.40)
		head.trigger_muzzle_flash(true)
		AudioManager.play_sound("shotgun_shot")
		
		# Сортируем врагов по расстоянию от игрока (ближайший — первая цель цепи)
		enemies_in_cone.sort_custom(func(a, b): return a["dist"] < b["dist"])
		
		var primary_hit_pos = enemies_in_cone[0]["hit_pos"]
		
		for idx in range(enemies_in_cone.size()):
			var item = enemies_in_cone[idx]
			var target = item["enemy"]
			var hit_pos = item["hit_pos"]
			var chain_depth = idx
			
			# Фактическая высота точки контакта на теле врага
			var feet_y = target.global_position.y - 1.0
			var head_top_y = target.global_position.y + 0.89
			var total_height = head_top_y - feet_y # ~1.89м
			
			var contact_y = hit_pos.y
			var rel_height = clamp((contact_y - feet_y) / max(0.1, total_height), 0.0, 1.0)
			
			var target_body = GameTypes.resolve_damageable(target)
			var target_on_floor: bool = target_body.is_on_floor() if (target_body and target_body.has_method("is_on_floor")) else false
				
			# Условие подброса: точка контакта в нижних ~25-30% капсулы (rel_height <= 0.28) и на земле
			var is_aiming_at_legs = (rel_height <= 0.28) and target_on_floor
			
			var push_vec: Vector3 = Vector3.ZERO
			if is_aiming_at_legs:
				var upward_impulse = 21.0
				var push_h = Vector3(aim_dir.x, 0, aim_dir.z).normalized() * 5.0
				push_vec = Vector3(push_h.x, upward_impulse, push_h.z)
				GameTypes.debug_log(&"weapon", "[ANVIL PISTON] VERTICAL LAUNCH -> %s (rel_height: %.2f, on_floor: true, impulse: %.1f)" % [target.name, rel_height, upward_impulse])
			else:
				var push_speed = 42.0
				var push_dir = aim_dir.normalized()
				push_vec = push_dir * push_speed
				GameTypes.debug_log(&"weapon", "[ANVIL PISTON] 3D DIRECTIONAL PUSH -> %s (rel_height: %.2f, on_floor: %s, speed: %.1f, push_vec: %s)" % [target.name, rel_height, str(target_on_floor), push_speed, push_vec])
				
			# 0 прямого урона, активирует wall_slam и collateral_slam
			target.take_damage(0, push_vec, hit_pos, false, false, true, false, chain_depth, "anvil")
			
		TracerPool.spawn_tracer(start_pos, primary_hit_pos, &"piston", false)
		return
		
	# 2. Прямого попадания во врагов нет — проверяем попадание конуса в статичную геометрию (стена, пол, потолок)
	var hit_geom: bool = false
	var geom_hit_pos: Vector3 = from_pos + aim_dir * PISTON_RANGE
	var geom_hit_normal: Vector3 = Vector3.UP
	var geom_hit_dist: float = PISTON_RANGE
	
	var geom_ray = PhysicsRayQueryParameters3D.create(from_pos, from_pos + aim_dir * PISTON_RANGE)
	if is_instance_valid(player_node):
		geom_ray.exclude = [player_node]
	geom_ray.collide_with_areas = false
	geom_ray.collide_with_bodies = true
	var geom_res = space_state.intersect_ray(geom_ray)
	
	if not geom_res.is_empty():
		hit_geom = true
		geom_hit_pos = geom_res.position
		geom_hit_normal = geom_res.normal
		geom_hit_dist = from_pos.distance_to(geom_hit_pos)
	else:
		var cam_basis = head.camera.global_transform.basis
		var cone_offsets = [
			Vector3.UP * 0.16,
			Vector3.DOWN * 0.16,
			Vector3.LEFT * 0.16,
			Vector3.RIGHT * 0.16
		]
		for offset in cone_offsets:
			var test_dir = (aim_dir + cam_basis * offset).normalized()
			var sub_query = PhysicsRayQueryParameters3D.create(from_pos, from_pos + test_dir * PISTON_RANGE)
			if is_instance_valid(player_node):
				sub_query.exclude = [player_node]
			sub_query.collide_with_areas = false
			sub_query.collide_with_bodies = true
			var sub_res = space_state.intersect_ray(sub_query)
			if not sub_res.is_empty():
				var d = from_pos.distance_to(sub_res.position)
				if d < geom_hit_dist:
					hit_geom = true
					geom_hit_dist = d
					geom_hit_pos = sub_res.position
					geom_hit_normal = sub_res.normal
					
	if hit_geom:
		# Проверяем: есть ли враги, стоящие на поверхности в радиусе ~1.8-2.0м от точки попадания (выстрел в пол под удалённым врагом)
		const FLOOR_SPLASH_RADIUS: float = 2.0
		var splash_enemies: Array = []
		
		for e in all_enemies:
			if not is_instance_valid(e):
				continue
			if ("current_state" in e and e.current_state == e.State.DEAD) or ("health" in e and e.health <= 0):
				continue
				
			var e_pos = e.global_position
			var e_feet_y = e_pos.y - 1.0
			var h_dist = Vector2(e_pos.x - geom_hit_pos.x, e_pos.z - geom_hit_pos.z).length()
			var v_diff = abs(geom_hit_pos.y - e_feet_y)
			
			if h_dist <= FLOOR_SPLASH_RADIUS and v_diff <= 1.4:
				var splash_occ = PhysicsRayQueryParameters3D.create(geom_hit_pos + geom_hit_normal * 0.1, e_pos + Vector3(0, -0.4, 0))
				if is_instance_valid(player_node):
					splash_occ.exclude = [player_node]
				splash_occ.collide_with_areas = false
				splash_occ.collide_with_bodies = true
				var splash_res = space_state.intersect_ray(splash_occ)
				if not splash_res.is_empty():
					var occ_col = splash_res.collider
					if occ_col != e and GameTypes.resolve_enemy(occ_col) == null:
						continue
						
				splash_enemies.append({
					"enemy": e,
					"dist": h_dist
				})
				
		if splash_enemies.size() > 0:
			splash_enemies.sort_custom(func(a, b): return a["dist"] < b["dist"])
			
			for idx in range(splash_enemies.size()):
				var target = splash_enemies[idx]["enemy"]
				var chain_depth = idx
				var upward_impulse = 21.0
				var push_h = Vector3(aim_dir.x, 0, aim_dir.z).normalized() * 5.0
				var push_vec = Vector3(push_h.x, upward_impulse, push_h.z)
				GameTypes.debug_log(&"weapon", "[ANVIL PISTON] FLOOR SPLASH LAUNCH -> %s (h_dist: %.2f, impulse: %.1f)" % [target.name, splash_enemies[idx]["dist"], upward_impulse])
				
				var hit_pos = target.global_position + Vector3(0, -0.6, 0)
				target.take_damage(0, push_vec, hit_pos, false, false, true, false, chain_depth, "anvil")
				
		# Выполняем self-launch игрока от статичной геометрии
		_perform_self_launch(aim_dir, geom_hit_pos, geom_hit_normal)
	else:
		# Выстрел в пустое пространство (> 5 метров)
		alt_timer = ALT_COOLDOWN
		head.add_recoil(0.08, 0.25)
		head.trigger_muzzle_flash(true)
		AudioManager.play_sound("shotgun_shot")
		TracerPool.spawn_tracer(start_pos, from_pos + aim_dir * PISTON_RANGE, &"piston", false)
		GameTypes.debug_log(&"weapon", "[ANVIL PISTON] Air blast (no surface or enemy in range)")

## Направленный self-launch игрока от геометрии
func _perform_self_launch(aim_dir: Vector3, surface_hit_pos: Vector3, _surface_normal: Vector3) -> void:
	var player_node = _get_player()
	if not is_instance_valid(player_node):
		return
		
	alt_timer = ALT_COOLDOWN
	
	if player_node.is_on_floor():
		self_launch_chain = 0
		
	var mult: float = 1.0
	if self_launch_chain == 0:
		mult = 1.0
	elif self_launch_chain == 1:
		mult = 0.60
	else:
		mult = 0.35
	self_launch_chain += 1
	
	var base_impulse: float = 19.5
	var final_impulse: float = base_impulse * mult
	
	# Импульс строго против взгляда камеры (-aim_dir)
	var push_dir: Vector3 = -aim_dir.normalized()
	var impulse_vec: Vector3 = push_dir * final_impulse
	
	player_node.velocity += impulse_vec
	
	# Ограничение вертикальной скорости
	var max_vertical: float = 22.0 * mult
	if player_node.velocity.y > max_vertical:
		player_node.velocity.y = max_vertical
		
	if impulse_vec.y >= 0.0 and player_node.is_on_floor() and player_node.velocity.y < 3.5:
		player_node.velocity.y = max(player_node.velocity.y, 3.5 * mult)
		
	if "has_jumped" in player_node:
		player_node.has_jumped = true
	if "time_on_ground" in player_node:
		player_node.time_on_ground = 0.0
	if "air_time" in player_node:
		player_node.air_time = 0.1
	if "coyote_timer" in player_node:
		player_node.coyote_timer = 0.0
	if "jump_buffer_timer" in player_node:
		player_node.jump_buffer_timer = 0.0
	if "is_sliding" in player_node and player_node.is_sliding:
		player_node.is_sliding = false
		
	var head = _get_head()
	if head:
		head.add_recoil(0.14, 0.45)
		head.trigger_muzzle_flash(true)
		head.landing_shake_trauma = max(head.landing_shake_trauma, 0.5 * mult)
	AudioManager.play_sound("shotgun_shot")
	
	var start_pos = _get_muzzle_position()
	TracerPool.spawn_tracer(start_pos, surface_hit_pos, &"piston", true)
	
	GameTypes.debug_log(&"weapon", "[ANVIL PISTON] SELF-LAUNCH! Chain: %d | Mult: %.2f | Impulse: %.1f | PushDir: %s | Vel: %s" % [
		self_launch_chain, mult, final_impulse, push_dir, player_node.velocity
	])

func get_alt_hud_suffix(_has_infinite_ammo: bool = false) -> String:
	if alt_timer > 0.0:
		return " (RMB %.1fs)" % alt_timer
	return ""
