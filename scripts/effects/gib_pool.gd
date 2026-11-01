class_name GibPool
extends Node3D

## Ошмётки врагов и пятна крови (ноябрь 2026). Один пул на сцену (группа "gib_pool", создаётся по первому
## запросу get_pool и живёт со сценой): куски — MeshInstance3D без своих скриптов, движение всех кусков
## считает один цикл _physics_process (гравитация, луч по шагу, отскок от стен и пола с трением). Кусок,
## упавший на пол быстро, оставляет пятно крови. Лежащий кусок луч не пускает; через GIB_LIFETIME кусок
## сжимается и пропадает. Больше MAX_GIBS кусков — переиспользуется следующий по кругу (самый старый).

const MAX_GIBS: int = 120
const MAX_STAINS: int = 64
const GIB_LIFETIME: float = 4.0 # + до 1 с случайно
const GIB_FADE_TIME: float = 0.5
const STAIN_LIFETIME: float = 8.0
const STAIN_FADE_TIME: float = 1.0
const GRAVITY: float = 20.0
const RESTITUTION: float = 0.3
const FRICTION: float = 0.55
const REST_SPEED: float = 1.5
const STAIN_MIN_SPEED: float = 5.0
const GIB_RADIUS: float = 0.08 # при масштабе 1

const COLOR_FLESH: Color = Color(0.42, 0.02, 0.02)
const COLOR_BODY: Color = Color(0.05, 0.045, 0.045)
const COLOR_STAIN: Color = Color(0.28, 0.0, 0.0)

var _gibs: Array[MeshInstance3D] = []
var _vel: PackedVector3Array = PackedVector3Array()
var _spin: PackedVector3Array = PackedVector3Array()
var _life: PackedFloat32Array = PackedFloat32Array()
var _size: PackedFloat32Array = PackedFloat32Array()
var _resting: PackedByteArray = PackedByteArray()
var _stained: PackedByteArray = PackedByteArray()
var _gib_cursor: int = -1

var _stains: Array[MeshInstance3D] = []
var _stain_life: PackedFloat32Array = PackedFloat32Array()
var _stain_size: PackedFloat32Array = PackedFloat32Array()
var _stain_cursor: int = -1

var _gib_meshes: Array[Mesh] = []
var _mat_flesh: StandardMaterial3D = null
var _mat_body: StandardMaterial3D = null
var _stain_mesh: PlaneMesh = null
var _ray: PhysicsRayQueryParameters3D = null

## Пул текущей сцены (создаётся при первом обращении)
static func get_pool(tree: SceneTree) -> GibPool:
	var existing: Node = tree.get_first_node_in_group("gib_pool")
	if existing is GibPool:
		return existing
	var root: Node = tree.current_scene
	if not root:
		return null
	var pool := GibPool.new()
	pool.name = "GibPool"
	root.add_child(pool)
	return pool

func _ready() -> void:
	add_to_group("gib_pool")
	# Куски летят в физическом тике — интерполируются (урок «Интерполяция физики — только по выбору…»)
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_ON
	for size in [Vector3(0.18, 0.12, 0.14), Vector3(0.26, 0.14, 0.1), Vector3(0.12, 0.12, 0.22), Vector3(0.2, 0.08, 0.2)]:
		var box := BoxMesh.new()
		box.size = size
		_gib_meshes.append(box)
	_mat_flesh = StandardMaterial3D.new()
	_mat_flesh.albedo_color = COLOR_FLESH
	_mat_flesh.roughness = 0.35
	_mat_body = StandardMaterial3D.new()
	_mat_body.albedo_color = COLOR_BODY
	_mat_body.roughness = 0.7
	_stain_mesh = PlaneMesh.new()
	_stain_mesh.size = Vector2(1.0, 1.0)
	var stain_mat := StandardMaterial3D.new()
	stain_mat.albedo_color = COLOR_STAIN
	stain_mat.roughness = 0.2
	_stain_mesh.material = stain_mat
	_ray = PhysicsRayQueryParameters3D.new()
	_ray.collide_with_areas = false
	_ray.collide_with_bodies = true
	_ray.collision_mask = 1

## Разлёт count кусков из origin: основное направление base_dir (толчок убийства, может быть нулевым),
## скорость speed, масштаб кусков size_scale (рой мельче)
func spawn_gibs(origin: Vector3, base_dir: Vector3, count: int, speed: float, size_scale: float) -> void:
	var flat_dir: Vector3 = Vector3(base_dir.x, 0.0, base_dir.z)
	flat_dir = flat_dir.normalized() if flat_dir.length_squared() > 0.0001 else Vector3.ZERO
	for i in range(count):
		var idx: int = _alloc_gib()
		var g: MeshInstance3D = _gibs[idx]
		g.mesh = _gib_meshes[randi() % _gib_meshes.size()]
		g.material_override = _mat_flesh if randf() < 0.6 else _mat_body
		var s: float = size_scale * randf_range(0.7, 1.3)
		_size[idx] = s
		var jitter: Vector3 = Vector3(randf_range(-1.0, 1.0), randf_range(-0.3, 1.0), randf_range(-1.0, 1.0))
		g.global_transform = Transform3D(
			Basis.from_euler(Vector3(randf() * TAU, randf() * TAU, randf() * TAU)).scaled(Vector3.ONE * s),
			origin + jitter * 0.25 * size_scale)
		var dir: Vector3 = (flat_dir * 1.2 + jitter.normalized() * 0.8 + Vector3.UP * 0.7).normalized()
		_vel[idx] = dir * speed * randf_range(0.6, 1.2)
		_spin[idx] = Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * 14.0
		_life[idx] = GIB_LIFETIME + randf()
		_resting[idx] = 0
		_stained[idx] = 0
		g.visible = true
		g.reset_physics_interpolation()

