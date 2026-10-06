class_name EnemyGround
extends EnemyBase

@export var move_speed: float = 11.5
@export var acceleration: float = 6.2
@export var rotation_speed: float = 6.0
@export var avoidance_enabled: bool = false
@export var avoidance_deadzone: float = 0.5
@export var wall_slam_threshold: float = 16.0
@export var wall_slam_damage_multiplier: float = 3.5
@export var wall_slam_max_damage: float = 55.0

@export var lunge_min_range: float = 5.0
@export var lunge_max_range: float = 8.5
@export var lunge_speed: float = 25.0
@export var lunge_damage: int = 20
@export var lunge_telegraph_time: float = 0.38
@export var lunge_cooldown: float = 4.5

var gravity = ProjectSettings.get_setting("physics/3d/default_gravity")
var wall_slam_timer: float = 0.0
# Источник толчка, открывшего окно wall slam. Запоминается в момент толчка отдельно от
# HealthComponent, чтобы урон в полёте (тик яда) не перезаписал автора удара о стену.
var wall_slam_source_weapon: String = ""
var wall_slam_source_melee: bool = false
var wall_slam_source_shockwave: bool = false
var pre_move_velocity: Vector3 = Vector3.ZERO
var path_update_timer: float = 0.0
const PATH_UPDATE_INTERVAL: float = 0.35
var debug_diag_timer: float = 0.0
var current_target_vel: Vector3 = Vector3.ZERO
var unreachable_timer: float = 0.0
const UNREACHABLE_TIMEOUT: float = 3.5
var repath_cooldown_timer: float = 0.0
const REPATH_COOLDOWN: float = 2.0

var is_jumping_link: bool = false
var jump_grace_timer: float = 0.0
var jump_timeout: float = 0.0

var lunge_cooldown_timer: float = 0.0
var lunge_timer: float = 0.0
var lunge_dir: Vector3 = Vector3.ZERO
var lunge_phase: int = 0
var lunge_has_hit: bool = false
var lunge_start_pos: Vector3 = Vector3.ZERO
var lunge_target_distance: float = 5.5

@onready var nav_agent: NavigationAgent3D = get_node_or_null("NavigationAgent3D")

func _ready() -> void:
	super._ready()
	
	floor_snap_length = 0.4
	floor_max_angle = deg_to_rad(60.0)
	floor_constant_speed = true
	
	if nav_agent:
		nav_agent.avoidance_enabled = avoidance_enabled
		nav_agent.velocity_computed.connect(_on_velocity_computed)
		nav_agent.link_reached.connect(_on_link_reached)
		
	lunge_cooldown_timer = randf_range(0.5, 2.5)

	# NavigationServer3D sync delay before using navigation agent
	set_physics_process(false)
	call_deferred("_setup_navigation")

func _setup_navigation() -> void:
	await get_tree().physics_frame
	set_physics_process(true)

func _physics_process(delta: float) -> void:
	if current_state == State.DEAD:
		return
		
	# Гравитация
	if not is_on_floor():
		velocity.y -= gravity * 2.0 * delta
		
	# Затухание отбрасывания
	var decay_rate = 2.5 if wall_slam_timer > 0.0 else 5.0
	knockback_velocity = knockback_velocity.lerp(Vector3.ZERO, decay_rate * delta)
	
	if hit_reaction_timer > 0.0:
		hit_reaction_timer -= delta
	if lunge_cooldown_timer > 0.0:
		lunge_cooldown_timer -= delta
		
	if is_jumping_link:
		jump_grace_timer -= delta
		jump_timeout -= delta
		# Приземление: после выхода из grace-таймера при касании пола или по таймауту
		if jump_grace_timer <= 0.0 and ((is_on_floor() and velocity.y <= 0.5) or jump_timeout <= 0.0):
			is_jumping_link = false
			velocity.x = 0.0
			velocity.z = 0.0
			path_update_timer = 0.0
			unreachable_timer = 0.0
			if nav_agent:
				nav_agent.set_velocity(Vector3.ZERO)
			GameTypes.debug_log(&"enemy", "[%s] NavigationLink3D LANDED (floor: %s, vel.y: %.2f, timeout: %s)" % [
				name, is_on_floor(), velocity.y, jump_timeout <= 0.0
			])
	else:
		match current_state:
			State.IDLE:
				_process_idle(delta)
			State.CHASE:
				_process_chase(delta)
			State.ATTACK:
				_process_attack(delta)
			State.LUNGE:
				_process_lunge(delta)
			State.TELEGRAPH:
				_process_telegraph(delta)
			State.FIRING:
				_process_firing(delta)

	pre_move_velocity = velocity
	move_and_slide()
	
	_check_wall_slam(delta)

