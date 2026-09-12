extends Node

var current_weapon_index = 0
var is_reloading = false
var is_bursting = false
var fire_timers = [0.0, 0.0]
var passive_reload_timers = [0.0, 0.0]
var active_reload_timer = 0.0

var weapons = [
	{
		"name": "КАЛИБР-0",
		"max_ammo": 4,
		"damage": 70,
		"pellets": 1,
		"spread": 0.0,
		"fire_rate": 1.0, # Ровно 1.0 секунда между выстрелами
		"reload_time": 1.1,
		"cam_shake": 0.09,
		"weapon_kick": 0.35,
		"knockback": 4.5,   # Толчок от пули крупного калибра
		"upward_kick": 0.0, # Не подбрасывает вверх
		"headshot_multiplier": 2.2, # Хедшот: 70 * 2.2 = 154 урона (ваншот)
		"air_multiplier": 2.0,      # Бонус x2 по воздушным целям (стакается с хедшотом)
		"alt_burst_interval": 0.12, # Увеличенный интервал между выстрелами ПКМ залпа (различимая очередь)
		"alt_spread": 0.06,         # Разброс пуль в залпе ПКМ
		"has_vacuum": true,
		"vacuum_radius": 2.0,
		"vacuum_force": 16.0
	},
	{
		"name": "SHOTGUN",
		"max_ammo": 2,
		"damage": 12,
		"pellets": 8,
		"spread": 0.08,
		"fire_rate": 0.5,
		"reload_time": 1.5,
		"cam_shake": 0.12,
		"weapon_kick": 0.4,
		"knockback": 6.0,   # Сильный толчок назад
		"upward_kick": 7.0, # Подбрасывает в воздух
		"headshot_multiplier": 1.5,
		"air_multiplier": 1.0,
		"has_vacuum": false,
		"vacuum_radius": 0.0,
		"vacuum_force": 0.0
	}
]

var ammos = [4, 2]

@onready var head = $"../Head"
@onready var ammo_label = $"../HUD/AmmoLabel"
@onready var hud = $"../HUD"

var weapon_hud_container: VBoxContainer
var weapon_ui_slots: Array = []

func _ready():
	_setup_weapon_hud()

func _setup_weapon_hud():
	if not hud:
		return
		
	# Скрываем старый простой текстовый AmmoLabel
	if ammo_label:
		ammo_label.visible = false
		
	if hud.has_node("WeaponHUDList"):
		weapon_hud_container = hud.get_node("WeaponHUDList")
	else:
		weapon_hud_container = VBoxContainer.new()
		weapon_hud_container.name = "WeaponHUDList"
		weapon_hud_container.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
		weapon_hud_container.anchor_left = 1.0
		weapon_hud_container.anchor_top = 1.0
		weapon_hud_container.anchor_right = 1.0
		weapon_hud_container.anchor_bottom = 1.0
		weapon_hud_container.offset_left = -290.0
		weapon_hud_container.offset_top = -140.0
		weapon_hud_container.offset_right = -20.0
		weapon_hud_container.offset_bottom = -20.0
		weapon_hud_container.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		weapon_hud_container.grow_vertical = Control.GROW_DIRECTION_BEGIN
		weapon_hud_container.add_theme_constant_override("separation", 8)
		hud.add_child(weapon_hud_container)
		
	_rebuild_weapon_slots()

