@tool
class_name CityMesh
extends RefCounted

## Сборщик геометрии городской застройки (CityBuilding, CityProp, CityWire, ноябрь 2026): коробки и цилиндры
## копятся по материалам и собираются в один ArrayMesh — одна поверхность на материал вместо узла на деталь
## (окна, перила, трубы — сотни деталей на здание). UV не нужны: материалы поверхностей — world_surface
## (рисунок в мировых координатах), остальные — однотонные.

const MATERIALS: Dictionary = {
	&"concrete": preload("res://materials/city/concrete.tres"),
	&"concrete_dark": preload("res://materials/city/concrete_dark.tres"),
	&"brick": preload("res://materials/city/brick.tres"),
	&"brick_dark": preload("res://materials/city/brick_dark.tres"),
	&"trim": preload("res://materials/city/trim.tres"),
	&"asphalt": preload("res://materials/city/asphalt.tres"),
	&"sidewalk": preload("res://materials/city/sidewalk.tres"),
	&"shutter": preload("res://materials/city/shutter.tres"),
	&"rubble": preload("res://materials/city/rubble.tres"),
	&"metal_rust": preload("res://materials/city/metal_rust.tres"),
	&"metal_dark": preload("res://materials/city/metal_dark.tres"),
	&"window": preload("res://materials/city/window.tres"),
	&"window_lit": preload("res://materials/city/window_lit.tres"),
	&"window_lit_cold": preload("res://materials/city/window_lit_cold.tres"),
	&"lamp_glow": preload("res://materials/city/lamp_glow.tres"),
	&"neon_red": preload("res://materials/city/neon_red.tres"),
	&"neon_cyan": preload("res://materials/city/neon_cyan.tres"),
	&"dumpster": preload("res://materials/city/dumpster.tres"),
	&"car_paint": preload("res://materials/city/car_paint.tres"),
	&"tire": preload("res://materials/city/tire.tres"),
}

var _tools: Dictionary = {} # материал -> SurfaceTool

## Коробка: центр, размер, поворот (в координатах узла, которому достанется меш)
func box(mat: StringName, center: Vector3, size: Vector3, rot: Basis = Basis.IDENTITY) -> void:
	var st: SurfaceTool = _tool(mat)
	var h: Vector3 = size * 0.5
	for axis in range(3):
		for side in [-1.0, 1.0]:
			var n := Vector3.ZERO
			n[axis] = side
			var u := Vector3.ZERO
			u[(axis + 1) % 3] = h[(axis + 1) % 3]
			var v := Vector3.ZERO
			v[(axis + 2) % 3] = h[(axis + 2) % 3]
			var c: Vector3 = n * h[axis]
			_quad(st, rot * n, center + rot * (c - u - v), center + rot * (c + u - v), center + rot * (c + u + v), center + rot * (c - u + v))

## Цилиндр вдоль локальной оси Y поворота rot: центр, радиус, высота, число граней
func cylinder(mat: StringName, center: Vector3, radius: float, height: float, rot: Basis = Basis.IDENTITY, segments: int = 8) -> void:
	var st: SurfaceTool = _tool(mat)
	var hy: float = height * 0.5
	for i in range(segments):
		var a0: float = TAU * float(i) / float(segments)
		var a1: float = TAU * float(i + 1) / float(segments)
		var d0 := Vector3(cos(a0), 0.0, sin(a0))
		var d1 := Vector3(cos(a1), 0.0, sin(a1))
		var nside: Vector3 = rot * ((d0 + d1) * 0.5).normalized()
		_quad(st, nside, center + rot * (d0 * radius + Vector3.DOWN * hy), center + rot * (d1 * radius + Vector3.DOWN * hy),
			center + rot * (d1 * radius + Vector3.UP * hy), center + rot * (d0 * radius + Vector3.UP * hy))
		_tri(st, rot * Vector3.UP, center + rot * (Vector3.UP * hy), center + rot * (d0 * radius + Vector3.UP * hy), center + rot * (d1 * radius + Vector3.UP * hy))
		_tri(st, rot * Vector3.DOWN, center + rot * (Vector3.DOWN * hy), center + rot * (d1 * radius + Vector3.DOWN * hy), center + rot * (d0 * radius + Vector3.DOWN * hy))

## Отрезок-балка (перила, провода, лестничные косоуры): квадратное сечение thickness от a до b
func beam(mat: StringName, a: Vector3, b: Vector3, thickness: float) -> void:
	var dir: Vector3 = b - a
	var length: float = dir.length()
	if length < 0.001:
		return
	var y: Vector3 = dir / length
	var x: Vector3 = y.cross(Vector3.UP if absf(y.y) < 0.95 else Vector3.RIGHT).normalized()
	var z: Vector3 = x.cross(y)
	box(mat, (a + b) * 0.5, Vector3(thickness, length, thickness), Basis(x, y, z))

func is_empty() -> bool:
	return _tools.is_empty()

## Собрать накопленное в MeshInstance3D (одна поверхность на материал)
func build(cast_shadows: bool = true) -> MeshInstance3D:
	var mesh := ArrayMesh.new()
	for mat in _tools:
		var st: SurfaceTool = _tools[mat]
		st.commit(mesh)
		mesh.surface_set_material(mesh.get_surface_count() - 1, MATERIALS[mat])
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if cast_shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi

func _tool(mat: StringName) -> SurfaceTool:
	if not _tools.has(mat):
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		_tools[mat] = st
	return _tools[mat]

func _quad(st: SurfaceTool, n: Vector3, p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3) -> void:
	_tri(st, n, p0, p1, p2)
	_tri(st, n, p0, p2, p3)

## Треугольник лицом по нормали n: передняя грань в Godot — обход по часовой стрелке, если смотреть на неё,
## то есть (p1 - p0) × (p2 - p0) направлен против нормали; иначе порядок меняется
func _tri(st: SurfaceTool, n: Vector3, p0: Vector3, p1: Vector3, p2: Vector3) -> void:
	if (p1 - p0).cross(p2 - p0).dot(n) > 0.0:
		var t: Vector3 = p1
		p1 = p2
		p2 = t
	for p in [p0, p1, p2]:
		st.set_normal(n)
		st.add_vertex(p)
