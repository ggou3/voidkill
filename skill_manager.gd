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

@export var blood_buff_duration: float = 7.0 # Длительность активного кровавого баффа (было 5.0 сек)
const BLOOD_DUR = 7.0

var dashes = MAX_DASH
var dash_timer_cd = 0.0
var dash_interval_timer = 0.0
var is_dashing = false
var dash_timer = 0.0
var dash_dir = Vector3.ZERO
var dash_current_speed: float = 16.0

var is_slamming = false
var slam_timer = 0.0
var blood_timer = 0.0

@onready var player = $".."
@onready var head = $"../Head"
@onready var slam_ray = $"../SlamRay"
@onready var dash_label = $"../HUD/DashLabel"

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

	# Таймер минимального интервала между дэшами
	if dash_interval_timer > 0.0:
		dash_interval_timer -= delta
			
	if slam_timer > 0: slam_timer -= delta
	if blood_timer > 0: blood_timer -= delta
	
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

func activate_blood_buff():
	blood_timer = blood_buff_duration

func has_blood_buff() -> bool:
	return blood_timer > 0

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
				hit.take_damage(100, Vector3.DOWN, hit.global_position)
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
					e.take_damage(SLAM_DMG, (e.global_position - player.global_position).normalized(), e.global_position)
					
	if is_slamming:
		vel.y = -SLAM_SPEED
		vel.x = 0
		vel.z = 0
		
	return vel
