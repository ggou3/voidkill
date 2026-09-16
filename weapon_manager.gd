class_name WeaponManager
extends Node

var current_weapon_index = 0
var is_reloading = false
var is_bursting = false
var fire_timers = [0.0, 0.0, 0.0, 0.0]
var passive_reload_timers = [0.0, 0.0, 0.0, 0.0]
var active_reload_timer = 0.0

var anvil_alt_cooldown: float = 1.2
var anvil_alt_timer: float = 0.0
var anvil_self_launch_chain: int = 0

var injector_alt_cooldown: float = 4.5
var injector_alt_timer: float = 0.0

var sewing_alt_cooldown: float = 1.5
var sewing_alt_timer: float = 0.0

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
		"has_vacuum": true,
		"vacuum_radius": 2.5,
		"vacuum_force": 25.6
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
		"damage": 10, # Прямой урон одного дротика 10 HP (очередь из 3 дротиков = 30 HP суммарно)
		"pellets": 1,
		"spread": 0.045, # Конусный разброс ~4-5 градусов
		"fire_rate": 0.28, # Кулдаун между очередями
		"reload_time": 1.4,
		"cam_shake": 0.025,
		"weapon_kick": 0.08,
		"knockback": 1.5,
		"upward_kick": 0.0,
		"headshot_multiplier": 1.5,
		"air_multiplier": 1.0,
		"has_vacuum": false,
		"is_injector": true
	},
	{
		"name": "ШВЕЙНАЯ МАШИНА",
		"max_ammo": 40,
		"damage": 6,
		"pellets": 1,
		"spread": 0.02,
		"fire_rate": 0.1, # 10 выстрелов/сек (0.1с интервал)
		"reload_time": 2.0,
		"cam_shake": 0.025,
		"weapon_kick": 0.08,
		"knockback": 1.0,
		"upward_kick": 0.0,
		"headshot_multiplier": 1.5,
		"air_multiplier": 1.0,
		"has_vacuum": false,
		"is_automatic": true,
		"is_sewing_machine": true
	}
]

var ammos = [4, 2, 6, 40]

@onready var head = $"../Head"
@onready var ammo_label = $"../HUD/AmmoLabel"
@onready var hud = $"../HUD"
@onready var skill_manager = get_node_or_null("../SkillManager")

func _get_bpm_tier() -> GameTypes.BPMTier:
	if not skill_manager and is_inside_tree():
		skill_manager = get_node_or_null("../SkillManager")
	if skill_manager is SkillManager:
		return skill_manager.get_bpm_tier()
	return GameTypes.BPMTier.CALM

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

	if sewing_alt_timer > 0.0:
		sewing_alt_timer -= delta

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

	# Автоматическая стрельба при удержании ЛКМ
	if current_weapon_index < weapons.size() and weapons[current_weapon_index].get("is_automatic", false):
		if Input.is_action_pressed("shoot") and not is_reloading and fire_timers[current_weapon_index] <= 0:
			var inf = false
			if player_node is Player:
				inf = player_node.has_infinite_ammo()
			shoot(inf)

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
				var alt_suffix = ""
				if i == 1 and anvil_alt_timer > 0.0:
					alt_suffix = " (RMB %.1fs)" % anvil_alt_timer
				elif i == 2 and injector_alt_timer > 0.0:
					alt_suffix = " (RMB %.1fs)" % injector_alt_timer
				elif i == 3 and sewing_alt_timer > 0.0:
					alt_suffix = " (RMB %.1fs)" % sewing_alt_timer
				slot["ammo_text"].text = ("RELOAD %d%%" % int(progress * 100.0)) + alt_suffix
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
				if i == 0:
					alt_suffix = " [RMB: %d]" % ammos[0]
				elif i == 1 and anvil_alt_timer > 0.0:
					alt_suffix = " (RMB %.1fs)" % anvil_alt_timer
				elif i == 2 and injector_alt_timer > 0.0:
					alt_suffix = " (RMB %.1fs)" % injector_alt_timer
				elif i == 3 and sewing_alt_timer > 0.0:
					alt_suffix = " (RMB %.1fs)" % sewing_alt_timer
				slot["ammo_text"].text = "INF (OVERDRIVE)" + alt_suffix
				slot["ammo_text"].add_theme_color_override("font_color", Color(1.0, 0.2, 0.2, 1.0))
				slot["pbar"].visible = false
			else:
				var alt_suffix = ""
				if i == 1 and anvil_alt_timer > 0.0:
					alt_suffix = " (RMB %.1fs)" % anvil_alt_timer
				elif i == 2 and injector_alt_timer > 0.0:
					alt_suffix = " (RMB %.1fs)" % injector_alt_timer
				elif i == 3 and sewing_alt_timer > 0.0:
					alt_suffix = " (RMB %.1fs)" % sewing_alt_timer
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
	if current_weapon_index == 2:
		_fire_injector_burst()
	else:
		_fire_pellets(current_weapon_index, -1.0, false)

