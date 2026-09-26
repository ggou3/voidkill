class_name StatusEffectComponent
extends Node

## StatusEffectComponent — компонент управления статус-эффектами врага
## (яд/DoT, застрявшие иглы, замедление, раздутие кровью/детонация).

signal effect_applied(kind: StringName, stacks: int)
signal effect_expired(kind: StringName)
signal visuals_need_update(kind: StringName)
signal requests_damage(amount: int, kind: StringName)

@export var actor: Node3D = null
var health_component: HealthComponent = null

# Замедление (Slow)
var slow_factor: float = 1.0
var slow_sources: int = 0

# Яд (Poison DoT)
const MAX_POISON_STACKS: int = 5
var poison_stacks: Array[Dictionary] = []

# Иглы (Needles)
var needle_count: int = 0
var needle_timers: Array[float] = []

# Инфляция (Раздутие кровью)
var is_inflated: bool = false
var inflation_tween: Tween = null
var inflation_pulse_tween: Tween = null

var blood_splatter_scene = preload("res://blood_splatter.tscn")

func _ready() -> void:
	if not actor:
		actor = get_parent() as Node3D
	if actor and not health_component:
		if "health_component" in actor and is_instance_valid(actor.health_component):
			health_component = actor.health_component
		elif actor.has_node("HealthComponent"):
			health_component = actor.get_node("HealthComponent") as HealthComponent

func is_actor_dead() -> bool:
	if not is_instance_valid(actor):
		return true
	if is_instance_valid(health_component) and health_component.is_dead():
		return true
	if "current_state" in actor and actor.current_state == 3: # State.DEAD in Enemy
		return true
	if "health" in actor and actor.health <= 0:
		return true
	return false

func _physics_process(delta: float) -> void:
	if is_actor_dead():
		return
	_process_poison(delta)
	_process_needles(delta)

# ==============================================================================
# ЗАМЕДЛЕНИЕ (SLOW)
# ==============================================================================

func add_slow(factor: float = 0.5) -> void:
	slow_sources += 1
	slow_factor = factor
	effect_applied.emit(&"slow", slow_sources)

func remove_slow() -> void:
	slow_sources = max(0, slow_sources - 1)
	if slow_sources == 0:
		slow_factor = 1.0
		effect_expired.emit(&"slow")

# ==============================================================================
# ЯД (POISON DOT & CONTAGION)
# ==============================================================================

func apply_poison_dot(duration: float = 3.0, damage_per_tick: int = 3, interval: float = 0.5, chain_depth: int = 0) -> void:
	if is_actor_dead():
		return
	if is_instance_valid(actor) and "last_damage_weapon" in actor:
		actor.last_damage_weapon = "injector"
	if is_instance_valid(health_component):
		health_component.last_damage_weapon = "injector"
		
	if poison_stacks.size() < MAX_POISON_STACKS:
		poison_stacks.append({
			"duration": duration,
			"tick_timer": interval,
			"damage": damage_per_tick,
			"interval": interval,
			"chain_depth": chain_depth
		})
	else:
		# При максимуме 5 стаков обновляем стак с наименьшим оставшимся временем
		var min_idx = 0
		var min_dur = float(poison_stacks[0]["duration"])
		for i in range(1, poison_stacks.size()):
			if float(poison_stacks[i]["duration"]) < min_dur:
				min_dur = float(poison_stacks[i]["duration"])
				min_idx = i
		poison_stacks[min_idx]["duration"] = max(float(poison_stacks[min_idx]["duration"]), duration)
		poison_stacks[min_idx]["chain_depth"] = min(int(poison_stacks[min_idx]["chain_depth"]), chain_depth)
		
	effect_applied.emit(&"poison", poison_stacks.size())

func _process_poison(delta: float) -> void:
	if poison_stacks.is_empty():
		return
	var had_stacks = poison_stacks.size() > 0
	var write_idx = 0
	for i in range(poison_stacks.size()):
		var stack = poison_stacks[i]
		stack["duration"] -= delta
		stack["tick_timer"] -= delta
		if stack["tick_timer"] <= 0.0:
			stack["tick_timer"] = float(stack["interval"])
			_apply_poison_tick(int(stack["damage"]))
			if is_actor_dead():
				break
		if stack["duration"] > 0.0 and not is_actor_dead():
			poison_stacks[write_idx] = stack
			write_idx += 1
	if not is_actor_dead():
		poison_stacks.resize(write_idx)
		if had_stacks and poison_stacks.is_empty():
			effect_expired.emit(&"poison")

