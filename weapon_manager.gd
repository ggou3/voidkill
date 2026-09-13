extends Node

var current_weapon_index = 0
var is_reloading = false
var is_bursting = false
var fire_timers = [0.0, 0.0, 0.0]
var passive_reload_timers = [0.0, 0.0, 0.0]
var active_reload_timer = 0.0

var anvil_alt_cooldown: float = 1.2
var anvil_alt_timer: float = 0.0
var anvil_self_launch_chain: int = 0

var injector_alt_cooldown: float = 2.8
var injector_alt_timer: float = 0.0

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
		"name": "КРОВАВАЯ НАКОВАЛЬНЯ",
		"max_ammo": 2,
		"damage": 12,
		"pellets": 8,
		"spread": 0.085, # Конус разброса ~8-10 градусов
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
	},
	{
		"name": "ИНЪЕКТОР",
		"max_ammo": 6,
		"damage": 18,
		"pellets": 1,
		"spread": 0.0,
		"fire_rate": 0.32,
		"reload_time": 1.4,
		"cam_shake": 0.04,
		"weapon_kick": 0.16,
		"knockback": 2.5,
		"upward_kick": 0.0,
		"headshot_multiplier": 1.5,
		"air_multiplier": 1.0,
		"has_vacuum": false,
		"is_injector": true
	}
]

var ammos = [4, 2, 6]

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
		weapon_hud_container.offset_left = -320.0
		weapon_hud_container.offset_top = -195.0
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

	if anvil_alt_timer > 0.0:
		anvil_alt_timer -= delta

	if injector_alt_timer > 0.0:
		injector_alt_timer -= delta

	var player_node = get_parent()
	if is_instance_valid(player_node) and player_node.is_on_floor() and player_node.velocity.y <= 0.0:
		anvil_self_launch_chain = 0

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
				var alt_suffix = ""
				if i == 1 and anvil_alt_timer > 0.0:
					alt_suffix = " (RMB %.1fs)" % anvil_alt_timer
				elif i == 2 and injector_alt_timer > 0.0:
					alt_suffix = " (RMB %.1fs)" % injector_alt_timer
				slot["ammo_text"].text = "INF (BLOOD)" + alt_suffix
				slot["ammo_text"].add_theme_color_override("font_color", Color(1.0, 0.2, 0.2, 1.0))
				slot["pbar"].visible = false
			else:
				var alt_suffix = ""
				if i == 1 and anvil_alt_timer > 0.0:
					alt_suffix = " (RMB %.1fs)" % anvil_alt_timer
				elif i == 2 and injector_alt_timer > 0.0:
					alt_suffix = " (RMB %.1fs)" % injector_alt_timer
				slot["ammo_text"].text = ("%d / %d" % [ammos[i], w["max_ammo"]]) + alt_suffix
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

func alt_shoot(has_infinite_ammo: bool = false):
	if is_bursting:
		return

	if current_weapon_index == 0:
		if is_reloading or fire_timers[0] > 0:
			return
		# Калибр-0: ПКМ быстрый залп (всегда расходует реальные патроны из барабана)
		if ammos[0] <= 0:
			reload()
			return
		var shots_to_fire = ammos[0]
		_perform_burst(shots_to_fire)
	elif current_weapon_index == 1:
		# Кровавая наковальня: ПКМ поршень (толчок врага / self-launch)
		_fire_anvil_piston()
	elif current_weapon_index == 2:
		# Инъектор: ПКМ раздутие (независимый кулдаун, не зависит от магазина ЛКМ)
		_fire_injector_inflate()

