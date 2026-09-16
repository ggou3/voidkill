class_name EnemyHunter
extends "res://enemy.gd"

## Враг "Охотник" (Hunter Enemy).
## Элитный преследователь (1.15x масштаб), реагирующий на пульс (BPM) игрока.
## В состоянии IDLE до достижения BPM тира SURGING (140+).
## При BPM >= 140 немедленно начинает всеведущую охоту через всю арену.
## Скорость (13 -> 20 м/с) и урон (20 -> 35 HP) непрерывно скейлятся от BPM (140..200).
## Прожилки и серебристые глаза пульсируют в такт сердцебиению игрока.
## Иммунен к Fear Chain (никогда не входит в State.FLEE).

@export var hunter_max_health: int = 180
@export var base_hunter_speed: float = 13.0
@export var max_hunter_speed: float = 20.0
@export var base_hunter_damage: int = 20
@export var max_hunter_damage: int = 35
@export var surging_threshold: float = 140.0
@export var deactivation_timeout: float = 5.0

var below_surging_timer: float = 0.0
var pulse_time: float = 0.0
var is_hunting: bool = false

var vein_materials: Array[StandardMaterial3D] = []
var hunter_eyes_material: StandardMaterial3D = null

@onready var eyes_mesh_inst: MeshInstance3D = get_node_or_null("Eyes")
@onready var vein_light: OmniLight3D = get_node_or_null("VeinLight")

const SILVER_WHITE_COLOR = Color(0.88, 0.95, 1.0)

func _ready():
	super._ready()
	max_health = hunter_max_health
	health = hunter_max_health
	attack_damage = base_hunter_damage
	move_speed = base_hunter_speed
	acceleration = 8.0
	attack_range = 2.2
	lunge_cooldown_timer = 999999.0
	
	scale = Vector3(1.15, 1.15, 1.15)
	
	# Настройка серебристых глаз
	if eyes_mesh_inst:
		var e_mat = eyes_mesh_inst.get_surface_override_material(0)
		if e_mat:
			hunter_eyes_material = e_mat.duplicate()
			eyes_mesh_inst.set_surface_override_material(0, hunter_eyes_material)
		else:
			hunter_eyes_material = StandardMaterial3D.new()
			hunter_eyes_material.emission_enabled = true
			hunter_eyes_material.emission = SILVER_WHITE_COLOR
			hunter_eyes_material.emission_energy_multiplier = 1.5
			eyes_mesh_inst.set_surface_override_material(0, hunter_eyes_material)
			
	# Сбор всех прожилок по телу и дублирование их материалов
	for child in get_children():
		if child is MeshInstance3D and child.name.begins_with("Vein"):
			var v_mat = child.get_surface_override_material(0)
			if v_mat:
				var dup_mat = v_mat.duplicate()
				child.set_surface_override_material(0, dup_mat)
				vein_materials.append(dup_mat)

func _can_lunge_to_player() -> bool:
	return false

func start_lunge():
	pass

func _process_fear_chain_check(_delta: float):
	# Охотник бесстрашен и игнорирует панику Overdrive / Fear Chain
	pass

func set_state(new_state: State):
	# Охотник никогда не спасается бегством
	if new_state == State.FLEE:
		return
	super.set_state(new_state)

func _on_detection_area_body_entered(body: Node3D):
	if body.is_in_group("player"):
		var bpm = _get_player_bpm()
		# Входит в погоню от DetectionArea только если BPM уже разогнан до SURGING+ или если уже охотится
		if bpm >= surging_threshold or is_hunting:
			if current_state == State.IDLE:
				start_chase(body)

func _get_player_bpm() -> float:
	var player = target_player if is_instance_valid(target_player) else get_tree().get_first_node_in_group("player")
	if is_instance_valid(player) and "skills" in player and is_instance_valid(player.skills) and "bpm" in player.skills:
		return player.skills.bpm
	return 50.0

func _physics_process(delta: float):
	if current_state == State.DEAD:
		super._physics_process(delta)
		return
		
	pulse_time += delta
	var player = target_player if is_instance_valid(target_player) else get_tree().get_first_node_in_group("player")
	var player_bpm = _get_player_bpm()
	
	# Непрерывный скейлинг скорости и урона от BPM в диапазоне [140, 200]
	var bpm_factor = clampf((player_bpm - surging_threshold) / 60.0, 0.0, 1.0)
	move_speed = lerp(base_hunter_speed, max_hunter_speed, bpm_factor)
	attack_damage = int(round(lerp(float(base_hunter_damage), float(max_hunter_damage), bpm_factor)))
	acceleration = lerp(8.0, 16.0, bpm_factor)
	
	# Логика активации/деактивации охоты
	if player_bpm >= surging_threshold:
		below_surging_timer = 0.0
		if not is_hunting:
			is_hunting = true
			AudioManager.play_sound("hunter_awaken")
			GameTypes.debug_log(&"enemy", "[%s] HUNTER AWAKENED by Surging BPM (%.1f)! Relentless pursuit engaged." % [name, player_bpm])
			
		if is_instance_valid(player) and not ("is_dead" in player and player.is_dead):
			if current_state == State.IDLE:
				start_chase(player)
				
			# Всеведущее отслеживание игрока через любые преграды/дистанции
			unreachable_timer = 0.0
			target_player = player
	else:
		# BPM упал ниже 140
		if current_state == State.CHASE or is_hunting:
			below_surging_timer += delta
			if below_surging_timer >= deactivation_timeout:
				GameTypes.debug_log(&"enemy", "[%s] HUNTER LOST TRACK: BPM below 140 for %.1fs. Returning to IDLE." % [name, below_surging_timer])
				is_hunting = false
				below_surging_timer = 0.0
				set_state(State.IDLE)
				target_player = null
				velocity.x = 0.0
				velocity.z = 0.0
				
	_update_pulse_visuals(player_bpm, bpm_factor)
	super._physics_process(delta)

func _update_pulse_visuals(player_bpm: float, bpm_factor: float):
	# Синхронизация пульсации прожилок точно в такт сердцебиению игрока
	var heartbeat_rad_sec = (max(50.0, player_bpm) / 60.0) * TAU
	var pulse = 0.5 + 0.5 * sin(pulse_time * heartbeat_rad_sec)
	
	var eye_energy: float
	var vein_energy: float
	
	if player_bpm >= surging_threshold:
		# Накаляющееся серебристо-платиновое сияние
		eye_energy = lerp(2.5, 6.5, bpm_factor) + pulse * lerp(0.8, 2.5, bpm_factor)
		vein_energy = lerp(1.8, 5.5, bpm_factor) + pulse * lerp(0.6, 2.2, bpm_factor)
	else:
		# Латентный полудремлющий режим
		var idle_t = clampf((player_bpm - 50.0) / 90.0, 0.0, 1.0)
		eye_energy = lerp(0.4, 1.4, idle_t) + pulse * 0.3
		vein_energy = lerp(0.1, 0.6, idle_t) + pulse * 0.2
		
	if hunter_eyes_material:
		hunter_eyes_material.emission_energy_multiplier = eye_energy
		
	for mat in vein_materials:
		if is_instance_valid(mat):
			mat.emission_energy_multiplier = vein_energy
			
	if vein_light:
		vein_light.light_energy = vein_energy * 0.6
