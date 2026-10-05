class_name EnemyFlyer
extends EnemyBase

@export var hover_height: float = 4.0
@export var move_speed: float = 8.5
@export var acceleration: float = 5.0
@export var preferred_dist_min: float = 12.0
@export var preferred_dist_max: float = 18.0

# Параметры лазерной атаки
@export var telegraph_duration: float = 0.6
@export var laser_duration: float = 1.8
@export var laser_tracking_speed: float = 1.05 # рад/с
@export var max_sector_angle_deg: float = 60.0 # полуугол сектора
@export var boundary_color: Color = Color(0.2, 0.85, 1.0, 0.28)
@export var attack_cooldown_min: float = 4.0
@export var attack_cooldown_max: float = 5.0
@export var tick_damage: int = 4
@export var tick_interval: float = 0.25

var attack_cooldown_timer: float = 0.0
var telegraph_timer: float = 0.0
var laser_timer: float = 0.0
var laser_tick_timer: float = 0.0
var current_beam_dir: Vector3 = Vector3.FORWARD
var initial_laser_dir: Vector3 = Vector3.FORWARD
var boundary_left_dir: Vector3 = Vector3.FORWARD
var boundary_right_dir: Vector3 = Vector3.FORWARD

var boundary_left_root: Node3D = null
var boundary_right_root: Node3D = null
var boundary_left_marker: MeshInstance3D = null
var boundary_right_marker: MeshInstance3D = null
var boundary_mat: StandardMaterial3D = null
var marker_mat: StandardMaterial3D = null
var bob_time: float = 0.0

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

const EYE_COLOR_IDLE = Color(0.15, 0.9, 1.0)
const EYE_COLOR_TELEGRAPH = Color(1.0, 0.85, 0.2)
const EYE_COLOR_FIRING = Color(0.1, 1.0, 0.95)

func _ready() -> void:
	max_health = 80
	health = 80
	super._ready()
	add_to_group("enemy_flyer")
	
	body_mesh = get_node_or_null("Visuals/CoreBody") as MeshInstance3D
	head_mesh = get_node_or_null("Visuals/HeadCowl")
	eyes = get_node_or_null("Visuals/EyeEmitter") as MeshInstance3D
	
	if eye_emitter:
		var mat = eye_emitter.get_surface_override_material(0)
		if mat:
			eye_material = mat.duplicate()
			eye_emitter.set_surface_override_material(0, eye_material)
			eyes_material = eye_material
			
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
		
	_setup_boundary_visuals()
	attack_cooldown_timer = randf_range(1.5, 3.0)

func _setup_health_bar() -> void:
	_ensure_health_bar().setup(
		health,
		max_health,
		0.95,
		Color(0.15, 0.8, 0.95, 1.0),
		Color(0.9, 0.98, 1.0),
		health_component
	)

func _setup_boundary_visuals() -> void:
	boundary_mat = StandardMaterial3D.new()
	boundary_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	boundary_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	boundary_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	boundary_mat.albedo_color = boundary_color
	
	marker_mat = boundary_mat.duplicate()
	marker_mat.albedo_color = Color(boundary_color.r, boundary_color.g, boundary_color.b, min(1.0, boundary_color.a * 2.2))
	
	var cyl = CylinderMesh.new()
	var sph = SphereMesh.new()
	sph.radius = 0.12
	sph.height = 0.24
	
	boundary_left_root = _create_boundary_mesh(cyl, boundary_mat)
	boundary_right_root = _create_boundary_mesh(cyl, boundary_mat)
	boundary_left_marker = _create_marker_mesh(sph, marker_mat)
	boundary_right_marker = _create_marker_mesh(sph, marker_mat)

func _create_boundary_mesh(mesh: Mesh, mat: Material) -> Node3D:
	var root = Node3D.new()
	root.visible = false
	var mi = MeshInstance3D.new()
	mi.mesh = mesh
	mi.set_surface_override_material(0, mat)
	root.add_child(mi)
	add_child(root)
	return root

