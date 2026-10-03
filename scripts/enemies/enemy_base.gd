class_name EnemyBase
extends CharacterBody3D

enum State {
	IDLE,
	CHASE,
	ATTACK,
	LUNGE,
	TELEGRAPH,
	FIRING,
	FLEE,
	DEAD
}

@export var max_health: int = 100:
	set(value):
		max_health = value
		if is_instance_valid(health_component):
			health_component.max_health = value

@export var reaction_delay: float = 0.4
@export var detection_range: float = 25.0

var current_state: State = State.IDLE
var health: int:
	get:
		if is_instance_valid(health_component):
			return health_component.health
		return _health
	set(value):
		_health = value
		if is_instance_valid(health_component):
			health_component.health = value
var _health: int = 100

var target_player: Node3D = null
var hit_reaction_timer: float = 0.0
var knockback_velocity: Vector3 = Vector3.ZERO
var last_hit_knockback: Vector3 = Vector3.ZERO

var fear_check_timer: float = 0.0
var flee_timer: float = 0.0

var last_headshot_bonus_frame: int = -1
var explosion_chain_depth: int = 0
var slam_chain_depth: int = 0

var blood_pool_scene = preload("res://blood_pool.tscn")
var blood_splatter_scene = preload("res://blood_splatter.tscn")

@onready var health_component: HealthComponent = _get_or_create_health_component()
@onready var status_effect_component: StatusEffectComponent = _get_or_create_status_effect_component()
@onready var health_bar: EnemyHealthBar = _get_or_create_health_bar()

@onready var collision_shape: CollisionShape3D = get_node_or_null("CollisionShape3D")
@onready var detection_area: Area3D = get_node_or_null("DetectionArea")
@onready var head_hitbox: Area3D = get_node_or_null("HeadHitbox")
@onready var head_mesh: Node3D = get_node_or_null("HeadMesh")
@onready var body_mesh: MeshInstance3D = get_node_or_null("MeshInstance3D")
@onready var eyes: MeshInstance3D = get_node_or_null("Eyes")

var eyes_material: StandardMaterial3D = null
var body_override_mat: StandardMaterial3D = null

func _ensure_health_component() -> HealthComponent:
	if not is_instance_valid(health_component):
		health_component = _get_or_create_health_component()
	return health_component

func _get_or_create_health_component() -> HealthComponent:
	var comp = get_node_or_null("HealthComponent") as HealthComponent
	if not comp:
		comp = HealthComponent.new()
		comp.name = "HealthComponent"
		add_child(comp)
	return comp

func _ensure_status_effect_component() -> StatusEffectComponent:
	if not is_instance_valid(status_effect_component):
		status_effect_component = _get_or_create_status_effect_component()
	return status_effect_component

func _get_or_create_status_effect_component() -> StatusEffectComponent:
	var comp = get_node_or_null("StatusEffectComponent") as StatusEffectComponent
	if not comp:
		comp = StatusEffectComponent.new()
		comp.name = "StatusEffectComponent"
		add_child(comp)
	return comp

func _ensure_health_bar() -> EnemyHealthBar:
	if not is_instance_valid(health_bar):
		health_bar = _get_or_create_health_bar()
	return health_bar

func _get_or_create_health_bar() -> EnemyHealthBar:
	var bar = get_node_or_null("EnemyHealthBar") as EnemyHealthBar
	if not bar:
		bar = EnemyHealthBar.new()
		bar.name = "EnemyHealthBar"
		add_child(bar)
	return bar

var slow_factor: float:
	get:
		return _ensure_status_effect_component().slow_factor
	set(val):
		_ensure_status_effect_component().slow_factor = val

var slow_sources: int:
	get:
		return _ensure_status_effect_component().slow_sources
	set(val):
		_ensure_status_effect_component().slow_sources = val

const MAX_POISON_STACKS: int = StatusEffectComponent.MAX_POISON_STACKS

var poison_stacks: Array[Dictionary]:
	get:
		return _ensure_status_effect_component().poison_stacks
	set(val):
		_ensure_status_effect_component().poison_stacks = val

var needle_count: int:
	get:
		return _ensure_status_effect_component().needle_count
	set(val):
		_ensure_status_effect_component().needle_count = val

