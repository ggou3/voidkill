extends "res://enemy.gd"

## Враг "Подрывник" (Bomber Enemy).
## Быстрый камикадзе (+40% к скорости обычного врага).
## При сближении на 2.5м запускает 0.8с таймер детонации с тикающим звуком и накаляющимся свечением.
## Взрывается по площади (радиус 5м, урон 40 HP) по истечении таймера или при преждевременной смерти.

@export var bomber_health: int = 55
@export var bomber_speed: float = 16.1 # +40% к базовой скорости 11.5 м/с
@export var detonation_distance: float = 2.5
@export var detonation_duration: float = 0.8
@export var explosion_damage: int = 40
@export var explosion_radius: float = 5.0
@export var warning_distance: float = 6.0

var is_detonating: bool = false
var detonation_timer: float = 0.0
var has_exploded: bool = false

var tick_timer: float = 0.0
var glow_time: float = 0.0

var core_material: StandardMaterial3D = null
var body_material: StandardMaterial3D = null

@onready var core_mesh: MeshInstance3D = get_node_or_null("CoreMesh")
@onready var core_light: OmniLight3D = get_node_or_null("CoreLight")
@onready var body_mesh_inst: MeshInstance3D = get_node_or_null("MeshInstance3D")

const CORE_IDLE_COLOR = Color(1.0, 0.15, 0.05)
const BODY_IDLE_COLOR = Color(0.09, 0.04, 0.04)
const OVERHEAT_COLOR = Color(1.0, 0.35, 0.1)

func _ready():
	super._ready()
	max_health = bomber_health
	health = bomber_health
	move_speed = bomber_speed
	acceleration = 8.5
	attack_range = 0.0
	attack_damage = 0
	lunge_cooldown_timer = 999999.0
	
	if core_mesh:
		var c_mat = core_mesh.get_surface_override_material(0)
		if c_mat:
			core_material = c_mat.duplicate()
			core_mesh.set_surface_override_material(0, core_material)
			
	if body_mesh_inst:
		var b_mat = body_mesh_inst.get_surface_override_material(0)
		if b_mat:
			body_material = b_mat.duplicate()
			body_mesh_inst.set_surface_override_material(0, body_material)
			
	if eyes_material:
		eyes_material.emission = Color(1.0, 0.15, 0.05)
		eyes_material.emission_energy_multiplier = 3.0

func _can_lunge_to_player() -> bool:
	return false

func start_lunge():
	pass

func _physics_process(delta: float):
	super._physics_process(delta)
	if has_exploded or current_state == State.DEAD:
		return
		
	glow_time += delta
	var player = target_player if is_instance_valid(target_player) else get_tree().get_first_node_in_group("player")
	
	if is_instance_valid(player) and not ("is_dead" in player and player.is_dead):
		var dist = global_position.distance_to(player.global_position)
		
		# 1. Если детонация ещё не началась
		if not is_detonating:
			if dist <= detonation_distance:
				_start_detonation()
			elif dist <= warning_distance:
				# Раннее предупреждение в пределах 6 метров: ядро постепенно разгорается
				var warn_t = clampf((warning_distance - dist) / (warning_distance - detonation_distance), 0.0, 1.0)
				var pulse = 0.5 + 0.5 * sin(glow_time * (4.0 + warn_t * 8.0))
				if core_material:
					core_material.emission_energy_multiplier = lerp(0.8, 3.8, warn_t) + pulse * 1.2
				if core_light:
					core_light.light_energy = lerp(0.5, 2.5, warn_t) + pulse * 0.8
			else:
				# Спокойное тусклое пульсирование на дальней дистанции
				var idle_pulse = 0.5 + 0.5 * sin(glow_time * 3.0)
				if core_material:
					core_material.emission_energy_multiplier = 0.7 + idle_pulse * 0.4
				if core_light:
					core_light.light_energy = 0.4 + idle_pulse * 0.3
					
		# 2. Фаза обратного отсчёта детонации (0.8с)
		else:
			detonation_timer -= delta
			var progress = clampf(1.0 - (detonation_timer / detonation_duration), 0.0, 1.0)
			
			# Ускоряющийся тикающий звук
			var current_tick_interval = lerp(0.22, 0.06, progress)
			tick_timer -= delta
			if tick_timer <= 0.0:
				AudioManager.play_sound("bomber_tick")
				tick_timer = current_tick_interval
				
			# Нарастающее накаливание ядра и всего тела (от красного к ослепительно-раскаленному)
			var overheat_pulse = 0.5 + 0.5 * sin(glow_time * (12.0 + progress * 24.0))
			var heat_energy = lerp(3.5, 8.0, progress) + overheat_pulse * 2.5
			if core_material:
				core_material.emission = OVERHEAT_COLOR
				core_material.emission_energy_multiplier = heat_energy
			if body_material:
				body_material.emission_enabled = true
				body_material.emission = Color(0.9, 0.15, 0.05)
				body_material.emission_energy_multiplier = lerp(0.0, 3.5, progress) + overheat_pulse * 1.5
			if core_light:
				core_light.light_energy = lerp(2.0, 6.0, progress) + overheat_pulse * 2.0
				
			# Легкое расширение корпуса от внутреннего давления перед взрывом
			var swell = 1.0 + progress * 0.12 + overheat_pulse * 0.03
			scale = Vector3(swell, swell, swell)
			
			if detonation_timer <= 0.0:
				_explode()