func _create_marker_mesh(mesh: Mesh, mat: Material) -> MeshInstance3D:
	var mi = MeshInstance3D.new()
	mi.mesh = mesh
	mi.set_surface_override_material(0, mat)
	mi.visible = false
	add_child(mi)
	return mi

func _physics_process(delta: float) -> void:
	if current_state == State.DEAD:
		return
		
	bob_time += delta
	knockback_velocity = knockback_velocity.lerp(Vector3.ZERO, 4.0 * delta)
	if attack_cooldown_timer > 0.0:
		attack_cooldown_timer -= delta
	if hit_reaction_timer > 0.0:
		hit_reaction_timer -= delta

	match current_state:
		State.IDLE:
			_process_idle(delta)
		State.CHASE:
			_process_flight_movement(delta)
		State.TELEGRAPH:
			_process_telegraph(delta)
		State.FIRING:
			_process_firing(delta)

	move_and_slide()

func set_state(new_state: State) -> void:
	if current_state == new_state or current_state == State.DEAD:
		return
	var old_state = current_state
	super.set_state(new_state)
	if (old_state == State.TELEGRAPH or old_state == State.FIRING) and new_state != State.TELEGRAPH and new_state != State.FIRING:
		_end_firing()

func _process_idle(delta: float) -> void:
	_maintain_hover_height(delta, Vector3.ZERO)
	var player = get_tree().get_first_node_in_group("player")
	if is_instance_valid(player) and not ("is_dead" in player and player.is_dead):
		if global_position.distance_to(player.global_position) <= detection_range and _has_line_of_sight_to(player):
			start_chase(player)

func _process_flight_movement(delta: float) -> void:
	if not is_instance_valid(target_player) or ("is_dead" in target_player and target_player.is_dead):
		set_state(State.IDLE)
		return
		
	var diff = target_player.global_position - global_position
	var dist = diff.length()
	var horiz_diff = Vector3(diff.x, 0, diff.z)
	var target_horiz_vel = Vector3.ZERO
	
	if horiz_diff.length_squared() > 0.01:
		var dir = horiz_diff.normalized()
		if dist > preferred_dist_max:
			target_horiz_vel = dir * (move_speed * slow_factor)
		elif dist < preferred_dist_min:
			target_horiz_vel = -dir * (move_speed * 0.75 * slow_factor)
			
		target_horiz_vel = _apply_obstacle_avoidance(target_horiz_vel)
		rotation.y = lerp_angle(rotation.y, atan2(-dir.x, -dir.z), min(1.0, 4.5 * delta))
		
	_maintain_hover_height(delta, target_horiz_vel)
	
	if attack_cooldown_timer <= 0.0 and dist <= 22.0 and _has_line_of_sight_to(target_player):
		_start_telegraph()

func _apply_obstacle_avoidance(desired_vel: Vector3) -> Vector3:
	if desired_vel.length_squared() <= 0.1 or not forward_ray:
		return desired_vel
	forward_ray.target_position = to_local(global_position + desired_vel.normalized() * 4.0)
	forward_ray.force_raycast_update()
	if not forward_ray.is_colliding():
		return desired_vel
		
	var col_n = forward_ray.get_collision_normal()
	var left_clear = true
	var right_clear = true
	if left_ray:
		left_ray.force_raycast_update()
		left_clear = not left_ray.is_colliding()
	if right_ray:
		right_ray.force_raycast_update()
		right_clear = not right_ray.is_colliding()
		
	var lat = transform.basis.x if (right_clear and not left_clear) or (col_n.dot(transform.basis.x) >= 0 and not (left_clear and not right_clear)) else -transform.basis.x
	return (desired_vel * 0.4 + lat * move_speed * 0.8 + col_n * 2.0).normalized() * move_speed

