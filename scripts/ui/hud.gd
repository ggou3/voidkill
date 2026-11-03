class_name HUD
extends CanvasLayer

## Единый менеджер пользовательского интерфейса (HUD).
## Инкапсулирует отображение резервуара HP (HealthFlask), карточки оружия в руке (WeaponCard), счётчика дэшей,
## индикатора BPM (сердце и ЭКГ, виньетка и дрожь HUD на высоком BPM), боевого моментума,
## всплывающих комбо-сообщений, счётчика врагов сектора и экрана Game Over.
## Панели по углам рисуются в SubViewport и выводятся с выпуклостью экрана (shaders/hud_curve.gdshader).
## Подписывается на сигналы игровых систем (Player, WeaponManager, SkillManager, BPMSystem, GameManager).

# Ссылки на дочерние UI-узлы сцены HUD
@onready var crosshair: ColorRect = get_node_or_null("Crosshair")
@onready var ammo_label: Label = get_node_or_null("AmmoLabel")
@onready var dash_label: Label = get_node_or_null("DashLabel")
@onready var combo_label: Label = get_node_or_null("ComboLabel")
@onready var momentum_label: Label = get_node_or_null("MomentumLabel")
@onready var speed_label: Label = get_node_or_null("SpeedLabel")
@onready var blood_buff_label: Label = get_node_or_null("BloodBuffLabel")
@onready var game_over_screen: Control = get_node_or_null("GameOverScreen")
@onready var restart_button: Button = get_node_or_null("GameOverScreen/VBoxContainer/RestartButton")
var restart_level_button: Button = null
var main_menu_button: Button = null
var enemies_label: Label = null
var damage_indicator: DamageIndicator = null
var bpm_hint: BPMHint = null
var heart_monitor: HeartMonitor = null
var bpm_vignette: BPMVignette = null
var health_flask: HealthFlask = null
var weapon_card: WeaponCard = null
var pause_menu: PauseMenu = null

# Ссылки на игровые системы
var player: Player = null
var weapon_manager: WeaponManager = null
var skill_manager: SkillManager = null
var bpm_system: BPMSystem = null

# Раскладка панелей по углам: отступ от краёв экрана (по выпуклости рамки углы и так уходят к центру)
const HUD_MARGIN: Vector2 = Vector2(48.0, 40.0)
const HEART_SCALE: float = 0.85
## Резервуар HP крупнее остальных панелей: 54×120 → 76×168; подписи моментума и дэша в player.tscn — справа от него
const FLASK_SCALE: float = 1.4
# Попап комбо (вне покачивания): всплывает над моментумом
const COMBO_Y: float = 500.0

# Параметры анимации комбо-попапов
var combo_tween: Tween = null

# Параметры анимации боевого моментума
const MOMENTUM_FONT: int = 22
const MOMENTUM_FONT_IDLE: int = 19
var momentum_idle_timer: float = 0.0
var momentum_display_alpha: float = 1.0
var momentum_font_size: int = MOMENTUM_FONT

# Выпуклость панелей: SubViewport с панелями и прямоугольник на весь экран, выводящий его с искажением
const CURVE_SHADER: Shader = preload("res://shaders/hud_curve.gdshader")
var _curve_viewport: SubViewport = null
var _curve_rect: ColorRect = null

