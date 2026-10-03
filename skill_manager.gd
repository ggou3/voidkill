class_name SkillManager
extends Node

const MAX_DASH = 3
@export var dash_cd: float = 3.5 # Заметно увеличенное время восполнения заряда (было 1.5 сек)
@export var dash_min_interval: float = 0.5 # Минимальный интервал между последовательными дэшами
@export var dash_target_speed: float = 16.0 # Базовая целевая скорость рывка (от 10 м/с бега до 16 м/с)
@export var dash_boost: float = 5.0 # Добавочный импульс к скорости движения
const DASH_DUR = 0.15

const SLAM_SPEED = 60.0
const BOUNCE_VEL = 14.0
const SLAM_AOE = 6.0
const SLAM_DMG = 30
const SLAM_CD = 4.0

var dashes = MAX_DASH
var dash_timer_cd = 0.0
var dash_interval_timer = 0.0
var is_dashing = false
var dash_timer = 0.0
var dash_dir = Vector3.ZERO
var dash_current_speed: float = 16.0

var is_slamming = false
var slam_timer = 0.0

signal dash_charges_changed(count: int)
signal hud_popup_requested(text: String)

@onready var player = $".."
@onready var head = $"../Head"
@onready var slam_ray = $"../SlamRay"
var blood_splatter_scene = preload("res://blood_splatter.tscn")

func _ready():
	dashes = MAX_DASH
	dash_timer_cd = 0.0
	dash_interval_timer = 0.0
	dash_current_speed = dash_target_speed

func _process(delta):
	# Восстановление зарядов дэша
	if dashes < MAX_DASH:
		dash_timer_cd -= delta
		if dash_timer_cd <= 0.0:
			dashes += 1
			dash_timer_cd = dash_cd if dashes < MAX_DASH else 0.0
			dash_charges_changed.emit(dashes)

	# Таймер минимального интервала между дэшами
	if dash_interval_timer > 0.0:
		dash_interval_timer -= delta
			
	if slam_timer > 0: slam_timer -= delta

func show_hud_popup(text: String):
	hud_popup_requested.emit(text)

func add_dash_charge():
	if dashes < MAX_DASH:
		dashes += 1
		if dashes == MAX_DASH:
			dash_timer_cd = 0.0
		dash_charges_changed.emit(dashes)