func set_state(new_state: State) -> void:
	if current_state == new_state or current_state == State.DEAD:
		return
		
	var prev_state = current_state
	if prev_state == State.LUNGE and new_state != State.LUNGE:
		_reset_lunge_visuals()
		lunge_phase = 0
	
	super.set_state(new_state)
	
	match current_state:
		State.IDLE:
			is_jumping_link = false
		State.CHASE:
			path_update_timer = 0.0
		State.ATTACK:
			velocity.x = 0.0
			velocity.z = 0.0
			is_jumping_link = false
		State.LUNGE:
			is_jumping_link = false
		State.DEAD:
			is_jumping_link = false

func _process_idle(delta: float) -> void:
	if repath_cooldown_timer > 0.0:
		repath_cooldown_timer -= delta
		velocity.x = knockback_velocity.x
		velocity.z = knockback_velocity.z
		return
		
	super._process_idle(delta)

func _process_chase(delta: float) -> void:
	if not is_instance_valid(target_player) or ("is_dead" in target_player and target_player.is_dead):
		set_state(State.IDLE)
		return
		
	var dist_to_player = global_position.distance_to(target_player.global_position)
	
	# Обновляем целевую позицию для NavigationAgent3D с фиксированным интервалом
	path_update_timer -= delta
	if path_update_timer <= 0.0:
		path_update_timer = PATH_UPDATE_INTERVAL
		if nav_agent:
			nav_agent.target_position = target_player.global_position
		
	# Проверка достижимости цели (защита от бесконечного застревания в недостижимой точке)
	var is_reachable = nav_agent.is_target_reachable() if nav_agent else true
	# С постоянным агром недостижимость не прерывает погоню: путь NavigationAgent3D к недостижимой
	# цели ведёт к ближайшей достижимой точке, враг идёт туда и ждёт там
	if not is_reachable and not persistent_aggro:
		unreachable_timer += delta
		if unreachable_timer >= UNREACHABLE_TIMEOUT:
			GameTypes.debug_log(&"enemy", "[%s] Target unreachable for %.1fs, returning to IDLE with repath cooldown" % [name, unreachable_timer])
			unreachable_timer = 0.0
			repath_cooldown_timer = REPATH_COOLDOWN
			set_state(State.IDLE)
			return
	else:
		unreachable_timer = max(0.0, unreachable_timer - delta * 2.0)
		
	var next_path_pos = nav_agent.get_next_path_position() if nav_agent else global_position
	var move_dir = next_path_pos - global_position
	move_dir.y = 0.0
	
	# Фолбэк: если nav_agent вернул текущую позицию (нет пути или точка на краю navmesh),
	# используем прямое направление на игрока ТОЛЬКО если путь в целом достижим или в упор (dist <= 6м)
	if move_dir.length_squared() <= 0.01:
		if is_reachable or dist_to_player <= 6.0:
			var direct = target_player.global_position - global_position
			direct.y = 0.0
			if direct.length_squared() > 0.01:
				move_dir = direct
			
	# Диагностический лог в CHASE (раз в 0.5с)
	debug_diag_timer -= delta
	if debug_diag_timer <= 0.0:
		debug_diag_timer = 0.5
		GameTypes.debug_log(&"enemy", "[%s CHASE] dist: %.2f | next_pos: %s | my_pos: %s | move_dir: %s | vel: (%.1f, %.1f) | reachable: %s | unreach_t: %.1f" % [
			name,
			dist_to_player,
			next_path_pos,
			global_position,
			move_dir,
			velocity.x,
			velocity.z,
			is_reachable,
			unreachable_timer
		])
	
	if move_dir.length_squared() > 0.05:
		move_dir = move_dir.normalized()
		current_target_vel = move_dir * (move_speed * slow_factor)
		if nav_agent and nav_agent.avoidance_enabled:
			nav_agent.set_velocity(current_target_vel)
		else:
			_apply_movement(current_target_vel, delta)
	else:
		current_target_vel = Vector3.ZERO
		if nav_agent and nav_agent.avoidance_enabled:
			nav_agent.set_velocity(Vector3.ZERO)
		else:
			_apply_movement(Vector3.ZERO, delta)