func _apply_poison_tick(damage: int) -> void:
	if is_actor_dead():
		return
	requests_damage.emit(damage, &"poison")

func trigger_poison_contagion(depth: int = 0) -> void:
	const CONTAGION_RADIUS: float = 2.5
	var actor_pos = actor.global_position if is_instance_valid(actor) else Vector3.ZERO
	var cloud_pos = actor_pos + Vector3(0, 0.8, 0)
	var actor_name = actor.name if is_instance_valid(actor) else "Enemy"
	
	GameTypes.debug_log(&"enemy", "[%s] POISON CONTAGION! depth: %d, radius: %.1fm" % [actor_name, depth, CONTAGION_RADIUS])
	AudioManager.play_sound("flask_splash")
	
	var scene_root = get_tree().current_scene if get_tree().current_scene else (actor.get_parent() if is_instance_valid(actor) else get_parent())
	if scene_root:
		_spawn_poison_cloud_visual(scene_root, cloud_pos, CONTAGION_RADIUS)
		
	var space_state: PhysicsDirectSpaceState3D = null
	if is_instance_valid(actor) and actor is Node3D:
		space_state = (actor as Node3D).get_world_3d().direct_space_state
		
	var all_enemies = get_tree().get_nodes_in_group("enemy")
	for enemy in all_enemies:
		if not is_instance_valid(enemy) or enemy == actor:
			continue
		if ("current_state" in enemy and enemy.current_state == enemy.State.DEAD) or ("health" in enemy and enemy.health <= 0):
			continue
			
		var enemy_center = enemy.global_position + Vector3(0, 0.8, 0)
		var dist = cloud_pos.distance_to(enemy_center)
		if dist <= CONTAGION_RADIUS:
			if space_state:
				var ray_query = PhysicsRayQueryParameters3D.create(cloud_pos, enemy_center)
				ray_query.exclude = [actor, enemy]
				ray_query.collide_with_areas = false
				ray_query.collide_with_bodies = true
				var hit_res = space_state.intersect_ray(ray_query)
				if not hit_res.is_empty():
					var col = hit_res.collider
					if col and not (col.is_in_group("enemy") or col.is_in_group("enemy_head")):
						continue
						
			if enemy.has_method("apply_poison_dot"):
				enemy.apply_poison_dot(3.0, 3, 0.5, depth + 1)
				GameTypes.debug_log(&"enemy", "[%s] CONTAGION INFECTED %s! Stack applied at depth %d" % [actor_name, enemy.name, depth + 1])

func spawn_poison_cloud_visual(scene_root: Node, cloud_pos: Vector3, cloud_radius: float) -> void:
	_spawn_poison_cloud_visual(scene_root, cloud_pos, cloud_radius)

func _spawn_poison_cloud_visual(scene_root: Node, cloud_pos: Vector3, cloud_radius: float) -> void:
	var mesh_inst = MeshInstance3D.new()
	var smesh = SphereMesh.new()
	smesh.radius = 0.4
	smesh.height = 0.8
	smesh.radial_segments = 16
	smesh.rings = 8
	mesh_inst.mesh = smesh
	
	var mat = StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = Color(0.25, 0.95, 0.35, 0.6) # Токсично-зеленый цвет яда
	mesh_inst.material_override = mat
	
	scene_root.add_child(mesh_inst)
	mesh_inst.global_position = cloud_pos
	
	var target_scale = Vector3.ONE * (cloud_radius / 0.4)
	var tween = mesh_inst.create_tween().set_parallel(true)
	tween.tween_property(mesh_inst, "scale", target_scale, 0.38).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(mat, "albedo_color:a", 0.0, 0.38).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(mesh_inst.queue_free)

# ==============================================================================
# ИГЛЫ (NEEDLES & BURST)
# ==============================================================================

func add_needle(_is_blood_needle: bool = false) -> void:
	if is_actor_dead():
		return
	if is_instance_valid(actor) and "last_damage_weapon" in actor:
		actor.last_damage_weapon = "sewing"
	if is_instance_valid(health_component):
		health_component.last_damage_weapon = "sewing"
		
	needle_timers.append(6.0)
	needle_count = needle_timers.size()
	effect_applied.emit(&"needle", needle_count)
	visuals_need_update.emit(&"needle")
	var actor_name = actor.name if is_instance_valid(actor) else "Enemy"
	GameTypes.debug_log(&"enemy", "[%s] Needle stuck! Total needles: %d" % [actor_name, needle_count])

