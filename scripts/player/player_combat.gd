class_name PlayerCombat
extends Node

## Ближний бой игрока: одиночный мили-удар, конусная ударная волна на высокой скорости,
## execute-добивание и парирование вражеских снарядов.

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

var player: Player

func setup(p: Player) -> void:
	player = p

func tick_cooldown(delta: float) -> void:
	if melee_timer > 0.0:
		melee_timer -= delta

## Отслеживание недавней пиковой скорости (до возможного гашения скорости столкновениями).
## Вызывается из Player._physics_process до move_and_slide().
func track_peak_speed(h_vel_len: float, delta: float) -> void:
	if h_vel_len >= recent_peak_speed:
		recent_peak_speed = h_vel_len
		recent_peak_timer = 0.35
	else:
		recent_peak_timer -= delta
		if recent_peak_timer <= 0.0:
			recent_peak_speed = h_vel_len

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

	var scene_root = get_tree().current_scene if get_tree().current_scene else player.get_parent()
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

func _check_and_deflect_projectiles(from_pos: Vector3, aim_dir: Vector3, is_shockwave: bool) -> bool:
	var projectiles = get_tree().get_nodes_in_group("enemy_projectile")
	if projectiles.is_empty():
		return false

	var check_range = cone_melee_range if is_shockwave else 3.8
	var check_angle = cone_melee_angle if is_shockwave else 90.0
	var min_cos = cos(deg_to_rad(check_angle * 0.5))
	var space_state = player.get_world_3d().direct_space_state

	var deflected_any = false

	for proj in projectiles:
		if not is_instance_valid(proj) or proj.is_queued_for_deletion():
			continue
		if ("is_destroyed" in proj and proj.is_destroyed) or ("is_deflected" in proj and proj.is_deflected):
			continue

		var to_proj = proj.global_position - from_pos
		var dist = to_proj.length()
		if dist > check_range:
			continue

		# Проверка угла: вблизи (до 1.8м) захватываем всё перед игроком, на дистанции — по конусу
		var dir_to_proj = to_proj / max(0.001, dist)
		var dot = aim_dir.dot(dir_to_proj)
		if dist > 1.8 and dot < min_cos:
			continue

		# Проверка Line of Sight: снаряд не должен быть за сплошной стеной
		if space_state:
			var ray = PhysicsRayQueryParameters3D.create(from_pos, proj.global_position)
			ray.exclude = [player, proj]
			var occ = space_state.intersect_ray(ray)
			if not occ.is_empty() and not occ.collider.is_in_group("enemy"):
				continue

		# Отражаем снаряд по вектору взгляда игрока (aim_dir)
		if proj is ProjectileEnemy:
			var orig_pos = proj.global_position
			proj.deflect(aim_dir, 27.0, 24, from_pos)
			_spawn_deflect_flash(orig_pos)
			_spawn_deflect_feedback(orig_pos)
			deflected_any = true

	if deflected_any:
		AudioManager.play_sound("parry_deflect")
		player.head.trigger_melee_impact(false)
		player.head.add_recoil(0.08, 0.4)

	return deflected_any

func _spawn_deflect_flash(pos: Vector3):
	var scene_root = get_tree().current_scene if (get_tree() and get_tree().current_scene) else player.get_parent()
	if not scene_root:
		return
	var flash = MeshInstance3D.new()
	var sphere = SphereMesh.new()
	sphere.radius = 0.35
	sphere.height = 0.7
	flash.mesh = sphere
	var mat = StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.25, 0.95, 1.0, 0.9)
	flash.material_override = mat
	scene_root.add_child(flash)
	flash.global_position = pos
	var tween = flash.create_tween().set_parallel(true)
	tween.tween_property(flash, "scale", Vector3(3.5, 3.5, 3.5), 0.2).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tween.tween_property(mat, "albedo_color:a", 0.0, 0.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(flash.queue_free)

func _spawn_deflect_feedback(pos: Vector3):
	var scene_root = get_tree().current_scene if (get_tree() and get_tree().current_scene) else player.get_parent()
	if not scene_root:
		return
	var label = Label3D.new()
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.outline_size = 8
	label.outline_modulate = Color.BLACK
	label.text = "PARRY!"
	label.modulate = Color(0.2, 0.95, 1.0, 1.0)
	label.font_size = 36
	scene_root.add_child(label)
	label.global_position = pos + Vector3(0.0, 0.3, 0.0)
	var tween = label.create_tween().set_parallel(true)
	tween.tween_property(label, "global_position", pos + Vector3(0.0, 1.2, 0.0), 0.65).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "modulate:a", 0.0, 0.65).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(label.queue_free)

