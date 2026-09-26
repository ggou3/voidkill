class_name HUD
extends CanvasLayer

## Единый менеджер пользовательского интерфейса (HUD).
## Инкапсулирует отображение полосы здоровья, слотов оружия, счётчика дэшей,
## BPM, боевого моментума, всплывающих комбо-сообщений и экрана Game Over.
## Подписывается на сигналы игровых систем (Player, WeaponManager, SkillManager, GameManager).

# Ссылки на дочерние UI-узлы сцены HUD
@onready var crosshair: ColorRect = get_node_or_null("Crosshair")
@onready var ammo_label: Label = get_node_or_null("AmmoLabel")
@onready var dash_label: Label = get_node_or_null("DashLabel")
@onready var combo_label: Label = get_node_or_null("ComboLabel")
@onready var bpm_label: Label = get_node_or_null("BPMLabel")
@onready var momentum_label: Label = get_node_or_null("MomentumLabel")
@onready var health_bar: ProgressBar = get_node_or_null("HealthBar")
@onready var hp_text: Label = get_node_or_null("HealthBar/HPText")
@onready var speed_label: Label = get_node_or_null("SpeedLabel")
@onready var blood_buff_label: Label = get_node_or_null("BloodBuffLabel")
@onready var game_over_screen: Control = get_node_or_null("GameOverScreen")
@onready var restart_button: Button = get_node_or_null("GameOverScreen/VBoxContainer/RestartButton")

# Ссылки на игровые системы
var player: Player = null
var weapon_manager: WeaponManager = null
var skill_manager: SkillManager = null

# Визуальные стили и твины полосы здоровья
var _health_bg_style: StyleBoxFlat
var _health_fill_style: StyleBoxFlat
var _health_tween: Tween = null
var _last_displayed_health: int = -1

# Параметры анимации комбо-попапов
var combo_tween: Tween = null

# Параметры анимации боевого моментума
var momentum_idle_timer: float = 0.0
var momentum_display_alpha: float = 1.0
var momentum_font_size: int = 28

# Управление списком слотов оружия
var weapon_hud_container: VBoxContainer
var weapon_ui_slots: Array = []

func _ready() -> void:
	_init_static_elements()
	call_deferred("_connect_systems")

func _init_static_elements() -> void:
	if ammo_label:
		ammo_label.visible = false
	if game_over_screen:
		game_over_screen.visible = false
	if crosshair:
		crosshair.visible = true
	if restart_button:
		restart_button.pressed.connect(_on_restart_pressed)
		
	_setup_health_bar()
	_setup_weapon_hud_container()

func _connect_systems() -> void:
	# Подключение к Player
	var p = get_parent()
	if p is Player:
		player = p
		player.health_changed.connect(_on_player_health_changed)
		player.speed_updated.connect(_on_player_speed_updated)
		player.blood_surf_status_changed.connect(_on_blood_surf_changed)
		player.died.connect(_on_player_died)
		update_health(player.health, player.max_health, false)

	# Подключение к SkillManager
	var sm = get_node_or_null("../SkillManager")
	if sm is SkillManager:
		skill_manager = sm
		skill_manager.hud_popup_requested.connect(show_popup)

	# Подключение к WeaponManager
	var wm = get_node_or_null("../WeaponManager")
	if wm is WeaponManager:
		weapon_manager = wm
		_rebuild_weapon_slots()

	# Подключение к GameManager
	var gm = get_node_or_null("/root/GameManager")
	if gm and gm.has_signal("game_over_triggered"):
		if not gm.game_over_triggered.is_connected(_on_game_over):
			gm.game_over_triggered.connect(_on_game_over)

func _process(delta: float) -> void:
	if skill_manager:
		_process_skill_hud(delta)
	if weapon_manager:
		_process_weapon_hud(delta)

# --- Здоровье ---

func _setup_health_bar() -> void:
	if not health_bar:
		return
		
	_health_bg_style = StyleBoxFlat.new()
	_health_bg_style.bg_color = Color(0.08, 0.08, 0.09, 0.85)
	_health_bg_style.border_color = Color(0.35, 0.35, 0.38, 0.9)
	_health_bg_style.set_border_width_all(2)
	_health_bg_style.set_corner_radius_all(3)
	
	_health_fill_style = StyleBoxFlat.new()
	_health_fill_style.bg_color = Color(0.2, 0.85, 0.3, 1.0)
	_health_fill_style.set_corner_radius_all(2)
	
	health_bar.add_theme_stylebox_override("background", _health_bg_style)
	health_bar.add_theme_stylebox_override("fill", _health_fill_style)