func _process_needles(delta: float) -> void:
	if needle_timers.is_empty():
		return
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
		visuals_need_update.emit(&"needle")
		if needle_count == 0:
			effect_expired.emit(&"needle")

func trigger_needle_burst(was_inflated: bool, depth: int) -> void:
	var burst_radius: float = 6.0 if was_inflated else 4.0
	var count = needle_count
	needle_count = 0
	needle_timers.clear()
	visuals_need_update.emit(&"needle")
	effect_expired.emit(&"needle")
	
	# Расчет урона за иглу с учетом раздутия и цепного затухания Инъектора
	var base_needle_dmg = 8.0 if was_inflated else 3.0
	var mult: float = 1.0
	if was_inflated:
		if depth >= 3:
			mult = 0.20
		else:
			mult = pow(0.7, depth)
	var damage_per_needle = max(1, int(round(base_needle_dmg * mult)))
	
	var actor_pos = actor.global_position if is_instance_valid(actor) else Vector3.ZERO
	var burst_pos = actor_pos + Vector3(0.0, 0.85, 0.0)
	var space_state: PhysicsDirectSpaceState3D = null
	if is_instance_valid(actor) and actor is Node3D:
		space_state = (actor as Node3D).get_world_3d().direct_space_state
	if not space_state:
		return
		
	var all_enemies = get_tree().get_nodes_in_group("enemy")
	var nearby_enemies: Array = []
	for e in all_enemies:
		if not is_instance_valid(e) or e == actor:
			continue
		if ("current_state" in e and e.current_state == e.State.DEAD) or ("health" in e and e.health <= 0):
			continue
		var e_pos = e.global_position + Vector3(0.0, 0.85, 0.0)
		var dist = burst_pos.distance_to(e_pos)
		if dist <= burst_radius:
			nearby_enemies.append({"enemy": e, "pos": e_pos, "dist": dist})
			
	nearby_enemies.sort_custom(func(a, b): return a["dist"] < b["dist"])
	
	var actor_name = actor.name if is_instance_valid(actor) else "Enemy"
	GameTypes.debug_log(&"enemy", "[%s] NEEDLE BURST! Count: %d | Inflated: %s | Radius: %.1f | DmgPerNeedle: %d | Depth: %d | EnemiesNearby: %d" % [
		actor_name, count, str(was_inflated), burst_radius, damage_per_needle, depth, nearby_enemies.size()
	])
	
	AudioManager.play_sound("needle_shot")
	
	const NEEDLE_TOLERANCE: float = 0.40
	
	for i in range(count):
		var needle_dir: Vector3 = Vector3.FORWARD
		if nearby_enemies.size() > 0:
			var target_entry = nearby_enemies[i % nearby_enemies.size()]
			var to_target = target_entry["pos"] - burst_pos
			var base_dir = to_target.normalized() if to_target.length_squared() > 0.01 else Vector3.FORWARD
			var jitter = Vector3(randf_range(-0.12, 0.12), randf_range(-0.12, 0.12), randf_range(-0.12, 0.12))
			needle_dir = (base_dir + jitter).normalized()
		else:
			var angle = (float(i) / float(count)) * TAU + randf_range(-0.1, 0.1)
			needle_dir = Vector3(cos(angle), randf_range(-0.2, 0.3), sin(angle)).normalized()
			
		var max_dist = burst_radius
		var wall_query = PhysicsRayQueryParameters3D.create(burst_pos, burst_pos + needle_dir * max_dist)
		wall_query.exclude = [actor]
		wall_query.collide_with_areas = false
		wall_query.collide_with_bodies = true
		var wall_res = space_state.intersect_ray(wall_query)
		var needle_end = burst_pos + needle_dir * max_dist
		if not wall_res.is_empty():
			var col = wall_res.collider
			if col and not (col.is_in_group("enemy") or col.is_in_group("enemy_head")):
				needle_end = wall_res.position
				max_dist = burst_pos.distance_to(needle_end)
				
		var line_vec = needle_end - burst_pos
		var line_len = line_vec.length()
		if line_len < 0.05:
			continue
		var line_dir = line_vec / line_len
		
		var hit_on_path: Array = []
		for cand in nearby_enemies:
			var e = cand["enemy"]
			if not is_instance_valid(e):
				continue
			var e_pos = cand["pos"]
			var t = clamp((e_pos - burst_pos).dot(line_dir), 0.0, line_len)
			if t < 0.05:
				continue
			var pt = burst_pos + line_dir * t
			var d = pt.distance_to(e_pos)
			if d <= (0.36 + NEEDLE_TOLERANCE):
				hit_on_path.append({"enemy": e, "hit_pos": pt, "dist": t})
				
		hit_on_path.sort_custom(func(a, b): return a["dist"] < b["dist"])
		
		if not was_inflated:
			# Обычный разлёт: игла поражает только ближайшего врага на траектории (не пробивает)
			if not hit_on_path.is_empty():
				var first_hit = hit_on_path[0]
				var target = first_hit["enemy"]
				if is_instance_valid(target) and ("health" in target and target.health > 0):
					var knock = needle_dir * 1.5 + Vector3.UP * 0.5
					target.take_damage(damage_per_needle, knock, first_hit["hit_pos"], false, false, false, false, -1, "sewing")
				needle_end = first_hit["hit_pos"]
		else:
			# Раздутый враг: иглы пробивают навылет всех врагов на своей траектории с наследованием chain_depth
			for hit_info in hit_on_path:
				var target = hit_info["enemy"]
				if is_instance_valid(target) and ("health" in target and target.health > 0):
					var knock = needle_dir * 2.5 + Vector3.UP * 0.8
					target.take_damage(damage_per_needle, knock, hit_info["hit_pos"], false, false, false, false, depth, "sewing")
					
		TracerPool.spawn_tracer(burst_pos, needle_end, &"shrapnel", was_inflated)