func _on_velocity_computed(safe_velocity: Vector3) -> void:
	if is_jumping_link or current_state == State.LUNGE:
		return
	var final_target = safe_velocity
	if current_target_vel.length_squared() > 0.1:
		var diff = safe_velocity - current_target_vel
		diff.y = 0.0
		if diff.length() < avoidance_deadzone:
			final_target = current_target_vel
	_apply_movement(final_target, get_physics_process_delta_time())

func _apply_movement(target_vel: Vector3, delta: float) -> void:
	if wall_slam_timer > 0.0:
		target_vel = Vector3.ZERO
		var flight_drag = 4.0 if is_on_floor() else 2.0
		velocity.x = lerp(velocity.x, 0.0, flight_drag * delta)
		velocity.z = lerp(velocity.z, 0.0, flight_drag * delta)
	else:
		velocity.x = lerp(velocity.x, target_vel.x + knockback_velocity.x, min(1.0, acceleration * delta))
		velocity.z = lerp(velocity.z, target_vel.z + knockback_velocity.z, min(1.0, acceleration * delta))
	
	var horiz_vel = Vector2(velocity.x, velocity.z)
	if horiz_vel.length_squared() > 0.2:
		var target_angle = atan2(-horiz_vel.x, -horiz_vel.y)
		var angle_diff = abs(wrapf(target_angle - rotation.y, -PI, PI))
		if angle_diff > 0.08:
			rotation.y = lerp_angle(rotation.y, target_angle, min(1.0, rotation_speed * delta))

func _has_floor_at_destination(target_pos: Vector3) -> bool:
	var space_state = get_world_3d().direct_space_state
	if not space_state:
		return true
	var ray_start_y = target_pos.y + 0.5
	var ray_end_y = min(global_position.y, target_pos.y) - 3.0
	var ray_start = Vector3(target_pos.x, ray_start_y, target_pos.z)
	var ray_end = Vector3(target_pos.x, ray_end_y, target_pos.z)
	var query = PhysicsRayQueryParameters3D.create(ray_start, ray_end)
	
	var exclude_list: Array[RID] = [get_rid()]
	if is_instance_valid(target_player) and target_player is CollisionObject3D:
		exclude_list.append(target_player.get_rid())
	for e in get_tree().get_nodes_in_group("enemy"):
		if e is CollisionObject3D:
			exclude_list.append(e.get_rid())
	query.exclude = exclude_list
	query.collide_with_areas = false
	query.collide_with_bodies = true
	
	var result = space_state.intersect_ray(query)
	if result.is_empty():
		return false
		
	var normal = result.get("normal", Vector3.UP)
	if normal.y < 0.5:
		return false
		
	return true

func _calculate_lunge_vector_and_distance() -> Dictionary:
	if not is_instance_valid(target_player):
		return {
			"dir": -transform.basis.z.normalized(),
			"dist": 8.0
		}
	var diff = target_player.global_position - global_position
	var horiz = Vector2(diff.x, diff.z)
	var horiz_dist = horiz.length()
	var dy = diff.y
	
	var dir_3d = Vector3.ZERO
	if horiz_dist > 0.01:
		var horiz_norm = horiz.normalized()
		var pitch = 0.0
		if dy > 0.0:
			var raw_pitch = atan2(dy, horiz_dist)
			pitch = min(raw_pitch, deg_to_rad(38.0))
		var cos_p = cos(pitch)
		var sin_p = sin(pitch)
		dir_3d = Vector3(horiz_norm.x * cos_p, sin_p, horiz_norm.y * cos_p).normalized()
	else:
		dir_3d = Vector3.UP if dy > 0.0 else -transform.basis.z.normalized()
		
	var total_dist = diff.length()
	var target_dist = clamp(total_dist + 1.5, 6.5, 7.5)
	
	return {
		"dir": dir_3d,
		"dist": target_dist
	}

