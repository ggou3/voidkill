@tool
class_name CityProp
extends Node3D

## Реквизит городской застройки (ноябрь 2026, уровень city_level): разбитая машина, мусорный бак, бетонный блок,
## завал, ящики, бочки, мешки с мусором, ограждение, уличный и настенный фонари, неоновая вывеска. Узел стоит на
## земле в центре предмета; длинная ось — локальная Z (у ограждения и вывески — X, вывеска и настенный фонарь
## смотрят в +Z). Геометрия и свет создаются в _ready и в редакторе (@tool) без владельца — в сцену не
## сохраняются. Коллизия (слой 1) — простыми коробками, у мелочи (мешки, свет) её нет.

enum Kind { CAR, DUMPSTER, JERSEY, RUBBLE, CRATES, BARRELS, TRASH, RAILING, STREET_LAMP, WALL_LAMP, NEON }

@export var kind: Kind = Kind.CAR:
	set(value):
		kind = value
		_queue_rebuild()
## Длина ограждения и ширина вывески (м)
@export var length: float = 3.0:
	set(value):
		length = value
		_queue_rebuild()
## Фонарь и вывеска: сила и радиус света
@export var light_energy: float = 3.2:
	set(value):
		light_energy = value
		_queue_rebuild()
@export var light_range: float = 16.0:
	set(value):
		light_range = value
		_queue_rebuild()
@export var light_shadows: bool = false:
	set(value):
		light_shadows = value
		_queue_rebuild()
## Фонарь и вывеска мигают (неисправная лампа) — только в игре
@export var flicker: bool = false
## Вывеска: 0 — красная, 1 — бирюзовая
@export_enum("Красный", "Бирюзовый") var neon_color: int = 0:
	set(value):
		neon_color = value
		_queue_rebuild()
## Зерно случайных деталей (0 — от позиции узла)
@export var detail_seed: int = 0:
	set(value):
		detail_seed = value
		_queue_rebuild()

const LAMP_COLOR: Color = Color(1.0, 0.62, 0.32)
const NEON_COLORS: Array[Color] = [Color(1.0, 0.12, 0.08), Color(0.2, 0.85, 1.0)]
## Мигание: средний интервал между провалами, длительность провала, яркость в провале (доля)
const FLICKER_INTERVAL: Vector2 = Vector2(0.4, 3.0)
const FLICKER_DIP: Vector2 = Vector2(0.04, 0.18)
const FLICKER_LEVEL: Vector2 = Vector2(0.05, 0.4)

var _generated: Node3D = null
var _rebuild_queued: bool = false
var _light: Light3D = null
var _glow: MeshInstance3D = null
var _flicker_timer: float = 0.0
var _dip_timer: float = 0.0

func _ready() -> void:
	_rebuild()
	set_process(flicker and not Engine.is_editor_hint())

func _queue_rebuild() -> void:
	if not is_inside_tree() or _rebuild_queued:
		return
	_rebuild_queued = true
	_rebuild.call_deferred()