var needle_timers: Array[float]:
	get:
		return _ensure_status_effect_component().needle_timers
	set(val):
		_ensure_status_effect_component().needle_timers = val

var is_inflated: bool:
	get:
		return _ensure_status_effect_component().is_inflated
	set(val):
		_ensure_status_effect_component().is_inflated = val

var inflation_tween: Tween:
	get:
		return _ensure_status_effect_component().inflation_tween
	set(val):
		_ensure_status_effect_component().inflation_tween = val

var inflation_pulse_tween: Tween:
	get:
		return _ensure_status_effect_component().inflation_pulse_tween
	set(val):
		_ensure_status_effect_component().inflation_pulse_tween = val

var hp_viewport: SubViewport:
	get:
		return _ensure_health_bar().hp_viewport
	set(val):
		_ensure_health_bar().hp_viewport = val

var hp_bar: ProgressBar:
	get:
		return _ensure_health_bar().hp_bar
	set(val):
		_ensure_health_bar().hp_bar = val

var hp_sprite: Sprite3D:
	get:
		return _ensure_health_bar().hp_sprite
	set(val):
		_ensure_health_bar().hp_sprite = val

var hp_label: Label3D:
	get:
		return _ensure_health_bar().hp_label
	set(val):
		_ensure_health_bar().hp_label = val

func _ready() -> void:
	_ensure_health_component()
	health_component.max_health = max_health
	health_component.health = max_health
	if not health_component.damaged.is_connected(_on_health_damaged):
		health_component.damaged.connect(_on_health_damaged)
	if not health_component.health_changed.is_connected(_on_health_changed):
		health_component.health_changed.connect(_on_health_changed)
	if not health_component.died.is_connected(_on_health_died):
		health_component.died.connect(_on_health_died)
	
	_ensure_status_effect_component()
	status_effect_component.actor = self
	status_effect_component.health_component = health_component
	if not status_effect_component.effect_applied.is_connected(_on_status_effect_applied):
		status_effect_component.effect_applied.connect(_on_status_effect_applied)
	if not status_effect_component.effect_expired.is_connected(_on_status_effect_expired):
		status_effect_component.effect_expired.connect(_on_status_effect_expired)
	if not status_effect_component.visuals_need_update.is_connected(_on_status_visuals_need_update):
		status_effect_component.visuals_need_update.connect(_on_status_visuals_need_update)
	if not status_effect_component.requests_damage.is_connected(_on_status_requests_damage):
		status_effect_component.requests_damage.connect(_on_status_requests_damage)
	
	if head_hitbox:
		head_hitbox.set_meta("enemy", self)
		
	if eyes:
		var mat = eyes.get_surface_override_material(0)
		if mat:
			eyes_material = mat.duplicate()
			eyes.set_surface_override_material(0, eyes_material)
		
	if detection_area:
		detection_area.body_entered.connect(_on_detection_area_body_entered)
		
	_setup_health_bar()
	fear_check_timer = randf_range(0.5, 2.5)

func _setup_health_bar() -> void:
	_ensure_health_bar().setup(
		health,
		max_health,
		1.15,
		Color(0.95, 0.15, 0.15, 1.0),
		Color(1.0, 0.9, 0.9),
		health_component
	)

func _update_health_bar() -> void:
	if is_instance_valid(health_bar):
		health_bar.update_health(health, max_health)

func _physics_process(delta: float) -> void:
	if current_state == State.DEAD:
		return
		
	if hit_reaction_timer > 0.0:
		hit_reaction_timer -= delta
		
	_process_fear_chain_check(delta)
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
		State.FLEE:
			_process_flee(delta)

func set_state(new_state: State) -> void:
	if current_state == new_state or current_state == State.DEAD:
		return
		
	GameTypes.debug_log(&"enemy", "[%s] State: %s -> %s" % [name, State.keys()[current_state], State.keys()[new_state]])
	current_state = new_state
	
	match current_state:
		State.IDLE:
			target_player = null
		State.DEAD:
			die()

func _process_idle(_delta: float) -> void:
	velocity.x = knockback_velocity.x
	velocity.z = knockback_velocity.z
	
	var player = get_tree().get_first_node_in_group("player")
	if is_instance_valid(player):
		if "is_dead" in player and player.is_dead:
			return
		var dist = global_position.distance_to(player.global_position)
		if dist <= detection_range:
			start_chase(player)

