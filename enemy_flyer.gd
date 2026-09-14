extends CharacterBody3D

enum State {
	IDLE,
	CHASE,
	TELEGRAPH,
	FIRING,
	FLEE,
	DEAD
}

@export var max_health: int = 80
@export var hover_height: float = 4.0
@export var move_speed: float = 8.5
@export var acceleration: float = 5.0
@export var preferred_dist_min: float = 12.0
@export var preferred_dist_max: float = 18.0
@export var detection_range: float = 35.0

# Параметры лазерной атаки
@export var telegraph_duration: float = 0.6 # 0.5-0.7с
@export var laser_duration: float = 1.8 # 1.5-2.0с
@export var laser_tracking_speed: float = 1.7 # рад/с (управляемый поворот луча)
@export var attack_cooldown_min: float = 4.0
@export var attack_cooldown_max: float = 5.0
@export var tick_damage: int = 4 # 4-5 HP за тик
@export var tick_interval: float = 0.25 # 0.2-0.3с

var current_state: State = State.IDLE
var health: int = 80
var target_player: Node3D = null

var attack_cooldown_timer: float = 0.0
var telegraph_timer: float = 0.0
var laser_timer: float = 0.0
var laser_tick_timer: float = 0.0
var current_beam_dir: Vector3 = Vector3.FORWARD
var bob_time: float = 0.0
var knockback_velocity: Vector3 = Vector3.ZERO
var slow_factor: float = 1.0
var slow_sources: int = 0
var fear_check_timer: float = 0.0
var flee_timer: float = 0.0

# Синергии оружия
var needle_count: int = 0
var needle_timers: Array[float] = []
var poison_stacks: Array[Dictionary] = []
const MAX_POISON_STACKS: int = 5
var is_inflated: bool = false
var explosion_chain_depth: int = 0
var last_damage_weapon: String = ""
var was_killed_by_melee: bool = false
var was_killed_by_shockwave: bool = false
var last_headshot_bonus_frame: int = -1

var blood_pool_scene = preload("res://blood_pool.tscn")
var blood_splatter_scene = preload("res://blood_splatter.tscn")

# Узлы сцены
@onready var collision_shape: CollisionShape3D = $CollisionShape3D
@onready var head_hitbox: Area3D = get_node_or_null("HeadHitbox")
@onready var eye_emitter: MeshInstance3D = get_node_or_null("Visuals/EyeEmitter")
@onready var eye_light: OmniLight3D = get_node_or_null("Visuals/EyeLight")
@onready var visuals: Node3D = get_node_or_null("Visuals")
@onready var floor_ray: RayCast3D = get_node_or_null("FloorRay")
@onready var forward_ray: RayCast3D = get_node_or_null("ForwardRay")
@onready var left_ray: RayCast3D = get_node_or_null("LeftRay")
@onready var right_ray: RayCast3D = get_node_or_null("RightRay")
@onready var laser_root: Node3D = get_node_or_null("LaserRoot")
@onready var laser_outer: MeshInstance3D = get_node_or_null("LaserRoot/LaserOuter")
@onready var laser_core: MeshInstance3D = get_node_or_null("LaserRoot/LaserCore")

var eye_material: StandardMaterial3D = null
var laser_outer_mat: StandardMaterial3D = null
var laser_core_mat: StandardMaterial3D = null

# HP Bar
var hp_viewport: SubViewport
var hp_bar: ProgressBar
var hp_sprite: Sprite3D
var hp_label: Label3D

const EYE_COLOR_IDLE = Color(0.15, 0.9, 1.0)
const EYE_COLOR_TELEGRAPH = Color(1.0, 0.85, 0.2)
const EYE_COLOR_FIRING = Color(0.1, 1.0, 0.95)

