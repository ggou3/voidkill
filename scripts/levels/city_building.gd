@tool
class_name CityBuilding
extends Node3D

## Здание городской застройки (ноябрь 2026, уровень city_level): коробка с коллизией и сгенерированные детали
## фасада — этажные карнизы, окна (часть горит), первый этаж с ролл-ставнями, пожарная лестница, кондиционеры,
## водостоки, парапет и хлам на крыше. Узел стоит в центре основания здания. Детали собирает CityMesh в один
## меш на материал; геометрия создаётся в _ready и в редакторе (@tool) без владельца — в сцену не сохраняется,
## в .tscn лежат только параметры. Коллизия — только основной объём (StaticBody3D, слой 1): навмеш уровня
## (разбор коллизий) видит здание, детали фасада игрока не цепляют.

## Ширина (X), высота (Y), глубина (Z), м
@export var size: Vector3 = Vector3(12.0, 18.0, 12.0):
	set(value):
		size = value
		_queue_rebuild()
## Отделка фасада
@export_enum("Бетон", "Тёмный бетон", "Кирпич", "Тёмный кирпич") var facade: int = 0:
	set(value):
		facade = value
		_queue_rebuild()
@export var floor_height: float = 3.2:
	set(value):
		floor_height = value
		_queue_rebuild()
## Доля горящих окон
@export_range(0.0, 1.0) var lit_windows: float = 0.1:
	set(value):
		lit_windows = value
		_queue_rebuild()
## Стороны с окнами (биты: 1 = +X, 2 = −X, 4 = +Z, 8 = −Z); глухие стены, прижатые к соседям, — без окон
@export_flags("+X", "-X", "+Z", "-Z") var window_sides: int = 15:
	set(value):
		window_sides = value
		_queue_rebuild()
## Сторона с пожарной лестницей: 0 — нет, 1 = +X, 2 = −X, 3 = +Z, 4 = −Z
@export_enum("Нет", "+X", "-X", "+Z", "-Z") var fire_escape: int = 0:
	set(value):
		fire_escape = value
		_queue_rebuild()
## Первый этаж — витрины с ролл-ставнями на сторонах с окнами
@export var storefront: bool = true:
	set(value):
		storefront = value
		_queue_rebuild()
## Зерно случайных деталей (0 — от позиции узла)
@export var detail_seed: int = 0:
	set(value):
		detail_seed = value
		_queue_rebuild()

const FACADE_MATERIALS: Array[StringName] = [&"concrete", &"concrete_dark", &"brick", &"brick_dark"]
const WINDOW_WIDTH: float = 1.3
const WINDOW_HEIGHT: float = 1.7
const WINDOW_SPACING: float = 3.0
const AC_CHANCE: float = 0.12
const ROOF_TANK_CHANCE: float = 0.5

var _generated: Node3D = null
var _rebuild_queued: bool = false

func _ready() -> void:
	_rebuild()

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
	var rng := RandomNumberGenerator.new()
	rng.seed = detail_seed if detail_seed != 0 else hash(Vector3i(position.round()))
	var m := CityMesh.new()
	var wall_mat: StringName = FACADE_MATERIALS[clampi(facade, 0, FACADE_MATERIALS.size() - 1)]
	m.box(wall_mat, Vector3(0.0, size.y * 0.5, 0.0), size)
	_add_bands(m)
	for side in range(4):
		if window_sides & (1 << side):
			_add_facade(m, rng, side)
	if fire_escape > 0:
		_add_fire_escape(m, rng, fire_escape - 1)
	_add_drainpipes(m, rng)
	_add_roof(m, rng)
	_generated.add_child(m.build())
	_add_collision()

## Сторона фасада: нормаль наружу, ось вдоль фасада, ширина фасада и расстояние от центра до стены
func _side_frame(side: int) -> Array:
	match side:
		0:
			return [Vector3.RIGHT, Vector3.BACK, size.z, size.x * 0.5]
		1:
			return [Vector3.LEFT, Vector3.FORWARD, size.z, size.x * 0.5]
		2:
			return [Vector3.BACK, Vector3.LEFT, size.x, size.z * 0.5]
		_:
			return [Vector3.FORWARD, Vector3.RIGHT, size.x, size.z * 0.5]

## Карнизы через два этажа, цоколь и венчающий карниз
func _add_bands(m: CityMesh) -> void:
	var outer: Vector3 = Vector3(size.x + 0.3, 0.0, size.z + 0.3)
	m.box(&"trim", Vector3(0.0, 0.3, 0.0), Vector3(size.x + 0.16, 0.6, size.z + 0.16))
	var floors: int = int(size.y / floor_height)
	for f in range(2, floors, 2):
		m.box(&"trim", Vector3(0.0, f * floor_height, 0.0), Vector3(outer.x, 0.22, outer.z))
	m.box(&"trim", Vector3(0.0, size.y - 0.25, 0.0), Vector3(size.x + 0.6, 0.5, size.z + 0.6))