func _fire_injector_burst():
	is_bursting = true
	const BURST_COUNT: int = 3
	const BURST_INTERVAL: float = 0.07
	for i in range(BURST_COUNT):
		if current_weapon_index != 2 or not is_inside_tree():
			break
		_fire_pellets(2, 0.045, false)
		if i < BURST_COUNT - 1:
			await get_tree().create_timer(BURST_INTERVAL).timeout
	is_bursting = false

func alt_shoot(has_infinite_ammo: bool = false):
	if is_bursting:
		return

	if current_weapon_index == 0:
		if is_reloading or fire_timers[0] > 0:
			return
		# Калибр-0: ПКМ пробивной рейлган-выстрел (BPM-гейт: доступен ТОЛЬКО на OVERDRIVE)
		if _get_bpm_tier() != GameTypes.BPMTier.OVERDRIVE:
			AudioManager.play_sound("dry_fire")
			return
		if ammos[0] <= 0:
			AudioManager.play_sound("dry_fire")
			reload()
			return
		_fire_caliber_piercing_shot()
	elif current_weapon_index == 1:
		# Кровавая наковальня: ПКМ поршень (толчок врага / self-launch)
		_fire_anvil_piston()
	elif current_weapon_index == 2:
		# Инъектор: ПКМ раздутие (независимый кулдаун, не зависит от магазина ЛКМ)
		_fire_injector_inflate()
	elif current_weapon_index == 3:
		# Швейная машина: ПКМ заградительный веерный залп
		_fire_sewing_barrage(has_infinite_ammo)

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
			else:
				direct_target = GameTypes.resolve_damageable(col)
				
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
			if occ_col != e and GameTypes.resolve_enemy(occ_col) == null:
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
			
			# Определение, находится ли враг на земле
			var target_body = GameTypes.resolve_damageable(target)
			var target_on_floor: bool = target_body.is_on_floor() if (target_body and target_body.has_method("is_on_floor")) else false
				
			# Условие подброса: точка контакта в нижних ~25-30% капсулы (rel_height <= 0.28, уровень ног)
			# И враг обязательно стоит на земле (is_on_floor == true).
			# Если враг уже в воздухе — подброс не применяется, выполняется стандартный 3D-толчок по вектору камеры.
			var is_aiming_at_legs = (rel_height <= 0.28) and target_on_floor
			
			var push_vec: Vector3 = Vector3.ZERO
			if is_aiming_at_legs:
				# Вертикальный подброс врага вверх (только для наземных целей)
				var upward_impulse = 21.0
				var push_h = Vector3(aim_dir.x, 0, aim_dir.z).normalized() * 5.0
				push_vec = Vector3(push_h.x, upward_impulse, push_h.z)
				GameTypes.debug_log(&"weapon", "[ANVIL PISTON] VERTICAL LAUNCH -> %s (rel_height: %.2f, on_floor: true, impulse: %.1f)" % [target.name, rel_height, upward_impulse])
			else:
				# Полный 3D-вектор толчка от игрока с учетом вертикального угла камеры (aim_dir.y):
				# Если игрок целится сверху вниз, толчок направляет врага в пол для срабатывания wall_slam.
				# Также применяется для любых попаданий по врагам, уже находящимся в воздухе.
				var push_speed = 42.0
				var push_dir = aim_dir.normalized()
				push_vec = push_dir * push_speed
				GameTypes.debug_log(&"weapon", "[ANVIL PISTON] 3D DIRECTIONAL PUSH -> %s (rel_height: %.2f, on_floor: %s, speed: %.1f, push_vec: %s)" % [target.name, rel_height, str(target_on_floor), push_speed, push_vec])
				
			# 0 прямого урона (прямой урон снят), активирует wall_slam и collateral_slam с затуханием цепи chain_depth
			target.take_damage(0, push_vec, hit_pos, false, false, true, false, chain_depth, "anvil")
			
		TracerPool.spawn_tracer(start_pos, primary_hit_pos, &"piston", false)
		return
		
	# 2. Прямого попадания во врагов нет — проверяем попадание конуса в статичную геометрию (стена, пол, потолок)
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
		# Проверяем: есть ли враги, стоящие на поверхности в радиусе ~1.8-2.0м от точки попадания (выстрел в пол под удалённым врагом)
		const FLOOR_SPLASH_RADIUS: float = 2.0
		var splash_enemies: Array = []
		
		for e in all_enemies:
			if not is_instance_valid(e):
				continue
			if ("current_state" in e and e.current_state == e.State.DEAD) or ("health" in e and e.health <= 0):
				continue
				
			var e_pos = e.global_position
			var e_feet_y = e_pos.y - 1.0 # Уровень земли/ступней врага
			var h_dist = Vector2(e_pos.x - geom_hit_pos.x, e_pos.z - geom_hit_pos.z).length()
			var v_diff = abs(geom_hit_pos.y - e_feet_y)
			
			# Враг должен стоять на этой поверхности (в радиусе до 2.0м и по высоте рядом)
			if h_dist <= FLOOR_SPLASH_RADIUS and v_diff <= 1.4:
				# Проверка видимости от точки удара в пол к ногам врага (не сквозь сплошную стену)
				var splash_occ = PhysicsRayQueryParameters3D.create(geom_hit_pos + geom_hit_normal * 0.1, e_pos + Vector3(0, -0.4, 0))
				if is_instance_valid(player_node):
					splash_occ.exclude = [player_node]
				splash_occ.collide_with_areas = false
				splash_occ.collide_with_bodies = true
				var splash_res = space_state.intersect_ray(splash_occ)
				if not splash_res.is_empty():
					var occ_col = splash_res.collider
					if occ_col != e and GameTypes.resolve_enemy(occ_col) == null:
						continue # Перекрыто препятствием
						
				splash_enemies.append({
					"enemy": e,
					"dist": h_dist
				})
				
		if splash_enemies.size() > 0:
			# НАЙДЕН ВРАГ НА ПОВЕРХНОСТИ: применяем вертикальный импульс подброса (выстрел в пол под ногами врага)
			splash_enemies.sort_custom(func(a, b): return a["dist"] < b["dist"])
			
			for idx in range(splash_enemies.size()):
				var target = splash_enemies[idx]["enemy"]
				var chain_depth = idx
				var upward_impulse = 21.0
				var push_h = Vector3(aim_dir.x, 0, aim_dir.z).normalized() * 5.0
				var push_vec = Vector3(push_h.x, upward_impulse, push_h.z)
				GameTypes.debug_log(&"weapon", "[ANVIL PISTON] FLOOR SPLASH LAUNCH -> %s (h_dist: %.2f, impulse: %.1f)" % [target.name, splash_enemies[idx]["dist"], upward_impulse])
				
				var hit_pos = target.global_position + Vector3(0, -0.6, 0)
				target.take_damage(0, push_vec, hit_pos, false, false, true, false, chain_depth, "anvil")
				
		# Выполняем self-launch игрока (в пределах дальности PISTON_RANGE при упоре в любую статичную геометрию).
		# Срабатывает ОДНОВРЕМЕННО с подбросом врагов, если выстрел был в пол рядом с ними.
		_perform_self_launch(aim_dir, geom_hit_pos, geom_hit_normal)
	else:
		# Выстрел в пустое пространство (> 5 метров)
		anvil_alt_timer = anvil_alt_cooldown
		head.add_recoil(0.08, 0.25)
		head.trigger_muzzle_flash(true)
		AudioManager.play_sound("shotgun_shot")
		TracerPool.spawn_tracer(start_pos, from_pos + aim_dir * PISTON_RANGE, &"piston", false)
		GameTypes.debug_log(&"weapon", "[ANVIL PISTON] Air blast (no surface or enemy in range)")

