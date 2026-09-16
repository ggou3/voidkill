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

# --- BPM SYSTEM (Сердцебиение) & COMBAT MOMENTUM ---
const MIN_BPM: float = 50.0
const MAX_BPM: float = 200.0
var bpm: float = MIN_BPM
var time_since_bpm_gain: float = 0.0
var last_kill_weapon: String = ""

var combat_momentum: float = 1.0
var time_since_momentum_gain: float = 0.0
var momentum_idle_timer: float = 0.0
var momentum_display_alpha: float = 1.0
var momentum_font_size: int = 28

@onready var player = $".."
@onready var head = $"../Head"
@onready var slam_ray = $"../SlamRay"
@onready var dash_label = $"../HUD/DashLabel"
@onready var bpm_label = get_node_or_null("../HUD/BPMLabel")
@onready var momentum_label: Label = get_node_or_null("../HUD/MomentumLabel")
@onready var combo_label: Label = get_node_or_null("../HUD/ComboLabel")
var combo_tween: Tween = null
var blood_splatter_scene = preload("res://blood_splatter.tscn")

func _ready():
	dashes = MAX_DASH
	dash_timer_cd = 0.0
	dash_interval_timer = 0.0
	dash_current_speed = dash_target_speed
	
	if not bpm_label:
		var hud = get_node_or_null("../HUD")
		if hud:
			bpm_label = Label.new()
			bpm_label.name = "BPMLabel"
			bpm_label.offset_left = 34.0
			bpm_label.offset_top = 484.0
			bpm_label.offset_right = 350.0
			bpm_label.offset_bottom = 529.0
			bpm_label.add_theme_font_size_override("font_size", 28)
			hud.add_child(bpm_label)

	if not momentum_label:
		var hud = get_node_or_null("../HUD")
		if hud:
			momentum_label = Label.new()
			momentum_label.name = "MomentumLabel"
			momentum_label.offset_left = 350.0
			momentum_label.offset_top = 484.0
			momentum_label.offset_right = 660.0
			momentum_label.offset_bottom = 529.0
			momentum_label.add_theme_font_size_override("font_size", 28)
			hud.add_child(momentum_label)

func _process(delta):
	# Восстановление зарядов дэша
	if dashes < MAX_DASH:
		dash_timer_cd -= delta
		if dash_timer_cd <= 0.0:
			dashes += 1
			dash_timer_cd = dash_cd if dashes < MAX_DASH else 0.0

	# Таймер минимального интервала между дэшами
	if dash_interval_timer > 0.0:
		dash_interval_timer -= delta
			
	if slam_timer > 0: slam_timer -= delta
	
	# BPM: прогрессивный пассивный спад при отсутствии событий роста:
	# decay_rate = lerp(1.5, 7.0, (bpm - 50) / 150), задержка 2.0с (или 5.0с на пике bpm >= 195)
	time_since_bpm_gain += delta
	var decay_delay: float = 5.0 if bpm >= 195.0 else 2.0
	if time_since_bpm_gain >= decay_delay and bpm > MIN_BPM:
		var bpm_ratio: float = clampf((bpm - MIN_BPM) / (MAX_BPM - MIN_BPM), 0.0, 1.0)
		var decay_rate: float = lerp(1.5, 7.0, bpm_ratio)
		bpm = max(MIN_BPM, bpm - decay_rate * delta)
		
	# Combat Momentum: источники роста в реальном времени
	var gained_momentum_continuous: bool = false
	if is_instance_valid(player):
		# 1. Активный кровавый сёрф (слайд по луже крови): +0.04 к моментуму/сек
		if player.is_sliding and player.is_on_blood:
			add_combat_momentum(0.04 * delta)
			gained_momentum_continuous = true
			
		# 2. Нахождение в воздухе на высокой скорости (не coyote-time, скорость >= WALK_SPEED): +0.015 к моментуму/сек
		var horiz_spd = Vector2(player.velocity.x, player.velocity.z).length()
		var in_air_speed = not player.is_on_floor() and player.coyote_timer <= 0.0 and horiz_spd >= player.WALK_SPEED
		if in_air_speed:
			add_combat_momentum(0.015 * delta)
			gained_momentum_continuous = true
			
	if not gained_momentum_continuous:
		time_since_momentum_gain += delta
		
	# Combat Momentum: пассивный спад при отсутствии приращений за последние 1.5 секунды: -0.1/сек (не ниже 1.0)
	if time_since_momentum_gain >= 1.5 and combat_momentum > 1.0:
		combat_momentum = max(1.0, combat_momentum - 0.1 * delta)
		
	# Индикация BPM в HUD
	if bpm_label:
		bpm_label.text = "BPM: %d (%s)" % [int(round(bpm)), GameTypes.tier_to_string(get_bpm_tier())]
		
	# Постоянная индикация Combat Momentum в HUD
	_update_momentum_hud(delta)
	
	# Индикация состояния зарядов и остывания
	if dash_label:
		if dashes == 0:
			dash_label.text = "DASH: 0 (+" + str(snapped(dash_timer_cd, 0.1)) + "s)"
		elif dash_interval_timer > 0.0 or is_dashing:
			var int_sec = max(0.1, snapped(dash_interval_timer, 0.1))
			dash_label.text = "DASH: " + str(dashes) + " (COOLDOWN " + str(int_sec) + "s)"
		elif dashes < MAX_DASH:
			dash_label.text = "DASH: " + str(dashes) + " (READY, +" + str(snapped(dash_timer_cd, 0.1)) + "s)"
		else:
			dash_label.text = "DASH: " + str(MAX_DASH) + " (READY)"