func trigger_dash(input_dir: Vector2, p_basis: Basis) -> bool:
	if dashes > 0 and not is_dashing and not is_slamming and dash_interval_timer <= 0.0:
		is_dashing = true
		dash_timer = DASH_DUR
		dash_interval_timer = dash_min_interval
		dashes -= 1
		dash_charges_changed.emit(dashes)
		if dash_timer_cd <= 0.0:
			dash_timer_cd = dash_cd
		
		if input_dir != Vector2.ZERO:
			dash_dir = (p_basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
		else:
			dash_dir = -p_basis.z
			
		# Вычисляем скорость рывка: всегда даёт заметное ускорение и никогда не замедляет
		var cur_h_vel = Vector2(player.velocity.x, player.velocity.z)
		var dash_dir_2d = Vector2(dash_dir.x, dash_dir.z).normalized()
		var forward_speed = cur_h_vel.dot(dash_dir_2d)
		var cur_speed = cur_h_vel.length()
		
		# Комбинация гарантированного минимума и добавочного импульса к текущей скорости
		var target_vel = max(dash_target_speed, max(forward_speed + dash_boost, cur_speed + 2.0))
		var max_cap = player.blood_buffed_max_speed if "blood_buffed_max_speed" in player else 20.0
		dash_current_speed = min(target_vel, max_cap)
		AudioManager.play_sound("dash")
		return true
	return false

func process_dash(delta, vel: Vector3) -> Vector3:
	if is_dashing:
		dash_timer -= delta
		if dash_timer <= 0: is_dashing = false
		var out_y = vel.y if vel.y > 0.0 else 0.0
		return Vector3(dash_dir.x * dash_current_speed, out_y, dash_dir.z * dash_current_speed)
	return vel

func trigger_slam():
	if not player.is_on_floor() and not is_slamming and slam_timer <= 0:
		is_slamming = true

func process_slam(_delta, vel: Vector3) -> Vector3:
	if not is_slamming: return vel
	
	slam_ray.force_shapecast_update()
	var hit_enemy = false
	
	if slam_ray.is_colliding():
		for i in range(slam_ray.get_collision_count()):
			var hit = slam_ray.get_collider(i)
			if hit != null and hit.has_method("take_damage"):
				hit_enemy = true
				is_slamming = false
				vel.y = BOUNCE_VEL
				add_dash_charge()
				hit.take_damage(100, Vector3.DOWN, hit.global_position, true, false, false, false, -1, "melee")
				head.add_recoil(0.1, 0.0)
				slam_timer = SLAM_CD
				AudioManager.play_sound("slam_impact")
				break
				
	if not hit_enemy and player.is_on_floor():
		is_slamming = false
		vel.y = 0
		slam_timer = SLAM_CD
		
		# Проверка наличия лужи крови в радиусе обычного слэма + 2 метра (8.0м) или нахождения на крови
		var search_radius: float = SLAM_AOE + 2.0
		var nearby_blood_pools = _find_nearby_blood_pools(player.global_position, search_radius)
		var has_blood_slam: bool = (nearby_blood_pools.size() > 0) or player.is_on_blood
		
		var effective_aoe: float = SLAM_AOE
		
		if has_blood_slam:
			effective_aoe = SLAM_AOE * 1.5 # 9.0 метров
			head.add_recoil(0.35, 0.0)
			AudioManager.play_sound("slam_impact")
			AudioManager.play_sound("flask_splash")
			
			# Временное расширение луж крови (масштаб x1.4 на 4.0 секунды)
			for pool in nearby_blood_pools:
				if pool is BloodPool:
					pool.expand_temporarily(1.4, 4.0)
					
			# Мгновенный разовый бонус +10 BPM
			show_hud_popup("★ BLOOD SLAM ★")
			
			# Визуальный эффект расширяющейся волны крови
			_spawn_blood_slam_vfx(player.global_position, effective_aoe)
			GameTypes.debug_log(&"bpm", "[BLOOD SLAM] Enhanced shockwave! AOE: %.1fm, +10 BPM, expanded %d blood pool(s)" % [
				effective_aoe, nearby_blood_pools.size()
			])
		else:
			head.add_recoil(0.25, 0.0)
			AudioManager.play_sound("slam_impact")
		
		var enemies = player.get_tree().get_nodes_in_group("enemy")
		for e in enemies:
			if is_instance_valid(e):
				if player.global_position.distance_to(e.global_position) <= effective_aoe:
					e.take_damage(SLAM_DMG, (e.global_position - player.global_position).normalized(), e.global_position, true, false, true, false, -1, "melee")
					
	if is_slamming:
		vel.y = -SLAM_SPEED
		vel.x = 0
		vel.z = 0
		
	return vel

func _find_nearby_blood_pools(impact_pos: Vector3, search_radius: float) -> Array[Node]:
	var blood_pools = player.get_tree().get_nodes_in_group("blood_pool")
	var found: Array[Node] = []
	for pool in blood_pools:
		if not is_instance_valid(pool) or not (pool is Node3D):
			continue
		var pool_pos = pool.global_position
		# Проверяем перепад высоты (допустимый перепад до 3.0м)
		if abs(impact_pos.y - pool_pos.y) <= 3.0:
			var horiz_dist = Vector2(impact_pos.x - pool_pos.x, impact_pos.z - pool_pos.z).length()
			# Радиус цилиндра лужи ~1.7м, учитываем его при проверке дистанции
			if horiz_dist <= (search_radius + 1.7):
				found.append(pool)
	return found

func _spawn_blood_slam_vfx(impact_pos: Vector3, radius: float):
	var scene_root = player.get_tree().current_scene if player.get_tree().current_scene else player.get_parent()
	if not scene_root:
		return
		
	var ground_y = impact_pos.y - 0.95
	var space_state = player.get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(impact_pos, impact_pos + Vector3.DOWN * 2.5)
	var result = space_state.intersect_ray(query)
	if result:
		ground_y = result.position.y + 0.05
		
	var center_pos = Vector3(impact_pos.x, ground_y, impact_pos.z)
	
	# 1. Радиальный разлёт брызг крови
	if blood_splatter_scene:
		var splatter = blood_splatter_scene.instantiate()
		splatter.amount = 85
		var pmat = splatter.process_material.duplicate()
		pmat.direction = Vector3.UP
		pmat.spread = 85.0
		pmat.initial_velocity_min = 10.0
		pmat.initial_velocity_max = 22.0
		pmat.scale_min = 0.35
		pmat.scale_max = 0.8
		splatter.process_material = pmat
		scene_root.add_child(splatter)
		splatter.global_position = center_pos + Vector3(0, 0.1, 0)
		
	# 2. Расширяющаяся тороидальная волна крови по полу
	var ring = MeshInstance3D.new()
	var tmesh = TorusMesh.new()
	tmesh.inner_radius = 0.88
	tmesh.outer_radius = 1.0
	tmesh.rings = 36
	tmesh.ring_segments = 12
	ring.mesh = tmesh
	
	var mat = StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = Color(0.9, 0.06, 0.06, 0.85)
	ring.material_override = mat
	
	scene_root.add_child(ring)
	ring.global_position = center_pos + Vector3(0, 0.04, 0)
	ring.scale = Vector3(0.5, 0.2, 0.5)
	
	var tween = ring.create_tween().set_parallel(true)
	tween.tween_property(ring, "scale", Vector3(radius, 0.2, radius), 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(mat, "albedo_color:a", 0.0, 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(ring.queue_free)
	
	# 3. Кратковременная алая вспышка освещения
	var light = OmniLight3D.new()
	light.light_color = Color(1.0, 0.1, 0.05)
	light.light_energy = 4.0
	light.omni_range = radius
	scene_root.add_child(light)
	light.global_position = center_pos + Vector3(0, 0.5, 0)
	var ltween = light.create_tween()
	ltween.tween_property(light, "light_energy", 0.0, 0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	ltween.tween_callback(light.queue_free)
