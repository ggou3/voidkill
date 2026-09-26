class_name EnemyHealthBar
extends Node3D

@export var bar_offset_y: float = 1.15
@export var label_offset_y: float = 1.32
@export var fill_color: Color = Color(0.95, 0.15, 0.15, 1.0)
@export var label_color: Color = Color(1.0, 0.9, 0.9)

var max_health: int = 100
var current_health: int = 100

var hp_viewport: SubViewport
var hp_bar: ProgressBar
var hp_sprite: Sprite3D
var hp_label: Label3D
var health_component: HealthComponent = null

var is_initialized: bool = false

func _ready() -> void:
	if not is_initialized:
		_build_ui()

func setup(
	p_current_hp: int,
	p_max_hp: int,
	p_bar_offset_y: float = 1.15,
	p_fill_color: Color = Color(0.95, 0.15, 0.15, 1.0),
	p_label_color: Color = Color(1.0, 0.9, 0.9),
	p_health_component: HealthComponent = null,
	p_label_offset_y: float = -1.0
) -> void:
	max_health = p_max_hp
	current_health = p_current_hp
	bar_offset_y = p_bar_offset_y
	label_offset_y = p_label_offset_y if p_label_offset_y >= 0.0 else (p_bar_offset_y + 0.17)
	fill_color = p_fill_color
	label_color = p_label_color
	
	if not is_initialized:
		_build_ui()
	else:
		_apply_configuration()
		
	if is_instance_valid(p_health_component):
		set_health_component(p_health_component)
		
	update_health(current_health, max_health)

func _build_ui() -> void:
	if is_initialized:
		return
	is_initialized = true

	# 1. SubViewport для отрисовки текстуры ProgressBar
	hp_viewport = SubViewport.new()
	hp_viewport.name = "SubViewport"
	hp_viewport.size = Vector2i(130, 20)
	hp_viewport.transparent_bg = true
	hp_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS

	hp_bar = ProgressBar.new()
	hp_bar.name = "ProgressBar"
	hp_bar.size = Vector2(130, 20)
	hp_bar.max_value = max_health
	hp_bar.value = current_health
	hp_bar.show_percentage = false

	var bg_box = StyleBoxFlat.new()
	bg_box.bg_color = Color(0.08, 0.08, 0.08, 0.85)
	bg_box.border_color = Color(0.35, 0.35, 0.35, 0.9)
	bg_box.set_border_width_all(2)
	bg_box.set_corner_radius_all(3)

	var fg_box = StyleBoxFlat.new()
	fg_box.bg_color = fill_color
	fg_box.set_corner_radius_all(2)

	hp_bar.add_theme_stylebox_override("background", bg_box)
	hp_bar.add_theme_stylebox_override("fill", fg_box)

	hp_viewport.add_child(hp_bar)
	add_child(hp_viewport)

	# 2. Sprite3D билборд полоски здоровья над головой врага
	hp_sprite = Sprite3D.new()
	hp_sprite.name = "HpSprite"
	hp_sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	hp_sprite.no_depth_test = true
	hp_sprite.position = Vector3(0, bar_offset_y, 0)
	hp_sprite.texture = hp_viewport.get_texture()
	hp_sprite.pixel_size = 0.007
	add_child(hp_sprite)

	# 3. Текстовое числовое значение HP над полоской
	hp_label = Label3D.new()
	hp_label.name = "HpLabel"
	hp_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	hp_label.no_depth_test = true
	hp_label.position = Vector3(0, label_offset_y, 0)
	hp_label.font_size = 18
	hp_label.outline_size = 4
	hp_label.outline_modulate = Color.BLACK
	hp_label.modulate = label_color
	hp_label.text = "%d / %d" % [current_health, max_health]
	add_child(hp_label)

func _apply_configuration() -> void:
	if hp_bar:
		hp_bar.max_value = max_health
		hp_bar.value = current_health
		var fg_box = StyleBoxFlat.new()
		fg_box.bg_color = fill_color
		fg_box.set_corner_radius_all(2)
		hp_bar.add_theme_stylebox_override("fill", fg_box)
	if hp_sprite:
		hp_sprite.position = Vector3(0, bar_offset_y, 0)
	if hp_label:
		hp_label.position = Vector3(0, label_offset_y, 0)
		hp_label.modulate = label_color
		hp_label.text = "%d / %d" % [current_health, max_health]

func set_health_component(p_comp: HealthComponent) -> void:
	if is_instance_valid(health_component) and health_component.health_changed.is_connected(_on_health_changed):
		health_component.health_changed.disconnect(_on_health_changed)
		
	health_component = p_comp
	if is_instance_valid(health_component):
		if not health_component.health_changed.is_connected(_on_health_changed):
			health_component.health_changed.connect(_on_health_changed)
		update_health(health_component.health, health_component.max_health)

func update_health(current_hp: int, max_hp: int = -1) -> void:
	if max_hp > 0:
		max_health = max_hp
		if hp_bar:
			hp_bar.max_value = max_hp
	elif hp_bar:
		max_health = int(hp_bar.max_value)
		
	current_health = current_hp
	if hp_bar:
		hp_bar.value = max(0, current_hp)
	if hp_label:
		hp_label.text = "%d / %d" % [max(0, current_hp), max_health]

func set_bar_visible(p_visible: bool) -> void:
	if hp_sprite:
		hp_sprite.visible = p_visible
	if hp_label:
		hp_label.visible = p_visible

func set_bar_offset_y(p_offset: float, p_label_offset: float = -1.0) -> void:
	bar_offset_y = p_offset
	label_offset_y = p_label_offset if p_label_offset >= 0.0 else (p_offset + 0.17)
	if hp_sprite:
		hp_sprite.position = Vector3(0, bar_offset_y, 0)
	if hp_label:
		hp_label.position = Vector3(0, label_offset_y, 0)

func _on_health_changed(p_current: int, p_max: int) -> void:
	update_health(p_current, p_max)