func _add_facade(m: CityMesh, rng: RandomNumberGenerator, side: int) -> void:
	var frame: Array = _side_frame(side)
	var n: Vector3 = frame[0]
	var along: Vector3 = frame[1]
	var width: float = frame[2]
	var dist: float = frame[3]
	var cols: int = int((width - 1.5) / WINDOW_SPACING)
	if cols < 1:
		return
	var start: float = -float(cols - 1) * WINDOW_SPACING * 0.5
	var floors: int = int(size.y / floor_height)
	var face_basis := Basis(along, Vector3.UP, n)
	for f in range(floors):
		var y0: float = f * floor_height
		if f == 0 and storefront:
			_add_storefront(m, rng, n, along, width, dist)
			continue
		if y0 + floor_height > size.y - 0.6:
			break
		for c in range(cols):
			var x: float = start + c * WINDOW_SPACING
			var center: Vector3 = n * (dist + 0.02) + along * x + Vector3.UP * (y0 + floor_height * 0.55)
			var r: float = rng.randf()
			var mat: StringName = &"window"
			if r < lit_windows:
				mat = &"window_lit" if rng.randf() < 0.7 else &"window_lit_cold"
			m.box(mat, center, Vector3(WINDOW_WIDTH, WINDOW_HEIGHT, 0.04), face_basis)
			# Подоконник и перемычка
			m.box(&"trim", center + Vector3.DOWN * (WINDOW_HEIGHT * 0.5 + 0.06) + n * 0.08, Vector3(WINDOW_WIDTH + 0.3, 0.1, 0.2), face_basis)
			m.box(&"trim", center + Vector3.UP * (WINDOW_HEIGHT * 0.5 + 0.08) + n * 0.03, Vector3(WINDOW_WIDTH + 0.2, 0.14, 0.08), face_basis)
			if rng.randf() < AC_CHANCE:
				var ac: Vector3 = center + Vector3.DOWN * (WINDOW_HEIGHT * 0.5 + 0.45) + n * 0.3
				m.box(&"metal_dark", ac, Vector3(0.8, 0.5, 0.5), face_basis)
				m.box(&"shutter", ac + n * 0.26, Vector3(0.6, 0.36, 0.02), face_basis)

## Первый этаж: ролл-ставни между пилонами, козырёк
func _add_storefront(m: CityMesh, rng: RandomNumberGenerator, n: Vector3, along: Vector3, width: float, dist: float) -> void:
	var face_basis := Basis(along, Vector3.UP, n)
	var bays: int = maxi(1, int(width / 4.0))
	var bay: float = width / float(bays)
	for b in range(bays):
		var x: float = -width * 0.5 + bay * (b + 0.5)
		var center: Vector3 = n * (dist + 0.03) + along * x + Vector3.UP * 1.5
		m.box(&"shutter", center, Vector3(bay - 0.8, 2.6, 0.06), face_basis)
		# Пилон между витринами
		m.box(&"trim", n * (dist + 0.1) + along * (-width * 0.5 + bay * b) + Vector3.UP * 1.6, Vector3(0.5, 3.2, 0.2), face_basis)
		if rng.randf() < 0.35:
			# Короб вывески над ставнями
			m.box(&"metal_dark", center + Vector3.UP * 1.65 + n * 0.12, Vector3(bay - 1.2, 0.5, 0.18), face_basis)
	m.box(&"trim", n * (dist + 0.45) + Vector3.UP * 3.3, Vector3(width, 0.12, 0.9), face_basis)

