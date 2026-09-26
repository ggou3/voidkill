class_name Enemy
extends EnemyGround

@export var attack_damage: int = 15
@export var attack_range: float = 2.0
@export var attack_cooldown: float = 1.0

var attack_timer: float = 0.0

func _ready() -> void:
	super._ready()
	
	if eyes:
		var mat = eyes.get_surface_override_material(0)
		if mat:
			eyes_material = mat.duplicate()
			eyes.set_surface_override_material(0, eyes_material)

func _physics_process(delta: float) -> void:
	if attack_timer > 0.0:
		attack_timer -= delta
		
	super._physics_process(delta)

func set_state(new_state: State) -> void:
	if current_state == new_state or current_state == State.DEAD:
		return
		
	super.set_state(new_state)
	
	match current_state:
		State.ATTACK:
			attack_timer = max(attack_timer, reaction_delay)
			hit_reaction_timer = max(hit_reaction_timer, reaction_delay)
		State.FLEE:
			attack_timer = 1.0
		State.DEAD:
			attack_timer = 999999.0

func _process_chase(delta: float) -> void:
	if not is_instance_valid(target_player) or ("is_dead" in target_player and target_player.is_dead):
		set_state(State.IDLE)
		return
		
	var dist_to_player = global_position.distance_to(target_player.global_position)
	
	if dist_to_player <= attack_range:
		set_state(State.ATTACK)
		return
		
	if lunge_cooldown_timer <= 0.0 and dist_to_player >= lunge_min_range and dist_to_player <= lunge_max_range:
		if is_on_floor() and not is_jumping_link and wall_slam_timer <= 0.0 and _can_lunge_to_player():
			start_lunge()
			return
			
	super._process_chase(delta)

func _process_attack(delta: float) -> void:
	if not is_instance_valid(target_player) or ("is_dead" in target_player and target_player.is_dead):
		set_state(State.IDLE)
		return
		
	var dist_to_player = global_position.distance_to(target_player.global_position)
	
	if dist_to_player > attack_range * 1.3:
		set_state(State.CHASE)
		return
		
	velocity.x = lerp(velocity.x, knockback_velocity.x, 10.0 * delta)
	velocity.z = lerp(velocity.z, knockback_velocity.z, 10.0 * delta)

	var to_player = target_player.global_position - global_position
	to_player.y = 0.0
	if to_player.length_squared() > 0.01:
		var target_angle = atan2(-to_player.x, -to_player.z)
		var angle_diff = abs(wrapf(target_angle - rotation.y, -PI, PI))
		if angle_diff > 0.08:
			rotation.y = lerp_angle(rotation.y, target_angle, min(1.0, rotation_speed * delta))
	
	if attack_timer <= 0.0 and hit_reaction_timer <= 0.0:
		if is_inside_tree() and current_state == State.ATTACK:
			perform_attack()
		attack_timer = attack_cooldown

func perform_attack() -> void:
	if not is_inside_tree() or current_state == State.DEAD:
		return
	if not is_instance_valid(target_player):
		return
		
	if eyes_material:
		eyes_material.emission = Color(1.0, 0.1, 0.1)
		var tween = create_tween()
		tween.tween_property(eyes_material, "emission", Color(1.0, 1.0, 1.0), 0.25)
		
	if target_player.has_method("take_damage"):
		var attack_dir = (target_player.global_position - global_position).normalized()
		var attack_impulse = attack_dir * 8.0 + Vector3.UP * 2.0
		target_player.take_damage(attack_damage, attack_impulse, target_player.global_position)

func take_damage(amount: int, knockback_vector: Vector3, hit_pos: Vector3, is_melee: bool = false, is_execute: bool = false, is_shockwave: bool = false, is_headshot: bool = false, source_chain_depth: int = -1, weapon_source: String = "") -> void:
	if current_state == State.DEAD:
		return
	attack_timer = max(attack_timer, reaction_delay)
	super.take_damage(amount, knockback_vector, hit_pos, is_melee, is_execute, is_shockwave, is_headshot, source_chain_depth, weapon_source)

func die(death_info: Dictionary = {}) -> void:
	attack_timer = 999999.0
	super.die(death_info)