func _maintain_hover_height(delta: float, target_horiz_vel: Vector3) -> void:
	var target_vy = 0.0
	var bobbing = sin(bob_time * 2.5) * 0.25
	if floor_ray:
		floor_ray.force_raycast_update()
		if floor_ray.is_colliding():
			var alt = global_position.y - floor_ray.get_collision_point().y
			target_vy = clamp((hover_height + bobbing - alt) * 3.5, -6.0, 6.0)
	elif is_instance_valid(target_player):
		target_vy = clamp((target_player.global_position.y + 3.0 + bobbing - global_position.y) * 2.5, -5.0, 5.0)
		
	velocity.x = lerp(velocity.x, target_horiz_vel.x + knockback_velocity.x, min(1.0, acceleration * delta))
	velocity.z = lerp(velocity.z, target_horiz_vel.z + knockback_velocity.z, min(1.0, acceleration * delta))
	velocity.y = lerp(velocity.y, target_vy + knockback_velocity.y, min(1.0, 6.0 * delta))

func _start_telegraph() -> void:
	set_state(State.TELEGRAPH)
	telegraph_timer = telegraph_duration
	current_beam_dir = (target_player.global_position + Vector3(0, 0.2, 0) - _get_eye_position()).normalized()
	
	if eye_material:
		eye_material.emission = EYE_COLOR_TELEGRAPH
		eye_material.emission_energy_multiplier = 5.5
	if eye_light:
		eye_light.light_color = EYE_COLOR_TELEGRAPH
		eye_light.light_energy = 2.8
		
	_update_beam_visual(true, 0.015, 0.25)
	AudioManager.play_sound("needle_shot")

func _process_telegraph(delta: float) -> void:
	telegraph_timer -= delta
	_maintain_hover_height(delta, Vector3.ZERO)
	
	if is_instance_valid(target_player):
		var target_aim = (target_player.global_position + Vector3(0, 0.2, 0) - _get_eye_position()).normalized()
		current_beam_dir = current_beam_dir.slerp(target_aim, min(1.0, 5.0 * delta)).normalized()
		var dir_h = Vector3(current_beam_dir.x, 0, current_beam_dir.z).normalized()
		if dir_h.length_squared() > 0.01:
			rotation.y = lerp_angle(rotation.y, atan2(-dir_h.x, -dir_h.z), min(1.0, 6.0 * delta))
		_update_beam_visual(true, 0.015, 0.35)
		
	if telegraph_timer <= 0.0:
		_start_firing()

func _start_firing() -> void:
	set_state(State.FIRING)
	laser_timer = laser_duration
	laser_tick_timer = 0.0
	initial_laser_dir = current_beam_dir.normalized()
	
	var max_angle = deg_to_rad(max_sector_angle_deg)
	var up_ref = Vector3.FORWARD if abs(initial_laser_dir.dot(Vector3.UP)) > 0.92 else Vector3.UP
	var sector_up = initial_laser_dir.cross(up_ref).normalized().cross(initial_laser_dir).normalized()
	boundary_left_dir = initial_laser_dir.rotated(sector_up, max_angle).normalized()
	boundary_right_dir = initial_laser_dir.rotated(sector_up, -max_angle).normalized()
	
	if eye_material:
		eye_material.emission = EYE_COLOR_FIRING
		eye_material.emission_energy_multiplier = 7.0
	if eye_light:
		eye_light.light_color = EYE_COLOR_FIRING
		eye_light.light_energy = 3.5
		
	_update_beam_visual(true, 0.06, 1.0)
	_update_boundary_visuals()
	AudioManager.play_sound("rail_shot")