# Покачивание HUD (ноябрь 2026): панели по углам (HP, BPM, моментум, дэш, скорость, оружие, счётчик врагов)
# лежат в общем узле SwayRoot (внутри SubViewport выпуклости) и смещаются от поворота камеры, движения, прыжков и приземлений, вздрагивают
# от отдачи и урона. Прицел, подсказки у прицела, попап комбо, индикатор урона и экраны смерти/конца уровня
# остаются на месте — стрелять по прицелу покачивание не мешает
## Сила покачивания HUD: 0 — выключено, 1 — по умолчанию
@export var sway_strength: float = 1.0
const SWAY_LOOK: float = 2.5 # px на рад/с поворота камеры (HUD отстаёт от поворота)
const SWAY_MOVE: float = 0.5 # px на м/с скорости вбок
const SWAY_VERTICAL: float = 0.35 # px на м/с вертикальной скорости
const SWAY_MAX: float = 26.0 # px — предел смещения
const SWAY_ROLL: float = 0.0012 # рад крена на px смещения по горизонтали
const SWAY_STIFFNESS: float = 140.0 # пружина возврата
const SWAY_DAMPING: float = 16.0
const SWAY_RECOIL_KICK: float = 6000.0 # px/с толчка вниз на рад отдачи камеры (выстрел, жёсткое приземление)
const SWAY_LAND_KICK: float = 22.0 # px/с толчка вниз на м/с скорости падения сверх SWAY_LAND_MIN_SPEED
const SWAY_LAND_MIN_SPEED: float = 5.0
const SWAY_HIT_KICK: float = 14.0 # px/с толчка на HP урона, от стороны удара
const SWAY_KICK_MAX: float = 700.0
var _sway_root: Control = null
var _sway_pos: Vector2 = Vector2.ZERO
var _sway_vel: Vector2 = Vector2.ZERO
var _prev_look: Vector2 = Vector2.ZERO # (рысканье, тангаж) прошлого кадра
var _prev_recoil: float = 0.0
var _was_on_floor: bool = true
var _air_min_vy: float = 0.0

# Дрожь HUD на высоком BPM: мелкая вибрация панелей и толчок вниз на каждый удар сердца. Нарастает с начала
# SURGING до 200 BPM, прицел не трогает (как и покачивание)
const SHAKE_FROM_RATIO: float = 0.6 # 140 BPM
const SHAKE_MAX: float = 2.0 # px вибрации на 200 BPM
const SHAKE_BEAT: float = 2.5 # px толчка на удар на 200 BPM
var _shake_time: float = 0.0

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

	_setup_sway_root()
	_setup_bpm_indicator()
	_setup_health_flask()
	_setup_weapon_card()
	_setup_feedback_elements()
	pause_menu = PauseMenu.new()
	pause_menu.name = "PauseMenu"
	add_child(pause_menu)

## Индикатор направления урона и подсказка BPM у прицела — под экранами смерти и конца уровня
func _setup_feedback_elements() -> void:
	damage_indicator = DamageIndicator.new()
	damage_indicator.name = "DamageIndicator"
	add_child(damage_indicator)
	bpm_hint = BPMHint.new()
	bpm_hint.name = "BPMHint"
	add_child(bpm_hint)
	if game_over_screen:
		move_child(damage_indicator, game_over_screen.get_index())
		move_child(bpm_hint, game_over_screen.get_index())

func _connect_systems() -> void:
	# Подключение к Player
	var p = get_parent()
	if p is Player:
		player = p
		player.health_changed.connect(_on_player_health_changed)
		player.speed_updated.connect(_on_player_speed_updated)
		player.blood_surf_status_changed.connect(_on_blood_surf_changed)
		player.died.connect(_on_player_died)
		player.damaged.connect(_on_player_damaged)
		damage_indicator.player = player
		health_flask.player = player
		update_health(player.health, player.max_health, false)

	# Подключение к SkillManager
	var sm = get_node_or_null("../SkillManager")
	if sm is SkillManager:
		skill_manager = sm
		skill_manager.hud_popup_requested.connect(show_popup)

	# Подключение к BPMSystem
	var bs = get_node_or_null("../BPMSystem")
	if bs is BPMSystem:
		bpm_system = bs
		bpm_system.hud_popup_requested.connect(show_popup)
		bpm_system.bpm_event.connect(bpm_hint.on_bpm_event)
		heart_monitor.bpm_system = bpm_system
		heart_monitor.player = player
		weapon_card.bpm_system = bpm_system

	# Подключение к WeaponManager
	var wm = get_node_or_null("../WeaponManager")
	if wm is WeaponManager:
		weapon_manager = wm
		weapon_card.weapon_manager = weapon_manager

	# Подключение к GameManager
	var gm = get_node_or_null("/root/GameManager")
	if gm and gm.has_signal("game_over_triggered"):
		if not gm.game_over_triggered.is_connected(_on_game_over):
			gm.game_over_triggered.connect(_on_game_over)
		if not gm.player_respawned.is_connected(_on_player_respawned):
			gm.player_respawned.connect(_on_player_respawned)
		if not gm.level_completed.is_connected(_on_level_completed):
			gm.level_completed.connect(_on_level_completed)
		if not gm.enemy_health_bars_toggled.is_connected(_on_enemy_health_bars_toggled):
			gm.enemy_health_bars_toggled.connect(_on_enemy_health_bars_toggled)