func _process_chase(_delta: float) -> void:
	pass

func _process_attack(_delta: float) -> void:
	pass

func _process_lunge(_delta: float) -> void:
	pass

func _process_telegraph(_delta: float) -> void:
	pass

func _process_firing(_delta: float) -> void:
	pass

func _process_flee(delta: float) -> void:
	if not is_instance_valid(target_player) or ("is_dead" in target_player and target_player.is_dead):
		set_state(State.IDLE)
		return
		
	var player_bpm: float = 0.0
	var is_overdrive: bool = false
	if "bpm_system" in target_player and is_instance_valid(target_player.bpm_system):
		if "bpm" in target_player.bpm_system:
			player_bpm = target_player.bpm_system.bpm
		if target_player.bpm_system.has_method("get_bpm_tier"):
			is_overdrive = (target_player.bpm_system.get_bpm_tier() == GameTypes.BPMTier.OVERDRIVE)
		else:
			is_overdrive = (player_bpm >= 180.0)
	if not is_overdrive:
		GameTypes.debug_log(&"enemy", "[%s] FLEE interrupted: Player left OVERDRIVE (BPM: %.1f). Resuming normal behavior." % [name, player_bpm])
		_resume_from_flee()
		return
		
	flee_timer -= delta
	if flee_timer <= 0.0:
		GameTypes.debug_log(&"enemy", "[%s] FLEE expired. Resuming normal behavior." % name)
		_resume_from_flee()
		return

func _resume_from_flee() -> void:
	flee_timer = 0.0
	if is_instance_valid(target_player) and not ("is_dead" in target_player and target_player.is_dead):
		var dist = global_position.distance_to(target_player.global_position)
		if dist <= detection_range:
			start_chase(target_player)
			return
	set_state(State.IDLE)

func start_chase(player: Node3D) -> void:
	target_player = player
	set_state(State.CHASE)

func _on_detection_area_body_entered(body: Node3D) -> void:
	if body.is_in_group("player") and current_state == State.IDLE:
		if "is_dead" in body and body.is_dead:
			return
		start_chase(body)

func _has_line_of_sight_to(target: Node3D) -> bool:
	if not is_instance_valid(target):
		return false
	var space_state = get_world_3d().direct_space_state
	if not space_state:
		return true
	var from_pos = global_position + Vector3(0.0, 0.6, 0.0)
	var to_pos = target.global_position + Vector3(0.0, 0.6, 0.0)
	var query = PhysicsRayQueryParameters3D.create(from_pos, to_pos)
	query.exclude = [get_rid()]
	var result = space_state.intersect_ray(query)
	if result.is_empty():
		return true
	var col_obj = result.get("collider")
	return is_instance_valid(col_obj) and (col_obj == target or col_obj.is_in_group("player"))

func _process_fear_chain_check(delta: float) -> void:
	if current_state != State.IDLE and current_state != State.CHASE:
		return
		
	fear_check_timer -= delta
	if fear_check_timer > 0.0:
		return
	fear_check_timer = 3.0
	
	var player = target_player
	if not is_instance_valid(player):
		player = get_tree().get_first_node_in_group("player")
	if not is_instance_valid(player) or ("is_dead" in player and player.is_dead):
		return
		
	var player_bpm: float = 0.0
	var is_overdrive: bool = false
	if "bpm_system" in player and is_instance_valid(player.bpm_system):
		if "bpm" in player.bpm_system:
			player_bpm = player.bpm_system.bpm
		if player.bpm_system.has_method("get_bpm_tier"):
			is_overdrive = (player.bpm_system.get_bpm_tier() == GameTypes.BPMTier.OVERDRIVE)
		else:
			is_overdrive = (player_bpm >= 180.0)
	if not is_overdrive:
		return
		
	var dist = global_position.distance_to(player.global_position)
	if dist > detection_range:
		return
	if not _has_line_of_sight_to(player):
		return
		
	if randf() <= 0.40:
		target_player = player
		flee_timer = randf_range(4.0, 5.0)
		GameTypes.debug_log(&"enemy", "[%s] FEAR CHAIN: Overdrive panic triggered (BPM: %.1f)! FLEE for %.2fs" % [name, player_bpm, flee_timer])
		set_state(State.FLEE)