func _can_lunge_to_player() -> bool:
	if not is_instance_valid(target_player):
		return false
		
	var height_diff = target_player.global_position.y - global_position.y
	if height_diff > 4.0 or height_diff < -2.5:
		return false
		
	if not _has_line_of_sight_to(target_player):
		return false
			
	var lunge_data = _calculate_lunge_vector_and_distance()
	var test_landing = global_position + lunge_data["dir"] * lunge_data["dist"]
	if not _has_floor_at_destination(test_landing):
		return false
			
	return true

func start_lunge() -> void:
	if not is_instance_valid(target_player):
		return
	set_state(State.LUNGE)
	lunge_phase = 1
	lunge_timer = lunge_telegraph_time
	lunge_has_hit = false
	lunge_cooldown_timer = lunge_cooldown
	
	velocity.x = 0.0
	velocity.z = 0.0
	if nav_agent and nav_agent.avoidance_enabled:
		nav_agent.set_velocity(Vector3.ZERO)
		
	var to_player = target_player.global_position - global_position
	to_player.y = 0.0
	if to_player.length_squared() > 0.01:
		lunge_dir = to_player.normalized()
		rotation.y = atan2(-lunge_dir.x, -lunge_dir.z)
	else:
		lunge_dir = -transform.basis.z.normalized()
		
	if eyes_material:
		eyes_material.emission_enabled = true
		eyes_material.emission = Color(1.0, 0.6, 0.0)
		eyes_material.emission_energy_multiplier = 4.5
		
	if not is_inflated:
		if body_mesh:
			body_mesh.scale = Vector3(1.2, 0.75, 1.2)
		if head_mesh:
			head_mesh.position = Vector3(0.0, 0.38, 0.0)
		if eyes:
			eyes.position = Vector3(0.0, 0.38, -0.28)
		if head_hitbox:
			head_hitbox.position = Vector3(0.0, 0.38, 0.0)
			
	GameTypes.debug_log(&"enemy", "[%s] LUNGE started: Telegraph (%.2fs) towards %s" % [name, lunge_telegraph_time, lunge_dir])