func _process(delta: float) -> void:
	if skill_manager:
		_process_skill_hud(delta)
	_process_level_hud()
	bpm_vignette.set_state(heart_monitor.ratio, heart_monitor.pulse)
	_process_sway(delta)

# --- Покачивание HUD ---

## Общий узел панелей, которые покачиваются: на весь экран, внутри SubViewport выпуклости. Панели переносятся
## в него без пересчёта якорей — родитель на весь экран, раскладка прежняя
func _setup_sway_root() -> void:
	_setup_curve_viewport()
	_sway_root = Control.new()
	_sway_root.name = "SwayRoot"
	_sway_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_curve_viewport.add_child(_sway_root)
	_sway_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for node in [ammo_label, dash_label, momentum_label, speed_label, blood_buff_label]:
		if node:
			node.reparent(_sway_root, false)

## Выпуклый «телевизор»: панели и виньетка рисуются в прозрачный SubViewport в полном разрешении окна (в
## логических координатах HUD), а прямоугольник под прицелом (индекс 0) выводит его с выпуклостью экрана.
## Прицел, подсказки у прицела, попап комбо, индикатор урона и экраны смерти/конца уровня — плоские, без
## искажения: на кнопках экранов совпадает курсор
func _setup_curve_viewport() -> void:
	_curve_viewport = SubViewport.new()
	_curve_viewport.name = "CurvedPanels"
	_curve_viewport.transparent_bg = true
	_curve_viewport.disable_3d = true
	_curve_viewport.size_2d_override_stretch = true
	add_child(_curve_viewport)
	_curve_rect = ColorRect.new()
	_curve_rect.name = "CurvedPanelsScreen"
	_curve_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat: ShaderMaterial = ShaderMaterial.new()
	mat.shader = CURVE_SHADER
	mat.set_shader_parameter("hud_tex", _curve_viewport.get_texture())
	_curve_rect.material = mat
	add_child(_curve_rect)
	move_child(_curve_rect, 0)
	_curve_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	get_viewport().size_changed.connect(_resize_curve_viewport)
	_resize_curve_viewport()

func _resize_curve_viewport() -> void:
	var logical: Vector2 = get_viewport().get_visible_rect().size
	var physical: Vector2i = get_window().size if get_window() else Vector2i(logical)
	_curve_viewport.size = Vector2i(maxi(physical.x, 1), maxi(physical.y, 1))
	_curve_viewport.size_2d_override = Vector2i(logical)

## Индикатор BPM — в левом верхнем углу среди покачивающихся панелей; виньетка — на весь экран под всеми
## панелями (первая в SubViewport выпуклости)
func _setup_bpm_indicator() -> void:
	heart_monitor = HeartMonitor.new()
	heart_monitor.name = "HeartMonitor"
	heart_monitor.position = HUD_MARGIN
	heart_monitor.scale = Vector2.ONE * HEART_SCALE
	_panels_parent().add_child(heart_monitor)
	bpm_vignette = BPMVignette.new()
	bpm_vignette.name = "BPMVignette"
	_curve_viewport.add_child(bpm_vignette)
	_curve_viewport.move_child(bpm_vignette, 0)