func apply_vacuum_pull(pull_impulse: Vector3) -> void:
	if current_state == State.DEAD:
		return
	knockback_velocity += Vector3(pull_impulse.x, 0.0, pull_impulse.z)
	velocity.x += pull_impulse.x
	velocity.z += pull_impulse.z
	if pull_impulse.y > 0.0:
		velocity.y = max(velocity.y, pull_impulse.y)
	elif pull_impulse.y < 0.0:
		velocity.y += pull_impulse.y
		
	hit_reaction_timer = max(hit_reaction_timer, 0.2)

func take_damage(amount: int, knockback_vector: Vector3, hit_pos: Vector3, is_melee: bool = false, is_execute: bool = false, is_shockwave: bool = false, is_headshot: bool = false, source_chain_depth: int = -1, weapon_source: String = "") -> void:
	if current_state == State.DEAD:
		return

	last_hit_knockback = knockback_vector
	hit_reaction_timer = reaction_delay
	knockback_velocity = Vector3(knockback_vector.x, 0, knockback_vector.z)
	
	if knockback_vector.y != 0.0:
		velocity.y = knockback_vector.y
		
	if current_state == State.IDLE:
		var player = get_tree().get_first_node_in_group("player")
		if is_instance_valid(player):
			start_chase(player)

	_ensure_health_component().take_damage(amount, knockback_vector, hit_pos, is_melee, is_execute, is_shockwave, is_headshot, source_chain_depth, weapon_source)

func _spawn_hit_blood_splatter(amount: int, hit_pos: Vector3, is_crit: bool, knock_vec: Vector3) -> void:
	if not blood_splatter_scene:
		return
	var splatter = blood_splatter_scene.instantiate()
	var pmat = splatter.process_material.duplicate()
	
	var is_exec = health_component.last_is_execute if is_instance_valid(health_component) else false
	var is_shock = health_component.was_killed_by_shockwave if is_instance_valid(health_component) else false
	var is_mel = health_component.was_killed_by_melee if is_instance_valid(health_component) else false
	
	if is_exec:
		splatter.amount = 160
		splatter.scale = Vector3(2.4, 2.4, 2.4)
		pmat.spread = 180.0
		pmat.initial_velocity_min = 8.0
		pmat.initial_velocity_max = 20.0
		pmat.scale_min = 0.35
		pmat.scale_max = 0.65
	elif is_crit:
		splatter.amount = 145
		splatter.scale = Vector3(2.2, 2.2, 2.2)
		pmat.spread = 160.0
		pmat.initial_velocity_min = 7.5
		pmat.initial_velocity_max = 18.0
		pmat.scale_min = 0.26
		pmat.scale_max = 0.55
	elif is_shock or amount >= 80 or knock_vec.length() >= 25.0:
		splatter.amount = 110
		splatter.scale = Vector3(1.9, 1.9, 1.9)
		pmat.spread = 100.0
		pmat.initial_velocity_min = 6.0
		pmat.initial_velocity_max = 16.0
		pmat.scale_min = 0.22
		pmat.scale_max = 0.50
	elif is_mel:
		splatter.amount = 20
		splatter.scale = Vector3(0.8, 0.8, 0.8)
		pmat.spread = 35.0
		pmat.initial_velocity_min = 3.0
		pmat.initial_velocity_max = 6.0
		pmat.scale_min = 0.08
		pmat.scale_max = 0.18
	else:
		splatter.amount = 28
		splatter.scale = Vector3(1.0, 1.0, 1.0)
		pmat.spread = 40.0
		pmat.initial_velocity_min = 4.0
		pmat.initial_velocity_max = 8.0
		pmat.scale_min = 0.10
		pmat.scale_max = 0.25
		
	splatter.process_material = pmat
	
	var scene_root = get_tree().current_scene if get_tree().current_scene else get_parent()
	if scene_root:
		scene_root.add_child(splatter)
		splatter.global_position = hit_pos
		
		var flat_knockback = Vector3(knock_vec.x, 0, knock_vec.z)
		if flat_knockback != Vector3.ZERO and hit_pos != hit_pos + flat_knockback:
			splatter.look_at(hit_pos + flat_knockback, Vector3.UP)