func _process_lunge(delta: float) -> void:
	lunge_timer -= delta
	
	if lunge_phase == 1:
		velocity.x = lerp(velocity.x, knockback_velocity.x, 15.0 * delta)
		velocity.z = lerp(velocity.z, knockback_velocity.z, 15.0 * delta)
		
		if is_instance_valid(target_player):
			var to_player = target_player.global_position - global_position
			to_player.y = 0.0
			if to_player.length_squared() > 0.01:
				var target_angle = atan2(-to_player.x, -to_player.z)
				rotation.y = lerp_angle(rotation.y, target_angle, min(1.0, 10.0 * delta))
				
		if lunge_timer <= 0.0:
			var lunge_data = _calculate_lunge_vector_and_distance()
			lunge_dir = lunge_data["dir"]
			lunge_target_distance = lunge_data["dist"]
				
			rotation.y = atan2(-lunge_dir.x, -lunge_dir.z)
			
			var landing_pos = global_position + lunge_dir * lunge_target_distance
			if not _has_floor_at_destination(landing_pos):
				GameTypes.debug_log(&"enemy", "[%s] LUNGE cancelled: Destination %s has no floor (chasm)! Resuming chase." % [name, landing_pos])
				lunge_cooldown_timer = 2.0
				end_lunge()
				return
				
			lunge_phase = 2
			lunge_has_hit = false
			lunge_start_pos = global_position
			lunge_timer = (lunge_target_distance / lunge_speed) + 0.08
			
			velocity = lunge_dir * lunge_speed
			
			if eyes_material:
				eyes_material.emission_enabled = true
				eyes_material.emission = Color(1.0, 0.15, 0.1)
				eyes_material.emission_energy_multiplier = 4.0
			if not is_inflated:
				if body_mesh:
					body_mesh.scale = Vector3(0.85, 1.0, 1.25)
				if head_mesh:
					head_mesh.position = Vector3(0.0, 0.55, 0.0)
				if eyes:
					eyes.position = Vector3(0.0, 0.55, -0.28)
				if head_hitbox:
					head_hitbox.position = Vector3(0.0, 0.55, 0.0)
					
			AudioManager.play_sound("dash")
			GameTypes.debug_log(&"enemy", "[%s] LUNGE DASH START! dir: %s, target_dist: %.2fm, speed: %.1f" % [
				name, lunge_dir, lunge_target_distance, lunge_speed
			])
			
	elif lunge_phase == 2:
		velocity = lunge_dir * lunge_speed
		
		if not lunge_has_hit:
			for i in range(get_slide_collision_count()):
				var col = get_slide_collision(i)
				var collider = col.get_collider()
				if is_instance_valid(collider) and collider.is_in_group("player"):
					_on_lunge_hit_player(collider)
					break
					
			if not lunge_has_hit and is_instance_valid(target_player):
				var dist = global_position.distance_to(target_player.global_position)
				if dist <= 1.6:
					_on_lunge_hit_player(target_player)
					
		var covered_dist = global_position.distance_to(lunge_start_pos)
		
		if covered_dist >= lunge_target_distance or lunge_timer <= 0.0:
			GameTypes.debug_log(&"enemy", "[%s] LUNGE DASH DISTANCE REACHED: traveled %.2fm / %.2fm (hit_player: %s, on_floor: %s). Handing over to ballistic inertia." % [
				name, covered_dist, lunge_target_distance, lunge_has_hit, is_on_floor()
			])
			_reset_lunge_visuals()
			if not is_on_floor():
				lunge_phase = 3
				lunge_timer = 2.5
			else:
				end_lunge()
				
	elif lunge_phase == 3:
		var air_drag = 4.0
		velocity.x = lerp(velocity.x, 0.0, air_drag * delta)
		velocity.z = lerp(velocity.z, 0.0, air_drag * delta)
		
		if not lunge_has_hit:
			for i in range(get_slide_collision_count()):
				var col = get_slide_collision(i)
				var collider = col.get_collider()
				if is_instance_valid(collider) and collider.is_in_group("player"):
					_on_lunge_hit_player(collider)
					break
			if not lunge_has_hit and is_instance_valid(target_player):
				var dist = global_position.distance_to(target_player.global_position)
				if dist <= 1.6:
					_on_lunge_hit_player(target_player)
					
		if is_on_floor() or lunge_timer <= 0.0:
			GameTypes.debug_log(&"enemy", "[%s] LUNGE LANDED on floor! (is_on_floor: %s, vel: (%.1f, %.1f, %.1f)). Resuming chase." % [
				name, is_on_floor(), velocity.x, velocity.y, velocity.z
			])
			end_lunge()

func _on_lunge_hit_player(player: Node3D) -> void:
	if lunge_has_hit:
		return
	lunge_has_hit = true
	if player.has_method("take_damage"):
		var attack_impulse = lunge_dir * 12.0 + Vector3.UP * 3.0
		player.take_damage(lunge_damage, attack_impulse, global_position)
	GameTypes.debug_log(&"enemy", "[%s] LUNGE HIT player for %d damage! (Continuing full dash)" % [name, lunge_damage])

func end_lunge() -> void:
	_reset_lunge_visuals()
	lunge_phase = 0
	set_state(State.CHASE)

func _reset_lunge_visuals() -> void:
	if eyes_material:
		eyes_material.emission_enabled = true
		eyes_material.emission = Color(1.0, 1.0, 1.0)
		eyes_material.emission_energy_multiplier = 2.0
	if head_mesh and not is_inflated:
		head_mesh.position = Vector3(0.0, 0.55, 0.0)
	if eyes:
		eyes.position = Vector3(0.0, 0.55, -0.28)
	if head_hitbox:
		head_hitbox.position = Vector3(0.0, 0.55, 0.0)
	if not is_inflated:
		if needle_count > 0:
			_update_needle_visuals()
		elif body_mesh:
			body_mesh.scale = Vector3.ONE
			if head_mesh:
				head_mesh.scale = Vector3.ONE

func start_chase(player: Node3D) -> void:
	if repath_cooldown_timer > 0.0:
		return
	unreachable_timer = 0.0
	super.start_chase(player)
	if is_instance_valid(nav_agent):
		nav_agent.target_position = target_player.global_position