func _perform_self_launch(aim_dir: Vector3, surface_hit_pos: Vector3, _surface_normal: Vector3):
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
	head.trigger_muzzle_flash(true)
	head.landing_shake_trauma = max(head.landing_shake_trauma, 0.5 * mult)
	AudioManager.play_sound("shotgun_shot")
	
	var start_pos = head.get_muzzle_position()
	TracerPool.spawn_tracer(start_pos, surface_hit_pos, &"piston", true)
	
	GameTypes.debug_log(&"weapon", "[ANVIL PISTON] SELF-LAUNCH! Chain: %d | Mult: %.2f | Impulse: %.1f | PushDir: %s | Vel: %s" % [
		anvil_self_launch_chain, mult, final_impulse, push_dir, player_node.velocity
	])

func _fire_injector_inflate():
	if injector_alt_timer > 0.0:
		return
		
	injector_alt_timer = injector_alt_cooldown
	head.add_recoil(0.07, 0.26)
	head.trigger_muzzle_flash(false)
	AudioManager.play_sound("injector_shot")
	
	var _aim_dir = head.get_aim_direction()
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
			else:
				target = GameTypes.resolve_damageable(hit)
				
			if target != null and target.has_method("inflate"):
				target.inflate()
				
	TracerPool.spawn_tracer(start_pos, hit_pos, &"inflate")