func _spawn_damage_number(dmg_amount: int, spawn_pos: Vector3, is_crit: bool = false, is_poison: bool = false) -> void:
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
	elif dmg_amount >= 140:
		label.text = "-%d AIR!" % dmg_amount
		label.modulate = Color(0.2, 0.85, 1.0, 1.0)
		label.font_size = 28
	else:
		label.text = "-%d" % dmg_amount
		label.modulate = Color(1.0, 0.92, 0.25, 1.0)
		label.font_size = 24
		
	var scene_root = get_tree().current_scene if get_tree().current_scene else get_parent()
	if not scene_root:
		return
	scene_root.add_child(label)
	
	var base_p = spawn_pos if spawn_pos.length_squared() > 0.01 else global_position + Vector3(0, 0.8, 0)
	var offset = Vector3(randf_range(-0.15, 0.15), randf_range(0.05, 0.2), randf_range(-0.15, 0.15))
	var start_p = base_p + offset
	label.global_position = start_p
	
	var target_p = start_p + Vector3(0.0, 0.75, 0.0)
	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "global_position", target_p, 0.65).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "modulate:a", 0.0, 0.65).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(label.queue_free)

func die(death_info: Dictionary = {}) -> void:
	if current_state == State.DEAD and not is_physics_processing():
		return
	current_state = State.DEAD
	set_physics_process(false)
	AudioManager.play_sound("enemy_death")
	
	if not death_info.is_empty():
		explosion_chain_depth = death_info.get("explosion_chain_depth", explosion_chain_depth)
		slam_chain_depth = death_info.get("slam_chain_depth", slam_chain_depth)
		if death_info.get("source_chain_depth", -1) >= 3:
			is_inflated = false
		if death_info.get("is_headshot", false):
			if eyes:
				eyes.visible = false
			if head_mesh:
				head_mesh.visible = false
	elif is_instance_valid(health_component):
		explosion_chain_depth = health_component.explosion_chain_depth
		slam_chain_depth = health_component.slam_chain_depth

	# Источник правды о способе убийства — HealthComponent
	var has_health = is_instance_valid(health_component)
	var killed_by_melee: bool = health_component.was_killed_by_melee if has_health else false
	var killed_by_shockwave: bool = health_component.was_killed_by_shockwave if has_health else false
	var killer_weapon: String = health_component.last_damage_weapon if has_health else ""

	var player = get_tree().get_first_node_in_group("player")
	if is_instance_valid(player) and "bpm_system" in player and is_instance_valid(player.bpm_system):
		var weapon_used = killer_weapon
		if killed_by_shockwave or killed_by_melee:
			weapon_used = "melee"
		elif weapon_used == "":
			var weapons_mgr = player.weapons if player is Player else null
			if weapons_mgr is WeaponManager:
				match weapons_mgr.current_weapon_index:
					0: weapon_used = "caliber0"
					1: weapon_used = "anvil"
					2: weapon_used = "injector"
					3: weapon_used = "sewing"
					_: weapon_used = "unknown"
			else:
				weapon_used = "unknown"
				
		if player.bpm_system.has_method("record_kill_bpm"):
			player.bpm_system.record_kill_bpm(weapon_used, killed_by_shockwave)
	
	if hp_sprite:
		hp_sprite.visible = false
	if hp_label:
		hp_label.visible = false
		
	if collision_shape:
		collision_shape.set_deferred("disabled", true)
		
	if head_hitbox:
		var head_col = head_hitbox.get_node_or_null("CollisionShape3D")
		if head_col:
			head_col.set_deferred("disabled", true)
			
	if detection_area:
		var det_col = detection_area.get_node_or_null("CollisionShape3D")
		if det_col:
			det_col.set_deferred("disabled", true)
			
	var was_inflated = is_inflated
	var chain_depth = health_component.explosion_chain_depth if is_instance_valid(health_component) else explosion_chain_depth
	if needle_count > 0:
		_trigger_needle_burst(was_inflated, chain_depth)

	if not poison_stacks.is_empty():
		var min_depth = 999
		for stack in poison_stacks:
			var d = int(stack.get("chain_depth", 0))
			if d < min_depth:
				min_depth = d
		if min_depth < 3:
			_trigger_poison_contagion(min_depth)

	if is_inflated:
		if chain_depth > 3:
			is_inflated = false
			if inflation_pulse_tween:
				inflation_pulse_tween.kill()
		else:
			_trigger_inflation_explosion(chain_depth)
		
	if blood_pool_scene:
		var space_state = get_world_3d().direct_space_state
		var query = PhysicsRayQueryParameters3D.create(global_position, global_position + Vector3.DOWN * 50.0)
		var result = space_state.intersect_ray(query)
		
		var pool = blood_pool_scene.instantiate()
		var scene_root = get_tree().current_scene if get_tree().current_scene else get_parent()
		if scene_root:
			scene_root.add_child(pool)
			if result:
				pool.global_position = result.position + Vector3(0, 0.01, 0)
			else:
				pool.global_position = global_position
			
	queue_free()