func _rebuild() -> void:
	_rebuild_queued = false
	if _generated:
		_generated.queue_free()
	_generated = Node3D.new()
	_generated.name = "Generated"
	add_child(_generated)
	_light = null
	_glow = null
	var rng := RandomNumberGenerator.new()
	rng.seed = detail_seed if detail_seed != 0 else hash(Vector3i(position.round()))
	var m := CityMesh.new()
	match kind:
		Kind.CAR:
			_build_car(m, rng)
		Kind.DUMPSTER:
			_build_dumpster(m)
		Kind.JERSEY:
			m.box(&"trim", Vector3(0.0, 0.15, 0.0), Vector3(0.62, 0.3, 3.0))
			m.box(&"trim", Vector3(0.0, 0.6, 0.0), Vector3(0.32, 0.6, 3.0))
			_add_box_collision(Vector3(0.0, 0.45, 0.0), Vector3(0.62, 0.9, 3.0))
		Kind.RUBBLE:
			_build_rubble(m, rng)
		Kind.CRATES:
			_build_crates(m, rng)
		Kind.BARRELS:
			_build_barrels(m, rng)
		Kind.TRASH:
			for i in range(rng.randi_range(3, 6)):
				var p := Vector3(rng.randf_range(-0.8, 0.8), 0.25, rng.randf_range(-0.8, 0.8))
				m.box(&"tire", p, Vector3(rng.randf_range(0.5, 0.8), rng.randf_range(0.4, 0.6), rng.randf_range(0.5, 0.8)),
					Basis(Vector3.UP, rng.randf() * TAU))
		Kind.RAILING:
			_build_railing(m)
		Kind.STREET_LAMP:
			_build_street_lamp(m)
		Kind.WALL_LAMP:
			m.box(&"metal_dark", Vector3(0.0, 0.0, 0.25), Vector3(0.12, 0.12, 0.5))
			m.box(&"metal_dark", Vector3(0.0, 0.05, 0.55), Vector3(0.5, 0.12, 0.4))
			_glow = _glow_box(Vector3(0.0, -0.03, 0.55), Vector3(0.4, 0.05, 0.3), &"lamp_glow")
			_add_light(Vector3(0.0, -0.4, 0.9), LAMP_COLOR)
		Kind.NEON:
			_build_neon(m, rng)
	if not m.is_empty():
		_generated.add_child(m.build(kind != Kind.NEON))

func _build_car(m: CityMesh, rng: RandomNumberGenerator) -> void:
	var paint: StringName = &"car_paint" if rng.randf() < 0.5 else &"metal_rust"
	# Кузов слегка завален — сгоревшая машина без части колёс
	var tilt := Basis(Vector3.FORWARD, rng.randf_range(-0.08, 0.08)) * Basis(Vector3.RIGHT, rng.randf_range(-0.04, 0.04))
	var lift: float = 0.35
	m.box(paint, Vector3(0.0, lift + 0.35, 0.0), Vector3(1.8, 0.7, 4.3), tilt)
	m.box(paint, tilt * Vector3(0.0, 0.62, -0.25) + Vector3.UP * lift, Vector3(1.6, 0.55, 2.2), tilt)
	m.box(&"window", tilt * Vector3(0.81, 0.62, -0.25) + Vector3.UP * lift, Vector3(0.02, 0.4, 1.9), tilt)
	m.box(&"window", tilt * Vector3(-0.81, 0.62, -0.25) + Vector3.UP * lift, Vector3(0.02, 0.4, 1.9), tilt)
	m.box(&"window", tilt * Vector3(0.0, 0.66, 0.86) + Vector3.UP * lift, Vector3(1.5, 0.4, 0.02), tilt * Basis(Vector3.RIGHT, -0.5))
	m.box(&"metal_dark", tilt * Vector3(0.0, 0.0, 2.12) + Vector3.UP * (lift + 0.25), Vector3(1.8, 0.3, 0.12), tilt)
	m.box(&"metal_dark", tilt * Vector3(0.0, 0.0, -2.12) + Vector3.UP * (lift + 0.25), Vector3(1.8, 0.3, 0.12), tilt)
	for w in [Vector3(0.82, 0.0, 1.35), Vector3(-0.82, 0.0, 1.35), Vector3(0.82, 0.0, -1.35), Vector3(-0.82, 0.0, -1.35)]:
		if rng.randf() < 0.25:
			continue
		m.cylinder(&"tire", w + Vector3.UP * 0.34, 0.34, 0.24, Basis(Vector3.FORWARD, PI * 0.5), 8)
	_add_box_collision(Vector3(0.0, 0.8, 0.0), Vector3(1.9, 1.6, 4.4))

func _build_dumpster(m: CityMesh) -> void:
	m.box(&"dumpster", Vector3(0.0, 0.75, 0.0), Vector3(1.9, 1.2, 1.15))
	m.box(&"dumpster", Vector3(0.0, 1.45, -0.2), Vector3(1.95, 0.06, 1.0), Basis(Vector3.RIGHT, 0.35))
	m.box(&"metal_dark", Vector3(0.0, 1.32, 0.6), Vector3(2.0, 0.1, 0.08))
	for x in [-0.8, 0.8]:
		for z in [-0.45, 0.45]:
			m.cylinder(&"tire", Vector3(x, 0.08, z), 0.08, 0.06, Basis(Vector3.FORWARD, PI * 0.5), 6)
	_add_box_collision(Vector3(0.0, 0.75, 0.0), Vector3(1.9, 1.5, 1.15))