func _fire_anvil_piston():
	if anvil_alt_timer > 0.0:
		return
		
	var aim_dir = head.get_aim_direction().normalized()
	var from_pos = head.camera.global_position
	var start_pos = head.get_muzzle_position()
	var space_state = head.camera.get_world_3d().direct_space_state
	var player_node = get_parent()
	
	const PISTON_RANGE: float = 5.0 # Дальность действия ПКМ (5.0 метров)
	const SPHERE_TOLERANCE: float = 0.40 # Радиус допуска sphere-cast (0.4 метра вокруг центральной линии прицела)
	const ENEMY_COL_RADIUS: float = 0.38 # Радиус коллизии врага
	
	# 1. Поиск врагов с помощью Sphere-Cast детекции с радиусом допуска вдоль линии прицела
	var enemies_in_cone: Array = []
	var detected_enemies_set: Dictionary = {}
	var all_enemies = get_tree().get_nodes_in_group("enemy")
	
	# А. Проверка прямого тонкого луча (для максимально точной фиксации точки коллизии при прямом прицеливании)
	var direct_ray = PhysicsRayQueryParameters3D.create(from_pos, from_pos + aim_dir * PISTON_RANGE)
	if is_instance_valid(player_node):
		direct_ray.exclude = [player_node]
	direct_ray.collide_with_areas = true
	direct_ray.collide_with_bodies = true
	var direct_res = space_state.intersect_ray(direct_ray)
	var direct_target: Node = null
	var direct_hit_pos: Vector3 = from_pos + aim_dir * PISTON_RANGE
	
	if not direct_res.is_empty():
		direct_hit_pos = direct_res.position
		var col = direct_res.collider
		if col:
			if col.is_in_group("enemy_head") or col.name == "HeadHitbox":
				direct_target = col.get_meta("enemy") if col.has_meta("enemy") else col.get_parent()
			elif col.has_method("take_damage"):
				direct_target = col
			elif col.get_parent() and col.get_parent().has_method("take_damage"):
				direct_target = col.get_parent()
				
	if direct_target and is_instance_valid(direct_target) and not ("current_state" in direct_target and direct_target.current_state == direct_target.State.DEAD):
		enemies_in_cone.append({
			"enemy": direct_target,
			"hit_pos": direct_hit_pos,
			"dist": from_pos.distance_to(direct_hit_pos)
		})
		detected_enemies_set[direct_target] = true
		
	# Б. Sphere-Cast сканирование врагов с радиусом допуска (0.4м на дистанции, до 0.55м в упор)
	var ray_dir_h = Vector2(aim_dir.x, aim_dir.z)
	var ray_dir_h_len_sq = ray_dir_h.length_squared()
	
	for e in all_enemies:
		if not is_instance_valid(e) or detected_enemies_set.has(e):
			continue
		if ("current_state" in e and e.current_state == e.State.DEAD) or ("health" in e and e.health <= 0):
			continue
			
		var e_pos = e.global_position
		var y_min = e_pos.y - 0.95
		var y_max = e_pos.y + 0.85
		
		# Проекция на линию луча прицела
		var t: float = 0.0
		if ray_dir_h_len_sq > 0.0001:
			var to_e_h = Vector2(e_pos.x - from_pos.x, e_pos.z - from_pos.z)
			var t_h = to_e_h.dot(ray_dir_h) / ray_dir_h_len_sq
			if t_h < -0.2:
				continue # Враг находится позади взгляда игрока
			t = clamp(t_h, 0.0, PISTON_RANGE)
		else:
			t = clamp(from_pos.y - e_pos.y, 0.0, PISTON_RANGE)
			
		var ray_pt = from_pos + aim_dir * t
		
		# Горизонтальное расстояние от точки луча до вертикальной оси врага
		var h_dist = Vector2(ray_pt.x - e_pos.x, ray_pt.z - e_pos.z).length()
		# Ближайшая точка по высоте на теле врага к точке луча
		var contact_y = clamp(ray_pt.y, y_min, y_max)
		var v_dist = abs(ray_pt.y - contact_y)
		
		var dist_to_axis = sqrt(h_dist * h_dist + v_dist * v_dist)
		var dist_to_surface = max(0.0, dist_to_axis - ENEMY_COL_RADIUS)
		
		# Радиус допуска: 0.40м на дистанции, до 0.55м в упор (до 2.0м)
		var allowed_tolerance = 0.55 if t <= 2.0 else SPHERE_TOLERANCE
		if dist_to_surface > allowed_tolerance:
			continue
			
		var hit_pos = Vector3(e_pos.x, contact_y, e_pos.z)
		if h_dist > 0.01:
			var h_norm = Vector3(ray_pt.x - e_pos.x, 0.0, ray_pt.z - e_pos.z).normalized()
			hit_pos += h_norm * ENEMY_COL_RADIUS
			
		var dist_from_player = from_pos.distance_to(hit_pos)
		if dist_from_player > PISTON_RANGE:
			continue
			
		# Проверка видимости цели через геометрию стен (Line of Sight)
		var occ_ray = PhysicsRayQueryParameters3D.create(from_pos, hit_pos)
		if is_instance_valid(player_node):
			occ_ray.exclude = [player_node]
		occ_ray.collide_with_areas = false
		occ_ray.collide_with_bodies = true
		var occ_res = space_state.intersect_ray(occ_ray)
		if not occ_res.is_empty():
			var occ_col = occ_res.collider
			if occ_col != e and not occ_col.is_in_group("enemy") and not (occ_col.get_parent() and occ_col.get_parent().is_in_group("enemy")):
				continue # Перекрыто сплошной стеной
				
		enemies_in_cone.append({
			"enemy": e,
			"hit_pos": hit_pos,
			"dist": dist_from_player
		})
		detected_enemies_set[e] = true
		
	# Если обнаружен хотя бы один враг в конусе — бьем врагов (self-launch не срабатывает)
	if enemies_in_cone.size() > 0:
		anvil_alt_timer = anvil_alt_cooldown
		head.add_recoil(0.12, 0.40)
		head.trigger_muzzle_flash(true)
		AudioManager.play_sound("shotgun_shot")
		
		# Сортируем врагов по расстоянию от игрока (ближайший — первая цель цепи)
		enemies_in_cone.sort_custom(func(a, b): return a["dist"] < b["dist"])
		
		var primary_hit_pos = enemies_in_cone[0]["hit_pos"]
		
		for idx in range(enemies_in_cone.size()):
			var data = enemies_in_cone[idx]
			var target = data["enemy"]
			var hit_pos = data["hit_pos"]
			var chain_depth = idx
			
			# Фактическая высота точки контакта на теле врага
			# Враг: капсула тела (y от -1.0 до +0.25) + сфера головы (y от +0.21 до +0.89)
			var feet_y = target.global_position.y - 1.0
			var head_top_y = target.global_position.y + 0.89
			var total_height = head_top_y - feet_y # ~1.89м
			
			# Определяем фактическую высоту точки контакта на модели цели
			var contact_y = hit_pos.y
			var rel_height = clamp((contact_y - feet_y) / max(0.1, total_height), 0.0, 1.0)
			
			# Условие подброса: точка контакта в нижних ~25-30% капсулы (rel_height <= 0.28, уровень ног)
			# Зависит ИСКЛЮЧИТЕЛЬНО от высоты точки контакта на теле цели, угол камеры не участвует
			var is_aiming_at_legs = (rel_height <= 0.28)
			
			var push_vec: Vector3 = Vector3.ZERO
			if is_aiming_at_legs:
				# Вертикальный подброс врага вверх (аналог self-launch)
				var upward_impulse = 21.0
				var push_h = Vector3(aim_dir.x, 0, aim_dir.z).normalized() * 5.0
				push_vec = Vector3(push_h.x, upward_impulse, push_h.z)
				print("[ANVIL PISTON] VERTICAL LAUNCH -> %s (rel_height: %.2f, impulse: %.1f)" % [target.name, rel_height, upward_impulse])
			else:
				# Горизонтальный отброс от игрока в упор (38-45 м/с -> 42.0 м/с)
				var push_speed = 42.0
				var push_dir = aim_dir.normalized()
				push_vec = push_dir * push_speed
				push_vec.y = clamp(push_vec.y, 3.0, 7.0)
				print("[ANVIL PISTON] HORIZONTAL SLAM PUSH -> %s (rel_height: %.2f, speed: %.1f)" % [target.name, rel_height, push_speed])
				
			# 0 прямого урона (прямой урон снят), активирует wall_slam и collateral_slam с затуханием цепи chain_depth
			target.take_damage(0, push_vec, hit_pos, false, false, true, false, chain_depth)
			
		spawn_piston_tracer(start_pos, primary_hit_pos, false)
		return
		
	# 2. Врагов нет — проверяем попадание конуса в статичную геометрию (стена, пол, потолок)
	var hit_geom: bool = false
	var geom_hit_pos: Vector3 = from_pos + aim_dir * PISTON_RANGE
	var geom_hit_normal: Vector3 = Vector3.UP
	var geom_hit_dist: float = PISTON_RANGE
	
	var geom_ray = PhysicsRayQueryParameters3D.create(from_pos, from_pos + aim_dir * PISTON_RANGE)
	if is_instance_valid(player_node):
		geom_ray.exclude = [player_node]
	geom_ray.collide_with_areas = false
	geom_ray.collide_with_bodies = true
	var geom_res = space_state.intersect_ray(geom_ray)
	
	if not geom_res.is_empty():
		hit_geom = true
		geom_hit_pos = geom_res.position
		geom_hit_normal = geom_res.normal
		geom_hit_dist = from_pos.distance_to(geom_hit_pos)
	else:
		# Проверяем лучи по периметру конуса (~18 градусов)
		var cam_basis = head.camera.global_transform.basis
		var cone_offsets = [
			Vector3.UP * 0.16,
			Vector3.DOWN * 0.16,
			Vector3.LEFT * 0.16,
			Vector3.RIGHT * 0.16
		]
		for offset in cone_offsets:
			var test_dir = (aim_dir + cam_basis * offset).normalized()
			var sub_query = PhysicsRayQueryParameters3D.create(from_pos, from_pos + test_dir * PISTON_RANGE)
			if is_instance_valid(player_node):
				sub_query.exclude = [player_node]
			sub_query.collide_with_areas = false
			sub_query.collide_with_bodies = true
			var sub_res = space_state.intersect_ray(sub_query)
			if not sub_res.is_empty():
				var d = from_pos.distance_to(sub_res.position)
				if d < geom_hit_dist:
					hit_geom = true
					geom_hit_dist = d
					geom_hit_pos = sub_res.position
					geom_hit_normal = sub_res.normal
					
	if hit_geom:
		# Self-launch при упоре в любую статичную геометрию (стена, пол, потолок)
		_perform_self_launch(aim_dir, geom_hit_pos, geom_hit_normal)
	else:
		# Выстрел в пустое пространство (> 5 метров)
		anvil_alt_timer = anvil_alt_cooldown
		head.add_recoil(0.08, 0.25)
		head.trigger_muzzle_flash(true)
		AudioManager.play_sound("shotgun_shot")
		spawn_piston_tracer(start_pos, from_pos + aim_dir * PISTON_RANGE, false)
		print("[ANVIL PISTON] Air blast (no surface or enemy in range)")