func _fire_caliber_piercing_shot():
	ammos[0] = 0
	fire_timers[0] = weapons[0]["fire_rate"]
	
	head.add_recoil(0.20, 0.60)
	head.trigger_muzzle_flash(true)
	AudioManager.play_sound("rail_shot")
	
	var aim_dir = head.get_aim_direction().normalized()
	var from_pos = head.camera.global_position
	var start_pos = head.get_muzzle_position()
	var space_state = head.camera.get_world_3d().direct_space_state
	var player_node = get_parent()
	
	const MAX_BEAM_DIST: float = 120.0
	var current_from = from_pos
	var remaining_dist = MAX_BEAM_DIST
	var beam_end = from_pos + aim_dir * MAX_BEAM_DIST
	var exclude_list: Array[RID] = []
	if is_instance_valid(player_node):
		exclude_list.append(player_node.get_rid())
		
	while remaining_dist > 0.1:
		var ray_query = PhysicsRayQueryParameters3D.create(current_from, current_from + aim_dir * remaining_dist)
		ray_query.exclude = exclude_list
		ray_query.collide_with_areas = true
		ray_query.collide_with_bodies = true
		var hit_res = space_state.intersect_ray(ray_query)
		if hit_res.is_empty():
			break
		var col = hit_res.collider
		var is_enemy_or_part = false
		if col:
			if col.is_in_group("enemy") or col.is_in_group("enemy_head") or col.name == "HeadHitbox":
				is_enemy_or_part = true
			elif GameTypes.resolve_damageable(col) != null:
				is_enemy_or_part = true
				
		if is_enemy_or_part:
			if "get_rid" in col:
				exclude_list.append(col.get_rid())
			current_from = hit_res.position + aim_dir * 0.05
			remaining_dist = MAX_BEAM_DIST - from_pos.distance_to(current_from)
		else:
			beam_end = hit_res.position
			break
			
	var beam_vec = beam_end - from_pos
	var beam_len = beam_vec.length()
	if beam_len < 0.1:
		reload()
		return
	var beam_dir = beam_vec / beam_len
	
	var all_enemies = get_tree().get_nodes_in_group("enemy")
	var hit_enemies: Array = []
	const BEAM_TOLERANCE: float = 0.38
	
	for e in all_enemies:
		if not is_instance_valid(e):
			continue
		if ("current_state" in e and e.current_state == e.State.DEAD) or ("health" in e and e.health <= 0):
			continue
			
		var e_pos = e.global_position
		var head_pos = e_pos + Vector3(0.0, 0.55, 0.0)
		var t_head = clamp((head_pos - from_pos).dot(beam_dir), 0.0, beam_len)
		var beam_pt_head = from_pos + beam_dir * t_head
		var dist_to_head = beam_pt_head.distance_to(head_pos)
		
		var t_body = clamp((e_pos - from_pos).dot(beam_dir), 0.0, beam_len)
		var beam_pt_body = from_pos + beam_dir * t_body
		var clamped_body_y = clamp(beam_pt_body.y, e_pos.y - 0.95, e_pos.y + 0.35)
		var body_axis_pt = Vector3(e_pos.x, clamped_body_y, e_pos.z)
		var dist_to_body = beam_pt_body.distance_to(body_axis_pt)
		
		var hit_head = dist_to_head <= (0.34 + BEAM_TOLERANCE)
		var hit_body = dist_to_body <= (0.36 + BEAM_TOLERANCE)
		
		if not hit_head and not hit_body:
			continue
			
		if t_head <= 0.05 and t_body <= 0.05:
			continue
			
		var is_headshot = false
		var hit_pos = beam_pt_body
		var target_dist = t_body
		
		if hit_head and (not hit_body or dist_to_head < dist_to_body or beam_pt_head.y >= e_pos.y + 0.35):
			is_headshot = true
			hit_pos = beam_pt_head
			target_dist = t_head
			
		var los_query = PhysicsRayQueryParameters3D.create(from_pos, hit_pos)
		los_query.collide_with_areas = false
		los_query.collide_with_bodies = true
		los_query.exclude = [player_node]
		var los_res = space_state.intersect_ray(los_query)
		if not los_res.is_empty():
			var blocker = los_res.collider
			if blocker != e and not blocker.is_in_group("enemy") and not blocker.is_in_group("enemy_head"):
				continue
				
		hit_enemies.append({
			"enemy": e,
			"hit_pos": hit_pos,
			"dist": target_dist,
			"is_headshot": is_headshot
		})
		
	hit_enemies.sort_custom(func(a, b): return a["dist"] < b["dist"])
	
	var w = weapons[0]
	var base_dmg = float(w.get("damage", 70))
	var hs_mult = float(w.get("headshot_multiplier", 2.2))
	var air_mult = float(w.get("air_multiplier", 2.0))
	var flat_dir = Vector3(aim_dir.x, 0.0, aim_dir.z).normalized()
	var knockback_vector = flat_dir * float(w.get("knockback", 4.5))
	knockback_vector.y = float(w.get("upward_kick", 0.0))
	
	for item in hit_enemies:
		var target = item["enemy"]
		if not is_instance_valid(target) or ("current_state" in target and target.current_state == target.State.DEAD):
			continue
			
		var is_headshot = item["is_headshot"]
		var target_body = GameTypes.resolve_damageable(target)
		var is_airborne: bool = not target_body.is_on_floor() if (target_body and target_body.has_method("is_on_floor")) else false
			
		var total_mult = 1.0
		if is_headshot and is_airborne:
			total_mult = hs_mult * air_mult
		elif is_headshot:
			total_mult = hs_mult
		elif is_airborne:
			total_mult = air_mult
			
		var final_dmg = int(round(base_dmg * total_mult))
		
		if is_headshot and is_airborne:
			GameTypes.debug_log(&"weapon", "[RAIL SHOT] AIRBORNE HEADSHOT on %s! (%.1fx MULTIPLICATIVE) Damage: %d | Base: %d" % [target.name, total_mult, final_dmg, int(base_dmg)])
		elif is_headshot:
			GameTypes.debug_log(&"weapon", "[RAIL SHOT] HEADSHOT on %s! (%.1fx) Damage: %d | Base: %d" % [target.name, total_mult, final_dmg, int(base_dmg)])
		elif is_airborne:
			GameTypes.debug_log(&"weapon", "[RAIL SHOT] AIRBORNE HIT on %s! (%.1fx) Damage: %d | Base: %d" % [target.name, total_mult, final_dmg, int(base_dmg)])
		else:
			GameTypes.debug_log(&"weapon", "[RAIL SHOT] PIERCING HIT on %s! Damage: %d | Base: %d" % [target.name, final_dmg, int(base_dmg)])
			
		target.take_damage(final_dmg, knockback_vector, item["hit_pos"], false, false, false, is_headshot, -1, "caliber0")
		
	TracerPool.spawn_tracer(start_pos, beam_end, &"piercing")
	apply_vacuum_wake(start_pos, beam_end, 2.5, 25.6, null)
	
	reload()