## Завал: груда бетонных обломков с арматурой; коллизия — низкая коробка (через неё не пройти, как укрытие)
func _build_rubble(m: CityMesh, rng: RandomNumberGenerator) -> void:
	for i in range(rng.randi_range(12, 18)):
		var r: float = sqrt(rng.randf()) * 1.9
		var a: float = rng.randf() * TAU
		var h: float = lerpf(1.1, 0.25, r / 1.9) * rng.randf_range(0.6, 1.1)
		var size := Vector3(rng.randf_range(0.4, 1.3), h, rng.randf_range(0.4, 1.1))
		var rot := Basis.from_euler(Vector3(rng.randf_range(-0.4, 0.4), rng.randf() * TAU, rng.randf_range(-0.4, 0.4)))
		m.box(&"rubble", Vector3(cos(a) * r, h * 0.4, sin(a) * r), size, rot)
	for i in range(rng.randi_range(2, 4)):
		var p := Vector3(rng.randf_range(-1.0, 1.0), 0.3, rng.randf_range(-1.0, 1.0))
		m.beam(&"metal_rust", p, p + Vector3(rng.randf_range(-0.8, 0.8), rng.randf_range(0.6, 1.4), rng.randf_range(-0.8, 0.8)), 0.04)
	_add_box_collision(Vector3(0.0, 0.4, 0.0), Vector3(2.8, 0.8, 2.8))

func _build_crates(m: CityMesh, rng: RandomNumberGenerator) -> void:
	var spots: Array = [Vector3(-0.55, 0.0, 0.0), Vector3(0.55, 0.0, 0.1), Vector3(0.0, 1.0, 0.05)]
	for i in range(rng.randi_range(2, 3)):
		var p: Vector3 = spots[i]
		var s: float = rng.randf_range(0.9, 1.05)
		var rot := Basis(Vector3.UP, rng.randf_range(-0.25, 0.25))
		m.box(&"shutter", p + Vector3.UP * s * 0.5, Vector3.ONE * s, rot)
		m.box(&"metal_dark", p + Vector3.UP * s * 0.5, Vector3(s + 0.04, 0.08, s + 0.04), rot)
		_add_box_collision(p + Vector3.UP * s * 0.5, Vector3.ONE * s)

func _build_barrels(m: CityMesh, rng: RandomNumberGenerator) -> void:
	for i in range(rng.randi_range(2, 4)):
		var p := Vector3(rng.randf_range(-0.7, 0.7), 0.0, rng.randf_range(-0.7, 0.7))
		if i == 0 and rng.randf() < 0.5:
			# Опрокинутая бочка
			m.cylinder(&"metal_rust", p + Vector3.UP * 0.3, 0.3, 0.9, Basis(Vector3.FORWARD, PI * 0.5) * Basis(Vector3.RIGHT, rng.randf() * TAU), 8)
			continue
		m.cylinder(&"metal_rust", p + Vector3.UP * 0.45, 0.3, 0.9, Basis.IDENTITY, 8)
		_add_box_collision(p + Vector3.UP * 0.45, Vector3(0.6, 0.9, 0.6))

func _build_railing(m: CityMesh) -> void:
	var half: float = length * 0.5
	for h in [0.5, 1.0]:
		m.beam(&"metal_dark", Vector3(-half, h, 0.0), Vector3(half, h, 0.0), 0.05)
	var posts: int = maxi(1, int(length / 1.2))
	for p in range(posts + 1):
		var x: float = -half + length * float(p) / float(posts)
		m.beam(&"metal_dark", Vector3(x, 0.0, 0.0), Vector3(x, 1.05, 0.0), 0.06)
	_add_box_collision(Vector3(0.0, 0.55, 0.0), Vector3(length, 1.1, 0.12))

