extends Node3D

const MOUSE_SENSITIVITY = 0.003
const BASE_FOV = 90.0
const MAX_CAM_ROLL = 0.06
const WALK_SPEED = 10.0

var camera_recoil = 0.0
var bob_time = 0.0
var wallrun_bob_time = 0.0
var landing_dip = 0.0
var landing_shake_trauma = 0.0
var slide_tween: Tween

@onready var player = $".."
@onready var camera = $Camera3D
@onready var raycast = $Camera3D/RayCast3D

@onready var revolver_model = $Camera3D/Revolver
@onready var shotgun_model = $Camera3D/Shotgun
@onready var injector_model = get_node_or_null("Camera3D/Injector")
@onready var smg_model = get_node_or_null("Camera3D/SewingMachine")
@onready var left_arm = $Camera3D/LeftArm

var active_weapon: Node3D
var weapon_default_pos = Vector3(0.35, -0.22, -0.46)
var left_arm_default_pos = Vector3(-0.36, -0.30, -0.24)
var melee_arm_tween: Tween
var muzzle_flash_tween: Tween

func _ready():
	camera.fov = BASE_FOV
	# Отключаем отбрасывание теней для всего view-model слоя (оружие и руки)
	_disable_viewmodel_shadows(camera)
	
	# По умолчанию достаем Калибр-0
	active_weapon = revolver_model
	if shotgun_model:
		shotgun_model.visible = false
		shotgun_model.position = weapon_default_pos
		shotgun_model.rotation = Vector3.ZERO
	if injector_model:
		injector_model.visible = false
		injector_model.position = weapon_default_pos
		injector_model.rotation = Vector3.ZERO
	if revolver_model:
		revolver_model.visible = true
		revolver_model.position = weapon_default_pos
		revolver_model.rotation = Vector3.ZERO
	if left_arm:
		left_arm.visible = false
		left_arm.position = left_arm_default_pos
		left_arm.rotation = Vector3.ZERO
		
	# Инициализация дульных вспышек (star flare mesh + индивидуальные материалы)
	var star_mesh = _create_star_flash_mesh()
	for w in [revolver_model, shotgun_model, injector_model]:
		if w:
			var m = w.get_node_or_null("Muzzle")
			if m:
				var f: MeshInstance3D = m.get_node_or_null("FlashMesh")
				if f:
					f.mesh = star_mesh
					f.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
					var mat = f.get_surface_override_material(0)
					if mat:
						f.set_surface_override_material(0, mat.duplicate())
		
	# Настройка RayCast для обнаружения хитбоксов головы (Area3D)
	raycast.collide_with_areas = true
	raycast.collide_with_bodies = true
	raycast.add_exception(player)

func _disable_viewmodel_shadows(node: Node):
	if node is GeometryInstance3D:
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for child in node.get_children():
		_disable_viewmodel_shadows(child)

func _input(event):
	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		player.rotate_y(-event.relative.x * MOUSE_SENSITIVITY)
		rotate_x(-event.relative.y * MOUSE_SENSITIVITY)
		rotation.x = clamp(rotation.x, deg_to_rad(-89), deg_to_rad(89))

func switch_weapon_visual(index: int):
	if revolver_model:
		revolver_model.visible = (index == 0)
	if shotgun_model:
		shotgun_model.visible = (index == 1)
	if injector_model:
		injector_model.visible = (index == 2)
	if smg_model:
		smg_model.visible = (index == 3)
		
	if index == 0:
		active_weapon = revolver_model
	elif index == 1:
		active_weapon = shotgun_model
	elif index == 2:
		active_weapon = injector_model
	elif index == 3:
		active_weapon = smg_model if smg_model else null
		
	if active_weapon:
		active_weapon.position = weapon_default_pos
		active_weapon.rotation = Vector3.ZERO

func add_recoil(cam_amount: float, weapon_kick: float = 0.2):
	camera_recoil -= cam_amount
	if active_weapon:
		active_weapon.position.z += weapon_kick
		active_weapon.rotation.x += weapon_kick * 1.5

func trigger_hard_landing(impact_speed: float, threshold: float = 12.0):
	var excess = max(0.0, impact_speed - threshold)
	var intensity = clamp(excess / 16.0, 0.0, 1.0)
	# Короткий "присед" камеры вниз: 0.16..0.32 м
	landing_dip = lerp(0.16, 0.32, intensity)
	# Тряска экрана, пропорциональная силе удара
	landing_shake_trauma = lerp(0.4, 0.9, intensity)
	# Импульс отдачи/наклона головы вниз
	add_recoil(lerp(0.04, 0.10, intensity), 0.0)