func _alloc_gib() -> int:
	if _gibs.size() < MAX_GIBS:
		var g := MeshInstance3D.new()
		g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(g)
		_gibs.append(g)
		_vel.append(Vector3.ZERO)
		_spin.append(Vector3.ZERO)
		_life.append(0.0)
		_size.append(1.0)
		_resting.append(0)
		_stained.append(0)
		return _gibs.size() - 1
	_gib_cursor = (_gib_cursor + 1) % MAX_GIBS
	return _gib_cursor

func _physics_process(delta: float) -> void:
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	for idx in range(_gibs.size()):
		var g: MeshInstance3D = _gibs[idx]
		if not g.visible:
			continue
		_life[idx] -= delta
		if _life[idx] <= 0.0:
			g.visible = false
			continue
		if _life[idx] < GIB_FADE_TIME:
			g.scale = Vector3.ONE * (_size[idx] * _life[idx] / GIB_FADE_TIME)
		if _resting[idx] == 1:
			continue
		var v: Vector3 = _vel[idx]
		v.y -= GRAVITY * delta
		var from: Vector3 = g.global_position
		var step: Vector3 = v * delta
		var radius: float = GIB_RADIUS * _size[idx]
		_ray.from = from
		_ray.to = from + step + step.normalized() * radius if step.length_squared() > 0.0 else from
		var hit: Dictionary = space.intersect_ray(_ray) if step.length_squared() > 0.0 else {}
		if hit.is_empty():
			g.global_position = from + step
		else:
			var n: Vector3 = hit.normal
			var vn: Vector3 = n * v.dot(n)
			var vt: Vector3 = v - vn
			if _stained[idx] == 0 and n.y > 0.5 and v.length() > STAIN_MIN_SPEED:
				_stained[idx] = 1
				_spawn_stain(hit.position, n, _size[idx])
			v = vt * (1.0 - FRICTION) - vn * RESTITUTION
			_spin[idx] *= 0.5
			g.global_position = hit.position + n * radius
			if n.y > 0.6 and v.length() < REST_SPEED:
				_resting[idx] = 1
				v = Vector3.ZERO
		var spin: Vector3 = _spin[idx]
		if spin.length_squared() > 0.01:
			g.rotate(spin.normalized(), spin.length() * delta)
		_vel[idx] = v
	_process_stains(delta)

func _spawn_stain(pos: Vector3, normal: Vector3, gib_size: float) -> void:
	var idx: int
	if _stains.size() < MAX_STAINS:
		var new_stain := MeshInstance3D.new()
		new_stain.mesh = _stain_mesh
		new_stain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(new_stain)
		_stains.append(new_stain)
		_stain_life.append(0.0)
		_stain_size.append(1.0)
		idx = _stains.size() - 1
	else:
		_stain_cursor = (_stain_cursor + 1) % MAX_STAINS
		idx = _stain_cursor
	var st: MeshInstance3D = _stains[idx]
	# Плоскость пятна — по нормали поверхности, поворот вокруг нормали случайный
	var y: Vector3 = normal.normalized()
	var x: Vector3 = y.cross(Vector3.FORWARD if absf(y.z) < 0.9 else Vector3.RIGHT).normalized()
	var z: Vector3 = x.cross(y)
	var size: float = gib_size * randf_range(2.5, 4.5) * 0.15
	var stain_basis := Basis(x, y, z).rotated(y, randf() * TAU)
	# Масштаб в локальных осях пятна (по плоскости), как и при затухании через scale
	st.global_transform = Transform3D(stain_basis * Basis.from_scale(Vector3(size, 1.0, size)), pos + y * 0.012)
	_stain_life[idx] = STAIN_LIFETIME
	_stain_size[idx] = size
	st.visible = true
	st.reset_physics_interpolation()

func _process_stains(delta: float) -> void:
	for idx in range(_stains.size()):
		var st: MeshInstance3D = _stains[idx]
		if not st.visible:
			continue
		_stain_life[idx] -= delta
		if _stain_life[idx] <= 0.0:
			st.visible = false
		elif _stain_life[idx] < STAIN_FADE_TIME:
			var k: float = _stain_life[idx] / STAIN_FADE_TIME
			st.scale = Vector3(_stain_size[idx] * k, 1.0, _stain_size[idx] * k)