## Уличный фонарь: столб, вылет, плафон со светом, направленным вниз
func _build_street_lamp(m: CityMesh) -> void:
	m.cylinder(&"metal_dark", Vector3(0.0, 0.3, 0.0), 0.2, 0.6, Basis.IDENTITY, 8)
	m.cylinder(&"metal_dark", Vector3(0.0, 3.2, 0.0), 0.08, 6.4, Basis.IDENTITY, 6)
	m.beam(&"metal_dark", Vector3(0.0, 6.2, 0.0), Vector3(0.0, 6.4, 1.6), 0.08)
	m.box(&"metal_dark", Vector3(0.0, 6.42, 1.7), Vector3(0.5, 0.16, 0.8))
	_glow = _glow_box(Vector3(0.0, 6.32, 1.7), Vector3(0.38, 0.04, 0.6), &"lamp_glow")
	_add_light(Vector3(0.0, 5.9, 1.7), LAMP_COLOR)
	_add_box_collision(Vector3(0.0, 3.2, 0.0), Vector3(0.3, 6.4, 0.3))

## Неоновая вывеска на стене: тёмная рама и светящиеся полосы-«буквы»
func _build_neon(m: CityMesh, rng: RandomNumberGenerator) -> void:
	var half: float = length * 0.5
	m.box(&"metal_dark", Vector3(0.0, 0.0, 0.08), Vector3(length + 0.2, 1.3, 0.12))
	var glow_mat: StringName = &"neon_red" if neon_color == 0 else &"neon_cyan"
	var neon := CityMesh.new()
	var x: float = -half + 0.2
	while x < half - 0.3:
		var w: float = rng.randf_range(0.25, 0.45)
		# «Буква»: вертикальные и горизонтальные штрихи
		neon.box(glow_mat, Vector3(x, 0.0, 0.16), Vector3(0.06, 0.8, 0.04))
		if rng.randf() < 0.7:
			neon.box(glow_mat, Vector3(x + w * 0.5, rng.randf_range(-0.35, 0.35), 0.16), Vector3(w, 0.06, 0.04))
		if rng.randf() < 0.5:
			neon.box(glow_mat, Vector3(x + w, 0.0, 0.16), Vector3(0.06, 0.8, 0.04))
		x += w + 0.25
	neon.box(glow_mat, Vector3(0.0, -0.55, 0.16), Vector3(length, 0.05, 0.04))
	_glow = neon.build(false)
	_generated.add_child(_glow)
	_add_light(Vector3(0.0, 0.0, 1.2), NEON_COLORS[clampi(neon_color, 0, 1)])

func _glow_box(center: Vector3, size: Vector3, mat: StringName) -> MeshInstance3D:
	var g := CityMesh.new()
	g.box(mat, center, size)
	var mi: MeshInstance3D = g.build(false)
	_generated.add_child(mi)
	return mi

func _add_light(pos: Vector3, color: Color) -> void:
	var light := OmniLight3D.new()
	light.position = pos
	light.light_color = color
	light.light_energy = light_energy
	light.omni_range = light_range
	light.omni_attenuation = 1.4
	light.shadow_enabled = light_shadows
	light.light_volumetric_fog_energy = 1.5
	_generated.add_child(light)
	_light = light

func _add_box_collision(center: Vector3, size: Vector3) -> void:
	var body: StaticBody3D = _generated.get_node_or_null("Body")
	if not body:
		body = StaticBody3D.new()
		body.name = "Body"
		_generated.add_child(body)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	shape.position = center
	body.add_child(shape)

## Мигание неисправной лампы: редкие короткие провалы яркости
func _process(delta: float) -> void:
	if not _light:
		return
	if _dip_timer > 0.0:
		_dip_timer -= delta
		if _dip_timer <= 0.0:
			_set_brightness(1.0)
		return
	_flicker_timer -= delta
	if _flicker_timer <= 0.0:
		_flicker_timer = randf_range(FLICKER_INTERVAL.x, FLICKER_INTERVAL.y)
		_dip_timer = randf_range(FLICKER_DIP.x, FLICKER_DIP.y)
		_set_brightness(randf_range(FLICKER_LEVEL.x, FLICKER_LEVEL.y))

func _set_brightness(k: float) -> void:
	_light.light_energy = light_energy * k
	if _glow:
		_glow.visible = k > 0.3