func perform_melee():
	var skills = player.skills
	var head = player.head
	if melee_timer > 0.0 or player.is_dead or skills.is_slamming:
		return

	melee_timer = melee_cooldown

	var cur_speed = Vector2(player.velocity.x, player.velocity.z).length()
	var effective_speed = max(cur_speed, recent_peak_speed)
	var cap = player.get_current_max_speed()
	var aim_dir = head.get_aim_direction()

	# Строгий порог: конусная ударная волна активируется ТОЛЬКО при скорости >= 16.5 м/с
	var is_cone_shockwave = effective_speed >= cone_melee_speed_threshold

	# Инерция и импульс: выпад вперёд в направлении взгляда при ударе в движении, дэше или слайде
	var is_moving = cur_speed > 0.5 or recent_peak_speed > 1.0 or skills.is_dashing or player.is_sliding
	if is_moving:
		var lunge_dir = Vector3(aim_dir.x, 0.0, aim_dir.z).normalized()
		if lunge_dir != Vector3.ZERO:
			var boost = melee_lunge_boost
			if skills.is_dashing or player.is_sliding or is_cone_shockwave:
				boost *= 1.3 # Усиленный кинетический выпад при выходе из дэша, слайда или на максимальной скорости
			player.velocity.x += lunge_dir.x * boost
			player.velocity.z += lunge_dir.z * boost

			# Удерживаем скорость в пределах действующего потолка скорости
			var new_horiz_speed = Vector2(player.velocity.x, player.velocity.z).length()
			if new_horiz_speed > cap:
				var clamped_vel = Vector2(player.velocity.x, player.velocity.z).normalized() * cap
				player.velocity.x = clamped_vel.x
				player.velocity.z = clamped_vel.y

	# Визуальная анимация удара левой рукой
	head.play_melee_animation()

	# Базовый толчок оружия/камеры при взмахе (усилен при конусной ударной волне)
	head.add_recoil(0.06 if is_cone_shockwave else 0.03, 0.35 if is_cone_shockwave else 0.2)

	var space_state = player.get_world_3d().direct_space_state
	var from_pos = head.camera.global_position

	# Парирование/отражение вражеских снарядов (Deflect/Parry)
	_check_and_deflect_projectiles(from_pos, aim_dir, is_cone_shockwave)

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
		direct_ray.exclude = [player]
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
		shape_query.exclude = [player]
		var close_results = space_state.intersect_shape(shape_query, 8)
		for r in close_results:
			var col = r.collider
			if col and col != player and col.is_in_group("enemy") and not ("current_state" in col and col.current_state == col.State.DEAD):
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
			occ_query.exclude = [player]
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
			var enemy_node = GameTypes.resolve_enemy(e)
			if enemy_node and "needle_count" in enemy_node:
				needle_count = enemy_node.needle_count
			elif "needle_count" in e:
				needle_count = e.needle_count

			var final_multiplier: float = 1.0 + min(needle_count, 15) * 0.04
			var eff_dmg: int = int(round(float(raw_eff_dmg) * final_multiplier))

			if needle_count > 0:
				GameTypes.debug_log(&"player", "[%s] CONE MELEE HIT: BaseEffDmg: %d | Needles: %d | Mult: %.2f | FinalDmg: %d" % [
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

		GameTypes.debug_log(&"player", "[MELEE] Speed: %.2f (Live: %.2f, Peak: %.2f) | Thresh: %.2f | BaseDmg: %.1f | SHOCKWAVE: true | Hits: %d" % [
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
		ray_query.exclude = [player]
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
			shape_query.exclude = [player]
			var results = space_state.intersect_shape(shape_query, 8)
			for r in results:
				var col = r.collider
				if col and col != player and (col.is_in_group("enemy") or col.has_method("take_damage")):
					hit_collider = col
					hit_pos = col.global_position + Vector3(0, 0.8, 0)
					break

		var hit_anything = false
		var damageable_target = GameTypes.resolve_damageable(hit_collider)
		if damageable_target and damageable_target.has_method("take_damage"):
			hit_collider = damageable_target
			hit_anything = true
			AudioManager.play_sound("melee_hit")
			var enemy_cur_hp: int = hit_collider.health if "health" in hit_collider else 100
			var enemy_max_hp: int = hit_collider.max_health if "max_health" in hit_collider else 100

			var needle_count: int = 0
			var enemy_node = GameTypes.resolve_enemy(hit_collider)
			if enemy_node and "needle_count" in enemy_node:
				needle_count = enemy_node.needle_count
			elif "needle_count" in hit_collider:
				needle_count = hit_collider.needle_count

			var final_multiplier: float = 1.0 + min(needle_count, 15) * 0.04
			var is_execute: bool = (float(enemy_cur_hp) <= float(enemy_max_hp) * execute_health_threshold)
			var eff_melee_damage: int = int(round(float(melee_damage) * final_multiplier))
			var dmg: int = max(eff_melee_damage, enemy_cur_hp) if is_execute else eff_melee_damage
			var will_kill: bool = is_execute or (enemy_cur_hp <= dmg)

			if needle_count > 0:
				GameTypes.debug_log(&"player", "[%s] REGULAR MELEE HIT: BaseDmg: %d | Needles: %d | Mult: %.2f | FinalDmg: %d" % [
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

		GameTypes.debug_log(&"player", "[MELEE] Speed: %.2f (Live: %.2f, Peak: %.2f) | Thresh: %.2f | SHOCKWAVE: false | Dmg: %d | Hit: %s" % [
			effective_speed, cur_speed, recent_peak_speed, cone_melee_speed_threshold, melee_damage, str(hit_anything)
		])
