class_name EnemyHealthBar
extends Node3D

## Отладочная полоска HP над врагом: квад-биллборд с шейдером (заливка по доле HP) и Label3D с цифрами.
## Создаётся врагом, только когда полоски включены (GameManager.show_enemy_health_bars, клавиша H).
## Один материал на всех врагов, доля HP и цвет — instance uniform, поэтому без SubViewport на врага.

const BAR_SHADER = preload("res://shaders/enemy_health_bar.gdshader")
# Размер прежнего ProgressBar 130×20 px при pixel_size 0.007
const BAR_SIZE = Vector2(0.91, 0.14)

static var _shared_material: ShaderMaterial = null
static var _shared_mesh: QuadMesh = null

@export var bar_offset_y: float = 1.15
@export var label_offset_y: float = 1.32
@export var fill_color: Color = Color(0.95, 0.15, 0.15, 1.0)
@export var label_color: Color = Color(1.0, 0.9, 0.9)

var max_health: int = 100
var current_health: int = 100

var hp_quad: MeshInstance3D
var hp_label: Label3D
var health_component: HealthComponent = null

var is_initialized: bool = false

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

static func _get_shared_material() -> ShaderMaterial:
	if not _shared_material:
		_shared_material = ShaderMaterial.new()
		_shared_material.shader = BAR_SHADER
	return _shared_material

static func _get_shared_mesh() -> QuadMesh:
	if not _shared_mesh:
		_shared_mesh = QuadMesh.new()
		_shared_mesh.size = BAR_SIZE
	return _shared_mesh

func _build_ui() -> void:
	if is_initialized:
		return
	is_initialized = true

	# 1. Квад-биллборд полоски здоровья над головой врага
	hp_quad = MeshInstance3D.new()
	hp_quad.name = "HpQuad"
	hp_quad.mesh = _get_shared_mesh()
	hp_quad.material_override = _get_shared_material()
	hp_quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(hp_quad)

	# 2. Текстовое числовое значение HP над полоской
	hp_label = Label3D.new()
	hp_label.name = "HpLabel"
	hp_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	hp_label.no_depth_test = true
	hp_label.font_size = 18
	hp_label.outline_size = 4
	hp_label.outline_modulate = Color.BLACK
	add_child(hp_label)

	_apply_configuration()

func _apply_configuration() -> void:
	if hp_quad:
		hp_quad.position = Vector3(0, bar_offset_y, 0)
		hp_quad.set_instance_shader_parameter("fill_color", fill_color)
	if hp_label:
		hp_label.position = Vector3(0, label_offset_y, 0)
		hp_label.modulate = label_color
	_refresh()

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
	current_health = current_hp
	_refresh()

func _refresh() -> void:
	if hp_quad:
		var ratio = clampf(float(current_health) / float(max_health), 0.0, 1.0) if max_health > 0 else 0.0
		hp_quad.set_instance_shader_parameter("fill_ratio", ratio)
	if hp_label:
		hp_label.text = "%d / %d" % [max(0, current_health), max_health]

func set_bar_visible(p_visible: bool) -> void:
	if hp_quad:
		hp_quad.visible = p_visible
	if hp_label:
		hp_label.visible = p_visible

func set_bar_offset_y(p_offset: float, p_label_offset: float = -1.0) -> void:
	bar_offset_y = p_offset
	label_offset_y = p_label_offset if p_label_offset >= 0.0 else (p_offset + 0.17)
	if hp_quad:
		hp_quad.position = Vector3(0, bar_offset_y, 0)
	if hp_label:
		hp_label.position = Vector3(0, label_offset_y, 0)

func set_label_font_size(p_size: int) -> void:
	if hp_label:
		hp_label.font_size = p_size

func _on_health_changed(p_current: int, p_max: int) -> void:
	update_health(p_current, p_max)
