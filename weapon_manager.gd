class_name WeaponManager
extends Node

## Менеджер оружия игрока (WeaponManager).
## Управляет переключением активного оружия, боезапасом (ammos), перезарядкой (активной и пассивной)
## и отрисовкой HUD слотов оружия. Делегирует механику стрельбы экземплярам WeaponBase.

var current_weapon_index: int = 0
var is_reloading: bool = false
var active_reload_timer: float = 0.0
var passive_reload_timers: Array[float] = [0.0, 0.0, 0.0, 0.0]

var weapons: Array[WeaponBase] = []
var ammos: Array[int] = []

var is_bursting: bool:
	get:
		if current_weapon_index >= 0 and current_weapon_index < weapons.size():
			return weapons[current_weapon_index].is_bursting
		return false

@onready var head = $"../Head"
@onready var ammo_label = $"../HUD/AmmoLabel"
@onready var hud = $"../HUD"
@onready var skill_manager = get_node_or_null("../SkillManager")

var weapon_hud_container: VBoxContainer
var weapon_ui_slots: Array = []

func _ready() -> void:
	_init_weapons()
	_init_ammos()
	_setup_weapon_hud()

func _init_weapons() -> void:
	if weapons.is_empty():
		weapons = [
			WeaponCaliber.new(),
			WeaponAnvil.new(),
			WeaponInjector.new(),
			WeaponSewing.new()
		]
		var weapon_names = [&"WeaponCaliber", &"WeaponAnvil", &"WeaponInjector", &"WeaponSewing"]
		for i in range(weapons.size()):
			var w = weapons[i]
			w.name = weapon_names[i]
			w.weapon_manager = self
			w.slot_index = i
			add_child(w)
	else:
		for i in range(weapons.size()):
			var w = weapons[i]
			w.weapon_manager = self
			w.slot_index = i
			if not w.is_inside_tree():
				add_child(w)

func _init_ammos() -> void:
	ammos.clear()
	for w in weapons:
		ammos.append(w.data.max_ammo if (w and w.data) else 0)

func _process(delta: float) -> void:
	var player_node = get_parent()

	# Активная перезарядка удерживаемого оружия
	if is_reloading:
		active_reload_timer -= delta
		if active_reload_timer <= 0.0:
			var active_w = weapons[current_weapon_index]
			ammos[current_weapon_index] = active_w.data.max_ammo if active_w.data else 0
			is_reloading = false
			active_reload_timer = 0.0

	# Автоматическая стрельба при удержании ЛКМ
	if current_weapon_index < weapons.size() and weapons[current_weapon_index].data and weapons[current_weapon_index].data.is_automatic:
		if Input.is_action_pressed("shoot") and not is_reloading and weapons[current_weapon_index].can_fire():
			var inf = false
			if player_node is Player:
				inf = player_node.has_infinite_ammo()
			shoot(inf)

	# Пассивная перезарядка неактивного оружия в фоне
	for i in range(weapons.size()):
		if i != current_weapon_index:
			var w_data = weapons[i].data
			if not w_data:
				continue
			if ammos[i] < w_data.max_ammo:
				passive_reload_timers[i] += delta
				if passive_reload_timers[i] >= w_data.reload_time:
					ammos[i] = w_data.max_ammo
					passive_reload_timers[i] = 0.0
			else:
				passive_reload_timers[i] = 0.0

func switch_weapon(index: int) -> void:
	if is_bursting or index == current_weapon_index or index < 0 or index >= weapons.size():
		return
	# Прерываем активную перезарядку в руках — неактивное оружие дозарядится пассивно в фоне
	if is_reloading:
		is_reloading = false
		active_reload_timer = 0.0
	current_weapon_index = index
	if head:
		head.switch_weapon_visual(index)

func shoot(has_infinite_ammo: bool) -> void:
	if is_reloading or is_bursting:
		return
	var w = weapons[current_weapon_index]
	if not w.can_fire():
		return
	if ammos[current_weapon_index] <= 0:
		reload()
		return
	if not has_infinite_ammo:
		ammos[current_weapon_index] -= 1
	w.fire()

func alt_shoot(has_infinite_ammo: bool = false) -> void:
	if is_bursting:
		return
	var w = weapons[current_weapon_index]
	w.alt_fire(has_infinite_ammo)

func reload() -> void:
	var w = weapons[current_weapon_index]
	if not w.data:
		return
	if ammos[current_weapon_index] == w.data.max_ammo or is_reloading or is_bursting:
		return
	is_reloading = true
	active_reload_timer = w.data.reload_time
	AudioManager.play_sound("reload")