func _ready():
	health = max_health
	add_to_group("enemy")
	add_to_group("enemy_flyer")
	
	if head_hitbox:
		head_hitbox.set_meta("enemy", self)
		head_hitbox.add_to_group("enemy_head")
		
	if eye_emitter:
		var mat = eye_emitter.get_surface_override_material(0)
		if mat:
			eye_material = mat.duplicate()
			eye_emitter.set_surface_override_material(0, eye_material)
			
	if laser_outer:
		var m = laser_outer.get_surface_override_material(0)
		if m:
			laser_outer_mat = m.duplicate()
			laser_outer.set_surface_override_material(0, laser_outer_mat)
			
	if laser_core:
		var m2 = laser_core.get_surface_override_material(0)
		if m2:
			laser_core_mat = m2.duplicate()
			laser_core.set_surface_override_material(0, laser_core_mat)
			
	if laser_root:
		laser_root.visible = false
		
	_setup_health_bar()
	attack_cooldown_timer = randf_range(1.5, 3.0)
	fear_check_timer = randf_range(1.0, 2.5)

func _setup_health_bar():
	hp_viewport = SubViewport.new()
	hp_viewport.size = Vector2i(130, 20)
	hp_viewport.transparent_bg = true
	hp_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS

	hp_bar = ProgressBar.new()
	hp_bar.size = Vector2(130, 20)
	hp_bar.max_value = max_health
	hp_bar.value = health
	hp_bar.show_percentage = false

	var bg_box = StyleBoxFlat.new()
	bg_box.bg_color = Color(0.08, 0.08, 0.08, 0.85)
	bg_box.border_color = Color(0.35, 0.35, 0.35, 0.9)
	bg_box.set_border_width_all(2)
	bg_box.set_corner_radius_all(3)

	var fg_box = StyleBoxFlat.new()
	fg_box.bg_color = Color(0.15, 0.8, 0.95, 1.0) # Циановый цвет полоски для летающего врага
	fg_box.set_corner_radius_all(2)

	hp_bar.add_theme_stylebox_override("background", bg_box)
	hp_bar.add_theme_stylebox_override("fill", fg_box)

	hp_viewport.add_child(hp_bar)
	add_child(hp_viewport)

	hp_sprite = Sprite3D.new()
	hp_sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	hp_sprite.no_depth_test = true
	hp_sprite.position = Vector3(0, 0.95, 0)
	hp_sprite.texture = hp_viewport.get_texture()
	hp_sprite.pixel_size = 0.007
	add_child(hp_sprite)

	hp_label = Label3D.new()
	hp_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	hp_label.no_depth_test = true
	hp_label.position = Vector3(0, 1.12, 0)
	hp_label.font_size = 18
	hp_label.outline_size = 4
	hp_label.outline_modulate = Color.BLACK
	hp_label.modulate = Color(0.9, 0.98, 1.0)
	hp_label.text = "%d / %d" % [health, max_health]
	add_child(hp_label)

func _update_health_bar():
	if hp_bar:
		hp_bar.value = max(0, health)
	if hp_label:
		hp_label.text = "%d / %d" % [max(0, health), max_health]

func _physics_process(delta: float):
	if current_state == State.DEAD:
		return
		
	bob_time += delta
	knockback_velocity = knockback_velocity.lerp(Vector3.ZERO, 4.0 * delta)
	
	if attack_cooldown_timer > 0.0:
		attack_cooldown_timer -= delta
		
	# Обработка яда DoT
	if not poison_stacks.is_empty():
		var write_idx = 0
		for i in range(poison_stacks.size()):
			var stack = poison_stacks[i]
			stack["duration"] -= delta
			stack["tick_timer"] -= delta
			if stack["tick_timer"] <= 0.0:
				stack["tick_timer"] = float(stack["interval"])
				_apply_poison_tick(int(stack["damage"]))
				if current_state == State.DEAD:
					break
			if stack["duration"] > 0.0 and current_state != State.DEAD:
				poison_stacks[write_idx] = stack
				write_idx += 1
		if current_state != State.DEAD:
			poison_stacks.resize(write_idx)
			
	# Обработка застрявших игл
	if not needle_timers.is_empty():
		var write_idx = 0
		for i in range(needle_timers.size()):
			var t = needle_timers[i] - delta
			if t > 0.0:
				needle_timers[write_idx] = t
				write_idx += 1
		needle_timers.resize(write_idx)
		needle_count = write_idx
		
	_process_fear_check(delta)
	
	match current_state:
		State.IDLE:
			_process_idle(delta)
		State.CHASE:
			_process_flight_movement(delta)
			_process_combat_triggers(delta)
		State.TELEGRAPH:
			_process_telegraph(delta)
		State.FIRING:
			_process_laser_firing(delta)
		State.FLEE:
			_process_flee(delta)
			
	move_and_slide()