func trigger_melee_impact(is_execute: bool = false):
	# Экранный толчок/тряска камеры при успешном попадании ближнего боя
	var trauma = 0.65 if is_execute else 0.38
	landing_shake_trauma = max(landing_shake_trauma, trauma)
	# Импульс отдачи оружия и наклон камеры вверх
	add_recoil(0.09 if is_execute else 0.05, 0.45 if is_execute else 0.25)

func play_melee_animation():
	if not left_arm:
		return
	if melee_arm_tween:
		melee_arm_tween.kill()
		
	left_arm.visible = true
	left_arm.position = Vector3(-0.36, -0.26, -0.22)
	left_arm.rotation = Vector3(deg_to_rad(10), deg_to_rad(24), deg_to_rad(-10))
	
	melee_arm_tween = create_tween()
	# Хлесткий выпад кулаком слева (широкая постановка рук по краям экрана)
	var punch_pos = Vector3(-0.20, -0.14, -0.40)
	var punch_rot = Vector3(deg_to_rad(-4), deg_to_rad(-6), deg_to_rad(14))
	
	melee_arm_tween.tween_property(left_arm, "position", punch_pos, 0.065).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	melee_arm_tween.parallel().tween_property(left_arm, "rotation", punch_rot, 0.065)
	
	# Небольшое смещение оружия вправо при ударе кулаком
	if active_weapon:
		var w_tween = create_tween()
		w_tween.tween_property(active_weapon, "position:y", weapon_default_pos.y - 0.05, 0.065)
		w_tween.parallel().tween_property(active_weapon, "position:x", weapon_default_pos.x + 0.04, 0.065)
		w_tween.chain().tween_property(active_weapon, "position", weapon_default_pos, 0.14).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	
	# Задержка на пике удара + плавный возврат назад в левый нижний угол
	melee_arm_tween.chain().tween_interval(0.035)
	melee_arm_tween.chain().tween_property(left_arm, "position", left_arm_default_pos, 0.11).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	melee_arm_tween.parallel().tween_property(left_arm, "rotation", Vector3(deg_to_rad(10), deg_to_rad(24), deg_to_rad(-10)), 0.11)
	melee_arm_tween.chain().tween_callback(func():
		left_arm.visible = false
	)

func trigger_slide_animation(is_sliding: bool):
	if slide_tween: slide_tween.kill()
	slide_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	if is_sliding:
		slide_tween.tween_property(self, "position:y", 0.0, 0.08)
	else:
		slide_tween.tween_property(self, "position:y", 0.6, 0.2)

func get_aim_raycast(spread: float = 0.0) -> RayCast3D:
	# Базовая дистанция стрельбы - 100 метров вперед по оси Z
	var target = Vector3(0, 0, -100)
	
	if spread > 0.0:
		# Добавляем случайное отклонение для разброса дроби
		target.x += randf_range(-spread, spread) * 100.0
		target.y += randf_range(-spread, spread) * 100.0
		
	raycast.target_position = target
	raycast.force_raycast_update()
	return raycast

func get_aim_direction() -> Vector3:
	return -camera.global_transform.basis.z.normalized()

func get_muzzle_position() -> Vector3:
	if active_weapon:
		var m = active_weapon.get_node_or_null("Muzzle")
		if m:
			return m.global_position
		return active_weapon.global_position - active_weapon.global_transform.basis.z * 0.35 + active_weapon.global_transform.basis.y * 0.05
	return camera.global_position + camera.global_transform.basis * Vector3(0.35, -0.18, -0.46)

func trigger_muzzle_flash(is_shotgun: bool = false):
	if not active_weapon:
		return
	var muzzle = active_weapon.get_node_or_null("Muzzle")
	if not muzzle:
		return
		
	var light: OmniLight3D = muzzle.get_node_or_null("MuzzleLight")
	var flash: MeshInstance3D = muzzle.get_node_or_null("FlashMesh")
	
	if muzzle_flash_tween:
		muzzle_flash_tween.kill()
		
	muzzle_flash_tween = create_tween()
	muzzle_flash_tween.set_parallel(true)
	
	if light:
		light.visible = true
		var target_energy = 9.5 if is_shotgun else 7.5
		light.light_energy = target_energy
		muzzle_flash_tween.tween_property(light, "light_energy", 0.0, 0.065).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		
	if flash:
		flash.visible = true
		flash.rotation.z = randf_range(0.0, TAU)
		var base_scale = Vector3(1.3, 1.3, 1.3) if is_shotgun else Vector3(0.95, 0.95, 0.95)
		flash.scale = base_scale * randf_range(0.85, 1.15)
		var mat = flash.get_surface_override_material(0)
		if mat:
			mat.albedo_color.a = 0.95
			muzzle_flash_tween.tween_property(mat, "albedo_color:a", 0.0, 0.065).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			
	muzzle_flash_tween.chain().tween_callback(func():
		if light: light.visible = false
		if flash: flash.visible = false
	)