func _rebuild_weapon_slots():
	if not weapon_hud_container:
		return
	for child in weapon_hud_container.get_children():
		child.queue_free()
	weapon_ui_slots.clear()
	
	for i in range(weapons.size()):
		var w = weapons[i]
		
		var panel = PanelContainer.new()
		panel.custom_minimum_size = Vector2(270, 48)
		
		var margin = MarginContainer.new()
		margin.add_theme_constant_override("margin_left", 12)
		margin.add_theme_constant_override("margin_right", 12)
		margin.add_theme_constant_override("margin_top", 5)
		margin.add_theme_constant_override("margin_bottom", 5)
		panel.add_child(margin)
		
		var vbox = VBoxContainer.new()
		vbox.add_theme_constant_override("separation", 3)
		margin.add_child(vbox)
		
		var hbox = HBoxContainer.new()
		vbox.add_child(hbox)
		
		var name_label = Label.new()
		name_label.text = "[%d] %s" % [i + 1, w["name"]]
		name_label.add_theme_font_size_override("font_size", 15)
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hbox.add_child(name_label)
		
		var ammo_text = Label.new()
		ammo_text.text = "%d / %d" % [ammos[i], w["max_ammo"]]
		ammo_text.add_theme_font_size_override("font_size", 16)
		ammo_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		hbox.add_child(ammo_text)
		
		var pbar = ProgressBar.new()
		pbar.custom_minimum_size = Vector2(0, 4)
		pbar.show_percentage = false
		pbar.max_value = 100.0
		pbar.value = 100.0
		
		var pbar_bg = StyleBoxFlat.new()
		pbar_bg.bg_color = Color(0.1, 0.12, 0.14, 0.7)
		pbar_bg.set_corner_radius_all(2)
		pbar.add_theme_stylebox_override("background", pbar_bg)
		
		var pbar_fg = StyleBoxFlat.new()
		pbar_fg.bg_color = Color(0.2, 0.75, 1.0, 1.0)
		pbar_fg.set_corner_radius_all(2)
		pbar.add_theme_stylebox_override("fill", pbar_fg)
		
		vbox.add_child(pbar)
		
		weapon_hud_container.add_child(panel)
		
		weapon_ui_slots.append({
			"panel": panel,
			"name_label": name_label,
			"ammo_text": ammo_text,
			"pbar": pbar,
			"pbar_fg": pbar_fg
		})

func _process(delta):
	# Кулдауны скорострельности
	for i in range(fire_timers.size()):
		if fire_timers[i] > 0:
			fire_timers[i] -= delta

	# Активная перезарядка удерживаемого оружия
	if is_reloading:
		active_reload_timer -= delta
		if active_reload_timer <= 0.0:
			ammos[current_weapon_index] = weapons[current_weapon_index]["max_ammo"]
			is_reloading = false
			active_reload_timer = 0.0

	# Пассивная перезарядка неактивного оружия в фоне
	for i in range(weapons.size()):
		if i != current_weapon_index:
			if ammos[i] < weapons[i]["max_ammo"]:
				passive_reload_timers[i] += delta
				if passive_reload_timers[i] >= weapons[i]["reload_time"]:
					ammos[i] = weapons[i]["max_ammo"]
					passive_reload_timers[i] = 0.0
			else:
				passive_reload_timers[i] = 0.0

func switch_weapon(index: int):
	if is_bursting or index == current_weapon_index or index < 0 or index >= weapons.size():
		return
	# Прерываем активную перезарядку в руках — неактивное оружие дозарядится пассивно в фоне
	if is_reloading:
		is_reloading = false
		active_reload_timer = 0.0
	current_weapon_index = index
	head.switch_weapon_visual(index)