func _process_idle(delta: float):
	_maintain_hover_height(delta, Vector3.ZERO)
	
	# Поиск игрока
	var player = get_tree().get_first_node_in_group("player")
	if is_instance_valid(player) and not ("is_dead" in player and player.is_dead):
		var dist = global_position.distance_to(player.global_position)
		if dist <= detection_range and _has_line_of_sight_to(player):
			target_player = player
			current_state = State.CHASE

func _process_flight_movement(delta: float):
	if not is_instance_valid(target_player) or ("is_dead" in target_player and target_player.is_dead):
		current_state = State.IDLE
		return
		
	var player_pos = target_player.global_position
	var diff = player_pos - global_position
	var dist_to_player = diff.length()
	
	# Горизонтальное направление к игроку
	var horiz_diff = Vector3(diff.x, 0, diff.z)
	var target_horiz_vel = Vector3.ZERO
	
	if horiz_diff.length_squared() > 0.01:
		var dir_to_player = horiz_diff.normalized()
		
		if dist_to_player > preferred_dist_max:
			# Подлетаем ближе
			target_horiz_vel = dir_to_player * (move_speed * slow_factor)
		elif dist_to_player < preferred_dist_min:
			# Отлетаем назад для сохранения дистанции 12-18м
			target_horiz_vel = -dir_to_player * (move_speed * 0.75 * slow_factor)
		else:
			# В зоне 12-18м плавно тормозим
			target_horiz_vel = Vector3.ZERO
			
		# Простой обход препятствий с помощью лучей
		target_horiz_vel = _apply_obstacle_avoidance(target_horiz_vel)
		
		# Поворот к игроку
		var target_angle = atan2(-dir_to_player.x, -dir_to_player.z)
		rotation.y = lerp_angle(rotation.y, target_angle, min(1.0, 4.5 * delta))
		
	_maintain_hover_height(delta, target_horiz_vel)

func _apply_obstacle_avoidance(desired_vel: Vector3) -> Vector3:
	if desired_vel.length_squared() <= 0.1:
		return desired_vel
		
	var forward_dir = desired_vel.normalized()
	if forward_ray:
		forward_ray.target_position = to_local(global_position + forward_dir * 4.0)
		forward_ray.force_raycast_update()
		if forward_ray.is_colliding():
			var col_n = forward_ray.get_collision_normal()
			var left_clear = true
			var right_clear = true
			if left_ray:
				left_ray.force_raycast_update()
				left_clear = not left_ray.is_colliding()
			if right_ray:
				right_ray.force_raycast_update()
				right_clear = not right_ray.is_colliding()
				
			var lateral_dir = transform.basis.x
			if left_clear and not right_clear:
				lateral_dir = -transform.basis.x
			elif right_clear and not left_clear:
				lateral_dir = transform.basis.x
			elif col_n.dot(transform.basis.x) < 0:
				lateral_dir = -transform.basis.x
			else:
				lateral_dir = transform.basis.x
				
			return (desired_vel * 0.4 + lateral_dir * move_speed * 0.8 + col_n * 2.0).normalized() * move_speed
	return desired_vel

func _maintain_hover_height(delta: float, target_horiz_vel: Vector3):
	var current_altitude = 0.0
	var has_floor = false
	
	if floor_ray:
		floor_ray.force_raycast_update()
		if floor_ray.is_colliding():
			has_floor = true
			current_altitude = global_position.y - floor_ray.get_collision_point().y
			
	var target_vy = 0.0
	var bobbing = sin(bob_time * 2.5) * 0.25
	
	if has_floor:
		var target_y = hover_height + bobbing
		var error_y = target_y - current_altitude
		target_vy = clamp(error_y * 3.5, -6.0, 6.0)
	elif is_instance_valid(target_player):
		var desired_y = target_player.global_position.y + 3.0 + bobbing
		target_vy = clamp((desired_y - global_position.y) * 2.5, -5.0, 5.0)
		
	var final_target = Vector3(target_horiz_vel.x, target_vy, target_horiz_vel.z)
	velocity.x = lerp(velocity.x, final_target.x + knockback_velocity.x, min(1.0, acceleration * delta))
	velocity.z = lerp(velocity.z, final_target.z + knockback_velocity.z, min(1.0, acceleration * delta))
	velocity.y = lerp(velocity.y, final_target.y + knockback_velocity.y, min(1.0, 6.0 * delta))

