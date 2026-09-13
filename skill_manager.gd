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

# --- BPM SYSTEM (Сердцебиение) ---
const MIN_BPM: float = 50.0
const MAX_BPM: float = 200.0
var bpm: float = MIN_BPM
var time_since_bpm_gain: float = 0.0
var last_kill_weapon: String = ""

@onready var player = $".."
@onready var head = $"../Head"
@onready var slam_ray = $"../SlamRay"
@onready var dash_label = $"../HUD/DashLabel"
@onready var bpm_label = get_node_or_null("../HUD/BPMLabel")

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
	
	# BPM: активный кровавый сёрф (слайд по луже крови): +3 BPM/сек
	if is_instance_valid(player) and player.is_sliding and player.is_on_blood:
		add_bpm(3.0 * delta)
	else:
		time_since_bpm_gain += delta
		
	# BPM: пассивный спад к 50.0 при отсутствии событий роста за последние 2 секунды: -4 BPM/сек
	if time_since_bpm_gain >= 2.0 and bpm > MIN_BPM:
		bpm = max(MIN_BPM, bpm - 4.0 * delta)
		
	# Индикация BPM в HUD
	if bpm_label:
		bpm_label.text = "BPM: %d (%s)" % [int(round(bpm)), get_bpm_tier()]
	
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

func add_bpm(amount: float):
	if amount <= 0.0:
		return
	bpm = clamp(bpm + amount, MIN_BPM, MAX_BPM)
	time_since_bpm_gain = 0.0

func record_kill_bpm(weapon_type: String, is_shockwave: bool = false) -> float:
	var base_bpm: float = 12.0 if is_shockwave else 8.0
	var bonus_bpm: float = 0.0
	
	# Бонус за разнообразие (+3 BPM), если оружие отличается от предыдущего убийства
	if last_kill_weapon != "" and weapon_type != "" and weapon_type != last_kill_weapon:
		bonus_bpm = 3.0
		print("[BPM VARIETY BONUS] +3.0 BPM! Killer: '%s' != previous: '%s' (Total: +%.1f BPM)" % [
			weapon_type, last_kill_weapon, base_bpm + bonus_bpm
		])
	elif last_kill_weapon != "" and weapon_type == last_kill_weapon:
		print("[BPM KILL] Same weapon '%s' (Total: +%.1f BPM, no variety bonus)" % [weapon_type, base_bpm])
	else:
		print("[BPM KILL] First kill with '%s' (Total: +%.1f BPM)" % [weapon_type, base_bpm])
		
	if weapon_type != "":
		last_kill_weapon = weapon_type
		
	var total_bpm = base_bpm + bonus_bpm
	add_bpm(total_bpm)
	return total_bpm

func drop_bpm_on_damage():
	# Резкое падение при получении урона игроком: -25% от текущего значения (не фиксированное число)
	var drop = bpm * 0.25
	bpm = max(MIN_BPM, bpm - drop)
	print("[BPM] Damage penalty: -%.1f -> %.1f (%s)" % [drop, bpm, get_bpm_tier()])

func get_bpm_tier() -> String:
	if bpm < 90.0:
		return "CALM"
	elif bpm < 140.0:
		return "PUMPING"
	elif bpm < 180.0:
		return "SURGING"
	else:
		return "OVERDRIVE"

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

func process_slam(delta, vel: Vector3) -> Vector3:
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
		head.add_recoil(0.25, 0.0)
		vel.y = 0
		slam_timer = SLAM_CD
		AudioManager.play_sound("slam_impact")
		
		var enemies = player.get_tree().get_nodes_in_group("enemy")
		for e in enemies:
			if is_instance_valid(e):
				if player.global_position.distance_to(e.global_position) <= SLAM_AOE:
					e.take_damage(SLAM_DMG, (e.global_position - player.global_position).normalized(), e.global_position, true, false, true, false, -1, "melee")
					
	if is_slamming:
		vel.y = -SLAM_SPEED
		vel.x = 0
		vel.z = 0
		
	return vel