func add_slow(factor: float = 0.5) -> void:
	_ensure_status_effect_component().add_slow(factor)

func remove_slow() -> void:
	_ensure_status_effect_component().remove_slow()

func apply_poison_dot(duration: float = 3.0, damage_per_tick: int = 3, interval: float = 0.5, chain_depth: int = 0) -> void:
	_ensure_status_effect_component().apply_poison_dot(duration, damage_per_tick, interval, chain_depth)

func _apply_poison_tick(damage: int) -> void:
	if is_instance_valid(status_effect_component):
		status_effect_component._apply_poison_tick(damage)
	else:
		_on_status_requests_damage(damage, &"poison")

func add_needle(_is_blood_needle: bool = false) -> void:
	_ensure_status_effect_component().add_needle(_is_blood_needle)

func _update_needle_visuals() -> void:
	if current_state == State.DEAD:
		return
	if is_inflated:
		return
		
	if needle_count > 0:
		var n_factor = clamp(float(needle_count) / 30.0, 0.0, 1.0)
		var target_scale = Vector3.ONE * (1.0 + n_factor * 0.18)
		if body_mesh:
			body_mesh.scale = target_scale
			if not body_override_mat:
				var orig_mat = body_mesh.get_surface_override_material(0)
				body_override_mat = orig_mat.duplicate() if orig_mat else StandardMaterial3D.new()
				body_mesh.set_surface_override_material(0, body_override_mat)
			body_override_mat.emission_enabled = true
			body_override_mat.emission = Color(0.75, 0.88, 1.0)
			body_override_mat.emission_energy_multiplier = 0.4 + n_factor * 1.6
		if head_mesh:
			head_mesh.scale = target_scale
	else:
		if body_mesh:
			body_mesh.scale = Vector3.ONE
			if body_override_mat:
				body_override_mat.emission_enabled = false
		if head_mesh:
			head_mesh.scale = Vector3.ONE

func inflate() -> void:
	if is_inflated or current_state == State.DEAD:
		return
	_ensure_status_effect_component().inflate()
	if current_state == State.IDLE:
		var player = get_tree().get_first_node_in_group("player")
		if is_instance_valid(player):
			start_chase(player)