# --- BPM API ---

func add_combat_momentum(amount: float):
	if amount <= 0.0:
		return
	combat_momentum = clampf(combat_momentum + amount, 1.0, 2.0)
	time_since_momentum_gain = 0.0
	momentum_idle_timer = 0.0

func _update_momentum_hud(delta: float):
	if not is_instance_valid(momentum_label):
		return
		
	# Отслеживание времени простоя на базовом значении 1.0
	if combat_momentum <= 1.001:
		momentum_idle_timer += delta
	else:
		momentum_idle_timer = 0.0
		
	# 1. Формат отображения: "MOMENTUM: ×1.45"
	momentum_label.text = "MOMENTUM: ×%.2f" % combat_momentum
	
	# 2. Линейная интерполяция цвета: от нейтрального белого (1.0) к яркому жёлтому/золотому (2.0)
	var t: float = clampf(combat_momentum - 1.0, 0.0, 1.0)
	var neutral_color: Color = Color(1.0, 1.0, 1.0, 1.0)
	var gold_color: Color = Color(1.0, 0.82, 0.2, 1.0)
	var active_color: Color = neutral_color.lerp(gold_color, t)
	
	# 3. Состояние покоя (2+ секунды без изменений на базовом значении 1.0)
	var is_dimmed: bool = (combat_momentum <= 1.001 and momentum_idle_timer >= 2.0)
	
	if is_dimmed:
		# Плавное затемнение/приглушение до 45% яркости и уменьшенный размер шрифта (24)
		momentum_display_alpha = move_toward(momentum_display_alpha, 0.45, 2.0 * delta)
		if momentum_font_size != 24:
			momentum_font_size = 24
			momentum_label.add_theme_font_size_override("font_size", 24)
	else:
		# Мгновенный возврат к полной яркости и полноразмерному шрифту (28) при любом росте
		momentum_display_alpha = 1.0
		if momentum_font_size != 28:
			momentum_font_size = 28
			momentum_label.add_theme_font_size_override("font_size", 28)
			
	momentum_label.add_theme_color_override("font_color", active_color)
	momentum_label.modulate.a = momentum_display_alpha

func force_max_bpm():
	bpm = MAX_BPM
	time_since_bpm_gain = 0.0
	GameTypes.debug_log(&"bpm", "[DEBUG] Max BPM (%.1f) forced via 'T' key! Peak delay set to 5.0s." % MAX_BPM)

func add_bpm(amount: float):
	if amount <= 0.0:
		return
	bpm = clamp(bpm + amount, MIN_BPM, MAX_BPM)
	time_since_bpm_gain = 0.0