func _process_combat_triggers(delta: float):
	if attack_cooldown_timer > 0.0 or not is_instance_valid(target_player):
		return
		
	var dist = global_position.distance_to(target_player.global_position)
	if dist <= 22.0 and _has_line_of_sight_to(target_player):
		_start_telegraph()

func _start_telegraph():
	current_state = State.TELEGRAPH
	telegraph_timer = telegraph_duration
	
	var eye_pos = _get_eye_position()
	var target_aim = (target_player.global_position + Vector3(0, 0.2, 0) - eye_pos).normalized()
	current_beam_dir = target_aim
	
	if eye_material:
		eye_material.emission = EYE_COLOR_TELEGRAPH
		eye_material.emission_energy_multiplier = 5.5
	if eye_light:
		eye_light.light_color = EYE_COLOR_TELEGRAPH
		eye_light.light_energy = 2.8
		
	# Показываем тонкий пред-луч прицеливания (гайдлайн)
	_update_beam_visual(true, 0.015, 0.25)
	AudioManager.play_sound("needle_shot")

func _process_telegraph(delta: float):
	telegraph_timer -= delta
	
	# Во время телеграфа зависаем на месте и ведем прицел за игроком
	_maintain_hover_height(delta, Vector3.ZERO)
	
	if is_instance_valid(target_player):
		var eye_pos = _get_eye_position()
		var target_aim = (target_player.global_position + Vector3(0, 0.2, 0) - eye_pos).normalized()
		current_beam_dir = current_beam_dir.slerp(target_aim, min(1.0, 5.0 * delta)).normalized()
		
		var dir_h = Vector3(current_beam_dir.x, 0, current_beam_dir.z).normalized()
		if dir_h.length_squared() > 0.01:
			rotation.y = lerp_angle(rotation.y, atan2(-dir_h.x, -dir_h.z), min(1.0, 6.0 * delta))
			
		_update_beam_visual(true, 0.015, 0.35)
		
	if telegraph_timer <= 0.0:
		_start_firing()

func _start_firing():
	current_state = State.FIRING
	laser_timer = laser_duration
	laser_tick_timer = 0.0
	
	if eye_material:
		eye_material.emission = EYE_COLOR_FIRING
		eye_material.emission_energy_multiplier = 7.0
	if eye_light:
		eye_light.light_color = EYE_COLOR_FIRING
		eye_light.light_energy = 3.5
		
	_update_beam_visual(true, 0.06, 1.0)
	AudioManager.play_sound("rail_shot")

func _process_laser_firing(delta: float):
	laser_timer -= delta
	laser_tick_timer -= delta
	
	# Во время стрельбы лазером медленно дрейфуем на высоте
	_maintain_hover_height(delta, Vector3.ZERO)
	
	if is_instance_valid(target_player) and not ("is_dead" in target_player and target_player.is_dead):
		var eye_pos = _get_eye_position()
		var target_aim = (target_player.global_position + Vector3(0, 0.2, 0) - eye_pos).normalized()
		
		# Ограниченная скорость доворачивания луча (laser_tracking_speed рад/с)
		var angle_diff = current_beam_dir.angle_to(target_aim)
		if angle_diff > 0.001:
			var max_step = laser_tracking_speed * delta
			var t = min(1.0, max_step / angle_diff)
			current_beam_dir = current_beam_dir.slerp(target_aim, t).normalized()
			
		# Поворачиваем тело дрона в сторону луча
		var dir_h = Vector3(current_beam_dir.x, 0, current_beam_dir.z).normalized()
		if dir_h.length_squared() > 0.01:
			rotation.y = lerp_angle(rotation.y, atan2(-dir_h.x, -dir_h.z), min(1.0, 3.5 * delta))
			
		# Просчёт луча лазера через raycast в мир
		_cast_laser_and_damage(eye_pos, delta)
	else:
		_update_beam_visual(true, 0.06, 1.0)
		
	if laser_timer <= 0.0:
		_end_firing()