func _perform_self_launch(aim_dir: Vector3, surface_hit_pos: Vector3, surface_normal: Vector3):
	var player_node = get_parent()
	if not is_instance_valid(player_node):
		return
		
	anvil_alt_timer = anvil_alt_cooldown
	
	# Защита от спама: если self-launch применяется повторно БЕЗ касания земли:
	# 1-е применение = 100%, 2-е = 60%, 3-е и далее = 35%
	if player_node.is_on_floor():
		anvil_self_launch_chain = 0
		
	var mult: float = 1.0
	if anvil_self_launch_chain == 0:
		mult = 1.0
	elif anvil_self_launch_chain == 1:
		mult = 0.60
	else:
		mult = 0.35
	anvil_self_launch_chain += 1
	
	var base_impulse: float = 19.5
	var final_impulse: float = base_impulse * mult
	
	# 1. Единый вектор импульса: строго в направлении, противоположном направлению взгляда камеры (-aim_dir),
	# независимо от того, куда именно попал выстрел (пол, стена, потолок, угол).
	var push_dir: Vector3 = -aim_dir.normalized()
	var impulse_vec: Vector3 = push_dir * final_impulse
	
	# 2. Импульс аддитивно ДОБАВЛЯЕТСЯ к текущей velocity игрока целиком (все три компонента x, y, z)
	player_node.velocity += impulse_vec
	
	# 3. Защита от чрезмерного подброса: ограничиваем ТОЛЬКО результирующую вертикальную компоненту (velocity.y).
	# Верхний предел: 22.0 при 100% силы, с учётом anti-spam модификатора (mult: 1.0 -> 0.6 -> 0.35).
	# Горизонтальные компоненты velocity.x и velocity.z не ограничиваются — они обеспечивают направленный rocket-jump.
	var max_vertical: float = 22.0 * mult
	if player_node.velocity.y > max_vertical:
		player_node.velocity.y = max_vertical
		
	# Если стоим на полу и стреляем строго горизонтально в стену — даем легкий стартовый отрыв от земли
	if impulse_vec.y >= 0.0 and player_node.is_on_floor() and player_node.velocity.y < 3.5:
		player_node.velocity.y = max(player_node.velocity.y, 3.5 * mult)
		
	if "has_jumped" in player_node:
		player_node.has_jumped = true
	if "time_on_ground" in player_node:
		player_node.time_on_ground = 0.0
	if "air_time" in player_node:
		player_node.air_time = 0.1
	if "coyote_timer" in player_node:
		player_node.coyote_timer = 0.0
	if "jump_buffer_timer" in player_node:
		player_node.jump_buffer_timer = 0.0
	if "is_sliding" in player_node and player_node.is_sliding:
		player_node.is_sliding = false
		
	head.add_recoil(0.14, 0.45)
	head.landing_shake_trauma = max(head.landing_shake_trauma, 0.5 * mult)
	AudioManager.play_sound("shotgun_shot")
	
	var start_pos = head.get_muzzle_position()
	spawn_piston_tracer(start_pos, surface_hit_pos, true)
	
	print("[ANVIL PISTON] SELF-LAUNCH! Chain: %d | Mult: %.2f | Impulse: %.1f | PushDir: %s | Vel: %s" % [
		anvil_self_launch_chain, mult, final_impulse, push_dir, player_node.velocity
	])