func update_hud(has_infinite_ammo: bool):
	if not weapon_hud_container:
		_setup_weapon_hud()
	if weapon_ui_slots.size() != weapons.size():
		_rebuild_weapon_slots()
		
	for i in range(weapons.size()):
		if i >= weapon_ui_slots.size():
			continue
		var w = weapons[i]
		var slot = weapon_ui_slots[i]
		var is_active = (i == current_weapon_index)
		
		var sb = StyleBoxFlat.new()
		if is_active:
			# Активное оружие: CS:GO стиль — янтарная плашка слева, яркий текст
			sb.bg_color = Color(0.12, 0.14, 0.18, 0.9)
			sb.border_color = Color(0.95, 0.72, 0.20, 1.0)
			sb.set_border_width_all(1)
			sb.border_width_left = 5
			sb.set_corner_radius_all(3)
			slot["panel"].add_theme_stylebox_override("panel", sb)
			
			slot["name_label"].text = "[%d] %s" % [i + 1, w["name"]]
			slot["name_label"].add_theme_color_override("font_color", Color(1.0, 0.88, 0.35, 1.0))
			
			if is_reloading:
				var progress = clamp((float(w["reload_time"]) - active_reload_timer) / float(w["reload_time"]), 0.0, 1.0)
				slot["ammo_text"].text = "RELOAD %d%%" % int(progress * 100.0)
				slot["ammo_text"].add_theme_color_override("font_color", Color(1.0, 0.6, 0.1, 1.0))
				slot["pbar"].visible = true
				slot["pbar"].value = progress * 100.0
				slot["pbar_fg"].bg_color = Color(0.95, 0.65, 0.15, 1.0) # Amber
			elif is_bursting:
				slot["ammo_text"].text = "%d / %d (BURST)" % [ammos[i], w["max_ammo"]]
				slot["ammo_text"].add_theme_color_override("font_color", Color(1.0, 0.3, 0.3, 1.0))
				slot["pbar"].visible = false
			elif has_infinite_ammo:
				slot["ammo_text"].text = "INF (BLOOD)"
				slot["ammo_text"].add_theme_color_override("font_color", Color(1.0, 0.2, 0.2, 1.0))
				slot["pbar"].visible = false
			else:
				slot["ammo_text"].text = "%d / %d" % [ammos[i], w["max_ammo"]]
				slot["ammo_text"].add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 1.0))
				slot["pbar"].visible = false
		else:
			# Неактивное оружие: приглушенный полупрозрачный слот
			sb.bg_color = Color(0.06, 0.07, 0.08, 0.55)
			sb.border_color = Color(0.25, 0.28, 0.32, 0.35)
			sb.set_border_width_all(1)
			sb.border_width_left = 2
			sb.set_corner_radius_all(3)
			slot["panel"].add_theme_stylebox_override("panel", sb)
			
			slot["name_label"].text = "[%d] %s" % [i + 1, w["name"]]
			slot["name_label"].add_theme_color_override("font_color", Color(0.65, 0.68, 0.72, 0.8))
			
			# Индикатор прогресса пассивной перезарядки спрятанного оружия
			if ammos[i] < w["max_ammo"]:
				var p_progress = clamp(passive_reload_timers[i] / float(w["reload_time"]), 0.0, 1.0)
				slot["ammo_text"].text = "%d / %d (%d%%)" % [ammos[i], w["max_ammo"], int(p_progress * 100.0)]
				slot["ammo_text"].add_theme_color_override("font_color", Color(0.3, 0.8, 1.0, 0.9)) # Cyan
				slot["pbar"].visible = true
				slot["pbar"].value = p_progress * 100.0
				slot["pbar_fg"].bg_color = Color(0.2, 0.75, 1.0, 0.9)
			else:
				slot["ammo_text"].text = "%d / %d" % [ammos[i], w["max_ammo"]]
				slot["ammo_text"].add_theme_color_override("font_color", Color(0.6, 0.6, 0.6, 0.7))
				slot["pbar"].visible = false

func shoot(has_infinite_ammo: bool):
	if is_reloading or is_bursting or fire_timers[current_weapon_index] > 0:
		return
	
	if ammos[current_weapon_index] <= 0:
		reload()
		return
		
	var w = weapons[current_weapon_index]
	if not has_infinite_ammo:
		ammos[current_weapon_index] -= 1
		
	fire_timers[current_weapon_index] = w["fire_rate"]
	_fire_pellets(current_weapon_index, -1.0, false)

func alt_shoot(_has_infinite_ammo: bool = false):
	# ПКМ — быстрый залп доступен для Калибр-0 (индекс 0)
	if current_weapon_index != 0:
		return
	if is_reloading or is_bursting or fire_timers[current_weapon_index] > 0:
		return
		
	# Залп ВСЕГДА расходует реальные патроны из барабана, даже во время активного кровавого баффа
	if ammos[current_weapon_index] <= 0:
		reload()
		return
		
	var shots_to_fire = ammos[current_weapon_index]
	_perform_burst(shots_to_fire)

func _perform_burst(shots_count: int):
	is_bursting = true
	var w = weapons[0]
	var burst_spread = float(w.get("alt_spread", 0.06))
	var burst_interval = float(w.get("alt_burst_interval", 0.12))
	
	for i in range(shots_count):
		if not is_instance_valid(self) or not is_inside_tree():
			is_bursting = false
			return
		if current_weapon_index != 0:
			break
			
		ammos[0] = max(0, ammos[0] - 1)
		_fire_pellets(0, burst_spread, true)
		
		if i < shots_count - 1:
			await get_tree().create_timer(burst_interval).timeout
			
	is_bursting = false
	ammos[0] = 0
	reload()