## Резервуар HP — в левом нижнем углу
func _setup_health_flask() -> void:
	health_flask = HealthFlask.new()
	health_flask.name = "HealthFlask"
	_panels_parent().add_child(health_flask)
	_anchor_corner(health_flask, HealthFlask.PANEL_SIZE, false, true, FLASK_SCALE)

## Карточка оружия в руке — в правом нижнем углу
func _setup_weapon_card() -> void:
	weapon_card = WeaponCard.new()
	weapon_card.name = "WeaponCard"
	_panels_parent().add_child(weapon_card)
	_anchor_corner(weapon_card, WeaponCard.CARD_SIZE, true, true)

## Привязка панели размера panel_size к углу экрана с отступом HUD_MARGIN; ui_scale — масштаб панели (от её
## левого верхнего угла), отступ считается по увеличенному размеру
func _anchor_corner(node: Control, panel_size: Vector2, right: bool, bottom: bool, ui_scale: float = 1.0) -> void:
	var visual: Vector2 = panel_size * ui_scale
	node.anchor_left = 1.0 if right else 0.0
	node.anchor_right = node.anchor_left
	node.anchor_top = 1.0 if bottom else 0.0
	node.anchor_bottom = node.anchor_top
	node.offset_left = -HUD_MARGIN.x - visual.x if right else HUD_MARGIN.x
	node.offset_right = node.offset_left + panel_size.x
	node.offset_top = -HUD_MARGIN.y - visual.y if bottom else HUD_MARGIN.y
	node.offset_bottom = node.offset_top + panel_size.y
	node.scale = Vector2.ONE * ui_scale

## Куда добавлять панели, созданные кодом (список оружия, счётчик врагов) — в покачивающийся узел
func _panels_parent() -> Node:
	return _sway_root if _sway_root else self

func _process_sway(delta: float) -> void:
	if not _sway_root or delta <= 0.0:
		return
	var target: Vector2 = Vector2.ZERO
	var active: bool = is_instance_valid(player) and not player.is_dead and sway_strength > 0.0 \
			and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED
	if active:
		target = _sway_target(delta)
		_sway_events()
	else:
		_sway_vel = Vector2.ZERO
	# Пружина к цели: смещение догоняет её с затуханием, толчки событий — в скорость пружины
	var accel: Vector2 = (target - _sway_pos) * SWAY_STIFFNESS - _sway_vel * SWAY_DAMPING
	_sway_vel += accel * delta
	_sway_pos += _sway_vel * delta
	_sway_pos = _sway_pos.limit_length(SWAY_MAX * 1.5)
	_sway_root.position = _sway_pos + _bpm_shake(delta)
	_sway_root.pivot_offset = _sway_root.size * 0.5
	_sway_root.rotation = _sway_pos.x * SWAY_ROLL

## Цель смещения: отставание от поворота камеры, от скорости вбок и по вертикали
func _sway_target(delta: float) -> Vector2:
	var look: Vector2 = Vector2.ZERO
	if player.head:
		var rot: Vector3 = player.head.global_rotation
		look = Vector2(rot.y, rot.x)
	var look_vel: Vector2 = Vector2(angle_difference(_prev_look.x, look.x), angle_difference(_prev_look.y, look.y)) / delta
	_prev_look = look
	var local_vel: Vector3 = player.global_basis.inverse() * player.velocity
	var target: Vector2 = look_vel * SWAY_LOOK
	target.x -= local_vel.x * SWAY_MOVE
	target.y += player.velocity.y * SWAY_VERTICAL
	return (target * sway_strength).limit_length(SWAY_MAX)