func spawn_piston_tracer(start_pos: Vector3, end_pos: Vector3, is_self_launch: bool = false):
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
	
	var r = 0.07 if is_self_launch else 0.055
	st.add_vertex(start_pos - right * r)
	st.add_vertex(end_pos + right * r)
	st.add_vertex(end_pos - right * r)
	
	st.add_vertex(start_pos - right * r)
	st.add_vertex(start_pos + right * r)
	st.add_vertex(end_pos + right * r)
	
	st.add_vertex(start_pos - up * r)
	st.add_vertex(end_pos + up * r)
	st.add_vertex(end_pos - up * r)
	
	st.add_vertex(start_pos - up * r)
	st.add_vertex(start_pos + up * r)
	st.add_vertex(end_pos + up * r)
	
	mesh_inst.mesh = st.commit()
	
	var mat = StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = Color(1.0, 0.65, 0.25, 0.9) if is_self_launch else Color(0.85, 0.95, 1.0, 0.9)
	mesh_inst.material_override = mat
	
	var scene_root = get_tree().current_scene if get_tree().current_scene else get_parent()
	if not scene_root:
		return
	scene_root.add_child(mesh_inst)
	mesh_inst.global_transform = Transform3D.IDENTITY
	
	var tween = create_tween()
	tween.tween_property(mat, "albedo_color:a", 0.0, 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_callback(mesh_inst.queue_free)
	
	var sphere = MeshInstance3D.new()
	var smesh = SphereMesh.new()
	smesh.radius = 0.25
	smesh.height = 0.5
	sphere.mesh = smesh
	var smat = StandardMaterial3D.new()
	smat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	smat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	smat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	smat.cull_mode = BaseMaterial3D.CULL_DISABLED
	smat.albedo_color = Color(1.0, 0.75, 0.3, 0.8) if is_self_launch else Color(0.6, 0.85, 1.0, 0.75)
	sphere.material_override = smat
	scene_root.add_child(sphere)
	sphere.global_position = end_pos
	
	var stween = create_tween().set_parallel(true)
	var target_scale = Vector3(2.4, 2.4, 2.4) if is_self_launch else Vector3(1.6, 1.6, 1.6)
	stween.tween_property(sphere, "scale", target_scale, 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	stween.tween_property(smat, "albedo_color:a", 0.0, 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	stween.chain().tween_callback(sphere.queue_free)

func _fire_injector_inflate():
	if injector_alt_timer > 0.0:
		return
		
	injector_alt_timer = injector_alt_cooldown
	head.add_recoil(0.07, 0.26)
	head.trigger_muzzle_flash(false)
	AudioManager.play_sound("injector_shot")
	
	var aim_dir = head.get_aim_direction()
	var start_pos = head.get_muzzle_position()
	var ray = head.get_aim_raycast(0.0)
	var hit_pos = ray.to_global(ray.target_position)
	
	if ray.is_colliding():
		hit_pos = ray.get_collision_point()
		var hit = ray.get_collider()
		if hit != null:
			var target: Node = null
			if hit.is_in_group("enemy_head") or hit.name == "HeadHitbox":
				if hit.has_meta("enemy"):
					target = hit.get_meta("enemy")
				elif hit.get_parent():
					target = hit.get_parent()
			elif hit.has_method("take_damage"):
				target = hit
			elif hit.get_parent() and hit.get_parent().has_method("take_damage"):
				target = hit.get_parent()
				
			if target != null and target.has_method("inflate"):
				target.inflate()
				
	spawn_inflate_tracer(start_pos, hit_pos)

func spawn_inflate_tracer(start_pos: Vector3, end_pos: Vector3):
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
	
	var r = 0.038
	st.add_vertex(start_pos - right * r)
	st.add_vertex(end_pos + right * r)
	st.add_vertex(end_pos - right * r)
	
	st.add_vertex(start_pos - right * r)
	st.add_vertex(start_pos + right * r)
	st.add_vertex(end_pos + right * r)
	
	st.add_vertex(start_pos - up * r)
	st.add_vertex(end_pos + up * r)
	st.add_vertex(end_pos - up * r)
	
	st.add_vertex(start_pos - up * r)
	st.add_vertex(start_pos + up * r)
	st.add_vertex(end_pos + up * r)
	
	mesh_inst.mesh = st.commit()
	
	var mat = StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = Color(1.0, 0.12, 0.18, 0.95)
	mesh_inst.material_override = mat
	
	var scene_root = get_tree().current_scene if get_tree().current_scene else get_parent()
	if not scene_root:
		return
	scene_root.add_child(mesh_inst)
	mesh_inst.global_transform = Transform3D.IDENTITY
	
	var tween = create_tween()
	tween.tween_property(mat, "albedo_color:a", 0.0, 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_callback(mesh_inst.queue_free)

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
	elif weapon_idx == 1:
		AudioManager.play_sound("shotgun_shot")
	elif weapon_idx == 2:
		AudioManager.play_sound("injector_shot")
		
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
						
					if weapon_idx == 2 and target.has_method("apply_poison_dot"):
						target.apply_poison_dot(3.0, 3, 0.5)
						
					target.take_damage(final_dmg, knockback_vector, hit_pos, false, false, false, is_headshot)
					
		if w.get("has_vacuum", false):
			spawn_bullet_tracer(start_pos, hit_pos)
			if not is_alt_fire:
				apply_vacuum_wake(start_pos, hit_pos, float(w.get("vacuum_radius", 2.0)), float(w.get("vacuum_force", 16.0)), directly_hit_target)
		elif weapon_idx == 1:
			spawn_shotgun_pellet_tracer(start_pos, hit_pos)
		elif weapon_idx == 2:
			spawn_syringe_tracer(start_pos, hit_pos)

func spawn_shotgun_pellet_tracer(start_pos: Vector3, end_pos: Vector3):
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
	
	var r = 0.016
	st.add_vertex(start_pos - right * r)
	st.add_vertex(end_pos + right * r)
	st.add_vertex(end_pos - right * r)
	
	st.add_vertex(start_pos - right * r)
	st.add_vertex(start_pos + right * r)
	st.add_vertex(end_pos + right * r)
	
	st.add_vertex(start_pos - up * r)
	st.add_vertex(end_pos + up * r)
	st.add_vertex(end_pos - up * r)
	
	st.add_vertex(start_pos - up * r)
	st.add_vertex(start_pos + up * r)
	st.add_vertex(end_pos + up * r)
	
	mesh_inst.mesh = st.commit()
	
	var mat = StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = Color(1.0, 0.72, 0.25, 0.85)
	mesh_inst.material_override = mat
	
	var scene_root = get_tree().current_scene if get_tree().current_scene else get_parent()
	if not scene_root:
		return
	scene_root.add_child(mesh_inst)
	mesh_inst.global_transform = Transform3D.IDENTITY
	
	var tween = create_tween()
	tween.tween_property(mat, "albedo_color:a", 0.0, 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_callback(mesh_inst.queue_free)

func spawn_syringe_tracer(start_pos: Vector3, end_pos: Vector3):
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
	
	var r = 0.022
	st.add_vertex(start_pos - right * r)
	st.add_vertex(end_pos + right * r)
	st.add_vertex(end_pos - right * r)
	
	st.add_vertex(start_pos - right * r)
	st.add_vertex(start_pos + right * r)
	st.add_vertex(end_pos + right * r)
	
	st.add_vertex(start_pos - up * r)
	st.add_vertex(end_pos + up * r)
	st.add_vertex(end_pos - up * r)
	
	st.add_vertex(start_pos - up * r)
	st.add_vertex(start_pos + up * r)
	st.add_vertex(end_pos + up * r)
	
	mesh_inst.mesh = st.commit()
	
	var mat = StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = Color(0.25, 1.0, 0.4, 0.95)
	mesh_inst.material_override = mat
	
	var scene_root = get_tree().current_scene if get_tree().current_scene else get_parent()
	if not scene_root:
		return
	scene_root.add_child(mesh_inst)
	mesh_inst.global_transform = Transform3D.IDENTITY
	
	var tween = create_tween()
	tween.tween_property(mat, "albedo_color:a", 0.0, 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_callback(mesh_inst.queue_free)

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