func _fire_pellets(weapon_idx: int, spread_override: float = -1.0, is_alt_fire: bool = false):
	var w = weapons[weapon_idx]
	var spread = spread_override if spread_override >= 0.0 else float(w.get("spread", 0.0))
	
	var cam_shake = float(w.get("cam_shake", 0.09))
	var weapon_kick = float(w.get("weapon_kick", 0.35))
	if is_alt_fire:
		cam_shake *= 0.75
		weapon_kick *= 0.75
		
	head.add_recoil(cam_shake, weapon_kick)
	head.trigger_muzzle_flash(weapon_idx == 1)
	
	if weapon_idx == 0:
		AudioManager.play_sound("revolver_shot")
	else:
		AudioManager.play_sound("shotgun_shot")
		
	var aim_dir = head.get_aim_direction()
	var start_pos = head.get_muzzle_position()
	var pellets_count = 1 if is_alt_fire else int(w.get("pellets", 1))
	
	for i in range(pellets_count):
		var ray = head.get_aim_raycast(spread)
		var hit_pos = ray.to_global(ray.target_position)
		var directly_hit_target: Node = null
		
		if ray.is_colliding():
			hit_pos = ray.get_collision_point()
			var hit = ray.get_collider()
			if hit != null:
				var target: Node = null
				var is_headshot: bool = false
				
				if hit.is_in_group("enemy_head") or hit.name == "HeadHitbox":
					is_headshot = true
					if hit.has_meta("enemy"):
						target = hit.get_meta("enemy")
					elif hit.get_parent():
						target = hit.get_parent()
				elif hit.has_method("take_damage"):
					target = hit
				elif hit.get_parent() and hit.get_parent().has_method("take_damage"):
					target = hit.get_parent()
					
				if target != null and target.has_method("take_damage"):
					directly_hit_target = target
					var flat_dir = Vector3(aim_dir.x, 0.0, aim_dir.z).normalized()
					var knockback_vector = flat_dir * float(w.get("knockback", 4.5))
					knockback_vector.y = float(w.get("upward_kick", 0.0))
					
					var is_airborne: bool = false
					if target.has_method("is_on_floor"):
						is_airborne = not target.is_on_floor()
					elif target.get_parent() and target.get_parent().has_method("is_on_floor"):
						is_airborne = not target.get_parent().is_on_floor()
						
					var base_dmg = float(w.get("damage", 70))
					var total_mult = 1.0
					
					if is_headshot:
						total_mult *= float(w.get("headshot_multiplier", 2.2))
					if is_airborne:
						total_mult *= float(w.get("air_multiplier", 2.0))
						
					var final_dmg = int(round(base_dmg * total_mult))
					
					if is_headshot and is_airborne:
						print("[%s] AIRBORNE HEADSHOT! (%.1fx) Damage: %d | Base: %d" % [target.name, total_mult, final_dmg, int(base_dmg)])
					elif is_airborne and float(w.get("air_multiplier", 1.0)) > 1.0:
						print("[%s] AIRBORNE HIT! (%.1fx) Damage: %d | Base: %d" % [target.name, total_mult, final_dmg, int(base_dmg)])
						
					target.take_damage(final_dmg, knockback_vector, hit_pos, false, false, false, is_headshot)
					
		if w.get("has_vacuum", false):
			spawn_bullet_tracer(start_pos, hit_pos)
			if not is_alt_fire:
				apply_vacuum_wake(start_pos, hit_pos, float(w.get("vacuum_radius", 2.0)), float(w.get("vacuum_force", 16.0)), directly_hit_target)