func _start_detonation():
	if is_detonating or has_exploded:
		return
	is_detonating = true
	detonation_timer = detonation_duration
	tick_timer = 0.0 # Первый тик раздаётся мгновенно
	print("[%s] BOMBER DETONATION STARTED! (Window: %.2fs)" % [name, detonation_duration])

func die():
	# Если враг умирает ДО или ВО ВРЕМЯ таймера детонации — моментальный взрыв
	if not has_exploded:
		_explode()
	else:
		super.die()

func _explode():
	if has_exploded:
		return
	has_exploded = true
	current_state = State.DEAD
	
	var explosion_pos = global_position + Vector3(0, 0.75, 0)
	print("[%s] BOMBER EXPLODED at %s! Radius: %.1fm, Dmg: %d" % [name, explosion_pos, explosion_radius, explosion_damage])
	
	AudioManager.play_sound("explosion")
	
	var scene_root = get_tree().current_scene if get_tree().current_scene else get_parent()
	if scene_root:
		# Сочный круговой разлёт крови и осколков
		if blood_splatter_scene:
			var splatter = blood_splatter_scene.instantiate()
			splatter.amount = 120
			splatter.scale = Vector3(2.2, 2.2, 2.2)
			var pmat = splatter.process_material.duplicate()
			pmat.spread = 180.0
			pmat.initial_velocity_min = 8.0
			pmat.initial_velocity_max = 20.0
			pmat.scale_min = 0.25
			pmat.scale_max = 0.60
			splatter.process_material = pmat
			scene_root.add_child(splatter)
			splatter.global_position = explosion_pos
			
		_spawn_explosion_shockwave(scene_root, explosion_pos, explosion_radius)
		
	# 1. Урон по игроку с затуханием по расстоянию
	var player = get_tree().get_first_node_in_group("player")
	if is_instance_valid(player) and not ("is_dead" in player and player.is_dead):
		var player_center = player.global_position + Vector3(0, 0.9, 0)
		var dist_to_player = explosion_pos.distance_to(player_center)
		if dist_to_player <= explosion_radius:
			var falloff = clampf(1.0 - (dist_to_player / explosion_radius) * 0.5, 0.35, 1.0)
			var dmg = max(1, int(round(float(explosion_damage) * falloff)))
			var knock_dir = (player_center - explosion_pos).normalized()
			if knock_dir.length_squared() < 0.01:
				knock_dir = Vector3.UP
			var knock_vec = knock_dir * 18.0 + Vector3.UP * 4.5
			player.take_damage(dmg, knock_vec, explosion_pos)
			print("[BOMBER] Hit player for %d dmg (dist: %.2fm)" % [dmg, dist_to_player])
			
	# 2. Урон по всем остальным врагам в радиусе поражения
	var all_enemies = get_tree().get_nodes_in_group("enemy")
	for other_enemy in all_enemies:
		if not is_instance_valid(other_enemy) or other_enemy == self:
			continue
		if ("current_state" in other_enemy and other_enemy.current_state == other_enemy.State.DEAD) or ("health" in other_enemy and other_enemy.health <= 0):
			continue
			
		var enemy_center = other_enemy.global_position + Vector3(0, 0.8, 0)
		var dist = explosion_pos.distance_to(enemy_center)
		if dist <= explosion_radius:
			var falloff = clampf(1.0 - (dist / explosion_radius) * 0.5, 0.35, 1.0)
			var dmg = max(1, int(round(float(explosion_damage) * falloff)))
			var knock_dir = (enemy_center - explosion_pos).normalized()
			if knock_dir.length_squared() < 0.01:
				knock_dir = Vector3.UP
			var knock_vec = knock_dir * 16.0 + Vector3.UP * 4.0
			other_enemy.take_damage(dmg, knock_vec, enemy_center, false, false, false, false, -1, "bomber")
			print("[BOMBER] Hit enemy %s for %d dmg" % [other_enemy.name, dmg])
			
	# Спавн лужи крови на полу
	if blood_pool_scene and scene_root:
		var pool = blood_pool_scene.instantiate()
		scene_root.add_child(pool)
		var space_state = get_world_3d().direct_space_state
		if space_state:
			var query = PhysicsRayQueryParameters3D.create(global_position + Vector3(0, 0.5, 0), global_position + Vector3(0, -3.0, 0))
			query.collision_mask = 1
			query.collide_with_areas = false
			query.collide_with_bodies = true
			var hit = space_state.intersect_ray(query)
			if hit:
				pool.global_position = hit.position + Vector3(0, 0.01, 0)
			else:
				pool.global_position = global_position
		else:
			pool.global_position = global_position
			
	queue_free()