func record_kill_bpm(weapon_type: String, is_shockwave: bool = false) -> float:
	var base_bpm: float = 8.0 if is_shockwave else 5.5
	var bonus_bpm: float = 0.0
	
	# Бонус за разнообразие (+2 BPM), если оружие отличается от предыдущего убийства
	if last_kill_weapon != "" and weapon_type != "" and weapon_type != last_kill_weapon:
		bonus_bpm = 2.0
		GameTypes.debug_log(&"bpm", "[BPM VARIETY BONUS] +2.0 BPM! Killer: '%s' != previous: '%s' (Total: +%.1f BPM)" % [
			weapon_type, last_kill_weapon, base_bpm + bonus_bpm
		])
		_show_combo_popup(bonus_bpm)
	elif last_kill_weapon != "" and weapon_type == last_kill_weapon:
		GameTypes.debug_log(&"bpm", "[BPM KILL] Same weapon '%s' (Total: +%.1f BPM, no variety bonus)" % [weapon_type, base_bpm])
	else:
		GameTypes.debug_log(&"bpm", "[BPM KILL] First kill with '%s' (Total: +%.1f BPM)" % [weapon_type, base_bpm])
		
	if weapon_type != "":
		last_kill_weapon = weapon_type
		
	var total_bpm = (base_bpm + bonus_bpm) * combat_momentum
	if combat_momentum > 1.0:
		GameTypes.debug_log(&"bpm", "[COMBAT MOMENTUM] x%.2f applied: +%.1f -> +%.1f BPM" % [
			combat_momentum, base_bpm + bonus_bpm, total_bpm
		])
	add_bpm(total_bpm)
	return total_bpm

func show_hud_popup(text: String):
	if not combo_label:
		var hud = get_node_or_null("../HUD")
		if hud:
			combo_label = hud.get_node_or_null("ComboLabel")
			if not combo_label:
				combo_label = Label.new()
				combo_label.name = "ComboLabel"
				combo_label.offset_left = 34.0
				combo_label.offset_top = 452.0
				combo_label.offset_right = 350.0
				combo_label.offset_bottom = 484.0
				combo_label.add_theme_font_size_override("font_size", 22)
				combo_label.add_theme_color_override("font_color", Color(1.0, 0.82, 0.2, 1.0))
				combo_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1.0))
				combo_label.add_theme_constant_override("outline_size", 6)
				combo_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
				combo_label.add_theme_constant_override("shadow_offset_x", 2)
				combo_label.add_theme_constant_override("shadow_offset_y", 2)
				hud.add_child(combo_label)

	if not combo_label:
		return
		
	# Если предыдущая плашка ещё на экране, отменяем её tween и обновляем таймер/текст
	if combo_tween and combo_tween.is_valid():
		combo_tween.kill()
		
	combo_label.text = text
	combo_label.visible = true
	combo_label.modulate.a = 1.0
	combo_label.position.y = 452.0
	
	combo_tween = create_tween()
	# Плавное всплытие вверх на 10px за 1.2 секунды
	combo_tween.tween_property(combo_label, "position:y", 442.0, 1.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	# Держится на экране 0.7с, затем плавное исчезновение (fade out) 0.5с
	combo_tween.parallel().tween_property(combo_label, "modulate:a", 1.0, 0.7)
	combo_tween.chain().tween_property(combo_label, "modulate:a", 0.0, 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	combo_tween.chain().tween_callback(func(): if is_instance_valid(combo_label): combo_label.visible = false)

func _show_combo_popup(bonus_amount: float):
	show_hud_popup("★ VARIETY +%d ★" % int(round(bonus_amount)))

func drop_bpm_on_damage():
	# Резкое падение при получении урона игроком: -25% от текущего значения (не фиксированное число)
	var drop = bpm * 0.25
	bpm = max(MIN_BPM, bpm - drop)
	GameTypes.debug_log(&"bpm", "[BPM] Damage penalty: -%.1f -> %.1f (%s)" % [drop, bpm, GameTypes.tier_to_string(get_bpm_tier())])

func get_bpm_tier() -> GameTypes.BPMTier:
	if bpm < 90.0:
		return GameTypes.BPMTier.CALM
	elif bpm < 140.0:
		return GameTypes.BPMTier.PUMPING
	elif bpm < 180.0:
		return GameTypes.BPMTier.SURGING
	else:
		return GameTypes.BPMTier.OVERDRIVE

# Устаревшие методы кровавого баффа (заменены BPM-системой)
func activate_blood_buff():
	pass

func has_blood_buff() -> bool:
	return false

func add_dash_charge():
	if dashes < MAX_DASH:
		dashes += 1
		if dashes == MAX_DASH:
			dash_timer_cd = 0.0

func trigger_dash(input_dir: Vector2, p_basis: Basis) -> bool:
	if dashes > 0 and not is_dashing and not is_slamming and dash_interval_timer <= 0.0:
		is_dashing = true
		dash_timer = DASH_DUR
		dash_interval_timer = dash_min_interval
		dashes -= 1
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