## Толчки: отдача камеры (выстрел, жёсткое приземление) и приземление — вниз
func _sway_events() -> void:
	if player.head:
		var recoil: float = player.head.camera_recoil
		var added: float = _prev_recoil - recoil # отдача копится в минус
		_prev_recoil = recoil
		if added > 0.0005:
			_sway_kick(Vector2(randf_range(-0.25, 0.25), 1.0) * added * SWAY_RECOIL_KICK)
	var on_floor: bool = player.is_on_floor()
	if not on_floor:
		_air_min_vy = minf(_air_min_vy, player.velocity.y)
	elif not _was_on_floor:
		var impact: float = -_air_min_vy - SWAY_LAND_MIN_SPEED
		if impact > 0.0:
			_sway_kick(Vector2(0.0, impact * SWAY_LAND_KICK))
		_air_min_vy = 0.0
	_was_on_floor = on_floor

func _sway_kick(impulse: Vector2) -> void:
	_sway_vel += (impulse * sway_strength).limit_length(SWAY_KICK_MAX)

## Дрожь от BPM поверх покачивания: сумма синусов ~11–21 Гц (вибрация без случайного мерцания) и толчок вниз
## по огибающей удара сердца
func _bpm_shake(delta: float) -> Vector2:
	var k: float = smoothstep(SHAKE_FROM_RATIO, 1.0, heart_monitor.ratio) * sway_strength
	if k <= 0.0:
		return Vector2.ZERO
	_shake_time += delta
	var t: float = _shake_time
	var jitter: Vector2 = Vector2(sin(t * 71.0) + 0.5 * sin(t * 113.0), sin(t * 89.0 + 1.3) + 0.5 * sin(t * 131.0)) / 1.5
	return (jitter * SHAKE_MAX + Vector2(0.0, heart_monitor.pulse * SHAKE_BEAT)) * k

# --- Здоровье ---

func update_health(current_hp: int, max_hp: int, animate: bool = true) -> void:
	health_flask.set_health(current_hp, max_hp, animate)

func _on_player_health_changed(current: int, maximum: int) -> void:
	update_health(current, maximum, true)

func _on_player_died() -> void:
	update_health(0, player.max_health if player else 100, false)
	damage_indicator.clear()
	bpm_hint.clear()

## Отладка (H): подтверждение переключения полосок HP врагов
func _on_enemy_health_bars_toggled(bars_visible: bool) -> void:
	show_popup("HP BARS: ON" if bars_visible else "HP BARS: OFF")