func _on_link_reached(details: Dictionary) -> void:
	if is_jumping_link or current_state == State.DEAD or current_state == State.LUNGE:
		return
		
	var exit_pos: Vector3 = details.get("link_exit_position", Vector3.ZERO)
	if exit_pos == Vector3.ZERO:
		var link_node = details.get("owner") as NavigationLink3D
		if link_node:
			var p_start = link_node.global_transform * link_node.start_position
			var p_end = link_node.global_transform * link_node.end_position
			if global_position.distance_squared_to(p_start) < global_position.distance_squared_to(p_end):
				exit_pos = p_end
			else:
				exit_pos = p_start
				
	if exit_pos == Vector3.ZERO:
		return
		
	_start_link_jump(exit_pos)

func _start_link_jump(target_pos: Vector3) -> void:
	var delta_pos = target_pos - global_position
	var delta_h = Vector3(delta_pos.x, 0.0, delta_pos.z)
	var dist_h = delta_h.length()
	var delta_y = delta_pos.y
	
	var eff_gravity: float = gravity * 2.0
	if eff_gravity <= 0.1:
		eff_gravity = 19.6
		
	var h_apex: float
	if delta_y >= 0.0:
		h_apex = max(delta_y + 1.5, 2.5)
	else:
		h_apex = 1.2
		
	var v_y: float = sqrt(2.0 * eff_gravity * h_apex)
	var t_up: float = v_y / eff_gravity
	var fall_height: float = max(0.01, h_apex - delta_y)
	var t_down: float = sqrt(2.0 * fall_height / eff_gravity)
	var t_total: float = t_up + t_down
	
	var horiz_vel: Vector3 = Vector3.ZERO
	if t_total > 0.01:
		horiz_vel = delta_h / t_total
	elif dist_h > 0.01:
		horiz_vel = delta_h.normalized() * move_speed
		
	velocity = Vector3(horiz_vel.x, v_y, horiz_vel.z)
	is_jumping_link = true
	jump_grace_timer = 0.25
	jump_timeout = t_total + 1.2
	unreachable_timer = 0.0
	
	if dist_h > 0.01:
		rotation.y = atan2(-delta_h.x, -delta_h.z)
		
	GameTypes.debug_log(&"enemy", "[%s] NavigationLink3D JUMP -> target %s, dy=%.2f, dh=%.2f, v=(%.1f, %.1f, %.1f), t_flight=%.2fs" % [
		name, target_pos, delta_y, dist_h, velocity.x, velocity.y, velocity.z, t_total
	])

func apply_vacuum_pull(pull_impulse: Vector3) -> void:
	if current_state == State.DEAD:
		return
	wall_slam_timer = max(wall_slam_timer, 0.25)
	super.apply_vacuum_pull(pull_impulse)

func take_damage(amount: int, knockback_vector: Vector3, hit_pos: Vector3, is_melee: bool = false, is_execute: bool = false, is_shockwave: bool = false, is_headshot: bool = false, source_chain_depth: int = -1, weapon_source: String = "") -> void:
	if current_state == State.DEAD:
		return

	if is_shockwave or is_execute or is_melee or knockback_vector.length_squared() > 10.0:
		is_jumping_link = false
	if current_state == State.LUNGE and (is_shockwave or is_execute or is_melee or amount >= 20 or knockback_vector.length_squared() > 10.0):
		GameTypes.debug_log(&"enemy", "[%s] Lunge interrupted by damage/melee!" % [name])
		end_lunge()
	
	if is_shockwave or is_execute:
		wall_slam_timer = 0.8 if is_shockwave else 0.4
		velocity.x = knockback_vector.x
		velocity.z = knockback_vector.z
		wall_slam_source_weapon = weapon_source
		wall_slam_source_melee = is_melee or is_execute
		wall_slam_source_shockwave = is_shockwave
	elif is_melee:
		wall_slam_timer = 0.25
		velocity.x = knockback_vector.x
		velocity.z = knockback_vector.z
		wall_slam_source_weapon = weapon_source
		wall_slam_source_melee = true
		wall_slam_source_shockwave = false

	super.take_damage(amount, knockback_vector, hit_pos, is_melee, is_execute, is_shockwave, is_headshot, source_chain_depth, weapon_source)