# ==============================================================================
# ИНФЛЯЦИЯ (РАЗДУТИЕ И ДЕТОНАЦИЯ)
# ==============================================================================

func inflate() -> void:
	if is_inflated or is_actor_dead():
		return
	if is_instance_valid(actor) and "last_damage_weapon" in actor:
		actor.last_damage_weapon = "injector"
	if is_instance_valid(health_component):
		health_component.last_damage_weapon = "injector"
		
	is_inflated = true
	effect_applied.emit(&"inflation", 1)
	visuals_need_update.emit(&"inflation")
	
	var actor_name = actor.name if is_instance_valid(actor) else "Enemy"
	GameTypes.debug_log(&"enemy", "[%s] INFLATED with blood!" % actor_name)

func trigger_inflation_explosion(depth: int = 0) -> void:
	is_inflated = false
	if inflation_pulse_tween:
		inflation_pulse_tween.kill()
	if inflation_tween:
		inflation_tween.kill()
	effect_expired.emit(&"inflation")
		
	var actor_pos = actor.global_position if is_instance_valid(actor) else Vector3.ZERO
	var explosion_pos = actor_pos + Vector3(0, 0.9, 0)
	
	# Расчёт затухания силы взрыва в зависимости от глубины цепи (chain_depth)
	# глубина 0 = 100%, глубина 1 = 70%, глубина 2 = 49%, глубина 3+ = 20%
	var mult: float = 1.0
	if depth >= 3:
		mult = 0.20
	else:
		mult = pow(0.7, depth)
		
	var base_radius: float = 5.2
	var base_damage: int = 85
	var explosion_radius: float = base_radius * mult
	var explosion_damage: int = max(1, int(round(float(base_damage) * mult)))
	
	var was_killed_melee: bool = false
	if is_instance_valid(health_component):
		was_killed_melee = health_component.was_killed_by_melee
	elif is_instance_valid(actor) and "was_killed_by_melee" in actor:
		was_killed_melee = actor.was_killed_by_melee
		
	var base_heal: int = 35 if was_killed_melee else 15
	var heal_amount: int = max(1, int(round(float(base_heal) * mult)))
	
	var actor_name = actor.name if is_instance_valid(actor) else "Enemy"
	GameTypes.debug_log(&"enemy", "[%s] DETONATION! chain_depth: %d | mult: %.2f | dmg: %d | radius: %.2fm | heal: %d%s" % [
		actor_name, depth, mult, explosion_damage, explosion_radius, heal_amount,
		" (CHAIN LIMIT: NO FURTHER CHAIN DETONATIONS)" if depth >= 3 else ""
	])
	
	AudioManager.play_sound("explosion")
	
	var scene_root = get_tree().current_scene if get_tree().current_scene else (actor.get_parent() if is_instance_valid(actor) else get_parent())
	if scene_root:
		# Сочный разлёт крови во все стороны (360 градусов), масштабируемый от силы взрыва
		var splatter_scene = blood_splatter_scene
		if is_instance_valid(actor) and "blood_splatter_scene" in actor and actor.blood_splatter_scene:
			splatter_scene = actor.blood_splatter_scene
			
		if splatter_scene:
			var splatter = splatter_scene.instantiate()
			splatter.amount = max(20, int(round(135.0 * mult)))
			splatter.scale = Vector3(2.4, 2.4, 2.4) * max(0.5, mult)
			var pmat = splatter.process_material.duplicate()
			pmat.spread = 180.0
			pmat.initial_velocity_min = 7.0 * max(0.5, mult)
			pmat.initial_velocity_max = 20.0 * max(0.5, mult)
			pmat.scale_min = 0.28 * max(0.6, mult)
			pmat.scale_max = 0.65 * max(0.6, mult)
			splatter.process_material = pmat
			scene_root.add_child(splatter)
			splatter.global_position = explosion_pos
			
		_spawn_explosion_shockwave(scene_root, explosion_pos, explosion_radius)
		
	# 1. АОЕ урон по соседним врагам (запускает цепную реакцию для других раздутых врагов)
	var all_enemies = get_tree().get_nodes_in_group("enemy")
	for enemy in all_enemies:
		if not is_instance_valid(enemy) or enemy == actor:
			continue
		if ("current_state" in enemy and enemy.current_state == enemy.State.DEAD) or ("health" in enemy and enemy.health <= 0):
			continue
			
		var enemy_center = enemy.global_position + Vector3(0, 0.9, 0)
		var dist = explosion_pos.distance_to(enemy_center)
		if dist <= explosion_radius:
			var falloff = 1.0 - (dist / explosion_radius) * 0.35
			var dmg = max(1, int(round(float(explosion_damage) * falloff)))
			var knock_dir = (enemy_center - explosion_pos).normalized()
			if knock_dir.length_squared() < 0.01:
				knock_dir = Vector3.UP
			var knock_vec = knock_dir * (14.0 * mult) + Vector3.UP * (4.5 * mult)
			
			GameTypes.debug_log(&"enemy", "[%s] DETONATION AOE HIT (chain %d -> %d) -> %s for %d dmg!" % [actor_name, depth, depth + 1, enemy.name, dmg])
			enemy.take_damage(dmg, knock_vec, enemy_center, false, false, false, false, depth, "injector")
			
	# 2. Лечение игрока, если он в радиусе взрыва
	var player = get_tree().get_first_node_in_group("player")
	if is_instance_valid(player) and not ("is_dead" in player and player.is_dead):
		var player_center = player.global_position + Vector3(0, 0.9, 0)
		var dist_to_player = explosion_pos.distance_to(player_center)
		var heal_radius = (5.2 + 1.8) * mult
		if dist_to_player <= heal_radius:
			if player.has_method("heal"):
				player.heal(heal_amount, was_killed_melee)

func spawn_explosion_shockwave(scene_root: Node, pos: Vector3, radius: float) -> void:
	_spawn_explosion_shockwave(scene_root, pos, radius)

func _spawn_explosion_shockwave(scene_root: Node, pos: Vector3, radius: float) -> void:
	var sphere = MeshInstance3D.new()
	var smesh = SphereMesh.new()
	smesh.radius = 0.4
	smesh.height = 0.8
	smesh.radial_segments = 16
	smesh.rings = 8
	sphere.mesh = smesh
	
	var mat = StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = Color(1.0, 0.15, 0.1, 0.8)
	sphere.material_override = mat
	
	scene_root.add_child(sphere)
	sphere.global_position = pos
	
	var tween = sphere.create_tween().set_parallel(true)
	tween.tween_property(sphere, "scale", Vector3(radius * 1.6, radius * 1.6, radius * 1.6), 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(mat, "albedo_color:a", 0.0, 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(sphere.queue_free)