func _on_player_damaged(amount: int, from_dir: Vector3) -> void:
	damage_indicator.add_hit(from_dir, amount)
	health_flask.on_damage(amount)
	# HUD вздрагивает в сторону от удара (сбоку — вбок, спереди — вниз)
	if is_instance_valid(player) and sway_strength > 0.0:
		var local_dir: Vector3 = player.global_basis.inverse() * from_dir
		var away: Vector2 = Vector2(-local_dir.x, 0.6).normalized()
		_sway_kick(away * float(amount) * SWAY_HIT_KICK)

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
	# 1. BPM — индикатор HeartMonitor обновляется сам
	# 2. Combat Momentum
	if momentum_label and bpm_system:
		var combat_momentum = bpm_system.combat_momentum
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
			if momentum_font_size != MOMENTUM_FONT_IDLE:
				momentum_font_size = MOMENTUM_FONT_IDLE
				momentum_label.add_theme_font_size_override("font_size", MOMENTUM_FONT_IDLE)
		else:
			momentum_display_alpha = 1.0
			if momentum_font_size != MOMENTUM_FONT:
				momentum_font_size = MOMENTUM_FONT
				momentum_label.add_theme_font_size_override("font_size", MOMENTUM_FONT)
				
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
	combo_label.position.y = COMBO_Y
	
	combo_tween = create_tween()
	# Плавное всплытие вверх на 10px за 1.2 секунды
	combo_tween.tween_property(combo_label, "position:y", COMBO_Y - 10.0, 1.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	# Держится на экране 0.7с, затем плавное исчезновение (fade out) 0.5с
	combo_tween.parallel().tween_property(combo_label, "modulate:a", 1.0, 0.7)
	combo_tween.chain().tween_property(combo_label, "modulate:a", 0.0, 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	combo_tween.chain().tween_callback(func(): if is_instance_valid(combo_label): combo_label.visible = false)

# --- Счётчик врагов сектора ---

## Сколько врагов осталось в текущей волне активного сектора (Охотник не считается) и номер волны.
## Виден только на уровне, пока идёт бой в секторе.
func _process_level_hud() -> void:
	var sector: Sector = null
	var gm = get_node_or_null("/root/GameManager")
	if gm and gm.is_level_active() and gm.level is LevelController:
		sector = gm.level.get_active_sector()
	if not sector:
		if enemies_label:
			enemies_label.visible = false
		return
	var label = _ensure_enemies_label()
	label.visible = true
	var text = "ВРАГИ: %d" % sector.get_remaining_count()
	if sector.get_wave_count() > 1:
		text += "   ВОЛНА %d/%d" % [sector.current_wave + 1, sector.get_wave_count()]
	label.text = text

func _ensure_enemies_label() -> Label:
	if enemies_label:
		return enemies_label
	enemies_label = Label.new()
	enemies_label.name = "EnemiesLabel"
	enemies_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	enemies_label.offset_left = -HUD_MARGIN.x - 380.0
	enemies_label.offset_top = HUD_MARGIN.y
	enemies_label.offset_right = -HUD_MARGIN.x
	enemies_label.offset_bottom = HUD_MARGIN.y + 36.0
	enemies_label.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	enemies_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	enemies_label.add_theme_font_size_override("font_size", 24)
	enemies_label.add_theme_color_override("font_color", Color(1.0, 0.25, 0.2, 1.0))
	enemies_label.add_theme_color_override("font_outline_color", Color.BLACK)
	enemies_label.add_theme_constant_override("outline_size", 6)
	_panels_parent().add_child(enemies_label)
	return enemies_label

# --- Game Over & Рестарт ---

func _on_game_over() -> void:
	if game_over_screen:
		game_over_screen.visible = true
	if crosshair:
		crosshair.visible = false
	# На уровне смерть ведёт к возрождению на чекпоинте; перезапуск уровня — отдельной кнопкой
	var gm = get_node_or_null("/root/GameManager")
	var on_level: bool = gm != null and gm.is_level_active()
	var hint: Label = get_node_or_null("GameOverScreen/VBoxContainer/RestartHintLabel")
	if hint:
		hint.text = "Нажмите R, чтобы возродиться на чекпоинте" if on_level else "Нажмите R для перезапуска"
	if restart_button:
		restart_button.text = "Возродиться (R)" if on_level else "Перезапуск (R)"
	if on_level:
		_ensure_restart_level_button().visible = true
	elif restart_level_button:
		restart_level_button.visible = false
	_ensure_main_menu_button()

func _on_player_respawned() -> void:
	health_flask.clear_cracks()
	damage_indicator.clear()
	bpm_hint.clear()
	if game_over_screen:
		game_over_screen.visible = false
	if crosshair:
		crosshair.visible = true

func _ensure_restart_level_button() -> Button:
	if restart_level_button:
		return restart_level_button
	restart_level_button = Button.new()
	restart_level_button.name = "RestartLevelButton"
	restart_level_button.text = "Начать уровень заново"
	restart_level_button.custom_minimum_size = Vector2(240, 50)
	restart_level_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	restart_level_button.add_theme_font_size_override("font_size", 22)
	restart_level_button.pressed.connect(_on_restart_level_pressed)
	if restart_button:
		restart_button.get_parent().add_child(restart_level_button)
	elif game_over_screen:
		game_over_screen.add_child(restart_level_button)
	return restart_level_button

## «Главное меню» на экране смерти — последней кнопкой, под перезапусками
func _ensure_main_menu_button() -> Button:
	if main_menu_button:
		main_menu_button.get_parent().move_child(main_menu_button, -1)
		return main_menu_button
	main_menu_button = _make_main_menu_button(240.0)
	if restart_button:
		restart_button.get_parent().add_child(main_menu_button)
	elif game_over_screen:
		game_over_screen.add_child(main_menu_button)
	return main_menu_button

func _make_main_menu_button(width: float) -> Button:
	var b = Button.new()
	b.name = "MainMenuButton"
	b.text = "Главное меню"
	b.custom_minimum_size = Vector2(width, 50)
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	b.add_theme_font_size_override("font_size", 22)
	b.pressed.connect(_on_main_menu_pressed)
	return b

func _on_main_menu_pressed() -> void:
	var gm = get_node_or_null("/root/GameManager")
	if gm:
		gm.go_to_main_menu()

func _on_restart_pressed() -> void:
	var gm = get_node_or_null("/root/GameManager")
	if gm and gm.has_method("restart_game"):
		gm.restart_game()
	else:
		get_tree().reload_current_scene()

# --- Конец уровня ---

## Экран конца уровня: время, убийства, урон, время в OVERDRIVE, смерти и буква рейтинга.
## Дерево сцены на паузе, поэтому экран работает с PROCESS_MODE_ALWAYS.
func _on_level_completed(stats: Dictionary) -> void:
	if crosshair:
		crosshair.visible = false
	damage_indicator.clear()
	bpm_hint.clear()
	var screen = Control.new()
	screen.name = "LevelCompleteScreen"
	screen.process_mode = Node.PROCESS_MODE_ALWAYS
	screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(screen)

	var bg = ColorRect.new()
	bg.color = Color(0.0, 0.0, 0.0, 0.8)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	screen.add_child(bg)

	var box = VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.offset_left = -260.0
	box.offset_top = -270.0
	box.offset_right = 260.0
	box.offset_bottom = 270.0
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 12)
	screen.add_child(box)

	_add_end_label(box, "УРОВЕНЬ ПРОЙДЕН", 48, Color(0.95, 0.15, 0.15))
	var t: float = stats.get("time", 0.0)
	_add_end_label(box, "Время: %d:%05.2f" % [int(t / 60.0), fmod(t, 60.0)], 24, Color.WHITE)
	_add_end_label(box, "Убийства: %d" % stats.get("kills", 0), 24, Color.WHITE)
	_add_end_label(box, "Полученный урон: %d" % stats.get("damage_taken", 0), 24, Color.WHITE)
	_add_end_label(box, "Время в OVERDRIVE: %.1f с (%d%%)" % [stats.get("overdrive_time", 0.0), int(round(stats.get("overdrive_fraction", 0.0) * 100.0))], 24, Color.WHITE)
	_add_end_label(box, "Смерти: %d" % stats.get("deaths", 0), 24, Color.WHITE)
	_add_end_label(box, "РЕЙТИНГ: %s" % stats.get("rank", "-"), 64, Color(1.0, 0.82, 0.2))

	var again = Button.new()
	again.text = "Пройти заново (R)"
	again.custom_minimum_size = Vector2(260, 50)
	again.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	again.add_theme_font_size_override("font_size", 22)
	again.pressed.connect(_on_restart_level_pressed)
	box.add_child(again)
	box.add_child(_make_main_menu_button(260.0))

func _add_end_label(parent: Control, text: String, font_size: int, color: Color) -> void:
	var label = Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 4)
	parent.add_child(label)

func _on_restart_level_pressed() -> void:
	var gm = get_node_or_null("/root/GameManager")
	if gm:
		gm.restart_level()
	else:
		get_tree().reload_current_scene()