func _check_wall_slam(delta: float) -> void:
	if wall_slam_timer <= 0.0 or current_state == State.DEAD:
		return
		
	wall_slam_timer -= delta
	
	for i in range(get_slide_collision_count()):
		var col = get_slide_collision(i)
		var n = col.get_normal()
		var impact_speed = -pre_move_velocity.dot(n)
		if impact_speed >= wall_slam_threshold:
			trigger_wall_slam(impact_speed, col)
			break

func trigger_wall_slam(impact_speed: float, col: KinematicCollision3D) -> void:
	wall_slam_timer = 0.0
	var raw_wall_damage = impact_speed * wall_slam_damage_multiplier
	var saturated_damage = wall_slam_max_damage * (1.0 - exp(-raw_wall_damage / wall_slam_max_damage))
	var base_wall_damage = mini(int(round(saturated_damage)), int(wall_slam_max_damage))
	
	# Глубина цепи wall slam хранится в HealthComponent (записывается при уроне ударной волной)
	var slam_depth: int = health_component.slam_chain_depth if is_instance_valid(health_component) else 0
	var my_mult: float = 1.0
	if slam_depth == 0:
		my_mult = 1.0
	elif slam_depth == 1:
		my_mult = 0.60
	elif slam_depth == 2:
		my_mult = 0.35
	else:
		my_mult = 0.20

	var wall_damage = int(round(base_wall_damage * my_mult))
	GameTypes.debug_log(&"enemy", "[%s] Wall slam! Speed: %.1f, chain_depth: %d, damage: %d (base: %d)" % [
		name, impact_speed, slam_depth, wall_damage, base_wall_damage
	])
	
	var other = col.get_collider()
	if is_instance_valid(other) and other != self:
		var target: Node = null
		if other.is_in_group("enemy_head") or other.name == "HeadHitbox":
			target = other.get_meta("enemy") if other.has_meta("enemy") else other.get_parent()
		else:
			target = GameTypes.resolve_damageable(other)
		# Игрок в цепочку не входит: впечатанный в него враг не наносит урона и цепочку не продолжает
		if target and target != self and not (target is Player) and target.has_method("take_damage"):
			var next_depth = slam_depth + 1
			var next_mult: float = 1.0
			if next_depth == 1:
				next_mult = 0.60
			elif next_depth == 2:
				next_mult = 0.35
			else:
				next_mult = 0.20
			var collateral_damage = int(round(base_wall_damage * next_mult))
			GameTypes.debug_log(&"enemy", "[%s] Collateral hit %s! Depth: %d, damage: %d" % [name, target.name, next_depth, collateral_damage])
			# Источник цепочки (кто толкнул первого) передаётся соседу вместе с глубиной
			target.take_damage(collateral_damage, -col.get_normal() * 12.0 + Vector3.UP * 4.0, col.get_position(), wall_slam_source_melee, false, true, false, next_depth, wall_slam_source_weapon)
	
	if blood_splatter_scene:
		var splatter = blood_splatter_scene.instantiate()
		splatter.amount = 60
		var pmat = splatter.process_material.duplicate()
		pmat.spread = 75.0
		pmat.initial_velocity_min = 4.0
		pmat.initial_velocity_max = 10.0
		splatter.process_material = pmat
		splatter.scale = Vector3(1.5, 1.5, 1.5)
		var scene_root = get_tree().current_scene if get_tree().current_scene else get_parent()
		if scene_root:
			scene_root.add_child(splatter)
			splatter.global_position = col.get_position()
			if col.get_normal() != Vector3.ZERO:
				splatter.look_at(col.get_position() + col.get_normal(), Vector3.UP)
				
	knockback_velocity = Vector3.ZERO
	velocity = velocity.slide(col.get_normal()) * 0.2
	
	# Удар о стену — последний удар; его автор — тот, кто толкнул (запомнен в момент толчка)
	if is_instance_valid(health_component):
		health_component.record_hit_source(wall_damage, wall_slam_source_melee, false, wall_slam_source_shockwave, -1, wall_slam_source_weapon)
	health -= wall_damage
	_update_health_bar()
	_spawn_damage_number(wall_damage, col.get_position(), false)
	if health <= 0:
		var player = get_tree().get_first_node_in_group("player")
		if is_instance_valid(player) and "skills" in player and player.skills:
			player.skills.add_dash_charge()
		set_state(State.DEAD)