## Пожарная лестница: площадки на каждом этаже (кроме первого), перила, марши между площадками
func _add_fire_escape(m: CityMesh, rng: RandomNumberGenerator, side: int) -> void:
	var frame: Array = _side_frame(side)
	var n: Vector3 = frame[0]
	var along: Vector3 = frame[1]
	var width: float = minf(frame[2] - 2.0, 6.0)
	var dist: float = frame[3]
	if width < 3.0:
		return
	var offset: float = rng.randf_range(-1.0, 1.0) * maxf(0.0, (frame[2] - width) * 0.5 - 1.0)
	var depth: float = 1.4
	var floors: int = int(size.y / floor_height)
	var face_basis := Basis(along, Vector3.UP, n)
	for f in range(1, floors):
		var y: float = f * floor_height
		if y > size.y - 1.5:
			break
		var center: Vector3 = n * (dist + depth * 0.5) + along * offset + Vector3.UP * y
		m.box(&"metal_rust", center, Vector3(width, 0.06, depth), face_basis)
		# Перила: верхний и средний поручни по трём сторонам, стойки
		var front: Vector3 = n * (dist + depth) + along * offset
		for h in [0.5, 1.0]:
			var yy: Vector3 = Vector3.UP * (y + h)
			m.beam(&"metal_rust", front - along * width * 0.5 + yy, front + along * width * 0.5 + yy, 0.04)
			m.beam(&"metal_rust", n * dist + along * (offset - width * 0.5) + yy, front - along * width * 0.5 + yy, 0.04)
			m.beam(&"metal_rust", n * dist + along * (offset + width * 0.5) + yy, front + along * width * 0.5 + yy, 0.04)
		var posts: int = int(width)
		for p in range(posts + 1):
			var px: Vector3 = front + along * (-width * 0.5 + width * float(p) / float(posts))
			m.beam(&"metal_rust", px + Vector3.UP * y, px + Vector3.UP * (y + 1.0), 0.035)
		# Кронштейны под площадкой
		m.beam(&"metal_rust", n * dist + along * (offset - width * 0.4) + Vector3.UP * (y - 0.8), front - along * width * 0.4 + Vector3.UP * y, 0.05)
		m.beam(&"metal_rust", n * dist + along * (offset + width * 0.4) + Vector3.UP * (y - 0.8), front + along * width * 0.4 + Vector3.UP * y, 0.05)
		# Марш на следующую площадку — по диагонали, направление чередуется
		if (f + 1) * floor_height <= size.y - 1.5:
			var dir: float = 1.0 if f % 2 == 0 else -1.0
			var mid: Vector3 = n * (dist + depth * 0.5) + along * offset
			var a: Vector3 = mid + along * (-dir * width * 0.35) + Vector3.UP * y
			var b: Vector3 = mid + along * (dir * width * 0.35) + Vector3.UP * (y + floor_height)
			m.beam(&"metal_rust", a + n * 0.25, b + n * 0.25, 0.06)
			m.beam(&"metal_rust", a - n * 0.25, b - n * 0.25, 0.06)
			var steps: int = 9
			for s in range(1, steps):
				var t: float = float(s) / float(steps)
				m.box(&"metal_rust", a.lerp(b, t), Vector3(0.25, 0.04, 0.55), face_basis)
	# Откидная лестница до второго этажа (не до земли — до неё не дотянуться)
	var ladder: Vector3 = n * (dist + depth - 0.3) + along * (offset + width * 0.5 - 0.5)
	m.beam(&"metal_rust", ladder + along * 0.2 + Vector3.UP * 1.6, ladder + along * 0.2 + Vector3.UP * floor_height, 0.04)
	m.beam(&"metal_rust", ladder - along * 0.2 + Vector3.UP * 1.6, ladder - along * 0.2 + Vector3.UP * floor_height, 0.04)

func _add_drainpipes(m: CityMesh, rng: RandomNumberGenerator) -> void:
	for corner in [Vector2(1, 1), Vector2(-1, -1)]:
		if rng.randf() < 0.3:
			continue
		var p := Vector3(corner.x * (size.x * 0.5 + 0.12), size.y * 0.5, corner.y * (size.z * 0.5 - 0.3))
		m.cylinder(&"metal_dark", p, 0.08, size.y, Basis.IDENTITY, 6)

## Парапет и хлам на крыше: бак на опорах, вентиляционные короба, антенна
func _add_roof(m: CityMesh, rng: RandomNumberGenerator) -> void:
	var top: float = size.y
	var hx: float = size.x * 0.5
	var hz: float = size.z * 0.5
	m.box(&"trim", Vector3(0.0, top + 0.5, hz - 0.15), Vector3(size.x, 1.0, 0.3))
	m.box(&"trim", Vector3(0.0, top + 0.5, -hz + 0.15), Vector3(size.x, 1.0, 0.3))
	m.box(&"trim", Vector3(hx - 0.15, top + 0.5, 0.0), Vector3(0.3, 1.0, size.z))
	m.box(&"trim", Vector3(-hx + 0.15, top + 0.5, 0.0), Vector3(0.3, 1.0, size.z))
	if rng.randf() < ROOF_TANK_CHANCE and size.x > 6.0 and size.z > 6.0:
		var tank := Vector3(rng.randf_range(-hx + 2.5, hx - 2.5), top, rng.randf_range(-hz + 2.5, hz - 2.5))
		for leg in [Vector3(1, 0, 1), Vector3(-1, 0, 1), Vector3(1, 0, -1), Vector3(-1, 0, -1)]:
			m.beam(&"metal_rust", tank + leg * 1.0, tank + leg * 1.0 + Vector3.UP * 2.5, 0.12)
		m.cylinder(&"brick_dark", tank + Vector3.UP * 4.0, 1.5, 3.0, Basis.IDENTITY, 10)
		m.cylinder(&"metal_dark", tank + Vector3.UP * 5.8, 1.6, 0.6, Basis.IDENTITY, 10)
	for i in range(rng.randi_range(1, 3)):
		var p := Vector3(rng.randf_range(-hx + 1.5, hx - 1.5), top + 0.6, rng.randf_range(-hz + 1.5, hz - 1.5))
		m.box(&"metal_dark", p, Vector3(rng.randf_range(1.0, 2.2), 1.2, rng.randf_range(1.0, 1.8)))
	if rng.randf() < 0.4:
		var a := Vector3(rng.randf_range(-hx + 1.0, hx - 1.0), top, rng.randf_range(-hz + 1.0, hz - 1.0))
		m.beam(&"metal_dark", a, a + Vector3.UP * rng.randf_range(4.0, 8.0), 0.08)

func _add_collision() -> void:
	var body := StaticBody3D.new()
	body.name = "Body"
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	shape.position = Vector3(0.0, size.y * 0.5, 0.0)
	body.add_child(shape)
	_generated.add_child(body)