func _process_firing(delta: float) -> void:
	laser_timer -= delta
	laser_tick_timer -= delta
	_maintain_hover_height(delta, Vector3.ZERO)
	
	var eye_pos = _get_eye_position()
	if is_instance_valid(target_player) and not ("is_dead" in target_player and target_player.is_dead):
		var target_aim = (target_player.global_position + Vector3(0, 0.2, 0) - eye_pos).normalized()
		var max_angle = deg_to_rad(max_sector_angle_deg)
		var angle_from_initial = initial_laser_dir.angle_to(target_aim)
		if angle_from_initial > max_angle and angle_from_initial > 0.001:
			target_aim = initial_laser_dir.slerp(target_aim, max_angle / angle_from_initial).normalized()
			
		var angle_diff = current_beam_dir.angle_to(target_aim)
		if angle_diff > 0.001:
			current_beam_dir = current_beam_dir.slerp(target_aim, min(1.0, (laser_tracking_speed * delta) / angle_diff)).normalized()
			
		var cur_angle = initial_laser_dir.angle_to(current_beam_dir)
		if cur_angle > max_angle and cur_angle > 0.001:
			current_beam_dir = initial_laser_dir.slerp(current_beam_dir, max_angle / cur_angle).normalized()
			
		var dir_h = Vector3(current_beam_dir.x, 0, current_beam_dir.z).normalized()
		if dir_h.length_squared() > 0.01:
			rotation.y = lerp_angle(rotation.y, atan2(-dir_h.x, -dir_h.z), min(1.0, 3.5 * delta))
			
		_cast_laser_and_damage(eye_pos)
	else:
		_update_beam_visual(true, 0.06, 1.0)
		
	_update_boundary_visuals()
	if laser_timer <= 0.0:
		set_state(State.CHASE)

func _cast_laser_and_damage(eye_pos: Vector3) -> void:
	var beam_end = eye_pos + current_beam_dir * 45.0
	var space_state = get_world_3d().direct_space_state
	if space_state:
		var q = PhysicsRayQueryParameters3D.create(eye_pos, beam_end)
		var exclude: Array[RID] = [get_rid()]
		for enemy in get_tree().get_nodes_in_group("enemy"):
			if enemy is CollisionObject3D:
				exclude.append(enemy.get_rid())
		q.exclude = exclude
		var hit = space_state.intersect_ray(q)
		if not hit.is_empty():
			beam_end = hit.position
			var target = GameTypes.resolve_damageable(hit.collider)
			if target and (target.is_in_group("player") or target.has_method("take_damage")):
				if laser_tick_timer <= 0.0:
					laser_tick_timer = tick_interval
					target.take_damage(tick_damage, current_beam_dir * 2.5 + Vector3.UP * 0.8, hit.position)
					
	_render_beam_between(eye_pos, beam_end, 0.06, 1.0)

func _update_beam_visual(is_active: bool, thickness: float, alpha: float) -> void:
	if not is_active:
		if laser_root:
			laser_root.visible = false
		return
	var eye_pos = _get_eye_position()
	_render_beam_between(eye_pos, eye_pos + current_beam_dir * 30.0, thickness, alpha)

func _orient_cylinder_between(node: Node3D, start_pos: Vector3, end_pos: Vector3, thickness: float) -> void:
	if not node:
		return
	var dist = start_pos.distance_to(end_pos)
	if dist < 0.1:
		node.visible = false
		return
	node.visible = true
	node.global_position = (start_pos + end_pos) * 0.5
	var dir = (end_pos - start_pos).normalized()
	if abs(dir.y) > 0.98:
		node.look_at(node.global_position + dir, Vector3.RIGHT)
	else:
		node.look_at(node.global_position + dir, Vector3.UP)
	node.rotate_object_local(Vector3.RIGHT, deg_to_rad(90.0))
	node.scale = Vector3(thickness, dist, thickness)

func _render_beam_between(start_pos: Vector3, end_pos: Vector3, thickness: float, alpha: float) -> void:
	if not laser_root or not laser_outer:
		return
	_orient_cylinder_between(laser_root, start_pos, end_pos, thickness)
	if laser_outer_mat:
		laser_outer_mat.albedo_color.a = alpha * 0.8
	if laser_core_mat:
		laser_core_mat.albedo_color.a = alpha