func update_health(current_hp: int, max_hp: int, animate: bool = true) -> void:
	_last_displayed_health = current_hp
	var display_hp = max(0, current_hp)
	
	if hp_text:
		hp_text.text = "%d / %d" % [display_hp, max_hp]
		
	if not health_bar:
		return
		
	health_bar.max_value = max_hp
	
	# Пороги здоровья:
	# > 50%: Зеленый / нейтральный
	# 25% - 50%: Желтый
	# < 25%: Красный критический
	var ratio = float(display_hp) / float(max_hp) if max_hp > 0 else 0.0
	var target_color: Color
	if ratio > 0.5:
		target_color = Color(0.2, 0.85, 0.3, 1.0)
	elif ratio >= 0.25:
		target_color = Color(0.95, 0.8, 0.15, 1.0)
	else:
		target_color = Color(0.95, 0.2, 0.2, 1.0)
		
	if animate and is_inside_tree():
		if _health_tween and _health_tween.is_valid():
			_health_tween.kill()
		_health_tween = create_tween().set_parallel(true)
		_health_tween.tween_property(health_bar, "value", float(display_hp), 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		if _health_fill_style:
			_health_tween.tween_property(_health_fill_style, "bg_color", target_color, 0.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	else:
		if _health_tween and _health_tween.is_valid():
			_health_tween.kill()
		health_bar.value = float(display_hp)
		if _health_fill_style:
			_health_fill_style.bg_color = target_color

func _on_player_health_changed(current: int, maximum: int) -> void:
	update_health(current, maximum, true)

func _on_player_died() -> void:
	update_health(0, player.max_health if player else 100, false)

# --- Скорость и Блад-сёрф ---

func _on_player_speed_updated(current_speed: float, bhop_chain: int) -> void:
	if not speed_label:
		return
	var bhop_text = ""
	if bhop_chain > 0:
		bhop_text = (" (BHOP x" + str(bhop_chain) + ")")
	speed_label.text = "SPEED: " + str(snapped(current_speed, 0.1)) + bhop_text

func _on_blood_surf_changed(active: bool) -> void:
	if not blood_buff_label:
		return
	blood_buff_label.visible = active
	if active:
		blood_buff_label.text = "★ BLOOD SURF (MOMENTUM +4%) ★"

# --- Скиллы (BPM, Momentum, Dash, Popups) ---

func _process_skill_hud(delta: float) -> void:
	# 1. BPM
	if bpm_label:
		var bpm_val = skill_manager.bpm
		var tier = skill_manager.get_bpm_tier()
		bpm_label.text = "BPM: %d (%s)" % [int(round(bpm_val)), GameTypes.tier_to_string(tier)]
		
	# 2. Combat Momentum
	if momentum_label:
		var combat_momentum = skill_manager.combat_momentum
		if combat_momentum <= 1.001:
			momentum_idle_timer += delta
		else:
			momentum_idle_timer = 0.0
			
		momentum_label.text = "MOMENTUM: ×%.2f" % combat_momentum
		var t: float = clampf(combat_momentum - 1.0, 0.0, 1.0)
		var neutral_color: Color = Color(1.0, 1.0, 1.0, 1.0)
		var gold_color: Color = Color(1.0, 0.82, 0.2, 1.0)
		var active_color: Color = neutral_color.lerp(gold_color, t)
		
		var is_dimmed: bool = (combat_momentum <= 1.001 and momentum_idle_timer >= 2.0)
		if is_dimmed:
			momentum_display_alpha = move_toward(momentum_display_alpha, 0.45, 2.0 * delta)
			if momentum_font_size != 24:
				momentum_font_size = 24
				momentum_label.add_theme_font_size_override("font_size", 24)
		else:
			momentum_display_alpha = 1.0
			if momentum_font_size != 28:
				momentum_font_size = 28
				momentum_label.add_theme_font_size_override("font_size", 28)
				
		momentum_label.add_theme_color_override("font_color", active_color)
		momentum_label.modulate.a = momentum_display_alpha
		
	# 3. Dash
	if dash_label:
		var dashes = skill_manager.dashes
		var max_dashes = skill_manager.MAX_DASH
		var dash_timer_cd = skill_manager.dash_timer_cd
		var dash_interval_timer = skill_manager.dash_interval_timer
		var is_dashing = skill_manager.is_dashing
		
		if dashes == 0:
			dash_label.text = "DASH: 0 (+" + str(snapped(dash_timer_cd, 0.1)) + "s)"
		elif dash_interval_timer > 0.0 or is_dashing:
			var int_sec = max(0.1, snapped(dash_interval_timer, 0.1))
			dash_label.text = "DASH: " + str(dashes) + " (COOLDOWN " + str(int_sec) + "s)"
		elif dashes < max_dashes:
			dash_label.text = "DASH: " + str(dashes) + " (READY, +" + str(snapped(dash_timer_cd, 0.1)) + "s)"
		else:
			dash_label.text = "DASH: " + str(max_dashes) + " (READY)"

func show_popup(text: String) -> void:
	if not combo_label:
		return
		
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

# --- Оружие (WeaponHUDList) ---

func _setup_weapon_hud_container() -> void:
	if has_node("WeaponHUDList"):
		weapon_hud_container = get_node("WeaponHUDList")
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
		add_child(weapon_hud_container)

func _rebuild_weapon_slots() -> void:
	if not weapon_hud_container or not weapon_manager:
		return
	for child in weapon_hud_container.get_children():
		child.queue_free()
	weapon_ui_slots.clear()
	
	for i in range(weapon_manager.weapons.size()):
		var w = weapon_manager.weapons[i]
		var w_name = w.data.name if (w and w.data) else ""
		var w_max_ammo = w.data.max_ammo if (w and w.data) else 0
		var current_ammo = weapon_manager.ammos[i] if i < weapon_manager.ammos.size() else 0
		
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

func _process_weapon_hud(_delta: float) -> void:
	if not weapon_hud_container:
		_setup_weapon_hud_container()
	if weapon_ui_slots.size() != weapon_manager.weapons.size():
		_rebuild_weapon_slots()
		
	var has_infinite_ammo = player.has_infinite_ammo() if is_instance_valid(player) else false
	
	for i in range(weapon_manager.weapons.size()):
		if i >= weapon_ui_slots.size():
			continue
		var w = weapon_manager.weapons[i]
		if not w or not w.data:
			continue
		var slot = weapon_ui_slots[i]
		var is_active = (i == weapon_manager.current_weapon_index)
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
			
			if weapon_manager.is_reloading:
				var progress = clamp((w.data.reload_time - weapon_manager.active_reload_timer) / max(0.001, w.data.reload_time), 0.0, 1.0)
				slot["ammo_text"].text = ("RELOAD %d%%" % int(progress * 100.0)) + alt_suffix
				slot["ammo_text"].add_theme_color_override("font_color", Color(1.0, 0.6, 0.1, 1.0))
				slot["pbar"].visible = true
				slot["pbar"].value = progress * 100.0
				slot["pbar_fg"].bg_color = Color(0.95, 0.65, 0.15, 1.0)
			elif weapon_manager.is_bursting:
				slot["ammo_text"].text = "%d / %d (BURST)" % [weapon_manager.ammos[i], w.data.max_ammo]
				slot["ammo_text"].add_theme_color_override("font_color", Color(1.0, 0.3, 0.3, 1.0))
				slot["pbar"].visible = false
			elif has_infinite_ammo:
				slot["ammo_text"].text = "INF (OVERDRIVE)" + alt_suffix
				slot["ammo_text"].add_theme_color_override("font_color", Color(1.0, 0.2, 0.2, 1.0))
				slot["pbar"].visible = false
			else:
				slot["ammo_text"].text = ("%d / %d" % [weapon_manager.ammos[i], w.data.max_ammo]) + alt_suffix
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
			
			if weapon_manager.ammos[i] < w.data.max_ammo:
				var p_progress = clamp(weapon_manager.passive_reload_timers[i] / max(0.001, w.data.reload_time), 0.0, 1.0)
				slot["ammo_text"].text = "%d / %d (%d%%)" % [weapon_manager.ammos[i], w.data.max_ammo, int(p_progress * 100.0)]
				slot["ammo_text"].add_theme_color_override("font_color", Color(0.3, 0.8, 1.0, 0.9))
				slot["pbar"].visible = true
				slot["pbar"].value = p_progress * 100.0
				slot["pbar_fg"].bg_color = Color(0.2, 0.75, 1.0, 0.9)
			else:
				slot["ammo_text"].text = "%d / %d" % [weapon_manager.ammos[i], w.data.max_ammo]
				slot["ammo_text"].add_theme_color_override("font_color", Color(0.6, 0.6, 0.6, 0.7))
				slot["pbar"].visible = false

# --- Game Over & Рестарт ---

func _on_game_over() -> void:
	if game_over_screen:
		game_over_screen.visible = true
	if crosshair:
		crosshair.visible = false

func _on_restart_pressed() -> void:
	var gm = get_node_or_null("/root/GameManager")
	if gm and gm.has_method("restart_game"):
		gm.restart_game()
	elif player and player.has_method("restart_game"):
		player.restart_game()
	else:
		get_tree().reload_current_scene()