func spawn_bullet_tracer(start_pos: Vector3, end_pos: Vector3):
	var dir = end_pos - start_pos
	var dist = dir.length()
	if dist < 0.2:
		return
		
	var forward = dir / dist
	var up = Vector3.UP
	if abs(forward.dot(up)) > 0.92:
		up = Vector3.RIGHT
	var right = forward.cross(up).normalized()
	up = right.cross(forward).normalized()
	
	var mesh_inst = MeshInstance3D.new()
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	
	# 1. Тонкий яркий белый сердечник следа пули (r = 0.035)
	var r_core = 0.035
	st.add_vertex(start_pos - right * r_core)
	st.add_vertex(end_pos + right * r_core)
	st.add_vertex(end_pos - right * r_core)
	
	st.add_vertex(start_pos - right * r_core)
	st.add_vertex(start_pos + right * r_core)
	st.add_vertex(end_pos + right * r_core)
	
	st.add_vertex(start_pos - up * r_core)
	st.add_vertex(end_pos + up * r_core)
	st.add_vertex(end_pos - up * r_core)
	
	st.add_vertex(start_pos - up * r_core)
	st.add_vertex(start_pos + up * r_core)
	st.add_vertex(end_pos + up * r_core)
	
	# 2. Внешняя полупрозрачная оболочка вакуумного возмущения воздуха (r = 0.16)
	var r_outer = 0.16
	st.add_vertex(start_pos - right * r_outer)
	st.add_vertex(end_pos + right * r_outer)
	st.add_vertex(end_pos - right * r_outer)
	
	st.add_vertex(start_pos - right * r_outer)
	st.add_vertex(start_pos + right * r_outer)
	st.add_vertex(end_pos + right * r_outer)
	
	st.add_vertex(start_pos - up * r_outer)
	st.add_vertex(end_pos + up * r_outer)
	st.add_vertex(end_pos - up * r_outer)
	
	st.add_vertex(start_pos - up * r_outer)
	st.add_vertex(start_pos + up * r_outer)
	st.add_vertex(end_pos + up * r_outer)
	
	var mesh = st.commit()
	mesh_inst.mesh = mesh
	
	var mat = StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = Color(0.8, 0.92, 1.0, 0.85)
	mesh_inst.material_override = mat
	
	var scene_root = get_tree().current_scene if get_tree().current_scene else get_parent()
	if not scene_root:
		return
	scene_root.add_child(mesh_inst)
	mesh_inst.global_transform = Transform3D.IDENTITY
	
	var tween = create_tween()
	tween.tween_property(mat, "albedo_color:a", 0.0, 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_callback(mesh_inst.queue_free)

func apply_vacuum_wake(start_pos: Vector3, end_pos: Vector3, radius: float, force: float, excluded_target: Node = null):
	var line_vec = end_pos - start_pos
	var line_len_sq = line_vec.length_squared()
	if line_len_sq < 0.01:
		return
		
	var all_enemies = get_tree().get_nodes_in_group("enemy")
	for enemy in all_enemies:
		if not is_instance_valid(enemy) or enemy == excluded_target:
			continue
		if ("current_state" in enemy and enemy.current_state == enemy.State.DEAD) or ("health" in enemy and enemy.health <= 0):
			continue
			
		var enemy_pos = enemy.global_position + Vector3(0.0, 0.9, 0.0)
		var to_enemy = enemy_pos - start_pos
		var t = clamp(to_enemy.dot(line_vec) / line_len_sq, 0.0, 1.0)
		var closest_point = start_pos + line_vec * t
		
		var to_line = closest_point - enemy_pos
		var dist = to_line.length()
		
		if dist <= radius:
			var falloff = 1.0 - (dist / radius)
			var pull_dir = to_line.normalized() if dist > 0.05 else -enemy.global_transform.basis.z
			pull_dir.y = max(pull_dir.y, 0.15)
			pull_dir = pull_dir.normalized()
			
			var pull_impulse = pull_dir * (force * falloff)
			if enemy.has_method("apply_vacuum_pull"):
				enemy.apply_vacuum_pull(pull_impulse)
			elif "velocity" in enemy:
				enemy.velocity += pull_impulse

func reload():
	var w = weapons[current_weapon_index]
	if ammos[current_weapon_index] == w["max_ammo"] or is_reloading or is_bursting:
		return
	is_reloading = true
	active_reload_timer = float(w["reload_time"])
	AudioManager.play_sound("reload")
