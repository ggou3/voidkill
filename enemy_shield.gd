extends "res://enemy.gd"

## Враг "Щитоносец" (Shield Enemy).
## Оснащён массивной фронтальной бронеплитой (1.2м × 1.8м).
## Блокирует 85% входящего урона во фронтальном секторе 90 градусов (±45° от направления взгляда).
## Полностью уязвим для атак с флангов и тыла.

@export var block_reduction: float = 0.85 # 85% снижения урона при фронтальном блоке
@export var block_state_duration: float = 1.5 # Длительность визуального состояния блока

var block_state_timer: float = 0.0

var barrier_material: StandardMaterial3D = null
var indicator_mat_left: StandardMaterial3D = null
var indicator_mat_right: StandardMaterial3D = null

var barrier_tween: Tween = null
var indicator_tween: Tween = null

@onready var shield_plate: MeshInstance3D = get_node_or_null("ShieldPlate")
@onready var shield_barrier: MeshInstance3D = get_node_or_null("ShieldBarrier")
@onready var damage_indicator_left: MeshInstance3D = get_node_or_null("DamageIndicatorLeft")
@onready var damage_indicator_right: MeshInstance3D = get_node_or_null("DamageIndicatorRight")

const INDICATOR_IDLE_COLOR = Color(0.3, 0.05, 0.05)
const INDICATOR_FLASH_COLOR = Color(1.0, 0.1, 0.1)

func _ready():
	super._ready()
	# Щитоносец использует стандартную ближнюю атаку, но НЕ использует LUNGE-выпад
	lunge_cooldown_timer = 999999.0
	
	# Дублируем материалы для независимой анимации каждого экземпляра
	if shield_barrier:
		var b_mat = shield_barrier.get_surface_override_material(0)
		if b_mat:
			barrier_material = b_mat.duplicate()
			shield_barrier.set_surface_override_material(0, barrier_material)
		shield_barrier.visible = false
		shield_barrier.position.y = -0.45
		shield_barrier.scale = Vector3(0.6, 0.1, 0.6)
		
	if damage_indicator_left:
		var ind_mat = damage_indicator_left.get_surface_override_material(0)
		if ind_mat:
			indicator_mat_left = ind_mat.duplicate()
			damage_indicator_left.set_surface_override_material(0, indicator_mat_left)
			
	if damage_indicator_right:
		var ind_mat = damage_indicator_right.get_surface_override_material(0)
		if ind_mat:
			indicator_mat_right = ind_mat.duplicate()
			damage_indicator_right.set_surface_override_material(0, indicator_mat_right)

func _can_lunge_to_player() -> bool:
	# Щитоносец не совершает прыжков-выпадов LUNGE
	return false

func start_lunge():
	# Блокировка LUNGE
	pass

func _physics_process(delta: float):
	super._physics_process(delta)
	if current_state == State.DEAD:
		return
		
	if block_state_timer > 0.0:
		block_state_timer -= delta
		if block_state_timer <= 0.0:
			_hide_barrier()

func is_damage_blocked(hit_pos: Vector3, knockback_vector: Vector3) -> bool:
	var forward_dir = -global_transform.basis.z
	forward_dir.y = 0.0
	if forward_dir.length_squared() < 0.001:
		forward_dir = Vector3.FORWARD
	else:
		forward_dir = forward_dir.normalized()
		
	# Определение направления на источник урона (откуда пришла атака)
	var attack_incoming_dir = Vector3.ZERO
	
	# 1. Приоритет — обратный вектор отброса (knockback направлен от стрелка к цели)
	if knockback_vector.length_squared() > 0.01:
		var flat_kb = Vector3(knockback_vector.x, 0.0, knockback_vector.z)
		if flat_kb.length_squared() > 0.01:
			attack_incoming_dir = -flat_kb.normalized()
			
	# 2. Если knockback отсутствует (или строго вертикальный), берём направление на игрока
	if attack_incoming_dir == Vector3.ZERO:
		var player = target_player if is_instance_valid(target_player) else get_tree().get_first_node_in_group("player")
		if is_instance_valid(player):
			var to_player = player.global_position - global_position
			to_player.y = 0.0
			if to_player.length_squared() > 0.01:
				attack_incoming_dir = to_player.normalized()
				
	# 3. Дополнительная проверка по точке контакта hit_pos
	if attack_incoming_dir == Vector3.ZERO and hit_pos != Vector3.ZERO:
		var to_hit = hit_pos - global_position
		to_hit.y = 0.0
		if to_hit.length_squared() > 0.01:
			attack_incoming_dir = to_hit.normalized()
			
	# Если вектор определить не удалось — по умолчанию считаем фронтальным
	if attack_incoming_dir == Vector3.ZERO:
		return true
		
	# Угол между взглядом врага и атакующим:
	# Фронтальный сектор 90 градусов (полуугол 45°: cos(45°) ≈ 0.7071)
	var dot = forward_dir.dot(attack_incoming_dir)
	return dot >= 0.7071