func _cast_laser_and_damage(eye_pos: Vector3, _delta: float):
	var max_range = 45.0
	var beam_end = eye_pos + current_beam_dir * max_range
	
	var space_state = get_world_3d().direct_space_state
	if space_state:
		var query = PhysicsRayQueryParameters3D.create(eye_pos, beam_end)
		var exclude: Array[RID] = [get_rid()]
		for enemy in get_tree().get_nodes_in_group("enemy"):
			if enemy is CollisionObject3D:
				exclude.append(enemy.get_rid())
		query.exclude = exclude
		query.collide_with_bodies = true
		query.collide_with_areas = false
		
		var hit = space_state.intersect_ray(query)
		if not hit.is_empty():
			beam_end = hit.position
			var collider = hit.collider
			if is_instance_valid(collider):
				var target: Node = collider
				if not target.is_in_group("player") and target.get_parent() and target.get_parent().is_in_group("player"):
					target = target.get_parent()
					
				if target.is_in_group("player") or target.has_method("take_damage"):
					if laser_tick_timer <= 0.0:
						laser_tick_timer = tick_interval
						var push = current_beam_dir * 2.5 + Vector3.UP * 0.8
						target.take_damage(tick_damage, push, hit.position)
						
	# Отрисовка геометрии луча
	_render_beam_between(eye_pos, beam_end, 0.06, 1.0)

func _update_beam_visual(is_active: bool, thickness: float, alpha: float):
	if not is_active:
		if laser_root:
			laser_root.visible = false
		return
	var eye_pos = _get_eye_position()
	var end_pos = eye_pos + current_beam_dir * 30.0
	_render_beam_between(eye_pos, end_pos, thickness, alpha)

func _render_beam_between(start_pos: Vector3, end_pos: Vector3, thickness: float, alpha: float):
	if not laser_root or not laser_outer:
		return
		
	var dist = start_pos.distance_to(end_pos)
	if dist < 0.1:
		laser_root.visible = false
		return
		
	laser_root.visible = true
	var mid = (start_pos + end_pos) * 0.5
	laser_root.global_position = mid
	
	var dir = (end_pos - start_pos).normalized()
	if abs(dir.y) > 0.98:
		laser_root.look_at(laser_root.global_position + dir, Vector3.RIGHT)
	else:
		laser_root.look_at(laser_root.global_position + dir, Vector3.UP)
		
	# Поворачиваем цилиндр вдоль оси луча (CylinderMesh ориентирован по Y)
	laser_root.rotate_object_local(Vector3.RIGHT, deg_to_rad(90.0))
	laser_root.scale = Vector3(thickness, dist, thickness)
	
	if laser_outer_mat:
		laser_outer_mat.albedo_color.a = alpha * 0.8
	if laser_core_mat:
		laser_core_mat.albedo_color.a = alpha

func _end_firing():
	if laser_root:
		laser_root.visible = false
	if eye_material:
		eye_material.emission = EYE_COLOR_IDLE
		eye_material.emission_energy_multiplier = 3.5
	if eye_light:
		eye_light.light_color = EYE_COLOR_IDLE
		eye_light.light_energy = 1.8
		
	attack_cooldown_timer = randf_range(attack_cooldown_min, attack_cooldown_max)
	current_state = State.CHASE

func _get_eye_position() -> Vector3:
	if eye_emitter:
		return eye_emitter.global_position
	return global_position + Vector3(0, 0.28, -0.25)

func _has_line_of_sight_to(target: Node3D) -> bool:
	if not is_instance_valid(target):
		return false
	var space_state = get_world_3d().direct_space_state
	if not space_state:
		return true
	var from_p = _get_eye_position()
	var to_p = target.global_position + Vector3(0, 0.5, 0)
	var query = PhysicsRayQueryParameters3D.create(from_p, to_p)
	query.exclude = [get_rid()]
	var res = space_state.intersect_ray(query)
	if res.is_empty():
		return true
	var col = res.get("collider")
	return is_instance_valid(col) and (col == target or col.is_in_group("player"))