func _fire_sewing_barrage(has_infinite_ammo: bool = false):
	if sewing_alt_timer > 0.0:
		return
		
	# Тратит 10 игл из общего магазина ЛКМ; если меньше 10 — недоступен (dry_fire)
	if ammos[3] < 10:
		AudioManager.play_sound("dry_fire")
		return
		
	if not has_infinite_ammo:
		ammos[3] -= 10
		
	sewing_alt_timer = sewing_alt_cooldown
	
	head.add_recoil(0.06, 0.22)
	head.trigger_muzzle_flash(false)
	AudioManager.play_sound("needle_shot")
	
	const NEEDLE_COUNT: int = 12
	const NEEDLE_DAMAGE: int = 4
	var aim_dir = head.get_aim_direction()
	var start_pos = head.get_muzzle_position()
	
	# Веерный разброс 12 игл широким сектором (конус разброса 35-40 градусов)
	for i in range(NEEDLE_COUNT):
		var h_frac = (float(i) / float(NEEDLE_COUNT - 1)) * 2.0 - 1.0 # от -1.0 до +1.0
		var spread_x = (h_frac * 0.34) + randf_range(-0.03, 0.03) # дуга ~38 градусов
		var spread_y = randf_range(-0.16, 0.16) # вертикальный разброс ~18 градусов
		
		head.raycast.target_position = Vector3(spread_x * 100.0, spread_y * 100.0, -100.0)
		head.raycast.force_raycast_update()
		var ray = head.raycast
		
		var hit_pos = ray.to_global(ray.target_position)
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
				else:
					target = GameTypes.resolve_damageable(hit)
					
				if target != null and target.has_method("take_damage"):
					var flat_dir = Vector3(aim_dir.x, 0.0, aim_dir.z).normalized()
					var knockback_vector = flat_dir * 1.5 + Vector3.UP * 0.5
					var final_dmg = NEEDLE_DAMAGE
					if is_headshot:
						final_dmg = int(round(float(NEEDLE_DAMAGE) * 1.5))
						
					if target.has_method("add_needle"):
						target.add_needle()
						
					target.take_damage(final_dmg, knockback_vector, hit_pos, false, false, false, is_headshot, -1, "sewing")
					
		TracerPool.spawn_tracer(start_pos, hit_pos, &"needle")
		
	head.raycast.target_position = Vector3(0, 0, -100)
	GameTypes.debug_log(&"weapon", "[SEWING MACHINE] Barrage fired! Needles: %d | Ammos remaining: %d" % [NEEDLE_COUNT, ammos[3]])

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
	elif weapon_idx == 3:
		AudioManager.play_sound("needle_shot")
		
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
				else:
					target = GameTypes.resolve_damageable(hit)
					
				if target != null and target.has_method("take_damage"):
					directly_hit_target = target
					var flat_dir = Vector3(aim_dir.x, 0.0, aim_dir.z).normalized()
					var knockback_vector = flat_dir * float(w.get("knockback", 4.5))
					knockback_vector.y = float(w.get("upward_kick", 0.0))
					
					var target_body = GameTypes.resolve_damageable(target)
					var is_airborne: bool = not target_body.is_on_floor() if (target_body and target_body.has_method("is_on_floor")) else false
						
					var base_dmg = float(w.get("damage", 70))
					var hs_mult = float(w.get("headshot_multiplier", 1.0)) if is_headshot else 1.0
					var air_mult = float(w.get("air_multiplier", 1.0)) if is_airborne else 1.0
					var total_mult = 1.0
					
					if is_headshot and is_airborne:
						if _get_bpm_tier() == GameTypes.BPMTier.OVERDRIVE:
							total_mult = hs_mult * air_mult
						else:
							total_mult = 1.0 + (hs_mult - 1.0) + (air_mult - 1.0)
					elif is_headshot:
						total_mult = hs_mult
					elif is_airborne:
						total_mult = air_mult
						
					var final_multiplier: float = 1.0
					var needle_count: int = 0
					if weapon_idx == 1:
						var enemy_node = GameTypes.resolve_enemy(target)
						if enemy_node and "needle_count" in enemy_node:
							needle_count = enemy_node.needle_count
						elif "needle_count" in target:
							needle_count = target.needle_count
						final_multiplier = 1.0 + min(needle_count, 15) * 0.04
					
					var final_dmg = int(round(base_dmg * total_mult * final_multiplier))
					
					if is_headshot and is_airborne:
						var stack_mode = "MULTIPLICATIVE" if _get_bpm_tier() == GameTypes.BPMTier.OVERDRIVE else "ADDITIVE"
						GameTypes.debug_log(&"weapon", "[%s] AIRBORNE HEADSHOT! (%.1fx, %s) Damage: %d | Base: %d" % [target.name, total_mult, stack_mode, final_dmg, int(base_dmg)])
					elif is_airborne and float(w.get("air_multiplier", 1.0)) > 1.0:
						GameTypes.debug_log(&"weapon", "[%s] AIRBORNE HIT! (%.1fx) Damage: %d | Base: %d" % [target.name, total_mult, final_dmg, int(base_dmg)])
					elif weapon_idx == 1 and needle_count > 0:
						GameTypes.debug_log(&"weapon", "[%s] SHOTGUN PELLET HIT: BaseDmg: %d | Needles: %d | Mult: %.2f | FinalDmg: %d" % [
							target.name, int(base_dmg), needle_count, final_multiplier, final_dmg
						])
						
					if weapon_idx == 2 and target.has_method("apply_poison_dot"):
						target.apply_poison_dot(3.0, 3, 0.5)
					elif weapon_idx == 3 and target.has_method("add_needle"):
						target.add_needle()
						
					var weapon_key = "caliber0"
					match weapon_idx:
						0: weapon_key = "caliber0"
						1: weapon_key = "anvil"
						2: weapon_key = "injector"
						3: weapon_key = "sewing"
					target.take_damage(final_dmg, knockback_vector, hit_pos, false, false, false, is_headshot, -1, weapon_key)
					
		if w.get("has_vacuum", false):
			TracerPool.spawn_tracer(start_pos, hit_pos, &"bullet")
			if not is_alt_fire and _get_bpm_tier() == GameTypes.BPMTier.OVERDRIVE:
				apply_vacuum_wake(start_pos, hit_pos, float(w.get("vacuum_radius", 2.5)), float(w.get("vacuum_force", 25.6)), directly_hit_target)
		elif weapon_idx == 1:
			TracerPool.spawn_tracer(start_pos, hit_pos, &"pellet")
		elif weapon_idx == 2:
			TracerPool.spawn_tracer(start_pos, hit_pos, &"syringe")
		elif weapon_idx == 3:
			TracerPool.spawn_tracer(start_pos, hit_pos, &"needle")

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