func take_damage(amount: int, knockback_vector: Vector3, hit_pos: Vector3, is_melee: bool = false, is_execute: bool = false, is_shockwave: bool = false, is_headshot: bool = false, source_chain_depth: int = -1, weapon_source: String = ""):
	if current_state == State.DEAD:
		return
		
	var blocked = is_damage_blocked(hit_pos, knockback_vector)
	var final_amount = amount
	var final_knockback = knockback_vector
	var final_headshot = is_headshot
	
	if blocked:
		# Фронтальный блок: урон снижается на 85%
		final_amount = max(1, int(round(float(amount) * (1.0 - block_reduction)))) if amount > 0 else 0
		final_knockback = knockback_vector * 0.25 # Бронеплита поглощает импульс
		final_headshot = false # Бронеплита закрывает голову с фронта
		_trigger_block_reaction(hit_pos)
	else:
		# Пробитие с фланга или тыла: полный урон + вспышка индикаторов пробития
		_trigger_flank_damage_reaction()
		
	super.take_damage(final_amount, final_knockback, hit_pos, is_melee, is_execute, is_shockwave, final_headshot, source_chain_depth, weapon_source)

func _trigger_block_reaction(hit_pos: Vector3):
	AudioManager.play_sound("shield_block")
	block_state_timer = block_state_duration
	_show_barrier()
	_spawn_spark_vfx(hit_pos)

func _show_barrier():
	if not shield_barrier:
		return
	shield_barrier.visible = true
	
	if barrier_tween and barrier_tween.is_valid():
		barrier_tween.kill()
		
	barrier_tween = create_tween().set_parallel(true)
	# Поднятие энергетического щита перед корпусом
	barrier_tween.tween_property(shield_barrier, "position:y", 0.08, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	barrier_tween.tween_property(shield_barrier, "scale", Vector3(1.0, 1.0, 1.0), 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	
	if barrier_material:
		barrier_tween.tween_property(barrier_material, "albedo_color:a", 0.42, 0.1)
		barrier_tween.tween_property(barrier_material, "emission_energy_multiplier", 3.2, 0.1)
		barrier_tween.chain().tween_property(barrier_material, "emission_energy_multiplier", 2.0, 0.3)

func _hide_barrier():
	if not shield_barrier:
		return
		
	if barrier_tween and barrier_tween.is_valid():
		barrier_tween.kill()
		
	barrier_tween = create_tween().set_parallel(true)
	barrier_tween.tween_property(shield_barrier, "position:y", -0.45, 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	barrier_tween.tween_property(shield_barrier, "scale", Vector3(0.6, 0.1, 0.6), 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	if barrier_material:
		barrier_tween.tween_property(barrier_material, "albedo_color:a", 0.0, 0.25)
	barrier_tween.chain().tween_callback(func():
		if shield_barrier and block_state_timer <= 0.0:
			shield_barrier.visible = false
	)

func _trigger_flank_damage_reaction():
	if indicator_tween and indicator_tween.is_valid():
		indicator_tween.kill()
		
	indicator_tween = create_tween().set_parallel(true)
	if indicator_mat_left:
		indicator_mat_left.emission = INDICATOR_FLASH_COLOR
		indicator_mat_left.emission_energy_multiplier = 4.5
		indicator_tween.tween_property(indicator_mat_left, "emission", INDICATOR_IDLE_COLOR, 0.45)
		indicator_tween.tween_property(indicator_mat_left, "emission_energy_multiplier", 0.4, 0.45)
		
	if indicator_mat_right:
		indicator_mat_right.emission = INDICATOR_FLASH_COLOR
		indicator_mat_right.emission_energy_multiplier = 4.5
		indicator_tween.tween_property(indicator_mat_right, "emission", INDICATOR_IDLE_COLOR, 0.45)
		indicator_tween.tween_property(indicator_mat_right, "emission_energy_multiplier", 0.4, 0.45)

func _spawn_spark_vfx(hit_pos: Vector3):
	var scene_root = get_tree().current_scene if (get_tree() and get_tree().current_scene) else get_parent()
	if not scene_root:
		return
	var spark = MeshInstance3D.new()
	var sphere = SphereMesh.new()
	sphere.radius = 0.14
	sphere.height = 0.28
	spark.mesh = sphere
	
	var mat = StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.9, 0.4, 0.9)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.95, 0.6)
	mat.emission_energy_multiplier = 5.0
	spark.material_override = mat
	
	scene_root.add_child(spark)
	var spawn_pt = hit_pos if hit_pos != Vector3.ZERO else (global_position + (-global_transform.basis.z * 0.5) + Vector3(0, 0.2, 0))
	spark.global_position = spawn_pt
	
	var tw = spark.create_tween().set_parallel(true)
	tw.tween_property(spark, "scale", Vector3(2.2, 2.2, 2.2), 0.14).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.14).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(spark.queue_free)

func die():
	if barrier_tween and barrier_tween.is_valid():
		barrier_tween.kill()
	if indicator_tween and indicator_tween.is_valid():
		indicator_tween.kill()
	if shield_barrier:
		shield_barrier.visible = false
	super.die()