func _process_fear_check(delta: float):
	if current_state == State.DEAD or current_state == State.FIRING:
		return
	fear_check_timer -= delta
	if fear_check_timer > 0.0:
		return
	fear_check_timer = 3.0
	
	var player = target_player if is_instance_valid(target_player) else get_tree().get_first_node_in_group("player")
	if is_instance_valid(player) and not ("is_dead" in player and player.is_dead):
		var player_bpm: float = 0.0
		if "skills" in player and is_instance_valid(player.skills) and "bpm" in player.skills:
			player_bpm = player.skills.bpm
		if player_bpm >= 180.0 and global_position.distance_to(player.global_position) <= detection_range and _has_line_of_sight_to(player):
			if randf() <= 0.40:
				flee_timer = randf_range(3.5, 4.5)
				_end_firing()
				current_state = State.FLEE

func _process_flee(delta: float):
	flee_timer -= delta
	if flee_timer <= 0.0 or not is_instance_valid(target_player):
		current_state = State.CHASE
		return
	var away = (global_position - target_player.global_position)
	away.y = 0.0
	if away.length_squared() > 0.01:
		away = away.normalized()
		var target_vel = away * (move_speed * 1.1)
		_maintain_hover_height(delta, target_vel)
		rotation.y = lerp_angle(rotation.y, atan2(away.x, away.z), min(1.0, 5.0 * delta))

func take_damage(amount: int, knockback_vector: Vector3, hit_pos: Vector3, is_melee: bool = false, is_execute: bool = false, is_shockwave: bool = false, is_headshot: bool = false, source_chain_depth: int = -1, weapon_source: String = ""):
	if current_state == State.DEAD:
		return
		
	explosion_chain_depth = (source_chain_depth + 1) if source_chain_depth >= 0 else 0
	was_killed_by_melee = is_melee or is_shockwave or is_execute
	was_killed_by_shockwave = is_shockwave
	
	if is_melee or is_shockwave or is_execute:
		last_damage_weapon = "melee"
	elif weapon_source != "":
		last_damage_weapon = weapon_source
		
	health -= amount
	_update_health_bar()
	_spawn_damage_number(amount, hit_pos, is_headshot)
	AudioManager.play_sound("enemy_hit")
	
	if is_headshot:
		var cur_frame = Engine.get_process_frames()
		if cur_frame != last_headshot_bonus_frame:
			last_headshot_bonus_frame = cur_frame
			var p = get_tree().get_first_node_in_group("player")
			if is_instance_valid(p) and "skills" in p and is_instance_valid(p.skills):
				p.skills.add_bpm(1.5)
				
	knockback_velocity = knockback_vector * 0.8
	
	if current_state == State.TELEGRAPH or current_state == State.FIRING:
		if amount >= 25 or is_melee or is_shockwave or knockback_vector.length() >= 12.0:
			_end_firing()
			
	if blood_splatter_scene:
		var splatter = blood_splatter_scene.instantiate()
		var pmat = splatter.process_material.duplicate()
		splatter.amount = 45 if is_headshot else 25
		splatter.process_material = pmat
		var scene_root = get_tree().current_scene if get_tree().current_scene else get_parent()
		if scene_root:
			scene_root.add_child(splatter)
			splatter.global_position = hit_pos
			
	if current_state == State.IDLE and is_instance_valid(get_tree().get_first_node_in_group("player")):
		target_player = get_tree().get_first_node_in_group("player")
		current_state = State.CHASE
		
	if health <= 0:
		die()