func _create_star_flash_mesh() -> ArrayMesh:
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var center = Vector3.ZERO
	var points = 8
	var r_outer = 0.18
	var r_inner = 0.035
	for i in range(points):
		var a1 = (float(i) / float(points)) * TAU
		var a_mid = (float(i) + 0.5) / float(points) * TAU
		var a2 = (float(i + 1) / float(points)) * TAU
		
		var p1 = Vector3(cos(a1) * r_inner, sin(a1) * r_inner, 0.0)
		var p_tip = Vector3(cos(a_mid) * r_outer, sin(a_mid) * r_outer, 0.0)
		var p2 = Vector3(cos(a2) * r_inner, sin(a2) * r_inner, 0.0)
		
		# Лицевая сторона к камере
		st.add_vertex(center)
		st.add_vertex(p_tip)
		st.add_vertex(p1)
		
		st.add_vertex(center)
		st.add_vertex(p2)
		st.add_vertex(p_tip)
	return st.commit()

func update_visuals(delta: float, current_speed: float, is_on_floor: bool, is_sliding: bool, is_dashing: bool, input_dir: Vector2, is_reloading: bool, wallrun_side: float = 0.0):
	if active_weapon:
		if not is_reloading:
			active_weapon.position = active_weapon.position.lerp(weapon_default_pos, 15.0 * delta)
		else:
			var reload_pos = weapon_default_pos + Vector3(0.0, -0.35, 0.0)
			active_weapon.position = active_weapon.position.lerp(reload_pos, 10.0 * delta)
			
		active_weapon.rotation.x = lerp(active_weapon.rotation.x, 0.0, 15.0 * delta)
		active_weapon.rotation.y = lerp(active_weapon.rotation.y, 0.0, 15.0 * delta)
		active_weapon.rotation.z = lerp(active_weapon.rotation.z, 0.0, 15.0 * delta)
	
	camera_recoil = lerp(camera_recoil, 0.0, 10.0 * delta)
	camera.rotation.x = camera_recoil

	# Усиленный динамический FOV от скорости (откалиброван под 10-20 м/с)
	var speed_over = max(0.0, current_speed - 8.0)
	var fov_offset = clamp(speed_over * 3.5, 0.0, 42.0)
	camera.fov = lerp(camera.fov, BASE_FOV + fov_offset, 12.0 * delta)

	var target_bob_y = 0.0
	var target_bob_x = 0.0

	if wallrun_side != 0.0:
		# Тряска камеры при wallrun: шаги по стене чуть заметнее, чем при обычной ходьбе, но умеренные
		wallrun_bob_time += delta * current_speed * 2.0
		target_bob_y = sin(wallrun_bob_time) * 0.11
		target_bob_x = cos(wallrun_bob_time * 0.5) * 0.07
	elif is_on_floor and not is_sliding and not is_dashing and current_speed > 1.0:
		bob_time += delta * current_speed * 1.8
		target_bob_y = sin(bob_time) * 0.08
		target_bob_x = cos(bob_time * 0.5) * 0.05

	# Применяем опускание камеры ("присед") при жестком приземлении
	target_bob_y -= landing_dip
	# Плавный возврат приседа камеры к норме (~0.12-0.15 сек)
	landing_dip = move_toward(landing_dip, 0.0, 2.0 * delta)

	camera.position.y = lerp(camera.position.y, target_bob_y, 16.0 * delta)
	camera.position.x = lerp(camera.position.x, target_bob_x, 14.0 * delta)
		
	var roll_target = -input_dir.x * MAX_CAM_ROLL
	if is_sliding: roll_target *= 1.5
	if wallrun_side != 0.0:
		# Наклон камеры (roll) К СТЕНЕ: если стена слева (-1), крен влево (-); если справа (+1), крен вправо (+)
		roll_target = wallrun_side * (MAX_CAM_ROLL * 2.5)
	camera.rotation.z = lerp(camera.rotation.z, roll_target, 8.0 * delta)

	# Дополнительная тряска экрана (screen shake) при жестком приземлении
	if landing_shake_trauma > 0.0:
		var trauma_p = landing_shake_trauma * landing_shake_trauma
		camera.position.x += randf_range(-1.0, 1.0) * trauma_p * 0.05
		camera.position.y += randf_range(-1.0, 1.0) * trauma_p * 0.05
		camera.rotation.z += randf_range(-1.0, 1.0) * trauma_p * 0.035
		landing_shake_trauma = move_toward(landing_shake_trauma, 0.0, 4.5 * delta)