func _update_inflation_visuals() -> void:
	if current_state == State.DEAD:
		return
	if inflation_tween:
		inflation_tween.kill()
	inflation_tween = create_tween().set_parallel(true)
	
	if body_mesh:
		var orig_mat = body_mesh.get_surface_override_material(0)
		if orig_mat:
			body_override_mat = orig_mat.duplicate()
		else:
			body_override_mat = StandardMaterial3D.new()
			body_override_mat.albedo_color = Color(0.015, 0.015, 0.015, 1)
		body_override_mat.emission_enabled = true
		body_override_mat.emission = Color(1.0, 0.12, 0.12)
		body_override_mat.emission_energy_multiplier = 1.6
		body_mesh.set_surface_override_material(0, body_override_mat)
		inflation_tween.tween_property(body_mesh, "scale", Vector3(1.26, 1.26, 1.26), 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		
	if head_mesh:
		inflation_tween.tween_property(head_mesh, "scale", Vector3(1.26, 1.26, 1.26), 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		
	if eyes_material:
		eyes_material.emission = Color(1.0, 0.1, 0.1)
		eyes_material.emission_energy_multiplier = 3.5
		
	if inflation_pulse_tween:
		inflation_pulse_tween.kill()
	inflation_pulse_tween = create_tween().set_loops()
	if body_override_mat:
		inflation_pulse_tween.tween_property(body_override_mat, "emission_energy_multiplier", 3.2, 0.45).set_trans(Tween.TRANS_SINE)
		inflation_pulse_tween.tween_property(body_override_mat, "emission_energy_multiplier", 1.2, 0.45).set_trans(Tween.TRANS_SINE)

func _on_status_effect_applied(_kind: StringName, _stacks: int) -> void:
	pass

func _on_status_effect_expired(_kind: StringName) -> void:
	pass

func _on_status_visuals_need_update(kind: StringName) -> void:
	if kind == &"needle":
		_update_needle_visuals()
	elif kind == &"inflation":
		_update_inflation_visuals()

func _on_status_requests_damage(amount: int, kind: StringName) -> void:
	if current_state == State.DEAD:
		return
	if kind == &"poison":
		if is_instance_valid(health_component):
			health_component.last_damage_weapon = "injector"
		health -= amount
		_update_health_bar()
		var hit_pos = global_position + Vector3(randf_range(-0.15, 0.15), 0.85 + randf_range(-0.1, 0.1), randf_range(-0.15, 0.15))
		_spawn_damage_number(amount, hit_pos, false, true)
		if current_state == State.IDLE:
			var player = get_tree().get_first_node_in_group("player")
			if is_instance_valid(player):
				start_chase(player)
		if health <= 0:
			explosion_chain_depth = 0
			if is_instance_valid(health_component):
				health_component.explosion_chain_depth = 0
			set_state(State.DEAD)

func _on_health_damaged(amount: int, is_crit: bool, hit_pos: Vector3) -> void:
	_spawn_damage_number(amount, hit_pos, is_crit)
	AudioManager.play_sound("enemy_hit")
	
	if is_crit:
		GameTypes.debug_log(&"enemy", "[%s] HEADSHOT! Damage: %d | Remaining HP: %d" % [name, amount, max(0, health)])
		var cur_frame = Engine.get_process_frames()
		if cur_frame != last_headshot_bonus_frame:
			last_headshot_bonus_frame = cur_frame
			var player_node = get_tree().get_first_node_in_group("player")
			if is_instance_valid(player_node) and "bpm_system" in player_node and is_instance_valid(player_node.bpm_system):
				player_node.bpm_system.add_bpm(1.5)
				GameTypes.debug_log(&"enemy", "[HEADSHOT BPM BONUS] +1.5 BPM granted for precision headshot! (Current BPM: %.1f)" % player_node.bpm_system.bpm)
				
	_spawn_hit_blood_splatter(amount, hit_pos, is_crit, last_hit_knockback)

func _on_health_changed(_current_hp: int, _max_hp: int) -> void:
	_update_health_bar()

func _on_health_died(death_info: Dictionary) -> void:
	die(death_info)

func _trigger_inflation_explosion(depth: int = 0) -> void:
	_ensure_status_effect_component().trigger_inflation_explosion(depth)

func trigger_inflation_explosion(depth: int = 0) -> void:
	_trigger_inflation_explosion(depth)

func _trigger_poison_contagion(depth: int = 0) -> void:
	_ensure_status_effect_component().trigger_poison_contagion(depth)

func trigger_poison_contagion(depth: int = 0) -> void:
	_trigger_poison_contagion(depth)

func _trigger_needle_burst(was_inflated: bool, depth: int) -> void:
	_ensure_status_effect_component().trigger_needle_burst(was_inflated, depth)

func trigger_needle_burst(was_inflated: bool, depth: int) -> void:
	_trigger_needle_burst(was_inflated, depth)

func _spawn_explosion_shockwave(scene_root: Node, pos: Vector3, radius: float) -> void:
	_ensure_status_effect_component().spawn_explosion_shockwave(scene_root, pos, radius)

func spawn_explosion_shockwave(scene_root: Node, pos: Vector3, radius: float) -> void:
	_ensure_status_effect_component().spawn_explosion_shockwave(scene_root, pos, radius)

func _spawn_poison_cloud_visual(scene_root: Node, cloud_pos: Vector3, cloud_radius: float) -> void:
	_ensure_status_effect_component().spawn_poison_cloud_visual(scene_root, cloud_pos, cloud_radius)

func spawn_poison_cloud_visual(scene_root: Node, cloud_pos: Vector3, cloud_radius: float) -> void:
	_ensure_status_effect_component().spawn_poison_cloud_visual(scene_root, cloud_pos, cloud_radius)