func _spawn_damage_number(dmg_amount: int, spawn_pos: Vector3, is_crit: bool = false, is_poison: bool = false):
	if dmg_amount <= 0:
		return
	var label = Label3D.new()
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.outline_size = 6
	label.outline_modulate = Color(0, 0, 0, 1)
	
	if is_poison:
		label.text = "-%d" % dmg_amount
		label.modulate = Color(0.25, 0.95, 0.35, 1.0)
		label.font_size = 20
	elif is_crit:
		label.text = "-%d CRIT!" % dmg_amount
		label.modulate = Color(1.0, 0.2, 0.1, 1.0)
		label.font_size = 32
	else:
		label.text = "-%d" % dmg_amount
		label.modulate = Color(0.3, 0.9, 1.0, 1.0) # Циановый оттенок урона по летуну
		label.font_size = 24
		
	var scene_root = get_tree().current_scene if get_tree().current_scene else get_parent()
	if not scene_root:
		return
	scene_root.add_child(label)
	
	var base_p = spawn_pos if spawn_pos.length_squared() > 0.01 else global_position + Vector3(0, 0.6, 0)
	var offset = Vector3(randf_range(-0.15, 0.15), randf_range(0.05, 0.2), randf_range(-0.15, 0.15))
	var start_p = base_p + offset
	label.global_position = start_p
	
	var target_p = start_p + Vector3(0.0, 0.75, 0.0)
	var tween = create_tween().set_parallel(true)
	tween.tween_property(label, "global_position", target_p, 0.65).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "modulate:a", 0.0, 0.65).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(label.queue_free)

func add_needle(is_blood_needle: bool = false):
	needle_count += 1
	needle_timers.append(6.0)

func apply_poison_dot(duration: float = 3.0, damage_per_tick: int = 3, interval: float = 0.5, chain_depth: int = 0):
	if current_state == State.DEAD:
		return
	last_damage_weapon = "injector"
	if poison_stacks.size() < MAX_POISON_STACKS:
		poison_stacks.append({
			"duration": duration,
			"tick_timer": interval,
			"damage": damage_per_tick,
			"interval": interval,
			"chain_depth": chain_depth
		})

func _apply_poison_tick(damage: int):
	if current_state == State.DEAD:
		return
	health -= damage
	_update_health_bar()
	_spawn_damage_number(damage, global_position + Vector3(0, 0.4, 0), false, true)
	if health <= 0:
		die()

func inflate():
	if is_inflated or current_state == State.DEAD:
		return
	is_inflated = true
	if visuals:
		var tw = create_tween().set_parallel(true)
		tw.tween_property(visuals, "scale", Vector3(1.25, 1.25, 1.25), 0.25)
	if current_state == State.IDLE and is_instance_valid(get_tree().get_first_node_in_group("player")):
		target_player = get_tree().get_first_node_in_group("player")
		current_state = State.CHASE

func add_slow(factor: float = 0.5):
	slow_sources += 1
	slow_factor = factor

func remove_slow():
	slow_sources = max(0, slow_sources - 1)
	if slow_sources == 0:
		slow_factor = 1.0

func apply_vacuum_pull(pull_impulse: Vector3):
	if current_state == State.DEAD:
		return
	knockback_velocity += pull_impulse * 0.8
	if current_state == State.TELEGRAPH or current_state == State.FIRING:
		_end_firing()

func die():
	current_state = State.DEAD
	set_physics_process(false)
	_end_firing()
	AudioManager.play_sound("enemy_death")
	
	# Начисление BPM игроку
	var player = get_tree().get_first_node_in_group("player")
	if is_instance_valid(player) and "skills" in player and is_instance_valid(player.skills):
		var weapon_used = last_damage_weapon
		if was_killed_by_shockwave or was_killed_by_melee:
			weapon_used = "melee"
		elif weapon_used == "":
			weapon_used = "unknown"
			
		if player.skills.has_method("record_kill_bpm"):
			player.skills.record_kill_bpm(weapon_used, was_killed_by_shockwave)
		else:
			var mult: float = player.skills.combat_momentum if "combat_momentum" in player.skills else 1.0
			player.skills.add_bpm(6.0 * mult)
			
	if hp_sprite:
		hp_sprite.visible = false
	if hp_label:
		hp_label.visible = false
	if collision_shape:
		collision_shape.set_deferred("disabled", true)
		
	# Лужа крови на полу под летуном
	if blood_pool_scene:
		var space_state = get_world_3d().direct_space_state
		if space_state:
			var q = PhysicsRayQueryParameters3D.create(global_position, global_position + Vector3.DOWN * 40.0)
			var res = space_state.intersect_ray(q)
			var pool = blood_pool_scene.instantiate()
			var scene_root = get_tree().current_scene if get_tree().current_scene else get_parent()
			if scene_root:
				scene_root.add_child(pool)
				pool.global_position = (res.position + Vector3(0, 0.01, 0)) if res else global_position
				
	queue_free()