func _setup_weapon_hud() -> void:
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

func _rebuild_weapon_slots() -> void:
	if not weapon_hud_container:
		return
	for child in weapon_hud_container.get_children():
		child.queue_free()
	weapon_ui_slots.clear()
	
	for i in range(weapons.size()):
		var w = weapons[i]
		var w_name = w.data.name if (w and w.data) else ""
		var w_max_ammo = w.data.max_ammo if (w and w.data) else 0
		var current_ammo = ammos[i] if i < ammos.size() else 0
		
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
		name_label.text = "[%d] %s" % [i + 1, w_name]
		name_label.add_theme_font_size_override("font_size", 15)
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hbox.add_child(name_label)
		
		var ammo_text = Label.new()
		ammo_text.text = "%d / %d" % [current_ammo, w_max_ammo]
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

func update_hud(has_infinite_ammo: bool) -> void:
	if not weapon_hud_container:
		_setup_weapon_hud()
	if weapon_ui_slots.size() != weapons.size():
		_rebuild_weapon_slots()
		
	for i in range(weapons.size()):
		if i >= weapon_ui_slots.size():
			continue
		var w = weapons[i]
		if not w or not w.data:
			continue
		var slot = weapon_ui_slots[i]
		var is_active = (i == current_weapon_index)
		var alt_suffix = w.get_alt_hud_suffix(has_infinite_ammo)
		
		var sb = StyleBoxFlat.new()
		if is_active:
			# Активное оружие: янтарная плашка слева, яркий текст
			sb.bg_color = Color(0.12, 0.14, 0.18, 0.9)
			sb.border_color = Color(0.95, 0.72, 0.20, 1.0)
			sb.set_border_width_all(1)
			sb.border_width_left = 5
			sb.set_corner_radius_all(3)
			slot["panel"].add_theme_stylebox_override("panel", sb)
			
			slot["name_label"].text = "[%d] %s" % [i + 1, w.data.name]
			slot["name_label"].add_theme_color_override("font_color", Color(1.0, 0.88, 0.35, 1.0))
			
			if is_reloading:
				var progress = clamp((w.data.reload_time - active_reload_timer) / max(0.001, w.data.reload_time), 0.0, 1.0)
				slot["ammo_text"].text = ("RELOAD %d%%" % int(progress * 100.0)) + alt_suffix
				slot["ammo_text"].add_theme_color_override("font_color", Color(1.0, 0.6, 0.1, 1.0))
				slot["pbar"].visible = true
				slot["pbar"].value = progress * 100.0
				slot["pbar_fg"].bg_color = Color(0.95, 0.65, 0.15, 1.0)
			elif is_bursting:
				slot["ammo_text"].text = "%d / %d (BURST)" % [ammos[i], w.data.max_ammo]
				slot["ammo_text"].add_theme_color_override("font_color", Color(1.0, 0.3, 0.3, 1.0))
				slot["pbar"].visible = false
			elif has_infinite_ammo:
				slot["ammo_text"].text = "INF (OVERDRIVE)" + alt_suffix
				slot["ammo_text"].add_theme_color_override("font_color", Color(1.0, 0.2, 0.2, 1.0))
				slot["pbar"].visible = false
			else:
				slot["ammo_text"].text = ("%d / %d" % [ammos[i], w.data.max_ammo]) + alt_suffix
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
			
			slot["name_label"].text = "[%d] %s" % [i + 1, w.data.name]
			slot["name_label"].add_theme_color_override("font_color", Color(0.65, 0.68, 0.72, 0.8))
			
			if ammos[i] < w.data.max_ammo:
				var p_progress = clamp(passive_reload_timers[i] / max(0.001, w.data.reload_time), 0.0, 1.0)
				slot["ammo_text"].text = "%d / %d (%d%%)" % [ammos[i], w.data.max_ammo, int(p_progress * 100.0)]
				slot["ammo_text"].add_theme_color_override("font_color", Color(0.3, 0.8, 1.0, 0.9))
				slot["pbar"].visible = true
				slot["pbar"].value = p_progress * 100.0
				slot["pbar_fg"].bg_color = Color(0.2, 0.75, 1.0, 0.9)
			else:
				slot["ammo_text"].text = "%d / %d" % [ammos[i], w.data.max_ammo]
				slot["ammo_text"].add_theme_color_override("font_color", Color(0.6, 0.6, 0.6, 0.7))
				slot["pbar"].visible = false