func _update_boundary_visuals() -> void:
	if not boundary_left_root or not boundary_right_root:
		return
	var eye_pos = _get_eye_position()
	var space_state = get_world_3d().direct_space_state
	var exclude: Array[RID] = [get_rid()]
	for enemy in get_tree().get_nodes_in_group("enemy"):
		if enemy is CollisionObject3D:
			exclude.append(enemy.get_rid())
	var p = get_tree().get_first_node_in_group("player")
	if is_instance_valid(p) and p is CollisionObject3D:
		exclude.append(p.get_rid())
		
	_cast_boundary_line(eye_pos, boundary_left_dir, boundary_left_root, boundary_left_marker, space_state, exclude)
	_cast_boundary_line(eye_pos, boundary_right_dir, boundary_right_root, boundary_right_marker, space_state, exclude)

func _cast_boundary_line(eye_pos: Vector3, dir: Vector3, root: Node3D, marker: MeshInstance3D, space_state: PhysicsDirectSpaceState3D, exclude: Array[RID]) -> void:
	var end_pos = eye_pos + dir * 45.0
	if space_state:
		var q = PhysicsRayQueryParameters3D.create(eye_pos, end_pos)
		q.exclude = exclude
		var hit = space_state.intersect_ray(q)
		if not hit.is_empty():
			end_pos = hit.position
			if marker:
				marker.visible = true
				marker.global_position = hit.position + hit.normal * 0.08
		elif marker:
			marker.visible = false
	elif marker:
		marker.visible = false
	_orient_cylinder_between(root, eye_pos, end_pos, 0.012)

func _end_firing() -> void:
	if laser_root:
		laser_root.visible = false
	for node in [boundary_left_root, boundary_right_root, boundary_left_marker, boundary_right_marker]:
		if node:
			node.visible = false
	if eye_material:
		eye_material.emission = EYE_COLOR_IDLE
		eye_material.emission_energy_multiplier = 3.5
	if eye_light:
		eye_light.light_color = EYE_COLOR_IDLE
		eye_light.light_energy = 1.8
		
	attack_cooldown_timer = randf_range(attack_cooldown_min, attack_cooldown_max)

func _get_eye_position() -> Vector3:
	return eye_emitter.global_position if eye_emitter else global_position + Vector3(0, 0.28, -0.25)

func take_damage(amount: int, knockback_vector: Vector3, hit_pos: Vector3, is_melee: bool = false, is_execute: bool = false, is_shockwave: bool = false, is_headshot: bool = false, source_chain_depth: int = -1, weapon_source: String = "") -> void:
	if current_state == State.DEAD:
		return
	if current_state == State.TELEGRAPH or current_state == State.FIRING:
		if amount >= 25 or is_melee or is_shockwave or knockback_vector.length() >= 12.0:
			set_state(State.CHASE)
	super.take_damage(amount, knockback_vector, hit_pos, is_melee, is_execute, is_shockwave, is_headshot, source_chain_depth, weapon_source)
	knockback_velocity = knockback_vector * 0.8

func apply_vacuum_pull(pull_impulse: Vector3) -> void:
	if current_state == State.DEAD:
		return
	if current_state == State.TELEGRAPH or current_state == State.FIRING:
		set_state(State.CHASE)
	super.apply_vacuum_pull(pull_impulse)

func die(death_info: Dictionary = {}) -> void:
	_end_firing()
	super.die(death_info)

func _update_needle_visuals() -> void:
	if current_state == State.DEAD or is_inflated:
		return
	if needle_count > 0:
		var n_factor = clampf(float(needle_count) / 30.0, 0.0, 1.0)
		if visuals:
			visuals.scale = Vector3.ONE * (1.0 + n_factor * 0.18)
	else:
		if visuals:
			visuals.scale = Vector3.ONE

func _update_inflation_visuals() -> void:
	if current_state == State.DEAD:
		return
	if inflation_tween:
		inflation_tween.kill()
	inflation_tween = create_tween().set_parallel(true)
	if visuals:
		inflation_tween.tween_property(visuals, "scale", Vector3(1.26, 1.26, 1.26), 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if eye_material:
		eye_material.emission = Color(1.0, 0.1, 0.1)
		eye_material.emission_energy_multiplier = 4.5
